# 02 · `mutex`, `shared_mutex`, `scoped_lock`, deadlock avoidance, and Linux futex internals

> **Scope.** An uncontended mutex lock is one atomic instruction in user space. The kernel is involved only when a
> thread must sleep: that is the futex design that Linux mutexes, condition variables and `atomic::wait` are built on.
> This file shows what `std::mutex` is on three platforms (from the object file), builds the classic three-state futex
> mutex and disassembles its Linux system calls, forces a lock-order deadlock deterministically and fixes it with
> `std::scoped_lock` (with the library's algorithm quoted), and measures when `std::shared_mutex` helps. It helps far
> less often than its name suggests.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 8.4 | `sync_sizes.cpp` | sizes of all 12 primitives: libstdc++/winpthreads (8-byte handles), libc++/Win32 (SRWLOCK), libc++/glibc x86-64 and AArch64 (`pthread_mutex_t` 40/48 B, `shared_mutex` 144/152 B) | run (Windows, both libraries); Linux values read from the object file's data section |
| 8.5 | `futex_mutex.cpp` | Drepper's 0/1/2 mutex: one `LOCK CMPXCHG`/LL-SC uncontended, `syscall(SYS_futex=202 / 98, FUTEX_WAIT_PRIVATE=128, ...)` only on contention; 0 sleeps uncontended | asm x86-64 + AArch64 (Linux, raw futex); run (Windows, `atomic::wait` as the futex) |
| 8.6 | `deadlock_order.cpp` | an opposite-order transfer deadlock, forced and detected with `try_lock_for`; `std::scoped_lock` completes 200,000 transfers; libstdc++'s `std::lock` algorithm | run, both compilers; excerpt of `<mutex>` |
| 8.7 | `shared_mutex_bench.cpp` | `shared_mutex` is 2–11× **slower** than `mutex` for empty read sections and wins clearly only with microsecond reads; libc++'s reader path takes an internal mutex | run, 1/2/4 threads; excerpt of libc++ `shared_mutex.cpp` |

**Verification line.** As in file 01. Linux runtime behaviour (glibc's futex paths) is described from source and
documentation (⚠ not run here). The Linux *code* (system-call numbers, data sizes) is compiled and shown.

---

## 1. First principles

### 1.1 What a mutex is, per platform (Listing 8.4)

```cpp
// sync_sizes.cpp - the size of every synchronization primitive, per library and ABI (Linux values read from the .o)
#include <barrier>
#include <condition_variable>
#include <cstddef>
#include <latch>
#include <mutex>
#include <print>
#include <semaphore>
#include <shared_mutex>
#include <thread>

extern const std::size_t size_mutex = sizeof(std::mutex);
extern const std::size_t size_recursive_mutex = sizeof(std::recursive_mutex);
extern const std::size_t size_timed_mutex = sizeof(std::timed_mutex);
extern const std::size_t size_shared_mutex = sizeof(std::shared_mutex);
extern const std::size_t size_condition_variable = sizeof(std::condition_variable);
extern const std::size_t size_condition_variable_any = sizeof(std::condition_variable_any);
extern const std::size_t size_counting_semaphore = sizeof(std::counting_semaphore<>);
extern const std::size_t size_binary_semaphore = sizeof(std::binary_semaphore);
extern const std::size_t size_latch = sizeof(std::latch);
extern const std::size_t size_barrier = sizeof(std::barrier<>);
extern const std::size_t size_once_flag = sizeof(std::once_flag);
extern const std::size_t size_jthread = sizeof(std::jthread);

#ifndef ASM_VIEW
int main() {
    const std::pair<const char*, std::size_t> rows[] = {
        {"mutex", size_mutex},
        {"recursive_mutex", size_recursive_mutex},
        {"timed_mutex", size_timed_mutex},
        {"shared_mutex", size_shared_mutex},
        {"condition_variable", size_condition_variable},
        {"condition_variable_any", size_condition_variable_any},
        {"counting_semaphore<>", size_counting_semaphore},
        {"binary_semaphore", size_binary_semaphore},
        {"latch", size_latch},
        {"barrier<>", size_barrier},
        {"once_flag", size_once_flag},
        {"jthread", size_jthread},
    };
    for (const auto& [name, size] : rows) std::println("{:<24} {:>3} bytes", name, size);
}
#endif
```

Windows (verified), GCC/libstdc++ (winpthreads), then Clang/libc++ (Win32):

```text
mutex                      8 bytes
recursive_mutex            8 bytes
timed_mutex                8 bytes
shared_mutex               8 bytes
condition_variable         8 bytes
condition_variable_any    24 bytes
counting_semaphore<>       8 bytes
binary_semaphore           8 bytes
latch                      4 bytes
barrier<>                 32 bytes
once_flag                  4 bytes
jthread                   16 bytes
```

```text
mutex                      8 bytes
recursive_mutex           40 bytes
timed_mutex               24 bytes
shared_mutex              32 bytes
condition_variable         8 bytes
condition_variable_any    24 bytes
counting_semaphore<>       8 bytes
binary_semaphore           8 bytes
latch                      8 bytes
barrier<>                 40 bytes
once_flag                  4 bytes
jthread                   16 bytes
```

Linux (libc++ on glibc, read from the object file's `.rodata`):

```text
object                       libc++ / glibc x86-64  libc++ / glibc AArch64
---------------------------  ---------------------  ----------------------
size_mutex                   .quad 40               .xword 48
size_recursive_mutex         .quad 40               .xword 48
size_timed_mutex             .quad 96               .xword 104
size_shared_mutex            .quad 144              .xword 152
size_condition_variable      .quad 48               .xword 48
size_condition_variable_any  .quad 64               .xword 64
size_counting_semaphore      .quad 8                .xword 8
size_binary_semaphore        .quad 8                .xword 8
size_latch                   .quad 8                .xword 8
size_barrier                 .quad 40               .xword 40
size_once_flag               .quad 8                .xword 8
size_jthread                 .quad 16               .xword 16
```

* **libstdc++ on MinGW**: every primitive is an 8-byte pointer-sized handle to a winpthreads object, created on first
  use. **libc++ on Windows**: `std::mutex` *is* a Win32 `SRWLOCK` (one pointer-sized word), and `condition_variable` is
  a `CONDITION_VARIABLE`. **glibc**: `pthread_mutex_t` is 40 bytes on x86-64 and 48 on AArch64. It holds the futex
  word plus owner, recursion count, kind and spin data.
* libc++'s `shared_mutex` is its own algorithm: a mutex, two condition variables and a state word. That's 144 bytes on
  glibc x86-64 and 32 on Windows (§1.4). libstdc++'s wraps `pthread_rwlock_t`.
* Sizes matter for layout: a mutex per element of a million-element container is 8 MB on one platform and 40–48 MB on
  another. A mutex must also never move (Chain 8).

### 1.2 The futex mutex (Listing 8.5)

```cpp
// futex_mutex.cpp - Drepper's three-state futex mutex: one CAS when uncontended, a syscall only when contended
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <print>
#include <thread>
#include <vector>
#if defined(__linux__) && defined(RAW_FUTEX)
#include <linux/futex.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

std::atomic<std::int64_t> g_sleeps{0};   // how often the slow path asked the OS to sleep

// The futex contract: WAIT sleeps only if *addr still equals `expected` (checked inside the kernel, atomically
// with going to sleep, so a wake between our check and the sleep is not lost); WAKE wakes up to n sleepers.
// C++20 atomic::wait/notify_one is the same contract; on Linux, libstdc++ and libc++ implement it with futex.
inline void os_wait(std::atomic<int>& word, int expected) {
    g_sleeps.fetch_add(1, std::memory_order_relaxed);
#if defined(__linux__) && defined(RAW_FUTEX)
    syscall(SYS_futex, &word, FUTEX_WAIT_PRIVATE, expected, nullptr, nullptr, 0);
#else
    word.wait(expected, std::memory_order_relaxed);
#endif
}
inline void os_wake_one(std::atomic<int>& word) {
#if defined(__linux__) && defined(RAW_FUTEX)
    syscall(SYS_futex, &word, FUTEX_WAKE_PRIVATE, 1, nullptr, nullptr, 0);
#else
    word.notify_one();
#endif
}

// state: 0 = unlocked, 1 = locked and no waiters, 2 = locked and a waiter may be asleep.
class FutexMutex {
    std::atomic<int> state_{0};

public:
    void lock() {
        int c = 0;
        if (state_.compare_exchange_strong(c, 1, std::memory_order_acquire)) return;   // fast path
        if (c != 2) c = state_.exchange(2, std::memory_order_acquire);                  // announce a waiter
        while (c != 0) {             // the lock was held: sleep while it is still "locked, contended"
            os_wait(state_, 2);
            c = state_.exchange(2, std::memory_order_acquire);   // 2, not 1: other sleepers may still exist
        }
    }
    void unlock() {
        if (state_.exchange(0, std::memory_order_release) == 2) os_wake_one(state_);   // wake only if needed
    }
};

void lock_it(FutexMutex& m) { m.lock(); }       // out-of-line copies for the assembly listing
void unlock_it(FutexMutex& m) { m.unlock(); }

#ifndef ASM_VIEW
template <class M>
double bench(int threads, int iters, std::int64_t& counter) {
    M m;
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {
            }
            for (int i = 0; i < iters; ++i) {
                m.lock();
                ++counter;
                m.unlock();
            }
        });
    while (ready.load() != threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    go.store(true, std::memory_order_release);
    ts.clear();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / (static_cast<double>(threads) * iters);
}

int main() {
    constexpr int kIters = 200'000;
    for (int threads : {1, 4}) {
        std::int64_t c1 = 0, c2 = 0;
        g_sleeps = 0;
        const double f = bench<FutexMutex>(threads, kIters, c1);
        const std::int64_t sleeps = g_sleeps.load();
        const double s = bench<std::mutex>(threads, kIters, c2);
        std::println("{} thread(s): FutexMutex {:6.1f} ns/op, std::mutex {:6.1f} ns/op, counts exact: {}", threads, f, s,
                     c1 == c2 && c1 == static_cast<std::int64_t>(threads) * kIters ? "yes" : "NO");
        if (threads == 1) std::println("  uncontended: slow-path sleeps = {}", sleeps);
        else std::println("  contended:   slow-path sleeps per 1000 ops = {:.1f}", 1000.0 * static_cast<double>(sleeps) / (threads * kIters));
    }
}
#endif
```

Linux x86-64 (Clang 21 `-O3`, `-DRAW_FUTEX`):

```asm
_Z7lock_itR10FutexMutex:           # lock_it(FutexMutex&)
	movl	$1, %ecx
	xorl	%eax, %eax
	lock	cmpxchgl	%ecx, (%rdi)
	je	.LBB0_6
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	movq	%rdi, %rbx
	cmpl	$2, %eax
	je	.LBB0_3
	movl	$2, %eax
	xchgl	%eax, (%rbx)
	testl	%eax, %eax
	je	.LBB0_5
.LBB0_3:
	movq	g_sleeps@GOTPCREL(%rip), %r14
.LBB0_4:
	lock	addq	$1, (%r14)
	movl	$0, (%rsp)
	movl	$202, %edi
	movq	%rbx, %rsi
	movl	$128, %edx
	movl	$2, %ecx
	xorl	%r8d, %r8d
	xorl	%r9d, %r9d
	xorl	%eax, %eax
	callq	syscall@PLT
	movl	$2, %eax
	xchgl	%eax, (%rbx)
	testl	%eax, %eax
	jne	.LBB0_4
.LBB0_5:
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
.LBB0_6:
	retq

_Z9unlock_itR10FutexMutex:         # unlock_it(FutexMutex&)
	xorl	%eax, %eax
	xchgl	%eax, (%rdi)
	cmpl	$2, %eax
	jne	.LBB1_2
	pushq	%rax
	movq	%rdi, %rsi
	movl	$0, (%rsp)
	movl	$202, %edi
	movl	$129, %edx
	movl	$1, %ecx
	xorl	%r8d, %r8d
	xorl	%r9d, %r9d
	xorl	%eax, %eax
	callq	syscall@PLT
	popq	%rax
.LBB1_2:
	retq
```

Linux AArch64:

```asm
_Z7lock_itR10FutexMutex:           // lock_it(FutexMutex&)
	stp	x30, x21, [sp, #-32]!
	stp	x20, x19, [sp, #16]
	mov	x19, x0
.LBB0_1:
	ldaxr	w8, [x19]
	cbnz	w8, .LBB0_4
	mov	w9, #1
	stxr	w10, w9, [x19]
	cbnz	w10, .LBB0_1
	tbz	w9, #0, .LBB0_5
	b	.LBB0_14
.LBB0_4:
	mov	w9, wzr
	clrex
	tbnz	w9, #0, .LBB0_14
.LBB0_5:
	cmp	w8, #2
	b.eq	.LBB0_9
	mov	w8, #2
.LBB0_7:
	ldaxr	w9, [x19]
	stxr	w10, w8, [x19]
	cbnz	w10, .LBB0_7
	cbz	w9, .LBB0_14
.LBB0_9:
	adrp	x20, :got:g_sleeps
	mov	w21, #2
	ldr	x20, [x20, :got_lo12:g_sleeps]
.LBB0_10:
	ldxr	x8, [x20]
	add	x8, x8, #1
	stxr	w9, x8, [x20]
	cbnz	w9, .LBB0_10
	mov	w0, #98
	mov	x1, x19
	mov	w2, #128
	mov	w3, #2
	mov	x4, xzr
	mov	x5, xzr
	mov	w6, wzr
	bl	syscall
.LBB0_12:
	ldaxr	w8, [x19]
	stxr	w9, w21, [x19]
	cbnz	w9, .LBB0_12
	cbnz	w8, .LBB0_10
.LBB0_14:
	ldp	x20, x19, [sp, #16]
	ldp	x30, x21, [sp], #32
	ret

_Z9unlock_itR10FutexMutex:         // unlock_it(FutexMutex&)
	mov	x1, x0
.LBB1_1:
	ldxr	w8, [x1]
	stlxr	w9, wzr, [x1]
	cbnz	w9, .LBB1_1
	cmp	w8, #2
	b.ne	.LBB1_4
	mov	w0, #98
	mov	w2, #129
	mov	w3, #1
	mov	x4, xzr
	mov	x5, xzr
	mov	w6, wzr
	b	syscall
.LBB1_4:
	ret
```

Run on Windows (verified, GCC then Clang; here `os_wait`/`os_wake_one` are `atomic::wait`/`notify_one`):

```text
1 thread(s): FutexMutex   10.4 ns/op, std::mutex   15.3 ns/op, counts exact: yes
  uncontended: slow-path sleeps = 0
4 thread(s): FutexMutex   57.8 ns/op, std::mutex   28.2 ns/op, counts exact: yes
  contended:   slow-path sleeps per 1000 ops = 306.8
1 thread(s): FutexMutex   10.1 ns/op, std::mutex   14.2 ns/op, counts exact: yes
  uncontended: slow-path sleeps = 0
4 thread(s): FutexMutex  120.9 ns/op, std::mutex   23.5 ns/op, counts exact: yes
  contended:   slow-path sleeps per 1000 ops = 1325.6
```

* **The kernel contract.** `futex(addr, FUTEX_WAIT_PRIVATE, expected)` puts the thread to sleep **only if `*addr ==
  expected`**. The kernel checks this under its hash-bucket lock, atomically with queueing the thread, so a wake that
  happens between the user-space check and the syscall is never lost. `FUTEX_WAKE_PRIVATE, n` wakes up to n sleepers.
  `_PRIVATE` (the +128 visible in the asm) skips cross-process lookup. In the asm, the system-call numbers are `202` on
  x86-64 and `98` on AArch64, the operations `128` (wait) and `129` (wake).
* **Why three states** (Drepper, *Futexes Are Tricky*). With only 0/1, `unlock` must call `FUTEX_WAKE` on every unlock,
  because it can't know whether anyone sleeps. State **2** means "someone may be asleep". `unlock` exchanges in 0 and
  makes the syscall only if the old value was 2. **Uncontended, lock and unlock are one `LOCK CMPXCHG` and one `XCHG`
  (one `LDAXR`/`STXR` loop each on AArch64), and the run shows 0 slow-path sleeps.**
* **Why a woken thread sets 2, not 1.** After waking, the thread can't know whether other sleepers remain. Taking the
  lock as 1 would make its `unlock` skip the wake and strand them. Setting 2 costs at most one unnecessary wake.
* **Measured:** uncontended, 10.1–10.7 ns per lock/unlock pair against 14.2–15.4 ns for `std::mutex`. With 4
  threads, **53–121 ns against 21–29 ns: the textbook mutex is 2–5× slower under contention**, with 258–1,326 sleeps per
  1,000 operations. It sleeps after one failed exchange, and on Windows its "futex" is each library's `atomic::wait`
  emulation (file 03). Production mutexes spin briefly before sleeping (glibc's adaptive type, `absl::Mutex`, WebKit's
  `WTF::Lock`) and hand off fairly. glibc's default mutex is this 0/1/2 design in `lowlevellock.h` (⚠ not run here).

### 1.3 Deadlock avoidance (Listing 8.6)

```cpp
// deadlock_order.cpp - lock-order inversion made deterministic, detected with a timeout, fixed by std::scoped_lock
#include <chrono>
#include <latch>
#include <mutex>
#include <print>
#include <thread>

struct Account {
    std::timed_mutex m;
    long long balance = 1000;
};

// Naive transfer: lock `from`, then `to`. Thread 1 moves A->B while thread 2 moves B->A.
bool transfer_naive(Account& from, Account& to, long long amount, std::latch& both_hold_first,
                    std::latch& both_tried) {
    std::unique_lock first(from.m);
    both_hold_first.arrive_and_wait();     // force the fatal interleaving: each thread holds its first lock
    std::unique_lock second(to.m, std::defer_lock);
    const bool got = second.try_lock_for(std::chrono::milliseconds(300));   // lock() would block forever
    both_tried.arrive_and_wait();          // keep holding `first` until the other thread has given up too
    if (!got) return false;
    from.balance -= amount;
    to.balance += amount;
    return true;
}

// std::scoped_lock acquires all its mutexes with a deadlock-avoidance algorithm, whatever order callers name them.
void transfer_safe(Account& from, Account& to, long long amount) {
    std::scoped_lock both(from.m, to.m);
    from.balance -= amount;
    to.balance += amount;
}

int main() {
    Account a, b;
    {
        std::latch both_hold_first(2), both_tried(2);
        bool ok1 = true, ok2 = true;
        {
            std::jthread t1([&] { ok1 = transfer_naive(a, b, 10, both_hold_first, both_tried); });
            std::jthread t2([&] { ok2 = transfer_naive(b, a, 20, both_hold_first, both_tried); });
        }
        std::println("naive lock order: thread 1 {}, thread 2 {} -> {}", ok1 ? "finished" : "timed out",
                     ok2 ? "finished" : "timed out", !ok1 && !ok2 ? "a deadlock (each waits for the other's lock)" : "no deadlock this time");
    }
    {
        constexpr int kTransfers = 100'000;
        {
            std::jthread t1([&] { for (int i = 0; i < kTransfers; ++i) transfer_safe(a, b, 1); });
            std::jthread t2([&] { for (int i = 0; i < kTransfers; ++i) transfer_safe(b, a, 1); });
        }
        std::println("scoped_lock: 2 x {} opposite-order transfers finished; total balance {} (expected 2000)",
                     kTransfers, a.balance + b.balance);
    }
}
```

Output (verified, GCC then Clang):

```text
naive lock order: thread 1 timed out, thread 2 timed out -> a deadlock (each waits for the other's lock)
scoped_lock: 2 x 100000 opposite-order transfers finished; total balance 2000 (expected 2000)
naive lock order: thread 1 timed out, thread 2 timed out -> a deadlock (each waits for the other's lock)
scoped_lock: 2 x 100000 opposite-order transfers finished; total balance 2000 (expected 2000)
```

How libstdc++'s `std::lock` (used by `std::scoped_lock` for two or more mutexes) avoids the deadlock:

```text
// mutex (libstdc++ 16.2), lines 636-670
  636      // On each recursion the lockables are rotated left one position,
  637      // e.g. depth 0: l0, l1, l2; depth 1: l1, l2, l0; depth 2: l2, l0, l1.
  638      // When a call to l_i.try_lock() fails it recurses/returns to depth=i
  639      // so that l_i is the first argument, and then blocks until l_i is locked.
  640      template<typename _L0, typename... _L1>
  641        void
  642        __lock_impl(int& __i, int __depth, _L0& __l0, _L1&... __l1)
  643        {
  644          while (__i >= __depth)
  645            {
  646              if (__i == __depth)
  647                {
  648                  int __failed = 1; // index that couldn't be locked
  649                  {
  650                    unique_lock<_L0> __first(__l0);
  651                    __failed += __detail::__try_lock_impl(__l1...);
  652                    if (!__failed)
  653                      {
  654                        __i = -1; // finished
  655                        __first.release();
  656                        return;
  657                      }
  658                  }
  659  #if defined _GLIBCXX_HAS_GTHREADS && defined _GLIBCXX_USE_SCHED_YIELD
  660                  __gthread_yield();
  661  #endif
  662                  constexpr auto __n = 1 + sizeof...(_L1);
  663                  __i = (__depth + __failed) % __n;
  664                }
  665              else // rotate left until l_i is first.
  666                __detail::__lock_impl(__i, __depth + 1, __l1..., __l0);
  667            }
  668        }
  669  
  670    } // namespace __detail
```

* **The deadlock** needs four conditions (Coffman): mutual exclusion, hold-and-wait, no preemption, and a circular
  wait. The two latches force the circular wait (each thread holds its first lock and wants the other's), and
  `try_lock_for` turns the hang into a report.
* **`std::lock` removes hold-and-wait.** It blocks on one mutex, *tries* the others, and if any `try_lock` fails it
  releases everything, yields, and restarts **blocking on the one that failed** (the rotation above). No thread ever
  blocks while holding a lock the others need. The cost: under heavy contention it can retry many times, and it gives
  no fairness guarantee.
* **The alternative is a global order**: lock accounts by ascending ID (or address). That is deterministic and
  cheaper, but every code path must follow it, which is easy to get wrong in a large codebase and is why lock-hierarchy
  checkers exist.

### 1.4 `shared_mutex`: when readers really run in parallel (Listing 8.7)

```cpp
// shared_mutex_bench.cpp - a read-mostly table: std::mutex vs std::shared_mutex, short vs long critical sections
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <print>
#include <shared_mutex>
#include <thread>
#include <vector>

struct Table {
    std::array<std::uint64_t, 64> v{};
    std::uint64_t read(int work) const {          // `work` = how long the reader holds the lock
        std::uint64_t s = 0;
        for (int r = 0; r < work; ++r)
            for (auto x : v) s += x ^ static_cast<std::uint64_t>(r);
        return s;
    }
};

template <class Mutex, bool Shared>
double run(int threads, int work, int ops) {
    Mutex m;
    Table t;
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::atomic<std::uint64_t> sink{0};
    std::vector<std::jthread> ts;
    for (int i = 0; i < threads; ++i)
        ts.emplace_back([&, i] {
            std::uint64_t local = 0;
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {
            }
            for (int op = 0; op < ops; ++op) {
                if (op % 100 == 0) {                       // 1% writes
                    std::unique_lock lk(m);
                    t.v[static_cast<std::size_t>(op % 64)] += static_cast<std::uint64_t>(i + 1);
                } else if constexpr (Shared) {
                    std::shared_lock lk(m);
                    local += t.read(work);
                } else {
                    std::unique_lock lk(m);
                    local += t.read(work);
                }
            }
            sink.fetch_add(local, std::memory_order_relaxed);
        });
    while (ready.load() != threads) {
    }
    const auto t0 = std::chrono::steady_clock::now();
    go.store(true, std::memory_order_release);
    ts.clear();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / (static_cast<double>(threads) * ops);
}

int main() {
    std::println("ns per operation (99% reads), wall time / total ops");
    std::println("threads  read section       std::mutex   std::shared_mutex");
    struct Case { int work, ops; const char* name; };
    for (const Case c : {Case{0, 200'000, "empty"}, Case{8, 100'000, "512 words"}, Case{128, 10'000, "8192 words"}})
        for (int threads : {1, 2, 4})
            std::println("{:>7}  {:<14} {:>12.1f}   {:>17.1f}", threads, c.name, run<std::mutex, false>(threads, c.work, c.ops),
                         run<std::shared_mutex, true>(threads, c.work, c.ops));
}
```

Output (verified, GCC/winpthreads `pthread_rwlock`, then Clang/libc++):

```text
ns per operation (99% reads), wall time / total ops
threads  read section       std::mutex   std::shared_mutex
      1  empty                  49.9               165.7
      2  empty                  39.4               198.0
      4  empty                  43.4               392.4
      1  512 words             305.4               378.7
      2  512 words             528.0               287.7
      4  512 words             390.0               537.0
      1  8192 words           3674.0              3906.6
      2  8192 words           4882.8              2088.2
      4  8192 words           4947.5              1232.6
ns per operation (99% reads), wall time / total ops
threads  read section       std::mutex   std::shared_mutex
      1  empty                  15.1                30.3
      2  empty                  18.6                46.5
      4  empty                  30.6               101.7
      1  512 words              63.1                79.7
      2  512 words              67.2               111.1
      4  512 words              85.4               199.9
      1  8192 words            808.2               817.1
      2  8192 words            861.4               448.5
      4  8192 words            919.4               250.1
```

libc++'s implementation (Howard Hinnant's two-gate algorithm):

```text
// shared_mutex.cpp (libc++ 21 sources), lines 22-29,50-57
   22  void __shared_mutex_base::lock() {
   23    unique_lock<mutex> lk(__mut_);
   24    while (__state_ & __write_entered_)
   25      __gate1_.wait(lk);
   26    __state_ |= __write_entered_;
   27    while (__state_ & __n_readers_)
   28      __gate2_.wait(lk);
   29  }
    ...
   50  void __shared_mutex_base::lock_shared() {
   51    unique_lock<mutex> lk(__mut_);
   52    while ((__state_ & __write_entered_) || (__state_ & __n_readers_) == __n_readers_)
   53      __gate1_.wait(lk);
   54    unsigned num_readers = (__state_ & __n_readers_) + 1;
   55    __state_ &= ~__n_readers_;
   56    __state_ |= num_readers;
   57  }
```

* **A shared lock is still a write.** Every `lock_shared` and `unlock_shared` updates the reader count. In libc++ it
  even takes the internal `std::mutex` exclusively for that update (above). Readers therefore serialize on one cache
  line for a moment at entry and exit, which costs more than the whole critical section when the section is short.
* **Measured** over two runs:
  * **Empty read sections:** `shared_mutex` was **2.0–3.3× slower** than `std::mutex` with libc++ and **3.3–10.6×
    slower** with winpthreads, at every thread count.
  * **512-word reads (60–300 ns):** libc++ was still 1.3–2.4× slower at every count. winpthreads was mixed: 1.2–1.4×
    slower at 1 and 4 threads, 1.8× faster at 2.
  * **8,192-word reads (0.8–4 µs):** it scaled. At 4 threads it ran 229–250 ns vs 853–919 ns (libc++) and 952–1,233 ns
    vs 4,396–4,948 ns (winpthreads): **3.7–4.6× faster**.
* **Writer preference.** libc++'s `__write_entered_` bit closes gate 1 as soon as a writer arrives: new readers wait,
  so writers can't be starved. libstdc++ uses `pthread_rwlock_t`, and glibc's default rwlock kind prefers *readers*, so
  a continuous stream of readers can delay a writer indefinitely (⚠ glibc, not run here). The standard specifies neither
  policy.

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| mutexes | `mutex`, `recursive_mutex`, `timed_mutex`, `recursive_timed_mutex` | `shared_timed_mutex` | `shared_mutex` | — | — | — |
| lock management | `lock_guard`, `unique_lock`, `std::lock`, `try_lock` | `shared_lock` | `scoped_lock` (variadic, deadlock-avoiding), CTAD for lock types | — | — | — |
| OS-level waiting | (implementation detail) | — | — | `atomic::wait`/`notify` exposes futex-style waiting (P1135) | — | — |
| related | — | — | — | `std::latch`, `std::barrier`, `std::counting_semaphore` (file 04) | — | hazard pointers, RCU for read-mostly data (Folder 09) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| two-object operation (transfer, swap, merge) | lock in parameter order (deadlocks on opposite calls, Listing 8.6) | `std::scoped_lock a(x.m, y.m)`, or lock by ascending ID everywhere |
| read-mostly map, short lookups | `std::shared_mutex` (2–11× slower here for tiny lookups) | `std::mutex` + sharding; or an immutable snapshot behind `atomic<shared_ptr>` / RCU (Folders 07, 09) |
| read-mostly, long scans (µs+) | `std::mutex` serializing readers | `std::shared_mutex` (3.7–4.6× at 4 threads), with an explicit writer-preference requirement |
| writers must not starve | rely on `std::shared_mutex` fairness (unspecified; glibc prefers readers) | a writer-preferring lock (Folder 11, problem 4), or libc++'s algorithm |
| self-deadlock when a method calls another | switch to `recursive_mutex` | public methods lock, private `_locked` helpers assume the lock |
| a mutex per element | `std::vector<Item>` where `Item` holds a `std::mutex` (no moves; 8 vs 40–48 B per item) | lock striping: a fixed array of mutexes indexed by hash |
| custom lock on a hot path | hand-written 0/1 spin or futex lock | the platform mutex (it spins adaptively and hands off fairly) unless profiling proves otherwise |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a hang only when two operations run in opposite directions | lock-order inversion | TSan's lock-order-inversion report (Folder 12, ⚠); lock-hierarchy assertions; `try_lock_for` probes as in Listing 8.6 |
| CPU high, throughput low under contention | `std::lock` retry storms, or a spin lock without back-off | `perf` shows time in `try_lock`/yield |
| readers fast, writers wait seconds | reader-preferring rwlock under constant read load | writer-latency histogram; switch the lock policy |
| `shared_mutex` slower than `mutex` | short critical sections; reader count is a contended write | measure both (Listing 8.7) |
| sporadic crash after a container reallocates | a mutex (or an object holding one) moved/copied while in use | `std::mutex` is non-movable; the compiler rejects direct moves, so look for `memcpy` or custom move constructors |
| futex-based lock hangs with a waiter never woken | 0/1 design that skips the wake, or a woken thread resetting state to 1 | Drepper's three-state invariants; stress tests |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Is locking a std::mutex a system call?"</b></summary>

**Initial prompt.** "Why is an uncontended `std::mutex` lock only ~15 ns if it's an OS mutex?"

**L5 textbook answer.** "The kernel caches the mutex, so the system call is fast."

**Why L5 breaks.** No system call happens. On Linux the lock word is a futex: `lock` is one `LOCK CMPXCHG` in user
space (Listing 8.5: the fast path before `.LBB0_6`), and `syscall` with number 202 appears only on the path where the
CAS fails. The run shows 0 slow-path sleeps for 200,000 uncontended lock/unlock pairs. Windows `SRWLOCK` works the same
way: user-space atomics first, a kernel wait only when contended.

**L7 principal defense.** "User space handles the uncontended case. The kernel is only a sleeping queue keyed by the
word's address: `FUTEX_WAIT` sleeps if the word still has the value I saw, atomically with queueing, and `FUTEX_WAKE`
wakes n. Contention is what costs: a sleep and a wake are two system calls plus two context switches."
</details>

<details><summary><b>Chain 2 ⚡ "Write a futex mutex"</b></summary>

**Initial prompt.** "Implement a mutex with `std::atomic<int>` and `wait`/`notify_one`."

**L5 textbook answer.**
`lock(): while (s.exchange(1)) s.wait(1);` and `unlock(): s.store(0); s.notify_one();`

**Why L5 breaks.** It works, but `unlock` pays for `notify_one` on **every** unlock: on Linux a `FUTEX_WAKE` system
call even when nobody waits, which multiplies the uncontended cost. Removing the unconditional wake with only two
states loses wakeups, because the unlocker cannot know whether a sleeper exists. And a woken thread that takes the lock
as `1` makes its own `unlock` skip waking the remaining sleepers.

**L7 principal defense.** "Three states, as in Listing 8.5: 0 unlocked, 1 locked uncontended, 2 locked and contended.
CAS 0→1 on the fast path. Otherwise exchange in 2 and wait while it's 2. `unlock` exchanges in 0 and wakes only if the
old value was 2, and a woken thread re-acquires with 2. Then I'd tell them I would still use the platform mutex: my
version was 2–5× slower than `std::mutex` under contention here, because it doesn't spin before sleeping."
</details>

<details><summary><b>Chain 3 🔥 "Bank transfer between two accounts"</b></summary>

**Initial prompt.** "`transfer(from, to, amount)` locks `from.m`, then `to.m`. Is it thread-safe?"

**L5 textbook answer.** "Yes. Both accounts are locked during the update, so balances are consistent."

**Why L5 deadlocks on ARM64.** It deadlocks on every architecture: `transfer(a, b)` and `transfer(b, a)` running at
once each hold one lock and wait for the other. That's a circular wait. Listing 8.6 forces exactly that interleaving
with two latches: both threads time out holding their first lock.

**L7 principal defense.** "`std::scoped_lock both(from.m, to.m)`: `std::lock`'s lock/try/back-off/rotate algorithm
never blocks while holding a contested lock. Or a global order (lock the lower account ID first), applied everywhere,
with a debug-mode lock-rank check. And handle `from == to`, or `scoped_lock` will try to lock the same mutex twice."
</details>

<details><summary><b>Chain 4 🧊 "Then scoped_lock everywhere?"</b></summary>

**Initial prompt.** "If `scoped_lock` avoids deadlock, should we replace all lock ordering with it?"

**L5 textbook answer.** "Yes, it's strictly better: no ordering rules to remember."

**Why L5 breaks.** It only protects locks acquired **in the same call**. Code that takes one lock, calls into another
module, and that module takes a second lock is outside its reach. Under heavy contention its try-and-back-off loop can
thrash: release everything, yield, retry. The excerpt shows `__gthread_yield()` between attempts. And it gives no
fairness.

**L7 principal defense.** "`scoped_lock` for multi-lock operations in one place; a documented global lock hierarchy for
locks that nest across modules; and a design goal of never calling unknown code (callbacks, virtual hooks) while
holding a lock."
</details>

<details><summary><b>Chain 5 🔥 "Use shared_mutex for the read-mostly cache"</b></summary>

**Initial prompt.** "Our config cache is read 99% of the time. We switched `std::mutex` to `std::shared_mutex` so
readers run in parallel. Latency got worse. How?"

**L5 textbook answer.** "Impossible. Readers no longer block each other, so it must be faster."

**Why L5 breaks.** Readers don't *block* each other, but they still *write* the lock's reader count. In libc++ every
`lock_shared` even takes an internal `std::mutex` (excerpt in §1.4). With short sections the lock's cache line
ping-pongs between readers, and that costs more than the lookup. Listing 8.7: 2–11× slower than `std::mutex` with
empty read sections, and up to 2.4× slower with 512-word reads on libc++. It pulled clearly ahead only with
microsecond-long reads.

**L7 principal defense.** "For short read-mostly lookups: a plain mutex, sharded; or readers that write nothing at
all, such as an immutable snapshot published through `atomic<shared_ptr>` (17 ns, Folder 07) or RCU/hazard pointers
(Folder 09). `shared_mutex` is for long read sections, and I measure it before believing it."
</details>

<details><summary><b>Chain 6 ⚡ "Can readers starve a writer?"</b></summary>

**Initial prompt.** "A writer waits seconds on our `std::shared_mutex` under constant read load. Isn't the standard
lock fair?"

**L5 textbook answer.** "Yes, the standard guarantees writers get the lock eventually."

**Why L5 breaks.** The standard specifies no fairness or preference. libstdc++ builds `std::shared_mutex` on
`pthread_rwlock_t`, and glibc's default rwlock prefers readers: new readers keep entering while a writer waits, so a
constant read stream can starve it (⚠ glibc, not run here). libc++ uses a writer-blocking gate (`__write_entered_`), so
the same code behaves differently on the two standard libraries.

**L7 principal defense.** "If writer latency is a requirement, it's in the lock's contract: a writer-preferring lock
(Folder 11, problem 4), or a phase-fair design. On glibc, `pthread_rwlockattr_setkind_np(...,
PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP)` on a raw `pthread_rwlock_t`. And I'd question whether the writers can
publish a new version instead of mutating in place."
</details>

<details><summary><b>Chain 7 🧊 "Just use recursive_mutex"</b></summary>

**Initial prompt.** "`Account::deposit()` locks the mutex and calls `Account::validate()`, which also locks it, and it
deadlocks. Switch to `std::recursive_mutex`?"

**L5 textbook answer.** "Yes, that's exactly what recursive mutexes are for."

**Why L5 breaks.** It hides the design problem. The inner call runs while the outer one has the object in a
half-updated state, so the invariant that `validate()` assumes doesn't hold. `std::condition_variable` cannot wait on a
`recursive_mutex`, and `condition_variable_any` releases only one level of a recursive lock, so the waiter sleeps while
still owning the mutex: a deadlock with the notifier. It is also bigger: 40 bytes vs 8 in libc++ on Windows (Listing 8.4).

**L7 principal defense.** "Public methods take the lock and call private `*_locked()` helpers that require it, and
the helpers never lock. The lock structure then mirrors the invariant structure. `recursive_mutex` only for wrapping
legacy re-entrant code, temporarily."
</details>

<details><summary><b>Chain 8 ⚡ "Why can't a std::mutex be moved?"</b></summary>

**Initial prompt.** "We want `std::vector<Shard>` where each `Shard` has a `std::mutex`. The compiler says the mutex
isn't movable. Can we write a move constructor that just creates a new mutex?"

**L5 textbook answer.** "Yes, the mutex has no state worth keeping; default-construct it in the move constructor."

**Why L5 corrupts memory on ARM64.** A mutex's identity is its address. The futex word, SRWLOCK or `pthread_mutex_t`
is what waiters are queued on in the kernel, and what condition variables reference. If the vector reallocates while
any thread holds or waits on a shard's mutex, that thread unlocks or waits on freed memory. A hand-written move
constructor makes the reallocation compile, and reallocation can happen concurrently with use if growth isn't itself
synchronized.

**L7 principal defense.** "Mutexes live in stable storage: a fixed-size `std::array` or a `std::deque` of shards
created once, or `std::unique_ptr<Shard>` elements, and sharding is decided at construction. That's also the lock
striping design of Folder 11's sharded LRU."
</details>

---

## 6. Invariants checklist

- [ ] Multi-lock operations use `std::scoped_lock` or one documented global order; no unknown code runs under a lock.
- [ ] `shared_mutex` is used only where read sections are long enough to win (measured), with a stated
      writer-preference requirement.
- [ ] No `recursive_mutex` in new code.
- [ ] Mutexes live in stable storage and are never moved or copied.
- [ ] Custom locks (if any) follow the futex three-state invariants and are benchmarked against `std::mutex` under
      contention.
- [ ] Lock-heavy code is checked by TSan (lock-order inversions) in CI (Folder 12).

## 7. References

- U. Drepper, "Futexes Are Tricky" (2011): <https://www.akkadia.org/drepper/futex.pdf>
- `futex(2)` manual page: <https://man7.org/linux/man-pages/man2/futex.2.html>
- H. Franke, R. Russell, M. Kirkwood, "Fuss, Futexes and Furwocks: Fast Userlevel Locking in Linux", OLS 2002: <https://www.kernel.org/doc/ols/2002/ols2002-pages-479-495.pdf>
- [thread.mutex], [thread.lock.algorithm], [thread.sharedmutex]: <https://eel.is/c++draft/thread.mutex>
- H. Hinnant, `shared_mutex` reference implementation and rationale (N2406): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2007/n2406.html>
- E. G. Coffman, M. Elphick, A. Shoshani, "System Deadlocks", ACM Computing Surveys 3(2), 1971, DOI 10.1145/356586.356588
- `pthread_rwlockattr_setkind_np(3)`: <https://man7.org/linux/man-pages/man3/pthread_rwlockattr_setkind_np.3.html>
