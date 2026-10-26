# 02 · A Cache-Coherent Scatter-Gather DMA Ping-Pong Driver in C

> **Folder:** `07-Production-Embedded-C-Code-Blueprints/` · **File 2 of 4**
> **Anchors:**
> - Arm *ARMv7-M Architecture Reference Manual* (DDI 0403E) A3.7 memory access ordering: Device vs Normal accesses and DMB. Arm *ARMv8-A ARM* (DDI 0487) B2.3 for the A-profile equivalent.
> - Arm *Cortex-M7 TRM* (DDI 0489): by-address cache maintenance (DCIMVAC, DCCMVAC) and line size.
> - Linux `Documentation/memory-barriers.txt` (`dma_wmb()`, `dma_rmb()`, and the barriers implied by `writel()`/`readl()`).
> - Linux `Documentation/core-api/dma-api.rst` and `dma-api-howto.rst` (streaming vs coherent mappings, ownership).
> - `arch/arm64/include/asm/io.h` (`__iowmb()`, `__iormb()`).
> - Descriptor-ring designs of real engines (Arm PL330, Synopsys DesignWare eDMA/GMAC, Intel e1000 legacy descriptors). The descriptor layout below is generic, not a specific IP's ⚠ verify against your engine's TRM.
>
> **Verification:**
> - `sgdma.c` and `sgdma_plat_m7.c` compile warning-free for Cortex-M7, Cortex-M33 and AArch64 (bare-metal) under the full warning set.
> - The driver was run on the host against a **behavioral DMA-engine model**. The model has an OWN-bit protocol, W1C status, a level-sensitive interrupt line, stall-on-no-buffer, and bus addresses offset from CPU addresses (`0x3000_0000 + offset`), so any CPU/bus address confusion faults the model.
> - Workloads: fast and slow consumers, an unaligned four-fragment gather, and **interrupt coalescing** (two completions, one interrupt).
> - The buggy driver was run on the same coalescing workload.
> - All outputs and listings are inserted verbatim.

---

## 0. The thesis

A DMA driver is an **ownership protocol between two bus masters** that share neither a cache nor a notion of "now". It fails in three independent ways, and each needs its own mechanism:

1. **Ordering.** The engine must never see the ownership bit before the fields it guards, and the CPU must never read data before it has seen the ownership bit. This is about barriers, *plus* the compiler.
2. **Visibility.** CPU caches must neither hide the engine's writes nor overwrite them with stale lines. This is about line-exact cache maintenance, or a non-cacheable window.
3. **Event accounting.** Interrupts are *level summaries*, not messages: two completions can be one interrupt, and a careless status clear can erase a third. This is about drain loops and exact W1C.

The driver below handles all three. The verified coalescing test shows that a driver getting only (3) wrong still passes a bench test and strands the last block of every burst.

---

## 1. First-Principles Mechanics

### 1.1 The ownership protocol

Each descriptor occupies one cache line (`alignas(32)`, statically asserted). `ctrl[31]` is **OWN**.

| State | OWN | Who may write the descriptor | Who may touch the buffer | Transition |
|---|---|---|---|---|
| Armed | 1 | Engine only | Engine only (writing) | Engine finishes → writes `status`, clears OWN, raises DONE |
| Completed | 0 | CPU (ISR) | CPU, after `rmb` + invalidate | ISR marks it ready; the consumer `take`s it |
| Held | 0 | CPU | Consumer | Consumer `release`s it → re-armed (OWN = 1) + doorbell |

The two ping-pong descriptors point at each other (`next`), forming a two-entry circular chain. If the engine reaches a descriptor it does not own, it **stalls** (raises STALL and drops incoming data). That is an overrun, and it is counted, never silent.

### 1.2 Four orderings, four barriers (and what Linux hides in `writel`/`readl`)

| # | Must be observed in this order | Memory types | Barrier here | Linux equivalent |
|---|---|---|---|---|
| a | Descriptor fields (`buf`, `next`, `status`) → OWN = 1 | Normal → Normal (NC or cached) | `plat->wmb()` | `dma_wmb()` |
| b | OWN = 1 → doorbell register write | Normal → **Device** | `plat->wmb()` before the doorbell | hidden in `writel()` (`__iowmb()`) |
| c | Interrupt status read → descriptor reads | **Device** → Normal | `plat->rmb()` after the read | hidden in `readl()` (`__iormb()`) |
| d | OWN observed = 0 → `status` and buffer reads | Normal → Normal | `plat->rmb()` | `dma_rmb()` |

Rows (b) and (c) are the ones bare-metal code forgets. The Arm architecture orders Device accesses **only with respect to other Device accesses**. A Normal-memory store (the OWN bit) and a later Device store (the doorbell) may be observed in either order unless a DMB separates them. If the doorbell overtakes OWN, the engine re-fetches the descriptor, still sees OWN = 0, and stalls again.

Linux builds this barrier into every `writel()`. That's why driver authors who move from Linux to bare metal lose it. Draft one of this driver had the same hole in `sg_pp_release`; the listing in §2.2 shows the fixed sequence.

The **compiler** is the fifth party. The descriptor lives in ordinary memory, so its fields are plain C objects, and the compiler may narrow, widen, merge or tear accesses to them. The listings show it narrowing reads to `ldrb`/`ldrh` (§2.2): harmless for Normal memory, and exactly why registers are `volatile`.

The **ownership word** is the hand-off point. It is accessed only through a `volatile` lvalue (`OWN_WORD()`), so every hand-off is exactly one untorn 32-bit access, even if the platform layer is later inlined. This is `WRITE_ONCE`/`READ_ONCE`.

### 1.3 Visibility: why invalidate **twice** for RX, and never on a partial line

For a buffer that the engine writes (RX) and that is cacheable:

1. **Before arming:** invalidate. Dirty lines left from the CPU's last use of the buffer could otherwise be *evicted on top of* the engine's fresh data at any later moment.
2. **After completion** (after observing OWN = 0 and `rmb`): invalidate again. While the engine was writing, the CPU may have *speculatively refilled* lines from the buffer, prefetching stale memory.

For TX (the engine reads), **clean** the fragments before handing them over. Cleaning a partially covered line is safe: it writes back the neighbor's data too, but doesn't discard it.

**Invalidating** a partially covered line is the neighbor-line disaster (Folder 03 File 03): it discards the CPU's unrelated dirty data that shares the line. The platform layer therefore **refuses** non-line-exact invalidates (verified: `invalidate ok/rejected = …/0`, and every buffer and descriptor is line-exact by construction).

On the File 01 board, all DMA memory is in the MPU **Normal-NC** window (D2 SRAM), so maintenance is a no-op there. The calls stay in the driver, and the code remains correct if a buffer ever moves to cacheable RAM. `sgdma_plat_m7.c` checks the address window and does real by-address maintenance outside it.

### 1.4 Event accounting

- **W1C exactly what you read.** `STATUS = st & KNOWN_BITS`, never `STATUS = 0xFFFFFFFF`. An event latched *between* your read and your write is otherwise erased.
- **Drain, don't count.** One interrupt may summarize several completions (coalescing; masked interrupts; level-sensitive lines). The ISR walks descriptors in order until it meets one the engine still owns, or one not yet released.
- **Read back before returning** (`(void)STATUS`). On posted-write buses the clear may still be in flight when the exception returns, and the NVIC re-samples the still-high line: the spurious double interrupt of Folder 06 File 01.
- **STALL is an overrun counter**, not an error to ignore.

### 1.5 TX gather chains: publish backwards

`sg_tx_submit()` fills every descriptor with OWN = 0, issues `wmb`, then sets OWN **from the last descriptor to the first**, cleaning each one. A running engine that reaches descriptor *k* through `next` therefore always finds *k*+1…*n* already complete. Publishing forwards opens a window where the engine follows `next` into a descriptor whose fields are not yet written.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

A first driver that passes the "send one block, see one interrupt" bench test:

```c
/* sgdma_bad.c - the same API as sgdma.c, written the way most first drivers
 * are. Compiles warning-free; passes a one-block-at-a-time bench test. */
#include "sgdma.h"

static void arm_rx(sg_pingpong_t *pp, uint32_t i)
{
    sg_desc_hw_t *d = &pp->desc[i].hw;
    d->ctrl = SG_OWN | SG_IRQ | PP_BYTES;              /* BUG 1: ownership handed over FIRST:
                                                        *  a running engine can fetch stale
                                                        *  buf/next                         */
    d->buf = pp->plat->to_bus(pp->buf[i]);
    d->next = pp->plat->to_bus(&pp->desc[i ^ 1u].hw);
    d->status = 0u;                                    /* BUG 2: no buffer invalidate before
                                                        *  arming, no wmb, no clean         */
}

int sg_pp_start(sg_pingpong_t *pp)
{
    pp->next_done = 0u;
    pp->ready_mask = 0u;
    arm_rx(pp, 1u);
    arm_rx(pp, 0u);
    pp->regs->DESC = pp->plat->to_bus(&pp->desc[0].hw);
    pp->regs->CTRL = SGR_RUN;
    return 0;
}

void sg_pp_isr(sg_pingpong_t *pp)
{
    pp->regs->STATUS = 0xFFFFFFFFu;                    /* BUG 3: clears ALL latched events,
                                                        *  including ones raised after entry */
    sg_desc_hw_t *d = &pp->desc[pp->next_done].hw;
    if ((d->ctrl & SG_OWN) == 0u) {                    /* BUG 4: ONE completion per interrupt:
                                                        *  coalesced completions are stranded */
        pp->ready_mask |= 1u << pp->next_done;          /* BUG 5: no rmb, no invalidate      */
        pp->completed++;
        pp->next_done ^= 1u;
    }
}

int sg_pp_take(sg_pingpong_t *pp, uint32_t *idx, uint32_t *len)   /* same as sgdma.c */
{
    uint32_t cand;
    if (pp->ready_mask == 3u) {
        cand = pp->next_done;
    } else if (pp->ready_mask != 0u) {
        cand = (pp->ready_mask == 1u) ? 0u : 1u;
    } else {
        return -1;
    }
    *idx = cand;
    *len = pp->desc[cand].hw.status & SG_LEN;
    return 0;
}

void sg_pp_release(sg_pingpong_t *pp, uint32_t idx)
{
    pp->ready_mask &= ~(1u << idx);
    arm_rx(pp, idx);
    pp->regs->DOORBELL = 1u;
}
```

BUG 1, 2 and 5 are ordering and visibility defects that a sequential model cannot exhibit. They need concurrent hardware: a running engine for BUG 1, cacheable buffers for BUG 2 and 5. BUG 3 and 4 are about **event accounting**, and they *are* observable.

The coalescing workload: in every burst the engine completes **both** buffers while interrupts are masked (a long critical section), so the two completions arrive as one interrupt. Then the line goes quiet.

```c
/* sgdma_coalesce_test.c - interrupt coalescing: in every burst the engine
 * completes BOTH ping-pong buffers while the CPU has interrupts masked, so two
 * completions arrive as ONE latched interrupt; then the line goes quiet.
 * A correct driver delivers everything the engine finished before the quiet
 * period. Link with sgdma.c (production) or sgdma_bad.c. */
#include <stdio.h>
#include <string.h>

#include "sgdma.h"

#define BUS_BASE 0x30000000u
#define BURSTS   100u

static alignas(SG_LINE) uint8_t arena[4096];
static bus_addr_t to_bus(const void *p) { return BUS_BASE + (bus_addr_t)((const uint8_t *)p - arena); }
static void *to_virt(bus_addr_t b) { return &arena[b - BUS_BASE]; }
static void clean(const void *p, size_t n) { (void)p; (void)n; }
static bool invalidate(void *p, size_t n) { (void)p; (void)n; return true; }
static void barrier(void) { __asm__ volatile("" : : : "memory"); }
static const sg_platform_t plat = { to_bus, clean, invalidate, barrier, barrier };

static sgdma_regs_t  regs;
static sg_pingpong_t pp;
static bus_addr_t    eng_cur;
static uint32_t      eng_pending, irq_masked, isr_calls, dropped;

static void irq_line(void)                     /* level-sensitive line into the NVIC */
{
    regs.STATUS = eng_pending;
    for (uint32_t guard = 0u; (irq_masked == 0u) && (eng_pending != 0u) && (guard < 8u); guard++) {
        isr_calls++;
        sg_pp_isr(&pp);
        eng_pending &= ~regs.STATUS;           /* the ISR's store is write-1-to-clear */
        regs.STATUS = eng_pending;
    }
}

static void engine_offer(uint32_t seq)         /* one incoming block from the wire */
{
    regs.DOORBELL = 0u;
    if (eng_cur == 0u) { eng_cur = regs.DESC; }
    sg_desc_hw_t *d = to_virt(eng_cur);
    if ((d->ctrl & SG_OWN) == 0u) {            /* no buffer: block lost on the wire */
        dropped++;
        eng_pending |= SGR_STALL;
        irq_line();
        return;
    }
    memcpy(to_virt(d->buf), &seq, sizeof seq);
    d->status = SG_ST_DONE | (d->ctrl & SG_LEN);
    d->ctrl &= ~SG_OWN;
    eng_cur = d->next;
    eng_pending |= SGR_DONE;
    irq_line();
}

int main(void)
{
    pp.regs = &regs; pp.plat = &plat;
    pp.desc = (sg_desc_t *)(void *)&arena[0];
    pp.buf = (uint8_t (*)[PP_BYTES])(void *)&arena[1024];
    (void)sg_pp_start(&pp);

    uint32_t seq = 0u, delivered = 0u, late = 0u, stranded_bursts = 0u, order_errors = 0u, last = 0u;
    for (uint32_t b = 0u; b < BURSTS; b++) {
        irq_masked = 1u;                       /* e.g. a long critical section */
        engine_offer(++seq);
        engine_offer(++seq);
        irq_masked = 0u;
        irq_line();                            /* ONE interrupt for both completions */
        uint32_t idx, len;
        while (sg_pp_take(&pp, &idx, &len) == 0) {
            uint32_t got;
            memcpy(&got, pp.buf[idx], sizeof got);
            if (got <= last) { order_errors++; }
            if (got + 2u <= seq) { late++; }   /* belongs to an earlier burst */
            last = got;
            delivered++;
            sg_pp_release(&pp, idx);
        }
        /* quiet line: anything completed by the engine but not delivered is stranded */
        for (uint32_t i = 0u; i < 2u; i++) {
            if ((((pp.desc[i].hw.ctrl & SG_OWN) == 0u)) && ((pp.ready_mask & (1u << i)) == 0u) &&
                ((pp.desc[i].hw.status & SG_ST_DONE) != 0u)) {
                stranded_bursts++;
                break;
            }
        }
    }
    printf("bursts=%u offered=%u delivered=%u dropped=%u late=%u order-errors=%u "
           "isr-calls=%u bursts-ending-with-stranded-data=%u\n",
           (unsigned)BURSTS, (unsigned)seq, (unsigned)delivered, (unsigned)dropped,
           (unsigned)late, (unsigned)order_errors, (unsigned)isr_calls, (unsigned)stranded_bursts);
    return 0;
}
```

**Result (verified, host model, same test linked against each driver):**

```
production sgdma.c : bursts=100 offered=200 delivered=200 dropped=0 late=0 order-errors=0 isr-calls=100 bursts-ending-with-stranded-data=0
buggy sgdma_bad.c  : bursts=100 offered=200 delivered=100 dropped=99 late=99 order-errors=0 isr-calls=100 bursts-ending-with-stranded-data=100
```

What happened to the buggy driver:

- Its ISR delivers one completion per interrupt. The second completed buffer is **stranded**, at the end of all 100 bursts.
- It is delivered only when the next burst's interrupt arrives (`late=99`).
- Meanwhile it is still CPU-owned, so the engine has only one buffer and **drops** every second block (`dropped=99`). Throughput halves.

In a NIC or audio driver this is the classic field bug: *"the last packet of each burst arrives only when the next burst starts"*, and *"we lose data under load but never on the bench"*.

**Finding.** The first draft of the *production* `sg_pp_take()` failed this same test with `order-errors=100`. With both buffers ready, it returned the newer one first. The older buffer is `next_done` (completions alternate), not `next_done ^ 1`. The single-completion tests never had both buffers ready at once, so they could not see it. The fixed version is below. Coalescing tests belong in every DMA driver's suite.

### 2.2 The Silicon-Hardened Production Way

**Interface** (descriptor ABI, register block, platform layer, ping-pong state):

```c
/* sgdma.h - cache-coherent scatter-gather DMA: RX ping-pong (two buffers,
 * circular descriptor chain) and TX gather chains. Ownership protocol:
 * a descriptor with OWN=1 belongs to the engine; the CPU touches neither it
 * nor its buffer until the engine clears OWN. Bus addresses are distinct from
 * CPU addresses (IOMMU / bus offset) and always come from the platform layer. */
#ifndef SGDMA_H
#define SGDMA_H

#include <stdalign.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef SG_LINE
#define SG_LINE 32u                      /* D-cache line (Cortex-M7); CWG on Cortex-A */
#endif
#define PP_BYTES 512u                    /* each ping-pong buffer: whole cache lines */
_Static_assert((PP_BYTES % SG_LINE) == 0u, "buffers must be line-exact");

typedef uint32_t bus_addr_t;

/* Hardware descriptor (16 bytes, little-endian, as the engine fetches it). */
typedef struct {
    bus_addr_t buf;                      /* 0x0 */
    uint32_t   ctrl;                     /* 0x4 [15:0] LEN, [29] LAST, [30] IRQ, [31] OWN */
    bus_addr_t next;                     /* 0x8 0 = end of chain */
    uint32_t   status;                   /* 0xC [15:0] bytes done, [30] ERR, [31] DONE */
} sg_desc_hw_t;
_Static_assert(sizeof(sg_desc_hw_t) == 16u, "descriptor ABI");

typedef struct { alignas(SG_LINE) sg_desc_hw_t hw; } sg_desc_t;      /* one per cache line */
_Static_assert(sizeof(sg_desc_t) == SG_LINE, "no two descriptors share a line");

#define SG_LEN     0x0000FFFFu
#define SG_LAST    (1u << 29)
#define SG_IRQ     (1u << 30)
#define SG_OWN     (1u << 31)
#define SG_ST_DONE (1u << 31)
#define SG_ST_ERR  (1u << 30)

typedef struct {
    volatile uint32_t CTRL;              /* [0] RUN                                   */
    volatile uint32_t DESC;              /* bus address of the first descriptor      */
    volatile uint32_t STATUS;            /* [0] DONE_IRQ, [1] STALL, [2] ERR  (W1C)  */
    volatile uint32_t DOORBELL;          /* write: re-fetch the current descriptor   */
} sgdma_regs_t;
#define SGR_RUN     (1u << 0)
#define SGR_DONE    (1u << 0)
#define SGR_STALL   (1u << 1)
#define SGR_ERR     (1u << 2)

typedef struct {                         /* everything that differs per platform */
    bus_addr_t (*to_bus)(const void *p);
    void       (*clean)(const void *p, size_t n);        /* CPU -> device */
    bool       (*invalidate)(void *p, size_t n);         /* device -> CPU, line-exact only */
    void       (*wmb)(void);                             /* dma_wmb: dmb oshst / dmb sy     */
    void       (*rmb)(void);                             /* dma_rmb: dmb oshld / dmb sy     */
} sg_platform_t;

typedef struct {
    sgdma_regs_t        *regs;
    const sg_platform_t *plat;
    sg_desc_t           *desc;           /* [2], line-aligned                        */
    uint8_t            (*buf)[PP_BYTES]; /* [2], line-aligned                        */
    uint32_t             next_done;      /* descriptor expected to complete next     */
    uint32_t             ready_mask;     /* bit i: buffer i completed, owned by CPU  */
    uint32_t             completed, overruns, errors;
} sg_pingpong_t;

int  sg_pp_start(sg_pingpong_t *pp);
void sg_pp_isr(sg_pingpong_t *pp);
int  sg_pp_take(sg_pingpong_t *pp, uint32_t *idx, uint32_t *len);  /* consumer: next full buffer */
void sg_pp_release(sg_pingpong_t *pp, uint32_t idx);               /* consumer: give it back    */

typedef struct { const void *p; uint32_t len; } sg_frag_t;
int  sg_tx_submit(sgdma_regs_t *regs, const sg_platform_t *plat, sg_desc_t *ring,
                  uint32_t ring_len, const sg_frag_t *frags, uint32_t nfrags);

#endif /* SGDMA_H */
```

**Driver:**

```c
/* sgdma.c - see sgdma.h. */
#include "sgdma.h"

/* The ownership word is the hand-off point: access it exactly once and untorn,
 * even if the platform layer is inlined (Linux: WRITE_ONCE / READ_ONCE). */
#define OWN_WORD(d) (*(volatile uint32_t *)&(d)->ctrl)

static void arm_rx(sg_pingpong_t *pp, uint32_t i)
{
    sg_desc_hw_t *d = &pp->desc[i].hw;
    /* The buffer may still hold lines the CPU read: invalidate BEFORE the
     * engine writes, so no dirty or stale line can be evicted onto new data. */
    (void)pp->plat->invalidate(pp->buf[i], PP_BYTES);
    d->buf = pp->plat->to_bus(pp->buf[i]);
    d->next = pp->plat->to_bus(&pp->desc[i ^ 1u].hw);
    d->status = 0u;
    pp->plat->wmb();                                    /* fields before ownership   */
    OWN_WORD(d) = SG_OWN | SG_IRQ | (PP_BYTES & SG_LEN); /* ONE store hands it over  */
    pp->plat->clean(d, sizeof *d);                      /* no-op if descriptors are NC */
}

int sg_pp_start(sg_pingpong_t *pp)
{
    if (((uintptr_t)pp->buf % SG_LINE) != 0u || ((uintptr_t)pp->desc % SG_LINE) != 0u) {
        return -1;                                      /* layout contract (Folder 03) */
    }
    pp->next_done = 0u;
    pp->ready_mask = 0u;
    arm_rx(pp, 1u);
    arm_rx(pp, 0u);
    pp->plat->wmb();
    pp->regs->DESC = pp->plat->to_bus(&pp->desc[0].hw);
    pp->regs->CTRL = SGR_RUN;
    (void)pp->regs->CTRL;                               /* posted-write flush */
    return 0;
}

void sg_pp_isr(sg_pingpong_t *pp)
{
    uint32_t st = pp->regs->STATUS;
    pp->plat->rmb();                                    /* readl(): descriptor reads below must
                                                         * not be performed before this MMIO read */
    pp->regs->STATUS = st & (SGR_DONE | SGR_STALL | SGR_ERR);   /* W1C exactly what we saw */
    if ((st & SGR_STALL) != 0u) {
        pp->overruns++;                                 /* both buffers were CPU-owned */
    }
    for (;;) {                                          /* drain completions in order */
        sg_desc_hw_t *d = &pp->desc[pp->next_done].hw;
        (void)pp->plat->invalidate(&pp->desc[pp->next_done], sizeof pp->desc[0]);
        if ((OWN_WORD(d) & SG_OWN) != 0u) {
            break;                                      /* engine still owns it */
        }
        if ((pp->ready_mask & (1u << pp->next_done)) != 0u) {
            break;                                      /* already delivered, not released */
        }
        pp->plat->rmb();                                /* OWN observed before status/data */
        if ((d->status & SG_ST_ERR) != 0u) {
            pp->errors++;
        }
        (void)pp->plat->invalidate(pp->buf[pp->next_done], PP_BYTES);  /* drop speculative refills */
        pp->ready_mask |= 1u << pp->next_done;
        pp->completed++;
        pp->next_done ^= 1u;
    }
    (void)pp->regs->STATUS;                             /* clear reached the device */
}

int sg_pp_take(sg_pingpong_t *pp, uint32_t *idx, uint32_t *len)
{
    uint32_t cand;
    if (pp->ready_mask == 3u) {
        cand = pp->next_done;                           /* both full: completions alternate, */
    } else if (pp->ready_mask != 0u) {                  /* so the older one is next_done     */
        cand = (pp->ready_mask == 1u) ? 0u : 1u;
    } else {
        return -1;
    }
    *idx = cand;                                        /* peek: stays CPU-owned until release */
    *len = pp->desc[cand].hw.status & SG_LEN;
    return 0;
}

void sg_pp_release(sg_pingpong_t *pp, uint32_t idx)
{
    pp->ready_mask &= ~(1u << idx);
    arm_rx(pp, idx);
    pp->plat->wmb();                                    /* writel(): OWN (Normal) before the
                                                         * doorbell (Device): Arm doesn't order them */
    pp->regs->DOORBELL = 1u;                            /* resume if the engine stalled */
}

/* Gather chain: descriptors filled first, OWN set from the LAST to the FIRST,
 * so the engine (which may be running) never follows `next` into a descriptor
 * that is not yet complete. One doorbell at the end. */
int sg_tx_submit(sgdma_regs_t *regs, const sg_platform_t *plat, sg_desc_t *ring,
                 uint32_t ring_len, const sg_frag_t *frags, uint32_t nfrags)
{
    if ((nfrags == 0u) || (nfrags > ring_len)) {
        return -1;
    }
    for (uint32_t i = 0u; i < nfrags; i++) {
        if ((frags[i].len == 0u) || (frags[i].len > SG_LEN)) {
            return -1;
        }
        plat->clean(frags[i].p, frags[i].len);          /* partial lines are safe to CLEAN */
        sg_desc_hw_t *d = &ring[i].hw;
        d->buf = plat->to_bus(frags[i].p);
        d->next = (i + 1u < nfrags) ? plat->to_bus(&ring[i + 1u].hw) : 0u;
        d->status = 0u;
        d->ctrl = frags[i].len;                         /* not yet owned */
    }
    plat->wmb();
    for (uint32_t i = nfrags; i-- > 0u; ) {             /* last -> first */
        uint32_t c = ring[i].hw.ctrl | SG_OWN | ((i + 1u == nfrags) ? (SG_LAST | SG_IRQ) : 0u);
        OWN_WORD(&ring[i].hw) = c;
        plat->clean(&ring[i], sizeof ring[i]);
        plat->wmb();
    }
    regs->DESC = plat->to_bus(&ring[0].hw);
    regs->CTRL = SGR_RUN;
    regs->DOORBELL = 1u;
    return 0;
}
```

**Platform layer for Cortex-M7** (NC window, by-address maintenance, line-exact invalidate):

```c
/* sgdma_plat_m7.c - sg_platform_t for a Cortex-M7. Buffers in the MPU
 * Normal-NC window (File 01: D2 SRAM) need no maintenance; anything else gets
 * by-address clean/invalidate. Invalidate refuses partial lines: discarding a
 * line that also holds CPU data is the neighbor-line disaster (Folder 03). */
#include "sgdma.h"

extern const sg_platform_t g_sg_plat_m7;

#define SCB_DCIMVAC (*(volatile uint32_t *)0xE000EF5Cu)   /* invalidate by MVA to PoC */
#define SCB_DCCMVAC (*(volatile uint32_t *)0xE000EF68u)   /* clean by MVA to PoC      */
#define NC_BASE     0x30000000u
#define NC_SIZE     (128u << 10)

static bool in_nc(uintptr_t a, size_t n)
{
    return (a >= NC_BASE) && (n <= NC_SIZE) && ((a - NC_BASE) <= (NC_SIZE - n));
}

static bus_addr_t m7_to_bus(const void *p)
{
    return (bus_addr_t)(uintptr_t)p;              /* no IOMMU: bus address == CPU address */
}

static void m7_clean(const void *p, size_t n)
{
    uintptr_t a = (uintptr_t)p;
    if ((n == 0u) || in_nc(a, n)) {
        return;
    }
    uintptr_t end = a + n;
    __asm__ volatile("dsb sy" : : : "memory");
    for (a &= ~(uintptr_t)(SG_LINE - 1u); a < end; a += SG_LINE) {   /* partial lines: safe to clean */
        SCB_DCCMVAC = (uint32_t)a;
    }
    __asm__ volatile("dsb sy" : : : "memory");    /* clean complete before the device reads */
}

static bool m7_invalidate(void *p, size_t n)
{
    uintptr_t a = (uintptr_t)p;
    if (((a % SG_LINE) != 0u) || ((n % SG_LINE) != 0u)) {
        return false;                             /* never discard a shared line */
    }
    if (in_nc(a, n)) {
        return true;
    }
    __asm__ volatile("dsb sy" : : : "memory");
    for (uintptr_t end = a + n; a < end; a += SG_LINE) {
        SCB_DCIMVAC = (uint32_t)a;
    }
    __asm__ volatile("dsb sy\n\tisb sy" : : : "memory");
    return true;
}

static void m7_wmb(void) { __asm__ volatile("dmb sy" : : : "memory"); }
static void m7_rmb(void) { __asm__ volatile("dmb sy" : : : "memory"); }

const sg_platform_t g_sg_plat_m7 = { m7_to_bus, m7_clean, m7_invalidate, m7_wmb, m7_rmb };
```

**Codegen (verified — Clang 21.1.0, -O2, thumbv7em-none-eabihf, Cortex-M7), `sg_pp_release` (with `arm_rx` inlined):**

```asm
sg_pp_release:
	push.w	{r4, r5, r6, r7, r8, r9, lr}
	sub	sp, #4
	mov	r4, r0
	mov.w	r8, #1
	mov	r6, r1
	lsl.w	r0, r8, r1
	ldrd	r1, r7, [r4, #4]
	ldr	r2, [r4, #12]
	lsl.w	r9, r6, #5
	ldr	r3, [r4, #20]
	add.w	r5, r7, r6, lsl #5
	bic.w	r0, r3, r0
	str	r0, [r4, #20]
	ldr	r3, [r1, #8]
	add.w	r0, r2, r6, lsl #9
	mov.w	r1, #512
	blx	r3
	ldr	r0, [r4, #4]
	ldr	r1, [r4, #12]
	ldr	r2, [r0]
	add.w	r0, r1, r6, lsl #9
	blx	r2
	ldrd	r1, r2, [r4, #4]
	eor	r3, r6, #1
	str.w	r0, [r7, r9]
	ldr	r1, [r1]
	add.w	r0, r2, r3, lsl #5
	blx	r1
	ldr	r2, [r4, #4]
	movs	r1, #0
	strd	r0, r1, [r5, #8]
	ldr	r0, [r2, #12]
	blx	r0
	movw	r0, #512
	movs	r1, #16
	movt	r0, #49152
	str	r0, [r5, #4]
	ldr	r0, [r4, #4]
	ldr	r2, [r0, #4]
	mov	r0, r5
	blx	r2
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #12]
	blx	r0
	ldr	r0, [r4]
	str.w	r8, [r0, #12]
	add	sp, #4
	pop.w	{r4, r5, r6, r7, r8, r9, pc}
```

How to read it (`r4 = pp`, `r5 = &desc[idx]`, platform ops called through `blx`):

1. `ready_mask` cleared, then `blx r3` = `invalidate(buf[idx], 512)`: the before-arming invalidate.
2. Two `to_bus` calls: `str.w r0, [r7, r9]` stores `buf`, and `strd r0, r1, [r5, #8]` stores `next` and `status = 0` together.
3. `blx` through `[r2, #12]` = `wmb` (ordering a).
4. `movw/movt 0xC0000200` → `str r0, [r5, #4]`: OWN | IRQ | 512 in **one** 32-bit store.
5. `clean(d, 16)` (`movs r1, #16`).
6. `blx` through `[r0, #12]` = `wmb` again (ordering b), then the doorbell: `str.w r8, [r0, #12]` with `r8 = 1`.

**Codegen (verified, same flags), `sg_pp_isr`:**

```asm
sg_pp_isr:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldrd	r0, r1, [r0]
	ldr	r5, [r0, #8]
	ldr	r0, [r1, #16]
	blx	r0
	ldr	r0, [r4]
	lsls	r1, r5, #30
	and	r1, r5, #7
	str	r1, [r0, #8]
	bpl	.LBB1_2
	ldr	r0, [r4, #28]
	adds	r0, #1
	str	r0, [r4, #28]
.LBB1_2:
	ldrd	r0, r1, [r4, #4]
	ldr	r2, [r4, #16]
	add.w	r5, r1, r2, lsl #5
	ldr	r2, [r0, #8]
	movs	r1, #32
	mov	r0, r5
	blx	r2
	ldr	r0, [r5, #4]
	cmp	r0, #0
	bmi	.LBB1_8
	movs	r6, #1
	b	.LBB1_5
.LBB1_4:
	ldr	r0, [r4, #4]
	ldrd	r1, r2, [r4, #12]
	ldr	r3, [r0, #8]
	add.w	r0, r1, r2, lsl #9
	mov.w	r1, #512
	blx	r3
	ldrd	r2, r3, [r4, #16]
	ldrd	r0, r1, [r4, #4]
	lsl.w	r5, r6, r2
	eor	r2, r2, #1
	orrs	r3, r5
	ldr	r5, [r4, #24]
	str	r3, [r4, #20]
	adds	r3, r5, #1
	add.w	r5, r1, r2, lsl #5
	str	r2, [r4, #16]
	ldr	r2, [r0, #8]
	movs	r1, #32
	mov	r0, r5
	str	r3, [r4, #24]
	blx	r2
	ldr	r0, [r5, #4]
	cmp.w	r0, #-1
	ble	.LBB1_8
.LBB1_5:
	ldrd	r0, r1, [r4, #16]
	lsr.w	r0, r1, r0
	lsls	r0, r0, #31
	bne	.LBB1_8
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #16]
	blx	r0
	ldrb	r0, [r5, #15]
	lsls	r0, r0, #25
	bpl	.LBB1_4
	ldr	r0, [r4, #32]
	adds	r0, #1
	str	r0, [r4, #32]
	b	.LBB1_4
.LBB1_8:
	ldr	r0, [r4]
	ldr	r0, [r0, #8]
	pop	{r4, r5, r6, pc}
```

How to read it:

- `ldr r5, [r0, #8]` reads STATUS. Then `blx` through `[r1, #16]` = `rmb` (ordering c), *before* the W1C store `and r1, r5, #7; str r1, [r0, #8]`.
- `lsls r1, r5, #30` tests STALL into the overrun counter.
- Each loop iteration:
  - invalidates the descriptor line (`movs r1, #32`);
  - loads the ownership word (`ldr r0, [r5, #4]`, a full-word volatile access) and tests bit 31 (`bmi`/`ble`);
  - calls `rmb` (ordering d);
  - reads the ERR bit as **`ldrb r0, [r5, #15]`**. The compiler narrowed the plain `status` read to one byte, legal for a non-volatile object in Normal memory, which is exactly why device registers must never be accessed this way.
- The final `ldr r0, [r0, #8]` is the read-back that drains the W1C write.

**Codegen (verified, same flags), `m7_invalidate`:**

```asm
m7_invalidate:
	orr.w	r12, r1, r0
	lsls.w	r2, r12, #27
	bne	.LBB2_11
	cmp.w	r0, #805306368
	blo	.LBB2_4
	cmp.w	r1, #131072
	bhi	.LBB2_4
	add.w	r2, r0, #-805306368
	rsb.w	r3, r1, #131072
	cmp	r2, r3
	bls	.LBB2_11
.LBB2_4:
	add	r1, r0
	dsb	sy
	cmp	r1, r0
	bls	.LBB2_10
	movw	r3, #61276
	movt	r3, #57344
.LBB2_6:
	add.w	r2, r0, #32
	str	r0, [r3]
	cmp	r2, r1
	bhs	.LBB2_10
	add.w	r0, r2, #32
	str	r2, [r3]
	cmp	r0, r1
	bhs	.LBB2_10
	add.w	r2, r0, #32
	str	r0, [r3]
	cmp	r2, r1
	bhs	.LBB2_10
	add.w	r0, r2, #32
	str	r2, [r3]
	cmp	r0, r1
	blo	.LBB2_6
.LBB2_10:
	dsb	sy
	isb	sy
.LBB2_11:
	and	r0, r12, #31
	clz	r0, r0
	lsrs	r0, r0, #5
	bx	lr
```

- The line-exact check was folded into one test: `(a | n) & 31` via `orr.w` + `lsls.w #27`.
- The NC-window check is three compares against `0x30000000`/`0x20000`.
- The DCIMVAC loop (`0xE000EF5C`) was unrolled by four, bracketed by `dsb` and `dsb; isb`.

**Host test harness** (engine model with W1C, stall-on-no-buffer, bus ≠ CPU addresses):

```c
/* sgdma_test.c - host test of sgdma.c against a behavioural DMA engine model.
 * DMA memory is an arena whose BUS addresses are 0x3000_0000 + offset, so any
 * place where the driver confused CPU and bus addresses would fault the model. */
#include <stdio.h>
#include <string.h>

#include "sgdma.h"

#define BUS_BASE 0x30000000u
static alignas(SG_LINE) uint8_t arena[16384];
static uint32_t n_clean, n_inval, n_inval_rejected;

static bus_addr_t to_bus(const void *p) { return BUS_BASE + (bus_addr_t)((const uint8_t *)p - arena); }
static void *to_virt(bus_addr_t b) { return &arena[b - BUS_BASE]; }
static void clean(const void *p, size_t n) { (void)p; (void)n; n_clean++; }
static bool invalidate(void *p, size_t n)
{
    if ((((uintptr_t)p % SG_LINE) != 0u) || ((n % SG_LINE) != 0u)) { n_inval_rejected++; return false; }
    n_inval++;
    return true;
}
static void barrier(void) { __asm__ volatile("" : : : "memory"); }
static const sg_platform_t plat = { to_bus, clean, invalidate, barrier, barrier };

/* ---------------- engine model ---------------- */
static sgdma_regs_t regs;
static bus_addr_t eng_cur;
static int eng_stalled;
static uint32_t eng_dropped;
static sg_pingpong_t *irq_target;
static uint32_t eng_pending;                       /* latched STATUS bits (W1C model) */

static void raise_irq(uint32_t bits)
{
    eng_pending |= bits;
    regs.STATUS = eng_pending;
    sg_pp_isr(irq_target);
    eng_pending &= ~regs.STATUS;                   /* the ISR's store is a write-1-to-clear */
    regs.STATUS = eng_pending;
}

static void engine_kick(void)            /* CTRL/DESC/DOORBELL side effects */
{
    if (regs.DOORBELL != 0u) { regs.DOORBELL = 0u; eng_stalled = 0; }
}

static void engine_rx_block(uint32_t seq)
{
    engine_kick();
    if ((regs.CTRL & SGR_RUN) == 0u) { return; }
    if (eng_cur == 0u) { eng_cur = regs.DESC; }
    sg_desc_hw_t *d = to_virt(eng_cur);
    if (eng_stalled || (d->ctrl & SG_OWN) == 0u) {    /* CPU still owns it: never write */
        if (!eng_stalled) { eng_stalled = 1; raise_irq(SGR_STALL); }
        eng_dropped++;
        return;
    }
    uint8_t *b = to_virt(d->buf);
    uint32_t len = d->ctrl & SG_LEN;
    for (uint32_t i = 0u; i < len; i++) { b[i] = (uint8_t)(seq + i); }
    memcpy(b, &seq, sizeof seq);
    d->status = SG_ST_DONE | len;
    d->ctrl &= ~SG_OWN;                                /* hand back */
    eng_cur = d->next;
    if ((d->ctrl & SG_IRQ) != 0u) { raise_irq(SGR_DONE); }
}

static uint32_t engine_tx(uint8_t *out, uint32_t cap)  /* walk a gather chain */
{
    uint32_t n = 0u;
    for (bus_addr_t a = regs.DESC; a != 0u; ) {
        sg_desc_hw_t *d = to_virt(a);
        if ((d->ctrl & SG_OWN) == 0u) { break; }
        uint32_t len = d->ctrl & SG_LEN;
        if (n + len > cap) { break; }
        memcpy(&out[n], to_virt(d->buf), len);
        n += len;
        d->status = SG_ST_DONE | len;
        d->ctrl &= ~SG_OWN;
        if ((d->ctrl & SG_LAST) != 0u) { break; }
        a = d->next;
    }
    return n;
}

static void run_rx(const char *name, uint32_t blocks, uint32_t hold)
{
    memset(arena, 0, sizeof arena);
    memset(&regs, 0, sizeof regs);
    eng_cur = 0u; eng_stalled = 0; eng_dropped = 0u; eng_pending = 0u;
    n_clean = 0u; n_inval = 0u; n_inval_rejected = 0u;
    static sg_pingpong_t pp;
    memset(&pp, 0, sizeof pp);
    pp.regs = &regs; pp.plat = &plat;
    pp.desc = (sg_desc_t *)(void *)&arena[0];
    pp.buf = (uint8_t (*)[PP_BYTES])(void *)&arena[1024];
    irq_target = &pp;
    if (sg_pp_start(&pp) != 0) { printf("start failed\n"); return; }

    uint32_t delivered = 0u, bad = 0u, last_seq = 0u, gaps = 0u, held = 0u, held_idx = 0u, held_seq = 0u;
    for (uint32_t seq = 1u; seq <= blocks; seq++) {
        engine_rx_block(seq);
        uint32_t idx, len;
        while (sg_pp_take(&pp, &idx, &len) == 0) {
            if (held != 0u && idx == held_idx) { break; }
            uint32_t got;
            memcpy(&got, pp.buf[idx], sizeof got);
            if (len != PP_BYTES) { bad++; }
            if (got <= last_seq) { bad++; }
            if (got != last_seq + 1u) { gaps += got - last_seq - 1u; }
            last_seq = got;
            delivered++;
            if (hold != 0u && held == 0u && (seq % 50u) == 0u) {   /* slow consumer: keep it */
                held = hold; held_idx = idx; held_seq = got;
                break;
            }
            sg_pp_release(&pp, idx);
        }
        if (held != 0u && --held == 0u) {
            uint32_t got;
            memcpy(&got, pp.buf[held_idx], sizeof got);
            if (got != held_seq) { bad++; }                 /* engine never wrote a CPU-owned buffer */
            sg_pp_release(&pp, held_idx);
        }
    }
    printf("%-22s blocks=%u delivered=%u bad=%u overrun-events=%u dropped=%u seq-gaps=%u "
           "invalidate ok/rejected=%u/%u\n", name, (unsigned)blocks, (unsigned)delivered,
           (unsigned)bad, (unsigned)pp.overruns, (unsigned)eng_dropped, (unsigned)gaps,
           (unsigned)n_inval, (unsigned)n_inval_rejected);
}

int main(void)
{
    run_rx("RX fast consumer", 1000u, 0u);
    run_rx("RX slow consumer", 1000u, 3u);

    /* TX: four fragments at arbitrary (unaligned) addresses and sizes. */
    memset(&regs, 0, sizeof regs);
    sg_desc_t *ring = (sg_desc_t *)(void *)&arena[0];
    uint8_t *src = &arena[4096];
    const uint32_t lens[4] = { 7u, 100u, 513u, 1u };
    const uint32_t offs[4] = { 3u, 211u, 1000u, 2047u };
    sg_frag_t fr[4];
    uint8_t expect[1024], out[1024];
    uint32_t total = 0u;
    for (uint32_t f = 0u; f < 4u; f++) {
        for (uint32_t i = 0u; i < lens[f]; i++) { src[offs[f] + i] = (uint8_t)(f * 60u + i); expect[total++] = (uint8_t)(f * 60u + i); }
        fr[f].p = &src[offs[f]]; fr[f].len = lens[f];
    }
    int rc = sg_tx_submit(&regs, &plat, ring, 8u, fr, 4u);
    uint32_t n = engine_tx(out, sizeof out);
    printf("TX gather: rc=%d sent=%u/%u match=%s last-flag-on-desc3=%s owners-cleared=%s\n", rc,
           (unsigned)n, (unsigned)total, (n == total && memcmp(out, expect, total) == 0) ? "yes" : "NO",
           (ring[3].hw.ctrl & SG_LAST) ? "yes" : "no",
           ((ring[0].hw.ctrl | ring[1].hw.ctrl | ring[2].hw.ctrl | ring[3].hw.ctrl) & SG_OWN) ? "no" : "yes");
    return 0;
}
```

**Result (verified, host model):**

```
RX fast consumer       blocks=1000 delivered=1000 bad=0 overrun-events=0 dropped=0 seq-gaps=0 invalidate ok/rejected=4002/0
RX slow consumer       blocks=1000 delivered=981 bad=0 overrun-events=19 dropped=19 seq-gaps=19 invalidate ok/rejected=3944/0
TX gather: rc=0 sent=621/621 match=yes last-flag-on-desc3=yes owners-cleared=yes
```

Reading the counters:

- **Fast consumer:** 1000/1000 delivered, in sequence, with no overruns.
  - 4002 invalidates = 4 per block, plus 2 at start: the ISR's descriptor line and buffer, the drain loop's re-check of the next descriptor, and the re-arm's pre-invalidate.
  - 0 rejected: every invalidate was line-exact.
- **Slow consumer:** holds one buffer for three blocks every 50 blocks.
  - With two buffers, each hold forces exactly one stall: 19 overrun events = 19 dropped = 19 sequence gaps. The 20th hold, at block 1000, has no later block to drop.
  - `bad=0`: the engine **never wrote a CPU-owned buffer** (the held buffer's sequence number was re-checked on release).
- **TX gather:** fragments of 7, 100, 513 and 1 bytes at unaligned offsets arrived as 621 contiguous bytes. LAST was on descriptor 3, and every OWN bit was returned.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| Last packet of each burst delivered only when the next burst starts | ISR handles one completion per interrupt (§2.1) | Count completions per ISR invocation; toggle a GPIO per completion and per ISR on a logic analyzer: two completions, one ISR entry |
| Throughput halves under load, fine on the bench | Stranded buffer leaves the engine one buffer → stalls | STALL/overrun counter; engine's current-descriptor register stuck on a CPU-owned descriptor |
| Occasional stale or zero payload, more frequent with the D-cache on | Missing invalidate before arming or after completion; buffer not line-exact | Move buffers to the NC window: if the bug disappears, it's maintenance. Check buffer alignment in the map file |
| Corruption of an unrelated variable next to a DMA buffer | Partial-line invalidate discarded the neighbor's dirty line | `invalidate rejected > 0` in the platform layer; align and size buffers to the line (Folder 03 File 03) |
| Engine stalls right after release, recovers on the next doorbell | Doorbell overtook the OWN store (missing `wmb` before a Device write) | Logic analyzer or bus trace: doorbell write precedes the descriptor write; ETM data trace shows the store order |
| Interrupt fires twice per completion | W1C not drained before exception return | Read back STATUS before return (Folder 06 File 01) |
| Lost completion under heavy load, no overrun flagged | `STATUS = 0xFFFFFFFF` erased an event latched after the read | Compare the engine's completed-descriptor count with the driver's `completed` |
| Engine reports bus error on the first descriptor fetch | CPU address given to a device that sees a bus address (IOMMU, alias window) | Engine's error-address register vs `to_bus()`; the host model's offset bus addresses catch this class |

**Instrumenting a ring in the field:**

- Keep `completed`, `overruns` and `errors` counters (as in `sg_pingpong_t`) and export them.
- On a fault, dump both descriptors: `ctrl` (OWN), `status`, `next`.
- An ETM/ITM trace (Trace32, Ozone) with data-address watchpoints on the two OWN words shows the hand-off sequence cycle by cycle.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Design a zero-copy RX ping-pong DMA driver for a Cortex-M7 with D-cache enabled."

- **L5:** "Two buffers, the DMA half/full interrupt toggles between them, and I call `SCB_InvalidateDCache_by_Addr` in the ISR."
- **Why L5 fails on real hardware:**
  - One invalidate is not enough: dirty lines must also be removed *before* arming, or an eviction lands on top of DMA data.
  - Unaligned buffers make the invalidate corrupt neighbors.
  - "Toggle on interrupt" loses track under coalescing.
  - No ownership protocol means the engine can overwrite a buffer the consumer is still reading.
- **L7 principal defense:**
  - Descriptors with an OWN bit, one per cache line (statically asserted).
  - Line-exact buffers. Invalidate before arming and after completion. A platform layer that refuses partial-line invalidates.
  - Barriers (a)–(d) from §1.2, including the two that Linux hides in `writel`/`readl`. A volatile ownership word.
  - An ISR that W1Cs exactly what it read, drains completions in order and reads back status.
  - Explicit `take`/`release`, so a slow consumer causes counted overruns, never overwrites. Verified: `bad=0`, 19 overruns = 19 drops.
  - Better still: put DMA memory in an MPU Normal-NC window (File 01) and keep the maintenance calls as no-ops for portability.

### Q2 "Why does `writel()` on arm64 contain a barrier, and what happens in bare-metal code that copies a Linux driver's logic but uses plain volatile stores?"

- **L5:** "Volatile is enough for registers."
- **Why L5 fails:**
  - Volatile constrains the *compiler*, not the *CPU*.
  - On Arm, a store to Normal memory (the descriptor's OWN bit) and a later store to Device memory (the doorbell) are not ordered for an external observer without a DMB.
  - The device can see the doorbell, fetch the descriptor, and still find OWN = 0.
- **L7 defense:**
  - `writel()` = `__iowmb()` (a `dma_wmb()`-strength barrier) + the store, and `readl()` = the load + `__iormb()`.
  - Bare-metal code must place these explicitly. The verified release path has `wmb` between the OWN store and the doorbell, and the ISR has `rmb` right after the STATUS read.
  - For hot paths, use the `_relaxed` accessors and batch one barrier per ring update.

### Q3 🔥 "Your NIC driver delivers the last packet of every burst late. The ISR looks correct. Debug it."

- **L5:** "Interrupt latency; raise the priority."
- **Why L5 fails:** Priority doesn't create interrupts that were never raised separately. Two completions under one latched interrupt (masked period, NAPI-style coalescing, or a level-sensitive line) are one ISR entry. An ISR that processes one descriptor per entry strands the rest until the next interrupt.
- **L7 defense:**
  - Count completions per ISR entry (GPIO toggles on a logic analyzer).
  - Fix with a drain loop that walks descriptors in order until it finds one still owned by the engine.
  - Add a coalescing test to the suite. Verified: the buggy driver stranded data at the end of 100/100 bursts and dropped 99 blocks; the production driver delivered 200/200.
  - Mention that the same test caught an ordering bug in the production `take()` during development: tests that never produce two simultaneous completions cannot validate ordering.

### Q4 "Why must TX descriptors in a chain be handed to the engine last-to-first?"

- **L5:** "Order doesn't matter if you write the doorbell at the end."
- **Why L5 fails:** A *running* engine (a previous chain in flight, or a ring in auto-poll mode) follows `next` pointers without waiting for the doorbell. Publish forward and it can reach descriptor *k*+1 after you set OWN on *k* but before you have finished *k*+1.
- **L7 defense:**
  - Fill everything with OWN = 0, `wmb`, then set OWN from the last descriptor to the first, cleaning each one; the doorbell last.
  - Equivalently, set OWN on the *first* descriptor last. That's the Linux NIC idiom: write the head descriptor's ownership last.
  - Verified: the gather completed with LAST on descriptor 3 and all OWN bits returned.

### Q5 "When is invalidating a buffer *dangerous*?"

- **L5:** "Never; it just drops cached data."
- **Why L5 fails:** "Just drops" is the danger.
  - Invalidating a line that also holds unrelated dirty CPU data destroys that data.
  - Invalidating by set/way at run time destroys arbitrary dirty data, and is never coherent on SMP.
- **L7 defense:**
  - By-address only.
  - Only on whole lines that the buffer exclusively owns. Enforce it in the platform layer (`m7_invalidate` returns `false` on partial lines, and the driver's layout contract makes that unreachable).
  - Use the CPU's real line size: 32 B on M7, `CTR_EL0.DminLine`/CWG on Cortex-A, often 64 B.

---

## 5. Invariants Checklist

- [ ] One descriptor per cache line (`alignas(line)`, `_Static_assert(sizeof == line)`); buffers line-aligned and line-sized.
- [ ] Ownership word accessed through a volatile lvalue (`WRITE_ONCE`/`READ_ONCE`); set in exactly one store, *after* `wmb`.
- [ ] `wmb` between the last descriptor store and any doorbell or MMIO write (the `writel` barrier); `rmb` after the status MMIO read (the `readl` barrier); `rmb` after observing OWN = 0.
- [ ] RX: invalidate before arming and after completion. TX: clean before handing over. Never invalidate partial lines.
- [ ] ISR: read STATUS, W1C exactly the bits read, drain all completions in order, read back STATUS before return.
- [ ] Explicit `take`/`release` ownership for consumers. Overruns counted (STALL), never silent overwrites.
- [ ] TX chains published last-to-first; doorbell last.
- [ ] Bus addresses only from the platform layer (IOMMU, alias windows); host tests use offset bus addresses.
- [ ] Test suite includes coalesced completions, a slow consumer and unaligned gather fragments.

## 6. References

1. Linux kernel, `Documentation/memory-barriers.txt`: "DMA barriers" (`dma_wmb`, `dma_rmb`) and "Kernel I/O barrier effects" (`readX`/`writeX` ordering guarantees).
2. Linux kernel, `Documentation/core-api/dma-api.rst` and `dma-api-howto.rst`: coherent vs streaming mappings, `dma_sync_single_for_cpu/device` (the two RX syncs).
3. Linux kernel, `arch/arm64/include/asm/io.h` and `barrier.h`: `__iowmb()`, `__iormb()`, `dma_wmb()` = `dmb oshst`, `dma_rmb()` = `dmb oshld`.
4. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E), A3.7: memory access order; Device vs Normal ordering; DMB semantics.
5. Arm, *Cortex-M7 TRM* (DDI 0489): DCIMVAC/DCCMVAC/DCCIMVAC, 32-byte lines; CMSIS `SCB_InvalidateDCache_by_Addr`, `SCB_CleanDCache_by_Addr`.
6. Arm, *PrimeCell DMA Controller (PL330) TRM*, and Synopsys DesignWare GMAC/eDMA databooks: descriptor-ring OWN-bit protocols (⚠ verify field layouts per IP).
7. Folder 03 File 03 (cache maintenance and the neighbor-line disaster), Folder 06 File 01 (posted writes and the spurious double interrupt), File 01 of this folder (the NC DMA window).
