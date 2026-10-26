# 02 · Lock-Free SPSC/MPMC Ring Buffers, LL/SC (`LDREX`/`STREX`, `LDXR`/`STXR`, LSE), and ABA

> **Folder:** `05-Deterministic-Memory-and-Lock-Free-Data-Structures/` · **File 2 of 3**
> **Anchors:**
> - ARMv7-M ARM A3.4 *Synchronization and semaphores* (local and global exclusive monitors, `CLREX`); Arm ARM DDI 0487 B2.9 *Exclusive access instructions* (Exclusives Reservation Granule, monitor clearing), FEAT_LSE (`CAS`, `CASP`, `LDADD`).
> - M. Herlihy, *Wait-Free Synchronization* (TOPLAS 1991); R. K. Treiber, *Systems Programming: Coping with Parallelism* (IBM RJ5118, 1986).
> - D. Vyukov, *Bounded MPMC queue* (1024cores.net); M. Michael, *Hazard Pointers* (TPDS 2004).
> - Linux `include/linux/kfifo.h`, `lib/llist.c`; DPDK `rte_ring`.
>
> **Verification:**
> - SPSC and MPMC rings compiled warning-free for Cortex-M7, AArch64 (v8.0 and v8.4), RV64 and x86-64.
> - **Real-thread stress** (one run, author's x86-64 laptop): SPSC ordering of 20M items; MPMC exactly-once delivery of 4M items with a per-item bitmap.
> - **ABA reproduced deterministically** and fixed with a tagged head.
> - Double-width CAS codegen on four ISAs.
> - All outputs inserted verbatim.

---

## 0. The thesis

Lock-free doesn't mean "no synchronization". It means **progress without mutual exclusion**: no thread can block another by being preempted while holding a lock. That property is what makes these structures usable between an ISR and a task (no priority inversion is possible, Folder 04) and between cores. It's paid for with three disciplines:

- the right memory orders on exactly the right accesses;
- capacity and index arithmetic that is correct across wrap-around;
- a defense against **ABA** whenever a CAS compares pointers or indices that can be reused.

---

## 1. First-Principles Mechanics

### 1.1 How LL/SC works in silicon

`LDREX`/`STREX` (AArch32/v7-M) and `LDXR`/`STXR` (AArch64) are **load-linked / store-conditional**:

1. `LDREX Rt, [Rn]` loads the value **and tags the address** in the **local exclusive monitor** (per core) and, for shareable memory, the **global exclusive monitor** (in the interconnect).
2. `STREX Rd, Rt, [Rn]` stores **only if the tag is still held**, and writes `Rd = 0` on success or `1` on failure.
3. The tag is lost if:
   - another observer writes to the same **Exclusives Reservation Granule** (ERG, `CTR_EL0[23:20]`: 16 bytes to 2 KB, typically one cache line);
   - `CLREX` executes;
   - on Cortex-M, **an exception entry or return** occurs (⚠ verify the implementation);
   - an implementation-defined event happens: cache eviction, a different exclusive access, and so on.

Consequences that compilers and kernel authors handle:

- **Any write to the granule by another core** fails your `STREX`, even a write to a *different variable* in the same ERG. Lock words need their own granule (Folder 01, File 02 `CTR_EL0.ERG`).
- **Context switches on A-profile.** If thread A does `LDREX`, gets switched out, and thread B's `STREX` to the same address executes on that core, B can succeed on *A's* reservation. Kernels therefore execute `CLREX` (or rely on an exception return that architecturally clears the monitor) on every context switch (⚠ verify the kernel's convention for your architecture version). Cortex-M clears it on exception entry/exit, which is why the Folder 04 PendSV handler needs no `CLREX`.
- **Keep the LL/SC window tiny.** No other memory accesses, no function calls, no exclusives to another address between the pair. Each can clear the reservation, and on some implementations a loop that always fails is a **livelock**. Compilers emit exactly the minimal loop (verified below), so prefer C11 atomics to hand-written exclusives.
- **Failed paths execute `CLREX`** (verified in every CAS listing), so a dangling reservation can't make a later unrelated `STREX` succeed.
- **LSE (ARMv8.1).** `CAS`, `CASP`, `LDADD`, `SWP` etc. are single instructions performed *at the point of coherence* ("far atomics") by many interconnects (CMN home nodes). There is no retry loop, and they scale far better than LL/SC under contention. A binary built for v8.0 uses LL/SC unless built with `-moutline-atomics`, which dispatches at run time (⚠ verify the defaults of your toolchain).

### 1.2 SPSC: the lock-free structure you'll use most

**Invariant:** only the producer writes `head`, only the consumer writes `tail`. No CAS is needed; it's *wait-free*.

`spsc.h`:

```c
/* spsc.h - wait-free single-producer/single-consumer ring of uint32_t.
 *  - Free-running 32-bit indices: (head - tail) is the fill level modulo 2^32,
 *    correct across wrap because the capacity is a power of two.
 *  - head and tail live on separate cache lines (no false sharing); each side
 *    keeps a private cached copy of the OTHER index on its own line, so the
 *    shared line is touched only when the cached view says full/empty.
 *  - release on publish, acquire on observe: the element write happens-before
 *    the consumer's read of it; the consumer's read happens-before the slot is
 *    reused. Producer may be an ISR, consumer a task (or vice versa), or two cores. */
#ifndef SPSC_H
#define SPSC_H

#include <stdalign.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#ifndef SPSC_LINE
#define SPSC_LINE 64u
#endif
#define SPSC_CAP 1024u
_Static_assert((SPSC_CAP & (SPSC_CAP - 1u)) == 0u, "capacity must be a power of two");

typedef struct {
    alignas(SPSC_LINE) _Atomic uint32_t head;   /* written by producer only */
    uint32_t tail_cache;                        /* producer-private          */
    alignas(SPSC_LINE) _Atomic uint32_t tail;   /* written by consumer only */
    uint32_t head_cache;                        /* consumer-private          */
    alignas(SPSC_LINE) uint32_t buf[SPSC_CAP];
} spsc_t;

static inline bool spsc_push(spsc_t *q, uint32_t v)
{
    uint32_t h = atomic_load_explicit(&q->head, memory_order_relaxed);
    if ((h - q->tail_cache) == SPSC_CAP) {                              /* looks full */
        q->tail_cache = atomic_load_explicit(&q->tail, memory_order_acquire);
        if ((h - q->tail_cache) == SPSC_CAP) {
            return false;
        }
    }
    q->buf[h & (SPSC_CAP - 1u)] = v;
    atomic_store_explicit(&q->head, h + 1u, memory_order_release);      /* publish */
    return true;
}

static inline bool spsc_pop(spsc_t *q, uint32_t *v)
{
    uint32_t t = atomic_load_explicit(&q->tail, memory_order_relaxed);
    if (t == q->head_cache) {                                           /* looks empty */
        q->head_cache = atomic_load_explicit(&q->head, memory_order_acquire);
        if (t == q->head_cache) {
            return false;
        }
    }
    *v = q->buf[t & (SPSC_CAP - 1u)];
    atomic_store_explicit(&q->tail, t + 1u, memory_order_release);      /* free the slot */
    return true;
}

#endif /* SPSC_H */
```

**Why each piece is there:**

| Element | Reason |
|---|---|
| Free-running `uint32_t` indices, `& (CAP-1)` on access | The fill level `head − tail` is correct modulo 2^32 across wrap-around. There's no "one slot wasted" ambiguity between full and empty |
| `release` store of `head` after writing `buf[h]` | The element is visible before the index that announces it (the MP pattern, Folder 03) |
| `acquire` load of `head` by the consumer | Pairs with the release: the read of `buf[t]` sees the published value |
| `release` store of `tail`, `acquire` load of `tail` by the producer | **The second direction**: the consumer has finished reading the slot before the producer may overwrite it (Folder 03 File 02 §2.2) |
| `alignas(64)` on `head`, `tail`, `buf` | No false sharing between the two writers (measured 3.9× in Folder 03) |
| `tail_cache` / `head_cache` | Each side reads the *other* side's line only when its cached view says full/empty, which removes most cross-core line transfers in the steady state |

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7; `p1` = push, `c1` = pop, `p2` = MPMC push):**

```asm
p1:
	ldr	r2, [r0]
	ldr	r3, [r0, #4]
	subs	r3, r2, r3
	cmp.w	r3, #1024
	bne	.LBB0_3
	ldr.w	r12, [r0, #64]
	dmb	sy
	sub.w	r3, r2, r12
	str.w	r12, [r0, #4]
	cmp.w	r3, #1024
	bne	.LBB0_3
	movs	r0, #0
	bx	lr
.LBB0_3:
	adds	r3, r2, #1
	bfc	r2, #10, #22
	add.w	r2, r0, r2, lsl #2
	str.w	r1, [r2, #128]
	dmb	sy
	str	r3, [r0]
	movs	r0, #1
	bx	lr
c1:
	ldr	r2, [r0, #64]
	ldr	r3, [r0, #68]
	cmp	r2, r3
	bne	.LBB1_3
	ldr	r3, [r0]
	dmb	sy
	cmp	r2, r3
	str	r3, [r0, #68]
	bne	.LBB1_3
	movs	r0, #0
	bx	lr
.LBB1_3:
	adds	r3, r2, #1
	bfc	r2, #10, #22
	add.w	r2, r0, r2, lsl #2
	ldr.w	r2, [r2, #128]
	str	r2, [r1]
	dmb	sy
	str	r3, [r0, #64]
	movs	r0, #1
	bx	lr
p2:
	push	{r4, r5, r6, lr}
	ldr	r4, [r0]
	add.w	r12, r0, #128
	b	.LBB2_2
.LBB2_1:
	clrex
	movs	r6, #0
	lsls	r6, r6, #31
	bne	.LBB2_7
.LBB2_2:
	mov	r3, r4
	mov	r2, r4
	bfc	r3, #10, #22
	ldr.w	lr, [r12, r3, lsl #3]
	dmb	sy
	cmp	lr, r4
	bne	.LBB2_5
	ldrex	r4, [r0]
	adds	r5, r2, #1
	cmp	r4, r2
	bne	.LBB2_1
	strex	r6, r5, [r0]
	cmp	r6, #0
	mov.w	r6, #0
	it	eq
	moveq.w	r6, #-1
	lsls	r6, r6, #31
	beq	.LBB2_2
	b	.LBB2_7
.LBB2_5:
	subs.w	r3, lr, r2
	bmi	.LBB2_8
	ldr	r4, [r0]
	b	.LBB2_2
.LBB2_7:
	add.w	r0, r12, r3, lsl #3
	str	r1, [r0, #4]
	dmb	sy
	str	r5, [r0]
.LBB2_8:
	sub.w	r0, lr, r2
	clz	r0, r0
	lsrs	r0, r0, #5
	pop	{r4, r5, r6, pc}
```

**Codegen (verified — AArch64 v8.4, LSE + RCpc):**

```asm
p1:
	ldr	w8, [x0]
	ldr	w9, [x0, #4]
	sub	w9, w8, w9
	cmp	w9, #1024
	b.ne	.LBB0_3
	add	x9, x0, #64
	ldapr	w9, [x9]
	sub	w10, w8, w9
	str	w9, [x0, #4]
	cmp	w10, #1024
	b.ne	.LBB0_3
	mov	w0, wzr
	ret
.LBB0_3:
	and	x9, x8, #0x3ff
	add	w8, w8, #1
	add	x9, x0, x9, lsl #2
	str	w1, [x9, #128]
	stlr	w8, [x0]
	mov	w0, #1
	ret
c1:
	ldr	w8, [x0, #64]
	ldr	w9, [x0, #68]
	cmp	w8, w9
	b.ne	.LBB1_3
	ldapr	w9, [x0]
	cmp	w8, w9
	str	w9, [x0, #68]
	b.ne	.LBB1_3
	mov	w0, wzr
	ret
.LBB1_3:
	and	x9, x8, #0x3ff
	add	w8, w8, #1
	add	x9, x0, x9, lsl #2
	ldr	w9, [x9, #128]
	str	w9, [x1]
	stlur	w8, [x0, #64]
	mov	w0, #1
	ret
p2:
	ldr	w12, [x0]
	add	x8, x0, #128
	b	.LBB2_2
.LBB2_1:
	add	w13, w9, #1
	mov	w12, w9
	cas	w12, w13, [x0]
	cmp	w12, w9
	b.eq	.LBB2_5
.LBB2_2:
	and	w11, w12, #0x3ff
	mov	w9, w12
	add	x10, x8, w11, uxtw #3
	ldapr	w10, [x10]
	cmp	w10, w12
	b.eq	.LBB2_1
	b.mi	.LBB2_6
	ldr	w12, [x0]
	b	.LBB2_2
.LBB2_5:
	add	x8, x8, x11, lsl #3
	str	w1, [x8, #4]
	stlr	w13, [x8]
.LBB2_6:
	cmp	w10, w9
	cset	w0, eq
	ret
```

- The SPSC push on Cortex-M7 touches the shared `tail` (`[r0, #64]`) only on the "looks full" path, then `dmb sy`. The common path is `str` of the element, `dmb sy`, `str` of `head`: one barrier per element. On AArch64 the same push is `stlr` of `head`, and the pop is `ldapr` (RCpc acquire) of `head`.
- `bfc r2, #10, #22` *is* the `& (CAP − 1)` for `CAP = 1024`: a single instruction.
- The MPMC push on AArch64 v8.4 uses `casal`/`cas` (LSE) for the claim of `enq`. On Cortex-M7 it's an `ldrex`/`strex` loop.

### 1.3 MPMC: Vyukov's bounded queue

With several producers, `enq` must be claimed by CAS. A naive "CAS the index, then write the slot" design lets a consumer read a slot whose producer claimed it but hasn't written it yet. Vyukov's design gives **every cell a sequence number**:

- **`seq == pos`**: free for the producer of lap `pos`.
- **`seq == pos + 1`**: full, for the consumer of lap `pos`.
- After consumption, `seq = pos + CAP`: free for the next lap.

A producer CASes `enq` only when the cell is ready for it, writes the data, then **release**-stores `seq`. A consumer acquire-loads `seq`. The sequence numbers make indices self-validating, so there's **no ABA on `enq`/`deq`**: a stale `pos` sees a mismatched `seq` and retries.

`mpmc.h`:

```c
/* mpmc.h - bounded multi-producer/multi-consumer queue (D. Vyukov's design):
 * every cell carries a sequence number that says whose turn it is, so there
 * is no ABA on indices and no per-element lock. Lock-free (not wait-free):
 * a CAS loser retries. 32-bit free-running positions; comparisons use the
 * sign bit of the unsigned difference (well-defined, no signed overflow). */
#ifndef MPMC_H
#define MPMC_H

#include <stdalign.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#define MPMC_CAP 1024u
_Static_assert((MPMC_CAP & (MPMC_CAP - 1u)) == 0u, "capacity must be a power of two");

typedef struct {
    _Atomic uint32_t seq;
    uint32_t         data;
} mpmc_cell_t;

typedef struct {
    alignas(64) _Atomic uint32_t enq;
    alignas(64) _Atomic uint32_t deq;
    alignas(64) mpmc_cell_t cell[MPMC_CAP];
} mpmc_t;

#define MPMC_NEG(d) (((d) & 0x80000000u) != 0u)

static inline void mpmc_init(mpmc_t *q)
{
    for (uint32_t i = 0u; i < MPMC_CAP; i++) {
        atomic_init(&q->cell[i].seq, i);
    }
    atomic_init(&q->enq, 0u);
    atomic_init(&q->deq, 0u);
}

static inline bool mpmc_push(mpmc_t *q, uint32_t v)
{
    uint32_t pos = atomic_load_explicit(&q->enq, memory_order_relaxed);
    mpmc_cell_t *c;
    for (;;) {
        c = &q->cell[pos & (MPMC_CAP - 1u)];
        uint32_t seq = atomic_load_explicit(&c->seq, memory_order_acquire);
        uint32_t d = seq - pos;
        if (d == 0u) {                                   /* cell free for this lap */
            if (atomic_compare_exchange_weak_explicit(&q->enq, &pos, pos + 1u,
                                                      memory_order_relaxed, memory_order_relaxed)) {
                break;
            }                                            /* lost the race: pos reloaded */
        } else if (MPMC_NEG(d)) {
            return false;                                /* full */
        } else {
            pos = atomic_load_explicit(&q->enq, memory_order_relaxed);
        }
    }
    c->data = v;
    atomic_store_explicit(&c->seq, pos + 1u, memory_order_release);     /* hand to consumers */
    return true;
}

static inline bool mpmc_pop(mpmc_t *q, uint32_t *v)
{
    uint32_t pos = atomic_load_explicit(&q->deq, memory_order_relaxed);
    mpmc_cell_t *c;
    for (;;) {
        c = &q->cell[pos & (MPMC_CAP - 1u)];
        uint32_t seq = atomic_load_explicit(&c->seq, memory_order_acquire);
        uint32_t d = seq - (pos + 1u);
        if (d == 0u) {                                   /* cell full for this lap */
            if (atomic_compare_exchange_weak_explicit(&q->deq, &pos, pos + 1u,
                                                      memory_order_relaxed, memory_order_relaxed)) {
                break;
            }
        } else if (MPMC_NEG(d)) {
            return false;                                /* empty */
        } else {
            pos = atomic_load_explicit(&q->deq, memory_order_relaxed);
        }
    }
    *v = c->data;
    atomic_store_explicit(&c->seq, pos + MPMC_CAP, memory_order_release); /* free for next lap */
    return true;
}

#endif /* MPMC_H */
```

Note `MPMC_NEG()`: the "is the difference negative" test is done on the **sign bit of the unsigned difference**. That avoids the implementation-defined conversion of an out-of-range unsigned value to `int32_t` (C11 §6.3.1.3p3), keeping the code strictly conforming, and MISRA-friendly.

### 1.4 Stress evidence (real threads)

```c
/* ring_stress.c - real-thread stress: SPSC in-order delivery of 20M items,
 * MPMC exactly-once delivery of 2 x 2M items to 2 consumers (bitmap check). */
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

#include "mpmc.h"
#include "spsc.h"

#define SPSC_N 20000000u
#define MPMC_PER 2000000u

static spsc_t g_spsc;
static mpmc_t g_mpmc;
static uint8_t *g_seen;                       /* 1 byte per expected item */
static _Atomic uint32_t g_dup, g_total;

static DWORD WINAPI spsc_prod(LPVOID a) { (void)a; for (uint32_t i = 0u; i < SPSC_N; ) { if (spsc_push(&g_spsc, i)) { i++; } } return 0; }
static DWORD WINAPI spsc_cons(LPVOID a)
{
    uint32_t *bad = a, expect = 0u, v;
    while (expect < SPSC_N) { if (spsc_pop(&g_spsc, &v)) { if (v != expect) { (*bad)++; } expect++; } }
    return 0;
}

static DWORD WINAPI mpmc_prod(LPVOID a)
{
    uint32_t id = (uint32_t)(uintptr_t)a;
    for (uint32_t i = 0u; i < MPMC_PER; ) { if (mpmc_push(&g_mpmc, id * MPMC_PER + i)) { i++; } }
    return 0;
}
static DWORD WINAPI mpmc_cons(LPVOID a)
{
    (void)a;
    uint32_t v;
    while (atomic_load(&g_total) < 2u * MPMC_PER) {
        if (mpmc_pop(&g_mpmc, &v)) {
            if (g_seen[v]++ != 0u) { atomic_fetch_add(&g_dup, 1u); }   /* one owner per v */
            atomic_fetch_add(&g_total, 1u);
        }
    }
    return 0;
}

static double now_ms(void)
{
    LARGE_INTEGER f, t;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart * 1000.0 / (double)f.QuadPart;
}

int main(void)
{
    uint32_t bad = 0u;
    double t0 = now_ms();
    HANDLE s[2] = { CreateThread(NULL, 0, spsc_prod, NULL, 0, NULL), CreateThread(NULL, 0, spsc_cons, &bad, 0, NULL) };
    WaitForMultipleObjects(2, s, TRUE, INFINITE);
    double t1 = now_ms();
    printf("SPSC: %u items, out-of-order=%u, %.1f ms (%.1f M items/s)\n",
           (unsigned)SPSC_N, (unsigned)bad, t1 - t0, (double)SPSC_N / (t1 - t0) / 1000.0);

    g_seen = calloc(2u * MPMC_PER, 1u);
    mpmc_init(&g_mpmc);
    t0 = now_ms();
    HANDLE m[4] = { CreateThread(NULL, 0, mpmc_prod, (LPVOID)(uintptr_t)0u, 0, NULL),
                    CreateThread(NULL, 0, mpmc_prod, (LPVOID)(uintptr_t)1u, 0, NULL),
                    CreateThread(NULL, 0, mpmc_cons, NULL, 0, NULL),
                    CreateThread(NULL, 0, mpmc_cons, NULL, 0, NULL) };
    WaitForMultipleObjects(4, m, TRUE, INFINITE);
    t1 = now_ms();
    uint32_t missing = 0u;
    for (uint32_t i = 0u; i < 2u * MPMC_PER; i++) { missing += (g_seen[i] == 0u); }
    printf("MPMC: 2 producers x %u, 2 consumers: received=%u duplicates=%u missing=%u, %.1f ms\n",
           (unsigned)MPMC_PER, (unsigned)atomic_load(&g_total), (unsigned)atomic_load(&g_dup),
           (unsigned)missing, t1 - t0);
    free(g_seen);
    return 0;
}
```

A test translation unit used for the codegen above:

```c
#include "spsc.h"
#include "mpmc.h"
bool p1(spsc_t *q, uint32_t v);
bool p1(spsc_t *q, uint32_t v) { return spsc_push(q, v); }
bool c1(spsc_t *q, uint32_t *v);
bool c1(spsc_t *q, uint32_t *v) { return spsc_pop(q, v); }
bool p2(mpmc_t *q, uint32_t v);
bool p2(mpmc_t *q, uint32_t v) { return mpmc_push(q, v); }
```

**One measured run (author's x86-64 laptop, Windows 11):**

```text
SPSC: 20000000 items, out-of-order=0, 54.8 ms (364.8 M items/s)
MPMC: 2 producers x 2000000, 2 consumers: received=4000000 duplicates=0 missing=0, 462.3 ms
```

- **SPSC:** 20,000,000 items delivered with **0 out-of-order**, about 365 M items/s in this run (machine-dependent).
- **MPMC:** 2 producers × 2,000,000 tagged items to 2 consumers, with **received = 4,000,000, duplicates = 0, missing = 0**, checked against a per-item bitmap. That's the exactly-once property that matters. The throughput is much lower than SPSC because every operation is a contended CAS on a shared index.
- x86-TSO is a *weaker test* than ARM for ordering bugs (Folder 03: MP can't fail on x86). The release/acquire placement above is what makes these correct on ARM and RISC-V. Run the same harness on an ARM64 machine and a herd7 model before shipping.

### 1.5 ABA, reproduced

A Treiber stack (a lock-free LIFO, the classic lock-free free list) pops with `CAS(head, h, h->next)`. ABA happens when `head` *changes and changes back* between the read of `h`/`h->next` and the CAS:

```c
/* aba_demo.c - the ABA problem on a Treiber (lock-free LIFO) free list,
 * reproduced deterministically by scripting the interleaving of two
 * "threads" in one thread, then fixed with a {index, tag} head. */
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define N 4u
typedef struct node { struct node *next; uint32_t id; } node_t;

/* ---------- naive: head is a bare pointer ---------- */
static node_t nodes[N];
static _Atomic(node_t *) head;

static void naive_reset(void)
{
    for (uint32_t i = 0u; i < N; i++) { nodes[i].id = i; nodes[i].next = (i + 1u < N) ? &nodes[i + 1u] : NULL; }
    atomic_store(&head, &nodes[0]);            /* stack: 0 -> 1 -> 2 -> 3 */
}

static node_t *naive_pop(void)
{
    node_t *h = atomic_load(&head);
    while (h != NULL && !atomic_compare_exchange_weak(&head, &h, h->next)) { }
    return h;
}
static void naive_push(node_t *n)
{
    node_t *h = atomic_load(&head);
    do { n->next = h; } while (!atomic_compare_exchange_weak(&head, &h, n));
}

/* ---------- fixed: head = {16-bit tag, 16-bit index} in one 32-bit CAS word ---------- */
#define NIL 0xFFFFu
static uint16_t next_idx[N];
static _Atomic uint32_t thead;                 /* [31:16] tag, [15:0] index */
static uint32_t pack(uint16_t tag, uint16_t idx) { return ((uint32_t)tag << 16) | idx; }
static uint16_t idx_of(uint32_t w) { return (uint16_t)(w & 0xFFFFu); }
static uint16_t tag_of(uint32_t w) { return (uint16_t)(w >> 16); }

static void tagged_reset(void)
{
    for (uint16_t i = 0u; i < N; i++) { next_idx[i] = (uint16_t)((i + 1u < N) ? i + 1u : NIL); }
    atomic_store(&thead, pack(0u, 0u));
}
static bool tagged_try_pop(uint32_t seen, uint16_t seen_next, uint16_t *out)  /* one CAS attempt */
{
    uint32_t expect = seen;
    uint32_t desired = pack((uint16_t)(tag_of(seen) + 1u), seen_next);       /* every change bumps the tag */
    if (atomic_compare_exchange_strong(&thead, &expect, desired)) { *out = idx_of(seen); return true; }
    return false;
}
static uint16_t tagged_pop(void)
{
    for (;;) {
        uint32_t h = atomic_load(&thead);
        if (idx_of(h) == NIL) { return NIL; }
        uint16_t out;
        if (tagged_try_pop(h, next_idx[idx_of(h)], &out)) { return out; }
    }
}
static void tagged_push(uint16_t i)
{
    for (;;) {
        uint32_t h = atomic_load(&thead);
        next_idx[i] = idx_of(h);
        uint32_t expect = h;
        if (atomic_compare_exchange_strong(&thead, &expect, pack((uint16_t)(tag_of(h) + 1u), i))) { return; }
    }
}

int main(void)
{
    /* Thread 1 starts pop: reads head = A(0) and A->next = B(1) ... and is preempted. */
    naive_reset();
    node_t *t1_head = atomic_load(&head);
    node_t *t1_next = t1_head->next;
    /* Thread 2: pop A, pop B (B is now "in use" by T2), push A back. */
    node_t *a = naive_pop(); node_t *b = naive_pop(); naive_push(a);
    /* Thread 1 resumes: CAS(head, A, B) - head IS A again, so it succeeds. */
    node_t *expect = t1_head;
    bool ok = atomic_compare_exchange_strong(&head, &expect, t1_next);
    node_t *h = atomic_load(&head);
    printf("naive : T1 CAS(head: A->B) %s; head is now node %u, which T2 still owns (b=%u) -> %s\n",
           ok ? "SUCCEEDED" : "failed", (unsigned)h->id, (unsigned)b->id,
           (h == b) ? "CORRUPTED free list (B handed out twice)" : "ok");

    /* Same interleaving with the tagged head. */
    tagged_reset();
    uint32_t t1_seen = atomic_load(&thead);
    uint16_t t1_next_i = next_idx[idx_of(t1_seen)];
    uint16_t ta = tagged_pop(); uint16_t tb = tagged_pop(); tagged_push(ta);
    uint16_t got;
    bool ok2 = tagged_try_pop(t1_seen, t1_next_i, &got);
    uint32_t now = atomic_load(&thead);
    printf("tagged: T1 CAS(head {tag %u, A} -> {tag %u, B}) %s; head is {tag %u, node %u}; T2 owns node %u\n",
           (unsigned)tag_of(t1_seen), (unsigned)tag_of(t1_seen) + 1u, ok2 ? "SUCCEEDED" : "FAILED (retry)",
           (unsigned)tag_of(now), (unsigned)idx_of(now), (unsigned)tb);
    return 0;
}
```

**Output (verified, deterministic scripted interleaving):**

```text
naive : T1 CAS(head: A->B) SUCCEEDED; head is now node 1, which T2 still owns (b=1) -> CORRUPTED free list (B handed out twice)
tagged: T1 CAS(head {tag 0, A} -> {tag 1, B}) FAILED (retry); head is {tag 3, node 0}; T2 owns node 1
```

Walking through it:
1. T1 reads `head = A` and `A->next = B`, then is preempted.
2. T2 pops A, pops B (B is now in use by T2), and pushes A back.
3. T1 resumes. `head == A`, so `CAS(head, A, B)` **succeeds** and installs B, which T2 still owns.
4. The next pop hands B out **twice**.

The value of `head` is the same; its *meaning* isn't.

**Fixes, by context:**

| Technique | How | Where |
|---|---|---|
| **Tagged head** (`{tag, index}` or `{tag, pointer}`) | Every successful update increments the tag, so a recycled index or pointer no longer compares equal (verified: the CAS *fails* and retries; head is `{tag 3, node 0}`) | Embedded pools and free lists. A 16-bit index + 16-bit tag fits **one 32-bit LL/SC word** on Cortex-M (verified `cas_packed` → `ldrex`/`strex` below). Tag wrap needs 65,536 updates *during one preemption*, which is a bounded, analyzable risk |
| Sequence numbers per cell | Vyukov MPMC (above) | Bounded queues |
| LL/SC directly on the head | The reservation breaks on *any* intervening write, so ABA is impossible. But compilers expose only CAS, and LL/SC can't load `h->next` safely inside the window | Hand-written kernels; rarely worth it |
| Safe memory reclamation | Hazard pointers, epoch-based reclamation, RCU: never free (or reuse) a node while a thread may hold a reference | Dynamic-memory lock-free structures (Linux, user-space servers) |
| Double-width CAS | `{pointer, counter}` in 2× the pointer width | 64-bit systems with `CMPXCHG16B` / `CASP` |

**Double-width CAS, per ISA:**

```c
/* wide_cas.c - the CAS width an ABA-proof {pointer, tag} head needs, per ISA. */
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct { void *ptr; uintptr_t tag; } tagged_ptr_t;     /* 2 x pointer width */
_Atomic tagged_ptr_t g_head_wide;
_Atomic uint32_t     g_head_packed;                            /* {16-bit tag, 16-bit index} */

bool cas_wide(tagged_ptr_t *expected, tagged_ptr_t desired);
bool cas_wide(tagged_ptr_t *expected, tagged_ptr_t desired)
{
    return atomic_compare_exchange_strong_explicit(&g_head_wide, expected, desired,
                                                   memory_order_acq_rel, memory_order_acquire);
}

bool cas_packed(uint32_t *expected, uint32_t desired);
bool cas_packed(uint32_t *expected, uint32_t desired)
{
    return atomic_compare_exchange_strong_explicit(&g_head_packed, expected, desired,
                                                   memory_order_acq_rel, memory_order_acquire);
}
```

**Codegen (verified — Clang 21.1.0, `-O2`; AArch64 v8.0, AArch64 v8.4 LSE, x86-64 baseline, Cortex-M7):**

```asm
== a64e
cas_wide:
	ldp	x11, x8, [x0]
	adrp	x12, g_head_wide
	add	x12, x12, :lo12:g_head_wide
.LBB0_1:
	ldaxp	x10, x9, [x12]
	cmp	x10, x11
	cset	w13, ne
	cmp	x9, x8
	cinc	w13, w13, ne
	cbz	w13, .LBB0_3
	stlxp	w13, x10, x9, [x12]
	cbnz	w13, .LBB0_1
	b	.LBB0_4
.LBB0_3:
	stlxp	w13, x1, x2, [x12]
	cbnz	w13, .LBB0_1
.LBB0_4:
	cmp	x10, x11
	ccmp	x9, x8, #0, eq
	cset	w8, eq
	b.eq	.LBB0_6
	stp	x10, x9, [x0]
.LBB0_6:
	mov	w0, w8
	ret
cas_packed:
	ldr	w8, [x0]
	adrp	x10, g_head_packed
	add	x10, x10, :lo12:g_head_packed
.LBB1_1:
	ldaxr	w9, [x10]
	cmp	w9, w8
	b.ne	.LBB1_4
	stlxr	w11, w1, [x10]
	cbnz	w11, .LBB1_1
	mov	w8, #1
	tbz	w8, #0, .LBB1_5
	b	.LBB1_6
.LBB1_4:
	mov	w8, wzr
	clrex
	tbnz	w8, #0, .LBB1_6
.LBB1_5:
	str	w9, [x0]
.LBB1_6:
	mov	w0, w8
	ret
== a64lse
cas_wide:
	ldp	x4, x5, [x0]
	mov	x7, x2
	mov	x6, x1
	adrp	x8, g_head_wide
	add	x8, x8, :lo12:g_head_wide
	mov	x2, x4
	mov	x3, x5
	caspal	x2, x3, x6, x7, [x8]
	cmp	x2, x4
	ccmp	x3, x5, #0, eq
	cset	w8, eq
	b.eq	.LBB0_2
	stp	x2, x3, [x0]
.LBB0_2:
	mov	w0, w8
	ret
cas_packed:
	ldr	w8, [x0]
	adrp	x10, g_head_packed
	add	x10, x10, :lo12:g_head_packed
	mov	w9, w8
	casal	w9, w1, [x10]
	cmp	w9, w8
	cset	w8, eq
	b.eq	.LBB1_2
	str	w9, [x0]
.LBB1_2:
	mov	w0, w8
	ret
== x64e
cas_wide:
	pushq	%rbx
	subq	$16, %rsp
	movq	%rdx, %rcx
	movq	%rsi, %rdx
	movq	%rdi, %rbx
	movups	(%rdi), %xmm0
	movaps	%xmm0, (%rsp)
	movq	%rsp, %rsi
	movl	$g_head_wide, %edi
	movl	$4, %r8d
	movl	$2, %r9d
	callq	__atomic_compare_exchange_16@PLT
	testb	%al, %al
	jne	.LBB0_2
	movq	(%rsp), %rcx
	movq	8(%rsp), %rdx
	movq	%rcx, (%rbx)
	movq	%rdx, 8(%rbx)
.LBB0_2:
	addq	$16, %rsp
	popq	%rbx
	retq
cas_packed:
	movl	(%rdi), %eax
	lock		cmpxchgl	%esi, g_head_packed(%rip)
	sete	%cl
	je	.LBB1_2
	movl	%eax, (%rdi)
.LBB1_2:
	movl	%ecx, %eax
	retq
== m7
cas_wide:
	push	{r4, lr}
	sub	sp, #24
	strd	r1, r2, [sp, #8]
	movw	r1, :lower16:g_head_wide
	mov	r4, r0
	ldrd	r0, r3, [r0]
	strd	r0, r3, [sp, #16]
	movt	r1, :upper16:g_head_wide
	add	r2, sp, #16
	add	r3, sp, #8
	movs	r0, #8
	mov.w	r12, #2
	mov.w	lr, #4
	strd	lr, r12, [sp]
	bl	__atomic_compare_exchange
	cbnz	r0, .LBB0_2
	ldrd	r1, r2, [sp, #16]
	strd	r1, r2, [r4]
.LBB0_2:
	add	sp, #24
	pop	{r4, pc}
cas_packed:
	push	{r7, lr}
	movw	r12, :lower16:g_head_packed
	ldr.w	lr, [r0]
	movt	r12, :upper16:g_head_packed
	ldrex	r2, [r12]
	cmp	r2, lr
	bne	.LBB1_4
	dmb	sy
.LBB1_2:
	strex	r3, r1, [r12]
	cbz	r3, .LBB1_5
	ldrex	r2, [r12]
	cmp	r2, lr
	beq	.LBB1_2
.LBB1_4:
	clrex
	movs	r1, #0
	b	.LBB1_6
.LBB1_5:
	movs	r1, #1
.LBB1_6:
	dmb	sy
	cmp	r1, #0
	it	eq
	streq	r2, [r0]
	mov	r0, r1
	pop	{r7, pc}
```

**x86-64 with `-mcx16` (verified):**

```asm
cas_wide:
	pushq	%rbx
	movq	%rdx, %rcx
	movq	(%rdi), %rax
	movq	8(%rdi), %rdx
	movq	%rsi, %rbx
	lock		cmpxchg16b	g_head_wide(%rip)
	sete	%cl
	je	.LBB0_2
	movq	%rax, (%rdi)
	movq	%rdx, 8(%rdi)
.LBB0_2:
	movl	%ecx, %eax
	popq	%rbx
	retq
cas_packed:
	movl	(%rdi), %eax
	lock		cmpxchgl	%esi, g_head_packed(%rip)
	sete	%cl
	je	.LBB1_2
	movl	%eax, (%rdi)
.LBB1_2:
	movl	%ecx, %eax
	retq
```

| ISA | 2 × pointer CAS (`cas_wide`) | 32-bit `{tag, index}` (`cas_packed`) |
|---|---|---|
| AArch64 v8.0 | `ldaxp`/`stlxp` loop (a store-exclusive *pair*, also on failure, to check atomicity) | `ldaxr`/`stlxr` + `clrex` |
| AArch64 v8.1+ (LSE) | **`caspal`**: one instruction | **`casal`** |
| x86-64 baseline | **library call** `__atomic_compare_exchange_16`: `cmpxchg16b` isn't in the base x86-64 ISA | `lock cmpxchgl` |
| x86-64 `-mcx16` | `lock cmpxchg16b` | `lock cmpxchgl` |
| Cortex-M7 | **library call** `__atomic_compare_exchange` (no `LDREXD` on v7-M) | `ldrex`/`strex` + `clrex` + `dmb sy` |

That's why embedded lock-free free lists use **indices plus a tag packed into 32 bits**: it's the widest *lock-free* CAS on every Cortex-M with exclusives, and indices are smaller and safer than pointers anyway (File 01).

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* ring_bad.c - the "lock-free" ring from a blog post. */
#include <stdint.h>

#define CAP 100u                              /* BUG 1: not a power of two: modulo is slow, and
                                               *        free-running indices break at 2^32 wrap   */
typedef struct {
    volatile uint32_t head, tail;             /* BUG 2: same cache line: false sharing           */
    uint32_t buf[CAP];                        /* BUG 3: volatile != ordering: element may become
                                               *        visible AFTER head on ARM (Folder 03)    */
} ring_t;

int ring_push(ring_t *r, uint32_t v);
int ring_push(ring_t *r, uint32_t v)
{
    uint32_t next = (r->head + 1u) % CAP;
    if (next == r->tail) { return -1; }       /* BUG 4: wastes a slot; reads tail without acquire */
    r->buf[r->head] = v;
    r->head = next;                           /* BUG 5: no release                               */
    return 0;
}

/* BUG 6: used with two producers (two ISRs at different priorities) - SPSC
 *        invariant violated; needs MPMC or a critical section. */
```

### 2.2 The Silicon-Hardened Production Way

- **SPSC:** `spsc.h` (verified): power-of-two capacity, free-running indices, separate lines, cached opposite index, and release/acquire in both directions.
- **MPMC:** `mpmc.h` (verified): per-cell sequence numbers, CAS-claimed positions, sign-bit comparisons.
- **Free lists:** a tagged 32-bit `{tag, index}` head (verified ABA fix). Folder 07 File 03 packages it as a lock-free, ISR-safe, canary-checked fixed-block pool.
- **Choosing:**

| Producers / consumers | Use |
|---|---|
| ISR → task, task → task, core → core (one each) | SPSC |
| Several ISRs at different priorities → one task | One SPSC per producer (simplest, wait-free), or MPMC |
| N ↔ M threads on SMP | MPMC (bounded), or a lock if contention is low and fairness matters |
| Need unbounded / dynamic size | Don't, in real-time code. Otherwise use a linked lock-free queue with hazard pointers/epochs (Michael & Scott) |

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| Ring occasionally delivers a stale or garbage element, on ARM only | Missing release on the index publish, or missing acquire on the consumer | Disassemble push/pop: look for `stlr`/`dmb` before the index store and `ldar`/`ldapr`/`dmb` after the index load. Run the stress test on ARM64 |
| Ring corrupts after ~4 billion operations | Non-power-of-two capacity with free-running indices, or signed index arithmetic | Unit test with indices initialized near `UINT32_MAX` |
| LL/SC loop spins forever (livelock) | Memory access or call inside the exclusive window; or two cores hammering one ERG | Disassemble the loop (no `ldr`/`str`/`bl` between `ldrex` and `strex`). Measure `STREX` failure rates with a debugger counter; move to LSE |
| Free list hands out the same block twice | ABA | Scripted interleaving test (§1.5), a tag on the head, ownership bitmaps (File 01) to catch it |
| Throughput collapses with more cores | Contended CAS on one index; LL/SC retry storms | `perf c2c`; switch to per-core SPSC rings, batching, LSE atomics |
| `STREX` "randomly" succeeds after a context switch on a custom A-profile kernel | Missing `CLREX` on the switch path | Review the switch code; Linux's `arch/arm` uses `clrex` (or its documented equivalent) on exception return (⚠ verify for your architecture version) |

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Implement an SPSC ring between an ISR and a task. Which memory orders, and why?"

- **L5:** "Make head and tail `volatile`."
- **Why L5 fails on multi-core ARM/DMA hardware:** `volatile` orders nothing in hardware (Folder 03). On ARM the element store can become visible after the index store. Without consumer→producer ordering, the producer can overwrite a slot the consumer is still reading. On one core the hardware happens to preserve order, but the *compiler* doesn't without barriers.
- **L7 principal defense:** The verified `spsc.h`:
  - release store of `head` after the element write;
  - acquire load of `head` before reading it;
  - release store of `tail` after the read;
  - acquire load of `tail` before overwriting;
  - power-of-two free-running indices;
  - separate cache lines, and cached opposite indices.
  
  Show the M7 codegen (one `dmb sy` per side) and the AArch64 version (`stlr`/`ldapr`). Evidence: 20M items in order. Note it's wait-free, so ISR-safe with no inversion.

### Q2 🔥 "What is ABA? Show me it happening, and fix it on a Cortex-M4."

- **L5:** "A value changes from A to B and back; use a counter."
- **Why L5 fails:** It needs a mechanism and a constraint. On Cortex-M4 there is no 64-bit CAS (`ATOMIC_LLONG_LOCK_FREE` is 1; verified library call), so "pointer + counter" doesn't fit.
- **L7 defense:**
  - The verified scripted interleaving: the naive CAS succeeds and hands B out twice.
  - The tagged CAS fails and retries.
  - On Cortex-M, use 16-bit **indices** + a 16-bit tag in one 32-bit word (verified `cas_packed` → `ldrex`/`strex`), with nodes in a static pool (File 01).
  - Bound the tag-wrap risk: 65,536 head updates within one preemption window.
  - On 64-bit servers use `caspal` (LSE) or `cmpxchg16b` (with `-mcx16`), or avoid reuse through hazard pointers/epochs.

### Q3 "Why must the consumer use acquire when reading `head`, if the producer already used release?"

- **L5:** "To be safe."
- **Why L5 fails:** Release/acquire is a **pair**. Release orders the producer's earlier stores before its `head` store. Without an acquire on the consumer side, the consumer's later loads of the element can be satisfied *before* its load of `head` (load→load reordering on ARM). It would then read the old element despite seeing the new index.
- **L7 defense:** Draw the happens-before edge. Show `ldapr` (RCpc acquire) and `ldr` + `dmb` (M7) in the verified listings, and mention address dependencies as Linux's lighter alternative for pointer-chasing (`READ_ONCE`), with its compiler caveats.

### Q4 🧊 "LL/SC vs. LSE: what changes for a lock-free queue on Neoverse?"

- **L5:** "LSE is faster."
- **Why L5 fails:** *Why* is the point. LL/SC holds a reservation the line must keep across the loop, and under contention reservations break and retries multiply. LSE atomics are single instructions that can be executed as **far atomics** at the interconnect home node, with no line migration to the requester and no retry loop.
- **L7 defense:** Show `ldaxr`/`stlxr` loops (v8.0) versus `ldaddal`/`casal`/`caspal` (v8.4, verified). Build with `-march=armv8.1-a+` or `-moutline-atomics` for mixed fleets. Measure with `perf` contention counters. Still avoid single shared hot indices: shard per core.

### Q5 "Is the Vyukov MPMC queue wait-free?"

- **L5:** "Yes, it's lock-free."
- **Why L5 fails:** Lock-free ≠ wait-free. A producer that keeps losing the CAS on `enq` can retry indefinitely (others make progress, so it's lock-free, but no per-operation bound exists). A preempted producer between claiming a position and publishing `seq` also blocks consumers *of that cell* (but not other cells).
- **L7 defense:** State the guarantees precisely: lock-free, linearizable, bounded capacity, per-cell blocking window. For hard real time, prefer per-producer SPSC rings (wait-free) and merge in the consumer.

---

## 5. Invariants Checklist

- [ ] SPSC only with exactly one producer context and one consumer context (multiple ISRs = multiple producers).
- [ ] Power-of-two capacity; free-running unsigned indices; wrap tested near `UINT32_MAX`.
- [ ] Release on every publish, acquire on every observe, in both directions.
- [ ] Producer- and consumer-owned fields on separate cache lines (and lock words in separate ERGs).
- [ ] Every CAS on a reusable pointer or index has an ABA defense: tag, sequence numbers, or safe reclamation.
- [ ] Lock-free width checked per target (`ATOMIC_*_LOCK_FREE`); embedded free lists use 32-bit `{tag, index}`.
- [ ] LL/SC hand-written only when unavoidable: minimal window, `CLREX` on failure, no accesses or calls inside.
- [ ] Stress-tested on ARM64 hardware, plus a herd7 model of the publish/consume protocol.

## 6. References

1. Arm, *ARMv7-M ARM* A3.4; *Arm ARM for A-profile* (DDI 0487) B2.9 exclusive monitors and ERG, C6 `CAS`/`CASP`/`LDADD` (FEAT_LSE).
2. M. Herlihy, *Wait-Free Synchronization*, ACM TOPLAS 13(1), 1991; M. Herlihy, N. Shavit, *The Art of Multiprocessor Programming*, 2nd ed.
3. R. K. Treiber, *Systems Programming: Coping with Parallelism*, IBM Research Report RJ 5118, 1986.
4. D. Vyukov, *Bounded MPMC queue*, 1024cores.net; DPDK `rte_ring` documentation.
5. M. M. Michael, *Hazard Pointers: Safe Memory Reclamation for Lock-Free Objects*, IEEE TPDS 15(6), 2004; M. Michael, M. Scott, *Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms*, PODC 1996.
6. Linux `include/linux/kfifo.h`, `include/linux/llist.h`, `Documentation/core-api/circular-buffers.rst`.
