# 04 · C++26 `std::execution` (P2300): senders, receivers, schedulers, and structured concurrency

> **Scope.** `std::execution` replaces "a future per step" with a different contract. A *sender* describes work,
> `connect` binds it to a *receiver* and produces one *operation state* object for the whole pipeline, and `start`
> runs it. Completion arrives on exactly one of three channels: value, error, or stopped. Because the whole pipeline is
> one object built before anything runs, there's no shared state to allocate, no race between "producer finished" and
> "continuation attached", and the compiler can see through it: this file's three-stage pipeline compiles to
> `mov $42`. Neither standard library here ships `std::execution` yet, so the file implements the core (≈250 lines,
> same names and shapes as P2300) and measures it against futures. **The win is allocations and structure, not
> single-hop latency.**

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 10.8 | `mini_exec.hpp` | `just`, `then`, `when_all`, `sync_wait`, and a thread-pool scheduler whose operation states queue themselves intrusively (no allocation); errors and stop tokens propagate | compiled into 10.9 |
| 10.9 | `senders_demo.cpp` | **0 heap allocations** for a pure pipeline and for a two-thread `when_all`; the `when_all` op state is one 136-byte object; error channel; cancellation before start; per hop onto a pool: same latency as `submit()`+future, but 0 vs 2–3 allocations; the pipeline compiles to a constant | run, both compilers; asm x86-64 + AArch64 |

**Verification line.** As in file 01, GCC with `-fno-assume-sane-operators-new-delete` for the counting
`operator new`. `__cpp_lib_senders` is undefined in both libraries (probed). The reference implementation of P2300
is NVIDIA's stdexec; nothing here depends on it.

---

## 1. First principles

### 1.1 The contract

```text
   sender  (a description; copyable/movable value; no work happens yet)
     |  connect(sender, receiver)
     v
   operation state  (ONE object for the whole pipeline, usually on the caller's stack;
     |               it must not move once started: other objects point into it)
     |  start(op)
     v
   ... work runs (inline, on a scheduler's thread, after I/O ...) ...
     |
     +--> receiver.set_value(vs...)        exactly one of these three,
     +--> receiver.set_error(e)            exactly once
     +--> receiver.set_stopped()           (cancellation is not an error)

   receiver environment: get_stop_token(), get_scheduler(), get_allocator()  (queried by upstream senders)
```

* **Compared with futures** (file 01): a future's shared state is allocated per step, and producer and consumer meet
  through it at run time, racing to "set" and "attach". Here `connect` wires everything *before* `start`, so the
  producer always knows where its result goes, and the nesting of the types is the nesting of the operation states. The
  compiler sees one object.
* **Structured concurrency:** child operations live *inside* their parent's operation state (`when_all`'s op contains
  both children's ops), so a child can't outlive the parent, and every started operation completes before the state
  that owns it is destroyed. No detached work, no dangling continuations.

### 1.2 The core, implemented (Listing 10.8)

```cpp
// mini_exec.hpp - a minimal sender/receiver core in the shape of C++26 std::execution (P2300); neither library ships it
#pragma once
#include <atomic>
#include <concepts>
#include <condition_variable>
#include <exception>
#include <future>
#include <mutex>
#include <optional>
#include <stop_token>
#include <thread>
#include <tuple>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace ex {

// A sender describes work; connect(sender, receiver) builds an OPERATION STATE (a plain object, usually on the
// caller's stack); start() runs it; the work completes by calling exactly one of the receiver's
// set_value(...) / set_error(exception_ptr) / set_stopped(). Every sender here sends at most one value (or none: void).
struct sender_base {};
template <class S>
concept sender = std::derived_from<std::remove_cvref_t<S>, sender_base>;

// ---------------- just(v) ----------------
template <class T>
struct just_t : sender_base {
    using value_type = T;
    T value;
    template <class R>
    struct op {
        T value;
        R r;
        void start() noexcept { r.set_value(std::move(value)); }
    };
    template <class R>
    op<R> connect(R r) && {
        return op<R>{std::move(value), std::move(r)};
    }
};
template <class T>
just_t<T> just(T v) {
    return {{}, std::move(v)};
}

// ---------------- then(f) ----------------
template <class In, class F>
struct then_result {
    using type = std::invoke_result_t<F, In>;
};
template <class F>
struct then_result<void, F> {
    using type = std::invoke_result_t<F>;
};

template <class S, class F>
struct then_t : sender_base {
    using value_type = typename then_result<typename S::value_type, F>::type;
    S s;
    F f;
    template <class R>
    struct recv {   // wraps the downstream receiver: calls f, forwards the result
        F f;
        R r;
        template <class... V>
        void set_value(V&&... v) noexcept {
            try {
                if constexpr (std::is_void_v<value_type>) {
                    f(std::forward<V>(v)...);
                    r.set_value();
                } else {
                    r.set_value(f(std::forward<V>(v)...));
                }
            } catch (...) {
                r.set_error(std::current_exception());   // an exception becomes the error channel
            }
        }
        void set_error(std::exception_ptr e) noexcept { r.set_error(std::move(e)); }
        void set_stopped() noexcept { r.set_stopped(); }
        std::stop_token get_stop_token() const noexcept { return r.get_stop_token(); }
    };
    template <class R>
    auto connect(R r) && {   // the operation state of `s`, with our receiver nested inside it: no allocation
        return std::move(s).connect(recv<R>{std::move(f), std::move(r)});
    }
};
template <class F>
struct then_closure {
    F f;
};
template <class F>
then_closure<F> then(F f) {
    return {std::move(f)};
}
template <sender S, class F>
then_t<std::remove_cvref_t<S>, F> operator|(S&& s, then_closure<F> c) {
    return {{}, std::forward<S>(s), std::move(c.f)};
}

// ---------------- when_all(a, b): both run; completes with a pair, or the first error, or stopped ----------------
template <class S1, class S2>
struct when_all_t : sender_base {
    using V1 = typename S1::value_type;
    using V2 = typename S2::value_type;
    using value_type = std::pair<V1, V2>;
    S1 s1;
    S2 s2;
    template <class R>
    struct op {
        template <int I>
        struct child {
            op* self;
            template <class V>
            void set_value(V&& v) noexcept {
                std::get<I>(self->vals).emplace(std::forward<V>(v));
                self->arrive();
            }
            void set_error(std::exception_ptr e) noexcept {
                {
                    std::scoped_lock lk(self->err_m);
                    if (!self->err) self->err = std::move(e);
                }
                self->arrive();
            }
            void set_stopped() noexcept {
                self->stopped.store(true);
                self->arrive();
            }
            std::stop_token get_stop_token() const noexcept { return self->r.get_stop_token(); }
        };
        R r;
        std::tuple<std::optional<V1>, std::optional<V2>> vals;
        std::atomic<int> remaining{2};
        std::mutex err_m;
        std::exception_ptr err;
        std::atomic<bool> stopped{false};
        decltype(std::declval<S1>().connect(std::declval<child<0>>())) op1;   // children live INSIDE this op
        decltype(std::declval<S2>().connect(std::declval<child<1>>())) op2;
        op(S1&& a, S2&& b, R rr)
            : r(std::move(rr)), op1(std::move(a).connect(child<0>{this})), op2(std::move(b).connect(child<1>{this})) {}
        void start() noexcept {
            op1.start();
            op2.start();
        }
        void arrive() noexcept {   // the last child to finish completes the parent
            if (remaining.fetch_sub(1, std::memory_order_acq_rel) != 1) return;
            if (err) r.set_error(err);
            else if (stopped.load()) r.set_stopped();
            else r.set_value(value_type{std::move(*std::get<0>(vals)), std::move(*std::get<1>(vals))});
        }
    };
    template <class R>
    op<R> connect(R r) && {
        return op<R>(std::move(s1), std::move(s2), std::move(r));   // guaranteed elision: op is never moved
    }
};
template <sender S1, sender S2>
when_all_t<std::remove_cvref_t<S1>, std::remove_cvref_t<S2>> when_all(S1&& a, S2&& b) {
    return {{}, std::forward<S1>(a), std::forward<S2>(b)};
}

// ---------------- sync_wait(sender): start it, block until it completes ----------------
template <class T>
using stored_t = std::conditional_t<std::is_void_v<T>, std::monostate, T>;

// Like std::execution's run_loop-based sync_wait: a mutex + condition variable. The completing thread notifies
// UNDER the lock, because the waiting thread destroys this state as soon as it sees `done` (Folder 08, file 03).
template <class T>
struct sync_state {
    std::optional<stored_t<T>> value;
    std::exception_ptr error;
    std::stop_token token;
    std::mutex m;
    std::condition_variable cv;
    bool done = false;
    void complete() {
        std::scoped_lock lk(m);
        done = true;
        cv.notify_one();
    }
};
template <class T>
struct sync_receiver {
    sync_state<T>* st;
    template <class... V>
    void set_value(V&&... v) noexcept {
        st->value.emplace(std::forward<V>(v)...);
        st->complete();
    }
    void set_error(std::exception_ptr e) noexcept {
        st->error = std::move(e);
        st->complete();
    }
    void set_stopped() noexcept { st->complete(); }   // value stays empty
    std::stop_token get_stop_token() const noexcept { return st->token; }
};
template <sender S>
std::optional<stored_t<typename std::remove_cvref_t<S>::value_type>> sync_wait(S&& s, std::stop_token tok = {}) {
    using T = typename std::remove_cvref_t<S>::value_type;
    sync_state<T> st;
    st.token = std::move(tok);
    auto op = std::forward<S>(s).connect(sync_receiver<T>{&st});   // the whole pipeline's state, on this frame
    op.start();
    {
        std::unique_lock lk(st.m);
        st.cv.wait(lk, [&] { return st.done; });
    }
    if (st.error) std::rethrow_exception(st.error);
    return std::move(st.value);
}

// ---------------- a thread-pool scheduler: operation states queue themselves intrusively ----------------
class thread_pool {
    struct node {
        node* next = nullptr;
        void (*run)(node*) = nullptr;
    };
    std::mutex m_;
    std::condition_variable cv_;
    node* head_ = nullptr;
    node* tail_ = nullptr;
    bool stop_ = false;
    std::vector<std::jthread> threads_;

    void enqueue(node* n) {
        {
            std::scoped_lock lk(m_);
            n->next = nullptr;
            (tail_ ? tail_->next : head_) = n;
            tail_ = n;
        }
        cv_.notify_one();
    }

public:
    explicit thread_pool(int n) {
        for (int i = 0; i < n; ++i)
            threads_.emplace_back([this] {
                for (;;) {
                    node* job;
                    {
                        std::unique_lock lk(m_);
                        cv_.wait(lk, [&] { return stop_ || head_ != nullptr; });
                        if (!head_) return;
                        job = head_;
                        head_ = job->next;
                        if (!head_) tail_ = nullptr;
                    }
                    job->run(job);
                }
            });
    }
    ~thread_pool() {
        {
            std::scoped_lock lk(m_);
            stop_ = true;
        }
        cv_.notify_all();
    }

    struct schedule_sender : sender_base {   // completes with set_value() on a pool thread
        using value_type = void;
        thread_pool* pool;
        template <class R>
        struct op : node {
            R r;
            thread_pool* pool;
            op(R rr, thread_pool* p) : r(std::move(rr)), pool(p) { this->run = &op::exec; }
            op(op&&) = delete;                       // it is linked into the pool's queue: never move it
            void start() noexcept { pool->enqueue(this); }
            static void exec(node* n) {
                op* self = static_cast<op*>(n);
                if (self->r.get_stop_token().stop_requested()) self->r.set_stopped();
                else self->r.set_value();
            }
        };
        template <class R>
        op<R> connect(R r) && {
            return op<R>(std::move(r), pool);
        }
    };
    schedule_sender schedule() { return {{}, this}; }

    // The classic alternative: a heap-allocated task and a future per submission.
    template <class F>
    std::future<std::invoke_result_t<F>> submit(F f) {
        struct heap_task : node {
            std::packaged_task<std::invoke_result_t<F>()> task;
        };
        auto* t = new heap_task;
        t->task = std::packaged_task<std::invoke_result_t<F>()>(std::move(f));
        t->run = [](node* n) {
            auto* self = static_cast<heap_task*>(n);
            self->task();
            delete self;
        };
        std::future<std::invoke_result_t<F>> fut = t->task.get_future();
        enqueue(t);
        return fut;
    }
};

}  // namespace ex
```

* **`then`** doesn't create an operation state of its own. Its `connect` connects the *upstream* sender to a receiver
  that wraps the downstream receiver and `f`. A chain `just | then | then` is one operation state, the innermost
  `just` op, with two nested receivers inside it.
* **`when_all`** holds both children's operation states as members, constructed in place with `this`-pointing
  receivers. The last child to finish (an `acq_rel` `fetch_sub` on `remaining`) completes the parent. That's why
  operation states are immovable: the children hold pointers to it.
* **`schedule()`** on the pool returns a sender whose operation state *is* the queue node (`struct op : node`), with a
  deleted move constructor. Guaranteed copy elision (C++17) lets `connect` return it anyway. Starting it links the op
  into the pool's list, so scheduling allocates nothing.
* **`sync_wait`** puts the whole pipeline's operation state on its own stack frame and waits on a mutex + condition
  variable (like the standard's `run_loop`). The completing thread notifies *under the lock* because the waiter
  destroys the state the moment it sees `done` (Folder 08, file 03, §1.3).
* **Errors and stops:** an exception thrown by a `then` callback is caught in the receiver wrapper and sent down the
  error channel, skipping later value steps; `sync_wait` rethrows it. The pool's op checks the receiver's stop token
  and completes with `set_stopped()` instead of running.

### 1.3 Measured (Listing 10.9)

```cpp
// senders_demo.cpp - sender pipelines: zero allocations, operation-state sizes, errors, cancellation, cost per hop
#include "mini_exec.hpp"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <new>
#include <print>
#include <stdexcept>
#include <string>

#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wmismatched-new-delete"   // false positive with replaced new/delete (Folder 03)
#endif
std::atomic<long> g_allocs{0};
void* operator new(std::size_t n) {   // count every allocation (GCC: -fno-assume-sane-operators-new-delete)
    g_allocs.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(n)) return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

// For the assembly listing: the same pure pipeline connected to a receiver that just stores the result.
struct store_receiver {
    int* out;
    void set_value(int v) noexcept { *out = v; }
    void set_error(std::exception_ptr) noexcept {}
    void set_stopped() noexcept {}
    std::stop_token get_stop_token() const noexcept { return {}; }
};
int pipeline_value() {
    int out = 0;
    auto op = (ex::just(20) | ex::then([](int x) { return x + 1; }) | ex::then([](int x) { return x * 2; }))
                  .connect(store_receiver{&out});
    op.start();
    return out;
}

int main() {
    // 1. A pure pipeline: describing it allocates nothing, running it allocates nothing.
    {
        const long a0 = g_allocs.load();
        auto pipeline = ex::just(20) | ex::then([](int x) { return x + 1; }) | ex::then([](int x) { return x * 2; });
        const std::optional<int> r = ex::sync_wait(std::move(pipeline));
        std::println("1. just(20) | then(+1) | then(*2) -> {}; heap allocations: {}", r.value(), g_allocs.load() - a0);
    }
    ex::thread_pool pool(2);
    // 2. Hop onto the pool, compute on two threads at once, join: the operation states live on sync_wait's frame
    //    and link themselves into the pool's queue, so still no allocation.
    {
        const long a0 = g_allocs.load();
        auto left = pool.schedule() | ex::then([] { return 6; });
        auto right = pool.schedule() | ex::then([] { return 7; });
        const auto r = ex::sync_wait(ex::when_all(std::move(left), std::move(right)) |
                                     ex::then([](std::pair<int, int> p) { return p.first * p.second; }));
        std::println("2. when_all(schedule|then(6), schedule|then(7)) | then(*) -> {}; heap allocations: {}", r.value(),
                     g_allocs.load() - a0);
        using Op = decltype(ex::when_all(pool.schedule() | ex::then([] { return 6; }), pool.schedule() | ex::then([] { return 7; }))
                                .connect(std::declval<ex::sync_receiver<std::pair<int, int>>>()));
        std::println("   the whole when_all operation state is one {}-byte object (two child ops, results, a count)", sizeof(Op));
    }
    // 3. Errors travel on their own channel: the exception reaches sync_wait, which rethrows it.
    {
        try {
            (void)ex::sync_wait(pool.schedule() | ex::then([]() -> int { throw std::runtime_error("parse failed"); }) |
                                ex::then([](int x) { return x + 1; }));   // skipped: the error bypasses value steps
        } catch (const std::runtime_error& e) {
            std::println("3. error channel: sync_wait rethrew \"{}\"", e.what());
        }
    }
    // 4. Cancellation: the stop token reaches the scheduler's operation, which completes with set_stopped();
    //    the then() callback never runs and sync_wait returns an empty optional.
    {
        std::stop_source stop;
        stop.request_stop();
        bool ran = false;
        const auto r = ex::sync_wait(pool.schedule() | ex::then([&] {
                                         ran = true;
                                         return 1;
                                     }),
                                     stop.get_token());
        std::println("4. stopped before start: result {}, callback ran: {}", r ? "has a value" : "empty (set_stopped)", ran);
    }
    // 5. Cost per hop onto the pool and back: sender + sync_wait vs submit() returning a std::future.
    {
        constexpr int n = 20'000;
        long a0 = g_allocs.load();
        auto t0 = std::chrono::steady_clock::now();
        long sum = 0;
        for (int i = 0; i < n; ++i) sum += ex::sync_wait(pool.schedule() | ex::then([i] { return i & 1; })).value();
        std::chrono::duration<double, std::micro> d = std::chrono::steady_clock::now() - t0;
        const long sender_allocs = g_allocs.load() - a0;
        const double sender_us = d.count() / n;
        a0 = g_allocs.load();
        t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < n; ++i) sum += pool.submit([i] { return i & 1; }).get();
        d = std::chrono::steady_clock::now() - t0;
        const long future_allocs = g_allocs.load() - a0;
        std::println("5. {} hops: sender {:.2f} us and {} allocations per hop; future {:.2f} us and {} allocations per hop (sum {})",
                     n, sender_us, static_cast<double>(sender_allocs) / n, d.count() / n,
                     static_cast<double>(future_allocs) / n, sum);
    }
}
```

Output (verified, GCC then Clang):

```text
1. just(20) | then(+1) | then(*2) -> 42; heap allocations: 0
2. when_all(schedule|then(6), schedule|then(7)) | then(*) -> 42; heap allocations: 0
   the whole when_all operation state is one 136-byte object (two child ops, results, a count)
3. error channel: sync_wait rethrew "parse failed"
4. stopped before start: result empty (set_stopped), callback ran: false
5. 20000 hops: sender 11.74 us and 0 allocations per hop; future 12.66 us and 3 allocations per hop (sum 20000)
1. just(20) | then(+1) | then(*2) -> 42; heap allocations: 0
2. when_all(schedule|then(6), schedule|then(7)) | then(*) -> 42; heap allocations: 0
   the whole when_all operation state is one 136-byte object (two child ops, results, a count)
3. error channel: sync_wait rethrew "parse failed"
4. stopped before start: result empty (set_stopped), callback ran: false
5. 20000 hops: sender 0.93 us and 0 allocations per hop; future 0.68 us and 2 allocations per hop (sum 20000)
```

`pipeline_value()`, Clang 21 `-O3`, x86-64 and AArch64:

```asm
_Z14pipeline_valuev:               # pipeline_value()
	movl	$42, %eax
	retq
```

```asm
_Z14pipeline_valuev:               // pipeline_value()
	mov	w0, #42
	ret
```

* **Allocations:** 0 for the pure pipeline and 0 for the two-thread `when_all` (its entire operation state is one
  136-byte object), on both libraries. The future path allocated 2 (libc++) or 3 (libstdc++) times per hop.
* **The abstraction disappears:** the same pipeline, connected to a receiver that stores the result, compiles to
  `movl $42, %eax` / `mov w0, #42`. No frames, no shared state, no indirect calls: every stage is a concrete type the
  optimizer can inline.
* **Latency per hop is a wash.** Over two runs, one hop onto the pool and back took 0.89–0.93 µs with senders vs
  0.68–0.95 µs with `submit()` + future on libc++ (SRW lock and condition variable), and 11.6–11.7 µs vs 12.0–12.7 µs on
  libstdc++ (winpthreads). Both wait on a condition variable, and the wake-up dominates. An earlier version of this
  listing waited on a `binary_semaphore` instead, and the senders looked *slower* on libc++ because libc++'s semaphore
  polls with sleeps on Windows (Folder 08). Comparing scheduling models means equalizing the blocking primitive.

### 1.4 The real vocabulary

| P2300 / C++26 | Here | What it does |
|---|---|---|
| `just(vs...)`, `just_error(e)`, `just_stopped()` | `just` | a sender that completes immediately |
| `then(f)`, `upon_error(f)`, `upon_stopped(f)` | `then` | transform one channel |
| `let_value(f)` | — | `f` returns a *sender*: the dynamic-continuation building block (what `future::then` wanted to be) |
| `scheduler`, `schedule(sch)`, `starts_on(sch, s)`, `continues_on(s, sch)` | `pool.schedule()` | where work runs; `continues_on` moves the rest of a chain to another context |
| `when_all(ss...)` | `when_all` (two senders) | fork-join; stops the others if one fails |
| `split(s)` / `ensure_started` replacements | — | share one result between several consumers |
| `sync_wait(s)`, `run_loop` | `sync_wait` | block the current thread until completion (never inside async code) |
| `counting_scope` (P3149) | — | spawn dynamic work whose lifetime is still bounded (structured `async_scope`) |
| `parallel_scheduler` (P2079), `task` (P3552) | — | a system thread pool; a coroutine task type that is also a sender |

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| asynchronous composition | `future`, `async` | Concurrency TS `future::then` (abandoned) | executors proposals (P0443 lineage) | coroutines | — | `std::execution` (P2300): senders, receivers, schedulers, `sync_wait` |
| cancellation | none | — | — | `stop_token` | — | stop tokens in receiver environments; `inplace_stop_token`, `set_stopped` channel |
| lifetimes | detached by default (`thread::detach`, discarded futures) | — | — | `jthread` | — | structured: operation states, `counting_scope` (P3149) |
| availability here | — | — | — | — | — | neither libstdc++ 16 nor libc++ 21 ships `<execution>` senders (stdexec, libunifex do) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| chaining asynchronous steps | a future (and allocation, lock, notify) per step | senders: one operation state per pipeline (0 allocations here) |
| custom operation state | a movable op holding a pointer to itself or linked into a queue | immovable (`op(op&&) = delete`), returned by guaranteed elision from `connect` |
| an exception inside a continuation | let it escape a pool thread (terminate) | catch in the receiver wrapper and send it down `set_error` |
| cancelling a pipeline | flags polled by hand | stop tokens in the receiver environment, `set_stopped` |
| waiting for a result inside async code | `sync_wait` on a pool thread (blocks a worker, starvation risk) | compose: `let_value`, `when_all`, or `co_await` the sender |
| fire-and-forget work | detached threads / discarded futures | `counting_scope.spawn` with a join at shutdown |
| comparing schedulers | different blocking primitives on each side | same wake-up mechanism; count allocations separately from latency |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| crash or garbage after `start` | operation state moved or destroyed while running | immovable ops; `sync_wait`-style lifetime ownership |
| a pipeline never completes | a receiver completion path missing (no `set_stopped` on cancellation, swallowed error) | every sender completes on exactly one channel; tests per channel |
| pool threads blocked in `sync_wait` | synchronous waiting inside async code | thread dumps; compose instead |
| a continuation runs on an unexpected thread | completion context of the predecessor | explicit `continues_on(scheduler)` |
| crash in a completion's `notify` | waiter destroyed the state before the notifier finished | notify under the lock (Listing 10.8's `sync_state::complete`) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "What's wrong with chaining futures?"</b></summary>

**Initial prompt.** "Why did C++26 add senders instead of just standardizing `future::then`?"

**L5 textbook answer.** "Senders are a more modern API; it's mostly a style difference."

**Why L5 breaks.** It's a cost model and a correctness model. Each future step is a heap-allocated shared state (2–3
allocations per hop here), a lock and a notify, plus a race between "value set" and "continuation attached" that the
library must arbitrate at run time. Execution context is implicit, and there's no cancellation. Senders connect the whole
chain into one object *before* starting it: 0 allocations, and the three-stage pipeline compiled to `mov $42`.

**L7 principal defense.** "Senders make asynchronous composition a compile-time structure: no shared state, no
attach race, explicit schedulers, three completion channels including cancellation, and operation states whose
lifetimes nest. `future::then` would have kept every cost of futures and added more."
</details>

<details><summary><b>Chain 2 🧊 "Why can't an operation state be moved?"</b></summary>

**Initial prompt.** "Our custom sender's operation state is returned by value from `connect`. A colleague added a
move constructor 'for flexibility'. What can go wrong?"

**L5 textbook answer.** "Nothing; moving is always safe in C++."

**Why L5 corrupts memory on ARM64.** Once started, other objects point *into* the operation state: the pool's intrusive
queue links to it (`struct op : node`), and `when_all`'s child receivers hold `this` of the parent op. Moving it after
`start` (or after connecting children) leaves those pointers aimed at the old address: the pool later runs a dead object,
and a child completes into freed memory. The bug shows up as random corruption, on any architecture.

**L7 principal defense.** "Operation states are immovable (`op(op&&) = delete` in Listing 10.8). C++17's guaranteed copy
elision still lets `connect` return them by value as prvalues, and the caller (`sync_wait`, a parent op, a coroutine
frame) constructs them in their final place."
</details>

<details><summary><b>Chain 3 ⚡ "On which thread does then() run?"</b></summary>

**Initial prompt.** "In `sync_wait(pool.schedule() | then(f) | then(g))`, which thread runs `g`?"

**L5 textbook answer.** "The thread that called `sync_wait`, after the pool returns the result."

**Why L5 breaks.** `then` runs its function where its predecessor *completed*: `schedule()` completes on a pool thread,
so `f` and `g` both run on that pool thread, inline in the completion. `sync_wait`'s thread only receives the final
value. If `g` touches UI state or thread-affine resources, that's a bug.

**L7 principal defense.** "Completion context is part of the contract. To move the rest of a chain, say so:
`continues_on(ui_scheduler)`. A sender's environment can also expose its completion scheduler, so generic code can
reason about it."
</details>

<details><summary><b>Chain 4 🧊 "Why is 'stopped' a separate channel?"</b></summary>

**Initial prompt.** "Why not report cancellation as an exception on the error channel?"

**L5 textbook answer.** "It could be; a cancelled operation is a failed operation."

**Why L5 breaks.** Cancellation is usually *intended* (a user left, a timeout fired, a sibling in `when_all` failed).
Treating it as an error means every layer must recognize and filter a special exception, pay for throwing it, and
log it as a failure. A separate `set_stopped()` lets algorithms react directly: `when_all` stops the other children
when one fails, and `sync_wait` returns an empty optional (Listing 10.9, part 4: the callback never ran).

**L7 principal defense.** "Three channels: value, error (something went wrong), stopped (someone asked us to stop).
Stop requests travel down through the receiver environment's stop token; stopped completions travel up. Each is cheap
and explicit."
</details>

<details><summary><b>Chain 5 🔥 "Senders are faster than futures, so switch everything"</b></summary>

**Initial prompt.** "We benchmarked one hop onto a thread pool. Senders and futures took the same time. Did we do it
wrong?"

**L5 textbook answer.** "Probably. Senders are zero-overhead, so they should be much faster."

**Why L5 breaks.** Probably not. A hop onto another thread and back is dominated by the wake-up: a condition variable
or futex wake plus a context switch. Listing 10.9 measured 0.89–0.93 µs (senders) vs 0.68–0.95 µs (futures) on libc++,
and 11.6–11.7 vs 12.0–12.7 µs on winpthreads. What differs is allocations (0 vs 2–3 per hop) and what the compiler can
do inside a context: the inline pipeline vanished into a constant. And a careless benchmark can invert the result, as
when this listing's `sync_wait` first used a polling semaphore.

**L7 principal defense.** "Senders pay off in allocation-free composition, inlining of inline stages, explicit
scheduling, cancellation and structured lifetimes: fewer allocations under load, better tail latency, fewer lifetime
bugs. Raw cross-thread hop latency is set by the wake-up mechanism. I'd benchmark with the same blocking primitive on
both sides and report allocations separately."
</details>

<details><summary><b>Chain 6 ⚡ "What is structured concurrency?"</b></summary>

**Initial prompt.** "Explain structured concurrency and how `std::execution` provides it."

**L5 textbook answer.** "Running tasks in parallel with a thread pool."

**Why L5 breaks.** It's a lifetime discipline, not a scheduling one. Concurrent operations are nested like scopes: a
child starts and *finishes* within its parent, so the parent can lend it references safely, and errors and cancellation
propagate along the nesting. `when_all`'s operation state physically contains both children (136 bytes in Listing 10.9),
so they cannot outlive it. Fire-and-forget (`detach`, discarded futures) is the unstructured opposite, the source of
shutdown crashes (Folder 08, file 01, Chain 7).

**L7 principal defense.** "Every asynchronous operation has an owner that waits for it: a parent op, a coroutine
frame, or a `counting_scope` for dynamically spawned work, joined at shutdown. Then references to the caller's state are
safe, cancellation reaches everything, and shutdown is deterministic."
</details>

<details><summary><b>Chain 7 🔥 "Call sync_wait inside a pool task"</b></summary>

**Initial prompt.** "A handler running on the pool does `auto v = sync_wait(pool.schedule() | then(load)).value();`.
Under load, everything freezes. Why?"

**L5 textbook answer.** "A bug in the pool's queue; add more threads."

**Why L5 deadlocks on ARM64.** `sync_wait` blocks the calling *thread*. When every pool worker is inside a handler
blocked in `sync_wait` on work queued to the same pool, no worker remains to run that work: the starvation deadlock of
file 01's Chain 8, in new syntax. More threads only move the threshold.

**L7 principal defense.** "`sync_wait` only at the edge (in `main`, tests, a bridge to blocking APIs), never inside
asynchronous code. Inside, compose: return a sender from the handler and use `let_value`, or `co_await` the sender in a
coroutine task (P2300 senders are awaitable), so the task suspends and the worker is free."
</details>

<details><summary><b>Chain 8 🧊 "Can we use std::execution today?"</b></summary>

**Initial prompt.** "C++26 has `std::execution`. Can we start using it with our current toolchain?"

**L5 textbook answer.** "Yes, add `-std=c++26`."

**Why L5 breaks.** In this toolchain, `__cpp_lib_senders` is undefined in both libstdc++ 16 and libc++ 21: the senders
part of `<execution>` isn't there yet. The standard's specification is large (environments, queries, completion
signatures, customization through `tag_invoke`'s successor), and implementations trail it.

**L7 principal defense.** "Use NVIDIA's stdexec (the reference implementation) or libunifex behind a thin layer with
the standard names, and switch to the library implementation when `__cpp_lib_senders` appears. And understand the core
well enough to debug it: connect, operation state, three channels. Listing 10.8 is that core in about 250 lines."
</details>

---

## 6. Invariants checklist

- [ ] Asynchronous pipelines are built as senders and connected once; no future per step.
- [ ] Operation states are immovable and owned by something that outlives their completion.
- [ ] Every operation completes on exactly one channel: value, error or stopped.
- [ ] Execution context is explicit (`starts_on`/`continues_on`); no assumptions about the completing thread.
- [ ] `sync_wait` appears only at the edges, never in pool or coroutine code.
- [ ] Dynamically spawned work belongs to a scope that is joined at shutdown.

## 7. References

- P2300R10 (`std::execution`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p2300r10.html>
- NVIDIA stdexec (reference implementation): <https://github.com/NVIDIA/stdexec>
- libunifex: <https://github.com/facebookexperimental/libunifex>
- E. Niebler, "Structured Concurrency" (2020): <https://ericniebler.com/2020/11/08/structured-concurrency/>
- L. Baker, "Structured Concurrency: Writing Safer Concurrent Code with Coroutines and Algorithms", CppCon 2019 (talk)
- P3149 (`async_scope` / `counting_scope`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p3149r11.html>
