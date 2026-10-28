# 02 · Curated source code: Abseil, folly, libunifex, stdexec, and the CppCon reading list

> **Scope.** This KB has rebuilt each mechanism from first principles: Swiss tables, futex mutexes, hazard pointers,
> Chase-Lev deques, senders. The production versions live in a small number of open-source code bases, and reading them
> is how an L7 engineer stays calibrated. This file has five parts. It measures what the standard library on this
> toolchain actually ships, so you know which features still come from libraries (Listing 12.4). It gives a method for
> reading concurrency code. It does one full **reading drill**: a claim from folly's source, reproduced and measured on
> x86-64 and AArch64 (Listing 12.5). It gives a curated list of source files, each with what to look for and the KB
> folder it calibrates. And it closes with the books, papers and talks, and a study plan.
> Every repository path below was checked to exist at the time of writing.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 12.4 | `feature_matrix.cpp` | the library feature-test macros under `-std=c++26`. libstdc++ 16 and libc++ 21 share the C++20 concurrency vocabulary, except that libc++ has no `atomic<shared_ptr>`. libc++ lacks `generator`, `move_only_function`, `inplace_vector`, `function_ref`, atomic `fetch_max`, contracts and `<debugging>`, all of which GCC 16 ships. **Neither** ships senders, hazard pointers, RCU, `hive`, `simd`, `stacktrace` or `text_encoding` | run, both libraries (deterministic) |
| 12.5 | `asymmetric_fence.cpp` | folly's asymmetric fence, reproduced. The reader's `seq_cst` fence (`lock or` / `dmb ish`) becomes *no instruction*, and the cost moves to a rare process-wide barrier. Measured: 4.6–4.8 ns → 0.2–0.4 ns per protect; the heavy side costs 0.25–0.42 µs alone and 1.95–2.34 µs with 6 busy threads, a break-even of 440–540 protects per heavy call | asm, x86-64 and AArch64; run, both compilers (timing-dependent) |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (zig, libc++), `-O2 -Wall -Wextra -Wpedantic
-Werror -Wshadow -Wconversion -Wsign-conversion`. Assembly from Clang 21 `-O3` targeting x86-64 and AArch64 Linux. The
machine has 12 logical CPUs; the heavy side runs on Windows as `FlushProcessWriteBuffers`.

---

## 1. First principles

### 1.1 The standard library is the floor (Listing 12.4)

```cpp
// feature_matrix.cpp - which C++20/23/26 library features this toolchain actually ships (library feature-test macros)
#include <print>
#include <version>

#define ROW(name, macro_text, present, value) std::println("  {:<36} {:<32} {}", name, macro_text, present ? value : "-")
#define FEATURE(name, macro)                                                         \
    do {                                                                             \
        if constexpr (sizeof(#macro) != sizeof(XSTR(macro))) ROW(name, #macro, true, XSTR(macro)); \
        else ROW(name, #macro, false, "");                                           \
    } while (0)
#define STR(x) #x
#define XSTR(x) STR(x)

int main() {
    std::println("C++ library features (value of the __cpp_lib_ macro; - = not provided), with -std=c++26:");
    // A macro that is not defined stringizes to its own name, so the two strings have the same length.
    FEATURE("std::atomic_ref (C++20)", __cpp_lib_atomic_ref);
    FEATURE("std::atomic<shared_ptr> (C++20)", __cpp_lib_atomic_shared_ptr);
    FEATURE("atomic wait/notify (C++20)", __cpp_lib_atomic_wait);
    FEATURE("std::jthread + stop_token (C++20)", __cpp_lib_jthread);
    FEATURE("std::counting_semaphore (C++20)", __cpp_lib_semaphore);
    FEATURE("std::latch (C++20)", __cpp_lib_latch);
    FEATURE("std::barrier (C++20)", __cpp_lib_barrier);
    FEATURE("coroutine support (C++20)", __cpp_lib_coroutine);
    FEATURE("std::expected (C++23)", __cpp_lib_expected);
    FEATURE("std::print (C++23)", __cpp_lib_print);
    FEATURE("std::flat_map (C++23)", __cpp_lib_flat_map);
    FEATURE("std::mdspan (C++23)", __cpp_lib_mdspan);
    FEATURE("std::generator (C++23)", __cpp_lib_generator);
    FEATURE("std::move_only_function (C++23)", __cpp_lib_move_only_function);
    FEATURE("std::stacktrace (C++23)", __cpp_lib_stacktrace);
    FEATURE("std::inplace_vector (C++26)", __cpp_lib_inplace_vector);
    FEATURE("std::function_ref (C++26)", __cpp_lib_function_ref);
    FEATURE("std::copyable_function (C++26)", __cpp_lib_copyable_function);
    FEATURE("saturation arithmetic (C++26)", __cpp_lib_saturation_arithmetic);
    FEATURE("std::atomic fetch_max/min (C++26)", __cpp_lib_atomic_min_max);
    FEATURE("std::execution senders (C++26)", __cpp_lib_senders);
    FEATURE("hazard pointers (C++26)", __cpp_lib_hazard_pointer);
    FEATURE("RCU (C++26)", __cpp_lib_rcu);
    FEATURE("std::hive (C++26)", __cpp_lib_hive);
    FEATURE("std::simd (C++26)", __cpp_lib_simd);
    FEATURE("std::linalg (C++26)", __cpp_lib_linalg);
    FEATURE("reflection <meta> (C++26)", __cpp_lib_reflection);
    FEATURE("contracts <contracts> (C++26)", __cpp_lib_contracts);
    FEATURE("std::text_encoding (C++26)", __cpp_lib_text_encoding);
    FEATURE("<debugging> breakpoint (C++26)", __cpp_lib_debugging);
}
```

GCC 16.2 / libstdc++:

```text
C++ library features (value of the __cpp_lib_ macro; - = not provided), with -std=c++26:
  std::atomic_ref (C++20)              __cpp_lib_atomic_ref             202603L
  std::atomic<shared_ptr> (C++20)      __cpp_lib_atomic_shared_ptr      201711L
  atomic wait/notify (C++20)           __cpp_lib_atomic_wait            201907L
  std::jthread + stop_token (C++20)    __cpp_lib_jthread                201911L
  std::counting_semaphore (C++20)      __cpp_lib_semaphore              201907L
  std::latch (C++20)                   __cpp_lib_latch                  201907L
  std::barrier (C++20)                 __cpp_lib_barrier                201907L
  coroutine support (C++20)            __cpp_lib_coroutine              201902L
  std::expected (C++23)                __cpp_lib_expected               202211L
  std::print (C++23)                   __cpp_lib_print                  202406L
  std::flat_map (C++23)                __cpp_lib_flat_map               202511L
  std::mdspan (C++23)                  __cpp_lib_mdspan                 202406L
  std::generator (C++23)               __cpp_lib_generator              202207L
  std::move_only_function (C++23)      __cpp_lib_move_only_function     202110L
  std::stacktrace (C++23)              __cpp_lib_stacktrace             -
  std::inplace_vector (C++26)          __cpp_lib_inplace_vector         202603L
  std::function_ref (C++26)            __cpp_lib_function_ref           202603L
  std::copyable_function (C++26)       __cpp_lib_copyable_function      202306L
  saturation arithmetic (C++26)        __cpp_lib_saturation_arithmetic  202603L
  std::atomic fetch_max/min (C++26)    __cpp_lib_atomic_min_max         202403L
  std::execution senders (C++26)       __cpp_lib_senders                -
  hazard pointers (C++26)              __cpp_lib_hazard_pointer         -
  RCU (C++26)                          __cpp_lib_rcu                    -
  std::hive (C++26)                    __cpp_lib_hive                   -
  std::simd (C++26)                    __cpp_lib_simd                   -
  std::linalg (C++26)                  __cpp_lib_linalg                 -
  reflection <meta> (C++26)            __cpp_lib_reflection             -
  contracts <contracts> (C++26)        __cpp_lib_contracts              202502L
  std::text_encoding (C++26)           __cpp_lib_text_encoding          -
  <debugging> breakpoint (C++26)       __cpp_lib_debugging              202403L
```

Clang 21.1 / libc++:

```text
C++ library features (value of the __cpp_lib_ macro; - = not provided), with -std=c++26:
  std::atomic_ref (C++20)              __cpp_lib_atomic_ref             201806L
  std::atomic<shared_ptr> (C++20)      __cpp_lib_atomic_shared_ptr      -
  atomic wait/notify (C++20)           __cpp_lib_atomic_wait            201907L
  std::jthread + stop_token (C++20)    __cpp_lib_jthread                201911L
  std::counting_semaphore (C++20)      __cpp_lib_semaphore              201907L
  std::latch (C++20)                   __cpp_lib_latch                  201907L
  std::barrier (C++20)                 __cpp_lib_barrier                201907L
  coroutine support (C++20)            __cpp_lib_coroutine              201902L
  std::expected (C++23)                __cpp_lib_expected               202211L
  std::print (C++23)                   __cpp_lib_print                  202207L
  std::flat_map (C++23)                __cpp_lib_flat_map               202207L
  std::mdspan (C++23)                  __cpp_lib_mdspan                 202406L
  std::generator (C++23)               __cpp_lib_generator              -
  std::move_only_function (C++23)      __cpp_lib_move_only_function     -
  std::stacktrace (C++23)              __cpp_lib_stacktrace             -
  std::inplace_vector (C++26)          __cpp_lib_inplace_vector         -
  std::function_ref (C++26)            __cpp_lib_function_ref           -
  std::copyable_function (C++26)       __cpp_lib_copyable_function      -
  saturation arithmetic (C++26)        __cpp_lib_saturation_arithmetic  202311L
  std::atomic fetch_max/min (C++26)    __cpp_lib_atomic_min_max         -
  std::execution senders (C++26)       __cpp_lib_senders                -
  hazard pointers (C++26)              __cpp_lib_hazard_pointer         -
  RCU (C++26)                          __cpp_lib_rcu                    -
  std::hive (C++26)                    __cpp_lib_hive                   -
  std::simd (C++26)                    __cpp_lib_simd                   -
  std::linalg (C++26)                  __cpp_lib_linalg                 -
  reflection <meta> (C++26)            __cpp_lib_reflection             -
  contracts <contracts> (C++26)        __cpp_lib_contracts              -
  std::text_encoding (C++26)           __cpp_lib_text_encoding          -
  <debugging> breakpoint (C++26)       __cpp_lib_debugging              -
```

How to read it:

* **The detection trick.** A macro that isn't defined stringizes to its own name, so `sizeof(#macro) ==
  sizeof(XSTR(macro))` exactly when it's missing, and that comparison is a constant expression. Include `<version>`, which
  defines every library macro without pulling in the headers.
* **The value is a date, and it matters.** `__cpp_lib_flat_map` is 202207L in libc++ and 202511L in libstdc++. Both
  ship `flat_map`, but not the same revision. `__cpp_lib_atomic_ref` is 201806L (C++20) in libc++ and 202603L in
  libstdc++, which includes the C++26 additions. Gate on `>=` a value, not on `defined`.
* **The C++20 concurrency vocabulary is shared** (`jthread`, `latch`, `barrier`, `counting_semaphore`, `atomic::wait`,
  `atomic_ref`, coroutines), **except `atomic<shared_ptr>`**. libstdc++ has it (the low-bit lock of Folder 07) and
  libc++ 21 doesn't. Portable code that needs it today uses libstdc++ or MSVC's STL, a library type, or a different
  design (an RCU-style pointer, Folder 09).
* **The C++26 concurrency headline features ship nowhere here.** `__cpp_lib_senders`, `__cpp_lib_hazard_pointer` and
  `__cpp_lib_rcu` are undefined in both libraries. Until they appear, the production implementations are the ones in
  this file's reading list. Senders come from **stdexec** (the reference implementation) and **libunifex**. Hazard
  pointers and RCU come from **folly** (`hazptr`, from which P2530 came, and `Rcu.h`) and **liburcu**. `hive` comes from
  **plf::hive**, its reference implementation, and stacktraces from Boost.Stacktrace.
* **GCC 16 is ahead on the library side**: `inplace_vector`, `function_ref`, `copyable_function`, atomic
  `fetch_max`/`fetch_min` (the `ldsmaxal` of Folder 07), contracts, `<debugging>`. Code that must build with both
  libraries has to gate each of them.

### 1.2 How to read a concurrency library

Reading 10,000 lines of folly is not like reading a textbook. The method that works:

1. **Start from the memory orders.** Grep for `memory_order` and list every operation that is *not* `seq_cst`. Each one
   must pair with something: a release with an acquire, a relaxed operation with an argument for why nothing depends on
   it. If you can't state the pairing for a line, you've found either the subtle part or a bug, and both are worth an
   hour.
2. **Find the slow path.** What happens under contention: spin (how many iterations, with which pause instruction), then
   yield, then park. And *which parking primitive*: a futex, `WaitOnAddress`, `__ulock_wait`, a condition variable.
   Folder 08 showed that the slow path is where the latency distribution's tail comes from.
3. **Find the platform layer.** folly's `portability/` and `detail/Futex.h`, Abseil's `base/internal/`, libc++'s
   `__thread/support/`, the Linux kernel's `arch/*/include/asm/`. That is where x86 and ARM64 differ, and where the
   assumptions are written down.
4. **Read the tests before the code.** The best libraries test concurrency deterministically. folly's lock-free
   structures take the atomic type as a template parameter (`template <typename T, template <typename> class Atom =
   std::atomic, ...> class MPMCQueue`). `folly/test/DeterministicSchedule.h` then substitutes `DeterministicAtomic<T>`,
   which calls `beforeSharedAccess()` on every operation so that a seeded scheduler (`uniform(seed)`) decides which
   thread runs next. Every interleaving the test finds can be replayed from its seed. That is Listing 12.3's
   forced-schedule idea, made systematic.
5. **Read `git blame` on the fence lines.** A fence that was added in a bug-fix commit comes with its failure scenario
   in the commit message. That is better documentation than the comments.
6. **Re-measure the benchmark claims on your hardware** (§1.3 does that for one claim). README numbers come from the
   author's machine, core count and workload.

A worked micro-example, `rigtorp/SPSCQueue` (Folder 09's SPSC). `push` spins `while (nextWriteIdx ==
readIdxCache_)` and refreshes `readIdxCache_ = readIdx_.load(std::memory_order_acquire)` only when the cached value
says "full". That is the **cached-index** optimization: the producer reads the consumer's line only when it must.
The class also `static_assert`s `sizeof(SPSCQueue<T>) >= 3 * kCacheLineSize`, and it allocates `2 * kPadding` extra
slots around the ring, so that the first and last slots can't share a line with whatever the allocator placed next to
the buffer. That's false sharing with *someone else's* data, which a benchmark of the queue alone never shows.

### 1.3 Reading drill: folly's asymmetric fences, reproduced (Listing 12.5)

**The claim, from the source.** `folly/synchronization/AsymmetricThreadFence.h` says: "A lightweight fence interacts with
a heavyweight fence as if both fences were normal std::atomic_thread_fence fences." The implementation (checked at the
time of writing):

```text
asymmetric_thread_fence_light(order):   if (kIsLinux) asm_volatile_memory();         // a compiler barrier only
                                        else          std::atomic_thread_fence(order);
asymmetric_thread_fence_heavy(order):   if (kIsLinux) { if (sysMembarrierAvailableCached())
                                                          sysMembarrierPrivateExpedited();   // membarrier(2)
                                                        else mprotectMembarrier(); }         // TLB-shootdown trick
                                        else          std::atomic_thread_fence(order);
```

So folly makes the reader free **only on Linux**. Elsewhere both sides are ordinary fences. The Linux fallback is a trick:
`mprotect` a resident dummy page from read-write to read-only, which forces a TLB shootdown, an inter-processor
interrupt to every core running a thread of the process. The API mimics P1202 (`asymmetric_thread_fence_light/heavy`),
a proposal that is not part of C++26. Hazard pointers use the pair for the SB pattern of Folder 09. The reader publishes
a hazard and re-checks the source, and the reclaimer unlinks and then scans the hazards. One side runs on every read and
the other once per batch of retirements.

**The reproduction.** The light side is `std::atomic_signal_fence(seq_cst)`, the standard spelling of a compiler-only
barrier. The heavy side is `FlushProcessWriteBuffers()` on Windows, which folly doesn't use. Its documentation says it
"flushes the write queue of each processor that is running a thread of the current process" and that it generates an
IPI to the processors in the process's affinity. On Linux it is `membarrier(MEMBARRIER_CMD_PRIVATE_EXPEDITED)`, after the
one-time `MEMBARRIER_CMD_REGISTER_PRIVATE_EXPEDITED`.

```cpp
// asymmetric_fence.cpp - reading drill: folly's asymmetric fences (free reader, expensive rare scanner), measured
#include <atomic>
#include <chrono>
#include <print>
#include <thread>
#include <vector>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
constexpr const char* kHeavyName = "FlushProcessWriteBuffers";
#else
#include <linux/membarrier.h>
#include <sys/syscall.h>
#include <unistd.h>
constexpr const char* kHeavyName = "membarrier(PRIVATE_EXPEDITED)";
#endif

// Light side (folly on Linux: asm volatile("" ::: "memory")): stops only the COMPILER from reordering.
inline void light_fence() { std::atomic_signal_fence(std::memory_order_seq_cst); }

// Heavy side: forces a full barrier on every core currently running a thread of this process (an IPI), which turns
// every light fence in the process into a real one for the purposes of this one pairing.
void heavy_fence_init() {
#if !defined(_WIN32)
    syscall(SYS_membarrier, MEMBARRIER_CMD_REGISTER_PRIVATE_EXPEDITED, 0, 0);   // once per process
#endif
}
void heavy_fence() {
#if defined(_WIN32)
    FlushProcessWriteBuffers();
#else
    syscall(SYS_membarrier, MEMBARRIER_CMD_PRIVATE_EXPEDITED, 0, 0);
#endif
}

// The reader side of hazard-pointer protect is the SB pattern: publish the hazard, fence, re-check the source.
std::atomic<long> g_hazard{0};
std::atomic<long> g_source{1};

long protect_seq_cst(long p) {
    g_hazard.store(p, std::memory_order_relaxed);
    std::atomic_thread_fence(std::memory_order_seq_cst);
    return g_source.load(std::memory_order_relaxed);
}
long protect_light(long p) {
    g_hazard.store(p, std::memory_order_relaxed);
    light_fence();
    return g_source.load(std::memory_order_relaxed);
}

template <class F>
double ns_per_op(F protect, long iters) {
    long sink = 0;
    const auto t0 = std::chrono::steady_clock::now();
    for (long i = 0; i < iters; ++i) sink += protect(i);
    const auto t1 = std::chrono::steady_clock::now();
    if (sink == -1) std::println("impossible");
    return std::chrono::duration<double, std::nano>(t1 - t0).count() / static_cast<double>(iters);
}

double heavy_us(int spinning_threads, int calls) {
    std::atomic<bool> stop{false};
    std::atomic<int> started{0};
    std::vector<std::jthread> spinners;
    for (int t = 0; t < spinning_threads; ++t)
        spinners.emplace_back([&] {
            started.fetch_add(1);
            while (!stop.load(std::memory_order_relaxed)) {   // a busy reader on another core: it must be interrupted
            }
        });
    while (started.load() < spinning_threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < calls; ++i) heavy_fence();
    const auto t1 = std::chrono::steady_clock::now();
    stop = true;
    return std::chrono::duration<double, std::micro>(t1 - t0).count() / calls;
}

int main() {
    heavy_fence_init();
    constexpr long kIters = 20'000'000;
    constexpr int kCalls = 2'000;
    const double sc = ns_per_op([](long p) { return protect_seq_cst(p); }, kIters);   // lambdas: both compilers inline
    const double light = ns_per_op([](long p) { return protect_light(p); }, kIters);
    std::println("reader side of protect (store hazard; fence; re-load source), {} iterations:", kIters);
    std::println("  seq_cst thread fence      {:6.2f} ns/op", sc);
    std::println("  light (compiler only)     {:6.2f} ns/op", light);
    const unsigned cpus = std::thread::hardware_concurrency();
    const int busy = static_cast<int>(cpus > 2 ? cpus / 2 : 1);
    const double idle_us = heavy_us(0, kCalls);
    const double busy_us = heavy_us(busy, kCalls);
    std::println("heavy side ({}), mean of {} calls, {} logical CPUs:", kHeavyName, kCalls, cpus);
    std::println("  no other thread running   {:6.2f} us", idle_us);
    std::println("  {:>2} threads spinning       {:6.2f} us", busy, busy_us);
    const double saved = sc - light;
    std::println("break-even: one heavy call (busy) costs as much as the fences saved by {:.0f} reader-side protects",
                 saved > 0 ? busy_us * 1000.0 / saved : 0.0);
}
```

The reader side on x86-64:

```text
_Z15protect_seq_cstl:              # protect_seq_cst(long)
	movq	g_hazard@GOTPCREL(%rip), %rax
	movq	%rdi, (%rax)
	lock	orl	$0, -64(%rsp)
	movq	g_source@GOTPCREL(%rip), %rax
	movq	(%rax), %rax
	retq

_Z13protect_lightl:                # protect_light(long)
	movq	g_hazard@GOTPCREL(%rip), %rax
	movq	%rdi, (%rax)
	movq	g_source@GOTPCREL(%rip), %rax
	movq	(%rax), %rax
	retq
```

On AArch64:

```text
_Z15protect_seq_cstl:              // protect_seq_cst(long)
	adrp	x8, :got:g_hazard
	ldr	x8, [x8, :got_lo12:g_hazard]
	str	x0, [x8]
	adrp	x8, :got:g_source
	ldr	x8, [x8, :got_lo12:g_source]
	dmb	ish
	ldr	x0, [x8]
	ret

_Z13protect_lightl:                // protect_light(long)
	adrp	x8, :got:g_hazard
	adrp	x9, :got:g_source
	ldr	x8, [x8, :got_lo12:g_hazard]
	ldr	x9, [x9, :got_lo12:g_source]
	str	x0, [x8]
	ldr	x0, [x9]
	ret
```

* **x86-64.** `protect_seq_cst` is store, `lock orl $0, -64(%rsp)`, load. The locked RMW is the full barrier that
  stops the load from passing the store (store→load is the one reordering TSO allows). Clang aims it at a red-zone
  slot 64 bytes *below* the stack pointer. GCC 16 aims it at `(%rsp)` itself (checked with its Windows-ABI build), the
  slot that holds the most recent push, such as a return address.
  `protect_light` is store, load, and nothing between.
* **AArch64.** `dmb ish` between the store and the load, versus nothing. In the light version Clang also hoisted both
  GOT address loads above the store. The compiler barrier keeps the two *accesses* in order and says nothing about
  computing their addresses.
* **The light version is not correct on its own.** Without the heavy side in some other thread, store→load reordering
  is allowed on both architectures, and that is exactly the hazard-pointer bug of Folder 09.

The measurements, GCC 16.2 / libstdc++:

```text
reader side of protect (store hazard; fence; re-load source), 20000000 iterations:
  seq_cst thread fence        4.70 ns/op
  light (compiler only)       0.30 ns/op
heavy side (FlushProcessWriteBuffers), mean of 2000 calls, 12 logical CPUs:
  no other thread running     0.27 us
   6 threads spinning         1.96 us
break-even: one heavy call (busy) costs as much as the fences saved by 446 reader-side protects
```

Clang 21.1 / libc++:

```text
reader side of protect (store hazard; fence; re-load source), 20000000 iterations:
  seq_cst thread fence        4.65 ns/op
  light (compiler only)       0.21 ns/op
heavy side (FlushProcessWriteBuffers), mean of 2000 calls, 12 logical CPUs:
  no other thread running     0.25 us
   6 threads spinning         1.95 us
break-even: one heavy call (busy) costs as much as the fences saved by 440 reader-side protects
```

* **The reader's fence is about 95% of protect's cost.** 4.65–4.70 ns with the `seq_cst` fence versus 0.21–0.30 ns
  with the compiler barrier in the captured run, on both compilers (4.6–4.8 vs 0.2–0.4 ns across repeat runs). That agrees with Folder 07's ~4.7 ns `seq_cst` store, which is the same
  locked instruction.
* **The heavy side is cheap when the process is alone and expensive when it's busy.** 0.25–0.27 µs with no other thread
  running, and 1.95 µs with 6 threads spinning on other cores (repeat runs: 0.25–0.42 and 1.95–2.34 µs), because each of those cores must take the interrupt
  and drain. Its cost grows with the number of *running* threads of the process, and it lands on them as an unexpected
  interrupt.
* **Break-even is 440–540 protects per heavy call on this machine** (about 500). A reclaimer that scans once per few thousand
  retirements, in a structure read far more often than written, wins by a large factor. A structure that retires on
  every operation would lose.

**Why the drill doesn't include a litmus test.** The obvious check is an SB litmus run with light/heavy, expecting 0
violations. It can't discriminate. The heavy call takes microseconds, so by the time the heavy side's load executes,
the reader's store has long drained, *with or without* the guarantee. A run with a plain microsecond delay in place of
the heavy fence would also show 0. Here the correctness rests on the OS contract (membarrier(2), the
`FlushProcessWriteBuffers` documentation) and on the argument, not on a test. That is a general lesson: some
correctness properties can't be established by stress testing, and an L7 engineer says which ones.

**What it costs, beyond time.** The C++ memory model has no notion of an IPI, so formally a relaxed store, a signal fence
and a relaxed load on the reader side order nothing against another thread. The guarantee comes from the platform, which
is why P1202 proposed standard names for it. In a latency-critical system with isolated cores (HFT, audio), the heavy
side sends interrupts to exactly the cores you isolated. That jitter is a reason to choose EBR or QSBR (Folder 09)
instead.

### 1.4 The curated source list

Each entry is a specific file and a specific thing to look for, tied to the KB folder whose claims it calibrates. All
links were checked to resolve at the time of writing. They point at the default branch, so file contents move; read with
`git log` open.

**Abseil (Google)**

| File | Look for | KB folder |
|---|---|---|
| [`absl/container/internal/raw_hash_set.h`](https://github.com/abseil/abseil-cpp/blob/master/absl/container/internal/raw_hash_set.h) | control bytes (H2 in 7 bits; empty / deleted / sentinel), group probing with SSE2 on x86 and NEON on ARM, the probe sequence, how erase leaves tombstones | 03 |
| [`absl/synchronization/mutex.h`](https://github.com/abseil/abseil-cpp/blob/master/absl/synchronization/mutex.h) and [`mutex.cc`](https://github.com/abseil/abseil-cpp/blob/master/absl/synchronization/mutex.cc) | one word holding reader count, writer bit and waiter-queue state; `Condition` / `Await` / `LockWhen` instead of condition variables (no lost wakeups by construction); debug deadlock detection (`SetMutexDeadlockDetectionMode`) | 08 |
| [`absl/synchronization/internal/futex_waiter.cc`](https://github.com/abseil/abseil-cpp/blob/master/absl/synchronization/internal/futex_waiter.cc) | the parking layer under `Mutex`, one implementation per OS primitive | 08 |
| [`absl/base/internal/spinlock.h`](https://github.com/abseil/abseil-cpp/blob/master/absl/base/internal/spinlock.h) | a spinlock that falls back to an OS wait after a bounded spin, and why it exists beside `Mutex` | 08, 11 |
| [`absl/base/call_once.h`](https://github.com/abseil/abseil-cpp/blob/master/absl/base/call_once.h), [`absl/synchronization/notification.h`](https://github.com/abseil/abseil-cpp/blob/master/absl/synchronization/notification.h) | one-time initialization and one-shot events without the `std::call_once` exception trap of Folder 08 | 08 |

**folly (Meta)**

| File | Look for | KB folder |
|---|---|---|
| [`folly/synchronization/Hazptr.h`](https://github.com/facebook/folly/blob/main/folly/synchronization/Hazptr.h), [`HazptrDomain.h`](https://github.com/facebook/folly/blob/main/folly/synchronization/HazptrDomain.h) | the production hazard-pointer design behind P2530: per-thread caches of hazard records, batched retirement, cohorts, asymmetric fences on the protect path | 09 |
| [`folly/synchronization/Rcu.h`](https://github.com/facebook/folly/blob/main/folly/synchronization/Rcu.h) | user-space RCU behind P2545: reader epochs, `synchronize` / `retire`, grace-period detection | 09 |
| [`folly/synchronization/AsymmetricThreadFence.cpp`](https://github.com/facebook/folly/blob/main/folly/synchronization/AsymmetricThreadFence.cpp) | `membarrier`, the `mprotect` fallback (§1.3) | 07, 09 |
| [`folly/MPMCQueue.h`](https://github.com/facebook/folly/blob/main/folly/MPMCQueue.h) | the `TurnSequencer` (each slot waits for its turn, futex-parked), the `Atom` template parameter used by deterministic tests | 09 |
| [`folly/ProducerConsumerQueue.h`](https://github.com/facebook/folly/blob/main/folly/ProducerConsumerQueue.h) | the minimal SPSC ring, without cached indices; compare with rigtorp below | 09 |
| [`folly/concurrency/UnboundedQueue.h`](https://github.com/facebook/folly/blob/main/folly/concurrency/UnboundedQueue.h) | segment-based unbounded queue with hazard-pointer reclamation of segments | 09 |
| [`folly/container/F14Map.h`](https://github.com/facebook/folly/blob/main/folly/container/F14Map.h), [`detail/F14Table.h`](https://github.com/facebook/folly/blob/main/folly/container/detail/F14Table.h) | 14-slot chunks with SIMD tag matching, a different set of trade-offs from Swiss tables | 03 |
| [`folly/SharedMutex.h`](https://github.com/facebook/folly/blob/main/folly/SharedMutex.h) | deferred reader slots that keep readers off the shared counter line, and the writer-priority policy | 08 |
| [`folly/synchronization/DistributedMutex.h`](https://github.com/facebook/folly/blob/main/folly/synchronization/DistributedMutex.h) | a waiter-chain mutex that can run the critical section *on behalf of* waiters (flat combining) | 08, 11 |
| [`folly/synchronization/Baton.h`](https://github.com/facebook/folly/blob/main/folly/synchronization/Baton.h), [`folly/detail/Futex.h`](https://github.com/facebook/folly/blob/main/folly/detail/Futex.h) | the one-shot spin-then-futex primitive everything else parks on | 08 |
| [`folly/concurrency/AtomicSharedPtr.h`](https://github.com/facebook/folly/blob/main/folly/concurrency/AtomicSharedPtr.h) | a lock-free `atomic<shared_ptr>` using local/global split reference counts packed with the pointer, versus libstdc++'s lock bit (Folder 07) | 07 |
| [`folly/coro/Task.h`](https://github.com/facebook/folly/blob/main/folly/coro/Task.h) | a production lazy task: symmetric transfer, executor affinity, cancellation | 10 |
| [`folly/executors/CPUThreadPoolExecutor.h`](https://github.com/facebook/folly/blob/main/folly/executors/CPUThreadPoolExecutor.h) | the pool's queue choices and the priority model | 10 |
| [`folly/test/DeterministicSchedule.h`](https://github.com/facebook/folly/blob/main/folly/test/DeterministicSchedule.h) | deterministic, seed-replayable tests of lock-free code (§1.2) | 12 |
| [`folly/TokenBucket.h`](https://github.com/facebook/folly/blob/main/folly/TokenBucket.h) | a lock-free token bucket: one atomic `double` for "zero time", updated by CAS | 11 |

**Senders: libunifex and stdexec**

| File | Look for | KB folder |
|---|---|---|
| [`libunifex/include/unifex/sync_wait.hpp`](https://github.com/facebookexperimental/libunifex/blob/main/include/unifex/sync_wait.hpp) | the blocking edge: a receiver plus a manual event loop | 10 |
| [`libunifex/include/unifex/when_all.hpp`](https://github.com/facebookexperimental/libunifex/blob/main/include/unifex/when_all.hpp) | the countdown of completions, the stop-source fan-out, error-wins-and-cancels | 10 |
| [`libunifex/include/unifex/task.hpp`](https://github.com/facebookexperimental/libunifex/blob/main/include/unifex/task.hpp), [`inplace_stop_token.hpp`](https://github.com/facebookexperimental/libunifex/blob/main/include/unifex/inplace_stop_token.hpp), [`async_scope.hpp`](https://github.com/facebookexperimental/libunifex/blob/main/include/unifex/async_scope.hpp) | coroutine/sender interop, allocation-free stop callbacks, structured spawning | 10 |
| [`libunifex/include/unifex/static_thread_pool.hpp`](https://github.com/facebookexperimental/libunifex/blob/main/include/unifex/static_thread_pool.hpp) | a sender-aware pool: per-thread queues and the scheduler interface | 10 |
| [`stdexec/include/stdexec/execution.hpp`](https://github.com/NVIDIA/stdexec/blob/main/include/stdexec/execution.hpp) and [`__detail/__when_all.hpp`](https://github.com/NVIDIA/stdexec/blob/main/include/stdexec/__detail/__when_all.hpp) | the P2300 vocabulary as standardized: environments, queries, completion signatures | 10 |
| [`stdexec/include/exec/static_thread_pool.hpp`](https://github.com/NVIDIA/stdexec/blob/main/include/exec/static_thread_pool.hpp), [`exec/async_scope.hpp`](https://github.com/NVIDIA/stdexec/blob/main/include/exec/async_scope.hpp) | work-stealing pool with bulk support; scopes (the `counting_scope` lineage) | 10 |

**Standard library implementations**

| File | Look for | KB folder |
|---|---|---|
| [`libcxx/include/__atomic/atomic_sync.h`](https://github.com/llvm/llvm-project/blob/main/libcxx/include/__atomic/atomic_sync.h), [`libcxx/src/atomic.cpp`](https://github.com/llvm/llvm-project/blob/main/libcxx/src/atomic.cpp) | `atomic::wait`: the spin/back-off policy, then the platform wait (futex, `__ulock`, or a contention table) | 08 |
| [`libcxx/src/memory.cpp`](https://github.com/llvm/llvm-project/blob/main/libcxx/src/memory.cpp) | the global mutex pool behind the (deprecated) `atomic_load(const shared_ptr*)` free functions, which is what libc++ offers instead of `atomic<shared_ptr>` | 05, 07 |
| [`libcxxabi/src/cxa_guard_impl.h`](https://github.com/llvm/llvm-project/blob/main/libcxxabi/src/cxa_guard_impl.h) | magic statics: the guard byte, the init-in-progress bit, the futex and global-mutex variants, recursion detection | 08 |
| [`libstdc++-v3/include/bits/atomic_wait.h`](https://github.com/gcc-mirror/gcc/blob/master/libstdc++-v3/include/bits/atomic_wait.h), [`src/c++20/atomic.cc`](https://github.com/gcc-mirror/gcc/blob/master/libstdc++-v3/src/c++20/atomic.cc) | libstdc++'s wait/notify: the waiter pool hashed by address, and the futex fast path | 08 |
| [`libstdc++-v3/include/bits/shared_ptr_atomic.h`](https://github.com/gcc-mirror/gcc/blob/master/libstdc++-v3/include/bits/shared_ptr_atomic.h) | `_Sp_atomic`: the pointer's low bit used as a lock, waited on with `atomic::wait` | 07 |
| [`libstdc++-v3/libsupc++/guard.cc`](https://github.com/gcc-mirror/gcc/blob/master/libstdc++-v3/libsupc++/guard.cc), [`include/bits/hashtable.h`](https://github.com/gcc-mirror/gcc/blob/master/libstdc++-v3/include/bits/hashtable.h) | libstdc++'s magic statics; the node-based `unordered_map` with its singly linked "before begin" list | 08, 03 |
| [`microsoft/STL stl/src/atomic_wait.cpp`](https://github.com/microsoft/STL/blob/main/stl/src/atomic_wait.cpp), [`stl/inc/atomic`](https://github.com/microsoft/STL/blob/main/stl/inc/atomic), [`stl/src/sharedmutex.cpp`](https://github.com/microsoft/STL/blob/main/stl/src/sharedmutex.cpp) | `WaitOnAddress` as the wait primitive; how MSVC lowers atomics with interlocked intrinsics; SRWLOCK under `shared_mutex` | 07, 08 |
| [glibc `nptl/pthread_cond_wait.c`](https://sourceware.org/git/?p=glibc.git;a=blob;f=nptl/pthread_cond_wait.c;hb=HEAD), [`nptl/pthread_mutex_lock.c`](https://sourceware.org/git/?p=glibc.git;a=blob;f=nptl/pthread_mutex_lock.c;hb=HEAD) | the 2016 condition variable (two groups of waiters, no requeue, Folder 08's "no wait morphing"); the mutex kinds and their futex protocols | 08 |

**Kernel, RCU, and other languages**

| File | Look for | KB folder |
|---|---|---|
| [`linux kernel/locking/qspinlock.c`](https://github.com/torvalds/linux/blob/master/kernel/locking/qspinlock.c) | one 32-bit word: locked byte, pending bit, an MCS tail (CPU and nesting index); MCS queueing only when contended | 08, 11 |
| [`kernel/locking/osq_lock.c`](https://github.com/torvalds/linux/blob/master/kernel/locking/osq_lock.c) | optimistic spinning for sleeping mutexes: spin while the owner is running | 08 |
| [`kernel/futex/waitwake.c`](https://github.com/torvalds/linux/blob/master/kernel/futex/waitwake.c), [`requeue.c`](https://github.com/torvalds/linux/blob/master/kernel/futex/requeue.c) | the kernel side of `FUTEX_WAIT`/`WAKE`: the hash bucket, the value re-check under the bucket lock that prevents lost wakeups; requeue | 08 |
| [`include/linux/seqlock.h`](https://github.com/torvalds/linux/blob/master/include/linux/seqlock.h) | sequence locks: readers retry, writers never wait for readers | 09, 11 |
| [`Documentation/memory-barriers.txt`](https://github.com/torvalds/linux/blob/master/Documentation/memory-barriers.txt), [`tools/memory-model/`](https://github.com/torvalds/linux/tree/master/tools/memory-model) | the kernel's informal and formal (herd7) memory models; the clearest prose on barrier pairing anywhere | 07 |
| [`userspace-rcu src/urcu.c`](https://github.com/urcu/userspace-rcu/blob/master/src/urcu.c), [`include/urcu/static/urcu-qsbr.h`](https://github.com/urcu/userspace-rcu/blob/master/include/urcu/static/urcu-qsbr.h) | liburcu flavours (memory-barrier, membarrier, QSBR); QSBR's reader cost of Folder 09's 0.33–0.46 ns | 09 |
| [`crossbeam-epoch/src/internal.rs`](https://github.com/crossbeam-rs/crossbeam/blob/master/crossbeam-epoch/src/internal.rs) | epoch-based reclamation in production: pinning, the global epoch, bags of garbage | 09 |
| [`crossbeam-deque/src/deque.rs`](https://github.com/crossbeam-rs/crossbeam/blob/master/crossbeam-deque/src/deque.rs) | Chase-Lev with the Lê et al. weak-memory orders, plus buffer reclamation through epochs | 10 |
| [`crossbeam-utils/src/cache_padded.rs`](https://github.com/crossbeam-rs/crossbeam/blob/master/crossbeam-utils/src/cache_padded.rs) | why it pads to **128** bytes on x86-64, AArch64 and POWER64: Intel's spatial prefetcher pulls pairs of 64-byte lines (from Sandy Bridge on), and "big" AArch64 cores have 128-byte lines | 07 |

**Focused queues and containers**

| File | Look for | KB folder |
|---|---|---|
| [`rigtorp/SPSCQueue`](https://github.com/rigtorp/SPSCQueue/blob/master/include/rigtorp/SPSCQueue.h) | cached indices and padding slots (§1.2) | 09 |
| [`rigtorp/MPMCQueue`](https://github.com/rigtorp/MPMCQueue/blob/master/include/rigtorp/MPMCQueue.h) | the turn-based bounded MPMC, the same family as Vyukov's and folly's | 09 |
| [`cameron314/concurrentqueue`](https://github.com/cameron314/concurrentqueue/blob/master/concurrentqueue.h) | per-producer sub-queues: high throughput by giving up global FIFO | 09, 11 |
| [`boostorg/lockfree spsc_queue.hpp`](https://github.com/boostorg/lockfree/blob/develop/include/boost/lockfree/spsc_queue.hpp) | the long-standing portable baseline | 09 |
| [`plf_hive`](https://github.com/mattreecebentley/plf_hive/blob/main/plf_hive.h) | the reference implementation of C++26 `std::hive`: blocks, skipfields, stable iterators | 03 |
| [Vyukov, bounded MPMC queue](https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue) | the original per-cell sequence-number design that Folder 09 implemented | 09 |

### 1.5 Books, papers and talks

**Books** (in reading order):

1. A. Williams, *C++ Concurrency in Action*, 2nd ed., Manning, 2019. The standard library's concurrency facilities by
   a principal author of the C++11 thread-library proposals.
2. M. Bos, *Rust Atomics and Locks*, O'Reilly, 2023 (free online: <https://marabos.nl/atomics/>). The best treatment of
   x86 versus ARM64 code generation for atomics, and the model is C++'s.
3. V. Nagarajan, D. Sorin, M. Hill, D. Wood, *A Primer on Memory Consistency and Cache Coherence*, 2nd ed., 2020.
   MESI, TSO, the store buffer, and the axiomatic models behind Folder 07.
4. P. McKenney, *Is Parallel Programming Hard, And, If So, What Can You Do About It?* (perfbook, free:
   <https://mirrors.edge.kernel.org/pub/linux/kernel/people/paulmck/perfbook/perfbook.html>). RCU, counters, and
   memory barriers from the person who wrote the kernel's.
5. M. Herlihy, N. Shavit, V. Luchangco, M. Spear, *The Art of Multiprocessor Programming*, 2nd ed., 2020.
   Linearizability, progress conditions, and the classic lock-free structures.
6. F. Pikus, *The Art of Writing Efficient Programs*, Packt, 2021. Measurement-first performance, with chapters on
   atomics and lock-free code.
7. U. Drepper, "Futexes Are Tricky" (<https://www.akkadia.org/drepper/futex.pdf>) and "What Every Programmer Should Know
   About Memory" (<https://www.akkadia.org/drepper/cpumemory.pdf>). Short; Folder 08's 0/1/2 mutex is from the first.

**Papers** (the ones the KB's claims rest on):

- H.-J. Boehm, S. Adve, "Foundations of the C++ Concurrency Memory Model", PLDI 2008.
- M. Batty, S. Owens, S. Sarkar, P. Sewell, T. Weber, "Mathematizing C++ Concurrency", POPL 2011.
- O. Lahav, V. Vafeiadis, J. Kang, C.-K. Hur, D. Dreyer, "Repairing Sequential Consistency in C/C++11", PLDI 2017
  (RC11; the basis of C++20's seq_cst repair, P0668: <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0668r5.html>).
- P. Sewell, S. Sarkar, S. Owens, F. Zappa Nardelli, M. Myreen, "x86-TSO: A Rigorous and Usable Programmer's Model for
  x86 Multiprocessors", CACM 2010.
- C. Pulte, S. Flur, W. Deacon, J. French, S. Sarkar, P. Sewell, "Simplifying ARM Concurrency: Multicopy-Atomic Axiomatic
  and Operational Models for ARMv8", POPL 2018.
- M. Michael, M. Scott, "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms", PODC 1996.
- M. Michael, "Hazard Pointers: Safe Memory Reclamation for Lock-Free Objects", IEEE TPDS 2004.
- K. Fraser, "Practical Lock-Freedom", PhD thesis, Cambridge, 2004 (epoch-based reclamation).
- M. Desnoyers, P. McKenney, A. Stern, M. Dagenais, J. Walpole, "User-Level Implementations of Read-Copy Update", IEEE
  TPDS 2012.
- D. Chase, Y. Lev, "Dynamic Circular Work-Stealing Deque", SPAA 2005; N. M. Lê, A. Pop, A. Cohen, F. Zappa Nardelli,
  "Correct and Efficient Work-Stealing for Weak Memory Models", PPoPP 2013.
- J. Mellor-Crummey, M. Scott, "Algorithms for Scalable Synchronization on Shared-Memory Multiprocessors", ACM TOCS 1991
  (MCS).
- J. F. Bastien, "No Sane Compiler Would Optimize Atomics", N4455, 2015:
  <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2015/n4455.html>.
- WG21: P2530 (hazard pointers, <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2530r3.pdf>), P2545 (RCU,
  <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2545r4.pdf>), P1202 (asymmetric fences,
  <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p1202r4.pdf>).

**Talks** (titles, speakers and venues; search the conference's channel. Watch older ones knowing what changed since):

| Talk | Why | Caveat |
|---|---|---|
| H. Sutter, "atomic<> Weapons: The C++ Memory Model and Modern Hardware", C++ and Beyond 2012 | still the best two-part introduction to acquire/release and what hardware does | predates C++20's seq_cst repair (P0668) and the discouragement of consume |
| H. Sutter, "Lock-Free Programming (or, Juggling Razor Blades)", CppCon 2014 | the reasoning style for lock-free structures | uses pre-C++17 idioms |
| J. Preshing, "How Ubisoft Develops Games for Multicore – Before and After C++11", CppCon 2014 | threading patterns from a shipping engine | game-engine workloads |
| P. McKenney, "C++ Atomics: The Sad Story of memory_order_consume: A Happy Ending At Last?", CppCon 2015 | why consume became acquire in every compiler | consume was discouraged in C++17 and deprecated in C++26, its semantics folded into acquire (P3475) |
| C. Carruth, "Tuning C++: Benchmarks, and CPUs, and Compilers! Oh My!", CppCon 2015 | how to benchmark without fooling yourself | — |
| H. Boehm, "Using Weakly Ordered C++ Atomics Correctly", CppCon 2016 | when relaxed is safe, and when it isn't | — |
| F. Pikus, "C++ atomics, from basic to advanced. What do they really do?", CppCon 2017 | cost of atomics measured, x86 code generation | x86-centric; run Folder 07 on ARM64 too |
| F. Pikus, "Read, Copy, Update, then what? RCU for non-kernel programmers", CppCon 2017 | RCU's model for user space | predates P2545 |
| M. Kulukundis, "Designing a Fast, Efficient, Cache-friendly Hash Table, Step by Step", CppCon 2017 | the Swiss-table design from its author | Abseil's current code has evolved since |
| G. Nishanov, "Nano-coroutines to the Rescue! (Using Coroutines TS, of Course)", CppCon 2018 | coroutines hiding memory latency | Coroutines TS syntax |
| L. Baker, "Structured Concurrency: Writing Safer Concurrent Code with Coroutines and Algorithms", CppCon 2019 | the argument that led to senders | — |
| B. A. Lelbach, "The C++20 Synchronization Library", CppCon 2019 | `atomic::wait`, `latch`, `barrier`, semaphores from the proposal side | implementations' wait strategies differ (Folder 08) |
| E. Niebler, "Working with Asynchrony Generically: A Tour of C++ Executors", CppCon 2021 | senders/receivers from P2300's author | API names changed before standardization |

Treat every number in a talk as a hypothesis for your hardware, and re-measure it the way §1.3 did folly's claim. Every
listing in this KB exists because a claim deserved checking.

### 1.6 Study plan: twelve weeks to an L7 bar

| Week | KB folder | Read in source | Build and verify | Interview drill (Folder 11 files) |
|---|---|---|---|---|
| 1 | 01 ABI, object model | Itanium C++ ABI (vtables, thunks); libcxxabi `private_typeinfo.cpp` (`dynamic_cast`) | Folder 01's layout dumps on x86-64 and AArch64 | file 04's ABI and lifetime Q&A |
| 2 | 02 standards evolution | cppreference compiler support; Listing 12.4 on your toolchain | the feature matrix for your production compilers | file 04's standards questions; §2's table from memory |
| 3 | 03 containers | `raw_hash_set.h`, `F14Table.h`, libstdc++ `hashtable.h` | Folder 03's flat-map vs `unordered_map` numbers | P5 sharded LRU cache; build-your-own flat hash map (file 02) |
| 4 | 04 algorithms, ranges | libc++ `__algorithm/`, range-v3 | dangling views and sentinels from Folder 04 | file 04's ranges and algorithm Q&A |
| 5 | 05 smart pointers | libstdc++ `shared_ptr_base.h`, libc++ `memory.cpp` | control-block layout, `make_shared` single allocation | build-your-own `shared_ptr` / `weak_ptr` (file 02) |
| 6 | 06 templates, concepts | your standard library's `<type_traits>`, `<concepts>` | concept-based dispatch compiled to zero overhead | build-your-own `function` (type erasure, file 02) |
| 7 | 07 memory model | `memory-barriers.txt`, LKMM, `cache_padded.rs`, `shared_ptr_atomic.h` | litmus tests on x86 *and* ARM64 | file 03's memory-model Q&A |
| 8 | 08 threads, futex | glibc `pthread_cond_wait.c`, `futex/waitwake.c`, `absl/.../mutex.cc`, `cxa_guard_impl.h` | the 0/1/2 futex mutex; a condvar with timeouts | P1 bounded blocking queue, P4 / P11 reader-writer locks, P10 dining philosophers |
| 9 | 09 lock-free, SMR | folly `Hazptr*.h`, `Rcu.h`, rigtorp queues, crossbeam-epoch, liburcu | SPSC + MPMC; hazard pointers vs EBR under a stalled reader | P2 ring buffers, P14 lock-free free list (ABA) |
| 10 | 10 async | crossbeam-deque, folly `coro/Task.h`, libunifex `when_all.hpp`, stdexec | the work-stealing pool; a 250-line sender core | P3 work-stealing pool, P9 DAG executor |
| 11 | 11 problem bank | folly `TokenBucket.h`, `DistributedMutex.h`, moodycamel | the 15 problems against their invariant checks | P6 rate limiter, P7 timing wheel, P8 logger, P15 single-flight; timed mock, 45 minutes each, out loud |
| 12 | 12 debugging, sources | TSan's `tsan_interface_atomic.cpp`, folly `DeterministicSchedule.h`, `AsymmetricThreadFence.cpp` | a TSan job and a model-check job for your own lock-free core | files 03 and 04 (30 + 30 Q&A), then this folder's chains |

The rule for every week: **read the source, predict the number, then measure it**. If your prediction is off by more than
2×, the gap is the lesson.

---

## 2. Evolution table: where each facility lived before the standard

| Facility | Lived first in | Standardized | Status on this toolchain (Listing 12.4) |
|---|---|---|---|
| threads, mutexes, condition variables | Boost.Thread, pthreads | C++11 | both |
| atomics, memory orders | compiler intrinsics (`__sync_*`, `Interlocked*`), Boost.Atomic | C++11 | both |
| futures | Boost.Thread; `.then` later in folly Futures | C++11 (no `.then`, ever) | both |
| `shared_mutex` | Boost.Thread | C++14 (`shared_timed_mutex`), C++17 | both |
| `latch`, `barrier`, `counting_semaphore`, `atomic::wait` | Concurrency TS, Boost | C++20 | both |
| `jthread`, `stop_token` | P0660's reference implementation (N. Josuttis et al.) | C++20 | both |
| `atomic<shared_ptr>` | Concurrency TS (`atomic_shared_ptr`), folly `AtomicSharedPtr` | C++20 | libstdc++ only |
| coroutines | Coroutines TS; cppcoro | C++20 (language), C++23 (`generator`) | both (language); `generator` in libstdc++ only |
| `flat_map` | Boost.Container | C++23 | both, different revisions |
| `stacktrace` | Boost.Stacktrace | C++23 | neither |
| atomic `fetch_max` / `fetch_min` | `ldsmax` / CAS loops by hand | C++26 (P0493) | libstdc++ only |
| `hive` | plf::colony → plf::hive | C++26 | neither |
| hazard pointers | folly `hazptr` | C++26 (P2530) | neither |
| RCU | liburcu, folly `Rcu.h` | C++26 (P2545) | neither |
| senders / receivers | libunifex, stdexec | C++26 (P2300) | neither |
| `simd` | Vc, `std::experimental::simd` | C++26 | neither (under this macro) |
| asymmetric fences | folly, Linux `membarrier`, Windows `FlushProcessWriteBuffers` | proposed (P1202), not in C++26 | library or OS only |

The pattern is that every facility shipped in a library for years before WG21 adopted it, and implementations then lag
the standard by one to several releases. An L7 plan budgets for both gaps.

---

## 3. Production blueprints

### 3.1 Gate on features, not on compiler versions

```cpp
// BUGGY: version checks are wrong in both directions (backports, partial implementations, libc++ with GCC, ...).
#if defined(__GNUC__) && __GNUC__ >= 15
#include <hazard_pointer>            // may not exist, even in a compiler that "supports C++26"
#endif

// HARDENED: one header owns the decision; it asks <version> and falls back to a vetted library.
#include <version>
#if defined(__cpp_lib_hazard_pointer) && __cpp_lib_hazard_pointer >= 202306L
#include <hazard_pointer>
namespace kb::smr { using std::hazard_pointer; using std::make_hazard_pointer; }
#else
#include <folly/synchronization/Hazptr.h>
namespace kb::smr { using hazard_pointer = folly::hazptr_holder<>; using folly::make_hazard_pointer; }
#endif
```

Everything else in the code base includes the one adapter header. When `__cpp_lib_hazard_pointer` appears, one file
changes. folly's holder is `hazptr_holder` and its factory is already called `make_hazard_pointer()` (checked in
`HazptrHolder.h` at the time of writing). The remaining differences from P2530 (`protect` / `try_protect` overloads,
`hazptr_obj_base` vs `hazard_pointer_obj_base`) are what the adapter absorbs; verify them against the folly version
you pin.

### 3.2 Adopting a third-party lock-free structure

| Check | Pass condition |
|---|---|
| memory-order audit | every non-`seq_cst` operation has a stated pairing (§1.2, step 1) |
| test strategy | deterministic or model-checked tests exist (folly's `DeterministicSchedule`, Relacy, loom), not only stress |
| ARM64 | CI runs on ARM64, or you add it: an LL/SC build and an LSE build |
| reclamation | the memory-reclamation scheme is stated (hazard pointers, epochs, none = leaks or bounded), and so is its behaviour with a stalled thread |
| progress | lock-free, wait-free or blocking is documented, and blocking windows are named (Vyukov's MPMC has one, Folder 09) |
| maintenance | issues about ordering bugs get answered; a release or tag you can pin |
| measurement | its benchmark reproduced on your hardware, with your thread count and item size |

### 3.3 Asymmetric fences: when to adopt them

Adopt them when reads outnumber reclamation scans by far more than the break-even (about 500:1 on this machine, §1.3),
the platform guarantees the heavy side (Linux `membarrier` registered once at start-up, or Windows
`FlushProcessWriteBuffers`), and no core in the process is isolated for latency. Otherwise keep the symmetric `seq_cst`
fences, or move to QSBR (a reader cost of 0.33–0.46 ns, Folder 09) if threads have natural quiescent points.

---

## 4. Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| builds on one compiler, fails on another, "both support C++26" | gating on compiler versions or on `-std` | gate on `__cpp_lib_*` values (Listing 12.4), behind one adapter header |
| same feature, different behaviour across libraries | different revisions shipped (`flat_map` 202207L vs 202511L) | gate on the macro *value*; test both libraries in CI |
| `atomic<shared_ptr>` doesn't compile with libc++ | libc++ 21 doesn't ship it | libstdc++ / MSVC STL, folly, or redesign (RCU-style publication) |
| latency spikes on isolated cores after adopting a hazard-pointer library | asymmetric heavy fences IPI every running core of the process | symmetric fences, QSBR, or keep latency-critical threads in a separate process |
| a benchmark from a README doesn't reproduce | different core count, cache topology, item size, compiler | re-measure on your hardware before adopting (§1.2, step 6) |
| an "SB litmus passes" claim for an asymmetric fence | the heavy call's delay hides the window (§1.3) | rely on the documented OS guarantee and the argument; don't cite the test |
| false sharing with neighbouring allocations | a ring buffer's first and last slots share lines with other heap objects | padding slots around the buffer (rigtorp's `kPadding`), 128-byte padding where adjacent-line prefetch applies |
| a pinned library version's names don't match the standard's | library names drifted from the final standard wording | an adapter layer; verify against the pinned version |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "C++26 has hazard pointers. Can we use them?"</b></summary>

**Initial prompt.** "C++26 adopted hazard pointers and RCU. Can we drop our homegrown reclamation and use the standard
ones?"

**L5 textbook answer.** "Yes, compile with `-std=c++26` and include `<hazard_pointer>`."

**Why L5 breaks.** Listing 12.4: `__cpp_lib_hazard_pointer` and `__cpp_lib_rcu` are undefined in both libstdc++ 16 and
libc++ 21, even with `-std=c++26`. The header doesn't exist. The standard adopted them, and implementations haven't
shipped them yet.

**L7 principal defense.** "Use folly's `hazptr`, the implementation P2530 came from, behind one adapter header gated
on `__cpp_lib_hazard_pointer >= 202306L` (§3.1). When the macro appears in a library we build with, one file changes. I'd
also keep our test suite (stalled reader, bounded garbage) running against whichever implementation is selected."
</details>

<details><summary><b>Chain 2 🧊 "folly says protect is nearly free. Is it?"</b></summary>

**Initial prompt.** "folly's hazard pointers claim near-zero reader overhead. Where does the cost go?"

**L5 textbook answer.** "Hazard pointers just store a pointer, so they're always cheap."

**Why L5 breaks.** A plain hazard store needs a full store→load fence before the re-check (the SB pattern): `lock or`
on x86 and `dmb ish` on ARM64, 4.6–4.8 ns per protect here (Listing 12.5). folly removes it *on Linux only*, by
pairing a compiler barrier on the reader with a process-wide `membarrier` on the reclaimer. The cost moves: about 0.25 µs per
heavy call with the process otherwise idle, about 2 µs with 6 busy threads, plus an interrupt on every core running
the process.

**L7 principal defense.** "It's a trade with a measurable break-even, roughly 500 protects per heavy call on this
machine. Read-mostly structures with batched retirement win big. A structure that retires on every operation, or a
process with isolated latency-critical cores, loses, and there I'd keep symmetric fences or use QSBR. Off Linux, folly
itself falls back to ordinary fences, so the claim is platform-specific."
</details>

<details><summary><b>Chain 3 ⚠️ "Prove the asymmetric fence works"</b></summary>

**Initial prompt.** "Write a test that proves our light/heavy fence pair prevents the store-buffer outcome."

**L5 textbook answer.** "Run the SB litmus test a million times with light on one side and heavy on the other; zero
violations proves it."

**Why L5 breaks.** The test can't fail for the right reason. The heavy side takes microseconds, so by the time its load
runs, the light side's store has drained anyway. A version with a plain microsecond spin instead of the heavy fence would
also show zero. The test shows that a delay closes the window, which nobody doubted.

**L7 principal defense.** "This property is established by the platform contract, not by testing. membarrier(2)
guarantees that every running thread of the process passes a full barrier, and `FlushProcessWriteBuffers` documents the
same for the processors running the process's threads. Then the SB argument applies: either the reader's store was
flushed before the heavy side's load, or the reader's load runs after the heavy side's store became visible. I'd put
that argument in the code, model the algorithm with seq_cst fences in its place in GenMC, and say plainly that the
substitution itself can't be stress-tested."
</details>

<details><summary><b>Chain 4 🔥 "This lock-free queue has 5,000 stars"</b></summary>

**Initial prompt.** "A teammate wants to adopt a popular lock-free queue from GitHub for the order pipeline. What do
you check?"

**L5 textbook answer.** "Stars and a benchmark showing it's faster than `std::mutex`, so it's fine."

**Why L5 corrupts memory on ARM64.** Popularity says nothing about memory orders. A queue tested only on x86 can carry
store→load or acquire/release bugs that TSO hides (Folder 07), and its stress tests will pass forever on the author's
machine. Its benchmark may also be the bimodal SPSC artefact of Folder 09 (a full ring vs a flowing one), measured with
unpinned threads.

**L7 principal defense.** "The §3.2 checklist: a memory-order audit with stated pairings, deterministic or model-checked
tests, ARM64 CI with LL/SC and LSE builds, a stated reclamation scheme and stalled-thread behaviour, a named progress
guarantee, and the benchmark reproduced on our hardware with our item size. If it fails any of those, we either
contribute the fix and the test, or we use a structure that passes."
</details>

<details><summary><b>Chain 5 🧊 "Abseil Mutex or std::mutex?"</b></summary>

**Initial prompt.** "Why would anyone use `absl::Mutex` when `std::mutex` exists?"

**L5 textbook answer.** "Google style; it's basically the same thing."

**Why L5 breaks.** It's a different design. `absl::Mutex` is a reader/writer lock in one word, and its `Await` /
`LockWhen` with a `Condition` replace condition variables. You state the predicate, the mutex re-evaluates it on unlock,
and the lost wakeups and forgotten predicate loops of Folder 08 can't be written. It also has debug-mode deadlock
detection (`SetMutexDeadlockDetectionMode`). `std::mutex` is whatever the platform gives: SRWLOCK under libc++ on
Windows, winpthreads under MinGW's libstdc++, a futex under glibc (Folder 08).

**L7 principal defense.** "`std::mutex` at API boundaries and in portable libraries. `absl::Mutex` in a code base already
built on Abseil, where `Condition`-based waiting removes a bug class and deadlock detection runs in debug. I'd benchmark
both under our contention profile, because their spin-then-park policies differ."
</details>

<details><summary><b>Chain 6 ⚠️ "Why does crossbeam pad to 128 bytes?"</b></summary>

**Initial prompt.** "Cache lines are 64 bytes on x86. Why does crossbeam's `CachePadded` use 128?"

**L5 textbook answer.** "It's wasteful; 64 is the line size, so 64 is enough."

**Why L5 breaks.** Its source explains it: from Sandy Bridge on, Intel's spatial prefetcher pulls *pairs* of 64-byte
lines, so two hot variables 64 bytes apart can still interfere. On AArch64, the "big" cores of big.LITTLE designs have
128-byte lines. `std::hardware_destructive_interference_size` reports 64 here (Folder 07), and GCC warns
(`-Winterference-size`) that the value isn't ABI-stable.

**L7 principal defense.** "Pad hot, independently written variables to 128 on x86-64 and AArch64 unless memory is
tight, and measure. Folder 07's test showed no 64-vs-128 difference *for its access pattern*, which is a data point, not
a rule. I'd never put `hardware_destructive_interference_size` in an ABI-visible type, because it can change with
`-mtune`."
</details>

<details><summary><b>Chain 7 🔥 "Which talks should a new hire watch on the memory model?"</b></summary>

**Initial prompt.** "Give me a reading and viewing list for a senior engineer joining the low-latency team."

**L5 textbook answer.** "Herb Sutter's atomic<> Weapons; that covers everything."

**Why L5 breaks.** It's still the best introduction, but it's from 2012. C++20 repaired the specification of `seq_cst`
(P0668, based on RC11). `consume` was discouraged (C++17) and then deprecated (C++26). The C++20 synchronization library, senders and the
C++26 reclamation facilities came later. A list that stops in 2012 teaches a model that has since been corrected.

**L7 principal defense.** "A path, not a talk. Bos for code generation, the Primer for hardware, Williams for the
library, McKenney for RCU and counters. The §1.5 talks each have a caveat column. Then every week of §1.6 ends with
predicting a number and measuring it. Talks are hypotheses, and this KB's listings are how we check them."
</details>

<details><summary><b>Chain 8 🧊 "libc++ has no atomic shared_ptr"</b></summary>

**Initial prompt.** "We moved to libc++ and `std::atomic<std::shared_ptr<Config>>` stopped compiling. Quick fix?"

**L5 textbook answer.** "Use `std::atomic_load(&ptr)` / `std::atomic_store`; those work everywhere."

**Why L5 breaks.** They do compile, but they're deprecated in C++20, and libc++ implements them with a small global pool
of mutexes chosen by hashing the address (`libcxx/src/memory.cpp`). Every reader of the hot config pointer then takes a
mutex that it may share with unrelated pointers. Under load that serializes the readers, which an atomic shared pointer
was meant to avoid.

**L7 principal defense.** "First ask whether the pattern needs `atomic<shared_ptr>` at all. A read-mostly config is the
RCU pattern: readers take a cheap snapshot and the writer publishes a new version and reclaims the old one after a grace
period (Folder 09). If it does, use folly's `AtomicSharedPtr` behind an adapter, or keep libstdc++ / MSVC STL where
`__cpp_lib_atomic_shared_ptr` is defined (Listing 12.4). And the gate is the macro, so the libc++ build fails loudly
instead of silently falling back to a mutex."
</details>

<details><summary><b>Chain 9 ⚠️ "How do you read stdexec without drowning?"</b></summary>

**Initial prompt.** "stdexec is enormous and template-heavy. How would you get productive in it in a week?"

**L5 textbook answer.** "Read `execution.hpp` from the top."

**Why L5 breaks.** The header is mostly machinery: environments, queries, completion-signature computation and
customization. Reading it top-down tells you how the library is assembled, not what a sender *does*. The concepts
everyone gets wrong (operation-state lifetime, which completion channel fires, where a continuation runs) aren't
visible from the top.

**L7 principal defense.** "Follow one path end to end: `sync_wait(then(just(42), f))`. Find `connect`, the operation
state and `start`, and the three completion channels. Then read `__when_all.hpp`, because it holds the hard parts:
counting completions, fanning out stop requests, error wins. Keep Folder 10's 250-line core open as a map, step through
in a debugger, and read the tests for each algorithm before its implementation."
</details>

---

## 6. Invariants checklist

- [ ] Every use of a C++23/26 library feature is gated on its `__cpp_lib_*` value through one adapter header.
- [ ] CI builds with both libstdc++ and libc++ (and MSVC STL if shipped), because the matrices differ.
- [ ] Every adopted third-party concurrent structure passed the §3.2 checklist, at a pinned version.
- [ ] Every benchmark claim we rely on was reproduced on our hardware and recorded with its configuration.
- [ ] Asymmetric fences are used only where the break-even is met, the OS guarantees the heavy side, and no core is isolated.
- [ ] Each team member's reading follows §1.6: read the source, predict the number, measure it.

## 7. References

- Feature-test macros (cppreference): <https://en.cppreference.com/w/cpp/utility/feature_test>
- folly asymmetric fences, header and implementation: <https://github.com/facebook/folly/blob/main/folly/synchronization/AsymmetricThreadFence.cpp>
- Linux `membarrier(2)`: <https://man7.org/linux/man-pages/man2/membarrier.2.html>
- Windows `FlushProcessWriteBuffers`: <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-flushprocesswritebuffers>
- J. Preshing, "Acquire and Release Semantics": <https://preshing.com/20120913/acquire-and-release-semantics/>; "Memory Ordering at Compile Time": <https://preshing.com/20120625/memory-ordering-at-compile-time/>
- The source list (§1.4), books, papers and talks (§1.5) are this file's main references.
