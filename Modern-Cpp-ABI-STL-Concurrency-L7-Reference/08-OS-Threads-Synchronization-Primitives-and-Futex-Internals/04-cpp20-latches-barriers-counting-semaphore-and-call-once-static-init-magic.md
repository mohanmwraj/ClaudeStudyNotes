# 04 · C++20 `latch`, `barrier`, `counting_semaphore`, and `call_once` / magic-static initialization

> **Scope.** C++20 added the coordination primitives that every codebase used to hand-roll: a single-use countdown
> (`latch`), a reusable phase barrier with a completion step (`barrier`), and counting/binary semaphores. They are all
> built on `atomic::wait`, so they inherit its per-platform behaviour (file 03). The older one-time-initialization
> tools, `std::call_once` and function-local statics, look simple and hide two of the sharpest edges in this folder.
> Both were observed here: **on this MinGW GCC, `std::call_once` blocks forever after a throwing first call**, and a
> **recursively initialized static deadlocks on both toolchains**.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 8.10 | `latch_barrier_sem.cpp` | latch countdown; barrier completion runs once per phase after all arrive; `counting_semaphore<2>` admits at most 2; a binary semaphore released by a thread that never acquired it | run, both compilers |
| 8.11 | `call_once_static.cpp` | a magic static under 8 racing first callers is constructed once; a throwing static initializer is retried; **`call_once` after a throwing call: retried on Clang/libc++, blocks forever on GCC/MinGW** | run with a 10 s kill timeout; libstdc++ `<mutex>` excerpt |
| 8.12 | `recursive_static.cpp` | re-entering a static's initialization blocks forever on both toolchains here; libc++abi detects it only where it can get a thread ID | run with a 5 s kill timeout; libc++abi `cxa_guard_impl.h` excerpt |

**Verification line.** As in file 01. The two blocking runs are executed with a kill timeout; the harness records
"no exit after N s". Linux behaviour of the guard implementation is shown from libc++abi source (⚠ not run).

---

## 1. First principles

### 1.1 `latch`, `barrier`, semaphores (Listing 8.10)

```cpp
// latch_barrier_sem.cpp - C++20 std::latch, std::barrier (with a completion step) and std::counting_semaphore
#include <algorithm>
#include <atomic>
#include <barrier>
#include <chrono>
#include <latch>
#include <print>
#include <semaphore>
#include <thread>
#include <vector>

using namespace std::chrono_literals;

int main() {
    // 1. latch: a single-use countdown. Workers count down once; the coordinator waits for zero.
    {
        std::latch done(4);
        std::atomic<int> finished{0};
        std::vector<std::jthread> ws;
        for (int i = 0; i < 4; ++i)
            ws.emplace_back([&] {
                finished.fetch_add(1, std::memory_order_relaxed);
                done.count_down();                 // count_down happens before wait() returns
            });
        done.wait();
        std::println("1. latch: wait() returned after {} of 4 workers counted down", finished.load());
    }

    // 2. barrier: reusable, phase by phase. The completion step runs ONCE per phase, in one of the
    //    participating threads, after all have arrived and before any of them continues.
    {
        constexpr int kThreads = 3, kPhases = 5;
        std::vector<int> partial(kThreads, 0);
        std::vector<int> phase_totals;
        bool every_phase_complete = true;
        int phase = 0;
        std::barrier sync(kThreads, [&]() noexcept {   // the completion function: no locks needed here
            int total = 0;
            for (int p : partial) total += p;
            every_phase_complete &= (total == kThreads * (phase + 1));
            phase_totals.push_back(total);
            ++phase;
        });
        {
            std::vector<std::jthread> ws;
            for (int t = 0; t < kThreads; ++t)
                ws.emplace_back([&, t] {
                    for (int p = 0; p < kPhases; ++p) {
                        partial[static_cast<std::size_t>(t)] = p + 1;   // this phase's work
                        sync.arrive_and_wait();
                    }
                });
        }
        std::println("2. barrier: completion ran {} times (once per phase); each saw all {} results: {}; totals {}",
                     phase_totals.size(), kThreads, every_phase_complete ? "yes" : "NO", phase_totals);
    }

    // 3. counting_semaphore: at most N threads inside a section (a connection pool, a rate gate).
    {
        std::counting_semaphore<2> slots(2);
        std::atomic<int> inside{0}, max_inside{0};
        {
            std::vector<std::jthread> ws;
            for (int i = 0; i < 6; ++i)
                ws.emplace_back([&] {
                    slots.acquire();
                    const int now = inside.fetch_add(1) + 1;
                    int seen = max_inside.load();
                    while (seen < now && !max_inside.compare_exchange_weak(seen, now)) {
                    }
                    std::this_thread::sleep_for(20ms);   // hold the slot long enough to overlap
                    inside.fetch_sub(1);
                    slots.release();
                });
        }
        std::println("3. counting_semaphore<2>: 6 threads, at most {} inside at once", max_inside.load());
    }

    // 4. binary_semaphore as a signal: released by a thread that never acquired it (a mutex can't do that).
    {
        std::binary_semaphore ready(0);
        int payload = 0;
        std::jthread producer([&] {
            payload = 42;
            ready.release();                       // release happens before the matching acquire returns
        });
        ready.acquire();
        std::println("4. binary_semaphore handoff: payload = {}", payload);
    }
}
```

Output (verified, GCC then Clang):

```text
1. latch: wait() returned after 4 of 4 workers counted down
2. barrier: completion ran 5 times (once per phase); each saw all 3 results: yes; totals [3, 6, 9, 12, 15]
3. counting_semaphore<2>: 6 threads, at most 2 inside at once
4. binary_semaphore handoff: payload = 42
1. latch: wait() returned after 4 of 4 workers counted down
2. barrier: completion ran 5 times (once per phase); each saw all 3 results: yes; totals [3, 6, 9, 12, 15]
3. counting_semaphore<2>: 6 threads, at most 2 inside at once
4. binary_semaphore handoff: payload = 42
```

```text
  latch(n):           [ count: n ] --count_down()--> ... --> 0  ==> every wait() returns; can never be reset
  barrier(n, f):      phase k: n x arrive  --> f() runs ONCE, in ONE of the arriving threads, others blocked
                                           --> phase k+1 begins, count reset to n (minus arrive_and_drop()s)
  counting_semaphore: [ count ] acquire(): wait until count > 0, then count--;  release(k): count += k, wake
```

* **Synchronization edges.** `count_down` happens before `wait` returns. Everything before `arrive` in phase k happens
  before the completion function, which happens before every thread's return from `arrive_and_wait` (that's why the
  completion function in part 2 can read `partial` without locks). `release` happens before the `acquire` it satisfies
  (part 4's payload).
* **The completion function must be `noexcept`** and runs while every participant is blocked, so it should be short.
  The standard leaves unspecified which thread runs it.
* **A semaphore has no owner.** Any thread may `release` (part 4), which makes it a signalling tool. It is also why a
  binary semaphore is not a mutex: no owner means no recursion detection, no priority inheritance, and no diagnostic for
  "unlocked by the wrong thread". `release` beyond `max()` is undefined behaviour.
* **Implementation.** All three are an atomic counter plus `atomic::wait` in both libraries (latch: 4 bytes in
  libstdc++, 8 in libc++; semaphores 8 bytes; Listing 8.4). Their wake-up latency is therefore the backend latency
  from file 03: futex on Linux, a proxy pool (libstdc++) or polling with sleeps (libc++) on this Windows machine. That's
  also why Folder 07's litmus harness used a spin barrier: a sleeping barrier releases threads microseconds apart.

### 1.2 `call_once` and magic statics (Listing 8.11)

```cpp
// call_once_static.cpp - std::call_once and magic statics: exactly once, even with racing first callers or exceptions
#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <print>
#include <stdexcept>
#include <thread>
#include <vector>

using namespace std::chrono_literals;

std::atomic<int> g_ctor_runs{0};
struct Service {
    Service() {
        g_ctor_runs.fetch_add(1);
        std::this_thread::sleep_for(30ms);   // slow constructor: the other first callers must wait, not re-run it
    }
};
Service& instance() {
    static Service s;                         // magic static: guard + __cxa_guard_acquire / release
    return s;
}

std::atomic<int> g_flaky_attempts{0};
struct Flaky {
    Flaky() {
        if (g_flaky_attempts.fetch_add(1) == 0) throw std::runtime_error("first attempt fails");
    }
};
Flaky& flaky() {
    static Flaky f;                           // a throwing initializer: __cxa_guard_abort, retried on the next call
    return f;
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);   // unbuffered: if a step blocks forever, the earlier lines survive
    // 1. Eight threads race to be the first caller.
    {
        std::vector<const Service*> seen(8);
        {
            std::vector<std::jthread> ts;
            for (std::size_t i = 0; i < seen.size(); ++i) ts.emplace_back([&, i] { seen[i] = &instance(); });
        }
        bool same = true;
        for (const Service* p : seen) same &= (p == seen[0]);
        std::println("1. magic static, 8 racing first callers: constructor ran {} time(s), all saw one object: {}",
                     g_ctor_runs.load(), same ? "yes" : "NO");
    }
    // 2. A throwing initializer leaves the static uninitialized; the next call tries again.
    {
        try {
            flaky();
        } catch (const std::exception& e) {
            std::println("2. first call threw \"{}\"", e.what());
        }
        flaky();
        std::println("   second call succeeded; constructor attempts = {}", g_flaky_attempts.load());
    }
    // 3. std::call_once: same rules, for code that is not a constructor.
    {
        std::once_flag flag;
        int calls = 0;
        try {
            std::call_once(flag, [&] {
                ++calls;
                throw std::runtime_error("init failed");
            });
        } catch (const std::exception&) {
        }
        std::call_once(flag, [&] { ++calls; });   // the exceptional call did not count: this one runs
        std::call_once(flag, [&] { ++calls; });   // the flag is now set: this one does not
        std::println("3. call_once: throwing call + 2 more calls -> callable executed {} times", calls);
    }
}
```

Output (verified): GCC/libstdc++ (MinGW), then Clang/libc++:

```text
1. magic static, 8 racing first callers: constructor ran 1 time(s), all saw one object: yes
2. first call threw "first attempt fails"
   second call succeeded; constructor attempts = 2
[no exit after 10 s: killed (blocked forever)]
```

```text
1. magic static, 8 racing first callers: constructor ran 1 time(s), all saw one object: yes
2. first call threw "first attempt fails"
   second call succeeded; constructor attempts = 2
3. call_once: throwing call + 2 more calls -> callable executed 2 times
```

What libstdc++ does on gthreads targets (excerpt from the installed `<mutex>`):

```text
// mutex (libstdc++ 16.2), lines 804-807,912-925
  804    private:
  805      // For gthreads targets a pthread_once_t is used with pthread_once, but
  806      // for most targets this doesn't work correctly for exceptional executions.
  807      __gthread_once_t _M_once = __GTHREAD_ONCE_INIT;
    ...
  912      call_once(once_flag& __once, _Callable&& __f, _Args&&... __args)
  913      {
  914        // Closure type that runs the function
  915        auto __callable = [&] {
  916            std::__invoke(std::forward<_Callable>(__f),
  917                          std::forward<_Args>(__args)...);
  918        };
  919  
  920        once_flag::_Prepare_execution __exec(__callable);
  921  
  922        // XXX pthread_once does not reset the flag if an exception is thrown.
  923        if (int __e = __gthread_once(&__once._M_once, &__once_proxy))
  924          __throw_system_error(__e);
  925      }
```

* **Part 1 (both):** 8 threads raced to be the first caller of `instance()`. The 30 ms constructor ran **once**, and
  all 8 saw the same object. The other 7 waited in `__cxa_guard_acquire` (the slow path of Folder 06, Listing 6.6) instead
  of constructing again.
* **Part 2 (both):** a static whose initializer throws is *not* initialized. `__cxa_guard_abort` resets the guard
  (Folder 06) and the next call runs the constructor again: 2 attempts.
* **Part 3:** the standard requires the same for `call_once`: an *exceptional* execution doesn't set the flag, and the
  next call runs its callable ([thread.once.callonce]). **Clang/libc++ does that** (2 executions). **GCC/libstdc++ on
  MinGW printed the first two parts and then blocked forever** in the second `call_once`. The header explains why: on
  gthreads targets `call_once` is `pthread_once`, and *"pthread_once does not reset the flag if an exception is
  thrown"*. The header's own comment says this "doesn't work correctly for exceptional executions" on most targets
  (GCC bug 66146). The once state is left "in progress", so every later caller waits for an execution that will never
  finish.

### 1.3 Recursive static initialization (Listing 8.12)

```cpp
// recursive_static.cpp - a function-local static whose initializer re-enters the same function
#include <cstdio>
#include <cstdlib>
#include <exception>

int& counter();

int compute_initial() { return counter() + 1; }   // re-enters counter() while its static is being initialized

int& counter() {
    static int v = compute_initial();               // [stmt.dcl]: re-entry during initialization is UB
    return v;
}

int main() {
    std::set_terminate([] {
        try {
            throw;   // rethrow the active exception, if any, to report its type
        } catch (const std::exception& e) {
            std::printf("std::terminate after an exception: %s\n", e.what());
        } catch (...) {
            std::puts("std::terminate without a std::exception");
        }
        std::fflush(stdout);
        std::_Exit(3);
    });
    std::printf("counter() = %d\n", counter());
}
```

Output (verified, GCC then Clang; both killed after 5 s):

```text
[no exit after 5 s: killed (blocked forever)]
[no exit after 5 s: killed (blocked forever)]
```

How libc++abi's guard works and when it can detect recursion (excerpt):

```text
// cxa_guard_impl.h (libc++abi 21 sources), lines 158-171,177-180,460-478
  158  
  159  #if defined(__APPLE__) && _LIBCPP_HAS_THREAD_API_PTHREAD
  160  uint32_t PlatformThreadID() {
  161    static_assert(sizeof(mach_port_t) == sizeof(uint32_t), "");
  162    return static_cast<uint32_t>(pthread_mach_thread_np(std::__libcpp_thread_get_current_id()));
  163  }
  164  #elif defined(SYS_gettid) && _LIBCPP_HAS_THREAD_API_PTHREAD
  165  uint32_t PlatformThreadID() {
  166    static_assert(sizeof(pid_t) == sizeof(uint32_t), "");
  167    return static_cast<uint32_t>(syscall(SYS_gettid));
  168  }
  169  #else
  170  constexpr uint32_t (*PlatformThreadID)() = nullptr;
  171  #endif
    ...
  177  static constexpr uint8_t UNSET = 0;
  178  static constexpr uint8_t COMPLETE_BIT = (1 << 0);
  179  static constexpr uint8_t PENDING_BIT = (1 << 1);
  180  static constexpr uint8_t WAITING_BIT = (1 << 2);
    ...
  460    bool acquire() {
  461      while (true) {
  462        uint8_t last_val = UNSET;
  463        if (init_byte.compare_exchange(&last_val, PENDING_BIT, std::_AO_Acq_Rel, std::_AO_Acquire)) {
  464          if (has_thread_id_support) {
  465            thread_id.store(current_thread_id.get(), std::_AO_Relaxed);
  466          }
  467          return false;
  468        }
  469  
  470        if (last_val == COMPLETE_BIT)
  471          return true;
  472  
  473        if (last_val & PENDING_BIT) {
  474  
  475          // Check for recursive initialization
  476          if (has_thread_id_support && thread_id.load(std::_AO_Relaxed) == current_thread_id.get()) {
  477            ABORT_WITH_MESSAGE("__cxa_guard_acquire detected recursive initialization: do you have a function-local static variable whose initialization depends on that function?");
  478          }
```

* **The rule** ([stmt.dcl]/4): if control re-enters the declaration while the variable is being initialized, the
  behaviour is undefined. Here `counter()`'s initializer calls `compute_initial()`, which calls `counter()` again. The
  guard is in the "pending" state, owned by **the same thread**, which now waits for itself.
* **The guard byte** has three bits: `COMPLETE`, `PENDING`, `WAITING`. `acquire` CASes `UNSET → PENDING` (the
  initializing thread), returns at once on `COMPLETE`, or sets `WAITING` and sleeps (on a futex on Linux). Recursion
  detection needs to know *who* set `PENDING`, so the guard stores the initializing thread's ID. **That ID is only
  available on Apple and on Linux (`SYS_gettid`)**; elsewhere `PlatformThreadID` is `nullptr`, `has_thread_id_support`
  is false, and the recursion becomes a silent self-wait. On Linux this program would abort with *"__cxa_guard_acquire
  detected recursive initialization"* (⚠ from the source above, not run here). libstdc++ blocks here as well.
* It is a deadlock with no other thread involved, and it typically appears in initialization-order cycles: a logger
  that reads config, a config that logs.

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| one-time init | thread-safe function-local statics ("magic statics", N2660); `call_once`, `once_flag` | — | — | `constinit` avoids dynamic init entirely (Folder 06) | — | — |
| coordination | — (hand-rolled latches/barriers) | — | — | `latch`, `barrier`, `counting_semaphore`, `binary_semaphore` (P1135) | — | — |
| barrier details | — | — | — | completion function must be `noexcept`; `arrive_and_drop` | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| "start all workers together" | a `bool go` + sleep | `std::latch start(n + 1)`; or a spin flag when nanosecond alignment matters (Folder 07) |
| iterative parallel algorithm (phases) | a new latch per phase, or reusing a latch | `std::barrier` with the per-phase reduction in the completion function |
| bounded resource (connections, in-flight requests) | mutex + counter + cv | `std::counting_semaphore<N>` |
| a mutex replaced by `binary_semaphore` | releases from the wrong thread go unnoticed | `std::mutex` for mutual exclusion; semaphores for signalling |
| one-time init that may fail and be retried | `std::call_once` with a throwing callable (blocks forever on GCC/MinGW, Listing 8.11) | a function-local static (retried correctly on both); or an explicit `mutex` + state enum `{empty, ready}` |
| singleton used during shutdown | `static T t;` destroyed at exit while other code still uses it | `static T& t = *new T;` (deliberately leaked); or explicit lifetime management |
| initialization dependencies between statics | A's initializer calls B, B's calls A (Listing 8.12) | break the cycle; inject dependencies; `constinit` for leaf data |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| a thread blocks forever in `call_once` after an earlier failure | exceptional `call_once` on a `pthread_once`-based implementation | a stack dump in `pthread_once`; avoid throwing out of `call_once` across toolchains |
| a hang at start-up, single thread, inside `__cxa_guard_acquire` | recursive static initialization | stack shows the same static's initializer twice; on Linux libc++abi aborts with a message |
| barrier participants stall at the end of a phase | a slow or blocking completion function | profile the completion; keep it O(1) or O(n) cheap |
| a latch "fires" too early or `count_down` asserts | reusing a latch, or more `count_down`s than the count | use a barrier; count arrivals exactly |
| semaphore count drifts | `release` without a matching `acquire` (no ownership) | wrap in RAII guards; assert the count never exceeds `max()` |
| one-shot coordination wakes slowly on one platform | `atomic::wait` backend (file 03) | measure; spin for short waits |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Reuse the latch for each phase"</b></summary>

**Initial prompt.** "A parallel solver has 100 iterations. We create one `std::latch(nthreads)` and have every thread
`arrive_and_wait()` at the end of each iteration. Fine?"

**L5 textbook answer.** "Yes, the latch synchronizes the threads at each iteration."

**Why L5 corrupts memory on ARM64.** A latch is single-use: after the first iteration its count is 0 and stays 0. From
iteration 2 on, `arrive_and_wait` returns immediately (and decrementing past zero violates the precondition). Threads
race into iteration k + 1 while others still write iteration k's data: data races on the shared arrays, which on ARM64
show up as torn and stale values.

**L7 principal defense.** "`std::barrier`: it resets itself every phase, and the completion function (Listing 8.10,
part 2) is the natural place for the per-iteration reduction or convergence check, executed once while everyone waits.
A latch is for one-shot events: 'all workers started', 'all shards loaded'."
</details>

<details><summary><b>Chain 2 ⚡ "Where does the barrier's completion function run?"</b></summary>

**Initial prompt.** "Our `std::barrier` completion function writes a checkpoint to disk, taking 200 ms, and sometimes
throws on I/O errors. Any concern?"

**L5 textbook answer.** "No. It runs in the background after the phase, so the threads continue."

**Why L5 deadlocks on ARM64.** The completion function runs in one of the participating threads, **while all the
others are blocked** in `arrive_and_wait`, before the next phase starts. A 200 ms completion stalls every worker for
200 ms per phase. It must be `noexcept`: an exception escaping it calls `std::terminate`. If it takes a lock that a
participant (or a thread waiting on a participant) holds, the whole barrier deadlocks.

**L7 principal defense.** "The completion function does O(n) in-memory work only: combine partial results, flip a
buffer index, decide whether to stop. Slow work, like the checkpoint, is handed to a separate thread or queue, and
errors are recorded in state, never thrown."
</details>

<details><summary><b>Chain 3 🧊 "A binary_semaphore is a cheaper mutex"</b></summary>

**Initial prompt.** "We replaced `std::mutex` with `std::binary_semaphore` because semaphores are 'lighter'. Any
downside?"

**L5 textbook answer.** "No, a binary semaphore is a mutex with count 1."

**Why L5 breaks.** A semaphore has no owner (Listing 8.10, part 4: released by a thread that never acquired it). That
is a feature for signalling and a hazard for mutual exclusion. Unlocking from the wrong thread isn't detected. A double
`release` makes the count 2, letting two threads in, and exceeding `max()` is undefined behaviour. There is no priority
inheritance, and sanitizers' and debuggers' lock-ownership tooling can't help. On this Windows toolchain it isn't even
faster: semaphore handoffs measured 0.26–8.8 µs, varying up to 10× between runs (file 03).

**L7 principal defense.** "Mutex for mutual exclusion; semaphores for counting resources and signalling between
threads. The names describe contracts, not performance tiers."
</details>

<details><summary><b>Chain 4 🔥 "call_once retries if the init throws"</b></summary>

**Initial prompt.** "Our connection pool initializes with `std::call_once`. If the database is down, the callable
throws and the next request retries. The standard guarantees that, right?"

**L5 textbook answer.** "Yes: an exceptional execution doesn't set the flag, so the next `call_once` runs the
callable again."

**Why L5 deadlocks on ARM64.** The standard says so, and libc++ does it (Listing 8.11, Clang: 2 executions). This GCC
16 / MinGW build **blocks forever** in the second `call_once`. libstdc++ implements `call_once` with `pthread_once` on
gthreads targets, and its own header warns that pthread_once doesn't reset the flag after an exception (GCC bug 66146).
After the first outage, every request thread hangs in `call_once`: a full service outage caused by a transient
database failure.

**L7 principal defense.** "Don't let exceptions escape `call_once` in code that ships on multiple toolchains. Either a
function-local static, which retried correctly on both (Listing 8.11, part 2), or an explicit state machine: a mutex,
an `enum {empty, ready}`, and a `try` that leaves the state `empty` on failure. Then a toolchain test in CI that runs
the exceptional path."
</details>

<details><summary><b>Chain 5 🔥 "Magic statics are thread-safe, so recursion is fine too"</b></summary>

**Initial prompt.** "`Logger& logger()` has a static whose constructor reads `config()`, and `Config`'s constructor
logs through `logger()`. Start-up sometimes hangs. Why, if statics are thread-safe?"

**L5 textbook answer.** "Thread-safe statics prevent races; this must be a different thread deadlocking."

**Why L5 deadlocks on ARM64.** No second thread is needed. The guard of `logger()`'s static is PENDING, owned by this
thread. Re-entering it makes `__cxa_guard_acquire` wait for the initialization to finish, which is waiting for this
call: a self-deadlock. [stmt.dcl] calls it undefined behaviour. Listing 8.12 hangs on both toolchains here. libc++abi
turns it into an abort with a message only where it can record the initializing thread's ID (Apple, Linux `gettid`).

**L7 principal defense.** "Break the cycle: the logger takes its configuration as a constructor argument, or logs to a
bootstrap sink until it is configured. Dependencies between statics are explicit and acyclic, and leaf data is
`constinit`, so it never needs a guard."
</details>

<details><summary><b>Chain 6 ⚡ "The singleton is destroyed at exit; is that a problem?"</b></summary>

**Initial prompt.** "`Registry& registry() { static Registry r; return r; }`. A crash happens during process exit in a
destructor of another static that unregisters itself. Why?"

**L5 textbook answer.** "Function-local statics are destroyed last, so the registry outlives everything."

**Why L5 corrupts memory on ARM64.** Statics are destroyed in **reverse order of construction completion**. A static
that was constructed *before* the registry was first used is destroyed *after* the registry, so its destructor
unregisters itself from a destroyed `Registry` (use-after-destruction). Detached threads still running at exit (file 01)
hit the same problem.

**L7 principal defense.** "For objects used during shutdown: `static Registry& r = *new Registry;`, deliberately never
destroyed. The guard still makes construction thread-safe. Or give the registry explicit lifetime: created and destroyed
in `main` and passed down. Leak checkers get a suppression; the OS reclaims the memory."
</details>

<details><summary><b>Chain 7 🧊 "What does the first call of a magic static cost, and every call after?"</b></summary>

**Initial prompt.** "Is a function-local static as cheap as a global after initialization?"

**L5 textbook answer.** "Yes, once initialized it's just a variable."

**Why L5 breaks.** Every call checks the guard byte with an acquire load: `movzbl` + test on x86, `ldarb` + `tbz` on
AArch64 (Folder 06, Listing 6.6). The slow path, `__cxa_guard_acquire`, is a CAS on the guard plus a possible futex wait
(excerpt in §1.3). That's small but not zero, and the compiler can't hoist it out of a loop because it can't prove the
initialization finished.

**L7 principal defense.** "`constinit` when the value can be constant (no guard at all), or hoist the reference out of
hot loops. For hot data that needs a dynamic constructor: initialize it once at start-up (in `main`) and pass a
reference."
</details>

<details><summary><b>Chain 8 ⚡ "std::barrier for a tight compute loop"</b></summary>

**Initial prompt.** "Each phase of our stencil code takes 2 µs per thread. We use `std::barrier` between phases.
Scaling past 4 threads is poor. Why?"

**L5 textbook answer.** "Barriers are cheap; the problem must be memory bandwidth."

**Why L5 breaks.** A sleeping barrier wakes its waiters through the OS. On Linux that's a futex wake per sleeper, and
each wake-to-run takes microseconds. On this Windows toolchain the waiters sit in a proxy pool or poll with sleeps (file
03). With 2 µs phases, the barrier's wake-up latency is the same size as the work, and the slowest waker sets the pace.
Folder 07's litmus harness hit the same issue and used a spin barrier.

**L7 principal defense.** "For microsecond phases with dedicated cores: a spin barrier (sense-reversing, Folder 07
Listing 7.5), possibly spin-then-sleep. For longer phases or oversubscribed machines: `std::barrier`. And restructure to
fewer, larger phases where possible. Measure the barrier's share of phase time."
</details>

---

## 6. Invariants checklist

- [ ] Latches are single-use; repeated phases use `std::barrier`.
- [ ] Barrier completion functions are `noexcept`, short, and take no locks held by participants.
- [ ] Semaphores are used for counting and signalling, not as mutexes.
- [ ] No exception escapes `std::call_once` in code built with more than one standard library.
- [ ] Static initializers form an acyclic dependency graph; leaf data is `constinit`.
- [ ] Objects used during shutdown are deliberately leaked or explicitly managed.

## 7. References

- [thread.latch], [thread.barrier], [thread.sema], [thread.once]: <https://eel.is/c++draft/thread>
- [stmt.dcl] (static initialization, recursion is UB): <https://eel.is/c++draft/stmt.dcl>
- P1135R6 (latch, barrier, semaphores, atomic wait): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1135r6.html>
- N2660 (dynamic initialization and destruction with concurrency, "magic statics"): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2008/n2660.htm>
- GCC bug 66146 (`call_once` with exceptions): <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=66146>
- libc++abi `cxa_guard_impl.h`: <https://github.com/llvm/llvm-project/blob/main/libcxxabi/src/cxa_guard_impl.h>
- Itanium C++ ABI §3.3.2 (one-time construction API): <https://itanium-cxx-abi.github.io/cxx-abi/abi.html#once-ctor>
