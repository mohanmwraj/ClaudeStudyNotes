# 01 · Safety-Critical C: MISRA, Static Analysis, Stack and WCET Bounds, and Watchdog Supervision

> **Folder:** `08-Silicon-Tier1-L7-Playbook-and-Bar-Raiser-QA/` · **File 1 of 3**
> **Anchors:**
> - MISRA C:2012 (third edition, with Amendments 1–4) consolidated as **MISRA C:2023**, and *MISRA Compliance:2020* (deviations, GRP).
> - Functional-safety standards: ISO 26262-6:2018, IEC 61508-3:2010, RTCA DO-178C with DO-330 (tool qualification), IEC 62304.
> - SEI CERT C Coding Standard.
> - Clang Static Analyzer and UndefinedBehaviorSanitizer documentation.
> - R. Wilhelm et al., *The Worst-Case Execution-Time Problem: Overview of Methods and Survey of Tools* (ACM TECS 7(3), 2008).
> - AUTOSAR *Specification of Watchdog Manager* (alive, deadline and logical supervision).
> - Arm *ARMv7-M ARM* C1.8 (DWT).
>
> **Verification:**
> - Six real-world defects were run through **every analysis layer available locally**:
>   - `-Wall -Wextra`;
>   - the full strict warning set;
>   - the **Clang Static Analyzer**;
>   - host unit tests under **UBSan**;
>   - a cross-ABI test.
>   The compliant rewrite was run through the same layers.
> - Stack bounds for the Folder 07 crash path came from `-fstack-usage`.
> - A WCET measurement campaign: Cortex-M7 code executed in Unicorn on 1,002 inputs, as instruction counts.
> - A **watchdog supervisor** was tested in simulated time against seven scenarios.
> - All code is warning-free on Cortex-M7/M33/M4 (the supervisor also on AArch64 and RV32). All outputs inserted verbatim, with sanitizer output normalized (thread ids and ASLR addresses removed).
> - No commercial MISRA checker or sound analyzer was available. Where the text names what such a tool *would* report, that is a rule-text mapping, not a run.

---

## 0. The thesis

In safety-critical work, correctness is not asserted. It is **argued from evidence** in a safety case, and every piece of evidence has a blind spot:

| Evidence | Gives | Blind spot |
|---|---|---|
| Coding standard (MISRA C) | A language subset in which analysis becomes tractable | Compliance is not correctness; `(void)` and deviations are legal |
| Compiler warnings | Cheap, every build | Heuristics tuned to avoid noise (verified: D1 slipped through) |
| Unsound static analysis (bug finders) | Deep path-sensitive defects | Misses things by design (verified: D5 missed) |
| Sound static analysis (abstract interpretation) | *Proof of absence* of run-time error classes | Cost, false alarms, needs annotations |
| Testing + sanitizers | Real executions | Only the paths you drive (verified: D3 no diagnostic, D6 invisible on one ABI) |
| Stack / WCET analysis | Resource bounds | Only as good as the call graph and the model |
| Run-time supervision (watchdog) | Detects what everything above missed, forces a safe state | Detection latency; only as good as what it supervises |

The layer matrix in §1.3 shows **no single layer catching all six defects**. That is the L7 argument for layered evidence, and for putting sound analysis on the critical modules.

| Standard | Domain | Integrity levels | Coding-guideline expectation |
|---|---|---|---|
| ISO 26262-6 | Automotive | ASIL A–D | "Modelling and coding guidelines" (strong typing, defensive implementation, a language subset); MISRA C is the de-facto choice |
| IEC 61508-3 | Industrial (generic) | SIL 1–4 | Coding standard, language subset, static analysis highly recommended at SIL 3/4 |
| DO-178C (+ DO-330) | Avionics | DAL A–E | Coding standards, structural coverage (MC/DC at DAL A), tool qualification |
| IEC 62304 | Medical | Class A–C | Development process; coding standards as part of it |

⚠ verify the exact clause and table numbers against the edition you are certified to.

---

## 1. First-Principles Mechanics

### 1.1 MISRA C in one page

- **Editions:**
  - MISRA C:2012 (third edition) plus Amendment 1 (security), Amendment 2 (C11 core), Amendment 3 (C11/C18 features) and Amendment 4 (concurrency and atomics);
  - consolidated as **MISRA C:2023**;
  - a 2025 edition was announced by MISRA ⚠ verify its status for your program.
- **Categories:**
  - **Mandatory:** no deviation allowed.
  - **Required:** formal deviation needed.
  - **Advisory:** a recorded decision.
  - **Directives** are only partly checkable by tools and need process evidence. **Rules** are decidable or undecidable by static analysis.
- **Process (MISRA Compliance:2020):**
  - a Guideline Re-categorization Plan (GRP);
  - a **compliance matrix** per project;
  - **deviation records**, each with rationale, scope, risk and approval;
  - **deviation permits** for recurring, pre-approved patterns.
- **The essential type model** is the heart of MISRA's arithmetic rules. Every expression has an *essential type* category: Boolean, character, enum, signed, unsigned, floating. Arithmetic across categories, or narrowing, is restricted, because C's integer promotions silently change signedness (D1) and plain `char`'s signedness is implementation-defined (D6).

The rules an L7 should be able to justify from hardware and compiler mechanics:

| Guideline | Category | Why (mechanism) | Where this KB shows it |
|---|---|---|---|
| Rule 1.3 / Dir 4.1 | Required | Undefined behavior licenses the optimizer to delete checks | Folder 01 File 01 |
| Dir 4.6 | Advisory | `int` width varies (16-bit DSPs, 32-bit MCUs) | D1 |
| Rule 9.1 | Mandatory | Indeterminate values: the optimizer may fold anything (verified: UBSan reported `9 * 2` as an overflow) | D4 |
| Rules 10.1–10.8 | Required/Advisory | Integer promotion of `uint16_t` to **signed** `int`; plain `char` signedness differs per ABI | D1, D6 |
| Rules 11.3, 11.4, 11.6 | Required/Advisory | Strict aliasing (Folder 01); integer↔pointer casts. **MMIO needs a documented deviation of 11.4** (below) | Folder 01, every driver here |
| Rule 12.2 | Required | Shift by ≥ width is UB, and the hardware differs. AArch32 register shifts use the low byte of the amount, so `x << 32` is 0. x86 and AArch64 mask the amount, so `x << 32` leaves `x` unchanged | D2 |
| Rule 13.2, 13.5 | Required | Unsequenced side effects; side effects skipped by `&&` short-circuit | — |
| Rule 14.2, 14.3 | Required | Well-formed loops make loop bounds derivable (WCET!) | §1.5 |
| Rule 17.2 | Required | **No recursion**: required for static stack bounds | §1.4 |
| Rule 17.7 | Required | Use return values, though a `(void)` cast complies (D4: the defect survives compliance) | D4 |
| Rule 18.1 | Required | Pointer arithmetic out of bounds | D3 |
| Rule 19.2 | Advisory | `union`: the Folder 07 crash record uses one deliberately → deviation | Folder 07 File 04 |
| Rule 21.3 | Required | No `malloc`/`free`: use pools (Folder 05, Folder 07 File 03) | — |

**A deviation record for MMIO** (the single most common deviation in embedded C):

| Field | Content |
|---|---|
| Guideline | MISRA C:2012 Rule 11.4 (Advisory): conversion between pointer and integer |
| Pattern | `#define REG (*(volatile uint32_t *)0xE000ED28u)` in board/CMSIS headers only |
| Rationale | Memory-mapped registers have fixed physical addresses defined by the SoC. No conforming alternative exists |
| Scope | Register-definition headers, vendor CMSIS headers. Never in application logic |
| Risk control | Addresses taken from the reference manual and reviewed. Every register is `volatile` and has the correct width. The MPU maps the region Device (Folder 07 File 01) |
| Approval | Safety manager, project-level permit |

### 1.2 Static analysis: what kind of tool proves what

| Class | Examples | Sound? | Output means |
|---|---|---|---|
| Compiler warnings | Clang/GCC `-W…` | No | "Likely mistake" heuristics, tuned for low noise |
| Coding-standard checkers | PC-lint Plus, Helix QAC, LDRA, Parasoft C/C++test, Polyspace Bug Finder, cppcheck + MISRA addon | Decidable rules: yes; undecidable: no | Rule violations |
| Path-sensitive bug finders | Clang Static Analyzer, Coverity, CodeSonar, Klocwork | **No** (bounded exploration) | "Found a path to a defect" |
| Sound abstract interpreters | Astrée, Polyspace Code Prover, Frama-C EVA/WP, TrustInSoft | **Yes**, within their semantics | Green = proven safe, red = proven error, orange = unknown |

Abstract interpretation (Cousot & Cousot, 1977) computes an over-approximation of all reachable states, so "no alarm" means *no execution* can trigger the error. It is the only class that turns "we found no bug" into "there is no bug of this class". That's why DAL A/ASIL D programs use it on critical modules, and why D3 below matters: every unsound layer here missed it.

### 1.3 The verified layer matrix

Six defects, each from real firmware. The defective file compiles cleanly with `-Wall -Wextra` (§2.1). Each layer was run as shown in §2.2:

| Defect | `-Wall -Wextra` | Strict set | Clang SA | UBSan host test | MISRA guideline that forbids it |
|---|---|---|---|---|---|
| D1 `uint16 * uint16` overflows signed `int` | – | – (Clang's range analysis treats the product as non-negative) | – | ✔ `signed integer overflow: 50000 * 50000` | Rule 10.6/10.8, Dir 4.6 |
| D2 shift by 32 | – | – | – | ✔ `shift exponent 32 is too large` | Rule 12.2 |
| D3 `n - 1u` loop bound, `n == 0` | – | – | – | ✘ **access violation, no diagnostic** | Rule 18.1, Dir 4.1 (a sound analyzer flags the out-of-bounds read) |
| D4 status discarded, uninitialized read | – | – | ✔ `left operand of '*' is a garbage value` | ✔, but **misleading**: `9 * 2 cannot be represented` | Rule 9.1 (17.7 is satisfied by the `(void)`!) |
| D5 NULL from a failed lookup | – | – | ✘ **missed** | ✔ `member access within null pointer` | Dir 4.1; CERT EXP34-C |
| D6 plain `char` checksum | – | – | – | ✘ invisible on one ABI. Only the cross-ABI test shows **197 vs 453** | Rule 10.1/10.5, Dir 4.6 |

Three lessons, each verified:

1. **Warnings are heuristics.** Even `-Wconversion -Wsign-conversion` stays silent on D1, because the compiler "knows" both operands are non-negative, and that is exactly the reasoning the overflow defeats.
2. **Bug finders and sanitizers are complementary, and both are incomplete.** The analyzer found D4 but not D5. UBSan found D5 but reported D4 with operands that cannot overflow (`9 * 2`): once a value is indeterminate, the optimizer may fold the check itself, and even the diagnostic is untrustworthy.
3. **Some defects only appear on another platform.** D6 is correct on Arm (unsigned `char`) and wrong on x86-64 (signed `char`). The host-side tool and the target disagree on every checksum containing a byte ≥ 0x80.

### 1.4 Stack bounds: `-fstack-usage` plus the call graph

A static worst-case stack needs two inputs:

1. **The frame size of every function:** `-fstack-usage` writes `file:line:function  bytes  static|dynamic`. `dynamic` means a VLA or `alloca`; ban both.
2. **The call graph:** worst case = max over all root-to-leaf paths of Σ frame sizes. Recursion (Rule 17.2) and function pointers (they need annotations) break it. GCC's `-fcallgraph-info=su` emits both together ⚠ verify; with Clang, derive the graph from the source or the map file.

**Interrupts add to the main stack:** each preemption level adds one ISR's worst path plus **32 bytes** of hardware frame (**104** with an FP frame, plus 4 bytes of alignment pad). With *k* preemption priority levels (set by the NVIC priority grouping):

`MSP ≥ main_path + Σ over the k levels (ISR_path_max + 104 + 4)`

This is the reason to keep few preemption levels and keep big buffers out of ISRs.

**Verified on the Folder 07 crash path** (Cortex-M7, `-O2`): see the `.su` output in §2.2. The private crash stack must hold `crash_capture` (32 B) → `crash_seal` (8 B) → `crash_crc` (36 B) = **76 B**, and `system_reset` (0 B) runs after `crash_seal` returns. 76 B against a 1,024 B crash stack is a 13× margin. `crash_take` (288 B, holding the record snapshot) runs only at boot, on the normal stack.

### 1.5 WCET: why measurement alone underestimates

| Method | Tools | Gives |
|---|---|---|
| Static | AbsInt aiT, OTAWA, Bound-T | A **safe upper bound**: micro-architectural model + loop bounds + path analysis (IPET: integer linear programming over basic-block counts) |
| Hybrid | Rapita RapiTime | Measured block times + static path combination |
| Measurement | DWT `CYCCNT` + high-water marks (`cyccnt.h` below), logic-analyzer GPIO toggles | A **lower bound**: the worst case *you happened to drive* |

On a Cortex-M7, variability comes from:

- I/D caches;
- flash wait states and the flash accelerator;
- the branch predictor and dual issue;
- AXI contention from DMA.

The deterministic platform choices are File 01 of Folder 07: hot code in **ITCM**, hot data in **DTCM**, no cache misses on the critical path.

**Verified measurement trap** (`isort16`, 16-sample insertion sort, Cortex-M7 code executed in Unicorn, counting instructions):

- 1,000 seeded random inputs never come close to the worst path.
- The largest random measurement is **82.6%** of the reverse-sorted worst case: a **17.4% underestimate**.
- Only the analytic loop bounds (15 outer iterations, Σi = 120 inner iterations) identify the input that reaches it.

These are instruction counts, a path-length proxy, not cycles. Cycles add the micro-architectural variability listed above, which widens the gap further.

### 1.6 Watchdog design

| Choice | Production rule |
|---|---|
| Watchdog type | **Independent** watchdog on its own oscillator (survives a main-clock failure), and/or a **window** watchdog (also catches a runaway refresher). External watchdog ICs for the highest integrity levels |
| Who refreshes | **Only a supervisor that has evidence every task is healthy.** Never a timer ISR unconditionally (verified: the SysTick design never reset with a dead task for 10 s) |
| What is supervised | **Alive** (jobs per cycle within [min, max]: catches hangs *and* runaway loops), **deadline** (checkpoint-to-checkpoint time), **logical/program-flow** (checkpoints in order) |
| On failure | Latch the first failure, write the cause (entity + type + time) into the crash record (Folder 07 File 04), stop refreshing (or reset immediately) |
| Early warning | Window-watchdog early-wakeup interrupt: capture state milliseconds before the reset |
| Boot | Read and record the reset cause (watchdog / software / brown-out / pin); crash-loop counter → safe mode |
| Debug | Debug-freeze bits stop the watchdog while halted. Production units must ship with it running |
| Long operations | Flash erase can block for longer than the timeout: split the operation, or bound it and refresh from the supervisor between steps. Never "refresh inside the erase loop" |

**Detection latency** (verified, 100 ms supervision, 250 ms hardware timeout):

`reset time = last healthy refresh + T_wdt`, and `detection ≤ fault + T_sup × ⌈slack⌉`.

The slack comes from `min_alive`. Task B (2 jobs per cycle, `min_alive = 1`) hanging at 3037 ms was detected only at **3200 ms**: its last job at 3002 ms still satisfied the 3000–3100 ms cycle. It was reset at **3350 ms** (313 ms after the fault). Tighter `min_alive` means faster detection but less tolerance to jitter. Choose from the task's timing analysis, not by guessing.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

Six defects that compile cleanly at the warning level most projects stop at:

```c
/* misra_bad.c - six defects from real firmware. Each compiles cleanly with
 * "-Wall -Wextra", the warning set most projects stop at. */
#include <stdbool.h>

#include "misra_api.h"

uint32_t scale_raw(uint16_t raw, uint16_t gain)
{
    return raw * gain;                           /* D1: both operands promote to SIGNED int:
                                                  *     50000 * 50000 overflows -> UB        */
}

uint32_t low_mask(uint32_t bits)
{
    return (1u << bits) - 1u;                    /* D2: bits == 32 shifts by the width -> UB */
}

uint32_t delta_sum(const uint16_t *buf, uint32_t n)
{
    uint32_t sum = 0u;
    for (uint32_t i = 0u; i < n - 1u; i++) {     /* D3: n == 0 -> bound 0xFFFFFFFF: reads
                                                  *     far past the buffer               */
        sum += (uint32_t)(buf[i + 1u] - buf[i]);
    }
    return sum;
}

static const int32_t k_cfg[4] = { 10, 20, 30, 40 };

static bool cfg_lookup(uint32_t id, int32_t *out)
{
    if (id < 4u) {
        *out = k_cfg[id];
        return true;
    }
    return false;
}

int32_t cfg_twice(uint32_t id)
{
    int32_t v;
    (void)cfg_lookup(id, &v);                    /* D4: failure discarded: v is read
                                                  *     uninitialized for id >= 4         */
    return v * 2;
}

typedef struct { uint32_t id; int32_t value; } sensor_t;
static sensor_t g_sensors[3] = { { 1u, 100 }, { 2u, 200 }, { 7u, 700 } };

static sensor_t *find_sensor(uint32_t id)
{
    for (size_t i = 0u; i < 3u; i++) {
        if (g_sensors[i].id == id) {
            return &g_sensors[i];
        }
    }
    return NULL;
}

int32_t sensor_value(uint32_t id)
{
    return find_sensor(id)->value;               /* D5: NULL for an unknown id            */
}

uint32_t frame_checksum(const char *frame, size_t len)
{
    uint32_t sum = 0u;
    for (size_t i = 0u; i < len; i++) {
        sum += (uint32_t)frame[i];               /* D6: plain char: byte 0xFF adds 255 on
                                                  *     Arm (unsigned char), 0xFFFFFFFF on
                                                  *     x86 (signed char)                 */
    }
    return sum;
}
```

And the watchdog refresh found in most first-generation firmware:

```c
/* wdg_bad.c - the watchdog refresh found in most first-generation firmware. */
#include <stdint.h>

#define WDT_KEY (*(volatile uint32_t *)0x58004800u)   /* IWDG key register, STM32H7-class (verify per part) */
#define WDT_REFRESH_KEY 0x0000AAAAu

void SysTick_Handler(void);

void SysTick_Handler(void)                    /* 1 kHz tick */
{
    static uint32_t ticks;
    ticks++;
    if ((ticks % 10u) == 0u) {
        WDT_KEY = WDT_REFRESH_KEY;            /* BUG: proves only that SysTick runs. A task that is
                                               *  hung, deadlocked or starved keeps getting covered;
                                               *  the watchdog fires only if interrupts die too   */
    }
}
```

### 2.2 The Silicon-Hardened Production Way

**The compliant rewrite:**

```c
/* misra_api.h - the six functions, in a defective and a compliant version. */
#ifndef MISRA_API_H
#define MISRA_API_H

#include <stddef.h>
#include <stdint.h>

#define CFG_DEFAULT    0
#define SENSOR_INVALID INT32_MIN

/* misra_bad.c */
uint32_t scale_raw(uint16_t raw, uint16_t gain);
uint32_t low_mask(uint32_t bits);
uint32_t delta_sum(const uint16_t *buf, uint32_t n);
int32_t  cfg_twice(uint32_t id);
int32_t  sensor_value(uint32_t id);
uint32_t frame_checksum(const char *frame, size_t len);

/* misra_good.c */
uint32_t scale_raw_ok(uint16_t raw, uint16_t gain);
uint32_t low_mask_ok(uint32_t bits);
uint32_t delta_sum_ok(const uint16_t *buf, uint32_t n);
int32_t  cfg_twice_ok(uint32_t id);
int32_t  sensor_value_ok(uint32_t id);
uint32_t frame_checksum_ok(const uint8_t *frame, size_t len);

#endif /* MISRA_API_H */
```

```c
/* misra_good.c - the same six functions, MISRA C:2012/2023-style: essential
 * types explicit, every precondition checked, every failure handled. */
#include <stdbool.h>

#include "misra_api.h"

uint32_t scale_raw_ok(uint16_t raw, uint16_t gain)
{
    return (uint32_t)raw * (uint32_t)gain;       /* R10.6/10.8: widen BEFORE the operation */
}

uint32_t low_mask_ok(uint32_t bits)
{
    uint32_t m;
    if (bits >= 32u) {                           /* R12.2: shift amount < width */
        m = 0xFFFFFFFFu;
    } else {
        m = (1u << bits) - 1u;
    }
    return m;
}

uint32_t delta_sum_ok(const uint16_t *buf, uint32_t n)
{
    uint32_t sum = 0u;
    for (uint32_t i = 1u; i < n; i++) {          /* R14.2 + Dir 4.1: no wrapping bound */
        sum += (uint32_t)buf[i] - (uint32_t)buf[i - 1u];   /* unsigned wrap is defined */
    }
    return sum;
}

static const int32_t k_cfg[4] = { 10, 20, 30, 40 };

static bool cfg_lookup(uint32_t id, int32_t *out)
{
    bool ok = false;
    if (id < 4u) {
        *out = k_cfg[id];
        ok = true;
    }
    return ok;                                   /* R15.5: single point of exit */
}

int32_t cfg_twice_ok(uint32_t id)
{
    int32_t v = CFG_DEFAULT;                     /* R9.1: initialized on every path */
    if (!cfg_lookup(id, &v)) {                   /* R17.7: the result is used */
        v = CFG_DEFAULT;
    }
    return v * 2;
}

typedef struct { uint32_t id; int32_t value; } sensor_t;
static const sensor_t g_sensors[3] = { { 1u, 100 }, { 2u, 200 }, { 7u, 700 } };

static const sensor_t *find_sensor(uint32_t id)
{
    const sensor_t *found = NULL;
    for (size_t i = 0u; (i < 3u) && (found == NULL); i++) {
        if (g_sensors[i].id == id) {
            found = &g_sensors[i];
        }
    }
    return found;
}

int32_t sensor_value_ok(uint32_t id)
{
    const sensor_t *s = find_sensor(id);
    int32_t v = SENSOR_INVALID;
    if (s != NULL) {                             /* Dir 4.1, CERT EXP34-C */
        v = s->value;
    }
    return v;
}

uint32_t frame_checksum_ok(const uint8_t *frame, size_t len)
{
    uint32_t sum = 0u;
    for (size_t i = 0u; i < len; i++) {
        sum += frame[i];                         /* R10.1: bytes are uint8_t, never plain char */
    }
    return sum;
}
```

**The host test** (one defect per process, because a sanitizer report aborts the run):

```c
/* misra_test.c - one defect per process (a sanitizer report aborts the run):
 * misra_test <1..6> runs the defective function on its trigger input, then
 * the compliant one on the same input. */
#include <stdio.h>
#include <stdlib.h>

#include "misra_api.h"

static uint16_t g_buf[4] = { 10u, 30u, 60u, 100u };
static const char    k_frame_c[4] = { 'A', 'B', (char)0xFF, 'C' };
static const uint8_t k_frame_u[4] = { 0x41u, 0x42u, 0xFFu, 0x43u };

int main(int argc, char **argv)
{
    int c = (argc > 1) ? atoi(argv[1]) : 0;
    uint32_t n = (uint32_t)argc - 2u;            /* 0 at run time, opaque to the optimizer */
    switch (c) {
    case 1:
        printf("ok:  scale_raw_ok(50000, 50000) = %u\n", (unsigned)scale_raw_ok(50000u, 50000u));
        printf("bad: scale_raw(50000, 50000)    = %u\n", (unsigned)scale_raw(50000u, 50000u));
        break;
    case 2:
        printf("ok:  low_mask_ok(32) = 0x%08X\n", (unsigned)low_mask_ok(32u + n));
        printf("bad: low_mask(32)    = 0x%08X\n", (unsigned)low_mask(32u + n));
        break;
    case 3:
        printf("ok:  delta_sum_ok(buf, 0) = %u, delta_sum_ok(buf, 4) = %u\n",
               (unsigned)delta_sum_ok(g_buf, n), (unsigned)delta_sum_ok(g_buf, 4u));
        fflush(stdout);
        printf("bad: delta_sum(buf, 0)    = %u\n", (unsigned)delta_sum(g_buf, n));
        break;
    case 4:
        printf("ok:  cfg_twice_ok(9) = %d\n", (int)cfg_twice_ok(9u + n));
        printf("bad: cfg_twice(9)    = %d (indeterminate)\n", (int)cfg_twice(9u + n));
        break;
    case 5:
        printf("ok:  sensor_value_ok(5) = %d\n", (int)sensor_value_ok(5u + n));
        fflush(stdout);
        printf("bad: sensor_value(5)    = %d\n", (int)sensor_value(5u + n));
        break;
    case 6:
        printf("ok:  frame_checksum_ok = %u | bad: frame_checksum = %u\n",
               (unsigned)frame_checksum_ok(k_frame_u, 4u), (unsigned)frame_checksum(k_frame_c, 4u));
        break;
    default:
        return 2;
    }
    return 0;
}
```

**The layer runner** (every analysis available in this kit):

```bash
#!/usr/bin/env bash
# layers.sh - run every analysis layer available in this kit over misra_bad.c
# and misra_good.c. Output is normalized (sanitizer thread ids, ASLR addresses,
# absolute paths and shell job ids removed) so that it is reproducible.
S="$1"
Z="$S/tools/zig/ziglang/zig.exe"
R="$S/tools/zig/ziglang/lib/include"
export ZIG_GLOBAL_CACHE_DIR="$S/zigcache" ZIG_LOCAL_CACHE_DIR="$S/zigcache"
M7="-target thumbv7em-none-eabihf -mcpu=cortex-m7 -mfloat-abi=hard -isystem $S/inc -isystem $R -O2 -std=c11"
STRICT="-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wcast-align -Wshadow -Wstrict-prototypes -Wmissing-prototypes"
norm() {
  sed -E -e 's/^thread [0-9]+ panic: /UBSan: /' \
         -e 's#^.*[\\/](misra_[a-z]+[.]c)#\1#' \
         -e 's/: 0x[0-9a-f]+ in /: in /' |
  grep -E '^(UBSan|misra_|ok:|bad:)' | grep -v 'in main'
}

for f in misra_bad.c misra_good.c; do
  echo "=================== $f"
  echo "--- layer 1: -Wall -Wextra (Cortex-M7)"
  out=$("$Z" clang $M7 -Wall -Wextra -c $f -o /dev/null 2>&1); echo "${out:-(no diagnostics)}"
  echo "--- layer 2: strict warning set (Cortex-M7)"
  out=$("$Z" clang $M7 $STRICT -c $f -o /dev/null 2>&1 | grep -E 'warning:'); echo "${out:-(no diagnostics)}"
  echo "--- layer 3: Clang Static Analyzer (Cortex-M7)"
  out=$("$Z" clang --analyze $M7 $f -o /dev/null 2>&1 | grep -E 'warning:'); echo "${out:-(no diagnostics)}"
done

echo "=================== layer 4: host unit tests under UBSan (one process per defect)"
"$Z" cc -target x86_64-windows-gnu -O1 -std=c11 -fsanitize=undefined misra_test.c misra_bad.c misra_good.c -o mt_ubsan.exe 2>&1
for c in 1 2 3 4 5 6; do
  echo "--- case D$c"
  { ./mt_ubsan.exe $c > mt.out 2> mt.err; } 2>/dev/null
  rc=$?
  cat mt.out mt.err | norm
  if [ $rc -eq 139 ]; then echo "process killed: access violation (exit status 139), no diagnostic";
  elif [ $rc -ne 0 ]; then echo "exit status $rc"; fi
done
echo "=================== D6 across platforms: same source, char signedness of each ABI"
"$Z" cc -target x86_64-windows-gnu -O1 -std=c11 misra_test.c misra_bad.c misra_good.c -o mt_s.exe
"$Z" cc -target x86_64-windows-gnu -O1 -std=c11 -funsigned-char misra_test.c misra_bad.c misra_good.c -o mt_u.exe
echo "x86-64 (signed char):          $(./mt_s.exe 6)"
echo "Arm AAPCS (-funsigned-char):   $(./mt_u.exe 6)"
rm -f mt.out mt.err
```

**Result (verified; run twice, identical):**

```
=================== misra_bad.c
--- layer 1: -Wall -Wextra (Cortex-M7)
(no diagnostics)
--- layer 2: strict warning set (Cortex-M7)
(no diagnostics)
--- layer 3: Clang Static Analyzer (Cortex-M7)
misra_bad.c:44:14: warning: The left operand of '*' is a garbage value [core.UndefinedBinaryOperatorResult]
=================== misra_good.c
--- layer 1: -Wall -Wextra (Cortex-M7)
(no diagnostics)
--- layer 2: strict warning set (Cortex-M7)
(no diagnostics)
--- layer 3: Clang Static Analyzer (Cortex-M7)
(no diagnostics)
=================== layer 4: host unit tests under UBSan (one process per defect)
--- case D1
ok:  scale_raw_ok(50000, 50000) = 2500000000
UBSan: signed integer overflow: 50000 * 50000 cannot be represented in type 'int'
misra_bad.c:9: in scale_raw (misra_bad.obj)
exit status 3
--- case D2
ok:  low_mask_ok(32) = 0xFFFFFFFF
UBSan: shift exponent 32 is too large for 32-bit type 'unsigned int'
misra_bad.c:15: in low_mask (misra_bad.obj)
exit status 3
--- case D3
ok:  delta_sum_ok(buf, 0) = 0, delta_sum_ok(buf, 4) = 90
process killed: access violation (exit status 139), no diagnostic
--- case D4
ok:  cfg_twice_ok(9) = 0
UBSan: signed integer overflow: 9 * 2 cannot be represented in type 'int'
misra_bad.c:44: in cfg_twice (misra_bad.obj)
exit status 3
--- case D5
ok:  sensor_value_ok(5) = -2147483648
UBSan: member access within null pointer of type 'sensor_t'
misra_bad.c:62: in sensor_value (misra_bad.obj)
exit status 3
--- case D6
ok:  frame_checksum_ok = 453 | bad: frame_checksum = 197
=================== D6 across platforms: same source, char signedness of each ABI
x86-64 (signed char):          ok:  frame_checksum_ok = 453 | bad: frame_checksum = 197
Arm AAPCS (-funsigned-char):   ok:  frame_checksum_ok = 453 | bad: frame_checksum = 453
```

**Stack usage of the Folder 07 crash subsystem** (verified — Clang 21.1.0, `-O2 -fstack-usage`, Cortex-M7):

```
crash_fault.c:37:HardFault_Handler	0	static
crash_fault.c:111:crash_capture	32	static
crash_fault.c:98:system_reset	0	static
crash_decode.c:6:crash_crc	36	static
crash_decode.c:21:crash_seal	8	static
crash_decode.c:163:crash_take	288	static
crash_decode.c:46:tx_h	8	static
main_crash.c:24:sensor_read	0	static
main_crash.c:29:filter_step	24	static
main_crash.c:38:app_task	0	static
main_crash.c:45:boot_done	0	static
main_crash.c:65:main	0	static
```

**The watchdog supervisor:**

```c
/* wdg.h - task-aware watchdog supervisor: alive, deadline and program-flow
 * (logical) supervision, the AUTOSAR WdgM model reduced to its core.
 *  - Each supervised entity reports checkpoints from ITS OWN context only
 *    (single writer); the supervisor reads only atomics.
 *  - The hardware watchdog is refreshed ONLY by wdg_supervise(), and only while
 *    every entity is healthy. The first failure is latched: from then on the
 *    hardware watchdog is starved and resets the part.
 *  - The supervisor is supervised by construction: if it stops running, nobody
 *    refreshes the hardware watchdog. */
#ifndef WDG_H
#define WDG_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#define WDG_MAX_ENTITIES 8u

typedef enum { WDG_OK = 0, WDG_ALIVE_LOW, WDG_ALIVE_HIGH, WDG_DEADLINE, WDG_FLOW } wdg_status_t;

typedef struct {
    const char *name;
    uint32_t    min_alive;                   /* completed jobs per supervision cycle  */
    uint32_t    max_alive;
    uint32_t    deadline;                    /* ticks from checkpoint 0 to the last   */
    uint8_t     ncp;                         /* checkpoints per job, in order 0..ncp-1 */
} wdg_entity_cfg_t;

typedef struct {
    const wdg_entity_cfg_t *cfg;
    _Atomic uint32_t alive;                  /* written by the entity                  */
    _Atomic uint32_t flow_errors;            /* written by the entity                  */
    _Atomic uint32_t deadline_errors;        /* written by the entity                  */
    uint8_t          next_cp;                /* entity-private program-flow state     */
    uint32_t         job_start;              /* entity-private                         */
    uint32_t         seen_alive, seen_flow, seen_deadline;   /* supervisor-private   */
} wdg_entity_t;

typedef struct {
    wdg_entity_t  e[WDG_MAX_ENTITIES];
    uint32_t      n;
    void        (*refresh)(void);            /* hardware watchdog kick                */
    bool          failed;                    /* latched                               */
    wdg_status_t  why;
    uint32_t      who, when;
} wdg_t;

void         wdg_init(wdg_t *w, void (*refresh)(void));
int32_t      wdg_register(wdg_t *w, const wdg_entity_cfg_t *cfg);
void         wdg_checkpoint(wdg_t *w, uint32_t id, uint8_t cp, uint32_t now);
wdg_status_t wdg_supervise(wdg_t *w, uint32_t now);
const char  *wdg_status_name(wdg_status_t s);

#endif /* WDG_H */
```

```c
/* wdg.c - see wdg.h. */
#include "wdg.h"

void wdg_init(wdg_t *w, void (*refresh)(void))
{
    w->n = 0u;
    w->refresh = refresh;
    w->failed = false;
    w->why = WDG_OK;
    w->who = 0u;
    w->when = 0u;
}

int32_t wdg_register(wdg_t *w, const wdg_entity_cfg_t *cfg)
{
    int32_t id = -1;
    if ((w->n < WDG_MAX_ENTITIES) && (cfg->ncp > 0u) && (cfg->min_alive <= cfg->max_alive)) {
        wdg_entity_t *e = &w->e[w->n];
        e->cfg = cfg;
        atomic_init(&e->alive, 0u);
        atomic_init(&e->flow_errors, 0u);
        atomic_init(&e->deadline_errors, 0u);
        e->next_cp = 0u;
        e->job_start = 0u;
        e->seen_alive = 0u;
        e->seen_flow = 0u;
        e->seen_deadline = 0u;
        id = (int32_t)w->n;
        w->n++;
    }
    return id;
}

/* Called by the supervised entity: cp 0 starts a job, cp ncp-1 completes it. */
void wdg_checkpoint(wdg_t *w, uint32_t id, uint8_t cp, uint32_t now)
{
    if (id >= w->n) {
        return;
    }
    wdg_entity_t *e = &w->e[id];
    if (cp != e->next_cp) {                                  /* skipped or repeated step */
        atomic_fetch_add_explicit(&e->flow_errors, 1u, memory_order_relaxed);
        e->next_cp = 0u;
        if (cp != 0u) {
            return;
        }
    }
    if (cp == 0u) {
        e->job_start = now;
    }
    if (cp + 1u == e->cfg->ncp) {                            /* job complete */
        if ((now - e->job_start) > e->cfg->deadline) {
            atomic_fetch_add_explicit(&e->deadline_errors, 1u, memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&e->alive, 1u, memory_order_release);
        e->next_cp = 0u;
    } else {
        e->next_cp = (uint8_t)(cp + 1u);
    }
}

wdg_status_t wdg_supervise(wdg_t *w, uint32_t now)
{
    wdg_status_t worst = WDG_OK;
    uint32_t who = 0u;
    for (uint32_t i = 0u; i < w->n; i++) {
        wdg_entity_t *e = &w->e[i];
        uint32_t a = atomic_load_explicit(&e->alive, memory_order_acquire);
        uint32_t f = atomic_load_explicit(&e->flow_errors, memory_order_relaxed);
        uint32_t d = atomic_load_explicit(&e->deadline_errors, memory_order_relaxed);
        uint32_t delta = a - e->seen_alive;                  /* wrap-safe */
        wdg_status_t s = WDG_OK;
        if (f != e->seen_flow) {
            s = WDG_FLOW;
        } else if (d != e->seen_deadline) {
            s = WDG_DEADLINE;
        } else if (delta < e->cfg->min_alive) {
            s = WDG_ALIVE_LOW;                               /* hung, starved, or dead */
        } else if (delta > e->cfg->max_alive) {
            s = WDG_ALIVE_HIGH;                              /* runaway loop */
        } else {
            s = WDG_OK;
        }
        e->seen_alive = a;
        e->seen_flow = f;
        e->seen_deadline = d;
        if ((s != WDG_OK) && (worst == WDG_OK)) {
            worst = s;
            who = i;
        }
    }
    if ((worst != WDG_OK) && !w->failed) {
        w->failed = true;                                    /* latch the FIRST failure */
        w->why = worst;
        w->who = who;
        w->when = now;
    }
    if (!w->failed) {
        w->refresh();
    }
    return worst;
}

const char *wdg_status_name(wdg_status_t s)
{
    static const char *const names[] = { "OK", "ALIVE_LOW", "ALIVE_HIGH", "DEADLINE", "FLOW" };
    return ((uint32_t)s < 5u) ? names[s] : "?";
}
```

**Simulated-time test** (three tasks, the supervisor every 100 ms, a hardware watchdog model with a 250 ms timeout and an optional 50 ms window):

```c
/* wdg_test.c - 1 ms simulated time: three periodic tasks, the supervisor every
 * 100 ms, and a hardware watchdog model (timeout 250 ms; optional window:
 * a refresh earlier than 50 ms after the previous one resets, as a window
 * watchdog does). Each scenario injects one failure. */
#include <stdio.h>

#include "wdg.h"

typedef struct {
    uint32_t timeout, window_min, last_kick, kicks, reset_at;
    bool reset;
    const char *reason;
} hwwdt_t;

static hwwdt_t  g_hw;
static uint32_t g_now;

static void hw_refresh(void)
{
    if (g_hw.reset) {
        return;
    }
    if ((g_hw.window_min != 0u) && (g_hw.kicks != 0u) && ((g_now - g_hw.last_kick) < g_hw.window_min)) {
        g_hw.reset = true;
        g_hw.reset_at = g_now;
        g_hw.reason = "window violation (refreshed too early)";
        return;
    }
    g_hw.last_kick = g_now;
    g_hw.kicks++;
}

static void hw_tick(void)
{
    if (!g_hw.reset && ((g_now - g_hw.last_kick) >= g_hw.timeout)) {
        g_hw.reset = true;
        g_hw.reset_at = g_now;
        g_hw.reason = "timeout (starved)";
    }
}

/*                                   name  min max deadline ncp */
static const wdg_entity_cfg_t k_a = { "A",  8u, 12u, 3u, 2u };   /* 10 ms period */
static const wdg_entity_cfg_t k_b = { "B",  1u,  3u, 5u, 3u };   /* 50 ms period */
static const wdg_entity_cfg_t k_c = { "C",  4u,  6u, 0u, 1u };   /* 20 ms period */

typedef enum { HEALTHY, B_HANGS, C_RUNAWAY, A_SKIPS_CP, A_LATE, ISR_KICK, ISR_KICK_WINDOWED } scen_t;

static void run(scen_t sc, const char *title, uint32_t fault_at)
{
    static const char *const names[] = { "A", "B", "C" };
    wdg_t w;
    wdg_init(&w, hw_refresh);
    uint32_t ia = (uint32_t)wdg_register(&w, &k_a);
    uint32_t ib = (uint32_t)wdg_register(&w, &k_b);
    uint32_t ic = (uint32_t)wdg_register(&w, &k_c);
    bool isr = (sc == ISR_KICK) || (sc == ISR_KICK_WINDOWED);
    g_hw = (hwwdt_t){ 250u, (sc == ISR_KICK) ? 0u : 50u, 0u, 0u, 0u, false, "" };

    for (g_now = 0u; (g_now < 10000u) && !g_hw.reset; g_now++) {
        uint32_t t = g_now;
        bool faulted = (fault_at != 0u) && (t >= fault_at);
        /* task A: 10 ms, two checkpoints */
        if ((t % 10u) == 0u && !((sc == A_SKIPS_CP) && (t == fault_at))) { wdg_checkpoint(&w, ia, 0u, t); }
        if ((t % 10u) == 1u && !((sc == A_LATE) && (t == fault_at + 1u))) { wdg_checkpoint(&w, ia, 1u, t); }
        if ((sc == A_LATE) && (t == fault_at + 5u)) { wdg_checkpoint(&w, ia, 1u, t); }
        /* task B: 50 ms, three checkpoints; hangs in the B scenarios */
        bool b_dead = ((sc == B_HANGS) || isr) && faulted;
        if (!b_dead) {
            if ((t % 50u) <= 2u) { wdg_checkpoint(&w, ib, (uint8_t)(t % 50u), t); }
        }
        /* task C: 20 ms, one checkpoint; spins in the runaway scenario */
        if (((sc == C_RUNAWAY) && faulted) || ((t % 20u) == 0u)) { wdg_checkpoint(&w, ic, 0u, t); }
        /* refresh path */
        if (isr) {
            if ((t % 10u) == 0u) { hw_refresh(); }          /* SysTick ISR, unconditional */
        } else if ((t != 0u) && ((t % 100u) == 0u)) {
            (void)wdg_supervise(&w, t);
        }
        hw_tick();
    }
    printf("%-40s ", title);
    if (w.failed) {
        printf("detected %s of %s at %u ms; ", wdg_status_name(w.why), names[w.who], (unsigned)w.when);
    } else if (fault_at != 0u) {
        printf("NOT detected; ");
    }
    if (g_hw.reset) {
        printf("reset at %u ms: %s", (unsigned)g_hw.reset_at, g_hw.reason);
        if ((fault_at != 0u) && (g_hw.reset_at >= fault_at)) {
            printf(" (%u ms after the fault)", (unsigned)(g_hw.reset_at - fault_at));
        } else if (fault_at != 0u) {
            printf(" (before the fault: the refresh pattern itself is illegal)");
        }
    } else {
        printf("no reset in 10 s (%u refreshes)", (unsigned)g_hw.kicks);
    }
    printf("\n");
}

int main(void)
{
    run(HEALTHY,           "healthy system, 10 s",                    0u);
    run(B_HANGS,           "task B hangs at 3037 ms",              3037u);
    run(C_RUNAWAY,         "task C runaway loop from 5013 ms",     5013u);
    run(A_SKIPS_CP,        "task A skips checkpoint 0 at 7020 ms", 7020u);
    run(A_LATE,            "task A job takes 5 ms at 8040 ms",     8040u);
    run(ISR_KICK,          "BUGGY: SysTick refresh, B hangs 3037",  3037u);
    run(ISR_KICK_WINDOWED, "BUGGY: SysTick refresh + window WDT",  3037u);
    return 0;
}
```

**Result (verified, host, under UBSan):**

```
healthy system, 10 s                     no reset in 10 s (99 refreshes)
task B hangs at 3037 ms                  detected ALIVE_LOW of B at 3200 ms; reset at 3350 ms: timeout (starved) (313 ms after the fault)
task C runaway loop from 5013 ms         detected ALIVE_HIGH of C at 5100 ms; reset at 5250 ms: timeout (starved) (237 ms after the fault)
task A skips checkpoint 0 at 7020 ms     detected FLOW of A at 7100 ms; reset at 7250 ms: timeout (starved) (230 ms after the fault)
task A job takes 5 ms at 8040 ms         detected DEADLINE of A at 8100 ms; reset at 8250 ms: timeout (starved) (210 ms after the fault)
BUGGY: SysTick refresh, B hangs 3037     NOT detected; no reset in 10 s (1000 refreshes)
BUGGY: SysTick refresh + window WDT      NOT detected; reset at 10 ms: window violation (refreshed too early) (before the fault: the refresh pattern itself is illegal)
```

Reading the scenarios:

- **Healthy:** 99 refreshes in 10 s, no reset.
- **Every injected failure is detected by its supervision type:**
  - a hang → `ALIVE_LOW`;
  - a runaway loop → `ALIVE_HIGH`, which a "did it check in?" design would never catch;
  - a skipped step → `FLOW`;
  - a slow job → `DEADLINE`.
  Each one is reset 210–313 ms after the fault.
- **The SysTick design** refreshed 1,000 times while task B was dead for 7 seconds. The watchdog proved only that SysTick was alive.
- With a **window** watchdog, the same SysTick design resets within 10 ms: refreshing every 10 ms violates the 50 ms window. The window catches refreshers that are too fast, such as a runaway refresh loop.

**Measuring WCET on target** (the DWT cycle counter, high-water marks):

```c
/* cyccnt.h - cycle-accurate measurement on ARMv7-M/ARMv8-M Mainline with the
 * DWT cycle counter (ARMv7-M ARM C1.8). Measurement gives a LOWER bound on
 * WCET; keep a high-water mark per measured section and report it. */
#ifndef CYCCNT_H
#define CYCCNT_H

#include <stdint.h>

#define DEMCR       (*(volatile uint32_t *)0xE000EDFCu)   /* bit 24 TRCENA          */
#define DWT_CTRL    (*(volatile uint32_t *)0xE0001000u)   /* bit 0 CYCCNTENA        */
#define DWT_CYCCNT  (*(volatile uint32_t *)0xE0001004u)
#define DWT_LAR     (*(volatile uint32_t *)0xE0001FB0u)   /* lock access (some M7 parts) */

static inline void cyccnt_init(void)
{
    DEMCR = DEMCR | (1u << 24);
    DWT_LAR = 0xC5ACCE55u;                       /* unlock where CoreSight locking is implemented */
    DWT_CYCCNT = 0u;
    DWT_CTRL = DWT_CTRL | 1u;
}

static inline uint32_t cyccnt_now(void)
{
    return DWT_CYCCNT;
}

typedef struct { uint32_t max, last, count; } cyc_hwm_t;

static inline void cyc_hwm_update(cyc_hwm_t *h, uint32_t start)
{
    uint32_t d = cyccnt_now() - start;           /* wrap-safe for spans < 2^32 cycles */
    h->last = d;
    h->count++;
    if (d > h->max) {
        h->max = d;
    }
}

#endif /* CYCCNT_H */
```

**The WCET measurement trap:**

```c
/* wcet_demo.c - insertion sort of a 16-sample window (a median filter's front
 * end). Both loops are bounded, so a static WCET exists; whether a
 * measurement campaign ever sees it is another matter. */
#include <stdint.h>

#define WN 16u

void isort16(uint16_t *a);

void isort16(uint16_t *a)
{
    for (uint32_t i = 1u; i < WN; i++) {             /* loop bound: 15               */
        uint16_t key = a[i];
        uint32_t j = i;
        while ((j > 0u) && (a[j - 1u] > key)) {      /* loop bound: i; total <= 120  */
            a[j] = a[j - 1u];
            j--;
        }
        a[j] = key;
    }
}
```

**Codegen (verified — Clang 21.1.0, -O2, Cortex-M7):** note the inner loop unrolled ×4, which is still bounded by `i`.

```asm
isort16:
	push	{r4, r5, r6, lr}
	add.w	r12, r0, #2
	movs	r2, #1
	mov.w	lr, #0
	b	.LBB0_3
.LBB0_1:
	movs	r3, #0
.LBB0_2:
	adds	r2, #1
	add.w	lr, lr, #1
	cmp	r2, #16
	add.w	r12, r12, #2
	strh.w	r1, [r0, r3, lsl #1]
	beq	.LBB0_15
.LBB0_3:
	ldrh.w	r1, [r0, r2, lsl #1]
	mov	r4, r12
	mov	r3, lr
.LBB0_4:
	ldrh	r5, [r4, #-2]
	cmp	r5, r1
	bls	.LBB0_12
	cmp	r3, #0
	strh	r5, [r4]
	beq	.LBB0_1
	ldrh	r5, [r4, #-4]
	cmp	r5, r1
	bls	.LBB0_2
	cmp	r3, #1
	strh	r5, [r4, #-2]
	beq	.LBB0_1
	ldrh	r5, [r4, #-6]
	cmp	r5, r1
	bls	.LBB0_13
	cmp	r3, #2
	strh	r5, [r4, #-4]
	beq	.LBB0_1
	ldrh	r5, [r4, #-8]
	cmp	r5, r1
	bls	.LBB0_14
	subs	r3, #4
	strh	r5, [r4, #-6]
	adds	r6, r3, #1
	sub.w	r4, r4, #8
	bne	.LBB0_4
	b	.LBB0_1
.LBB0_12:
	adds	r3, #1
	b	.LBB0_2
.LBB0_13:
	subs	r3, #1
	b	.LBB0_2
.LBB0_14:
	subs	r3, #2
	b	.LBB0_2
.LBB0_15:
	pop	{r4, r5, r6, pc}
```

```python
"""emu_count.py - execute isort16() from a linked Cortex-M7 ELF in Unicorn on
many inputs; count executed instructions and stores into the array (stores - 15
= inner-loop iterations). Instruction counts are a path-length proxy, NOT
cycles: the M7 dual-issues, predicts branches and has caches and wait states.
usage: emu_count.py wcet.elf"""
import random, sys
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_LR, UC_ARM_REG_SP, UC_CPU_ARM_CORTEX_M7

elf = ELFFile(open(sys.argv[1], "rb"))
fn = {s.name: s["st_value"] for s in elf.get_section_by_name(".symtab").iter_symbols()}["isort16"]
uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
uc.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_M7)
uc.mem_map(0x08000000, 0x10000)
uc.mem_map(0x20000000, 0x10000)
text = elf.get_section_by_name(".text")
uc.mem_write(text["sh_addr"], text.data())            # the function is self-contained
STOP, ARR = 0x0800F000, 0x20000000
cnt = {"ins": 0, "st": 0}
def on_code(u, a, s, d): cnt["ins"] += 1
def on_wr(u, acc, a, s, v, d): cnt["st"] += 1
uc.hook_add(UC_HOOK_CODE, on_code, begin=0x08000000, end=0x0800EFFF)
uc.hook_add(UC_HOOK_MEM_WRITE, on_wr, begin=ARR, end=ARR + 31)

def run(vals):
    uc.mem_write(ARR, b"".join(v.to_bytes(2, "little") for v in vals))
    uc.reg_write(UC_ARM_REG_R0, ARR)
    uc.reg_write(UC_ARM_REG_SP, 0x2000F000)
    uc.reg_write(UC_ARM_REG_LR, STOP | 1)
    cnt["ins"] = cnt["st"] = 0
    uc.emu_start(fn | 1, STOP, count=100000)
    out = [int.from_bytes(uc.mem_read(ARR + 2 * i, 2), "little") for i in range(16)]
    assert out == sorted(vals), "sort is wrong"
    return cnt["ins"], cnt["st"] - 15

rng = random.Random(1)
best = run(list(range(100, 116)))
rand = [run([rng.randrange(65536) for _ in range(16)]) for _ in range(1000)]
worst = run(list(range(115, 99, -1)))
ri = [r[0] for r in rand]
print("isort16, Cortex-M7 code at -O2 (executed instructions; a path-length proxy, not cycles)")
print(f"  sorted input (best case)          {best[0]:4d} instructions, {best[1]:3d} inner iterations")
print(f"  1000 random inputs (seeded)       min {min(ri)}  mean {sum(ri) / len(ri):.1f}  max {max(ri)} instructions, "
      f"max {max(r[1] for r in rand)} inner iterations")
print(f"  reverse-sorted (analytic worst)   {worst[0]:4d} instructions, {worst[1]:3d} inner iterations = 15*16/2")
print(f"  largest random measurement is {100.0 * max(ri) / worst[0]:.1f}% of the true worst case "
      f"(a {100.0 * (worst[0] - max(ri)) / worst[0]:.1f}% underestimate)")
print(f"  all 1002 outputs verified sorted")
```

**Result (verified):**

```
isort16, Cortex-M7 code at -O2 (executed instructions; a path-length proxy, not cycles)
  sorted input (best case)           216 instructions,   0 inner iterations
  1000 random inputs (seeded)       min 372  mean 578.3  max 766 instructions, max 90 inner iterations
  reverse-sorted (analytic worst)    927 instructions, 120 inner iterations = 15*16/2
  largest random measurement is 82.6% of the true worst case (a 17.4% underestimate)
  all 1002 outputs verified sorted
```

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| Field units "freeze" but never reset | Watchdog refreshed from an ISR, or the debug-freeze bit left set in production | Review every refresh call site (exactly one, in the supervisor). Check the DBGMCU freeze configuration in release builds |
| Watchdog resets with no crash record | Lockup, starvation of the supervisor, or a reset during a long flash operation | Reset-cause register at boot; window-watchdog early-warning interrupt writing the record; the supervisor's latched `why/who/when` |
| Reset loop after an OTA update | Deterministic crash at boot | Crash-loop counter + safe mode / rollback (Folder 07 File 04 Q4) |
| Intermittent deadline misses only in the field | WCET measured on the lab's typical inputs only | Drive the analytic worst path (§1.5); high-water marks exported via telemetry; static WCET for the critical ISRs |
| Stack overflow under rare interrupt nesting | Stack sized from typical depth | `-fstack-usage` + call graph + the interrupt-nesting formula (§1.4); MPU guard / PSPLIM; paint the stack with a pattern and read the high-water mark |
| Host-tool checksum disagrees with the device | Plain `char` (D6), `int` width, endianness | Build host tools with the target's ABI flags (`-funsigned-char`), or use `uint8_t` everywhere |
| Analyzer reports thousands of findings | Legacy code base | Baseline, then ratchet (Q5) |

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Where in the firmware do you refresh the watchdog?"

- **L5:** "In a timer interrupt, so it never times out by accident," or "in the main loop."
- **Why L5 fails on real hardware:**
  - The timer-ISR refresh proves only that interrupts work. Verified: task B dead for 7 s, 1,000 refreshes, no reset.
  - The main-loop refresh in an RTOS proves only that the idle path runs.
  - Neither catches a runaway task, a skipped processing step or a missed deadline.
- **L7 principal defense:**
  - One supervisor refreshes, and only while every supervised entity passed **alive** (min *and* max), **deadline** and **program-flow** supervision in the last cycle.
  - The first failure is latched and recorded. The hardware watchdog (independent, ideally windowed) then resets.
  - The supervisor itself is supervised by construction.
  - Verified: four failure types detected, resets 210–313 ms after the fault, and the latency formula derived from `T_sup`, `min_alive` and `T_wdt`.
  - Add: read the reset cause at boot, a crash-loop counter, and an early-warning interrupt for a last-gasp record.

### Q2 🔥 "Your code is MISRA-compliant. Is it safe?"

- **L5:** "Yes, the checker shows zero violations."
- **Why L5 fails:**
  - MISRA defines a **subset in which analysis is tractable**, not a proof of correctness.
  - D4 is *compliant* with Rule 17.7, because the return value is explicitly discarded with `(void)`, and still reads an indeterminate value.
  - D3 has no rule violation a decidable checker can flag: Rule 18.1 is undecidable in general.
  - Approved deviations are legal by definition.
- **L7 defense:**
  - Compliance is one evidence item among several (§0 table).
  - Verified: of six defects, warnings caught 0, the analyzer 1, UBSan 4 (one misleadingly), and one was visible only cross-ABI. D3 was caught by nothing short of a sound analyzer.
  - So: MISRA plus sound analysis on critical modules, plus tests with sanitizers, plus run-time supervision.
  - Review every `(void)` on a status return.

### Q3 "How do you establish the WCET of an ISR on a Cortex-M7?"

- **L5:** "Toggle a GPIO and measure it on a scope over a long test run."
- **Why L5 fails:** A measurement is a lower bound, set by the inputs and the micro-architectural state you happened to produce. Verified: 1,000 random inputs reached only 82.6% of the worst path. Caches, flash wait states, branch prediction and DMA contention add variance that a lab run rarely maximizes.
- **L7 defense:**
  - Make the ISR **analyzable**: bounded loops (Rules 14.2/14.3), no recursion, no dynamic dispatch, and code and data in ITCM/DTCM to remove cache variability.
  - Derive the worst path from loop bounds and drive it in test.
  - Measure with DWT `CYCCNT` high-water marks under worst-case interference (DMA running, cold caches).
  - For certification, use a static tool (aiT) or a hybrid (RapiTime). Add a margin, and monitor deadlines at run time (deadline supervision).

### Q4 "How large must the main stack be?"

- **L5:** "Fill it with a pattern, run the tests, look at the high-water mark, add 50%."
- **Why L5 fails:** The high-water mark sees only the interrupt nesting and paths your tests produced. A rare preemption chain (each level adds its ISR's path plus 32 or 104 B of hardware frame) can exceed it in the field.
- **L7 defense:**
  - Static: `-fstack-usage` per function plus the call graph (no recursion, annotated function pointers), plus Σ over preemption levels of (ISR worst path + hardware frame).
  - Keep the number of preemption levels small (NVIC priority grouping).
  - Then use the painted high-water mark as **confirmation**, not as the method.
  - Guard with the MPU or MSPLIM.
  - Verified on the crash path: 76 B against a 1 KB private stack.

### Q5 "You inherit a legacy codebase; the analyzer reports 4,000 findings. What do you do?"

- **L5:** "Fix them all," or "turn the checker off for legacy code."
- **Why L5 fails:** Fixing everything is unbounded churn that introduces regressions. Turning it off forfeits the evidence.
- **L7 defense:**
  1. **Baseline:** freeze today's findings as accepted debt.
  2. **Zero tolerance for new findings**, gated in CI.
  3. **Triage by class:** Mandatory rules and UB classes (9.1, 12.2, 18.1, 1.3) first, in safety-relevant modules first.
  4. **Ratchet:** the baseline may only shrink.
  5. Record **deviations** for the justified patterns (MMIO, unions for records).
  6. Put **sound analysis** on the modules whose failure is hazardous.
  7. Measure progress in the safety case, not in a finding count.

---

## 5. Invariants Checklist

- [ ] A coding standard (MISRA C:2012/2023) with a GRP, a compliance matrix, and deviation records/permits (MMIO under Rule 11.4, records under 19.2).
- [ ] CI layers: the strict warning set at `-Werror`, a MISRA checker, a path-sensitive analyzer, host unit tests under UBSan, tests built for both the host ABI and the target's (`-funsigned-char` etc.), and sound analysis on critical modules.
- [ ] Every `(void)` on a status return reviewed; no plain `char` for data; arithmetic widened before the operation.
- [ ] No recursion, no VLAs/`alloca`, function pointers annotated. Static worst-case stack per root (main and each ISR level) with the hardware-frame terms. MPU/MSPLIM guards.
- [ ] Loop bounds derivable for every timing-critical function; critical code in TCM; DWT high-water marks exported; the worst path driven in test.
- [ ] One watchdog refresh site: a supervisor with alive (min/max), deadline and program-flow supervision; latched first failure recorded; independent + window hardware watchdog; reset cause and crash-loop counter at boot; debug freeze disabled in production.

## 6. References

1. MISRA, *MISRA C:2012 Guidelines for the use of the C language in critical systems* (3rd ed., Amendments 1–4) and *MISRA C:2023*; *MISRA Compliance:2020*.
2. ISO 26262-6:2018 (software level); IEC 61508-3:2010; RTCA DO-178C and DO-330; IEC 62304:2006+A1:2015.
3. SEI CERT C Coding Standard (EXP34-C, INT30-C, INT34-C, MSC37-C).
4. P. Cousot, R. Cousot, "Abstract Interpretation: A Unified Lattice Model…", POPL 1977; AbsInt Astrée, Polyspace Code Prover, Frama-C EVA documentation.
5. Clang Static Analyzer (`clang --analyze`) and UndefinedBehaviorSanitizer documentation (clang.llvm.org).
6. R. Wilhelm et al., "The Worst-Case Execution-Time Problem: Overview of Methods and Survey of Tools", *ACM TECS* 7(3), 2008; AbsInt aiT; Rapita RapiTime; OTAWA.
7. AUTOSAR, *Specification of Watchdog Manager* (alive, deadline, logical supervision).
8. Arm, *ARMv7-M Architecture Reference Manual*, C1.8 (DWT, CYCCNT) and C1.6 (DEMCR).
9. Folder 01 File 01 (UB and the optimizer), Folder 05 (pools instead of `malloc`), Folder 07 File 01 (TCM placement, MPU), Folder 07 File 04 (crash record, crash-loop protection).
