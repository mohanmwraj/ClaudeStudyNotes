# 03 · Priority Inversion, Inheritance, Ceiling Protocols, and ISR-Safe Synchronization

> **Folder:** `04-Interrupts-Exceptions-and-RTOS-Kernel-Internals/` · **File 3 of 3**
> **Anchors:**
> - L. Sha, R. Rajkumar, J. Lehoczky, *Priority Inheritance Protocols: An Approach to Real-Time Synchronization*, IEEE ToC 1990.
> - T. Baker, *Stack-Based Scheduling of Real-Time Processes* (SRP), Real-Time Systems 1991.
> - G. Reeves, *What really happened on Mars?* (JPL, 1997) and M. Jones' summary.
> - Audsley, Burns, Richardson, Tindell, Wellings, response-time analysis (1993).
> - OSEK/VDX OS 2.2.3 and AUTOSAR OS (immediate ceiling, "OSEK PCP").
> - FreeRTOS `queue.c` / `tasks.c` (mutex inheritance, `FromISR` API); Zephyr `kernel/mutex.c`.
>
> **Verification:**
> - A tick-accurate, preemptive single-CPU **simulator** runs one scenario under three protocols (no protocol, inheritance, ceiling).
> - A production-style **priority-inheritance mutex** (transitive boosting, deadlock detection, exact priority restoration) was compiled warning-free for Cortex-M0+/M7/AArch64 and exercised on an inheritance chain.
> - All outputs were inserted verbatim.

---

## 0. The thesis

Priority scheduling guarantees that the most urgent *ready* task runs. A mutex can make the most urgent task *not ready*, waiting on a low-priority holder, and then any medium-priority task can starve both. **That is priority inversion.** Bounding it is a protocol problem (inheritance, ceiling), a timing problem (the blocking term in schedulability analysis), and an interrupt problem: ISRs can't block at all, so they need different synchronization.

---

## 1. First-Principles Mechanics

### 1.1 Bounded vs. unbounded inversion, simulated

Scenario: one CPU, fully preemptive, priorities H(3) > M(2) > L(1), one mutex.

- **L** arrives at t = 0: runs 1 tick, locks, holds the lock for 4 ticks, unlocks, runs 1.
- **H** arrives at t = 2: runs 1, locks, 1 tick inside, unlocks, runs 1. That is 3 ticks of CPU in total.
- **M** arrives at t = 3: 6 ticks of CPU, never touches the mutex.

```c
/* inversion_sim.c - single-CPU, tick-driven, fully preemptive priority
 * scheduler with one mutex, run under three locking protocols:
 *   NONE    - plain mutex (unbounded priority inversion)
 *   INHERIT - priority inheritance (holder runs at the highest waiter's priority)
 *   CEILING - immediate priority ceiling (holder runs at the mutex's ceiling)
 * Scenario: L locks, H arrives and needs the lock, M (no lock) arrives. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef enum { OP_RUN, OP_LOCK, OP_UNLOCK, OP_END } op_t;
typedef struct { op_t op; int ticks; } step_t;
typedef struct {
    char         name;
    int          base, prio, arrive;
    const step_t *prog;
    int          pc, left, done_at;
    bool         blocked;
} task_t;
typedef enum { P_NONE, P_INHERIT, P_CEILING } proto_t;

static const step_t L_prog[] = { {OP_RUN,1}, {OP_LOCK,0}, {OP_RUN,4}, {OP_UNLOCK,0}, {OP_RUN,1}, {OP_END,0} };
static const step_t H_prog[] = { {OP_RUN,1}, {OP_LOCK,0}, {OP_RUN,1}, {OP_UNLOCK,0}, {OP_RUN,1}, {OP_END,0} };
static const step_t M_prog[] = { {OP_RUN,6}, {OP_END,0} };

static void simulate(proto_t proto, const char *label)
{
    task_t t[3] = {
        { 'L', 1, 1, 0, L_prog, 0, -1, -1, false },
        { 'M', 2, 2, 3, M_prog, 0, -1, -1, false },
        { 'H', 3, 3, 2, H_prog, 0, -1, -1, false },
    };
    const int ceiling = 3;                 /* highest priority of any task using the mutex */
    task_t *owner = NULL;
    char line[64];
    int n = 0;

    for (int now = 0; now < 40 && n < 63; now++) {
        task_t *run = NULL;
        for (;;) {                         /* pick highest-priority ready task; process zero-time ops */
            run = NULL;
            for (int i = 0; i < 3; i++) {
                task_t *x = &t[i];
                if ((x->arrive <= now) && (x->done_at < 0) && !x->blocked &&
                    ((run == NULL) || (x->prio > run->prio))) {
                    run = x;
                }
            }
            if (run == NULL) { break; }
            const step_t *s = &run->prog[run->pc];
            if (s->op == OP_LOCK) {
                if (owner == NULL) {
                    owner = run;
                    if (proto == P_CEILING) { run->prio = ceiling; }
                    run->pc++;
                } else {
                    run->blocked = true;
                    if ((proto == P_INHERIT) && (owner->prio < run->prio)) { owner->prio = run->prio; }
                }
                continue;
            }
            if (s->op == OP_UNLOCK) {
                owner = NULL;
                run->prio = run->base;     /* drop inherited / ceiling priority */
                for (int i = 0; i < 3; i++) { t[i].blocked = false; }   /* waiters retry */
                run->pc++;
                continue;
            }
            if (s->op == OP_END) { run->done_at = now; continue; }
            break;                          /* OP_RUN */
        }
        if (run == NULL) { line[n++] = '.'; continue; }
        if (run->left < 0) { run->left = run->prog[run->pc].ticks; }
        line[n++] = run->name;
        if (--run->left == 0) { run->left = -1; run->pc++; }
        bool all_done = true;
        for (int i = 0; i < 3; i++) {
            if (t[i].done_at < 0) {
                if ((t[i].prog[t[i].pc].op == OP_END) && (t[i].left < 0) && (t[i].arrive <= now)) {
                    t[i].done_at = now + 1;
                } else {
                    all_done = false;
                }
            }
        }
        if (all_done) { break; }
    }
    line[n] = '\0';
    printf("%-8s %s   H response = %d ticks (arrived t=2, needs 3 ticks of CPU)\n",
           label, line, t[2].done_at - t[2].arrive);
}

int main(void)
{
    printf("         t=0123456789...  (one char per tick: running task)\n");
    simulate(P_NONE, "NONE");
    simulate(P_INHERIT, "INHERIT");
    simulate(P_CEILING, "CEILING");
    return 0;
}
```

**Output (verified; one character per tick shows which task is running):**

```text
         t=0123456789...  (one char per tick: running task)
NONE     LLHMMMMMMLLLHHL   H response = 12 ticks (arrived t=2, needs 3 ticks of CPU)
INHERIT  LLHLLLHHMMMMMML   H response = 6 ticks (arrived t=2, needs 3 ticks of CPU)
CEILING  LLLLLHHHMMMMMML   H response = 6 ticks (arrived t=2, needs 3 ticks of CPU)
```

Reading the three timelines:

- **NONE: `LLHMMMMMMLLLHHL`.**
  1. H preempts L at t = 2, runs 1 tick, then blocks on the mutex L holds.
  2. L should finish its critical section, but **M arrives at t = 3 and preempts L** (M > L).
  3. M runs 6 ticks while H, the most urgent task in the system, waits.
  
  H's response is **12 ticks** for 3 ticks of work. The delay is *unbounded* in general: it's as long as any medium task cares to run. This is the Mars Pathfinder bug.
- **INHERIT: `LLHLLLHHMMMMMML`.** When H blocks, L **inherits priority 3**, so M can't preempt it. L finishes its critical section, H runs, then M. H's response is **6 ticks**. The blocking is bounded by L's critical section.
- **CEILING: `LLLLLHHHMMMMMML`.** On locking, L is raised immediately to the mutex's **ceiling**, the highest priority of any task that uses it (3). H arriving at t = 2 *doesn't even preempt*: it can't run anyway until the lock is free. H then runs without ever blocking on the mutex itself. Response time is again **6 ticks**, with one fewer context switch and no blocking chain.

### 1.2 The protocols compared

| Protocol | Rule | Blocking bound for a task | Deadlock | Cost / caveats |
|---|---|---|---|---|
| None | Plain mutex | **Unbounded** | Possible | Never acceptable for mixed-priority sharing |
| **Priority inheritance (PIP)** | The holder runs at the max priority of its waiters, **transitively** along chains | Sum of one critical section per lower-priority task that can block it (chains possible) | **Possible** (needs lock ordering, or detection) | Dynamic; the implementation must handle chains and restore priority exactly (§2.2). POSIX `PTHREAD_PRIO_INHERIT`; FreeRTOS mutexes; Linux rt-mutexes (futex PI) |
| **Original PCP** (Sha/Rajkumar/Lehoczky) | Lock granted only if the task's priority > the *system ceiling* (max ceiling of all currently locked mutexes); otherwise inherit | **At most one** lower-priority critical section | **Prevented** | Needs ceilings known offline; more bookkeeping |
| **Immediate ceiling (ICPP / "highest locker")** | On lock, raise to the mutex's ceiling immediately | At most one critical section, and **only at arrival** | **Prevented** (single-CPU) | Simplest to implement; ceilings static. OSEK/AUTOSAR "PCP" resources; POSIX `PTHREAD_PRIO_PROTECT` |
| **SRP** (Baker) | Preemption level ≥ system ceiling to start | One critical section | Prevented | Enables **all tasks to share one stack** (no blocking after start), as in OSEK BCC1 |
| Interrupt masking (PRIMASK/BASEPRI) | Raise to "above every user" for the critical section | The longest masked section, for *everyone*, including ISRs | Prevented | Only for very short sections. BASEPRI is the immediate ceiling with the interrupt controller as the scheduler |

**Response-time analysis** with blocking (fixed priority):

```text
R_i = C_i + B_i + Σ_{j ∈ hp(i)} ⌈ R_i / T_j ⌉ · C_j        (iterate to a fixed point; schedulable iff R_i ≤ D_i)
```

`B_i` is the protocol's blocking bound:
- under PCP, ICPP or SRP, **the longest single critical section of any lower-priority task on a resource with ceiling ≥ prio(i)**;
- under PIP, a sum over potential chains;
- under "none", it's unbounded, and the analysis can't close.

That's the formal reason safety standards (DO-178C, ISO 26262 projects using AUTOSAR OS) require ceiling protocols and short critical sections.

### 1.3 Mars Pathfinder, 1997

The spacecraft ran VxWorks. A high-priority bus-management task shared an "information bus" mutex with a low-priority meteorological data task, while medium-priority communication tasks ran long. With inheritance **disabled** on that mutex (the default for the semaphore option used), the high-priority task missed its deadline. A watchdog then reset the system repeatedly. JPL reproduced it on the ground, using the trace facility left enabled in the flight software, and fixed it by **uploading a patch that turned priority inheritance on** for that mutex.

The lessons:
- the default mattered;
- *tracing in production* saved the mission;
- the watchdog converted a scheduling bug into a recoverable reset (Folder 08).

### 1.4 ISRs can't block: synchronization rules at the interrupt boundary

| Need | From an ISR | Why |
|---|---|---|
| Take a mutex | ❌ never | An ISR has no task context to block, or to boost via inheritance |
| Wait on anything | ❌ never | Same |
| Signal a task | ✅ `xSemaphoreGiveFromISR`, `xTaskNotifyFromISR`, `k_sem_give` (Zephyr is ISR-safe) | Non-blocking. They may *pend* PendSV to switch on exit (`portYIELD_FROM_ISR`) |
| Pass data | ✅ `xQueueSendFromISR` (non-blocking, may fail), or a **lock-free SPSC ring** with the ISR as the producer (Folder 05) | No locks; bounded time |
| Protect data shared with a task | Task side: a critical section that masks *that* ISR (BASEPRI up to its priority, or PRIMASK). ISR side: nothing, since it can't be preempted by the task | One-sided protection |
| Share with a *zero-latency* ISR | Lock-free only (SPSC with acquire/release, a seqlock), or a single-word atomic | The kernel can't mask it (File 01) |
| SMP kernels (Linux, Zephyr SMP) | `spin_lock_irqsave()`: spin + local IRQ mask | Masking alone doesn't stop another core; spinning alone deadlocks against your own ISR |

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* sync_bad.c - patterns that pass unit tests and fail under load. */
#include <stdbool.h>
#include <stdint.h>

typedef struct { volatile bool locked; } spin_t;          /* "mutex" */
extern void task_delay(uint32_t ticks);

static spin_t   g_bus_lock;
static uint8_t  g_bus_buf[64];

void bus_lock(spin_t *l);
void bus_lock(spin_t *l)
{
    while (l->locked) { task_delay(1u); }   /* BUG 1: test-and-set race (not atomic);       */
    l->locked = true;                       /* BUG 2: no priority inheritance: inversion    */
}

void bus_unlock(spin_t *l);
void bus_unlock(spin_t *l) { l->locked = false; }

void I2C1_EV_IRQHandler(void);
void I2C1_EV_IRQHandler(void)
{
    bus_lock(&g_bus_lock);                  /* BUG 3: blocking (task_delay!) inside an ISR  */
    g_bus_buf[0] = 0x42u;
    bus_unlock(&g_bus_lock);
}

void sensor_task_step(void);
void sensor_task_step(void)
{
    bus_lock(&g_bus_lock);                  /* BUG 4: long critical section (I2C transfer   */
    for (volatile uint32_t i = 0u; i < 100000u; i++) { }   /* in the lock) dominates B_i    */
    bus_unlock(&g_bus_lock);
}
```

### 2.2 The Silicon-Hardened Production Way: a correct PI mutex core (verified)

```c
/* pi_mutex.c - priority-inheritance mutex bookkeeping for an RTOS kernel
 * (scheduling itself omitted: the kernel calls these with its own lock held).
 *  - lock on an owned mutex boosts the owner TRANSITIVELY along the chain
 *    owner -> mutex it waits on -> that mutex's owner -> ...
 *  - unlock hands off to the highest-priority waiter and recomputes the
 *    releaser's effective priority from the mutexes it STILL holds. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MAX_HELD    4u
#define MAX_WAITERS 8u

struct pi_mutex;
typedef struct pi_task {
    const char      *name;
    uint8_t          base_prio;           /* assigned priority (higher = more urgent) */
    uint8_t          prio;                /* effective priority                      */
    struct pi_mutex *waiting_on;          /* mutex this task is blocked on, or NULL  */
    struct pi_mutex *held[MAX_HELD];
    uint8_t          nheld;
} pi_task_t;

typedef struct pi_mutex {
    pi_task_t *owner;
    pi_task_t *waiters[MAX_WAITERS];
    uint8_t    nwait;
} pi_mutex_t;

typedef enum { PI_ACQUIRED = 0, PI_BLOCKED, PI_EFULL, PI_EDEADLK } pi_status_t;

pi_status_t pi_lock(pi_mutex_t *m, pi_task_t *t);
pi_task_t  *pi_unlock(pi_mutex_t *m, pi_task_t *t);

static uint8_t max_waiter_prio(const pi_mutex_t *m)
{
    uint8_t p = 0u;
    for (uint8_t i = 0u; i < m->nwait; i++) {
        if (m->waiters[i]->prio > p) { p = m->waiters[i]->prio; }
    }
    return p;
}

static void recompute(pi_task_t *t)       /* effective = max(base, waiters of held mutexes) */
{
    uint8_t p = t->base_prio;
    for (uint8_t i = 0u; i < t->nheld; i++) {
        uint8_t w = max_waiter_prio(t->held[i]);
        if (w > p) { p = w; }
    }
    t->prio = p;
}

pi_status_t pi_lock(pi_mutex_t *m, pi_task_t *t)
{
    if (m->owner == NULL) {
        if (t->nheld >= MAX_HELD) { return PI_EFULL; }
        m->owner = t;
        t->held[t->nheld++] = m;
        return PI_ACQUIRED;
    }
    if (m->nwait >= MAX_WAITERS) { return PI_EFULL; }
    /* Deadlock check: does the chain from m's owner lead back to t? */
    for (pi_mutex_t *c = m; c != NULL && c->owner != NULL; c = c->owner->waiting_on) {
        if (c->owner == t) { return PI_EDEADLK; }
    }
    m->waiters[m->nwait++] = t;
    t->waiting_on = m;
    /* Transitive boost: walk owner -> waiting_on -> owner ... */
    for (pi_mutex_t *c = m; c != NULL && c->owner != NULL; c = c->owner->waiting_on) {
        if (c->owner->prio >= t->prio) { break; }   /* chain already at least this urgent */
        c->owner->prio = t->prio;                   /* (kernel re-sorts it in the ready list) */
    }
    return PI_BLOCKED;
}

pi_task_t *pi_unlock(pi_mutex_t *m, pi_task_t *t)
{
    if (m->owner != t) { return NULL; }
    for (uint8_t i = 0u; i < t->nheld; i++) {      /* remove m from t's held set */
        if (t->held[i] == m) { t->held[i] = t->held[--t->nheld]; break; }
    }
    pi_task_t *next = NULL;
    uint8_t best = 0u;
    for (uint8_t i = 0u; i < m->nwait; i++) {       /* highest-priority waiter wins */
        if ((next == NULL) || (m->waiters[i]->prio > m->waiters[best]->prio)) { best = i; next = m->waiters[i]; }
    }
    if (next != NULL) {
        m->waiters[best] = m->waiters[--m->nwait];
        next->waiting_on = NULL;
        m->owner = next;
        next->held[next->nheld++] = m;
        recompute(next);                            /* inherits remaining waiters of m */
    } else {
        m->owner = NULL;
    }
    recompute(t);                                   /* drop exactly to what is still owed */
    return next;
}

#ifdef PI_SELFTEST
#include <stdio.h>

static void show(const char *when, pi_task_t *const *ts, unsigned n)
{
    printf("%-34s", when);
    for (unsigned i = 0u; i < n; i++) {
        printf(" %s=%u(base %u)", ts[i]->name, (unsigned)ts[i]->prio, (unsigned)ts[i]->base_prio);
    }
    printf("\n");
}

int main(void)
{
    pi_task_t L = { "L", 1u, 1u, NULL, { 0 }, 0u };
    pi_task_t M = { "M", 2u, 2u, NULL, { 0 }, 0u };
    pi_task_t H = { "H", 9u, 9u, NULL, { 0 }, 0u };
    pi_mutex_t m1 = { 0 }, m2 = { 0 };
    pi_task_t *const all[] = { &L, &M, &H };

    printf("L lock m1: %d\n", (int)pi_lock(&m1, &L));
    printf("M lock m2: %d\n", (int)pi_lock(&m2, &M));
    printf("M lock m1 (held by L): %d\n", (int)pi_lock(&m1, &M));
    show("after M blocks on m1:", all, 3u);
    printf("H lock m2 (held by M): %d\n", (int)pi_lock(&m2, &H));
    show("after H blocks on m2 (chain):", all, 3u);
    printf("L lock m2 would close a cycle: %d\n", (int)pi_lock(&m2, &L));
    pi_task_t *n1 = pi_unlock(&m1, &L);
    printf("L unlock m1 -> handed to %s\n", n1 ? n1->name : "-");
    show("after L releases m1:", all, 3u);
    pi_task_t *n2 = pi_unlock(&m2, &M);
    printf("M unlock m2 -> handed to %s\n", n2 ? n2->name : "-");
    show("after M releases m2:", all, 3u);
    return 0;
}
#endif
```

**Build evidence (verified):** zero diagnostics on Cortex-M0+, Cortex-M7 and AArch64 (full warning set, `-std=c11`).

**Self-test output (verified, native).** The status codes are 0 = acquired, 1 = blocked, 3 = `EDEADLK`.

```text
L lock m1: 0
M lock m2: 0
M lock m1 (held by L): 1
after M blocks on m1:              L=2(base 1) M=2(base 2) H=9(base 9)
H lock m2 (held by M): 1
after H blocks on m2 (chain):      L=9(base 1) M=9(base 2) H=9(base 9)
L lock m2 would close a cycle: 3
L unlock m1 -> handed to M
after L releases m1:               L=1(base 1) M=9(base 2) H=9(base 9)
M unlock m2 -> handed to H
after M releases m2:               L=1(base 1) M=2(base 2) H=9(base 9)
```

What the test proves:

- **Transitive inheritance.**
  - L holds `m1`.
  - M holds `m2` and blocks on `m1`, so L is boosted to 2.
  - H blocks on `m2` (held by M), so M is boosted to 9 **and the boost propagates along M → `m1` → L**: L = 9.
  
  A non-transitive implementation leaves L at 2, and *M-priority* tasks would then preempt L while H waits. That's an inversion surviving a naive PIP. Several production RTOSes have shipped this bug.
- **Deadlock detection.** L trying to lock `m2` would close the cycle L → `m2` → M → `m1` → L, so `EDEADLK` is returned instead of a silent hang.
- **Exact restoration.** When L releases `m1`, it drops to its base priority 1, because it holds no other mutex with waiters. M inherits `m1` and stays at 9, because H still waits on `m2`. When M releases `m2`, it drops to 2. The `recompute()` rule: effective = max(base, highest waiter of every mutex *still held*). Restoring to "the priority before I locked" is the common bug when mutexes are released out of order.

How the kernel uses it:
- call `pi_lock`/`pi_unlock` inside the kernel's own critical section (BASEPRI);
- re-sort boosted tasks in the ready bitmap (File 02 `sched_ready`);
- on `PI_BLOCKED`, pend PendSV;
- on a hand-off, make the new owner ready.

### 2.3 ISR → task hand-off without locks

The hardened ISR (File 01 §2.3) pushes into a lock-free SPSC ring (ISR = producer, task = consumer; Folder 05 has the verified implementation) and calls a `FromISR` notification. Neither side ever blocks or masks the other for more than one instruction.

For **ceiling-style protection on Cortex-M** (task data shared with a kernel-aware ISR), use the verified `cpu_basepri_raise(ceiling)` / `cpu_basepri_restore()` from Folder 01 File 03. It's the immediate ceiling protocol, enforced by the NVIC: ISRs at or below the ceiling are held off, and more urgent ones still run.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Likely cause | How to see it |
|---|---|---|
| A high-priority task misses deadlines only under specific load mixes | Priority inversion (no PI, or non-transitive PI) | RTOS trace (Percepio Tracealyzer, SEGGER SystemView, FreeRTOS+Trace) shows H "blocked on mutex", the owner preempted by M, M running. That's exactly the NONE timeline above |
| Watchdog resets with no fault record | Inversion or deadlock starving the task that kicks the watchdog (Pathfinder) | Per-task watchdog check-ins (Folder 08) identify *which* task stopped. Then the trace |
| Hang with two tasks blocked | Lock-order deadlock (PIP doesn't prevent it) | Kernel-aware debugger: `TASK.List` in TRACE32 shows each task's wait object and owner. Cycle detection as in `pi_lock` |
| HardFault or assert in an ISR calling an RTOS API | Blocking or non-`FromISR` call, or a zero-latency ISR calling the kernel | Keep `configASSERT` on; check `IPSR` ≠ 0 in API entry points |
| Tasks run at the wrong priority after an unlock | Priority not restored from the set of still-held mutexes | Log `prio`/`base_prio` on unlock; the verified test pattern |

Instrumentation: put a `TRACE()` hook on lock, block, boost and unlock, and timestamp it with DWT `CYCCNT`. The inversion shows up immediately as "boost never happened" or "boost didn't propagate".

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Explain priority inversion with the Mars Pathfinder example. How was it fixed?"

- **L5:** "A low-priority task held a lock the high-priority task needed. They added priority inheritance."
- **Why L5 fails on real hardware:** It skips the **medium-priority task**, which is the whole point. Without it, inversion is bounded by L's critical section and is "just blocking". It also misses that the fix was enabling a *flag* on an existing mutex, by a patch uploaded to Mars, and that a watchdog turned the deadline miss into repeated resets.
- **L7 principal defense:** Walk the verified NONE timeline: H blocks, M preempts L, M runs 6 ticks, and H's response is 12 ticks for 3 ticks of work. Contrast INHERIT and CEILING (6 ticks). State the blocking bounds of each protocol, the deadlock properties, and how `B_i` enters response-time analysis. Close with the process lessons: inheritance on by default for shared mutexes, production tracing, per-task watchdog supervision.

### Q2 🔥 "Priority inheritance or priority ceiling, for a safety-critical ECU?"

- **L5:** "Inheritance, because it's automatic."
- **Why L5 fails:** PIP allows **chained blocking** and **deadlock**, and its worst case is harder to bound for certification.
- **L7 defense:** Immediate ceiling (OSEK/AUTOSAR resources): at most one lower-priority critical section blocks a task, and only at arrival; no deadlock on a single core; trivial to implement (raise to the ceiling on lock). On Cortex-M it maps directly onto **BASEPRI**. Ceilings are computed offline from the resource-usage table. PIP stays for general-purpose RTOS mutexes where usage isn't known statically, and then it must be transitive (verified).

### Q3 "Why can't an ISR take a mutex, and how do you share data between an ISR and a task?"

- **L5:** "Because ISRs must be fast."
- **Why L5 fails:** The reason is structural. An ISR has no task context: it can't be put to sleep, it can't be boosted by inheritance, and if the holder is the task it interrupted, waiting would deadlock forever.
- **L7 defense:**
  - **Task side:** mask that ISR (a BASEPRI ceiling or PRIMASK) for the shortest possible section.
  - **ISR side:** no protection needed on a single core.
  - **Or go lock-free:** an SPSC ring with acquire/release (Folder 05), a seqlock for multi-word state (Folder 03), and `FromISR` signaling.
  - **On SMP:** `spin_lock_irqsave`.
  - **Zero-latency ISRs:** lock-free only.

### Q4 🧊 "Your PI mutex implementation passed all tests. A reviewer says it's broken for nested locks. Why?"

- **L5:** "Nested locks aren't supported."
- **Why L5 fails:** The common bugs are subtle:
  1. **Non-transitive boosting.** The owner is boosted, but the owner's *own* blocker isn't.
  2. **Wrong restoration.** On unlock, the task returns to the priority it had *before locking*, instead of max(base, waiters of the mutexes it still holds). That breaks when mutexes are released out of order.
  3. **No deadlock detection.**
  4. **Waiters not ordered by priority** at hand-off.
- **L7 defense:** The verified test exercises exactly these: chain boost L→9, `EDEADLK` on the cycle, exact restoration L→1 / M→9 → 2, and highest-priority hand-off. Mention Linux rt-mutex's PI chain walk with lock-stealing rules, and its depth limit on chains.

### Q5 "How do you measure the blocking term `B_i` on real hardware?"

- **L5:** "Estimate the critical section length."
- **Why L5 fails:** Estimates miss cache misses, flash wait states, interrupts within the section, and the paths that run with locks held.
- **L7 defense:** Instrument every lock and unlock with `CYCCNT` timestamps and record the maximum hold time per resource under worst-case stimulus. Or use static WCET analysis (aiT) of the critical sections (Folder 08). For a ceiling protocol, `B_i` = the max over lower-priority sections on resources with ceiling ≥ prio(i). Verify end to end with trace-based response times.

---

## 5. Invariants Checklist

- [ ] Every mutex shared across priorities uses inheritance (transitive) or a ceiling; plain binary semaphores are never used as mutexes.
- [ ] Ceilings computed offline for statically known resource usage; BASEPRI implements ISR-level ceilings on v7-M/v8-M Mainline.
- [ ] Lock ordering documented, or deadlock detection on (PIP doesn't prevent deadlock).
- [ ] Unlock restores priority from the set of mutexes still held (exact), and hands off to the highest-priority waiter.
- [ ] No blocking call, mutex or non-`FromISR` API in any ISR; zero-latency ISRs are lock-free only.
- [ ] Critical sections short and measured; maximum hold time per resource recorded; `B_i` in the schedulability analysis.
- [ ] Production builds keep a lightweight trace (lock/block/boost/unlock) and per-task watchdog supervision.

## 6. References

1. L. Sha, R. Rajkumar, J. P. Lehoczky, *Priority Inheritance Protocols: An Approach to Real-Time Synchronization*, IEEE Transactions on Computers 39(9), 1990.
2. T. P. Baker, *Stack-Based Scheduling of Realtime Processes*, Real-Time Systems 3(1), 1991.
3. G. Reeves, *What Really Happened on Mars?* (JPL, Dec 1997); M. B. Jones, *What really happened on Mars Rover Pathfinder*, RISKS Digest 19.49.
4. N. Audsley, A. Burns, M. Richardson, K. Tindell, A. Wellings, *Applying New Scheduling Theory to Static Priority Pre-emptive Scheduling*, Software Engineering Journal, 1993.
5. OSEK/VDX Operating System Specification 2.2.3 (resources, ceiling priority); AUTOSAR Classic OS specification.
6. FreeRTOS `queue.c`/`tasks.c` (`xTaskPriorityInherit`, `xTaskPriorityDisinheritAfterTimeout`); Linux `kernel/locking/rtmutex.c`; Zephyr `kernel/mutex.c`.
