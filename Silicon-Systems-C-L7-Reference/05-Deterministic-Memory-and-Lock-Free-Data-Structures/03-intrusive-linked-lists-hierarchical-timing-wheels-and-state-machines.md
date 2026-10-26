# 03 · Intrusive Linked Lists, Hierarchical Timing Wheels, and State Machines

> **Folder:** `05-Deterministic-Memory-and-Lock-Free-Data-Structures/` · **File 3 of 3**
> **Anchors:**
> - Linux `include/linux/list.h` (intrusive `list_head`, `container_of`) and `kernel/time/timer.c` (the timer wheel; Gleixner's 2016 rework).
> - G. Varghese, T. Lauck, *Hashed and Hierarchical Timing Wheels* (SOSP 1987).
> - D. Harel, *Statecharts* (1987); M. Samek, *Practical UML Statecharts in C/C++* (QP framework).
> - MISRA C:2012 Rules 16.4 (`switch` default), 14.x (loops), 18.x (pointers).
>
> **Verification:**
> - The intrusive list, a 4-level × 64-slot timing wheel (2,000 timers, 400,001 ticks: every timer fires at exactly its tick), and a table-driven protocol FSM all compiled warning-free for Cortex-M0+/M7/AArch64; the self-tests ran natively.
> - The FSM dispatch codegen is inserted verbatim.

---

## 0. The thesis

The three structures that dominate firmware and kernels (lists of objects, timeouts, protocol states) all have a deterministic, allocation-free form:

- **intrusive lists** put the link inside the object, so insert and remove are O(1) with no allocation;
- **timing wheels** make starting and cancelling a timeout O(1), independent of how many are pending;
- **table-driven state machines** make every (state, event) pair explicit, so the behavior is reviewable and can't fall through.

Each replaces a structure that is "fine in tests" with one whose worst case you can state.

---

## 1. First-Principles Mechanics

### 1.1 Intrusive lists

```c
/* ilist.h - intrusive, circular, doubly linked list with a sentinel (the
 * Linux list_head design): O(1) insert/remove with no allocation, no
 * NULL checks on the hot path, and an object can be on several lists via
 * several embedded nodes. */
#ifndef ILIST_H
#define ILIST_H

#include <stdbool.h>
#include <stddef.h>

typedef struct ilist_node {
    struct ilist_node *next, *prev;
} ilist_node_t;

#define ILIST_CONTAINER_OF(ptr, type, member) \
    ((type *)(void *)((char *)(ptr) - offsetof(type, member)))

static inline void ilist_init(ilist_node_t *head) { head->next = head; head->prev = head; }
static inline bool ilist_empty(const ilist_node_t *head) { return head->next == head; }

static inline void ilist_insert_between(ilist_node_t *n, ilist_node_t *prev, ilist_node_t *next)
{
    n->prev = prev;
    n->next = next;
    prev->next = n;
    next->prev = n;
}
static inline void ilist_push_back(ilist_node_t *head, ilist_node_t *n)  { ilist_insert_between(n, head->prev, head); }
static inline void ilist_push_front(ilist_node_t *head, ilist_node_t *n) { ilist_insert_between(n, head, head->next); }

/* Unlink and self-loop: removing an already-removed node is then harmless,
 * and "am I linked?" is (n->next != n). */
static inline void ilist_remove(ilist_node_t *n)
{
    n->prev->next = n->next;
    n->next->prev = n->prev;
    n->next = n;
    n->prev = n;
}

/* Move every node of src to the end of dst in O(1). */
static inline void ilist_splice_back(ilist_node_t *dst, ilist_node_t *src)
{
    if (ilist_empty(src)) { return; }
    ilist_node_t *first = src->next, *last = src->prev;
    first->prev = dst->prev;
    dst->prev->next = first;
    last->next = dst;
    dst->prev = last;
    ilist_init(src);
}

#endif /* ILIST_H */
```

| Property | Intrusive (this) | External (`list.append(obj)`, nodes allocated separately) |
|---|---|---|
| Allocation on insert | **none** | one node per insert (heap or pool) |
| Remove given the object | **O(1)**: the node is inside the object | O(n) search, or a stored back-pointer |
| Object on several lists | Yes: one embedded node per list (e.g. a task on a ready list *and* a timer list) | Needs several allocations |
| Cache behavior | The node shares a line with the object's hot fields | An extra pointer chase to a separate node |
| Failure modes | Forgetting to remove before freeing (dangling links). Mitigated by self-looping on remove (`n->next == n` ⇒ unlinked) | Allocation failure; leaks |

The **sentinel** (a circular list with a head node) removes every NULL check from insert and remove. `ilist_remove` *self-loops* the removed node, so a second remove is harmless (verified in the timer test: `tw_cancel` called twice). `ILIST_CONTAINER_OF` is the `char *` / `offsetof` idiom, which stays within one object's provenance (Folder 01, File 01 §3.3).

### 1.2 Hierarchical timing wheels

Most timers in a system are **cancelled before they fire**: retransmit timers, watchdog-style supervision, protocol timeouts. A sorted list costs O(n) per start. A binary heap costs O(log n) per start and cancel. A **timing wheel** makes start and cancel O(1):

```text
 level 0: 64 slots x 1 tick       covers delays    1 ..      63
 level 1: 64 slots x 64 ticks     covers delays   64 ..    4095
 level 2: 64 slots x 4096 ticks   covers delays 4096 ..  262143
 level 3: 64 slots x 262144 ticks covers delays     .. 16777215  (2^24 ticks)

 start(t, d):  choose level by d; slot = (expires >> 6*level) & 63; O(1) list append
 tick():       now++; whenever level k-1 wraps (now % 64^k == 0) CASCADE level-k slot
               into lower levels; then fire everything in level-0 slot (now & 63)
```

```c
/* twheel.c - hierarchical timing wheel (Varghese & Lauck 1987): 4 levels x 64
 * slots cover 2^24 ticks. O(1) start/cancel, amortized O(1) per tick; level-k
 * slots cascade into lower levels when the lower level wraps. Timers are
 * intrusive (no allocation): the caller owns the storage. */
#include <stdbool.h>
#include <stdint.h>

#include "ilist.h"

#define TW_BITS   6u
#define TW_SLOTS  (1u << TW_BITS)
#define TW_LEVELS 4u
#define TW_MASK   (TW_SLOTS - 1u)

typedef struct tw_timer {
    ilist_node_t node;
    uint32_t     expires;                   /* absolute tick */
    void       (*cb)(struct tw_timer *t, uint32_t now);
} tw_timer_t;

typedef struct {
    uint32_t     now;
    ilist_node_t slot[TW_LEVELS][TW_SLOTS];
    uint32_t     cascaded;                  /* instrumentation: timers moved between levels */
} twheel_t;

void tw_init(twheel_t *w);
int  tw_start(twheel_t *w, tw_timer_t *t, uint32_t delay);
void tw_cancel(tw_timer_t *t);
void tw_tick(twheel_t *w);

void tw_init(twheel_t *w)
{
    w->now = 0u;
    w->cascaded = 0u;
    for (uint32_t l = 0u; l < TW_LEVELS; l++) {
        for (uint32_t s = 0u; s < TW_SLOTS; s++) { ilist_init(&w->slot[l][s]); }
    }
}

static void place(twheel_t *w, tw_timer_t *t)
{
    uint32_t delta = t->expires - w->now;
    uint32_t level = 0u;
    while ((level + 1u < TW_LEVELS) && (delta >= (1u << (TW_BITS * (level + 1u))))) { level++; }
    uint32_t idx = (t->expires >> (TW_BITS * level)) & TW_MASK;
    ilist_push_back(&w->slot[level][idx], &t->node);
}

int tw_start(twheel_t *w, tw_timer_t *t, uint32_t delay)
{
    if ((delay == 0u) || (delay >= (1u << (TW_BITS * TW_LEVELS)))) { return -1; }
    t->expires = w->now + delay;
    place(w, t);
    return 0;
}

void tw_cancel(tw_timer_t *t) { ilist_remove(&t->node); }   /* O(1), idempotent */

static void cascade(twheel_t *w, uint32_t level)
{
    uint32_t idx = (w->now >> (TW_BITS * level)) & TW_MASK;
    ilist_node_t moving;
    ilist_init(&moving);
    ilist_splice_back(&moving, &w->slot[level][idx]);
    while (!ilist_empty(&moving)) {
        tw_timer_t *t = ILIST_CONTAINER_OF(moving.next, tw_timer_t, node);
        ilist_remove(&t->node);
        place(w, t);                         /* lands in a lower level (or level 0) */
        w->cascaded++;
    }
}

void tw_tick(twheel_t *w)
{
    w->now++;
    /* When level k-1 wraps, pull the matching level-k slot down. */
    for (uint32_t l = 1u; l < TW_LEVELS; l++) {
        if ((w->now & ((1u << (TW_BITS * l)) - 1u)) != 0u) { break; }
        cascade(w, l);
    }
    ilist_node_t *head = &w->slot[0][w->now & TW_MASK];
    while (!ilist_empty(head)) {
        tw_timer_t *t = ILIST_CONTAINER_OF(head->next, tw_timer_t, node);
        ilist_remove(&t->node);
        t->cb(t, w->now);                    /* callback may restart the timer */
    }
}

#ifdef TW_SELFTEST
#include <stdio.h>

#define NT 2000u
static tw_timer_t timers[NT];
static uint32_t fired_at[NT];
static uint32_t fired, mismatched;

static void on_fire(tw_timer_t *t, uint32_t now)
{
    uint32_t i = (uint32_t)(t - timers);
    fired_at[i] = now;
    fired++;
    if (now != t->expires) { mismatched++; }
}

int main(void)
{
    static twheel_t w;
    uint32_t rng = 0xBADC0DEu;
    tw_init(&w);
    const uint32_t fixed[] = { 1u, 63u, 64u, 65u, 4095u, 4096u, 4097u, 262143u, 262144u, 300000u };
    uint32_t n = 0u;
    for (; n < 10u; n++) { timers[n].cb = on_fire; (void)tw_start(&w, &timers[n], fixed[n]); }
    for (; n < NT; n++) {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
        timers[n].cb = on_fire;
        (void)tw_start(&w, &timers[n], 1u + rng % 400000u);
    }
    tw_cancel(&timers[3]);                     /* the 65-tick timer */
    tw_cancel(&timers[3]);                     /* idempotent */
    for (uint32_t k = 0u; k < 400001u; k++) { tw_tick(&w); }
    printf("timers=%u fired=%u (1 cancelled) fired-at-wrong-tick=%u cascades=%u\n",
           (unsigned)NT, (unsigned)fired, (unsigned)mismatched, (unsigned)w.cascaded);
    printf("fixed delays fired at:");
    for (uint32_t i = 0u; i < 10u; i++) { printf(" %u", (unsigned)fired_at[i]); }
    printf("  (index 3 cancelled -> 0)\n");
    return 0;
}
#endif
```

**Self-test output (verified, native; 2,000 timers, including edge delays at every level boundary):**

```text
timers=2000 fired=1999 (1 cancelled) fired-at-wrong-tick=0 cascades=4592
fixed delays fired at: 1 63 64 0 4095 4096 4097 262143 262144 300000  (index 3 cancelled -> 0)
```

- **0 timers fired at the wrong tick**, including the boundary cases 63/64/65 (level 0/1), 4095/4096/4097 (level 1/2) and 262143/262144 (level 2/3).
- The cancelled 65-tick timer never fired. A double cancel was harmless, thanks to the self-looping remove.
- **4,592 cascades** for 2,000 timers over 400,000 ticks. A timer placed at a high level is re-filed at most once per level on its way down (≤ 3 moves here), which is **amortized O(1)** per timer. The worst case for a *single* tick is a cascade of everything in one high-level slot. That is bounded by the number of timers, and spread across ticks by the slot design.

Design notes:
- **Precision vs range.** Higher levels have coarser slots. A timer cascades into the correct lower slot, so this implementation fires *exactly* on time. Linux's 2016 rework deliberately trades exactness for no cascading: timers in upper levels fire *late*, by up to the level's granularity. That's acceptable for timeouts that are usually cancelled. Choose per use: exact for protocol timing, lossy for "about 30 s" timeouts.
- **Callbacks run in the tick context** (an ISR or a timer task). They must be short and may restart their own timer (supported: the timer is unlinked before the callback runs).
- **One-shot hardware timer for tickless systems.** Program the hardware for the earliest non-empty slot's tick (File 02 tickless idle) instead of ticking through empty slots.

### 1.3 Table-driven, run-to-completion state machines

```c
/* fsm.c - table-driven, run-to-completion state machine: a framed serial
 * protocol  [0x7E][len][payload...][xor] . Every (state, event-class) pair
 * has an explicit entry - no default fall-through, no missing transition. */
#include <stdbool.h>
#include <stdint.h>

typedef enum { ST_IDLE = 0, ST_LEN, ST_PAYLOAD, ST_CHECK, ST_COUNT } state_t;
typedef enum { EV_SYNC = 0, EV_BYTE, EV_TIMEOUT, EV_COUNT } event_t;   /* event classes */

typedef struct {
    state_t  st;
    uint8_t  len, got, sum;
    uint8_t  buf[32];
    uint32_t frames_ok, frames_bad, resyncs;
} parser_t;

typedef state_t (*action_t)(parser_t *p, uint8_t b);

static state_t a_ignore(parser_t *p, uint8_t b) { (void)b; return p->st; }
static state_t a_start(parser_t *p, uint8_t b)  { (void)b; p->got = 0u; p->sum = 0u; return ST_LEN; }
static state_t a_resync(parser_t *p, uint8_t b) { (void)b; p->resyncs++; p->got = 0u; p->sum = 0u; return ST_LEN; }
static state_t a_abort(parser_t *p, uint8_t b)  { (void)b; p->frames_bad++; return ST_IDLE; }
static state_t a_len(parser_t *p, uint8_t b)
{
    if ((b == 0u) || (b > sizeof p->buf)) { p->frames_bad++; return ST_IDLE; }
    p->len = b; p->sum ^= b; return ST_PAYLOAD;
}
static state_t a_data(parser_t *p, uint8_t b)
{
    p->buf[p->got++] = b; p->sum ^= b;
    return (p->got == p->len) ? ST_CHECK : ST_PAYLOAD;
}
static state_t a_check(parser_t *p, uint8_t b)
{
    if (b == p->sum) { p->frames_ok++; } else { p->frames_bad++; }
    return ST_IDLE;
}

/* The whole behaviour, reviewable in one screen. */
static const action_t k_table[ST_COUNT][EV_COUNT] = {
    /*               EV_SYNC     EV_BYTE    EV_TIMEOUT */
    [ST_IDLE]    = { a_start,    a_ignore,  a_ignore },
    [ST_LEN]     = { a_resync,   a_len,     a_abort  },
    [ST_PAYLOAD] = { a_data,     a_data,    a_abort  },   /* 0x7E is legal payload (length-framed) */
    [ST_CHECK]   = { a_check,    a_check,   a_abort  },
};

void parser_event(parser_t *p, event_t ev, uint8_t b);
void parser_event(parser_t *p, event_t ev, uint8_t b)
{
    if (((unsigned)p->st >= (unsigned)ST_COUNT) || ((unsigned)ev >= (unsigned)EV_COUNT)) {
        p->st = ST_IDLE;                      /* corrupted state: fail safe, never index OOB */
        return;
    }
    p->st = k_table[p->st][ev](p, b);
}

void parser_byte(parser_t *p, uint8_t b);
void parser_byte(parser_t *p, uint8_t b) { parser_event(p, (b == 0x7Eu) ? EV_SYNC : EV_BYTE, b); }

#ifdef FSM_SELFTEST
#include <stdio.h>

int main(void)
{
    parser_t p = { ST_IDLE, 0u, 0u, 0u, { 0 }, 0u, 0u, 0u };
    const uint8_t stream[] = {
        0x00, 0x7E, 0x03, 0x11, 0x7E, 0x33, 0x03 ^ 0x11 ^ 0x7E ^ 0x33,  /* good frame, 0x7E inside payload */
        0x7E, 0x02, 0xAA, 0xBB, 0x00,                                   /* bad checksum                     */
        0x7E, 0x7E, 0x01, 0x42, 0x01 ^ 0x42,                            /* double sync -> resync, good      */
        0x7E, 0x40,                                                     /* length 64 > 32 -> rejected       */
    };
    for (unsigned i = 0u; i < sizeof stream; i++) { parser_byte(&p, stream[i]); }
    parser_event(&p, EV_TIMEOUT, 0u);
    printf("frames ok=%u bad=%u resyncs=%u final state=%d\n",
           (unsigned)p.frames_ok, (unsigned)p.frames_bad, (unsigned)p.resyncs, (int)p.st);
    return 0;
}
#endif
```

**Self-test output (verified, native):**

```text
frames ok=2 bad=2 resyncs=1 final state=0
```

The test stream contains:
1. a good frame whose payload includes the sync byte `0x7E` (legal, because the protocol is length-framed);
2. a frame with a bad checksum;
3. a double sync, which causes a resync followed by a good frame;
4. an oversize length (64 > 32), which is rejected.

The result is 2 good, 2 bad, 1 resync, and the parser ends `IDLE` after the timeout.

**Dispatch codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
parser_event:
	push	{r4, lr}
	cmp	r1, #2
	mov	r4, r0
	mov.w	r0, #0
	bhi	.LBB0_3
	ldr	r3, [r4]
	cmp	r3, #3
	bhi	.LBB0_3
	add.w	r0, r3, r3, lsl #1
	movw	r3, :lower16:k_table
	movt	r3, :upper16:k_table
	add.w	r0, r3, r0, lsl #2
	ldr.w	r3, [r0, r1, lsl #2]
	mov	r0, r4
	mov	r1, r2
	blx	r3
.LBB0_3:
	str	r0, [r4]
	pop	{r4, pc}
parser_byte:
```

The entire dispatcher is:
- **two bounds checks** (`cmp r1, #2` for the event, `cmp r3, #3` for the state; a corrupted state falls to `ST_IDLE` = 0 rather than indexing out of bounds);
- one index computation (`state × 3 + event`);
- one `blx` through the `const` table.

O(1) dispatch with a single, reviewable artifact (the table), and constant execution time per event. That suits WCET analysis (Folder 08).

**Why tables beat nested `switch` for safety code:**
- **Every (state, event) pair is explicit.** A missing entry is a visible hole in a 4 × 3 grid, not a forgotten `case`. MISRA Rule 16.4 demands a `default` in every `switch`, and tables make the "default" deliberate.
- **Run-to-completion.** Each event is fully processed before the next one (no re-entrancy). That's the property that lets ISRs post events into a queue (an SPSC ring, File 02) and a single task drain it, with no locks inside the FSM.
- **The `const` table lives in flash** (`.rodata`): it can't be corrupted by a RAM fault, and it can be CRC-checked at boot.
- **Hierarchical statecharts** (Harel; Samek's QP) add state nesting, entry/exit actions and guards, for complex devices. The flat table is the special case that covers most drivers and protocol parsers.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* timers_bad.c - the sorted-list timer service and the switch-statement parser. */
#include <stddef.h>
#include <stdint.h>

typedef struct tmr { struct tmr *next; uint32_t expires; void (*cb)(void); } tmr_t;
static tmr_t *g_list;                         /* sorted by expiry */

void tmr_start(tmr_t *t, uint32_t now, uint32_t delay);
void tmr_start(tmr_t *t, uint32_t now, uint32_t delay)
{
    t->expires = now + delay;
    tmr_t **pp = &g_list;
    while (*pp != NULL && (*pp)->expires <= t->expires) {   /* BUG 1: O(n) insert, in the tick ISR's  */
        pp = &(*pp)->next;                                  /*        critical section                 */
    }                                                       /* BUG 2: `<=` on raw ticks breaks at the  */
    t->next = *pp;                                          /*        2^32 wrap (use (int32_t)(a - b)  */
    *pp = t;                                                /*        or the wheel)                    */
}

void tmr_cancel(tmr_t *t);
void tmr_cancel(tmr_t *t)
{
    for (tmr_t **pp = &g_list; *pp != NULL; pp = &(*pp)->next) {   /* BUG 3: O(n) cancel        */
        if (*pp == t) { *pp = t->next; return; }
    }                                                               /* BUG 4: cancel of a timer   */
}                                                                   /* not in the list: silent    */

int parse(uint8_t b);
int parse(uint8_t b)
{
    static int st;
    switch (st) {
    case 0: if (b == 0x7Eu) { st = 1; } break;
    case 1: st = 2; break;                  /* BUG 5: no length validation, no checksum state     */
    case 2: if (b == 0x7Eu) { st = 1; } break;  /* BUG 6: treats in-band 0x7E as a new frame     */
    }                                       /* BUG 7: no default: a corrupted `st` is stuck forever */
    return st;
}
```

### 2.2 The Silicon-Hardened Production Way

The verified `ilist.h`, `twheel.c` and `fsm.c` above, plus:
- **Timer service:** wheel ticks driven from the RTOS tick, or from a one-shot hardware timer in tickless mode. Callbacks are deferred to a timer task if they're longer than a few microseconds. Timer storage is embedded in the owning objects (intrusive), with no allocation.
- **FSM:**
  - events posted by ISRs into an SPSC ring (File 02);
  - one task drains it and calls `parser_event()` (run-to-completion);
  - the table is `const` in flash, CRC-covered by the boot image check (Folder 02, File 03);
  - per-state timeouts implemented as wheel timers whose callbacks post `EV_TIMEOUT`.
- **Wrap-safe time comparisons:** `(int32_t)(a - b) < 0` means "a is before b" (implementation-defined conversion, as in File 02; or compare the sign bit of the unsigned difference). The wheel avoids comparisons entirely by indexing.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Mechanism | Diagnosis |
|---|---|---|
| Tick ISR execution time grows with load | O(n) timer insert/cancel/expiry in the ISR | DWT `CYCCNT` around the tick handler vs the number of active timers. Replace with the wheel |
| Timers fire early or never after ~49.7 days (at 1 kHz) | 32-bit tick wrap with `<=` comparisons | Unit test with `now` initialized near `UINT32_MAX` |
| Crash in list code long after an object was freed | Object freed while still linked (dangling intrusive node) | Debug builds: poison `next`/`prev` on free and assert that `n->next == n` (unlinked) before freeing |
| Parser stuck forever after an EMI burst | Corrupted state variable plus a `switch` without a default | Table dispatch with bounds check and reset to `IDLE` (verified codegen); periodic state-sanity checks |
| Protocol desync under in-band sync bytes | Byte-stuffing vs length-framing confusion | Fuzz the parser with random streams; check the "sync in payload" case explicitly (in the verified test stream) |

TRACE32 or GDB scripts that walk the wheel's slots (`slot[l][s]` sentinels) and count nodes give an instant picture of where timers are and how cascades will hit upcoming ticks.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Design a timer service for 10,000 TCP connections, each with a retransmit timer."

- **L5:** "A min-heap: O(log n)."
- **Why L5 fails:** Most retransmit timers are **cancelled** (the ACK arrives), so start and cancel dominate. A heap makes cancel O(log n) and needs an index back-pointer. Its per-operation cost and cache misses grow with n.
- **L7 principal defense:** A hierarchical timing wheel with intrusive timers. O(1) start and cancel; expiry amortized O(1) (verified: 2,000 timers, exact firing, 4,592 cascades total). Decide exact (cascade) versus lossy (Linux 2016 design: no cascading, bounded lateness) per timer class. Drive it from a one-shot hardware timer for the earliest slot in tickless systems.

### Q2 "Why does the Linux kernel use intrusive lists everywhere?"

- **L5:** "To save memory."
- **Why L5 fails:** Memory is the smallest benefit. The decisive properties are:
  - **no allocation on insert**, so it's usable in atomic contexts and IRQs, and it can't fail;
  - **O(1) removal given the object**;
  - **one object on many lists** (a task on run queues, wait queues and timer lists at once).
- **L7 defense:** The verified `ilist.h`: sentinel, self-looping remove (idempotent), O(1) splice. `container_of` with provenance-safe `char *` arithmetic. RCU-safe list variants (`list_add_rcu`) for lock-free readers. The dangling-link failure mode and how debug builds catch it.

### Q3 "Table-driven FSM or switch statement? Defend it for an ASIL-D gateway."

- **L5:** "Switch statements are more readable."
- **Why L5 fails:** Readability for whom? A reviewer certifying behavior needs **every (state, event) pair** visible. Switches hide missing cases and fall-throughs, and a corrupted state variable silently does nothing.
- **L7 defense:** The verified table FSM: a 4 × 3 grid of explicit actions, a bounds check on state and event that fails safe to `IDLE` (verified codegen), a `const` table in flash under CRC, constant-time dispatch for WCET, and run-to-completion with events from ISRs via an SPSC ring. For complex devices, hierarchical statecharts (QP) generated from a model, with the table as the reviewed artifact.

### Q4 🧊 "Your timer wheel fires a 70,000-tick timer at 69,632. Why?"

- **L5:** "Off-by-one."
- **Why L5 fails:** It's a classic *non-cascading* wheel artifact. The timer sits in a level-2 slot (4096-tick granularity), and the implementation fires level-2 slots directly instead of cascading them, so it fires at the slot boundary, which is early. (Linux's design fires *late* instead, by rounding up, which is safer for timeouts.)
- **L7 defense:** Either cascade into lower levels (verified exact firing), or round the expiry *up* to the slot granularity and document the maximum lateness per level. Never fire early: a protocol timeout that fires early is a correctness bug, while one that fires late is a QoS trade.

---

## 5. Invariants Checklist

- [ ] Lists are intrusive with sentinels; removal self-loops; objects are unlinked before being freed (asserted in debug builds).
- [ ] Timer start and cancel are O(1) (wheel); expiry is exact (cascading) or bounded-late, never early; lateness bound documented per level.
- [ ] Tick comparisons are wrap-safe; tests start near `UINT32_MAX`.
- [ ] Timer callbacks are short, or deferred to a task; they may restart their own timer.
- [ ] State machines are table-driven with explicit entries for every (state, event); state and event are bounds-checked with a fail-safe reset; the table is `const` in flash.
- [ ] FSMs run to completion in one context; ISRs post events through an SPSC ring.

## 6. References

1. G. Varghese, A. Lauck, *Hashed and Hierarchical Timing Wheels: Data Structures for the Efficient Implementation of a Timer Facility*, SOSP 1987.
2. Linux `include/linux/list.h`, `kernel/time/timer.c` (T. Gleixner, *timer: Switch to a non-cascading wheel*, 2016), LWN *Reinventing the timer wheel* (2015).
3. D. Harel, *Statecharts: A Visual Formalism for Complex Systems*, Science of Computer Programming 8, 1987.
4. M. Samek, *Practical UML Statecharts in C/C++*, 2nd ed. (QP/C real-time embedded framework).
5. MISRA C:2012 Rule 16.4 and Directive 4.1.
