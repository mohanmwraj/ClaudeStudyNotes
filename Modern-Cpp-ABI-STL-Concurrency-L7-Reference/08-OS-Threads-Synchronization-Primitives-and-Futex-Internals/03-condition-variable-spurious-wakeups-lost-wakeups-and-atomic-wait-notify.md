# 03 · `condition_variable`: spurious wakeups, lost wakeups, notify placement, and `atomic::wait`/`notify`

> **Scope.** A condition variable is a waiting room with no memory. It doesn't record that something happened; only
> the predicate, protected by the mutex, does. Almost every condition-variable bug comes from forgetting that: waiting
> without a predicate, changing the predicate without the mutex, `if` instead of `while`, `notify_one` to the wrong
> waiter. This file forces a lost wakeup deterministically and counts stolen wakeups. It measures notify-under-lock vs
> notify-after-unlock on two Windows implementations, and **corrects a common belief about glibc's "wait morphing"**.
> It then shows how C++20 `atomic::wait` is implemented on each platform, and what that does to handoff latency.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 8.8 | `cv_traps.cpp` | a notification before the wait is lost (no predicate: timeout); with a predicate the wait returns at once; 3 consumers on one queue see 1,190–2,198 wakeups with nothing to do | run, both compilers |
| 8.9 | `handoff_latency.cpp` | round-trip latency of spin, `atomic::wait`, condition variable (both notify placements), and semaphores; the ranking depends on the library | run, 2 threads, both compilers |
| — | library excerpts | libstdc++ has no platform wait outside Linux/macOS/FreeBSD (a proxy pool); libc++'s fallback is "a timed backoff" | regenerated from the installed sources |

**Verification line.** As in file 01. On Windows, libstdc++'s `condition_variable` is winpthreads', and libc++'s is
the Win32 `CONDITION_VARIABLE` on an `SRWLOCK`. Linux (glibc, futex) behaviour is from source and documentation (⚠).

---

## 1. First principles

### 1.1 The contract, and why the mutex protects the predicate

```text
  waiter                                        notifier
  ------                                        --------
  lock(m)
  while (!pred())         <-- reads the state under m
      cv.wait(lk)         <-- ATOMICALLY: unlock(m) + start waiting; on return: lock(m) again
  use the state
  unlock(m)                                     lock(m); change the state; unlock(m)
                                                cv.notify_one()   (may also be done before unlock)

  The lost-wakeup window, when the notifier changes the state WITHOUT m:
     waiter: lock(m); pred() == false ...................... wait(lk)  -> sleeps forever
     notifier:              state = true; notify_one()  ^ nobody was waiting yet: the notification is gone
```

* **`wait` releases the mutex and starts waiting as one atomic step** with respect to `notify`. That is the whole point
  of the mutex: a notifier that changes the state under `m` cannot slip between the waiter's check and its sleep.
  Change the predicate without `m`, even with an atomic `bool`, and the window reopens.
* **`wait` may return without a notification** (a spurious wakeup). The standard and POSIX allow it, and the Windows
  documentation for `SleepConditionVariableSRW` says so too. Causes include implementation details of futex-based
  condition variables and interrupted waits. The defence is always the same: re-check the predicate in a loop, which
  `cv.wait(lk, pred)` does.
* **A notification is not a message.** `notify_one` with no waiter does nothing, and a later `wait` will not see it.

### 1.2 Lost and stolen wakeups (Listing 8.8)

```cpp
// cv_traps.cpp - condition variable traps: the lost wakeup (no predicate) and the stolen wakeup (no re-check)
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

using namespace std::chrono_literals;

// 1. Lost wakeup: the notification happens before anyone waits. A condition variable has no memory;
//    only the predicate (the shared state, under the mutex) remembers that something happened.
void lost_wakeup() {
    std::mutex m;
    std::condition_variable cv;
    bool ready = false;
    {
        std::lock_guard lk(m);
        ready = true;
    }
    cv.notify_one();                                    // nobody is waiting yet: this notification is gone
    std::unique_lock lk(m);
    const std::cv_status st = cv.wait_for(lk, 300ms);  // waits for an EVENT
    std::println("1a. wait without a predicate after an early notify: {}",
                 st == std::cv_status::timeout ? "timed out (the wakeup was lost)" : "woken");
    const bool got = cv.wait_for(lk, 300ms, [&] { return ready; });   // checks the STATE first
    std::println("1b. wait with the predicate: returned at once, ready = {}", got);
}

// 2. Stolen wakeup: a consumer is woken for an item, but a consumer that was not asleep takes it first.
//    The woken thread finds the queue empty; only re-checking the predicate makes that harmless.
void stolen_wakeup() {
    std::mutex m;
    std::condition_variable cv;
    std::deque<int> q;
    bool done = false;
    std::atomic<long> woke_to_nothing{0}, consumed{0};
    constexpr int kItems = 200'000;
    auto consumer = [&] {
        for (;;) {
            std::unique_lock lk(m);
            while (q.empty() && !done) {   // the predicate loop that cv.wait(lk, pred) runs, written out
                cv.wait(lk);
                if (q.empty() && !done) woke_to_nothing.fetch_add(1, std::memory_order_relaxed);
            }
            if (q.empty()) return;         // done, and drained
            q.pop_front();
            consumed.fetch_add(1, std::memory_order_relaxed);
        }
    };
    {
        std::vector<std::jthread> consumers;
        for (int i = 0; i < 3; ++i) consumers.emplace_back(consumer);
        for (int i = 0; i < kItems; ++i) {
            {
                std::lock_guard lk(m);
                q.push_back(i);
            }
            cv.notify_one();
        }
        {
            std::lock_guard lk(m);
            done = true;
        }
        cv.notify_all();
    }
    std::println("2.  {} items, 3 consumers: all consumed: {}; wakeups that found nothing to do: {}", kItems,
                 consumed.load() == kItems ? "yes" : "NO", woke_to_nothing.load());
}

int main() {
    lost_wakeup();
    stolen_wakeup();
}
```

Output (verified, GCC then Clang; the count in line 2 varies between runs):

```text
1a. wait without a predicate after an early notify: timed out (the wakeup was lost)
1b. wait with the predicate: returned at once, ready = true
2.  200000 items, 3 consumers: all consumed: yes; wakeups that found nothing to do: 1190
1a. wait without a predicate after an early notify: woken
1b. wait with the predicate: returned at once, ready = true
2.  200000 items, 3 consumers: all consumed: yes; wakeups that found nothing to do: 2010
```

* **1a, lost**: the state became true and the notification was sent before the wait began. The predicate-less wait
  slept for its whole timeout; without a timeout it would sleep forever.
* **1b, predicate**: the same situation with `wait_for(lk, t, pred)` returns immediately, because it checks the
  state first.
* **2, stolen**: over two runs per compiler, 1,190–2,198 of the wakeups found the queue empty. A consumer was woken
  for an item, but another consumer that wasn't asleep took it first. With `if (q.empty()) cv.wait(lk);
  q.pop_front();`, each of those would be a `pop_front()` on an empty deque: undefined behaviour, usually a crash or
  heap corruption.

### 1.3 Notify placement, and what "wait morphing" really does (Listing 8.9)

```cpp
// handoff_latency.cpp - one-item ping-pong between two threads: spin, atomic::wait, condition variable
//                       (notify under the lock vs after unlocking), and a pair of binary semaphores
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <print>
#include <semaphore>
#include <thread>

using Clock = std::chrono::steady_clock;

template <class Body>
double us_per_round_trip(int rounds, Body body) {
    const auto t0 = Clock::now();
    body(rounds);
    const std::chrono::duration<double, std::micro> d = Clock::now() - t0;
    return d.count() / rounds;
}

double spin(int rounds) {
    std::atomic<int> turn{0};
    return us_per_round_trip(rounds, [&](int n) {
        std::jthread other([&] {
            for (int i = 0; i < n; ++i) {
                while (turn.load(std::memory_order_acquire) != 1) {
                }
                turn.store(0, std::memory_order_release);
            }
        });
        for (int i = 0; i < n; ++i) {
            turn.store(1, std::memory_order_release);
            while (turn.load(std::memory_order_acquire) != 0) {
            }
        }
    });
}

double atomic_wait(int rounds) {
    std::atomic<int> turn{0};
    return us_per_round_trip(rounds, [&](int n) {
        std::jthread other([&] {
            for (int i = 0; i < n; ++i) {
                turn.wait(0, std::memory_order_acquire);   // sleep while turn == 0
                turn.store(0, std::memory_order_release);
                turn.notify_one();
            }
        });
        for (int i = 0; i < n; ++i) {
            turn.store(1, std::memory_order_release);
            turn.notify_one();
            turn.wait(1, std::memory_order_acquire);       // sleep while turn == 1
        }
    });
}

template <bool NotifyUnderLock>
double condvar(int rounds) {
    std::mutex m;
    std::condition_variable cv;
    int turn = 0;
    auto pass = [&](int to) {
        std::unique_lock lk(m);
        turn = to;
        if constexpr (NotifyUnderLock) {
            cv.notify_one();               // the woken thread immediately blocks on m, which we still hold
        } else {
            lk.unlock();
            cv.notify_one();               // m is free when the woken thread runs
        }
    };
    auto await = [&](int value) {
        std::unique_lock lk(m);
        cv.wait(lk, [&] { return turn == value; });
    };
    return us_per_round_trip(rounds, [&](int n) {
        std::jthread other([&] {
            for (int i = 0; i < n; ++i) {
                await(1);
                pass(0);
            }
        });
        for (int i = 0; i < n; ++i) {
            pass(1);
            await(0);
        }
    });
}

double semaphores(int rounds) {
    std::binary_semaphore ping{0}, pong{0};
    return us_per_round_trip(rounds, [&](int n) {
        std::jthread other([&] {
            for (int i = 0; i < n; ++i) {
                ping.acquire();
                pong.release();
            }
        });
        for (int i = 0; i < n; ++i) {
            ping.release();
            pong.acquire();
        }
    });
}

int main() {
    constexpr int n = 20'000, n_sleep = 2'000;   // fewer rounds for the primitives that may sleep
    std::println("round trip (us), two threads passing one token back and forth");
    std::println("spin on an atomic (2 cores busy)          {:8.2f}", spin(n));
    std::println("atomic::wait / notify_one                 {:8.2f}", atomic_wait(n_sleep));
    std::println("condition_variable, notify under the lock {:8.2f}", condvar<true>(n_sleep));
    std::println("condition_variable, notify after unlock   {:8.2f}", condvar<false>(n_sleep));
    std::println("binary_semaphore pair                     {:8.2f}", semaphores(n_sleep));
}
```

Output (verified, GCC/winpthreads then Clang/libc++ on Win32):

```text
round trip (us), two threads passing one token back and forth
spin on an atomic (2 cores busy)              0.76
atomic::wait / notify_one                     4.60
condition_variable, notify under the lock    46.24
condition_variable, notify after unlock      42.49
binary_semaphore pair                         8.81
round trip (us), two threads passing one token back and forth
spin on an atomic (2 cores busy)              0.24
atomic::wait / notify_one                     5.80
condition_variable, notify under the lock     0.91
condition_variable, notify after unlock       0.64
binary_semaphore pair                         0.26
```

Over two runs: the condition-variable round trip was **0.61–0.64 µs (notify after unlock) vs 0.91 µs (notify under
the lock) with libc++/SRW**, and 22.5–46.2 µs for both placements with winpthreads.

* **Notify under the lock** can make the woken thread run, try to take the mutex the notifier still holds, and block
  again. This "hurry up and wait" costs an extra context switch. Notifying after unlocking avoids it, which matches the
  libc++/SRW numbers here.
* **"Wait morphing"** is the optimization where the kernel moves waiters from the condition variable's queue directly
  onto the mutex's queue (`FUTEX_CMP_REQUEUE`) instead of waking them. Old glibc condition variables used requeue for
  broadcasts. **The condition variable rewritten for glibc 2.25 (2017, Torvald Riegel) does not use requeue**: its commit
  message says requeue is not used yet and may not be the right approach. So on current glibc, notifying under the lock
  gets no requeue help (⚠ glibc behaviour from source, not run here).
* **When you must notify under the lock**: when the woken thread may destroy the condition variable as soon as it sees
  the predicate (for example a stack-allocated cv in a one-shot rendezvous). Unlocking first would let the notifier
  call `notify_one()` on a destroyed object. Otherwise, notify after unlock.
* **Platform matters more than placement**: winpthreads' condition variable was 25–75× slower than SRW for the same
  code. Measure on the target platform.

### 1.4 `atomic::wait` / `notify`: one API, three implementations

`a.wait(old)` blocks while `a == old`, comparing value representations, and returns once it observes a different
value. `notify_one`/`notify_all` wake waiters. The waiting rule is the futex rule from file 02, exposed to every
program. How each library implements it:

```text
// bits/atomic_wait.h (libstdc++ 16.2), lines 104-128
  104  #else
  105  // define _GLIBCX_HAVE_PLATFORM_WAIT and implement __platform_wait()
  106  // and __platform_notify() if there is a more efficient primitive supported
  107  // by the platform (e.g. __ulock_wait()/__ulock_wake()) which is better than
  108  // a mutex/condvar based wait.
  109    namespace __detail
  110    {
  111  # if defined __OpenBSD__ || defined __DragonFly__
  112      // These targets provide 32-bit futex-like syscalls.
  113      // We don't currently make use of them, but we want to in future.
  114      using __platform_wait_t = unsigned int;
  115  # elif ATOMIC_LONG_LOCK_FREE == 2
  116      using __platform_wait_t = unsigned long;
  117  # else
  118      using __platform_wait_t = unsigned int;
  119  # endif
  120      inline constexpr size_t __platform_wait_alignment
  121        = sizeof(__platform_wait_t) < __alignof__(__platform_wait_t)
  122            ? __alignof__(__platform_wait_t) : sizeof(__platform_wait_t);
  123    } // namespace __detail
  124  
  125    // This must be false for the general case where we don't know of any
  126    // futex-like syscall.
  127    template<typename>
  128      inline constexpr bool __platform_wait_uses_type = false;
```

```text
// atomic.cpp (libc++ 21 sources), lines 104-117
  104  #else // <- Add other operating systems here
  105  
  106  // Baseline is just a timed backoff
  107  
  108  static void
  109  __libcpp_platform_wait_on_address(__cxx_atomic_contention_t const volatile* __ptr, __cxx_contention_t __val) {
  110    __libcpp_thread_poll_with_backoff(
  111        [=]() -> bool { return !__cxx_nonatomic_compare_equal(__cxx_atomic_load(__ptr, memory_order_relaxed), __val); },
  112        __libcpp_timed_backoff_policy());
  113  }
  114  
  115  static void __libcpp_platform_wake_by_address(__cxx_atomic_contention_t const volatile*, bool) {}
  116  
  117  #endif // __linux__
```

| Platform | libstdc++ 16 | libc++ 21 |
|---|---|---|
| Linux | `futex` directly for 4-byte types; other sizes through a proxy contention word | `futex` |
| macOS | `__ulock_wait`/`__ulock_wake` | `__ulock_wait` (with `_LIBCPP_USE_ULOCK`) |
| FreeBSD | `_umtx_op` | `_umtx_op` |
| **Windows (this machine)** | **no platform wait: a pool of mutex + condition-variable "waiters" keyed by address**, with spinning first | **"a timed backoff": poll the value, yield, then sleep with growing intervals**; `notify` does nothing |

* Windows has a futex-like API (`WaitOnAddress`/`WakeByAddressSingle`, Windows 8+), which MSVC's STL uses. Neither
  library in this toolchain uses it.
* **Measured** (two runs): `atomic::wait` round trips took 1.5–4.6 µs with libstdc++ and 2.95–5.8 µs with libc++.
  The semaphores, which both libraries build on the same waiting machinery, took 0.67–8.8 µs and 0.26–5.04 µs: **up
  to 10× between runs**, depending on whether the waiter was still in its spinning phase or had gone to sleep. A spin
  loop took 0.19–0.76 µs, but it keeps two cores at 100%.
* `wait` can miss **transient** values: if the value changes and changes back before the waiter checks, the waiter may
  keep sleeping (an ABA in waiting). It is for monotonic flags, counters and states that don't return to the old value.

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| condition variables | `condition_variable`, `condition_variable_any`, `notify_all_at_thread_exit` | — | — | `condition_variable_any` stop-token waits (P0660) | — | — |
| clocks for timed waits | `wait_for`/`wait_until` (implementations often used the system clock) | — | — | libstdc++ 10 uses `pthread_cond_clockwait` with the steady clock (GCC PR 41861) | — | — |
| address-based waiting | — | — | — | `atomic::wait`/`notify_one`/`notify_all`, `atomic_flag::wait`, `atomic_ref::wait` (P1135) | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| waiting for a condition | `cv.wait(lk);` then use the state | `cv.wait(lk, [&]{ return pred; });` always |
| setting the condition | `ready.store(true); cv.notify_one();` without the mutex (lost wakeup window) | change the state under the mutex; notify after unlocking |
| multiple consumers | `if (q.empty()) cv.wait(lk); q.pop_front();` | `while` / predicate overload, then pop |
| producers and consumers on one cv | `notify_one()` (may wake a producer when an item arrived) | two cvs: `not_empty`, `not_full`; or `notify_all` |
| shutdown | set `stop = true` without the mutex, `notify_all` | set it under the mutex, include it in every predicate, `notify_all`; or stop tokens (file 01) |
| one-shot flag between threads | mutex + cv + bool | `std::atomic<bool>::wait`/`notify_one`, or `std::latch` (file 04) |
| latency-critical handoff | condition variable on an unmeasured platform | measure (25–75× between implementations here); bounded spin, then `atomic::wait` |
| timed wait | `wait_until(system_clock::now() + 5s)` | `wait_for` / `steady_clock` deadlines, predicate overload |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a thread sleeps forever although the flag is true | lost wakeup: notify before wait, or the flag changed without the mutex | TSan (race on the flag, Folder 12, ⚠); add `wait_for` + logging to find it |
| crash in `pop_front`/`front` on an empty queue | `if` instead of `while` (stolen or spurious wakeup) | Listing 8.8 pattern; ASan |
| producers and consumers both asleep with work pending | `notify_one` woke the wrong kind of waiter on a shared cv | separate cvs, or `notify_all` |
| crash in `notify_one` after a one-shot rendezvous | cv destroyed by the woken thread before the notifier's call | notify under the lock, or keep the cv alive |
| timeouts too long or short after a clock change | waiting against the system clock | `steady_clock`; the library's clockwait support |
| handoff latency 10× worse on one platform | a different `condition_variable` / `atomic::wait` backend | benchmark per platform (Listing 8.9) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "cv.wait(lk) is fine because we always notify"</b></summary>

**Initial prompt.** "The producer sets `ready = true` and calls `notify_one()`; the consumer calls `cv.wait(lk)`. We
always notify, so why use a predicate?"

**L5 textbook answer.** "You don't need one if every state change is notified; the predicate is just for spurious
wakeups, which are rare."

**Why L5 deadlocks on ARM64.** Two independent failures. If the producer runs first, the notification finds no waiter
and is lost. Listing 8.8 1a shows the consumer sleeping its whole timeout, and without one it sleeps forever. And
spurious wakeups are allowed (POSIX, Windows), so the consumer can return with `ready == false`. Both are timing
behaviours, identical on x86 and ARM64; ARM64 only changes how often the timing happens.

**L7 principal defense.** "`cv.wait(lk, [&]{ return ready; })`: the predicate is the memory a condition variable
doesn't have. It handles 'notified before I waited' (1b returns at once) and spurious returns in one line."
</details>

<details><summary><b>Chain 2 🔥 "The flag is atomic, so it doesn't need the mutex"</b></summary>

**Initial prompt.** "`ready` is a `std::atomic<bool>`. The producer does `ready = true; cv.notify_one();` without
locking. The consumer does `cv.wait(lk, [&]{ return ready.load(); })`. Race-free, right?"

**L5 textbook answer.** "Yes. The atomic prevents a data race, and the predicate handles the rest."

**Why L5 deadlocks on ARM64.** No data race, but a lost wakeup. The consumer evaluates the predicate (`false`) under the
mutex. Before it enters the wait, the producer, which never takes the mutex, sets the flag and notifies nobody. The
consumer then sleeps with the flag already true, forever. The mutex works only if the state change happens under it:
that's what makes "check predicate, then sleep" atomic with respect to the change.

**L7 principal defense.** "The producer changes the state while holding the mutex (it can still notify after
unlocking). The atomic is then unnecessary. If the state really must be lock-free, the waiting mechanism should be
`ready.wait(false)` / `ready.notify_one()`, which checks and sleeps atomically in the kernel or library."
</details>

<details><summary><b>Chain 3 ⚡ "if or while?"</b></summary>

**Initial prompt.** "`std::unique_lock lk(m); if (q.empty()) cv.wait(lk); auto x = q.front(); q.pop_front();` Three
consumer threads. Problem?"

**L5 textbook answer.** "No: if we were woken, someone pushed an item."

**Why L5 corrupts memory on ARM64.** Being woken doesn't mean the item is still there. Another consumer that was
running, not waiting, can take it between the notification and the woken thread re-acquiring the mutex (a stolen
wakeup), and spurious wakeups come with no item at all. Listing 8.8 counted 1,190–2,198 wakeups to an empty queue in
200,000 items. Each one would be `front()`/`pop_front()` on an empty deque: undefined behaviour, typically heap
corruption.

**L7 principal defense.** "`while`, or `cv.wait(lk, [&]{ return !q.empty() || done; })`. Then distinguish 'item' from
'shutdown' after the wait. The loop is not a performance detail; it is what makes the code correct."
</details>

<details><summary><b>Chain 4 🧊 "notify_one is enough for a bounded queue"</b></summary>

**Initial prompt.** "Our bounded queue has one cv. Producers wait for space, consumers wait for items. Every push and
pop calls `notify_one()`. Occasionally everything stops. Why?"

**L5 textbook answer.** "`notify_one` is more efficient than `notify_all`, and every state change notifies someone,
so it can't stall."

**Why L5 deadlocks on ARM64.** `notify_one` wakes *some* waiter, possibly one of the wrong kind. A consumer pops and
notifies; the woken thread is another consumer, who finds the queue empty and sleeps again. The producer waiting for
space is never woken. With the right interleaving, all producers wait for space and all consumers wait for items, with
the only notification spent on the wrong side.

**L7 principal defense.** "Two condition variables, `not_full` and `not_empty`, each with one kind of waiter, so
`notify_one` always targets a thread that can make progress. If waiters must share a cv, `notify_all`."
</details>

<details><summary><b>Chain 5 🔥 "Notify under the lock: wait morphing makes it free"</b></summary>

**Initial prompt.** "Should `notify_one()` be called while holding the mutex or after unlocking? I've read that wait
morphing makes notifying under the lock free on Linux."

**L5 textbook answer.** "Under the lock is free: the kernel requeues the woken thread directly onto the mutex, so it
never wakes up just to block."

**Why L5 breaks.** That describes old glibc. The condition variable rewritten for glibc 2.25 (Riegel, 2017) does not
use `FUTEX_CMP_REQUEUE`, so there is no requeue help (⚠ from source). A thread woken under the lock may run and block
straight away on the held mutex. On this machine, libc++/SRW measured 0.61–0.64 µs per round trip notifying after
unlock vs 0.91 µs under the lock (Listing 8.9), while winpthreads was 22–46 µs either way: the implementation mattered
far more than the placement.

**L7 principal defense.** "Change the state under the lock, notify after unlocking, except when the woken thread may
destroy the condition variable as soon as it sees the state. Then notify under the lock, or extend the cv's lifetime.
And measure on the deployment platform; folklore about requeue is a decade out of date."
</details>

<details><summary><b>Chain 6 ⚡ "atomic::wait is a futex, so it's always better than a cv"</b></summary>

**Initial prompt.** "We replaced mutex + cv with `std::atomic<int>::wait`/`notify_one` everywhere. It's a direct futex,
so it should be faster on all our platforms, Linux and Windows."

**L5 textbook answer.** "Yes: no mutex and one futex syscall. It's the fastest blocking primitive."

**Why L5 breaks.** On Linux it is futex-based in both libraries. On this Windows toolchain neither library has a
platform wait. libstdc++ uses a pool of mutex + condition-variable waiters, and libc++ **polls with sleeps, and its
`notify` does nothing** (excerpts in §1.4). Measured round trips: 1.5–5.8 µs, with semaphores built on the same machinery
varying up to 10× between runs. Also, `wait` can miss a value that changes and changes back (ABA), which a cv protocol
with a predicate never misses.

**L7 principal defense.** "`atomic::wait` for one-shot flags, counters and sequence numbers that only move forward.
Then benchmark the backend on every target. MSVC's STL uses `WaitOnAddress`; MinGW toolchains here don't. For latency
paths: a bounded spin, then the platform's best wait."
</details>

<details><summary><b>Chain 7 🧊 "Do spurious wakeups really happen?"</b></summary>

**Initial prompt.** "In ten years I've never seen a spurious wakeup. Can we drop the predicate loops for speed?"

**L5 textbook answer.** "Spurious wakeups are theoretical; modern kernels don't produce them."

**Why L5 breaks.** They are permitted by POSIX, the C++ standard and the Win32 documentation, so code that depends on
their absence is non-portable by definition. More importantly, the loop handles **stolen** wakeups, which are not
theoretical: 1,190–2,198 in Listing 8.8. The predicate loop costs one condition check per wakeup, nothing measurable.

**L7 principal defense.** "The loop stays. It's what makes `notify_one`, `notify_all`, spurious returns and
competing consumers all correct with one rule: wake up, re-check the state, sleep again if needed."
</details>

<details><summary><b>Chain 8 ⚡ "wait_for(5s) waits five seconds"</b></summary>

**Initial prompt.** "A worker does `cv.wait_for(lk, 5s, pred)`. NTP adjusted the clock by an hour and the worker woke
early or hung. How?"

**L5 textbook answer.** "`wait_for` uses a duration, so clock changes don't matter."

**Why L5 breaks.** For years, libstdc++ implemented `wait_for` by converting to a `system_clock` deadline and calling
`pthread_cond_timedwait` (CLOCK_REALTIME). A wall-clock jump moved the deadline. Since GCC 10 it uses
`pthread_cond_clockwait` with the monotonic clock where glibc provides it (2.30+, GCC PR 41861). `wait_until(
system_clock::now() + 5s)` is still affected by design.

**L7 principal defense.** "Deadlines on `steady_clock`, the predicate overload (which returns the predicate's value
at timeout), and a toolchain/glibc combination known to use the monotonic clock. Timeouts are for liveness checks, not
for correctness."
</details>

---

## 6. Invariants checklist

- [ ] Every `wait` has a predicate (or is in a `while` loop re-checking the state).
- [ ] Every predicate state change happens under the same mutex the waiter uses.
- [ ] Each condition variable has one kind of waiter, or uses `notify_all`.
- [ ] Notifications happen after unlocking, unless the cv's lifetime requires otherwise.
- [ ] `atomic::wait` is used only for values that don't return to their old state; its backend has been measured on
      each target.
- [ ] Timed waits use `steady_clock`.

## 7. References

- [thread.condition], [atomics.wait]: <https://eel.is/c++draft/thread.condition>
- glibc commit ed19993b5b, "New condvar implementation that provides stronger ordering guarantees" (2017): <https://sourceware.org/git/?p=glibc.git;a=commit;h=ed19993b5b0d05d62cc883571519a67dae481a14>
- `futex(2)` (`FUTEX_CMP_REQUEUE`): <https://man7.org/linux/man-pages/man2/futex.2.html>
- P1135R6 (atomic wait/notify, latch, barrier, semaphores): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1135r6.html>
- Microsoft, `SleepConditionVariableSRW` (spurious wakeups): <https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-sleepconditionvariablesrw>
- Microsoft, `WaitOnAddress`: <https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitonaddress>
- GCC PR 41861 (`condition_variable::wait_for` and the system clock): <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=41861>
