# 02 · Reset Vector, crt0, `.bss` Zeroing, `.data` Relocation, and XIP Flash

> **Folder:** `02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/` · **File 2 of 3**
> **Anchors:**
> - ARMv7-M ARM (DDI 0403) §B1.5.5 *Reset behavior*, §B3.2 SCB (VTOR, CPACR, AIRCR); ARMv8-M ARM (DDI 0553).
> - Arm ARM for A-profile (DDI 0487): reset state, CPACR_EL1, VBAR_ELx, MPIDR_EL1.
> - RISC-V Privileged ISA (mtvec, mhartid); RISC-V psABI (`__global_pointer$`, relaxation).
> - Arm AN321 (barriers after CPACR/VTOR writes); Cortex-M7 TRM (cache enable sequence).
> - STM32 reference manuals and app notes for flash latency, ART and QSPI XIP (⚠ verify part-specific numbers).
>
> **Verification:** the Cortex-M7, AArch64 and RISC-V startup code in this file was compiled (Clang 21.1.0), linked (LLD 21.1.0), and **executed in Unicorn 2.1.4** with RAM pre-filled with `0xA5` power-on garbage. Only the bytes stored in non-volatile memory were loaded, which simulates a cold boot. All outputs shown are from those runs.

---

## 0. The thesis

Between the reset signal and the first line of `main`, the C language's promises do not yet hold:

- initialized globals don't have their values;
- zero-initialized globals aren't zero;
- on A-profile and RISC-V cores there isn't even a stack;
- the FPU may trap;
- the clock may be a slow internal oscillator with flash wait states set for it.

`crt0` builds the C abstract machine out of raw silicon. Every bug in it is a bug in *every* function that runs afterwards. That's why Tier-1 interviews ask about it.

---

## 1. First-Principles Hardware Mechanics

### 1.1 What the hardware guarantees at reset

| | Cortex-M (ARMv6-M/v7-M/v8-M) | Cortex-A (AArch64) | RISC-V (M-mode) |
|---|---|---|---|
| First fetch | `PC = vector[1]` (bit 0 must be 1: Thumb), `MSP = vector[0]`, both read from the reset `VTOR` (address 0, or a vendor boot alias) | `PC = RVBAR_ELx` (implementation-defined) | Implementation-defined reset vector |
| Stack | **Valid immediately** (loaded from vector 0) | **None**: SP is UNKNOWN | **None** |
| Mode | Privileged Thread, MSP, `PRIMASK = 0`, all NVIC IRQs disabled | Highest implemented EL (often EL3), MMU/caches off | M-mode, `mtvec` not usable until written |
| FPU | Disabled (`CPACR = 0` → `NOCP` UsageFault on the first FP instruction) | Trapped at EL1/EL0 until `CPACR_EL1.FPEN` is set | Off until `mstatus.FS` ≠ 0 |
| Caches/MPU | Off (Cortex-M7 I/D caches disabled, MPU disabled) | Off | Platform-specific |
| Multi-core | Usually single core per cluster | Every core starts at reset (unless held by a power controller); primary must be selected via `MPIDR_EL1` | Every hart starts; select via `mhartid` |

**Cortex-M was designed so that the reset handler can be plain C.** The hardware loads the stack pointer, and the AAPCS caller-saved frame matches the exception frame (Folder 01, File 03). A-profile and RISC-V must start in assembly.

### 1.2 The Cortex-M7 Reset_Handler, in C

This is the complete startup used throughout Folder 02 (vector table, weak default handlers, crt0):

```c
/* startup_min.c - Cortex-M7 crt0 in C: vector table, Reset_Handler, default
 * handlers. Hardware loads MSP from vector[0] and PC from vector[1], so C is
 * legal from the first instruction of Reset_Handler. */
#include <stdint.h>

/* Linker-script symbols: declared as arrays of unknown bound (no size the
 * optimizer can reason about, File 01 section 3.3). */
extern uint32_t __stack_top[];
extern uint32_t __data_load__[], __data_start__[], __data_end__[];
extern uint32_t __ramfunc_load__[], __ramfunc_start__[], __ramfunc_end__[];
extern uint32_t __bss_start__[], __bss_end__[];
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

/* A union makes "word 0 is a stack pointer, the rest are handlers" expressible
 * in ISO C without converting an object pointer to a function pointer. */
typedef union {
    void (*handler)(void);
    const void *stack_top;
} vector_entry_t;

__attribute__((section(".isr_vector"), used))
const vector_entry_t g_vector_table[16] = {
    { .stack_top = __stack_top },
    { .handler = Reset_Handler },
    { .handler = NMI_Handler },
    { .handler = HardFault_Handler },
    { .handler = MemManage_Handler },
    { .handler = BusFault_Handler },
    { .handler = UsageFault_Handler },
    { .handler = 0 }, { .handler = 0 }, { .handler = 0 }, { .handler = 0 },
    { .handler = SVC_Handler },
    { .handler = 0 },              /* DebugMon */
    { .handler = 0 },              /* reserved */
    { .handler = PendSV_Handler },
    { .handler = SysTick_Handler },
};

#define SCB_VTOR   (*(volatile uint32_t *)0xE000ED08u)
#define SCB_CPACR  (*(volatile uint32_t *)0xE000ED88u)

/* Word copy / fill through volatile pointers: the loops cannot be turned into
 * calls to memcpy/memset (which may themselves live in .ramfunc, or be built
 * with FP/SIMD instructions that are not yet enabled). */
static void copy_words(uint32_t *dst, const uint32_t *src, const uint32_t *dst_end)
{
    volatile uint32_t *d = dst;
    const volatile uint32_t *s = src;
    uintptr_t n = ((uintptr_t)dst_end - (uintptr_t)dst) / sizeof(uint32_t);
    for (uintptr_t i = 0u; i < n; i++) {
        d[i] = s[i];
    }
}

static void zero_words(uint32_t *dst, const uint32_t *dst_end)
{
    volatile uint32_t *d = dst;
    uintptr_t n = ((uintptr_t)dst_end - (uintptr_t)dst) / sizeof(uint32_t);
    for (uintptr_t i = 0u; i < n; i++) {
        d[i] = 0u;
    }
}

__attribute__((noreturn)) void Reset_Handler(void)
{
    /* 1. FPU on before ANY floating-point instruction can execute:
     *    CP10/CP11 full access, then DSB+ISB so the next instruction sees it. */
    SCB_CPACR |= (0xFu << 20);
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory");

    /* 2. Point VTOR at our table (needed when a bootloader jumped here). */
    SCB_VTOR = (uint32_t)(uintptr_t)g_vector_table;
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory");

    /* 3. Code that must run from ITCM: copy LMA -> VMA before anyone calls it. */
    copy_words(__ramfunc_start__, __ramfunc_load__, __ramfunc_end__);

    /* 4. .data: copy initial values from FLASH. 5. .bss: zero. */
    copy_words(__data_start__, __data_load__, __data_end__);
    zero_words(__bss_start__, __bss_end__);

    /* Instruction-side visibility of the code we just wrote into ITCM. */
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory");

    /* 6. Static constructors (C __attribute__((constructor)), C++ globals). */
    for (const init_fn_t *f = __init_array_start; f < __init_array_end; f++) {
        (*f)();
    }

    /* 7. main. Returning from main on bare metal is a bug: park the core. */
    (void)main();
    for (;;) {
        __asm__ volatile("wfi" : : : "memory");
    }
}

void Default_Handler(void)
{
    for (;;) {
    }
}
```

The test application, which touches every section class so the emulator can prove each one was set up:

```c
/* main_min.c - exercises every section class so an emulator run can prove the
 * startup code did its job. */
#include <stdint.h>

uint32_t g_table[4] = { 0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u }; /* .data   */
uint32_t g_zero[8];                                                              /* .bss    */
const uint32_t g_k = 0xC0DEC0DEu;                                                /* .rodata */
__attribute__((section(".noinit"))) uint32_t g_boot_count;                       /* .noinit */
volatile uint32_t g_result[6];                                                   /* .bss    */

static uint32_t ctor_ran;

/* Reads hardware, so the compiler cannot evaluate it at build time and must
 * emit a real .init_array entry (a constant-only constructor gets folded away). */
__attribute__((constructor)) static void early_ctor(void)
{
    ctor_ran = *(const volatile uint32_t *)0xE000ED00u;   /* SCB->CPUID */
}

/* Lives in ITCM; called from FLASH code 128 MB away -> needs a long-branch thunk. */
__attribute__((section(".ramfunc"), noinline)) uint32_t ram_mix(uint32_t a, uint32_t b);
__attribute__((section(".ramfunc"), noinline)) uint32_t ram_mix(uint32_t a, uint32_t b)
{
    return (a ^ b) + 0x5A5A5A5Au;
}

__attribute__((noinline)) void test_done(void);
__attribute__((noinline)) void test_done(void)
{
    for (;;) {
        __asm__ volatile("" : : : "memory");
    }
}

int main(void)
{
    uint32_t sum = 0u;
    uint32_t zeros_ok = 1u;

    for (unsigned i = 0u; i < 4u; i++) {
        sum += g_table[i];
    }
    for (unsigned i = 0u; i < 8u; i++) {
        if (g_zero[i] != 0u) {
            zeros_ok = 0u;
        }
    }
    g_result[0] = sum;
    g_result[1] = zeros_ok;
    g_result[2] = ram_mix(sum, g_k);
    g_result[3] = (uint32_t)(uintptr_t)&ram_mix;
    g_result[4] = ctor_ran;
    g_result[5] = ++g_boot_count;
    test_done();
    return 0;
}
```

**Build evidence (verified):** both files compile with zero diagnostics under the full warning set (`-std=c11`, Cortex-M7). They link with the File 01 script (`fw_min.ld`), and section and segment headers are in File 01 §1.1.

**Execution evidence (verified):** Unicorn Cortex-M7, RAM pre-filled with `0xA5`, flash image loaded at LMAs, then two resets without re-filling RAM, so the second is a warm reset. The emulator planted `CPUID = 0x411FC272`.

```text
run 1: reset SP=0x20001050 PC=0x08000049 -> stopped at 0x08000268 (test_done)
  g_result@0x20000034: 0xAAAAAAAA 0x00000001 0xC4CEC4CE 0x00000001 0x411FC272 0xA5A5A5A6
  g_zero@0x20000014: 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000
run 2: reset SP=0x20001050 PC=0x08000049 -> stopped at 0x08000268 (test_done)
  g_result@0x20000034: 0xAAAAAAAA 0x00000001 0xC4CEC4CE 0x00000001 0x411FC272 0xA5A5A5A7
  g_zero@0x20000014: 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000 0x00000000
```

Line by line:

| Result | Value | Proves |
|---|---|---|
| `g_result[0]` | `0xAAAAAAAA` = Σ `g_table` | `.data` was copied from flash (the RAM had `0xA5A5A5A5`) |
| `g_result[1]` | 1, and `g_zero` all 0 | `.bss` was zeroed over garbage |
| `g_result[2]` | `0xC4CEC4CE` = `(0xAAAAAAAA ^ 0xC0DEC0DE) + 0x5A5A5A5A` | The ITCM copy of `ram_mix` executed (through the linker thunk, File 01 §1.5.1) |
| `g_result[3]` | `0x00000001` | `ram_mix` is at ITCM address 0, with the Thumb bit |
| `g_result[4]` | `0x411FC272` | The constructor ran (it read `SCB->CPUID`) |
| `g_result[5]` | `0xA5A5A5A6`, then `0xA5A5A5A7` | **`.noinit` survives a warm reset, but its first value is garbage.** Any `.noinit` consumer must validate it (§1.6) |

**The Reset_Handler as linked (verified, capstone disassembly of `fw_min.elf`):**

```asm
Reset_Handler:
  08000048:  movw     r0, #0xed88
  0800004c:  movw     lr, #0
  08000050:  movt     r0, #0xe000
  08000054:  movt     lr, #0
  08000058:  ldr      r1, [r0]
  0800005a:  orr      r1, r1, #0xf00000
  0800005e:  str      r1, [r0]
  08000060:  movw     r1, #0
  08000064:  dsb      sy
  08000068:  isb      sy
  0800006c:  movt     r1, #0x800
  08000070:  str      r1, [r0, #-0x80]
  08000074:  movw     r0, #8
  08000078:  dsb      sy
  0800007c:  isb      sy
  08000080:  movt     r0, #0
  08000084:  subs.w   r0, r0, lr
  08000088:  beq      #0x8000112
  0800008a:  mov.w    r1, #-1
  0800008e:  add.w    r1, r1, r0, lsr #2
  08000092:  cmp      r1, #3
  08000094:  movw     r1, #0x318
  08000098:  ubfx     ip, r0, #2, #2
  0800009c:  movt     r1, #0x800
  080000a0:  bhs      #0x80000ac
  080000a2:  movs     r2, #0
  080000a4:  cmp.w    ip, #0
  080000a8:  bne      #0x80000ea
  080000aa:  b        #0x8000112
  080000ac:  mvn      r2, #3
  080000b0:  movs     r3, #0
  080000b2:  and.w    r0, r2, r0, lsr #2
  080000b6:  rsbs     r2, r0, #0
  080000b8:  movs     r0, #0
  080000ba:  nop
  080000bc:  nop
  080000be:  nop
  080000c0:  adds     r4, r1, r0
  080000c2:  add.w    r5, lr, r0
  080000c6:  ldr      r6, [r1, r0]
  080000c8:  str.w    r6, [lr, r0]
  080000cc:  ldr      r6, [r4, #4]
  080000ce:  str      r6, [r5, #4]
  080000d0:  subs     r3, #4
  080000d2:  ldr      r6, [r4, #8]
  080000d4:  str      r6, [r5, #8]
  080000d6:  cmp      r2, r3
  080000d8:  add.w    r0, r0, #0x10
  080000dc:  ldr      r4, [r4, #0xc]
  080000de:  str      r4, [r5, #0xc]
  080000e0:  bne      #0x80000c0
  080000e2:  rsbs     r2, r3, #0
  080000e4:  cmp.w    ip, #0
  080000e8:  beq      #0x8000112
  080000ea:  cmp.w    ip, #1
  080000ee:  ldr.w    r0, [r1, r2, lsl #2]
  080000f2:  str.w    r0, [lr, r2, lsl #2]
  080000f6:  beq      #0x8000112
  080000f8:  adds     r0, r2, #1
  080000fa:  cmp.w    ip, #2
  080000fe:  ldr.w    r3, [r1, r0, lsl #2]
  08000102:  str.w    r3, [lr, r0, lsl #2]
  08000106:  beq      #0x8000112
  08000108:  adds     r0, r2, #2
  0800010a:  ldr.w    r1, [r1, r0, lsl #2]
  0800010e:  str.w    r1, [lr, r0, lsl #2]
  08000112:  movw     lr, #0
  08000116:  movw     r0, #0x10
  0800011a:  movt     lr, #0x2000
  0800011e:  movt     r0, #0x2000
  08000122:  subs.w   r0, r0, lr
  08000126:  beq      #0x80001aa
  08000128:  mov.w    r1, #-1
  0800012c:  add.w    r1, r1, r0, lsr #2
  08000130:  cmp      r1, #3
  08000132:  movw     r1, #0x320
  08000136:  ubfx     ip, r0, #2, #2
  0800013a:  movt     r1, #0x800
  0800013e:  bhs      #0x800014a
  08000140:  movs     r2, #0
  08000142:  cmp.w    ip, #0
  08000146:  bne      #0x8000182
  08000148:  b        #0x80001aa
  0800014a:  mvn      r2, #3
  0800014e:  movs     r3, #0
  08000150:  and.w    r0, r2, r0, lsr #2
  08000154:  rsbs     r2, r0, #0
  08000156:  movs     r0, #0
  08000158:  adds     r4, r1, r0
  0800015a:  add.w    r5, lr, r0
  0800015e:  ldr      r6, [r1, r0]
  08000160:  str.w    r6, [lr, r0]
  08000164:  ldr      r6, [r4, #4]
  08000166:  str      r6, [r5, #4]
  08000168:  subs     r3, #4
  0800016a:  ldr      r6, [r4, #8]
  0800016c:  str      r6, [r5, #8]
  0800016e:  cmp      r2, r3
  08000170:  add.w    r0, r0, #0x10
  08000174:  ldr      r4, [r4, #0xc]
  08000176:  str      r4, [r5, #0xc]
  08000178:  bne      #0x8000158
  0800017a:  rsbs     r2, r3, #0
  0800017c:  cmp.w    ip, #0
  08000180:  beq      #0x80001aa
  08000182:  cmp.w    ip, #1
  08000186:  ldr.w    r0, [r1, r2, lsl #2]
  0800018a:  str.w    r0, [lr, r2, lsl #2]
  0800018e:  beq      #0x80001aa
  08000190:  adds     r0, r2, #1
  08000192:  cmp.w    ip, #2
  08000196:  ldr.w    r3, [r1, r0, lsl #2]
  0800019a:  str.w    r3, [lr, r0, lsl #2]
  0800019e:  beq      #0x80001aa
  080001a0:  adds     r0, r2, #2
  080001a2:  ldr.w    r1, [r1, r0, lsl #2]
  080001a6:  str.w    r1, [lr, r0, lsl #2]
  080001aa:  movw     ip, #0x10
  080001ae:  movw     r0, #0x4c
  080001b2:  movt     ip, #0x2000
  080001b6:  movt     r0, #0x2000
  080001ba:  subs.w   r1, r0, ip
  080001be:  beq      #0x8000214
  080001c0:  lsrs     r0, r1, #2
  080001c2:  movs     r2, #0
  080001c4:  cmp      r0, #1
  080001c6:  mov.w    r0, #1
  080001ca:  it       hi
  080001cc:  lsrhi    r0, r1, #2
  080001ce:  cmp      r1, #0x10
  080001d0:  and      r1, r0, #3
  080001d4:  blo      #0x80001fa
  080001d6:  bic      r0, r0, #3
  080001da:  sub.w    r3, ip, #0x10
  080001de:  rsbs     r0, r0, #0
  080001e0:  movs     r4, #0
  080001e2:  nop
  080001e4:  nop
  080001e6:  nop
  080001e8:  subs     r4, #4
  080001ea:  str      r2, [r3, #0x10]!
  080001ee:  cmp      r0, r4
  080001f0:  str      r2, [r3, #4]
  080001f2:  str      r2, [r3, #8]
  080001f4:  str      r2, [r3, #0xc]
  080001f6:  bne      #0x80001e8
  080001f8:  rsbs     r2, r4, #0
  080001fa:  cbz      r1, #0x8000214
  080001fc:  cmp      r1, #1
  080001fe:  mov.w    r0, #0
  08000202:  str.w    r0, [ip, r2, lsl #2]
  08000206:  beq      #0x8000214
  08000208:  add.w    r2, ip, r2, lsl #2
  0800020c:  cmp      r1, #2
  0800020e:  str      r0, [r2, #4]
  08000210:  it       ne
  08000212:  strne    r0, [r2, #8]
  08000214:  movw     r4, #0x318
  08000218:  movw     r0, #0x314
  0800021c:  movt     r4, #0x800
  08000220:  movt     r0, #0x800
  08000224:  dsb      sy
  08000228:  isb      sy
  0800022c:  cmp      r0, r4
  0800022e:  bhs      #0x8000244
  08000230:  subs     r5, r0, #4
  08000232:  nop
  08000234:  nop
  08000236:  nop
  08000238:  ldr      r0, [r5, #4]!
  0800023c:  blx      r0
  0800023e:  adds     r0, r5, #4
  08000240:  cmp      r0, r4
  08000242:  blo      #0x8000238
  08000244:  bl       #0x8000270
  08000248:  wfi
  0800024a:  b        #0x8000248
```

The `nop`s are alignment padding the compiler emitted before loop heads. `ldr r0, [r5, #4]!` + `blx r0` is the constructor walk over `.init_array`.

What to verify in your own startup's disassembly:

1. **CPACR first.** `0xE000ED88 |= 0x00F00000` precedes everything, followed by `dsb`/`isb`. No `vldr`/`vstr`/`vmov` appears before it. In a hard-float build the compiler is allowed to use FP registers for ordinary copies, so this check is real.
2. **VTOR.** `str r1, [r0, #-0x80]` writes `0xE000ED08` (`0xE000ED88 − 0x80`) with `0x08000000`, then `dsb`/`isb`.
3. **No library calls.** The three loops are open-coded and unrolled four times with word `ldr`/`str`. There is no `bl memcpy` and no `__aeabi_memclr`. Compare §2.1.
4. **Linker constants.** `0x08000318` = `__ramfunc_load__`, `0x08000320` = `__data_load__`, and `0x20000010`–`0x2000004C` = `.bss`. These match `readelf` in File 01.
5. **Constructors** run through `blx r0` from `.init_array`, then `bl main` (`0x08000270`), then the `wfi` park loop.

### 1.3 The "C before the C runtime" rules

Code that runs before step 5 completes (CPACR, the copies, the zeroing) must not depend on:

| Dependency | Why it breaks | How it sneaks in |
|---|---|---|
| Any global with an initializer, or one expected to be zero | Not yet copied or zeroed | A helper that uses a `static` counter; `errno` |
| **Compiler-generated library calls** | `memcpy`/`memset` may not be linked, may live in `.ramfunc` (not yet copied), or may use FP/SIMD (not yet enabled) | **Loop idiom recognition** (verified, §2.1: Clang turns plain copy/zero loops into `__aeabi_memcpy4`/`__aeabi_memclr4`); struct assignment |
| Stack protector | `__stack_chk_guard` is in `.bss`/`.data`: uninitialized, then *changed* by the zeroing, so the canary check fails when the function returns | `-fstack-protector-strong` applied to the startup TU. Build crt0 with `-fno-stack-protector` |
| FP/SIMD | `NOCP` UsageFault until `CPACR` is written | Hard-float ABI, auto-vectorized copies, `double` in a "harmless" debug helper |
| Profiling / instrumentation | `-pg`, `-finstrument-functions` and sanitizers call runtime hooks that use globals | Build flags applied globally |
| Clocks and flash latency | Raising SYSCLK before raising flash wait states makes instruction fetches return garbage | `SystemInit()` ordering (§1.7) |

The production stance is to compile the startup TU with `-ffreestanding -fno-builtin -fno-stack-protector -fno-profile-arcs -fno-sanitize=all` **and** write the copy loops through `volatile`, so correctness doesn't depend on any flag being present. Both are belt and braces.

### 1.4 Linker-script symbols are not C objects

`extern uint32_t _sdata, _edata;` (the STM32Cube style) declares two **separate scalar objects**. `&_edata - &_sdata` is then a subtraction of pointers to different objects, and `p < &_edata` is a relational comparison between them: both UB (Folder 01, File 01 §3.3). GCC 12 and later can warn about out-of-bounds access through them (`-Warray-bounds`) when they're treated as single objects. The robust form, used in `startup_min.c`, is:

- declare them as `extern uint32_t __data_start__[];`;
- compute counts in `uintptr_t`;
- index from one base.

### 1.5 A-profile and RISC-V: the assembly crt0 is mandatory

#### 1.5.1 AArch64

```asm
// start_a64.S - AArch64 bare-metal entry. Unlike Cortex-M, an A-profile core
// comes out of reset with NO stack pointer, MMU and caches off, FP/SIMD
// trapped, at the highest implemented EL. C cannot run until this file has
// established all of that.

    .section .text.boot, "ax"
    .global _start
    .type   _start, %function
_start:
    // 1. Only the primary core continues; secondaries park (MPIDR_EL1.Aff0 != 0).
    mrs     x0, mpidr_el1
    and     x0, x0, #0xff
    cbnz    x0, park

    // 2. Find our EL (CurrentEL[3:2]) and enable FP/SIMD for EL1/EL0.
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    cmp     x0, #1
    b.ne    park                     // this minimal entry expects EL1 (TF-A/hypervisor hand-off)
    mov     x0, #(3 << 20)           // CPACR_EL1.FPEN = 0b11: no trapping of FP/SIMD
    msr     cpacr_el1, x0
    isb

    // 3. Stack (16-byte aligned, AAPCS64) and exception vectors.
    ldr     x0, =__stack_top
    mov     sp, x0
    adr     x0, vectors
    msr     vbar_el1, x0
    isb

    // 4. Zero .bss with 16-byte stores (linker script aligns both ends to 16).
    ldr     x0, =__bss_start__
    ldr     x1, =__bss_end__
1:  cmp     x0, x1
    b.hs    2f
    stp     xzr, xzr, [x0], #16
    b       1b

    // 5. Copy .data from its load address (non-zero only for ROM/XIP images).
2:  ldr     x0, =__data_start__
    ldr     x1, =__data_end__
    ldr     x2, =__data_load__
3:  cmp     x0, x1
    b.hs    4f
    ldp     x3, x4, [x2], #16
    stp     x3, x4, [x0], #16
    b       3b

4:  bl      main
park:
    wfe
    b       park
    .size   _start, .-_start

    // Minimal vector table: 16 entries x 128 bytes, 2 KB aligned (VBAR_EL1[10:0] = 0).
    .section .vectors, "ax"
    .balign 2048
vectors:
    .rept   16
    b       .
    .balign 128
    .endr
```

```ld
/* a64.ld - AArch64 image executing from ROM at 0x0, data/stack in DRAM. */
ENTRY(_start)
MEMORY
{
  ROM  (rx)  : ORIGIN = 0x00000000, LENGTH = 1M
  DRAM (rwx) : ORIGIN = 0x40000000, LENGTH = 1M
}
SECTIONS
{
  .text : { KEEP(*(.text.boot)) *(.text .text.*) *(.rodata .rodata.*) } > ROM
  .vectors : { KEEP(*(.vectors)) } > ROM
  .data : ALIGN(16)
  {
    __data_start__ = .;
    *(.data .data.*)
    . = ALIGN(16);
    __data_end__ = .;
  } > DRAM AT > ROM
  __data_load__ = LOADADDR(.data);
  .bss (NOLOAD) : ALIGN(16)
  {
    __bss_start__ = .;
    *(.bss .bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end__ = .;
  } > DRAM
  .stack (NOLOAD) : ALIGN(16) { . = . + 0x4000; __stack_top = .; } > DRAM
}
ASSERT((ADDR(.vectors) & 0x7FF) == 0, "VBAR_EL1 needs 2 KB alignment")
```

```c
/* main_a64.c - proves .data was copied, .bss zeroed, and SIMD works after FPEN. */
#include <stdint.h>

uint64_t g_init[4] = { 1u, 2u, 3u, 4u };
uint64_t g_bss[6];
volatile uint64_t g_out[3];

__attribute__((noinline)) void a64_done(void);
__attribute__((noinline)) void a64_done(void) { for (;;) { __asm__ volatile("" ::: "memory"); } }

int main(void);
int main(void)
{
    uint64_t s = 0u, z = 0u;
    for (unsigned i = 0u; i < 4u; i++) { s += g_init[i]; }
    for (unsigned i = 0u; i < 6u; i++) { z |= g_bss[i]; }
    double d = (double)s * 1.5;              /* FP instruction: traps if FPEN was not set */
    g_out[0] = s;
    g_out[1] = z;
    g_out[2] = (uint64_t)d;
    a64_done();
    return 0;
}
```

**The layout bug the `ASSERT` caught (verified).** The first link of this image failed:

```text
ld.lld: error: VBAR_EL1 needs 2 KB alignment
```

The vector table was in an input section called `.text.vectors`, and the earlier `.text` rule's wildcard `*(.text .text.*)` **claimed it first**. Input sections go to the *first* output-section rule that matches. The dedicated `.vectors` rule then received nothing, and its address was simply "wherever `.text` ended". Without the `ASSERT`, the image would have linked, and the first exception would have vectored into the middle of `.text`. The fix was to name the input section `.vectors`, or to place the specific rule before the general one.

**Execution evidence (verified, Unicorn AArch64, cold boot):**

```text
  [ 1] .text             PROGBITS         0000000000000000  00001000
  [ 2] .vectors          PROGBITS         0000000000000800  00001800
  [ 3] .data             PROGBITS         0000000040000000  00002000
  [ 4] .bss              NOBITS           0000000040000020  00002020
  [ 5] .stack            NOBITS           0000000040000070  00002020
  LOAD           0x0000000000001000 0x0000000000000000 0x0000000000000000
  LOAD           0x0000000000002000 0x0000000040000000 0x0000000000001000
  LOAD           0x0000000000002020 0x0000000040000020 0x0000000040000020
entry 0x0 -> stopped at 0xB0 (a64_done)
  g_init@0x40000000: 0x1 0x2 0x3 0x4
  g_bss@0x40000020: 0x0 0x0 0x0 0x0 0x0 0x0
  g_out@0x40000050: 0xA 0x0 0xF
```

- `.vectors` is at `0x800`, 2 KB-aligned as `VBAR_EL1` requires.
- `.data` has VMA `0x40000000` and LMA `0x1000` (in ROM), and was copied.
- `.bss` was zeroed over `0xA5` garbage.
- `g_out[2] = 15 = (1+2+3+4) × 1.5`: the FP multiply executed. That works only because `CPACR_EL1.FPEN = 0b11` was set *before* `main` (otherwise the conversion would trap with ESR EC `0x07`).

Production AArch64 entry code also does the following:
- drops from EL3/EL2 to EL1 (`SCR_EL3`, `HCR_EL2.RW`, `SPSR_ELx`/`ELR_ELx` + `eret`);
- invalidates caches before enabling them;
- builds page tables and enables the MMU (File 03);
- releases secondary cores through PSCI `CPU_ON` (TF-A) or a spin-table.

#### 1.5.2 RISC-V

```asm
// start_rv.S - RISC-V (RV64 / RV32) machine-mode entry. Reset gives you a PC
// and nothing else: no sp, no gp, no trap vector.
    .section .text.init, "ax"
    .global _start
_start:
    // 1. gp MUST be loaded with relaxation disabled: otherwise the linker may
    //    "relax" this very sequence into a gp-relative access - using gp
    //    before it has been set.
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    // 2. Only hart 0 runs crt0; the others wait for an IPI.
    csrr    t0, mhartid
    bnez    t0, park

    la      sp, __stack_top          // 16-byte aligned per psABI
    la      t0, trap_entry
    csrw    mtvec, t0                // direct mode (mtvec[1:0] = 0)

    // 3. Zero .bss.
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       1b

    // 4. Copy .data from its load address.
2:  la      t0, __data_start
    la      t1, __data_end
    la      t2, __data_load
3:  bgeu    t0, t1, 4f
    ld      t3, 0(t2)
    sd      t3, 0(t0)
    addi    t0, t0, 8
    addi    t2, t2, 8
    j       3b

4:  call    main
park:
    wfi
    j       park

    .balign 4                        // mtvec requires 4-byte alignment
trap_entry:
    j       trap_entry
```

```ld
/* rv.ld - RV64 image in ROM at 0x8000_0000 (QEMU virt-style), RAM at 0x8010_0000. */
ENTRY(_start)
MEMORY
{
  ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 1M
  RAM (rwx) : ORIGIN = 0x80100000, LENGTH = 1M
}
SECTIONS
{
  .text : { KEEP(*(.text.init)) *(.text .text.*) *(.rodata .rodata.*) } > ROM
  .data : ALIGN(8)
  {
    __data_start = .;
    *(.data .data.*)
    /* gp points 2 KB into the small-data area so +/-2 KB gp-relative
     * offsets (12-bit signed immediates) cover 4 KB of hot globals. */
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
    . = ALIGN(8);
    __data_end = .;
  } > RAM AT > ROM
  __data_load = LOADADDR(.data);
  .bss (NOLOAD) : ALIGN(8)
  {
    __bss_start = .;
    *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > RAM
  .stack (NOLOAD) : ALIGN(16) { . = . + 0x4000; __stack_top = .; } > RAM
}
```

```c
/* main_rv.c - small globals land in .sdata/.sbss and are reached via gp. */
#include <stdint.h>

uint64_t g_init[4] = { 10u, 20u, 30u, 40u };
uint64_t g_small = 0x1234u;            /* .sdata: gp-relative after relaxation */
uint64_t g_bss[4];
volatile uint64_t g_out[3];

__attribute__((noinline)) void rv_done(void);
__attribute__((noinline)) void rv_done(void) { for (;;) { __asm__ volatile("" ::: "memory"); } }

int main(void);
int main(void)
{
    uint64_t s = 0u, z = 0u;
    for (unsigned i = 0u; i < 4u; i++) { s += g_init[i]; z |= g_bss[i]; }
    g_out[0] = s;
    g_out[1] = z;
    g_out[2] = g_small;
    rv_done();
    return 0;
}
```

**Execution evidence (verified, Unicorn RV64, cold boot; built with `-march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany`):**

```text
stopped at 0x80000076; gp=0x80100828 (__global_pointer$=0x80100828)
  g_init@0x80100008: 0xa 0x14 0x1e 0x28
  g_bss@0x80100040: 0x0 0x0 0x0 0x0
  g_out@0x80100028: 0x64 0x0 0x1234
_start:
  80000000:  auipc    gp, 0x101
  80000004:  addi     gp, gp, -0x7d8
  80000008:  csrr     t0, mhartid
  8000000c:  bnez     t0, 0x62
  80000010:  auipc    sp, 0x104
  80000014:  addi     sp, sp, 0x50
  80000018:  auipc    t0, 0
  8000001c:  addi     t0, t0, 0x5c
  80000020:  csrw     mtvec, t0
  80000024:  auipc    t0, 0x100
  80000028:  addi     t0, t0, 4
  8000002c:  auipc    t1, 0x100
  80000030:  addi     t1, t1, 0x34
  80000034:  bgeu     t0, t1, 0xc
  80000038:  sd       zero, 0(t0)
  8000003c:  c.addi   t0, 8
  8000003e:  c.j      -0xa
```

Two observations:

- **`la gp` stayed an `auipc`+`addi` pair**, which is what `.option norelax` guarantees. **GNU ld relaxes eligible accesses near `__global_pointer$` into single `gp`-relative instructions by default.** Without `norelax`, the `la gp` sequence *itself* is a relaxation candidate, which means using `gp` to compute `gp`. LLD 21 relaxes to `gp` only with `--relax-gp` (opt-in), so in this build `main` reached `g_small` through `auipc` (PC-relative). That is correct, just one instruction longer. Treat `norelax` around `la gp` as mandatory regardless of linker.
- `-mcmodel=medany` makes all addressing PC-relative within ±2 GB. That's required here, because the image sits at `0x8000_0000`, outside `medlow`'s absolute ±2 GB-around-0 window.

### 1.6 `.noinit` done right: validate before you trust

The verified run shows a `.noinit` variable starting as `0xA5A5A5A6`, power-on garbage plus one. Persistent RAM is valid only if you can prove it was *written by firmware*:

```c
/* noinit_record.h - a .noinit record that knows whether it is valid. */
#include <stdint.h>

typedef struct {
    uint32_t magic;          /* NOINIT_MAGIC when valid                       */
    uint32_t magic_inv;      /* ~magic: random power-on patterns rarely match */
    uint32_t boot_count;
    uint32_t last_reset_cause;
    uint32_t crc;            /* CRC-32 over the fields above (CRC routine not shown) */
} noinit_record_t;

#define NOINIT_MAGIC 0x4E4F494Eu   /* "NOIN" */

static inline int noinit_valid(const noinit_record_t *r, uint32_t crc)
{
    return (r->magic == NOINIT_MAGIC) && (r->magic_inv == ~NOINIT_MAGIC) && (r->crc == crc);
}
```

The policy has four parts:
1. On every boot, read the **reset-cause register** (STM32 `RCC_RSR`/`RCC_CSR`, NXP `RSTCTL`, or the `AIRCR.SYSRESETREQ`-initiated flag).
2. If the cause is power-on/brown-out, or the record is invalid, re-initialize the record.
3. Otherwise, trust it. That is how the Folder 07 HardFault handler's crash dump survives the watchdog reset it triggers.
4. On parts with ECC SRAM, **uninitialized ECC RAM may raise a double-bit error on first read**. Several Cortex-M7/M33 SoCs require RAM to be written once before reading, so `.noinit` must live in a non-ECC region or be scrubbed on cold boot (⚠ verify for your part).

### 1.7 XIP flash: wait states, accelerators, and RAM functions

Execute-in-place means instructions are fetched straight from flash, at flash speed:

| Mechanism | What it does | Startup consequence |
|---|---|---|
| **Wait states (latency)** | Embedded flash needs N CPU cycles per access at high SYSCLK (often 0 WS at 16–30 MHz, rising to 4–7 WS at 200–480 MHz, depending on voltage scaling; ⚠ verify the datasheet table) | **Raise latency before raising the clock, and lower the clock before lowering latency.** The wrong order means instruction fetches return garbage: a HardFault or random execution, *before* any handler is meaningful. Read the latency back to confirm it took effect before switching the clock source |
| Prefetch / ART accelerator / flash cache (STM32), Cortex-M7 L1 I-cache on AXIM | Hide wait states on sequential and looping code | Enable after the latency is set. Flash programming routines must invalidate them afterwards, or stale instructions execute |
| **Read-while-write** | On single-bank flash, the bus **stalls** for the whole erase or program (milliseconds) | Code that erases or programs flash, *and every ISR that may fire meanwhile*, must run from RAM. That's `.ramfunc` (in ITCM/SRAM) plus a RAM copy of the vector table (`VTOR` → RAM), or interrupts masked during the operation. Dual-bank flash allows executing from bank A while programming bank B |
| External QSPI/OSPI XIP (memory-mapped mode) | Instructions fetched over a quad/octal SPI at a mapped address (e.g. `0x9000_0000`) | Configure the controller and memory-mapped mode before jumping. On Cortex-M7, configure the MPU so **speculative accesses can't reach unmapped external regions**: vendor notes recommend a background no-access/XN region with explicit regions over the real device (⚠ verify for your part; File 03) |
| Copying code to RAM in a cached system | D-cache holds the copied instructions as *data*; the I-cache may hold stale lines | After copying to *cacheable* RAM: `SCB_CleanDCache_by_Addr` + `SCB_InvalidateICache` + `DSB` + `ISB`. TCM isn't cached, so the `dsb`/`isb` in `Reset_Handler` suffice for ITCM |

### 1.8 The bootloader → application jump

A bootloader must hand the application a core that looks freshly reset. Anything left running is a bug in the application that the application can't see:
- a SysTick still interrupting;
- a pending USB interrupt;
- `VTOR` still pointing at the bootloader;
- `CONTROL.SPSEL = 1`, so the core runs on PSP.

```c
/* boot_jump.c - Cortex-M bootloader -> application hand-off. The application
 * must start as if from reset: no pending/enabled IRQs, SysTick off, MSP and
 * VTOR from the application's own vector table, privileged Thread mode on MSP. */
#include <stdint.h>

#define SCB_VTOR      (*(volatile uint32_t *)0xE000ED08u)
#define SYST_CSR      (*(volatile uint32_t *)0xE000E010u)
#define SYST_RVR      (*(volatile uint32_t *)0xE000E014u)
#define SYST_CVR      (*(volatile uint32_t *)0xE000E018u)
#define NVIC_ICER(n)  (*(volatile uint32_t *)(0xE000E180u + 4u * (n)))
#define NVIC_ICPR(n)  (*(volatile uint32_t *)(0xE000E280u + 4u * (n)))
#define SCB_ICSR      (*(volatile uint32_t *)0xE000ED04u)
#define ICSR_PENDSTCLR (1u << 25)
#define ICSR_PENDSVCLR (1u << 27)
#define NVIC_WORDS    16u            /* covers 512 IRQ lines (implementation max 496) */

typedef enum { JUMP_ERR_SP = 1, JUMP_ERR_PC, JUMP_ERR_ALIGN } jump_err_t;

/* Validate the target vector table before committing. */
static int app_vectors_plausible(uint32_t base, uint32_t ram_lo, uint32_t ram_hi,
                                 uint32_t flash_lo, uint32_t flash_hi)
{
    const volatile uint32_t *v = (const volatile uint32_t *)(uintptr_t)base;
    uint32_t sp = v[0], pc = v[1];
    if ((base & 0x7Fu) != 0u)                                  { return JUMP_ERR_ALIGN; }
    if ((sp < ram_lo) || (sp > ram_hi) || ((sp & 7u) != 0u))  { return JUMP_ERR_SP; }
    if (((pc & 1u) == 0u) || (pc < flash_lo) || (pc >= flash_hi)) { return JUMP_ERR_PC; }
    return 0;
}

int boot_jump(uint32_t app_base, uint32_t ram_lo, uint32_t ram_hi,
              uint32_t flash_lo, uint32_t flash_hi);
int boot_jump(uint32_t app_base, uint32_t ram_lo, uint32_t ram_hi,
              uint32_t flash_lo, uint32_t flash_hi)
{
    int err = app_vectors_plausible(app_base, ram_lo, ram_hi, flash_lo, flash_hi);
    if (err != 0) {
        return err;
    }
    __asm__ volatile("cpsid i" : : : "memory");          /* 1. nothing may preempt us now   */
    SYST_CSR = 0u;                                       /* 2. SysTick off, cleared          */
    SYST_RVR = 0u;
    SYST_CVR = 0u;
    for (uint32_t i = 0u; i < NVIC_WORDS; i++) {         /* 3. every IRQ disabled + unpended */
        NVIC_ICER(i) = 0xFFFFFFFFu;
        NVIC_ICPR(i) = 0xFFFFFFFFu;
    }
    SCB_ICSR = ICSR_PENDSTCLR | ICSR_PENDSVCLR;          /*    system exceptions unpended   */
    SCB_VTOR = app_base;                                 /* 4. application's vector table   */
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory");

    const volatile uint32_t *v = (const volatile uint32_t *)(uintptr_t)app_base;
    uint32_t app_sp = v[0];
    uint32_t app_pc = v[1];
    /* 5. Switch to MSP-based privileged thread mode, load the app's MSP, and
     *    branch. Interrupts stay masked: the app's Reset_Handler unmasks them
     *    (or its crt0 runs with PRIMASK=1 until it has a valid vector table). */
    __asm__ volatile(
        "msr  control, %[zero]   \n\t"
        "isb  sy                 \n\t"
        "msr  msp, %[sp]         \n\t"
        "bx   %[pc]              \n\t"
        : : [zero] "r"(0u), [sp] "r"(app_sp), [pc] "r"(app_pc) : "memory");
    __builtin_unreachable();
}
```

**Build evidence (verified):** zero diagnostics on Cortex-M7 and Cortex-M33 (full warning set, `-std=c11`).

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
boot_jump:
	push	{r7, lr}
	lsls.w	r12, r0, #25
	ldr.w	lr, [r0]
	ldr.w	r12, [r0, #4]
	itt	ne
	movne	r0, #3
	popne	{r7, pc}
.LBB0_1:
	cmp	lr, r1
	mov.w	r1, #1
	blo	.LBB0_7
	cmp	lr, r2
	bhi	.LBB0_7
	ands	r2, lr, #7
	bne	.LBB0_7
	ldr	r1, [sp, #8]
	cmp	r12, r1
	mov.w	r1, #2
	bhs	.LBB0_7
	cmp	r12, r3
	blo	.LBB0_7
	ands	r2, r12, #1
	bne	.LBB0_8
.LBB0_7:
	mov	r0, r1
	pop	{r7, pc}
.LBB0_8:
	movw	r2, #57360
	cpsid i
	movt	r2, #57344
	movs	r1, #0
	mov.w	r3, #-1
	str	r1, [r2]
	str	r1, [r2, #4]
	str	r1, [r2, #8]
	str.w	r3, [r2, #368]
	str.w	r3, [r2, #624]
	str.w	r3, [r2, #372]
	str.w	r3, [r2, #628]
	str.w	r3, [r2, #376]
	str.w	r3, [r2, #632]
	str.w	r3, [r2, #380]
	str.w	r3, [r2, #636]
	str.w	r3, [r2, #384]
	str.w	r3, [r2, #640]
	str.w	r3, [r2, #388]
	str.w	r3, [r2, #644]
	str.w	r3, [r2, #392]
	str.w	r3, [r2, #648]
	str.w	r3, [r2, #396]
	str.w	r3, [r2, #652]
	str.w	r3, [r2, #400]
	str.w	r3, [r2, #656]
	str.w	r3, [r2, #404]
	str.w	r3, [r2, #660]
	str.w	r3, [r2, #408]
	str.w	r3, [r2, #664]
	str.w	r3, [r2, #412]
	str.w	r3, [r2, #668]
	str.w	r3, [r2, #416]
	str.w	r3, [r2, #672]
	str.w	r3, [r2, #420]
	str.w	r3, [r2, #676]
	str.w	r3, [r2, #424]
	str.w	r3, [r2, #680]
	str.w	r3, [r2, #428]
	str.w	r3, [r2, #684]
	movw	r2, #60676
	movt	r2, #57344
	mov.w	r3, #167772160
	str	r3, [r2]
	str	r0, [r2, #4]
	dsb	sy
	isb	sy
	ldr	r2, [r0]
	ldr	r0, [r0, #4]
	msr	control, r1
	isb	sy
	msr	msp, r2
	bx	r0
```

The base register is `0xE000E010` (`57344 << 16 | 57360`), the SysTick block. `ICER0` is `+368` (`0xE000E180`) and `ICPR0` is `+624` (`0xE000E280`). Then `0xE000ED04` gets `0x0A000000` (`PENDSVCLR | PENDSTCLR`) and `+4` = `VTOR` gets the application base. The volatile vector reads are redone after the `dsb`/`isb`, `CONTROL` is cleared and synchronized with `isb`, MSP is loaded, and `bx r0` (Thumb bit set) branches.

Also note: *this* code runs with the bootloader's stack until the final `msr msp`. Its locals live in registers, so switching MSP mid-function is safe. That's why the switch and branch are in **one** asm statement: no C code may run between them.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way: the vendor-template crt0

```c
/* startup_bad.c - the crt0 found in countless vendor templates. It looks
 * fine and has three latent defects (see the KB). */
#include <stdint.h>

extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss, _estack;   /* single objects! */
int main(void);
void Reset_Handler(void);
void Default_Handler(void);

typedef union { void (*handler)(void); const void *stack_top; } vector_entry_t;
__attribute__((section(".isr_vector"), used))
const vector_entry_t g_vector_table[16] = {
    { .stack_top = &_estack }, { .handler = Reset_Handler },
    { .handler = Default_Handler }, { .handler = Default_Handler },
};

void Reset_Handler(void)
{
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;
    while (dst < &_edata) {          /* relational compare of different objects */
        *dst++ = *src++;
    }
    for (dst = &_sbss; dst < &_ebss; ) {
        *dst++ = 0u;
    }
    (void)main();
    for (;;) {
    }
}

void Default_Handler(void)
{
    for (;;) {
    }
}
```

**Diagnostics (verified):** zero warnings under the full warning set (Cortex-M7, `-std=c11`).

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
Reset_Handler:
	movw	r1, :lower16:_edata
	movw	r0, :lower16:_sdata
	movt	r1, :upper16:_edata
	movt	r0, :upper16:_sdata
	cmp	r0, r1
	bhs	.LBB0_2
	subs	r1, r0, r1
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
	subs	r1, r0, r1
	mvn	r2, #3
	bic.w	r1, r2, r1
	adds	r1, #4
	bl	__aeabi_memclr4
.LBB0_4:
	bl	main
.LBB0_5:
	b	.LBB0_5
```

**Link result without a C library (verified, LLD):**

```text
ld.lld: error: undefined symbol: __aeabi_memcpy4
>>> referenced by startup_bad.c
>>>               startup_bad.o:(Reset_Handler)

ld.lld: error: undefined symbol: __aeabi_memclr4
>>> referenced by startup_bad.c
```

**With `-ffreestanding` or `-fno-builtin` (verified):** the loops stay loops, with no runtime calls in the listing.

The three defects:

1. **Loop idiom recognition.** Clang recognized both loops as `memcpy`/`memset` and emitted calls to the **ARM EABI runtime helpers** `__aeabi_memcpy4`/`__aeabi_memclr4`. In a normal newlib build these resolve, so *the build succeeds*. You are now calling a library routine before `.data`/`.bss` exist. That routine may:
   - be placed in `.ramfunc` or `.itcm` by a performance-minded colleague (not yet copied);
   - be the FP/NEON-optimized variant (FPU not yet enabled);
   - use a global (not yet initialized).
   
   GCC does the same transformation through `-ftree-loop-distribute-patterns` (⚠ verify per release), and GCC *requires* `memcpy`/`memset`/`memmove`/`memcmp` to exist even in freestanding mode.
2. **No CPACR, no VTOR, no barriers.** The first FP instruction anywhere before the clock setup enables the FPU raises `NOCP`. A bootloader-launched image takes its first interrupt through the *bootloader's* vector table.
3. **Linker symbols as scalar objects** with pointer relational comparisons (§1.4), which is UB the optimizer is entitled to use.

### 2.2 The Silicon-Hardened Production Way

`startup_min.c` (§1.2) is the hardened version:
- volatile word loops that are immune to idiom recognition (verified: unrolled `ldr`/`str`, no calls);
- CPACR then VTOR, each followed by `dsb`/`isb`;
- ITCM functions copied before any call;
- `.data` copied, then `.bss` zeroed;
- an instruction-side barrier;
- constructors;
- `main`;
- a park loop.

Extended for production (Folder 07, File 01 builds the full version), it adds:
1. **Cache enable on Cortex-M7** after the copies. I-cache: invalidate all, then enable, with `dsb`/`isb`. D-cache: invalidate by set/way, then enable. Once caches are on, any later code copy into *cacheable* RAM needs clean + invalidate.
2. **Clock bring-up ordered by flash latency** (§1.7).
3. **`.noinit` validation and reset-cause capture** before anything can trigger another reset (§1.6).
4. **MPU configuration** (File 03 encoders) before enabling caches, so DMA regions are non-cacheable from the first cached access.
5. **Stack limit** (`MSPLIM` on v8-M) set to `__stack_limit` as the very first instruction, or an MPU guard below the stack.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| Core locks up immediately; debugger shows `HFSR.VECTTBL` (bit 1) or lockup state | Vector-table read failed: wrong boot address, erased flash, or `VTOR` pointing at garbage | `x/2wx <boot address>`. Word 0 must be a plausible, 8-aligned SRAM address; word 1 must be odd and inside flash |
| HardFault before `main`, `CFSR.NOCP` (bit 19) | FP instruction before `CPACR` was written | Disassemble `Reset_Handler` and every function it calls for `v*` instructions |
| HardFault before `main`, `CFSR.INVSTATE` (bit 17) | Reset vector or a called function pointer without the Thumb bit | Vector word 1 even? `blx` to a data-derived address? |
| Random crash immediately after clock-tree setup | Flash wait states raised *after* SYSCLK | Single-step `SystemInit` with the vector catch. Read the latency register back |
| Globals correct under the debugger, wrong after a power cycle | LMA in RAM (File 01 §2.1), or a debugger `load` writing RAM sections | Cold boot with the debugger detached; compare RAM with the ELF (`compare-sections`) |
| `.noinit` record "valid" after a power cycle | No magic/CRC validation | §1.6 |
| Infinite reset loop before `main` | Watchdog enabled by option bytes (hardware IWDG) with a slow crt0 (large `.bss` zeroing at low clock), or a brown-out | Read reset-cause flags first thing. Pet the watchdog inside long zeroing loops, or zero `.bss` after raising the clock |
| Breakpoint at `Reset_Handler` never hits | Debugger attaches after reset | Enable **vector catch on core reset**: `DEMCR.VC_CORERESET` (bit 0, `0xE000EDFC`). Then the core halts at the first instruction of the reset handler. `monitor reset halt` in OpenOCD uses this |
| No printf available yet | It's crt0 | GPIO toggle with a logic analyzer; the ITM stimulus port (`0xE0000000`, via SWO) works before clocks and libc; or write a breadcrumb word to `.noinit` |

**TRACE32 reset-path recipe:**
1. `SYStem.Up` (halts at reset via vector catch);
2. `Register.view`, checking `SP` = vector 0 and `PC` = vector 1 & ~1;
3. `Data.dump 0x20000000--0x200000FF` before and after `Go Reset_Handler\main`;
4. `List.Mix` to step crt0 at instruction level.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Walk me from reset to `main` on a Cortex-M7."

- **L5:** "The reset handler copies `.data`, zeroes `.bss` and calls `main`."
- **Why L5 fails on hardware:** It omits:
  - what hardware does first (MSP from vector 0, PC from vector 1 with the Thumb bit);
  - `CPACR` enabling before *any* FP instruction, and the compiler may emit FP for ordinary code in a hard-float build;
  - `VTOR` for bootloader-launched images;
  - the ITCM/`.ramfunc` copy *before* the first call to such code;
  - barriers after system-register writes;
  - constructors;
  - flash-latency-before-clock ordering;
  - cache enable after the copies;
  - the fact that `main` must never return.
- **L7 defense:** The verified seven-step `Reset_Handler` (§1.2) with its disassembly, and the emulator evidence table (each result proves one step). Then the "C before C runtime" rules (§1.3), and the production additions: MPU, caches, clocks, `.noinit` validation, stack limit.

### Q2 🔥⚡ "Your crt0 is three lines of C. What can the compiler do to it?"

- **L5:** "Nothing; it's simple loops."
- **Why L5 fails:** Clang 21 at `-O2` turned both loops into **`__aeabi_memcpy4`/`__aeabi_memclr4` calls** (verified listing and link error). The startup then depends on a library routine running before the runtime exists. Other hazards: stack-protector code reading a guard that the zeroing later changes, instrumentation hooks, and FP-register moves before `CPACR`.
- **L7 defense:** Write the loops through `volatile` pointers (verified: open-coded `ldr`/`str`), and compile the TU with `-ffreestanding -fno-builtin -fno-stack-protector -fno-sanitize=all`. Then *read the disassembly in CI*: grep `Reset_Handler`'s listing for `bl`/`blx` before the call to `main`, and for any `v*` instruction before the `CPACR` store.

### Q3 "Why can Cortex-M start in C, but Cortex-A and RISC-V can't?"

- **L5:** "Cortex-M is simpler."
- **Why L5 fails:** It's an explicit architectural feature. Cortex-M **loads MSP from vector-table word 0** in hardware, and its exception frame matches the AAPCS caller-saved set. A-profile resets with SP UNKNOWN, possibly at EL3, with FP trapped and caches and MMU off, with every core running. RISC-V resets with nothing but a PC.
- **L7 defense:** Show the verified assembly entries:
  - **AArch64:** primary-core selection via `MPIDR_EL1`; EL check; `CPACR_EL1.FPEN` (and the verified FP multiply that would otherwise trap); SP; a 2 KB-aligned `VBAR_EL1`, which the `ASSERT` caught; `.bss`/`.data`.
  - **RISC-V:** `gp` under `.option norelax`; hart selection; `mtvec`; `-mcmodel=medany`.

### Q4 ⚡ "A colleague added `.option norelax` around `la gp` and asks if it's cargo cult."

- **L5:** "It disables an optimization; probably harmless either way."
- **Why L5 fails:** With relaxation, the linker may rewrite accesses near `__global_pointer$` as single `gp`-relative instructions. The `la gp, __global_pointer$` pair is itself such an access. Relaxing it would compute `gp` *from* `gp`, which is uninitialized at reset. GNU ld relaxes by default. LLD 21 needs `--relax-gp`, so in the verified build the bug would stay latent until someone switches linkers or flags.
- **L7 defense:** It's mandatory, because toolchain defaults differ (verified: LLD left `main`'s accesses PC-relative). Place `__global_pointer$` 2 KB into `.sdata` so ±2 KB 12-bit offsets cover the small-data area, and make sure interrupt handlers never change `gp`.

### Q5 🔥 "The bootloader jumps to the application, which crashes on its first interrupt. Why?"

- **L5:** "Set the stack pointer and jump."
- **Why L5 fails:** Several things are left over:
  - `VTOR` still points at the bootloader's table, so the application's first IRQ runs bootloader code;
  - SysTick or a peripheral IRQ is still enabled and pending;
  - `CONTROL.SPSEL` may be 1 (PSP);
  - the jump happened from inside an ISR (handler mode), so the application starts in Handler mode with an active exception;
  - nothing validated the application's vector table.
- **L7 defense:** The verified `boot_jump` (§1.8):
  1. validate SP/PC/alignment;
  2. `cpsid i`;
  3. SysTick off;
  4. clear every `ICER`/`ICPR` word and pending PendSV/SysTick;
  5. `VTOR` = app, then `dsb`/`isb`;
  6. `CONTROL = 0` + `isb`, MSP, and `bx` in **one asm statement**.

  Call it from Thread mode, never from an ISR (or trigger a system reset and branch early in the *bootloader's* `Reset_Handler`, based on a `.noinit` flag, which is the most robust pattern). File 03 adds signature verification before any of this.

### Q6 "Why does code that programs flash have to run from RAM?"

- **L5:** "Because you can't read flash while writing it."
- **Why L5 fails:** Close, but it misses the system consequences. On single-bank flash, the bus **stalls** instruction fetches for the full erase (milliseconds), so *every interrupt handler and vector-table read* in flash stalls too. Watchdogs fire, and real-time deadlines are missed.
- **L7 defense:**
  - The programming routine runs from `.ramfunc` (ITCM is ideal).
  - The vector table is relocated to RAM (`VTOR`), and any ISR allowed during programming is also in RAM; otherwise interrupts are masked, with the watchdog budget accounted for.
  - The flash accelerator and I-cache are invalidated afterwards.
  - Dual-bank parts use read-while-write across banks for A/B updates.
  - The linker places these routines with `AT > FLASH`, and the thunk cost from flash callers is noted (File 01 §1.5.1).

### Q7 🧊 "How do you make a crash log survive the watchdog reset it triggers, and how do you know it's real?"

- **L5:** "Put it in `.noinit`."
- **Why L5 fails:** The verified run shows `.noinit` starting as `0xA5A5A5A6`, garbage that a naive check would accept. ECC SRAM may fault on the first read of never-written words. A debugger `load` without `NOLOAD` zeros it.
- **L7 defense:**
  - A `.noinit (NOLOAD)` section outside `.bss` symbols;
  - a record with magic, ~magic and CRC (§1.6);
  - the reset cause read first thing;
  - re-initialization on power-on or brown-out;
  - non-ECC or scrubbed RAM;
  - on parts with battery-backed SRAM (backup domain), use it, with the backup-domain write protection handled.

  Folder 07 File 04 writes the HardFault record this way.

---

## 5. Invariants Checklist

- [ ] Vector table: word 0 = 8-aligned stack top; every handler odd (Thumb); `KEEP`; VTOR-aligned; `ASSERT`ed.
- [ ] `Reset_Handler`: `CPACR` (+ `dsb`/`isb`) before any FP instruction; `VTOR` set; RAM code copied before first call; `.data` copied; `.bss` zeroed; `dsb`/`isb`; constructors; `main` never returns.
- [ ] Copy and zero loops through `volatile`; startup TU built with `-ffreestanding -fno-builtin -fno-stack-protector -fno-sanitize=all`; CI greps the startup disassembly for early calls and FP instructions.
- [ ] Linker symbols are `extern T sym[]`, sized and compared as `uintptr_t`.
- [ ] A-profile entry selects the primary core, sets SP before any call, enables FP, sets a 2 KB-aligned `VBAR`.
- [ ] RISC-V entry loads `gp` under `.option norelax`, sets `mtvec` (4-byte aligned), uses `-mcmodel=medany` for high images.
- [ ] Flash latency raised before clock frequency; accelerator and I-cache enabled after; flash programming code and its ISRs in RAM.
- [ ] `.noinit` records validated (magic, ~magic, CRC, reset cause); not in ECC RAM that faults on first read.
- [ ] Bootloader jump: validated vectors, IRQs masked and cleared, SysTick off, `VTOR` + barriers, `CONTROL = 0`, MSP + branch in one asm statement, never from Handler mode.
- [ ] Cold-boot qualification with the debugger detached, and emulator runs with poisoned RAM in CI.

## 6. References

1. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E): §B1.5.5 *Reset behavior*, §B3.2.5 *VTOR*, §B3.2.20 *CPACR*; *ARMv8-M Architecture Reference Manual* (DDI 0553): stack limit registers.
2. Arm, *Arm Architecture Reference Manual for A-profile* (DDI 0487): `CPACR_EL1`, `VBAR_EL1` alignment, `MPIDR_EL1`, reset state; Arm Trusted Firmware-A *Firmware Design* (cold boot flow, PSCI).
3. RISC-V International, *The RISC-V Instruction Set Manual, Volume II: Privileged Architecture* (`mtvec`, `mhartid`); *RISC-V ELF psABI* (`__global_pointer$`, linker relaxation); LLD `--relax-gp` documentation.
4. Arm, Application Note 321, *ARM Cortex-M Programming Guide to Memory Barrier Instructions*; *Cortex-M7 Technical Reference Manual* and *Processor Optimization Guide* (cache enable).
5. CMSIS-Core `startup_<device>.c` / `system_<device>.c` templates (ARM-software/CMSIS_6) as a reference implementation of the same sequence.
6. Vendor reference manuals for flash latency tables, accelerators and QSPI memory-mapped mode, e.g. STM32H7 RM0433 and application notes on external-memory MPU configuration (⚠ verify for your part).
