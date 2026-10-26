# 01 · ARM NVIC and GIC: Tail-Chaining, Late Arrival, and Zero-Latency ISRs

> **Folder:** `04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/` · **File 1 of 3**
> **Anchors:**
> - ARMv7-M ARM (DDI 0403) B1.5 *Exception model* (entry, return, `EXC_RETURN`, tail-chaining, late arrival), B3.4 *NVIC*.
> - ARMv6-M ARM (DDI 0419): NVIC priority registers word-only. ARMv8-M ARM (DDI 0553): extended `EXC_RETURN`.
> - Cortex-M0+/M3/M4/M7 TRMs (interrupt latency figures).
> - Arm *GICv3 and GICv4 Architecture Specification* (IHI 0069).
> - Joseph Yiu, *The Definitive Guide to Arm Cortex-M3 and Cortex-M4 Processors* (3rd ed.).
>
> **Verification:**
> - NVIC driver codegen for Cortex-M0+ and Cortex-M7, and the GICv3 dispatcher for AArch64, compiled warning-free; listings inserted verbatim.
> - The AArch64 vector table and entry/exit assembled.
> - Cycle counts are vendor-documented (TRM) figures and marked ⚠ verify per core and memory system. They were not measured here.

---

## 0. The thesis

An interrupt controller is a hardware scheduler. On Cortex-M, the NVIC decides in a few cycles which handler runs, saves the caller-saved state *in hardware*, and chains handlers without returning to the interrupted code. On Cortex-A, the GIC prioritizes and routes interrupts across cores, but the CPU saves nothing except PC and PSTATE. Interrupt latency, nesting, and the safety of every RTOS critical section fall out of these two designs.

---

## 1. First-Principles Hardware Mechanics

### 1.1 The M-profile exception model

| Exception | Number | Priority | Notes |
|---|---|---|---|
| Reset | 1 | −3 (fixed) | |
| NMI | 2 | −2 (fixed) | Can't be masked by PRIMASK/BASEPRI: watchdog early-warning, clock-security failure |
| HardFault | 3 | −1 (fixed) | Escalation target for disabled or failing configurable faults |
| MemManage / BusFault / UsageFault | 4 / 5 / 6 | configurable | Enable in `SHCSR`, or they escalate to HardFault |
| SecureFault | 7 | configurable | ARMv8-M Security Extension |
| SVCall | 11 | configurable | `SVC` instruction: system calls, RTOS start |
| DebugMonitor | 12 | configurable | |
| PendSV | 14 | configurable | **Software-pended, set to lowest priority: the RTOS context switch (File 02)** |
| SysTick | 15 | configurable | |
| IRQ0…IRQn | 16+ | configurable | Up to 480 (v7-M) / 496 external interrupts |

**Priority:** a *lower number* is *more urgent*. Only the implemented MSBs of each 8-bit priority field exist (2 bits on M0/M0+; typically 3–4 on M3/M4/M7 SoCs). `AIRCR.PRIGROUP` splits the field into a **preemption group** (decides nesting) and a **subpriority** (decides order among pending interrupts of the same group, without preemption).

**Entry sequence** (ARMv7-M B1.5.6), in hardware, with no software instructions:

1. **Stack** 8 words onto the current SP (MSP or PSP): `xPSR, PC, LR, R12, R3, R2, R1, R0`, the *basic frame*, at descending addresses.
   - With an active FP context (`CONTROL.FPCA = 1`), the *extended frame* adds `S0`–`S15`, `FPSCR` and a reserved word: 26 words.
   - With **lazy stacking** (`FPCCR.LSPEN = 1`, the default), only *space* is reserved and `FPCAR` points at it. The registers are written only if the handler actually executes an FP instruction.
2. **In parallel** (Harvard bus), fetch the handler address from `VTOR + 4 × exception number`.
3. Load `LR` with **`EXC_RETURN`**, switch to Handler mode on MSP, and set `IPSR` to the exception number.
4. If `CCR.STKALIGN = 1`, realign SP to 8 bytes and record it in stacked xPSR bit 9.

**`EXC_RETURN` values** (`bx lr` or `pop {pc}` with these triggers exception return):

| Value | Return to | Stack | Frame |
|---|---|---|---|
| `0xFFFFFFF1` | Handler mode (nested) | MSP | basic |
| `0xFFFFFFF9` | Thread mode | MSP | basic |
| `0xFFFFFFFD` | Thread mode | PSP | basic |
| `0xFFFFFFE1` / `E9` / `ED` | same as above | | **extended (FP)**: bit 4 = 0 |
| ARMv8-M | bits 6 (`S`), 5 (`DCRS`), 3, 2, 0 (`ES`) add Secure/Non-secure state and callee-register stacking, e.g. `0xFFFFFFBC` | | |

Bit 4 of `EXC_RETURN` (0 = an FP frame was stacked) is what the File 02 context switcher tests (`tst lr, #0x10`) to decide whether to save `S16`–`S31`.

### 1.2 Tail-chaining, late arrival, pop preemption

```text
Back-to-back, no tail-chaining (hypothetical):   [ISR A] unstack 8w | stack 8w [ISR B]
With tail-chaining:                              [ISR A] --6 cyc--> [ISR B]     (no memory traffic)
Late arrival (B higher, arrives during A's stacking):  stack 8w (shared) -> vector fetch switches to B
                                                       -> [ISR B] -> tail-chain -> [ISR A]
Pop preemption (C arrives during unstacking):    unstack abandoned -> [ISR C] (frame still in place)
```

| Mechanism | What the hardware does | Documented cost (⚠ verify per TRM and memory wait states) |
|---|---|---|
| Entry latency | Stacking + vector fetch | **12 cycles** Cortex-M3/M4/M7 (zero-wait memory); 16 Cortex-M0; 15 Cortex-M0+ |
| **Tail-chaining** | A pending interrupt of sufficient priority when a handler returns: skip the unstack/restack pair, go straight to the next vector | **6 cycles** on Cortex-M3/M4, instead of a full exit plus entry (~2 × 12) |
| **Late arrival** | A higher-priority request during *stacking* of a lower one: the same stack frame serves both, and the vector fetch is redirected | Saves a full nested entry |
| **Pop preemption** | A request during *unstacking*: abandon the unstack | Saves a stack plus unstack |
| Lazy FP stacking | Reserve 18 words; write them only if the handler uses FP | Removes ~18 cycles of FP saves from integer-only ISRs |

What this means for design:
- **Short ISRs chain efficiently.** A storm of back-to-back interrupts costs about 6 cycles of overhead each, not 24.
- **The first FP instruction in an ISR triggers the deferred FP stacking.** One `float` in a hot ISR adds tens of cycles to it. Keep ISRs integer-only, or accept the cost knowingly.
- **Worst-case latency isn't the 12-cycle best case.** Add:
  - flash wait states for the vector fetch (or place the vector table in TCM);
  - multi-cycle instructions that must complete (`LDM`/`STM` are interruptible/continuable on M3/M4, but a 64-bit `LDRD` to slow memory isn't free);
  - bus contention with DMA;
  - the longest PRIMASK/BASEPRI critical section in the system;
  - **the longest higher-priority ISR**.

### 1.3 Zero-latency interrupts and the RTOS boundary

An RTOS must protect its kernel data structures from interrupts that call kernel APIs (give a semaphore, post to a queue). There are two strategies:

| Strategy | Mechanism | Effect |
|---|---|---|
| PRIMASK kernel (simple; mandatory on ARMv6-M) | `cpsid i` around kernel critical sections | **Every** interrupt is delayed by the longest kernel critical section |
| **BASEPRI kernel** (FreeRTOS `configMAX_SYSCALL_INTERRUPT_PRIORITY`, Zephyr on v7-M) | `msr basepri_max, #ceiling` around kernel critical sections (Folder 01 File 03 `cpu_basepri_raise`, verified) | Interrupts **more urgent than the ceiling** are never masked by the kernel. Their latency is the hardware latency only: **zero-latency ISRs** |

The contract for a zero-latency ISR: **it must not call any RTOS API**, because the kernel can't mask it, so the kernel's data structures may be mid-update when it runs. It communicates with tasks through lock-free structures (Folder 05 SPSC rings) or by pending a lower-priority, kernel-aware interrupt, which then signals the task. Typical uses: motor PWM commutation, high-rate ADC sampling, safety shutdown. FreeRTOS's port asserts (`configASSERT`) when a too-urgent ISR calls a `FromISR` API, and that assertion should stay enabled in development.

### 1.4 The GICv3 (Cortex-A / Neoverse)

```text
 SPIs (peripherals) ──► Distributor (GICD_*)  ── affinity routing (GICD_IROUTERn) ──┐
 LPIs (MSI writes)  ──► ITS (translates DeviceID/EventID → LPI, per-PE tables) ────┤
                                                                                   ▼
                     Redistributor (GICR_*, one per PE: SGIs, PPIs, LPI config/pending tables)
                                                                                   ▼
                     CPU interface: system registers ICC_*_EL1 (no MMIO on the fast path)
```

| INTID range | Type | Notes |
|---|---|---|
| 0–15 | **SGI** (software-generated, inter-processor) | `ICC_SGI1R_EL1` writes target PEs by affinity |
| 16–31 | **PPI** (private per PE) | Architected timers (e.g. 30 = EL1 physical timer), PMU |
| 32–1019 | **SPI** (shared peripheral) | Routed to one PE or "1 of N" |
| 1020–1023 | Special | **1023 = spurious**: nothing pending for this PE |
| 8192+ | **LPI** | Message-based (MSI/MSI-X via the ITS), configured in memory tables |

Handling an interrupt is a **read-acknowledge, then an end-of-interrupt write**:
- **`ICC_IAR1_EL1`** read: returns the highest-priority pending Group-1 INTID and marks it *active*. Running priority rises.
- **`ICC_EOIR1_EL1`** write: priority drop. With `EOImode = 0` it also deactivates. With `EOImode = 1` (hypervisors, threaded handlers), deactivation is a separate `ICC_DIR_EL1` write, so the priority can be dropped early while the interrupt stays active until a thread finishes.
- **`ICC_PMR_EL1`**: the priority mask, the GIC's BASEPRI.

GICv4/4.1 add **direct injection of virtual LPIs (and SGIs)** into running vCPUs without a hypervisor exit.

AArch64 hardware saves *only* `ELR_EL1` (return PC) and `SPSR_EL1` (PSTATE) on exception entry. The vector code must save every register the C handler may clobber (§2.3).

---

## 2. Production Code Blueprints

### 2.1 The Subtle Buggy Way: ISR and NVIC code from a hundred forum posts

```c
/* irq_bad.c - each line is a real-world defect class (comments say which). */
#include <stdint.h>

#define NVIC_ISER0   (*(volatile uint32_t *)0xE000E100u)
#define NVIC_IPR_B   ((volatile uint8_t *)0xE000E400u)      /* byte view of the priority regs */
#define UART_SR      (*(volatile uint32_t *)0x40011000u)
#define UART_ICR     (*(volatile uint32_t *)0x40011020u)
#define UART_DR      (*(volatile uint32_t *)0x40011008u)

extern void process_byte(uint8_t b);
extern void rtos_queue_send(uint8_t b);                    /* not ISR-safe */

void uart_irq_setup(void);
void uart_irq_setup(void)
{
    NVIC_IPR_B[37] = 1u;      /* BUG 1: byte access: UNPREDICTABLE/faults on ARMv6-M; and 1 is
                               *        NOT priority 1 when only 4 MSBs are implemented (=0) */
    NVIC_ISER0 |= 1u << 5;    /* BUG 2: RMW of a write-1-to-set register (harmless) but uses the
                               *        wrong word/bit for IRQ 37 (ISER1, bit 5); no pending clear */
}

void USART1_IRQHandler(void);
void USART1_IRQHandler(void)
{
    uint8_t b = (uint8_t)UART_DR;
    process_byte(b);           /* BUG 3: long work in the ISR inflates every lower ISR's latency */
    rtos_queue_send(b);        /* BUG 4: non-FromISR API (and illegal if this is zero-latency)  */
    UART_ICR = UART_SR;        /* BUG 5: clear LAST with no DSB/read-back: the buffered write may
                                *        not reach the peripheral before exception return ->
                                *        the still-asserted line re-pends the IRQ (double entry) */
}
```

### 2.2 The Silicon-Hardened Production Way: NVIC driver (verified)

`nvic.h`:

```c
/* nvic.h - NVIC and SCB exception control for ARMv6-M / ARMv7-M / ARMv8-M.
 * Priority registers are byte-accessible on v7-M/v8-M Mainline but WORD-ONLY on
 * ARMv6-M (and v8-M Baseline): one implementation that is correct on both
 * uses word read-modify-write inside a critical section. */
#ifndef NVIC_H
#define NVIC_H

#include <stdint.h>

#ifndef NVIC_PRIO_BITS
#define NVIC_PRIO_BITS 4u              /* implemented priority bits: 2 on M0/M0+, 3-8 on M3+ */
#endif

#define NVIC_ISER(n)   (*(volatile uint32_t *)(0xE000E100u + 4u * (n)))   /* set-enable    */
#define NVIC_ICER(n)   (*(volatile uint32_t *)(0xE000E180u + 4u * (n)))   /* clear-enable  */
#define NVIC_ISPR(n)   (*(volatile uint32_t *)(0xE000E200u + 4u * (n)))   /* set-pending   */
#define NVIC_ICPR(n)   (*(volatile uint32_t *)(0xE000E280u + 4u * (n)))   /* clear-pending */
#define NVIC_IABR(n)   (*(const volatile uint32_t *)(0xE000E300u + 4u * (n))) /* active (v7-M+) */
#define NVIC_IPR(n)    (*(volatile uint32_t *)(0xE000E400u + 4u * (n)))   /* 4 priorities/word */
#define SCB_AIRCR      (*(volatile uint32_t *)0xE000ED0Cu)
#define SCB_SHPR(n)    (*(volatile uint32_t *)(0xE000ED18u + 4u * (n)))   /* SHPR1..3       */
#define AIRCR_VECTKEY  (0x05FAu << 16)

static inline uint32_t nvic_irq_save(void)
{
    uint32_t m;
    __asm__ volatile("mrs %0, primask\n\tcpsid i" : "=r"(m) : : "memory");
    return m;
}
static inline void nvic_irq_restore(uint32_t m)
{
    __asm__ volatile("msr primask, %0" : : "r"(m) : "memory");
}

/* Hardware priority value: implemented bits are the MOST significant bits. */
static inline uint32_t nvic_encode_prio(uint32_t level)
{
    return (level << (8u - NVIC_PRIO_BITS)) & 0xFFu;
}

static inline void nvic_enable(uint32_t irq)
{
    NVIC_ISER(irq >> 5) = 1u << (irq & 31u);            /* write-1-to-set: no RMW needed */
}

static inline void nvic_disable(uint32_t irq)
{
    NVIC_ICER(irq >> 5) = 1u << (irq & 31u);
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory"); /* disable has taken effect     */
}

static inline void nvic_clear_pending(uint32_t irq)
{
    NVIC_ICPR(irq >> 5) = 1u << (irq & 31u);
}

/* Word RMW: legal on every M-profile core (byte access faults/ignored on v6-M). */
static inline void nvic_set_priority(uint32_t irq, uint32_t level)
{
    uint32_t shift = (irq & 3u) * 8u;
    uint32_t key = nvic_irq_save();
    uint32_t w = NVIC_IPR(irq >> 2);
    w = (w & ~(0xFFu << shift)) | (nvic_encode_prio(level) << shift);
    NVIC_IPR(irq >> 2) = w;
    nvic_irq_restore(key);
}

/* PRIGROUP (v7-M/v8-M Mainline): split priority into preempt group / subpriority.
 * AIRCR writes are ignored unless VECTKEY = 0x05FA is written in the same store. */
static inline void nvic_set_priority_grouping(uint32_t prigroup)
{
    uint32_t v = SCB_AIRCR;
    v &= ~((0xFFFFu << 16) | (7u << 8));
    v |= AIRCR_VECTKEY | ((prigroup & 7u) << 8);
    SCB_AIRCR = v;
}

/* PendSV and SysTick lowest priority, so they never preempt a real ISR. */
static inline void scb_set_pendsv_systick_lowest(void)
{
    uint32_t key = nvic_irq_save();
    uint32_t w = SCB_SHPR(2);                          /* SHPR3: [23:16] PendSV, [31:24] SysTick */
    w |= (0xFFu << 16) | (0xFFu << 24);
    SCB_SHPR(2) = w;
    nvic_irq_restore(key);
}

#endif /* NVIC_H */
```

Test translation unit:

```c
#include "nvic.h"
void setup_irq(uint32_t irq, uint32_t level);
void setup_irq(uint32_t irq, uint32_t level) { nvic_set_priority(irq, level); nvic_clear_pending(irq); nvic_enable(irq); }
void init_core(void);
void init_core(void) { nvic_set_priority_grouping(3u); scb_set_pendsv_systick_lowest(); }
```

**Build evidence (verified):** zero diagnostics on Cortex-M0+, Cortex-M7 and Cortex-M33 (full warning set, `-std=c11`).

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7, `NVIC_PRIO_BITS = 4`):**

```asm
setup_irq:
	push	{r4, r5, r6, lr}
	movw	r6, #57600
	bic	r3, r0, #3
	movt	r6, #57344
	movs	r2, #24
	add	r3, r6
	and.w	r2, r2, r0, lsl #3
	mrs	r12, primask
	cpsid i
	mov.w	lr, #255
	lsls	r1, r1, #4
	ldr.w	r5, [r3, #768]
	lsl.w	r4, lr, r2
	uxtb	r1, r1
	lsls	r1, r2
	bic.w	r2, r5, r4
	lsrs	r5, r0, #5
	orrs	r1, r2
	str.w	r1, [r3, #768]
	and	r0, r0, #31
	add.w	r1, r6, r5, lsl #2
	msr	primask, r12
	movs	r2, #1
	lsl.w	r0, r2, r0
	str.w	r0, [r1, #384]
	str.w	r0, [r6, r5, lsl #2]
	pop	{r4, r5, r6, pc}
init_core:
	movw	r0, #60684
	movw	r2, #63743
	movt	r0, #57344
	ldr	r1, [r0]
	ands	r1, r2
	movw	r2, #768
	movt	r2, #1530
	orrs	r1, r2
	str	r1, [r0]
	mrs	r1, primask
	cpsid i
	ldr	r2, [r0, #20]
	movt	r2, #65535
	str	r2, [r0, #20]
	msr	primask, r1
	bx	lr
```

**Codegen (verified — Cortex-M0+, `NVIC_PRIO_BITS = 2`):**

```asm
setup_irq:
	push	{r4, r5, r6, r7, lr}
	movs	r2, #3
	mov	r3, r0
	bics	r3, r2
	mrs	r2, primask
	cpsid i
	ldr	r4, .LCPI0_0
	ldr	r5, [r3, r4]
	lsls	r6, r0, #30
	lsrs	r6, r6, #27
	movs	r7, #255
	lsls	r7, r6
	bics	r5, r7
	lsls	r1, r1, #6
	uxtb	r1, r1
	lsls	r1, r6
	orrs	r1, r5
	str	r1, [r3, r4]
	msr	primask, r2
	movs	r1, #31
	ands	r1, r0
	movs	r2, #1
	lsls	r2, r1
	lsrs	r0, r0, #5
	lsls	r0, r0, #2
	ldr	r1, .LCPI0_1
	str	r2, [r0, r1]
	ldr	r1, .LCPI0_2
	str	r2, [r0, r1]
	pop	{r4, r5, r6, r7, pc}
.LCPI0_0:
	.long	3758154752
.LCPI0_1:
	.long	3758154368
.LCPI0_2:
	.long	3758153984
init_core:
	ldr	r0, .LCPI1_0
	ldr	r1, [r0]
	ldr	r2, .LCPI1_1
	ands	r2, r1
	ldr	r1, .LCPI1_2
	adds	r1, r2, r1
	str	r1, [r0]
	mrs	r1, primask
	cpsid i
	ldr	r2, [r0, #20]
	ldr	r3, .LCPI1_3
	orrs	r3, r2
	str	r3, [r0, #20]
	msr	primask, r1
	bx	lr
.LCPI1_0:
	.long	3758157068
.LCPI1_1:
	.long	63743
.LCPI1_2:
	.long	100270848
.LCPI1_3:
	.long	4294901760
```

Reading the M7 listing:
- **`setup_irq`:**
  - computes the `IPR` word address `0xE000E100 + 768 + (irq & ~3)` (base `57600 = 0xE100`, `+768` → `0xE400`);
  - performs a **word** `ldr`/`bic`/`orr`/`str` read-modify-write inside `mrs primask; cpsid i … msr primask`;
  - shifts the level left by 4 (`lsls r1, r1, #4`) into the implemented MSBs;
  - then writes **`ICPR`** (`+384` → `0xE000E280`) before **`ISER`** (`[r6, r5, lsl #2]` → `0xE000E100`).
  
  Clearing first matters: a pending bit latched before the driver was ready would otherwise fire immediately on enable.
- **`init_core`:**
  - `AIRCR = (AIRCR & ~(VECTKEY | PRIGROUP)) | 0x05FA0000 | (3 << 8)` (`movt r2, #1530` is `0x05FA`). Without the key in the *same* store, the write is ignored.
  - Then `SHPR3 |= 0xFFFF0000` (PendSV and SysTick at lowest priority), again a word access under PRIMASK.

The M0+ listing uses the same word-only access pattern, which is the only legal one on ARMv6-M, with a 6-bit shift for 2 implemented priority bits.

### 2.3 The hardened ISR pattern

```c
/* irq_good.c - minimal ISR: acknowledge at the source, capture, defer, synchronize. */
#include <stdint.h>

#define UART_SR      (*(volatile uint32_t *)0x40011004u)
#define UART_ICR     (*(volatile uint32_t *)0x40011020u)
#define UART_DR      (*(volatile uint32_t *)0x40011008u)
#define UART_SR_ERR  0x0000000Fu

extern int  rx_ring_push_isr(uint8_t b);          /* lock-free SPSC (Folder 05), ISR = producer */
extern void task_notify_from_isr(void);           /* RTOS FromISR API -> pends PendSV if needed */
extern volatile uint32_t g_uart_overruns;

void USART1_IRQHandler(void);
void USART1_IRQHandler(void)
{
    uint32_t sr = UART_SR;                         /* 1. one snapshot of status                */
    if ((sr & UART_SR_ERR) != 0u) {
        UART_ICR = sr & UART_SR_ERR;               /* 2. W1C exactly the error bits seen       */
        g_uart_overruns = g_uart_overruns + 1u;
    }
    uint8_t b = (uint8_t)UART_DR;                  /* 3. data read clears RXNE at the source   */
    if (rx_ring_push_isr(b) != 0) {                /* 4. hand off without locks                */
        task_notify_from_isr();                    /* 5. wake the worker task                  */
    }
    __asm__ volatile("dsb sy" : : : "memory");     /* 6. clears reached the peripheral before
                                                    *    exception return re-samples the line */
}
```

The deferred-work rule: an ISR acknowledges, captures and signals. The task does the parsing, the logging and the protocol work. The ISR's worst-case execution time becomes a few dozen cycles, which is what every lower-priority ISR's latency budget needs.

### 2.4 AArch64: vector table, register save, and GICv3 dispatch (verified)

`vectors_a64.S` (assembled for `aarch64-none-elf`, zero diagnostics; `.vectors` 2 KB-aligned):

```asm
// vectors_a64.S - EL1 exception vector table and IRQ entry/exit. Unlike
// Cortex-M, AArch64 hardware saves only PC->ELR_EL1 and PSTATE->SPSR_EL1:
// software must save every register the C handler may clobber.
    .equ    FRAME_SIZE, 272                 // x0-x30 (31*8) + ELR + SPSR = 264, rounded to 16

    .macro  KERNEL_ENTRY
    sub     sp, sp, #FRAME_SIZE
    stp     x0, x1,   [sp, #16 * 0]
    stp     x2, x3,   [sp, #16 * 1]
    stp     x4, x5,   [sp, #16 * 2]
    stp     x6, x7,   [sp, #16 * 3]
    stp     x8, x9,   [sp, #16 * 4]
    stp     x10, x11, [sp, #16 * 5]
    stp     x12, x13, [sp, #16 * 6]
    stp     x14, x15, [sp, #16 * 7]
    stp     x16, x17, [sp, #16 * 8]
    stp     x18, x19, [sp, #16 * 9]
    stp     x20, x21, [sp, #16 * 10]
    stp     x22, x23, [sp, #16 * 11]
    stp     x24, x25, [sp, #16 * 12]
    stp     x26, x27, [sp, #16 * 13]
    stp     x28, x29, [sp, #16 * 14]
    mrs     x21, elr_el1
    mrs     x22, spsr_el1
    stp     x30, x21, [sp, #16 * 15]        // LR, ELR
    str     x22,      [sp, #16 * 16]        // SPSR
    .endm

    .macro  KERNEL_EXIT
    ldr     x22,      [sp, #16 * 16]
    ldp     x30, x21, [sp, #16 * 15]
    msr     spsr_el1, x22                   // restore BEFORE nested IRQs could clobber them
    msr     elr_el1, x21
    ldp     x0, x1,   [sp, #16 * 0]
    ldp     x2, x3,   [sp, #16 * 1]
    ldp     x4, x5,   [sp, #16 * 2]
    ldp     x6, x7,   [sp, #16 * 3]
    ldp     x8, x9,   [sp, #16 * 4]
    ldp     x10, x11, [sp, #16 * 5]
    ldp     x12, x13, [sp, #16 * 6]
    ldp     x14, x15, [sp, #16 * 7]
    ldp     x16, x17, [sp, #16 * 8]
    ldp     x18, x19, [sp, #16 * 9]
    ldp     x20, x21, [sp, #16 * 10]
    ldp     x22, x23, [sp, #16 * 11]
    ldp     x24, x25, [sp, #16 * 12]
    ldp     x26, x27, [sp, #16 * 13]
    ldp     x28, x29, [sp, #16 * 14]
    add     sp, sp, #FRAME_SIZE
    eret                                    // PC <- ELR_EL1, PSTATE <- SPSR_EL1
    .endm

    .macro  VENTRY label
    .balign 128
    b       \label
    .endm

    .section .vectors, "ax"
    .balign 2048
    .global el1_vectors
el1_vectors:
    VENTRY  unhandled          // Current EL, SP_EL0: Synchronous
    VENTRY  unhandled          //                     IRQ
    VENTRY  unhandled          //                     FIQ
    VENTRY  unhandled          //                     SError
    VENTRY  el1_sync           // Current EL, SP_ELx: Synchronous
    VENTRY  el1_irq            //                     IRQ
    VENTRY  unhandled          //                     FIQ
    VENTRY  unhandled          //                     SError
    VENTRY  unhandled          // Lower EL, AArch64:  Synchronous (syscalls, user faults)
    VENTRY  unhandled          //                     IRQ
    VENTRY  unhandled          //                     FIQ
    VENTRY  unhandled          //                     SError
    VENTRY  unhandled          // Lower EL, AArch32:  x4
    VENTRY  unhandled
    VENTRY  unhandled
    VENTRY  unhandled

    .text
el1_irq:
    KERNEL_ENTRY
    bl      gic_handle_irq                  // C, AAPCS64: may clobber x0-x18, x30
    KERNEL_EXIT

el1_sync:
    KERNEL_ENTRY
    mrs     x0, esr_el1                     // fault syndrome (EC/ISS) for the C decoder
    mrs     x1, far_el1
    mov     x2, sp                          // pointer to the saved frame
    bl      el1_sync_handler
    KERNEL_EXIT

unhandled:
    wfe
    b       unhandled
```

`gicv3.c` (zero diagnostics, `aarch64-none-elf`):

```c
/* gicv3.c - AArch64 EL1 interrupt acknowledge / dispatch / end-of-interrupt
 * through the GICv3 CPU interface system registers (ICC_*_EL1). */
#include <stdint.h>

#define GIC_SPURIOUS   1023u
#define GIC_MAX_INTID  1020u

typedef void (*irq_handler_t)(uint32_t intid);
static irq_handler_t g_handlers[GIC_MAX_INTID];
static uint32_t g_spurious;

static inline uint32_t icc_iar1(void)
{
    uint64_t v;
    __asm__ volatile("mrs %0, icc_iar1_el1" : "=r"(v) : : "memory"); /* ack: highest-priority pending Group-1 */
    return (uint32_t)v;
}
static inline void icc_eoir1(uint32_t intid)
{
    __asm__ volatile("msr icc_eoir1_el1, %0" : : "r"((uint64_t)intid) : "memory"); /* priority drop (+deactivate if EOImode=0) */
}
static inline void icc_pmr(uint32_t prio)
{
    __asm__ volatile("msr icc_pmr_el1, %0\n\tisb" : : "r"((uint64_t)prio) : "memory");
}

void gic_cpu_init(void);
void gic_cpu_init(void)
{
    __asm__ volatile("msr icc_sre_el1, %0\n\tisb" : : "r"((uint64_t)1u) : "memory"); /* system-register interface */
    icc_pmr(0xF0u);                                                                 /* unmask priorities < 0xF0   */
    __asm__ volatile("msr icc_igrpen1_el1, %0\n\tisb" : : "r"((uint64_t)1u) : "memory"); /* enable Group 1   */
}

void gic_register(uint32_t intid, irq_handler_t h);
void gic_register(uint32_t intid, irq_handler_t h)
{
    if (intid < GIC_MAX_INTID) {
        g_handlers[intid] = h;
    }
}

/* Called from the EL1 IRQ vector after the assembly entry saved x0-x18, x29, x30, ELR, SPSR. */
void gic_handle_irq(void);
void gic_handle_irq(void)
{
    for (;;) {
        uint32_t intid = icc_iar1() & 0xFFFFFFu;    /* INTID is 24 bits (LPIs >= 8192) */
        if (intid == GIC_SPURIOUS) {
            g_spurious++;                           /* nothing pending (or taken by another PE) */
            return;
        }
        if ((intid < GIC_MAX_INTID) && (g_handlers[intid] != 0)) {
            g_handlers[intid](intid);
        }
        icc_eoir1(intid);                           /* EOI with the SAME INTID that was acked */
    }
}
```

**Codegen (verified — Clang 21.1.0, `-O2`):**

```asm
gic_cpu_init:
	mov	w8, #1
	msr	ICC_SRE_EL1, x8
	isb
	mov	w9, #240
	msr	ICC_PMR_EL1, x9
	isb
	msr	ICC_IGRPEN1_EL1, x8
	isb
	ret
gic_register:
	cmp	w0, #1019
	b.hi	.LBB1_2
	adrp	x8, g_handlers
	add	x8, x8, :lo12:g_handlers
	str	x1, [x8, w0, uxtw #3]
.LBB1_2:
	ret
gic_handle_irq:
	stp	x29, x30, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	mov	x29, sp
	mrs	x8, ICC_IAR1_EL1
	and	w0, w8, #0xffffff
	cmp	w0, #1023
	b.ne	.LBB2_2
.LBB2_1:
	adrp	x8, g_spurious
	ldp	x20, x19, [sp, #16]
	ldr	w9, [x8, :lo12:g_spurious]
	add	w9, w9, #1
	str	w9, [x8, :lo12:g_spurious]
	ldp	x29, x30, [sp], #32
	ret
.LBB2_2:
	adrp	x19, g_handlers
	add	x19, x19, :lo12:g_handlers
	b	.LBB2_4
.LBB2_3:
	msr	ICC_EOIR1_EL1, x20
	mrs	x8, ICC_IAR1_EL1
	and	w0, w8, #0xffffff
	cmp	w0, #1023
	b.eq	.LBB2_1
.LBB2_4:
	cmp	w0, #1019
	and	x20, x8, #0xffffff
	b.hi	.LBB2_3
	ldr	x8, [x19, x20, lsl #3]
	cbz	x8, .LBB2_3
	blr	x8
	b	.LBB2_3
```

- The dispatch loop: `mrs ICC_IAR1_EL1` (acknowledge) → mask to 24 bits → `cmp #1023` (spurious exits) → bounds check (`cmp w0, #1019`) → `blr` the handler → `msr ICC_EOIR1_EL1` with the **same INTID** → re-read IAR to drain everything pending before the costly exception return. That's the same idea as tail-chaining, done in software.
- The entry macro saves **all 31 GPRs plus `ELR` and `SPSR`**, in a 272-byte frame that is a multiple of 16 (the AAPCS64 SP alignment). The C handler may clobber `x0`–`x18` and `x30`. Saving `x19`–`x28` as well gives the frame a uniform layout for the synchronous-exception decoder, which receives `ESR_EL1`, `FAR_EL1` and the frame pointer.
- `KERNEL_EXIT` restores `SPSR`/`ELR` *before* the GPRs, then `eret`. If the handler re-enabled interrupts (`msr daifclr, #2`) for nesting, it must mask them again before `KERNEL_EXIT`. Otherwise a nested IRQ overwrites `ELR`/`SPSR` between their restore and the `eret`.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| ISR runs twice per event | Source cleared too late or posted (no `DSB`/read-back), or a level-sensitive source still asserted | Logic analyzer on a GPIO toggled at ISR entry, vs the peripheral IRQ line. Add `dsb` before return (§2.3); Folder 06 covers the APB mechanism |
| HardFault on the first NVIC priority write on Cortex-M0+ | Byte access to word-only `IPR` | Disassemble: `strb` to `0xE000E4xx`. Use the word RMW (§2.2) |
| Interrupt never fires | Not enabled in `ISER`; masked by PRIMASK/BASEPRI; wrong vector-table entry; `VTOR` points at another table | `NVIC_ISPR` shows it pending. `ICSR.VECTPENDING` (bits [20:12]) gives the highest pending exception number. Check `BASEPRI` and `PRIMASK` in the register view |
| System locks in an interrupt storm | Source never cleared, or a level interrupt from a disconnected pin | `ICSR.VECTACTIVE` (bits [8:0]) gives the exception currently running. A DWT PC sample histogram shows the same handler |
| Latency spikes | Long critical sections, FP lazy stacking, flash wait states on the vector fetch | DWT `CYCCNT` timestamps in the ISR prologue; ETM/SWO **exception trace** (`DWT_CTRL.EXCTRCENA`) shows entry, exit and return for every exception, with timestamps |
| MSP overflow on deep nesting | Each preemption level adds a frame of 8 or 26 words plus the handler's own stack | Size MSP as Σ(max frame + handler stack) over the preemption levels; paint MSP and check its high-water mark |
| GIC: storms of INTID 1023 | Another PE took it (1-of-N), or the handler forgot EOI and priority isn't dropping | `ICC_RPR_EL1` (running priority) stuck high = a missing EOI. `GICD_ISACTIVER*` shows stuck-active SPIs |

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Walk me through what the Cortex-M hardware does between an IRQ asserting and the first ISR instruction."

- **L5:** "It saves the registers and jumps to the handler."
- **Why L5 fails on real hardware:** Which registers, on which stack, and what about FP? It also misses:
  - 8 words (`R0`–`R3`, `R12`, `LR`, `PC`, xPSR) on the *current* stack, MSP or PSP;
  - the extended 26-word frame with lazy FP stacking;
  - the vector fetch in parallel;
  - `LR` = `EXC_RETURN`;
  - the 8-byte realignment recorded in xPSR bit 9;
  - tail-chaining (6 cycles), late arrival, and pop preemption.
  
  And worst-case latency includes critical sections and higher-priority ISRs, not just the 12-cycle best case.
- **L7 principal defense:** Recite the sequence (§1.1) and the `EXC_RETURN` table. Explain why an ISR can be a plain AAPCS function (the stacked set equals the caller-saved set). Describe the latency budget composition and how to measure it (DWT `CYCCNT`, SWO exception trace). Then the design levers: vector table and hot ISRs in TCM, integer-only ISRs, short PRIMASK/BASEPRI sections.

### Q2 🔥 "What is a zero-latency interrupt, and what can't it do?"

- **L5:** "An interrupt with priority 0."
- **Why L5 fails:** "Zero latency" means *the RTOS never masks it*. That's only possible with a BASEPRI-based kernel on v7-M/v8-M Mainline (verified `basepri_max` sequence; v6-M has no BASEPRI). The price is that it **must not call RTOS APIs**, because the kernel's lists may be mid-update when it preempts a kernel critical section.
- **L7 defense:** Configure the syscall ceiling (`configMAX_SYSCALL_INTERRUPT_PRIORITY`) and assign urgent ISRs above it. They communicate via lock-free SPSC rings or by pending a lower-priority kernel-aware IRQ. Keep the `configASSERT` checks on, and document which ISRs are zero-latency in the interrupt map.

### Q3 ⚡ "Your UART ISR occasionally runs twice for one byte. Why?"

- **L5:** "Hardware glitch; debounce it."
- **Why L5 fails:** The usual cause is the clear write still sitting in a **write buffer or APB bridge** when the core performs exception return and re-samples the still-asserted IRQ line. The line then re-pends. It's more likely when the clear is the last instruction of the handler (§2.1 bug 5).
- **L7 defense:** Clear the source early. Finish with `DSB` or a read-back of the peripheral (verified pattern in §2.3; Folder 06 explains the bus). Distinguish level- from pulse-triggered sources. Verify with a GPIO toggle at ISR entry on a logic analyzer.

### Q4 "Design interrupt priorities for a motor controller with CAN, USB, and an RTOS."

- **L5:** "Give the motor the highest priority."
- **Why L5 fails:** Without a ceiling and grouping plan, the "highest" motor ISR still gets masked by kernel critical sections (with a PRIMASK kernel), and CAN and USB fight within one group.
- **L7 defense:**
  - **PRIGROUP** so that preemption levels are coarse and subpriorities order peers.
  - Levels 0–1: motor PWM/ADC, zero-latency above the syscall ceiling, no RTOS calls, data out via SPSC rings.
  - Level 2: the fault and overcurrent comparator (or NMI).
  - Levels 3–5: CAN and USB, kernel-aware, deferring to tasks.
  - Lowest: SysTick and PendSV.
  - Budget each level's WCET, and verify worst-case latency with exception trace.

### Q5 🧊 "On a GICv3 system, why does the IRQ handler loop on `ICC_IAR1_EL1` until it reads 1023?"

- **L5:** "To handle all interrupts."
- **Why L5 fails:** It misses *why that's cheaper*. Each exception entry and `eret` costs a full register save and restore (verified: 272-byte frame). Draining every pending INTID in one entry amortizes it, which is a software tail-chain. 1023 means spurious: nothing more for this PE, possibly because another PE claimed a 1-of-N SPI.
- **L7 defense:** Explain IAR (acknowledge, activate, raise running priority) and EOIR (priority drop, plus deactivation in EOImode 0). Explain the EOImode-1 split (`ICC_DIR_EL1`) for threaded IRQs and hypervisors, the PMR as the GIC's BASEPRI, and LPIs via the ITS for MSI-X. Debug stuck priorities with `ICC_RPR_EL1`.

---

## 5. Invariants Checklist

- [ ] Priority values written through an `encode(level)` helper (MSB-aligned); `IPR`/`SHPR` accessed by word (portable to v6-M) under a critical section.
- [ ] Pending cleared before enabling; disable followed by `DSB`+`ISB` where the code relies on it.
- [ ] `AIRCR` written with `VECTKEY = 0x05FA` in the same store; PRIGROUP chosen once at boot.
- [ ] PendSV and SysTick at the lowest priority; preemption levels documented with WCET per level.
- [ ] Zero-latency ISRs above the syscall ceiling never call RTOS APIs; kernel-aware ISRs use `FromISR` APIs only.
- [ ] ISRs: snapshot status, clear exactly what was seen (W1C), defer work, `DSB` before return.
- [ ] Vector table and hottest ISRs in zero-wait memory (TCM) when latency matters; ISRs integer-only unless FP cost is accepted.
- [ ] MSP sized for worst-case nesting; painted and monitored.
- [ ] AArch64: full register frame, 16-byte aligned; IAR/EOIR pairing; drain until 1023.

## 6. References

1. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E) B1.5 and B3.4; *ARMv6-M ARM* (DDI 0419) B3.4; *ARMv8-M ARM* (DDI 0553) exception model.
2. Arm, *Cortex-M0+ / M3 / M4 / M7 Technical Reference Manuals*: interrupt latency and tail-chaining figures (⚠ verify per revision and memory system).
3. Arm, *GICv3 and GICv4 Architecture Specification* (IHI 0069); *Learn the architecture: Generic Interrupt Controller v3 and v4*.
4. J. Yiu, *The Definitive Guide to Arm Cortex-M3 and Cortex-M4 Processors*, 3rd ed., ch. 7–8.
5. FreeRTOS, *Running the RTOS on an ARM Cortex-M Core* (`configMAX_SYSCALL_INTERRUPT_PRIORITY`, BASEPRI); Zephyr `arch/arm/core` interrupt handling.
6. Linux `drivers/irqchip/irq-gic-v3.c` and `arch/arm64/kernel/entry.S` as production references.
