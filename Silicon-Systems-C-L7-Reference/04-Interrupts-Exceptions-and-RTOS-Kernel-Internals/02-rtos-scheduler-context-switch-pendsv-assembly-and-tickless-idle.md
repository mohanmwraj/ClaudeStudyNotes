# 02 · RTOS Scheduler, the PendSV Context Switch in Assembly, and Tickless Idle

> **Folder:** `04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/` · **File 2 of 3**
> **Anchors:**
> - ARMv7-M ARM B1.4 (PSP/MSP, `CONTROL`), B1.5.6–B1.5.8 (exception entry/return), B5.2 (`MRS`/`MSR`).
> - FreeRTOS `portable/GCC/ARM_CM4F/port.c` and `ARM_CM7/r0p1`; Zephyr `arch/arm/core/cortex_m/swap_helper.S`.
> - Arm AN298 *Cortex-M4(F) Lazy Stacking and Context Switching*.
> - J. Labrosse, *µC/OS-III* (bitmap scheduling); Liu & Layland (1973), rate-monotonic scheduling.
>
> **Verification:**
> - The Thumb-2 `PendSV_Handler`/`SVC_Handler` was assembled and linked with a two-task mini-RTOS, then **executed in Unicorn** (Cortex-M7 model). A Python harness emulates exactly the hardware's part: exception-entry stacking, `EXC_RETURN` and unstacking, per ARMv7-M B1.5. The firmware ran unmodified.
> - The O(1) scheduler and the tickless-idle routine compiled warning-free; the host self-tests ran natively.

---

## 0. The thesis

A Cortex-M RTOS context switch is **half hardware, half software**. The NVIC already pushed the caller-saved registers onto the task's own stack. PendSV, at the lowest priority, saves the callee-saved half, swaps one register (`PSP`), and lets the hardware restore the rest on exception return. Get one detail wrong and you have a scheduler that runs every test and corrupts a register in the field once a week:

- the `EXC_RETURN` FP bit;
- the `ISB` after `MSR PSP`;
- the order of the saved registers;
- PendSV's priority.

---

## 1. First-Principles Mechanics

### 1.1 Why PendSV, why lowest priority, why PSP

- **Tasks run on PSP; handlers run on MSP.** Each task stack needs room only for the task itself plus *one* exception frame (the hardware pushes onto PSP once at entry, then switches to MSP). Interrupt nesting depth is paid once, on MSP, not on every task stack.
- **The switch is *pended*, not performed immediately.** A tick ISR or a "give semaphore from ISR" call sets `ICSR.PENDSVSET`. Because PendSV has the **lowest priority**, it runs only when no other exception is active. It then tail-chains after the last ISR (6 cycles, File 01) and never preempts an ISR halfway through.
- **SVC starts the first task.** It enters Handler mode so that an exception return can load PSP and drop into Thread mode cleanly.

### 1.2 The frames on a task's stack

```text
   high addresses (task stack top)
   ┌───────────────┐
   │ xPSR          │  ┐
   │ PC            │  │ pushed by HARDWARE on exception entry (basic frame, 8 words)
   │ LR            │  │ (+ S0-S15, FPSCR, reserved = 18 more words if FP context active)
   │ R12           │  │
   │ R3 R2 R1 R0   │  ┘
   ├───────────────┤
   │ (S16-S31)     │  ┐ pushed by PendSV software only if EXC_RETURN[4] == 0
   │ LR=EXC_RETURN │  │ pushed by PendSV software: tells the restore path which frame type
   │ R11 … R4      │  ┘ pushed by PendSV software (callee-saved)
   └───────────────┘ ◄── TCB->sp
   low addresses
```

### 1.3 The context switch, line by line (verified)

`ctxsw.S`:

```asm
// ctxsw.S - Cortex-M4F/M7 context switch (FreeRTOS-style), PSP-based tasks.
// On entry to PendSV the hardware has already pushed {r0-r3, r12, lr, pc, xPSR}
// (and s0-s15/FPSCR lazily, if the task used the FPU) onto the TASK's PSP stack.
// Software saves the rest: r4-r11, EXC_RETURN, and s16-s31 for FP tasks.
    .syntax unified
    .thumb
    .equ    MAX_SYSCALL_PRIO, 0x50          // BASEPRI value: level 5 with 4 prio bits

    .text
    .global PendSV_Handler
    .type   PendSV_Handler, %function
    .thumb_func
PendSV_Handler:
    mrs     r0, psp                         // r0 = current task's stack (hardware frame on top)
    isb
    ldr     r3, =g_current_tcb
    ldr     r2, [r3]                        // r2 = &current TCB
    tst     lr, #0x10                       // EXC_RETURN[4] == 0 -> extended frame (task used FP)
    it      eq
    vstmdbeq r0!, {s16-s31}                 // callee-saved FP regs (forces lazy stacking to finish)
    stmdb   r0!, {r4-r11, lr}               // callee-saved core regs + this task's EXC_RETURN
    str     r0, [r2]                        // TCB->sp

    mov     r0, #MAX_SYSCALL_PRIO           // mask kernel-aware IRQs; zero-latency IRQs stay live
    msr     basepri, r0
    dsb
    isb
    bl      scheduler_switch                // C: picks the next task, updates g_current_tcb
    mov     r0, #0
    msr     basepri, r0

    ldr     r3, =g_current_tcb
    ldr     r1, [r3]
    ldr     r0, [r1]                        // r0 = next task's saved sp
    ldmia   r0!, {r4-r11, lr}               // restore core regs + its EXC_RETURN
    tst     lr, #0x10
    it      eq
    vldmiaeq r0!, {s16-s31}
    msr     psp, r0                         // hardware unstacks the rest from here
    isb
    bx      lr                              // EXC_RETURN -> Thread mode, PSP
    .size   PendSV_Handler, .-PendSV_Handler
    .ltorg

    // SVC 0 from main(): start the first task (never returns to main).
    .global SVC_Handler
    .type   SVC_Handler, %function
    .thumb_func
SVC_Handler:
    ldr     r3, =g_current_tcb
    ldr     r1, [r3]
    ldr     r0, [r1]
    ldmia   r0!, {r4-r11, lr}               // initial software frame (lr = 0xFFFFFFFD)
    msr     psp, r0
    isb
    mov     r0, #0
    msr     basepri, r0
    bx      lr
    .size   SVC_Handler, .-SVC_Handler
    .ltorg
```

**As linked (verified, capstone disassembly of the firmware):**

```asm
PendSV_Handler:
  08000424:  mrs      r0, psp
  08000428:  isb      sy
  0800042c:  ldr      r3, [pc, #0x4c]
  0800042e:  ldr      r2, [r3]
  08000430:  tst.w    lr, #0x10
  08000434:  it       eq
  08000436:  vstmdbeq r0!, {s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30, s31}
  0800043a:  stmdb    r0!, {r4, r5, r6, r7, r8, sb, sl, fp, lr}
  0800043e:  str      r0, [r2]
  08000440:  mov.w    r0, #0x50
  08000444:  msr      basepri, r0
  08000448:  dsb      sy
  0800044c:  isb      sy
  08000450:  bl       #0x8000250
  08000454:  mov.w    r0, #0
  08000458:  msr      basepri, r0
  0800045c:  ldr      r3, [pc, #0x1c]
  0800045e:  ldr      r1, [r3]
  08000460:  ldr      r0, [r1]
  08000462:  ldm.w    r0!, {r4, r5, r6, r7, r8, sb, sl, fp, lr}
  08000466:  tst.w    lr, #0x10
  0800046a:  it       eq
  0800046c:  vldmiaeq r0!, {s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30, s31}
  08000470:  msr      psp, r0
  08000474:  isb      sy
  08000478:  bx       lr
SVC_Handler:
  08000480:  ldr      r3, [pc, #0x18]
  08000482:  ldr      r1, [r3]
  08000484:  ldr      r0, [r1]
  08000486:  ldm.w    r0!, {r4, r5, r6, r7, r8, sb, sl, fp, lr}
  0800048a:  msr      psp, r0
  0800048e:  isb      sy
  08000492:  mov.w    r0, #0
  08000496:  msr      basepri, r0
  0800049a:  bx       lr
```

| Instruction(s) | Why it is there |
|---|---|
| `mrs r0, psp` / `isb` | The task's stack pointer. The hardware frame is already on it |
| `tst lr, #0x10` / `vstmdbeq r0!, {s16-s31}` | `EXC_RETURN[4] = 0` means the task had an active FP context. Hardware stacked (or reserved, lazily) `S0`–`S15`. Software must save the callee-saved `S16`–`S31`. **The `VSTM` also triggers completion of a pending lazy FP stack**, so the reserved hardware FP area is filled before the task's stack is abandoned (AN298) |
| `stmdb r0!, {r4-r11, lr}` | Callee-saved core registers **and `EXC_RETURN`**, which is per task: an FP task and an integer task return with different values |
| `str r0, [r2]` | `TCB->sp`. The TCB layout puts `sp` at offset 0 (the C struct comment enforces it) |
| `msr basepri, #0x50` + `dsb`/`isb` | Mask kernel-aware interrupts while the scheduler touches the ready lists. Zero-latency interrupts above the ceiling stay live (File 01) |
| `bl scheduler_switch` | C code. It may clobber `r0`–`r3`, `r12`, `lr`, which is why `lr` was saved *first* and `r3` is reloaded afterwards |
| `ldmia r0!, {r4-r11, lr}` / `vldmiaeq` / `msr psp, r0` / `isb` / `bx lr` | Mirror image for the next task. **`bx lr` with `EXC_RETURN`** makes the hardware pop the rest of the frame from the *new* PSP |
| `SVC_Handler` | Pops the fabricated initial software frame of the first task and returns into it with `EXC_RETURN = 0xFFFFFFFD` |

On Cortex-M, an interrupted `LDREX`/`STREX` sequence in the old task fails and retries after the switch. Exception entry and return clear the local exclusive monitor on Cortex-M3/M4/M7 (⚠ verify for your core), so a stale reservation from the old task can't let the new task's `STREX` succeed falsely. A-profile kernels must take care of this explicitly (Folder 05).

### 1.4 The mini-RTOS it was tested with

`rtos_mini.c` (zero diagnostics, Cortex-M7, full warning set):

```c
/* rtos_mini.c - two PSP tasks, a round-robin scheduler and an initial stack
 * frame builder: the minimum around ctxsw.S that exercises a real switch. */
#include <stdint.h>

#define SCB_ICSR        (*(volatile uint32_t *)0xE000ED04u)
#define ICSR_PENDSVSET  (1u << 28)
#define STACK_WORDS     256u
#define EXC_RETURN_THREAD_PSP 0xFFFFFFFDu       /* Thread mode, PSP, basic (no FP) frame */

typedef struct tcb {
    uint32_t   *sp;                              /* MUST be first: ctxsw.S reads [tcb, #0] */
    struct tcb *next;
    uint32_t    id;
} tcb_t;

tcb_t *volatile g_current_tcb;
static tcb_t g_tcb[2];
static uint32_t g_stack[2][STACK_WORDS] __attribute__((aligned(8)));

volatile uint32_t g_trace_a[8], g_trace_b[8];
volatile uint32_t g_na, g_nb, g_switches;

void scheduler_switch(void);
void scheduler_switch(void)                      /* runs inside PendSV with BASEPRI raised */
{
    g_current_tcb = g_current_tcb->next;
    g_switches++;
}

static inline void yield(void)
{
    SCB_ICSR = ICSR_PENDSVSET;                   /* pend PendSV (lowest priority)          */
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory"); /* taken right here           */
}

static void task_exit_trap(void) { for (;;) { } }

/* Each task keeps a running value in a callee-saved register across yields:
 * if r4-r11 are not saved/restored exactly, the recurrence breaks. */
static void task_a(void *arg)
{
    uint32_t x = (uint32_t)(uintptr_t)arg;
    for (;;) {
        x = x * 3u + 1u;
        if (g_na < 8u) { g_trace_a[g_na] = x; g_na = g_na + 1u; }
        yield();
    }
}

static void task_b(void *arg)
{
    uint32_t y = (uint32_t)(uintptr_t)arg;
    for (;;) {
        y = (y << 1) ^ 0x9E3779B9u;
        if (g_nb < 8u) { g_trace_b[g_nb] = y; g_nb = g_nb + 1u; }
        yield();
    }
}

/* Fabricate the frames an exception return will pop: hardware part (8 words)
 * below the software part (r4-r11 + EXC_RETURN, 9 words). */
static void task_init(tcb_t *t, uint32_t *stack_top, void (*entry)(void *), void *arg)
{
    uint32_t *sp = stack_top;
    *--sp = 0x01000000u;                         /* xPSR: Thumb bit set (EPSR.T)            */
    *--sp = (uint32_t)(uintptr_t)entry;          /* PC  (bit 0 ignored in the frame)        */
    *--sp = (uint32_t)(uintptr_t)task_exit_trap; /* LR: where a returning task goes         */
    *--sp = 0x12121212u;                         /* R12 */
    *--sp = 0x03030303u;                         /* R3  */
    *--sp = 0x02020202u;                         /* R2  */
    *--sp = 0x01010101u;                         /* R1  */
    *--sp = (uint32_t)(uintptr_t)arg;            /* R0: task argument                       */
    *--sp = EXC_RETURN_THREAD_PSP;               /* LR saved by ctxsw (EXC_RETURN)          */
    for (uint32_t r = 11u; r >= 4u; r--) {       /* R11..R4 with recognizable values        */
        *--sp = r * 0x01010101u;
    }
    t->sp = sp;
}

int main(void)
{
    task_init(&g_tcb[0], &g_stack[0][STACK_WORDS], task_a, (void *)(uintptr_t)7u);
    task_init(&g_tcb[1], &g_stack[1][STACK_WORDS], task_b, (void *)(uintptr_t)1u);
    g_tcb[0].next = &g_tcb[1]; g_tcb[0].id = 0u;
    g_tcb[1].next = &g_tcb[0]; g_tcb[1].id = 1u;
    g_current_tcb = &g_tcb[0];
    __asm__ volatile("svc 0" : : : "memory");    /* SVC_Handler launches task_a            */
    for (;;) { }
}
```

**Initial frame construction (`task_init`):**
- `xPSR = 0x01000000`. **EPSR.T must be 1**, or the first exception return raises `INVSTATE`.
- `PC = entry` and `LR = task_exit_trap`, so a task that returns lands in a trap rather than garbage.
- `R0 = arg`.
- Then the 9-word software frame, whose `EXC_RETURN = 0xFFFFFFFD` says "Thread mode, PSP, no FP".

The two tasks keep a running value in a **callee-saved register** across `yield()`. If any of `r4`–`r11` weren't preserved exactly, the recurrence would break.

### 1.5 Execution evidence (verified)

The harness emulates exactly what the NVIC does on SVC/PendSV entry and `EXC_RETURN`. The firmware's own PendSV assembly, scheduler and tasks run unmodified:

```python
"""emu_rtos.py - run a Cortex-M ELF in Unicorn with a minimal software NVIC:
SVC and PendSV exception ENTRY (hardware stacking of r0-r3,r12,lr,pc,xPSR onto
the active stack, LR = EXC_RETURN, SPSEL=0) and EXC_RETURN UNSTACKING are done
here exactly as ARMv7-M B1.5.6/B1.5.8 describe; everything else is the
firmware's own code. usage: emu_rtos.py fw.elf max_pendsv"""
import sys
from elftools.elf.elffile import ELFFile
from unicorn import (Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS,
                     UC_HOOK_INTR, UC_HOOK_MEM_WRITE, UC_HOOK_CODE)
from unicorn.arm_const import *

elf = ELFFile(open(sys.argv[1], "rb"))
max_pendsv = int(sys.argv[2])
sym = {s.name: s["st_value"] for s in elf.get_section_by_name(".symtab").iter_symbols()}
uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
uc.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_M7)
for base, size in ((0x08000000, 0x80000), (0x00000000, 0x4000), (0x20000000, 0x20000), (0xE000E000, 0x1000)):
    uc.mem_map(base, size)
    if base != 0x08000000:
        uc.mem_write(base, b"\xA5" * size)
for seg in elf.iter_segments():
    if seg["p_type"] == "PT_LOAD" and seg["p_filesz"] and 0x08000000 <= seg["p_paddr"] < 0x08080000:
        uc.mem_write(seg["p_paddr"], seg.data())

R = lambda r: uc.reg_read(r)
def rd(a): return int.from_bytes(uc.mem_read(a, 4), "little")
def wr(a, v): uc.mem_write(a, (v & 0xFFFFFFFF).to_bytes(4, "little"))

pending = {"svc": False, "pendsv": False, "ret": 0}
last = {"addr": 0, "size": 0}
def on_code(uc_, addr, size, data):                # track instruction boundaries
    last["addr"], last["size"] = addr, size
def on_intr(uc_, intno, data):
    if intno == 2:                       # EXCP_SWI: SVC instruction
        pending["svc"] = True
        pending["ret"] = last["addr"] + last["size"]
        uc_.emu_stop()
def on_write(uc_, access, addr, size, value, data):
    if addr == 0xE000ED04 and (value >> 28) & 1:   # ICSR.PENDSVSET
        pending["pendsv"] = True
        pending["ret"] = last["addr"] + last["size"]   # exception taken AFTER the store
        uc_.emu_stop()
uc.hook_add(UC_HOOK_CODE, on_code)
uc.hook_add(UC_HOOK_INTR, on_intr)
uc.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=0xE000ED04, end=0xE000ED07)

def exception_entry(handler, ret_pc):
    ctrl = R(UC_ARM_REG_CONTROL)
    on_psp = (ctrl >> 1) & 1
    sp = R(UC_ARM_REG_PSP) if on_psp else R(UC_ARM_REG_MSP)
    frame = [R(UC_ARM_REG_R0), R(UC_ARM_REG_R1), R(UC_ARM_REG_R2), R(UC_ARM_REG_R3),
             R(UC_ARM_REG_R12), R(UC_ARM_REG_LR), ret_pc & ~1, 0x01000000]
    sp = (sp - 32) & ~7                  # 8-byte aligned frame (CCR.STKALIGN)
    for i, v in enumerate(frame):
        wr(sp + 4 * i, v)
    if on_psp:
        uc.reg_write(UC_ARM_REG_PSP, sp)
        exc_return = 0xFFFFFFFD           # back to Thread mode, PSP, basic frame
    else:
        uc.reg_write(UC_ARM_REG_MSP, sp)
        exc_return = 0xFFFFFFF9           # back to Thread mode, MSP
    uc.reg_write(UC_ARM_REG_CONTROL, ctrl & ~2)   # handler always runs on MSP
    uc.reg_write(UC_ARM_REG_LR, exc_return)
    return sym[handler] | 1

def exception_return(exc_return):
    use_psp = (exc_return & 0xF) == 0xD
    sp = R(UC_ARM_REG_PSP) if use_psp else R(UC_ARM_REG_MSP)
    v = [rd(sp + 4 * i) for i in range(8)]
    for reg, val in zip((UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3,
                         UC_ARM_REG_R12, UC_ARM_REG_LR), v[:6]):
        uc.reg_write(reg, val)
    if use_psp:
        uc.reg_write(UC_ARM_REG_PSP, sp + 32)
        uc.reg_write(UC_ARM_REG_CONTROL, R(UC_ARM_REG_CONTROL) | 2)
    else:
        uc.reg_write(UC_ARM_REG_MSP, sp + 32)
    return v[6] | 1

vec = elf.get_section_by_name(".isr_vector")["sh_addr"]
uc.reg_write(UC_ARM_REG_MSP, rd(vec))
pc = rd(vec + 4)
n_pendsv = 0
log = []
idle = 0
while n_pendsv < max_pendsv:
    try:
        uc.emu_start(pc | 1, 0xFFFFFFFF, timeout=2_000_000, count=200_000)
        pc = R(UC_ARM_REG_PC)
    except UcError as e:
        pc = R(UC_ARM_REG_PC)
        if pc & 0xFFFFFF00 != 0xFFFFFF00:
            print(f"UcError {e} at PC=0x{pc:08X}", flush=True)
            raise
    if pc & 0xFFFFFF00 == 0xFFFFFF00:            # bx lr with LR = EXC_RETURN magic
        pc = exception_return(R(UC_ARM_REG_LR))
        continue
    if not (pending["svc"] or pending["pendsv"]):
        idle += 1
        if idle > 3:
            print(f"no exception event; stuck at PC=0x{pc:08X} LR=0x{R(UC_ARM_REG_LR):08X}", flush=True)
            break
        continue
    idle = 0
    if pending["svc"]:
        pending["svc"] = False
        log.append("SVC   -> SVC_Handler (start first task)")
        pc = exception_entry("SVC_Handler", pending["ret"])
    elif pending["pendsv"]:
        pending["pendsv"] = False
        n_pendsv += 1
        cur = rd(sym["g_current_tcb"])
        log.append(f"PendSV #{n_pendsv}: from task {rd(cur + 8)} (PSP=0x{R(UC_ARM_REG_PSP):08X})")
        pc = exception_entry("PendSV_Handler", pending["ret"])
for line in log:
    print(line)
na, nb = rd(sym["g_na"]), rd(sym["g_nb"])
ta = [rd(sym["g_trace_a"] + 4 * i) for i in range(na)]
tb = [rd(sym["g_trace_b"] + 4 * i) for i in range(nb)]
print(f"switches={rd(sym['g_switches'])} task_a ran {na}x, task_b ran {nb}x")
print("task_a trace:", " ".join(f"0x{v:X}" for v in ta))
print("task_b trace:", " ".join(f"0x{v:X}" for v in tb))
# independent check of the recurrences (callee-saved state survived every switch)
ea, x = [], 7
for _ in range(na):
    x = (x * 3 + 1) & 0xFFFFFFFF; ea.append(x)
eb, y = [], 1
for _ in range(nb):
    y = ((y << 1) ^ 0x9E3779B9) & 0xFFFFFFFF; eb.append(y)
print("task_a recurrence intact:", ta == ea, "| task_b recurrence intact:", tb == eb)
```

**Output (verified, Unicorn 2.1.4, Cortex-M7 model):**

```text
SVC   -> SVC_Handler (start first task)
PendSV #1: from task 0 (PSP=0x20000420)
PendSV #2: from task 1 (PSP=0x20000820)
PendSV #3: from task 0 (PSP=0x20000420)
PendSV #4: from task 1 (PSP=0x20000820)
PendSV #5: from task 0 (PSP=0x20000420)
PendSV #6: from task 1 (PSP=0x20000820)
PendSV #7: from task 0 (PSP=0x20000420)
PendSV #8: from task 1 (PSP=0x20000820)
PendSV #9: from task 0 (PSP=0x20000420)
PendSV #10: from task 1 (PSP=0x20000820)
PendSV #11: from task 0 (PSP=0x20000420)
PendSV #12: from task 1 (PSP=0x20000820)
PendSV #13: from task 0 (PSP=0x20000420)
PendSV #14: from task 1 (PSP=0x20000820)
PendSV #15: from task 0 (PSP=0x20000420)
PendSV #16: from task 1 (PSP=0x20000820)
switches=15 task_a ran 8x, task_b ran 8x
task_a trace: 0x16 0x43 0xCA 0x25F 0x71E 0x155B 0x4012 0xC037
task_b trace: 0x9E3779BB 0xA2598ACF 0xDA846C27 0x2B3FA1F7 0xC8483A57 0xEA70D17 0x83796397 0x98C5BE97
task_a recurrence intact: True | task_b recurrence intact: True
```

- PendSV alternates between task 0 (PSP `0x20000420`) and task 1 (PSP `0x20000820`). Each PSP is its own stack after the hardware frame was pushed. The two tasks never share a stack.
- Each task ran 8 times, and **both recurrences match an independent Python recomputation**. Callee-saved state survived 15 switches exactly.
- A development bug the harness caught: the first version resumed each task *at* the `ICSR` store instead of after it, because the emulator stopped mid-instruction. The task then re-pended PendSV forever without making progress (each "ran 1×"). Real hardware takes the exception after the store retires. The harness now records instruction boundaries. The firmware was correct throughout, which is exactly why you test a scheduler against a model of the *hardware*.

### 1.6 The O(1) scheduler core (verified)

```c
/* sched.c - O(1) priority scheduler core (ready bitmap + per-priority FIFO,
 * highest priority via count-leading-zeros) and tickless-idle arithmetic. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define NPRIO 32u                         /* priority 31 = highest (FreeRTOS convention) */

typedef struct task {
    struct task *next;                    /* intrusive ready-list link */
    uint8_t      prio;
    const char  *name;
} task_t;

typedef struct {
    uint32_t bits;                        /* bit p set <=> ready list p non-empty */
    task_t  *head[NPRIO];
    task_t  *tail[NPRIO];
} ready_q_t;

void sched_ready(ready_q_t *q, task_t *t);
task_t *sched_pick(ready_q_t *q);
uint32_t tickless_max_ticks(uint32_t core_hz, uint32_t tick_hz);

void sched_ready(ready_q_t *q, task_t *t)          /* O(1): append to its FIFO */
{
    t->next = NULL;
    if (q->tail[t->prio] != NULL) {
        q->tail[t->prio]->next = t;
    } else {
        q->head[t->prio] = t;
    }
    q->tail[t->prio] = t;
    q->bits |= 1u << t->prio;
}

task_t *sched_pick(ready_q_t *q)                   /* O(1): CLZ + dequeue head */
{
    if (q->bits == 0u) {
        return NULL;                               /* idle */
    }
    uint32_t p = 31u - (uint32_t)__builtin_clz(q->bits);
    task_t *t = q->head[p];
    q->head[p] = t->next;
    if (q->head[p] == NULL) {
        q->tail[p] = NULL;
        q->bits &= ~(1u << p);
    }
    return t;
}

/* SysTick is a 24-bit down-counter at the core clock: the longest single
 * tickless sleep is floor(0xFFFFFF / cycles_per_tick) ticks. */
uint32_t tickless_max_ticks(uint32_t core_hz, uint32_t tick_hz)
{
    uint32_t cycles_per_tick = core_hz / tick_hz;
    return 0x00FFFFFFu / cycles_per_tick;
}

#ifdef SCHED_SELFTEST
#include <stdio.h>

int main(void)
{
    static ready_q_t q;
    task_t t[6] = {
        { NULL, 3u, "logger" }, { NULL, 7u, "net-A" }, { NULL, 7u, "net-B" },
        { NULL, 31u, "motor" }, { NULL, 0u, "idle" }, { NULL, 7u, "net-C" },
    };
    for (unsigned i = 0u; i < 6u; i++) { sched_ready(&q, &t[i]); }
    printf("ready bits = 0x%08X\npick order:", (unsigned)q.bits);
    for (task_t *x = sched_pick(&q); x != NULL; x = sched_pick(&q)) {
        printf(" %s(%u)", x->name, (unsigned)x->prio);
    }
    printf("\n");
    const uint32_t cfg[][2] = { { 480000000u, 1000u }, { 168000000u, 1000u },
                                { 64000000u, 1000u }, { 16000000u, 100u } };
    for (unsigned i = 0u; i < 4u; i++) {
        printf("SysTick tickless cap @ %3u MHz, %4u Hz tick: %5u ticks (%u ms)\n",
               (unsigned)(cfg[i][0] / 1000000u), (unsigned)cfg[i][1],
               (unsigned)tickless_max_ticks(cfg[i][0], cfg[i][1]),
               (unsigned)(tickless_max_ticks(cfg[i][0], cfg[i][1]) * 1000u / cfg[i][1]));
    }
    printf("LPTIM 16-bit @ 32768 Hz, 1000 Hz tick: %u ticks per period\n",
           (unsigned)(0xFFFFu / (32768u / 1000u)));
    return 0;
}
#endif
```

**Self-test output (verified, native):**

```text
ready bits = 0x80000089
pick order: motor(31) net-A(7) net-B(7) net-C(7) logger(3) idle(0)
SysTick tickless cap @ 480 MHz, 1000 Hz tick:    34 ticks (34 ms)
SysTick tickless cap @ 168 MHz, 1000 Hz tick:    99 ticks (99 ms)
SysTick tickless cap @  64 MHz, 1000 Hz tick:   262 ticks (262 ms)
SysTick tickless cap @  16 MHz,  100 Hz tick:   104 ticks (1040 ms)
LPTIM 16-bit @ 32768 Hz, 1000 Hz tick: 2047 ticks per period
```

**`sched_pick` codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
sched_pick:
	ldr	r2, [r0]
	cbz	r2, .LBB1_3
	push	{r4, lr}
	mov	r1, r0
	clz	r0, r2
	eor	r12, r0, #31
	add.w	lr, r1, r12, lsl #2
	ldr.w	r0, [lr, #4]
	ldr	r3, [r0]
	str.w	r3, [lr, #4]
	cmp	r3, #0
	it	ne
	popne	{r4, pc}
.LBB1_2:
	movs	r4, #1
	movs	r3, #0
	str.w	r3, [lr, #132]
	lsl.w	r3, r4, r12
	bics	r2, r3
	str	r2, [r1]
	pop	{r4, pc}
.LBB1_3:
	movs	r0, #0
	bx	lr
tickless_max_ticks:
```

- **One `clz` + `eor #31`** finds the highest ready priority in constant time: `31 − clz(bits)`, independent of the number of tasks. That's the µC/OS and FreeRTOS (`configUSE_PORT_OPTIMISED_TASK_SELECTION`) technique. More than 32 priorities use a two-level bitmap (a group word plus per-group words).
- **Round-robin among equal priorities** comes for free from the per-priority FIFO: `net-A`, `net-B`, `net-C` were picked in arrival order. Time-slicing re-appends the running task at each tick.
- Delayed tasks live in a separate structure sorted by wake time. Folder 05 implements **hierarchical timing wheels** for O(1) insert.

### 1.7 Tickless idle

Waking 1000 times a second to discover there's nothing to do dominates power in sleepy devices. **Tickless idle** stops the periodic tick and programs one long interrupt for the next timeout.

The **24-bit SysTick limit** caps one sleep (verified above):

| Core clock / tick | Max ticks per SysTick sleep |
|---|---|
| 480 MHz / 1 kHz | **34 ticks (34 ms)** |
| 168 MHz / 1 kHz | 99 ticks |
| 64 MHz / 1 kHz | 262 ticks |
| 16 MHz / 100 Hz | 104 ticks (1.04 s) |
| 16-bit LPTIM @ 32.768 kHz / 1 kHz | 2047 ticks per period |

For long sleeps in deep low-power modes (where SysTick stops with the core clock), production ports use a low-power timer (LPTIM/RTC) clocked from 32.768 kHz.

`tickless.c` (zero diagnostics on Cortex-M4, M7 and M33):

```c
/* tickless.c - SysTick-based tickless idle (the structure of FreeRTOS's
 * vPortSuppressTicksAndSleep), for an RTOS idle hook on ARMv7-M/v8-M. */
#include <stdint.h>

#define SYST_CSR   (*(volatile uint32_t *)0xE000E010u)
#define SYST_RVR   (*(volatile uint32_t *)0xE000E014u)
#define SYST_CVR   (*(volatile uint32_t *)0xE000E018u)
#define SCB_ICSR   (*(volatile uint32_t *)0xE000ED04u)
#define CSR_ENABLE    (1u << 0)
#define CSR_TICKINT   (1u << 1)
#define CSR_CLKSRC    (1u << 2)
#define CSR_COUNTFLAG (1u << 16)
#define ICSR_PENDSTCLR (1u << 25)

#define CYCLES_PER_TICK  (480000000u / 1000u)       /* core clock / tick rate       */
#define MAX_SUPPRESSED   (0x00FFFFFFu / CYCLES_PER_TICK)  /* 24-bit counter limit: 34 */
#define STOPPED_FUDGE    94u                        /* cycles lost while SysTick is stopped (measure!) */

extern int  rtos_ready_to_sleep(void);              /* re-check: no task became ready */
extern void rtos_step_tick(uint32_t ticks);         /* advance kernel time            */

void tickless_idle(uint32_t expected_idle_ticks);
void tickless_idle(uint32_t expected_idle_ticks)
{
    if (expected_idle_ticks > MAX_SUPPRESSED) {
        expected_idle_ticks = MAX_SUPPRESSED;
    }
    if (expected_idle_ticks < 2u) {
        return;                                      /* not worth it */
    }
    SYST_CSR = CSR_CLKSRC | CSR_TICKINT;             /* 1. stop SysTick (counter frozen) */

    uint32_t reload = SYST_CVR + CYCLES_PER_TICK * (expected_idle_ticks - 1u);
    reload = (reload > STOPPED_FUDGE) ? (reload - STOPPED_FUDGE) : reload;

    /* 2. Mask with PRIMASK, NOT BASEPRI: a masked interrupt still WAKES WFI, but its
     *    handler cannot run until we unmask, so we can finish the bookkeeping first. */
    __asm__ volatile("cpsid i" : : : "memory");
    if (rtos_ready_to_sleep() == 0) {                /* an ISR made a task ready meanwhile */
        SYST_CSR = CSR_CLKSRC | CSR_TICKINT | CSR_ENABLE;
        __asm__ volatile("cpsie i" : : : "memory");
        return;
    }
    SYST_RVR = reload;                               /* 3. one long "tick"                */
    SYST_CVR = 0u;
    SYST_CSR = CSR_CLKSRC | CSR_TICKINT | CSR_ENABLE;

    __asm__ volatile("dsb sy\n\twfi\n\tisb sy" : : : "memory");   /* 4. sleep */

    /* 5. Woken: by the long tick (COUNTFLAG) or by another interrupt. */
    SYST_CSR = CSR_CLKSRC | CSR_TICKINT;             /* stop again to read a stable count */
    uint32_t slept;
    if ((SYST_CSR & CSR_COUNTFLAG) != 0u) {
        slept = expected_idle_ticks - 1u;            /* full period elapsed             */
        SYST_RVR = CYCLES_PER_TICK - 1u;
    } else {
        uint32_t elapsed = (reload + 1u) - SYST_CVR; /* cycles actually slept           */
        slept = elapsed / CYCLES_PER_TICK;
        SYST_RVR = CYCLES_PER_TICK - 1u - (elapsed % CYCLES_PER_TICK); /* finish partial tick */
    }
    SCB_ICSR = ICSR_PENDSTCLR;                       /* drop a stale SysTick pend       */
    SYST_CVR = 0u;
    SYST_CSR = CSR_CLKSRC | CSR_TICKINT | CSR_ENABLE;
    rtos_step_tick(slept);                           /* 6. kernel time catches up        */
    SYST_RVR = CYCLES_PER_TICK - 1u;                 /* normal period from next reload   */
    __asm__ volatile("cpsie i" : : : "memory");      /* 7. now the waking ISR runs        */
}
```

The non-obvious steps:

- **`cpsid i` before `WFI`, not BASEPRI.** With PRIMASK set, a pending interrupt still **wakes** `WFI`, but its handler doesn't run until `cpsie i`. The kernel can therefore stop the timer, measure how long it really slept, and step the tick count *before* any ISR observes stale time. A BASEPRI mask doesn't have this property for masked priorities. A masked interrupt below the BASEPRI threshold doesn't wake the core on all implementations (⚠ verify), and the bookkeeping race returns.
- **Re-check readiness with interrupts masked** (`rtos_ready_to_sleep()`). An ISR between the idle decision and `cpsid i` may have readied a task. Sleeping anyway would add up to the whole sleep period of latency.
- **Compensation.** On an early wake, compute the elapsed cycles from the stopped counter, step whole ticks, and load the remainder of the partial tick, so time doesn't drift. `STOPPED_FUDGE` (cycles lost while SysTick is stopped) **must be measured** on the target. FreeRTOS calls it `portMISSED_COUNTS_FACTOR`.
- **`dsb; wfi; isb`.** `DSB` makes sure outstanding writes complete before sleep (Folder 03). `ISB` after wake ensures the following instructions see the state the wake-up handler path established.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way: a context switch that passes the demo

```asm
// ctxsw_bad.S - every line is a shipped bug class.
    .syntax unified
    .thumb
    .global PendSV_Handler
    .thumb_func
PendSV_Handler:
    cpsid   i                       // BUG 1: masks zero-latency IRQs too (use BASEPRI)
    mrs     r0, psp
    stmdb   r0!, {r4-r11}           // BUG 2: FP tasks: s16-s31 not saved; EXC_RETURN not saved,
                                    //        so every task is resumed with the SAME frame type
    ldr     r1, =g_current_tcb
    ldr     r2, [r1]
    str     r0, [r2]
    bl      scheduler_switch        // BUG 3: lr (EXC_RETURN) clobbered here and never restored
    ldr     r1, =g_current_tcb
    ldr     r2, [r1]
    ldr     r0, [r2]
    ldmia   r0!, {r4-r11}
    msr     psp, r0                 // BUG 4: no ISB before the exception return uses PSP
    cpsie   i
    bx      lr                      // lr = whatever scheduler_switch left: HardFault (INVPC)
```

A further bug class lives *outside* this function: **PendSV left at its reset priority of 0, the highest.** A tick ISR that pends PendSV is then *preempted mid-handler* by the context switch, which switches tasks while an ISR is half-done on MSP. The verified `scb_set_pendsv_systick_lowest()` (File 01) sets `SHPR3[23:16] = 0xFF`.

### 2.2 The Silicon-Hardened Production Way

The verified `ctxsw.S` plus `rtos_mini.c`, with the production additions:

1. **FP context handling:** `EXC_RETURN[4]`-driven `S16`–`S31` save and restore (in `ctxsw.S`), `FPCCR.LSPEN`/`ASPEN` left at their reset defaults (lazy, automatic), and per-task `EXC_RETURN` saved in the frame.
2. **ARMv8-M:** also save and restore `PSPLIM` per task (stack-overflow detection, Folder 01 File 03). On TrustZone parts, track the secure context (`TZ_StoreContext_S`).
3. **Cortex-M7 r0p1:** the BASEPRI erratum workaround (`cpsid i; msr basepri; dsb; isb; cpsie i`; Folder 01 File 03).
4. **Stack-overflow check on switch:** compare the saved `sp` with the task's stack limit and check a canary word at the stack base. Cheap, and it catches most overflows before the corruption spreads.
5. **Never run `scheduler_switch` without the kernel ceiling** (`BASEPRI`). Never allocate memory or log inside it.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| HardFault with `CFSR.INVPC` on the first context switch | Bad `EXC_RETURN` (`lr` clobbered), or a frame with the wrong layout | Breakpoint at `bx lr` in PendSV: `lr` must be `0xFFFFFFxD`/`xE1`/`xED` and `PSP` must point at a valid hardware frame |
| `INVSTATE` when a new task starts | Initial xPSR without the T bit (`0x01000000`) | Dump the fabricated frame: word 7 (xPSR) |
| FP values corrupted in one task when another task uses FP | `S16`–`S31` not saved, or the `EXC_RETURN` FP bit not per task | Set `FPCCR.LSPEN = 0` temporarily: if the bug moves, it's FP context |
| Random register corruption, rare | Missing `r4`–`r11` save, or a scheduler written in C that the compiler made use callee-saved registers without saving them (naked/attribute misuse) | Run the switcher in an emulator against a register-preservation test (§1.5). TRACE32 `Register.view` across `PendSV` with `Break.Set PendSV_Handler` |
| Tick ISR half-executed, odd scheduling | PendSV not at the lowest priority | Read `SHPR3`; `NVIC` priority view in the IDE |
| Time drifts in tickless mode | Missing compensation / fudge factor | Compare RTOS time with an RTC over hours; measure `STOPPED_FUDGE` with DWT `CYCCNT` |
| Device never wakes from tickless idle | Wake source masked by BASEPRI-based sleep, or the timer not reprogrammed | Use the PRIMASK + `WFI` pattern; check the low-power mode's wake-up sources in the RCC/PWR registers |

**Per-task stack inspection:** TRACE32 `TASK.STacK.view` (with RTOS awareness), or GDB with an RTOS-aware server (OpenOCD's `rtos FreeRTOS`) shows each task's saved frame. The saved `PC` is at `TCB->sp + 9*4 + 6*4` for the integer frame layout in §1.2: 9 software words, then hardware word 6.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Write and explain a Cortex-M4F context switch."

- **L5:** Writes `stmdb r0!, {r4-r11}` / `ldmia`, and swaps PSP.
- **Why L5 fails on real hardware:** It misses:
  - `EXC_RETURN` as part of the task context (FP tasks need `0xFFFFFFED`);
  - `S16`–`S31` and the lazy-stacking interaction (`VSTM` triggers it);
  - BASEPRI versus PRIMASK;
  - `ISB` after `MSR PSP`;
  - saving `lr` *before* calling C;
  - PendSV at the lowest priority;
  - the T bit in fabricated frames.
- **L7 principal defense:** The verified `ctxsw.S`, line by line (§1.3), the frame diagram (§1.2), and the emulator evidence (§1.5: 15 switches, recurrences intact). Then the production additions: PSPLIM, the TrustZone context, the M7 errata, and stack checks.

### Q2 🔥 "Why is PendSV set to the lowest priority, and why not just switch in the SysTick handler?"

- **L5:** "So it doesn't interrupt other interrupts."
- **Why L5 fails:** That's half of it. Switching inside SysTick would swap tasks while other ISRs may be preempted and *still active* on MSP, and their state belongs to no task. With PendSV pended at the lowest priority, the switch happens exactly when the last ISR returns, **tail-chained** (6 cycles, no extra stacking). Multiple "switch requests" from several ISRs collapse into one PendSV.
- **L7 defense:** The pend/tail-chain mechanism. `ICSR.PENDSVSET` from any context, coalesced requests, and handler-mode MSP isolation. Plus the failure mode when PendSV's priority is left at 0 (§2.1).

### Q3 "How does an O(1) scheduler find the highest-priority ready task?"

- **L5:** "Scan the task list from highest priority."
- **Why L5 fails:** That's O(n) and has variable latency, which shows up as jitter in the switch time.
- **L7 defense:** A ready bitmap with one bit per priority, plus a per-priority FIFO. Pick is `31 − clz(bits)` (verified: `clz` + `eor #31`), insert is O(1), and round-robin comes from the FIFO (verified pick order). Use a two-level bitmap beyond 32 priorities. On cores without CLZ (ARMv6-M has none), use a 256-entry lookup table or a de Bruijn multiply.

### Q4 🧊 "Your tickless idle sometimes adds a full sleep period of latency to an event. Why?"

- **L5:** "The timer resolution."
- **Why L5 fails:** It's a race. An ISR between "decide to sleep for N ticks" and `WFI` readied a task, and the idle code slept anyway.
- **L7 defense:** `cpsid i`, then re-check readiness, then `WFI` *with PRIMASK set*. A pending interrupt still wakes the core, but its handler waits until the kernel has stepped time (verified `tickless.c`). Respect the 24-bit cap (verified 34 ticks at 480 MHz), measure the fudge factor, and switch to an LPTIM for deep sleep.

### Q5 "What has to change in your context switch for ARMv8-M with TrustZone?"

- **L5:** "Nothing; same instructions."
- **Why L5 fails:**
  - **`PSPLIM`** must be saved and restored per task, or stack-limit checking uses the previous task's limit (UsageFault `STKOF` for no reason, or no protection).
  - `EXC_RETURN` gains security-state bits (`S`, `ES`, `DCRS`).
  - Tasks that call Secure services need a Secure context (the TF-M `TZ_*` APIs) switched alongside.
  - The Secure and Non-secure stacks and MPUs are banked.
- **L7 defense:** List those changes. Note FreeRTOS's `ARM_CM33` port as a reference, and test with the same emulator technique (§1.5) extended to `PSPLIM`.

---

## 5. Invariants Checklist

- [ ] Tasks on PSP, handlers on MSP; MSP sized for nesting, task stacks for one frame plus task use.
- [ ] PendSV and SysTick at the lowest priority; the switch only ever happens in PendSV.
- [ ] Context = `r4`–`r11` + `EXC_RETURN` (+ `S16`–`S31` when `EXC_RETURN[4] = 0`) (+ `PSPLIM` on v8-M); `lr` saved before any C call.
- [ ] `MSR PSP` followed by `ISB` before `BX LR`; BASEPRI (not PRIMASK) around the scheduler call.
- [ ] Fabricated initial frames have xPSR.T = 1, a valid `EXC_RETURN`, and an exit trap in `LR`.
- [ ] Scheduler pick is O(1) (bitmap + CLZ or table) with FIFO round-robin per priority.
- [ ] Tickless idle: PRIMASK + re-check + `DSB; WFI; ISB`; compensation with a measured fudge; LPTIM for deep sleep.
- [ ] The switcher is tested against a hardware-exception model (emulator) with register-preservation checks.

## 6. References

1. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E) B1.4–B1.5; Application Note 298, *Cortex-M4(F) Lazy Stacking and Context Switching*.
2. FreeRTOS kernel `portable/GCC/ARM_CM4F/port.c`, `ARM_CM7/r0p1/port.c`, `ARM_CM33/non_secure/portasm.c`; Zephyr `arch/arm/core/cortex_m/swap_helper.S`.
3. J. J. Labrosse, *µC/OS-III: The Real-Time Kernel* (ready-list bitmap).
4. C. L. Liu, J. W. Layland, *Scheduling Algorithms for Multiprogramming in a Hard-Real-Time Environment*, JACM 1973.
5. Unicorn Engine documentation (M-class mode, register IDs) and ARMv7-M B1.5 pseudocode, used for the exception-model harness.
