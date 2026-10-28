# 01 · `std::thread` vs `std::jthread`, cooperative cancellation with `stop_token`/`stop_callback`, and `thread_local`

> **Scope.** A thread object is a resource with a lifecycle. Getting that lifecycle wrong terminates the process
> (`std::thread`), leaves dangling references (`detach`), or hangs a shutdown (a worker that never notices it should
> stop). C++20's `std::jthread` and stop tokens fix the common cases, if you know where callbacks run and what a
> blocked thread can and cannot notice. Thread-local storage looks free and isn't: this file shows the four TLS access
> models in the object file, the dynamic-initialization wrappers, and a 13× cost difference between the two compilers
> on this machine.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 8.1 | `jthread_stop.cpp` | `~jthread` requests stop and joins; where `stop_callback` runs (requesting thread, or immediately); `condition_variable_any::wait` with a token returns on stop; one `stop_source` cancels a group | run, both compilers |
| 8.2 | `thread_terminate.cpp` | destroying a joinable `std::thread` calls `std::terminate` | run (exit code 3), both compilers |
| 8.3 | `tls_cost.cpp` | general-dynamic / initial-exec / local-exec TLS on x86-64 and AArch64; `_ZTH` init calls for dynamic and `extern` TLS; MinGW GCC uses emulated TLS: 13–14 ns per access vs 1 ns with Clang | asm: Clang x86-64/AArch64 (3 TLS models), MinGW GCC; run, both compilers |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++ on winpthreads) and Clang 21.1 (zig, libc++ on the Win32 API),
`-O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`, on an Intel Core i5-11260H running
Windows 11. Linux behaviour is shown through Linux-target assembly and library source, and marked ⚠ where a claim was
not executed here.

---

## 1. First principles

### 1.1 The thread object's state machine (Listings 8.1, 8.2)

```text
   std::thread t;            std::thread t(f);              t.join()  -> waits, then not joinable
   (not a thread) ---------> JOINABLE ---------------------> t.detach() -> not joinable, thread runs on
                                 |
                                 |  ~thread() while JOINABLE  -> std::terminate()          (Listing 8.2)
                                 |
   std::jthread j(f);  ~jthread() while joinable -> request_stop(); join();                (Listing 8.1, 1)
```

```cpp
// thread_terminate.cpp - destroying a joinable std::thread calls std::terminate (std::jthread would join)
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <thread>

int main() {
    std::set_terminate([] {
        std::puts("std::terminate: a joinable std::thread was destroyed without join() or detach()");
        std::fflush(stdout);
        std::_Exit(3);
    });
    {
        std::thread t([] {});
    }   // ~thread() on a joinable thread -> std::terminate()
    std::puts("never reached");
}
```

Output (verified, GCC then Clang):

```text
std::terminate: a joinable std::thread was destroyed without join() or detach()
[exit code] 0x3
std::terminate: a joinable std::thread was destroyed without join() or detach()
[exit code] 0x3
```

* **Why `std::thread` terminates** (N2802, 2008): implicit `join` in a destructor can block forever during exception
  unwinding, and implicit `detach` leaves a running thread holding references into a destroyed scope. Neither is safe
  as a default, so the committee made the mistake loud.
* **`std::jthread` (C++20, P0660)** chose a third option: the destructor calls `request_stop()` and then `join()`. It
  is safe *if the thread function cooperates* by checking its `stop_token` (Listing 8.1, part 1). A thread that ignores
  the token turns `~jthread` into an unbounded wait.
* A `jthread` is 16 bytes in both libraries: the native handle plus a pointer to the shared stop state (file 02,
  Listing 8.4).

### 1.2 Stop tokens, stop callbacks, and interruptible waits (Listing 8.1)

```cpp
// jthread_stop.cpp - std::jthread joins in its destructor; cooperative cancellation with stop_token and stop_callback
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <print>
#include <stop_token>
#include <thread>
#include <vector>

using namespace std::chrono_literals;

int main() {
    // 1. ~jthread calls request_stop() and then join(): the worker sees the request and returns.
    std::atomic<bool> saw_stop{false};
    {
        std::jthread worker([&](std::stop_token st) {
            while (!st.stop_requested()) std::this_thread::sleep_for(1ms);
            saw_stop = true;
        });
        std::this_thread::sleep_for(10ms);
    }
    std::println("1.  ~jthread requested stop and joined; worker saw the request: {}", saw_stop.load() ? "yes" : "no");

    // 2. stop_callback runs in the thread that requests stop if it was registered before the request,
    //    and immediately in the registering thread if stop was already requested.
    {
        std::stop_source src;
        std::thread::id ran_in, requester;
        std::stop_callback early(src.get_token(), [&] { ran_in = std::this_thread::get_id(); });
        std::jthread t([&] {
            requester = std::this_thread::get_id();
            src.request_stop();            // runs `early` synchronously, here, before returning
        });
        t.join();
        std::println("2a. callback registered before the request ran in the requesting thread: {}",
                     ran_in == requester ? "yes" : "no");
        std::thread::id ran_in_late;
        std::stop_callback late(src.get_token(), [&] { ran_in_late = std::this_thread::get_id(); });
        std::println("2b. callback registered after the request ran at once, in the registering thread: {}",
                     ran_in_late == std::this_thread::get_id() ? "yes" : "no");
    }

    // 3. condition_variable_any::wait(lock, token, pred) also returns when stop is requested: nobody has
    //    to notify the condition variable to cancel a blocked consumer.
    {
        std::mutex m;
        std::condition_variable_any cv;
        std::deque<int> q;
        bool cancelled = false;
        std::jthread consumer([&](std::stop_token st) {
            std::unique_lock lk(m);
            const bool got_item = cv.wait(lk, st, [&] { return !q.empty(); });
            cancelled = !got_item && st.stop_requested();
        });
        std::this_thread::sleep_for(20ms);
        consumer.request_stop();
        consumer.join();
        std::println("3.  blocked wait returned because of request_stop, queue still empty: {}", cancelled ? "yes" : "no");
    }

    // 4. One stop_source cancels a whole group of workers that share its token.
    {
        std::stop_source group;
        std::atomic<int> stopped{0};
        {
            std::vector<std::jthread> workers;
            for (int i = 0; i < 4; ++i)
                workers.emplace_back([&stopped, tok = group.get_token()] {
                    while (!tok.stop_requested()) std::this_thread::sleep_for(1ms);
                    stopped.fetch_add(1);
                });
            std::this_thread::sleep_for(10ms);
            group.request_stop();
        }   // joins all four
        std::println("4.  one stop_source stopped {} of 4 workers", stopped.load());
    }
}
```

Output (verified, GCC then Clang):

```text
1.  ~jthread requested stop and joined; worker saw the request: yes
2a. callback registered before the request ran in the requesting thread: yes
2b. callback registered after the request ran at once, in the registering thread: yes
3.  blocked wait returned because of request_stop, queue still empty: yes
4.  one stop_source stopped 4 of 4 workers
1.  ~jthread requested stop and joined; worker saw the request: yes
2a. callback registered before the request ran in the requesting thread: yes
2b. callback registered after the request ran at once, in the registering thread: yes
3.  blocked wait returned because of request_stop, queue still empty: yes
4.  one stop_source stopped 4 of 4 workers
```

```text
  stop_source --+                      shared stop state (heap, reference-counted)
  stop_token ---+---->  +---------------------------------------------------------+
  stop_token ---+       | atomic: stop-requested bit + lock bit + source count    |
                        | intrusive list of registered stop_callbacks (locked)    |
                        +---------------------------------------------------------+
  request_stop():  set the bit once (atomic RMW), then run every registered callback, SYNCHRONOUSLY,
                   in the calling thread, one at a time.        -> part 2a
  stop_callback(token, f):  if stop was already requested, run f now, in THIS thread.  -> part 2b
  ~stop_callback():  unregister; if f is running in another thread right now, WAIT for it to finish.
```

* **Callbacks are not asynchronous.** `request_stop()` returns only after the callbacks have run (2a). Calling it
  while holding a mutex that a callback also locks is a self-deadlock.
* **A destroyed callback waits for a running one.** If thread A destroys a `stop_callback` while thread B's
  `request_stop()` is executing it, A blocks until B's call returns. If A holds a lock the callback needs, that's a
  deadlock (Chain 4).
* **A token cannot wake a blocked thread by itself.** Part 3 works because `condition_variable_any::wait(lock, token,
  pred)` registers a stop callback that notifies the condition variable under its internal mutex, and the overload
  returns `pred()`. `std::condition_variable` (the non-`_any` one) has no such overload. A thread blocked in
  `cv.wait(lk, pred)`, `sleep_for`, `recv` or a semaphore keeps sleeping when stop is requested, unless something else
  wakes it.
* **One source, many tokens** (part 4): a whole subsystem shuts down by sharing one `stop_source`'s token.

### 1.3 `thread_local` in the object file (Listing 8.3)

```cpp
// tls_cost.cpp - thread_local in the object file (TLS models, init wrappers, emutls) and what an access costs
#include <chrono>
#include <cstdint>
#include <print>
#include <string>
#include <thread>
#include <vector>

thread_local int tls_counter = 0;                      // constant-initialized
thread_local std::string tls_name = "worker";          // dynamic init: constructed on first use in each thread
extern thread_local int tls_elsewhere;                 // defined in another TU: may need dynamic init
extern constinit thread_local int tls_constinit_elsewhere;   // C++20: promised constant-initialized

int bump_tls() { return ++tls_counter; }
std::size_t name_len() { return tls_name.size(); }
int read_elsewhere() { return tls_elsewhere; }
int read_constinit_elsewhere() { return tls_constinit_elsewhere; }

#ifndef ASM_VIEW
thread_local int tls_elsewhere = 1;
constinit thread_local int tls_constinit_elsewhere = 2;

int global_counter = 0;
int bump_global() { return ++global_counter; }

template <class F>
double ns_per_call(F* f, int n) {
    F* volatile fn = f;                            // called through a volatile pointer: no inlining, no merging
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < n; ++i) fn();
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    return d.count() / n;
}

int main() {
    constexpr int n = 20'000'000;
    const double g = ns_per_call<int()>(&bump_global, n);
    const double t = ns_per_call<int()>(&bump_tls, n);
    const double s = ns_per_call<std::size_t()>(&name_len, n);
    std::println("call + increment a global          {:5.2f} ns", g);
    std::println("call + increment a thread_local    {:5.2f} ns", t);
    std::println("call + read a dynamic thread_local {:5.2f} ns", s);

    constexpr int kThreads = 2000;
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < kThreads; ++i) std::jthread([] {}).join();
    const std::chrono::duration<double, std::micro> d = std::chrono::steady_clock::now() - t0;
    std::println("create + join one std::jthread     {:5.1f} us", d.count() / kThreads);
    std::println("(checksum {})", (global_counter + tls_counter) & 0xFF);
}
#endif
```

x86-64. Clang 21 builds Linux targets as position-independent code here, so the default model is general-dynamic;
the other two come from `-ftls-model`. The last row is MinGW GCC 16 (Windows):

```text
bump_tls:
  general-dynamic (default PIC)  pushq %rax ; data16 ; leaq tls_counter@TLSGD(%rip), %rdi ; data16 ; data16 ; rex64 ; callq __tls_get_addr@PLT ; movl (%rax), %ecx ; addl $1, %ecx ; movl %ecx, (%rax) ; popq %rcx
  initial-exec                   movq tls_counter@GOTTPOFF(%rip), %rcx ; movl %fs:(%rcx), %eax ; addl $1, %eax ; movl %eax, %fs:(%rcx)
  local-exec                     movl %fs:tls_counter@TPOFF, %eax ; addl $1, %eax ; movl %eax, %fs:tls_counter@TPOFF
  MinGW GCC (emutls)             subq $40, %rsp ; leaq __emutls_v.tls_counter(%rip), %rcx ; call __emutls_get_address ; movq %rax, %rdx ; movl (%rax), %eax ; addl $1, %eax ; movl %eax, (%rdx) ; addq $40, %rsp

read_constinit_elsewhere:
  general-dynamic (default PIC)  pushq %rax ; data16 ; leaq tls_constinit_elsewhere@TLSGD(%rip), %rdi ; data16 ; data16 ; rex64 ; callq __tls_get_addr@PLT ; movl (%rax), %eax ; popq %rcx
  initial-exec                   movq tls_constinit_elsewhere@GOTTPOFF(%rip), %rax ; movl %fs:(%rax), %eax
  local-exec                     movl %fs:tls_constinit_elsewhere@TPOFF, %eax
  MinGW GCC (emutls)             subq $40, %rsp ; movq .refptr.__emutls_v.tls_constinit_elsewhere(%rip), %rcx ; call __emutls_get_address ; movl (%rax), %eax ; addq $40, %rsp
```

AArch64:

```text
bump_tls:
  general-dynamic (TLS descriptor)  str x30, [sp, #-16]! ; ldr x1, [x0, :tlsdesc_lo12:tls_counter] ; add x0, x0, :tlsdesc_lo12:tls_counter ; blr x1 ; mrs x9, TPIDR_EL0 ; mov x8, x0 ; ldr w10, [x9, x0] ; add w0, w10, #1 ; str w0, [x9, x8] ; ldr x30, [sp], #16
  initial-exec                      ldr x8, [x8, :gottprel_lo12:tls_counter] ; mrs x9, TPIDR_EL0 ; ldr w10, [x9, x8] ; add w0, w10, #1 ; str w0, [x9, x8]
  local-exec                        mrs x8, TPIDR_EL0 ; add x8, x8, :tprel_hi12:tls_counter ; add x8, x8, :tprel_lo12_nc:tls_counter ; ldr w9, [x8] ; add w0, w9, #1 ; str w0, [x8]

read_constinit_elsewhere:
  general-dynamic (TLS descriptor)  str x30, [sp, #-16]! ; ldr x1, [x0, :tlsdesc_lo12:tls_constinit_elsewhere] ; add x0, x0, :tlsdesc_lo12:tls_constinit_elsewhere ; blr x1 ; mrs x8, TPIDR_EL0 ; ldr w0, [x8, x0] ; ldr x30, [sp], #16
  initial-exec                      ldr x8, [x8, :gottprel_lo12:tls_constinit_elsewhere] ; mrs x9, TPIDR_EL0 ; ldr w0, [x9, x8]
  local-exec                        mrs x8, TPIDR_EL0 ; add x8, x8, :tprel_hi12:tls_constinit_elsewhere ; add x8, x8, :tprel_lo12_nc:tls_constinit_elsewhere ; ldr w0, [x8]
```

The dynamic-initialization machinery, Clang x86-64 (general-dynamic):

```asm
_Z8bump_tlsv:                      # bump_tls()
	pushq	%rax
	data16
	leaq	tls_counter@TLSGD(%rip), %rdi
	data16
	data16
	rex64
	callq	__tls_get_addr@PLT
	movl	(%rax), %ecx
	addl	$1, %ecx
	movl	%ecx, (%rax)
	movl	%ecx, %eax
	popq	%rcx
	retq

_Z8name_lenv:                      # name_len()
	pushq	%rax
	callq	_ZTH8tls_name@PLT                    # TLS init function for tls_name
	data16
	leaq	tls_name@TLSGD(%rip), %rdi
	data16
	data16
	rex64
	callq	__tls_get_addr@PLT
	movq	%rax, %rcx
	movzbl	(%rax), %eax
	testb	$1, %al
	je	.LBB1_1
	movq	8(%rcx), %rax
	popq	%rcx
	retq
.LBB1_1:
	shrl	%eax
	popq	%rcx
	retq

_Z14read_elsewherev:               # read_elsewhere()
	pushq	%rax
	cmpq	$0, _ZTH13tls_elsewhere@GOTPCREL(%rip) # TLS init function for tls_elsewhere
	je	.LBB3_2
	callq	_ZTH13tls_elsewhere@PLT              # TLS init function for tls_elsewhere
.LBB3_2:
	data16
	leaq	tls_elsewhere@TLSGD(%rip), %rdi
	data16
	data16
	rex64
	callq	__tls_get_addr@PLT
	movl	(%rax), %eax
	popq	%rcx
	retq

_Z24read_constinit_elsewherev:     # read_constinit_elsewhere()
	pushq	%rax
	data16
	leaq	tls_constinit_elsewhere@TLSGD(%rip), %rdi
	data16
	data16
	rex64
	callq	__tls_get_addr@PLT
	movl	(%rax), %eax
	popq	%rcx
	retq
```

Cost on this machine (verified, GCC then Clang):

```text
call + increment a global           1.69 ns
call + increment a thread_local    13.58 ns
call + read a dynamic thread_local 25.82 ns
create + join one std::jthread      82.6 us
(checksum 0)
call + increment a global           1.73 ns
call + increment a thread_local     1.00 ns
call + read a dynamic thread_local  1.68 ns
create + join one std::jthread      76.0 us
(checksum 0)
```

* **Four ways to reach a thread-local** (Drepper, *ELF Handling For Thread-Local Storage*):
  * **local-exec** (main executable, variable defined there): one `%fs:`/`TPIDR_EL0`-relative access, the offset fixed
    at link time;
  * **initial-exec** (variable in a library loaded at startup): load the offset from the GOT, then `%fs:` access;
  * **general-dynamic** (code in a `dlopen`-able shared library): a call to `__tls_get_addr`, or on AArch64 a TLS
    descriptor call (`blr x1`) that resolves to a fast path after first use;
  * **emulated TLS** (this MinGW GCC): `__emutls_get_address` on every access, a function call plus a lookup.
* **Measured** over two runs: a call that increments a `thread_local` took 0.96–1.00 ns with Clang (native Windows
  TLS) and **12.95–13.58 ns with MinGW GCC (emutls)**. Reading a dynamically-initialized `thread_local` took 1.60–1.68
  ns vs 25.8–26.5 ns. The global-variable baseline was 1.69–1.73 ns on both. Code ported from Linux GCC to MinGW GCC
  can lose an order of magnitude on TLS-heavy paths (allocators, loggers, per-thread caches).
* **Dynamic initialization.** `tls_name` (a `std::string`) needs a constructor per thread. Every use calls the TLS
  init function `_ZTH8tls_name`, which runs the constructor the first time in each thread (GCC uses a TLS guard
  variable `__tls_guard`). For an `extern thread_local` defined elsewhere, the compiler can't know whether
  initialization is dynamic. It tests a **weak** `_ZTH13tls_elsewhere` symbol for null and calls it if present.
  **`constinit` removes the test**: `read_constinit_elsewhere` is a plain TLS access.
* **Thread creation is not cheap:** create + join of an empty `std::jthread` cost 75.5–83.3 µs here (Windows, both
  libraries). That's why work goes to pools (Folder 10). On Linux the figure is typically lower (⚠ not measured here).

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| thread objects | `std::thread` (terminate on joinable destruction, N2802) | — | — | `std::jthread`: stop + join in the destructor (P0660) | — | — |
| cancellation | none (flags by hand) | — | — | `stop_source`, `stop_token`, `stop_callback`; `condition_variable_any` stop-token waits (P0660) | — | `inplace_stop_source`/`inplace_stop_token` and the `stoppable_token` concept for `std::execution` (P2300) |
| TLS | `thread_local`, dynamic init per thread | — | — | `constinit thread_local` removes init checks (P1143) | — | — |
| identification | `get_id`, `hardware_concurrency` | — | — | — | `std::formatter<thread::id>` (P2693) | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| worker owned by an object | `std::thread` member, joined in `stop()` (forgotten on an exception path: terminate) | `std::jthread` member declared **last**, so it stops and joins before the members it uses are destroyed |
| fire-and-forget background work | `std::thread(f).detach()` capturing locals by reference | hand it to a pool; never detach a thread that references a scope |
| cancelling a blocked consumer | `request_stop()` + hope (it sleeps in `cv.wait`) | `condition_variable_any::wait(lk, token, pred)`, or a `stop_callback` that notifies under the mutex |
| stop callback doing real work | callback takes locks, logs, joins | callback only sets state and notifies; the worker does the cleanup |
| hot per-thread cache in a library | `thread_local` object with a constructor, accessed per call | `constinit thread_local` POD (or a pointer initialized lazily), or a cached pointer in the hot loop; consider `-ftls-model=initial-exec` |
| TLS-heavy code on MinGW | assume Linux-like TLS cost | measure: this MinGW GCC build uses emutls (13× slower); Clang or MSVC use native TLS |
| per-request context in a thread pool | `thread_local RequestContext` | pass the context explicitly; pool threads outlive requests |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| process aborts with exit code 3 / "terminate called without an active exception" | a joinable `std::thread` destroyed (often on an exception path) | Listing 8.2 pattern; prefer `jthread` |
| shutdown hangs in `~jthread` | the thread function ignores its `stop_token`, or is blocked where the token cannot wake it | dump the stack of the joined thread; interruptible waits |
| deadlock between `request_stop()` and a stop callback | callback locks a mutex held by the caller of `request_stop()` or by the destroyer of the callback | lock-order review; tiny callbacks |
| crash after `main` returns | detached threads touching destroyed globals | join everything before `main` returns |
| TLS-heavy code much slower on one platform | emulated TLS or general-dynamic model | look for `__emutls_get_address` / `__tls_get_addr` in the profile |
| data from one request visible in another | `thread_local` state reused by pool threads | per-task context objects; reset in the task wrapper |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Why does std::thread's destructor terminate? Just detach it"</b></summary>

**Initial prompt.** "Our service aborts when an exception is thrown before `worker.join()`. Simplest fix: detach the
thread in the constructor so the destructor never terminates?"

**L5 textbook answer.** "Yes, detach it. The thread finishes on its own and the destructor is happy."

**Why L5 corrupts memory on ARM64.** The worker typically captures `this` or locals by reference. Detached, it keeps
running after the scope (or the object) is destroyed and reads and writes freed memory, a use-after-free on every
architecture. Terminating (Listing 8.2) was chosen by the standard precisely because both implicit alternatives are
worse (N2802): implicit detach dangles, and implicit join can block forever during unwinding.

**L7 principal defense.** "`std::jthread`, declared as the last member so it stops and joins before the members it
uses are destroyed. The thread function takes a `stop_token` and checks it at every blocking point. Detach only for
threads that own everything they touch and may legitimately outlive `main`, which is almost never."
</details>

<details><summary><b>Chain 2 🔥 "How do you stop a jthread that is blocked on a condition variable?"</b></summary>

**Initial prompt.** "A consumer `jthread` sits in `cv.wait(lk, [&]{ return !q.empty(); })`. At shutdown we call
`request_stop()`. Why does the destructor hang?"

**L5 textbook answer.** "Because `request_stop()` should wake it; add a `cv.notify_all()` after `request_stop()`."

**Why L5 deadlocks on ARM64.** `request_stop()` only sets the token's flag. `std::condition_variable` doesn't know about
the token, and the predicate doesn't check it, so the consumer re-checks `!q.empty()`, finds it false, and sleeps again
even after the `notify_all()`. Adding `|| st.stop_requested()` to the predicate leaves a gap: if the flag is set and the
notify is sent between the consumer's predicate check and its going to sleep, without the mutex held, the wakeup is
lost (file 03). The join then hangs, depending only on timing, on any architecture.

**L7 principal defense.** "`std::condition_variable_any` with `wait(lk, token, pred)` (Listing 8.1, part 3): it
registers a stop callback that notifies under the condition variable's own mutex, so there is no gap. Or keep
`std::condition_variable`, put `stop_requested()` in the predicate, and notify from a `stop_callback` that locks the
same mutex first."
</details>

<details><summary><b>Chain 3 ⚡ "Which thread runs a stop_callback?"</b></summary>

**Initial prompt.** "We register `stop_callback cb(token, [&]{ socket.close(); });`. In which thread does it run, and
when?"

**L5 textbook answer.** "In a background thread when stop is requested, like a signal handler."

**Why L5 breaks.** Listing 8.1 part 2: if registered before the request, it runs **synchronously inside
`request_stop()`**, in the requesting thread, before `request_stop()` returns (2a). If stop was already requested, it
runs **immediately inside the `stop_callback` constructor**, in the registering thread (2b). There is no background
thread. A callback that takes a lock the requester holds deadlocks the requester.

**L7 principal defense.** "Callbacks are small and non-blocking: set a flag, notify, cancel an I/O handle. I assume
they can run in either thread, and I never call `request_stop()` while holding a lock that a callback takes."
</details>

<details><summary><b>Chain 4 🧊 "Destroying a stop_callback can block?"</b></summary>

**Initial prompt.** "A worker destroys its `stop_callback` at the end of a request while holding `state_mutex`. The
callback locks `state_mutex` too. Occasionally shutdown hangs. Why?"

**L5 textbook answer.** "Destructors don't block; it must be something else."

**Why L5 deadlocks on ARM64.** `~stop_callback` must not return while its callback may still be running, or the
callback would access a destroyed object. So if another thread is in `request_stop()` executing this callback right
now, the destructor **waits** for it. The callback is waiting for `state_mutex`, which the destroying thread holds: a
deadlock, but only when a stop request lands in that window.

**L7 principal defense.** "Destroy stop callbacks without holding locks the callback uses. Better, design callbacks
that take no locks at all (an atomic flag plus `notify`), which removes the cycle. This is the same rule as joining a
thread while holding a lock it needs."
</details>

<details><summary><b>Chain 5 ⚡ "thread_local is just a register-relative load"</b></summary>

**Initial prompt.** "Our allocator keeps a per-thread cache in a `thread_local`. On Linux it's fast; the Windows MinGW
build is 10× slower in that path. Why?"

**L5 textbook answer.** "`thread_local` is `%fs`-relative addressing, always one instruction, so it must be
something else."

**Why L5 breaks.** Only the local-exec model is one instruction (Listing 8.3 table). Code in a shared library uses
general-dynamic (`__tls_get_addr` or a TLS descriptor call). This MinGW GCC build uses **emulated TLS**: every access
calls `__emutls_get_address`. Measured: 12.95–13.58 ns per increment against 0.96–1.00 ns with Clang's native TLS, and a
dynamically-initialized `thread_local` adds a TLS init call or guard check to every access (25.8–26.5 ns vs 1.6–1.7 ns).

**L7 principal defense.** "Make the hot per-thread state `constinit thread_local` and trivially initialized. Fetch
its address once per operation, not per access. On Linux libraries, consider `-ftls-model=initial-exec` when the
library is never `dlopen`ed. On Windows, measure the toolchain: native TLS (Clang, MSVC) vs emutls."
</details>

<details><summary><b>Chain 6 ⚡ "Threads are cheap, spawn one per request"</b></summary>

**Initial prompt.** "Each RPC spawns a `std::jthread` to do its work. Any problem at 50k requests per second?"

**L5 textbook answer.** "Modern OSes create threads quickly; it's fine."

**Why L5 breaks.** Listing 8.3: create + join of an *empty* `jthread` costs 75.5–83.3 µs on this machine. At 50k
requests per second that is 4 seconds of thread-creation work per second, before any real work. Each thread also
reserves a stack (1 MB by default on Windows, typically 8 MB of virtual memory on Linux), and the scheduler degrades
with thousands of runnable threads.

**L7 principal defense.** "A fixed pool sized to cores (work-stealing, Folder 10), with tasks as small objects, plus
asynchronous I/O for waiting, so blocked requests don't hold threads. Threads are for parallelism, not for
concurrency of waiting."
</details>

<details><summary><b>Chain 7 🔥 "What happens to a detached thread when main returns?"</b></summary>

**Initial prompt.** "A detached logging thread drains a global queue. Sometimes the process crashes during exit. Why?"

**L5 textbook answer.** "Detached threads are killed when the process exits, so it can't be the logger."

**Why L5 corrupts memory on ARM64.** Returning from `main` calls `exit()`, which runs static destructors **while the
detached thread is still running**: the global queue and its mutex are destroyed under the logger's feet. The logger
then locks a destroyed mutex and reads freed nodes. Only after `exit()` finishes do the remaining threads die.

**L7 principal defense.** "Every thread is joined before `main` returns: owned by a `jthread` in an object whose
lifetime ends before static destruction, with an explicit `shutdown()` that drains and stops. For must-not-block exits,
`std::quick_exit` skips static destructors, and then flushing is my job."
</details>

<details><summary><b>Chain 8 🧊 "thread_local per-request state in a pool"</b></summary>

**Initial prompt.** "We store the current user ID in a `thread_local` set at the start of each request. Any issue
when we move to a thread pool?"

**L5 textbook answer.** "No, each thread has its own copy, so requests can't interfere."

**Why L5 breaks.** Pool threads run many requests one after another. If any path forgets to set or clear the value,
the next request on that thread sees the previous user's ID: a security bug, not a crash. Coroutines (Folder 10) make
it worse: a coroutine suspended on thread A may resume on thread B and read B's value.

**L7 principal defense.** "Per-request context is passed explicitly (a parameter, or a context object captured by the
task). `thread_local` is for caches keyed by *thread*, such as allocator magazines and RNG state, never for identity.
If a framework forces TLS, the task wrapper sets and restores it with RAII."
</details>

---

## 6. Invariants checklist

- [ ] No `std::thread` without a guaranteed join on every path; prefer `std::jthread` members declared last.
- [ ] Every long-running thread function takes a `stop_token` and checks it at each blocking point.
- [ ] Blocking waits that must be cancellable use `condition_variable_any` stop-token overloads or a notifying
      `stop_callback`.
- [ ] Stop callbacks are tiny, take no locks held by requesters or destroyers.
- [ ] No detached threads touching objects with static storage duration.
- [ ] Hot `thread_local`s are `constinit` and trivially initialized; their TLS model is known on each platform.
- [ ] No identity or per-request state in `thread_local` when threads are pooled or coroutines migrate.

## 7. References

- [thread.thread.class], [thread.jthread.class], [thread.stoptoken]: <https://eel.is/c++draft/thread>
- P0660R10 (`std::jthread` and stop tokens): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p0660r10.pdf>
- N2802 (a plea to reconsider detach-on-destruction for thread objects): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2008/n2802.html>
- U. Drepper, "ELF Handling For Thread-Local Storage": <https://www.akkadia.org/drepper/tls.pdf>
- Itanium C++ ABI (thread-local wrapper and init functions, `_ZTW`/`_ZTH`): <https://itanium-cxx-abi.github.io/cxx-abi/abi.html>
- P1143R2 (`constinit`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1143r2.html>
