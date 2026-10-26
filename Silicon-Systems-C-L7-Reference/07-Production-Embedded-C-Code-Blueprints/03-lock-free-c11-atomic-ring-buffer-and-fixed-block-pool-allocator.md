# 03 · Lock-Free C11 Atomic Ring Buffer and Fixed-Block Pool Allocator (ISR-Safe, Zero-Copy)

> **Folder:** `07-Production-Embedded-C-Code-Blueprints/` · **File 3 of 4**
> **Anchors:**
> - ISO/IEC 9899:2018 §7.17 (`<stdatomic.h>`) and §5.1.2.4 (happens-before, release/acquire).
> - Arm *ARMv7-M Architecture Reference Manual* (DDI 0403E) A3.4: synchronization primitives and the exclusive monitors.
> - Arm *Cortex-M4/M7 Devices Generic User Guide*, LDREX/STREX: the processor removes its exclusive-access tag on CLREX, on any STREX, **and when an exception occurs**.
> - R. K. Treiber, *Systems Programming: Coping with Parallelism* (IBM RJ 5118, 1986), the lock-free stack.
> - Herlihy & Shavit, *The Art of Multiprocessor Programming* (ABA, tagged references).
> - Production relatives: Zephyr `k_mem_slab`, FreeRTOS stream/message buffers, DPDK `rte_ring`, Linux `kfifo`.
> - Folder 05 File 02, which proved the uint32 SPSC and Vyukov MPMC and reproduced ABA. This file builds the reusable production layer on top of it.
>
> **Verification:**
> - `lf_pool.h` and `lf_ring.h` compile warning-free for Cortex-M7, M4, M33, AArch64 (LL/SC and LSE), x86-64, RV64GC and RV32IMAC.
> - A **4-thread host stress test**: one shared pool, two rings, 1,000,000 messages, with the pool deliberately run dry.
> - Four **deterministic** defect demonstrations, naive vs production.
> - Codegen captured for M7 and AArch64-LSE.
> - The stress test ran on x86-64 (TSO). It validates the algorithm and the compiler's handling of the atomics, **not** weak-memory hardware reordering. Arm ordering follows from the C11 model and is visible in the listed barriers (`dmb`, `ldapr`, `casal`); litmus evidence is in Folder 03 File 02.
> - All outputs and listings are inserted verbatim.

---

## 0. The thesis

"No `malloc` in an ISR" is not about speed. `malloc` is **unbounded** (search time), **fragmenting** (it can fail with plenty of free bytes), and **lock-based**: an ISR can't take a lock the interrupted thread holds.

The production replacement is two structures with *different* concurrency contracts:

| Structure | Contract | Operations | Bound |
|---|---|---|---|
| Fixed-block **pool** | **MPMC**: any context, any core, any priority, concurrently | `alloc`, `free` | O(1); lock-free (a retry happens only when another context *succeeded*) |
| **SPSC ring** | Exactly **one** producer context and **one** consumer context | `push`/`pop`, or zero-copy `reserve/commit` and `peek/release` | O(1); **wait-free** |

Composed, they give **zero-copy message passing**. The producer allocates a block, builds the message in place, and pushes a one-byte handle. The consumer pops the handle, reads the block, and frees it. No byte of payload is copied, nothing blocks, and nothing masks interrupts.

Most field failures come from violating a **contract** (a second producer on an SPSC ring, a free of a block someone else owns, a non-power-of-two capacity), not from the algorithms. So this design makes violations *detectable* or *impossible to express*.

---

## 1. First-Principles Mechanics

### 1.1 The pool's head: one 32-bit word, `{tag:24 | index:8}`

The free list is a Treiber stack, but it stores **indices, not pointers**, and the links live **out of band** in `next[]`, not inside the blocks:

```
head (one _Atomic uint32_t)       next[] (_Atomic uint16_t, one per block)
+-----------------+--------+       +----+----+----+----+
|  tag (24 bits)  | idx(8) | ----> | 3  | NIL| 0  | 1  |   blocks: [guard|state|payload|guard] x N
+-----------------+--------+       +----+----+----+----+
```

Three properties follow:

1. **One CAS word on every core.** ARMv7-M has 32-bit LDREX/STREX but **no LDREXD**, so a `{pointer, tag}` double-width CAS is not available on Cortex-M. Index plus tag fits in 32 bits.
2. **The tag advances on every successful head update** (alloc *and* free). Verified: after 1,000,000 messages the tag reads exactly **2,000,000**. A thread that loaded `head`, was preempted, and then CASes against a head that has since gone A → B → A fails, because the tag differs. That's ABA (reproduced in Folder 05 File 02).
3. **Payload writes can't corrupt the allocator.** With links inside the blocks (the naive design), a write-after-free *is* a free-list corruption (demo 1 in §2.1).

### 1.2 Spend bits on the tag: the wrap budget

ABA returns if exactly *k*·2^tagbits head updates happen while one context sits between its load and its CAS, *and* the same index is back on top. For a **starved low-priority task**, that's not a theoretical window:

| `LFP_IDX_BITS` | Max blocks | Tag bits | Updates to wrap | Time to wrap at 100k pool ops/s |
|---|---|---|---|---|
| 16 | 65,534 | 16 | 65,536 | **0.66 s** (a starved task can sleep that long) |
| 12 | 4,094 | 20 | 1,048,576 | 10.5 s |
| 8 (default) | 254 | 24 | 16,777,216 | 168 s |

Embedded pools rarely need more than a few hundred blocks, so the index should be no wider than the pool requires. On 64-bit cores (AArch64, x86-64, RV64), widen `head` to 64 bits with a 32-bit tag and the window is gone in practice. `lfp_init()` refuses `n ≥ 2^IDX_BITS − 1`, because the all-ones index is NIL.

### 1.3 Why it is ISR-safe without masking (and where that stops)

On Cortex-M, the C11 CAS compiles to `ldrex … strex` (listing in §2.2). If an interrupt arrives between the thread's `ldrex` and `strex`:

1. Exception entry clears the local exclusive monitor (Generic User Guide).
2. The ISR runs its own `alloc`/`free` to completion. It can't be preempted by the thread it interrupted.
3. On return, the thread's `strex` **fails** (monitor cleared) and the loop retries with a freshly loaded `head`.

The ISR always completes, and the thread retries at most once per preemption. Nothing is masked, so interrupt latency is unaffected, which is the point (Folder 04 File 01).

**Where it stops:** across **cores**, exclusives on a shared RAM require a **global exclusive monitor** for that memory in the interconnect. Many MCU-class SoCs don't provide one for every RAM. Dual-core STM32H745/H755-class parts provide a hardware semaphore block (HSEM) for inter-core locking. ⚠ verify your SoC's reference manual for exclusive-access support per memory region before sharing a lock-free structure between cores. On Cortex-A/R SMP with coherent, cacheable memory, it works by construction.

### 1.4 Misuse detection at free time, and its limits

| Misuse | Detection | Response |
|---|---|---|
| Pointer not from this pool, or not a payload start | Range + modulo check | `LFP_EFOREIGN` |
| Overflow or underflow into a neighbor | `guard_head`/`guard_tail` mismatch | `LFP_EGUARD`; the block is **quarantined** (never re-listed), since its neighbors may be damaged |
| Double free | `state` CAS `USED → FREE`: exactly one freer can win | `LFP_EDOUBLE` |

**Limits, stated honestly:**

- **Double free** is detected only while the block is still free. Once it has been re-allocated, a stale second free *succeeds* and frees someone else's block. The fix is **generation-tagged handles** `{gen, idx}`, checked at free time: the same idea as the head tag.
- **Write-after-free inside the payload** is not detected (no MMU), but it *cannot* corrupt the allocator: links are out of band. Debug builds can poison freed payloads and check the poison on `alloc`.
- **Constant guard values** are predictable. Security-sensitive builds XOR them with a per-boot random canary.

### 1.5 The SPSC ring template

`LF_RING_DEFINE(name, T, CAP);` generates a type-safe ring for any element type:

- **Power-of-two `CAP`** is statically asserted. Head and tail are free-running `uint32_t`, so `head − tail` is the fill level even across 2^32, and `idx & (CAP − 1)` maps them to consecutive slots across the wrap (demo 4). With `% 3`, the slot sequence jumps at 2^32.
- **Release on publish, acquire on observe.** `commit` stores `head` with release: the slot write happens-before any consumer that acquires that `head`. `release` stores `tail` with release: the consumer's read of the slot happens-before the producer reuses it.
- **Cached opposite index.** The producer reads the consumer's `tail` only when its cached copy says "full" (and vice versa), so the shared line moves between cores only at apparent full/empty, not on every operation.
- **`LF_LINE = 64`**, even on a 32-byte-line M7. The ring may be shared with a Cortex-A core or placed where a 64-byte-line master reads it; on a single M7 it only costs padding.
- **Zero-copy:**
  - `reserve` returns a slot pointer; you build `T` in place, then `commit`.
  - `peek` returns a `const T *`; you use it in place, then `release`.
  - Between `reserve` and `commit` (or `peek` and `release`) the slot belongs to you alone.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

The pool and ring most codebases start with:

```c
/* lf_bad.h - interface of the naive pool and ring in lf_bad.c. */
#ifndef LF_BAD_H
#define LF_BAD_H

#include <stddef.h>
#include <stdint.h>

void  cpu_irq_disable(void);                 /* provided by the port (CPSID i) */
void  cpu_irq_enable(void);                  /* provided by the port (CPSIE i) */

void  bad_pool_init(void *mem, size_t bsize, size_t n);
void *bad_alloc(void);
void  bad_free(void *p);

void  bad_ring_seed(uint32_t start);
int   bad_push(uint32_t v);
int   bad_pop(uint32_t *v);

#endif /* LF_BAD_H */
```

```c
/* lf_bad.c - the pool and ring most codebases start with. Compiles warning-free. */
#include "lf_bad.h"

typedef struct free_node { struct free_node *next; } free_node_t;

static free_node_t *g_free;                  /* BUG 1: free list threaded THROUGH the
                                              *  payload: a write-after-free corrupts
                                              *  the allocator itself                 */

void bad_pool_init(void *mem, size_t bsize, size_t n)
{
    uint8_t *p = mem;
    g_free = NULL;
    for (size_t i = n; i-- > 0u; ) {
        free_node_t *f = (free_node_t *)(void *)(p + i * bsize);
        f->next = g_free;
        g_free = f;
    }
}

void *bad_alloc(void)
{
    cpu_irq_disable();                       /* BUG 2: "ISR-safe" by masking: no help
                                              *  against a second core or DMA, and ...  */
    free_node_t *f = g_free;
    if (f != NULL) {
        g_free = f->next;                    /* BUG 3: a bare-pointer head: the obvious
                                              *  CAS port of this is ABA-prone         */
    }
    cpu_irq_enable();                        /* ... an UNCONDITIONAL re-enable: a caller
                                              *  that had interrupts masked continues
                                              *  its critical section unmasked         */
    return f;
}

void bad_free(void *p)
{
    cpu_irq_disable();
    free_node_t *f = p;                      /* BUG 4: no ownership/state check: a double
                                              *  free lists the block twice            */
    f->next = g_free;
    g_free = f;
    cpu_irq_enable();
}

#define BAD_CAP 3u                           /* BUG 5: not a power of two ...          */
static uint32_t g_slot[BAD_CAP];
static volatile uint32_t g_head, g_tail;     /* BUG 6: volatile, no acquire/release:
                                              *  the slot write may be observed after
                                              *  the head update on a weak core        */

void bad_ring_seed(uint32_t start)
{
    g_head = start;
    g_tail = start;
}

int bad_push(uint32_t v)
{
    if ((g_head - g_tail) == BAD_CAP) {
        return 0;
    }
    g_slot[g_head % BAD_CAP] = v;            /* ... so with free-running indices the
                                              *  slot sequence jumps at 2^32           */
    g_head = g_head + 1u;
    return 1;
}

int bad_pop(uint32_t *v)
{
    if (g_head == g_tail) {
        return 0;
    }
    *v = g_slot[g_tail % BAD_CAP];
    g_tail = g_tail + 1u;
    return 1;
}
```

**Codegen (verified — Clang 21.1.0, -O2, thumbv7em-none-eabihf, Cortex-M7), `bad_push`:**

```asm
bad_push:
	movw	r12, :lower16:g_head
	movw	r2, :lower16:g_tail
	movt	r12, :upper16:g_head
	movt	r2, :upper16:g_tail
	ldr.w	r3, [r12]
	ldr	r2, [r2]
	subs	r2, r3, r2
	cmp	r2, #3
	bne	.LBB4_2
	movs	r0, #0
	bx	lr
.LBB4_2:
	ldr.w	r2, [r12]
	movw	r3, #43691
	movt	r3, #43690
	umull	r3, r1, r2, r3
	lsrs	r1, r1, #1
	add.w	r1, r1, r1, lsl #1
	subs	r1, r2, r1
	movw	r2, :lower16:g_slot
	movt	r2, :upper16:g_slot
	str.w	r0, [r2, r1, lsl #2]
	ldr.w	r0, [r12]
	adds	r0, #1
	str.w	r0, [r12]
	movs	r0, #1
	bx	lr
```

Read the listing:

- `% 3` became a multiply-by-reciprocal (`umull` with `0xAAAAAAAB`, shift, subtract): correct arithmetic, wrong algorithm at the wrap.
- `head` is re-read twice, as `volatile` demands.
- There is **no `dmb` anywhere**. On a multi-core or cache-coherent system, the slot store `str.w r0, [r2, r1, lsl #2]` may become visible after the `head` store.

**Four deterministic demonstrations**, each defect next to the production structure doing the same thing:

```c
/* lf_bad_demo.c - four deterministic, single-threaded demonstrations: each
 * defect of lf_bad.c next to the production pool/ring doing the same thing. */
#include <stdio.h>
#include <string.h>

#include "lf_bad.h"
#include "lf_pool.h"
#include "lf_ring.h"

static int g_irq_enabled = 1;                /* models PRIMASK */
void cpu_irq_disable(void) { g_irq_enabled = 0; }
void cpu_irq_enable(void)  { g_irq_enabled = 1; }

LFP_DECLARE_BLOCK(blk_t, 56);
LF_RING_DEFINE(r4, uint32_t, 4u);

static blk_t            g_st[8];
static _Atomic uint16_t g_ln[8];
static lf_pool_t        g_pool;
static alignas(8) uint8_t g_naive[8][64];
static r4_t             g_ring;
static struct { void *link; uint32_t value; } g_victim = { NULL, 42u };   /* live app object */

static int is_block(const void *p)
{
    for (unsigned i = 0u; i < 8u; i++) {
        if ((p == g_naive[i]) || (p == g_st[i].payload)) { return 1; }
    }
    return 0;
}

int main(void)
{
    /* 1. write-after-free: the app still uses `a` as its own list node and links
     *    it to a live object - the most common shape of a stale-pointer write */
    bad_pool_init(g_naive, sizeof g_naive[0], 8u);
    uint8_t *a = bad_alloc();
    bad_free(a);
    void *stale = &g_victim;
    memcpy(a, &stale, sizeof stale);
    void *n1 = bad_alloc(), *n2 = bad_alloc(), *n3 = bad_alloc();
    printf("[1] write-after-free  naive: alloc #2 returned %s; alloc #3 returned %s (6 of 8 blocks are free)\n",
           (n2 == (void *)&g_victim) ? "the LIVE global g_victim" : "a block",
           (n3 == NULL) ? "NULL" : "a block");
    (void)n1;
    (void)LFP_INIT(&g_pool, g_st, g_ln, blk_t);
    uint8_t *pa = lfp_alloc(&g_pool);
    (void)lfp_free(&g_pool, pa);
    memcpy(pa, &stale, sizeof stale);
    void *m1 = lfp_alloc(&g_pool), *m2 = lfp_alloc(&g_pool);
    printf("    production: links are out-of-band, both allocs are blocks: %s\n",
           (is_block(m1) && is_block(m2)) ? "yes" : "NO");

    /* 2. double free */
    bad_pool_init(g_naive, sizeof g_naive[0], 8u);
    uint8_t *d = bad_alloc();
    bad_free(d);
    bad_free(d);
    void *x = bad_alloc(), *y = bad_alloc();
    printf("[2] double free       naive: two allocations returned the SAME block: %s\n", (x == y) ? "yes" : "no");
    (void)LFP_INIT(&g_pool, g_st, g_ln, blk_t);
    uint8_t *pd = lfp_alloc(&g_pool);
    int r1 = (int)lfp_free(&g_pool, pd), r2 = (int)lfp_free(&g_pool, pd);
    void *px = lfp_alloc(&g_pool), *py = lfp_alloc(&g_pool);
    printf("    production: free=%d then %d (EDOUBLE), next two allocs distinct: %s\n",
           r1, r2, (px != py) ? "yes" : "NO");

    /* 3. interrupt-mask leak */
    cpu_irq_disable();                       /* caller is inside its own critical section */
    (void)bad_alloc();
    printf("[3] irq mask          naive: caller's interrupts still masked after bad_alloc(): %s\n",
           (g_irq_enabled == 0) ? "yes" : "NO");
    cpu_irq_disable();
    (void)lfp_alloc(&g_pool);
    printf("    production: never touches the mask, still masked: %s\n", (g_irq_enabled == 0) ? "yes" : "NO");
    cpu_irq_enable();

    /* 4. index wrap at 2^32 */
    bad_ring_seed(0xFFFFFFFEu);
    for (uint32_t v = 1u; v <= 3u; v++) { (void)bad_push(v); }
    printf("[4] wrap at 2^32      naive (CAP 3) pushed 1 2 3, popped:");
    for (uint32_t v; bad_pop(&v) != 0; ) { printf(" %u", (unsigned)v); }
    r4_init(&g_ring);
    atomic_store(&g_ring.head, 0xFFFFFFFEu); g_ring.tail_cache = 0xFFFFFFFEu;
    atomic_store(&g_ring.tail, 0xFFFFFFFEu); g_ring.head_cache = 0xFFFFFFFEu;
    for (uint32_t v = 1u; v <= 4u; v++) { (void)r4_push(&g_ring, v); }
    printf("\n    production (CAP 4) pushed 1 2 3 4, popped:");
    for (uint32_t v; r4_pop(&g_ring, &v); ) { printf(" %u", (unsigned)v); }
    printf("\n");
    return 0;
}
```

**Result (verified, host):**

```
[1] write-after-free  naive: alloc #2 returned the LIVE global g_victim; alloc #3 returned NULL (6 of 8 blocks are free)
    production: links are out-of-band, both allocs are blocks: yes
[2] double free       naive: two allocations returned the SAME block: yes
    production: free=0 then 2 (EDOUBLE), next two allocs distinct: yes
[3] irq mask          naive: caller's interrupts still masked after bad_alloc(): NO
    production: never touches the mask, still masked: yes
[4] wrap at 2^32      naive (CAP 3) pushed 1 2 3, popped: 1 3 3
    production (CAP 4) pushed 1 2 3 4, popped: 1 2 3 4
```

1. **Write-after-free.** The application still treats a freed block as its list node and links it to a live object. The naive allocator then **hands out the live global `g_victim` as a block**, and reports exhaustion with 6 of 8 blocks actually free. On an MCU the next user of that "block" overwrites unrelated state: a heisenbug far from its cause. The production pool is unaffected (links out of band).
2. **Double free.** The naive pool returns the **same block to two owners**. The production pool reports `EDOUBLE` and stays consistent.
3. **Interrupt-mask leak.** A caller inside its own critical section calls `bad_alloc()`, which ends with an unconditional `cpsie i`. The caller's critical section continues **unmasked**. The production pool never touches the mask.
4. **Wrap at 2^32.** With `CAP = 3`, pushing 1 2 3 across the wrap pops `1 3 3`: one item lost, one duplicated. With power-of-two `CAP = 4` it pops `1 2 3 4`. At 1,000 items/s, free-running indices reach 2^32 after **49.7 days** of uptime.

### 2.2 The Silicon-Hardened Production Way

**The pool:**

```c
/* lf_pool.h - lock-free, ISR-safe, O(1) fixed-block pool.
 *  - Free list = Treiber stack of block indices. The head is ONE 32-bit CAS
 *    word {tag, index}: lock-free on every core with 32-bit exclusives or CAS
 *    (Cortex-M3+ LDREX/STREX, AArch64, RISC-V A, x86) - no double-width CAS.
 *  - Bits go to the ABA tag, not the index: LFP_IDX_BITS = 8 gives up to 254
 *    blocks and a 24-bit tag (2^24 head updates before a wrap; Folder 05 File 02).
 *  - Guard words before and after every payload, and an atomic state word:
 *    overflow, underflow and double free are DETECTED at free time instead of
 *    silently corrupting the free list.
 *  - No locks, no interrupt masking: callable from any ISR priority and any
 *    core. (ARMv6-M has no exclusives: provide __atomic_* helpers, Folder 03.) */
#ifndef LF_POOL_H
#define LF_POOL_H

#include <stdalign.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef LFP_IDX_BITS
#define LFP_IDX_BITS 8u
#endif
#define LFP_IDX_MASK   ((1u << LFP_IDX_BITS) - 1u)
#define LFP_TAG_ONE    (1u << LFP_IDX_BITS)
#define LFP_NIL        LFP_IDX_MASK          /* all-ones index = empty list */
#define LFP_GUARD_HEAD 0xC0DEFACEu
#define LFP_GUARD_TAIL 0xFEEDBEEFu
#define LFP_FREE       0x46524545u           /* "FREE" */
#define LFP_USED       0x55534544u           /* "USED" */
_Static_assert((LFP_IDX_BITS >= 2u) && (LFP_IDX_BITS <= 16u), "index field width");

typedef enum { LFP_OK = 0, LFP_EFOREIGN, LFP_EDOUBLE, LFP_EGUARD } lfp_err_t;

#define LFP_DECLARE_BLOCK(name, payload_bytes)                                     \
    typedef struct {                                                               \
        uint32_t         guard_head;                                               \
        _Atomic uint32_t state;                                                    \
        alignas(8) uint8_t payload[(payload_bytes)];                               \
        uint32_t         guard_tail;                                               \
    } name

typedef struct {
    _Atomic uint32_t  head;                  /* [31:IDX_BITS] tag, [IDX_BITS-1:0] index */
    _Atomic uint16_t *next;                  /* next[i]: link of free block i            */
    uint8_t          *blocks;                /* nblocks * bsize bytes                    */
    size_t            bsize;                 /* sizeof(block type)                       */
    size_t            payload_off, payload_len, tail_off;
    uint16_t          nblocks;
    _Atomic uint32_t  in_use, peak;
    _Atomic uint32_t  guard_errors, double_frees;
} lf_pool_t;

#define LFP_INIT(pool, storage, links, blocktype)                                  \
    lfp_init((pool), (storage), (links), sizeof(blocktype),                        \
             offsetof(blocktype, payload), sizeof(((blocktype *)0)->payload),      \
             offsetof(blocktype, guard_tail),                                      \
             (uint16_t)(sizeof(storage) / sizeof(blocktype)))

static inline uint32_t *lfp_word(const lf_pool_t *p, uint16_t i, size_t off)
{
    return (uint32_t *)(void *)(p->blocks + (size_t)i * p->bsize + off);
}

static inline bool lfp_init(lf_pool_t *p, void *storage, _Atomic uint16_t *links,
                            size_t bsize, size_t payload_off, size_t payload_len,
                            size_t tail_off, uint16_t n)
{
    if ((n == 0u) || (n >= LFP_NIL)) {
        return false;                        /* index field too narrow for n blocks */
    }
    p->blocks = storage; p->next = links; p->bsize = bsize;
    p->payload_off = payload_off; p->payload_len = payload_len; p->tail_off = tail_off;
    p->nblocks = n;
    for (uint16_t i = 0u; i < n; i++) {
        *lfp_word(p, i, 0u) = LFP_GUARD_HEAD;
        atomic_init((_Atomic uint32_t *)(void *)lfp_word(p, i, 4u), LFP_FREE);
        *lfp_word(p, i, tail_off) = LFP_GUARD_TAIL;
        atomic_init(&links[i], (uint16_t)((i + 1u < n) ? (i + 1u) : LFP_NIL));
    }
    atomic_init(&p->head, 0u);               /* tag 0, index 0 */
    atomic_init(&p->in_use, 0u); atomic_init(&p->peak, 0u);
    atomic_init(&p->guard_errors, 0u); atomic_init(&p->double_frees, 0u);
    return true;
}

static inline void *lfp_alloc(lf_pool_t *p)
{
    uint32_t h = atomic_load_explicit(&p->head, memory_order_acquire);
    for (;;) {
        uint16_t idx = (uint16_t)(h & LFP_IDX_MASK);
        if (idx == LFP_NIL) {
            return NULL;                                           /* exhausted */
        }
        uint16_t nxt = atomic_load_explicit(&p->next[idx], memory_order_relaxed);
        uint32_t nh = ((h & ~LFP_IDX_MASK) + LFP_TAG_ONE) | nxt;   /* bump tag */
        if (atomic_compare_exchange_weak_explicit(&p->head, &h, nh,
                                                  memory_order_acq_rel, memory_order_acquire)) {
            _Atomic uint32_t *st = (_Atomic uint32_t *)(void *)lfp_word(p, idx, 4u);
            atomic_store_explicit(st, LFP_USED, memory_order_relaxed);
            uint32_t u = atomic_fetch_add_explicit(&p->in_use, 1u, memory_order_relaxed) + 1u;
            uint32_t pk = atomic_load_explicit(&p->peak, memory_order_relaxed);
            while ((u > pk) && !atomic_compare_exchange_weak_explicit(&p->peak, &pk, u,
                                                     memory_order_relaxed, memory_order_relaxed)) { }
            return p->blocks + (size_t)idx * p->bsize + p->payload_off;
        }                                                          /* h reloaded by CAS */
    }
}

static inline lfp_err_t lfp_free(lf_pool_t *p, void *payload)
{
    uintptr_t a = (uintptr_t)payload, lo = (uintptr_t)p->blocks;
    if ((a < lo + p->payload_off) || (a >= lo + (size_t)p->nblocks * p->bsize) ||
        (((a - lo - p->payload_off) % p->bsize) != 0u)) {
        return LFP_EFOREIGN;
    }
    uint16_t idx = (uint16_t)((a - lo - p->payload_off) / p->bsize);
    if ((*lfp_word(p, idx, 0u) != LFP_GUARD_HEAD) || (*lfp_word(p, idx, p->tail_off) != LFP_GUARD_TAIL)) {
        atomic_fetch_add_explicit(&p->guard_errors, 1u, memory_order_relaxed);
        return LFP_EGUARD;                   /* overflow/underflow: quarantine (never re-list) */
    }
    _Atomic uint32_t *st = (_Atomic uint32_t *)(void *)lfp_word(p, idx, 4u);
    uint32_t expect = LFP_USED;
    if (!atomic_compare_exchange_strong_explicit(st, &expect, LFP_FREE,
                                                 memory_order_acq_rel, memory_order_relaxed)) {
        atomic_fetch_add_explicit(&p->double_frees, 1u, memory_order_relaxed);
        return LFP_EDOUBLE;                  /* only ONE freer can win this CAS */
    }
    atomic_fetch_sub_explicit(&p->in_use, 1u, memory_order_relaxed);
    uint32_t h = atomic_load_explicit(&p->head, memory_order_relaxed);
    for (;;) {
        atomic_store_explicit(&p->next[idx], (uint16_t)(h & LFP_IDX_MASK), memory_order_relaxed);
        uint32_t nh = ((h & ~LFP_IDX_MASK) + LFP_TAG_ONE) | idx;
        if (atomic_compare_exchange_weak_explicit(&p->head, &h, nh,
                                                  memory_order_release, memory_order_relaxed)) {
            return LFP_OK;
        }
    }
}

#endif /* LF_POOL_H */
```

**The ring template:**

```c
/* lf_ring.h - type-generic, wait-free SPSC ring: the production template of
 * the uint32_t ring proved in Folder 05 File 02.
 *   LF_RING_DEFINE(name, T, CAP); defines name_t and
 *     name_init                          reset (before either side runs)
 *     name_push / name_pop               copy in / copy out
 *     name_reserve / name_commit         zero-copy producer: build T in place
 *     name_peek / name_release           zero-copy consumer: read T in place
 *  - CAP is a power of two; head/tail are free-running uint32_t, so
 *    (head - tail) is the fill level across wrap.
 *  - Producer and consumer state live on separate cache lines; each side caches
 *    the other's index, so the shared line moves only on apparent full/empty.
 *  - Exactly ONE producer context and ONE consumer context (an ISR, a task, or
 *    a core each). A second producer needs a second ring, or Vyukov MPMC. */
#ifndef LF_RING_H
#define LF_RING_H

#include <stdalign.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef LF_LINE
#define LF_LINE 64u                          /* worst-case line of any core touching it */
#endif

#define LF_RING_DEFINE(name, T, CAP)                                               \
    typedef struct {                                                               \
        alignas(LF_LINE) _Atomic uint32_t head;  /* producer writes               */ \
        uint32_t tail_cache;                     /* producer-private              */ \
        alignas(LF_LINE) _Atomic uint32_t tail;  /* consumer writes               */ \
        uint32_t head_cache;                     /* consumer-private              */ \
        alignas(LF_LINE) T slot[(CAP)];                                            \
    } name##_t;                                                                    \
    static inline void name##_init(name##_t *q)                                    \
    {                                                                              \
        atomic_init(&q->head, 0u); q->tail_cache = 0u;                             \
        atomic_init(&q->tail, 0u); q->head_cache = 0u;                             \
    }                                                                              \
    static inline T *name##_reserve(name##_t *q)                                   \
    {                                                                              \
        uint32_t h = atomic_load_explicit(&q->head, memory_order_relaxed);         \
        if ((h - q->tail_cache) == (uint32_t)(CAP)) {          /* looks full */    \
            q->tail_cache = atomic_load_explicit(&q->tail, memory_order_acquire);  \
            if ((h - q->tail_cache) == (uint32_t)(CAP)) {                          \
                return NULL;                                                       \
            }                                                                      \
        }                                                                          \
        return &q->slot[h & ((uint32_t)(CAP) - 1u)];                               \
    }                                                                              \
    static inline void name##_commit(name##_t *q)              /* after reserve */ \
    {                                                                              \
        uint32_t h = atomic_load_explicit(&q->head, memory_order_relaxed);         \
        atomic_store_explicit(&q->head, h + 1u, memory_order_release);             \
    }                                                                              \
    static inline bool name##_push(name##_t *q, T v)                               \
    {                                                                              \
        T *s = name##_reserve(q);                                                  \
        if (s == NULL) {                                                           \
            return false;                                                          \
        }                                                                          \
        *s = v;                                                                    \
        name##_commit(q);                                                          \
        return true;                                                               \
    }                                                                              \
    static inline const T *name##_peek(name##_t *q)                                \
    {                                                                              \
        uint32_t t = atomic_load_explicit(&q->tail, memory_order_relaxed);         \
        if (t == q->head_cache) {                              /* looks empty */   \
            q->head_cache = atomic_load_explicit(&q->head, memory_order_acquire);  \
            if (t == q->head_cache) {                                              \
                return NULL;                                                       \
            }                                                                      \
        }                                                                          \
        return &q->slot[t & ((uint32_t)(CAP) - 1u)];                               \
    }                                                                              \
    static inline void name##_release(name##_t *q)             /* after peek */    \
    {                                                                              \
        uint32_t t = atomic_load_explicit(&q->tail, memory_order_relaxed);         \
        atomic_store_explicit(&q->tail, t + 1u, memory_order_release);             \
    }                                                                              \
    static inline bool name##_pop(name##_t *q, T *out)                             \
    {                                                                              \
        const T *s = name##_peek(q);                                               \
        if (s == NULL) {                                                           \
            return false;                                                          \
        }                                                                          \
        *out = *s;                                                                 \
        name##_release(q);                                                         \
        return true;                                                               \
    }                                                                              \
    _Static_assert((((uint32_t)(CAP)) & ((uint32_t)(CAP) - 1u)) == 0u,             \
                   #name ": capacity must be a power of two")

#endif /* LF_RING_H */
```

**Instantiation unit** used for the per-target compile checks and the listings:

```c
/* lf_tu.c - instantiation unit for codegen and per-target compile checks. */
#include "lf_pool.h"
#include "lf_ring.h"

LFP_DECLARE_BLOCK(blk_t, 56);
LF_RING_DEFINE(hring, uint16_t, 64u);

static blk_t            g_st[32];
static _Atomic uint16_t g_ln[32];
lf_pool_t               g_p;
hring_t                 g_r;

bool  pinit(void);
void *palloc(void);
int   pfree(void *q);
bool  rpush(uint16_t v);
bool  rpop(uint16_t *v);

bool  pinit(void)        { hring_init(&g_r); return LFP_INIT(&g_p, g_st, g_ln, blk_t); }
void *palloc(void)       { return lfp_alloc(&g_p); }
int   pfree(void *q)     { return (int)lfp_free(&g_p, q); }
bool  rpush(uint16_t v)  { return hring_push(&g_r, v); }
bool  rpop(uint16_t *v)  { return hring_pop(&g_r, v); }
```

**Codegen (verified — Clang 21.1.0, -O2, thumbv7em-none-eabihf, Cortex-M7), `palloc` = `lfp_alloc` inlined:**

```asm
palloc:
	push	{r4, r5, r6, lr}
	movw	r1, :lower16:g_p
	movw	r12, #17732
	movt	r1, :upper16:g_p
	movt	r12, #21843
	ldr	r3, [r1]
	dmb	sy
	b	.LBB1_3
.LBB1_1:
	ldrd	r3, r0, [r1, #8]
	mla	r0, r0, r2, r3
	ldr	r2, [r1, #16]
	add	r0, r2
.LBB1_2:
	cmp.w	lr, #0
	mov	r3, r6
	bne.w	.LBB1_28
.LBB1_3:
	uxtb	r2, r3
	cmp	r2, #255
	beq.w	.LBB1_27
	ldr	r6, [r1, #4]
	ldrh.w	r5, [r6, r2, lsl #1]
	ldrex	r6, [r1]
	cmp	r6, r3
	bne	.LBB1_6
	bic	r3, r3, #255
	add.w	r3, r3, #256
	dmb	sy
	orrs	r3, r5
	strex	r5, r3, [r1]
	movs	r3, #0
	cmp	r5, #0
	it	eq
	moveq.w	r3, #-1
	b	.LBB1_7
.LBB1_6:
	clrex
	movs	r3, #0
.LBB1_7:
	dmb	sy
	lsls.w	lr, r3, #31
	beq	.LBB1_2
	ldrd	r0, r3, [r1, #8]
	mla	r0, r3, r2, r0
	str.w	r12, [r0, #4]
.LBB1_9:
	ldrex	r0, [r1, #32]
	adds	r0, #1
	strex	r3, r0, [r1, #32]
	cmp	r3, #0
	bne	.LBB1_9
	ldr	r4, [r1, #36]
	b	.LBB1_12
.LBB1_11:
	clrex
	movs	r3, #0
	lsls	r3, r3, #31
	bne	.LBB1_1
.LBB1_12:
	cmp	r0, r4
	bls	.LBB1_1
	ldrex	r5, [r1, #36]
	cmp	r5, r4
	bne	.LBB1_15
	strex	r3, r0, [r1, #36]
	cmp	r3, #0
	mov.w	r3, #0
	it	eq
	moveq.w	r3, #-1
	lsls	r3, r3, #31
	beq	.LBB1_16
	b	.LBB1_1
.LBB1_15:
	clrex
	movs	r3, #0
	lsls	r3, r3, #31
	bne	.LBB1_1
.LBB1_16:
	cmp	r0, r5
	bls	.LBB1_1
	ldrex	r4, [r1, #36]
	cmp	r4, r5
	bne	.LBB1_19
	strex	r3, r0, [r1, #36]
	cmp	r3, #0
	mov.w	r3, #0
	it	eq
	moveq.w	r3, #-1
	lsls	r3, r3, #31
	beq	.LBB1_20
	b	.LBB1_1
.LBB1_19:
	clrex
	movs	r3, #0
	lsls	r3, r3, #31
	bne.w	.LBB1_1
.LBB1_20:
	cmp	r0, r4
	bls.w	.LBB1_1
	ldrex	r5, [r1, #36]
	cmp	r5, r4
	bne	.LBB1_23
	strex	r3, r0, [r1, #36]
	cmp	r3, #0
	mov.w	r3, #0
	it	eq
	moveq.w	r3, #-1
	lsls	r3, r3, #31
	beq	.LBB1_24
	b	.LBB1_1
.LBB1_23:
	clrex
	movs	r3, #0
	lsls	r3, r3, #31
	bne.w	.LBB1_1
.LBB1_24:
	cmp	r0, r5
	bls.w	.LBB1_1
	ldrex	r4, [r1, #36]
	cmp	r4, r5
	bne	.LBB1_11
	strex	r3, r0, [r1, #36]
	cmp	r3, #0
	mov.w	r3, #0
	it	eq
	moveq.w	r3, #-1
	lsls	r3, r3, #31
	beq	.LBB1_12
	b	.LBB1_1
.LBB1_27:
	movs	r0, #0
.LBB1_28:
	pop	{r4, r5, r6, pc}
```

How to read it:

- `ldr` + `dmb sy` is the initial acquire load of `head`.
- `uxtb`/`cmp #255` is the NIL check on the 8-bit index.
- The CAS itself:
  1. `ldrh` of `next[idx]` *before* the exclusive section;
  2. `ldrex` of `head`, compared with the expected value (mismatch → `clrex`, retry);
  3. the new head: `bic #255` (keep the tag), `add.w #256` (tag + 1), `orr` (new index);
  4. `dmb sy` (release half of `acq_rel`), then `strex`, then `dmb sy` (acquire half).
- `str.w r12, [r0, #4]` is the relaxed `state = USED` store (`0x55534544`).
- The relaxed `in_use` increment is a plain `ldrex`/`adds`/`strex` loop with **no** barriers.
- The `peak` CAS loop was unrolled four times by the optimizer.

**Codegen (verified, same flags), `rpush` and `rpop`** (ring of `uint16_t`, CAP 64):

```asm
rpush:
	movw	r1, :lower16:g_r
	movt	r1, :upper16:g_r
	ldr	r2, [r1]
	ldr	r3, [r1, #4]
	subs	r3, r2, r3
	cmp	r3, #64
	bne	.LBB3_3
	ldr.w	r12, [r1, #64]
	dmb	sy
	sub.w	r3, r2, r12
	str.w	r12, [r1, #4]
	cmp	r3, #64
	bne	.LBB3_3
	movs	r0, #0
	bx	lr
.LBB3_3:
	and	r2, r2, #63
	add.w	r2, r1, r2, lsl #1
	strh.w	r0, [r2, #128]
	ldr	r0, [r1]
	dmb	sy
	adds	r0, #1
	str	r0, [r1]
	movs	r0, #1
	bx	lr
```

```asm
rpop:
	movw	r1, :lower16:g_r
	movt	r1, :upper16:g_r
	ldr	r2, [r1, #64]
	ldr	r3, [r1, #68]
	cmp	r2, r3
	bne	.LBB4_3
	ldr	r3, [r1]
	dmb	sy
	cmp	r2, r3
	str	r3, [r1, #68]
	bne	.LBB4_3
	movs	r0, #0
	bx	lr
.LBB4_3:
	and	r2, r2, #63
	add.w	r2, r1, r2, lsl #1
	ldrh.w	r2, [r2, #128]
	strh	r2, [r0]
	ldr	r0, [r1, #64]
	dmb	sy
	adds	r0, #1
	str	r0, [r1, #64]
	movs	r0, #1
	bx	lr
```

The layout is visible in the offsets: `head` at +0, `tail_cache` at +4, `tail` at **+64**, `head_cache` at +68, slots at **+128**, each side on its own 64-byte line.

- **Acquire** of the other side's index = `ldr` then `dmb sy`. It is executed **only on the slow path**, when the cached copy says full or empty.
- **Publish** = `strh` of the slot, then `dmb sy`, then `str` of the incremented index (release).
- The fast path of `rpush` has exactly one `dmb`.

**Codegen (verified — Clang 21.1.0, -O2, aarch64-none-elf, `-march=armv8.4-a`), the same `palloc` with LSE atomics:**

```asm
palloc:
	adrp	x8, g_p
	add	x8, x8, :lo12:g_p
	mov	w10, #17732
	ldapr	w16, [x8]
	adrp	x9, g_p+16
	add	x9, x9, :lo12:g_p+16
	movk	w10, #21843, lsl #16
	mov	w11, #1
	adrp	x12, g_p+64
	add	x12, x12, :lo12:g_p+64
	b	.LBB1_3
.LBB1_1:
	ldp	x17, x16, [x9]
	madd	x13, x16, x13, x17
	ldr	x16, [x9, #16]
	add	x0, x13, x16
.LBB1_2:
	mov	w16, w14
	cbnz	w15, .LBB1_9
.LBB1_3:
	and	w13, w16, #0xff
	cmp	w13, #255
	b.eq	.LBB1_8
	ldr	x14, [x8, #8]
	and	w15, w16, #0xffffff00
	add	w15, w15, #256
	ldrh	w14, [x14, w13, uxtw #1]
	orr	w15, w15, w14
	mov	w14, w16
	casal	w14, w15, [x8]
	cmp	w14, w16
	cset	w15, eq
	b.ne	.LBB1_2
	ldp	x17, x16, [x9]
	madd	x16, x16, x13, x17
	str	w10, [x16, #4]
	add	x16, x9, #44
	ldadd	w11, w16, [x16]
	ldr	w17, [x9, #48]
	add	w16, w16, #1
.LBB1_6:
	cmp	w16, w17
	b.ls	.LBB1_1
	mov	w18, w17
	cas	w18, w16, [x12]
	cmp	w18, w17
	mov	w17, w18
	b.ne	.LBB1_6
	b	.LBB1_1
.LBB1_8:
	mov	x0, xzr
.LBB1_9:
	ret
```

On v8.4-A the barriers disappear into the instructions:

- `ldapr` (RCpc acquire load) for the initial `head` load;
- **`casal`** (single-instruction CAS, acquire + release) for the head update;
- **`ldadd`** (relaxed far atomic) for `in_use`;
- **`cas`** (relaxed) for `peak`.

There's no retry loop around `casal` beyond the algorithmic one, and no `dmb`. LSE atomics can execute *at* the interconnect (far atomics), which is why contended counters scale far better than LL/SC on Neoverse-class systems (Folder 05 File 02, Q4).

**Stress test** (4 threads, one pool, two rings, both ring APIs, pool run dry):

```c
/* lf_stress.c - four threads, ONE shared lock-free pool, two SPSC rings:
 *     P0 --ring0--> C0        producers allocate a block, fill it, send its
 *     P1 --ring1--> C1        8-bit handle; consumers verify and free it to
 *                             the same pool (the pool sees 4-way contention).
 * P0 uses copy-in push, P1 zero-copy reserve/commit; C0 pop, C1 peek/release.
 * Rings hold 2 x 64 handles but the pool has only 64 blocks, so producers
 * also run the pool dry. Checks exactly-once delivery, per-ring FIFO order,
 * payload integrity, pool conservation, and every misuse detector. */
#include <stdio.h>
#include <string.h>
#include <windows.h>

#include "lf_pool.h"
#include "lf_ring.h"

LFP_DECLARE_BLOCK(msg_block_t, 56);
LF_RING_DEFINE(hring, uint16_t, 64u);

#define NBLK         64u
#define PER_PRODUCER 500000u

static msg_block_t      g_storage[NBLK];
static _Atomic uint16_t g_links[NBLK];
static lf_pool_t        g_pool;
static hring_t          g_ring[2];
static _Atomic uint32_t g_delivered, g_corrupt, g_order, g_exhausted;

static uint16_t handle_of(const uint8_t *payload)
{
    return (uint16_t)((size_t)(payload - g_storage[0].payload) / sizeof(msg_block_t));
}

static DWORD WINAPI producer(LPVOID arg)
{
    uint32_t id = (uint32_t)(uintptr_t)arg;
    for (uint32_t i = 0u; i < PER_PRODUCER; ) {
        uint8_t *m = lfp_alloc(&g_pool);
        if (m == NULL) {
            atomic_fetch_add_explicit(&g_exhausted, 1u, memory_order_relaxed);
            continue;
        }
        uint32_t tag = (id << 24) | i;
        memcpy(m, &tag, 4u);
        for (uint32_t k = 4u; k < 56u; k++) { m[k] = (uint8_t)(tag * 31u + k); }
        if (id == 0u) {
            while (!hring_push(&g_ring[0], handle_of(m))) { }
        } else {
            uint16_t *slot;
            while ((slot = hring_reserve(&g_ring[1])) == NULL) { }
            *slot = handle_of(m);                     /* built in place */
            hring_commit(&g_ring[1]);
        }
        i++;
    }
    return 0;
}

static DWORD WINAPI consumer(LPVOID arg)
{
    uint32_t id = (uint32_t)(uintptr_t)arg;
    for (uint32_t expect = 0u; expect < PER_PRODUCER; ) {
        uint16_t h;
        if (id == 0u) {
            if (!hring_pop(&g_ring[0], &h)) { continue; }
        } else {
            const uint16_t *s = hring_peek(&g_ring[1]);
            if (s == NULL) { continue; }
            h = *s;                                   /* read in place */
            hring_release(&g_ring[1]);
        }
        uint8_t *m = g_storage[h].payload;
        uint32_t tag;
        memcpy(&tag, m, 4u);
        if (tag != ((id << 24) | expect)) { atomic_fetch_add(&g_order, 1u); }
        for (uint32_t k = 4u; k < 56u; k++) {
            if (m[k] != (uint8_t)(tag * 31u + k)) { atomic_fetch_add(&g_corrupt, 1u); break; }
        }
        if (lfp_free(&g_pool, m) != LFP_OK) { atomic_fetch_add(&g_corrupt, 1u); }
        atomic_fetch_add_explicit(&g_delivered, 1u, memory_order_relaxed);
        expect++;
    }
    return 0;
}

int main(void)
{
    if (!LFP_INIT(&g_pool, g_storage, g_links, msg_block_t)) { return 1; }
    hring_init(&g_ring[0]);
    hring_init(&g_ring[1]);
    HANDLE t[4] = { CreateThread(NULL, 0, producer, (LPVOID)(uintptr_t)0u, 0, NULL),
                    CreateThread(NULL, 0, producer, (LPVOID)(uintptr_t)1u, 0, NULL),
                    CreateThread(NULL, 0, consumer, (LPVOID)(uintptr_t)0u, 0, NULL),
                    CreateThread(NULL, 0, consumer, (LPVOID)(uintptr_t)1u, 0, NULL) };
    WaitForMultipleObjects(4, t, TRUE, INFINITE);
    printf("messages=%u fifo-violations=%u corrupt=%u in_use_after=%u peak=%u/%u pool-dry-retries>0:%s\n",
           (unsigned)atomic_load(&g_delivered), (unsigned)atomic_load(&g_order),
           (unsigned)atomic_load(&g_corrupt), (unsigned)atomic_load(&g_pool.in_use),
           (unsigned)atomic_load(&g_pool.peak), (unsigned)NBLK,
           (atomic_load(&g_exhausted) > 0u) ? "yes" : "no");

    uint32_t free_count = 0u;                         /* conservation: walk the free list */
    for (uint16_t i = (uint16_t)(atomic_load(&g_pool.head) & LFP_IDX_MASK); i != LFP_NIL;
         i = atomic_load(&g_links[i])) {
        if (++free_count > NBLK) { break; }
    }
    printf("free list holds %u of %u blocks; head tag advanced to %u (24-bit tag)\n",
           (unsigned)free_count, (unsigned)NBLK, (unsigned)(atomic_load(&g_pool.head) >> LFP_IDX_BITS));

    uint8_t *a = lfp_alloc(&g_pool);
    int f1 = (int)lfp_free(&g_pool, a);
    int f2 = (int)lfp_free(&g_pool, a);
    printf("double free: first=%d second=%d (EDOUBLE=2)\n", f1, f2);
    uint8_t *b = lfp_alloc(&g_pool);
    memset(b, 0x55, 60u);                             /* 4-byte overflow into guard_tail */
    printf("overflow  -> %d (EGUARD=3)\n", (int)lfp_free(&g_pool, b));
    uint8_t *c = lfp_alloc(&g_pool);
    memset(c - 8, 0x55, 4u);                          /* underflow into guard_head */
    printf("underflow -> %d (EGUARD=3), guard_errors=%u, quarantined blocks stay out of the pool\n",
           (int)lfp_free(&g_pool, c), (unsigned)atomic_load(&g_pool.guard_errors));
    printf("foreign   -> %d (EFOREIGN=1); misaligned interior pointer -> %d\n",
           (int)lfp_free(&g_pool, &free_count), (int)lfp_free(&g_pool, g_storage[3].payload + 1));
    return 0;
}
```

**Result (verified, one run on the author's x86-64 laptop):**

```
messages=1000000 fifo-violations=0 corrupt=0 in_use_after=0 peak=64/64 pool-dry-retries>0:yes
free list holds 64 of 64 blocks; head tag advanced to 2000000 (24-bit tag)
double free: first=0 second=2 (EDOUBLE=2)
overflow  -> 3 (EGUARD=3)
underflow -> 3 (EGUARD=3), guard_errors=2, quarantined blocks stay out of the pool
foreign   -> 1 (EFOREIGN=1); misaligned interior pointer -> 1
```

What it shows:

- 1,000,000 messages delivered **exactly once**, with per-ring FIFO order intact and no payload corrupted.
- `peak = 64/64` with `pool-dry-retries > 0`: the producers really did exhaust the pool and recover.
- **Conservation:** after the run, `in_use = 0` and a walk of the free list finds all 64 blocks.
- The tag advanced exactly 2,000,000: one per successful alloc and per free.
- Every misuse detector fired: double free (`2`), overflow and underflow (`3`, both quarantined), foreign pointer and misaligned interior pointer (`1`).

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Tooling |
|---|---|---|
| Pool reports exhausted, but load is light | Leak (missing free), or a free-list corruption (naive pool) | Export `in_use`/`peak`; walk the free list (as in the stress test) and compare count + `in_use` with N; a mismatch means corruption |
| Two subsystems corrupt the same buffer | Double free (naive pool), or a stale free after reuse | `double_frees` counter; generation-tagged handles; log the caller's LR in `lfp_free` on error |
| `guard_errors` increments | Overflow/underflow by the previous owner | Set a **DWT data watchpoint** (`DWT_COMPn` = address of the guard word, `DWT_FUNCTIONn` = write) on a suspect block's `guard_tail`: the core halts or takes a DebugMonitor exception **at the culprit store**, with its PC |
| Ring loses or duplicates an item after weeks of uptime | Non-power-of-two capacity with free-running indices (§2.1, demo 4): 49.7 days at 1 kHz, 71.6 min at 1 MHz | Static-assert power-of-two `CAP`; to test, seed indices at `0xFFFFFFFE` (demo 4) instead of waiting |
| Rare reordering of ring data on a dual-core or Cortex-A system, never on a single M4 | `volatile` indices without acquire/release | Listing review: look for the `dmb` (or `stlr`/`ldar`) between the slot write and the index publish |
| Interrupt latency spikes when the pool is busy | Allocator masks interrupts | Measure with DWT `CYCCNT` at ISR entry; a lock-free pool doesn't touch PRIMASK |
| Corruption only when an M4 and an M7 core share a structure | No global exclusive monitor on that RAM (§1.3) | Check the RM's exclusive-access support; use HSEM-protected or message-passing designs ⚠ verify |

**Live observability:** `in_use`, `peak`, `guard_errors` and `double_frees` are plain atomics. Debuggers with background memory access (Ozone, Trace32, J-Link RTT viewers) can graph them while the system runs. `peak` against N is the sizing evidence a design review needs.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Design an allocator that any ISR on a Cortex-M7 can call, without masking interrupts."

- **L5:** "A fixed-block pool with a linked free list; disable interrupts around the list operations."
- **Why L5 fails on real hardware:**
  - Masking adds the allocator's worst case to *every* interrupt's latency, and it protects nothing against a second core or a DMA engine.
  - The usual `cpsid`/`cpsie` pair re-enables interrupts inside callers that had them masked (verified, demo 3).
  - A free list threaded through the payload turns every write-after-free into allocator corruption (verified: the naive pool handed out a live global).
- **L7 principal defense:**
  - A Treiber stack of **indices** with a `{tag:24, idx:8}` head in one 32-bit CAS word (no LDREXD on M-profile), with links out of band.
  - The exclusive monitor is cleared on exception entry, so a preempted thread's `strex` fails and retries; the ISR always completes.
  - Guards plus a state-word CAS detect overflow and double free at free time; corrupted blocks are quarantined.
  - Verified: 1,000,000 messages across 4 threads with conservation checked by walking the free list; M7 listing `ldrex … dmb; strex … dmb`.
  - State the limits: cross-core exclusives need a global monitor (HSEM otherwise); a stale free after reuse needs generation handles.

### Q2 🔥 "Your lock-free stack has an ABA tag. How long until it wraps, and does that matter?"

- **L5:** "It's 16 bits; it'll never wrap in practice."
- **Why L5 fails:** "In practice" means "unless a low-priority task is starved". At 100k pool operations/s, a 16-bit tag wraps in 0.66 s, well within a starvation episode. ABA then needs the same index on top at the exact tag, which is rare. *Rare* in a fleet of millions of devices means *weekly*.
- **L7 defense:**
  - Spend bits on the tag: size the index field to the pool (8 bits → 254 blocks) and get a 24-bit tag (168 s at the same rate).
  - On 64-bit cores use a 64-bit head with a 32-bit tag.
  - Verified: the tag advances once per successful update (exactly 2,000,000 after 1M round-trips), so the wrap budget is computable from the operation rate.

### Q3 "Why is your ring capacity a power of two? Isn't that just for speed?"

- **L5:** "`&` is faster than `%`."
- **Why L5 fails:** It's for **correctness**. With free-running 32-bit indices, `idx % CAP` is continuous across 2^32 only if CAP divides 2^32, which means a power of two. Otherwise the slot sequence jumps at the wrap. Verified: CAP 3 seeded at `0xFFFFFFFE` popped `1 3 3`. At 1 kHz that's day 49.7 of uptime: the classic "49.7-day bug" class.
- **L7 defense:**
  - `_Static_assert` power-of-two CAP inside the template, so a wrong instantiation fails to compile.
  - Free-running indices with `head − tail` as the fill level.
  - Test the wrap by seeding indices near 2^32 instead of waiting (demo 4).

### Q4 "Can two ISRs at different priorities both push into your SPSC ring?"

- **L5:** "Yes, the operations are atomic."
- **Why L5 fails:** Each *index update* is atomic. The *operation* is not:
  1. ISR A reads `head = h` and writes slot *h*.
  2. ISR B preempts, also reads `head = h`, writes slot *h*, and publishes `h + 1`.
  3. A resumes and publishes `h + 1` too.
  One element is lost and one slot is overwritten.
- **L7 defense:**
  - SPSC means one producer *context*. Give each producer its own ring (the stress test uses two), or use the Vyukov MPMC queue (Folder 05 File 02).
  - Or reserve the ring for the highest-priority producer and funnel the others through it.
  - Document the contract in the type name.

### Q5 🧊 "Can the M7 and M4 cores of a dual-core MCU share your lock-free pool?"

- **L5:** "Yes, both have LDREX/STREX."
- **Why L5 fails:** LDREX/STREX across cores require the memory's interconnect to implement a **global exclusive monitor**. Without one, a `strex` can succeed on both cores for the same location, or exclusives may not be supported on that RAM at all. Many MCU SoCs provide a hardware semaphore block for exactly this reason. Caches add a second problem: the M7's D-cache isn't coherent with the M4.
- **L7 defense:**
  - Check the reference manual for exclusive-access support per memory region and master ⚠ verify.
  - Put shared structures in non-cacheable memory (File 01's MPU map).
  - Without a global monitor, use HSEM-guarded critical sections, or a per-direction SPSC ring (single writer per index, which needs only ordered stores, not exclusives) with explicit cache maintenance or NC memory, plus an inter-core interrupt for wakeup.

---

## 5. Invariants Checklist

- [ ] Pool head is one CAS word `{tag, index}`; index width sized to the pool; tag wrap budget computed from the worst-case operation rate and the longest starvation of the lowest-priority user.
- [ ] Free-list links out of band (`next[]`), never inside payloads.
- [ ] Every free validated: range, alignment, guards, state CAS. Corrupted blocks quarantined, never re-listed. Counters exported.
- [ ] No interrupt masking in the pool or the ring.
- [ ] Ring capacity power-of-two (static assert); free-running indices; release on publish, acquire on observe; producer and consumer state on separate lines.
- [ ] Exactly one producer and one consumer context per SPSC ring, enforced by design (one ring per producer).
- [ ] Cross-core sharing only with a global exclusive monitor (or HSEM) and non-cacheable or coherent memory ⚠ verify per SoC.
- [ ] Tests: multi-threaded stress with conservation checks, pool exhaustion, the wrap seeded near 2^32, and misuse detection.

## 6. References

1. ISO/IEC 9899:2018, §5.1.2.4 (multi-threaded executions and data races) and §7.17 (atomics).
2. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E), A3.4: synchronization and semaphores, local and global exclusive monitors.
3. Arm, *Cortex-M4 Devices Generic User Guide* (DUI 0553) and *Cortex-M7 Devices Generic User Guide* (DUI 0646): LDREX/STREX/CLREX and exclusive-tag clearing on exception.
4. Arm, *ARMv8-A Architecture Reference Manual* (DDI 0487): LSE atomics (CAS, LDADD), RCpc `LDAPR` (v8.3).
5. R. K. Treiber, *Systems Programming: Coping with Parallelism*, IBM Research Report RJ 5118, 1986.
6. M. Herlihy, N. Shavit, *The Art of Multiprocessor Programming*: ABA and tagged references.
7. Zephyr RTOS `kernel/mem_slab.c` (`k_mem_slab`); FreeRTOS `stream_buffer.c`; DPDK `lib/ring` (`rte_ring`); Linux `include/linux/kfifo.h`.
8. STMicroelectronics, *RM0399* (STM32H745/755/747/757): hardware semaphore (HSEM) and inter-core sharing ⚠ verify exclusive-access support per memory.
9. Folder 03 File 02 (memory-order matrix and litmus tests), Folder 05 File 02 (SPSC, MPMC, ABA reproduction).
