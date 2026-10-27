# 03 · Concurrency Primitives: the JMM, CAS, AQS, StampedLock, Striping, Mechanical Sympathy and Clock Injection, in Java and C++

> **Folder 01 · File 3 of 3.** This file is the mechanics behind every concurrent design in the KB. It covers what the Java Memory Model and the C++ memory model guarantee (and what C++ leaves undefined), how CAS, AQS, `StampedLock`, `ConcurrentHashMap` and `LongAdder` are built, where false sharing and pointer-chasing cost real time, how to make time deterministic, and the stress harness the 20 problems reuse.
>
> **Eight listing pairs**, each in Java and C++, all self-testing:
>
> | # | Java | C++ | Shows |
> |---|---|---|---|
> | 3.1 | `StoreBufferLitmus.java` | `store_buffer_litmus.cpp` | Which access modes forbid the store-buffer reordering, measured |
> | 3.2 | `LostUpdates.java` | `lost_updates.cpp` | Check-then-act, CAS retry storms, `LongAdder`, CAS by identity vs by bits |
> | 3.3 | `AqsSynchronizers.java` | `futex_mutex.cpp` | Building a latch, a mutex and conditions on AQS; Drepper's futex mutex on `atomic::wait` |
> | 3.4 | `ReadMostlyLocks.java` | `seqlock_vs_shared_mutex.cpp` | `synchronized` vs `ReentrantReadWriteLock` vs `StampedLock`; mutex vs `shared_mutex` vs a race-free seqlock |
> | 3.5 | `OrderedLocking.java` | `ordered_locking.cpp` | Lock-order deadlock and three cures, striping with `bulkGet`, CHM per-bin locks |
> | 3.6 | `FalseSharingRing.java` | `false_sharing_ring.cpp` | False sharing at 8/64/128 B; an SPSC ring with padded, cached indices |
> | 3.7 | `ClockInjection.java` | `clock_injection.cpp` | `Clock` vs monotonic `Ticker`, `nanoTime` overflow, NTP steps, a virtual-time scheduler |
> | 3.8 | `StressHarness.java` | `stress_harness.cpp` | The reusable harness: spin gate, seeded streams, invariants, timeouts, deadlock diagnosis |
>
> **Verified with:** JDK 25.0.4.1 (`--release 21 -Xlint:all -Werror`), GCC 16.2 / libstdc++ and Clang 21.1 / libc++ (`-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`), on an Intel i5-11260H (6C/12T, x86-64), Windows 11. Deterministic outputs are **Output (verified)**. Timings and race counts are **one measured run**, with ranges quoted where several runs were taken.

---

## Contents

1. [Three hazards, and where reordering comes from](#1-three-hazards-and-where-reordering-comes-from)
2. [The memory models: JMM and C++](#2-the-memory-models-jmm-and-c)
3. [CAS, atomics and contention](#3-cas-atomics-and-contention)
4. [AQS and the anatomy of a lock](#4-aqs-and-the-anatomy-of-a-lock)
5. [Read-mostly data: RW locks, StampedLock, seqlocks](#5-read-mostly-data-rw-locks-stampedlock-seqlocks)
6. [Lock striping and deterministic lock ordering](#6-lock-striping-and-deterministic-lock-ordering)
7. [Mechanical sympathy: false sharing and ring buffers](#7-mechanical-sympathy-false-sharing-and-ring-buffers)
8. [Deterministic time: Clock, Ticker, virtual schedulers](#8-deterministic-time-clock-ticker-virtual-schedulers)
9. [Testing concurrent code: the harness and its limits](#9-testing-concurrent-code-the-harness-and-its-limits)
10. [Virtual threads and structured concurrency: what changes for LLD](#10-virtual-threads-and-structured-concurrency-what-changes-for-lld)
11. [Decision guide: which primitive, when](#11-decision-guide-which-primitive-when)
12. [Failure modes](#12-failure-modes)
13. [Bar-raiser chains](#13-bar-raiser-chains)
14. [Invariants checklist](#14-invariants-checklist)
15. [References](#15-references)

---

## 1. Three hazards, and where reordering comes from

Every concurrency bug in this KB is one of three hazards:

| Hazard | Question it asks | Typical bug | Tool that fixes it |
|---|---|---|---|
| **Atomicity** | Can another thread observe or interleave with the *middle* of my operation? | Check-then-act; `count++`; multi-key updates | Locks, CAS, single-writer ownership |
| **Visibility** | Will another thread *ever* see my write? | A stop flag that is never seen; a stale cache | `volatile`/atomics, locks, `final` fields |
| **Ordering** | Will another thread see my writes *in the order I made them*? | Publishing a pointer before the object's fields; Dekker-style flags | Release/acquire, sequentially consistent atomics, fences |

Reordering, the root of visibility and ordering bugs, comes from three independent layers. Any one of them is enough to break naive code:

1. **The compiler (javac rarely; the JIT and C++ optimizers routinely).** It may hoist a load out of a loop, keep a value in a register, merge or eliminate stores, and reorder independent accesses. This is legal whenever a *single-threaded* observer can't tell the difference.
2. **The CPU's store buffer.** A core retires a store into a private buffer and continues. Its own later loads may complete *before* that store becomes visible to other cores. x86-TSO allows exactly this one reordering (store→load). ARMv8 and POWER allow load→load, load→store and store→store as well.
3. **The cache hierarchy.** Coherence (MESI and its variants) guarantees all cores eventually agree on each *single* location's value. It doesn't order *different* locations without fences.

Listing 3.1 makes layer 2 visible on this laptop.

---

## 2. The memory models: JMM and C++

### 2.1 The contract both languages offer: DRF-SC 🔥

Both the Java Memory Model (JLS §17.4, JSR-133) and the C++11 memory model rest on the same theorem:

> **If a program has no data races, every execution appears sequentially consistent.** A *data race* is two accesses to the same location, at least one a write, in different threads, not ordered by happens-before. In C++ the conflicting accesses also must not both be atomic.

The two languages differ on what happens *with* a race:

- **Java:** a racy program still has defined semantics. Reads may see "stale" or surprising values, but never values out of thin air, and never a torn reference. `long`/`double` without `volatile` may tear (JLS §17.7), although 64-bit HotSpot doesn't tear them in practice.
- **C++:** a data race is **undefined behaviour**. The compiler may assume it never happens: it can delete a spin loop on a plain `bool`, or invent and merge stores. This single difference drives most of the C++ listings' design choices. Every shared mutable location is a `std::atomic` (at least `relaxed`) or is guarded by a lock.

### 2.2 Happens-before: the rules you actually use

| Edge (A happens-before B) | Java | C++ |
|---|---|---|
| Program order | A before B in the same thread | sequenced-before |
| Lock | `unlock(m)` → later `lock(m)` | `mutex::unlock` synchronizes-with the next `lock` |
| Atomic publication | `volatile` write → read that sees it | `store(release)` → `load(acquire)` that reads it |
| Thread lifecycle | `t.start()` → `t`'s first action; `t`'s last action → `t.join()` returns | `std::thread` constructor → thread body; body → `join()` returns |
| Library hand-offs | `j.u.c` "memory consistency effects": `queue.put` → `take`, `submit` → task, `countDown` → `await` returns, `Future` completion → `get` | `promise::set_value` → `future::get`; `latch::count_down` → `wait` returns |
| Final fields | Constructor end "freezes" `final` fields: readers see them correctly even via a racy publication, *if `this` didn't escape* | No equivalent; publish through release/acquire |
| Transitivity | A→B and B→C ⇒ A→C | same |

### 2.3 Access modes, side by side, with what x86-64 and AArch64 emit

| Java (`VarHandle` / field) | C++ `std::memory_order` | Guarantees | x86-64 load / store | AArch64 load / store ⚠ |
|---|---|---|---|---|
| plain field | non-atomic (a race is UB) | none across threads | `mov` / `mov` | `ldr` / `str` |
| `getOpaque` / `setOpaque` | `relaxed` | atomic, coherent per location, never hoisted out of loops; no ordering with other locations | `mov` / `mov` | `ldr` / `str` |
| `getAcquire` / `setRelease` | `acquire` / `release` | release: earlier accesses can't move after it; acquire: later accesses can't move before it. **Does not order a store before a later load** | `mov` / `mov` | `ldar` (or `ldapr`) / `stlr` |
| `volatile` / `getVolatile` / `setVolatile` | `seq_cst` | a single total order over all such accesses | `mov` / **`xchg`** (C++) or `mov` + `lock addl` (HotSpot) | `ldar` / `stlr` |
| `compareAndSet` | `compare_exchange_strong` (seq_cst) | atomic RMW plus full ordering | `lock cmpxchg` | `casal` (LSE) or an `ldaxr`/`stlxr` loop |
| `getAndAdd` | `fetch_add` | atomic RMW | `lock xadd` | `ldaddal` (LSE) |

On x86 the only extra cost of `seq_cst` over release/acquire is on the **store** side: an `xchg` or a full fence, tens of cycles. That one instruction is what forbids the store→load reordering. GCC's `xchg` for a seq_cst store is verified in the assembly study in §2.4. The AArch64 column follows the standard published mappings (⚠ verify for your compiler); the full table is in §15's Cambridge mappings reference.

### 2.4 Listing 3.1: the store-buffer litmus test 🔥

The test is Dekker's core: **Thread 1:** `x = 1; r1 = y`. **Thread 2:** `y = 1; r2 = x`. Under sequential consistency at least one store precedes both loads, so `r1 = r2 = 0` is impossible. With store buffers, both stores can sit in buffers while both loads read memory, giving `(0, 0)`.

```java
// StoreBufferLitmus.java - Dekker's store-buffer test: which access modes forbid r1 == r2 == 0?
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicIntegerArray;

public final class StoreBufferLitmus {

    enum Mode { PLAIN, RELEASE_ACQUIRE, VOLATILE }

    static final int ITERATIONS = 1_000_000;

    /**
     * Thread 1: x = 1; r1 = y.     Thread 2: y = 1; r2 = x.
     * Every iteration uses fresh slots (no reset races); the two threads start each iteration
     * from a spin gate so they really overlap.
     */
    static int[] run(Mode mode) throws InterruptedException {
        int[] px = new int[ITERATIONS], py = new int[ITERATIONS];           // PLAIN
        AtomicIntegerArray ax = new AtomicIntegerArray(ITERATIONS), ay = new AtomicIntegerArray(ITERATIONS);
        int[] r1 = new int[ITERATIONS], r2 = new int[ITERATIONS];
        AtomicInteger go = new AtomicInteger(-1), done = new AtomicInteger();

        Thread t1 = Thread.ofPlatform().start(() -> {
            for (int i = 0; i < ITERATIONS; i++) {
                while (go.get() < i) Thread.onSpinWait();
                switch (mode) {
                    case PLAIN -> { px[i] = 1; r1[i] = py[i]; }
                    case RELEASE_ACQUIRE -> { ax.setRelease(i, 1); r1[i] = ay.getAcquire(i); }
                    case VOLATILE -> { ax.set(i, 1); r1[i] = ay.get(i); }
                }
                done.incrementAndGet();
            }
        });
        Thread t2 = Thread.ofPlatform().start(() -> {
            for (int i = 0; i < ITERATIONS; i++) {
                while (go.get() < i) Thread.onSpinWait();
                switch (mode) {
                    case PLAIN -> { py[i] = 1; r2[i] = px[i]; }
                    case RELEASE_ACQUIRE -> { ay.setRelease(i, 1); r2[i] = ax.getAcquire(i); }
                    case VOLATILE -> { ay.set(i, 1); r2[i] = ax.get(i); }
                }
                done.incrementAndGet();
            }
        });
        for (int i = 0; i < ITERATIONS; i++) {
            go.set(i);
            while (done.get() < 2 * (i + 1)) Thread.onSpinWait();
        }
        t1.join();
        t2.join();
        int[] histogram = new int[4];                                       // index = r1*2 + r2
        for (int i = 0; i < ITERATIONS; i++) histogram[r1[i] * 2 + r2[i]]++;
        return histogram;
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.printf("%,d iterations per mode, %d hardware threads%n", ITERATIONS, Runtime.getRuntime().availableProcessors());
        System.out.printf("%-16s %10s %10s %10s %10s%n", "mode", "(0,0)", "(0,1)", "(1,0)", "(1,1)");
        int volatileZeroZero = -1;
        for (Mode m : Mode.values()) {
            int[] h = run(m);
            System.out.printf("%-16s %,10d %,10d %,10d %,10d%n", m, h[0], h[1], h[2], h[3]);
            if (m == Mode.VOLATILE) volatileZeroZero = h[0];
        }
        System.out.println(volatileZeroZero == 0 ? "SELF-TEST OK: volatile (sequentially consistent) never shows (0,0)"
                : "SELF-TEST FAILED: volatile produced (0,0)");
        if (volatileZeroZero != 0) System.exit(1);
    }
}
```

**One measured run (JDK 25.0.4.1). The `(0,0)` count varies; its *absence* under VOLATILE is guaranteed:**

```text
1,000,000 iterations per mode, 12 hardware threads
mode                  (0,0)      (0,1)      (1,0)      (1,1)
PLAIN               110,631    435,776    436,070     17,523
RELEASE_ACQUIRE      45,603    431,911    451,221     71,265
VOLATILE                  0    239,513    158,598    601,889
SELF-TEST OK: volatile (sequentially consistent) never shows (0,0)
```

```cpp
// store_buffer_litmus.cpp - Dekker's store-buffer test: which memory orders forbid r1 == r2 == 0?
#include <array>
#include <atomic>
#include <cstddef>
#include <memory>
#include <print>
#include <thread>
#include <vector>

constexpr std::size_t kIterations = 1'000'000;

inline void cpu_relax() {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#else
    std::this_thread::yield();
#endif
}

/**
 * Thread 1: x = 1; r1 = y.     Thread 2: y = 1; r2 = x.
 * All accesses to x/y are std::atomic (a plain int here would be a data race = UB); only the
 * memory_order differs. Fresh slots per iteration, spin-gated start.
 * The orders are template arguments on purpose: passed as runtime values, GCC 16 emitted the
 * seq_cst store (xchg) for every mode and the test silently measured the wrong thing.
 */
template <std::memory_order store_mo, std::memory_order load_mo>
std::array<std::size_t, 4> run() {
    auto x = std::make_unique<std::atomic<int>[]>(kIterations);
    auto y = std::make_unique<std::atomic<int>[]>(kIterations);
    std::vector<int> r1(kIterations), r2(kIterations);
    std::atomic<std::ptrdiff_t> go{-1};
    std::atomic<std::size_t> done{0};
    auto worker = [&](std::atomic<int>* mine, std::atomic<int>* theirs, std::vector<int>& out) {
        for (std::size_t i = 0; i < kIterations; ++i) {
            while (go.load(std::memory_order_acquire) < static_cast<std::ptrdiff_t>(i)) cpu_relax();
            mine[i].store(1, store_mo);
            out[i] = theirs[i].load(load_mo);
            done.fetch_add(1, std::memory_order_acq_rel);
        }
    };
    std::thread t1(worker, x.get(), y.get(), std::ref(r1));
    std::thread t2(worker, y.get(), x.get(), std::ref(r2));
    for (std::size_t i = 0; i < kIterations; ++i) {
        go.store(static_cast<std::ptrdiff_t>(i), std::memory_order_release);
        while (done.load(std::memory_order_acquire) < 2 * (i + 1)) cpu_relax();
    }
    t1.join();
    t2.join();
    std::array<std::size_t, 4> h{};
    for (std::size_t i = 0; i < kIterations; ++i) ++h[static_cast<std::size_t>(r1[i] * 2 + r2[i])];
    return h;
}

int main() {
    std::println("{} iterations per mode, {} hardware threads", kIterations, std::thread::hardware_concurrency());
    std::println("{:<16} {:>10} {:>10} {:>10} {:>10}", "mode", "(0,0)", "(0,1)", "(1,0)", "(1,1)");
    auto report = [](const char* name, const std::array<std::size_t, 4>& h) {
        std::println("{:<16} {:>10} {:>10} {:>10} {:>10}", name, h[0], h[1], h[2], h[3]);
        return h[0];
    };
    report("RELAXED", run<std::memory_order_relaxed, std::memory_order_relaxed>());
    report("RELEASE_ACQUIRE", run<std::memory_order_release, std::memory_order_acquire>());
    const std::size_t seq_cst_zero_zero = report("SEQ_CST", run<std::memory_order_seq_cst, std::memory_order_seq_cst>());
    std::println("{}", seq_cst_zero_zero == 0 ? "SELF-TEST OK: seq_cst never shows (0,0)" : "SELF-TEST FAILED: seq_cst produced (0,0)");
    return seq_cst_zero_zero == 0 ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
1000000 iterations per mode, 12 hardware threads
mode                  (0,0)      (0,1)      (1,0)      (1,1)
RELAXED               24754     158778     814895       1573
RELEASE_ACQUIRE       20277     367145     610257       2321
SEQ_CST                   0     361977     457634     180389
SELF-TEST OK: seq_cst never shows (0,0)
```

**One measured run, Clang 21.1:**

```text
1000000 iterations per mode, 12 hardware threads
mode                  (0,0)      (0,1)      (1,0)      (1,1)
RELAXED              260089     317981     415498       6432
RELEASE_ACQUIRE       78765     419323     497716       4196
SEQ_CST                   0     346080     412736     241184
SELF-TEST OK: seq_cst never shows (0,0)
```

What this proves, and the trap the C++ listing fell into on its first draft:

- **Plain/relaxed and release/acquire both permit `(0,0)` on x86.** Java plain showed 110,631 per million (11.1%). Release/acquire still showed 45,603: **acquire/release doesn't order a store before a later load.** Dekker-style mutual exclusion, "set my flag, then check yours", needs `volatile`/`seq_cst` (or a full fence). Interviewers love this: "Is `setRelease`/`getAcquire` enough for Peterson's lock?" No.
- **`volatile`/`seq_cst` produced zero `(0,0)` in every run**, as the model requires.
- **The trap: a runtime `memory_order` argument.** The first C++ draft passed the order as a *function parameter*. GCC 16 compiled the store as `xchg` (seq_cst) for **every** mode, so the "relaxed" row also showed 0 and the test silently measured the wrong thing. The worker loop GCC emitted:

  ```text
  mov  eax, 1
  xchg eax, DWORD PTR [r8]     ; "relaxed" store compiled as seq_cst
  mov  r10d, DWORD PTR [r9]
  ```

  Clang branched on the order instead. Making the orders **template arguments** fixed it. The lesson generalizes: memory orders must be compile-time constants if you want what you wrote, and a litmus test that never shows the relaxed outcome is suspect, not reassuring.

### 2.5 Safe publication and initialization ⚡

An object is *safely published* when another thread sees it, and everything it references, fully constructed. The idioms:

| Idiom | Java | C++ |
|---|---|---|
| Static/class initialization | `static final` field; initialization runs under the class-init lock | Function-local `static` ("magic statics", thread-safe since C++11) |
| Atomic reference | `volatile` field / `AtomicReference.set` → `get` | `std::atomic<T*>` store(release) → load(acquire) |
| Final fields | All fields `final` and `this` not escaping the constructor | — (no final-field semantics; use release/acquire) |
| Lock | Write and read under the same lock | same |
| Concurrent collection | `put` into CHM / `BlockingQueue` → `get` / `take` | your own release/acquire hand-off |
| One-time lazy init | Holder-class idiom, or double-checked locking **with `volatile`** | `std::call_once`, or a magic static |

Double-checked locking without `volatile` is broken in Java for a precise reason. The reference store may become visible before the constructor's field stores (store→store reordering on weak hardware, or compiler motion), so a second thread can see a non-null reference to an object whose fields are still default. `volatile` adds the release/acquire edge. The holder idiom avoids the question entirely, because the JVM's class-initialization lock provides the edge.

---
## 3. CAS, atomics and contention

### 3.1 Anatomy of a CAS loop

`compareAndSet(expected, new)` is one hardware instruction on x86 (`lock cmpxchg`): if the location still holds `expected`, write `new` and report success. Otherwise fail, and in C++ report the current value back through `expected`. Every lock-free algorithm is a loop:

```text
do {
    old  = read(location)
    next = f(old)              // pure: may run many times
} while (!CAS(location, old, next))
```

Four properties follow, and each has a measured counterpart in Listing 3.2:

1. **`f` runs once per *attempt*, not once per success.** `AtomicLong.updateAndGet` ran its function **2.08×** per successful update under 4-thread contention (2.08–2.24× across two runs; the C++ CAS loop needed 1.77–2.43 attempts per update). A side effect inside `f` (logging, incrementing another counter, I/O) happens more than once. The Javadoc says the function "should be side-effect-free". Interviewers check that you know *why*.
2. **Contention turns CAS into a retry storm.** Every failed CAS is a cache-line round trip. A single hot `AtomicLong` took 207 ms for 20 M increments, while `LongAdder` took 58 ms (3.6×). In C++, a hot `fetch_add` vs 16 padded cells measured 6.4–8.3× (GCC) and 10.8–14.0× (Clang) across two runs.
3. **Java compares references; C++ compares bits.** `AtomicReference.compareAndSet` uses `==` on references. `compareAndSet(1000L, …)` fails because autoboxing produced two `Long` objects, while `127L` succeeds only because of the `Long` cache. A CAS against an *equal* record fails for the same reason. C++ `compare_exchange` compares the **value representation**: a stored `0.0` doesn't match an expected `-0.0` even though `0.0 == -0.0`, and a stored NaN *does* match an expected NaN even though `NaN != NaN`. C++20 also specifies that padding bits don't participate (P0528).
4. **ABA.** A CAS succeeds if the value is equal *now*, regardless of what happened in between.
   - Java's GC prevents the pointer-reuse form of ABA for freshly allocated nodes: an address can't be reused while you still hold a reference to the old object.
   - *Value* ABA remains: counters that wrap, pooled nodes, or the business-level ABA of file 01 §5.4. The fixes are a version stamp (`AtomicStampedReference`, or the fencing token of file 01).
   - In C++, ABA with node reuse is the classic lock-free-stack bug. The fixes are tagged pointers (version bits), hazard pointers, or epoch-based reclamation. C++26 adds `std::hazard_pointer` and RCU ⚠ library support varies.

### 3.2 Listing 3.2

```java
// LostUpdates.java - check-then-act on ConcurrentHashMap, CAS retry storms, LongAdder, CAS by identity
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.IntConsumer;

public final class LostUpdates {

    static final int THREADS = 4;

    /** Runs body(threadIndex) on THREADS platform threads released together; returns elapsed ms. */
    static double parallel(IntConsumer body) throws InterruptedException {
        CountDownLatch ready = new CountDownLatch(THREADS), start = new CountDownLatch(1), done = new CountDownLatch(THREADS);
        for (int t = 0; t < THREADS; t++) {
            final int tid = t;
            Thread.ofPlatform().start(() -> {
                ready.countDown();
                try {
                    start.await();
                    body.accept(tid);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } finally {
                    done.countDown();
                }
            });
        }
        ready.await();
        long t0 = System.nanoTime();
        start.countDown();
        done.await();
        return (System.nanoTime() - t0) / 1e6;
    }

    record Version(long n) {}

    public static void main(String[] args) throws InterruptedException {
        final int perThread = 250_000, keys = 8;
        final long expected = (long) THREADS * perThread;

        System.out.println("== 1. ConcurrentHashMap: every call is atomic, the sequence is not ==");
        ConcurrentHashMap<Integer, Integer> racy = new ConcurrentHashMap<>();
        parallel(t -> {
            for (int i = 0; i < perThread; i++) {
                int k = i % keys;
                Integer v = racy.get(k);                                  // CHECK
                racy.put(k, v == null ? 1 : v + 1);                       // THEN ACT
            }
        });
        ConcurrentHashMap<Integer, Integer> merged = new ConcurrentHashMap<>();
        parallel(t -> {
            for (int i = 0; i < perThread; i++) merged.merge(i % keys, 1, Integer::sum);  // one atomic step per key
        });
        ConcurrentHashMap<Integer, LongAdder> adders = new ConcurrentHashMap<>();
        parallel(t -> {
            for (int i = 0; i < perThread; i++) adders.computeIfAbsent(i % keys, k -> new LongAdder()).increment();
        });
        long racyTotal = racy.values().stream().mapToLong(Integer::longValue).sum();
        long mergedTotal = merged.values().stream().mapToLong(Integer::longValue).sum();
        long adderTotal = adders.values().stream().mapToLong(LongAdder::sum).sum();
        System.out.printf("get-then-put        total %,9d  lost %,9d%n", racyTotal, expected - racyTotal);
        System.out.printf("merge(k,1,sum)      total %,9d  lost %,9d%n", mergedTotal, expected - mergedTotal);
        System.out.printf("computeIfAbsent+LA  total %,9d  lost %,9d%n", adderTotal, expected - adderTotal);

        System.out.println("== 2. updateAndGet retries its function: it must be pure ==");
        AtomicLong counter = new AtomicLong();
        LongAdder invocations = new LongAdder();
        parallel(t -> {
            for (int i = 0; i < perThread; i++) counter.updateAndGet(x -> {
                invocations.increment();                                    // a side effect: runs once per ATTEMPT
                return x + 1;
            });
        });
        System.out.printf("updates %,d  function invocations %,d  (%.2f per update)%n", counter.get(), invocations.sum(),
                invocations.sum() / (double) counter.get());

        System.out.println("== 3. One hot counter: AtomicLong vs LongAdder (4 threads x 5,000,000) ==");
        AtomicLong hot = new AtomicLong();
        LongAdder striped = new LongAdder();
        double atomicMs = parallel(t -> {
            for (int i = 0; i < 5_000_000; i++) hot.incrementAndGet();
        });
        double adderMs = parallel(t -> {
            for (int i = 0; i < 5_000_000; i++) striped.increment();
        });
        System.out.printf("AtomicLong.incrementAndGet %7.1f ms   LongAdder.increment %7.1f ms   (%.1fx)%n", atomicMs, adderMs, atomicMs / adderMs);

        System.out.println("== 4. compareAndSet compares REFERENCES ==");
        AtomicReference<Long> small = new AtomicReference<>(127L), large = new AtomicReference<>(1000L);
        System.out.println("AtomicReference<Long>(127L).compareAndSet(127L, ...)   -> " + small.compareAndSet(127L, 128L) + "  (Long cache: -128..127)");
        System.out.println("AtomicReference<Long>(1000L).compareAndSet(1000L, ...) -> " + large.compareAndSet(1000L, 1001L) + " (two different Long objects)");
        AtomicReference<Version> ver = new AtomicReference<>(new Version(1));
        System.out.println("CAS(new Version(1) [equal record], ...)                  -> " + ver.compareAndSet(new Version(1), new Version(2)));
        Version seen = ver.get();
        System.out.println("CAS(the instance we read, ...)                           -> " + ver.compareAndSet(seen, new Version(2)));

        System.out.println("== 5. ConcurrentHashMap.compute* must not touch the map recursively ==");
        ConcurrentHashMap<String, Integer> cache = new ConcurrentHashMap<>();
        try {
            cache.computeIfAbsent("fib", k -> cache.computeIfAbsent("fib", k2 -> 1) + 1);
        } catch (IllegalStateException e) {
            System.out.println("nested computeIfAbsent on the same key -> IllegalStateException: " + e.getMessage());
        }

        boolean ok = mergedTotal == expected && adderTotal == expected && counter.get() == expected
                && invocations.sum() >= expected && striped.sum() == 5_000_000L * THREADS && hot.get() == 5_000_000L * THREADS;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**One measured run (JDK 25.0.4.1). The lost count and timings vary; the zero-loss lines and the exception are guaranteed:**

```text
== 1. ConcurrentHashMap: every call is atomic, the sequence is not ==
get-then-put        total   812,540  lost   187,460
merge(k,1,sum)      total 1,000,000  lost         0
computeIfAbsent+LA  total 1,000,000  lost         0
== 2. updateAndGet retries its function: it must be pure ==
updates 1,000,000  function invocations 2,075,292  (2.08 per update)
== 3. One hot counter: AtomicLong vs LongAdder (4 threads x 5,000,000) ==
AtomicLong.incrementAndGet   207.4 ms   LongAdder.increment    58.2 ms   (3.6x)
== 4. compareAndSet compares REFERENCES ==
AtomicReference<Long>(127L).compareAndSet(127L, ...)   -> true  (Long cache: -128..127)
AtomicReference<Long>(1000L).compareAndSet(1000L, ...) -> false (two different Long objects)
CAS(new Version(1) [equal record], ...)                  -> false
CAS(the instance we read, ...)                           -> true
== 5. ConcurrentHashMap.compute* must not touch the map recursively ==
nested computeIfAbsent on the same key -> IllegalStateException: Recursive update
SELF-TEST OK
```

```cpp
// lost_updates.cpp - check-then-act across locked calls, CAS retry counts, striped counters, CAS by bits
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <latch>
#include <limits>
#include <mutex>
#include <new>
#include <optional>
#include <print>
#include <thread>
#include <unordered_map>
#include <vector>

constexpr int kThreads = 4;

double parallel(const std::function<void(int)>& body) {  // returns elapsed ms
    std::latch ready(kThreads), start(1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < kThreads; ++t)
        ts.emplace_back([&, t] {
            ready.count_down();
            start.wait();
            body(t);
        });
    ready.wait();
    const auto t0 = std::chrono::steady_clock::now();
    start.count_down();
    ts.clear();  // join
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

class SyncMap {  // every call locked: "thread-safe"
    mutable std::mutex m_;
    std::unordered_map<int, long> map_;
public:
    std::optional<long> get(int k) const {
        std::scoped_lock l(m_);
        auto it = map_.find(k);
        return it == map_.end() ? std::nullopt : std::optional<long>(it->second);
    }
    void put(int k, long v) {
        std::scoped_lock l(m_);
        map_[k] = v;
    }
    template <class F> void update(int k, F f) {  // the whole read-modify-write under one lock
        std::scoped_lock l(m_);
        auto& v = map_[k];
        v = f(v);
    }
    long total() const {
        std::scoped_lock l(m_);
        long s = 0;
        for (const auto& [k, v] : map_) s += v;
        return s;
    }
};

/** LongAdder's idea: spread one logical counter over cache-line-sized cells; sum on read. */
class StripedCounter {
    struct alignas(64) Cell { std::atomic<long> v{0}; };
    Cell cells_[16];
public:
    void increment(unsigned slot) { cells_[slot & 15].v.fetch_add(1, std::memory_order_relaxed); }
    long sum() const {
        long s = 0;
        for (const auto& c : cells_) s += c.v.load(std::memory_order_relaxed);
        return s;
    }
};

int main() {
    constexpr int per_thread = 250'000, keys = 8;
    constexpr long expected = static_cast<long>(kThreads) * per_thread;

    std::println("== 1. Every call locked, the sequence is not ==");
    SyncMap racy, safe;
    parallel([&](int) {
        for (int i = 0; i < per_thread; ++i) {
            const int k = i % keys;
            const auto v = racy.get(k);       // CHECK
            racy.put(k, v ? *v + 1 : 1);      // THEN ACT
        }
    });
    parallel([&](int) {
        for (int i = 0; i < per_thread; ++i) safe.update(i % keys, [](long v) { return v + 1; });
    });
    std::println("get-then-put      total {:>9}  lost {:>9}", racy.total(), expected - racy.total());
    std::println("update(k, f)      total {:>9}  lost {:>9}", safe.total(), expected - safe.total());

    std::println("== 2. A CAS loop retries under contention ==");
    std::atomic<long> counter{0};
    std::atomic<long> attempts{0};
    parallel([&](int) {
        for (int i = 0; i < per_thread; ++i) {
            long cur = counter.load(std::memory_order_relaxed);
            do {
                attempts.fetch_add(1, std::memory_order_relaxed);  // once per ATTEMPT
            } while (!counter.compare_exchange_weak(cur, cur + 1, std::memory_order_acq_rel, std::memory_order_relaxed));
        }
    });
    std::println("updates {}  CAS attempts {}  ({:.2f} per update)", counter.load(), attempts.load(),
                 static_cast<double>(attempts.load()) / static_cast<double>(counter.load()));

    std::println("== 3. One hot counter: fetch_add vs striped cells (4 threads x 5,000,000) ==");
    std::atomic<long> hot{0};
    StripedCounter striped;
    const double atomic_ms = parallel([&](int) {
        for (int i = 0; i < 5'000'000; ++i) hot.fetch_add(1, std::memory_order_relaxed);
    });
    const double striped_ms = parallel([&](int t) {
        for (int i = 0; i < 5'000'000; ++i) striped.increment(static_cast<unsigned>(t));
    });
    std::println("atomic fetch_add {:7.1f} ms   striped cells {:7.1f} ms   ({:.1f}x)", atomic_ms, striped_ms, atomic_ms / striped_ms);

    std::println("== 4. compare_exchange compares BITS (value representation), not operator== ==");
    std::atomic<double> d{0.0};
    double want = -0.0;  // -0.0 == 0.0 is true...
    std::println("-0.0 == 0.0 -> {};  CAS(expected=-0.0) on stored 0.0 -> {}", -0.0 == 0.0, d.compare_exchange_strong(want, 1.0));
    const double nan = std::numeric_limits<double>::quiet_NaN();
    std::atomic<double> n{nan};
    double want_nan = nan;
    std::println("NaN == NaN -> {};  CAS(expected=NaN) on stored NaN -> {}", nan == nan, n.compare_exchange_strong(want_nan, 1.0));

    const bool ok = safe.total() == expected && counter.load() == expected && attempts.load() >= expected &&
                    hot.load() == 5'000'000L * kThreads && striped.sum() == 5'000'000L * kThreads;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
== 1. Every call locked, the sequence is not ==
get-then-put      total    812365  lost    187635
update(k, f)      total   1000000  lost         0
== 2. A CAS loop retries under contention ==
updates 1000000  CAS attempts 2431744  (2.43 per update)
== 3. One hot counter: fetch_add vs striped cells (4 threads x 5,000,000) ==
atomic fetch_add   201.5 ms   striped cells    24.4 ms   (8.3x)
== 4. compare_exchange compares BITS (value representation), not operator== ==
-0.0 == 0.0 -> true;  CAS(expected=-0.0) on stored 0.0 -> false
NaN == NaN -> false;  CAS(expected=NaN) on stored NaN -> true
SELF-TEST OK
```

**One measured run, Clang 21.1:**

```text
== 1. Every call locked, the sequence is not ==
get-then-put      total    865677  lost    134323
update(k, f)      total   1000000  lost         0
== 2. A CAS loop retries under contention ==
updates 1000000  CAS attempts 1772027  (1.77 per update)
== 3. One hot counter: fetch_add vs striped cells (4 threads x 5,000,000) ==
atomic fetch_add   578.9 ms   striped cells    41.3 ms   (14.0x)
== 4. compare_exchange compares BITS (value representation), not operator== ==
-0.0 == 0.0 -> true;  CAS(expected=-0.0) on stored 0.0 -> false
NaN == NaN -> false;  CAS(expected=NaN) on stored NaN -> true
SELF-TEST OK
```

### 3.3 `LongAdder` / `Striped64`: why it wins, and what it gives up ⚡

`LongAdder` keeps a `base` and, once contention is detected (a failed CAS on `base`), an array of `Cell`s. Each cell is annotated `@jdk.internal.vm.annotation.Contended` so it gets its own cache line. Each thread hashes to a cell by its `ThreadLocalRandom` probe, the array grows up to the number of CPUs, and `increment()` CASes only the thread's own cell. `sum()` adds `base` and all cells. What it gives up:

- **`sum()` isn't an atomic snapshot.** Concurrent increments may or may not be included. It's a statistics counter, not a sequence generator.
- **No `compareAndSet`, no `getAndIncrement`.** You can't build "allocate the next id" from it.
- **Memory.** Up to NCPU padded cells per counter. Fine for one hot counter; wasteful for a million keys.

C++ has no standard `LongAdder`. The `StripedCounter` in Listing 3.2 (16 `alignas(64)` cells indexed by thread) is the whole idea in eight lines.

---

## 4. AQS and the anatomy of a lock

### 4.1 What `AbstractQueuedSynchronizer` gives you

Almost every `java.util.concurrent` synchronizer (`ReentrantLock`, `ReentrantReadWriteLock`, `Semaphore`, `CountDownLatch`, `ThreadPoolExecutor.Worker`) is built on AQS. It's a **template method**: you define what the `int state` means, AQS does the hard part.

| You implement | Meaning |
|---|---|
| `tryAcquire(arg)` / `tryRelease(arg)` | Exclusive mode: try to take or give back ownership via `getState`/`setState`/`compareAndSetState` |
| `tryAcquireShared(arg)` / `tryReleaseShared(arg)` | Shared mode: a negative return means "enqueue me", ≥ 0 means acquired (latches, semaphores, read locks) |
| `isHeldExclusively()` | Needed for `Condition` support |

| AQS provides | How |
|---|---|
| A FIFO wait queue | A variant of the CLH queue (rewritten by Doug Lea in JDK 14): nodes carry a waiter thread and a status; enqueue with CAS on `tail` |
| Blocking | A brief spin while the node is first in the queue, then `LockSupport.park`; the releaser `unpark`s the successor |
| Interruptible and timed acquires | `acquireInterruptibly`, `tryAcquireNanos` |
| Conditions | `ConditionObject`: a separate condition queue; `signal` *transfers* a node to the sync queue, and the waiter must re-acquire before returning from `await` |
| Introspection | `getQueueLength`, `hasQueuedThreads`, `getExclusiveOwnerThread` |

`LockSupport.park`/`unpark` use a **permit**, not a counter: `unpark` before `park` makes the next `park` return immediately. That's why AQS never loses a wake-up between "decide to sleep" and "sleep", the race that hand-rolled `wait`/`notify` code gets wrong.

### 4.2 Barging vs fairness, quantified 🔥

A **non-fair** (barging) lock lets an arriving thread CAS the state *before* queueing, even if others are waiting. The releasing thread, hot in cache, often re-acquires immediately, and the woken thread finds the lock taken and re-parks. Throughput wins; fairness loses. A **fair** lock checks `hasQueuedPredecessors()` and always hands off to the queue head, so *every* release under contention costs an unpark plus a context switch. Listing 3.3 measured the gap:

| Lock (4 threads, tiny critical section) | ns per lock/unlock |
|---|---|
| AQS `Mutex` (barging, ~40 lines) | 24.7 |
| `ReentrantLock` (non-fair) | 29.2 |
| `synchronized` | 34.5 |
| `ReentrantLock(true)` (fair) | **3,966.3**, about 160× slower |

Fair locks are a tool for bounded waiting in rare cases, not a default. Starvation is better addressed at the admission layer: queues, timeouts, rate limits.

### 4.3 Listing 3.3 (Java): a latch, a mutex and a bounded buffer on AQS

```java
// AqsSynchronizers.java - building synchronizers on AbstractQueuedSynchronizer: a latch, a mutex, conditions
import java.util.ArrayDeque;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.AbstractQueuedSynchronizer;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public final class AqsSynchronizers {

    /** JCIP 14.6: state 0 = closed, 1 = open. Shared mode: every waiter passes once it is open. */
    static final class OneShotLatch {
        private static final class Sync extends AbstractQueuedSynchronizer {
            @java.io.Serial private static final long serialVersionUID = 1L;

            @Override protected int tryAcquireShared(int ignored) {
                return getState() == 1 ? 1 : -1;               // >= 0 means "acquired"; -1 means "enqueue me"
            }

            @Override protected boolean tryReleaseShared(int ignored) {
                setState(1);
                return true;                                   // true: wake the queued sharers
            }
        }

        private final Sync sync = new Sync();

        void signal() {
            sync.releaseShared(0);
        }

        void await() throws InterruptedException {
            sync.acquireSharedInterruptibly(0);
        }
    }

    /** Non-reentrant exclusive lock: state 0 = free, 1 = held. AQS supplies queueing, parking, timeouts. */
    static final class Mutex implements Lock {
        private static final class Sync extends AbstractQueuedSynchronizer {
            @java.io.Serial private static final long serialVersionUID = 1L;

            @Override protected boolean tryAcquire(int acquires) {
                if (compareAndSetState(0, 1)) {               // the ONLY CAS on the fast path
                    setExclusiveOwnerThread(Thread.currentThread());
                    return true;
                }
                return false;
            }

            @Override protected boolean tryRelease(int releases) {
                if (getState() == 0 || getExclusiveOwnerThread() != Thread.currentThread())
                    throw new IllegalMonitorStateException();
                setExclusiveOwnerThread(null);
                setState(0);                                   // volatile write: publishes the critical section
                return true;
            }

            @Override protected boolean isHeldExclusively() {
                return getExclusiveOwnerThread() == Thread.currentThread();
            }

            Condition newCondition() {
                return new ConditionObject();
            }
        }

        private final Sync sync = new Sync();

        @Override public void lock() { sync.acquire(1); }
        @Override public void lockInterruptibly() throws InterruptedException { sync.acquireInterruptibly(1); }
        @Override public boolean tryLock() { return sync.tryAcquire(1); }
        @Override public boolean tryLock(long t, TimeUnit u) throws InterruptedException { return sync.tryAcquireNanos(1, u.toNanos(t)); }
        @Override public void unlock() { sync.release(1); }
        @Override public Condition newCondition() { return sync.newCondition(); }
        int queueLength() { return sync.getQueueLength(); }
    }

    /** Two conditions on one lock: the textbook bounded buffer, with while-loops for spurious wakeups. */
    static final class BoundedBuffer {
        private final Lock lock = new Mutex();
        private final Condition notFull = lock.newCondition(), notEmpty = lock.newCondition();
        private final ArrayDeque<Long> items = new ArrayDeque<>();
        private final int capacity;

        BoundedBuffer(int capacity) {
            this.capacity = capacity;
        }

        void put(long v) throws InterruptedException {
            lock.lock();
            try {
                while (items.size() == capacity) notFull.await();   // releases the lock while parked
                items.addLast(v);
                notEmpty.signal();
            } finally {
                lock.unlock();
            }
        }

        long take() throws InterruptedException {
            lock.lock();
            try {
                while (items.isEmpty()) notEmpty.await();
                long v = items.removeFirst();
                notFull.signal();
                return v;
            } finally {
                lock.unlock();
            }
        }
    }

    static long counter;                                       // guarded by whichever lock the benchmark uses

    static double contend(Lock lock, int threads, int perThread) throws InterruptedException {
        counter = 0;
        CountDownLatch start = new CountDownLatch(1);
        Thread[] ts = new Thread[threads];
        for (int t = 0; t < threads; t++) {
            ts[t] = Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                } catch (InterruptedException e) {
                    return;
                }
                for (int i = 0; i < perThread; i++) {
                    lock.lock();
                    try {
                        counter++;
                    } finally {
                        lock.unlock();
                    }
                }
            });
        }
        long t0 = System.nanoTime();
        start.countDown();
        for (Thread t : ts) t.join();
        if (counter != (long) threads * perThread) throw new AssertionError("lost increments: " + counter);
        return (System.nanoTime() - t0) / 1e6;
    }

    static final Object MONITOR = new Object();

    static double contendSynchronized(int threads, int perThread) throws InterruptedException {
        counter = 0;
        CountDownLatch start = new CountDownLatch(1);
        Thread[] ts = new Thread[threads];
        for (int t = 0; t < threads; t++) {
            ts[t] = Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                } catch (InterruptedException e) {
                    return;
                }
                for (int i = 0; i < perThread; i++) {
                    synchronized (MONITOR) {
                        counter++;
                    }
                }
            });
        }
        long t0 = System.nanoTime();
        start.countDown();
        for (Thread t : ts) t.join();
        if (counter != (long) threads * perThread) throw new AssertionError("lost increments");
        return (System.nanoTime() - t0) / 1e6;
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("== Mutex on AQS: correctness + one measured run, 4 threads, ns per lock/unlock ==");
        System.out.printf("Mutex (AQS, barging)   %6.1f ns  (4 x 1,000,000)%n", contend(new Mutex(), 4, 1_000_000) * 1e6 / 4_000_000);
        System.out.printf("ReentrantLock          %6.1f ns  (4 x 1,000,000)%n", contend(new ReentrantLock(), 4, 1_000_000) * 1e6 / 4_000_000);
        System.out.printf("synchronized           %6.1f ns  (4 x 1,000,000)%n", contendSynchronized(4, 1_000_000) * 1e6 / 4_000_000);
        System.out.printf("ReentrantLock(fair)    %6.1f ns  (4 x   100,000: every hand-off parks and unparks)%n",
                contend(new ReentrantLock(true), 4, 100_000) * 1e6 / 400_000);

        System.out.println("== Reentrancy ==");
        Mutex m = new Mutex();
        ReentrantLock r = new ReentrantLock();
        m.lock();
        r.lock();
        System.out.println("owner calls Mutex.tryLock()         -> " + m.tryLock() + " (lock() here would self-deadlock)");
        System.out.println("owner calls ReentrantLock.tryLock() -> " + r.tryLock() + " (hold count " + r.getHoldCount() + ")");
        r.unlock();
        r.unlock();

        System.out.println("== The CLH wait queue, observed ==");
        AtomicInteger acquired = new AtomicInteger();
        Thread[] waiters = new Thread[3];
        for (int i = 0; i < 3; i++) {
            waiters[i] = Thread.ofPlatform().start(() -> {
                m.lock();
                try {
                    acquired.incrementAndGet();
                } finally {
                    m.unlock();
                }
            });
        }
        long deadline = System.nanoTime() + 5_000_000_000L;
        while (m.queueLength() < 3 && System.nanoTime() < deadline) Thread.onSpinWait();
        System.out.println("main holds the Mutex; queued threads = " + m.queueLength() + ", acquired so far = " + acquired.get());
        m.unlock();
        for (Thread w : waiters) w.join();
        System.out.println("after unlock: acquired = " + acquired.get() + ", queued = " + m.queueLength());

        System.out.println("== OneShotLatch (shared mode) ==");
        OneShotLatch latch = new OneShotLatch();
        AtomicInteger passed = new AtomicInteger();
        Thread[] gate = new Thread[3];
        for (int i = 0; i < 3; i++) {
            gate[i] = Thread.ofPlatform().start(() -> {
                try {
                    latch.await();
                    passed.incrementAndGet();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }
        System.out.println("before signal: passed = " + passed.get());
        latch.signal();
        for (Thread g : gate) g.join();
        System.out.println("after signal:  passed = " + passed.get());

        System.out.println("== BoundedBuffer(16) on Mutex + 2 Conditions: 2 producers, 2 consumers, 200,000 items ==");
        BoundedBuffer buf = new BoundedBuffer(16);
        AtomicLong consumedSum = new AtomicLong();
        int items = 200_000;
        Thread[] ps = new Thread[4];
        for (int p = 0; p < 2; p++) {
            final int base = p * items / 2;
            ps[p] = Thread.ofPlatform().start(() -> {
                try {
                    for (int i = 1; i <= items / 2; i++) buf.put(base + i);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }
        for (int c = 2; c < 4; c++) {
            ps[c] = Thread.ofPlatform().start(() -> {
                try {
                    for (int i = 0; i < items / 2; i++) consumedSum.addAndGet(buf.take());
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }
        for (Thread t : ps) t.join();
        long expectedSum = (long) items * (items + 1) / 2;
        System.out.println("consumed sum = " + consumedSum.get() + " (expected " + expectedSum + ")");
        boolean ok = acquired.get() == 3 && passed.get() == 3 && consumedSum.get() == expectedSum;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (timings: one measured run; everything else verified):**

```text
== Mutex on AQS: correctness + one measured run, 4 threads, ns per lock/unlock ==
Mutex (AQS, barging)     24.7 ns  (4 x 1,000,000)
ReentrantLock            29.2 ns  (4 x 1,000,000)
synchronized             34.5 ns  (4 x 1,000,000)
ReentrantLock(fair)    3966.3 ns  (4 x   100,000: every hand-off parks and unparks)
== Reentrancy ==
owner calls Mutex.tryLock()         -> false (lock() here would self-deadlock)
owner calls ReentrantLock.tryLock() -> true (hold count 2)
== The CLH wait queue, observed ==
main holds the Mutex; queued threads = 3, acquired so far = 0
after unlock: acquired = 3, queued = 0
== OneShotLatch (shared mode) ==
before signal: passed = 0
after signal:  passed = 3
== BoundedBuffer(16) on Mutex + 2 Conditions: 2 producers, 2 consumers, 200,000 items ==
consumed sum = 20000100000 (expected 20000100000)
SELF-TEST OK
```

### 4.4 Listing 3.3 (C++): Drepper's futex mutex on `std::atomic::wait`

C++20's `atomic<T>::wait(old)` / `notify_one()` are a portable futex: `wait` sleeps only while the value still equals `old`, which closes the lost-wake-up window the same way AQS's permit does. The three-state mutex from Drepper's *Futexes Are Tricky* uses it as follows:
- **0** = free, **1** = held, **2** = held and possibly contended.
- The fast path is one CAS.
- Only an unlock that sees **2** pays for a `notify`.

The mutex satisfies *BasicLockable*, so `std::condition_variable_any` composes with it to build the same bounded buffer as the Java version.

```cpp
// futex_mutex.cpp - Drepper's three-state mutex and a one-shot latch on C++20 atomic wait/notify
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <latch>
#include <mutex>
#include <print>
#include <stdexcept>
#include <thread>
#include <vector>

/**
 * "Futexes Are Tricky" (Drepper), mutex #2. State 0 = free, 1 = held, 2 = held and maybe contended.
 * atomic::wait/notify are the portable futex: wait(old) sleeps only while the value still equals old.
 */
class FutexMutex {
    std::atomic<int> state_{0};
    std::atomic<std::uint64_t> slow_unlocks_{0};  // instrumentation: unlocks that had to wake someone
public:
    void lock() {
        int c = 0;
        if (state_.compare_exchange_strong(c, 1, std::memory_order_acquire, std::memory_order_relaxed)) return;  // fast path
        if (c != 2) c = state_.exchange(2, std::memory_order_acquire);  // announce contention
        while (c != 0) {
            state_.wait(2, std::memory_order_relaxed);                  // sleeps only if still 2
            c = state_.exchange(2, std::memory_order_acquire);
        }
    }
    bool try_lock() {
        int c = 0;
        return state_.compare_exchange_strong(c, 1, std::memory_order_acquire, std::memory_order_relaxed);
    }
    void unlock() {
        if (state_.exchange(0, std::memory_order_release) == 2) {     // only contended unlocks pay for a wake
            slow_unlocks_.fetch_add(1, std::memory_order_relaxed);
            state_.notify_one();
        }
    }
    std::uint64_t slow_unlocks() const { return slow_unlocks_.load(); }
};

class OneShotLatch {  // closed until signal(); then every waiter passes
    std::atomic<int> open_{0};
public:
    void signal() {
        open_.store(1, std::memory_order_release);
        open_.notify_all();
    }
    void await() {
        while (open_.load(std::memory_order_acquire) == 0) open_.wait(0, std::memory_order_acquire);
    }
};

/** std::condition_variable_any accepts any BasicLockable: the futex mutex composes with it. */
class BoundedBuffer {
    FutexMutex m_;
    std::condition_variable_any not_full_, not_empty_;
    std::deque<std::int64_t> items_;
    std::size_t capacity_;
public:
    explicit BoundedBuffer(std::size_t capacity) : capacity_(capacity) {}
    void put(std::int64_t v) {
        std::unique_lock lock(m_);
        not_full_.wait(lock, [&] { return items_.size() < capacity_; });  // predicate loop: spurious-wakeup safe
        items_.push_back(v);
        not_empty_.notify_one();
    }
    std::int64_t take() {
        std::unique_lock lock(m_);
        not_empty_.wait(lock, [&] { return !items_.empty(); });
        const std::int64_t v = items_.front();
        items_.pop_front();
        not_full_.notify_one();
        return v;
    }
};

std::int64_t g_counter = 0;  // guarded by the lock under test (not long: 32-bit on Windows)

template <class Lock>
double contend(Lock& lock, int threads, int per_thread) {
    g_counter = 0;
    std::latch start(1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&] {
            start.wait();
            for (int i = 0; i < per_thread; ++i) {
                std::scoped_lock g(lock);
                ++g_counter;
            }
        });
    const auto t0 = std::chrono::steady_clock::now();
    start.count_down();
    ts.clear();
    if (g_counter != static_cast<std::int64_t>(threads) * per_thread) throw std::logic_error("lost increments");
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

int main() {
    std::println("== FutexMutex: correctness + one measured run (4 threads x 1,000,000) ==");
    FutexMutex fm;
    std::mutex sm;
    const double fm_ms = contend(fm, 4, 1'000'000);
    std::println("FutexMutex  {:7.1f} ms   contended unlocks that called notify: {} of 4000000", fm_ms, fm.slow_unlocks());
    std::println("std::mutex  {:7.1f} ms", contend(sm, 4, 1'000'000));
    FutexMutex solo;
    const double solo_ms = contend(solo, 1, 4'000'000);
    std::println("FutexMutex, 1 thread x 4,000,000: {:.1f} ms, notify calls: {} (fast path only)", solo_ms, solo.slow_unlocks());

    std::println("== Reentrancy ==");
    fm.lock();
    std::println("owner calls FutexMutex::try_lock() -> {} (std::mutex: undefined behaviour; use std::recursive_mutex)", fm.try_lock());
    fm.unlock();

    std::println("== OneShotLatch ==");
    OneShotLatch latch;
    std::atomic<int> passed{0};
    {
        std::vector<std::jthread> gate;
        for (int i = 0; i < 3; ++i)
            gate.emplace_back([&] {
                latch.await();
                passed.fetch_add(1);
            });
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        std::println("before signal: passed = {}", passed.load());
        latch.signal();
    }
    std::println("after signal:  passed = {}", passed.load());

    std::println("== BoundedBuffer(16) on FutexMutex + condition_variable_any: 2 producers, 2 consumers, 200,000 items ==");
    BoundedBuffer buf(16);
    std::atomic<std::int64_t> sum{0};
    constexpr std::int64_t kItems = 200'000;  // long is 32-bit on Windows: kItems*(kItems+1) overflows it
    {
        std::vector<std::jthread> ts;
        for (std::int64_t p = 0; p < 2; ++p)
            ts.emplace_back([&, base = p * kItems / 2] {
                for (std::int64_t i = 1; i <= kItems / 2; ++i) buf.put(base + i);
            });
        for (int c = 0; c < 2; ++c)
            ts.emplace_back([&] {
                for (std::int64_t i = 0; i < kItems / 2; ++i) sum.fetch_add(buf.take());
            });
    }
    const std::int64_t expected = kItems * (kItems + 1) / 2;
    std::println("consumed sum = {} (expected {})", sum.load(), expected);
    const bool ok = passed.load() == 3 && sum.load() == expected && solo.slow_unlocks() == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
== FutexMutex: correctness + one measured run (4 threads x 1,000,000) ==
FutexMutex    249.1 ms   contended unlocks that called notify: 1026125 of 4000000
std::mutex    121.4 ms
FutexMutex, 1 thread x 4,000,000: 39.8 ms, notify calls: 0 (fast path only)
== Reentrancy ==
owner calls FutexMutex::try_lock() -> false (std::mutex: undefined behaviour; use std::recursive_mutex)
== OneShotLatch ==
before signal: passed = 0
after signal:  passed = 3
== BoundedBuffer(16) on FutexMutex + condition_variable_any: 2 producers, 2 consumers, 200,000 items ==
consumed sum = 20000100000 (expected 20000100000)
SELF-TEST OK
```

**One measured run, Clang 21.1:**

```text
== FutexMutex: correctness + one measured run (4 threads x 1,000,000) ==
FutexMutex    340.7 ms   contended unlocks that called notify: 2075551 of 4000000
std::mutex     90.7 ms
FutexMutex, 1 thread x 4,000,000: 40.3 ms, notify calls: 0 (fast path only)
== Reentrancy ==
owner calls FutexMutex::try_lock() -> false (std::mutex: undefined behaviour; use std::recursive_mutex)
== OneShotLatch ==
before signal: passed = 0
after signal:  passed = 3
== BoundedBuffer(16) on FutexMutex + condition_variable_any: 2 producers, 2 consumers, 200,000 items ==
consumed sum = 20000100000 (expected 20000100000)
SELF-TEST OK
```

Reading the C++ numbers honestly:

- **The textbook futex mutex is 2–5× *slower* than `std::mutex` under contention**: 249 vs 121 ms with GCC, 341 vs 91 ms with Clang in the run shown (279 vs 113 and 532 vs 102 on a rerun). It goes to sleep on the first conflict. Production mutexes, AQS included, **spin briefly before parking**, because most critical sections finish faster than a sleep/wake round trip. A quarter to three quarters of all unlocks (1.0–3.2 M of 4 M across runs) had to notify, and each one is a kernel transition.
- **Uncontended, it never enters the kernel:** 4 M lock/unlock pairs on one thread made 0 notify calls. That's the property that makes futex-style locks cheap in the common case.
- **Reentrancy:** the owner's `try_lock` returns `false`. Calling `try_lock` on a `std::mutex` you already own is *undefined behaviour*, which is why the listing uses its own type for the demonstration.

### 4.5 `synchronized` in modern HotSpot ⚠

- **Biased locking is gone.** It was deprecated in JDK 15 (JEP 374) and removed in later releases. Uncontended `synchronized` is a CAS on the object's header.
- **Contention inflates the lock** to an `ObjectMonitor`, which spins adaptively before blocking.
- **JDK 24 (JEP 491):** a virtual thread blocked in or on `synchronized` no longer pins its carrier thread. The old advice "replace `synchronized` with `ReentrantLock` for virtual threads" applies only to JDK 21–23.
- **Use `synchronized` when:** you need neither `tryLock`, timeouts, interruptible acquisition nor multiple conditions; scope-bound release is automatic. **Use `ReentrantLock` when** you need any of those. **Use `StampedLock`** for read-mostly data where optimistic reads pay off (§5).

---
## 5. Read-mostly data: RW locks, StampedLock, seqlocks

### 5.1 Why a read-write lock is often *slower* than a mutex 🔥

A reader-writer lock lets readers proceed in parallel, but **every read acquisition still writes the lock's shared state** (the reader count). Three readers hammering one `ReentrantReadWriteLock` bounce that cache line between cores exactly as a mutex would. RRWL adds hold-count bookkeeping on top: per-thread counters behind a `ThreadLocal`, with a one-entry cache. RW locks pay off only when the read-side critical section is long enough to amortize the shared write. Listing 3.4 shows the short-section case.

**StampedLock's optimistic read writes nothing.** `tryOptimisticRead()` returns the current version. The reader copies the fields into locals, then calls `validate(stamp)`, which issues an acquire fence and compares the version. If a writer intervened, the reader falls back to a real read lock. Readers never write shared memory, so they scale with cores.

### 5.2 The semantics that bite in interviews

| Lock | Reentrant | Upgrade read→write | Downgrade write→read | Conditions | Notes |
|---|---|---|---|---|---|
| `ReentrantReadWriteLock` | yes | **no**: `writeLock().lock()` while holding a read lock deadlocks; `tryLock()` returns `false` (verified) | **yes**: take read while holding write, then release write (verified) | write lock only | Non-fair mode blocks new readers if the queue head is a writer, which mitigates writer starvation |
| `StampedLock` | **no** (holding read, `tryWriteLock()` returns 0: verified) | `tryConvertToWriteLock(stamp)`, which succeeds when the caller is the sole reader (verified) | `tryConvertToReadLock` | none | Optimistic reads; stamps aren't owner-bound; never call user code while holding it |
| `std::shared_mutex` | no | no | no | via `condition_variable_any` | Fairness and writer preference are implementation-defined |
| Seqlock (C++, hand-rolled) | n/a | n/a | n/a | n/a | Readers retry; writers must be serialized; **data must be atomic** (§5.4) |

### 5.3 Listing 3.4 (Java)

```java
// ReadMostlyLocks.java - synchronized vs ReentrantReadWriteLock vs StampedLock optimistic reads
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.concurrent.locks.StampedLock;

public final class ReadMostlyLocks {

    /** Invariant kept by every writer: x + y == 0. A reader that sees x + y != 0 saw a torn state. */
    interface Point {
        void set(long v);
        long[] read();
    }

    static final class SyncPoint implements Point {
        private long x, y;
        @Override public synchronized void set(long v) { x = v; y = -v; }
        @Override public synchronized long[] read() { return new long[] {x, y}; }
    }

    static final class RwPoint implements Point {
        private final ReentrantReadWriteLock rw = new ReentrantReadWriteLock();
        private long x, y;

        @Override public void set(long v) {
            rw.writeLock().lock();
            try { x = v; y = -v; } finally { rw.writeLock().unlock(); }
        }

        @Override public long[] read() {
            rw.readLock().lock();                         // still a CAS on shared state per read
            try { return new long[] {x, y}; } finally { rw.readLock().unlock(); }
        }
    }

    static final class StampedPoint implements Point {
        private final StampedLock sl = new StampedLock();
        private long x, y;
        final LongAdder optimisticHits = new LongAdder(), fallbacks = new LongAdder(), tornButCaught = new LongAdder();

        @Override public void set(long v) {
            long stamp = sl.writeLock();
            try { x = v; y = -v; } finally { sl.unlockWrite(stamp); }
        }

        @Override public long[] read() {
            long stamp = sl.tryOptimisticRead();          // no write to shared memory at all
            long cx = x, cy = y;                          // copy into locals FIRST ...
            if (sl.validate(stamp)) {                     // ... then validate (it contains an acquire fence)
                optimisticHits.increment();
                return new long[] {cx, cy};
            }
            if (cx + cy != 0) tornButCaught.increment();  // we did read garbage; validate() caught it
            fallbacks.increment();
            stamp = sl.readLock();
            try { return new long[] {x, y}; } finally { sl.unlockRead(stamp); }
        }
    }

    record Result(double readsPerSec, long writes, long torn) {}

    static Result run(Point p, int readers, long millis) throws InterruptedException {
        AtomicBoolean stop = new AtomicBoolean();
        LongAdder reads = new LongAdder(), torn = new LongAdder(), writes = new LongAdder();
        Thread writer = Thread.ofPlatform().start(() -> {
            long v = 0;
            while (!stop.get()) {
                p.set(++v);
                writes.increment();
                for (int k = 0; k < 200; k++) Thread.onSpinWait();   // ~1 write per few microseconds
            }
        });
        Thread[] rs = new Thread[readers];
        for (int i = 0; i < readers; i++) {
            rs[i] = Thread.ofPlatform().start(() -> {
                long n = 0, bad = 0;
                while (!stop.get()) {
                    long[] xy = p.read();
                    if (xy[0] + xy[1] != 0) bad++;
                    n++;
                }
                reads.add(n);
                torn.add(bad);
            });
        }
        Thread.sleep(millis);
        stop.set(true);
        writer.join();
        for (Thread r : rs) r.join();
        return new Result(reads.sum() * 1000.0 / millis, writes.sum(), torn.sum());
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("== 3 readers + 1 writer for 400 ms each (one measured run) ==");
        long totalTorn = 0;
        for (Point p : new Point[] {new SyncPoint(), new RwPoint(), new StampedPoint()}) {
            run(p, 3, 150);                               // warm-up
            Result r = run(p, 3, 400);
            totalTorn += r.torn();
            System.out.printf("%-13s reads %7.1f M/s   writes %,9d   torn reads returned %d%n",
                    p.getClass().getSimpleName(), r.readsPerSec() / 1e6, r.writes(), r.torn());
            if (p instanceof StampedPoint s)
                System.out.printf("              optimistic hits %,d   fallbacks to readLock %,d   torn copies caught by validate %,d%n",
                        s.optimisticHits.sum(), s.fallbacks.sum(), s.tornButCaught.sum());
        }

        System.out.println("== Semantics that bite ==");
        ReentrantReadWriteLock rw = new ReentrantReadWriteLock();
        rw.readLock().lock();
        System.out.println("RRWL: holding read, writeLock().tryLock() -> " + rw.writeLock().tryLock() + " (no upgrade: lock() would deadlock)");
        rw.readLock().unlock();
        rw.writeLock().lock();
        rw.readLock().lock();                             // downgrade: allowed
        rw.writeLock().unlock();
        System.out.println("RRWL: write -> read downgrade, now read-held = " + (rw.getReadLockCount() == 1) + ", write-held = " + rw.isWriteLocked());
        rw.readLock().unlock();

        StampedLock sl = new StampedLock();
        long rs = sl.readLock();
        System.out.println("StampedLock: holding read, tryWriteLock() -> " + sl.tryWriteLock() + " (0 = failed; not reentrant)");
        long ws = sl.tryConvertToWriteLock(rs);
        System.out.println("StampedLock: tryConvertToWriteLock(sole reader) -> " + (ws != 0 ? "converted" : "failed")
                + ", isWriteLocked = " + sl.isWriteLocked());
        sl.unlockWrite(ws);

        System.out.println(totalTorn == 0 ? "SELF-TEST OK: no torn state ever returned" : "SELF-TEST FAILED");
        if (totalTorn != 0) System.exit(1);
    }
}
```

**One measured run (JDK 25.0.4.1). Throughput varies; "torn reads returned 0" is guaranteed:**

```text
== 3 readers + 1 writer for 400 ms each (one measured run) ==
SyncPoint     reads    18.7 M/s   writes    44,731   torn reads returned 0
RwPoint       reads    12.0 M/s   writes    25,853   torn reads returned 0
StampedPoint  reads   248.4 M/s   writes    45,616   torn reads returned 0
              optimistic hits 129,896,345   fallbacks to readLock 140,987   torn copies caught by validate 640
== Semantics that bite ==
RRWL: holding read, writeLock().tryLock() -> false (no upgrade: lock() would deadlock)
RRWL: write -> read downgrade, now read-held = true, write-held = false
StampedLock: holding read, tryWriteLock() -> 0 (0 = failed; not reentrant)
StampedLock: tryConvertToWriteLock(sole reader) -> converted, isWriteLocked = true
SELF-TEST OK: no torn state ever returned
```

### 5.4 Listing 3.4 (C++): a seqlock that is race-free under the C++ model 🧊

A seqlock is StampedLock's optimistic read in its rawest form:
- The writer makes the sequence odd, writes the data, then makes the sequence even.
- A reader reads the sequence, reads the data, and re-reads the sequence. It accepts only an unchanged, even value.

**In C++, the data fields must be `std::atomic` (relaxed is enough).** A plain field read while a writer stores to it is a data race and therefore UB, *even if the reader would discard the value*. Java's `StampedLock` may read plain fields because a racy read in Java returns *some* value rather than licensing the compiler to do anything. The fence placement follows Boehm's 2012 analysis:
- **Writer:** release fence *after* the odd store, so the odd sequence is ordered before the data stores.
- **Reader:** acquire fence *before* re-reading the sequence, so the data loads are ordered before the re-check.

```cpp
// seqlock_vs_shared_mutex.cpp - std::mutex vs std::shared_mutex vs a race-free seqlock (Boehm 2012)
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <print>
#include <shared_mutex>
#include <thread>
#include <utility>
#include <vector>

using Pair = std::pair<std::int64_t, std::int64_t>;  // invariant kept by every writer: first + second == 0

inline void cpu_relax() {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#else
    std::this_thread::yield();
#endif
}

class MutexPoint {
    mutable std::mutex m_;
    std::int64_t x_ = 0, y_ = 0;
public:
    void set(std::int64_t v) { std::scoped_lock l(m_); x_ = v; y_ = -v; }
    Pair read() const { std::scoped_lock l(m_); return {x_, y_}; }
};

class SharedMutexPoint {
    mutable std::shared_mutex m_;
    std::int64_t x_ = 0, y_ = 0;
public:
    void set(std::int64_t v) { std::unique_lock l(m_); x_ = v; y_ = -v; }
    Pair read() const { std::shared_lock l(m_); return {x_, y_}; }  // readers still write the lock word
};

/**
 * Seqlock. In C++ the protected data must itself be atomic (relaxed is enough): a plain field read
 * while a writer stores to it is a data race, i.e. undefined behaviour, even if the reader discards it.
 * Java's StampedLock may read plain fields because the JMM gives racy reads defined (if useless) values.
 */
class SeqLockPoint {
    std::atomic<std::uint64_t> seq_{0};
    std::atomic<std::int64_t> x_{0}, y_{0};
    std::mutex writers_;  // seqlocks need serialised writers
public:
    mutable std::atomic<std::uint64_t> retries{0};
    void set(std::int64_t v) {
        std::scoped_lock l(writers_);
        const auto s = seq_.load(std::memory_order_relaxed);
        seq_.store(s + 1, std::memory_order_relaxed);         // odd: write in progress
        std::atomic_thread_fence(std::memory_order_release);  // orders the odd seq before the data stores
        x_.store(v, std::memory_order_relaxed);
        y_.store(-v, std::memory_order_relaxed);
        seq_.store(s + 2, std::memory_order_release);         // even: publish
    }
    Pair read() const {
        while (true) {
            const auto s0 = seq_.load(std::memory_order_acquire);
            if (s0 & 1) {
                retries.fetch_add(1, std::memory_order_relaxed);
                cpu_relax();
                continue;
            }
            const auto x = x_.load(std::memory_order_relaxed), y = y_.load(std::memory_order_relaxed);
            std::atomic_thread_fence(std::memory_order_acquire);  // orders the data loads before the re-check
            if (seq_.load(std::memory_order_relaxed) == s0) return {x, y};
            retries.fetch_add(1, std::memory_order_relaxed);
        }
    }
};

struct Result { double reads_per_sec; std::uint64_t writes, torn; };

template <class P>
Result run(P& p, int readers, std::chrono::milliseconds dur) {
    std::atomic<bool> stop{false};
    std::atomic<std::uint64_t> reads{0}, torn{0}, writes{0};
    {
        std::vector<std::jthread> ts;
        ts.emplace_back([&] {
            std::int64_t v = 0;
            while (!stop.load(std::memory_order_relaxed)) {
                p.set(++v);
                writes.fetch_add(1, std::memory_order_relaxed);
                for (int k = 0; k < 200; ++k) cpu_relax();
            }
        });
        for (int i = 0; i < readers; ++i)
            ts.emplace_back([&] {
                std::uint64_t n = 0, bad = 0;
                while (!stop.load(std::memory_order_relaxed)) {
                    const auto [x, y] = p.read();
                    bad += (x + y != 0);
                    ++n;
                }
                reads.fetch_add(n);
                torn.fetch_add(bad);
            });
        std::this_thread::sleep_for(dur);
        stop.store(true);
    }
    return {static_cast<double>(reads.load()) * 1000.0 / static_cast<double>(dur.count()), writes.load(), torn.load()};
}

int main() {
    using namespace std::chrono_literals;
    std::println("== 3 readers + 1 writer for 400 ms each (one measured run) ==");
    std::uint64_t total_torn = 0;
    auto report = [&](const char* name, auto& p) {
        run(p, 3, 150ms);  // warm-up
        const auto r = run(p, 3, 400ms);
        total_torn += r.torn;
        std::println("{:<17} reads {:7.1f} M/s   writes {:>9}   torn reads returned {}", name, r.reads_per_sec / 1e6, r.writes, r.torn);
    };
    MutexPoint mp;
    SharedMutexPoint sp;
    SeqLockPoint qp;
    report("std::mutex", mp);
    report("std::shared_mutex", sp);
    report("seqlock", qp);
    std::println("                  seqlock reader retries (odd seq or changed seq): {}", qp.retries.load());
    std::println("{}", total_torn == 0 ? "SELF-TEST OK: no torn state ever returned" : "SELF-TEST FAILED");
    return total_torn == 0 ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
== 3 readers + 1 writer for 400 ms each (one measured run) ==
std::mutex        reads    21.4 M/s   writes     42038   torn reads returned 0
std::shared_mutex reads     2.7 M/s   writes     32757   torn reads returned 0
seqlock           reads  2734.0 M/s   writes     46698   torn reads returned 0
                  seqlock reader retries (odd seq or changed seq): 103707
SELF-TEST OK: no torn state ever returned
```

**One measured run, Clang 21.1:**

```text
== 3 readers + 1 writer for 400 ms each (one measured run) ==
std::mutex        reads    33.2 M/s   writes     40262   torn reads returned 0
std::shared_mutex reads     9.7 M/s   writes     41887   torn reads returned 0
seqlock           reads  2352.5 M/s   writes     52924   torn reads returned 0
                  seqlock reader retries (odd seq or changed seq): 46582
SELF-TEST OK: no torn state ever returned
```

### 5.5 Reading the read-mostly numbers ⚡

| Mechanism | Reads/s with 3 readers + 1 writer (range over two runs, both compilers) | Why |
|---|---|---|
| `synchronized` / `std::mutex` | 16–19 M (Java), 21–35 M (C++) | one lock word; readers serialize |
| `ReentrantReadWriteLock` / `std::shared_mutex` | 12.0–12.5 M (Java), 2.6–12.8 M (C++) | readers *write* the shared count, so the cache line ping-pongs. Slower than a mutex for short sections |
| `StampedLock` optimistic | **248.4 M** | readers write nothing; 99.9% optimistic hits (129.9 M; the counters include the 150 ms warm-up), 141 k fallbacks, and **640 torn copies caught by `validate()`** before they could be returned |
| Seqlock (C++) | **2.0–2.7 G** | the same idea without allocation or a fallback lock; retries 47–104 k |

The 640 caught torn copies are the most important number in the table. Optimistic reads *do* see inconsistent state, routinely. Correctness comes entirely from copying into locals and calling `validate` **before using** the values. Never dereference, index or branch on optimistically read data before validating, because a torn index can throw before you get the chance.

The L7 alternative for small read-mostly values is often simpler than any lock: an **immutable snapshot behind a `volatile`/`AtomicReference`** (copy-on-write). Readers do one acquire load; writers build a new object and publish it. This is how configuration, routing tables and the price ladder snapshot in P12 should be shared.

---

## 6. Lock striping and deterministic lock ordering

### 6.1 `ConcurrentHashMap` internals (JDK 8+) 🔥

The JDK 7 "segments" design is gone. The modern map uses a few distinct mechanisms:

| Operation | Mechanism |
|---|---|
| `get` | Lock-free: volatile reads of the bin array (`tabAt`), then a walk of the immutable-ish chain |
| `put` into an **empty bin** | Lock-free: `casTabAt` installs the first node |
| `put` into an occupied bin | `synchronized` on the **first node of that bin**: per-bin locking, so the lock count scales with the table |
| Long chains | A bin with ≥ 8 nodes treeifies (if the table is ≥ 64), bounding the worst case at O(log n) |
| `compute`/`computeIfAbsent`/`merge` | Hold the **bin lock while the function runs** (a `ReservationNode` for an empty bin). Recursion into the same bin throws `IllegalStateException: Recursive update` (verified in 3.2) |
| Resize | Incremental: `ForwardingNode`s mark moved bins, and writers *help* transfer |
| `size()` | `baseCount` plus `CounterCell[]`, the `LongAdder` design again |

Listing 3.5 measures the bin-lock consequence directly. In a default (16-bin) map, keys `0` and `16` share bin 0. While one thread runs a 200 ms `compute(0, …)`, `compute(16, …)` waited **200.5 ms** and `compute(1, …)` waited **0.4 ms**. A slow or remote call inside `compute` is a hidden lock on unrelated keys.

### 6.2 Striped locks (Guava's `Striped`, and building your own)

When the key space is unbounded (seat ids, user ids, account numbers) but contention is local, map keys onto a **fixed pool** of locks:
- **The index:** `stripe = spread(hash(key)) & (n − 1)`.
- **Memory is bounded and lock objects aren't churned.** The cost is false contention between unrelated keys that share a stripe: in the run, the busiest of 16 stripes guarded 10 of 100 seat keys.
- **Multi-key operations go through `bulkGet(keys)`.** It returns the stripes **sorted by index and de-duplicated** (Guava's documented contract), which gives a consistent global order and never locks the same stripe twice.
- **Pad the stripes.** Guava's eager `Striped.lock(n)` pads its locks to avoid false sharing ⚠. The C++ version uses `alignas(64)` stripes (verified `sizeof` = 64 B).

### 6.3 Four cures for lock-order deadlock, compared

| Cure | How | Cost | Use when |
|---|---|---|---|
| **Natural total order** | Lock by ascending id (seat, account) | none | Entities have stable comparable ids: almost always |
| **`identityHashCode` + tie lock** (JCIP 10.3) | Order by identity hash; on a collision take a global tie-breaking lock first | rare global serialization | Objects have no natural key |
| **`std::scoped_lock(a, b)` / `std::lock`** | Lock one, `try_lock` the others, back off and retry in another order | retries under contention | C++, a small fixed set of mutexes known at the call site |
| **`tryLock` with timeout + randomized backoff** | Give up and retry instead of waiting forever | retries; possible livelock without jitter (107 backoffs in the run) | Lock order unknowable up front; lock-coupling isn't possible |

When the resources aren't known up front (walking a tree, following references), none of the ordering cures apply directly. Use **lock coupling** (hand-over-hand in a fixed direction, as in P18's file system) or optimistic validation.

### 6.4 Listing 3.5 (Java)

```java
// OrderedLocking.java - deadlock by lock order, three cures, lock striping, and ConcurrentHashMap's per-bin locks
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.SplittableRandom;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.LockSupport;
import java.util.concurrent.locks.ReentrantLock;

public final class OrderedLocking {

    static final class Account {
        final long id;
        long balanceCents;                            // guarded by lock (or by this monitor in variant 3)
        final ReentrantLock lock = new ReentrantLock();

        Account(long id, long balanceCents) {
            this.id = id;
            this.balanceCents = balanceCents;
        }
    }

    interface Transfer {
        boolean apply(Account from, Account to, long cents) throws InterruptedException;
    }

    static boolean move(Account from, Account to, long cents) {
        if (from.balanceCents < cents) return false;  // checked while BOTH locks are held
        from.balanceCents -= cents;
        to.balanceCents += cents;
        return true;
    }

    /** Variant 0: lock `from` then `to`. A->B racing B->A deadlocks. */
    static final Transfer NAIVE = (from, to, cents) -> {
        from.lock.lock();
        try {
            to.lock.lock();
            try { return move(from, to, cents); } finally { to.lock.unlock(); }
        } finally {
            from.lock.unlock();
        }
    };

    /** Cure 1: one global order -- the smaller id is always locked first. */
    static final Transfer ORDERED = (from, to, cents) -> {
        Account first = from.id < to.id ? from : to, second = first == from ? to : from;
        first.lock.lock();
        try {
            second.lock.lock();
            try { return move(from, to, cents); } finally { second.lock.unlock(); }
        } finally {
            first.lock.unlock();
        }
    };

    /** Cure 2 (JCIP 10.3): no natural key -> identityHashCode order, plus a tie-breaking lock for collisions. */
    static final Object TIE_LOCK = new Object();
    static final Transfer IDENTITY_ORDERED = (from, to, cents) -> {
        int fh = System.identityHashCode(from), th = System.identityHashCode(to);
        if (fh < th) {
            synchronized (from) { synchronized (to) { return move(from, to, cents); } }
        } else if (fh > th) {
            synchronized (to) { synchronized (from) { return move(from, to, cents); } }
        } else {
            synchronized (TIE_LOCK) { synchronized (from) { synchronized (to) { return move(from, to, cents); } } }
        }
    };

    /** Cure 3: tryLock with a timeout + randomized backoff. No deadlock; retries are the price. */
    static final AtomicLong BACKOFFS = new AtomicLong();
    static final Transfer TRY_LOCK = (from, to, cents) -> {
        while (true) {
            if (from.lock.tryLock(1, TimeUnit.MILLISECONDS)) {
                try {
                    if (to.lock.tryLock(1, TimeUnit.MILLISECONDS)) {
                        try { return move(from, to, cents); } finally { to.lock.unlock(); }
                    }
                } finally {
                    from.lock.unlock();
                }
            }
            BACKOFFS.incrementAndGet();
            LockSupport.parkNanos(ThreadLocalRandom.current().nextLong(1_000, 50_000));  // break the symmetry
        }
    };

    static String deadlockGraph() {
        var mx = ManagementFactory.getThreadMXBean();
        long[] ids = mx.findDeadlockedThreads();
        if (ids == null) return "stalled, no cycle";
        List<String> edges = new ArrayList<>();
        for (ThreadInfo ti : mx.getThreadInfo(ids)) edges.add(ti.getThreadName() + " -> " + ti.getLockOwnerName());
        edges.sort(null);
        return String.join(", ", edges);
    }

    /** 4 threads x N random transfers over 8 accounts; the sum of balances is the invariant. */
    static String stress(String name, Transfer t, int perThread) throws InterruptedException {
        Account[] accts = new Account[8];
        for (int i = 0; i < accts.length; i++) accts[i] = new Account(i, 1_000_00);
        AtomicLong done = new AtomicLong();
        CountDownLatch start = new CountDownLatch(1);
        for (int w = 0; w < 4; w++) {
            final int seed = w;
            Thread.ofPlatform().daemon().name(name + "-" + w).start(() -> {
                SplittableRandom rnd = new SplittableRandom(seed);
                try {
                    start.await();
                    for (int i = 0; i < perThread; i++) {
                        int a = rnd.nextInt(8), b = (a + 1 + rnd.nextInt(7)) % 8;
                        t.apply(accts[a], accts[b], rnd.nextInt(1, 5_000));
                        done.incrementAndGet();
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }
        start.countDown();
        long total = 4L * perThread, last = -1, stalledSince = System.nanoTime();
        while (done.get() < total) {
            long now = done.get();
            if (now != last) {
                last = now;
                stalledSince = System.nanoTime();
            } else if (System.nanoTime() - stalledSince > 2_000_000_000L) {
                return String.format("%-17s DEADLOCK after %,d transfers: %s", name, now, deadlockGraph());
            }
            Thread.sleep(5);
        }
        long sum = 0;
        for (Account a : accts) sum += a.balanceCents;
        return String.format("%-17s %,d transfers, sum of balances %,d (expected %,d)%s", name, total, sum, 8 * 1_000_00L,
                sum == 8 * 1_000_00L ? "" : "  <-- BROKEN");
    }

    /** Guava-style striping: a fixed pool of locks; multi-key ops lock sorted, de-duplicated stripes. */
    static final class Striped {
        private final ReentrantLock[] locks;

        Striped(int stripes) {
            if (Integer.bitCount(stripes) != 1) throw new IllegalArgumentException("power of two");
            locks = new ReentrantLock[stripes];
            for (int i = 0; i < stripes; i++) locks[i] = new ReentrantLock();
        }

        int indexFor(Object key) {
            int h = key.hashCode();
            h ^= h >>> 16;                            // spread high bits, like HashMap
            return h & (locks.length - 1);
        }

        /** Same contract as Guava's Striped.bulkGet: a consistent order across all callers. */
        List<ReentrantLock> bulkGet(Collection<?> keys) {
            return keys.stream().mapToInt(this::indexFor).sorted().distinct().mapToObj(i -> locks[i]).toList();
        }
    }

    public static void main(String[] args) throws InterruptedException {
        System.out.println("== Opposite-order transfers, 4 threads x 200,000 ==");
        System.out.println(stress("naive", NAIVE, 200_000));
        boolean curesOk = true;
        for (String line : List.of(stress("ordered-by-id", ORDERED, 200_000),
                stress("identity+tie-lock", IDENTITY_ORDERED, 200_000), stress("tryLock+backoff", TRY_LOCK, 200_000))) {
            System.out.println(line);
            curesOk &= !line.contains("DEADLOCK") && !line.contains("BROKEN");
        }
        System.out.printf("                  tryLock backoffs: %,d%n", BACKOFFS.get());
        if (!curesOk) throw new AssertionError("a cure failed");

        System.out.println("== Lock striping ==");
        Striped striped = new Striped(16);
        int[] perStripe = new int[16];
        for (int s = 1; s <= 100; s++) perStripe[striped.indexFor("seat-" + s)]++;
        int busiest = 0;
        for (int c : perStripe) busiest = Math.max(busiest, c);
        System.out.println("100 seat keys over 16 stripes: busiest stripe guards " + busiest + " keys");
        String a = null, b = null;
        outer:
        for (int i = 1; i <= 100; i++)
            for (int j = i + 1; j <= 100; j++)
                if (striped.indexFor("seat-" + i) == striped.indexFor("seat-" + j)) {
                    a = "seat-" + i;
                    b = "seat-" + j;
                    break outer;
                }
        System.out.println("bulkGet([" + a + ", " + b + "]) -> " + striped.bulkGet(List.of(a, b)).size()
                + " lock (same stripe: de-duplicated, so a non-reentrant lock would not self-deadlock)");
        System.out.println("bulkGet([seat-9, seat-1]) == bulkGet([seat-1, seat-9]) -> "
                + striped.bulkGet(List.of("seat-9", "seat-1")).equals(striped.bulkGet(List.of("seat-1", "seat-9"))));

        System.out.println("== ConcurrentHashMap locks per BIN: a slow compute() blocks its bin-mates ==");
        ConcurrentHashMap<Integer, Integer> map = new ConcurrentHashMap<>();   // 16 bins once initialised
        map.put(0, 0);
        CountDownLatch holding = new CountDownLatch(1);
        Thread slow = Thread.ofPlatform().start(() -> map.compute(0, (k, v) -> {
            holding.countDown();
            LockSupport.parkNanos(200_000_000L);      // 200 ms "remote call" inside compute: the anti-pattern
            return v + 1;
        }));
        holding.await();
        long t0 = System.nanoTime();
        map.compute(1, (k, v) -> 1);                   // bin 1
        long other = System.nanoTime() - t0;
        t0 = System.nanoTime();
        map.compute(16, (k, v) -> 1);                  // 16 & 15 == 0: same bin as key 0
        long sameBin = System.nanoTime() - t0;
        slow.join();
        System.out.printf("compute(1)  [different bin] waited %6.1f ms%n", other / 1e6);
        System.out.printf("compute(16) [same bin as 0] waited %6.1f ms%n", sameBin / 1e6);
        System.out.println("SELF-TEST OK");
    }
}
```

**One measured run (JDK 25.0.4.1). The deadlock point and backoff count vary; the conserved sums are guaranteed:**

```text
== Opposite-order transfers, 4 threads x 200,000 ==
naive             DEADLOCK after 57 transfers: naive-0 -> naive-3, naive-2 -> naive-0, naive-3 -> naive-2
ordered-by-id     800,000 transfers, sum of balances 800,000 (expected 800,000)
identity+tie-lock 800,000 transfers, sum of balances 800,000 (expected 800,000)
tryLock+backoff   800,000 transfers, sum of balances 800,000 (expected 800,000)
                  tryLock backoffs: 107
== Lock striping ==
100 seat keys over 16 stripes: busiest stripe guards 10 keys
bulkGet([seat-1, seat-70]) -> 1 lock (same stripe: de-duplicated, so a non-reentrant lock would not self-deadlock)
bulkGet([seat-9, seat-1]) == bulkGet([seat-1, seat-9]) -> true
== ConcurrentHashMap locks per BIN: a slow compute() blocks its bin-mates ==
compute(1)  [different bin] waited    0.4 ms
compute(16) [same bin as 0] waited  200.5 ms
SELF-TEST OK
```

### 6.5 Listing 3.5 (C++)

```cpp
// ordered_locking.cpp - deadlock by lock order, ordered locking, std::scoped_lock, padded lock striping
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <memory>
#include <mutex>
#include <print>
#include <random>
#include <string>
#include <thread>
#include <vector>

struct Account {
    std::uint64_t id;
    std::int64_t balance_cents;  // guarded by m
    std::mutex m;
    Account(std::uint64_t i, std::int64_t b) : id(i), balance_cents(b) {}
};

bool move_money(Account& from, Account& to, std::int64_t cents) {  // caller holds both locks
    if (from.balance_cents < cents) return false;
    from.balance_cents -= cents;
    to.balance_cents += cents;
    return true;
}

using Transfer = std::function<bool(Account&, Account&, std::int64_t)>;

bool naive(Account& from, Account& to, std::int64_t c) {  // A->B racing B->A deadlocks
    std::scoped_lock a(from.m);
    std::scoped_lock b(to.m);
    return move_money(from, to, c);
}

bool ordered(Account& from, Account& to, std::int64_t c) {  // one global order: smaller id first
    Account& first = from.id < to.id ? from : to;
    Account& second = &first == &from ? to : from;
    std::scoped_lock a(first.m);
    std::scoped_lock b(second.m);
    return move_money(from, to, c);
}

bool scoped(Account& from, Account& to, std::int64_t c) {  // std::lock's try-and-back-off algorithm
    std::scoped_lock both(from.m, to.m);                    // deadlock-free in ANY argument order
    return move_money(from, to, c);
}

bool g_leaked = false;

std::string stress(const char* name, const Transfer& t, int per_thread) {
    // Heap-allocated and shared with the workers: if they deadlock, they keep it alive forever.
    auto accts = std::make_shared<std::vector<std::unique_ptr<Account>>>();
    for (std::uint64_t i = 0; i < 8; ++i) accts->push_back(std::make_unique<Account>(i, 100'000));
    auto done = std::make_shared<std::atomic<std::int64_t>>(0);
    std::vector<std::thread> ws;
    for (int w = 0; w < 4; ++w)
        ws.emplace_back([accts, done, t, w, per_thread] {
            std::mt19937 rng(static_cast<unsigned>(w));
            std::uniform_int_distribution<int> pick(0, 7), other(1, 7), amount(1, 4'999);
            for (int i = 0; i < per_thread; ++i) {
                const int a = pick(rng), b = (a + other(rng)) % 8;
                t(*(*accts)[static_cast<std::size_t>(a)], *(*accts)[static_cast<std::size_t>(b)], amount(rng));
                done->fetch_add(1, std::memory_order_relaxed);
            }
        });
    const std::int64_t total = 4LL * per_thread;
    std::int64_t last = -1;
    auto stalled_since = std::chrono::steady_clock::now();
    while (done->load() < total) {
        const auto now = done->load();
        if (now != last) {
            last = now;
            stalled_since = std::chrono::steady_clock::now();
        } else if (std::chrono::steady_clock::now() - stalled_since > std::chrono::seconds(2)) {
            for (auto& w : ws) w.detach();
            g_leaked = true;
            return std::format("{:<17} DEADLOCK after {} transfers (no progress for 2 s)", name, now);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    for (auto& w : ws) w.join();
    std::int64_t sum = 0;
    for (const auto& a : *accts) sum += a->balance_cents;
    return std::format("{:<17} {} transfers, sum of balances {} (expected 800000){}", name, total, sum,
                       sum == 800'000 ? "" : "  <-- BROKEN");
}

/** Lock striping with one mutex per cache line: adjacent stripes must not false-share. */
class Striped {
    struct alignas(64) Stripe { std::mutex m; };
    std::unique_ptr<Stripe[]> stripes_;
    std::size_t mask_;
public:
    static constexpr std::size_t kStripeBytes = sizeof(Stripe);
    explicit Striped(std::size_t n) : stripes_(std::make_unique<Stripe[]>(n)), mask_(n - 1) {
        if ((n & (n - 1)) != 0) throw std::invalid_argument("power of two");
    }
    std::size_t index_for(const std::string& key) const {
        auto h = std::hash<std::string>{}(key);
        h ^= h >> 16;
        return h & mask_;
    }
    /** Sorted + de-duplicated: a consistent order, and std::mutex is never locked twice by one thread. */
    std::vector<std::mutex*> bulk_get(const std::vector<std::string>& keys) const {
        std::vector<std::size_t> idx;
        for (const auto& k : keys) idx.push_back(index_for(k));
        std::ranges::sort(idx);
        idx.erase(std::ranges::unique(idx).begin(), idx.end());
        std::vector<std::mutex*> out;
        for (auto i : idx) out.push_back(&stripes_[i].m);
        return out;
    }
};

int main() {
    std::println("== Opposite-order transfers, 4 threads x 200,000 ==");
    bool cures_ok = true;
    std::println("{}", stress("naive", naive, 200'000));
    for (auto [name, fn] : {std::pair<const char*, Transfer>{"ordered-by-id", ordered},
                            std::pair<const char*, Transfer>{"std::scoped_lock", scoped}}) {
        const auto line = stress(name, fn, 200'000);
        std::println("{}", line);
        cures_ok &= line.find("DEADLOCK") == std::string::npos && line.find("BROKEN") == std::string::npos;
    }

    std::println("== Lock striping ==");
    Striped striped(16);
    std::println("sizeof one stripe = {} B (alignas(64): no two stripes share a cache line)", Striped::kStripeBytes);
    std::string a, b;
    for (int i = 1; i <= 100 && a.empty(); ++i)
        for (int j = i + 1; j <= 100; ++j)
            if (striped.index_for("seat-" + std::to_string(i)) == striped.index_for("seat-" + std::to_string(j))) {
                a = "seat-" + std::to_string(i);
                b = "seat-" + std::to_string(j);
                break;
            }
    std::println("bulk_get([{}, {}]) -> {} mutex (same stripe, de-duplicated)", a, b, striped.bulk_get({a, b}).size());
    std::println("bulk_get([seat-9, seat-1]) == bulk_get([seat-1, seat-9]) -> {}",
                 striped.bulk_get({"seat-9", "seat-1"}) == striped.bulk_get({"seat-1", "seat-9"}));
    std::println("{}", cures_ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    std::fflush(stdout);
    if (g_leaked) std::quick_exit(cures_ok ? 0 : 1);  // deadlocked detached threads: skip destructors
    return cures_ok ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
== Opposite-order transfers, 4 threads x 200,000 ==
naive             DEADLOCK after 820 transfers (no progress for 2 s)
ordered-by-id     800000 transfers, sum of balances 800000 (expected 800000)
std::scoped_lock  800000 transfers, sum of balances 800000 (expected 800000)
== Lock striping ==
sizeof one stripe = 64 B (alignas(64): no two stripes share a cache line)
bulk_get([seat-1, seat-25]) -> 1 mutex (same stripe, de-duplicated)
bulk_get([seat-9, seat-1]) == bulk_get([seat-1, seat-9]) -> true
SELF-TEST OK
```

**One measured run, Clang 21.1:**

```text
== Opposite-order transfers, 4 threads x 200,000 ==
naive             DEADLOCK after 2028 transfers (no progress for 2 s)
ordered-by-id     800000 transfers, sum of balances 800000 (expected 800000)
std::scoped_lock  800000 transfers, sum of balances 800000 (expected 800000)
== Lock striping ==
sizeof one stripe = 64 B (alignas(64): no two stripes share a cache line)
bulk_get([seat-1, seat-4]) -> 1 mutex (same stripe, de-duplicated)
bulk_get([seat-9, seat-1]) == bulk_get([seat-1, seat-9]) -> true
SELF-TEST OK
```

### 6.6 Diagnosing a deadlock in production

- **Java:**
  - `jcmd <pid> Thread.print` (or `jstack`) prints `Found one Java-level deadlock:` with the full cycle, including `ReentrantLock` owners, which is the same information `ThreadMXBean.findDeadlockedThreads()` returned above (`naive-0 -> naive-3, naive-2 -> naive-0, naive-3 -> naive-2`).
  - JFR's `jdk.JavaMonitorEnter` and `jdk.ThreadPark` events show contention *before* it becomes deadlock.
  - Note that `findDeadlockedThreads` also reports threads blocked *behind* a cycle, not only its members. Listing 3.8's report shows a waiter on the cycle listed alongside it.
- **C++:** `std::mutex` exposes no owner, so diagnosis needs a debugger (thread stacks), lock-order instrumentation in debug builds (a per-thread held-locks list checked against a global order), or ThreadSanitizer's deadlock detector on platforms that support it (⚠ not MinGW).

---
## 7. Mechanical sympathy: false sharing and ring buffers

### 7.1 Cache lines and the cost of sharing

Caches move data in **lines**: 64 B on x86 and most ARM servers, 128 B on Apple M-series. Intel's L2 spatial prefetcher also fetches the *adjacent* line, pairing lines into 128 B. Under MESI-family coherence, a core must own a line *exclusively* to write it. Two cores writing **different variables in the same line** therefore ping-pong ownership on every write. That's **false sharing**: no logical sharing, full physical contention. The JDK guards its own hot fields with `@jdk.internal.vm.annotation.Contended`:
- the padding defaults to **128 B** (`-XX:ContendedPaddingWidth`);
- application classes need `-XX:-RestrictContended`;
- JDK users include `Striped64.Cell`, `ConcurrentHashMap.CounterCell`, `Thread`'s `ThreadLocalRandom` fields, and `ForkJoinPool` work queues.

Portable alternatives: pad with array spacing (as below), use class-hierarchy padding (JCTools), or `alignas` in C++.

### 7.2 The single-producer/single-consumer ring buffer

The ring is the building block of P17's logger and the LMAX-style engine in P12. Correctness needs only release/acquire:
- **The producer** writes `buf[tail]`, then publishes `tail+1` with a *release* store.
- **The consumer** reads `tail` with an *acquire* load, then reads `buf[head]`.

Performance needs two more ideas:

1. **Padding.** Keep the producer-owned and consumer-owned indices on different lines, 128 B apart to cover the adjacent-line prefetcher.
2. **Cached remote indices** (FastFlow, Folly's `ProducerConsumerQueue`, rigtorp's `SPSCQueue`). Each side keeps a private copy of the *other* side's index and re-reads the shared one only when its copy says full or empty. That turns a cross-core read per item into one per *batch*.

### 7.3 Listing 3.6

```java
// FalseSharingRing.java - false sharing measured, and an SPSC ring buffer with padded, cached indices
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicLongArray;

public final class FalseSharingRing {

    static final VarHandle LONGS = MethodHandles.arrayElementVarHandle(long[].class);

    /** Each thread owns ONE slot (no logical sharing); only the distance between slots changes. */
    static double counters(int threads, int strideLongs, long perThread) throws InterruptedException {
        long[] slots = new long[16 + threads * strideLongs + 16];     // 128 B of padding at both ends
        CountDownLatch start = new CountDownLatch(1);
        Thread[] ts = new Thread[threads];
        for (int t = 0; t < threads; t++) {
            final int idx = 16 + t * strideLongs;
            ts[t] = Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                } catch (InterruptedException e) {
                    return;
                }
                for (long i = 0; i < perThread; i++) {
                    long v = (long) LONGS.getOpaque(slots, idx);      // opaque: a real memory access every time,
                    LONGS.setOpaque(slots, idx, v + 1);               // no fences (single writer per slot)
                }
            });
        }
        long t0 = System.nanoTime();
        start.countDown();
        for (Thread t : ts) t.join();
        double ms = (System.nanoTime() - t0) / 1e6;
        for (int t = 0; t < threads; t++)
            if (slots[16 + t * strideLongs] != perThread) throw new AssertionError("slot " + t);
        return ms;
    }

    interface Ring {
        boolean offer(long v);
        long poll();                                                 // Long.MIN_VALUE when empty
    }

    static final long EMPTY = Long.MIN_VALUE;

    /** Naive: head and tail on one cache line, volatile on every access, no caching. */
    static final class NaiveRing implements Ring {
        private final long[] buf;
        private final int mask;
        private final AtomicLongArray ht = new AtomicLongArray(2);   // [0] head, [1] tail: same line

        NaiveRing(int capacityPow2) {
            buf = new long[capacityPow2];
            mask = capacityPow2 - 1;
        }

        @Override public boolean offer(long v) {
            long t = ht.get(1);
            if (t - ht.get(0) == buf.length) return false;
            buf[(int) (t & mask)] = v;
            ht.set(1, t + 1);
            return true;
        }

        @Override public long poll() {
            long h = ht.get(0);
            if (h == ht.get(1)) return EMPTY;
            long v = buf[(int) (h & mask)];
            ht.set(0, h + 1);
            return v;
        }
    }

    /**
     * Padded: consumer-owned {head, cachedTail} and producer-owned {tail, cachedHead} sit 128 bytes
     * apart; each side re-reads the other's index only when its cached copy says full/empty.
     */
    static final class PaddedRing implements Ring {
        private static final int HEAD = 16, CACHED_TAIL = 17, TAIL_READS = 18, TAIL = 32, CACHED_HEAD = 33, HEAD_READS = 34;
        private final long[] buf;
        private final int mask;
        private final long[] idx = new long[50];

        PaddedRing(int capacityPow2) {
            buf = new long[capacityPow2];
            mask = capacityPow2 - 1;
        }

        @Override public boolean offer(long v) {                     // producer thread only
            long t = idx[TAIL];
            if (t - idx[CACHED_HEAD] == buf.length) {
                idx[CACHED_HEAD] = (long) LONGS.getAcquire(idx, HEAD);
                idx[HEAD_READS]++;
                if (t - idx[CACHED_HEAD] == buf.length) return false;
            }
            buf[(int) (t & mask)] = v;
            LONGS.setRelease(idx, TAIL, t + 1);                      // publishes buf[t] (release)
            return true;
        }

        @Override public long poll() {                               // consumer thread only
            long h = idx[HEAD];
            if (h == idx[CACHED_TAIL]) {
                idx[CACHED_TAIL] = (long) LONGS.getAcquire(idx, TAIL);
                idx[TAIL_READS]++;
                if (h == idx[CACHED_TAIL]) return EMPTY;
            }
            long v = buf[(int) (h & mask)];
            LONGS.setRelease(idx, HEAD, h + 1);                      // frees the slot (release)
            return v;
        }

        long tailReads() { return idx[TAIL_READS]; }                 // read after both threads joined
        long headReads() { return idx[HEAD_READS]; }
    }

    static double pump(Ring ring, long n) throws InterruptedException {
        long[] result = new long[2];                                 // [0] sum, [1] order violations
        Thread consumer = Thread.ofPlatform().start(() -> {
            long expect = 0, sum = 0, bad = 0;
            while (expect < n) {
                long v = ring.poll();
                if (v == EMPTY) {
                    Thread.onSpinWait();
                    continue;
                }
                if (v != expect) bad++;
                sum += v;
                expect++;
            }
            result[0] = sum;
            result[1] = bad;
        });
        long t0 = System.nanoTime();
        for (long i = 0; i < n; i++) while (!ring.offer(i)) Thread.onSpinWait();
        consumer.join();
        double secs = (System.nanoTime() - t0) / 1e9;
        if (result[1] != 0 || result[0] != n * (n - 1) / 2) throw new AssertionError("ring lost or reordered items");
        return n / secs / 1e6;
    }

    public static void main(String[] args) throws InterruptedException {
        long per = 50_000_000L;
        System.out.println("== False sharing: 4 threads x 50,000,000 private increments (one measured run) ==");
        counters(4, 16, 5_000_000);                                  // warm-up
        for (int stride : new int[] {1, 8, 16})
            System.out.printf("slots %3d bytes apart: %7.1f ms%n", stride * 8, counters(4, stride, per));
        System.out.println("== SPSC ring (capacity 1024), 50,000,000 longs, order + sum verified ==");
        pump(new PaddedRing(1024), 5_000_000);                       // warm-up
        pump(new NaiveRing(1024), 5_000_000);
        System.out.printf("naive  (shared line, volatile everywhere) %6.1f M items/s%n", pump(new NaiveRing(1024), 50_000_000));
        PaddedRing padded = new PaddedRing(1024);
        System.out.printf("padded (128 B apart, cached indices)      %6.1f M items/s%n", pump(padded, 50_000_000));
        System.out.printf("       items per cross-core read: consumer %.1f (tail), producer %.1f (head)%n",
                50e6 / padded.tailReads(), 50e6 / Math.max(1, padded.headReads()));
        System.out.println("SELF-TEST OK");
    }
}
```

**One measured run (JDK 25.0.4.1):**

```text
== False sharing: 4 threads x 50,000,000 private increments (one measured run) ==
slots   8 bytes apart:   140.2 ms
slots  64 bytes apart:   103.0 ms
slots 128 bytes apart:   105.2 ms
== SPSC ring (capacity 1024), 50,000,000 longs, order + sum verified ==
naive  (shared line, volatile everywhere)   14.4 M items/s
padded (128 B apart, cached indices)        71.2 M items/s
       items per cross-core read: consumer 6.6 (tail), producer 42.9 (head)
SELF-TEST OK
```

```cpp
// false_sharing_ring.cpp - false sharing measured, and an SPSC ring buffer with padded, cached indices
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <latch>
#include <memory>
#include <optional>
#include <print>
#include <stdexcept>
#include <thread>
#include <vector>

inline void cpu_relax() {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#else
    std::this_thread::yield();
#endif
}

template <std::size_t Align>
struct alignas(Align) Slot {  // Align 8: four slots share one line; 64: one line each; 128: one line PAIR each
    std::atomic<std::uint64_t> v{0};
};

template <std::size_t Align>
double counters(int threads, std::uint64_t per_thread) {
    auto slots = std::make_unique<Slot<Align>[]>(static_cast<std::size_t>(threads));
    std::latch start(1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            auto& s = slots[static_cast<std::size_t>(t)].v;
            start.wait();
            for (std::uint64_t i = 0; i < per_thread; ++i)
                s.store(s.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);  // single writer: no RMW
        });
    const auto t0 = std::chrono::steady_clock::now();
    start.count_down();
    ts.clear();
    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    for (int t = 0; t < threads; ++t)
        if (slots[static_cast<std::size_t>(t)].v.load() != per_thread) throw std::logic_error("lost increments");
    return ms;
}

/** Naive: head and tail adjacent (one cache line), seq_cst everywhere, no caching. */
class NaiveRing {
    std::vector<std::uint64_t> buf_;
    std::size_t mask_;
    std::atomic<std::uint64_t> head_{0}, tail_{0};
public:
    explicit NaiveRing(std::size_t cap) : buf_(cap), mask_(cap - 1) {}
    bool offer(std::uint64_t v) {
        const auto t = tail_.load();
        if (t - head_.load() == buf_.size()) return false;
        buf_[t & mask_] = v;
        tail_.store(t + 1);
        return true;
    }
    std::optional<std::uint64_t> poll() {
        const auto h = head_.load();
        if (h == tail_.load()) return std::nullopt;
        const auto v = buf_[h & mask_];
        head_.store(h + 1);
        return v;
    }
};

/** Padded: consumer-owned {head, cached_tail} and producer-owned {tail, cached_head} on separate 128-byte blocks. */
class PaddedRing {
    std::vector<std::uint64_t> buf_;
    std::size_t mask_;
    struct alignas(128) Consumer { std::atomic<std::uint64_t> head{0}; std::uint64_t cached_tail = 0, tail_reads = 0; } c_;
    struct alignas(128) Producer { std::atomic<std::uint64_t> tail{0}; std::uint64_t cached_head = 0, head_reads = 0; } p_;
public:
    explicit PaddedRing(std::size_t cap) : buf_(cap), mask_(cap - 1) {}
    bool offer(std::uint64_t v) {  // producer thread only
        const auto t = p_.tail.load(std::memory_order_relaxed);
        if (t - p_.cached_head == buf_.size()) {
            p_.cached_head = c_.head.load(std::memory_order_acquire);
            ++p_.head_reads;
            if (t - p_.cached_head == buf_.size()) return false;
        }
        buf_[t & mask_] = v;
        p_.tail.store(t + 1, std::memory_order_release);  // publishes buf_[t]
        return true;
    }
    std::optional<std::uint64_t> poll() {  // consumer thread only
        const auto h = c_.head.load(std::memory_order_relaxed);
        if (h == c_.cached_tail) {
            c_.cached_tail = p_.tail.load(std::memory_order_acquire);
            ++c_.tail_reads;
            if (h == c_.cached_tail) return std::nullopt;
        }
        const auto v = buf_[h & mask_];
        c_.head.store(h + 1, std::memory_order_release);  // frees the slot
        return v;
    }
    std::uint64_t tail_reads() const { return c_.tail_reads; }  // read after both threads joined
    std::uint64_t head_reads() const { return p_.head_reads; }
};

template <class Ring>
double pump(Ring& ring, std::uint64_t n) {
    std::uint64_t sum = 0, bad = 0;
    std::jthread consumer([&] {
        std::uint64_t expect = 0;
        while (expect < n) {
            const auto v = ring.poll();
            if (!v) {
                cpu_relax();
                continue;
            }
            bad += (*v != expect);
            sum += *v;
            ++expect;
        }
    });
    const auto t0 = std::chrono::steady_clock::now();
    for (std::uint64_t i = 0; i < n; ++i)
        while (!ring.offer(i)) cpu_relax();
    consumer.join();
    const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    if (bad != 0 || sum != n * (n - 1) / 2) throw std::logic_error("ring lost or reordered items");
    return static_cast<double>(n) / secs / 1e6;
}

int main() {
    constexpr std::uint64_t per = 50'000'000;
    std::println("== False sharing: 4 threads x 50,000,000 private increments (one measured run) ==");
    std::println("slots   8 bytes apart: {:7.1f} ms", counters<8>(4, per));
    std::println("slots  64 bytes apart: {:7.1f} ms", counters<64>(4, per));
    std::println("slots 128 bytes apart: {:7.1f} ms", counters<128>(4, per));
    std::println("== SPSC ring (capacity 1024), 50,000,000 items, order + sum verified ==");
    NaiveRing naive(1024);
    PaddedRing padded(1024);
    std::println("naive  (shared line, seq_cst everywhere) {:6.1f} M items/s", pump(naive, 50'000'000));
    std::println("padded (128 B apart, cached indices)     {:6.1f} M items/s", pump(padded, 50'000'000));
    std::println("       items per cross-core read: consumer {:.1f} (tail), producer {:.1f} (head)",
                 50e6 / static_cast<double>(padded.tail_reads()), 50e6 / static_cast<double>(padded.head_reads() ? padded.head_reads() : 1));
    std::println("SELF-TEST OK");
}
```

**One measured run, GCC 16.2:**

```text
== False sharing: 4 threads x 50,000,000 private increments (one measured run) ==
slots   8 bytes apart:   172.1 ms
slots  64 bytes apart:    39.3 ms
slots 128 bytes apart:    49.0 ms
== SPSC ring (capacity 1024), 50,000,000 items, order + sum verified ==
naive  (shared line, seq_cst everywhere)   12.3 M items/s
padded (128 B apart, cached indices)      108.4 M items/s
       items per cross-core read: consumer 633.5 (tail), producer 5.8 (head)
SELF-TEST OK
```

**One measured run, Clang 21.1:**

```text
== False sharing: 4 threads x 50,000,000 private increments (one measured run) ==
slots   8 bytes apart:   231.5 ms
slots  64 bytes apart:    25.7 ms
slots 128 bytes apart:    40.0 ms
== SPSC ring (capacity 1024), 50,000,000 items, order + sum verified ==
naive  (shared line, seq_cst everywhere)   14.6 M items/s
padded (128 B apart, cached indices)       43.9 M items/s
       items per cross-core read: consumer 33.1 (tail), producer 3.6 (head)
SELF-TEST OK
```

### 7.4 Reading the mechanical-sympathy numbers ⚡

**False sharing is real, and its size depends on the loop.**
- Four threads incrementing *private* slots 8 B apart ran **2.2–4.4× (GCC) and 4.8–9× (Clang) slower** in C++ than with the slots a line apart (two runs each).
- In Java the penalty was 1.36× in this run (1.35–2.0× across six runs). The Java loop does more work per increment (opaque `VarHandle` access, a 64-bit loop counter, a safepoint poll), so a smaller fraction of its time is the contended store.
- On this Tiger Lake CPU, **128 B gave no consistent gain over 64 B** in the counter test. Each won in some runs, by up to ±30%, so the adjacent-line effect is in the noise here.
- Pad to 128 B anyway in portable libraries, because the JDK, Folly and JCTools target CPUs where it does matter (and Apple's 128 B lines). Report what you measured, not folklore.

**The ring buffer: padding + caching = 3–14× throughput, and the regime decides the rest.**

| Build | Naive (shared line, volatile/seq_cst everywhere) | Padded + cached indices | Range across runs (padded) |
|---|---|---|---|
| Java | 14.4 M items/s | 71.2 M items/s | 71–236 M items/s |
| C++ GCC | 12.3 M | 108.4 M | 108–142 M |
| C++ Clang | 14.6 M | 43.9 M | 22–44 M |

The instrumentation line explains the spread:
- In the GCC run the consumer re-read the producer's `tail` once every **633** items, so the queue ran with slack and each cross-core read was amortized over a large batch.
- In the Clang run it re-read every **33** items, and the producer re-read `head` every **3.6** items. The queue oscillated near full, so nearly every operation crossed cores.

Same algorithm, same padding, 2.5× apart, because of *queue regime* (who is faster, and by how much), which the compiler's code layout shifted.

The L7 conclusion: **padding removes false sharing; it can't remove true sharing.** The next levers are consumer-side *batching* (drain everything available, publish one `head` update, which is the LMAX Disruptor's batch effect) and producer-side batching (publish `tail` once per N items). Measure items per cross-core read, not just throughput.

---

## 8. Deterministic time: Clock, Ticker, virtual schedulers

### 8.1 Two kinds of time, two abstractions 🔥

| Need | Source | Abstraction to inject | Can it jump? |
|---|---|---|---|
| Timestamps humans read (booking time, audit, "expires at 12:05") | wall clock: `Instant.now()`, `system_clock` | `java.time.Clock`, or `InstantSource` (Java 17+, no zone) | **Yes**: NTP steps, manual changes, VM migration, leap-second smearing |
| Durations, TTLs, timeouts, rate-limiter refill | monotonic: `System.nanoTime()`, `steady_clock` | a `Ticker` (`LongSupplier` of nanos; Guava/Caffeine name), or a C++ clock *instance* | No (monotonic), but **arbitrary origin**: only differences mean anything |

Expiry logic that uses the wall clock is a latent outage. Listing 3.7 steps the wall clock back one hour during a 5-minute hold. Five real minutes later, the wall-clock map **still holds the seat**; it would hold it for another hour. The ticker-based map expired it on time.

### 8.2 The `nanoTime` difference rule 🧊

`System.nanoTime()` values may be negative and may overflow, and only `t1 - t0` is meaningful. Its Javadoc says to compare with `t1 - t0 < 0`, never `t1 < t0`. Listing 3.7 starts a fake ticker 500 ms before `Long.MAX_VALUE` and puts an entry with a 1 s TTL, so the deadline wraps to a large negative number. **One millisecond later**, the naive `now >= deadline` says *expired*, because a positive `now` exceeds a negative deadline. The difference check correctly says *present*. In C++ the equivalent arithmetic on `chrono` durations is *signed overflow*, which is UB, so there is no wraparound trick. "TTL = forever" must **saturate** (`saturating_add` in the listing).

### 8.3 Virtual time: test schedules without sleeping

The `ManualScheduler` in Listing 3.7 is a deterministic stand-in for `ScheduledExecutorService` and timer threads:
- a priority queue ordered by `(deadline, sequence)`, so equal deadlines run FIFO;
- `advance(d)` runs every due task **with the clock set to that task's own deadline**, re-enqueues periodic tasks, and finally lands on the target time;
- cancellation is a flag checked at dequeue.

The test then asserts exact behaviour: a sweeper at `t = 60 s, 120 s, 180 s`, a cancelled payment timeout that never fires, and two tasks with the same deadline in submission order. This is the testing backbone for P2 (rate limiter), P3 (scheduler and timing wheel), P5 (circuit breaker) and P6 (seat-lock expiry).

### 8.4 Listing 3.7 (Java)

```java
// ClockInjection.java - deterministic time: a Ticker for durations, a Clock for wall time, a manual scheduler
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.PriorityQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

public final class ClockInjection {

    // ===== Two different kinds of time ==========================================================

    /** Monotonic nanoseconds for durations/TTLs (Guava and Caffeine call this a Ticker). */
    @FunctionalInterface
    interface Ticker {
        long read();

        static Ticker system() {
            return System::nanoTime;
        }
    }

    static final class FakeTicker implements Ticker {
        private final AtomicLong nanos;

        FakeTicker(long start) {
            nanos = new AtomicLong(start);
        }

        void advance(Duration d) {
            nanos.addAndGet(d.toNanos());
        }

        void set(long n) {
            nanos.set(n);
        }

        @Override public long read() {
            return nanos.get();
        }
    }

    /** Wall time for timestamps humans read (it can jump: NTP steps, VM migration, manual changes). */
    static final class MutableClock extends Clock {
        private final AtomicReference<Instant> now;
        private final ZoneId zone;

        MutableClock(Instant start) {
            this(new AtomicReference<>(start), ZoneOffset.UTC);
        }

        private MutableClock(AtomicReference<Instant> now, ZoneId zone) {
            this.now = now;
            this.zone = zone;
        }

        void advance(Duration d) {
            now.updateAndGet(t -> t.plus(d));
        }

        @Override public Instant instant() { return now.get(); }
        @Override public ZoneId getZone() { return zone; }
        @Override public Clock withZone(ZoneId z) { return new MutableClock(now, z); }
    }

    // ===== A TTL map on each kind of time ========================================================

    static final class ExpiringMap<K, V> {
        private record Entry<V>(V value, long deadlineNanos) {}
        private final ConcurrentHashMap<K, Entry<V>> map = new ConcurrentHashMap<>();
        private final Ticker ticker;

        ExpiringMap(Ticker ticker) {
            this.ticker = ticker;
        }

        void put(K k, V v, Duration ttl) {
            map.put(k, new Entry<>(v, ticker.read() + ttl.toNanos()));   // may overflow: that is fine ...
        }

        Optional<V> get(K k) {
            Entry<V> e = map.get(k);
            if (e == null) return Optional.empty();
            if (ticker.read() - e.deadlineNanos() >= 0) {               // ... because we compare DIFFERENCES
                map.remove(k, e);                                       // remove only this exact entry
                return Optional.empty();
            }
            return Optional.of(e.value());
        }

        boolean naiveExpired(K k) {                                     // the bug: compares absolute values
            Entry<V> e = map.get(k);
            return e == null || ticker.read() >= e.deadlineNanos();
        }

        int sweep() {
            long now = ticker.read();
            int before = map.size();
            map.entrySet().removeIf(en -> now - en.getValue().deadlineNanos() >= 0);
            return before - map.size();
        }
    }

    static final class WallClockExpiringMap<K, V> {
        private record Entry<V>(V value, Instant deadline) {}
        private final ConcurrentHashMap<K, Entry<V>> map = new ConcurrentHashMap<>();
        private final Clock clock;

        WallClockExpiringMap(Clock clock) {
            this.clock = clock;
        }

        void put(K k, V v, Duration ttl) {
            map.put(k, new Entry<>(v, clock.instant().plus(ttl)));
        }

        Optional<V> get(K k) {
            Entry<V> e = map.get(k);
            return e == null || !clock.instant().isBefore(e.deadline()) ? Optional.empty() : Optional.of(e.value());
        }
    }

    // ===== A deterministic stand-in for ScheduledExecutorService ===============================

    static final class ManualScheduler {
        private record Task(long dueNanos, long seq, Runnable body, long periodNanos, AtomicBoolean cancelled) {}
        private final PriorityQueue<Task> queue = new PriorityQueue<>(
                Comparator.comparingLong(Task::dueNanos).thenComparingLong(Task::seq));   // FIFO for equal deadlines
        private final FakeTicker ticker;
        private long seq;

        ManualScheduler(FakeTicker ticker) {
            this.ticker = ticker;
        }

        AtomicBoolean schedule(Runnable r, Duration delay) {
            return enqueue(r, ticker.read() + delay.toNanos(), 0);
        }

        AtomicBoolean scheduleAtFixedRate(Runnable r, Duration initial, Duration period) {
            return enqueue(r, ticker.read() + initial.toNanos(), period.toNanos());
        }

        private AtomicBoolean enqueue(Runnable r, long due, long period) {
            AtomicBoolean cancelled = new AtomicBoolean();
            queue.add(new Task(due, seq++, r, period, cancelled));
            return cancelled;
        }

        /** Runs every due task with the clock set to THAT task's deadline, then lands on the target. */
        void advance(Duration d) {
            long target = ticker.read() + d.toNanos();
            while (!queue.isEmpty() && queue.peek().dueNanos() - target <= 0) {
                Task t = queue.poll();
                if (t.cancelled().get()) continue;
                ticker.set(t.dueNanos());
                t.body().run();
                if (t.periodNanos() > 0) queue.add(new Task(t.dueNanos() + t.periodNanos(), seq++, t.body(), t.periodNanos(), t.cancelled()));
            }
            ticker.set(target);
        }
    }

    public static void main(String[] args) {
        Duration ttl = Duration.ofMinutes(5);

        System.out.println("== 1. TTL boundary in nanoseconds, no sleeping ==");
        FakeTicker ticker = new FakeTicker(0);
        ExpiringMap<String, String> holds = new ExpiringMap<>(ticker);
        holds.put("seat-7", "alice", ttl);
        ticker.advance(ttl.minusNanos(1));
        boolean presentBefore = holds.get("seat-7").isPresent();
        ticker.advance(Duration.ofNanos(1));
        boolean presentAt = holds.get("seat-7").isPresent();
        System.out.println("present at TTL-1ns = " + presentBefore + ", present at TTL = " + presentAt);

        System.out.println("== 2. nanoTime is only meaningful as a DIFFERENCE ==");
        FakeTicker nearWrap = new FakeTicker(Long.MAX_VALUE - Duration.ofMillis(500).toNanos());
        ExpiringMap<String, String> wrap = new ExpiringMap<>(nearWrap);
        wrap.put("k", "v", Duration.ofSeconds(1));                       // deadline overflows to a negative long
        nearWrap.advance(Duration.ofMillis(1));                          // now is still positive: only the deadline wrapped
        System.out.println("1 ms after put, 1 s TTL, deadline wrapped past Long.MAX_VALUE: naive `now >= deadline` says expired = "
                + wrap.naiveExpired("k") + "; difference check says present = " + wrap.get("k").isPresent());

        System.out.println("== 3. Wall clock jumps back 1 h (NTP step) during a 5-minute hold ==");
        MutableClock wall = new MutableClock(Instant.parse("2026-01-01T12:00:00Z"));
        FakeTicker mono = new FakeTicker(0);
        WallClockExpiringMap<String, String> wallMap = new WallClockExpiringMap<>(wall);
        ExpiringMap<String, String> monoMap = new ExpiringMap<>(mono);
        wallMap.put("seat-9", "bob", ttl);
        monoMap.put("seat-9", "bob", ttl);
        wall.advance(Duration.ofHours(-1));                              // the step
        wall.advance(ttl);                                               // 5 real minutes pass
        mono.advance(ttl);
        System.out.println("after 5 real minutes: wall-clock map still holds seat-9 = " + wallMap.get("seat-9").isPresent()
                + ", ticker map holds seat-9 = " + monoMap.get("seat-9").isPresent());

        System.out.println("== 4. ManualScheduler: virtual time, deterministic order ==");
        FakeTicker vt = new FakeTicker(0);
        ManualScheduler sched = new ManualScheduler(vt);
        ExpiringMap<Integer, String> cache = new ExpiringMap<>(vt);
        for (int i = 0; i < 5; i++) cache.put(i, "v" + i, Duration.ofSeconds(30L * (i + 1)));   // 30 s .. 150 s
        List<String> log = new ArrayList<>();
        sched.scheduleAtFixedRate(() -> log.add("t=" + vt.read() / 1_000_000_000L + "s sweep removed " + cache.sweep()),
                Duration.ofSeconds(60), Duration.ofSeconds(60));
        AtomicBoolean timeout = sched.schedule(() -> log.add("payment timeout fired (BUG)"), Duration.ofSeconds(90));
        sched.schedule(() -> log.add("t=" + vt.read() / 1_000_000_000L + "s A (scheduled first)"), Duration.ofSeconds(120));
        sched.schedule(() -> log.add("t=" + vt.read() / 1_000_000_000L + "s B (same deadline, scheduled second)"), Duration.ofSeconds(120));
        timeout.set(true);                                               // the payment arrived: cancel the timeout
        sched.advance(Duration.ofMinutes(3));
        log.forEach(s -> System.out.println("  " + s));

        System.out.println("== 5. java.time.Clock decorators ==");
        Clock fixed = Clock.fixed(Instant.parse("2026-01-01T12:34:56.789Z"), ZoneOffset.UTC);
        System.out.println("Clock.tick(fixed, 1 min).instant() = " + Clock.tick(fixed, Duration.ofMinutes(1)).instant());
        System.out.println("Clock.offset(fixed, -1 day).instant() = " + Clock.offset(fixed, Duration.ofDays(-1)).instant());

        boolean ok = presentBefore && !presentAt && wrap.naiveExpired("k") && wrap.get("k").isPresent()
                && wallMap.get("seat-9").isPresent() && monoMap.get("seat-9").isEmpty()
                && log.size() == 5 && log.stream().noneMatch(s -> s.contains("BUG"));
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (verified):**

```text
== 1. TTL boundary in nanoseconds, no sleeping ==
present at TTL-1ns = true, present at TTL = false
== 2. nanoTime is only meaningful as a DIFFERENCE ==
1 ms after put, 1 s TTL, deadline wrapped past Long.MAX_VALUE: naive `now >= deadline` says expired = true; difference check says present = true
== 3. Wall clock jumps back 1 h (NTP step) during a 5-minute hold ==
after 5 real minutes: wall-clock map still holds seat-9 = true, ticker map holds seat-9 = false
== 4. ManualScheduler: virtual time, deterministic order ==
  t=60s sweep removed 2
  t=120s A (scheduled first)
  t=120s B (same deadline, scheduled second)
  t=120s sweep removed 2
  t=180s sweep removed 1
== 5. java.time.Clock decorators ==
Clock.tick(fixed, 1 min).instant() = 2026-01-01T12:34:00Z
Clock.offset(fixed, -1 day).instant() = 2025-12-31T12:34:56.789Z
SELF-TEST OK
```

### 8.5 Listing 3.7 (C++)

The C++ version injects the clock in two ways, and both are idiomatic:
- **A template parameter constrained by a concept** (`SteadyClockLike`). `ExpiringMap<K, V, Clock>` holds a `const Clock&`, so production code pays nothing for the indirection and tests pass a `FakeSteadyClock`.
- **A virtual interface**, as in file 01's `Clock`, for runtime wiring.

Avoid a clock type with a *static* `now()`, as the standard's *Clock* requirement shapes it, for anything you want to fake. A static `now()` is a global again.

```cpp
// clock_injection.cpp - deterministic time: steady time for durations, system time for wall clock, a manual scheduler
#include <atomic>
#include <chrono>
#include <concepts>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <queue>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std::chrono_literals;
using SteadyTp = std::chrono::steady_clock::time_point;
using SysTp = std::chrono::system_clock::time_point;

// ===== Clocks: injected as instances (a static now() would be global state again) ============

template <class C>
concept SteadyClockLike = requires(const C& c) {
    { c.now() } -> std::same_as<SteadyTp>;
};

struct RealSteadyClock {
    SteadyTp now() const { return std::chrono::steady_clock::now(); }
};

class FakeSteadyClock {
    std::atomic<std::int64_t> ns_{0};
public:
    SteadyTp now() const { return SteadyTp(std::chrono::nanoseconds(ns_.load(std::memory_order_acquire))); }
    void advance(std::chrono::nanoseconds d) { ns_.fetch_add(d.count(), std::memory_order_acq_rel); }
    void set(SteadyTp t) { ns_.store(t.time_since_epoch().count(), std::memory_order_release); }
};

class FakeSystemClock {  // wall time: may jump in either direction
    std::atomic<std::int64_t> ns_;
public:
    explicit FakeSystemClock(SysTp start) : ns_(std::chrono::duration_cast<std::chrono::nanoseconds>(start.time_since_epoch()).count()) {}
    SysTp now() const { return SysTp(std::chrono::duration_cast<SysTp::duration>(std::chrono::nanoseconds(ns_.load()))); }
    void advance(std::chrono::nanoseconds d) { ns_.fetch_add(d.count()); }
};

/** Signed chrono overflow is UB, so "TTL = forever" must saturate instead of wrapping like Java's nanoTime. */
SteadyTp saturating_add(SteadyTp t, std::chrono::nanoseconds d) {
    return d > SteadyTp::max() - t ? SteadyTp::max() : t + d;
}

// ===== TTL maps on each kind of time ==========================================================

template <class K, class V, SteadyClockLike Clock>
class ExpiringMap {  // Clock is a template parameter: zero-cost in production, fake in tests
    struct Entry { V value; SteadyTp deadline; };
    const Clock& clock_;
    mutable std::mutex m_;
    std::unordered_map<K, Entry> map_;
public:
    explicit ExpiringMap(const Clock& c) : clock_(c) {}
    void put(const K& k, V v, std::chrono::nanoseconds ttl) {
        std::scoped_lock l(m_);
        map_.insert_or_assign(k, Entry{std::move(v), saturating_add(clock_.now(), ttl)});
    }
    std::optional<V> get(const K& k) {
        std::scoped_lock l(m_);
        auto it = map_.find(k);
        if (it == map_.end()) return std::nullopt;
        if (clock_.now() >= it->second.deadline) {  // expired iff now >= deadline
            map_.erase(it);
            return std::nullopt;
        }
        return it->second.value;
    }
    std::size_t sweep() {
        std::scoped_lock l(m_);
        const auto now = clock_.now();
        return std::erase_if(map_, [&](const auto& kv) { return now >= kv.second.deadline; });
    }
};

template <class K, class V>
class WallClockExpiringMap {
    struct Entry { V value; SysTp deadline; };
    const FakeSystemClock& clock_;
    std::unordered_map<K, Entry> map_;
public:
    explicit WallClockExpiringMap(const FakeSystemClock& c) : clock_(c) {}
    void put(const K& k, V v, std::chrono::nanoseconds ttl) {
        map_.insert_or_assign(k, Entry{std::move(v), clock_.now() + std::chrono::duration_cast<SysTp::duration>(ttl)});
    }
    std::optional<V> get(const K& k) const {
        auto it = map_.find(k);
        if (it == map_.end() || clock_.now() >= it->second.deadline) return std::nullopt;
        return it->second.value;
    }
};

// ===== A deterministic stand-in for a timer thread ===========================================

class ManualScheduler {
    struct Task {
        SteadyTp due;
        std::uint64_t seq;
        std::function<void()> body;
        std::chrono::nanoseconds period;
        std::shared_ptr<std::atomic<bool>> cancelled;
        bool operator>(const Task& o) const { return due != o.due ? due > o.due : seq > o.seq; }  // FIFO ties
    };
    std::priority_queue<Task, std::vector<Task>, std::greater<>> q_;
    FakeSteadyClock& clock_;
    std::uint64_t seq_ = 0;
public:
    explicit ManualScheduler(FakeSteadyClock& c) : clock_(c) {}
    std::shared_ptr<std::atomic<bool>> schedule(std::function<void()> f, std::chrono::nanoseconds delay,
                                                std::chrono::nanoseconds period = 0ns) {
        auto c = std::make_shared<std::atomic<bool>>(false);
        q_.push(Task{clock_.now() + delay, seq_++, std::move(f), period, c});
        return c;
    }
    /** Runs every due task with the clock set to THAT task's deadline, then lands on the target. */
    void advance(std::chrono::nanoseconds d) {
        const auto target = clock_.now() + d;
        while (!q_.empty() && q_.top().due <= target) {
            Task t = q_.top();
            q_.pop();
            if (t.cancelled->load()) continue;
            clock_.set(t.due);
            t.body();
            if (t.period > 0ns) q_.push(Task{t.due + t.period, seq_++, t.body, t.period, t.cancelled});
        }
        clock_.set(target);
    }
};

int main() {
    constexpr auto ttl = 5min;

    std::println("== 1. TTL boundary in nanoseconds, no sleeping ==");
    FakeSteadyClock clock;
    ExpiringMap<std::string, std::string, FakeSteadyClock> holds(clock);
    holds.put("seat-7", "alice", ttl);
    clock.advance(ttl - 1ns);
    const bool present_before = holds.get("seat-7").has_value();
    clock.advance(1ns);
    const bool present_at = holds.get("seat-7").has_value();
    std::println("present at TTL-1ns = {}, present at TTL = {}", present_before, present_at);

    std::println("== 2. TTL = forever: saturate, never overflow ==");
    holds.put("vip", "carol", std::chrono::nanoseconds::max());
    clock.advance(24h * 365 * 100);
    std::println("after 100 virtual years, the 'forever' hold is present = {}", holds.get("vip").has_value());

    std::println("== 3. Wall clock jumps back 1 h (NTP step) during a 5-minute hold ==");
    FakeSystemClock wall(SysTp(std::chrono::sys_days(std::chrono::year(2026) / 1 / 1) + 12h));
    FakeSteadyClock mono;
    WallClockExpiringMap<std::string, std::string> wall_map(wall);
    ExpiringMap<std::string, std::string, FakeSteadyClock> mono_map(mono);
    wall_map.put("seat-9", "bob", ttl);
    mono_map.put("seat-9", "bob", ttl);
    wall.advance(-1h);  // the step
    wall.advance(ttl);  // 5 real minutes pass
    mono.advance(ttl);
    const bool wall_still = wall_map.get("seat-9").has_value(), mono_still = mono_map.get("seat-9").has_value();
    std::println("after 5 real minutes: wall-clock map still holds seat-9 = {}, steady map holds seat-9 = {}", wall_still, mono_still);

    std::println("== 4. ManualScheduler: virtual time, deterministic order ==");
    FakeSteadyClock vt;
    ManualScheduler sched(vt);
    ExpiringMap<int, std::string, FakeSteadyClock> cache(vt);
    for (int i = 0; i < 5; ++i) cache.put(i, "v" + std::to_string(i), std::chrono::seconds(30 * (i + 1)));
    std::vector<std::string> log;
    auto secs = [&] { return std::chrono::duration_cast<std::chrono::seconds>(vt.now().time_since_epoch()).count(); };
    sched.schedule([&] { log.push_back(std::format("t={}s sweep removed {}", secs(), cache.sweep())); }, 60s, 60s);
    auto timeout = sched.schedule([&] { log.push_back("payment timeout fired (BUG)"); }, 90s);
    sched.schedule([&] { log.push_back(std::format("t={}s A (scheduled first)", secs())); }, 120s);
    sched.schedule([&] { log.push_back(std::format("t={}s B (same deadline, scheduled second)", secs())); }, 120s);
    timeout->store(true);  // the payment arrived: cancel the timeout
    sched.advance(3min);
    for (const auto& s : log) std::println("  {}", s);

    std::println("== 5. Truncation, the chrono way (java.time Clock.tick) ==");
    const auto t = SysTp(std::chrono::sys_days(std::chrono::year(2026) / 1 / 1)) + 12h + 34min + 56s + 789ms;
    std::println("floor<minutes>(12:34:56.789) = {:%H:%M:%S}", std::chrono::floor<std::chrono::minutes>(t));

    bool ok = present_before && !present_at && holds.get("vip").has_value() && wall_still && !mono_still && log.size() == 5;
    for (const auto& s : log) ok &= s.find("BUG") == std::string::npos;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output (verified; identical under GCC 16.2 and Clang 21.1):**

```text
== 1. TTL boundary in nanoseconds, no sleeping ==
present at TTL-1ns = true, present at TTL = false
== 2. TTL = forever: saturate, never overflow ==
after 100 virtual years, the 'forever' hold is present = true
== 3. Wall clock jumps back 1 h (NTP step) during a 5-minute hold ==
after 5 real minutes: wall-clock map still holds seat-9 = true, steady map holds seat-9 = false
== 4. ManualScheduler: virtual time, deterministic order ==
  t=60s sweep removed 2
  t=120s A (scheduled first)
  t=120s B (same deadline, scheduled second)
  t=120s sweep removed 2
  t=180s sweep removed 1
== 5. Truncation, the chrono way (java.time Clock.tick) ==
floor<minutes>(12:34:56.789) = 12:34:00
SELF-TEST OK
```

### 8.6 The time checklist

- [ ] TTLs, timeouts and refill rates use a monotonic source; only timestamps use the wall clock.
- [ ] The expiry predicate is written once and tested at `deadline − 1 ns` and `deadline`.
- [ ] Java: deadlines are compared by difference (`now - deadline >= 0`); C++: "forever" saturates.
- [ ] Time is injected (constructor parameter); tests drive it; no test sleeps.
- [ ] Scheduled work is testable through a virtual-time scheduler, with deterministic order for equal deadlines.
- [ ] `java.time.Clock` subclasses honour `withZone` (return a view; never throw), and `InstantSource` is preferred when no zone is needed.

---
## 9. Testing concurrent code: the harness and its limits

### 9.1 Design of the harness every problem uses ⚡

Listing 3.8 is the canonical harness that Folders 03–07 reuse. Each design decision answers a specific failure of naive concurrent tests:

| Decision | Naive test | Why it fails | Harness behaviour |
|---|---|---|---|
| Start gate | `CountDownLatch` or thread creation in a loop | Wake-ups are staggered by microseconds, so threads rarely overlap; races hide | Workers **spin** on a volatile/atomic round number, starting within ~100 ns of each other |
| State per round | One shared object for the whole test | One early corruption masks the rest; no way to count | **Fresh state every round**; violations counted per round |
| Assertions | Exact counts or interleavings | Flaky; valid schedules differ | **Invariants**: conserved sums, "at most one holder", "count == ops" |
| Hangs | The test never ends | CI times out with no diagnosis | **Round timeout**, then the lock cycle from `ThreadMXBean` (Java) or a "no progress" report (C++); the threads are abandoned safely |
| Exceptions in workers | Lost on a background thread | A test passes while threads die | First throwable captured and reported with its round |
| Reproducibility | `new Random()` | A failure can't be replayed | Per-thread RNG = f(seed, thread, round): **the operations replay; the interleaving does not** |
| C++ lifetimes | `std::thread` joined in a destructor | A deadlocked thread hangs the test forever | State shared via `shared_ptr`; on a timeout, detach and leak deliberately; `quick_exit` at the end |

### 9.2 Listing 3.8

```java
// StressHarness.java - the reusable concurrency stress harness used by every problem in this KB
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.SplittableRandom;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReentrantLock;

public final class StressHarness {

    /** Fresh state per round, one action per thread per round, an invariant check after each round. */
    public interface Scenario<S> {
        S newState();

        void act(S state, int thread, SplittableRandom rnd) throws Exception;

        Optional<String> check(S state);                     // empty = invariant holds
    }

    public record Report(String name, int roundsRun, int violations, String firstViolation, String failure, long seed) {
        @Override public String toString() {
            return String.format("%-22s rounds=%,6d violations=%,6d%s%s  [seed=%d]", name, roundsRun, violations,
                    firstViolation.isEmpty() ? "" : "  first: " + firstViolation,
                    failure.isEmpty() ? "" : "  FAILURE: " + failure, seed);
        }
    }

    private record Round<S>(int no, S state) {}

    /**
     * Workers spin on a volatile round number (start skew ~100 ns, unlike a latch's ~us unpark chain).
     * Each thread's random stream is derived from (seed, thread, round), so a failing seed replays the
     * same operations -- not the same interleaving; that is what the round count is for.
     */
    public static <S> Report run(String name, Scenario<S> sc, int threads, int rounds, Duration roundTimeout, long seed) {
        AtomicReference<Round<S>> current = new AtomicReference<>(new Round<>(0, null));
        AtomicInteger finished = new AtomicInteger();
        AtomicReference<Throwable> crash = new AtomicReference<>();
        AtomicInteger abort = new AtomicInteger();
        List<Thread> workers = new ArrayList<>();
        for (int t = 0; t < threads; t++) {
            final int tid = t;
            workers.add(Thread.ofPlatform().daemon().name(name + "-w" + t).start(() -> {
                for (int r = 1; r <= rounds; r++) {
                    Round<S> round;
                    while ((round = current.get()).no() < r) {
                        if (abort.get() != 0) return;
                        Thread.onSpinWait();
                    }
                    try {
                        sc.act(round.state(), tid, new SplittableRandom(seed ^ ((long) tid << 32) ^ r));
                    } catch (Throwable e) {
                        crash.compareAndSet(null, e);
                    }
                    finished.incrementAndGet();
                }
            }));
        }
        int violations = 0;
        String first = "";
        for (int r = 1; r <= rounds; r++) {
            Round<S> round = new Round<>(r, sc.newState());
            current.set(round);
            long deadline = System.nanoTime() + roundTimeout.toNanos();
            while (finished.get() < r * threads) {
                if (System.nanoTime() > deadline) {
                    abort.set(1);
                    return new Report(name, r - 1, violations, first, "round " + r + " timed out: " + lockCycle(), seed);
                }
                Thread.onSpinWait();
            }
            if (crash.get() != null) {
                abort.set(1);
                return new Report(name, r, violations, first, "round " + r + " threw " + crash.get(), seed);
            }
            Optional<String> bad = sc.check(round.state());
            if (bad.isPresent()) {
                if (violations++ == 0) first = "round " + r + ": " + bad.get();
            }
        }
        return new Report(name, rounds, violations, first, "", seed);
    }

    static String lockCycle() {
        var mx = ManagementFactory.getThreadMXBean();
        long[] ids = mx.findDeadlockedThreads();
        if (ids == null) return "no lock cycle (livelock, lost wake-up or a slow round?)";
        List<String> edges = new ArrayList<>();
        for (ThreadInfo ti : mx.getThreadInfo(ids)) edges.add(ti.getThreadName() + "->" + ti.getLockOwnerName());
        edges.sort(null);
        return "lock cycle " + String.join(" ", edges);
    }

    // ===== Demo subjects ===========================================================================

    static final class PlainCounter { int n; }

    static final class Bank {
        final long[] balance = {1_000, 1_000};
        final ReentrantLock[] locks = {new ReentrantLock(), new ReentrantLock()};
    }

    public static void main(String[] args) {
        final int threads = 4, ops = 1_000;
        Duration timeout = Duration.ofSeconds(2);
        List<Report> reports = new ArrayList<>();

        reports.add(run("plain int++", new Scenario<PlainCounter>() {
            public PlainCounter newState() { return new PlainCounter(); }
            public void act(PlainCounter s, int t, SplittableRandom rnd) { for (int i = 0; i < ops; i++) s.n++; }
            public Optional<String> check(PlainCounter s) {
                return s.n == threads * ops ? Optional.empty() : Optional.of("count " + s.n + " != " + threads * ops);
            }
        }, threads, 2_000, timeout, 42));

        reports.add(run("AtomicInteger", new Scenario<AtomicInteger>() {
            public AtomicInteger newState() { return new AtomicInteger(); }
            public void act(AtomicInteger s, int t, SplittableRandom rnd) { for (int i = 0; i < ops; i++) s.incrementAndGet(); }
            public Optional<String> check(AtomicInteger s) {
                return s.get() == threads * ops ? Optional.empty() : Optional.of("count " + s.get());
            }
        }, threads, 2_000, timeout, 42));

        for (boolean ordered : new boolean[] {false, true}) {
            reports.add(run(ordered ? "transfers, ordered" : "transfers, unordered", new Scenario<Bank>() {
                public Bank newState() { return new Bank(); }
                public void act(Bank b, int t, SplittableRandom rnd) {
                    for (int i = 0; i < 200; i++) {
                        int from = rnd.nextInt(2), to = 1 - from;
                        int first = ordered ? 0 : from, second = 1 - first;
                        b.locks[first].lock();
                        try {
                            b.locks[second].lock();
                            try {
                                long amt = rnd.nextInt(1, 50);
                                if (b.balance[from] >= amt) {
                                    b.balance[from] -= amt;
                                    b.balance[to] += amt;
                                }
                            } finally {
                                b.locks[second].unlock();
                            }
                        } finally {
                            b.locks[first].unlock();
                        }
                    }
                }
                public Optional<String> check(Bank b) {
                    long sum = b.balance[0] + b.balance[1];
                    return sum == 2_000 ? Optional.empty() : Optional.of("sum " + sum);
                }
            }, threads, 2_000, timeout, 7));
        }
        reports.forEach(System.out::println);
        boolean ok = reports.get(1).violations() == 0 && reports.get(1).failure().isEmpty()
                && reports.get(3).violations() == 0 && reports.get(3).failure().isEmpty();
        System.out.println(ok ? "SELF-TEST OK: the harness passes correct subjects" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**One measured run (JDK 25.0.4.1). The violation counts vary; the passes are guaranteed:**

```text
plain int++            rounds= 2,000 violations= 1,966  first: round 1: count 1529 != 4000  [seed=42]
AtomicInteger          rounds= 2,000 violations=     0  [seed=42]
transfers, unordered   rounds=     0 violations=     0  FAILURE: round 1 timed out: lock cycle transfers, unordered-w0->transfers, unordered-w2 transfers, unordered-w1->transfers, unordered-w2 transfers, unordered-w2->transfers, unordered-w1  [seed=7]
transfers, ordered     rounds= 2,000 violations=     0  [seed=7]
SELF-TEST OK: the harness passes correct subjects
```

```cpp
// stress_harness.cpp - the reusable concurrency stress harness used by every problem in this KB
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <format>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <random>
#include <string>
#include <thread>
#include <vector>

inline void cpu_relax() {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#else
    std::this_thread::yield();
#endif
}

struct Report {
    std::string name;
    int rounds_run = 0, violations = 0;
    std::string first_violation, failure;
    std::uint64_t seed = 0;
    std::string str() const {
        return std::format("{:<22} rounds={:>6} violations={:>6}{}{}  [seed={}]", name, rounds_run, violations,
                           first_violation.empty() ? "" : "  first: " + first_violation,
                           failure.empty() ? "" : "  FAILURE: " + failure, seed);
    }
};

inline bool g_leaked_threads = false;  // a deadlocked std::thread can never be joined

/**
 * Fresh state per round; act(state, thread, rng) on every worker; check(state) after the round.
 * Workers spin on an atomic round number. Per-thread RNG = f(seed, thread, round): a failing seed
 * replays the same operations (not the same interleaving).
 */
template <class S>
Report run(std::string name, int threads, int rounds, std::chrono::milliseconds timeout, std::uint64_t seed,
           std::function<std::unique_ptr<S>()> new_state, std::function<void(S&, int, std::mt19937_64&)> act,
           std::function<std::optional<std::string>(S&)> check) {
    struct Round { int no; std::unique_ptr<S> state; };
    struct Shared {
        std::atomic<Round*> current{nullptr};
        std::atomic<int> finished{0};
        std::atomic<bool> abort{false};
        std::mutex crash_m;
        std::string crash;
        std::vector<std::unique_ptr<Round>> keep;  // rounds are freed only once all workers are done
    };
    auto sh = std::make_shared<Shared>();
    sh->keep.push_back(std::make_unique<Round>(Round{0, nullptr}));
    sh->current.store(sh->keep.back().get());
    std::vector<std::thread> workers;
    for (int t = 0; t < threads; ++t)
        workers.emplace_back([sh, act, t, rounds, seed] {
            for (int r = 1; r <= rounds; ++r) {
                Round* round;
                while ((round = sh->current.load(std::memory_order_acquire))->no < r) {
                    if (sh->abort.load(std::memory_order_relaxed)) return;
                    cpu_relax();
                }
                std::mt19937_64 rng(seed ^ (static_cast<std::uint64_t>(t) << 32) ^ static_cast<std::uint64_t>(r));
                try {
                    act(*round->state, t, rng);
                } catch (const std::exception& e) {
                    std::scoped_lock l(sh->crash_m);
                    if (sh->crash.empty()) sh->crash = e.what();
                }
                sh->finished.fetch_add(1, std::memory_order_acq_rel);
            }
        });
    Report rep{std::move(name), 0, 0, "", "", seed};
    for (int r = 1; r <= rounds; ++r) {
        auto round = std::make_unique<Round>(Round{r, new_state()});
        sh->current.store(round.get(), std::memory_order_release);
        const auto deadline = std::chrono::steady_clock::now() + timeout;
        while (sh->finished.load(std::memory_order_acquire) < r * threads) {
            if (std::chrono::steady_clock::now() > deadline) {
                sh->abort.store(true);
                sh->keep.push_back(std::move(round));  // workers may still hold it: leak with the threads
                for (auto& w : workers) w.detach();
                g_leaked_threads = true;
                rep.rounds_run = r - 1;
                rep.failure = std::format("round {} timed out (no owner introspection for std::mutex)", r);
                return rep;
            }
            cpu_relax();
        }
        {
            std::scoped_lock l(sh->crash_m);
            if (!sh->crash.empty()) {
                sh->abort.store(true);
                for (auto& w : workers) w.join();
                rep.rounds_run = r;
                rep.failure = "round " + std::to_string(r) + " threw " + sh->crash;
                return rep;
            }
        }
        if (auto bad = check(*round->state); bad && rep.violations++ == 0)
            rep.first_violation = "round " + std::to_string(r) + ": " + *bad;
        sh->keep.back().swap(round);  // keep the newest round alive until the next one is published
    }
    for (auto& w : workers) w.join();
    rep.rounds_run = rounds;
    return rep;
}

// ===== Demo subjects ===========================================================================

struct LoadStoreCounter { std::atomic<int> n{0}; };  // read, then write: the lost-update interleaving, no UB
struct AtomicCounter { std::atomic<int> n{0}; };
struct Bank {
    std::int64_t balance[2] = {1'000, 1'000};
    std::mutex locks[2];
};

int main() {
    constexpr int threads = 4, ops = 1'000;
    const auto timeout = std::chrono::milliseconds(2'000);
    std::vector<Report> reports;

    reports.push_back(run<LoadStoreCounter>(
        "load-then-store ++", threads, 2'000, timeout, 42, [] { return std::make_unique<LoadStoreCounter>(); },
        [](LoadStoreCounter& s, int, std::mt19937_64&) {
            for (int i = 0; i < ops; ++i) s.n.store(s.n.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
        },
        [](LoadStoreCounter& s) -> std::optional<std::string> {
            if (s.n.load() == threads * ops) return std::nullopt;
            return "count " + std::to_string(s.n.load()) + " != " + std::to_string(threads * ops);
        }));

    reports.push_back(run<AtomicCounter>(
        "fetch_add", threads, 2'000, timeout, 42, [] { return std::make_unique<AtomicCounter>(); },
        [](AtomicCounter& s, int, std::mt19937_64&) {
            for (int i = 0; i < ops; ++i) s.n.fetch_add(1, std::memory_order_relaxed);
        },
        [](AtomicCounter& s) -> std::optional<std::string> {
            if (s.n.load() == threads * ops) return std::nullopt;
            return "count " + std::to_string(s.n.load());
        }));

    for (const bool ordered : {false, true}) {
        reports.push_back(run<Bank>(
            ordered ? "transfers, ordered" : "transfers, unordered", threads, 2'000, timeout, 7,
            [] { return std::make_unique<Bank>(); },
            [ordered](Bank& b, int, std::mt19937_64& rng) {
                for (int i = 0; i < 200; ++i) {
                    const int from = static_cast<int>(rng() % 2), to = 1 - from;
                    const int first = ordered ? 0 : from, second = 1 - first;
                    std::scoped_lock a(b.locks[first]);
                    std::scoped_lock c(b.locks[second]);
                    const auto amt = static_cast<std::int64_t>(1 + rng() % 49);
                    if (b.balance[from] >= amt) {
                        b.balance[from] -= amt;
                        b.balance[to] += amt;
                    }
                }
            },
            [](Bank& b) -> std::optional<std::string> {
                const auto sum = b.balance[0] + b.balance[1];
                if (sum == 2'000) return std::nullopt;
                return "sum " + std::to_string(sum);
            }));
    }
    for (const auto& r : reports) std::println("{}", r.str());
    const bool ok = reports[1].violations == 0 && reports[1].failure.empty() && reports[3].violations == 0 &&
                    reports[3].failure.empty();
    std::println("{}", ok ? "SELF-TEST OK: the harness passes correct subjects" : "SELF-TEST FAILED");
    std::fflush(stdout);
    if (g_leaked_threads) std::quick_exit(ok ? 0 : 1);
    return ok ? 0 : 1;
}
```

**One measured run, GCC 16.2:**

```text
load-then-store ++     rounds=  2000 violations=  1999  first: round 2: count 1080 != 4000  [seed=42]
fetch_add              rounds=  2000 violations=     0  [seed=42]
transfers, unordered   rounds=     1 violations=     0  FAILURE: round 2 timed out (no owner introspection for std::mutex)  [seed=7]
transfers, ordered     rounds=  2000 violations=     0  [seed=7]
SELF-TEST OK: the harness passes correct subjects
```

**One measured run, Clang 21.1:**

```text
load-then-store ++     rounds=  2000 violations=  1998  first: round 2: count 1606 != 4000  [seed=42]
fetch_add              rounds=  2000 violations=     0  [seed=42]
transfers, unordered   rounds=     1 violations=     0  FAILURE: round 2 timed out (no owner introspection for std::mutex)  [seed=7]
transfers, ordered     rounds=  2000 violations=     0  [seed=7]
SELF-TEST OK: the harness passes correct subjects
```

The racy counter failed in 1,966 of 2,000 rounds in Java (1,998–1,999 in C++). Spin-gated rounds make races the *common* case rather than a rare one. The unordered transfers deadlocked in round 1 or 2, and the Java report names the cycle. Correct subjects pass all 2,000 rounds.

### 9.3 What stress testing can and can't prove

A passing stress test is evidence, not proof. Escalate when the stakes justify it:

| Tool | Proves / finds | Platform | Use for |
|---|---|---|---|
| This harness | Invariant violations, deadlocks, crashes under real scheduling | Java, C++ | Every LLD problem; interview demos |
| **jcstress** (OpenJDK) | Which outcomes of a litmus test the JVM and hardware actually produce, classified ACCEPTABLE / FORBIDDEN / INTERESTING | JVM | JMM questions; validating a lock-free publication protocol |
| **Lincheck** (JetBrains) | Linearizability of a concurrent data structure against a sequential spec, by stress *and* model checking | JVM (Kotlin/Java) | Queues, maps, caches |
| **ThreadSanitizer** | Data races and lock-order inversions, dynamically | GCC/Clang on Linux/macOS ⚠ (not MinGW) | Any C++ concurrency; run in CI |
| **GenMC / CDSChecker / Relacy** | Exhaustive exploration of C++11-model executions for small tests | C/C++ | Lock-free algorithms, memory-order choices |
| **Deterministic simulation** | Replays the *interleaving* from a seed by owning the scheduler | Custom (FoundationDB-style) | Distributed state machines (Folder 05) |
| **JFR** (`jdk.JavaMonitorEnter`, `jdk.ThreadPark`) | Where threads actually wait in production | JVM | Contention profiling before re-architecting |

---

## 10. Virtual threads and structured concurrency: what changes for LLD

Folder 07, file 03 goes deep. The design-relevant facts:

- **Virtual threads (JDK 21, JEP 444) make blocking cheap, not concurrency free.** Shared mutable state needs the same locks. What changes is that you stop pooling threads and start **bounding concurrency explicitly**: a `Semaphore` around the downstream call, instead of a fixed pool size that bounds it by accident.
- **Pinning.** In JDK 21–23 a virtual thread blocking inside `synchronized` pins its carrier. JDK 24 (JEP 491) removed that for `synchronized`. Native frames and class initialization still pin ⚠.
- **`ThreadLocal` at a million threads** is a memory and inheritance problem. `ScopedValue` (final in JDK 25, JEP 506) is immutable, bounded to a scope, and inherited by `StructuredTaskScope` subtasks (verified in file 02, Listing 2.5).
- **Structured concurrency** (JEP 505, preview in 25) makes fan-out fail fast and cancel siblings, which is exactly the shape of P20's DAG executor. The C++ analogue is `std::jthread` + `std::stop_source` (file 02, Listing 2.5), with `std::execution` senders/receivers arriving in C++26 ⚠.
- **Locks still matter.** A virtual thread waiting on `ReentrantLock` unmounts cheaply, but a convoy is still a convoy. The fair-lock measurement in §4.2 applies equally to virtual threads.

---

## 11. Decision guide: which primitive, when

| Problem | First choice | Escalate to | Never |
|---|---|---|---|
| A hot counter (metrics) | `LongAdder` / per-thread padded cells | — | `synchronized` counter; `volatile` `++` |
| An id/sequence generator | `AtomicLong.incrementAndGet` / `fetch_add` | Block allocation (grab 1,000 ids per CAS) | `LongAdder` (no atomic read-modify-write) |
| Single-key read-modify-write in a map | `ConcurrentHashMap.compute`/`merge` with a pure, fast function | Per-key lock object for slow work | `get`-then-`put` |
| A multi-key atomic update | Locks in one global order (per-entity or striped `bulkGet`) | Single-writer event loop (P12) | Locks in request order |
| An aggregate's state machine | `AtomicReference<State>` + pure `transition` | Lock per aggregate when retries get expensive | Field-by-field mutation from many methods |
| A read-mostly small value | Immutable snapshot behind `volatile`/`AtomicReference` | `StampedLock` optimistic / seqlock for larger, frequently written data | `ReentrantReadWriteLock` for tiny critical sections |
| Producer → consumer | `ArrayBlockingQueue` / `LinkedBlockingQueue` | SPSC/MPSC rings (JCTools, P17) | Hand-rolled `wait`/`notify` |
| Wait for an event | `CountDownLatch`, `CompletableFuture`, `Phaser` | Custom AQS (§4) | Spinning or sleeping without a bound |
| Bound concurrency | `Semaphore` | Admission queue with deadlines | An unbounded executor |
| One-time lazy init | Holder idiom / `volatile` DCL; C++ magic static / `call_once` | — | DCL without `volatile` |
| Time-based expiry | Injected `Ticker` + lazy expiry + optional sweeper | Timing wheel (P3) | Wall clock; `Thread.sleep` in tests |

---

## 12. Failure modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Totals drift low under load | Lost increments (18.7% in 3.2) | Check-then-act across atomic calls | `merge`/`compute`, or a lock around the sequence | Review rule: no `get`→`put` on shared maps |
| F2 | Side effect happens 2× | Duplicate log lines or emails per update | Impure function in `updateAndGet`/`compute` | Make the function pure; act after the CAS succeeds | Lint: no I/O inside atomic update lambdas |
| F3 | CAS "never succeeds" | Infinite retry or false failures | Comparing equal but non-identical objects (Java); `-0.0`/NaN bits (C++) | CAS against the instance you read; compare ids | Wrap atomics in domain methods |
| F4 | p99 latency cliff on a hot key | Throughput flat as cores grow | CAS retry storm on one location | `LongAdder`, striping, batching | Measure contention before choosing CAS |
| F5 | Throughput collapses with a fair lock | ~µs per acquisition | Hand-off on every release | Non-fair lock; fairness at admission | Never `new ReentrantLock(true)` without a measurement |
| F6 | Threads stuck forever | `Found one Java-level deadlock` | Locks in request order | Global order; `scoped_lock`; `tryLock` + backoff | `bulkGet`-style helpers; lock-order lint |
| F7 | Unrelated keys stall together | One slow key blocks others | Slow work inside CHM `compute` (bin lock) | Compute outside; insert a future | Code review: no remote calls in `compute` |
| F8 | `IllegalStateException: Recursive update` | From CHM `compute*` | The function touches the same map/bin | Restructure; memoize with futures | Never recurse into CHM from its own compute |
| F9 | Reader thread deadlocks itself | Hangs holding a read lock | RRWL upgrade attempt; StampedLock reentrancy | Release then re-acquire; `tryConvertToWriteLock` | Document: these locks don't upgrade/re-enter |
| F10 | Garbage values or a crash in optimistic readers | Exceptions from torn indices | Using optimistic data before `validate()` | Copy to locals → validate → use | Pattern review; seqlock data atomic in C++ |
| F11 | Scaling stops at 2 cores | High cache misses on writer threads | False sharing between per-thread fields | Padding / `@Contended` / `alignas(128)` | Layout review for per-thread state |
| F12 | Queue throughput varies 2–5× by build | Items per cross-core read low | True sharing of indices in a near-empty/near-full ring | Batching; cached indices | Track items per index read |
| F13 | Holds never expire, or all expire at once | After an NTP correction | Wall clock used for TTL | Monotonic ticker | Inject `Ticker`; ban `Instant.now()` in expiry code |
| F14 | Entries expire immediately on some hosts | `nanoTime` near overflow | `now >= deadline` comparison | `now - deadline >= 0` | Wrap time in a helper with the rule baked in |
| F15 | Flaky time tests | Pass locally, fail in CI | `Thread.sleep` in tests | Fake clock + virtual scheduler | No `sleep` in unit tests (lint) |
| F16 | C++ loop never terminates (`-O2` only) | Spin on a plain `bool` | Data race = UB; the load was hoisted | `std::atomic<bool>` | `-fsanitize=thread` in CI where available |
| F17 | Litmus test "proves" relaxed is safe | Never shows the relaxed outcome | Runtime `memory_order` compiled as seq_cst | Template/constexpr orders; inspect the asm | Litmus tests must show the allowed outcome |
| F18 | Futex-style lock slower than `std::mutex` | Many kernel wake-ups | No spin phase before sleeping | Spin briefly, then park (as AQS does) | Use the platform mutex unless measured otherwise |

---

## 13. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Is <code>volatile</code> enough to make a counter thread-safe?"</b></summary>

**L5:** "Yes, volatile makes it visible to all threads."

**Why it fails:** `count++` is a read, an add and a write. `volatile` orders and publishes each access but doesn't make the three steps atomic. Listing 3.8's racy counter failed in 98% of rounds.

**L7 defence:** "`volatile` gives visibility and ordering, a release/acquire edge or the total order for volatiles, but not atomicity of compound actions. For a sequence number I use `AtomicLong` (one `lock xadd`). For a statistics counter under contention I use `LongAdder`, because its cells avoid the CAS storm. It measured 3.6× faster here, and the trade is that `sum()` isn't a snapshot."
</details>

<details>
<summary><b>Q2 ⚡ "Is <code>setRelease</code>/<code>getAcquire</code> enough for Dekker's or Peterson's algorithm?"</b></summary>

**L5:** "Yes, release/acquire handles ordering."

**Why it fails:** Listing 3.1 observed `(0,0)` 45,603 times per million under release/acquire on x86. Release/acquire forbids moving accesses across the release *downwards* and across the acquire *upwards*, but a release store followed by an acquire load of a *different* variable may still be reordered. That is exactly the store-buffer case.

**L7 defence:** "Mutual exclusion by flags needs a store→load barrier: `volatile`/`seq_cst` (an `xchg` or `mfence` on x86) or an explicit full fence. That's also why production locks use an atomic RMW (CAS) rather than plain flag protocols."
</details>

<details>
<summary><b>Q3 🔥 "Why is <code>ConcurrentHashMap.computeIfAbsent</code> dangerous for a cache loader?"</b></summary>

**L5:** "It isn't; it's atomic."

**Why it fails:** the mapping function runs while the **bin lock** is held. A slow loader blocks every key in the bin (200 ms measured for a bin-mate vs 0.4 ms for another bin). A loader that touches the map recursively throws `Recursive update`.

**L7 defence:** "Keep the function cheap and pure. For a cache, `computeIfAbsent(k, k -> new CompletableFuture<>())` installs a placeholder atomically, then the loader runs *outside* the lock and completes the future. Concurrent callers share the future (no stampede), and other bins are never blocked. That's the shape of P1 and of Caffeine's async loading."
</details>

<details>
<summary><b>Q4 ⚡ "When does <code>ReentrantReadWriteLock</code> beat a plain lock?"</b></summary>

**L5:** "Whenever reads outnumber writes."

**Why it fails:** each read acquisition still writes the shared reader count. With short critical sections, 3 readers got 12.0 M reads/s under RRWL vs 18.7 M under `synchronized` (C++ `shared_mutex`: 2.6–12.8 M vs mutex 21–35 M).

**L7 defence:** "RW locks pay off when the read section is long relative to the cache-line transfer, say tens of microseconds of work. For short reads, use optimistic reading (`StampedLock`, 248 M reads/s here) with copy-then-validate, or an immutable snapshot behind an `AtomicReference`, whose readers do one acquire load and no writes."
</details>

<details>
<summary><b>Q5 🧊 "Write a seqlock in C++. What's wrong with reading the data as plain fields?"</b></summary>

**L5:** "Nothing; the sequence check discards torn reads."

**Why it fails:** under the C++ model the racy plain read is a data race, which is UB before any check happens. The compiler may assume no concurrent writer and transform the code accordingly.

**L7 defence:** "Make the data fields `std::atomic` and access them relaxed. The writer does an odd store, a release fence, the data stores, then an even store with release. The reader does an acquire load of the sequence, relaxed data loads, an acquire fence, and re-checks the sequence (Boehm 2012). Java's `StampedLock` can read plain fields because Java defines racy reads; C++ doesn't. Writers must be serialized separately."
</details>

<details>
<summary><b>Q6 ⚡ "How would you test a 5-minute expiry and a periodic sweeper?"</b></summary>

**L5:** "Use a 1-second TTL and sleep."

**Why it fails:** it tests a different configuration, is slow and flaky, never pins the boundary, and can't check scheduling order.

**L7 defence:**
- "Inject a `Ticker` for durations and a `Clock` only for timestamps.
- Test `deadline − 1 ns` and `deadline`.
- Drive periodic work with a virtual-time scheduler that runs each task at its own deadline, FIFO for ties, with cancellation. Then assert the exact log: sweeps at 60/120/180 s, a cancelled timeout that never fired.
- Compare `nanoTime` deadlines by difference, so values near `Long.MAX_VALUE` don't expire instantly. In C++, saturate 'forever' instead of overflowing."
</details>

<details>
<summary><b>Q7 🧊 "Your lock-free stack works in Java. Port it to C++ — what breaks?"</b></summary>

**L5:** "Nothing; use `std::atomic<Node*>`."

**Why it fails:** Java's GC guarantees a popped node's memory isn't reused while another thread still holds a reference, so pointer-ABA can't happen. In C++, `delete` plus a new allocation can return the same address. A thread whose CAS expected the old `head` then succeeds against a different node: ABA. It may also dereference freed memory.

**L7 defence:** "I need safe memory reclamation: hazard pointers (C++26 `std::hazard_pointer` ⚠), epoch-based reclamation, or reference counting. Or I avoid reuse ABA with a tagged pointer (version counter in spare bits, or a double-width CAS). Often the right answer is not to write it: use a mutex-protected `std::vector`, or a vetted library (Folly, Boost.Lockfree, libcds), and measure first."
</details>

---

## 14. Invariants checklist

- [ ] Every shared mutable variable has exactly one documented protection: a named lock, an atomic with a named memory order, or confinement to one thread.
- [ ] No compound action spans multiple atomic calls without a lock or a single atomic operation.
- [ ] Functions passed to `updateAndGet`/`compute`/`merge` are pure and fast.
- [ ] All multi-lock acquisitions follow one global order (sorted, de-duplicated), or use `std::scoped_lock`.
- [ ] No lock is held across I/O, callbacks, or `ConcurrentHashMap.compute` recursion.
- [ ] Optimistic reads copy to locals and `validate` before use; seqlock data is atomic in C++.
- [ ] Per-thread hot fields are padded (64 B minimum, 128 B for portability); queue indices are owner-separated.
- [ ] Durations use a monotonic, injected ticker, compared by difference; timestamps use an injected `Clock`/`InstantSource`.
- [ ] Concurrency tests assert invariants per round, spin-gate the start, time out with diagnosis, and replay operations from a seed.
- [ ] C++: no data races (every shared access atomic or locked), memory orders are compile-time constants, threads are `jthread`s or deliberately managed on timeout.

---

## 15. References

- Java Language Specification SE 21, ch. 17 "Threads and Locks". <https://docs.oracle.com/javase/specs/jls/se21/html/jls-17.html>
- Doug Lea, "The JSR-133 Cookbook for Compiler Writers". <https://gee.cs.oswego.edu/dl/jmm/cookbook.html>
- Doug Lea, "Using JDK 9 Memory Order Modes". <https://gee.cs.oswego.edu/dl/html/j9mm.html>
- Doug Lea, "The java.util.concurrent Synchronizer Framework", 2004 (AQS). <https://gee.cs.oswego.edu/dl/papers/aqs.pdf>
- Aleksey Shipilëv, "Java Memory Model Pragmatics". <https://shipilev.net/blog/2014/jmm-pragmatics/>
- Aleksey Shipilëv, "Close Encounters of The Java Memory Model Kind". <https://shipilev.net/blog/2016/close-encounters-of-jmm-kind/>
- Aleksey Shipilëv, "Safe Publication and Safe Initialization in Java". <https://shipilev.net/blog/2014/safe-public-construction/>
- Hans-J. Boehm and Sarita V. Adve, "Foundations of the C++ Concurrency Memory Model", PLDI 2008. <https://doi.org/10.1145/1375581.1375591>
- Hans-J. Boehm, "Can Seqlocks Get Along with Programming Language Memory Models?", MSPC 2012. <https://doi.org/10.1145/2247684.2247688>
- C/C++11 mappings to processors (Sewell et al., Cambridge). <https://www.cl.cam.ac.uk/~pes20/cpp/cpp0xmappings.html>
- Ulrich Drepper, "Futexes Are Tricky". <https://www.akkadia.org/drepper/futex.pdf>
- Jeff Preshing, "Memory Reordering Caught in the Act". <https://preshing.com/20120515/memory-reordering-caught-in-the-act/>
- Herb Sutter, "atomic<> Weapons" (2012 talk). <https://herbsutter.com/2013/02/11/atomic-weapons-the-c-memory-model-and-modern-hardware/>
- Martin Thompson, "False Sharing". <https://mechanical-sympathy.blogspot.com/2011/07/false-sharing.html>
- LMAX Disruptor technical paper. <https://lmax-exchange.github.io/disruptor/disruptor.html>
- JCTools (lock-free queues for the JVM). <https://github.com/JCTools/JCTools>
- Erik Rigtorp, SPSCQueue. <https://github.com/rigtorp/SPSCQueue>
- Guava `Striped`. <https://guava.dev/releases/snapshot-jre/api/docs/com/google/common/util/concurrent/Striped.html>
- OpenJDK jcstress. <https://github.com/openjdk/jcstress> · JetBrains Lincheck. <https://github.com/JetBrains/lincheck>
- JDK source: `AbstractQueuedSynchronizer`, `StampedLock`, `ConcurrentHashMap`, `LongAdder` (`java.util.concurrent`). <https://github.com/openjdk/jdk/tree/master/src/java.base/share/classes/java/util/concurrent>
- cppreference: `std::memory_order` <https://en.cppreference.com/w/cpp/atomic/memory_order> · `std::atomic::wait` <https://en.cppreference.com/w/cpp/atomic/atomic/wait>
- Brian Goetz et al., *Java Concurrency in Practice*: ch. 3 (publication), 10 (deadlock), 12 (testing), 14 (AQS), 15 (atomics).
- In this KB: [01 · Rubric](01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md) (the seat-hold exhibit that uses these primitives) · [02 · SOLID and DOP](02-solid-composition-and-data-oriented-java21-sealed-records.md) (ADTs, typestate, layout).
