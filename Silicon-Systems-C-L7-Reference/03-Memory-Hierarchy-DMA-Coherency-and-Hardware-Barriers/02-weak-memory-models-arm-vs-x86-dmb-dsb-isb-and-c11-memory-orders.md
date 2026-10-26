# 02 · Weak Memory Models: ARM vs. x86, `DMB`/`DSB`/`ISB`, and C11 Memory Orders

> **Folder:** `03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/` · **File 2 of 3**
> **Anchors:**
> - Arm ARM (DDI 0487) B2.3 *Definition of the Armv8 memory model* (other-multi-copy-atomic, barrier-ordered-before, dependencies), C6 `DMB`/`DSB`/`ISB`/`LDAR`/`STLR`/`LDAPR`.
> - Arm *Barrier Litmus Tests and Cookbook*; Arm AN321 *Cortex-M Programming Guide to Memory Barrier Instructions*.
> - Sewell et al., *x86-TSO* (CACM 2010).
> - RISC-V Unprivileged ISA ch. 17 *RVWMO*.
> - Pulte et al., *Simplifying ARM Concurrency: Multicopy-Atomic Axiomatic and Operational Models for ARMv8* (POPL 2018).
> - Linux `Documentation/memory-barriers.txt`, `tools/memory-model/`, `arch/arm64/include/asm/barrier.h`.
>
> **Verification:**
> - x86-64 litmus outcomes were **measured** with real threads (one run, author's laptop).
> - ARM/RISC-V allowed outcomes are **architectural**: they're what the formal models (herd7 `aarch64.cat`, RVWMO) permit. They were not measured, because no ARM hardware was available. Run them with litmus7 on your silicon.
> - All instruction sequences are verified Clang 21.1.0 codegen (this file and File 01's matrix).

---

## 0. The thesis

"The order in which I wrote the stores" and "the order in which another observer sees them" are different things. A *memory model* is the contract that says which differences are allowed:

- x86-TSO allows exactly one reordering (store → later load).
- ARMv8 and RISC-V allow almost all reorderings, unless you use dependencies, acquire/release, or barriers.

The L7 skill is to pick the *minimum* ordering that makes a protocol correct on the *weakest* target you ship, and to know which barrier variant (`DMB` vs `DSB`, `ISH` vs `OSH` vs `SY`, `ST`/`LD`) the hardware actually requires.

---

## 1. First-Principles Mechanics

### 1.1 Four models, one table

| Reordering (as seen by another observer) | Sequential consistency | x86-TSO | ARMv8 / AArch64 | RISC-V RVWMO | POWER |
|---|---|---|---|---|---|
| store → later store (different addresses) | ✗ | ✗ | ✅ | ✅ | ✅ |
| load → later load | ✗ | ✗ | ✅ | ✅ | ✅ |
| load → later store | ✗ | ✗ | ✅ | ✅ | ✅ |
| **store → later load** | ✗ | **✅ (store buffer)** | ✅ | ✅ | ✅ |
| Multi-copy atomicity (all others see a store at the same time) | ✅ | ✅ | **Other-MCA** (since the 2017 revision: a store becomes visible to all *other* cores at once) | Other-MCA | ✗ (IRIW observable) |
| Dependencies ordered (address/data) | n/a | n/a | ✅ (address and data dependencies order later accesses; control dependencies order later *stores*) | ✅ (syntactic dependencies) | ✅ |

### 1.2 The canonical litmus tests

```text
SB (store buffering)            MP (message passing)            LB (load buffering)
T0: x = 1;  r0 = y;             T0: data = 1; flag = 1;          T0: r0 = x; y = 1;
T1: y = 1;  r1 = x;             T1: r0 = flag; r1 = data;        T1: r1 = y; x = 1;
Forbidden under SC: r0=r1=0     Bad: r0=1, r1=0                   Bad: r0=r1=1
```

| Test (bad outcome) | SC | x86-TSO | ARMv8, no barriers | ARMv8 with the minimal fix | Minimal fix |
|---|---|---|---|---|---|
| SB `r0 = r1 = 0` | forbidden | **allowed (measured: 94,243 / 200,000)** | allowed | forbidden | full barrier between store and load on both sides: `dmb ish` / `seq_cst` fence (x86: `mfence` or a `lock`ed op, measured 0 / 200,000) |
| MP `flag = 1, data = 0` | forbidden | **forbidden (measured: 0 / 200,000)** | **allowed** | forbidden | writer: `stlr flag` (release) or `dmb ishst` between stores; reader: `ldar flag` (acquire), an address dependency, or `dmb ishld` |
| LB `r0 = r1 = 1` | forbidden | forbidden | allowed (architecturally; rarely observed) | forbidden | a data/address dependency, or acquire on either load |

**One measured run (x86-64; the same `races.c` harness as File 01; inserted verbatim):**

```text
2 threads x 1,000,000 increments: volatile=1024996 (lost 975004)  atomic=2000000
SB no fence (relaxed)     r0,r1 = 0,0:  94243  0,1:  19153  1,0:  83110  1,1:   3494
SB with seq_cst fence     r0,r1 = 0,0:      0  0,1:  49329  1,0:  43236  1,1: 107435
MP no fence (relaxed)     flag,data = 0,0:  75522  0,1:  54449  1,0:      0  1,1:  70029
false sharing, 2 x 20000000 increments: same line 37.4 ms, separate lines 9.6 ms
```

This is the asymmetry behind "works on x86, broken on ARM". x86 *already* gives MP for free, so a missing release/acquire on a flag is invisible in x86 CI and fatal on Cortex-A. Conversely, SB, the pattern at the heart of Dekker/Peterson mutual exclusion and of "store my intent, then read yours" handshakes, fails **even on x86** without a full fence.

### 1.3 Why ARM allows MP: the microarchitecture

1. **Store side.** The writer's two stores go to different cache lines. The store buffer may drain `flag`'s line first: it hits in L1, while `data`'s line misses, or `data` is still waiting for ownership (RFO in flight). Nothing in ARMv8 forces FIFO draining to *different* addresses.
2. **Load side.** The reader's load of `data` may be **satisfied early**, speculatively or out of order, *before* the load of `flag` returns. If `flag` then reads 1, the core doesn't retroactively re-execute the `data` load, because the architecture doesn't require load→load order.
3. **Invalidation side.** The reader's core may have acknowledged the invalidation of `data`'s line but not yet applied it (an invalidation queue), so its read of `data` hits the stale copy.

Each fix targets one of these:
- `STLR` / `DMB ISHST` stops (1).
- `LDAR` / `LDAPR` / `DMB ISHLD` / an address dependency stops (2) and (3) for the reader.

### 1.4 The three ARM barriers, precisely

| Barrier | What it guarantees | Typical mandatory uses |
|---|---|---|
| **`DMB <opt>`** (Data Memory Barrier) | **Ordering** only: explicit memory accesses before the barrier are *observed* (within the shareability domain `opt`) before explicit accesses after it. It doesn't wait for completion and doesn't affect instruction fetch | Inter-core message passing (`ish`); CPU↔DMA ordering of Normal-memory writes vs a doorbell (`oshst`); C11 fences on v7/v8 (verified: `fence_acquire` → `dmb ishld`, `fence_release`/`seq_cst` → `dmb ish`) |
| **`DSB <opt>`** (Data Synchronization Barrier) | **Completion**: no instruction after it executes until all prior memory accesses, **cache maintenance and TLB maintenance** are complete | Before `WFI`/`WFE`, so a pending clear or wake source isn't lost (Folder 01 `cpu_wfi`); after `DC`/`IC`/`TLBI` (File 03, Folder 02 BBM); after writes to MPU/SCB/NVIC registers whose *effect* later code depends on; before `SEV` in some protocols; before triggering a system reset (`AIRCR.SYSRESETREQ`, as CMSIS `NVIC_SystemReset` does) |
| **`ISB`** (Instruction Synchronization Barrier) | **Context synchronization**: flushes the pipeline, so later instructions are fetched and decoded under the new context | After `MSR CONTROL`, `CPACR`, `VTOR`, MPU enable (with a `DSB` first); after enabling the MMU or changing `SCTLR`/`TCR`/`TTBR` (verified `mmu_enable_el1`, Folder 02); after `IC IVAU` + `DSB` when executing new code (§2.3); after `MSR BASEPRI` when the new mask must apply to the very next instruction |

**`DMB`/`DSB` option field.** It combines a domain with an access type:

| Option | Domain | Accesses ordered |
|---|---|---|
| `SY` | Full system | All |
| `ISH` | Inner Shareable: CPUs in the same OS image | All |
| `ISHST` | Inner Shareable | Stores only |
| `ISHLD` | Inner Shareable | Loads → later loads and stores |
| `OSH` / `OSHST` / `OSHLD` | Outer Shareable: includes DMA-capable masters on many SoCs | All / stores / loads |
| `NSH` | Non-shareable: the local core | All |

On **M-profile** only `SY` is defined, and compilers emit `dmb sy` for everything (verified matrix).

### 1.5 Acquire/release instructions: one-sided barriers

`STLR` (store-release) orders *all earlier* accesses before the store. `LDAR` (load-acquire) orders the load before *all later* accesses. Each is a barrier on one side only, which is cheaper than a full `DMB`. That's the hardware embodiment of C11 release/acquire.

- `LDAR` is **RCsc**: it also can't pass an earlier `STLR`, which is what `seq_cst` needs.
- `LDAPR` (FEAT_LRCPC) is **RCpc**, which is enough for `acquire` (verified: v8.4 acquire → `ldapr`, `seq_cst` → `ldar`).
- RISC-V expresses the same with `.aq`/`.rl` bits on AMOs and LR/SC (verified `amoadd.w.aqrl`, `lr.w.aq`/`sc.w.rl`), and with `fence r,rw` / `fence rw,w` around plain loads and stores (verified).

### 1.6 Dependencies, and why `memory_order_consume` died

On ARM, a load whose **address** depends on the value of an earlier load is ordered after it, with no barrier needed. Linux exploits this for RCU: `rcu_dereference` → `READ_ONCE` + address dependency. C11 tried to expose this as `memory_order_consume`. But compilers can't reliably preserve dependencies through optimization (they may turn `p[x - x]` into `p[0]`), so **every major compiler promotes `consume` to `acquire`**. Linux keeps its own dependency rules (`tools/memory-model`) and relies on `READ_ONCE` plus compiler discipline. Portable C code: use `acquire`.

### 1.7 Cortex-M specifics (AN321, condensed)

- A single Cortex-M core observes its own accesses in program order, so no barriers are needed *within one core*, except the context-synchronization cases.
- **Other bus masters** (DMA, a second core, a debugger) can observe Normal-memory accesses reordered or merged by the write buffer and the bus matrix. Use `DMB` before the access that publishes data to them.
- `CPSID i` takes effect immediately, so no `ISB` is needed for the interrupt mask itself. `MSR BASEPRI` should be followed by `ISB` if the next instruction must already run with the new priority (plus the M7 r0p1 erratum: Folder 01, File 03).
- **`DSB` after clearing an interrupt source before exiting an ISR.** On parts where the peripheral sits behind a buffered APB bridge, the clear may not have reached the peripheral when the core unstacks and re-evaluates pending interrupts. The ISR then re-enters. Folder 06, File 01 has the full bus-level explanation; the fix is a `DSB` or a dummy read-back of the peripheral.
- After writing `VTOR`, `CPACR`, `MPU_CTRL` or `CONTROL`: `DSB` + `ISB` (verified in every Folder 02 startup listing).

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way: x86-correct, ARM-broken

```c
/* ring_flag_bad.c - a "lock-free" single-producer/single-consumer hand-off
 * written and tested on x86. Correct under TSO, broken under ARMv8/RVWMO. */
#include <stdint.h>

typedef struct {
    uint32_t          len;
    uint8_t           data[60];
    volatile uint32_t full;          /* 0 = empty, 1 = full */
} mailbox_t;

void mbox_put(mailbox_t *m, const uint8_t *src, uint32_t n);
void mbox_put(mailbox_t *m, const uint8_t *src, uint32_t n)
{
    while (m->full != 0u) { }
    for (uint32_t i = 0u; i < n && i < 60u; i++) { m->data[i] = src[i]; }
    m->len  = n;
    m->full = 1u;                    /* ARM: may become visible before data/len */
}

uint32_t mbox_get(mailbox_t *m, uint8_t *dst);
uint32_t mbox_get(mailbox_t *m, uint8_t *dst)
{
    while (m->full == 0u) { }
    uint32_t n = m->len;             /* ARM: may be satisfied before 'full' was read */
    for (uint32_t i = 0u; i < n && i < 60u; i++) { dst[i] = m->data[i]; }
    m->full = 0u;                    /* ARM: may become visible before the data reads complete */
    return n;
}
```

Three distinct reorderings break it on ARM:
1. `full = 1` overtakes `data`/`len` (store→store).
2. The consumer's `len`/`data` loads overtake its `full` load (load→load).
3. The consumer's `full = 0` overtakes its own `data` reads (load→store), so the producer overwrites data the consumer hasn't read yet.

On x86 TSO, none of the three is allowed. Hence it "works".

### 2.2 The Silicon-Hardened Production Way: release/acquire on both hand-offs

```c
/* ring_flag_good.c - the same mailbox with the minimal correct ordering:
 * release publishes, acquire consumes, in BOTH directions. */
#include <stdatomic.h>
#include <stdint.h>

typedef struct {
    uint32_t         len;
    uint8_t          data[60];
    _Atomic uint32_t full;
} mailbox_t;

void mbox_put(mailbox_t *m, const uint8_t *src, uint32_t n);
void mbox_put(mailbox_t *m, const uint8_t *src, uint32_t n)
{
    while (atomic_load_explicit(&m->full, memory_order_acquire) != 0u) { }  /* consumer done reading */
    for (uint32_t i = 0u; i < n && i < 60u; i++) { m->data[i] = src[i]; }
    m->len = n;
    atomic_store_explicit(&m->full, 1u, memory_order_release);              /* data/len before full */
}

uint32_t mbox_get(mailbox_t *m, uint8_t *dst);
uint32_t mbox_get(mailbox_t *m, uint8_t *dst)
{
    while (atomic_load_explicit(&m->full, memory_order_acquire) == 0u) { }  /* full before data/len */
    uint32_t n = m->len;
    for (uint32_t i = 0u; i < n && i < 60u; i++) { dst[i] = m->data[i]; }
    atomic_store_explicit(&m->full, 0u, memory_order_release);              /* reads before 'empty' */
    return n;
}
```

The "empty" hand-off (consumer → producer) needs the same release/acquire pair as the "full" hand-off. That second direction is the one most often forgotten. Folder 05 generalizes this into SPSC and MPMC rings with head and tail indices.

### 2.3 Barriers at the CPU↔device and CPU↔instruction-fetch boundaries (verified)

```c
/* barriers_a64.c - the Linux arm64 barrier vocabulary, and two sequences that
 * need it: publishing a DMA descriptor, and making freshly written code
 * executable (JIT, module loading, firmware patching). */
#include <stddef.h>
#include <stdint.h>

/* arch/arm64/include/asm/barrier.h equivalents */
#define dma_wmb()  __asm__ volatile("dmb oshst" : : : "memory")   /* CPU->device ordering, normal memory  */
#define dma_rmb()  __asm__ volatile("dmb oshld" : : : "memory")
#define smp_mb()   __asm__ volatile("dmb ish"   : : : "memory")   /* CPU<->CPU                           */
#define wmb()      __asm__ volatile("dsb st"    : : : "memory")   /* completion, incl. device memory     */

static inline void writel(uint32_t v, volatile uint32_t *reg)     /* Linux writel(): __iowmb(); store */
{
    dma_wmb();
    *reg = v;
}

typedef struct {
    uint64_t addr;
    uint32_t len;
    volatile uint32_t ctrl;          /* bit 31 = OWN (device may consume) */
} desc_t;

void publish_desc(desc_t *d, uint64_t buf, uint32_t len, volatile uint32_t *doorbell, uint32_t tail);
void publish_desc(desc_t *d, uint64_t buf, uint32_t len, volatile uint32_t *doorbell, uint32_t tail)
{
    d->addr = buf;                   /* 1. fill the descriptor (Normal memory, coherent DMA pool) */
    d->len  = len;
    dma_wmb();                       /* 2. fields visible to the device BEFORE ownership flips    */
    d->ctrl = 0x80000000u;           /* 3. hand over                                              */
    writel(tail, doorbell);          /* 4. doorbell: its own barrier orders it after the OWN store */
}

/* Make [p, p+n) executable after writing instructions with data stores. */
void sync_icache(const void *p, size_t n, unsigned dline, unsigned iline);
void sync_icache(const void *p, size_t n, unsigned dline, unsigned iline)
{
    uintptr_t a, end = (uintptr_t)p + n;
    for (a = (uintptr_t)p & ~(uintptr_t)(dline - 1u); a < end; a += dline) {
        __asm__ volatile("dc cvau, %0" : : "r"(a) : "memory");   /* clean D to Point of Unification */
    }
    __asm__ volatile("dsb ish" : : : "memory");
    for (a = (uintptr_t)p & ~(uintptr_t)(iline - 1u); a < end; a += iline) {
        __asm__ volatile("ic ivau, %0" : : "r"(a) : "memory");   /* invalidate I to PoU            */
    }
    __asm__ volatile("dsb ish\n\tisb" : : : "memory");          /* this core refetches             */
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-none-elf`):**

```asm
publish_desc:
	mov	w8, #-2147483648
	str	x1, [x0]
	str	w2, [x0, #8]
	dmb	oshst
	str	w8, [x0, #12]
	dmb	oshst
	str	w4, [x3]
	ret
sync_icache:
	sub	w9, w2, #1
	add	x8, x1, x0
	bic	x9, x0, x9
	cmp	x9, x8
	b.hs	.LBB1_3
	mov	w10, w2
.LBB1_2:
	dc	cvau, x9
	add	x9, x9, x10
	cmp	x9, x8
	b.lo	.LBB1_2
.LBB1_3:
	sub	w9, w3, #1
	dsb	ish
	bic	x9, x0, x9
	cmp	x9, x8
	b.hs	.LBB1_6
	mov	w10, w3
.LBB1_5:
	ic	ivau, x9
	add	x9, x9, x10
	cmp	x9, x8
	b.lo	.LBB1_5
.LBB1_6:
	dsb	ish
	isb
	ret
```

- **`publish_desc`:**
  1. Fill the fields (`str x1`, `str w2`).
  2. **`dmb oshst`** (`dma_wmb()`): the fields are observable by the device before …
  3. … `str w8` sets OWN.
  4. `writel`'s own **`dmb oshst`** orders the OWN store before the doorbell `str w4, [x3]`.
  
  Why **`OSH`** rather than `ISH`? DMA masters are in the outer-shareable domain on typical SoCs. Why **`DMB`**, not `DSB`? Only *order* is needed, not completion: the device will see the doorbell after the descriptor. Linux arm64 implements `dma_wmb()` as exactly `dmb oshst`, and `writel()` as `dma_wmb()` + `str`. If the descriptor lived in *non-coherent cached* memory, a `DC CVAC` clean would be needed too (File 03).
- **`sync_icache`:** the architectural sequence for executing code written as data (JIT, module loader, a firmware patcher):
  1. `DC CVAU` per D-line (clean to the Point of Unification);
  2. `DSB ISH`;
  3. `IC IVAU` per I-line;
  4. `DSB ISH`;
  5. `ISB`.
  
  Other cores must also execute an `ISB` (or take an exception) before running the new code. Cores reporting `CTR_EL0.IDC`/`DIC` (Folder 01, File 02) can skip the D-clean or the I-invalidate. Line sizes must come from `CTR_EL0` (`DminLine`/`IminLine`), never a constant.

### 2.4 The Linux barrier vocabulary on arm64

| Linux primitive | arm64 implementation | Use |
|---|---|---|
| `smp_mb()` | `dmb ish` | Full ordering between CPUs |
| `smp_rmb()` | `dmb ishld` | Load→load between CPUs |
| `smp_wmb()` | `dmb ishst` | Store→store between CPUs |
| `smp_load_acquire()` / `smp_store_release()` | `ldar` / `stlr` | One-sided |
| `dma_rmb()` / `dma_wmb()` | `dmb oshld` / `dmb oshst` | CPU ↔ coherent DMA memory ordering |
| `rmb()` / `wmb()` / `mb()` | `dsb ld` / `dsb st` / `dsb sy` | Completion, including against Device memory |
| `writel()` / `readl()` | `dma_wmb()` + `str` / `ldr` + `dma_rmb()`-like ordering | MMIO with ordering |
| `writel_relaxed()` / `readl_relaxed()` | plain `str` / `ldr` | MMIO with no ordering vs Normal memory |
| `READ_ONCE()` / `WRITE_ONCE()` | volatile access | No tearing or merging; *no* hardware ordering |

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| Rare corruption in a hand-off on ARM, never on x86 | Missing release/acquire (MP/LB) | Reduce to a litmus test. Ask **herd7** whether the bad outcome is allowed (`herd7 -model aarch64.cat test.litmus`), then run **litmus7** on the board to measure it |
| Mutual-exclusion handshake (`flag[me]=1; if (!flag[other])`) fails on x86 too | SB reordering (verified on x86: 94,243 / 200,000) | Full fence between the store and the load, or use an atomic RMW |
| Device reads stale descriptor fields | Missing `dma_wmb()` before OWN or the doorbell, *or* the descriptor is cached and not cleaned | AXI bus trace: the doorbell write precedes the descriptor writeback. Check the page and MPU attributes |
| Core sleeps forever after `WFI` | An interrupt-clear or event-flag write not completed before `WFI` | Add `dsb sy` before `wfi` (verified `cpu_wfi`); check the wake source in the NVIC/GIC |
| ISR re-enters immediately (spurious second interrupt) | Clear not yet at the peripheral when the ISR exits (buffered bridge) | `dsb` or a read-back of the cleared register before returning (Folder 06) |
| New code executes old instructions after a patch | Missing `DC CVAU` / `IC IVAU` / `ISB`, or wrong line size | Disassemble the patch routine; check `CTR_EL0` |
| MPU or `CONTROL` change "doesn't take effect" for a few instructions | Missing `DSB`/`ISB` context synchronization | Step at the instruction level in TRACE32; insert the barrier |

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "What is the difference between `DMB`, `DSB` and `ISB`? Give a case where each is the *only* correct choice."

- **L5:** "`DMB` orders memory, `DSB` waits for memory, `ISB` flushes the pipeline."
- **Why L5 fails:** The definitions are fine, but the L5 answer can't pick one. Common errors: using `DSB` everywhere (correct but slow in hot paths), or `DMB` before `WFI` (wrong, because ordering doesn't guarantee the clear completed), or forgetting that `DMB` doesn't order instruction fetch.
- **L7 defense:**
  - **`DMB` only:** an SPSC ring publish between cores (`dmb ish`, or `stlr`), and a descriptor → doorbell (`dmb oshst`, verified `publish_desc`).
  - **`DSB` required:** before `WFI` (the clear must *complete*); after `DC`/`TLBI` before relying on the effect; before `SYSRESETREQ`.
  - **`ISB` required:** after `MSR CONTROL`/`CPACR`/`VTOR`/MPU enable, after enabling the MMU, and after `IC IVAU` (verified `sync_icache` and `mmu_enable_el1`).
  - Also name the option domains (`ISH` for CPUs, `OSH` for DMA, `SY` on M-profile).

### Q2 🔥 "Your lock-free hand-off passes a billion iterations on x86 and fails on Graviton/Ampere. Explain."

- **L5:** "ARM has a weaker memory model; add barriers."
- **Why L5 fails:** "Add barriers" isn't a design. Which reordering? Where is the minimum fix?
- **L7 defense:** Identify the pattern as **MP**: forbidden by TSO (measured 0 / 200,000 on x86), allowed by ARMv8. Then:
  - the publisher uses a release store (`stlr`);
  - the consumer uses an acquire load (`ldar`, or `ldapr` with RCpc);
  - **both** directions of a two-way hand-off need it (§2.2);
  - prove it with herd7 and litmus7;
  - add an ARM64 CI runner.
  
  Explain the microarchitecture (§1.3: non-FIFO store draining, early-satisfied loads, invalidation queues), so the fix is understood, not cargo-culted.

### Q3 "Why did Linux pick `dmb oshst` for `dma_wmb()` and not `dsb st`?"

- **L5:** "Because it's faster."
- **Why L5 fails:** True, but the reason it's *sufficient* is the point. `dma_wmb()` must ensure that a device observing the later write (OWN bit or doorbell) also observes the earlier writes. That's an *ordering* property in the outer-shareable domain, which is what `DMB OSHST` gives. `DSB` additionally waits for completion, and nothing in the protocol needs completion.
- **L7 defense:** Map each Linux primitive to its guarantee (§2.4). `wmb()` (= `dsb st`) is used when completion matters, e.g. before an operation the device performs outside the normal memory system. `writel_relaxed` drops even the ordering, for back-to-back register writes to the same device, which Device-nGnRE already keeps in order. Use it carefully.

### Q4 🧊 "Is ARMv8 multi-copy atomic? Why does it matter?"

- **L5:** "Yes, it's like x86."
- **Why L5 fails:** ARMv8 is **other-multi-copy-atomic**, a property introduced in the 2017 revision of the architecture. Once a store is visible to any *other* core, it's visible to all of them. The writing core may see its own store early, through forwarding. ARMv7 and POWER are non-MCA: two readers can disagree about the order of two independent writes (IRIW). This simplifies reasoning and made the axiomatic model tractable (Pulte et al., POPL 2018). It does *not* give MP or SB for free.
- **L7 defense:** Explain the IRIW test, why OMCA forbids its weird outcome while MP is still allowed, and why portable code (ARMv7 still ships in Cortex-A7/A9 parts) must not rely on MCA. Use `seq_cst` only where IRIW-style reasoning actually matters.

### Q5 "When is `memory_order_seq_cst` actually needed instead of acquire/release?"

- **L5:** "Always use `seq_cst` to be safe."
- **Why L5 fails:** `seq_cst` costs a full barrier on some stores (verified: x86 `xchg`; M7 `dmb; str; dmb`; RISC-V `fence rw,w; sw; fence rw,rw`). Most protocols (MP, rings, locks) are correct with acquire/release.
- **L7 defense:** `seq_cst` (or a `seq_cst` fence) is needed for **SB-shaped** protocols, where each side stores its own flag and then reads the other's: Dekker, Peterson, some hazard-pointer and epoch schemes, "set my state, then check for a waiter" sleep/wake races. Verified on x86: SB without a fence fails 94,243 times in 200,000; with a `seq_cst` fence, 0. Everything else uses acquire/release, and the choice is documented in comments.

### Q6 "Write the barrier sequence for executing code you just copied into RAM on a Cortex-A, and on a Cortex-M7."

- **L5:** "`ISB` after copying."
- **Why L5 fails:** The new instructions are in the **D-cache** (written as data). The I-cache may hold stale lines for those addresses. `ISB` flushes only the pipeline.
- **L7 defense:**
  - **Cortex-A:** `DC CVAU` on each D-line → `DSB ISH` → `IC IVAU` on each I-line → `DSB ISH` → `ISB` (verified listing), with line sizes taken from `CTR_EL0`, and an `ISB` on other cores that may execute it.
  - **Cortex-M7:** `SCB_CleanDCache_by_Addr` → `DSB` → `SCB_InvalidateICache` (`ICIALLU`) → `DSB` → `ISB`. Or copy into **ITCM**, which is not cached, so `DSB` + `ISB` suffice (Folder 02 crt0).

---

## 5. Invariants Checklist

- [ ] Every cross-core hand-off has a named ordering: release/acquire for MP-shaped, `seq_cst` (fence) only for SB-shaped; both directions of two-way hand-offs covered.
- [ ] Barrier variant chosen deliberately: `DMB` for order, `DSB` for completion, `ISB` for context; `ISH` for CPUs, `OSH` for DMA, `SY` on M-profile.
- [ ] `DSB` before `WFI`/`WFE`, after cache/TLB maintenance, before system reset; `DSB`+`ISB` after `CONTROL`/`CPACR`/`VTOR`/MPU/MMU changes.
- [ ] Descriptor publish: fields → `dma_wmb()` → OWN → doorbell via `writel()` (or explicit `dmb oshst`).
- [ ] Code modification: `DC CVAU` → `DSB ISH` → `IC IVAU` → `DSB ISH` → `ISB`, with line sizes from `CTR_EL0`.
- [ ] `memory_order_consume` is not used (it is promoted to acquire); kernel code uses `READ_ONCE` + LKMM rules.
- [ ] Protocols proven with herd7 against `aarch64.cat`/RVWMO and exercised with litmus7 on target silicon; ARM64 in CI.

## 6. References

1. Arm, *Arm Architecture Reference Manual for A-profile* (DDI 0487), B2.3 memory model, C6.2 `DMB`/`DSB`/`ISB`/`LDAR`/`STLR`/`LDAPR`; *Arm Barrier Litmus Tests and Cookbook* (PRD03-GENC-007826).
2. Arm Application Note 321, *ARM Cortex-M Programming Guide to Memory Barrier Instructions*.
3. P. Sewell, S. Sarkar, S. Owens, F. Zappa Nardelli, M. Myreen, *x86-TSO: A Rigorous and Usable Programmer's Model for x86 Multiprocessors*, CACM 53(7), 2010.
4. C. Pulte, S. Flur, W. Deacon, J. French, S. Sarkar, P. Sewell, *Simplifying ARM Concurrency*, POPL 2018.
5. RISC-V International, *The RISC-V Instruction Set Manual, Volume I*, ch. *RVWMO Memory Consistency Model*.
6. J. Alglave, L. Maranget, P. E. McKenney, A. Parri, A. Stern, *Frightening Small Children and Disconcerting Grown-ups: Concurrency in the Linux Kernel*, ASPLOS 2018 (LKMM); herdtools7.
7. Linux: `Documentation/memory-barriers.txt`, `arch/arm64/include/asm/barrier.h`, `arch/arm64/include/asm/io.h`.
