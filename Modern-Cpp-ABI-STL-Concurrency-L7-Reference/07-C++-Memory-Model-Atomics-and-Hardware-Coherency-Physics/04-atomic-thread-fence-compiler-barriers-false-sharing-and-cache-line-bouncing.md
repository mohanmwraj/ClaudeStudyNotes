# 04 · `atomic_thread_fence`, compiler barriers, false sharing, and cache-line bouncing

> **Scope.** Two topics that interviewers tend to blur. **Fences** are ordering without a variable: what
> `atomic_thread_fence` and `atomic_signal_fence` compile to, when a fence is cheaper than an ordered operation (and when
> it is a full barrier in disguise), and why `asm volatile("" ::: "memory")` orders nothing in hardware. **Cache lines**
> are the unit of coherence: false sharing between per-thread counters, true sharing on one atomic, and the
> test-and-set vs test-and-test-and-set spin lock, all measured on this machine.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 7.14 | `fences_asm.cpp` | acquire/release/acq_rel fences emit nothing on x86 and `DMB ISHLD`/`DMB ISH` on AArch64; a `seq_cst` fence is `LOCK OR` to the stack (not `MFENCE`); signal fences and asm barriers emit nothing but stop store merging | asm: Clang x86-64, GCC x86-64, Clang AArch64 |
| 7.15 | `false_sharing.cpp` | private counters 8 bytes apart cost 3–4× padded ones with 2–4 threads; one shared `fetch_add` costs 9–47 ns | run, 1/2/4 threads, both compilers |
| 7.16 | `spin_bounce.cpp` | TAS, TTAS and TTAS + `PAUSE` spin locks under contention: `PAUSE` helps in every run, TTAS vs TAS is within noise at 4 threads | run, 1/2/4 threads, both compilers |

**Verification line.** As in file 01 (Intel Core i5-11260H, 6 cores / 12 threads, 64-byte lines; 48 KB L1D and 1.25 MB L2
per core, 12 MB L3). AArch64 is compiled, not run (⚠).

---

## 1. First principles

### 1.1 Fences (Listing 7.14)

```cpp
// fences_asm.cpp - atomic_thread_fence vs ordered operations, atomic_signal_fence, and compiler-only barriers
#include <atomic>

void fence_acquire() { std::atomic_thread_fence(std::memory_order_acquire); }
void fence_release() { std::atomic_thread_fence(std::memory_order_release); }
void fence_acq_rel() { std::atomic_thread_fence(std::memory_order_acq_rel); }
void fence_seq_cst() { std::atomic_thread_fence(std::memory_order_seq_cst); }
void signal_fence_seq_cst() { std::atomic_signal_fence(std::memory_order_seq_cst); }   // compiler-only

// Publishing with a release STORE vs a release FENCE followed by a relaxed store.
void publish_store(int* data, std::atomic<int>& flag) {
    *data = 42;
    flag.store(1, std::memory_order_release);
}
void publish_fence(int* data, std::atomic<int>& flag) {
    *data = 42;
    std::atomic_thread_fence(std::memory_order_release);   // orders ALL earlier memory ops before ALL later stores
    flag.store(1, std::memory_order_relaxed);
}
// Consuming: an acquire load per iteration vs relaxed polling and ONE acquire fence after the loop.
int consume_load(const int* data, const std::atomic<int>& flag) {
    while (flag.load(std::memory_order_acquire) == 0) {
    }
    return *data;
}
int consume_fence(const int* data, const std::atomic<int>& flag) {
    while (flag.load(std::memory_order_relaxed) == 0) {
    }
    std::atomic_thread_fence(std::memory_order_acquire);
    return *data;
}

// Compiler barriers: two plain stores to the same int merge into one unless something stops the compiler.
void two_stores_plain(int* p) {
    *p = 1;
    *p = 2;
}
void two_stores_asm_barrier(int* p) {
    *p = 1;
    asm volatile("" ::: "memory");   // GCC/Clang: the compiler must assume memory is read and written here
    *p = 2;
}
void two_stores_signal_fence(int* p) {
    *p = 1;
    std::atomic_signal_fence(std::memory_order_seq_cst);
    *p = 2;
}
```

The ordering-relevant instructions per function (generated from the three asm outputs):

```text
fence_acquire:
  x86-64 Clang 21  (nothing)
  x86-64 GCC 16    (nothing)
  AArch64 v8.0     dmb ishld

fence_release:
  x86-64 Clang 21  (nothing)
  x86-64 GCC 16    (nothing)
  AArch64 v8.0     dmb ish

fence_acq_rel:
  x86-64 Clang 21  (nothing)
  x86-64 GCC 16    (nothing)
  AArch64 v8.0     dmb ish

fence_seq_cst:
  x86-64 Clang 21  lock orl $0, -64(%rsp)
  x86-64 GCC 16    lock orq $0, (%rsp)
  AArch64 v8.0     dmb ish

signal_fence_seq_cst:
  x86-64 Clang 21  (nothing)
  x86-64 GCC 16    (nothing)
  AArch64 v8.0     (nothing)

publish_store:
  x86-64 Clang 21  movl $42, (%rdi) ; movl $1, (%rsi)
  x86-64 GCC 16    movl $42, (%rdi) ; movl $1, (%rsi)
  AArch64 v8.0     mov w8, #42 ; mov w9, #1 ; str w8, [x0] ; stlr w9, [x1]

publish_fence:
  x86-64 Clang 21  movl $42, (%rdi) ; movl $1, (%rsi)
  x86-64 GCC 16    movl $42, (%rdi) ; movl $1, (%rsi)
  AArch64 v8.0     mov w8, #42 ; str w8, [x0] ; mov w8, #1 ; dmb ish ; str w8, [x1]

consume_load:
  x86-64 Clang 21  movl (%rsi), %eax ; testl %eax, %eax ; je .LBB7_1 ; movl (%rdi), %eax
  x86-64 GCC 16    movl (%rsi), %eax ; testl %eax, %eax ; je .L10 ; movl (%rdi), %eax
  AArch64 v8.0     ldar w8, [x1] ; cbz w8, .LBB7_1 ; ldr w0, [x0]

consume_fence:
  x86-64 Clang 21  movl (%rsi), %eax ; testl %eax, %eax ; je .LBB8_1 ; movl (%rdi), %eax
  x86-64 GCC 16    movl (%rsi), %eax ; testl %eax, %eax ; je .L14 ; movl (%rdi), %eax
  AArch64 v8.0     ldr w8, [x1] ; cbz w8, .LBB8_1 ; dmb ishld ; ldr w0, [x0]

two_stores_plain:
  x86-64 Clang 21  movl $2, (%rdi)
  x86-64 GCC 16    movl $2, (%rdi)
  AArch64 v8.0     mov w8, #2 ; str w8, [x0]

two_stores_asm_barrier:
  x86-64 Clang 21  movl $1, (%rdi) ; movl $2, (%rdi)
  x86-64 GCC 16    movl $1, (%rdi) ; movl $2, (%rdi)
  AArch64 v8.0     mov w8, #1 ; str w8, [x0] ; mov w8, #2 ; str w8, [x0]

two_stores_signal_fence:
  x86-64 Clang 21  movl $1, (%rdi) ; movl $2, (%rdi)
  x86-64 GCC 16    movl $1, (%rdi) ; movl $2, (%rdi)
  AArch64 v8.0     mov w8, #1 ; mov w9, #2 ; str w8, [x0] ; str w9, [x0]
```

**What a fence means ([atomics.fences]).** A fence is not attached to a variable. It works through the atomic
operations around it:

```text
  release fence F;  ... ; X.store(v, relaxed)      Y = X.load(relaxed) reads v ; ... ; acquire fence G
  ^ F synchronizes-with G: everything sequenced before F happens before everything sequenced after G.

  The two other combinations: release FENCE + acquire LOAD, and release STORE + acquire FENCE, synchronize the same way.
```

* **Release fence = "all earlier memory operations before *all later stores*"**, not just one store. That is
  stronger than a release store. On AArch64 it needs a full `DMB ISH` (the store-only `DMB ISHST` does not order
  earlier loads). `publish_fence` is `STR`, `DMB ISH`, `STR`, while `publish_store` is `STR` + `STLR`. **On ARM, a
  release fence is more expensive than a release store**; on x86 both are plain `MOV`s.
* **Acquire fence = `DMB ISHLD`** (later loads and stores wait for earlier loads). `consume_fence` polls with plain
  `LDR`s and executes one `DMB ISHLD` after the loop. `consume_load` executes `LDAR` on every iteration. When a loop spins
  many times, the fence version does less ordering work. It is correct only because the fence comes *after* the load
  that observed the flag.
* **`seq_cst` fence = `LOCK OR $0` to the stack on both x86 compilers, not `MFENCE`.** A dummy locked RMW on a line
  the core already owns drains the store buffer, which is all a C++ fence needs on write-back memory, and compilers
  prefer it to `MFENCE`. On AArch64 it is `DMB ISH`.
* **`atomic_signal_fence` emits nothing on any target.** It orders memory only against a signal handler running on the
  *same* thread, so it is a compiler barrier. Both compilers then keep the two stores in `two_stores_signal_fence`,
  exactly as with `asm volatile("" ::: "memory")`. Without either, the stores merge into one (`two_stores_plain`). None
  of these three emits a hardware barrier.

### 1.2 False sharing and true sharing (Listing 7.15)

```cpp
// false_sharing.cpp - per-thread counters: true sharing, false sharing, and padding to 64 or 128 bytes
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <new>
#include <print>
#include <thread>
#include <vector>

constexpr std::int64_t kOps = 4'000'000;

// Each thread updates ONLY its own counter (single writer), so a relaxed load + store is a correct
// increment: no LOCK prefix, no RMW. Any slowdown comes from the cache line, not from the instruction.
template <std::size_t Stride>
struct alignas(Stride) Slot {
    std::atomic<std::int64_t> v{0};
};

template <std::size_t Stride>
double per_thread_counters(int threads) {
    std::vector<Slot<Stride>> slots(static_cast<std::size_t>(threads));   // Stride 8: all in one line
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            // Read the address through a volatile pointer so every stride gets the same instruction
            // (addq $1, (%reg)); otherwise Clang keeps an indexed address for Stride 8, which on this
            // Tiger Lake was 3.7x slower even with ONE thread and would masquerade as false sharing.
            std::atomic<std::int64_t>* volatile pv = &slots[static_cast<std::size_t>(t)].v;
            std::atomic<std::int64_t>& c = *pv;
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {
            }
            for (std::int64_t i = 0; i < kOps; ++i) c.store(c.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
        });
    while (ready.load() != threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    go.store(true, std::memory_order_release);
    ts.clear();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / kOps;   // wall time per increment of ONE thread (all threads run in parallel)
}

// True sharing: everybody increments the same counter (a LOCKed RMW is now required).
double one_shared_counter(int threads) {
    alignas(64) std::atomic<std::int64_t> c{0};
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {
            }
            for (std::int64_t i = 0; i < kOps; ++i) c.fetch_add(1, std::memory_order_relaxed);
        });
    while (ready.load() != threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    go.store(true, std::memory_order_release);
    ts.clear();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / kOps;
}

int main() {
    std::println("hardware_destructive_interference_size = {}", std::hardware_destructive_interference_size);
    std::println("threads  private, 8 B apart  private, 64 B apart  private, 128 B apart  one shared (fetch_add)");
    for (int threads : {1, 2, 4})
        std::println("{:>7}  {:>15.2f} ns  {:>16.2f} ns  {:>17.2f} ns  {:>19.2f} ns", threads,
                     per_thread_counters<8>(threads), per_thread_counters<64>(threads),
                     per_thread_counters<128>(threads), one_shared_counter(threads));
}
```

Output (verified, GCC then Clang):

```text
hardware_destructive_interference_size = 64
threads  private, 8 B apart  private, 64 B apart  private, 128 B apart  one shared (fetch_add)
      1             0.69 ns              0.69 ns               0.67 ns                 4.74 ns
      2             1.68 ns              0.65 ns               0.63 ns                20.61 ns
      4             1.85 ns              0.73 ns               0.89 ns                47.09 ns
hardware_destructive_interference_size = 64
threads  private, 8 B apart  private, 64 B apart  private, 128 B apart  one shared (fetch_add)
      1             0.54 ns              0.47 ns               0.49 ns                 4.74 ns
      2             1.84 ns              0.48 ns               0.47 ns                 9.16 ns
      4             2.01 ns              0.53 ns               0.52 ns                45.92 ns
```

Over repeated runs: with one thread every layout costs 0.47–0.79 ns per increment. With 2–4 threads, **counters 8
bytes apart cost 1.68–2.25 ns, against 0.47–0.89 ns when padded to 64 or 128 bytes**: 3–4× for counters no other thread
reads. One shared counter with `fetch_add` costs 4.6–4.7 ns alone and 9–22 ns with 2 threads. The 9 ns run was most
likely both threads on one core's two hyper-threads, which share an L1; threads are not pinned here. With 4 threads it
costs 39–47 ns per increment, **per thread**. Total throughput falls as threads are added.

* **The mechanism (MESI).** A store needs the line in the Modified/Exclusive state in the writer's L1. When two
  cores write different bytes of one 64-byte line, each store issues a read-for-ownership that invalidates the other
  core's copy, and the line migrates on every increment. The program has no data race and no shared variable; the
  hardware shares the *line*.
* **Single-writer counters need no `LOCK`.** Each thread owns its counter, so `store(load() + 1)` is correct (contrast
  with file 01, Listing 7.2), and Clang compiles it to a non-locked `addq $1, (mem)`. A padded private line stays
  Modified in its core's L1, so the increment costs about 2 cycles.
* **A measurement trap found while writing this listing.** The first version let Clang address the 8-byte-stride slot
  with an indexed operand `(%rcx,%rax,8)` and the others with `(%rax)`. The indexed form was 3.7× slower **with one
  thread**, which would have been reported as false sharing. Reading the slot address through a `volatile` pointer made
  the instruction identical for every stride. Microbenchmarks of memory effects must be checked at the instruction level.
* **64 vs 128 bytes.** No difference here. Intel's L2 spatial prefetcher fetches 128-byte-aligned *pairs* of lines,
  so neighbouring lines can still interfere under some access patterns, and Apple M-series cores use 128-byte lines.
  That's why libraries such as folly and crossbeam pad to 128 bytes on x86-64 and AArch64. Both standard libraries
  here report `hardware_destructive_interference_size` = 64. GCC warns (`-Winterference-size`) when the constant is used
  in a header, because a value that depends on `-mtune` is an ABI hazard.

### 1.3 Cache-line bouncing in spin locks (Listing 7.16)

```cpp
// spin_bounce.cpp - cache-line bouncing in spin locks: test-and-set vs test-and-test-and-set (+ pause)
#include <atomic>
#include <chrono>
#include <cstdint>
#include <print>
#include <thread>
#include <vector>
#if defined(__x86_64__)
#include <immintrin.h>
#endif

inline void cpu_relax() {
#if defined(__x86_64__)
    _mm_pause();                       // PAUSE: yields pipeline resources to the sibling hyper-thread
#elif defined(__aarch64__)
    asm volatile("yield");
#endif
}

// TAS: every waiting iteration is an RMW, so every waiter keeps pulling the line in EXCLUSIVE state.
struct TasLock {
    std::atomic<bool> locked{false};
    void lock() {
        while (locked.exchange(true, std::memory_order_acquire)) {
        }
    }
    void unlock() { locked.store(false, std::memory_order_release); }
};
// TTAS: wait with plain loads (the line stays SHARED in every waiter's cache), RMW only when it looks free.
template <bool Pause>
struct TtasLock {
    std::atomic<bool> locked{false};
    void lock() {
        for (;;) {
            if (!locked.exchange(true, std::memory_order_acquire)) return;
            while (locked.load(std::memory_order_relaxed))
                if constexpr (Pause) cpu_relax();
        }
    }
    void unlock() { locked.store(false, std::memory_order_release); }
};

constexpr int kAcquisitions = 200'000;   // per thread

template <class Lock>
double bench(int threads) {
    alignas(64) Lock lk;
    alignas(64) std::int64_t shared_counter = 0;   // protected by lk
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {
            }
            for (int i = 0; i < kAcquisitions; ++i) {
                lk.lock();
                ++shared_counter;               // a short critical section
                lk.unlock();
            }
        });
    while (ready.load() != threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    go.store(true, std::memory_order_release);
    ts.clear();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    if (shared_counter != static_cast<std::int64_t>(threads) * kAcquisitions) std::println("MUTUAL EXCLUSION BROKEN");
    return d.count() / (static_cast<double>(threads) * kAcquisitions);
}

int main() {
    std::println("threads   TAS ns/acq   TTAS ns/acq   TTAS+pause ns/acq");
    for (int threads : {1, 2, 4})
        std::println("{:>7}   {:>10.1f}   {:>11.1f}   {:>17.1f}", threads, bench<TasLock>(threads),
                     bench<TtasLock<false>>(threads), bench<TtasLock<true>>(threads));
}
```

Output (verified, GCC then Clang):

```text
threads   TAS ns/acq   TTAS ns/acq   TTAS+pause ns/acq
      1          6.8           7.0                 7.1
      2         27.3          18.1                14.9
      4         54.4          35.4                31.1
threads   TAS ns/acq   TTAS ns/acq   TTAS+pause ns/acq
      1          6.9           7.0                 6.9
      2         34.7          25.8                17.7
      4         65.4          66.9                52.8
```

Over repeated runs (ns per lock/unlock pair, short critical section): 1 thread, 6.4–7.7 ns for all three. 2 threads:
TAS 21–38, TTAS 18–52, TTAS + `PAUSE` 15–31. 4 threads: TAS 47–65, TTAS 35–67, TTAS + `PAUSE` 20–53.

* **TAS** spins with `exchange`, an RMW that needs the line exclusive. Every waiter keeps stealing the line from the
  holder and from each other.
* **TTAS** spins with plain loads. Waiters share the line read-only, and only an apparently free lock triggers the
  `exchange`. On unlock, though, every waiter sees the invalidation and attempts the exchange at once (a thundering
  herd). At 2–4 threads on 6 cores that herd is small, which is why TTAS vs TAS is within run-to-run noise here. The
  advantage grows with the number of spinning cores.
* **`PAUSE`** was the best variant in every run. It slows the polling loop (on Skylake and later Intel cores PAUSE takes
  on the order of a hundred cycles), hands resources to the sibling hyper-thread, and avoids the memory-order
  mis-speculation flush when the line finally changes.
* Past a few threads the answer is not a better spin: it is a queue lock (MCS or CLH: each waiter spins on its own line;
  Folder 11, problem 12) or a futex-based mutex that sleeps (Folder 08).

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| fences | `atomic_thread_fence`, `atomic_signal_fence` | — | — | `seq_cst` fence semantics strengthened (P0668) | — | — |
| cache-line size | — (Boost/folly constants) | — | `hardware_destructive_interference_size`, `hardware_constructive_interference_size` (P0154) | — | — | — |
| waiting | spin or condition variable | — | — | `atomic::wait`/`notify` (P1135), `std::barrier`, `std::latch` | — | — |
| per-object alignment | `alignas` | — | over-aligned `new` (P0035) | — | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| per-thread statistics | `std::vector<std::atomic<int64_t>> counters(nthreads)` (8 bytes apart, 3–4× slower) | `struct alignas(128) Slot { std::atomic<int64_t> v; };`, or a `thread_local` accumulator flushed periodically |
| global hit counter on a hot path | one `atomic::fetch_add` (39–47 ns at 4 threads, Listing 7.15) | sharded counters summed on read; an approximate counter |
| a hot struct with a producer field and a consumer field | `struct { atomic<size_t> head, tail; }` | `alignas(128)` each written-by-different-threads field (Folder 09 SPSC ring) |
| publishing with fences on ARM | release fence + relaxed store "because fences are cheap" | release store (`STLR`); use fences when one barrier covers many stores |
| spin-wait for a flag set by another thread | `while (!flag.load(acquire)) {}` | `while (!flag.load(relaxed)) pause(); atomic_thread_fence(acquire);`, or `flag.wait(false)` |
| spin lock | `while (locked.exchange(true)) {}` | TTAS + `PAUSE` with a bounded spin, then block (futex/`atomic::wait`); MCS for many cores |
| "compiler barrier" to order threads | `asm volatile("" ::: "memory")` | real atomics/fences; compiler barriers only for signal handlers, interrupt contexts on a single core, benchmarks |
| non-temporal stores then publish | `_mm_stream_si128(...)` + `flag.store(1, release)` | `_mm_sfence()` before the release store |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a parallel loop scales worse than linearly with no locks in sight | false sharing of per-thread data | `perf c2c` (HITM events) on Linux; VTune memory access; pad and remeasure |
| one atomic counter dominates the profile at high core counts | true sharing (line migration on every RMW) | ns/op vs thread count (Listing 7.15 shape) |
| a spin lock's throughput collapses as cores are added | TAS bouncing or TTAS thundering herd | lock-holder vs waiter cycles; switch to MCS/futex |
| fence-based code correct on x86, broken on ARM | the fence on the wrong side of the load/store it should order | check the fence follows the observing load (acquire) or precedes the publishing store (release) |
| data published with streaming stores read stale | NT stores are not ordered by a release `MOV` | `SFENCE` before publishing |
| benchmark numbers that change with an unrelated layout tweak | addressing-mode or alignment artefacts | read the hot loop's asm (§1.2 trap) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 ⚡ "Release fence or release store?"</b></summary>

**Initial prompt.** "To publish a buffer we do `atomic_thread_fence(release); ready.store(true, relaxed);`. A colleague
says a release store is better. Who's right?"

**L5 textbook answer.** "They're the same thing; the fence is just more flexible."

**Why L5 breaks.** Same guarantee for this one store, different cost and scope. A release fence orders earlier accesses
before **all** later stores, so it has to be a full `DMB ISH` on AArch64, while a release store is `STLR` (Listing 7.14:
`publish_fence` vs `publish_store`). On x86 both are free. A fence also does nothing on its own: it needs an atomic
store after it, read by an acquire on the other side.

**L7 principal defense.** "Release store for publishing one value. A release fence when one barrier must cover several
subsequent relaxed stores (publishing to multiple flags or slots), or in generic code that receives the store's order as
a parameter. I check the AArch64 output to see which barrier I'm actually buying."
</details>

<details><summary><b>Chain 2 🔥 "Where does the acquire fence go?"</b></summary>

**Initial prompt.** "We poll `flag` in a loop. To avoid an `LDAR` per iteration, we put
`atomic_thread_fence(acquire)` before the loop and use relaxed loads. OK?"

**L5 textbook answer.** "Yes: the fence makes the following loads acquire loads."

**Why L5 corrupts memory on ARM64.** An acquire fence orders loads that come **before** it against accesses after it.
It must follow the load that observed the flag. Placed before the loop, it orders nothing useful: the relaxed `LDR` that
finally sees `flag == 1` and the subsequent data loads can be reordered, so the data can be read stale on ARM64. On x86
it "works" because every load is already acquire.

**L7 principal defense.** "Relaxed loads in the loop, then `atomic_thread_fence(acquire)` **after** the loop
(`consume_fence` in Listing 7.14: `LDR` loop, then one `DMB ISHLD`). It pairs with a release store or release fence on
the writer's side. If the loop usually exits on the first check, an acquire load is simpler and just as fast."
</details>

<details><summary><b>Chain 3 🔥 "Is asm volatile("" ::: "memory") a memory barrier?"</b></summary>

**Initial prompt.** "Our codebase uses a `COMPILER_BARRIER()` macro (`asm volatile("" ::: "memory")`) between writing
a message and setting the 'ready' flag. Is that enough between threads?"

**L5 textbook answer.** "Yes, it's a memory barrier: it stops reordering."

**Why L5 corrupts memory on ARM64.** It stops the *compiler* from reordering or merging memory accesses across it
(Listing 7.14: `two_stores_asm_barrier` keeps both stores). It emits **no instruction**, so the CPU may still reorder.
On AArch64 the message stores and the flag store are plain `STR`s that another core can observe in any order (the MP
pattern), and the flag is a non-atomic variable, a data race. On x86, TSO hides the hardware half of the bug.

**L7 principal defense.** "Between threads: ordered atomics or `atomic_thread_fence`. `atomic_signal_fence` is the
portable compiler-only barrier, for a signal handler on the same thread, a single-core interrupt context, or keeping a
benchmark's stores alive. Legacy `COMPILER_BARRIER` macros in threaded code are a review red flag."
</details>

<details><summary><b>Chain 4 ⚠ "Streaming stores and a release flag"</b></summary>

**Initial prompt.** "We fill a 1 MB frame with `_mm_stream_si128` (bypassing the cache) and then
`ready.store(true, release)`. Readers acquire `ready`. Correct on x86?"

**L5 textbook answer.** "Yes. x86 is TSO, and release keeps earlier stores before the flag."

**Why L5 corrupts memory on x86.** Non-temporal stores are **weakly ordered** even on x86: they go through
write-combining buffers and may become visible after later ordinary stores. TSO's store→store ordering does not cover
them. The release store is a plain `MOV` (file 02) and drains nothing, and C++ atomics don't model streaming stores at
all. A reader can see `ready` and then stale frame data. (A `seq_cst` store or fence would happen to help, because any
`LOCK`ed instruction also evicts the write-combining buffers per the Intel SDM, but that is an x86 detail the C++ code
shouldn't depend on silently.)

**L7 principal defense.** "`_mm_sfence()` after the streaming stores and before the release store: the documented,
cheapest fence for exactly this. It is one of the few places where a hand-placed hardware fence is still needed in x86
C++. The same applies to other weakly ordered x86 memory: write-combining (WC) mappings, and the fast-string
`rep movsb`/`stosb` stores, which the SDM allows to become visible out of order."
</details>

<details><summary><b>Chain 5 🧊 "Pad to 64 bytes: that's the cache line, done"</b></summary>

**Initial prompt.** "Why do folly and crossbeam pad to 128 bytes on x86-64 when the line is 64?"

**L5 textbook answer.** "Over-engineering. `std::hardware_destructive_interference_size` is 64; use that."

**Why L5 breaks.** Intel's L2 spatial prefetcher brings in the 128-byte-aligned *pair* of a missed line, so two hot
lines in one pair can interfere. Apple's M-series cores have 128-byte lines. And the standard constant is a
compile-time value that GCC derives from `-mtune`, which is why GCC warns about using it in headers
(`-Winterference-size`). Honestly reported: Listing 7.15 shows no 64-vs-128 difference *for this access pattern on this
Tiger Lake*. The 128-byte choice is a portable worst case, not something this benchmark proves.

**L7 principal defense.** "A project-wide `constexpr std::size_t kCacheLinePad = 128;` on x86-64 and AArch64, used with
`alignas` for every field written by a different thread than its neighbours. It's fixed, so no ABI drift across
`-mtune`, and validated with a padded-vs-unpadded benchmark on the production hardware."
</details>

<details><summary><b>Chain 6 ⚡ "Each thread has its own counter, so there's no contention"</b></summary>

**Initial prompt.** "Workers increment `stats[thread_id]` in a `std::vector<std::atomic<int64_t>>`. No thread touches
another's element. Why doesn't it scale?"

**L5 textbook answer.** "It should scale: there's no shared data. Maybe the atomics are slow; use plain ints."

**Why L5 breaks.** The elements share cache lines: eight 8-byte counters per 64-byte line. Every increment needs the
line exclusive, so the line ping-pongs between cores. Listing 7.15: 1.7–2.25 ns per increment instead of about 0.5 ns
when padded, with only 2–4 threads; the gap widens with more cores and across sockets. Plain `int`s would make it a data
race whenever a reader sums them, and the coherence traffic would be the same.

**L7 principal defense.** "One 128-byte-aligned slot per thread (or per core), or a `thread_local` accumulator
published every N increments. Readers sum the slots with relaxed loads, because a statistic tolerates a slightly stale
total. I'd verify the fix with `perf c2c` HITM counts on Linux."
</details>

<details><summary><b>Chain 7 🔥 "TTAS always beats TAS"</b></summary>

**Initial prompt.** "Write a spin lock. Why is test-and-test-and-set better than test-and-set?"

**L5 textbook answer.** "TTAS spins on a cached read, so waiters don't generate bus traffic. It always wins."

**Why L5 breaks.** Partly. TTAS waiters share the line read-only while the lock is held, but at every unlock they all
see the invalidation and all try the `exchange`: a thundering herd of RFOs. Listing 7.16 on 6 cores: at 4 threads, TAS
47–65 ns, TTAS 35–67 ns, within noise of each other. Only TTAS + `PAUSE` (20–53 ns) was consistently better. Without
`PAUSE` the polling loop also starves the sibling hyper-thread.

**L7 principal defense.** "TTAS + `PAUSE` (`YIELD`/`WFE` on ARM), a bounded spin, then block on a futex/`atomic::wait`.
That's how glibc's adaptive mutexes and most production locks behave (Folder 08). For many cores contending on one lock,
MCS/CLH queue locks: each waiter spins on its own cache line and the holder hands over to exactly one successor
(Folder 11). And first ask whether the lock can be sharded away."
</details>

<details><summary><b>Chain 8 ⚡ "Why is one shared counter 10× slower with 4 threads?"</b></summary>

**Initial prompt.** "An uncontended `fetch_add` is about 5 ns. With 4 threads it's 40+ ns per increment. The LOCK
prefix is the same; what changed?"

**L5 textbook answer.** "Lock contention: the threads wait for each other's LOCK."

**Why L5 breaks.** There is no lock to wait for. The *cache line* is the serialization point. A `LOCK XADD` executes
locally once its core owns the line in the Modified state. With 4 writers, the line migrates to a different core for
nearly every increment, and each migration is a cross-core coherence transaction of tens of nanoseconds (Listing 7.15:
4.6–4.7 ns alone, 39–47 ns with 4 threads, per thread). Throughput doesn't just fail to scale; it drops.

**L7 principal defense.** "Contended RMWs on one line cost one coherence round-trip each, whatever the instruction.
The fix is structural: shard (per-core counters), batch (combine locally, publish rarely), or approximate. For
'is anyone left' checks (a refcount at zero, a latch), keep the shared RMW but take it off the per-item path."
</details>

---

## 6. Invariants checklist

- [ ] Fences are placed *after* the observing load (acquire) and *before* the publishing store (release).
- [ ] No compiler-only barrier is used to order memory between threads.
- [ ] `SFENCE` separates non-temporal stores from the release that publishes them.
- [ ] Every field written by a different thread than its neighbours is padded with a project-wide constant (128 on
      x86-64/AArch64).
- [ ] Hot shared counters are sharded or batched; contention is measured as ns/op vs thread count.
- [ ] Spin locks use TTAS + pause with bounded spinning, then block.
- [ ] Memory microbenchmarks are checked at the instruction level before conclusions are drawn.

## 7. References

- [atomics.fences]: <https://eel.is/c++draft/atomics.fences>
- P0154R1 (`hardware_*_interference_size`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0154r1.html>
- Intel 64 and IA-32 Architectures Software Developer's Manual, Vol. 3A §9.2 (memory ordering) and Optimization Reference
  Manual (spatial prefetcher, PAUSE latency): <https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html>
- J. Mellor-Crummey, M. Scott, "Algorithms for Scalable Synchronization on Shared-Memory Multiprocessors", 1991 (MCS lock): <https://www.cs.rochester.edu/u/scott/papers/1991_TOCS_synch.pdf>
- `perf c2c` (cache-to-cache false-sharing analysis): <https://man7.org/linux/man-pages/man1/perf-c2c.1.html>
- crossbeam `CachePadded` (per-architecture padding choices): <https://docs.rs/crossbeam-utils/latest/crossbeam_utils/struct.CachePadded.html>
- folly `hardware_destructive_interference_size`: <https://github.com/facebook/folly/blob/main/folly/lang/Align.h>
