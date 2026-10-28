# 01 · `std::future`, `std::promise`, `packaged_task`, `std::async` pitfalls, and `shared_future`

> **Scope.** `std::future` was C++11's answer to "run this somewhere and give me the result". It is a one-shot
> channel through a heap-allocated, reference-counted, mutex-and-condition-variable-protected *shared state*. Its
> semantics contain several traps that look like bugs in the program but are the specification: a future that blocks
> in its destructor, a "launched" task that never runs, a polling loop that never ends. This file demonstrates each
> one, measures what the machinery allocates, and shows in the object file what `get()` and `set_value()` really call.
> Files 02–04 then build what replaced it in high-performance code: work-stealing pools, coroutines, and senders.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 10.1 | `future_pitfalls.cpp` | a discarded `std::async` future blocks for the task's whole duration; `launch::deferred` never runs until `get()` and `wait_for` returns `deferred`; broken promises; exception transport; `shared_future` fan-out; 1–2 allocations per promise/future pair and 3–5 per `std::async` | run, both compilers (deterministic); asm of `get()`/`set_value()` (libc++) and the call sequence of libstdc++'s `set_value()` |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++ on winpthreads) and Clang 21.1 (zig, libc++ on Win32),
`-O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`; GCC with
`-fno-assume-sane-operators-new-delete` so that the counting `operator new` sees every allocation (Folder 03).

---

## 1. First principles

### 1.1 The shared state

```text
   std::promise<T> ----+                               +---- std::future<T>  (or many std::shared_future<T>)
                       |   shared state (heap, ref-counted by both ends)
                       +-> +--------------------------------------------+ <-+
                           | mutex + condition variable (or futex word) |
                           | status: not ready / ready / deferred       |
                           | storage: T, or std::exception_ptr          |
                           | (deferred: the callable; async: the thread)|
                           +--------------------------------------------+
   set_value / set_exception: lock, store, mark ready, notify all          get(): lock, wait until ready, move out
```

```cpp
// future_pitfalls.cpp - std::future/promise/async: blocking destructors, deferred launches, broken promises, shared_future
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <future>
#include <new>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wmismatched-new-delete"   // false positive with replaced new/delete (Folder 03)
#endif

// Count every operator new (GCC 16 needs -fno-assume-sane-operators-new-delete for this, Folder 03).
std::atomic<long> g_allocs{0}, g_bytes{0};
void* operator new(std::size_t n) {
    g_allocs.fetch_add(1, std::memory_order_relaxed);
    g_bytes.fetch_add(static_cast<long>(n), std::memory_order_relaxed);
    if (void* p = std::malloc(n)) return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

// Out-of-line copies for the assembly listing: what get() and set_value() compile to.
int get_value(std::future<int>& f) { return f.get(); }
void fulfill(std::promise<int>& p) { p.set_value(1); }

#ifndef ASM_VIEW
int main() {
    // 1. The future returned by std::async(launch::async) blocks in its destructor until the task finishes.
    {
        const auto t0 = Clock::now();
        (void)std::async(std::launch::async, [] { std::this_thread::sleep_for(100ms); });   // temporary future
        const auto waited = Clock::now() - t0;
        std::println("1. discarded std::async(launch::async, 100 ms task): the statement took >= 100 ms: {}",
                     waited >= 100ms ? "yes (the temporary future's destructor joined the task)" : "no");
    }
    // 2. A deferred task runs only inside get()/wait(), on the calling thread; wait_for never reports ready.
    {
        std::atomic<bool> ran{false};
        std::future<int> f = std::async(std::launch::deferred, [&] {
            ran = true;
            return 42;
        });
        std::this_thread::sleep_for(20ms);
        const std::future_status st = f.wait_for(10ms);
        std::println("2. deferred task after 20 ms: ran = {}, wait_for(10ms) -> {}", ran.load(),
                     st == std::future_status::deferred ? "deferred (a 'wait until ready' loop never ends)" : "other");
        const int v = f.get();
        std::println("   get() ran it on the calling thread: value {}, ran = {}", v, ran.load());
    }
    // 3. The default policy is launch::async | launch::deferred: the implementation chooses.
    {
        const std::thread::id runner = std::async([] { return std::this_thread::get_id(); }).get();
        std::println("3. default launch policy ran the task on another thread: {}",
                     runner != std::this_thread::get_id() ? "yes (both libraries here choose async)" : "no (deferred)");
    }
    // 4. A promise destroyed without a value: the future reports broken_promise.
    {
        std::future<int> f;
        {
            std::promise<int> p;
            f = p.get_future();
        }
        try {
            (void)f.get();
        } catch (const std::future_error& e) {
            std::println("4. promise destroyed unfulfilled: get() throws future_error({})",
                         e.code() == std::future_errc::broken_promise ? "broken_promise" : "other");
        }
    }
    // 5. An exception thrown by the task travels through the shared state and is rethrown by get().
    {
        std::future<int> f = std::async(std::launch::async, []() -> int { throw std::runtime_error("disk full"); });
        try {
            (void)f.get();
        } catch (const std::runtime_error& e) {
            std::println("5. exception from the task, rethrown by get(): \"{}\"", e.what());
        }
    }
    // 6. std::future::get is one-shot; shared_future lets several consumers wait for one value.
    {
        std::promise<std::string> p;
        std::shared_future<std::string> sf = p.get_future().share();
        std::atomic<int> got{0};
        {
            std::vector<std::jthread> ts;
            for (int i = 0; i < 3; ++i)
                ts.emplace_back([sf, &got] {
                    if (sf.get() == "config v2") got.fetch_add(1);   // get() returns const&: no copy, no move
                });
            p.set_value("config v2");
        }
        std::promise<int> p2;
        std::future<int> f2 = p2.get_future();
        p2.set_value(1);
        (void)f2.get();
        std::println("6. shared_future: {} of 3 waiters got the value; a std::future after get(): valid() = {}", got.load(),
                     f2.valid());
    }
    // 7. What the machinery allocates.
    {
        long a0 = g_allocs.load(), b0 = g_bytes.load();
        {
            std::promise<int> p;
            std::future<int> f = p.get_future();
            p.set_value(7);
            (void)f.get();
        }
        const long pa = g_allocs.load() - a0, pb = g_bytes.load() - b0;
        a0 = g_allocs.load(), b0 = g_bytes.load();
        {
            std::future<int> f = std::async(std::launch::async, [] { return 1; });
            (void)f.get();
        }
        const long aa = g_allocs.load() - a0, ab = g_bytes.load() - b0;
        std::println("7. promise<int> + future<int>: {} allocation(s), {} bytes; std::async(launch::async): {} allocation(s), {} bytes",
                     pa, pb, aa, ab);
    }
}
#endif
```

Output (verified, GCC/libstdc++ then Clang/libc++):

```text
1. discarded std::async(launch::async, 100 ms task): the statement took >= 100 ms: yes (the temporary future's destructor joined the task)
2. deferred task after 20 ms: ran = false, wait_for(10ms) -> deferred (a 'wait until ready' loop never ends)
   get() ran it on the calling thread: value 42, ran = true
3. default launch policy ran the task on another thread: yes (both libraries here choose async)
4. promise destroyed unfulfilled: get() throws future_error(broken_promise)
5. exception from the task, rethrown by get(): "disk full"
6. shared_future: 3 of 3 waiters got the value; a std::future after get(): valid() = false
7. promise<int> + future<int>: 2 allocation(s), 88 bytes; std::async(launch::async): 3 allocation(s), 152 bytes
```

```text
1. discarded std::async(launch::async, 100 ms task): the statement took >= 100 ms: yes (the temporary future's destructor joined the task)
2. deferred task after 20 ms: ran = false, wait_for(10ms) -> deferred (a 'wait until ready' loop never ends)
   get() ran it on the calling thread: value 42, ran = true
3. default launch policy ran the task on another thread: yes (both libraries here choose async)
4. promise destroyed unfulfilled: get() throws future_error(broken_promise)
5. exception from the task, rethrown by get(): "disk full"
6. shared_future: 3 of 3 waiters got the value; a std::future after get(): valid() = false
7. promise<int> + future<int>: 1 allocation(s), 48 bytes; std::async(launch::async): 5 allocation(s), 160 bytes
```

* **1, the blocking destructor.** The future returned by `std::async` (and only that one) waits for the task in its
  destructor ([futures.async]: the shared state is "made ready" only when the thread finishes, and the last future
  releasing it joins). Discarding it makes the statement synchronous: here the line took at least 100 ms. Code that "fires
  off" work with `std::async` and ignores the result runs serially. Both libraries mark `std::async` `[[nodiscard]]`, so
  discarding it is a warning (an error under `-Werror`, which is why the listing writes `(void)`), but a `(void)` cast
  silences the warning and keeps the blocking.
* **2, deferred.** `launch::deferred` stores the callable in the shared state and runs it *inside* `get()`/`wait()` on
  the calling thread. `wait_for` returns `future_status::deferred` forever, so a loop `while (f.wait_for(10ms) !=
  future_status::ready)` never terminates.
* **3, the default policy** is `launch::async | launch::deferred`, the implementation's choice. Both libraries here
  chose a new thread, but code that relies on that is relying on an implementation detail; pass `launch::async`
  explicitly.
* **4, 5:** a promise destroyed without a value makes `get()` throw `future_error(broken_promise)`, and an exception
  thrown by the task is transported as an `exception_ptr` and rethrown by `get()`.
* **6:** `future::get()` moves the value out and invalidates the future (`valid() == false`). `shared_future::get()`
  returns `const T&`, so any number of waiters can read the same value.
* **7, allocations:** libc++ allocates one 48-byte shared state for a `promise<int>`/`future<int>` pair; libstdc++
  allocates two blocks (88 bytes: the state and the result storage). `std::async` costs 3–5 allocations (state, the
  callable, the thread's start record) plus an OS thread per call.

### 1.2 What `get()` and `set_value()` compile to

libc++ (Clang 21 `-O3`, x86-64 Linux):

```asm
_Z9get_valueRNSt3__16futureIiEE:   # get_value(std::__1::future<int>&)
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	movq	(%rdi), %rbx
	movq	$0, (%rdi)
	movq	%rbx, %rdi
	callq	_ZNSt3__113__assoc_stateIiE4moveEv@PLT # std::__1::__assoc_state<int>::move()
	movq	$-1, %rcx
	lock	xaddq	%rcx, 8(%rbx)
	testq	%rcx, %rcx
	jne	.LBB3_3
	movq	(%rbx), %rcx
	movq	%rbx, %rdi
	movl	%eax, %ebx
	callq	*16(%rcx)
	movl	%ebx, %eax
.LBB3_3:
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	retq
.Ltmp2:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %r14
	movq	$-1, %rax
	lock	xaddq	%rax, 8(%rbx)
	testq	%rax, %rax
	jne	.LBB3_6
	movq	(%rbx), %rax
	movq	%rbx, %rdi
	callq	*16(%rax)
.LBB3_6:
	movq	%r14, %rdi
	callq	_Unwind_Resume@PLT

_Z7fulfillRNSt3__17promiseIiEE:    # fulfill(std::__1::promise<int>&)
	pushq	%rax
	movl	$1, 4(%rsp)
	movq	(%rdi), %rdi
	testq	%rdi, %rdi
	je	.LBB4_2
	leaq	4(%rsp), %rsi
	callq	_ZNSt3__113__assoc_stateIiE9set_valueIiEEvOT_@PLT # void std::__1::__assoc_state<int>::set_value<int>(int&&)
	popq	%rax
	retq
.LBB4_2:
	movl	$3, %edi
	callq	_ZNSt3__120__throw_future_errorB8ne210100ENS_11future_errcE@PLT # std::__1::__throw_future_error[abi:ne210100](std::__1::future_errc)
```

libstdc++ (GCC 16 `-O2`, MinGW): every call and jump in `promise<int>::set_value`:

```text
_Z7fulfillRSt7promiseIiE: control transfers in GCC -O2 output
	call _ZSt19__get_once_callablev    # std::__get_once_callable()
	call _ZSt15__get_once_callv    # std::__get_once_call()
	call pthread_once
	call _ZSt19__get_once_callablev    # std::__get_once_callable()
	call _ZSt15__get_once_callv    # std::__get_once_call()
	call pthread_mutex_lock
	call _ZNSt18condition_variable10notify_allEv    # std::condition_variable::notify_all()
	call pthread_mutex_unlock
	ret
	call *%rax
	ret
	jmp .L84
	jmp .L89
	jmp .L86
```

* **libc++** keeps everything out of line: `get()` is a call to `__assoc_state<int>::move()` (lock, wait, move out)
  plus a reference-count decrement (`lock xaddq`) and a virtual destroy call when it reaches zero. `set_value` is a call
  to `__assoc_state<int>::set_value`.
* **libstdc++** inlines more and shows the whole protocol: `set_value` builds a `std::function` "setter", runs it
  through `std::call_once` (implemented with `pthread_once` and two TLS slots, `__once_callable`/`__once_call`, which
  are emulated TLS on this MinGW build, Folder 08), then locks the state's mutex, calls
  `condition_variable::notify_all`, and unlocks.
* So **every hop through a future is a heap allocation plus a lock plus a condition-variable notify**, and nothing can
  be inlined across it. A chain of `.then()` continuations, had they been standardized (the Concurrency TS proposed
  them), would repeat that per step: the motivation for senders (file 04), which compose without allocating.

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| futures | `future`, `shared_future`, `promise`, `packaged_task`, `async`, `launch` | — | — | — | — | — |
| continuations | — | Concurrency TS v1: `future::then`, `when_all`, `when_any` (never standardized) | — | — | — | replaced by `std::execution` senders (P2300) |
| coroutines | — | — | — | `co_await`, `co_return` (a `future`-like type can be made awaitable) | `std::generator` | — |
| move-only callables for tasks | `std::function` (copyable) | — | — | — | `std::move_only_function` | `std::function_ref`, `std::copyable_function` |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| fire-and-forget background work | `std::async(launch::async, f);` (blocks until `f` finishes) | a thread pool's `post(f)`; or keep the future and `get()` it later |
| "start this, check later" | default `std::async(f)` (may be deferred) | `std::async(std::launch::async, f)` explicitly |
| waiting with a timeout | `while (f.wait_for(10ms) != ready)` (never ends for deferred) | handle `future_status::deferred`, or never use deferred |
| one producer, many readers of a result | copies of a `std::future` (impossible) or multiple `get()`s | `shared_future` (`get()` returns `const T&`) |
| a promise owned by a task that may fail | let it be destroyed unfulfilled | `set_exception(std::current_exception())` in a catch block; broken_promise is a last resort |
| high-rate request/response between threads | a promise/future per request (allocation + mutex + notify per hop) | a pool with continuation callbacks, coroutines, or senders (files 02–04) |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| "parallel" code runs serially | discarded `std::async` futures joining in their destructors | profile: tasks never overlap; `[[nodiscard]]` warnings on `std::async` |
| a wait loop spins forever | `wait_for` on a deferred future | check for `future_status::deferred` |
| `future_error: broken promise` in logs | a promise destroyed on an error path | RAII that sets an exception on unwind |
| `future_error: no state` | `get()` called twice, or on a moved-from/default future | `valid()` checks; `shared_future` |
| throughput collapses with many small async tasks | a thread (and 3–5 allocations) per `std::async` | pools (file 02) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Why is our std::async code serial?"</b></summary>

**Initial prompt.** "We call `std::async(std::launch::async, process, chunk)` in a loop over 8 chunks and ignore the
return value. It takes 8× as long as one chunk. Why?"

**L5 textbook answer.** "Thread creation overhead; use fewer, bigger chunks."

**Why L5 breaks.** Each discarded future is a temporary destroyed at the end of its statement, and a future obtained
from `std::async` blocks in its destructor until the task completes (Listing 10.1, part 1: the statement took at least
100 ms for a 100 ms task). The loop starts chunk 1, waits for it, starts chunk 2, and so on. Nothing ever overlaps.

**L7 principal defense.** "Keep the futures (`std::vector<std::future<R>>`) and `get()` them after starting all
chunks, or better, submit the chunks to a pool and wait on a latch (Folder 08) or one sender (file 04). The blocking
destructor is specified behaviour, which is why both libraries mark `std::async` `[[nodiscard]]` (verified: discarding it
is a `-Wunused-result` diagnostic on GCC 16 and Clang 21)."
</details>

<details><summary><b>Chain 2 ⚡ "wait_for never returns ready"</b></summary>

**Initial prompt.** "`auto f = std::async(compute); while (f.wait_for(10ms) != std::future_status::ready) poll_ui();`
hangs on one platform. Why?"

**L5 textbook answer.** "The task must be stuck; add logging inside `compute`."

**Why L5 breaks.** With the default policy (`async | deferred`), the implementation may choose *deferred*. Then
`compute` has not started and won't start until someone calls `get()` or `wait()`. `wait_for` returns
`future_status::deferred`, never `ready`, so the loop spins forever and `compute` never runs (Listing 10.1, part 2: after
20 ms, `ran = false` and `wait_for` reports `deferred`).

**L7 principal defense.** "Always `std::launch::async` when I mean concurrency, and polling loops handle the
`deferred` status explicitly. In new code, no polling at all: a callback or an awaitable completion."
</details>

<details><summary><b>Chain 3 🧊 "What does a future cost?"</b></summary>

**Initial prompt.** "We pass results between pipeline stages with `std::promise`/`std::future` pairs, about 200k per
second. What's the cost?"

**L5 textbook answer.** "Nothing significant: a future is a small handle."

**Why L5 breaks.** The handle is small; the shared state isn't free. Listing 10.1: 1 allocation (48 bytes) with libc++,
2 (88 bytes) with libstdc++, per pair. Then `set_value` locks a mutex and notifies a condition variable, and in libstdc++
it also goes through `std::call_once` and a `std::function` (§1.2's call list). `get()` locks and possibly sleeps. At
200k per second that's 200k–400k allocations and as many lock/notify pairs per second, before any work.

**L7 principal defense.** "For high-rate handoff: a bounded SPSC/MPMC ring (Folder 09) or a pool with continuation
callbacks, and for composition, senders (file 04: 0 allocations per hop). Futures for coarse-grained 'start a job, get
its result later' at human time scales."
</details>

<details><summary><b>Chain 4 ⚡ "Two consumers need the result"</b></summary>

**Initial prompt.** "Two threads both need the configuration loaded by a third. We give each a copy of the
`std::future`. Compile error. How should it work?"

**L5 textbook answer.** "Call `get()` once and pass the value around."

**Why L5 breaks.** That works if one place can call `get()` before the others need it, which defeats asynchronous
waiting. `std::future` is move-only and `get()` is one-shot: it moves the value out, and afterwards `valid()` is false
(Listing 10.1, part 6). A second `get()` throws `future_error(no_state)` in libstdc++ and is a precondition violation by
the standard.

**L7 principal defense.** "`future.share()` gives a copyable `shared_future`, whose `get()` returns `const T&` to the
one stored value. Any number of threads wait on it (part 6: 3 of 3 waiters). For large shared values, make `T` a
`shared_ptr<const Config>` so readers can keep it beyond the future."
</details>

<details><summary><b>Chain 5 🔥 "The worker crashed, and the caller hangs"</b></summary>

**Initial prompt.** "Our worker takes a `std::promise<Result>` and sets it at the end. When parsing throws, the caller
hangs in `get()`. Why?"

**L5 textbook answer.** "The exception killed the worker thread, so `get()` waits forever."

**Why L5 breaks.** If the promise is destroyed unfulfilled, `get()` doesn't hang: it throws
`future_error(broken_promise)` (Listing 10.1, part 4). A *hang* means the promise is still alive and unfulfilled: it was
moved into a long-lived object, leaked, or the worker caught and swallowed the exception. And an uncaught exception in a
`std::thread` calls `std::terminate` rather than quietly ending the thread.

**L7 principal defense.** "Every path that owns a promise ends in `set_value` or `set_exception`: a `try`/`catch(...)`
with `p.set_exception(std::current_exception())`, or `std::packaged_task`, which does exactly that for me (part 5's
exception transport). A timeout on the waiting side turns a lost promise into a diagnosable error."
</details>

<details><summary><b>Chain 6 🧊 "Why was future::then never standardized?"</b></summary>

**Initial prompt.** "The Concurrency TS had `future::then`. Why didn't it make it into the standard, and what replaced
it?"

**L5 textbook answer.** "Nobody needed it; people use callbacks."

**Why L5 breaks.** Continuations on the future model inherit its costs at every step: a shared state per stage
(allocation), synchronization between "set" and "attach continuation" (which may race, so a lock or atomic RMW per
step), and no control over *where* the continuation runs: the setting thread, the attaching thread, or a hidden
executor. Cancellation and structured lifetimes don't exist in the model.

**L7 principal defense.** "C++26 `std::execution` (P2300): senders describe the work, `connect` builds one
operation-state object for the whole chain, and schedulers say where each step runs. File 04's pipeline allocates
nothing and compiles to a constant. Futures remain fine as a coarse handoff, and coroutines can await them."
</details>

<details><summary><b>Chain 7 ⚡ "packaged_task or promise?"</b></summary>

**Initial prompt.** "When do you use `std::packaged_task` instead of a `std::promise`?"

**L5 textbook answer.** "They're the same thing."

**Why L5 breaks.** A `packaged_task<R(Args...)>` *is* a callable bundled with a promise: invoking it calls the
function and stores the result, or catches any exception and stores that, in the shared state. With a raw promise every
code path must remember to fulfil it. A packaged_task destroyed before being invoked still breaks its promise. It's
move-only, so it can't be stored in a `std::function` (which requires copyable targets); that's why pools historically
wrapped it in a `shared_ptr`, adding another allocation.

**L7 principal defense.** "`packaged_task` when submitting a callable whose result someone awaits, as file 04's
`thread_pool::submit` does. A promise when the result is produced by code that isn't a single callable (a callback API,
a state machine). And `std::move_only_function` (C++23) to store packaged tasks without the `shared_ptr` wrapper."
</details>

<details><summary><b>Chain 8 🔥 "Calling get() on a future from inside the pool"</b></summary>

**Initial prompt.** "A task running on our 4-thread pool submits a subtask to the same pool and calls `get()` on its
future. Under load the service freezes. Why?"

**L5 textbook answer.** "Probably a deadlock in our queue; add more threads."

**Why L5 deadlocks on ARM64.** When all 4 workers run tasks that each block in `get()` on subtasks queued behind them,
no worker is free to run the subtasks: a thread-starvation deadlock. Adding threads moves the threshold; it doesn't
remove it. Futures make it easy because `get()` blocks the *thread*, not just the task.

**L7 principal defense.** "Never block a pool thread on work submitted to the same pool. Use fork-join with work
stealing, where the waiting worker runs other tasks (file 02's pool does that by design), or continuations, coroutines
(`co_await` suspends the task, not the thread, file 03), or senders (`let_value`)."
</details>

---

## 6. Invariants checklist

- [ ] No discarded `std::async` futures; `launch::async` stated explicitly.
- [ ] No polling loops that ignore `future_status::deferred`.
- [ ] Every promise is fulfilled on every path (value or exception); prefer `packaged_task`.
- [ ] One consumer: `future`; several: `shared_future`.
- [ ] No pool thread blocks on a future of work in the same pool.
- [ ] High-rate handoffs don't use a promise/future per item.

## 7. References

- [futures] (futures, promises, `async`): <https://eel.is/c++draft/futures>
- N3679, H.-J. Boehm, "Async() future destructors must wait" (2013): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3679.html>
- Concurrency TS (N4399: `future::then`, `when_all`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2015/n4399.html>
- P2300R10 (`std::execution`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2300r10.html>
- E. Niebler, "Structured Concurrency" (2020): <https://ericniebler.com/2020/11/08/structured-concurrency/>
