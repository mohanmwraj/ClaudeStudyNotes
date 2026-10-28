# 01 · Happens-before, synchronizes-with, modification orders, and data-race UB

> **Scope.** The C++ memory model does not describe "when" things happen. It defines a few relations between the
> operations of one execution (sequenced-before, reads-from, modification order, synchronizes-with,
> happens-before) and one rule: **two conflicting accesses, at least one non-atomic, not ordered by happens-before,
> are a data race, and a data race is undefined behaviour.** This file makes those relations concrete. It shows what
> optimizers do to racy code (in the object file), why atomic loads and stores are not an atomic increment (by
> measurement), and four happens-before constructions that hold on every architecture (run on this machine).
> File 02 maps the orders to instructions, file 03 covers `std::atomic` internals, and file 04 covers fences and
> cache lines.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 7.1 | `race_codegen.cpp` | a racy wait loop is **deleted**, racy counters are merged, racy reads are folded, `volatile` is not atomic | asm: Clang x86-64 + AArch64, GCC x86-64 |
| 7.2 | `lost_updates.cpp` | `store(load() + 1)` with atomics is race-free and still loses most increments; `fetch_add` and a CAS loop do not | run, 4 threads, both compilers |
| 7.3 | `hb_chains.cpp` | message passing, transitivity across three threads, a release sequence continued by a relaxed RMW, per-object coherence | run, 2–3 threads, both compilers |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (zig, libc++), `-O2 -Wall -Wextra -Wpedantic
-Werror -Wshadow -Wconversion -Wsign-conversion`, run on an Intel Core i5-11260H (Tiger Lake-H, 6 cores / 12 threads,
x86-64 TSO). Assembly: Clang 21.1 `-O3` for `x86_64-linux-gnu` and `aarch64-linux-gnu`, and GCC 16.2 `-O3`. **No ARM64
hardware is available here.** Every AArch64 statement is about the generated instructions and the architecture's
published memory model, never about a run (⚠ where it matters). Multi-threaded tests use at most 4 threads and finish
in about a second.

---

## 1. First principles

### 1.1 The relations, as a picture

One execution of the message-passing program (Listing 7.3 A), with every relation the standard defines:

```text
 Thread P (producer)                               Thread C (consumer)
 ---------------------------------------------     ---------------------------------------------
 box = {r, 2r, 3r};         (non-atomic writes)
        | sb  (sequenced-before: program order)
        v
 seq.store(r, release)  ---- rf (reads-from) --->  seq.load(acquire) == r
                        ==== sw (synchronizes-with) ====>   | sb
                                                            v
                                                   read box.a, box.b, box.c   (non-atomic reads)

 happens-before (hb) = sb and sw, closed transitively:  box writes  -hb->  box reads   => no data race
 modification order (mo): every atomic object has ONE total order of all writes to it (seq: 0, 1, 2, ... r),
                          which every thread agrees with (coherence), whatever memory_order was used.
```

* **sequenced-before** is evaluation order inside one thread ([intro.execution]).
* **reads-from**: an atomic load takes its value from one particular store in that object's modification order.
* **synchronizes-with**: a *release* operation on `M` and an *acquire* operation on `M` that reads the value written
  by the release (or by a later member of its *release sequence*, §1.4). Fences have their own rules ([atomics.fences],
  file 04).
* **happens-before**: built from sequenced-before and synchronizes-with, transitively. C++20 (P0668) split it into
  *simply* and *strongly* happens-before so that the `seq_cst` rules stay implementable on POWER. For programs that do
  not mix `seq_cst` with weaker orders on the same objects, the intuitive version is enough.
* **data race** ([intro.races]): two *potentially concurrent conflicting* actions (same location, at least one write),
  at least one of them non-atomic, neither happening before the other. **Undefined behaviour**, for the whole
  program, not "a stale value".

Happens-before is **not time**. Two operations can be ordered in wall-clock time and unordered by happens-before, and
then the later one may still read the older value. Reasoning has to follow the arrows.

### 1.2 What optimizers do with a data race (Listing 7.1)

```cpp
// race_codegen.cpp - a data race is UB, and the optimizer uses that: hoisted loads, merged updates, folded reads
#include <atomic>

// 1. Spin on a NON-atomic flag. No other thread may write it without a data race (UB), so the
//    compiler may read it once; a side-effect-free loop may also be assumed to terminate
//    ([intro.progress]). Together: the loop is deleted, and the function returns at once.
void spin_plain(const bool* ready) {
    while (!*ready) {
    }
}
// An atomic flag is re-read on every iteration, even with relaxed ordering ([intro.progress]:
// the last store "should" become visible to all threads "in a finite period of time").
void spin_atomic(const std::atomic<bool>* ready) {
    while (!ready->load(std::memory_order_relaxed)) {
    }
}

// 2. A non-atomic counter in a loop: kept in a register, stored once (other threads "cannot" look).
void count_plain(int* hits, int n) {
    for (int i = 0; i < n; ++i) ++*hits;
}
// Relaxed RMWs stay one locked instruction per iteration: compilers do not merge atomics.
void count_atomic(std::atomic<int>* hits, int n) {
    for (int i = 0; i < n; ++i) hits->fetch_add(1, std::memory_order_relaxed);
}

// 3. Two reads of a non-atomic int fold into one value: the result is the constant 0.
int read_twice_plain(const int* p) { return *p - *p; }
int read_twice_atomic(const std::atomic<int>* p) {
    return p->load(std::memory_order_relaxed) - p->load(std::memory_order_relaxed);
}

// 4. volatile forces each access to happen, but the increment is still a separate load, add and store:
//    volatile is for memory-mapped I/O and signal handlers, not for threads.
void count_volatile(volatile int* hits) { *hits = *hits + 1; }
```

Clang 21 `-O3`, x86-64:

```asm
_Z10spin_plainPKb:                 # spin_plain(bool const*)
	retq

_Z11spin_atomicPKNSt3__16atomicIbEE: # spin_atomic(std::__1::atomic<bool> const*)
.LBB1_1:
	movzbl	(%rdi), %eax
	cmpb	$1, %al
	jne	.LBB1_1
	retq

_Z11count_plainPii:                # count_plain(int*, int)
	testl	%esi, %esi
	jle	.LBB2_2
	addl	%esi, (%rdi)
.LBB2_2:
	retq

_Z12count_atomicPNSt3__16atomicIiEEi: # count_atomic(std::__1::atomic<int>*, int)
	testl	%esi, %esi
	jle	.LBB3_6
	movl	%esi, %eax
	andl	$7, %eax
	cmpl	$8, %esi
	jb	.LBB3_4
	andl	$2147483640, %esi
.LBB3_3:
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	addl	$-8, %esi
	jne	.LBB3_3
.LBB3_4:
	testl	%eax, %eax
	je	.LBB3_6
.LBB3_5:
	lock	addl	$1, (%rdi)
	addl	$-1, %eax
	jne	.LBB3_5
.LBB3_6:
	retq

_Z16read_twice_plainPKi:           # read_twice_plain(int const*)
	xorl	%eax, %eax
	retq

_Z17read_twice_atomicPKNSt3__16atomicIiEE: # read_twice_atomic(std::__1::atomic<int> const*)
	movl	(%rdi), %eax
	movl	(%rdi), %ecx
	subl	%ecx, %eax
	retq

_Z14count_volatilePVi:             # count_volatile(int volatile*)
	addl	$1, (%rdi)
	retq
```

Clang 21 `-O3`, AArch64:

```asm
_Z10spin_plainPKb:                 // spin_plain(bool const*)
	ret

_Z11spin_atomicPKNSt3__16atomicIbEE: // spin_atomic(std::__1::atomic<bool> const*)
.LBB1_1:
	ldrb	w8, [x0]
	cmp	w8, #1
	b.ne	.LBB1_1
	ret

_Z11count_plainPii:                // count_plain(int*, int)
	cmp	w1, #1
	b.lt	.LBB2_2
	ldr	w8, [x0]
	add	w8, w8, w1
	str	w8, [x0]
.LBB2_2:
	ret

_Z12count_atomicPNSt3__16atomicIiEEi: // count_atomic(std::__1::atomic<int>*, int)
	cmp	w1, #1
	b.lt	.LBB3_4
	mov	w8, wzr
.LBB3_2:
	ldxr	w9, [x0]
	add	w9, w9, #1
	stxr	w10, w9, [x0]
	cbnz	w10, .LBB3_2
	add	w8, w8, #1
	cmp	w8, w1
	b.ne	.LBB3_2
.LBB3_4:
	ret

_Z16read_twice_plainPKi:           // read_twice_plain(int const*)
	mov	w0, wzr
	ret

_Z17read_twice_atomicPKNSt3__16atomicIiEE: // read_twice_atomic(std::__1::atomic<int> const*)
	ldr	w8, [x0]
	ldr	w9, [x0]
	sub	w0, w8, w9
	ret

_Z14count_volatilePVi:             // count_volatile(int volatile*)
	ldr	w8, [x0]
	add	w8, w8, #1
	str	w8, [x0]
	ret
```

GCC 16 `-O3`, x86-64:

```asm
_Z10spin_plainPKb:                 # spin_plain(bool const*)
	ret

_Z11spin_atomicPKSt6atomicIbE:     # spin_atomic(std::atomic<bool> const*)
.L4:
	cmpb	$0, (%rdi)
	je	.L4
	ret

_Z11count_plainPii:                # count_plain(int*, int)
	testl	%esi, %esi
	jle	.L7
	addl	%esi, (%rdi)
.L7:
	ret

_Z12count_atomicPSt6atomicIiEi:    # count_atomic(std::atomic<int>*, int)
	testl	%esi, %esi
	jle	.L9
	xorl	%eax, %eax
	testb	$1, %sil
	je	.L11
	lock	addl	$1, (%rdi)
	movl	$1, %eax
	cmpl	$1, %esi
	je	.L18
.L11:
	lock	addl	$1, (%rdi)
	lock	addl	$1, (%rdi)
	addl	$2, %eax
	cmpl	%eax, %esi
	jne	.L11
.L9:
	ret
.L18:
	ret

_Z16read_twice_plainPKi:           # read_twice_plain(int const*)
	xorl	%eax, %eax
	ret

_Z17read_twice_atomicPKSt6atomicIiE: # read_twice_atomic(std::atomic<int> const*)
	movl	(%rdi), %eax
	subl	(%rdi), %eax
	ret

_Z14count_volatilePVi:             # count_volatile(int volatile*)
	addl	$1, (%rdi)
	ret
```

* **`spin_plain` is a bare `ret` on all three targets.** The compiler may assume no other thread writes `*ready`
  (that would be a race). It may also assume that a loop with no I/O, volatile access, atomic or synchronization
  operation eventually terminates ([intro.progress]). A loop that could only end if `*ready` were already true is
  therefore removed. A thread that "waits for the flag" walks straight past it and reads a half-published payload.
  C++26 (P2809) makes *trivial* infinite loops (`while (true) {}`) defined. It does not cover this loop, because the
  condition is not a constant expression.
* **`spin_atomic` keeps the load in the loop** (`movzbl`/`ldrb` + branch). Even a relaxed atomic load counts as
  an atomic operation for forward progress, and every iteration must perform it.
* **`count_plain` becomes one `addl %esi, (%rdi)`** (one `ldr`/`add`/`str` on AArch64): n increments merged into one.
  Another thread reading the counter would see 0 and then n, with no values in between.
  **`count_atomic` keeps one `lock addl` (or `ldxr`/`stxr` loop) per increment.** The standard would allow some
  merging of relaxed atomics, but GCC and Clang do not do it (WG21 N4455 discusses which merges would be legal).
* **`read_twice_plain` is the constant 0.** Two reads of a non-atomic `int` fold into one, so a torn or changing value
  "cannot" happen. `read_twice_atomic` performs two loads.
* **`count_volatile`** is `addl $1, (%rdi)` on x86-64: one instruction, **without** `LOCK`, so it is not atomic between
  cores. On AArch64 it is a separate `ldr`, `add`, `str`. `volatile` forces each access to happen and keeps volatile
  accesses in order relative to each other. It gives no atomicity for read-modify-write and no ordering relative to
  non-volatile memory, and a racy volatile access is still a data race in C++.

### 1.3 Atomic is not the same as an atomic read-modify-write (Listing 7.2)

```cpp
// lost_updates.cpp - atomic loads and stores are not an atomic read-modify-write
#include <atomic>
#include <cstdint>
#include <latch>
#include <print>
#include <thread>
#include <vector>

constexpr int kThreads = 4;
constexpr std::int64_t kPerThread = 2'000'000;

template <class Op>
std::int64_t hammer(Op op) {
    std::atomic<std::int64_t> counter{0};
    std::latch start(kThreads);
    std::vector<std::jthread> ts;
    for (int t = 0; t < kThreads; ++t)
        ts.emplace_back([&] {
            start.arrive_and_wait();          // all threads run the loop at the same time
            for (std::int64_t i = 0; i < kPerThread; ++i) op(counter);
        });
    ts.clear();                               // join
    return counter.load();
}

int main() {
    constexpr std::int64_t expected = kThreads * kPerThread;
    // Each load and each store is atomic, so the program is race-free (no UB). The read-modify-write is not:
    // two threads load the same value, both store value + 1, and one increment disappears.
    const std::int64_t load_store = hammer([](std::atomic<std::int64_t>& c) {
        c.store(c.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
    });
    const std::int64_t rmw = hammer([](std::atomic<std::int64_t>& c) {
        c.fetch_add(1, std::memory_order_relaxed);   // one indivisible RMW (LOCK XADD / LDADD / LDXR+STXR loop)
    });
    const std::int64_t cas = hammer([](std::atomic<std::int64_t>& c) {
        std::int64_t cur = c.load(std::memory_order_relaxed);
        while (!c.compare_exchange_weak(cur, cur + 1, std::memory_order_relaxed)) {
        }
    });
    std::println("expected {} increments ({} threads x {})", expected, kThreads, kPerThread);
    std::println("load + store : {:>8}  lost {}", load_store, expected - load_store);
    std::println("fetch_add    : {:>8}  exact: {}", rmw, rmw == expected ? "yes" : "NO");
    std::println("CAS loop     : {:>8}  exact: {}", cas, cas == expected ? "yes" : "NO");
}
```

Output (verified, GCC then Clang; the "lost" counts differ from run to run):

```text
expected 8000000 increments (4 threads x 2000000)
load + store :  2049265  lost 5950735
fetch_add    :  8000000  exact: yes
CAS loop     :  8000000  exact: yes
expected 8000000 increments (4 threads x 2000000)
load + store :  4322072  lost 3677928
fetch_add    :  8000000  exact: yes
CAS loop     :  8000000  exact: yes
```

The load + store program is **race-free**: every access is atomic, so there is no undefined behaviour. It is still
wrong: two threads load the same value and both store value + 1. Over repeated runs on this machine, 47–74% of the
8,000,000 increments were lost. A data race is UB; a *race condition* (a logic error in interleaving) is not, and
`std::atomic` does not prevent one. The fix is one indivisible RMW: `fetch_add` (`LOCK XADD`, `LDADD`, or an
`LDXR`/`STXR` loop) or a CAS loop.

### 1.4 Happens-before by construction (Listing 7.3)

```cpp
// hb_chains.cpp - happens-before by construction: message passing, transitivity, release sequences, coherence
#include <atomic>
#include <cstdint>
#include <print>
#include <thread>

using i64 = std::int64_t;
constexpr auto rlx = std::memory_order_relaxed;
constexpr auto acq = std::memory_order_acquire;
constexpr auto rel = std::memory_order_release;

template <class F>
void spin_until(F done) {
    while (!done()) {
    }
}

// A. Message passing: a plain payload published by a release store and consumed after an acquire load.
//    The ack in the other direction makes the producer's NEXT write happen after the consumer's read.
i64 message_passing(i64 rounds) {
    struct Payload { i64 a, b, c; } box{};            // non-atomic
    std::atomic<i64> seq{0}, ack{0};
    i64 bad = 0;
    std::jthread consumer([&] {
        for (i64 r = 1; r <= rounds; ++r) {
            spin_until([&] { return seq.load(acq) == r; });  // synchronizes with the release store of r
            if (box.a != r || box.b != 2 * r || box.c != 3 * r) ++bad;
            ack.store(r, rel);
        }
    });
    for (i64 r = 1; r <= rounds; ++r) {
        box = {r, 2 * r, 3 * r};
        seq.store(r, rel);
        spin_until([&] { return ack.load(acq) == r; });
    }
    consumer.join();
    return bad;
}

// B. Transitivity: A -> B -> C. C never touches A's flag, yet A's write happens before C's read.
i64 transitivity(i64 rounds) {
    i64 x = 0;                                          // non-atomic, written by A, read by C
    std::atomic<i64> f1{0}, f2{0}, done{0};
    i64 bad = 0;
    std::jthread b([&] {
        for (i64 r = 1; r <= rounds; ++r) {
            spin_until([&] { return f1.load(acq) == r; });
            f2.store(r, rel);
        }
    });
    std::jthread c([&] {
        for (i64 r = 1; r <= rounds; ++r) {
            spin_until([&] { return f2.load(acq) == r; });
            if (x != r) ++bad;
            done.store(r, rel);
        }
    });
    for (i64 r = 1; r <= rounds; ++r) {
        x = r;
        f1.store(r, rel);
        spin_until([&] { return done.load(acq) == r; });
    }
    b.join();
    c.join();
    return bad;
}

// C. Release sequence: A's release store is followed by B's RELAXED read-modify-write. C acquires the
//    value B wrote, and still synchronizes with A, because an RMW continues the release sequence that A's
//    store heads. (If B did a plain relaxed STORE instead, C would not synchronize with A: data race.)
i64 release_sequence(i64 rounds) {
    i64 data = 0;
    std::atomic<i64> flag{0}, done{0};
    i64 bad = 0;
    std::jthread b([&] {
        for (i64 r = 1; r <= rounds; ++r) {
            i64 e = 3 * r;
            while (!flag.compare_exchange_weak(e, 3 * r + 1, rlx)) e = 3 * r;   // relaxed RMW: 3r -> 3r+1
        }
    });
    std::jthread c([&] {
        for (i64 r = 1; r <= rounds; ++r) {
            spin_until([&] { return flag.load(acq) == 3 * r + 1; });  // reads B's value, syncs with A
            if (data != r) ++bad;
            done.store(r, rel);
        }
    });
    for (i64 r = 1; r <= rounds; ++r) {
        data = r;
        flag.store(3 * r, rel);
        spin_until([&] { return done.load(acq) == r; });
    }
    b.join();
    c.join();
    return bad;
}

// D. Coherence: every atomic object has ONE modification order that all threads agree on. A reader can
//    miss values, but can never see the counter go backwards, even with relaxed loads, on any hardware.
i64 coherence(i64 n) {
    std::atomic<i64> x{0};
    std::atomic<i64> backwards{0};
    auto reader = [&] {
        i64 last = 0, seen;
        do {
            seen = x.load(rlx);
            if (seen < last) backwards.fetch_add(1, rlx);
            last = seen;
        } while (seen != n);
    };
    std::jthread r1(reader), r2(reader);
    for (i64 v = 1; v <= n; ++v) x.store(v, rlx);
    r1.join();
    r2.join();
    return backwards.load();
}

int main() {
    std::println("A. message passing, 100000 rounds  : stale or torn payloads = {}", message_passing(100'000));
    std::println("B. transitivity A->B->C, 50000 rds : stale reads of x       = {}", transitivity(50'000));
    std::println("C. release sequence via RMW, 50000 : stale reads of data    = {}", release_sequence(50'000));
    std::println("D. coherence, 2 readers, 2000000   : counter went backwards = {}", coherence(2'000'000));
}
```

Output (verified, GCC then Clang):

```text
A. message passing, 100000 rounds  : stale or torn payloads = 0
B. transitivity A->B->C, 50000 rds : stale reads of x       = 0
C. release sequence via RMW, 50000 : stale reads of data    = 0
D. coherence, 2 readers, 2000000   : counter went backwards = 0
A. message passing, 100000 rounds  : stale or torn payloads = 0
B. transitivity A->B->C, 50000 rds : stale reads of x       = 0
C. release sequence via RMW, 50000 : stale reads of data    = 0
D. coherence, 2 readers, 2000000   : counter went backwards = 0
```

* **A, message passing.** The release store of `seq` synchronizes with the acquire load that reads it, so the plain
  `box` writes happen before the plain `box` reads. The `ack` in the other direction is just as necessary: it makes the
  consumer's read of round r happen before the producer's write of round r + 1. Without it the program has a write-read
  race on `box`, even though "the producer waits".
* **B, transitivity.** C never touches `f1`. A's write of `x` happens before C's read anyway, through
  `x = r` -sb-> `f1` release -sw-> B's acquire -sb-> `f2` release -sw-> C's acquire -sb-> read `x`.
  Happens-before composes across any number of threads, so a pipeline of acquire/release handoffs needs no global
  barrier.
* **C, release sequences.** A writes `data`, then `flag = 3r` with release. B changes `3r` to `3r + 1` with a
  **relaxed CAS**. C acquires `3r + 1`, a value A never wrote, and still synchronizes with A. The *release sequence*
  headed by A's store includes every later read-modify-write on `flag` by any thread, so reading the RMW's value counts
  as reading from the sequence. Reference counts depend on this rule (`fetch_sub` on the last reference, Folder 05).
  C++20 (P0982) narrowed the definition: a later *plain store* by the releasing thread no longer continues the
  sequence. If B had done `flag.store(3r + 1, relaxed)` instead of the CAS, C would not synchronize with A, and C's read
  of `data` would be a data race.
* **D, coherence.** Every atomic object has one modification order, and four rules ([intro.races]: write-write,
  read-read, read-write and write-read coherence) make every thread's view consistent with it. A relaxed reader can
  miss values but **never sees the counter go backwards**, on any conforming implementation. `memory_order_relaxed`
  gives up ordering *between different objects*, not consistency for one object.

### 1.5 What the orders add on top (preview of file 02)

| Order | What it adds to a plain atomic access |
|---|---|
| `relaxed` | atomicity + per-object coherence; nothing for other objects |
| `release` (store/RMW) | earlier memory operations of this thread become visible to a thread that acquires this value |
| `acquire` (load/RMW) | later memory operations of this thread cannot move before the load; pairs with a release |
| `acq_rel` (RMW) | both, on one RMW |
| `seq_cst` | acquire/release plus one total order `S` over all `seq_cst` operations, consistent with happens-before. This forbids store-buffering (file 02, Listing 7.5) |
| `consume` | intended as acquire for dependent loads only; every compiler implements it as `acquire`; **deprecated in C++26 (P3475)** |

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| memory model | first standard threads + memory model (Boehm & Adve) | out-of-thin-air note rewritten as "should" | `consume` temporarily discouraged (P0371) | `seq_cst` fixes for POWER (P0668): *strongly* happens-before; release sequences weakened (P0982) | — | `consume` deprecated, `[[carries_dependency]]` removed (P3475) |
| forward progress | implementations may assume termination | — | — | — | — | trivial infinite loops (constant condition) are not UB (P2809) |
| atomics API | `std::atomic`, fences | — | `is_always_lock_free` | `atomic_ref`, `wait`/`notify`, value-initializing default constructor (P0883), `atomic<shared_ptr>`, floating-point `fetch_add` | `<stdatomic.h>` compatibility (P0943) | `fetch_max`/`fetch_min` (P0493), `atomic_ref` updates (P2835, P3323) |
| `volatile` | unchanged from C++03 | — | — | many compound operations on volatile deprecated (P1152) | some un-deprecated (P2327) | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| "is the worker ready?" flag | `bool ready;` polled in a loop (deleted by the optimizer, Listing 7.1) | `std::atomic<bool>` with release/acquire, or `atomic::wait` (Folder 08) |
| statistics counter, many writers | `c.store(c.load() + 1)` on an atomic (loses most updates, Listing 7.2) | `fetch_add(1, relaxed)`, or one counter per thread summed on read (file 04) |
| publishing a struct to another thread | write fields, then set a relaxed flag | write fields, then **release** store; reader **acquire** loads before reading fields |
| handoff in both directions (ping-pong buffer) | only the producer→consumer edge synchronized | an acquire/release edge in each direction (Listing 7.3 A) |
| refcount or "last one out" logic | `count.store(count.load() - 1)` | `fetch_sub(1, acq_rel)` (or release + acquire fence on zero, Folder 05 Listing 5.7): RMWs continue release sequences |
| device registers, signal handlers | `std::atomic` for MMIO | `volatile` for MMIO; `volatile std::sig_atomic_t` or lock-free atomics for signal handlers |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a "wait" returns immediately or hangs forever, only at `-O2` | plain-variable spin loop hoisted or deleted (Listing 7.1) | TSan (Folder 12, ⚠ not on this Windows toolchain); grep for non-atomic flags shared between threads |
| counters too low under load | non-atomic increment, or atomic load + store | stress test with a known total (Listing 7.2) |
| torn or mixed struct contents on ARM64 only | flag published with relaxed or plain stores; x86 TSO hid it (file 02) | TSan; litmus-style stress on ARM hardware; review every relaxed flag |
| "impossible" value after the third thread | reasoning by time instead of happens-before; missing edge in a chain | draw the sb/sw arrows; TSan reports the missing edge |
| a refcount object freed while in use | relaxed decrement without acquire on the last reference | the Folder 05 Listing 5.7 pattern (relaxed increment, release decrement, acquire fence on zero); ASan use-after-free |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "A bool flag is atomic on x86, so this is fine"</b></summary>

**Initial prompt.** "Thread A fills a buffer and sets `bool done = true;`. Thread B does `while (!done) {}` and then
reads the buffer. It works in our tests. Is it correct?"

**L5 textbook answer.** "On x86 a one-byte store is atomic and TSO keeps stores in order, so B sees the buffer
after it sees `done`. It's technically a data race, but benign."

**Why L5 corrupts memory on ARM64.** There are two separate failures, and neither needs exotic hardware. First, the
compiler: Listing 7.1 shows `spin_plain` compiled to a bare `ret` by Clang on x86-64 and AArch64 and by GCC on x86-64.
The wait is gone, and B reads the buffer immediately. Second, the hardware: on AArch64 plain `str`/`ldr` instructions
can be reordered. Even if the loop survived, B could see `done == true` and then read old buffer contents. This is the
MP pattern that the AArch64 model allows and that has been observed on ARM hardware (Alglave et al., *Herding Cats*).
No data race is benign in C++: it is undefined behaviour, and optimizers rely on it.

**L7 principal defense.** "`std::atomic<bool> done`, `store(true, release)` after filling the buffer,
`load(acquire)` in the loop. That is `stlr` and `ldar` on ARMv8.0, and plain moves on x86 (file 02). If B blocks
rather than spins, `done.wait(false)` + `notify_one()` (Folder 08). The proof is the happens-before chain buffer writes
-sb-> release -sw-> acquire -sb-> buffer reads, not the test results."
</details>

<details><summary><b>Chain 2 ⚡ "Make it volatile then"</b></summary>

**Initial prompt.** "OK, then `volatile bool done` and `volatile int counter`. Volatile tells the compiler not to
optimize the accesses away."

**L5 textbook answer.** "Yes, volatile forces every read to go to memory, which fixes the loop. For the counter,
`++counter` on a volatile int is fine because it's one instruction on x86."

**Why L5 corrupts memory on ARM64.** Volatile fixes only the deleted loop. It keeps volatile accesses in order
relative to *other volatile accesses*. It does not order them against the non-volatile buffer writes, and it emits no
barrier: on AArch64 the buffer writes and the `done` store are still plain `str`s that can reorder. For the counter,
Listing 7.1 shows `addl $1, (%rdi)` on x86, one instruction **without `LOCK`**. Two cores can both load, add and store,
and lose an update. On AArch64 it is visibly three instructions (`ldr`, `add`, `str`). And in C++ the race remains UB.

**L7 principal defense.** "`volatile` is for memory-mapped I/O and `sig_atomic_t` in signal handlers. Threads use
`std::atomic` (or `std::atomic_ref` over existing memory, file 03). C++20 deprecated most compound operations on
volatile (P1152) precisely because `++v` on a volatile looks atomic and isn't. MSVC's `/volatile:ms` gives volatile
acquire/release semantics, but that is an MSVC-specific x86 extension (and not the default for ARM64 targets), not C++."
</details>

<details><summary><b>Chain 3 🔥 "The counter is std::atomic, so it's thread-safe"</b></summary>

**Initial prompt.** "Every access to `hits` is `std::atomic<int64_t>`. Code: `hits.store(hits.load() + 1);`. Is it
thread-safe?"

**L5 textbook answer.** "Yes: atomic operations can't be interrupted, so there's no race."

**Why L5 breaks.** There is no *data race*: each load and each store is atomic, so the behaviour is defined. There
is a *race condition*: Listing 7.2 lost 47–74% of 8 million increments on this machine, with 4 threads. Defined
behaviour and correct behaviour are different properties. This bug appears identically on x86 and ARM64, and no memory
order fixes it, because the problem is the read-modify-write being split, not visibility.

**L7 principal defense.** "One RMW: `fetch_add(1, relaxed)`. Relaxed is enough for a pure counter: atomicity and the
single modification order guarantee the total. Under heavy contention, shard it: one counter per thread or per core on
its own cache line, summed on read (file 04 measures 17–47 ns per contended `fetch_add` against about 0.5 ns per
private increment)."
</details>

<details><summary><b>Chain 4 🧊 "Define happens-before"</b></summary>

**Initial prompt.** "What does 'A happens before B' mean in the C++ memory model?"

**L5 textbook answer.** "A executed earlier than B in time, so B sees A's effects."

**Why L5 breaks.** Happens-before is a relation built from program order (sequenced-before) and synchronizes-with
edges, closed under transitivity. It is not wall-clock time. A relaxed load executed a microsecond after a store in
real time may still return the older value: nothing orders them. Conversely, Listing 7.3 B shows A's write happening
before C's read through two threads, without C ever reading anything A wrote atomically. Reasoning "it happened earlier,
so it's visible" is exactly how stale-read bugs on ARM64 get written.

**L7 principal defense.** "I reason in edges: which load reads from which store (reads-from), whether that pair is
release/acquire (synchronizes-with), and then transitivity. A data race is two conflicting accesses, at least one
non-atomic, with no happens-before path either way. C++20 added *strongly* happens-before (P0668) for the `seq_cst`
rules, and for code that doesn't mix `seq_cst` with weaker orders on the same objects the simple version is exact."
</details>

<details><summary><b>Chain 5 ⚡ "Release sequences: does the relaxed RMW in the middle break synchronization?"</b></summary>

**Initial prompt.** "Thread A writes `data`, then `flag.store(1, release)`. Thread B does
`flag.fetch_add(1, relaxed)`. Thread C waits for `flag == 2` with acquire and reads `data`. Is the read safe? What if
B does `flag.store(2, relaxed)` after reading 1?"

**L5 textbook answer.** "C didn't read A's value, so it doesn't synchronize with A. You need B to use release too.
And the store version is the same as the RMW version."

**Why L5 breaks.** Both halves are wrong. With the RMW, C *does* synchronize with A: the release sequence headed by
A's store contains every later RMW on `flag`, and reading the RMW's value counts as reading from the sequence. Listing
7.3 C runs exactly this, with 0 stale reads. With a plain relaxed store in B, there is no synchronization, and C's read
of `data` is a data race (UB), even though it may work on ARMv8, whose multi-copy-atomic model and coherence happen to
order it in hardware. C++20 (P0982) narrowed the release-sequence definition to RMWs only.

**L7 principal defense.** "Any 'pass along' step between a releaser and an acquirer must be an RMW (or itself
release/acquire). That's why `shared_ptr` decrements are RMWs and why a `count.store(count.load() - 1)` refcount is
wrong twice: lost updates *and* a broken release sequence."
</details>

<details><summary><b>Chain 6 🧊 "Can a relaxed reader see a counter go backwards?"</b></summary>

**Initial prompt.** "A single writer increments `x` with relaxed stores. Can a reader using relaxed loads see 5 and
then 3?"

**L5 textbook answer.** "Yes. Relaxed means no ordering guarantees at all, so the CPU can reorder anything."

**Why L5 breaks.** Relaxed operations on the *same* object are still coherent. All threads agree on one modification
order per atomic object, and read-read coherence forbids reading 5 and then an earlier value. Listing 7.3 D: two
readers, 2 million stores, 0 backward steps, on both compilers. AArch64 guarantees the same for same-address loads in
hardware. *Herding Cats* (Alglave et al., 2014) reported a load-load hazard on some older ARMv7 cores, which ARM treated
as an erratum: a hardware bug, not permitted behaviour.

**L7 principal defense.** "Relaxed is right for monotonic counters, statistics, and 'max seen so far' values, where
each object is read on its own. It's wrong the moment I conclude something about *another* object from what I read, like
'the counter is 5, so the 5th slot is filled'. That needs acquire/release."
</details>

<details><summary><b>Chain 7 🔥 "Why did the compiler delete my loop?"</b></summary>

**Initial prompt.** "`while (!*ready) {}` compiles to just `ret` at `-O2`. Is that a compiler bug?"

**L5 textbook answer.** "Probably over-aggressive optimization; add `-fno-strict-aliasing` or make the variable
global."

**Why L5 breaks.** It's conforming. Two rules combine (Listing 7.1). The compiler may assume that no other thread
writes `*ready`, because that would be a data race, so the value is loop-invariant. And [intro.progress] lets it assume
that a loop without I/O, volatile access, or atomic/synchronization operations terminates. A loop that could only
terminate if the condition were already false at entry is dead code. C++26 P2809 makes `while (true) {}` (a constant
condition) defined behaviour, but not this loop. Flags won't help, and making the variable global changes nothing.

**L7 principal defense.** "Any wait for another thread's write must involve an atomic or synchronization operation.
Then the loop cannot be assumed to terminate, and the load stays in the loop (`spin_atomic`). For anything longer than a
few hundred nanoseconds, don't spin at all: `atomic::wait`, a condition variable, or a semaphore (Folder 08)."
</details>

<details><summary><b>Chain 8 🔥 "Is double-checked locking broken in C++?"</b></summary>

**Initial prompt.** "Implement a lazily-initialized singleton with double-checked locking. Isn't DCLP broken?"

**L5 textbook answer.** "DCLP is broken (Meyers and Alexandrescu, 2004); always take the mutex."

**Why L5 corrupts memory on ARM64.** The 2004 paper is about plain pointers. There, the first unlocked check is a
data race. And with a plain pointer on AArch64, the reader can see the pointer before the object's fields: the MP
pattern, so it reads a half-constructed object. Always taking the mutex is correct, but it costs a lock acquisition on
every call for no reason. The broken version is the plain-pointer one, not the technique.

**L7 principal defense.** "First choice: a function-local static. The compiler emits exactly the correct DCLP: a guard
byte loaded with `ldarb` on ARM64 (Folder 06, Listing 6.6) and `__cxa_guard_acquire` on the slow path. Second:
`std::call_once`. If I must hand-roll it: `std::atomic<T*>` loaded with acquire, a mutex on the slow path, a relaxed
re-check under the lock, and a release store after construction."
</details>

---

## 6. Invariants checklist

- [ ] Every object accessed by more than one thread, with at least one writer, is atomic (or `atomic_ref`-accessed),
      or every access is ordered by happens-before (mutex, release/acquire, thread start/join).
- [ ] No spin loop polls a non-atomic variable.
- [ ] Every read-modify-write of shared state is one atomic RMW (`fetch_*`, `exchange`, CAS), never load + store.
- [ ] Every handoff edge has a release on the writer side and an acquire on the reader side, in **each** direction the
      data flows.
- [ ] Intermediate steps between a releaser and an acquirer are RMWs (release sequences, C++20 rules).
- [ ] `volatile` appears only for MMIO and signal-handler flags.
- [ ] Relaxed atomics are used only where no conclusion about other memory is drawn from the value.

## 7. References

- [intro.races] (data races, happens-before, coherence): <https://eel.is/c++draft/intro.races>
- [intro.progress] (forward progress): <https://eel.is/c++draft/intro.progress>
- [atomics.order] (memory orders, release sequences): <https://eel.is/c++draft/atomics.order>
- H.-J. Boehm, S. Adve, "Foundations of the C++ Concurrency Memory Model", PLDI 2008: <https://www.hboehm.info/c++mm/>
- M. Batty et al., "Mathematizing C++ Concurrency", POPL 2011: <https://www.cl.cam.ac.uk/~pes20/cpp/popl085ap-sewell.pdf>
- J. Alglave, L. Maranget, M. Tautschnig, "Herding Cats", TOPLAS 2014: <https://arxiv.org/abs/1308.6810>
- P0668R5 (revising the C++ memory model): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0668r5.html>
- P0982R1 (weaken release sequences): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0982r1.html>
- P2809R3 (trivial infinite loops are not UB): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2809r3.html>
- P3475R2 (defang and deprecate `memory_order::consume`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p3475r2.pdf>
- N4455 (no sane compiler would optimize atomics): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2015/n4455.html>
- S. Meyers, A. Alexandrescu, "C++ and the Perils of Double-Checked Locking", 2004: <https://www.aristeia.com/Papers/DDJ_Jul_Aug_2004_revised.pdf>
