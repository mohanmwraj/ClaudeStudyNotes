# 04 · HardFault Crash-Dump Handler and Stack Unwinder (C + Assembly)

> **Folder:** `07-Production-Embedded-C-Code-Blueprints/` · **File 4 of 4**
> **Anchors:**
> - Arm *ARMv7-M Architecture Reference Manual* (DDI 0403E): B1.5.6 exception entry, B1.5.7 stack alignment, B1.5.8 exception return and EXC_RETURN, B1.5.15 unrecoverable exceptions and **lockup**, B3.2.15–B3.2.18 CFSR/HFSR/MMFAR/BFAR, B3.2.6 AIRCR (VECTKEY, SYSRESETREQ), C1.6.2 DHCSR.
> - Arm *Cortex-M7 TRM* (DDI 0489): fault status, AFSR, lazy FP stacking.
> - Arm/Keil *Application Note 209: Using Cortex-M3/M4/M7 Fault Exceptions*.
> - Arm *Cortex-M4 Devices Generic User Guide*: ACTLR.DISDEFWBUF and imprecise faults.
> - Production relatives: Zephyr `arch/arm/core/cortex_m/fault.c`, the FreeRTOS `prvGetRegistersFromStack` idiom, CmBacktrace, Memfault's coredump format.
> - File 01 of this folder (the boot, the MPU map, and `.bkp_noinit` in backup SRAM).
>
> **Verification:**
> - All target C files compile warning-free for Cortex-M7 and M33 under the full warning set. The firmware links with the File 01 crt0, MPU map and linker script.
> - **End-to-end emulation (Unicorn 2.1.4, Cortex-M7):**
>   - power-on with 0xA5-filled RAM;
>   - an RTOS-style task on PSP faults three calls deep on a bus error;
>   - the harness performs the architectural exception entry and latches the fault registers;
>   - the real handler captures, seals and requests SYSRESETREQ;
>   - a **warm reset** keeps RAM, and the next boot validates and decodes the record;
>   - the harness checks 24 record fields against the injected CPU state and symbolizes the trace from the ELF.
> - The forum-style handler was run on the same fault for comparison.
> - The decoder was tested on the host with synthetic records for the paths the emulation does not reach.
> - All outputs and listings are inserted verbatim.

---

## 0. The thesis

When a Cortex-M faults, the hardware does three things: it **stacks 8 words** (26 with FP state) on the stack that was in use, **latches the cause** in fault-status registers, and enters the handler. Those registers and that stack are the only truth that will ever exist about the failure, and a reset clears the registers.

A production fault path therefore must:

1. **Capture before anything changes it.**
2. **Trust nothing.** The faulting stack may be the cause, and any wild dereference inside HardFault is **lockup**.
3. **Persist into memory that survives reset**, sealed against power-loss tearing.
4. **Reset deterministically**, with the watchdog as backstop.
5. **Validate and report on the next boot, exactly once.**
6. **Symbolize offline**, against the exact ELF.

The typical forum handler does none of these. The emulated comparison in §2.1 shows it reporting `PC = 0xA5A5A5A5` for a fault whose real PC it was handed on the other stack.

---

## 1. First-Principles Mechanics

### 1.1 What the hardware does at exception entry

On entry (ARMv7-M B1.5.6) the core pushes onto the **active** stack (MSP or PSP):

| Offset | Basic frame (8 words) | Notes |
|---|---|---|
| +0x00 | r0 | |
| +0x04 | r1 | |
| +0x08 | r2 | |
| +0x0C | r3 | |
| +0x10 | r12 | |
| +0x14 | LR | the interrupted code's LR (live return address in a leaf) |
| +0x18 | **PC** | precise faults: the **faulting instruction**; interrupts: the next instruction |
| +0x1C | xPSR | bit 9 = 1 means a 4-byte alignment pad sits above the frame (CCR.STKALIGN) |
| +0x20…+0x64 | s0–s15, FPSCR, reserved | extended frame only (EXC_RETURN[4] = 0), possibly *lazily* stacked |

Then it sets `LR = EXC_RETURN` and enters Handler mode on **MSP**:

| EXC_RETURN | Return to | Stack | Frame |
|---|---|---|---|
| `0xFFFFFFF1` | Handler | MSP | basic |
| `0xFFFFFFF9` | Thread | MSP | basic |
| `0xFFFFFFFD` | Thread | PSP | basic |
| `0xFFFFFFE1` / `E9` / `ED` | same three | | **extended (FP)** |

So the handler has to ask **`EXC_RETURN[2]`** which stack holds the frame: 0 = MSP, 1 = PSP. Under an RTOS, faults in tasks are on PSP.

r4–r11 are **not** stacked. They are still live in the registers when the handler starts, so the entry stub must save them before any C code reuses them.

### 1.2 The fault-status registers

| Register | Address | Content |
|---|---|---|
| CFSR | `0xE000ED28` | `[7:0]` MMFSR, `[15:8]` BFSR, `[31:16]` UFSR, all W1C |
| HFSR | `0xE000ED2C` | `VECTTBL` (1), `FORCED` (30: escalated), `DEBUGEVT` (31) |
| MMFAR | `0xE000ED34` | MemManage address, **valid only if `CFSR.MMARVALID`** |
| BFAR | `0xE000ED38` | BusFault address, **valid only if `CFSR.BFARVALID`** (never for imprecise faults) |
| AFSR | `0xE000ED3C` | implementation-defined auxiliary status |
| SHCSR | `0xE000ED24` | which configurable faults are enabled/active/pending |

**Escalation.** MemManage, BusFault and UsageFault are disabled after reset (`SHCSR[18:16] = 0`). Until enabled, they **escalate** to HardFault with `HFSR.FORCED = 1` and the real cause in CFSR. That is exactly the emulated case below: a precise BusFault (`CFSR = 0x8200`) reported through HardFault.

**Lockup.** A fault while executing HardFault (priority −1) or NMI (−2) cannot escalate further. The core enters **lockup** (B1.5.15): it stops executing and asserts its LOCKUP signal. Some SoCs reset on lockup and some just stop ⚠ verify. Either way, only the watchdog recovers, and nothing was recorded. This is why every address the handler dereferences must be validated first.

### 1.3 Why the entry must be naked assembly

A C function has a prologue. The compiler may push callee-saved registers and LR onto the current stack, and that stack may be the corrupted one: a stack overflow is the most common cause of a HardFault. The prologue also moves SP, so "read the frame at SP + 24" depends on optimizer decisions.

The naked stub (listing in §2.2) does only register work:

1. `tst lr, #4` + `ite` + `mrs r0, msp/psp` picks the frame by EXC_RETURN[2].
2. `stm r2, {r4-r11}` and `str msp` save the registers that C code would overwrite.
3. `mrs r3, ipsr` records which vector fired (3 HardFault, 4 MemManage, 5 BusFault, 6 UsageFault). All four vectors alias the same entry.
4. `mov sp, <private 1 KB crash stack>`, so the C capture never uses the faulting stack.
5. `b crash_capture`, with four arguments in r0–r3 per AAPCS.

### 1.4 Validate, then dereference

Before reading the frame, `crash_capture` checks:

- the frame and its full size (8 or 26 words) lie in a RAM region (DTCM, AXI, D2);
- it is word-aligned;
- CFSR shows **no** stacking error (`STKERR`/`MSTKERR`). With a stacking error, the frame write itself failed, so its contents are garbage.

Every later read (stack snapshot, return-address scan, the halfwords at a candidate return address) is bounds-checked against the same region or the code range. If validation fails, the record still carries the fault registers and SP, with `frame_ok = 0`. That is often the most important crash type of all: stack overflow.

### 1.5 Heuristic unwinding, and why it is heuristic

Thumb-2 code at `-O2` has no frame-pointer chain, and this build has no unwind tables (`-fno-unwind-tables`). The handler therefore reconstructs a *probable* call chain:

| Frame | Source | Reliability |
|---|---|---|
| #0 | stacked PC | exact for precise faults |
| #1 | stacked LR, if it is a valid return address | exact when the fault is in a leaf, or before the function's first call |
| #2… | stack words that are odd, inside the code range, **and** directly preceded by a `BL` (32-bit: `11110x…`/`11x1x…`) or `BLX Rm` (`0x4780 \| Rm<<3`) | probable |

What breaks it:

- **False positives:** stale return addresses left on the stack by earlier, already-returned calls.
- **False negatives:** tail calls (`b`, no return address), and leaf functions that never push LR.

The exact alternatives are:

- **EHABI unwind tables** (`.ARM.exidx`/`.ARM.extab`): exact, but cost flash.
- **A frame-pointer chain** (`-fno-omit-frame-pointer`): costs a register and code size.

The record stores **raw candidates**, and symbolization happens **offline** against the ELF named by `build_id`. Never symbolize on the device.

### 1.6 Persist, seal, reset

- **Where:** `.bkp_noinit` in backup SRAM (File 01). It is never zeroed by crt0, and the MPU maps it **Normal non-cacheable**. If the record were in cacheable RAM, it would have to be cleaned to memory before reset, because **a reset does not write back dirty cache lines**.
- **Sealing:**
  - `magic = 0` first;
  - fill the body;
  - `version` (layout: `(1 << 16) | words`) and CRC-32 over the body;
  - **`magic` last**.
  A power loss mid-write leaves `magic != CRSH` or a CRC mismatch, so the record is rejected, never misreported.
- **Reset:**
  - If `DHCSR.C_DEBUGEN` is set, execute `bkpt` instead, so a debugger halts with the fault state live.
  - Otherwise: `dsb` (record stores complete), then `AIRCR = 0x05FA0000 | (PRIGROUP preserved) | SYSRESETREQ`, then `dsb`, then spin.
  - If the reset request is ignored, the independent watchdog, which the handler never kicks, ends the spin.

### 1.7 The next boot

`crash_take()`:

1. Validates magic, layout version and CRC.
2. Decodes the record into text (libc-free, identical on target and host).
3. **Invalidates the record in every case**: a record is reported exactly once. Even power-on garbage is cleared, which is why its magic reads 0 afterwards.

In production the report goes to telemetry, and a **crash-loop counter** (in the same backup domain) switches to a safe mode after *N* consecutive crash resets (Q4).

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* crash_bad.c - the HardFault handler from a thousand forum posts. Compiles
 * warning-free, prints plausible numbers, and is wrong in three ways. */
#include "board.h"
#include "crash.h"

#define SCB_CFSR (*(volatile uint32_t *)0xE000ED28u)
#define UART_TDR (*(volatile uint32_t *)0x40011028u)

BKP_NOINIT crash_record_t g_crash;            /* declared, never written */
volatile uint32_t g_bad_cfsr, g_bad_pc, g_bad_lr;

void HardFault_Handler(void);
__attribute__((noinline)) static void log_hex(uint32_t v);

static void log_hex(uint32_t v)
{
    for (int sh = 28; sh >= 0; sh -= 4) {
        UART_TDR = "0123456789ABCDEF"[(v >> (unsigned)sh) & 0xFu];
    }
}

void HardFault_Handler(void)
{
    uint32_t *sp;
    __asm__ volatile("mov %0, sp" : "=r"(sp));   /* BUG 1: the HANDLER's SP: the wrong stack
                                                  *  when the task ran on PSP, and shifted by
                                                  *  this function's own prologue          */
    g_bad_cfsr = SCB_CFSR;
    g_bad_pc = sp[6];                            /* BUG 2: assumes MSP, no prologue, basic
                                                  *  frame, no STKALIGN pad                */
    g_bad_lr = sp[5];
    log_hex(g_bad_pc);                           /* polled UART from HardFault: slow, and
                                                  *  the UART may be the faulting device   */
    for (;;) { }                                 /* BUG 3: no record that survives reset,
                                                  *  no reset: dead until the watchdog
                                                  *  bites, and then every clue is gone    */
}
```

**Codegen (verified — Clang 21.1.0, -O2, Cortex-M7, linked):**

```asm
HardFault_Handler:
  080005f8:  movw     r1, #0xed28
  080005fc:  movw     r2, #0
  08000600:  movt     r1, #0xe000
  08000604:  movt     r2, #0x2400
  08000608:  mov      r0, sp
  0800060a:  ldr      r1, [r1]
  0800060c:  str      r1, [r2]
  0800060e:  movw     r2, #4
  08000612:  movt     r2, #0x2400
  08000616:  ldrd     r0, r1, [r0, #0x14]
  0800061a:  str      r1, [r2]
  0800061c:  movw     r1, #8
  08000620:  movt     r1, #0x2400
  08000624:  str      r0, [r1]
  08000626:  ldr      r0, [r2]
  08000628:  bl       #0x8000638
  0800062c:  nop      
  0800062e:  nop      
  08000630:  b        #0x8000630
```

Here Clang emitted **no prologue**: the call to `log_hex` is followed by an infinite loop, so nothing needed saving, and `ldrd r0, r1, [r0, #0x14]` happens to read SP + 20/24 directly. Add one local array, or one more live variable, and the offsets shift. This handler's correctness depends on register allocation.

**Same fault, same firmware, forum handler (verified, emulation):**

```
=== boot 1: power-on
  bus error: load from 0x60000000 by 'ldr.w r0, [r0, r1, lsl #2]' at PC=0x0800290C (sensor_read+0x4), Thread mode on PSP
  exception entry: frame at 0x200007C8, LR=EXC_RETURN 0xFFFFFFFD, -> HardFault_Handler 0x080005F8
  handler never resets: still spinning at PC=0x08000630 after 5,000,000 instructions
  it reported PC=0xA5A5A5A5 (?) LR=0xA5A5A5A5 (?) CFSR=0x00008200
  truth:      PC=0x0800290C (sensor_read+0x4) LR=0x08002931 (filter_step+0x18)
  backup SRAM record magic: 0x00000000 (nothing survives the eventual watchdog reset)
```

What went wrong:

- The fault happened in a task on **PSP**. The handler read the **MSP**, and reported `PC = LR = 0xA5A5A5A5`: never-written power-on RAM above the main stack.
- The CFSR value is right, but without the right PC, LR or BFAR it says only "some bus error, somewhere".
- The handler then spins forever. When the watchdog finally resets the part, nothing survives: there is no record.

### 2.2 The Silicon-Hardened Production Way

**Record format and API** (portable):

```c
/* crash.h - post-mortem crash record for ARMv7-M / ARMv8-M Mainline.
 * Written by the fault handler into memory that survives reset (backup SRAM,
 * .bkp_noinit), validated (magic + layout version + CRC-32) and decoded on the
 * next boot. The record holds raw facts only; symbolization happens offline
 * against the ELF identified by build_id. */
#ifndef CRASH_H
#define CRASH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CRASH_MAGIC   0x43525348u            /* "CRSH" */
#define CRASH_NBT     8u                     /* backtrace candidates      */
#define CRASH_NSTACK  16u                    /* raw words above the frame */

typedef struct {
    uint32_t build_id;                       /* which ELF to symbolize against          */
    uint32_t vector;                         /* IPSR: 3 HardFault 4 MemManage 5 Bus 6 Usage */
    uint32_t exc_return;
    uint32_t frame_ok;                       /* 1: frame address validated and read     */
    uint32_t r[13];                          /* r0-r3, r12 from the frame; r4-r11 live  */
    uint32_t sp;                             /* SP of the faulting context              */
    uint32_t lr, pc, xpsr;                   /* stacked                                 */
    uint32_t msp, psp;                       /* at handler entry                        */
    uint32_t cfsr, hfsr, mmfar, bfar, afsr, shcsr;
    uint32_t nbt;
    uint32_t bt[CRASH_NBT];                  /* return-address candidates (Thumb bit)   */
    uint32_t stack[CRASH_NSTACK];
} crash_body_t;

#define CRASH_BODY_WORDS (sizeof(crash_body_t) / 4u)
#define CRASH_VERSION    ((1u << 16) | (uint32_t)CRASH_BODY_WORDS)  /* layout change => stale */

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t crc;                            /* CRC-32 (IEEE, reflected) of body.w[] */
    union {
        crash_body_t f;
        uint32_t     w[CRASH_BODY_WORDS];
    } body;
} crash_record_t;
_Static_assert(sizeof(crash_body_t) == 4u * CRASH_BODY_WORDS, "body is an array of words");

/* CFSR bits (ARMv7-M B3.2.15) */
#define CFSR_IACCVIOL    (1u << 0)
#define CFSR_DACCVIOL    (1u << 1)
#define CFSR_MUNSTKERR   (1u << 3)
#define CFSR_MSTKERR     (1u << 4)
#define CFSR_MLSPERR     (1u << 5)
#define CFSR_MMARVALID   (1u << 7)
#define CFSR_IBUSERR     (1u << 8)
#define CFSR_PRECISERR   (1u << 9)
#define CFSR_IMPRECISERR (1u << 10)
#define CFSR_UNSTKERR    (1u << 11)
#define CFSR_STKERR      (1u << 12)
#define CFSR_LSPERR      (1u << 13)
#define CFSR_BFARVALID   (1u << 15)
#define CFSR_UNDEFINSTR  (1u << 16)
#define CFSR_INVSTATE    (1u << 17)
#define CFSR_INVPC       (1u << 18)
#define CFSR_NOCP        (1u << 19)
#define CFSR_STKOF       (1u << 20)          /* ARMv8-M only */
#define CFSR_UNALIGNED   (1u << 24)
#define CFSR_DIVBYZERO   (1u << 25)
#define HFSR_VECTTBL     (1u << 1)
#define HFSR_FORCED      (1u << 30)
#define HFSR_DEBUGEVT    (1u << 31)

uint32_t crash_crc(const volatile crash_record_t *r);
void     crash_seal(volatile crash_record_t *r);          /* version + crc + magic, last */
/* Validate, decode into out (always NUL-terminated), then invalidate the record.
 * Returns true only if a valid record was found. */
bool     crash_take(volatile crash_record_t *r, char *out, size_t cap);

#endif /* CRASH_H */
```

**Target half: naked entry, capture, scan, reset:**

```c
/* crash_fault.c - target half: the fault entry (naked asm), capture into the
 * backup-SRAM record, a heuristic return-address scan, and the reset.
 * Rules of a fault handler: trust nothing on the faulting stack, read every
 * fault register before anything can change it, validate every address before
 * dereferencing it (a fault inside HardFault is LOCKUP), and never return. */
#include "board.h"
#include "crash.h"

#ifndef CRASH_BUILD_ID
#define CRASH_BUILD_ID 0x07A1B2C3u            /* CI injects the ELF build-id hash */
#endif

#define SCB_ICSR   (*(volatile uint32_t *)0xE000ED04u)
#define SCB_AIRCR  (*(volatile uint32_t *)0xE000ED0Cu)
#define SCB_SHCSR  (*(volatile uint32_t *)0xE000ED24u)
#define SCB_CFSR   (*(volatile uint32_t *)0xE000ED28u)
#define SCB_HFSR   (*(volatile uint32_t *)0xE000ED2Cu)
#define SCB_MMFAR  (*(volatile uint32_t *)0xE000ED34u)
#define SCB_BFAR   (*(volatile uint32_t *)0xE000ED38u)
#define SCB_AFSR   (*(volatile uint32_t *)0xE000ED3Cu)
#define DHCSR      (*(volatile uint32_t *)0xE000EDF0u)

BKP_NOINIT crash_record_t g_crash;            /* survives reset (File 01: .bkp_noinit)  */
DTCM_BSS uint32_t g_crash_saved[9];           /* r4-r11 and MSP at entry, from the asm  */
DTCM_BSS uint64_t g_crash_stack[128];         /* 1 KB private stack for the C capture   */

void HardFault_Handler(void);
void MemManage_Handler(void) __attribute__((alias("HardFault_Handler")));
void BusFault_Handler(void)   __attribute__((alias("HardFault_Handler")));
void UsageFault_Handler(void) __attribute__((alias("HardFault_Handler")));
__attribute__((noreturn, used)) void crash_capture(const uint32_t *frame, uint32_t exc_return,
                                                   const uint32_t *saved, uint32_t ipsr);

/* Entry: r0 = frame (MSP or PSP per EXC_RETURN[2]), r1 = EXC_RETURN,
 * r2 = &g_crash_saved after storing r4-r11 + MSP, r3 = IPSR; then move SP to
 * the private crash stack (the faulting stack may be the cause) and branch. */
__attribute__((naked)) void HardFault_Handler(void)
{
    __asm__ volatile(
        "tst     lr, #4                          \n"
        "ite     eq                              \n"
        "mrseq   r0, msp                         \n"
        "mrsne   r0, psp                         \n"
        "mov     r1, lr                          \n"
        "movw    r2, #:lower16:g_crash_saved     \n"
        "movt    r2, #:upper16:g_crash_saved     \n"
        "stmia   r2, {r4-r11}                    \n"
        "mrs     r12, msp                        \n"
        "str     r12, [r2, #32]                  \n"
        "mrs     r3, ipsr                        \n"
        "movw    r12, #:lower16:g_crash_stack    \n"
        "movt    r12, #:upper16:g_crash_stack    \n"
        "add.w   r12, r12, #1024                 \n"
        "mov     sp, r12                         \n"
        "b       crash_capture                   \n");
}

typedef struct { uint32_t lo, hi; } range_t;
static const range_t k_ram[] = {                  /* where a stack may legally be */
    { 0x20000000u, 0x20020000u },                 /* DTCM     */
    { 0x24000000u, 0x24080000u },                 /* AXI SRAM */
    { 0x30000000u, 0x30020000u },                 /* D2 SRAM  */
};
static const range_t k_code = { 0x08000000u, 0x08200000u };

static bool in_range(const range_t *r, uint32_t a, uint32_t len)
{
    return (a >= r->lo) && (a < r->hi) && (len <= (r->hi - a));
}

static const range_t *ram_of(uint32_t a, uint32_t len)
{
    for (size_t i = 0u; i < (sizeof k_ram / sizeof k_ram[0]); i++) {
        if (in_range(&k_ram[i], a, len)) {
            return &k_ram[i];
        }
    }
    return NULL;
}

/* A Thumb return address is odd, lies in code, and follows a BL (32-bit) or
 * BLX Rm (16-bit). Anything else on the stack is data. */
static bool is_return_address(uint32_t ret)
{
    uint32_t a = ret & ~1u;
    if (((ret & 1u) == 0u) || !in_range(&k_code, a - 4u, 4u)) {
        return false;
    }
    const volatile uint16_t *hw = (const volatile uint16_t *)(uintptr_t)(a - 4u);
    uint16_t h1 = hw[0];
    uint16_t h2 = hw[1];
    bool bl  = ((h1 & 0xF800u) == 0xF000u) && ((h2 & 0xD000u) == 0xD000u);
    bool blx = (h2 & 0xFF87u) == 0x4780u;
    return bl || blx;
}

static void system_reset(void) __attribute__((noreturn));
static void system_reset(void)
{
    if ((DHCSR & 1u) != 0u) {                     /* C_DEBUGEN: a debugger is attached */
        __asm__ volatile("bkpt #0" : : : "memory");   /* halt here for live inspection */
    }
    __asm__ volatile("dsb sy" : : : "memory");    /* record stores complete (NC memory) */
    SCB_AIRCR = (0x05FAu << 16) | (SCB_AIRCR & (7u << 8)) | (1u << 2);  /* VECTKEY, PRIGROUP, SYSRESETREQ */
    __asm__ volatile("dsb sy" : : : "memory");
    for (;;) {                                    /* if the reset request is ignored, the */
        __asm__ volatile("nop");                  /* independent watchdog ends this       */
    }
}

void crash_capture(const uint32_t *frame, uint32_t exc_return, const uint32_t *saved, uint32_t ipsr)
{
    volatile crash_record_t *rec = &g_crash;
    volatile crash_body_t *f = &rec->body.f;
    uint32_t cfsr = SCB_CFSR;                     /* 1. fault registers first */
    uint32_t psp;
    __asm__ volatile("mrs %0, psp" : "=r"(psp));

    rec->magic = 0u;                              /* invalid until sealed */
    f->build_id = CRASH_BUILD_ID;
    f->vector = ipsr & 0x1FFu;
    f->exc_return = exc_return;
    f->cfsr = cfsr;
    f->hfsr = SCB_HFSR;
    f->mmfar = SCB_MMFAR;
    f->bfar = SCB_BFAR;
    f->afsr = SCB_AFSR;
    f->shcsr = SCB_SHCSR;
    f->msp = saved[8];
    f->psp = psp;
    for (unsigned i = 0u; i < 8u; i++) {
        f->r[4u + i] = saved[i];                  /* r4-r11: untouched by stacking */
    }

    uint32_t fa = (uint32_t)(uintptr_t)frame;
    uint32_t words = ((exc_return & 16u) != 0u) ? 8u : 26u;   /* basic or FP frame */
    const range_t *ram = ram_of(fa, 4u * words);
    bool ok = (ram != NULL) && ((fa & 3u) == 0u) && ((cfsr & (CFSR_STKERR | CFSR_MSTKERR)) == 0u);
    f->frame_ok = ok ? 1u : 0u;
    f->nbt = 0u;
    if (ok) {
        f->r[0] = frame[0]; f->r[1] = frame[1]; f->r[2] = frame[2]; f->r[3] = frame[3];
        f->r[12] = frame[4]; f->lr = frame[5]; f->pc = frame[6]; f->xpsr = frame[7];
        uint32_t sp = fa + 4u * words + (((frame[7] >> 9) & 1u) * 4u);   /* STKALIGN pad */
        f->sp = sp;
        uint32_t nbt = 0u;
        f->bt[nbt] = f->pc | 1u;                  /* frame 0: the faulting instruction */
        nbt++;
        if (is_return_address(f->lr)) {           /* frame 1: leaf caller, if LR is live */
            f->bt[nbt] = f->lr;
            nbt++;
        }
        for (uint32_t i = 0u; i < CRASH_NSTACK; i++) {
            uint32_t a = sp + 4u * i;
            uint32_t w = in_range(ram, a, 4u) ? *(const volatile uint32_t *)(uintptr_t)a : 0u;
            f->stack[i] = w;
        }
        for (uint32_t a = sp; (nbt < CRASH_NBT) && in_range(ram, a, 4u) && (a < sp + 256u); a += 4u) {
            uint32_t w = *(const volatile uint32_t *)(uintptr_t)a;
            if (is_return_address(w) && (w != f->bt[nbt - 1u])) {
                f->bt[nbt] = w;
                nbt++;
            }
        }
        f->nbt = nbt;
    } else {
        f->r[0] = 0u; f->r[1] = 0u; f->r[2] = 0u; f->r[3] = 0u; f->r[12] = 0u;
        f->lr = 0u; f->pc = 0u; f->xpsr = 0u; f->sp = fa;
        for (uint32_t i = 0u; i < CRASH_NSTACK; i++) {
            f->stack[i] = 0u;
        }
    }
    for (uint32_t i = f->nbt; i < CRASH_NBT; i++) {
        f->bt[i] = 0u;
    }
    SCB_CFSR = cfsr;                              /* W1C: next boot starts clean */
    SCB_HFSR = f->hfsr;
    crash_seal(rec);                              /* magic written last */
    system_reset();
}
```

**Codegen (verified — Clang 21.1.0, -O2, Cortex-M7, linked): `HardFault_Handler`, exactly as written:**

```asm
HardFault_Handler:
  080005f8:  tst.w    lr, #4
  080005fc:  ite      eq
  080005fe:  mrseq    r0, msp
  08000602:  mrsne    r0, psp
  08000606:  mov      r1, lr
  08000608:  movw     r2, #0
  0800060c:  movt     r2, #0x2000
  08000610:  stm.w    r2, {r4, r5, r6, r7, r8, sb, sl, fp}
  08000614:  mrs      ip, msp
  08000618:  str.w    ip, [r2, #0x20]
  0800061c:  mrs      r3, ipsr
  08000620:  movw     ip, #0x28
  08000624:  movt     ip, #0x2000
  08000628:  add.w    ip, ip, #0x400
  0800062c:  mov      sp, ip
  0800062e:  b.w      #0x8000638
```

`g_crash_saved` resolved to `0x20000000` and the crash stack to `0x20000028` + 1 KB (both in DTCM, from File 01's `.dtcm_bss`). `b.w` goes straight to `crash_capture` with LR still holding EXC_RETURN.

**`system_reset` (verified, same build):**

```asm
system_reset:
  08000b78:  movw     r0, #0xed0c
  08000b7c:  movt     r0, #0xe000
  08000b80:  ldr.w    r1, [r0, #0xe4]
  08000b84:  lsls     r1, r1, #0x1f
  08000b86:  beq      #0x8000b8a
  08000b88:  bkpt     #0
  08000b8a:  dsb      sy
  08000b8e:  movs     r2, #4
  08000b90:  ldr      r1, [r0]
  08000b92:  movt     r2, #0x5fa
  08000b96:  and      r1, r1, #0x700
  08000b9a:  orrs     r1, r2
  08000b9c:  str      r1, [r0]
  08000b9e:  dsb      sy
  08000ba2:  nop      
  08000ba4:  nop      
  08000ba6:  nop      
  08000ba8:  nop      
  08000baa:  b        #0x8000ba8
```

How to read it:

- `ldr.w r1, [r0, #0xe4]` reads DHCSR (`0xE000ED0C + 0xE4 = 0xE000EDF0`). `lsls #0x1f` tests C_DEBUGEN, and if it's set: `bkpt #0`.
- Then `dsb sy` → `AIRCR = 0x05FA0004 | (AIRCR & 0x700)` (VECTKEY + preserved PRIGROUP + SYSRESETREQ) → `dsb sy`.
- Then the `nop` spin that the watchdog terminates if the reset doesn't happen.

**Portable half: CRC, seal, validate, decode:**

```c
/* crash_decode.c - portable half of the crash subsystem: CRC, sealing,
 * validation and a libc-free decoder (runs on the target at boot, and on the
 * host in tests and tooling). */
#include "crash.h"

uint32_t crash_crc(const volatile crash_record_t *r)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0u; i < CRASH_BODY_WORDS; i++) {
        uint32_t w = r->body.w[i];
        for (unsigned b = 0u; b < 4u; b++) {             /* little-endian byte order */
            crc ^= (w >> (8u * b)) & 0xFFu;
            for (unsigned k = 0u; k < 8u; k++) {
                crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
            }
        }
    }
    return ~crc;
}

void crash_seal(volatile crash_record_t *r)
{
    r->version = CRASH_VERSION;
    r->crc = crash_crc(r);
    r->magic = CRASH_MAGIC;                              /* last: a torn write is invalid */
}

typedef struct { char *buf; size_t cap, len; } txt_t;

static void tx_c(txt_t *t, char c)
{
    if (t->len + 1u < t->cap) {
        t->buf[t->len] = c;
        t->len++;
    }
    t->buf[t->len] = '\0';
}

static void tx_s(txt_t *t, const char *s)
{
    for (; *s != '\0'; s++) {
        tx_c(t, *s);
    }
}

static void tx_h(txt_t *t, uint32_t v)
{
    static const char hex[] = "0123456789ABCDEF";
    tx_s(t, "0x");
    for (int sh = 28; sh >= 0; sh -= 4) {
        tx_c(t, hex[(v >> (unsigned)sh) & 0xFu]);
    }
}

static void tx_u(txt_t *t, uint32_t v)
{
    char d[10];
    unsigned n = 0u;
    do {
        d[n] = (char)('0' + (char)(v % 10u));
        n++;
        v /= 10u;
    } while ((v != 0u) && (n < 10u));
    while (n > 0u) {
        n--;
        tx_c(t, d[n]);
    }
}

typedef struct { uint32_t bit; const char *name; } bitname_t;

static void tx_bits(txt_t *t, uint32_t v, const bitname_t *tab, size_t n)
{
    for (size_t i = 0u; i < n; i++) {
        if ((v & tab[i].bit) != 0u) {
            tx_c(t, ' ');
            tx_s(t, tab[i].name);
        }
    }
}

static const bitname_t k_mmfsr[] = {
    { CFSR_IACCVIOL, "IACCVIOL" }, { CFSR_DACCVIOL, "DACCVIOL" }, { CFSR_MUNSTKERR, "MUNSTKERR" },
    { CFSR_MSTKERR, "MSTKERR" }, { CFSR_MLSPERR, "MLSPERR" }, { CFSR_MMARVALID, "MMARVALID" },
};
static const bitname_t k_bfsr[] = {
    { CFSR_IBUSERR, "IBUSERR" }, { CFSR_PRECISERR, "PRECISERR" }, { CFSR_IMPRECISERR, "IMPRECISERR" },
    { CFSR_UNSTKERR, "UNSTKERR" }, { CFSR_STKERR, "STKERR" }, { CFSR_LSPERR, "LSPERR" },
    { CFSR_BFARVALID, "BFARVALID" },
};
static const bitname_t k_ufsr[] = {
    { CFSR_UNDEFINSTR, "UNDEFINSTR" }, { CFSR_INVSTATE, "INVSTATE" }, { CFSR_INVPC, "INVPC" },
    { CFSR_NOCP, "NOCP" }, { CFSR_STKOF, "STKOF" }, { CFSR_UNALIGNED, "UNALIGNED" },
    { CFSR_DIVBYZERO, "DIVBYZERO" },
};
static const bitname_t k_hfsr[] = {
    { HFSR_VECTTBL, "VECTTBL" }, { HFSR_FORCED, "FORCED" }, { HFSR_DEBUGEVT, "DEBUGEVT" },
};

static const char *vector_name(uint32_t v)
{
    static const char *const names[] = { "Thread", "Reset", "NMI", "HardFault", "MemManage",
                                         "BusFault", "UsageFault", "SecureFault" };
    return (v < 8u) ? names[v] : "IRQ";
}

static const char *diagnosis(const crash_body_t *f)
{
    uint32_t c = f->cfsr;
    if ((c & (CFSR_STKERR | CFSR_MSTKERR)) != 0u) { return "stack overflow/corruption during exception entry: frame not trustworthy"; }
    if ((c & CFSR_STKOF) != 0u)       { return "stack limit (PSPLIM/MSPLIM) violated"; }
    if ((c & CFSR_IMPRECISERR) != 0u) { return "imprecise bus error: stacked PC is NOT the faulting store (buffered write); M3/M4: rerun with ACTLR.DISDEFWBUF=1, any core: DSB after suspect stores"; }
    if ((c & CFSR_PRECISERR) != 0u)   { return "precise bus error: data access at BFAR by the instruction at PC"; }
    if ((c & CFSR_IBUSERR) != 0u)     { return "instruction fetch bus error: PC in unmapped/unpowered memory"; }
    if ((c & (CFSR_DACCVIOL | CFSR_IACCVIOL)) != 0u) { return "MPU violation (NULL or stale pointer if MMFAR is small)"; }
    if ((c & CFSR_INVSTATE) != 0u)    { return "branch to an even address (NULL/corrupt function pointer) or bad EPSR.T"; }
    if ((c & CFSR_INVPC) != 0u)       { return "bad EXC_RETURN (corrupted LR in a handler)"; }
    if ((c & CFSR_UNDEFINSTR) != 0u)  { return "undefined instruction: executing data or corrupted code"; }
    if ((c & CFSR_NOCP) != 0u)        { return "FPU access with CP10/CP11 disabled (CPACR)"; }
    if ((c & CFSR_DIVBYZERO) != 0u)   { return "integer divide by zero (CCR.DIV_0_TRP=1)"; }
    if ((c & CFSR_UNALIGNED) != 0u)   { return "unaligned access (CCR.UNALIGN_TRP=1, or LDM/STM/LDRD)"; }
    if ((f->hfsr & HFSR_VECTTBL) != 0u) { return "vector table read failed (VTOR / table corrupt)"; }
    return "no configurable fault bit set";
}

static void decode(const crash_body_t *f, txt_t *t)
{
    tx_s(t, "vector  "); tx_u(t, f->vector); tx_c(t, ' '); tx_s(t, vector_name(f->vector));
    tx_s(t, "  EXC_RETURN "); tx_h(t, f->exc_return);
    tx_s(t, ((f->exc_return & 8u) != 0u) ? " Thread" : " Handler");
    tx_s(t, ((f->exc_return & 4u) != 0u) ? " PSP" : " MSP");
    tx_s(t, ((f->exc_return & 16u) != 0u) ? " basic-frame\n" : " FP-frame\n");
    tx_s(t, "HFSR    "); tx_h(t, f->hfsr); tx_bits(t, f->hfsr, k_hfsr, sizeof k_hfsr / sizeof k_hfsr[0]); tx_c(t, '\n');
    tx_s(t, "CFSR    "); tx_h(t, f->cfsr);
    tx_bits(t, f->cfsr, k_mmfsr, sizeof k_mmfsr / sizeof k_mmfsr[0]);
    tx_bits(t, f->cfsr, k_bfsr, sizeof k_bfsr / sizeof k_bfsr[0]);
    tx_bits(t, f->cfsr, k_ufsr, sizeof k_ufsr / sizeof k_ufsr[0]);
    tx_c(t, '\n');
    if ((f->cfsr & CFSR_MMARVALID) != 0u) { tx_s(t, "MMFAR   "); tx_h(t, f->mmfar); tx_s(t, "  (faulting address)\n"); }
    if ((f->cfsr & CFSR_BFARVALID) != 0u) { tx_s(t, "BFAR    "); tx_h(t, f->bfar); tx_s(t, "  (faulting address)\n"); }
    tx_s(t, "cause   "); tx_s(t, diagnosis(f)); tx_c(t, '\n');
    if (f->frame_ok == 0u) {
        tx_s(t, "frame   NOT READ (SP outside RAM, or a stacking error made it untrustworthy)\n");
    } else {
        tx_s(t, "PC      "); tx_h(t, f->pc); tx_s(t, "  LR "); tx_h(t, f->lr);
        tx_s(t, "  xPSR "); tx_h(t, f->xpsr); tx_c(t, '\n');
        for (unsigned i = 0u; i < 13u; i++) {
            tx_s(t, (i < 10u) ? "r" : "r1");
            tx_u(t, (i < 10u) ? i : (i - 10u));
            tx_s(t, (i < 10u) ? "      " : "     ");
            tx_h(t, f->r[i]);
            tx_s(t, (((i % 4u) == 3u) || (i == 12u)) ? "\n" : "  ");
        }
    }
    tx_s(t, "SP      "); tx_h(t, f->sp); tx_s(t, "  MSP "); tx_h(t, f->msp);
    tx_s(t, "  PSP "); tx_h(t, f->psp); tx_c(t, '\n');
    tx_s(t, "trace  ");
    for (uint32_t i = 0u; (i < f->nbt) && (i < CRASH_NBT); i++) { tx_c(t, ' '); tx_h(t, f->bt[i]); }
    if (f->nbt == 0u) { tx_s(t, " (none)"); }
    tx_s(t, "\nbuild   "); tx_h(t, f->build_id); tx_c(t, '\n');
}

bool crash_take(volatile crash_record_t *r, char *out, size_t cap)
{
    txt_t t = { out, cap, 0u };
    bool ok = false;
    if (cap == 0u) {
        return false;
    }
    out[0] = '\0';
    if (r->magic != CRASH_MAGIC) {
        tx_s(&t, "no crash record (magic ");
        tx_h(&t, r->magic);
        tx_s(&t, ")\n");
    } else if (r->version != CRASH_VERSION) {
        tx_s(&t, "stale crash record layout ");
        tx_h(&t, r->version);
        tx_c(&t, '\n');
    } else if (r->crc != crash_crc(r)) {
        tx_s(&t, "crash record CRC mismatch: discarded\n");
    } else {
        union { crash_body_t f; uint32_t w[CRASH_BODY_WORDS]; } snap;
        for (size_t i = 0u; i < CRASH_BODY_WORDS; i++) {   /* snapshot out of volatile memory */
            snap.w[i] = r->body.w[i];
        }
        tx_s(&t, "CRASH RECORD (crc ok)\n");
        decode(&snap.f, &t);
        ok = true;
    }
    r->magic = 0u;                                       /* consumed or rejected: never twice */
    return ok;
}
```

**Test firmware** (the File 01 boot, a PSP task faulting three calls deep):

```c
/* main_crash.c - boots with the File 01 crt0; reports a crash record left by
 * the previous run, otherwise starts a task on PSP that faults three calls deep
 * (a sensor driver reading an external-bus window whose controller was never
 * initialized: the interconnect answers with a bus error). */
#include <stdint.h>

#include "board.h"
#include "crash.h"

extern crash_record_t g_crash;
char                  g_report[1024];
volatile uint32_t     g_boot_result;          /* 1: crash reported, 2: app started */
volatile uint32_t     g_sink;
DTCM_BSS uint64_t     g_task_stack[256];      /* 2 KB task stack (PSP)             */

typedef struct { const volatile uint32_t *regs; uint32_t gain; } sensor_t;
static const sensor_t k_sensor = { (const volatile uint32_t *)0x60000000u, 3u };

__attribute__((noinline)) uint32_t sensor_read(const sensor_t *s, uint32_t ch);
__attribute__((noinline)) uint32_t filter_step(const sensor_t *s, uint32_t n);
__attribute__((noinline)) void app_task(void);
__attribute__((noinline)) void boot_done(void);

uint32_t sensor_read(const sensor_t *s, uint32_t ch)
{
    return s->regs[ch] * s->gain;                 /* the faulting load */
}

uint32_t filter_step(const sensor_t *s, uint32_t n)
{
    uint32_t acc = 0u;
    for (uint32_t ch = 0u; ch < n; ch++) {
        acc = (acc >> 1) + sensor_read(s, ch);
    }
    return acc ^ n;
}

void app_task(void)
{
    for (;;) {
        g_sink = filter_step(&k_sensor, 4u);
    }
}

void boot_done(void)
{
    for (;;) {
        __asm__ volatile("" : : : "memory");
    }
}

static void start_task_on_psp(void (*fn)(void)) __attribute__((noreturn));
static void start_task_on_psp(void (*fn)(void))
{
    uint32_t top = (uint32_t)(uintptr_t)&g_task_stack[256];
    __asm__ volatile("msr   psp, %0     \n\t"
                     "movs  r1, #2      \n\t"
                     "msr   control, r1 \n\t"      /* Thread mode on PSP, like an RTOS task */
                     "isb               \n\t"
                     "blx   %1          \n\t"
                     : : "r"(top), "r"(fn) : "r1", "lr", "memory");
    for (;;) { }
}

int main(void)
{
    if (crash_take(&g_crash, g_report, sizeof g_report)) {
        g_boot_result = 1u;
        boot_done();
    }
    g_boot_result = 2u;
    start_task_on_psp(app_task);
}
```

**Build** (File 01 objects plus the crash subsystem):

```bash
for f in startup_h7 board_mpu mpu crash_fault crash_decode main_crash; do zig clang $CF -std=c11 -c $f.c -o $f.o; done
zig ld.lld -T linker_h7.ld --gc-sections -z max-page-size=4 -z norelro -Map crash.map \
    -o crash.elf startup_h7.o board_mpu.o mpu.o crash_fault.o crash_decode.o main_crash.o
```

**The emulation harness.** Unicorn executes the firmware; the harness supplies the bus error, the architectural exception entry and the warm reset:

```python
"""emu_crash.py - power-on, fault, reset, report: the crash subsystem end to end.
Unicorn executes the firmware; this harness supplies what Unicorn lacks:
  * a bus that answers unmapped accesses with an error -> the harness performs
    the ARMv7-M exception entry (B1.5.6: 8-word frame on the active stack,
    STKALIGN padding, LR = EXC_RETURN, Handler mode on MSP, IPSR = 3) and sets
    CFSR/HFSR/BFAR/ICSR as a precise BusFault escalated to HardFault would;
  * SYSRESETREQ (AIRCR write with VECTKEY) -> warm reset: RAM retained, SCS
    registers back to reset values, execution from the reset vector.
usage: emu_crash.py fw.elf"""
import sys
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_MEM_UNMAPPED, UC_HOOK_MEM_WRITE
from unicorn.arm_const import *
import capstone as cs

elf = ELFFile(open(sys.argv[1], "rb"))
syms, funcs = {}, []
for s in elf.get_section_by_name(".symtab").iter_symbols():
    if s.name:
        syms[s.name] = s["st_value"]
        if s["st_info"]["type"] == "STT_FUNC":
            funcs.append((s["st_value"] & ~1, s["st_size"], s.name))
def symbolize(a):
    a &= ~1
    for base, size, name in funcs:
        if base <= a < base + size:
            return f"{name}+0x{a - base:X}"
    return "?"

REG = {"FLASH": (0x08000000, 0x200000), "ITCM": (0x0, 0x10000), "DTCM": (0x20000000, 0x20000),
       "AXI": (0x24000000, 0x80000), "D2": (0x30000000, 0x20000), "BKP": (0x38800000, 0x1000),
       "PERIPH": (0x40000000, 0x100000), "SCS": (0xE000E000, 0x1000)}
uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
uc.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_M7)
for name, (b, n) in REG.items():
    uc.mem_map(b, n)
    if name not in ("FLASH", "SCS"):
        uc.mem_write(b, b"\xA5" * n)             # power-on: RAM holds garbage
for seg in elf.iter_segments():
    if seg["p_type"] == "PT_LOAD" and seg["p_filesz"] and 0x08000000 <= seg["p_paddr"] < 0x08200000:
        uc.mem_write(seg["p_paddr"], seg.data())

R = uc.reg_read
def rd(a): return int.from_bytes(uc.mem_read(a, 4), "little")
def wr(a, v): uc.mem_write(a, (v & 0xFFFFFFFF).to_bytes(4, "little"))
def scs_reset():
    uc.mem_write(0xE000E000, b"\x00" * 0x1000)    # CFSR/HFSR/BFAR/... reset to 0
    wr(0xE000ED00, 0x411FC272)                     # CPUID Cortex-M7 r1p2
    wr(0xE000ED80, 0x000FE019)                     # CCSIDR: 16 KB, 4-way, 32 B lines
    wr(0xE000ED14, 0x00000200)                     # CCR reset value (STKALIGN)

ev = {"fault": None, "reset": None}
def on_unmapped(uc_, access, addr, size, value, data):
    ev["fault"] = {"addr": addr, "pc": R(UC_ARM_REG_PC),
                   "regs": [R(r) for r in (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3,
                                           UC_ARM_REG_R4, UC_ARM_REG_R5, UC_ARM_REG_R6, UC_ARM_REG_R7,
                                           UC_ARM_REG_R8, UC_ARM_REG_R9, UC_ARM_REG_R10, UC_ARM_REG_R11,
                                           UC_ARM_REG_R12)],
                   "lr": R(UC_ARM_REG_LR), "xpsr": R(UC_ARM_REG_XPSR), "control": R(UC_ARM_REG_CONTROL),
                   "msp": R(UC_ARM_REG_MSP), "psp": R(UC_ARM_REG_PSP)}
    return False
def on_aircr(uc_, access, addr, size, value, data):
    if (value >> 16) == 0x05FA and (value & 4):
        ev["reset"] = value & 0xFFFFFFFF
        uc_.emu_stop()
uc.hook_add(UC_HOOK_MEM_UNMAPPED, on_unmapped)
uc.hook_add(UC_HOOK_MEM_WRITE, on_aircr, begin=0xE000ED0C, end=0xE000ED0F)

def take_hardfault(f):
    on_psp = (f["control"] >> 1) & 1
    sp = f["psp"] if on_psp else f["msp"]
    xpsr = (f["xpsr"] & ~0x1FF) | 0x01000000
    frame_at = sp - 32
    if frame_at & 4:                               # STKALIGN: 8-byte aligned frame
        frame_at -= 4
        xpsr |= 1 << 9
    r = f["regs"]
    for i, v in enumerate((r[0], r[1], r[2], r[3], r[12], f["lr"], f["pc"] & ~1, xpsr)):
        wr(frame_at + 4 * i, v)
    if on_psp:
        uc.reg_write(UC_ARM_REG_PSP, frame_at)
    else:
        uc.reg_write(UC_ARM_REG_MSP, frame_at)
    wr(0xE000ED28, 0x00008200)                     # CFSR: BFARVALID | PRECISERR
    wr(0xE000ED2C, 0x40000000)                     # HFSR: FORCED (BusFault disabled in SHCSR)
    wr(0xE000ED38, f["addr"])                      # BFAR
    wr(0xE000ED04, 3)                              # ICSR.VECTACTIVE = HardFault
    uc.reg_write(UC_ARM_REG_CONTROL, f["control"] & ~2)    # handler runs on MSP
    uc.reg_write(UC_ARM_REG_XPSR, 0x01000003)      # Handler mode, IPSR = 3
    exc_return = 0xFFFFFFFD if on_psp else 0xFFFFFFF9
    uc.reg_write(UC_ARM_REG_LR, exc_return)
    f["frame_at"], f["exc_return"], f["stacked_xpsr"] = frame_at, exc_return, xpsr
    return rd(syms["g_vectors"] + 4 * 3)

vec = syms["g_vectors"]
md = cs.Cs(cs.CS_ARCH_ARM, cs.CS_MODE_THUMB | cs.CS_MODE_MCLASS)
truth = None
for boot in (1, 2):
    scs_reset()
    uc.reg_write(UC_ARM_REG_CONTROL, 0)
    uc.reg_write(UC_ARM_REG_XPSR, 0x01000000)
    uc.reg_write(UC_ARM_REG_MSP, rd(vec))
    pc = rd(vec + 4)
    kind = "power-on" if boot == 1 else "warm reset (SYSRESETREQ), RAM retained"
    print(f"=== boot {boot}: {kind}")
    while True:
        ev["fault"] = ev["reset"] = None
        try:
            uc.emu_start(pc | 1, syms["boot_done"] & ~1, timeout=5_000_000, count=5_000_000)
        except UcError:
            pass
        if ev["fault"]:
            f = ev["fault"]
            ins = next(md.disasm(bytes(uc.mem_read(f["pc"], 4)), f["pc"]))
            print(f"  bus error: load from 0x{f['addr']:08X} by '{ins.mnemonic} {ins.op_str}' at "
                  f"PC=0x{f['pc']:08X} ({symbolize(f['pc'])}), Thread mode on {'PSP' if (f['control'] >> 1) & 1 else 'MSP'}")
            pc = take_hardfault(f)
            print(f"  exception entry: frame at 0x{f['frame_at']:08X}, LR=EXC_RETURN 0x{f['exc_return']:08X}, "
                  f"-> HardFault_Handler 0x{pc & ~1:08X}")
            truth = f
            continue
        if ev["reset"] is not None:
            print(f"  handler wrote AIRCR=0x{ev['reset']:08X} (VECTKEY|SYSRESETREQ) -> system reset")
            break
        if R(UC_ARM_REG_PC) == syms["boot_done"] & ~1 and boot == 1:
            raise SystemExit("unexpected: boot 1 reached boot_done")
        pcnow = R(UC_ARM_REG_PC)
        if pcnow == syms["boot_done"] & ~1:
            print(f"  boot_done: g_boot_result={rd(syms['g_boot_result'])}")
            rep = bytes(uc.mem_read(syms["g_report"], 1024)).split(b"\0")[0].decode()
            for line in rep.rstrip("\n").split("\n"):
                print("  | " + line)
            break
        hf = [(b, n) for b, n, name in funcs if name == "HardFault_Handler"][0]
        if truth and hf[0] <= pcnow < hf[0] + hf[1]:
            print(f"  handler never resets: still spinning at PC=0x{pcnow:08X} after 5,000,000 instructions")
            if "g_bad_pc" in syms:
                print(f"  it reported PC=0x{rd(syms['g_bad_pc']):08X} ({symbolize(rd(syms['g_bad_pc']))}) "
                      f"LR=0x{rd(syms['g_bad_lr']):08X} ({symbolize(rd(syms['g_bad_lr']))}) CFSR=0x{rd(syms['g_bad_cfsr']):08X}")
                print(f"  truth:      PC=0x{truth['pc']:08X} ({symbolize(truth['pc'])}) "
                      f"LR=0x{truth['lr']:08X} ({symbolize(truth['lr'])})")
            print(f"  backup SRAM record magic: 0x{rd(syms['g_crash']):08X} (nothing survives the eventual watchdog reset)")
            raise SystemExit(0)
        raise SystemExit(f"stopped unexpectedly at PC=0x{pcnow:08X}")
    if boot == 1:
        rep = bytes(uc.mem_read(syms["g_report"], 1024)).split(b"\0")[0].decode().strip()
        print(f"  (this boot's own check of the power-on contents said: {rep})")
        print(f"  backup SRAM record magic after the fault: 0x{rd(syms['g_crash']):08X}")
        continue
    if boot == 2 and truth:
        body = syms["g_crash"] + 12
        names = ["build_id", "vector", "exc_return", "frame_ok"] + [f"r{i}" for i in range(13)] + \
                ["sp", "lr", "pc", "xpsr", "msp", "psp", "cfsr", "hfsr", "mmfar", "bfar", "afsr", "shcsr", "nbt"]
        val = {n: rd(body + 4 * i) for i, n in enumerate(names)}
        nbt = val["nbt"]
        bt = [rd(body + 4 * (len(names) + i)) for i in range(nbt)]
        print("  offline symbolization of the trace (host side, ELF symtab):")
        for i, a in enumerate(bt):
            print(f"    #{i} 0x{a:08X} {symbolize(a)}")
        t = truth
        expect = {"vector": 3, "exc_return": t["exc_return"], "frame_ok": 1, "pc": t["pc"] & ~1,
                  "lr": t["lr"], "xpsr": t["stacked_xpsr"], "bfar": t["addr"], "cfsr": 0x8200,
                  "hfsr": 0x40000000, "psp": t["frame_at"],
                  "sp": t["frame_at"] + 32 + (4 if t["stacked_xpsr"] & 0x200 else 0)}
        for i in range(13):
            expect[f"r{i}"] = t["regs"][i]
        bad = [k for k, v in expect.items() if val[k] != v]
        print(f"  record vs injected CPU state: {len(expect) - len(bad)}/{len(expect)} fields match"
              + (f"  MISMATCH: {bad}" if bad else ""))
        print(f"  record magic after report: 0x{rd(syms['g_crash']):08X} (consumed)")
```

**End-to-end result (verified):**

```
=== boot 1: power-on
  bus error: load from 0x60000000 by 'ldr.w r0, [r0, r1, lsl #2]' at PC=0x08002E3C (sensor_read+0x4), Thread mode on PSP
  exception entry: frame at 0x20000BF0, LR=EXC_RETURN 0xFFFFFFFD, -> HardFault_Handler 0x080005F8
  handler wrote AIRCR=0x05FA0004 (VECTKEY|SYSRESETREQ) -> system reset
  (this boot's own check of the power-on contents said: no crash record (magic 0xA5A5A5A5))
  backup SRAM record magic after the fault: 0x43525348
=== boot 2: warm reset (SYSRESETREQ), RAM retained
  boot_done: g_boot_result=1
  | CRASH RECORD (crc ok)
  | vector  3 HardFault  EXC_RETURN 0xFFFFFFFD Thread PSP basic-frame
  | HFSR    0x40000000 FORCED
  | CFSR    0x00008200 PRECISERR BFARVALID
  | BFAR    0x60000000  (faulting address)
  | cause   precise bus error: data access at BFAR by the instruction at PC
  | PC      0x08002E3C  LR 0x08002E61  xPSR 0x41000000
  | r0      0x60000000  r1      0x00000000  r2      0x00000003  r3      0x0000000A
  | r4      0x00000004  r5      0x080035FC  r6      0x00000000  r7      0x00000000
  | r8      0x00003FE0  r9      0x0000007F  r10     0x00000003  r11     0xE000EF60
  | r12     0x080030FA
  | SP      0x20000C10  MSP 0x20002C40  PSP 0x20000BF0
  | trace   0x08002E3D 0x08002E61 0x08002E91
  | build   0x07A1B2C3
  offline symbolization of the trace (host side, ELF symtab):
    #0 0x08002E3D sensor_read+0x4
    #1 0x08002E61 filter_step+0x18
    #2 0x08002E91 app_task+0x18
  record vs injected CPU state: 24/24 fields match
  record magic after report: 0x00000000 (consumed)
```

Clause by clause:

| Evidence | Meaning |
|---|---|
| Boot 1: `no crash record (magic 0xA5A5A5A5)` | Power-on contents of backup SRAM rejected, not misreported |
| `ldr.w r0, [r0, r1, lsl #2]` at `sensor_read+0x4`, Thread mode on PSP | The faulting load. The harness stacked the frame on **PSP** with `EXC_RETURN = 0xFFFFFFFD` |
| `AIRCR = 0x05FA0004` | The handler captured, sealed (magic `0x43525348` = "CRSH" present after the fault) and requested the reset |
| Boot 2: `CFSR 0x00008200 PRECISERR BFARVALID`, `HFSR FORCED`, `BFAR 0x60000000` | Cause, escalation and faulting data address, all captured before the reset cleared them |
| `PC 0x08002E3C`, `r0 0x60000000` (the sensor's register base) | The faulting instruction and its base register |
| `r8 = 0x3FE0`, `r9 = 0x7F`, `r11 = 0xE000EF60` | r4–r11 really are live values: leftovers of crt0's DCISW loop (File 01), which the app never touched. Only the naked stub can capture these |
| `SP 0x20000C10 = PSP + 32` | Basic frame, no alignment pad |
| trace → `sensor_read+0x4`, `filter_step+0x18`, `app_task+0x18` | Frame #0 from the PC, #1 from the live LR (a leaf fault), #2 found by the BL-preceded scan, then symbolized on the host |
| `24/24 fields match` | Every register, the PC, LR, xPSR, EXC_RETURN, CFSR, HFSR, BFAR, SP and PSP are equal to the injected CPU state |
| magic `0x00000000` after the report | Reported exactly once |

**Host test of the decoder and validation** (paths the emulation doesn't reach):

```c
/* crash_host_test.c - the decoder and the record validation on the host, with
 * synthetic records for every decode path the emulator run does not reach. */
#include <stdio.h>
#include <string.h>

#include "crash.h"

static crash_record_t g_rec;
static char g_out[1024];

static void fill(uint32_t vector, uint32_t exc_return, uint32_t cfsr, uint32_t hfsr, uint32_t frame_ok)
{
    memset(&g_rec, 0, sizeof g_rec);
    crash_body_t *f = &g_rec.body.f;
    f->build_id = 0x07A1B2C3u;
    f->vector = vector;
    f->exc_return = exc_return;
    f->cfsr = cfsr;
    f->hfsr = hfsr;
    f->frame_ok = frame_ok;
    for (unsigned i = 0u; i < 13u; i++) { f->r[i] = 0x1000u * i; }
    f->pc = 0x08001234u; f->lr = 0x08001301u; f->xpsr = 0x01000000u;
    f->sp = 0x2000F000u; f->msp = 0x2000F000u; f->psp = 0x20004000u;
    f->nbt = 2u; f->bt[0] = 0x08001235u; f->bt[1] = 0x08001301u;
}

static void run(const char *title)
{
    bool ok = crash_take(&g_rec, g_out, sizeof g_out);
    printf("--- %s -> %s\n%s", title, ok ? "VALID" : "rejected", g_out);
}

int main(void)
{
    fill(4u, 0xFFFFFFE9u, CFSR_DACCVIOL | CFSR_MMARVALID, 0u, 1u);
    g_rec.body.f.mmfar = 0x00000008u;
    crash_seal(&g_rec);
    run("A: MemManage, NULL->field, FP frame on MSP");
    run("A again: a record is reported exactly once");

    fill(6u, 0xFFFFFFFDu, CFSR_DIVBYZERO, 0u, 1u);
    crash_seal(&g_rec);
    run("B: UsageFault, divide by zero, task on PSP");

    fill(3u, 0xFFFFFFFDu, CFSR_STKERR, HFSR_FORCED, 0u);
    g_rec.body.f.sp = 0x1FFFFFE0u;
    g_rec.body.f.nbt = 0u;                            /* capture records no trace then */
    crash_seal(&g_rec);
    run("C: stacking error (task stack overflow), frame not read");

    fill(3u, 0xFFFFFFF1u, CFSR_IMPRECISERR, HFSR_FORCED, 1u);
    crash_seal(&g_rec);
    run("D: imprecise BusFault inside an ISR (Handler mode)");

    fill(3u, 0xFFFFFFF9u, CFSR_INVSTATE, HFSR_FORCED, 1u);
    crash_seal(&g_rec);
    g_rec.body.w[10] ^= 0x00000100u;                  /* one bit flips after sealing */
    run("E: bit flip in the body after sealing");

    fill(3u, 0xFFFFFFF9u, CFSR_UNDEFINSTR, HFSR_FORCED, 1u);
    crash_seal(&g_rec);
    g_rec.version = (1u << 16) | 40u;                 /* written by older firmware */
    run("F: record from a firmware with a different layout");

    memset(&g_rec, 0xA5, sizeof g_rec);
    run("G: power-on contents of backup SRAM");
    return 0;
}
```

**Result (verified, host):**

```
--- A: MemManage, NULL->field, FP frame on MSP -> VALID
CRASH RECORD (crc ok)
vector  4 MemManage  EXC_RETURN 0xFFFFFFE9 Thread MSP FP-frame
HFSR    0x00000000
CFSR    0x00000082 DACCVIOL MMARVALID
MMFAR   0x00000008  (faulting address)
cause   MPU violation (NULL or stale pointer if MMFAR is small)
PC      0x08001234  LR 0x08001301  xPSR 0x01000000
r0      0x00000000  r1      0x00001000  r2      0x00002000  r3      0x00003000
r4      0x00004000  r5      0x00005000  r6      0x00006000  r7      0x00007000
r8      0x00008000  r9      0x00009000  r10     0x0000A000  r11     0x0000B000
r12     0x0000C000
SP      0x2000F000  MSP 0x2000F000  PSP 0x20004000
trace   0x08001235 0x08001301
build   0x07A1B2C3
--- A again: a record is reported exactly once -> rejected
no crash record (magic 0x00000000)
--- B: UsageFault, divide by zero, task on PSP -> VALID
CRASH RECORD (crc ok)
vector  6 UsageFault  EXC_RETURN 0xFFFFFFFD Thread PSP basic-frame
HFSR    0x00000000
CFSR    0x02000000 DIVBYZERO
cause   integer divide by zero (CCR.DIV_0_TRP=1)
PC      0x08001234  LR 0x08001301  xPSR 0x01000000
r0      0x00000000  r1      0x00001000  r2      0x00002000  r3      0x00003000
r4      0x00004000  r5      0x00005000  r6      0x00006000  r7      0x00007000
r8      0x00008000  r9      0x00009000  r10     0x0000A000  r11     0x0000B000
r12     0x0000C000
SP      0x2000F000  MSP 0x2000F000  PSP 0x20004000
trace   0x08001235 0x08001301
build   0x07A1B2C3
--- C: stacking error (task stack overflow), frame not read -> VALID
CRASH RECORD (crc ok)
vector  3 HardFault  EXC_RETURN 0xFFFFFFFD Thread PSP basic-frame
HFSR    0x40000000 FORCED
CFSR    0x00001000 STKERR
cause   stack overflow/corruption during exception entry: frame not trustworthy
frame   NOT READ (SP outside RAM, or a stacking error made it untrustworthy)
SP      0x1FFFFFE0  MSP 0x2000F000  PSP 0x20004000
trace   (none)
build   0x07A1B2C3
--- D: imprecise BusFault inside an ISR (Handler mode) -> VALID
CRASH RECORD (crc ok)
vector  3 HardFault  EXC_RETURN 0xFFFFFFF1 Handler MSP basic-frame
HFSR    0x40000000 FORCED
CFSR    0x00000400 IMPRECISERR
cause   imprecise bus error: stacked PC is NOT the faulting store (buffered write); M3/M4: rerun with ACTLR.DISDEFWBUF=1, any core: DSB after suspect stores
PC      0x08001234  LR 0x08001301  xPSR 0x01000000
r0      0x00000000  r1      0x00001000  r2      0x00002000  r3      0x00003000
r4      0x00004000  r5      0x00005000  r6      0x00006000  r7      0x00007000
r8      0x00008000  r9      0x00009000  r10     0x0000A000  r11     0x0000B000
r12     0x0000C000
SP      0x2000F000  MSP 0x2000F000  PSP 0x20004000
trace   0x08001235 0x08001301
build   0x07A1B2C3
--- E: bit flip in the body after sealing -> rejected
crash record CRC mismatch: discarded
--- F: record from a firmware with a different layout -> rejected
stale crash record layout 0x00010028
--- G: power-on contents of backup SRAM -> rejected
no crash record (magic 0xA5A5A5A5)
```

What the host cases cover:

- **A:** MemManage with `MMARVALID` and `MMFAR = 0x8` (a NULL-pointer field access) and an **FP frame** (`EXC_RETURN 0xFFFFFFE9`). Taking it a second time is rejected: reported exactly once.
- **B:** a direct UsageFault (not escalated, `HFSR = 0`).
- **C:** `STKERR` (task stack overflow). The frame is not read and there is no trace.
- **D:** an **imprecise** BusFault from an ISR (`EXC_RETURN 0xFFFFFFF1`, Handler mode). The diagnosis warns that PC is not the culprit.
- **E–G:** a single-bit flip after sealing (CRC), a record from firmware with another layout (version), and power-on garbage (magic). All three are rejected, none misreported.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

**Reading a record:**

| CFSR / HFSR pattern | Meaning | Next step |
|---|---|---|
| `PRECISERR + BFARVALID` | The instruction at PC accessed BFAR on a bus that answered with an error | Check BFAR against the memory map: unclocked peripheral, uninitialized external bus, powered-down domain |
| `IMPRECISERR` (no BFAR) | A **buffered write** failed later; PC is innocent | Cortex-M3/M4: set `ACTLR.DISDEFWBUF = 1` to make it precise. Any core: add `DSB` after suspect stores, or map the region Strongly-ordered with the MPU while hunting |
| `DACCVIOL + MMARVALID`, MMFAR < 0x100 | NULL pointer + field offset | The File 01 NULL guard makes this a clean MemManage fault |
| `IACCVIOL`, or `IBUSERR` with PC in RAM/peripheral space | Executing from XN memory, or a corrupt function pointer | Check the MPU XN map; check LR to find the caller that branched |
| `INVSTATE` | Branch to an even address: a NULL or corrupt function pointer, or `bx` to data | The stacked LR names the caller |
| `INVPC` | Corrupt EXC_RETURN (a handler overwrote its LR on the stack) | Stack overflow in a handler; check the MSP high-water mark |
| `STKERR`/`MSTKERR` | Stacking failed: **stack overflow** | Frame invalid; check SP against the stack limits. v8-M: `PSPLIM`/`MSPLIM` gives `STKOF` before the corruption |
| `UNDEFINSTR` | Executing data, or corrupted or overwritten code | Compare the code at PC with the ELF (flash corruption vs a wild jump) |
| `NOCP` | FP instruction with the FPU disabled | CPACR ordering in crt0 (File 01) |
| `HFSR.FORCED` and CFSR = 0 | A fault in a handler at equal or higher priority, or **SVC executed in an ISR of higher priority** | Check ICSR/IPSR and SVC usage in ISRs |
| `HFSR.VECTTBL` | Vector fetch failed | VTOR value and table placement |
| No record after a watchdog reset | Lockup (fault inside the handler), or the handler never ran | Validate every dereference; keep the stub tiny; use the private crash stack |

**Tools:**

- **Offline symbolization:** `arm-none-eabi-addr2line -f -i -e fw-<build_id>.elf 0x08002E3C 0x08002E61 0x08002E91`, or `llvm-symbolizer`. The `build_id` in the record selects the ELF; keep every released ELF.
- **Live, with a debugger:** the handler's `bkpt` path halts with the fault intact.
  - GDB: `info registers`, then `x/8wx $psp` (or `$msp`, per LR bit 2), then `info symbol <stacked PC>`.
  - Trace32: `Register.view`, `Frame.view /Caller` (it unwinds through the exception frame), `Data.dump E:0xE000ED28--0xE000ED3F`.
  - Segger Ozone: a built-in fault analyzer reads the same registers.
- **ETM/MTB trace:** an instruction trace buffer (MTB on M0+/M23/M33, ETB/ETF on M7) holds the last *N* branches before the fault. That is the only way to see *how* execution arrived at a wild PC. Freeze the trace in the handler's first instruction.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Write me a production HardFault handler for a Cortex-M7 running an RTOS."

- **L5:** "A C handler that reads the stacked PC from SP + 24 and prints the registers over the UART, then loops."
- **Why L5 fails on real hardware:**
  - Under an RTOS the faulting frame is on **PSP**. The verified forum handler read MSP and reported `PC = 0xA5A5A5A5`.
  - A C prologue shifts SP by an amount the optimizer chooses.
  - The UART may be the faulting peripheral, or need interrupts (masked at priority −1).
  - Looping loses everything at the watchdog reset.
- **L7 principal defense:**
  - A naked stub: EXC_RETURN[2] picks MSP/PSP; save r4–r11 and MSP; pass IPSR; switch to a private stack; then C.
  - C captures CFSR/HFSR/MMFAR/BFAR/AFSR/SHCSR first, validates the frame (RAM range, alignment, no STKERR/MSTKERR), and scans BL/BLX-preceded return addresses within bounds.
  - It writes a magic-last, CRC-sealed, versioned record with a build ID into non-cacheable backup SRAM.
  - Then: debugger attached → `bkpt`; else `dsb` + SYSRESETREQ (VECTKEY `0x05FA`, PRIGROUP preserved), with the watchdog as backstop.
  - The next boot validates, reports once and invalidates. Symbolization is offline.
  - Verified end to end: 24/24 fields match and the trace resolves to `sensor_read` → `filter_step` → `app_task`.

### Q2 🔥 "The crash log says the fault is in `memcpy`, but `memcpy` is fine. Explain."

- **L5:** "Memory corruption; run a memory test."
- **Why L5 fails:** Look at CFSR. `IMPRECISERR` means a **buffered store** failed some cycles earlier; the stacked PC is wherever execution had got to. `memcpy` is a frequent victim because it issues many stores in a row. BFAR is not valid for imprecise faults.
- **L7 defense:**
  - Make the fault precise to find the culprit: `ACTLR.DISDEFWBUF = 1` on M3/M4 (it costs performance, so debug only). On cores without it, use `DSB` after suspect stores or MPU Strongly-ordered mapping of the suspect region.
  - Rerun. Now `PRECISERR + BFARVALID` names the instruction and the address.
  - Typical culprits: writes to an unclocked peripheral, or a posted write to a region whose controller was powered down.

### Q3 "Why do you switch to a private stack in the handler? Isn't MSP fine?"

- **L5:** "MSP is the handler stack; it's fine."
- **Why L5 fails:** The most common HardFault cause *is* stack overflow, often on MSP itself (ISR nesting, deep recursion in an interrupt). If the handler's C code pushes onto an exhausted or corrupted MSP, the second fault happens **inside HardFault**, and that is lockup: no record and no reset until the watchdog fires.
- **L7 defense:**
  - Do register-only work in the naked stub, then `mov sp, <private crash stack>`, sized by static stack analysis of `crash_capture` (`-fstack-usage`, Folder 08).
  - Record the original MSP and PSP in the record; validate them before use.
  - On v8-M, add `MSPLIM`/`PSPLIM`, so an overflow becomes a clean `STKOF` UsageFault *before* the corruption.

### Q4 "After a field crash, the device reboots in a loop. Design crash-loop protection."

- **L5:** "Fix the bug."
- **Why L5 fails:** Devices in the field can't wait for a fix. A deterministic crash at boot (corrupt configuration, a failed sensor, a bad OTA) makes the unit unusable and burns flash-wear and battery.
- **L7 defense:**
  - A **crash counter** next to the record in the backup domain, protected by a complement word or CRC. Increment it in `crash_capture`. Clear it only after the application has run healthily for *T* seconds (watchdog kicked from a supervisor that checks every task: Folder 08 File 01).
  - On boot, if the counter is ≥ *N*: enter **safe mode** (minimal drivers, telemetry and OTA only), or **roll back** to the previous firmware slot (A/B images, Folder 02 File 03).
  - Report the crash records from safe mode.
  - Record the hardware reset cause (watchdog / software / brown-out / pin) at the same time, because it disambiguates "crashed" from "hung" from "browned out".

### Q5 🧊 "What happens if your HardFault handler itself faults?"

- **L5:** "It takes another HardFault."
- **Why L5 fails:** HardFault runs at priority −1. A synchronous fault at that priority cannot be taken, so the core enters **lockup** (ARMv7-M B1.5.15). It stops executing, asserts LOCKUP, and stays there until a reset (watchdog, or a SoC lockup-reset feature ⚠ verify per part). A debugger sees "core locked up" with PC = `0xEFFFFFFE`-class values.
- **L7 defense:**
  - Make lockup structurally impossible:
    - register-only naked stub;
    - private stack;
    - every dereference bounds-checked (frame, scan, code halfwords);
    - no peripherals, no `printf`, no flash writes in the handler;
    - non-cacheable record memory (no maintenance needed).
  - Keep the independent watchdog running as the last line of defense.
  - Log the hardware reset cause, since "watchdog with no record" is itself a diagnostic (§3).

---

## 5. Invariants Checklist

- [ ] HardFault, MemManage, BusFault and UsageFault all enter the same **naked** stub. The configurable faults are enabled in SHCSR in production, so they don't escalate.
- [ ] The stub selects the frame by `EXC_RETURN[2]`, saves r4–r11 + MSP, records IPSR, switches to a private crash stack, and branches to C.
- [ ] Fault registers read first. MMFAR/BFAR trusted only with MMARVALID/BFARVALID. W1C clear after capture.
- [ ] Every dereference bounds-checked. Frame trusted only without STKERR/MSTKERR. Basic vs FP frame and the STKALIGN pad handled.
- [ ] Record in NOLOAD, never-zeroed, non-cacheable memory: magic written last, layout version, CRC, build ID.
- [ ] Debugger attached → `bkpt`; otherwise `dsb` + SYSRESETREQ with VECTKEY and PRIGROUP preserved; watchdog backstop.
- [ ] Next boot: validate, report once, invalidate. Crash-loop counter and safe mode. Hardware reset cause recorded.
- [ ] Symbolization offline against archived ELFs; trace understood as heuristic (tail calls and leaf functions).
- [ ] The fault path is tested without hardware: emulated exception entry + warm reset, plus host tests of every decode path.

## 6. References

1. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E): B1.5.6 (exception entry), B1.5.7 (stack alignment), B1.5.8 (EXC_RETURN), B1.5.15 (lockup), B3.2.6 (AIRCR), B3.2.15–B3.2.18 (CFSR, HFSR, MMFAR, BFAR), C1.6.2 (DHCSR).
2. Arm, *Armv8-M Architecture Reference Manual* (DDI 0553): stack limit registers and `STKOF`, SecureFault, extended EXC_RETURN encodings.
3. Arm/Keil, *Application Note 209: Using Cortex-M3/M4/M7 Fault Exceptions*.
4. Arm, *Cortex-M4 Devices Generic User Guide* (DUI 0553): ACTLR (DISDEFWBUF), fault handling. *Cortex-M7 TRM* (DDI 0489): AFSR, lazy FP stacking, ETM.
5. Zephyr RTOS `arch/arm/core/cortex_m/fault.c` and `fault_s.S` (production fault decoding); FreeRTOS forum `prvGetRegistersFromStack` (the classic handler, and the PSP pitfall).
6. CmBacktrace (github.com/armink/CmBacktrace) and Memfault's coredump/`memfault-firmware-sdk` (production crash capture and offline symbolization).
7. Segger, *AN00016: Analyzing HardFaults on Cortex-M*; Trace32 `Frame.view` documentation.
8. File 01 (boot, MPU map, `.bkp_noinit`), Folder 02 File 03 (A/B secure boot for rollback), Folder 08 File 01 (watchdog supervisor, static stack analysis).
