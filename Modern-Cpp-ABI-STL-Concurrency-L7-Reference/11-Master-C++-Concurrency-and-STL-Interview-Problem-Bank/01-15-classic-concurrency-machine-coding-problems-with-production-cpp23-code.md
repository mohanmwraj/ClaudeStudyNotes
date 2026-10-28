# 01 · 15 classic concurrency machine-coding problems, with production C++23 code

> **Scope.** The fifteen problems that recur in senior and staff concurrency interviews (FAANG infrastructure, NVIDIA,
> HFT), each solved as a complete, compilable, race-free C++23 program with a stress test whose invariants it checks
> and prints. Every listing below ran on both GCC 16 and Clang 21. Several first drafts failed their own checks: a
> pool that could lose a shutdown wakeup, a cache that silently used half its shards, a timer demo stopped by its own
> `jthread` destructor, a demo that relied on undefined behaviour. Each section notes what went wrong, because in an
> interview the follow-up questions target exactly those places.

| # | Problem | Listing | Verified invariant |
|---|---|---|---|
| 1 | bounded blocking queue, timeouts, `close()` | `p01_bounded_queue.cpp` | 600,000 items exactly once; timeout and close semantics |
| 2 | lock-free SPSC and MPMC rings | `p02_rings.cpp` | FIFO order (SPSC), every item once (MPMC) |
| 3 | work-stealing pool, `submit(F&&, Args&&...) -> future<R>`, `jthread` shutdown | `p03_ws_pool.cpp` | 40,000 tasks, results and exceptions through futures, steals |
| 4 | reader-writer lock with writer preference | `p04_rwlock_writer_pref.cpp` | writer starves under reader preference, not under writer preference |
| 5 | concurrent sharded LRU cache | `p05_sharded_lru.cpp` | LRU order; size ≤ capacity; no wrong values |
| 6 | token-bucket and sliding-window rate limiters (packed 64-bit CAS) | `p06_rate_limiter.cpp` | exact deterministic behaviour; never over the limit under contention |
| 7 | hierarchical timing wheel with O(1) cancel | `p07_timing_wheel.cpp` | 2,000 timers fire on their exact tick, 1,000 cancelled never fire |
| 8 | asynchronous MPSC logger, no blocking on the hot path | `p08_mpsc_logger.cpp` | delivered + dropped = produced; per-thread order |
| 9 | parallel DAG executor, atomic in-degree counters, no locks | `p09_dag_executor.cpp` | 20,000 nodes run once, values equal the sequential order |
| 10 | dining philosophers, deadlock-free multi-account transfer | `p10_philosophers_transfer.cpp` | completion; money conserved; no overdraft |
| 11 | readers-writers-upgradable lock | `p11_upgradable_lock.cpp` | the double-upgrade deadlock reproduced; each key computed once |
| 12 | fair ticket spin lock and MCS queue lock | `p12_ticket_mcs.cpp` | counts consistent; fairness measured |
| 13 | H2O barrier and multi-stage pipeline barrier | `p13_h2o_barrier.cpp` | 10 molecules, each exactly H2O; pipeline equals sequential |
| 14 | thread-safe object pool / slab, tagged free list | `p14_object_pool.cpp` | no slot handed out twice; all slots returned |
| 15 | single-flight request coalescer | `p15_single_flight.cpp` | 100 concurrent requests → 1 backend fetch; errors reach all |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (zig, libc++), `-O2 -Wall -Wextra -Wpedantic
-Werror -Wshadow -Wconversion -Wsign-conversion`, Intel Core i5-11260H. Outputs are GCC's; Clang printed the same
except where both are shown (timing-dependent numbers).

---

## 1. First principles

### 1.0 How to run a machine-coding round

1. **State the contract first.** Blocking or not? Bounded? What do `close`/`cancel`/shutdown mean for items in flight?
   FIFO per producer or global? Most "bugs" interviewers probe are unstated contracts.
2. **Write the invariants** you will check: "every item exactly once", "never over the limit", "fires exactly at its
   tick". Then the stress test is easy to write and convincing.
3. **Pick the simplest primitive that meets the progress requirement:** a mutex and condition variables first, atomics
   when a measured hot path or a progress guarantee demands them (Folders 07–09).
4. **Name the failure modes as you code:** lost wakeup, ABA, lock-order inversion, lifetime of the thing a thread
   points to.

### 1.1 P1 · Bounded blocking queue with timeouts and `close()` (Listing 11.1)

**Problem.** A fixed-capacity queue: `push` blocks while full, `pop` blocks while empty, `try_push_for`/`try_pop_for`
give up after a timeout, and `close()` makes producers fail and lets consumers drain what's left.

```cpp
// p01_bounded_queue.cpp - P1: thread-safe bounded blocking queue with try_push_for/try_pop_for timeouts and close()
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <print>
#include <thread>
#include <vector>

template <class T>
class BoundedQueue {
public:
    enum class Status { ok, timeout, closed };
    explicit BoundedQueue(std::size_t capacity) : cap_(capacity) {}

    Status push(T v) { return push_until(std::move(v), std::nullopt); }
    template <class Rep, class Period>
    Status try_push_for(T v, std::chrono::duration<Rep, Period> d) {
        return push_until(std::move(v), std::chrono::steady_clock::now() + d);
    }
    // Returns nullopt only when the queue is closed AND drained: consumers finish the backlog first.
    std::optional<T> pop() { return pop_until(std::nullopt); }
    template <class Rep, class Period>
    std::optional<T> try_pop_for(std::chrono::duration<Rep, Period> d) {
        return pop_until(std::chrono::steady_clock::now() + d);
    }
    void close() {
        {
            std::scoped_lock lk(m_);
            closed_ = true;
        }
        not_full_.notify_all();    // wake blocked producers (they will see `closed`)
        not_empty_.notify_all();   // wake blocked consumers (they drain, then see `closed`)
    }

private:
    using Deadline = std::optional<std::chrono::steady_clock::time_point>;
    Status push_until(T v, Deadline deadline) {
        std::unique_lock lk(m_);
        auto ready = [&] { return closed_ || q_.size() < cap_; };
        if (deadline) {
            if (!not_full_.wait_until(lk, *deadline, ready)) return Status::timeout;
        } else {
            not_full_.wait(lk, ready);
        }
        if (closed_) return Status::closed;
        q_.push_back(std::move(v));
        lk.unlock();               // notify after unlocking: the queue outlives every waiter
        not_empty_.notify_one();
        return Status::ok;
    }
    std::optional<T> pop_until(Deadline deadline) {
        std::unique_lock lk(m_);
        auto ready = [&] { return closed_ || !q_.empty(); };
        if (deadline) {
            if (!not_empty_.wait_until(lk, *deadline, ready)) return std::nullopt;
        } else {
            not_empty_.wait(lk, ready);
        }
        if (q_.empty()) return std::nullopt;   // closed and drained
        T v = std::move(q_.front());
        q_.pop_front();
        lk.unlock();
        not_full_.notify_one();
        return v;
    }

    std::mutex m_;
    std::condition_variable not_full_, not_empty_;   // two cvs: each has one kind of waiter (Folder 08, file 03)
    std::deque<T> q_;
    const std::size_t cap_;
    bool closed_ = false;
};

int main() {
    using Q = BoundedQueue<std::uint64_t>;
    // Timeouts and close semantics, deterministically.
    {
        Q q(1);
        const bool first = q.push(1) == Q::Status::ok;
        const bool timed_out = q.try_push_for(2, std::chrono::milliseconds(50)) == Q::Status::timeout;
        q.close();
        const bool closed = q.push(3) == Q::Status::closed;
        const std::optional<std::uint64_t> drained = q.pop();
        const std::optional<std::uint64_t> after = q.pop();
        std::println("capacity 1: push ok {}, second try_push_for(50ms) timed out {}, push after close -> closed {}", first,
                     timed_out, closed);
        std::println("after close: pop() drains the backlog -> {}, then pop() -> {}", drained.value_or(0),
                     after ? "a value" : "nullopt (closed and empty)");
    }
    // 3 producers x 200,000 items, 3 consumers, capacity 64; close() after the producers finish.
    {
        Q q(64);
        constexpr std::uint64_t kPer = 200'000;
        std::atomic<std::uint64_t> sum{0}, count{0};
        {
            std::vector<std::jthread> consumers;
            for (int c = 0; c < 3; ++c)
                consumers.emplace_back([&] {
                    std::uint64_t s = 0, n = 0;
                    while (std::optional<std::uint64_t> v = q.pop()) s += *v, ++n;
                    sum.fetch_add(s);
                    count.fetch_add(n);
                });
            {
                std::vector<std::jthread> producers;
                for (std::uint64_t p = 0; p < 3; ++p)
                    producers.emplace_back([&, p] {
                        for (std::uint64_t i = 1; i <= kPer; ++i) (void)q.push(p * kPer + i);
                    });
            }
            q.close();
        }
        const std::uint64_t n = 3 * kPer;
        std::println("3 producers + 3 consumers, {} items through capacity 64: all received exactly once: {}", n,
                     count.load() == n && sum.load() == n * (n + 1) / 2 ? "yes" : "NO");
    }
}
```

```text
capacity 1: push ok true, second try_push_for(50ms) timed out true, push after close -> closed true
after close: pop() drains the backlog -> 1, then pop() -> nullopt (closed and empty)
3 producers + 3 consumers, 600000 items through capacity 64: all received exactly once: yes
```

* **Two condition variables**, `not_full_` and `not_empty_`, each with one kind of waiter, so `notify_one` always
  wakes a thread that can make progress (Folder 08, file 03, Chain 4).
* **`close()` semantics:** producers get `closed`; consumers get values until the backlog is empty and then
  `nullopt`. Both conditions are in the wait predicates, so closing can't be a lost wakeup.
* Follow-ups: *"Make it lock-free"* (P2's rings, bounded); *"Add batching"* (pop up to n per lock acquisition);
  *"priority"* (a heap instead of a deque; mind starvation).

### 1.2 P2 · Lock-free SPSC and MPMC ring buffers (Listing 11.2)

**Problem.** A bounded single-producer/single-consumer ring and a multi-producer/multi-consumer ring, with cache-line
alignment and sequence numbers.

```cpp
// p02_rings.cpp - P2: lock-free SPSC ring (cached indices) and Vyukov MPMC ring (per-slot sequence numbers)
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <print>
#include <thread>
#include <vector>

constexpr std::size_t kLine = 128;   // two 64-byte lines: also defeats the adjacent-line prefetcher (Folder 07)

template <class T, std::size_t N>
class SpscRing {   // wait-free: one release store per operation, an acquire load only when the cache says full/empty
    static_assert((N & (N - 1)) == 0);
    alignas(kLine) std::atomic<std::size_t> tail_{0};
    std::size_t head_cache_ = 0;   // producer's view of head
    alignas(kLine) std::atomic<std::size_t> head_{0};
    std::size_t tail_cache_ = 0;   // consumer's view of tail
    alignas(kLine) T slots_[N];

public:
    bool try_push(const T& v) {
        const std::size_t t = tail_.load(std::memory_order_relaxed);
        if (t - head_cache_ == N && t - (head_cache_ = head_.load(std::memory_order_acquire)) == N) return false;
        slots_[t & (N - 1)] = v;
        tail_.store(t + 1, std::memory_order_release);
        return true;
    }
    bool try_pop(T& v) {
        const std::size_t h = head_.load(std::memory_order_relaxed);
        if (h == tail_cache_ && h == (tail_cache_ = tail_.load(std::memory_order_acquire))) return false;
        v = slots_[h & (N - 1)];
        head_.store(h + 1, std::memory_order_release);
        return true;
    }
};

template <class T>
class MpmcRing {   // Vyukov: one CAS per operation on the position counter
    struct alignas(64) Cell {
        std::atomic<std::size_t> seq;
        T data;
    };
    const std::size_t mask_;
    std::unique_ptr<Cell[]> cells_;
    alignas(kLine) std::atomic<std::size_t> enq_{0};
    alignas(kLine) std::atomic<std::size_t> deq_{0};

public:
    explicit MpmcRing(std::size_t cap) : mask_(cap - 1), cells_(new Cell[cap]) {
        for (std::size_t i = 0; i < cap; ++i) cells_[i].seq.store(i, std::memory_order_relaxed);
    }
    bool try_push(const T& v) {
        std::size_t pos = enq_.load(std::memory_order_relaxed);
        for (;;) {
            Cell& c = cells_[pos & mask_];
            const auto diff = static_cast<std::intptr_t>(c.seq.load(std::memory_order_acquire)) -
                              static_cast<std::intptr_t>(pos);
            if (diff == 0 && enq_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                c.data = v;
                c.seq.store(pos + 1, std::memory_order_release);
                return true;
            }
            if (diff < 0) return false;   // full
            if (diff > 0) pos = enq_.load(std::memory_order_relaxed);
        }
    }
    bool try_pop(T& v) {
        std::size_t pos = deq_.load(std::memory_order_relaxed);
        for (;;) {
            Cell& c = cells_[pos & mask_];
            const auto diff = static_cast<std::intptr_t>(c.seq.load(std::memory_order_acquire)) -
                              static_cast<std::intptr_t>(pos + 1);
            if (diff == 0 && deq_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                v = c.data;
                c.seq.store(pos + mask_ + 1, std::memory_order_release);
                return true;
            }
            if (diff < 0) return false;   // empty
            if (diff > 0) pos = deq_.load(std::memory_order_relaxed);
        }
    }
};

int main() {
    {
        auto ring = std::make_unique<SpscRing<std::uint64_t, 1024>>();
        constexpr std::uint64_t n = 5'000'000;
        std::uint64_t sum = 0;
        bool ordered = true;
        {
            std::jthread consumer([&] {
                std::uint64_t v = 0, expect = 1;
                while (expect <= n)
                    if (ring->try_pop(v)) {
                        ordered &= (v == expect++);
                        sum += v;
                    }
            });
            for (std::uint64_t i = 1; i <= n;)
                if (ring->try_push(i)) ++i;
        }
        std::println("SPSC: {} items, FIFO order kept: {}, sum correct: {}", n, ordered ? "yes" : "NO",
                     sum == n * (n + 1) / 2 ? "yes" : "NO");
    }
    {
        MpmcRing<std::uint64_t> ring(1024);
        constexpr std::uint64_t per = 500'000;
        std::atomic<std::uint64_t> sum{0}, count{0};
        {
            std::vector<std::jthread> ts;
            for (std::uint64_t p = 0; p < 2; ++p)
                ts.emplace_back([&, p] {
                    for (std::uint64_t i = 1; i <= per;)
                        if (ring.try_push(p * per + i)) ++i;
                });
            for (int c = 0; c < 2; ++c)
                ts.emplace_back([&] {
                    std::uint64_t v = 0, s = 0;
                    while (count.load(std::memory_order_relaxed) < 2 * per)
                        if (ring.try_pop(v)) {
                            s += v;
                            count.fetch_add(1, std::memory_order_relaxed);
                        }
                    sum.fetch_add(s);
                });
        }
        const std::uint64_t n = 2 * per;
        std::println("MPMC: 2 producers + 2 consumers, {} items: every item once: {}", n,
                     count.load() == n && sum.load() == n * (n + 1) / 2 ? "yes" : "NO");
    }
}
```

```text
SPSC: 5000000 items, FIFO order kept: yes, sum correct: yes
MPMC: 2 producers + 2 consumers, 1000000 items: every item once: yes
```

* SPSC: no RMW, release/acquire on the indices, a cached copy of the other side's index. MPMC: Vyukov's per-slot
  sequence numbers, one CAS per operation. Folder 09 measures both, including the regime effects (a full ring makes
  caching useless) and the MPMC queue's blocking window.
* Follow-ups: *"Is the MPMC queue lock-free?"* (No: a producer stalled between claim and publish blocks consumers,
  Folder 09, file 02); *"why 128-byte alignment?"* (adjacent-line prefetch, Folder 07, file 04).

### 1.3 P3 · Work-stealing thread pool with `submit -> future` and `jthread` shutdown (Listing 11.3)

**Problem.** `submit(f, args...)` returns `std::future<R>`; tasks submitted from inside the pool go to the worker's
own deque; idle workers steal; destruction drains queued work and shuts down cooperatively.

```cpp
// p03_ws_pool.cpp - P3: work-stealing thread pool, submit(F&&, Args&&...) -> std::future<R>, jthread shutdown
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <print>
#include <stop_token>
#include <thread>
#include <tuple>
#include <type_traits>
#include <vector>

class WorkStealingPool {
    struct Task {   // type-erased, move-only: holds a packaged_task without std::function's copyability requirement
        virtual ~Task() = default;
        virtual void run() = 0;
    };
    template <class R>
    struct TaskImpl final : Task {
        std::packaged_task<R()> fn;
        explicit TaskImpl(std::packaged_task<R()> f) : fn(std::move(f)) {}
        void run() override { fn(); }
    };
    // Per-worker deques with a lock each: the owner works at the back (LIFO), thieves take from the front (FIFO).
    // (Folder 10's Chase-Lev deque removes even these uncontended locks; this version favours clarity.)
    struct alignas(128) Worker {
        std::mutex m;
        std::deque<std::unique_ptr<Task>> dq;
    };

public:
    explicit WorkStealingPool(unsigned n = std::max(1u, std::thread::hardware_concurrency() / 2)) : workers_(n) {
        for (unsigned i = 0; i < n; ++i)
            threads_.emplace_back([this, i](std::stop_token st) { run(i, st); });
    }
    // Drains every task already submitted; then ~jthread requests stop (which wakes idle workers through their
    // stop_token-aware wait) and joins.
    ~WorkStealingPool() {
        std::unique_lock lk(idle_m_);
        all_done_.wait(lk, [&] { return pending_.load() == 0; });
    }

    template <class F, class... Args>
    auto submit(F&& f, Args&&... args) -> std::future<std::invoke_result_t<F, Args...>> {
        using R = std::invoke_result_t<F, Args...>;
        std::packaged_task<R()> task(
            [fn = std::forward<F>(f), tup = std::make_tuple(std::forward<Args>(args)...)]() mutable {
                return std::apply(std::move(fn), std::move(tup));
            });
        std::future<R> fut = task.get_future();
        auto t = std::make_unique<TaskImpl<R>>(std::move(task));
        pending_.fetch_add(1, std::memory_order_relaxed);
        if (t_index >= 0 && t_owner == this) {   // submitted by one of our workers: its own deque, no shared lock
            std::scoped_lock lk(workers_[static_cast<std::size_t>(t_index)].m);
            workers_[static_cast<std::size_t>(t_index)].dq.push_back(std::move(t));
        } else {
            std::scoped_lock lk(inject_m_);
            inject_.push_back(std::move(t));
        }
        {
            std::scoped_lock lk(idle_m_);   // a new epoch: a worker that scanned before this push won't sleep
            ++epoch_;
        }
        idle_cv_.notify_one();
        return fut;
    }

private:
    std::unique_ptr<Task> find_task(unsigned self) {
        {
            Worker& w = workers_[self];
            std::scoped_lock lk(w.m);
            if (!w.dq.empty()) {
                auto t = std::move(w.dq.back());
                w.dq.pop_back();
                return t;
            }
        }
        {
            std::scoped_lock lk(inject_m_);
            if (!inject_.empty()) {
                auto t = std::move(inject_.front());
                inject_.pop_front();
                return t;
            }
        }
        for (std::size_t k = 1; k < workers_.size(); ++k) {   // steal the oldest task of another worker
            Worker& v = workers_[(self + k) % workers_.size()];
            std::scoped_lock lk(v.m);
            if (!v.dq.empty()) {
                auto t = std::move(v.dq.front());
                v.dq.pop_front();
                steals_.fetch_add(1, std::memory_order_relaxed);
                return t;
            }
        }
        return nullptr;
    }
    void run(unsigned self, std::stop_token st) {
        t_index = static_cast<int>(self);
        t_owner = this;
        while (!st.stop_requested()) {
            std::uint64_t seen;
            {
                std::scoped_lock lk(idle_m_);
                seen = epoch_;
            }
            if (std::unique_ptr<Task> t = find_task(self)) {
                t->run();                                        // exceptions are captured by packaged_task
                t.reset();
                if (pending_.fetch_sub(1, std::memory_order_acq_rel) == 1) {
                    std::scoped_lock lk(idle_m_);
                    all_done_.notify_all();
                }
                continue;
            }
            std::unique_lock lk(idle_m_);   // nothing anywhere: sleep until a submit (new epoch) or a stop request
            idle_cv_.wait(lk, st, [&] { return epoch_ != seen; });
        }
    }

    std::vector<Worker> workers_;
    std::mutex inject_m_;
    std::deque<std::unique_ptr<Task>> inject_;
    std::mutex idle_m_;
    std::condition_variable_any idle_cv_;   // the stop_token overload of wait(): shutdown can't be a lost wakeup
    std::condition_variable all_done_;
    std::uint64_t epoch_ = 0;               // bumped by every submit, under idle_m_
    std::atomic<std::int64_t> pending_{0};

public:
    std::atomic<std::uint64_t> steals_{0};

private:
    static inline thread_local int t_index = -1;
    static inline thread_local WorkStealingPool* t_owner = nullptr;
    std::vector<std::jthread> threads_;   // last member: joined before the queues above are destroyed
};

int main() {
    std::uint64_t total = 0, expected = 0;
    std::uint64_t steals = 0;
    bool error_propagated = false;
    {
        WorkStealingPool pool(4);
        std::vector<std::future<std::uint64_t>> results;
        for (std::uint64_t i = 1; i <= 20'000; ++i) {
            expected += i * 2;
            results.push_back(pool.submit([&pool](std::uint64_t x) {
                // Each task spawns a child into its own worker's deque (no shared lock) and doesn't wait for it.
                (void)pool.submit([] {});
                return x * 2;
            }, i));
        }
        for (auto& f : results) total += f.get();
        auto failing = pool.submit([]() -> int { throw std::runtime_error("task failed"); });
        try {
            (void)failing.get();
        } catch (const std::runtime_error&) {
            error_propagated = true;
        }
        steals = pool.steals_.load();
    }   // ~WorkStealingPool: drains the 20,000 child tasks, then stops and joins the workers
    std::println("20,000 tasks (+20,000 spawned children) on 4 workers: results correct: {}; exception reached get(): {}; "
                 "stole at least one task: {}",
                 total == expected ? "yes" : "NO", error_propagated ? "yes" : "no", steals > 0 ? "yes" : "no");
}
```

```text
20,000 tasks (+20,000 spawned children) on 4 workers: results correct: yes; exception reached get(): yes; stole at least one task: yes
```

* **Type erasure without copyability:** `std::packaged_task` is move-only, so a small virtual `Task` interface holds
  it (`std::function` requires copyable targets; C++23 `std::move_only_function` would also work).
* **The shutdown race in the first draft.** Idle workers slept on a `condition_variable` with a predicate that
  checked the stop token. A worker could test the predicate, then the destructor's `request_stop()` + `notify_all()`
  could happen before the worker blocked: a lost wakeup and a hung destructor. The fix uses
  `condition_variable_any::wait(lock, stop_token, pred)`, which handles stop requests atomically (Folder 08, file 01),
  and a submit *epoch*, so a submit between a worker's scan and its sleep is never missed.
* **Members in destruction order:** `threads_` is declared last, so the workers are joined before the queues they use
  are destroyed.
* Per-worker locks keep this readable; Folder 10's Chase-Lev deque removes them. Follow-up: *"a task waits on another
  task's future"*, the starvation deadlock of Folder 10 file 01's Chain 8. Answer with help-while-waiting or
  continuations.

### 1.4 P4 · Reader-writer lock with writer preference (Listing 11.4)

**Problem.** Many readers or one writer, and a writer must not starve under a continuous stream of readers.

```cpp
// p04_rwlock_writer_pref.cpp - P4: a reader-writer lock with WRITER preference, vs reader preference under constant reads
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

using namespace std::chrono_literals;

template <bool PreferWriters>
class RwLock {
    std::mutex m_;
    std::condition_variable readers_cv_, writers_cv_;
    int active_readers_ = 0;
    int waiting_writers_ = 0;
    bool writer_active_ = false;

public:
    void lock_shared() {
        std::unique_lock lk(m_);
        // Writer preference: a WAITING writer also closes the door to new readers.
        readers_cv_.wait(lk, [&] { return !writer_active_ && (!PreferWriters || waiting_writers_ == 0); });
        ++active_readers_;
    }
    void unlock_shared() {
        std::unique_lock lk(m_);
        if (--active_readers_ == 0 && waiting_writers_ > 0) {
            lk.unlock();
            writers_cv_.notify_one();
        }
    }
    void lock() {
        std::unique_lock lk(m_);
        ++waiting_writers_;
        writers_cv_.wait(lk, [&] { return !writer_active_ && active_readers_ == 0; });
        --waiting_writers_;
        writer_active_ = true;
    }
    void unlock() {
        std::unique_lock lk(m_);
        writer_active_ = false;
        const bool writers_next = PreferWriters && waiting_writers_ > 0;
        lk.unlock();
        if (writers_next) writers_cv_.notify_one();   // hand over to the next writer first
        else {
            readers_cv_.notify_all();
            writers_cv_.notify_one();
        }
    }
};

// 3 readers keep the lock continuously read-held (each holds it 2 ms, staggered so they overlap);
// one writer tries to get in. How many times does it succeed in 300 ms?
template <class Lock>
int writer_acquisitions() {
    Lock lk;
    std::atomic<bool> stop{false};
    std::atomic<int> writes{0};
    {
        std::vector<std::jthread> readers;
        for (int r = 0; r < 3; ++r)
            readers.emplace_back([&, r] {
                std::this_thread::sleep_for(std::chrono::milliseconds(r));   // stagger
                while (!stop.load()) {
                    lk.lock_shared();
                    std::this_thread::sleep_for(2ms);
                    lk.unlock_shared();
                }
            });
        std::jthread writer([&] {
            std::this_thread::sleep_for(20ms);
            while (!stop.load()) {
                lk.lock();
                writes.fetch_add(1);
                lk.unlock();
                std::this_thread::sleep_for(1ms);
            }
        });
        std::this_thread::sleep_for(300ms);
        stop = true;
    }
    return writes.load();
}

int main() {
    const int rp = writer_acquisitions<RwLock<false>>();
    const int wp = writer_acquisitions<RwLock<true>>();
    std::println("writer acquisitions in 300 ms against 3 overlapping readers:");
    std::println("  reader-preferring lock: {:>3} -> writer starved: {}", rp, rp <= 2 ? "yes" : "no");
    std::println("  writer-preferring lock: {:>3} -> writer starved: {}", wp, wp <= 2 ? "yes" : "no");
}
```

```text
writer acquisitions in 300 ms against 3 overlapping readers:
  reader-preferring lock:   1 -> writer starved: yes
  writer-preferring lock:  11 -> writer starved: no
```

* The only difference between the two policies is one condition in `lock_shared`: with writer preference, a
  *waiting* writer closes the door to new readers. With 3 overlapping readers, the reader-preferring lock admitted the
  writer at most once in 300 ms (starved); the writer-preferring one 11–12 times. The writer's own 1 ms sleeps between
  attempts, at Windows timer granularity, limit that number.
* The price: writer preference can starve *readers* under a continuous stream of writers. Phase-fair locks alternate.
  `std::shared_mutex` promises neither policy (Folder 08, file 02).

### 1.5 P5 · Concurrent sharded LRU cache (Listing 11.5)

**Problem.** `get`/`put` with O(1) LRU eviction, safe under concurrency, scaling beyond one lock.

```cpp
// p05_sharded_lru.cpp - P5: concurrent sharded LRU cache: lock striping + intrusive doubly-linked list + O(1) eviction
#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

template <class K, class V>
class LruShard {
    struct Node {   // intrusive list node: no separate list allocation, O(1) unlink from anywhere
        K key;
        V value;
        Node* prev = nullptr;
        Node* next = nullptr;
    };
    std::size_t cap_;
    std::unordered_map<K, std::unique_ptr<Node>> map_;
    Node* head_ = nullptr;   // most recently used
    Node* tail_ = nullptr;   // least recently used

    void unlink(Node* n) {
        (n->prev ? n->prev->next : head_) = n->next;
        (n->next ? n->next->prev : tail_) = n->prev;
        n->prev = n->next = nullptr;
    }
    void push_front(Node* n) {
        n->next = head_;
        if (head_) head_->prev = n;
        head_ = n;
        if (!tail_) tail_ = n;
    }

public:
    explicit LruShard(std::size_t cap) : cap_(cap) {}
    std::optional<V> get(const K& k) {
        auto it = map_.find(k);
        if (it == map_.end()) return std::nullopt;
        Node* n = it->second.get();
        unlink(n);
        push_front(n);           // touch: O(1)
        return n->value;
    }
    void put(const K& k, V v) {
        if (auto it = map_.find(k); it != map_.end()) {
            it->second->value = std::move(v);
            unlink(it->second.get());
            push_front(it->second.get());
            return;
        }
        if (map_.size() == cap_) {   // evict the least recently used: O(1)
            Node* victim = tail_;
            unlink(victim);
            map_.erase(victim->key);
        }
        auto node = std::make_unique<Node>(Node{k, std::move(v)});
        push_front(node.get());
        map_.emplace(k, std::move(node));
    }
    std::size_t size() const { return map_.size(); }
};

template <class K, class V>
class ShardedLru {
    struct alignas(128) Shard {   // one lock per shard, on its own cache line (lock striping)
        std::mutex m;
        LruShard<K, V> lru;
        explicit Shard(std::size_t cap) : lru(cap) {}
    };
    std::vector<std::unique_ptr<Shard>> shards_;
    // Mix before choosing a shard: std::hash<integer> is the identity in both libraries, so structured keys
    // (all odd, all multiples of 16, ...) would land in a few shards. Without this, only 8 of 16 shards filled.
    Shard& shard_for(const K& k) {
        std::uint64_t h = std::hash<K>{}(k);
        h ^= h >> 33;
        h *= 0xff51afd7ed558ccdULL;
        h ^= h >> 33;
        return *shards_[h % shards_.size()];
    }

public:
    ShardedLru(std::size_t shards, std::size_t cap_per_shard) {
        for (std::size_t i = 0; i < shards; ++i) shards_.push_back(std::make_unique<Shard>(cap_per_shard));
    }
    std::optional<V> get(const K& k) {
        Shard& s = shard_for(k);
        std::scoped_lock lk(s.m);
        return s.lru.get(k);
    }
    void put(const K& k, V v) {
        Shard& s = shard_for(k);
        std::scoped_lock lk(s.m);
        s.lru.put(k, std::move(v));
    }
    std::size_t size() {
        std::size_t n = 0;
        for (auto& s : shards_) {
            std::scoped_lock lk(s->m);
            n += s->lru.size();
        }
        return n;
    }
};

int main() {
    // LRU order, single shard, capacity 2.
    {
        LruShard<std::string, int> lru(2);
        lru.put("a", 1);
        lru.put("b", 2);
        (void)lru.get("a");   // a becomes most recently used
        lru.put("c", 3);      // evicts b, the least recently used
        std::println("capacity 2: put a, put b, get a, put c -> a {}, b {}, c {}", lru.get("a") ? "kept" : "evicted",
                     lru.get("b") ? "kept" : "evicted", lru.get("c") ? "kept" : "evicted");
    }
    // 4 threads, mixed get/put over 10,000 keys, 16 shards x 256 entries.
    {
        ShardedLru<std::uint64_t, std::uint64_t> cache(16, 256);
        std::atomic<std::uint64_t> wrong{0};
        {
            std::vector<std::jthread> ts;
            for (std::uint64_t t = 0; t < 4; ++t)
                ts.emplace_back([&, t] {
                    std::uint64_t x = 88172645463325252ULL + t, bad = 0;
                    for (int i = 0; i < 200'000; ++i) {
                        x ^= x << 13, x ^= x >> 7, x ^= x << 17;
                        const std::uint64_t k = x % 10'000;
                        if ((x >> 40) & 1) cache.put(k, k * 7);   // decision independent of the key's bits
                        else if (auto v = cache.get(k); v && *v != k * 7) ++bad;
                    }
                    wrong.fetch_add(bad);
                });
        }
        std::println("4 threads x 200,000 ops: wrong values {}, size {} <= capacity 4096: {}", wrong.load(), cache.size(),
                     cache.size() <= 16 * 256 ? "yes" : "NO");
    }
}
```

```text
capacity 2: put a, put b, get a, put c -> a kept, b evicted, c kept
4 threads x 200,000 ops: wrong values 0, size 4096 <= capacity 4096: yes
```

* **Per shard:** a hash map from key to an intrusive list node, plus the list in recency order. Touch = unlink +
  push-front, eviction = pop-back, all O(1). **Across shards:** lock striping, one mutex per shard on its own cache line.
* **The bug the first run found.** The shard index was `std::hash<K>{}(k) % shards`. `std::hash` of an integer is the
  identity in both libraries, and the test happened to insert only odd keys, so only 8 of 16 shards were ever used: the
  cache held 2,048 entries out of 4,096. Mixing the hash before choosing a shard fixed it (4,096 now). Real keys are
  often structured (ids that are multiples of something), so mixing is not optional.
* LRU is per shard: global recency is approximate. That's the standard trade (it's how memcached-style caches scale).

### 1.6 P6 · Token-bucket and sliding-window rate limiters, lock-free (Listing 11.6)

**Problem.** A rate limiter with bursts, safe from many threads without a lock.

```cpp
// p06_rate_limiter.cpp - P6: lock-free token bucket and sliding-window limiters, each one packed 64-bit atomic + CAS
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <print>
#include <thread>
#include <vector>

using Clock = std::uint64_t (*)();   // microseconds; injected so tests can drive time deterministically

// ---- token bucket: state = (refill timestamp in us : 40 bits) | (tokens : 24 bits) ----
class TokenBucket {
    static constexpr std::uint64_t kTokMask = (std::uint64_t{1} << 24) - 1;
    std::atomic<std::uint64_t> state_;
    const std::uint64_t rate_, burst_;   // tokens per second, bucket size
    Clock now_;
    static std::uint64_t pack(std::uint64_t ts, std::uint64_t tok) { return (ts << 24) | tok; }

public:
    TokenBucket(std::uint64_t rate_per_s, std::uint64_t burst, Clock now)
        : state_(pack(now(), burst)), rate_(rate_per_s), burst_(burst), now_(now) {}
    bool try_acquire(std::uint64_t n = 1) {
        std::uint64_t old = state_.load(std::memory_order_relaxed);
        for (;;) {
            const std::uint64_t now = now_();
            std::uint64_t ts = old >> 24, tokens = old & kTokMask;
            if (now > ts) {
                const std::uint64_t add = (now - ts) * rate_ / 1'000'000;   // whole tokens earned since ts
                if (add > 0) {
                    tokens = std::min(burst_, tokens + add);
                    ts = tokens == burst_ ? now : ts + add * 1'000'000 / rate_;   // keep the fractional remainder
                }
            }
            if (tokens < n) return false;
            if (state_.compare_exchange_weak(old, pack(ts, tokens - n), std::memory_order_relaxed)) return true;
        }   // CAS failed: another thread changed tokens or ts; `old` was refreshed, recompute from it
    }
};

// ---- sliding-window counter: state = (window index : 24) | (previous window count : 20) | (current count : 20) ----
// Estimate of the last W microseconds = prev * (fraction of the previous window still inside) + curr.
class SlidingWindow {
    static constexpr std::uint64_t kM = (std::uint64_t{1} << 20) - 1;
    std::atomic<std::uint64_t> state_{0};
    const std::uint64_t window_us_, limit_;
    Clock now_;

public:
    SlidingWindow(std::uint64_t window_us, std::uint64_t limit, Clock now)
        : window_us_(window_us), limit_(limit), now_(now) {
        state_.store(((now() / window_us) & 0xFF'FFFF) << 40);
    }
    bool try_acquire() {
        std::uint64_t old = state_.load(std::memory_order_relaxed);
        for (;;) {
            const std::uint64_t now = now_();
            const std::uint64_t w = (now / window_us_) & 0xFF'FFFF, into = now % window_us_;
            std::uint64_t idx = old >> 40, prev = (old >> 20) & kM, curr = old & kM;
            if (w != idx) {   // rotate: the current window becomes "previous" (or zero if we skipped windows)
                prev = (w == ((idx + 1) & 0xFF'FFFF)) ? curr : 0;
                curr = 0;
                idx = w;
            }
            const std::uint64_t estimate = prev * (window_us_ - into) / window_us_ + curr;
            if (estimate + 1 > limit_) return false;
            if (state_.compare_exchange_weak(old, (idx << 40) | (prev << 20) | (curr + 1), std::memory_order_relaxed))
                return true;
        }
    }
};

std::atomic<std::uint64_t> g_fake_us{0};
std::uint64_t fake_clock() { return g_fake_us.load(); }
std::uint64_t real_clock() {
    static const auto t0 = std::chrono::steady_clock::now();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count());
}

int main() {
    // Deterministic: token bucket, 10 tokens/s, burst 5.
    {
        g_fake_us = 1'000'000;
        TokenBucket tb(10, 5, &fake_clock);
        int burst_ok = 0;
        for (int i = 0; i < 6; ++i) burst_ok += tb.try_acquire() ? 1 : 0;
        g_fake_us += 100'000;   // +100 ms earns exactly 1 token
        const bool one_more = tb.try_acquire(), then_empty = !tb.try_acquire();
        g_fake_us += 10'000'000;   // +10 s: refills only up to the burst
        int after_idle = 0;
        for (int i = 0; i < 10; ++i) after_idle += tb.try_acquire() ? 1 : 0;
        std::println("token bucket 10/s, burst 5: first 6 requests -> {} granted; +100 ms -> 1 more: {}, then empty: {}; "
                     "after 10 s idle -> {} granted (capped at the burst)",
                     burst_ok, one_more, then_empty, after_idle);
    }
    // Deterministic: sliding window, 100 per 1 s.
    {
        g_fake_us = 5'000'000;   // the start of a window
        SlidingWindow sw(1'000'000, 100, &fake_clock);
        int first = 0;
        for (int i = 0; i < 150; ++i) first += sw.try_acquire() ? 1 : 0;
        g_fake_us += 1'500'000;   // halfway into the next window: half of the previous 100 still counts
        int half = 0;
        for (int i = 0; i < 150; ++i) half += sw.try_acquire() ? 1 : 0;
        std::println("sliding window 100/s: 150 requests at once -> {} granted; 1.5 s later -> {} granted "
                     "(50 of the previous window's 100 still inside)",
                     first, half);
    }
    // Concurrent: 4 threads hammer a real-clock bucket (100,000/s, burst 1,000) for ~200 ms.
    {
        TokenBucket tb(100'000, 1'000, &real_clock);
        const std::uint64_t t0 = real_clock();
        std::atomic<std::uint64_t> granted{0};
        {
            std::vector<std::jthread> ts;
            for (int t = 0; t < 4; ++t)
                ts.emplace_back([&] {
                    std::uint64_t g = 0;
                    while (real_clock() - t0 < 200'000)
                        if (tb.try_acquire()) ++g;
                    granted.fetch_add(g);
                });
        }
        const std::uint64_t elapsed = real_clock() - t0;
        const std::uint64_t allowance = 1'000 + elapsed * 100'000 / 1'000'000 + 1;
        std::println("4 threads, real clock, {} us: granted {} of an allowance of {} -> never over the limit: {}", elapsed,
                     granted.load(), allowance, granted.load() <= allowance ? "yes" : "NO");
    }
}
```

```text
token bucket 10/s, burst 5: first 6 requests -> 5 granted; +100 ms -> 1 more: true, then empty: true; after 10 s idle -> 5 granted (capped at the burst)
sliding window 100/s: 150 requests at once -> 100 granted; 1.5 s later -> 50 granted (50 of the previous window's 100 still inside)
4 threads, real clock, 200258 us: granted 20900 of an allowance of 21026 -> never over the limit: yes
```

* **The whole state is one 64-bit word** (timestamp | tokens, or window index | previous | current), so one CAS updates
  it consistently. A failed CAS returns the fresh state, and the thread recomputes from it. There is no lock and no
  torn state.
* **Keep the fractional time.** The refill advances the timestamp only by the time that "paid" for the whole tokens
  added (`ts + add * 1e6 / rate`). Setting it to `now` instead would silently lose up to one token interval per refill.
  When the bucket is full the timestamp jumps to `now`, so idle time can't bank beyond the burst.
* **An injected clock** makes the behaviour testable exactly: 5 of 6 granted, 1 more after 100 ms, then empty; 100 of
  150 in a window, and 50 more halfway into the next. Under 4 contending threads the real-clock bucket never exceeded
  its allowance (`burst + rate × elapsed`).
* Follow-ups: *"distributed rate limiting"* (Redis/CAS with the same packed state, or per-node budgets);
  *"fairness between clients"* (a bucket per client in a sharded map).

### 1.7 P7 · Hierarchical timing wheel with O(1) cancel (Listing 11.7)

**Problem.** Millions of timers (timeouts, retries) with O(1) schedule and cancel, one ticker thread, callbacks run on
workers.

```cpp
// p07_timing_wheel.cpp - P7: hierarchical timing wheel: O(1) schedule and cancel, one ticker thread, worker dispatch
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <print>
#include <random>
#include <thread>
#include <vector>

// Two levels (Varghese & Lauck): 256 slots of 1 tick, 64 slots of 256 ticks (horizon 16,384 ticks), and an
// overflow list for longer delays. Timers are intrusive list nodes in a pool; an id = (index, generation).
class TimingWheel {
public:
    struct TimerId {
        std::uint32_t index, gen;
    };
    using Callback = std::function<void(std::uint64_t fired_at)>;

    explicit TimingWheel(std::size_t max_timers) : nodes_(max_timers) {
        for (std::uint32_t i = 0; i < nodes_.size(); ++i) free_.push_back(i);
        std::fill(std::begin(l0_), std::end(l0_), kNil);
        std::fill(std::begin(l1_), std::end(l1_), kNil);
    }
    TimerId schedule(std::uint64_t delay_ticks, Callback cb) {   // O(1)
        std::scoped_lock lk(m_);
        const std::uint32_t i = free_.back();
        free_.pop_back();
        Node& n = nodes_[i];
        n.expire = now_ + std::max<std::uint64_t>(delay_ticks, 1);
        n.cb = std::move(cb);
        n.armed = true;
        insert(i);
        return {i, n.gen};
    }
    bool cancel(TimerId id) {   // O(1): unlink from whatever slot holds it
        std::scoped_lock lk(m_);
        Node& n = nodes_[id.index];
        if (!n.armed || n.gen != id.gen) return false;   // already fired, cancelled, or the slot was reused
        unlink(id.index);
        release(id.index);
        return true;
    }
    // Advance one tick; returns the callbacks that expired (run by the caller, outside the lock).
    std::vector<std::pair<Callback, std::uint64_t>> tick() {
        std::vector<std::pair<Callback, std::uint64_t>> due;
        std::scoped_lock lk(m_);
        ++now_;
        if ((now_ & 255) == 0) {   // level 0 wrapped: cascade one level-1 slot down into level 0
            cascade(l1_[(now_ >> 8) & 63]);
            if ((now_ & 16383) == 0) cascade(overflow_);
        }
        std::uint32_t i = l0_[now_ & 255];
        while (i != kNil) {
            const std::uint32_t next = nodes_[i].next;
            if (nodes_[i].expire == now_) {
                unlink(i);
                due.emplace_back(std::move(nodes_[i].cb), now_);
                release(i);
            }
            i = next;
        }
        return due;
    }
    std::uint64_t now() {
        std::scoped_lock lk(m_);
        return now_;
    }

private:
    static constexpr std::uint32_t kNil = 0xFFFF'FFFF;
    struct Node {
        std::uint32_t prev = kNil, next = kNil, gen = 0;
        std::uint32_t* head = nullptr;   // the list this node is in
        std::uint64_t expire = 0;
        bool armed = false;
        Callback cb;
    };
    void insert(std::uint32_t i) {
        Node& n = nodes_[i];
        const std::uint64_t delta = n.expire - now_;
        std::uint32_t* head = delta < 256          ? &l0_[n.expire & 255]
                              : delta < 256 * 64   ? &l1_[(n.expire >> 8) & 63]
                                                   : &overflow_;
        n.head = head;
        n.prev = kNil;
        n.next = *head;
        if (*head != kNil) nodes_[*head].prev = i;
        *head = i;
    }
    void unlink(std::uint32_t i) {
        Node& n = nodes_[i];
        (n.prev != kNil ? nodes_[n.prev].next : *n.head) = n.next;
        if (n.next != kNil) nodes_[n.next].prev = n.prev;
        n.prev = n.next = kNil;
        n.head = nullptr;
    }
    void release(std::uint32_t i) {
        nodes_[i].armed = false;
        ++nodes_[i].gen;   // stale TimerIds can no longer cancel the reused node
        nodes_[i].cb = nullptr;
        free_.push_back(i);
    }
    void cascade(std::uint32_t& list) {
        std::uint32_t i = list;
        list = kNil;
        while (i != kNil) {
            const std::uint32_t next = nodes_[i].next;
            insert(i);   // closer now: lands in a finer slot
            i = next;
        }
    }

    std::mutex m_;
    std::uint64_t now_ = 0;
    std::vector<Node> nodes_;
    std::vector<std::uint32_t> free_;
    std::uint32_t l0_[256];
    std::uint32_t l1_[64];
    std::uint32_t overflow_ = kNil;
};

int main() {
    // Deterministic: 3,000 timers with delays up to 40,000 ticks (beyond the 16,384-tick horizon too),
    // every third one cancelled; advance 40,001 ticks by hand and check every firing.
    {
        TimingWheel wheel(4096);
        std::mt19937_64 rng(42);
        std::vector<std::uint64_t> expect(3000), fired_at(3000, 0);
        std::vector<TimingWheel::TimerId> ids;
        for (std::size_t k = 0; k < 3000; ++k) {
            expect[k] = 1 + rng() % 40'000;
            ids.push_back(wheel.schedule(expect[k], [&, k](std::uint64_t at) { fired_at[k] = at; }));
        }
        int cancelled = 0;
        for (std::size_t k = 0; k < 3000; k += 3) cancelled += wheel.cancel(ids[k]) ? 1 : 0;
        const bool stale_cancel_rejected = !wheel.cancel(ids[0]);
        for (int t = 0; t < 40'001; ++t)
            for (auto& [cb, at] : wheel.tick()) cb(at);
        int on_time = 0, wrong = 0;
        for (std::size_t k = 0; k < 3000; ++k) {
            if (k % 3 == 0) wrong += fired_at[k] != 0;          // cancelled: must not fire
            else if (fired_at[k] == expect[k]) ++on_time;
            else ++wrong;
        }
        std::println("3,000 timers up to 40,000 ticks, {} cancelled: {} fired exactly on their tick, {} wrong; "
                     "double cancel rejected: {}",
                     cancelled, on_time, wrong, stale_cancel_rejected);
    }
    // Real time: a ticker thread (1 tick = 1 ms) hands expired callbacks to 2 workers.
    {
        TimingWheel wheel(64);
        std::mutex qm;
        std::condition_variable qcv;
        std::deque<std::function<void()>> work;
        bool stop = false;
        std::mutex om;
        std::vector<int> order;
        {
            std::vector<std::jthread> workers;
            for (int w = 0; w < 2; ++w)
                workers.emplace_back([&] {
                    for (;;) {
                        std::function<void()> job;
                        {
                            std::unique_lock lk(qm);
                            qcv.wait(lk, [&] { return stop || !work.empty(); });
                            if (work.empty()) return;
                            job = std::move(work.front());
                            work.pop_front();
                        }
                        job();
                    }
                });
            auto record = [&](int id) {
                return [&, id](std::uint64_t) {
                    std::scoped_lock lk(om);
                    order.push_back(id);
                };
            };
            (void)wheel.schedule(30, record(3));
            const TimingWheel::TimerId mid = wheel.schedule(20, record(2));
            (void)wheel.schedule(10, record(1));
            (void)wheel.cancel(mid);
            {
                std::jthread ticker([&](std::stop_token st) {
                    while (!st.stop_requested() && wheel.now() < 40) {
                        std::this_thread::sleep_for(std::chrono::milliseconds(1));
                        for (auto& [cb, at] : wheel.tick()) {
                            {
                                std::scoped_lock lk(qm);
                                work.push_back([f = std::move(cb), t = at] { f(t); });
                            }
                            qcv.notify_one();
                        }
                    }
                });
                ticker.join();   // join(), not ~jthread: the destructor would request stop before tick 40
            }
            {
                std::scoped_lock lk(qm);
                stop = true;
            }
            qcv.notify_all();
        }
        std::println("real-time wheel: timers 10, 20 (cancelled), 30 ticks -> fired in order {}", order);
    }
}
```

```text
3,000 timers up to 40,000 ticks, 1000 cancelled: 2000 fired exactly on their tick, 0 wrong; double cancel rejected: true
real-time wheel: timers 10, 20 (cancelled), 30 ticks -> fired in order [1, 3]
```

* **Two levels** (Varghese & Lauck): 256 one-tick slots and 64 slots of 256 ticks, plus an overflow list beyond 16,384
  ticks. When level 0 wraps, one level-1 slot cascades down. Timers are intrusive doubly-linked nodes in a pool, so
  cancel is an unlink. A **generation counter** in the id makes cancelling a fired or reused timer a safe no-op.
* **Callbacks run outside the wheel's lock**: `tick()` collects them, and the ticker hands them to workers. A callback
  that schedules or cancels timers would otherwise deadlock on the wheel's mutex.
* **The bug in the first demo:** the ticker was a `std::jthread` inside a block that ended immediately, and
  `~jthread` requests stop *before* joining, so the ticker stopped at tick 0 and nothing fired. `join()` waits without
  requesting stop. It is the same `jthread` semantics Folder 08 file 01 describes, met in practice.

### 1.8 P8 · Asynchronous MPSC logger with a non-blocking hot path (Listing 11.8)

**Problem.** Many threads log at high rate; logging must never block them; one thread drains to the sink.

```cpp
// p08_mpsc_logger.cpp - P8: async logger: per-thread SPSC rings, one drain thread, no blocking on the hot path
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <print>
#include <string>
#include <thread>
#include <vector>

struct Record {   // fixed size: the hot path copies bytes, it never allocates or formats
    std::uint64_t seq;
    std::uint32_t thread;
    std::uint32_t len;
    char text[48];
};

template <class T, std::size_t N>
class SpscRing {   // Folder 09, Listing 9.3, compact
    alignas(128) std::atomic<std::size_t> tail_{0};
    std::size_t head_cache_ = 0;
    alignas(128) std::atomic<std::size_t> head_{0};
    std::size_t tail_cache_ = 0;
    alignas(128) T slots_[N];

public:
    bool try_push(const T& v) {
        const std::size_t t = tail_.load(std::memory_order_relaxed);
        if (t - head_cache_ == N && t - (head_cache_ = head_.load(std::memory_order_acquire)) == N) return false;
        slots_[t & (N - 1)] = v;
        tail_.store(t + 1, std::memory_order_release);
        return true;
    }
    bool try_pop(T& v) {
        const std::size_t h = head_.load(std::memory_order_relaxed);
        if (h == tail_cache_ && h == (tail_cache_ = tail_.load(std::memory_order_acquire))) return false;
        v = slots_[h & (N - 1)];
        head_.store(h + 1, std::memory_order_release);
        return true;
    }
};

class Logger {
    struct Channel {
        SpscRing<Record, 16384> ring;   // sized for bursts: 16,384 x 64 B = 1 MB per thread
        alignas(128) std::atomic<std::uint64_t> dropped{0};   // written only by the producing thread
        std::uint32_t id = 0;
        std::uint64_t next_seq = 0;                           // producer-private
    };
    static constexpr std::size_t kMaxThreads = 16;
    std::array<std::unique_ptr<Channel>, kMaxThreads> channels_;
    std::atomic<std::size_t> registered_{0};
    std::atomic<std::size_t> claim_{0};
    std::atomic<bool> stop_{false};
    std::jthread drain_;

    Channel& my_channel() {
        thread_local Channel* mine = nullptr;   // one registration per thread, then a plain TLS read
        if (!mine) {
            const std::size_t slot = claim_.fetch_add(1);
            channels_[slot] = std::make_unique<Channel>();
            channels_[slot]->id = static_cast<std::uint32_t>(slot);
            mine = channels_[slot].get();
            std::size_t expected = slot;   // publish slots in order so the drain thread sees a prefix
            while (!registered_.compare_exchange_weak(expected, slot + 1, std::memory_order_release)) expected = slot;
        }
        return *mine;
    }

public:
    // The sink: here, per-thread counters and an order check instead of a file.
    std::array<std::uint64_t, kMaxThreads> received{};
    std::array<bool, kMaxThreads> in_order{};

    Logger() {
        in_order.fill(true);
        drain_ = std::jthread([this] {
            std::array<std::uint64_t, kMaxThreads> last{};
            Record r;
            int idle_rounds = 0;
            for (;;) {
                bool any = false;
                const std::size_t n = registered_.load(std::memory_order_acquire);
                for (std::size_t i = 0; i < n; ++i)
                    while (channels_[i]->ring.try_pop(r)) {   // a real logger formats and write()s a batch here
                        any = true;
                        if (received[i]++ && r.seq <= last[i]) in_order[i] = false;   // gaps = drops; never reorder
                        last[i] = r.seq;
                    }
                if (any) {
                    idle_rounds = 0;
                } else {
                    if (stop_.load(std::memory_order_acquire)) break;
                    // Idle: yield for a while (bursts arrive faster than an OS sleep returns: a Windows sleep is
                    // ~1 ms, enough for a thread to fill its ring), then sleep.
                    if (++idle_rounds < 2'000) std::this_thread::yield();
                    else std::this_thread::sleep_for(std::chrono::microseconds(200));
                }
            }
        });
    }
    ~Logger() { flush_and_stop(); }
    void flush_and_stop() {
        stop_.store(true, std::memory_order_release);
        if (drain_.joinable()) drain_.join();   // drains everything already queued before exiting
    }
    // Hot path: no lock, no allocation, no formatting, no blocking. When the ring is full the record is dropped
    // and counted: a logger must never stall the thread it observes.
    void log(const char* msg) {
        Channel& ch = my_channel();
        Record r;
        r.seq = ch.next_seq++;
        r.thread = ch.id;
        r.len = static_cast<std::uint32_t>(std::min<std::size_t>(std::strlen(msg), sizeof r.text));
        std::memcpy(r.text, msg, r.len);
        if (!ch.ring.try_push(r)) ch.dropped.store(ch.dropped.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
    }
    std::uint64_t dropped(std::size_t i) const { return channels_[i] ? channels_[i]->dropped.load() : 0; }
};

int main() {
    constexpr int kThreads = 4, kPer = 200'000;
    Logger log;
    double ns_per_call = 0;
    {
        std::vector<std::jthread> ts;
        std::atomic<std::int64_t> total_ns{0};
        for (int t = 0; t < kThreads; ++t)
            ts.emplace_back([&] {
                const auto t0 = std::chrono::steady_clock::now();
                for (int i = 0; i < kPer; ++i) log.log("order filled: AAPL 100 @ 189.25");
                total_ns.fetch_add(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count());
            });
        ts.clear();
        ns_per_call = static_cast<double>(total_ns.load()) / (kThreads * kPer);
    }
    log.flush_and_stop();
    std::uint64_t got = 0, lost = 0;
    bool ordered = true;
    for (std::size_t i = 0; i < kThreads; ++i) {
        got += log.received[i];
        lost += log.dropped(i);
        ordered &= log.in_order[i];
    }
    std::println("{} threads x {} records: delivered + dropped == produced: {}; per-thread order kept: {}",
                 kThreads, kPer, got + lost == std::uint64_t{kThreads} * kPer ? "yes" : "NO", ordered ? "yes" : "NO");
    std::println("hot path {:.1f} ns per log() call; delivered {}, dropped {} (ring full)", ns_per_call, got, lost);
}
```

GCC, then Clang:

```text
4 threads x 200000 records: delivered + dropped == produced: yes; per-thread order kept: yes
hot path 7.3 ns per log() call; delivered 454676, dropped 345324 (ring full)
4 threads x 200000 records: delivered + dropped == produced: yes; per-thread order kept: yes
hot path 23.9 ns per log() call; delivered 800000, dropped 0 (ring full)
```

* **One SPSC ring per producer thread** (registered once, then a TLS pointer) instead of one MPMC queue: producers
  never contend with each other. The hot path is a fixed-size `memcpy` and a release store: 7–11 ns with GCC, 22–24 ns
  with Clang here.
* **Full ring = drop and count, never block.** A logger that blocks makes the system it observes slower exactly
  when it is under stress. The invariant is "delivered + dropped = produced", and it held in every run.
* **Drops depend on the drain thread's wake-up latency.** The first version slept 50 µs when idle, which on Windows is
  about 1 ms, enough for a fast producer to fill a 4,096-slot ring. With bigger rings and a bounded yield-spin before
  sleeping, Clang's slower producers lost nothing, while GCC's faster ones still overflowed (120,000–345,000 of 800,000
  dropped in a burst). Size the rings for the burst, not the average.

### 1.9 P9 · Parallel DAG executor with atomic in-degree counters (Listing 11.9)

**Problem.** Execute a dependency graph in parallel: a node runs when all predecessors are done; no locks during
traversal.

```cpp
// p09_dag_executor.cpp - P9: parallel DAG executor: atomic in-degree counters, a lock-free ready queue, no locks at all
#include <atomic>
#include <cstdint>
#include <memory>
#include <print>
#include <random>
#include <thread>
#include <vector>

template <class T>
class MpmcRing {   // Vyukov's bounded queue (Folder 09, Listing 9.4), compact
    struct alignas(64) Cell {
        std::atomic<std::size_t> seq;
        T data;
    };
    const std::size_t mask_;
    std::unique_ptr<Cell[]> cells_;
    alignas(128) std::atomic<std::size_t> enq_{0};
    alignas(128) std::atomic<std::size_t> deq_{0};

public:
    explicit MpmcRing(std::size_t cap) : mask_(cap - 1), cells_(new Cell[cap]) {
        for (std::size_t i = 0; i < cap; ++i) cells_[i].seq.store(i, std::memory_order_relaxed);
    }
    bool try_push(const T& v) {
        std::size_t pos = enq_.load(std::memory_order_relaxed);
        for (;;) {
            Cell& c = cells_[pos & mask_];
            const auto diff = static_cast<std::intptr_t>(c.seq.load(std::memory_order_acquire)) - static_cast<std::intptr_t>(pos);
            if (diff == 0 && enq_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                c.data = v;
                c.seq.store(pos + 1, std::memory_order_release);
                return true;
            }
            if (diff < 0) return false;
            if (diff > 0) pos = enq_.load(std::memory_order_relaxed);
        }
    }
    bool try_pop(T& v) {
        std::size_t pos = deq_.load(std::memory_order_relaxed);
        for (;;) {
            Cell& c = cells_[pos & mask_];
            const auto diff = static_cast<std::intptr_t>(c.seq.load(std::memory_order_acquire)) - static_cast<std::intptr_t>(pos + 1);
            if (diff == 0 && deq_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                v = c.data;
                c.seq.store(pos + mask_ + 1, std::memory_order_release);
                return true;
            }
            if (diff < 0) return false;
            if (diff > 0) pos = deq_.load(std::memory_order_relaxed);
        }
    }
};

struct Node {
    std::vector<std::uint32_t> preds, succs;
    std::atomic<int> pending{0};        // unfinished predecessors
    std::atomic<int> runs{0};           // executions (must end at exactly 1)
    std::uint64_t value = 0;            // written once by the node's task, read by its successors
};

// value(n) = 1 + sum of the predecessors' values (mod 2^61 - 1): any wrong order or a missed dependency changes it.
std::uint64_t compute(const std::vector<Node>& g, std::uint32_t n) {
    std::uint64_t v = 1;
    for (std::uint32_t p : g[n].preds) v = (v + g[p].value) % ((std::uint64_t{1} << 61) - 1);
    return v;
}

int main() {
    constexpr std::uint32_t kNodes = 20'000;
    std::vector<Node> g(kNodes);
    std::mt19937 rng(7);
    for (std::uint32_t j = 1; j < kNodes; ++j) {   // edges i -> j with i < j: a DAG by construction
        const std::uint32_t fan_in = rng() % 4;
        for (std::uint32_t k = 0; k < fan_in; ++k) {
            const std::uint32_t i = static_cast<std::uint32_t>(rng() % j);
            g[i].succs.push_back(j);
            g[j].preds.push_back(i);
        }
    }
    std::vector<std::uint64_t> reference(kNodes);   // sequential evaluation in index order (a topological order)
    for (std::uint32_t n = 0; n < kNodes; ++n) {
        std::uint64_t v = 1;
        for (std::uint32_t p : g[n].preds) v = (v + reference[p]) % ((std::uint64_t{1} << 61) - 1);
        reference[n] = v;
    }

    MpmcRing<std::uint32_t> ready(32'768);
    for (std::uint32_t n = 0; n < kNodes; ++n) {
        g[n].pending.store(static_cast<int>(g[n].preds.size()), std::memory_order_relaxed);
        if (g[n].preds.empty()) (void)ready.try_push(n);
    }
    std::atomic<std::uint32_t> remaining{kNodes};
    {
        std::vector<std::jthread> workers;
        for (int w = 0; w < 4; ++w)
            workers.emplace_back([&] {
                std::uint32_t n = 0;
                while (remaining.load(std::memory_order_acquire) > 0) {
                    if (!ready.try_pop(n)) continue;
                    g[n].runs.fetch_add(1, std::memory_order_relaxed);
                    g[n].value = compute(g, n);
                    // The acq_rel decrement publishes our value to whichever worker drops a successor's count to 0.
                    for (std::uint32_t s : g[n].succs)
                        if (g[s].pending.fetch_sub(1, std::memory_order_acq_rel) == 1)
                            while (!ready.try_push(s)) {
                            }
                    remaining.fetch_sub(1, std::memory_order_release);
                }
            });
    }
    std::uint32_t once = 0, equal = 0;
    for (std::uint32_t n = 0; n < kNodes; ++n) {
        once += g[n].runs.load() == 1;
        equal += g[n].value == reference[n];
    }
    std::println("DAG of {} nodes, 4 workers: every node ran exactly once: {}; every value matches the sequential order: {}",
                 kNodes, once == kNodes ? "yes" : "NO", equal == kNodes ? "yes" : "NO");
}
```

```text
DAG of 20000 nodes, 4 workers: every node ran exactly once: yes; every value matches the sequential order: yes
```

* **Each node's `pending` counter** starts at its in-degree. A finishing node decrements each successor's counter with
  `acq_rel`, and the decrement that reaches 0 enqueues the successor. The acq_rel RMW chain on one counter forms a
  release sequence, so the worker that releases a node has seen every predecessor's `value` (Folder 07, file 01, §1.4 C).
  The ready queue is Vyukov's MPMC ring: no locks anywhere.
* **The check is semantic:** each value is `1 + sum(predecessor values)`, so a node that ran too early, twice, or with a
  missing dependency would change it. All 20,000 values matched the sequential evaluation.

### 1.10 P10 · Dining philosophers and deadlock-free transfers (Listing 11.10)

**Problem.** Acquire two locks without deadlock: five philosophers with shared forks; transfers between accounts in
arbitrary directions.

```cpp
// p10_philosophers_transfer.cpp - P10: dining philosophers and multi-account transfers without deadlock (std::scoped_lock)
#include <array>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <print>
#include <random>
#include <thread>
#include <vector>

int main() {
    // Five philosophers, five forks. Each needs both neighbouring forks. Naively locking "left, then right"
    // deadlocks when all five pick up their left fork at once. std::scoped_lock acquires both with the
    // deadlock-avoidance algorithm of std::lock (Folder 08, Listing 8.6).
    {
        std::array<std::mutex, 5> forks;
        std::array<int, 5> meals{};
        {
            std::vector<std::jthread> ps;
            for (int i = 0; i < 5; ++i)
                ps.emplace_back([&, i] {
                    for (int k = 0; k < 20'000; ++k) {
                        std::scoped_lock both(forks[static_cast<std::size_t>(i)], forks[static_cast<std::size_t>((i + 1) % 5)]);
                        ++meals[static_cast<std::size_t>(i)];   // eat (protected by both forks)
                    }
                });
        }
        int total = 0;
        for (int m : meals) total += m;
        std::println("5 philosophers x 20,000 meals: all finished, {} meals, nobody starved: {}", total,
                     total == 100'000 ? "yes" : "NO");
    }
    // Transfers between 8 accounts from 4 threads. Two disciplines, both deadlock-free:
    //   (a) std::scoped_lock on both accounts; (b) a global order: always lock the lower account id first.
    {
        struct Account {
            std::mutex m;
            std::int64_t balance = 1'000;
        };
        std::array<Account, 8> acc;
        auto transfer_scoped = [&](std::size_t from, std::size_t to, std::int64_t amount) {
            if (from == to) return;                          // scoped_lock would lock the same mutex twice
            std::scoped_lock lk(acc[from].m, acc[to].m);
            if (acc[from].balance < amount) return;          // no overdraft
            acc[from].balance -= amount;
            acc[to].balance += amount;
        };
        auto transfer_ordered = [&](std::size_t from, std::size_t to, std::int64_t amount) {
            if (from == to) return;
            std::unique_lock first(acc[std::min(from, to)].m);   // lock order by id: no cycle can form
            std::unique_lock second(acc[std::max(from, to)].m);
            if (acc[from].balance < amount) return;
            acc[from].balance -= amount;
            acc[to].balance += amount;
        };
        {
            std::vector<std::jthread> ts;
            for (std::uint32_t t = 0; t < 4; ++t)
                ts.emplace_back([&, t] {
                    std::mt19937 rng(t);
                    for (int k = 0; k < 200'000; ++k) {
                        const std::size_t a = rng() % 8, b = rng() % 8;
                        const auto amount = static_cast<std::int64_t>(rng() % 50);
                        if (t % 2 == 0) transfer_scoped(a, b, amount);
                        else transfer_ordered(a, b, amount);
                    }
                });
        }
        std::int64_t total = 0, lowest = 1'000;
        for (Account& a : acc) {
            total += a.balance;
            lowest = std::min(lowest, a.balance);
        }
        std::println("800,000 random transfers, 8 accounts, 4 threads: total {} (expected 8000), no negative balance: {}",
                     total, lowest >= 0 ? "yes" : "NO");
    }
}
```

```text
5 philosophers x 20,000 meals: all finished, 100000 meals, nobody starved: yes
800,000 random transfers, 8 accounts, 4 threads: total 8000 (expected 8000), no negative balance: yes
```

* Two correct disciplines side by side: `std::scoped_lock` (try-and-back-off, Folder 08's Listing 8.6 excerpt) and
  a global lock order (lower id first). Mixing them is safe: a thread inside `std::lock` blocks only on its first
  mutex while holding none (it merely *tries* the others), so it can never be one of the "hold one, wait for another"
  links a deadlock cycle needs, and the ordered threads can't form a cycle among themselves.
* The `from == to` check matters: `scoped_lock(m, m)` would lock the same mutex twice.

### 1.11 P11 · Readers-writers-upgradable lock (Listing 11.11)

**Problem.** Read; if you need to write, convert to exclusive without letting another writer slip in, and without the
classic deadlock.

```cpp
// p11_upgradable_lock.cpp - P11: shared -> upgrade -> exclusive without the "two readers upgrade" deadlock
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <latch>
#include <map>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

// Three ownership levels (the Boost upgrade_mutex model):
//   shared   - many at once;
//   upgrade  - AT MOST ONE, coexists with shared holders, excludes writers and other upgraders;
//   exclusive- alone. Only the upgrade holder may convert to exclusive, so two conversions can never wait on
//              each other: the deadlock below is impossible by construction.
class UpgradableMutex {
    std::mutex m_;
    std::condition_variable cv_;
    int readers_ = 0;
    bool upgrader_ = false, writer_ = false, upgrading_ = false;

public:
    void lock_shared() {
        std::unique_lock lk(m_);
        cv_.wait(lk, [&] { return !writer_ && !upgrading_; });   // an upgrade in progress closes the door
        ++readers_;
    }
    void unlock_shared() {
        {
            std::scoped_lock lk(m_);
            --readers_;
        }
        cv_.notify_all();
    }
    void lock_upgrade() {
        std::unique_lock lk(m_);
        cv_.wait(lk, [&] { return !writer_ && !upgrader_; });
        upgrader_ = true;
    }
    void unlock_upgrade() {
        {
            std::scoped_lock lk(m_);
            upgrader_ = false;
        }
        cv_.notify_all();
    }
    void unlock_upgrade_and_lock() {   // atomic conversion: nobody else can take exclusive in between
        std::unique_lock lk(m_);
        upgrading_ = true;
        cv_.wait(lk, [&] { return readers_ == 0; });
        upgrading_ = false;
        upgrader_ = false;
        writer_ = true;
    }
    void unlock_and_lock_upgrade() {   // downgrade
        {
            std::scoped_lock lk(m_);
            writer_ = false;
            upgrader_ = true;
        }
        cv_.notify_all();
    }
    void lock() {
        std::unique_lock lk(m_);
        cv_.wait(lk, [&] { return !writer_ && !upgrader_ && readers_ == 0; });
        writer_ = true;
    }
    template <class Rep, class Period>
    bool try_lock_for(std::chrono::duration<Rep, Period> d) {
        std::unique_lock lk(m_);
        if (!cv_.wait_for(lk, d, [&] { return !writer_ && !upgrader_ && readers_ == 0; })) return false;
        writer_ = true;
        return true;
    }
    void unlock() {
        {
            std::scoped_lock lk(m_);
            writer_ = false;
        }
        cv_.notify_all();
    }
};

int main() {
    // 1. The deadlock an upgrade lock exists to prevent: two readers each try to become the writer while still
    //    holding their shared lock. Each waits for the other to release: forever (here: until a 200 ms timeout).
    //    (Doing this with std::shared_mutex is undefined behaviour, recursive ownership; this lock defines it.)
    {
        UpgradableMutex m;
        std::latch both_reading(2);
        bool upgraded[2] = {true, true};
        {
            std::vector<std::jthread> ts;
            for (int i = 0; i < 2; ++i)
                ts.emplace_back([&, i] {
                    m.lock_shared();
                    both_reading.arrive_and_wait();
                    upgraded[i] = m.try_lock_for(std::chrono::milliseconds(200));   // "upgrade" while still shared
                    if (upgraded[i]) m.unlock();
                    m.unlock_shared();
                });
        }
        std::println("two readers each requesting exclusive while holding shared: reader 1 {}, reader 2 {} -> {}",
                     upgraded[0] ? "upgraded" : "timed out", upgraded[1] ? "upgraded" : "timed out",
                     !upgraded[0] && !upgraded[1] ? "deadlock (each waits for the other's shared lock)" : "no deadlock");
    }
    // 2. Get-or-compute cache: hits take shared; misses take upgrade (readers keep reading meanwhile), re-check,
    //    compute, then convert to exclusive only for the insertion.
    {
        UpgradableMutex mu;
        std::map<int, int> cache;
        std::atomic<int> computes{0};
        auto get = [&](int k) {
            mu.lock_shared();
            if (auto it = cache.find(k); it != cache.end()) {
                const int v = it->second;
                mu.unlock_shared();
                return v;
            }
            mu.unlock_shared();
            mu.lock_upgrade();
            if (auto it = cache.find(k); it != cache.end()) {   // someone filled it while we waited
                const int v = it->second;
                mu.unlock_upgrade();
                return v;
            }
            computes.fetch_add(1);
            const int v = k * k;                                 // "expensive": readers are NOT blocked here
            mu.unlock_upgrade_and_lock();
            cache.emplace(k, v);
            mu.unlock();
            return v;
        };
        std::atomic<int> wrong{0};
        {
            std::vector<std::jthread> ts;
            for (int t = 0; t < 4; ++t)
                ts.emplace_back([&] {
                    for (int round = 0; round < 50; ++round)
                        for (int k = 0; k < 200; ++k)
                            if (get(k) != k * k) wrong.fetch_add(1);
                });
        }
        std::println("4 threads x 40,000 lookups of 200 keys: computes {} (each key exactly once: {}), wrong values {}",
                     computes.load(), computes.load() == 200 ? "yes" : "NO", wrong.load());
    }
}
```

```text
two readers each requesting exclusive while holding shared: reader 1 timed out, reader 2 timed out -> deadlock (each waits for the other's shared lock)
4 threads x 40,000 lookups of 200 keys: computes 200 (each key exactly once: yes), wrong values 0
```

* **The deadlock:** two shared holders that each request exclusive while still shared wait for each other forever.
  The listing reproduces it deterministically, with timed acquisition on its own lock. The first draft did this with
  `std::shared_timed_mutex::try_lock_for` while holding it shared, which the standard makes *undefined behaviour*
  (recursive ownership), so it was replaced.
* **The fix:** a third mode, *upgrade*, held by at most one thread, coexisting with readers and excluding writers. Only
  the upgrade holder may convert, so two conversions can never deadlock. The get-or-compute cache computes each of
  200 keys exactly once while readers keep reading during the computation.

### 1.12 P12 · Fair ticket lock and MCS queue lock (Listing 11.12)

**Problem.** A spin lock that is fair (FIFO) and doesn't melt down at high core counts.

```cpp
// p12_ticket_mcs.cpp - P12: fair FIFO ticket spin lock and MCS queue lock (each waiter spins on its OWN cache line)
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <print>
#include <thread>
#include <type_traits>
#include <vector>
#if defined(__x86_64__)
#include <immintrin.h>
#endif

inline void cpu_relax() {
#if defined(__x86_64__)
    _mm_pause();
#elif defined(__aarch64__)
    asm volatile("yield");
#endif
}

class TtasLock {   // baseline (Folder 07, Listing 7.16): unfair, everyone spins on one line
    std::atomic<bool> locked_{false};

public:
    void lock() {
        for (;;) {
            if (!locked_.exchange(true, std::memory_order_acquire)) return;
            while (locked_.load(std::memory_order_relaxed)) cpu_relax();
        }
    }
    void unlock() { locked_.store(false, std::memory_order_release); }
};

class TicketLock {   // FIFO: take a number, wait until it is served
    alignas(64) std::atomic<std::uint32_t> next_{0};
    alignas(64) std::atomic<std::uint32_t> serving_{0};

public:
    void lock() {
        const std::uint32_t my = next_.fetch_add(1, std::memory_order_relaxed);
        while (serving_.load(std::memory_order_acquire) != my) cpu_relax();   // all waiters read one line
    }
    void unlock() { serving_.store(serving_.load(std::memory_order_relaxed) + 1, std::memory_order_release); }
};

class McsLock {   // FIFO, and each waiter spins on its own node: one cache-line transfer per hand-off
public:
    struct alignas(64) QNode {
        std::atomic<QNode*> next{nullptr};
        std::atomic<bool> locked{false};
    };
    void lock(QNode& me) {
        me.next.store(nullptr, std::memory_order_relaxed);
        me.locked.store(true, std::memory_order_relaxed);
        QNode* prev = tail_.exchange(&me, std::memory_order_acq_rel);   // join the queue
        if (!prev) return;                                             // it was free
        prev->next.store(&me, std::memory_order_release);              // link behind our predecessor
        while (me.locked.load(std::memory_order_acquire)) cpu_relax();  // spin on OUR line only
    }
    void unlock(QNode& me) {
        QNode* succ = me.next.load(std::memory_order_acquire);
        if (!succ) {
            QNode* expected = &me;
            if (tail_.compare_exchange_strong(expected, nullptr, std::memory_order_release, std::memory_order_relaxed))
                return;                                                // nobody waiting
            while (!(succ = me.next.load(std::memory_order_acquire))) cpu_relax();   // a successor is linking in
        }
        succ->locked.store(false, std::memory_order_release);          // hand over directly
    }

private:
    alignas(64) std::atomic<QNode*> tail_{nullptr};
};

// 4 threads, 250 ms, tiny critical section. Report ns per acquisition and fairness (min/max acquisitions per thread).
template <class Lock>
void bench(const char* name) {
    Lock lk;
    std::int64_t counter = 0;
    std::atomic<bool> go{false}, stop{false};
    std::vector<std::int64_t> per(4, 0);
    {
        std::vector<std::jthread> ts;
        for (std::size_t t = 0; t < 4; ++t)
            ts.emplace_back([&, t] {
                typename McsLock::QNode node;   // used only by the MCS variant
                while (!go.load()) {
                }
                while (!stop.load(std::memory_order_relaxed)) {
                    if constexpr (std::is_same_v<Lock, McsLock>) lk.lock(node);
                    else lk.lock();
                    ++counter;
                    ++per[t];
                    if constexpr (std::is_same_v<Lock, McsLock>) lk.unlock(node);
                    else lk.unlock();
                }
            });
        const auto t0 = std::chrono::steady_clock::now();
        go = true;
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
        stop = true;
        ts.clear();
        const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
        std::int64_t sum = 0;
        for (std::int64_t p : per) sum += p;
        const auto [mn, mx] = std::minmax_element(per.begin(), per.end());
        std::println("{:<12} {:6.1f} ns/acquisition, count consistent: {}, fairness min/max per thread {:.2f}", name,
                     d.count() / static_cast<double>(sum), sum == counter ? "yes" : "NO",
                     static_cast<double>(*mn) / static_cast<double>(*mx));
    }
}

int main() {
    std::println("4 threads contending for 250 ms on one lock:");
    bench<TtasLock>("TTAS");
    bench<TicketLock>("ticket");
    bench<McsLock>("MCS");
}
```

GCC, then Clang:

```text
4 threads contending for 250 ms on one lock:
TTAS           70.7 ns/acquisition, count consistent: yes, fairness min/max per thread 0.44
ticket        116.7 ns/acquisition, count consistent: yes, fairness min/max per thread 0.98
MCS           115.1 ns/acquisition, count consistent: yes, fairness min/max per thread 1.00
4 threads contending for 250 ms on one lock:
TTAS           48.8 ns/acquisition, count consistent: yes, fairness min/max per thread 0.74
ticket        117.8 ns/acquisition, count consistent: yes, fairness min/max per thread 0.99
MCS           126.7 ns/acquisition, count consistent: yes, fairness min/max per thread 0.99
```

* **The trade-off, measured** (4 threads, two runs per compiler): TTAS ran 49–71 ns per acquisition but was unfair
  (min/max acquisitions per thread 0.42–0.74). The releasing core tends to re-acquire, so one thread runs in bursts.
  Ticket and MCS ran 115–127 ns and were fair (0.97–1.00). FIFO hand-off forces the lock to a different core on every
  acquisition, and that transfer is the cost.
* **Ticket vs MCS:** every ticket waiter spins on the same `serving_` line, so a release invalidates all of them. MCS
  waiters spin on their own nodes, so a release touches one line. At 4 threads they tie; at 64 cores and across NUMA
  nodes MCS wins (⚠ not measured here). That's why the Linux kernel's qspinlock is MCS-based.

### 1.13 P13 · H2O barrier and a multi-stage pipeline barrier (Listing 11.13)

**Problem.** Hydrogen and oxygen threads must leave in groups of exactly two H and one O; and a pipeline whose stages
advance in lock step.

```cpp
// p13_h2o_barrier.cpp - P13: the H2O barrier (semaphores + std::barrier) and a multi-stage pipeline barrier
#include <atomic>
#include <barrier>
#include <cstdint>
#include <print>
#include <semaphore>
#include <string>
#include <thread>
#include <vector>

// H2O: hydrogen and oxygen threads arrive in any order; they may only leave in groups of exactly two H and one O.
// The semaphores admit at most 2 H and 1 O into the "bonding" stage; the barrier releases them together,
// and its completion step (run once, while all three are inside) checks and records the molecule.
class H2O {
    std::counting_semaphore<2> h_slots_{2};
    std::counting_semaphore<1> o_slots_{1};
    std::atomic<int> h_in_{0}, o_in_{0};
    struct Completion {
        H2O* self;
        void operator()() noexcept {
            self->molecules_.push_back(std::string(static_cast<std::size_t>(self->h_in_.load()), 'H') +
                                       std::string(static_cast<std::size_t>(self->o_in_.load()), 'O'));
            self->h_in_ = 0;
            self->o_in_ = 0;
        }
    };
    std::barrier<Completion> bond_{3, Completion{this}};

public:
    std::vector<std::string> molecules_;   // written only by the completion step
    void hydrogen() {
        h_slots_.acquire();
        h_in_.fetch_add(1);
        bond_.arrive_and_wait();
        h_slots_.release();
    }
    void oxygen() {
        o_slots_.acquire();
        o_in_.fetch_add(1);
        bond_.arrive_and_wait();
        o_slots_.release();
    }
};

int main() {
    {
        H2O water;
        {
            std::vector<std::jthread> atoms;
            for (int i = 0; i < 30; ++i) {   // 20 H and 10 O, interleaved irregularly
                if (i % 3 == 1) atoms.emplace_back([&] { water.oxygen(); });
                else atoms.emplace_back([&] { water.hydrogen(); });
            }
        }
        bool all_water = water.molecules_.size() == 10;
        for (const auto& m : water.molecules_) all_water &= (m == "HHO");
        std::println("30 atom threads (20 H, 10 O): {} molecules formed, every one exactly H2O: {}", water.molecules_.size(),
                     all_water ? "yes" : "NO");
    }
    // Pipeline: 3 workers each own a third of a vector. Each phase: every worker smooths its part reading the
    // previous phase's buffer; the barrier's completion step swaps the buffers once all are done.
    {
        constexpr int kN = 3'000, kPhases = 200;
        std::vector<double> a(kN), b(kN), ref(kN), ref2(kN);
        for (int i = 0; i < kN; ++i) a[static_cast<std::size_t>(i)] = ref[static_cast<std::size_t>(i)] = i % 7;
        std::vector<double>* cur = &a;
        std::vector<double>* nxt = &b;
        auto smooth = [](const std::vector<double>& in, std::vector<double>& out, int lo, int hi) {
            for (int i = lo; i < hi; ++i) {
                const auto u = static_cast<std::size_t>(i);
                const double l = i > 0 ? in[u - 1] : in[u], r = i + 1 < kN ? in[u + 1] : in[u];
                out[u] = (l + in[u] + r) / 3.0;
            }
        };
        std::barrier sync(3, [&]() noexcept { std::swap(cur, nxt); });
        {
            std::vector<std::jthread> ws;
            for (int w = 0; w < 3; ++w)
                ws.emplace_back([&, w] {
                    for (int p = 0; p < kPhases; ++p) {
                        smooth(*cur, *nxt, w * kN / 3, (w + 1) * kN / 3);
                        sync.arrive_and_wait();   // nobody starts phase p+1 before everyone finished phase p
                    }
                });
        }
        for (int p = 0; p < kPhases; ++p) {
            smooth(ref, ref2, 0, kN);
            std::swap(ref, ref2);
        }
        std::println("3-stage barrier pipeline, {} phases: result identical to the sequential run: {}", kPhases,
                     *cur == ref ? "yes" : "NO");
    }
}
```

```text
30 atom threads (20 H, 10 O): 10 molecules formed, every one exactly H2O: yes
3-stage barrier pipeline, 200 phases: result identical to the sequential run: yes
```

* **Semaphores bound who may be in the bonding stage** (at most 2 H and 1 O); **the barrier releases them together**.
  The check runs in the barrier's **completion step**, which executes once per phase while all three are inside, so
  it sees exactly the molecule being formed. Checking printed output afterwards can't do that, because the releases of
  one molecule interleave with the next.
* **Pipeline:** the completion step swaps the buffers between phases; no worker starts phase p + 1 before all finished
  phase p. The result is bit-identical to the sequential computation.

### 1.14 P14 · Thread-safe object pool with a lock-free free list (Listing 11.14)

**Problem.** Allocate and free fixed-size objects from many threads without the global allocator.

```cpp
// p14_object_pool.cpp - P14: thread-safe object pool on a slab: lock-free free list with a tagged (ABA-proof) head
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <new>
#include <print>
#include <thread>
#include <vector>

template <class T>
class ObjectPool {
    static constexpr std::uint32_t kNil = 0xFFFF'FFFF;
    struct Storage {
        alignas(T) std::byte bytes[sizeof(T)];
    };
    // One slab, never returned while the pool lives (type-stable memory). The free-list links live in a SEPARATE
    // array, so a stale read of a link never touches an object's storage (no union, no lifetime games).
    std::unique_ptr<Storage[]> slab_;
    std::unique_ptr<std::atomic<std::uint32_t>[]> next_;
    std::uint32_t capacity_;
    alignas(64) std::atomic<std::uint64_t> head_;   // (tag << 32) | index of the first free slot

    static std::uint64_t make(std::uint32_t i, std::uint64_t tag) { return (tag << 32) | i; }

public:
    explicit ObjectPool(std::uint32_t capacity)
        : slab_(new Storage[capacity]), next_(new std::atomic<std::uint32_t>[capacity]), capacity_(capacity) {
        for (std::uint32_t i = 0; i < capacity; ++i) next_[i].store(i + 1 < capacity ? i + 1 : kNil);
        head_.store(make(0, 0));
    }
    template <class... A>
    T* create(A&&... args) {
        std::uint64_t old = head_.load(std::memory_order_acquire);
        for (;;) {
            const auto i = static_cast<std::uint32_t>(old);
            if (i == kNil) return nullptr;   // exhausted
            const std::uint32_t next = next_[i].load(std::memory_order_relaxed);   // may be stale: the tag catches it
            if (head_.compare_exchange_weak(old, make(next, (old >> 32) + 1), std::memory_order_acquire,
                                            std::memory_order_acquire))
                return ::new (static_cast<void*>(slab_[i].bytes)) T(std::forward<A>(args)...);
        }
    }
    void destroy(T* p) {
        const std::uint32_t i = index_of(p);
        p->~T();
        std::uint64_t old = head_.load(std::memory_order_relaxed);
        for (;;) {
            next_[i].store(static_cast<std::uint32_t>(old), std::memory_order_relaxed);
            if (head_.compare_exchange_weak(old, make(i, (old >> 32) + 1), std::memory_order_release,
                                            std::memory_order_relaxed))
                return;
        }
    }
    std::uint32_t free_count() const {   // only when quiescent
        std::uint32_t n = 0;
        for (auto i = static_cast<std::uint32_t>(head_.load()); i != kNil; i = next_[i].load()) ++n;
        return n;
    }
    std::uint32_t index_of(const T* p) const {
        return static_cast<std::uint32_t>(reinterpret_cast<const Storage*>(p) - slab_.get());
    }
};

struct Order {
    std::uint64_t id;
    double price;
    std::uint32_t qty;
};

int main() {
    constexpr std::uint32_t kCap = 1024;
    ObjectPool<Order> pool(kCap);
    auto owner = std::make_unique<std::atomic<int>[]>(kCap);   // which thread holds each slot (-1 = free)
    for (std::uint32_t i = 0; i < kCap; ++i) owner[i].store(-1);
    std::atomic<int> double_alloc{0};
    const auto t0 = std::chrono::steady_clock::now();
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < 4; ++t)
            ts.emplace_back([&, t] {
                std::vector<Order*> mine;
                std::uint64_t x = 0x9E3779B97F4A7C15ULL * static_cast<std::uint64_t>(t + 1);
                for (int op = 0; op < 500'000; ++op) {
                    x ^= x << 13, x ^= x >> 7, x ^= x << 17;
                    if ((x & 1) && mine.size() < 200) {
                        if (Order* o = pool.create(Order{x, 100.0, 1})) {
                            int expected = -1;
                            if (!owner[pool.index_of(o)].compare_exchange_strong(expected, t)) double_alloc.fetch_add(1);
                            mine.push_back(o);
                        }
                    } else if (!mine.empty()) {
                        Order* o = mine.back();
                        mine.pop_back();
                        owner[pool.index_of(o)].store(-1);
                        pool.destroy(o);
                    }
                }
                for (Order* o : mine) {
                    owner[pool.index_of(o)].store(-1);
                    pool.destroy(o);
                }
            });
    }
    const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
    std::println("4 threads x 500,000 create/destroy: a slot handed to two owners: {} times; all {} slots free at the end: {}",
                 double_alloc.load(), kCap, pool.free_count() == kCap ? "yes" : "NO");
    std::println("{:.1f} ns per operation (wall time / 2,000,000 ops)", d.count() / 2'000'000.0);
}
```

GCC, then Clang:

```text
4 threads x 500,000 create/destroy: a slot handed to two owners: 0 times; all 1024 slots free at the end: yes
54.7 ns per operation (wall time / 2,000,000 ops)
4 threads x 500,000 create/destroy: a slot handed to two owners: 0 times; all 1024 slots free at the end: yes
62.1 ns per operation (wall time / 2,000,000 ops)
```

* **A slab plus a Treiber free list of indices with a 32-bit tag** (Folder 09: no ABA, one 64-bit CAS). The slab is
  never returned while the pool lives, so a stale read of a link reads valid memory.
* **The first draft stored the link inside the free object** (a union of the link and the object's storage), the
  classic free-list trick. But the algorithm *reads stale links* of slots that another thread may already have turned
  back into objects, which reads an object outside its lifetime. A separate link array (4 bytes per slot) removes the
  problem.
* 55–78 ns per operation with 4 threads hitting one head word. In production, add per-thread magazines (a small local
  cache refilled in batches) so the shared CAS is rare.

### 1.15 P15 · Single-flight request coalescer (Listing 11.15)

**Problem.** When 100 requests for the same key arrive together, call the backend once and give all of them the
result, without holding a global lock during the I/O.

```cpp
// p15_single_flight.cpp - P15: request coalescing: 100 concurrent requests for one key trigger ONE backend fetch
#include <atomic>
#include <chrono>
#include <future>
#include <latch>
#include <mutex>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

template <class K, class V>
class SingleFlight {
    std::mutex m_;                                       // guards the map only: never held during the fetch
    std::unordered_map<K, std::shared_future<V>> inflight_;

public:
    template <class Fetch>
    V get(const K& key, Fetch fetch) {
        std::promise<V> promise;
        std::shared_future<V> result;
        bool leader = false;
        {
            std::scoped_lock lk(m_);
            if (auto it = inflight_.find(key); it != inflight_.end()) {
                result = it->second;                     // someone is already fetching: share their result
            } else {
                result = promise.get_future().share();
                inflight_.emplace(key, result);
                leader = true;
            }
        }
        if (leader) {
            try {
                promise.set_value(fetch(key));           // the slow I/O runs with NO lock held
            } catch (...) {
                promise.set_exception(std::current_exception());   // every waiter gets the error
            }
            std::scoped_lock lk(m_);
            inflight_.erase(key);                        // the next request after completion fetches again
        }
        return result.get();                             // followers wait here, without holding m_
    }
};

int main() {
    SingleFlight<std::string, std::string> sf;
    std::atomic<int> backend_calls{0};
    auto slow_fetch = [&](const std::string& k) {
        backend_calls.fetch_add(1);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));   // a remote call
        return "value-of-" + k;
    };
    auto wave = [&](auto fetch, std::atomic<int>& ok, std::atomic<int>& failed) {
        std::latch start(100);
        std::vector<std::jthread> ts;
        for (int i = 0; i < 100; ++i)
            ts.emplace_back([&] {
                start.arrive_and_wait();                 // all 100 ask at the same moment
                try {
                    if (sf.get("user:42", fetch) == "value-of-user:42") ok.fetch_add(1);
                } catch (const std::runtime_error&) {
                    failed.fetch_add(1);
                }
            });
    };
    {
        std::atomic<int> ok{0}, failed{0};
        wave(slow_fetch, ok, failed);
        std::println("100 concurrent requests for one key: backend fetches {}, requests answered {}", backend_calls.load(), ok.load());
        std::atomic<int> ok2{0}, failed2{0};
        wave(slow_fetch, ok2, failed2);
        std::println("a second wave after the first completed: backend fetches now {} (no stale result is served)",
                     backend_calls.load());
    }
    {
        std::atomic<int> ok{0}, failed{0};
        backend_calls = 0;
        wave([&](const std::string&) -> std::string {
            backend_calls.fetch_add(1);
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            throw std::runtime_error("backend unavailable");
        }, ok, failed);
        std::println("a failing backend: fetches {}, requests that received the error {}", backend_calls.load(), failed.load());
    }
}
```

```text
100 concurrent requests for one key: backend fetches 1, requests answered 100
a second wave after the first completed: backend fetches now 2 (no stale result is served)
a failing backend: fetches 1, requests that received the error 100
```

* **The map lock is held only to find or insert the in-flight entry.** The leader fetches with no lock held, and
  followers wait on the `shared_future`, not on the mutex. Errors reach every waiter through `set_exception`.
* **Erase after completion:** the next wave fetches again (fetches: 2), so a single-flight is not a cache. Add caching
  separately, with its own TTL and invalidation.
* Follow-ups: *"the leader hangs"* (a timeout on followers, cancellation of the leader); *"thundering herd at TTL
  expiry"* (refresh ahead, or single-flight the refresh).

---

## 2. Evolution table

| Standard | What it made easier in these problems |
|---|---|
| C++11 | `std::mutex`, `condition_variable`, `std::atomic` with memory orders, `std::thread`, `future`/`promise`/`packaged_task` (P1, P3, P6, P15) |
| C++14 | `shared_timed_mutex` (P4, P11) |
| C++17 | `std::scoped_lock` (P10), `std::shared_mutex`, `hardware_destructive_interference_size`, guaranteed elision |
| C++20 | `std::jthread` + `stop_token` (P3, P7), `condition_variable_any` stop-token waits (P3), `std::latch`/`std::barrier`/`counting_semaphore` (P13, P15 tests), `atomic::wait` |
| C++23 | `std::move_only_function` (task storage, P3), `std::print` |
| C++26 | hazard pointers and RCU (P14's reclamation alternatives), `std::execution` (P3, P9 as sender graphs) |

---

## 3. Production blueprints

| Problem | Subtle buggy way | Production-hardened way |
|---|---|---|
| P1 queue | one condition variable for both conditions; `close()` without predicates | two cvs; `closed` in every predicate; drain-then-nullopt semantics |
| P3 pool | idle wait whose stop check races with `notify_all` | `condition_variable_any` stop-token wait + submit epoch; `jthread` members last |
| P4 RW lock | `std::shared_mutex` assumed fair | explicit writer preference (or phase-fair), documented |
| P5 cache | shard = `std::hash(k) % n` | mix the hash first; one lock per shard on its own line |
| P6 limiter | mutex + floating-point tokens; timestamp reset to `now` | one packed 64-bit word, CAS, carry the fractional time; injectable clock |
| P7 timers | priority queue with O(log n) cancel by search; callbacks under the wheel's lock | intrusive wheel nodes, generation-checked ids, callbacks dispatched outside the lock |
| P8 logger | `std::mutex` around `fprintf` on the caller's thread | per-thread SPSC rings, drop-and-count, a drain thread that spins briefly before sleeping |
| P9 DAG | a mutex-protected ready queue; relaxed in-degree counters | acq_rel decrements (release sequences), lock-free ready queue |
| P10 transfers | lock in parameter order | `scoped_lock` or a global id order; handle `from == to` |
| P11 upgrade | shared → exclusive conversion from any reader | a single upgrade slot; conversion only from it |
| P12 spin locks | TAS/TTAS on many cores | MCS (local spinning) or a futex-based lock; measure fairness, not just ns |
| P13 barrier | check results by printed order | check inside the barrier's completion step |
| P14 pool | free-list link inside the freed object, read stale by other threads | separate link array or SMR; tagged head |
| P15 coalescing | hold the global lock during the backend call | lock only the map; leader fetches unlocked; followers wait on a `shared_future` |

---

## 4. Failure modes

| Symptom | Problem / root cause | Detection |
|---|---|---|
| shutdown hangs occasionally | P3: lost wakeup between predicate check and sleep | stop-token-aware waits; shutdown stress tests |
| a cache uses a fraction of its capacity | P5: identity hash and structured keys | per-shard size metrics |
| limiter admits slightly more than configured | P6: timestamp reset loses fractional time (or gains it) | deterministic tests with an injected clock |
| timers never fire in tests | P7: `~jthread` stopped the ticker | `join()` when the thread must finish naturally |
| logging stalls the service under load | P8: blocking logger | drop counters; non-blocking design |
| DAG values sometimes wrong | P9: relaxed counters, missed release sequence | semantic checks against a sequential run |
| two writers deadlock after reading | P11: conversion from shared without an upgrade slot | upgradable lock |
| p99 latency spikes under contention | P12: unfair lock (one thread hogs) | per-thread acquisition counts |
| backend overloaded on cache miss storms | P15: no request coalescing | backend calls per key per second |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 P1 "What happens to items in the queue on close()?"</b></summary>

**Initial prompt.** "Add `close()` to your blocking queue. What should happen to producers, consumers, and items
already queued?"

**L5 textbook answer.** "`close()` sets a flag; everyone checks it and returns."

**Why L5 deadlocks on ARM64.** Unless the flag is set under the mutex *and* part of every wait predicate, a consumer
can check "empty and not closed", then `close()` sets the flag and notifies, and the consumer sleeps forever: a lost
wakeup. And "everyone returns" drops the backlog. Listing 11.1 defines it: producers get `closed`, consumers drain the
remaining items and only then get `nullopt`.

**L7 principal defense.** "The flag lives under the queue's mutex and appears in both predicates; `close()` notifies
both condition variables. And the semantics are written down: drain-then-end for consumers, fail-fast for producers.
Then I'd test exactly that: Listing 11.1's deterministic close test plus the 600,000-item run."
</details>

<details><summary><b>Chain 2 🔥 P3 "Your pool's destructor hangs once in a thousand runs"</b></summary>

**Initial prompt.** "Workers sleep on a condition variable when idle. The destructor calls `request_stop()` on every
`jthread` and then `notify_all()`. Sometimes it hangs. Why?"

**L5 textbook answer.** "Add a `sleep` before `notify_all` so the workers are waiting."

**Why L5 deadlocks on ARM64.** A worker evaluates its predicate (stop not yet requested), then the destructor requests
stop and notifies, and only then does the worker block: the notification found nobody, and the worker sleeps forever
(Listing 11.3's first draft had exactly this). A sleep only shrinks the window. ARM64's weaker ordering doesn't cause it
but makes the window easier to hit.

**L7 principal defense.** "`condition_variable_any::wait(lock, stop_token, pred)`: it registers a stop callback that
notifies under the cv's internal mutex, so a stop request can't fall between check and sleep (Folder 08, file 01). For
submits, an epoch counter changed under the idle mutex closes the same window. Workers are `jthread` members declared
last, so they're joined before the queues die."
</details>

<details><summary><b>Chain 3 ⚡ P5 "Shard by hash modulo N"</b></summary>

**Initial prompt.** "Your sharded cache picks `shard = std::hash<K>{}(key) % 16`. Problems?"

**L5 textbook answer.** "No, `std::hash` distributes keys uniformly."

**Why L5 breaks.** `std::hash` for integers is the identity in libstdc++ and libc++ (Folder 03). Keys that share low
bits (even ids, multiples of 16, odd-only, as in Listing 11.5's first run) land in a fraction of the shards. The cache
held 2,048 of 4,096 entries, and those 8 shards took all the lock traffic.

**L7 principal defense.** "Mix before sharding (a murmur/splitmix finalizer, as the fixed listing does), and use
different bits of the mixed hash for the shard and for the bucket inside the shard. Then monitor per-shard size and
lock contention, which would have shown the skew immediately."
</details>

<details><summary><b>Chain 4 🧊 P6 "Is your lock-free rate limiter exact?"</b></summary>

**Initial prompt.** "Your token bucket recomputes the refill on every request inside a CAS loop. Is it exact under
contention, and over hours?"

**L5 textbook answer.** "Yes, CAS makes it atomic."

**Why L5 breaks.** Atomic, yes: one CAS on the whole packed state (Listing 11.6). Exact depends on arithmetic. Setting
the timestamp to `now` on every refill drops the fractional remainder, about one token interval per refill, so a busy
limiter admits fewer than configured, and the error grows with the request rate. The 40-bit microsecond timestamp
wraps after about 12.7 days. And two threads may read slightly different `now` values, so time can appear to go
backwards unless `now <= ts` is handled (the listing ignores negative intervals).

**L7 principal defense.** "Advance the timestamp only by the time the added tokens paid for, jump to `now` only when
full, guard against backwards time, and size or rebase the timestamp field. Prove it with an injected clock (5 of 6,
then exactly 1 after 100 ms) and a contention test that checks the upper bound."
</details>

<details><summary><b>Chain 5 ⚡ P7 "Why a timing wheel instead of a priority queue?"</b></summary>

**Initial prompt.** "Why not keep timers in a `std::priority_queue` ordered by deadline?"

**L5 textbook answer.** "A heap is O(log n), which is fine."

**Why L5 breaks.** Schedule is O(log n), but **cancel is the problem**: most timers (RPC timeouts) are cancelled before
they fire, and a heap can't remove an arbitrary element without searching (O(n)) or lazy deletion (tombstones that
bloat the heap). A wheel makes schedule and cancel O(1): an intrusive list insert or unlink. Expiry costs amortized
O(1) per tick, plus cascading.

**L7 principal defense.** "A hierarchical wheel: fine slots for the near future, coarse slots that cascade, an overflow
list beyond the horizon. Generation-checked ids make stale cancels safe, and callbacks run outside the lock. It's what
the Linux kernel, Netty and Kafka use. Listing 11.7 checks all 2,000 survivors fire on their exact tick."
</details>

<details><summary><b>Chain 6 🔥 P8 "Should the logger block when its buffer is full?"</b></summary>

**Initial prompt.** "Our async logger blocks the caller when its queue is full, so no log line is lost. Good design?"

**L5 textbook answer.** "Yes, losing logs is worse than waiting a bit."

**Why L5 breaks.** Queues fill when the system is under stress, exactly when blocking the threads that log
amplifies the stress: request threads stall on logging, latency explodes, timeouts cascade, and logging becomes the
outage. Listing 11.8 shows how easily rings fill: with a drainer that slept about 1 ms on Windows, GCC's producers
overflowed 4,096-slot rings in microseconds.

**L7 principal defense.** "Never block the observed thread: per-thread rings, drop and *count* when full (and log the
drop count), size rings for bursts, and keep the drainer responsive (yield-spin, then sleep). Audit logs that must not
lose records go to a separate, deliberately synchronous path with its own capacity planning."
</details>

<details><summary><b>Chain 7 🧊 P9 "Can the in-degree counters be relaxed?"</b></summary>

**Initial prompt.** "In your DAG executor, the `pending` decrements are `acq_rel`. Relaxed would be faster. Safe?"

**L5 textbook answer.** "Yes. The counter is atomic, so the decrement to zero is correctly detected."

**Why L5 corrupts memory on ARM64.** Detecting zero is fine; *seeing the predecessors' results* is the issue. The
worker that decrements to zero runs (or enqueues) the successor, which reads every predecessor's `value`. With relaxed
decrements nothing orders those writes before the successor's reads, and on ARM64 it can read stale values. Acq_rel
makes the decrements a release sequence: the final decrement acquires every earlier one's release (Folder 07, file 01,
§1.4 C).

**L7 principal defense.** "Release on every decrement, acquire on the one that hits zero (`acq_rel` does both), plus the
queue's own release/acquire. Validate semantically: Listing 11.9 recomputes every value sequentially and compares."
</details>

<details><summary><b>Chain 8 ⚡ P12 "Fair locks are faster, right?"</b></summary>

**Initial prompt.** "Ticket and MCS locks are fair. Are they faster than a test-and-test-and-set lock?"

**L5 textbook answer.** "Yes, fairness means less contention."

**Why L5 breaks.** Listing 11.12, 4 threads: TTAS 49–71 ns per acquisition, ticket and MCS 115–127 ns. TTAS is
*faster* because it's unfair: the releasing core often re-acquires the lock while its line is still local
(fairness 0.42–0.74). FIFO hand-off moves the lock to another core on every acquisition, by design.

**L7 principal defense.** "Fairness buys bounded waiting and predictable tail latency, and MCS keeps it from
collapsing at high core counts, because each waiter spins locally. TTAS buys throughput and risks starvation. For most
production code: a futex-based mutex that spins briefly (Folder 08). MCS or qspinlock-style locks for kernel-like
contexts with many cores."
</details>

<details><summary><b>Chain 9 🔥 P15 "Hold the lock while fetching"</b></summary>

**Initial prompt.** "Implement request coalescing: the first request for a key fetches it, the others wait."

**L5 textbook answer.** "Lock a mutex, check the cache, fetch on a miss, store, unlock."

**Why L5 breaks.** Holding the mutex across the fetch serializes *all* keys behind one slow backend call: a 50 ms
fetch for key A blocks requests for key B. And if the fetch hangs, the whole service hangs.

**L7 principal defense.** "Lock only the in-flight map: find or insert a `shared_future`, then unlock. The leader fetches
unlocked and fulfils the promise, or sets the exception so every waiter gets it. Followers wait on the future. Erase on
completion, so no stale data is served (Listing 11.15: 100 requests, 1 fetch; a second wave fetches again; a failure
reaches all 100). Plus a follower timeout, because a hung leader shouldn't hang everyone."
</details>

---

## 6. Invariants checklist

- [ ] Every machine-coding answer starts with the contract and ends with a stress test that checks its invariants.
- [ ] Every wait has a predicate that includes shutdown/close; shutdown can't be a lost wakeup.
- [ ] Every RMW that hands data to another thread is at least release, and the receiver acquires.
- [ ] Shards and buckets use mixed hashes.
- [ ] No lock is held across I/O, callbacks, or user code.
- [ ] Hot paths that must not block never block (drop and count instead).
- [ ] Lifetimes: threads joined before the data they use dies; no stale reads of objects outside their lifetime.

## 7. References

- G. Varghese, A. Lauck, "Hashed and Hierarchical Timing Wheels", SOSP 1987, DOI 10.1145/41457.37504
- J. Mellor-Crummey, M. Scott, "Algorithms for Scalable Synchronization on Shared-Memory Multiprocessors" (MCS): <https://www.cs.rochester.edu/u/scott/papers/1991_TOCS_synch.pdf>
- golang.org/x/sync/singleflight (the request-coalescing pattern): <https://pkg.go.dev/golang.org/x/sync/singleflight>
- D. Vyukov, bounded MPMC queue: <https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue>
- Boost.Thread `upgrade_mutex` (the upgrade-ownership model): <https://www.boost.org/doc/libs/release/doc/html/thread/synchronization.html>
- Linux kernel qspinlock (MCS-based): <https://github.com/torvalds/linux/blob/master/kernel/locking/qspinlock.c>
