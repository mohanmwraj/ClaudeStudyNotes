# 01 · Custom Slab, Pool, and Arena Allocators, and Preventing Fragmentation

> **Folder:** `05-Deterministic-Memory-and-Lock-Free-Data-Structures/` · **File 1 of 3**
> **Anchors:**
> - P. Wilson, M. Johnstone, M. Neely, D. Boles, *Dynamic Storage Allocation: A Survey and Critical Review* (IWMM 1995).
> - J. Bonwick, *The Slab Allocator* (USENIX 1994).
> - M. Masmano et al., *TLSF: a New Dynamic Memory Allocator for Real-Time Systems* (ECRTS 2004).
> - MISRA C:2012 Rule 21.3 (no `<stdlib.h>` memory allocation); ISO 26262-6 and DO-178C guidance on dynamic memory.
> - Linux `mm/slub.c`; FreeRTOS `heap_1`–`heap_5`; Zephyr `k_mem_slab`.
>
> **Verification:**
> - A deterministic fragmentation experiment: an adversarial pattern and a 400,000-step heavy-tailed random churn against a first-fit coalescing heap, plus analytic pool sizing.
> - A size-class slab allocator with double-free and foreign-pointer detection, and an aligned arena. Both compiled warning-free on Cortex-M0+/M7/AArch64/x86-64, with self-tests run.
> - All outputs inserted verbatim.

---

## 0. The thesis

A general-purpose heap answers "give me *n* bytes" with **unbounded time** (searching) and **unbounded failure** (fragmentation) behavior. Neither is acceptable in code with deadlines or certification requirements. Deterministic allocators trade *memory* and *generality* for **O(1) time and failure modes you can prove absent by analysis**. The L7 skill is to choose the allocator per lifetime pattern:
- **arena** for phase-scoped data;
- **pool/slab** for fixed-size objects;
- **TLSF** where variable sizes are unavoidable;
- **nothing at all** (static allocation) where it can be avoided.

---

## 1. First-Principles Mechanics

### 1.1 What fragmentation is, measured

**External fragmentation:** free memory exists, but not in one piece large enough for a request.

**Internal fragmentation:** an allocated block is larger than the request (size-class rounding, alignment, headers).

```c
/* frag_sim.c - external fragmentation, measured, and the determinism/memory
 * trade-off of fixed-block pools.
 *   1. Adversarial interleaving: free memory is plentiful but unusable.
 *   2. Heavy-tailed random churn against a first-fit coalescing heap.
 *   3. The same churn against size-class pools sized BY ANALYSIS (worst-case
 *      concurrency per class from a dry run): zero failures, more memory. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define ARENA   16384u
#define SLOTS   64u
#define STEPS   400000u

typedef struct blk { uint32_t size; uint32_t free; struct blk *next; } blk_t;
static _Alignas(16) uint8_t heap_mem[ARENA];
static blk_t *heap_head;

static void heap_init(void)
{
    heap_head = (blk_t *)(void *)heap_mem;
    heap_head->size = ARENA - (uint32_t)sizeof(blk_t);
    heap_head->free = 1u;
    heap_head->next = NULL;
}

static void *heap_alloc(uint32_t n)
{
    n = (n + 15u) & ~15u;
    for (blk_t *b = heap_head; b != NULL; b = b->next) {
        if (b->free && b->size >= n) {
            if (b->size >= n + (uint32_t)sizeof(blk_t) + 16u) {
                blk_t *r = (blk_t *)(void *)((uint8_t *)(b + 1) + n);
                r->size = b->size - n - (uint32_t)sizeof(blk_t);
                r->free = 1u;
                r->next = b->next;
                b->next = r;
                b->size = n;
            }
            b->free = 0u;
            return b + 1;
        }
    }
    return NULL;
}

static void heap_free(void *p)
{
    blk_t *b = (blk_t *)p - 1;
    b->free = 1u;
    for (blk_t *c = heap_head; c != NULL; c = c->next) {
        while (c->free && c->next != NULL && c->next->free) {
            c->size += (uint32_t)sizeof(blk_t) + c->next->size;
            c->next = c->next->next;
        }
    }
}

static void heap_stats(uint32_t *ft, uint32_t *lg, uint32_t *fr)
{
    *ft = *lg = *fr = 0u;
    for (blk_t *b = heap_head; b != NULL; b = b->next) {
        if (b->free) { *ft += b->size; (*fr)++; if (b->size > *lg) { *lg = b->size; } }
    }
}

static uint32_t rng;
static uint32_t xorshift(void) { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static uint32_t draw_size(void)                 /* 80% small 8..64 B, 20% large 256..1024 B */
{
    return ((xorshift() % 10u) < 8u) ? (8u + xorshift() % 57u) : (256u + xorshift() % 769u);
}

int main(void)
{
    /* ---- 1. adversarial interleaving ---- */
    static void *small[64], *large[64];
    unsigned ns = 0u, nl = 0u;
    heap_init();
    for (;;) {
        void *a = heap_alloc(32u), *b = heap_alloc(208u);
        if (a == NULL || b == NULL) { break; }
        small[ns++] = a; large[nl++] = b;
    }
    for (unsigned i = 0u; i < nl; i++) { heap_free(large[i]); }
    uint32_t ft, lg, fr;
    heap_stats(&ft, &lg, &fr);
    void *big = heap_alloc(1024u);
    printf("1. interleaved 32B/208B x%u, freed all 208B blocks: free %u B in %u holes, "
           "largest %u B -> malloc(1024) = %s\n", nl, (unsigned)ft, (unsigned)fr, (unsigned)lg,
           big ? "OK" : "NULL");

    /* ---- 2. random churn on the heap ---- */
    void    *ptr[SLOTS];
    uint32_t sz[SLOTS];
    uint32_t live = 0u;
    heap_init();
    memset(ptr, 0, sizeof ptr);
    rng = 0xC0FFEE11u;
    for (uint32_t step = 0u; step < STEPS; step++) {
        uint32_t s = xorshift() % SLOTS;
        if (ptr[s] != NULL) { heap_free(ptr[s]); live -= sz[s]; ptr[s] = NULL; continue; }
        uint32_t n = draw_size();
        void *p = heap_alloc(n);
        if (p == NULL) {
            heap_stats(&ft, &lg, &fr);
            printf("2. first-fit heap (16384 B): first failure at step %u: request %u B with "
                   "live payload %u B, free %u B in %u fragments, largest %u B\n",
                   (unsigned)step, (unsigned)n, (unsigned)live, (unsigned)ft, (unsigned)fr, (unsigned)lg);
            break;
        }
        ptr[s] = p; sz[s] = n; live += n;
    }

    /* ---- 3. pools sized by analysis: dry run for worst-case concurrency ---- */
    uint32_t cur_s = 0u, cur_l = 0u, max_s = 0u, max_l = 0u;
    memset(ptr, 0, sizeof ptr);
    rng = 0xC0FFEE11u;
    for (uint32_t step = 0u; step < STEPS; step++) {
        uint32_t s = xorshift() % SLOTS;
        if (ptr[s] != NULL) { if (sz[s] <= 64u) { cur_s--; } else { cur_l--; } ptr[s] = NULL; continue; }
        uint32_t n = draw_size();
        ptr[s] = (void *)1; sz[s] = n;
        if (n <= 64u) { if (++cur_s > max_s) { max_s = cur_s; } } else { if (++cur_l > max_l) { max_l = cur_l; } }
    }
    printf("3. worst-case concurrency over %u steps: %u small (64 B class), %u large (1024 B class)\n"
           "   pools for zero failures need %u x 64 + %u x 1024 = %u B (vs 16384 B heap): every\n"
           "   allocation O(1), no fragmentation possible, failure only if the analysis is wrong\n",
           (unsigned)STEPS, (unsigned)max_s, (unsigned)max_l, (unsigned)max_s, (unsigned)max_l,
           (unsigned)(max_s * 64u + max_l * 1024u));
    return 0;
}
```

**Output (verified, deterministic; native, `-Wall -Wextra -Wpedantic -Werror` clean):**

```text
1. interleaved 32B/208B x60, freed all 208B blocks: free 12480 B in 60 holes, largest 208 B -> malloc(1024) = NULL
2. first-fit heap (16384 B): first failure at step 277599: request 675 B with live payload 12585 B, free 2720 B in 13 fragments, largest 544 B
3. worst-case concurrency over 400000 steps: 42 small (64 B class), 20 large (1024 B class)
   pools for zero failures need 42 x 64 + 20 x 1024 = 23168 B (vs 16384 B heap): every
   allocation O(1), no fragmentation possible, failure only if the analysis is wrong
```

1. **Adversarial interleaving.** 60 small (32 B) and 60 large (208 B) blocks alternate. All 60 large ones are freed, leaving **12,480 B free, 76% of the arena**, in 60 holes of at most 208 B. `malloc(1024)` returns NULL. Coalescing can't help, because every hole is pinned between two live small blocks. This is the pattern a long-lived connection table interleaved with short-lived message buffers produces.
2. **Random churn.** A heavy-tailed size mix (80% 8–64 B, 20% 256–1024 B), 64 live slots, a 16 KB first-fit coalescing heap. It runs for **277,599 steps**, then fails a 675 B request with 2,720 B free in 13 fragments. That is "works in every test, fails after days in the field". The step count depends on the random seed and the workload, and no test duration proves it can't happen.
3. **Pools sized by analysis.** A dry run of the same request stream finds worst-case concurrency: 42 small and 20 large objects live at once. Pools of 42 × 64 B + 20 × 1024 B = **23,168 B** never fail on that workload, and every operation is O(1). The cost is **41% more memory than the heap**, which is the honest price of determinism: internal fragmentation plus per-class worst-case provisioning. The guarantee holds only as long as the concurrency analysis does. That's why production pools track **low-water marks** (§2.2) and why the analysis is a reviewed artifact.

### 1.2 The allocator menu

| Allocator | Time | Fragmentation | Free semantics | Use for |
|---|---|---|---|---|
| **Static** (globals, `static` arrays) | 0 | none | never | Everything whose count is known at build time. The MISRA default |
| **Arena / bump / linear** | O(1) | none within an arena | bulk only (reset or mark/release) | Per-frame, per-request, per-boot-phase scratch; parsers; image decode |
| **Fixed-block pool** | O(1) | external: **none**; internal: block size − request | individual | Messages, descriptors, timers, connections: one object type per pool |
| **Slab / size classes** | O(1) | none external; bounded internal (≤ 2× with power-of-2 classes) | individual | A family of object sizes; the Linux kernel's `kmalloc-*` caches |
| **TLSF** (two-level segregated fit) | **O(1) bounded** (two bitmap lookups + split/merge) | low, bounded worst case | individual, variable size | RTOS heaps that must accept variable sizes (Zephyr, RTEMS, some FreeRTOS ports) |
| First/best-fit free list | O(n) | unbounded | individual | Never in hard real-time code |
| Buddy | O(log n) | internal up to 2× | individual, coalescing | Page allocators (Linux `mm/page_alloc.c`) |

### 1.3 Why the certification standards say "no heap after init"

- **MISRA C:2012 Rule 21.3:** the memory allocation and deallocation functions of `<stdlib.h>` shall not be used. MISRA Dir 4.12: dynamic memory allocation shall not be used.
- Typical ISO 26262 / DO-178C project rules allow allocation **during initialization only**. After that, all memory comes from pools sized by analysis, or from static objects.
- The reasons are exactly the three measurements above: unbounded time, failure after an arbitrary run time, and no way to test for it.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* alloc_bad.c - each line ships in real firmware. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint32_t id; uint8_t payload[200]; } msg_t;

msg_t *msg_new(void);
msg_t *msg_new(void)
{
    msg_t *m = malloc(sizeof *m);       /* BUG 1: heap in steady state: O(n), fragments, may fail late */
    memset(m, 0, sizeof *m);            /* BUG 2: no NULL check                                       */
    return m;
}

void msg_free_from_isr(msg_t *m);
void msg_free_from_isr(msg_t *m)
{
    free(m);                            /* BUG 3: newlib malloc locks are task-level (or absent): an ISR
                                         *        calling free() corrupts the heap if it preempted malloc */
}

static uint8_t g_pool[16 * 208];
static uint8_t *g_pool_next = g_pool;
void *pool_take(void);
void *pool_take(void)
{
    void *p = g_pool_next;              /* BUG 4: no bounds check; no alignment (208 is fine for msg_t,
                                         *        but the pool is uint8_t-aligned); no free; no
                                         *        exhaustion telemetry                               */
    g_pool_next += 208;
    return p;
}
```

### 2.2 The Silicon-Hardened Production Way: arena + slab (verified)

`arena.h`:

```c
/* arena.h - bump ("linear") allocator with marks: O(1) alloc, O(1) bulk free,
 * zero fragmentation within a frame/request/boot phase. Not thread-safe:
 * one arena per context (task, frame, request). */
#ifndef ARENA_H
#define ARENA_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t *base;
    size_t   cap;
    size_t   used;
    size_t   high_water;
} arena_t;

typedef size_t arena_mark_t;

static inline void arena_init(arena_t *a, void *mem, size_t cap)
{
    a->base = mem;
    a->cap = cap;
    a->used = 0u;
    a->high_water = 0u;
}

/* align must be a power of two. Overflow-safe: never wraps past cap. */
static inline void *arena_alloc(arena_t *a, size_t n, size_t align)
{
    uintptr_t cur = (uintptr_t)a->base + a->used;
    uintptr_t pad = (align - (cur & (align - 1u))) & (align - 1u);
    if ((pad > a->cap - a->used) || (n > a->cap - a->used - pad)) {
        return NULL;
    }
    a->used += pad + n;
    if (a->used > a->high_water) {
        a->high_water = a->used;
    }
    return (void *)(cur + pad);
}

static inline arena_mark_t arena_mark(const arena_t *a) { return a->used; }
static inline void arena_release(arena_t *a, arena_mark_t m) { if (m <= a->used) { a->used = m; } }
static inline void arena_reset(arena_t *a) { a->used = 0u; }

#endif /* ARENA_H */
```

**`arena_alloc(a, n, 8)` codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
aa:
	push	{r4, lr}
	ldr	r3, [r0]
	ldr	r4, [r0, #4]
	ldr	r2, [r0, #8]
	mov.w	lr, #0
	add.w	r12, r2, r3
	subs	r4, r4, r2
	rsb.w	r3, r12, #0
	and	r3, r3, #7
	cmp	r4, r3
	blo	.LBB0_3
	subs	r4, r4, r3
	cmp	r1, r4
	bhi	.LBB0_3
	add	r1, r2
	ldr	r2, [r0, #12]
	add	r1, r3
	add.w	lr, r3, r12
	cmp	r1, r2
	str	r1, [r0, #8]
	it	hi
	strhi	r1, [r0, #12]
.LBB0_3:
	mov	r0, lr
	pop	{r4, pc}
```

The whole allocator is about 20 instructions with no loop. Look at the padding computation (`rsb`, `and #7`), the two overflow-safe comparisons (`cmp r4, r3` / `cmp r1, r4`, arranged so `used + pad + n` is never computed in a way that could wrap), and the high-water update (`strhi`).

`slab.c`:

```c
/* slab.c - size-class allocator: one fixed-block pool per class, O(1)
 * alloc/free, index-based free lists (16-bit links: works on 8/16/32/64-bit
 * cores, cannot be corrupted into an arbitrary pointer), double-free and
 * foreign-pointer detection via an ownership bitmap. Single context per slab:
 * wrap calls in a critical section if ISRs share it (Folder 07 has the
 * lock-free ISR-safe pool). */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define SLAB_NCLASS   4u
#define SLAB_NONE     0xFFFFu

typedef struct {
    uint8_t  *mem;          /* nblocks * bsize bytes, aligned to bsize's alignment */
    uint16_t *next;         /* free-list links, by block index                     */
    uint32_t *inuse;        /* 1 bit per block                                     */
    uint32_t  bsize;
    uint16_t  nblocks;
    uint16_t  head;
    uint16_t  nfree;
    uint16_t  low_water;    /* fewest free blocks ever: the sizing feedback          */
} pool_t;

typedef struct { pool_t cls[SLAB_NCLASS]; } slab_t;

typedef enum { SLAB_OK = 0, SLAB_EDOUBLE, SLAB_EFOREIGN } slab_err_t;

void       pool_init(pool_t *p, void *mem, uint16_t *links, uint32_t *bits, uint32_t bsize, uint16_t n);
void      *slab_alloc(slab_t *s, size_t n);
slab_err_t slab_free(slab_t *s, void *ptr);

void pool_init(pool_t *p, void *mem, uint16_t *links, uint32_t *bits, uint32_t bsize, uint16_t n)
{
    p->mem = mem; p->next = links; p->inuse = bits; p->bsize = bsize; p->nblocks = n;
    for (uint16_t i = 0u; i < n; i++) { links[i] = (uint16_t)(i + 1u); }
    links[n - 1u] = SLAB_NONE;
    memset(bits, 0, ((n + 31u) / 32u) * sizeof(uint32_t));
    p->head = 0u; p->nfree = n; p->low_water = n;
}

static void *pool_get(pool_t *p)
{
    uint16_t i = p->head;
    if (i == SLAB_NONE) { return NULL; }
    p->head = p->next[i];
    p->inuse[i >> 5] |= 1u << (i & 31u);
    p->nfree--;
    if (p->nfree < p->low_water) { p->low_water = p->nfree; }
    return p->mem + (size_t)i * p->bsize;
}

void *slab_alloc(slab_t *s, size_t n)
{
    for (uint32_t c = 0u; c < SLAB_NCLASS; c++) {     /* smallest class that fits */
        if (n <= s->cls[c].bsize) {
            return pool_get(&s->cls[c]);           /* no fallback to a bigger class:   */
        }                                          /* exhaustion must surface in tests */
    }
    return NULL;
}

slab_err_t slab_free(slab_t *s, void *ptr)
{
    uintptr_t a = (uintptr_t)ptr;
    for (uint32_t c = 0u; c < SLAB_NCLASS; c++) {
        pool_t *p = &s->cls[c];
        uintptr_t lo = (uintptr_t)p->mem, hi = lo + (uintptr_t)p->nblocks * p->bsize;
        if ((a >= lo) && (a < hi)) {
            if (((a - lo) % p->bsize) != 0u) { return SLAB_EFOREIGN; }  /* interior pointer */
            uint16_t i = (uint16_t)((a - lo) / p->bsize);
            uint32_t bit = 1u << (i & 31u);
            if ((p->inuse[i >> 5] & bit) == 0u) { return SLAB_EDOUBLE; }
            p->inuse[i >> 5] &= ~bit;
            p->next[i] = p->head;
            p->head = i;
            p->nfree++;
            return SLAB_OK;
        }
    }
    return SLAB_EFOREIGN;
}

#ifdef SLAB_SELFTEST
#include <stdio.h>
#include "arena.h"

static _Alignas(16) uint8_t m0[32 * 16], m1[16 * 64], m2[8 * 256], m3[4 * 1024];
static uint16_t l0[32], l1[16], l2[8], l3[4];
static uint32_t b0[1], b1[1], b2[1], b3[1];

int main(void)
{
    slab_t s;
    pool_init(&s.cls[0], m0, l0, b0, 16u, 32u);
    pool_init(&s.cls[1], m1, l1, b1, 64u, 16u);
    pool_init(&s.cls[2], m2, l2, b2, 256u, 8u);
    pool_init(&s.cls[3], m3, l3, b3, 1024u, 4u);

    void *a = slab_alloc(&s, 10u), *b = slab_alloc(&s, 60u), *c = slab_alloc(&s, 900u);
    printf("alloc 10/60/900 B -> classes 16/64/1024: %s %s %s\n",
           a ? "ok" : "NULL", b ? "ok" : "NULL", c ? "ok" : "NULL");
    void *big[5];
    for (int i = 0; i < 5; i++) { big[i] = slab_alloc(&s, 1000u); }
    printf("1024-B class (4 blocks, 1 used): next 5 allocs -> %s %s %s %s %s\n",
           big[0] ? "ok" : "NULL", big[1] ? "ok" : "NULL", big[2] ? "ok" : "NULL",
           big[3] ? "ok" : "NULL", big[4] ? "ok" : "NULL");
    printf("free b: %d, free b again: %d (EDOUBLE=1), free a+4: %d (EFOREIGN=2), free stack var: %d\n",
           (int)slab_free(&s, b), (int)slab_free(&s, b), (int)slab_free(&s, (uint8_t *)a + 4),
           (int)slab_free(&s, &s));
    printf("low-water marks: 16B=%u/32 64B=%u/16 256B=%u/8 1024B=%u/4\n",
           (unsigned)s.cls[0].low_water, (unsigned)s.cls[1].low_water,
           (unsigned)s.cls[2].low_water, (unsigned)s.cls[3].low_water);

    static _Alignas(64) uint8_t frame_mem[256];
    arena_t ar;
    arena_init(&ar, frame_mem, sizeof frame_mem);
    void *x = arena_alloc(&ar, 3u, 1u);
    void *y = arena_alloc(&ar, 8u, 8u);
    arena_mark_t mk = arena_mark(&ar);
    void *z = arena_alloc(&ar, 64u, 64u);
    printf("arena: x@+%u y@+%u z@+%u (aligned 64), used=%u\n",
           (unsigned)((uint8_t *)x - frame_mem), (unsigned)((uint8_t *)y - frame_mem),
           (unsigned)((uint8_t *)z - frame_mem), (unsigned)ar.used);
    arena_release(&ar, mk);
    printf("arena: after release used=%u, alloc 300 B -> %s, high_water=%u\n",
           (unsigned)ar.used, arena_alloc(&ar, 300u, 1u) ? "ok" : "NULL", (unsigned)ar.high_water);
    return 0;
}
#endif
```

**Build evidence (verified):** `slab.c` and an `arena.h` TU compile with zero diagnostics on Cortex-M7, Cortex-M0+, AArch64 and x86-64.

**Self-test output (verified, native):**

```text
alloc 10/60/900 B -> classes 16/64/1024: ok ok ok
1024-B class (4 blocks, 1 used): next 5 allocs -> ok ok ok NULL NULL
free b: 0, free b again: 1 (EDOUBLE=1), free a+4: 2 (EFOREIGN=2), free stack var: 2
low-water marks: 16B=31/32 64B=15/16 256B=8/8 1024B=0/4
arena: x@+0 y@+8 z@+64 (aligned 64), used=128
arena: after release used=16, alloc 300 B -> NULL, high_water=128
```

The design decisions the output proves:

- **Smallest-fitting class, no fallback to larger classes.** The 1024 B class ran out after its four blocks (`ok ok ok NULL NULL`), and the allocator did *not* silently consume a different class. Fallback hides a sizing error until the other class runs dry too.
- **Index-based free lists (16-bit links)** in a separate array, not pointers stored inside freed blocks:
  - a use-after-free write into a freed block can't redirect the allocator to an arbitrary address;
  - links are a quarter of the size of 64-bit pointers;
  - the same structure is used verbatim by the lock-free ISR-safe pool in Folder 07, where indices fit a 32-bit `{tag, index}` CAS word (File 02).
- **Ownership bitmap:**
  - a double free returns `SLAB_EDOUBLE` instead of creating a cycle in the free list;
  - an interior pointer (`a + 4`) or a pointer from outside the slab (a stack variable) returns `SLAB_EFOREIGN`.
  - In production these become an assert, a fault-log record, or a safe-state transition (Folder 08).
- **Low-water marks** (`1024B = 0/4`) are the field telemetry that validates the sizing analysis. If a class ever reaches 0 in the field, the analysis was wrong, before any allocation actually fails.
- **The arena** aligned `z` to 64 (offset 64, after 3 + pad + 8 bytes). `mark`/`release` rolled `used` back to 16, and a 300-byte request into a 256-byte arena was refused (`NULL`), not wrapped.

### 2.3 Lifetime-driven allocator selection (the design review checklist)

| Lifetime pattern | Allocator | Example |
|---|---|---|
| Whole program | static | Driver state, RTOS objects (FreeRTOS `configSUPPORT_STATIC_ALLOCATION = 1`) |
| One phase (boot, one frame, one request) | arena + reset | Boot-time table construction, a per-frame scratch arena, a JSON parse |
| Many objects of one type, independent lifetimes | fixed-block pool | Network buffers, timers, messages, descriptors |
| A few sizes, independent lifetimes | slab (size classes) | Protocol PDUs of 3–4 sizes |
| Truly variable sizes, real-time | TLSF, with a budget and a fallback policy | Image or codec buffers in an RTOS application |
| Variable sizes, non-real-time | general heap, isolated in its own region | Linux user space, logging/debug subsystems |

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| `malloc` returns NULL after days; plenty of "free heap" reported | External fragmentation (measured above) | Log the free total *and the largest free block*; the ratio is the fragmentation index. Heap walkers (newlib `mallinfo`, FreeRTOS `vPortGetHeapStats`) give fragment counts |
| Random corruption near a freed object | Use-after-free writing into an allocator's in-block free link | Index-based links (§2.2); canaries/guard words (Folder 07 pool); MPU no-access guard regions around pools during debug |
| Heap corruption only under interrupt load | ISR calling `malloc`/`free` (no ISR-safe lock) | Grep the ISR call graph; keep allocation out of ISRs, or use the lock-free ISR-safe pool (Folder 07) |
| Pool exhaustion in the field | Sizing analysis wrong | Low-water telemetry; trace allocation call sites per class; review the concurrency model |
| Deadline misses correlate with allocation | O(n) free-list search | Measure `malloc` time with DWT `CYCCNT`; replace it with a pool, slab or TLSF |

TRACE32 and GDB scripts that walk the pool bitmaps and free-index chains give a live picture: count bits set versus `nfree`. A mismatch is corruption.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Why is `malloc` banned in safety-critical firmware?"

- **L5:** "It's slow and can fail."
- **Why L5 fails on real hardware:** "Can fail" isn't the point; *when* it fails is. The measured churn ran 277,599 steps before its first failure, with 2,720 B still free. No test of finite length proves the absence of that failure. The adversarial case shows **76% free memory and a 1 KB request refused**. Time is also unbounded (first-fit searches), and an ISR calling it corrupts the heap.
- **L7 principal defense:**
  - MISRA 21.3 and Dir 4.12, and "allocate at init only" project rules.
  - Replace steady-state allocation with static objects, phase arenas, and pools sized by **worst-case concurrency analysis** (measured: 23,168 B for zero failures).
  - Ship low-water telemetry to validate the analysis.
  - Accept the memory overhead knowingly (41% here) as the price of a proof.

### Q2 🔥 "Design an O(1) allocator for 64-byte messages shared between an ISR and a task."

- **L5:** "A linked list of free blocks; pop to allocate, push to free."
- **Why L5 fails:** Two contexts mutate the list head, so the L5 answer needs a lock (PRIMASK) or is broken. Pointer links stored in freed blocks are a use-after-free amplifier. There's no double-free detection, and no telemetry.
- **L7 defense:** Index-based free list, ownership bitmap, low-water mark (verified slab). For ISR safety:
  - mask that ISR around the 3-instruction critical section, or
  - make it lock-free with a `{tag, index}` 32-bit CAS head (File 02's verified ABA fix), which fits LDREX/STREX on v7-M.
  
  Folder 07 File 03 is the complete production version, with canaries.

### Q3 "When would you use an arena instead of a pool?"

- **L5:** "When objects are different sizes."
- **Why L5 fails:** Size isn't the deciding factor. **Lifetime** is. An arena is correct exactly when all objects allocated in a phase die together: frame, request, boot stage, parse. Then allocation is a pointer bump (verified: ~20 instructions, no loop), free is O(1) for the whole set, and fragmentation is impossible.
- **L7 defense:** Lifetime-driven selection (§2.3). Overflow-safe bump arithmetic (verified). Mark/release for nested phases. Arenas per context, never shared without a lock. The high-water mark gives sizing feedback, as with pools.

### Q4 🧊 "What is TLSF, and why do some RTOSes use it?"

- **L5:** "Another malloc."
- **Why L5 fails:** It misses the property that matters: **bounded O(1) worst-case time for variable-size allocation**. That's the one thing classic allocators can't offer.
- **L7 defense:** Two-level segregated free lists. The first level splits by power of two (found with CLZ on a bitmap), the second level subdivides each range linearly (another bitmap). Allocation:
  1. two bitmap scans find a list whose blocks are guaranteed to fit ("good fit");
  2. split the block;
  3. immediate coalescing on free via boundary tags.
  
  Time is bounded; fragmentation is low but not zero, so you still budget. Use it where variable sizes are unavoidable and pools would waste too much. Keep it out of ISRs, and still measure the largest free block.

---

## 5. Invariants Checklist

- [ ] No `malloc`/`free` after initialization in real-time or safety code (MISRA 21.3 / Dir 4.12); the linker map shows no heap use from those modules.
- [ ] Every pool and slab class sized from a documented worst-case concurrency analysis; low-water marks reported in the field.
- [ ] Pools use index-based free lists, ownership bitmaps (double-free / foreign-pointer detection) and aligned block storage.
- [ ] No silent fallback between size classes.
- [ ] Arenas only for same-lifetime data, with overflow-safe bump arithmetic; one arena per context.
- [ ] No allocation in ISRs unless the allocator is explicitly ISR-safe (lock-free or masked critical section).
- [ ] Heap use (non-real-time subsystems) is isolated in its own region, with largest-free-block telemetry.

## 6. References

1. P. R. Wilson, M. S. Johnstone, M. Neely, D. Boles, *Dynamic Storage Allocation: A Survey and Critical Review*, IWMM 1995.
2. J. Bonwick, *The Slab Allocator: An Object-Caching Kernel Memory Allocator*, USENIX Summer 1994.
3. M. Masmano, I. Ripoll, A. Crespo, J. Real, *TLSF: A New Dynamic Memory Allocator for Real-Time Systems*, ECRTS 2004.
4. MISRA C:2012 Rule 21.3, Directive 4.12; ISO 26262-6:2018 Annex on software unit design (dynamic objects).
5. FreeRTOS `portable/MemMang/heap_1..5.c`; Zephyr `k_mem_slab` and `sys_heap` documentation; Linux `mm/slub.c`.
