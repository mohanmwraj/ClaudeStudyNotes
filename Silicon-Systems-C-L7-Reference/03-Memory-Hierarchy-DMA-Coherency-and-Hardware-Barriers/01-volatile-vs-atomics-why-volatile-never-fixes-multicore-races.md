# 01 · `volatile` vs. Atomics: Why `volatile` Never Fixes Multi-Core Races

> **Folder:** `03-Memory-Hierarchy-DMA-Coherency-and-Hardware-Barriers/` · **File 1 of 3**
> **Anchors:**
> - ISO/IEC 9899 C11/C17: §5.1.2.3 (volatile accesses as observable behavior), §5.1.2.4 (data races, happens-before), §6.7.3p7 (volatile), §7.17 (`<stdatomic.h>`), §7.14.1.1p5 (`volatile sig_atomic_t`).
> - Linux `Documentation/process/volatile-considered-harmful.rst` and `Documentation/memory-barriers.txt`.
> - P. McKenney, *Is Parallel Programming Hard…* (perfbook) ch. 15 and appendix C (store buffers, invalidate queues).
> - ARMv7-M ARM §A3.4 (single-copy atomicity, exclusives); Arm ARM DDI 0487 B2.2 (single-copy atomicity) and B2.3 (ordering).
> - H.-J. Boehm, *Can Seqlocks Get Along with Programming Language Memory Models?* (MSPC 2012).
>
> **Verification:**
> - Codegen for every C11 memory order on six targets (Clang 21.1.0) was compiled and inserted verbatim.
> - The 64-bit atomics probe and ARMv6-M helper library were compiled and linked.
> - Lost updates, store-buffering and message-passing litmus tests, a seqlock stress test, and false sharing were **measured with real threads on the author's x86-64 Windows 11 laptop**. Each is one measured run; counts vary by machine and run.

---

## 0. The thesis

`volatile` is a contract between **you and the compiler** about the abstract machine: every access happens, at its width, in program order *relative to other volatile accesses*. It says nothing to the **hardware**:

- store buffers, out-of-order load execution, invalidation queues, write buffers and bus interconnects are free to reorder what *other observers* (cores, DMA engines) see;
- it doesn't make a read-modify-write indivisible;
- it doesn't make a 64-bit value on a 32-bit bus single-copy atomic.

`_Atomic` plus a memory order is the contract with *both* the compiler and the hardware. Every claim below is shown in emitted instructions or measured on silicon.

---

## 1. First-Principles Mechanics

### 1.1 What `volatile` actually guarantees

| Guarantee | Source | Holds? |
|---|---|---|
| Each volatile access is performed (not elided, not cached in a register) | §5.1.2.3p6: volatile accesses are observable behavior | ✅ |
| Volatile accesses are not reordered **with respect to each other** by the compiler | Same | ✅ |
| The access uses the declared width (no splitting/merging) | Implementation-defined ("what constitutes an access", §6.7.3p7). GCC and Clang preserve width for naturally aligned scalars | ✅ in practice, for aligned native-width objects |
| Non-volatile accesses stay on the same side of a volatile access | **No.** The compiler may move ordinary loads and stores across volatile ones | ❌ |
| The CPU and interconnect preserve that order **as seen by other cores and DMA** | **No.** `volatile` emits no barrier instructions | ❌ |
| `v++` is indivisible | **No.** It is a load, an add, and a store | ❌ |
| A 64-bit volatile on a 32-bit core is read in one indivisible access | **No** (§1.5, verified) | ❌ |
| Concurrent access by two threads is defined behavior | **No.** It's a data race (§5.1.2.4) unless the object is atomic | ❌ |

### 1.2 The hardware that `volatile` can't see

```text
   Core 0                                  Core 1
 ┌───────────────┐                       ┌───────────────┐
 │ pipeline      │                       │ pipeline      │
 │  OoO loads ───┼──┐                 ┌──┼─── OoO loads  │
 │  store buffer │  │  coherent        │  │  store buffer │
 │  (FIFO or not)│  ▼  interconnect    ▼  │               │
 │   L1D ◄───────┼──►  (MESI/MOESI) ◄──┼──► L1D          │
 │   inval queue │      snoop filter      │  inval queue  │
 └───────────────┘          │             └───────────────┘
                     shared L2/L3, DRAM ◄─── DMA master (often NOT coherent)
```

- **Store buffer.** A store retires into a per-core buffer and drains to L1 later. The core's own later loads see it (store-to-load forwarding), but other cores don't yet. This causes **store→load reordering** even on x86 (TSO). The store-buffering litmus test measures it below.
- **Out-of-order and speculative loads.** A later load can be satisfied before an earlier one. On ARM and RISC-V this produces **load→load** and **load→store** reordering as observed externally.
- **Non-FIFO store draining** to different cache lines (ARM, POWER) produces **store→store** reordering.
- **Invalidation queues** (McKenney) let a core acknowledge an invalidation before applying it, so its later loads can see stale data.
- **DMA masters** see only memory, not caches, unless the interconnect makes them coherent (File 03).

### 1.3 Measured: what `volatile` buys on a real multi-core CPU

`races.c`: every shared access in the litmus parts is `_Atomic` with `memory_order_relaxed`, so the *program* has no undefined behavior, and the *hardware* is still free to reorder. `atomic_signal_fence` pins the compiler. The lost-update part deliberately uses `volatile`.

```c
/* races.c - hardware memory-model experiments on the host CPU (x86-64, TSO).
 * Every shared access is an _Atomic (relaxed where we want the HARDWARE to be
 * free to reorder), so the program itself has no data-race UB; compiler
 * reordering is pinned with atomic_signal_fence. */
#include <stdalign.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <windows.h>

#define ITERS 200000u

/* ---------- 1. lost updates: volatile vs atomic ---------- */
static volatile uint32_t v_counter;
static _Atomic uint32_t a_counter;

static DWORD WINAPI inc_volatile(LPVOID arg) { (void)arg; for (uint32_t i = 0; i < 1000000u; i++) { v_counter++; } return 0; }
static DWORD WINAPI inc_atomic(LPVOID arg)   { (void)arg; for (uint32_t i = 0; i < 1000000u; i++) { atomic_fetch_add_explicit(&a_counter, 1u, memory_order_relaxed); } return 0; }

static void run2(LPTHREAD_START_ROUTINE f, LPTHREAD_START_ROUTINE g, void *a, void *b)
{
    HANDLE t[2] = { CreateThread(NULL, 0, f, a, 0, NULL), CreateThread(NULL, 0, g, b, 0, NULL) };
    WaitForMultipleObjects(2, t, TRUE, INFINITE);
    CloseHandle(t[0]);
    CloseHandle(t[1]);
}

/* ---------- 2/3. litmus tests with a per-iteration rendezvous ---------- */
static alignas(64) _Atomic uint32_t x;
static alignas(64) _Atomic uint32_t y;
static alignas(64) _Atomic uint32_t go[2];
static alignas(64) _Atomic uint32_t done[2];
static uint32_t r0s[ITERS], r1s[ITERS];
static int use_fence;
static int test_kind;           /* 0 = SB (store buffering), 1 = MP (message passing) */

static void wait_go(unsigned me, uint32_t it)
{
    while (atomic_load_explicit(&go[me], memory_order_acquire) != it + 1u) { }
}

static DWORD WINAPI litmus_t0(LPVOID arg)
{
    (void)arg;
    for (uint32_t it = 0; it < ITERS; it++) {
        wait_go(0u, it);
        if (test_kind == 0) {                                   /* SB: x=1; r0=y */
            atomic_store_explicit(&x, 1u, memory_order_relaxed);
            if (use_fence) { atomic_thread_fence(memory_order_seq_cst); }
            else { atomic_signal_fence(memory_order_seq_cst); }
            r0s[it] = atomic_load_explicit(&y, memory_order_relaxed);
        } else {                                                /* MP writer: data=1; flag=1 */
            atomic_store_explicit(&x, 1u, memory_order_relaxed);
            atomic_signal_fence(memory_order_seq_cst);
            atomic_store_explicit(&y, 1u, memory_order_relaxed);
        }
        atomic_store_explicit(&done[0], it + 1u, memory_order_release);
    }
    return 0;
}

static DWORD WINAPI litmus_t1(LPVOID arg)
{
    (void)arg;
    for (uint32_t it = 0; it < ITERS; it++) {
        wait_go(1u, it);
        if (test_kind == 0) {                                   /* SB: y=1; r1=x */
            atomic_store_explicit(&y, 1u, memory_order_relaxed);
            if (use_fence) { atomic_thread_fence(memory_order_seq_cst); }
            else { atomic_signal_fence(memory_order_seq_cst); }
            r1s[it] = atomic_load_explicit(&x, memory_order_relaxed);
        } else {                                                /* MP reader: r0=flag; r1=data */
            r0s[it] = atomic_load_explicit(&y, memory_order_relaxed);
            atomic_signal_fence(memory_order_seq_cst);
            r1s[it] = atomic_load_explicit(&x, memory_order_relaxed);
        }
        atomic_store_explicit(&done[1], it + 1u, memory_order_release);
    }
    return 0;
}

static void litmus(int kind, int fence)
{
    test_kind = kind;
    use_fence = fence;
    atomic_store(&go[0], 0u); atomic_store(&go[1], 0u);
    atomic_store(&done[0], 0u); atomic_store(&done[1], 0u);
    HANDLE t[2] = { CreateThread(NULL, 0, litmus_t0, NULL, 0, NULL),
                    CreateThread(NULL, 0, litmus_t1, NULL, 0, NULL) };
    for (uint32_t it = 0; it < ITERS; it++) {
        atomic_store_explicit(&x, 0u, memory_order_relaxed);
        atomic_store_explicit(&y, 0u, memory_order_relaxed);
        atomic_store_explicit(&go[0], it + 1u, memory_order_release);
        atomic_store_explicit(&go[1], it + 1u, memory_order_release);
        while (atomic_load_explicit(&done[0], memory_order_acquire) != it + 1u ||
               atomic_load_explicit(&done[1], memory_order_acquire) != it + 1u) { }
    }
    WaitForMultipleObjects(2, t, TRUE, INFINITE);
    CloseHandle(t[0]); CloseHandle(t[1]);
    uint32_t hist[4] = { 0, 0, 0, 0 };
    for (uint32_t it = 0; it < ITERS; it++) { hist[(r0s[it] << 1) | r1s[it]]++; }
    if (kind == 0) {
        printf("SB %-22s r0,r1 = 0,0:%7u  0,1:%7u  1,0:%7u  1,1:%7u\n",
               fence ? "with seq_cst fence" : "no fence (relaxed)", (unsigned)hist[0],
               (unsigned)hist[1], (unsigned)hist[2], (unsigned)hist[3]);
    } else {
        printf("MP %-22s flag,data = 0,0:%7u  0,1:%7u  1,0:%7u  1,1:%7u\n",
               "no fence (relaxed)", (unsigned)hist[0], (unsigned)hist[1],
               (unsigned)hist[2], (unsigned)hist[3]);
    }
}

/* ---------- 4. false sharing ---------- */
struct shared_line { volatile uint64_t a; volatile uint64_t b; };
struct padded_line { alignas(64) volatile uint64_t a; alignas(64) volatile uint64_t b; };
static alignas(64) struct shared_line s_same;
static alignas(64) struct padded_line s_pad;
#define FS_ITERS 20000000u
static DWORD WINAPI bump(LPVOID p) { volatile uint64_t *c = p; for (uint32_t i = 0; i < FS_ITERS; i++) { *c = *c + 1u; } return 0; }

static double time_pair(volatile uint64_t *a, volatile uint64_t *b)
{
    LARGE_INTEGER f, t0, t1;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t0);
    run2(bump, bump, (void *)(uintptr_t)a, (void *)(uintptr_t)b);
    QueryPerformanceCounter(&t1);
    return (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)f.QuadPart;
}

int main(void)
{
    run2(inc_volatile, inc_volatile, NULL, NULL);
    run2(inc_atomic, inc_atomic, NULL, NULL);
    printf("2 threads x 1,000,000 increments: volatile=%u (lost %u)  atomic=%u\n",
           (unsigned)v_counter, 2000000u - (unsigned)v_counter, (unsigned)atomic_load(&a_counter));
    litmus(0, 0);
    litmus(0, 1);
    litmus(1, 0);
    printf("false sharing, 2 x %u increments: same line %.1f ms, separate lines %.1f ms\n",
           (unsigned)FS_ITERS, time_pair(&s_same.a, &s_same.b), time_pair(&s_pad.a, &s_pad.b));
    return 0;
}
```

**One measured run (author's x86-64 laptop, Windows 11, 200,000 litmus iterations):**

```text
2 threads x 1,000,000 increments: volatile=1024996 (lost 975004)  atomic=2000000
SB no fence (relaxed)     r0,r1 = 0,0:  94243  0,1:  19153  1,0:  83110  1,1:   3494
SB with seq_cst fence     r0,r1 = 0,0:      0  0,1:  49329  1,0:  43236  1,1: 107435
MP no fence (relaxed)     flag,data = 0,0:  75522  0,1:  54449  1,0:      0  1,1:  70029
false sharing, 2 x 20000000 increments: same line 37.4 ms, separate lines 9.6 ms
```

1. **`volatile` lost 975,004 of 2,000,000 increments.** Two cores each did load, add, store on the same line, and each overwrote the other's work. The relaxed atomic `fetch_add` (`lock xadd`) was exact. `volatile` provides no read-modify-write atomicity at all.
2. **Store buffering (SB): `r0 = r1 = 0` in 94,243 of 200,000 runs.** Under sequential consistency at least one thread must see the other's store. Here both stores sat in their store buffers while both loads read memory. **x86 is "strongly" ordered and still does this.** A `seq_cst` fence (`lock orl $0,-64(%rsp)`, §1.4) drains the buffer, and the outcome count drops to **0**.
3. **Message passing (MP): `flag = 1, data = 0` never occurred.** x86-TSO forbids store→store and load→load reordering. **That is exactly why "volatile flag" code that works on x86 breaks on ARM**, where MP is architecturally allowed without barriers (File 02).
4. **False sharing: 37.4 ms vs 9.6 ms (3.9×).** Same work, but two counters sharing one 64-byte line ping-pong under MESI (File 03).

### 1.4 What each memory order compiles to (verified, six ISAs)

The reference source (every function is a self-contained idiom):

```c
/* orders.c - what each C11 memory order and `volatile` lower to, per ISA. */
#include <stdatomic.h>
#include <stdint.h>

volatile uint32_t v_flag;
volatile uint32_t v_data;
_Atomic uint32_t a_flag;
uint32_t payload;
_Atomic uint32_t a_ctr;
volatile uint32_t v_ctr;

void     mp_volatile_publish(uint32_t x);
uint32_t mp_volatile_consume(void);
void     mp_release_publish(uint32_t x);
uint32_t mp_acquire_consume(void);
uint32_t load_relaxed(void);
uint32_t load_seq_cst(void);
void     store_relaxed(uint32_t x);
void     store_seq_cst(uint32_t x);
void     volatile_inc(void);
uint32_t rmw_relaxed(void);
uint32_t rmw_acq_rel(void);
_Bool    cas_strong(uint32_t *expected, uint32_t desired);
void     fence_acquire(void);
void     fence_release(void);
void     fence_seq_cst(void);
void     fence_signal(void);

/* message passing with volatile: program order for the compiler only */
void mp_volatile_publish(uint32_t x) { v_data = x; v_flag = 1u; }
uint32_t mp_volatile_consume(void) { while (v_flag == 0u) { } return v_data; }

/* message passing with release/acquire */
void mp_release_publish(uint32_t x)
{
    payload = x;
    atomic_store_explicit(&a_flag, 1u, memory_order_release);
}
uint32_t mp_acquire_consume(void)
{
    while (atomic_load_explicit(&a_flag, memory_order_acquire) == 0u) { }
    return payload;
}

uint32_t load_relaxed(void)  { return atomic_load_explicit(&a_flag, memory_order_relaxed); }
uint32_t load_seq_cst(void)  { return atomic_load_explicit(&a_flag, memory_order_seq_cst); }
void store_relaxed(uint32_t x) { atomic_store_explicit(&a_flag, x, memory_order_relaxed); }
void store_seq_cst(uint32_t x) { atomic_store_explicit(&a_flag, x, memory_order_seq_cst); }

/* read-modify-write */
void     volatile_inc(void)   { v_ctr++; }
uint32_t rmw_relaxed(void)    { return atomic_fetch_add_explicit(&a_ctr, 1u, memory_order_relaxed); }
uint32_t rmw_acq_rel(void)    { return atomic_fetch_add_explicit(&a_ctr, 1u, memory_order_acq_rel); }
_Bool    cas_strong(uint32_t *expected, uint32_t desired)
{
    return atomic_compare_exchange_strong_explicit(&a_ctr, expected, desired,
                                                   memory_order_acq_rel, memory_order_acquire);
}

/* fences */
void fence_acquire(void) { atomic_thread_fence(memory_order_acquire); }
void fence_release(void) { atomic_thread_fence(memory_order_release); }
void fence_seq_cst(void) { atomic_thread_fence(memory_order_seq_cst); }
void fence_signal(void)  { atomic_signal_fence(memory_order_seq_cst); }
```

**AArch64, ARMv8.0 (`aarch64-none-elf`; zero diagnostics):**

```asm
mp_volatile_publish:
	adrp	x8, v_data
	adrp	x9, v_flag
	mov	w10, #1
	str	w0, [x8, :lo12:v_data]
	str	w10, [x9, :lo12:v_flag]
	ret
mp_volatile_consume:
	adrp	x8, v_flag
.LBB1_1:
	ldr	w9, [x8, :lo12:v_flag]
	cbz	w9, .LBB1_1
	adrp	x8, v_data
	ldr	w0, [x8, :lo12:v_data]
	ret
mp_release_publish:
	adrp	x8, payload
	mov	w9, #1
	str	w0, [x8, :lo12:payload]
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
	stlr	w9, [x8]
	ret
mp_acquire_consume:
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
.LBB3_1:
	ldar	w9, [x8]
	cbz	w9, .LBB3_1
	adrp	x8, payload
	ldr	w0, [x8, :lo12:payload]
	ret
load_relaxed:
	adrp	x8, a_flag
	ldr	w0, [x8, :lo12:a_flag]
	ret
load_seq_cst:
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
	ldar	w0, [x8]
	ret
store_relaxed:
	adrp	x8, a_flag
	str	w0, [x8, :lo12:a_flag]
	ret
store_seq_cst:
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
	stlr	w0, [x8]
	ret
volatile_inc:
	adrp	x8, v_ctr
	ldr	w9, [x8, :lo12:v_ctr]
	add	w9, w9, #1
	str	w9, [x8, :lo12:v_ctr]
	ret
rmw_relaxed:
	adrp	x8, a_ctr
	add	x8, x8, :lo12:a_ctr
.LBB9_1:
	ldxr	w0, [x8]
	add	w9, w0, #1
	stxr	w10, w9, [x8]
	cbnz	w10, .LBB9_1
	ret
rmw_acq_rel:
	adrp	x8, a_ctr
	add	x8, x8, :lo12:a_ctr
.LBB10_1:
	ldaxr	w0, [x8]
	add	w9, w0, #1
	stlxr	w10, w9, [x8]
	cbnz	w10, .LBB10_1
	ret
cas_strong:
	ldr	w8, [x0]
	adrp	x10, a_ctr
	add	x10, x10, :lo12:a_ctr
.LBB11_1:
	ldaxr	w9, [x10]
	cmp	w9, w8
	b.ne	.LBB11_4
	stlxr	w11, w1, [x10]
	cbnz	w11, .LBB11_1
	mov	w8, #1
	tbz	w8, #0, .LBB11_5
	b	.LBB11_6
.LBB11_4:
	mov	w8, wzr
	clrex
	tbnz	w8, #0, .LBB11_6
.LBB11_5:
	str	w9, [x0]
.LBB11_6:
	mov	w0, w8
	ret
fence_acquire:
	dmb	ishld
	ret
fence_release:
	dmb	ish
	ret
fence_seq_cst:
	dmb	ish
	ret
fence_signal:
	ret
```

**AArch64, ARMv8.4 (`-march=armv8.4-a`: LSE atomics + RCpc):**

```asm
mp_volatile_publish:
	adrp	x8, v_data
	adrp	x9, v_flag
	mov	w10, #1
	str	w0, [x8, :lo12:v_data]
	str	w10, [x9, :lo12:v_flag]
	ret
mp_volatile_consume:
	adrp	x8, v_flag
.LBB1_1:
	ldr	w9, [x8, :lo12:v_flag]
	cbz	w9, .LBB1_1
	adrp	x8, v_data
	ldr	w0, [x8, :lo12:v_data]
	ret
mp_release_publish:
	adrp	x8, payload
	mov	w9, #1
	str	w0, [x8, :lo12:payload]
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
	stlr	w9, [x8]
	ret
mp_acquire_consume:
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
.LBB3_1:
	ldapr	w9, [x8]
	cbz	w9, .LBB3_1
	adrp	x8, payload
	ldr	w0, [x8, :lo12:payload]
	ret
load_relaxed:
	adrp	x8, a_flag
	ldr	w0, [x8, :lo12:a_flag]
	ret
load_seq_cst:
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
	ldar	w0, [x8]
	ret
store_relaxed:
	adrp	x8, a_flag
	str	w0, [x8, :lo12:a_flag]
	ret
store_seq_cst:
	adrp	x8, a_flag
	add	x8, x8, :lo12:a_flag
	stlr	w0, [x8]
	ret
volatile_inc:
	adrp	x8, v_ctr
	ldr	w9, [x8, :lo12:v_ctr]
	add	w9, w9, #1
	str	w9, [x8, :lo12:v_ctr]
	ret
rmw_relaxed:
	mov	w8, #1
	adrp	x9, a_ctr
	add	x9, x9, :lo12:a_ctr
	ldadd	w8, w0, [x9]
	ret
rmw_acq_rel:
	mov	w8, #1
	adrp	x9, a_ctr
	add	x9, x9, :lo12:a_ctr
	ldaddal	w8, w0, [x9]
	ret
cas_strong:
	ldr	w8, [x0]
	adrp	x10, a_ctr
	add	x10, x10, :lo12:a_ctr
	mov	w9, w8
	casal	w9, w1, [x10]
	cmp	w9, w8
	cset	w8, eq
	b.eq	.LBB11_2
	str	w9, [x0]
.LBB11_2:
	mov	w0, w8
	ret
fence_acquire:
	dmb	ishld
	ret
fence_release:
	dmb	ish
	ret
fence_seq_cst:
	dmb	ish
	ret
fence_signal:
	ret
```

**Cortex-M7 (ARMv7E-M; zero diagnostics):**

```asm
mp_volatile_publish:
	movw	r1, :lower16:v_data
	movt	r1, :upper16:v_data
	str	r0, [r1]
	movw	r0, :lower16:v_flag
	movt	r0, :upper16:v_flag
	movs	r1, #1
	str	r1, [r0]
	bx	lr
mp_volatile_consume:
	movw	r0, :lower16:v_flag
	movt	r0, :upper16:v_flag
.LBB1_1:
	ldr	r1, [r0]
	cbnz	r1, .LBB1_4
	ldr	r1, [r0]
	cmp	r1, #0
	itt	eq
	ldreq	r1, [r0]
	cmpeq	r1, #0
	bne	.LBB1_4
	ldr	r1, [r0]
	cmp	r1, #0
	beq	.LBB1_1
.LBB1_4:
	movw	r0, :lower16:v_data
	movt	r0, :upper16:v_data
	ldr	r0, [r0]
	bx	lr
mp_release_publish:
	movw	r1, :lower16:payload
	movt	r1, :upper16:payload
	str	r0, [r1]
	movw	r0, :lower16:a_flag
	dmb	sy
	movt	r0, :upper16:a_flag
	movs	r1, #1
	str	r1, [r0]
	bx	lr
mp_acquire_consume:
	movw	r0, :lower16:a_flag
	movt	r0, :upper16:a_flag
.LBB3_1:
	ldr	r1, [r0]
	dmb	sy
	cbnz	r1, .LBB3_4
	ldr	r1, [r0]
	dmb	sy
	cmp	r1, #0
	ittt	eq
	ldreq	r1, [r0]
	dmbeq	sy
	cmpeq	r1, #0
	bne	.LBB3_4
	ldr	r1, [r0]
	dmb	sy
	cmp	r1, #0
	beq	.LBB3_1
.LBB3_4:
	movw	r0, :lower16:payload
	movt	r0, :upper16:payload
	ldr	r0, [r0]
	bx	lr
load_relaxed:
	movw	r0, :lower16:a_flag
	movt	r0, :upper16:a_flag
	ldr	r0, [r0]
	bx	lr
load_seq_cst:
	movw	r0, :lower16:a_flag
	movt	r0, :upper16:a_flag
	ldr	r0, [r0]
	dmb	sy
	bx	lr
store_relaxed:
	movw	r1, :lower16:a_flag
	movt	r1, :upper16:a_flag
	str	r0, [r1]
	bx	lr
store_seq_cst:
	movw	r1, :lower16:a_flag
	movt	r1, :upper16:a_flag
	dmb	sy
	str	r0, [r1]
	dmb	sy
	bx	lr
volatile_inc:
	movw	r0, :lower16:v_ctr
	movt	r0, :upper16:v_ctr
	ldr	r1, [r0]
	adds	r1, #1
	str	r1, [r0]
	bx	lr
rmw_relaxed:
	movw	r1, :lower16:a_ctr
	movt	r1, :upper16:a_ctr
.LBB9_1:
	ldrex	r0, [r1]
	adds	r2, r0, #1
	strex	r3, r2, [r1]
	cmp	r3, #0
	bne	.LBB9_1
	bx	lr
rmw_acq_rel:
	dmb	sy
	movw	r1, :lower16:a_ctr
	movt	r1, :upper16:a_ctr
.LBB10_1:
	ldrex	r0, [r1]
	adds	r2, r0, #1
	strex	r3, r2, [r1]
	cmp	r3, #0
	bne	.LBB10_1
	dmb	sy
	bx	lr
cas_strong:
	push	{r7, lr}
	movw	r12, :lower16:a_ctr
	ldr.w	lr, [r0]
	movt	r12, :upper16:a_ctr
	ldrex	r2, [r12]
	cmp	r2, lr
	bne	.LBB11_4
	dmb	sy
.LBB11_2:
	strex	r3, r1, [r12]
	cbz	r3, .LBB11_5
	ldrex	r2, [r12]
	cmp	r2, lr
	beq	.LBB11_2
.LBB11_4:
	clrex
	movs	r1, #0
	b	.LBB11_6
.LBB11_5:
	movs	r1, #1
.LBB11_6:
	dmb	sy
	cmp	r1, #0
	it	eq
	streq	r2, [r0]
	mov	r0, r1
	pop	{r7, pc}
fence_acquire:
	dmb	sy
	bx	lr
fence_release:
	dmb	sy
	bx	lr
fence_seq_cst:
	dmb	sy
	bx	lr
fence_signal:
	bx	lr
```

**x86-64 (`x86_64-unknown-elf`; zero diagnostics):**

```asm
mp_volatile_publish:
	movl	%edi, v_data(%rip)
	movl	$1, v_flag(%rip)
	retq
mp_volatile_consume:
.LBB1_1:
	cmpl	$0, v_flag(%rip)
	je	.LBB1_1
	movl	v_data(%rip), %eax
	retq
mp_release_publish:
	movl	%edi, payload(%rip)
	movl	$1, a_flag(%rip)
	retq
mp_acquire_consume:
.LBB3_1:
	movl	a_flag(%rip), %eax
	testl	%eax, %eax
	je	.LBB3_1
	movl	payload(%rip), %eax
	retq
load_relaxed:
	movl	a_flag(%rip), %eax
	retq
load_seq_cst:
	movl	a_flag(%rip), %eax
	retq
store_relaxed:
	movl	%edi, a_flag(%rip)
	retq
store_seq_cst:
	xchgl	%edi, a_flag(%rip)
	retq
volatile_inc:
	incl	v_ctr(%rip)
	retq
rmw_relaxed:
	movl	$1, %eax
	lock		xaddl	%eax, a_ctr(%rip)
	retq
rmw_acq_rel:
	movl	$1, %eax
	lock		xaddl	%eax, a_ctr(%rip)
	retq
cas_strong:
	movl	(%rdi), %eax
	lock		cmpxchgl	%esi, a_ctr(%rip)
	sete	%cl
	je	.LBB11_2
	movl	%eax, (%rdi)
.LBB11_2:
	movl	%ecx, %eax
	retq
fence_acquire:
	retq
fence_release:
	retq
fence_seq_cst:
	lock		orl	$0, -64(%rsp)
	retq
fence_signal:
	retq
```

**RISC-V RV64GC (`riscv64-unknown-elf`; zero diagnostics):**

```asm
mp_volatile_publish:
.Lpcrel_hi0:
	auipc	a1, %pcrel_hi(.L_MergedGlobals)
	addi	a1, a1, %pcrel_lo(.Lpcrel_hi0)
	sw	a0, 0(a1)
	li	a0, 1
	sw	a0, 4(a1)
	ret
mp_volatile_consume:
.Lpcrel_hi1:
	auipc	a0, %pcrel_hi(.L_MergedGlobals)
	addi	a0, a0, %pcrel_lo(.Lpcrel_hi1)
.LBB1_1:
	lw	a1, 4(a0)
	beqz	a1, .LBB1_1
	lw	a0, 0(a0)
	ret
mp_release_publish:
.Lpcrel_hi2:
	auipc	a1, %pcrel_hi(.L_MergedGlobals)
	addi	a1, a1, %pcrel_lo(.Lpcrel_hi2)
	sw	a0, 8(a1)
	li	a0, 1
	fence	rw, w
	sw	a0, 12(a1)
	ret
mp_acquire_consume:
.Lpcrel_hi3:
	auipc	a0, %pcrel_hi(.L_MergedGlobals)
	addi	a0, a0, %pcrel_lo(.Lpcrel_hi3)
.LBB3_1:
	lw	a1, 12(a0)
	fence	r, rw
	beqz	a1, .LBB3_1
	lw	a0, 8(a0)
	ret
load_relaxed:
.Lpcrel_hi4:
	auipc	a0, %pcrel_hi(.L_MergedGlobals+12)
	lw	a0, %pcrel_lo(.Lpcrel_hi4)(a0)
	ret
load_seq_cst:
	fence	rw, rw
.Lpcrel_hi5:
	auipc	a0, %pcrel_hi(.L_MergedGlobals+12)
	lw	a0, %pcrel_lo(.Lpcrel_hi5)(a0)
	fence	r, rw
	ret
store_relaxed:
.Lpcrel_hi6:
	auipc	a1, %pcrel_hi(.L_MergedGlobals+12)
	sw	a0, %pcrel_lo(.Lpcrel_hi6)(a1)
	ret
store_seq_cst:
	fence	rw, w
.Lpcrel_hi7:
	auipc	a1, %pcrel_hi(.L_MergedGlobals+12)
	sw	a0, %pcrel_lo(.Lpcrel_hi7)(a1)
	fence	rw, rw
	ret
volatile_inc:
.Lpcrel_hi8:
	auipc	a0, %pcrel_hi(v_ctr)
	lw	a1, %pcrel_lo(.Lpcrel_hi8)(a0)
	addi	a1, a1, 1
	sw	a1, %pcrel_lo(.Lpcrel_hi8)(a0)
	ret
rmw_relaxed:
.Lpcrel_hi9:
	auipc	a0, %pcrel_hi(a_ctr)
	addi	a0, a0, %pcrel_lo(.Lpcrel_hi9)
	li	a1, 1
	amoadd.w	a0, a1, (a0)
	ret
rmw_acq_rel:
.Lpcrel_hi10:
	auipc	a0, %pcrel_hi(a_ctr)
	addi	a0, a0, %pcrel_lo(.Lpcrel_hi10)
	li	a1, 1
	amoadd.w.aqrl	a0, a1, (a0)
	ret
cas_strong:
	lw	a3, 0(a0)
.Lpcrel_hi11:
	auipc	a2, %pcrel_hi(a_ctr)
	addi	a4, a2, %pcrel_lo(.Lpcrel_hi11)
.LBB11_3:
	lr.w.aq	a2, (a4)
	bne	a2, a3, .LBB11_5
	sc.w.rl	a5, a1, (a4)
	bnez	a5, .LBB11_3
.LBB11_5:
	xor	a1, a2, a3
	seqz	a1, a1
	beq	a2, a3, .LBB11_2
	sw	a2, 0(a0)
.LBB11_2:
	mv	a0, a1
	ret
fence_acquire:
	fence	r, rw
	ret
fence_release:
	fence	rw, w
	ret
fence_seq_cst:
	fence	rw, rw
	ret
fence_signal:
	ret
```

**Cortex-M0+ (ARMv6-M), built with `-Wno-atomic-alignment`. Without that flag the strict build *fails* with:**

```text
orders.c:37:5: error: large atomic operation may incur significant performance penalty; the access size (4 bytes) exceeds the max lock-free size (0 bytes) [-Werror,-Watomic-alignment]
```

```asm
mp_volatile_publish:
	ldr	r1, .LCPI0_0
	str	r0, [r1]
	ldr	r0, .LCPI0_1
	movs	r1, #1
	str	r1, [r0]
	bx	lr
.LCPI0_0:
	.long	v_data
.LCPI0_1:
	.long	v_flag
mp_volatile_consume:
	ldr	r0, .LCPI1_0
.LBB1_1:
	ldr	r1, [r0]
	cmp	r1, #0
	bne	.LBB1_5
	ldr	r1, [r0]
	cmp	r1, #0
	bne	.LBB1_5
	ldr	r1, [r0]
	cmp	r1, #0
	bne	.LBB1_5
	ldr	r1, [r0]
	cmp	r1, #0
	beq	.LBB1_1
.LBB1_5:
	ldr	r0, .LCPI1_1
	ldr	r0, [r0]
	bx	lr
.LCPI1_0:
	.long	v_flag
.LCPI1_1:
	.long	v_data
mp_release_publish:
	push	{r7, lr}
	ldr	r1, .LCPI2_0
	str	r0, [r1]
	ldr	r0, .LCPI2_1
	movs	r1, #1
	movs	r2, #3
	bl	__atomic_store_4
	pop	{r7, pc}
.LCPI2_0:
	.long	payload
.LCPI2_1:
	.long	a_flag
mp_acquire_consume:
	push	{r4, lr}
	ldr	r4, .LCPI3_0
.LBB3_1:
	movs	r1, #2
	mov	r0, r4
	bl	__atomic_load_4
	cmp	r0, #0
	bne	.LBB3_5
	movs	r1, #2
	mov	r0, r4
	bl	__atomic_load_4
	cmp	r0, #0
	bne	.LBB3_5
	movs	r1, #2
	mov	r0, r4
	bl	__atomic_load_4
	cmp	r0, #0
	bne	.LBB3_5
	movs	r1, #2
	mov	r0, r4
	bl	__atomic_load_4
	cmp	r0, #0
	beq	.LBB3_1
.LBB3_5:
	ldr	r0, .LCPI3_1
	ldr	r0, [r0]
	pop	{r4, pc}
.LCPI3_0:
	.long	a_flag
.LCPI3_1:
	.long	payload
load_relaxed:
	push	{r7, lr}
	ldr	r0, .LCPI4_0
	movs	r1, #0
	bl	__atomic_load_4
	pop	{r7, pc}
.LCPI4_0:
	.long	a_flag
load_seq_cst:
	push	{r7, lr}
	ldr	r0, .LCPI5_0
	movs	r1, #5
	bl	__atomic_load_4
	pop	{r7, pc}
.LCPI5_0:
	.long	a_flag
store_relaxed:
	push	{r7, lr}
	mov	r1, r0
	ldr	r0, .LCPI6_0
	movs	r2, #0
	bl	__atomic_store_4
	pop	{r7, pc}
.LCPI6_0:
	.long	a_flag
store_seq_cst:
	push	{r7, lr}
	mov	r1, r0
	ldr	r0, .LCPI7_0
	movs	r2, #5
	bl	__atomic_store_4
	pop	{r7, pc}
.LCPI7_0:
	.long	a_flag
volatile_inc:
	ldr	r0, .LCPI8_0
	ldr	r1, [r0]
	adds	r1, r1, #1
	str	r1, [r0]
	bx	lr
.LCPI8_0:
	.long	v_ctr
rmw_relaxed:
	push	{r7, lr}
	ldr	r0, .LCPI9_0
	movs	r1, #1
	movs	r2, #0
	bl	__atomic_fetch_add_4
	pop	{r7, pc}
.LCPI9_0:
	.long	a_ctr
rmw_acq_rel:
	push	{r7, lr}
	ldr	r0, .LCPI10_0
	movs	r1, #1
	movs	r2, #4
	bl	__atomic_fetch_add_4
	pop	{r7, pc}
.LCPI10_0:
	.long	a_ctr
cas_strong:
	push	{r4, lr}
	sub	sp, #8
	mov	r2, r1
	mov	r4, r0
	ldr	r0, [r0]
	str	r0, [sp, #4]
	movs	r0, #2
	str	r0, [sp]
	ldr	r0, .LCPI11_0
	add	r1, sp, #4
	movs	r3, #4
	bl	__atomic_compare_exchange_4
	cmp	r0, #0
	bne	.LBB11_2
	ldr	r1, [sp, #4]
	str	r1, [r4]
.LBB11_2:
	add	sp, #8
	pop	{r4, pc}
.LCPI11_0:
	.long	a_ctr
fence_acquire:
	dmb	sy
	bx	lr
fence_release:
	dmb	sy
	bx	lr
fence_seq_cst:
	dmb	sy
	bx	lr
fence_signal:
	bx	lr
```

The matrix, distilled (every cell is from the listings above):

| C11 operation | AArch64 v8.0 | AArch64 v8.4 | Cortex-M7 | Cortex-M0+ | x86-64 | RV64 |
|---|---|---|---|---|---|---|
| `volatile` store, store (MP publish) | `str; str` (no barrier) | same | `str; str` | `str; str` | `mov; mov` | `sw; sw` |
| load `relaxed` | `ldr` | `ldr` | `ldr` | `bl __atomic_load_4` | `mov` | `lw` |
| load `acquire` | `ldar` | **`ldapr`** (RCpc) | `ldr; dmb sy` | `bl __atomic_load_4` | `mov` | `lw; fence r,rw` |
| load `seq_cst` | `ldar` | `ldar` | `ldr; dmb sy` | `bl __atomic_load_4` | `mov` | `fence rw,rw; lw; fence r,rw` |
| store `release` | `stlr` | `stlr` | `dmb sy; str` | `bl __atomic_store_4` | `mov` | `fence rw,w; sw` |
| store `seq_cst` | `stlr` | `stlr` | `dmb sy; str; dmb sy` | `bl __atomic_store_4` | **`xchg`** | `fence rw,w; sw; fence rw,rw` |
| `v++` on `volatile` | `ldr; add; str` | same | `ldr; adds; str` | `ldr; adds; str` | `incl mem` (**not** `lock`) | `lw; addi; sw` |
| `fetch_add` relaxed | `ldxr/stxr` loop | **`ldadd`** | `ldrex/strex` loop | `bl __atomic_fetch_add_4` | `lock xadd` | `amoadd.w` |
| `fetch_add` acq_rel | `ldaxr/stlxr` loop | **`ldaddal`** | `dmb; ldrex/strex; dmb` | `bl __atomic_fetch_add_4` | `lock xadd` | `amoadd.w.aqrl` |
| CAS strong acq_rel | `ldaxr/cmp/stlxr` + `clrex` on failure | **`casal`** | `ldrex/strex` + `clrex` + `dmb` | `bl __atomic_compare_exchange_4` | `lock cmpxchg` | `lr.w.aq/sc.w.rl` |
| fence acquire | `dmb ishld` | `dmb ishld` | `dmb sy` | `dmb sy` | *(none)* | `fence r,rw` |
| fence release | `dmb ish` | `dmb ish` | `dmb sy` | `dmb sy` | *(none)* | `fence rw,w` |
| fence seq_cst | `dmb ish` | `dmb ish` | `dmb sy` | `dmb sy` | `lock orl $0,-64(%rsp)` | `fence rw,rw` |
| `atomic_signal_fence` | *(none)* | *(none)* | *(none)* | *(none)* | *(none)* | *(none)* |

Things to notice:

- **The volatile MP publish has no barrier on any ISA.** On AArch64, Cortex-M7 and RISC-V, an observer may see `v_flag = 1` before `v_data`.
- **x86 needs almost nothing.** Acquire and release are plain `mov`s; only `seq_cst` stores and fences pay. That's why x86-tested lock-free code is a poor predictor of ARM correctness.
- **On x86, `volatile_inc` is one instruction (`incl v_ctr(%rip)`) and still not atomic.** Without the `lock` prefix, the read and the write are separate cache transactions (the measured 975,004 lost updates).
- **LSE (ARMv8.1+) replaces LL/SC loops with single instructions** (`ldadd`, `ldaddal`, `casal`). They scale much better under contention, because the interconnect can perform *far atomics* at the home node instead of bouncing the line. `-march`/`-mcpu` decides which one you get, and a binary built for v8.0 never uses LSE unless it is built with outline atomics (`-moutline-atomics`, the GCC 10+ default on aarch64 Linux; ⚠ verify defaults).
- **RCpc acquire (`ldapr`) is weaker than `ldar`.** It doesn't wait for earlier `stlr`s to other addresses, which is exactly the C11 acquire semantics. Clang uses it for `acquire` and keeps `ldar` for `seq_cst`.
- **Cortex-M uses `dmb sy`**, because the inner-shareable domain qualifiers are meaningless on M-profile. A failed `strex`/CAS path executes **`clrex`**, so a stale exclusive reservation can't let a later unrelated `strex` succeed (Folder 05).
- **`atomic_signal_fence` emits nothing on every ISA.** It's a compiler-only barrier, the C11 spelling of `asm volatile("" ::: "memory")`.

### 1.5 Width and lock-freedom: the 32-bit core trap

```c
/* wide.c - 64-bit shared variables on 32-bit cores. */
#include <stdatomic.h>
#include <stdint.h>

volatile uint64_t v_stamp;
_Atomic uint64_t a_stamp;

uint64_t read_volatile64(void);
uint64_t read_volatile64(void) { return v_stamp; }
uint64_t read_atomic64(void);
uint64_t read_atomic64(void)   { return atomic_load_explicit(&a_stamp, memory_order_acquire); }

const int k_llong_lock_free = ATOMIC_LLONG_LOCK_FREE;   /* 0 never, 1 sometimes, 2 always */
const int k_int_lock_free   = ATOMIC_INT_LOCK_FREE;
```

**Codegen (verified — Clang 21.1.0, `-O2`; Cortex-M7, Cortex-M0+, AArch64; the constants are the `ATOMIC_*_LOCK_FREE` values, where 0 means never, 1 sometimes, 2 always):**

```asm
== m7
read_volatile64:
	movw	r0, :lower16:v_stamp
	movt	r0, :upper16:v_stamp
	ldrd	r0, r1, [r0]
	bx	lr
read_atomic64:
	push	{r7, lr}
	movw	r0, :lower16:a_stamp
	movs	r1, #2
	movt	r0, :upper16:a_stamp
	bl	__atomic_load_8
	pop	{r7, pc}
v_stamp:
	.long	0
	.long	0
a_stamp:
	.long	0
	.long	0
k_llong_lock_free:
	.long	1
k_int_lock_free:
	.long	2
== m0
read_volatile64:
	ldr	r0, .LCPI0_0
	ldr	r1, [r0, #4]
	ldr	r0, [r0]
	bx	lr
.LCPI0_0:
	.long	v_stamp
read_atomic64:
	push	{r7, lr}
	ldr	r0, .LCPI1_0
	movs	r1, #2
	bl	__atomic_load_8
	pop	{r7, pc}
.LCPI1_0:
	.long	a_stamp
v_stamp:
	.long	0
	.long	0
a_stamp:
	.long	0
	.long	0
k_llong_lock_free:
	.long	1
k_int_lock_free:
	.long	1
== a64e
read_volatile64:
	adrp	x8, v_stamp
	ldr	x0, [x8, :lo12:v_stamp]
	ret
read_atomic64:
	adrp	x8, a_stamp
	add	x8, x8, :lo12:a_stamp
	ldar	x0, [x8]
	ret
v_stamp:
	.xword	0
a_stamp:
	.xword	0
k_llong_lock_free:
	.word	2
k_int_lock_free:
	.word	2
```

- **Cortex-M7:** `volatile uint64_t` is a single **`ldrd`**, which is *two* 32-bit bus transactions. Another bus master (DMA, a second core in a multi-core MCU) can update the value between them, and the read is torn. ARMv7-M has `LDREX`/`STREX` for 8/16/32 bits but **no `LDREXD`**, so `_Atomic uint64_t` is a **library call** (`__atomic_load_8`) and `ATOMIC_LLONG_LOCK_FREE` is 1 ("sometimes"). `ATOMIC_INT_LOCK_FREE` is 2.
- **Cortex-M0+:** two separate `ldr`s, **high word first** (`[r0, #4]` then `[r0]`). An ISR that updates the value between them produces a mixture of old high and new low. A 64-bit tick counter updated by SysTick wraps "backwards" by 2^32 for one read. ARMv6-M reports `ATOMIC_INT_LOCK_FREE = 1`, and the M0+ matrix above shows *every* atomic, even 32-bit, as a library call.
- **AArch64:** a single `ldr x0` or `ldar x0`, which is single-copy atomic for aligned 64-bit.

**The fix on 32-bit cores is a seqlock** (§2.2). Single-writer, wait-free for the writer, lock-free retry for readers: measured 0 torn reads in 604,536, against 1,291 for the naive two-half read.

**Who provides `__atomic_*_4` on Cortex-M0+?** The toolchain's libatomic or compiler-rt (often lock-based with a global spinlock, which is useless or deadlock-prone in an ISR on a single core), or **you**. The verified single-core implementation in §2.3 uses PRIMASK.

### 1.6 MMIO: where `volatile` is necessary but not sufficient

For a peripheral register, `volatile` is mandatory: without it, the compiler deletes, merges and reorders the accesses (Folder 01, File 02). But ordering *between* Normal memory (a DMA descriptor in RAM) and Device memory (a doorbell register) needs a barrier. Cortex-M7 and AArch64 both allow a Normal-memory store to become visible to the DMA engine *after* a later Device store reached the peripheral. File 02 shows the verified `publish_desc` sequence: `str` fields → `dmb oshst` → `str` OWN → `dmb oshst` → `str` doorbell. That is Linux's `dma_wmb()` and `writel()`.

Linux's position (`volatile-considered-harmful.rst`): kernel code doesn't use `volatile` variables for shared data. It uses locks, atomics, `READ_ONCE`/`WRITE_ONCE` (volatile *accesses* that prevent tearing and compiler merging), and explicit barriers. MMIO goes through `readl`/`writel`, which carry the right barriers per architecture.

### 1.7 Single-core ISR ↔ thread: when `volatile` *is* enough

On a **single-core** Cortex-M, an interrupt observes the interrupted thread's memory accesses in program order, because the core sees its own accesses in order. So, for a flag or value of native width (≤ 32 bits) and natural alignment, written by exactly one side:

- `volatile` (or a relaxed `_Atomic`) is sufficient for the flag itself;
- the *payload* it guards must be ordered by the compiler: a `"memory"` clobber or `atomic_signal_fence` between the payload write and the flag write;
- `volatile sig_atomic_t` is the ISO C analogue for signal handlers (§7.14.1.1p5).

It stops being enough when:
- a second core exists (dual-core M7+M4 parts, or an M33 plus a DSP);
- a **DMA engine** reads the payload (it doesn't see the CPU's order of cache writebacks: File 03);
- the value is wider than 32 bits (§1.5);
- the update is a read-modify-write from both sides (use a critical section or exclusives).

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way

```c
/* shared_bad.c - each pattern passes testing on x86 and on a single-core
 * bench setup, and fails on multi-core ARM or with DMA observers. */
#include <stdint.h>

volatile uint32_t g_ready;          /* "volatile makes it thread-safe"            */
uint32_t          g_payload[16];
volatile uint32_t g_events;         /* incremented by an ISR AND by a thread      */
volatile uint64_t g_uptime_us;      /* written by a timer ISR, read by tasks      */

void producer(const uint32_t *src);
void producer(const uint32_t *src)
{
    for (unsigned i = 0u; i < 16u; i++) { g_payload[i] = src[i]; }
    g_ready = 1u;                   /* BUG 1: no release ordering (compiler AND hardware) */
}

uint32_t consumer(void);
uint32_t consumer(void)
{
    while (g_ready == 0u) { }       /* BUG 2: no acquire: payload loads may be satisfied early */
    return g_payload[0];
}

void count_event(void);
void count_event(void) { g_events++; } /* BUG 3: RMW from two contexts: lost updates (measured) */

uint64_t uptime(void);
uint64_t uptime(void) { return g_uptime_us; } /* BUG 4: torn on 32-bit cores (ldrd / 2x ldr) */
```

Bug 1 is visible in the verified `mp_volatile_publish` listings: plain `str; str` on every ISA, so the compiler may even sink the payload stores past the flag. Bug 3 is the measured 975,004 lost updates. Bug 4 is the verified `ldrd` on M7 and the high-word-first `ldr` pair on M0+.

### 2.2 The Silicon-Hardened Production Way: release/acquire + seqlock

Release/acquire message passing is `mp_release_publish` / `mp_acquire_consume` in the verified matrix:
- AArch64: `stlr` / `ldar`, or `ldapr` with RCpc;
- Cortex-M7: `dmb sy; str` / `ldr; dmb sy`;
- RISC-V: `fence rw,w` / `fence r,rw`.

For 64-bit values on 32-bit cores, use the seqlock:

`seqlock64.h`:

```c
/* seqlock64.h - single-writer 64-bit value readable from any context without
 * locks, on cores where 64-bit atomics are NOT lock-free (Cortex-M: no
 * LDREXD on v7-M, no exclusives at all on v6-M). The writer must be a single
 * context (one ISR, or one thread); readers retry instead of blocking. */
#ifndef SEQLOCK64_H
#define SEQLOCK64_H

#include <stdatomic.h>
#include <stdint.h>

typedef struct {
    _Atomic uint32_t seq;        /* odd while a write is in progress */
    _Atomic uint32_t lo;
    _Atomic uint32_t hi;
} seqlock64_t;

static inline void seqlock64_write(seqlock64_t *s, uint64_t v)
{
    uint32_t q = atomic_load_explicit(&s->seq, memory_order_relaxed);
    atomic_store_explicit(&s->seq, q + 1u, memory_order_relaxed);      /* -> odd  */
    atomic_thread_fence(memory_order_release);                         /* seq before data */
    atomic_store_explicit(&s->lo, (uint32_t)v, memory_order_relaxed);
    atomic_store_explicit(&s->hi, (uint32_t)(v >> 32), memory_order_relaxed);
    atomic_store_explicit(&s->seq, q + 2u, memory_order_release);      /* data before even seq */
}

static inline uint64_t seqlock64_read(seqlock64_t *s)
{
    for (;;) {
        uint32_t q1 = atomic_load_explicit(&s->seq, memory_order_acquire);
        uint32_t lo = atomic_load_explicit(&s->lo, memory_order_relaxed);
        uint32_t hi = atomic_load_explicit(&s->hi, memory_order_relaxed);
        atomic_thread_fence(memory_order_acquire);                     /* data before re-check */
        uint32_t q2 = atomic_load_explicit(&s->seq, memory_order_relaxed);
        if (((q1 & 1u) == 0u) && (q1 == q2)) {
            return ((uint64_t)hi << 32) | lo;
        }
    }
}

#endif /* SEQLOCK64_H */
```

A test translation unit for embedded targets:

```c
#include "seqlock64.h"
uint64_t rd(seqlock64_t *s);
uint64_t rd(seqlock64_t *s) { return seqlock64_read(s); }
void wr(seqlock64_t *s, uint64_t v);
void wr(seqlock64_t *s, uint64_t v) { seqlock64_write(s, v); }
```

**Build evidence (verified):** zero diagnostics on Cortex-M7, Cortex-M33, AArch64 and RV64.

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M7):**

```asm
rd:
.LBB0_1:
	ldr	r3, [r0]
	dmb	sy
	ldr.w	r12, [r0, #4]
	ldr	r1, [r0, #8]
	dmb	sy
	lsls	r2, r3, #31
	ldr	r2, [r0]
	bne	.LBB0_3
	cmp	r3, r2
	beq	.LBB0_9
.LBB0_3:
	ldr	r3, [r0]
	dmb	sy
	ldr.w	r12, [r0, #4]
	ldr	r1, [r0, #8]
	dmb	sy
	lsls	r2, r3, #31
	ldr	r2, [r0]
	bne	.LBB0_5
	cmp	r3, r2
	beq	.LBB0_9
.LBB0_5:
	ldr	r3, [r0]
	dmb	sy
	ldr.w	r12, [r0, #4]
	ldr	r1, [r0, #8]
	dmb	sy
	lsls	r2, r3, #31
	ldr	r2, [r0]
	bne	.LBB0_7
	cmp	r3, r2
	beq	.LBB0_9
.LBB0_7:
	ldr	r3, [r0]
	dmb	sy
	ldr.w	r12, [r0, #4]
	ldr	r1, [r0, #8]
	dmb	sy
	lsls	r2, r3, #31
	ldr	r2, [r0]
	bne	.LBB0_1
	cmp	r3, r2
	bne	.LBB0_1
.LBB0_9:
	mov	r0, r12
	bx	lr
wr:
	ldr.w	r12, [r0]
	add.w	r1, r12, #1
	str	r1, [r0]
	dmb	sy
	str	r2, [r0, #4]
	add.w	r1, r12, #2
	str	r3, [r0, #8]
	dmb	sy
	str	r1, [r0]
	bx	lr
```

The writer is: `seq+1` (odd) → `dmb sy` → `lo`, `hi` → `dmb sy` → `seq+2` (even). The reader is: `seq` → `dmb` → `lo`, `hi` → `dmb` → `seq` again, retrying while odd or changed. The compiler unrolled the retry loop four times.

The host stress test:

```c
/* seqlock_test.c - writer publishes v = (n << 32) | n; readers check hi == lo.
 * Compares the seqlock with a naive "read two halves" reader. */
#include <stdio.h>
#include <windows.h>

#include "seqlock64.h"

#define WRITES 3000000u
static seqlock64_t g_s;
static _Atomic int g_stop;
static _Atomic uint32_t naive_lo, naive_hi;

static DWORD WINAPI writer(LPVOID arg)
{
    (void)arg;
    for (uint32_t n = 1u; n <= WRITES; n++) {
        seqlock64_write(&g_s, ((uint64_t)n << 32) | n);
        atomic_store_explicit(&naive_lo, n, memory_order_relaxed);
        atomic_store_explicit(&naive_hi, n, memory_order_relaxed);
    }
    atomic_store(&g_stop, 1);
    return 0;
}

static DWORD WINAPI reader(LPVOID arg)
{
    uint32_t *res = arg;           /* [0]=reads [1]=seqlock torn [2]=naive torn */
    while (!atomic_load(&g_stop)) {
        uint64_t v = seqlock64_read(&g_s);
        res[1] += ((uint32_t)(v >> 32) != (uint32_t)v);
        uint32_t lo = atomic_load_explicit(&naive_lo, memory_order_relaxed);
        uint32_t hi = atomic_load_explicit(&naive_hi, memory_order_relaxed);
        res[2] += (lo != hi);
        res[0]++;
    }
    return 0;
}

int main(void)
{
    static uint32_t res[3];
    HANDLE t[2] = { CreateThread(NULL, 0, writer, NULL, 0, NULL),
                    CreateThread(NULL, 0, reader, res, 0, NULL) };
    WaitForMultipleObjects(2, t, TRUE, INFINITE);
    printf("reads=%u  seqlock torn=%u  naive two-half torn=%u\n",
           (unsigned)res[0], (unsigned)res[1], (unsigned)res[2]);
    return 0;
}
```

**One measured run (x86-64, 3,000,000 writes, concurrent reader):**

```text
reads=604536  seqlock torn=0  naive two-half torn=1291
```

Rules for the seqlock: exactly **one writer context**. If an ISR is the writer, nothing else may write. If both a task and an ISR write, the task's write must mask that ISR. Readers must tolerate retrying, so a reader must never be an ISR that *preempts the writer* on the same core: it would spin forever on an odd sequence number. In that configuration, read with interrupts masked instead.

### 2.3 Lock-free where possible, honest where not: ARMv6-M atomic helpers

```c
/* atomic_v6m.c - the sized __atomic_* helpers the compiler calls on ARMv6-M
 * (Cortex-M0/M0+/M1), which has no LDREX/STREX. SINGLE-CORE ONLY: atomicity
 * comes from masking interrupts (PRIMASK), which does nothing against a second
 * core or a DMA master. Signatures follow the GCC/LLVM libatomic ABI. */
#include <stdbool.h>
#include <stdint.h>

static inline uint32_t irq_save(void)
{
    uint32_t m;
    __asm__ volatile("mrs %0, primask\n\tcpsid i" : "=r"(m) : : "memory");
    return m;
}
static inline void irq_restore(uint32_t m)
{
    __asm__ volatile("msr primask, %0" : : "r"(m) : "memory");
}

uint32_t __atomic_load_4(const volatile void *mem, int model);
void     __atomic_store_4(volatile void *mem, uint32_t val, int model);
uint32_t __atomic_fetch_add_4(volatile void *mem, uint32_t val, int model);
bool     __atomic_compare_exchange_4(volatile void *mem, void *expected, uint32_t desired,
                                     int success, int failure);

/* Aligned 32-bit loads/stores are already single-copy atomic on v6-M; the
 * "memory" clobbers in irq_save/restore provide the compiler ordering. */
uint32_t __atomic_load_4(const volatile void *mem, int model)
{
    (void)model;
    return *(const volatile uint32_t *)mem;
}

void __atomic_store_4(volatile void *mem, uint32_t val, int model)
{
    (void)model;
    *(volatile uint32_t *)mem = val;
}

uint32_t __atomic_fetch_add_4(volatile void *mem, uint32_t val, int model)
{
    (void)model;
    uint32_t key = irq_save();
    volatile uint32_t *p = mem;
    uint32_t old = *p;
    *p = old + val;
    irq_restore(key);
    return old;
}

bool __atomic_compare_exchange_4(volatile void *mem, void *expected, uint32_t desired,
                                 int success, int failure)
{
    (void)success; (void)failure;
    uint32_t key = irq_save();
    volatile uint32_t *p = mem;
    uint32_t *e = expected;
    uint32_t cur = *p;
    bool ok = (cur == *e);
    if (ok) {
        *p = desired;
    } else {
        *e = cur;
    }
    irq_restore(key);
    return ok;
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, Cortex-M0+):**

```asm
__atomic_load_4:
	ldr	r0, [r0]
	bx	lr
__atomic_store_4:
	str	r1, [r0]
	bx	lr
__atomic_fetch_add_4:
	mrs	r3, primask
	cpsid i
	ldr	r2, [r0]
	adds	r1, r2, r1
	str	r1, [r0]
	msr	primask, r3
	mov	r0, r2
	bx	lr
__atomic_compare_exchange_4:
	push	{r4, r5, r7, lr}
	mrs	r4, primask
	cpsid i
	ldr	r3, [r0]
	ldr	r5, [r1]
	cmp	r3, r5
	bne	.LBB3_2
	str	r2, [r0]
	b	.LBB3_3
.LBB3_2:
	str	r3, [r1]
.LBB3_3:
	msr	primask, r4
	subs	r1, r3, r5
	rsbs	r0, r1, #0
	adcs	r0, r1
	pop	{r4, r5, r7, pc}
```

**Link evidence (verified):** `orders.c` (all C11 operations) plus `atomic_v6m.c` links for Cortex-M0+ with no undefined symbols.

This is correct **only on a single core**, which is the honest limit of PRIMASK. On multi-core v6-M systems (e.g. RP2040's dual Cortex-M0+), atomicity across cores needs the hardware spinlocks or the SIO block (⚠ verify for your SoC), not PRIMASK.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

| Symptom | Likely cause | How to prove it |
|---|---|---|
| Counter slowly drifts low under load | Non-atomic RMW from two contexts | Count events at the source (a GPIO toggle per event on a logic analyzer) vs the counter. The verified lost-update numbers show the scale |
| Consumer occasionally sees stale payload with a valid flag, only on Cortex-A/multi-core | Missing release/acquire (MP) | Run a **litmus7** test on the target (herdtools7 generates C litmus harnesses that run on real ARM hardware). Code review: find a flag written without `stlr`/`dmb` |
| Uptime or timestamp jumps by ±2^32 µs for one sample | Torn 64-bit read on a 32-bit core | Log both halves. Disassemble the reader: `ldrd` or two `ldr`s |
| Works on x86 CI, fails on ARM boards | TSO hides MP/LB reordering (verified MP count 0 on x86) | Run CI on ARM64 runners; use TSan on the host for data races |
| Deadlock in an M0+ ISR calling an atomic | Lock-based libatomic (global spinlock) entered from an ISR that interrupted a holder | Check the link map for `__atomic_*` and their implementation; provide the PRIMASK helpers |
| DMA engine reads an old descriptor although the CPU wrote it before ringing the doorbell | Normal-store vs Device-store ordering (needs `dmb`), or cache not cleaned (File 03) | Trace32/ETM data trace shows the store order. Bus analyzer on AXI shows the doorbell write arriving first |

Tools:
- **ThreadSanitizer** (`-fsanitize=thread`) on host builds of shared logic.
- **KCSAN** in Linux kernels (data-race detector).
- **herd7** to evaluate a litmus test against the formal ARMv8/RISC-V/LKMM models: "is this outcome allowed?".
- **litmus7** to run the same test on hardware: "does this silicon exhibit it?".
- Lauterbach `Trace.List` with data trace (ETM/ETB) to see the actual order of loads and stores from one core.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Why doesn't `volatile` make a flag safe between two cores?"

- **L5:** "`volatile` stops the compiler caching the variable in a register, so the other core sees the update."
- **Why L5 fails on multi-core ARM/DMA hardware:** That's the *only* thing it does. Its gaps:
  - It doesn't order the **payload** relative to the flag. The compiler may move non-volatile stores, and the verified listings emit plain `str; str` on every ISA.
  - It doesn't stop the hardware reordering the stores (ARM, RISC-V) or the loads.
  - On ARM the MP outcome "flag seen, data stale" is architecturally allowed. On x86 it's forbidden, which is why it "works" in CI (verified MP count 0 on x86).
  - It provides no RMW atomicity (verified: 975,004 lost updates).
  - And it's a data race, so undefined behavior in C11.
- **L7 principal defense:** `_Atomic` flag with `memory_order_release` on publish and `memory_order_acquire` on consume. That lowers to `stlr`/`ldar` (or `ldapr`) on AArch64, `dmb sy` + `str` / `ldr` + `dmb sy` on M7, and `fence rw,w`/`fence r,rw` on RISC-V (verified matrix). Keep `volatile` only for MMIO and the single-core ISR flag case (§1.7). Validate with herd7 and litmus7 on target, and TSan on the host.

### Q2 🔥 "What does `volatile_inc` compile to on x86-64, and why isn't one instruction atomic?"

- **L5:** "`incl` is a single instruction, so it's atomic."
- **Why L5 fails:** Single *instruction* ≠ single *bus transaction*. A non-`lock` `incl mem` reads the line, increments, and writes it back as separate steps. Another core's RFO can intervene. Only the `lock` prefix (verified `lock xadd` for `fetch_add`) holds the line exclusively for the whole RMW.
- **L7 defense:** Atomic RMW instructions per ISA: `lock xadd`/`cmpxchg`, `ldadd` (LSE) or `ldxr`/`stxr`, `amoadd`, and on v6-M a critical section. Use the C11 operations rather than hand-coding them, and measure contention (LSE vs LL/SC scaling) if it's hot.

### Q3 🔥 "Your SysTick ISR maintains a 64-bit microsecond counter on a Cortex-M4. Tasks read it. What breaks?"

- **L5:** "Nothing, it's `volatile`."
- **Why L5 fails:** The 64-bit read is `ldrd` (M3/M4/M7) or two `ldr` (M0+, verified high word first). The ISR can run between the two halves, causing a 2^32 jump on wrap. `_Atomic uint64_t` is a library call on v7-M (no `LDREXD`, verified `__atomic_load_8`, `ATOMIC_LLONG_LOCK_FREE = 1`).
- **L7 defense:** A seqlock (verified: 0 torn reads vs 1,291 naive), or read hi-lo-hi and retry if hi changed (valid for a monotonic counter whose low word wraps), or briefly mask SysTick. If it's needed in an ISR that can preempt the writer, mask, since spinning is impossible there. On AArch64, a plain aligned 64-bit atomic is lock-free.

### Q4 "When IS `volatile` the right tool?"

- **L5:** "Never use it." Or: "For all shared variables."
- **Why L5 fails:** Both extremes are wrong.
- **L7 defense:**
  1. MMIO registers. Mandatory, with barriers where Normal/Device ordering matters.
  2. Variables changed by a **single-core** ISR and read by the thread it interrupts, when native-width, aligned and single-writer, with a compiler barrier (`atomic_signal_fence`) ordering the payload.
  3. `setjmp`/`longjmp` locals.
  4. Forcing a real access in a benchmark or startup copy loop (Folder 02 crt0: volatile copy loops defeat idiom recognition).

  Everything that crosses cores, or that DMA observes, uses atomics, barriers and cache maintenance.

### Q5 🧊 "Why does C11 `acquire` compile to `ldapr` on newer ARM cores but `seq_cst` to `ldar`?"

- **L5:** "They're the same thing."
- **Why L5 fails:** `LDAR` is RCsc: it can't be reordered before an earlier `STLR` to *any* address, which C11 `seq_cst` needs. C11 `acquire` doesn't need that. `LDAPR` (FEAT_LRCPC, Armv8.3) is RCpc and lets the load pass earlier releases to other addresses, which is cheaper. The verified v8.4 listing uses `ldapr` for acquire and `ldar` for `seq_cst`.
- **L7 defense:** Use the weakest order that is correct. Know that the performance difference appears in tight message-passing loops on big cores. Know that `-march` determines availability, and that the code must not assume LSE or RCpc unless the deployed fleet guarantees them, or use outline atomics or ifuncs.

### Q6 "How do atomics work on a Cortex-M0+?"

- **L5:** "Use `LDREX`/`STREX`."
- **Why L5 fails:** ARMv6-M has no exclusives. Every C11 atomic becomes a `__atomic_*` library call (verified, along with the `max lock-free size (0 bytes)` diagnostic).
- **L7 defense:** Provide single-core PRIMASK helpers (verified listing and link), or design around them: single-writer, aligned 32-bit loads and stores are already single-copy atomic. For dual-core M0+ parts, use the SoC's hardware spinlocks or mailbox. Keep critical sections short, because PRIMASK masking adds latency to every interrupt.

---

## 5. Invariants Checklist

- [ ] No `volatile` variable is used as an inter-core or DMA synchronization mechanism; use `_Atomic` + release/acquire, or locks.
- [ ] MMIO accessed only through `volatile` pointers *and* the platform's barrier discipline (`readl`/`writel`, `dmb` between descriptor and doorbell).
- [ ] Every RMW shared between contexts is a C11 atomic RMW or inside a critical section.
- [ ] No `uint64_t` shared variable on a 32-bit core without a seqlock or critical section; `ATOMIC_LLONG_LOCK_FREE` checked per target.
- [ ] On ARMv6-M, the `__atomic_*` implementation is known (PRIMASK or SoC spinlock), never an ISR-unsafe global lock.
- [ ] Single-core ISR/thread flags: native width, aligned, single writer, compiler barrier for the payload.
- [ ] CI runs shared-state code on ARM64 hardware (x86 hides reorderings), plus TSan on the host and herd7/litmus7 for the protocols.

## 6. References

1. ISO/IEC 9899:2011 §5.1.2.4, §6.7.3, §7.17; WG21/WG14 memory model papers (Boehm & Adve, *Foundations of the C++ Concurrency Memory Model*, PLDI 2008).
2. P. E. McKenney, *Is Parallel Programming Hard, And, If So, What Can You Do About It?*, ch. 15 *Advanced Synchronization: Memory Ordering*, appendix C *Why Memory Barriers?*.
3. Linux: `Documentation/process/volatile-considered-harmful.rst`, `Documentation/memory-barriers.txt`, `Documentation/atomic_t.txt`, `tools/memory-model/` (LKMM).
4. Arm, *Arm Architecture Reference Manual* (DDI 0487) B2 *The AArch64 Application Level Memory Model*; *ARMv7-M ARM* A3.4 *Synchronization and semaphores*; FEAT_LSE, FEAT_LRCPC.
5. H.-J. Boehm, *Can Seqlocks Get Along with Programming Language Memory Models?*, MSPC 2012.
6. J. Alglave, L. Maranget, M. Tautschnig, *Herding Cats*, TOPLAS 2014; herdtools7 (`herd7`, `litmus7`).
7. LLVM *Atomic Instructions and Concurrency Guide*; GCC `__atomic` builtins and libatomic ABI.
