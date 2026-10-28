# 02 · Work-stealing thread pool architecture, the Chase-Lev deque, and task graphs

> **Scope.** A thread pool built around one mutex-protected queue serializes every task hand-off through one lock and
> one cache line. As workers are added it gets *slower*, not faster. Work stealing gives every worker its own deque:
> the owner pushes and pops at one end without synchronization in the common case, and idle workers steal from the
> other end. This file implements the Chase-Lev deque in the C11 formulation of Lê et al. (with the fence that makes
> it correct on ARM), stress-tests it with an owner and three thieves, and races a single-queue pool against a
> work-stealing pool on a million-task spawn tree.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 10.2 | `chase_lev.hpp` | the deque: owner `push`/`pop` at the bottom, thieves `steal` at the top; a `seq_cst` fence on both sides of the last-element race | compiled into 10.3, 10.4 |
| 10.3 | `chase_lev_test.cpp` | 2,000,000 tasks shared by 1 owner and 3 thieves: every task executed exactly once; the fences are `LOCK OR` / `DMB ISH`, the CAS only on `top` | run, 4 threads, both compilers; asm x86-64 + AArch64 |
| 10.4 | `pool_bench.cpp` | a spawn tree of 1,048,575 tasks: the single-queue pool goes from 59–124 to 169–248 ns per task as workers grow from 1 to 4; the work-stealing pool from 39–53 to 9–23 ns, with only 4–49 steals | run, 1/2/4 workers, both compilers |

**Verification line.** As in file 01. At most 4 worker threads on this 6-core machine; behaviour at 64 cores is
discussed, not measured (⚠).

---

## 1. First principles

### 1.1 Why one shared queue stops scaling

```text
   single-queue pool                                  work-stealing pool
   +--------------------------+                       worker 0: [ t9 t8 t7 ]  <- push/pop at the bottom (LIFO)
   |  mutex | deque of tasks  | <- every submit           ^ top: thieves steal the OLDEST (FIFO)
   +--------------------------+ <- every take         worker 1: [ t4 ]       worker 2: [ ]  -> steals from 0
      ^   ^   ^   ^                                   worker 3: [ t6 t5 ]
      w0  w1  w2  w3   all on ONE lock + ONE line     plus one injection queue for tasks submitted from outside
```

* With short tasks, the critical section (push or pop) is about as long as the task itself. Each additional worker
  adds contention on the lock's cache line, and on Linux contended futex sleeps and wakes add system calls (⚠ not
  measured here). Listing 10.4: **59–124 ns per task with one worker, 169–248 ns with four**. More workers, more total
  time.
* At high core counts the same effect becomes a lock convoy: most CPU time goes into acquiring, waiting for, and
  handing over the lock, not into tasks. With 4 workers here it already costs 2–4× the single-worker time.

### 1.2 The Chase-Lev deque (Listings 10.2, 10.3)

```cpp
// chase_lev.hpp - the Chase-Lev work-stealing deque, in the C11 formulation of Le, Pop, Cohen and Zappa Nardelli (2013)
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>

// The owner pushes and pops at the BOTTOM (LIFO: the most recently spawned task, still warm in the cache).
// Thieves steal from the TOP (FIFO: the oldest task, typically the biggest piece of remaining work).
// Fixed capacity (a power of two); push reports full instead of growing, so no array reclamation is needed.
template <class T>
class ChaseLevDeque {
    static_assert(std::atomic<T>::is_always_lock_free, "slots must be lock-free atomics (stealers race with push)");
    const std::int64_t mask_;
    std::unique_ptr<std::atomic<T>[]> buf_;
    alignas(128) std::atomic<std::int64_t> top_{0};      // written by thieves (CAS) and by the owner's last-item pop
    alignas(128) std::atomic<std::int64_t> bottom_{0};   // written only by the owner

public:
    explicit ChaseLevDeque(std::int64_t capacity_pow2)
        : mask_(capacity_pow2 - 1), buf_(new std::atomic<T>[static_cast<std::size_t>(capacity_pow2)]) {}

    // Owner only.
    bool push(T x) {
        const std::int64_t b = bottom_.load(std::memory_order_relaxed);
        const std::int64_t t = top_.load(std::memory_order_acquire);
        if (b - t > mask_) return false;                                   // full
        buf_[static_cast<std::size_t>(b & mask_)].store(x, std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_release);              // the slot before the new bottom
        bottom_.store(b + 1, std::memory_order_relaxed);
        return true;
    }

    // Owner only. Claim the bottom slot first, then look at top: the seq_cst fence makes the owner and a thief that
    // race for the LAST element see each other (store bottom / load top vs load top / load bottom: the SB shape).
    bool pop(T& out) {
        const std::int64_t b = bottom_.load(std::memory_order_relaxed) - 1;
        bottom_.store(b, std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_seq_cst);
        std::int64_t t = top_.load(std::memory_order_relaxed);
        if (t > b) {                                                        // empty: undo
            bottom_.store(b + 1, std::memory_order_relaxed);
            return false;
        }
        out = buf_[static_cast<std::size_t>(b & mask_)].load(std::memory_order_relaxed);
        if (t < b) return true;                                             // more than one left: no race possible
        // Exactly one element: race the thieves for it with a CAS on top.
        const bool won = top_.compare_exchange_strong(t, t + 1, std::memory_order_seq_cst, std::memory_order_relaxed);
        bottom_.store(b + 1, std::memory_order_relaxed);
        return won;
    }

    // Any thread. Returns false if empty or if it lost a race (the caller simply tries elsewhere).
    bool steal(T& out) {
        std::int64_t t = top_.load(std::memory_order_acquire);
        std::atomic_thread_fence(std::memory_order_seq_cst);
        const std::int64_t b = bottom_.load(std::memory_order_acquire);
        if (t >= b) return false;
        out = buf_[static_cast<std::size_t>(t & mask_)].load(std::memory_order_relaxed);
        return top_.compare_exchange_strong(t, t + 1, std::memory_order_seq_cst, std::memory_order_relaxed);
    }

    std::int64_t size_estimate() const {
        return bottom_.load(std::memory_order_relaxed) - top_.load(std::memory_order_relaxed);
    }
};
```

```cpp
// chase_lev_test.cpp - one owner pushing and popping, three thieves stealing: every task runs exactly once
#include "chase_lev.hpp"

#include <atomic>
#include <cstdint>
#include <memory>
#include <print>
#include <thread>
#include <vector>

// Out-of-line copies for the assembly listing.
bool deque_pop(ChaseLevDeque<std::uint64_t>& d, std::uint64_t& out) { return d.pop(out); }
bool deque_steal(ChaseLevDeque<std::uint64_t>& d, std::uint64_t& out) { return d.steal(out); }
bool deque_push(ChaseLevDeque<std::uint64_t>& d, std::uint64_t x) { return d.push(x); }

#ifndef ASM_VIEW
int main() {
    constexpr std::uint64_t kTasks = 2'000'000;
    ChaseLevDeque<std::uint64_t> dq(1024);
    auto runs = std::make_unique<std::atomic<std::uint8_t>[]>(kTasks);   // how often each task id was executed
    std::atomic<bool> done{false};
    std::atomic<std::uint64_t> stolen{0}, popped{0};
    {
        std::vector<std::jthread> thieves;
        for (int i = 0; i < 3; ++i)
            thieves.emplace_back([&] {
                std::uint64_t mine = 0, id = 0;
                while (!done.load(std::memory_order_acquire) || dq.size_estimate() > 0)
                    if (dq.steal(id)) {
                        runs[id].fetch_add(1, std::memory_order_relaxed);
                        ++mine;
                    }
                stolen.fetch_add(mine);
            });
        // The owner: push in bursts of 64, then pop until empty or a quarter of the burst is gone.
        std::uint64_t next = 0, mine = 0, id = 0;
        while (next < kTasks) {
            for (int k = 0; k < 64 && next < kTasks; ++k)
                if (dq.push(next)) ++next;
            for (int k = 0; k < 16 && dq.pop(id); ++k) {
                runs[id].fetch_add(1, std::memory_order_relaxed);
                ++mine;
            }
        }
        while (dq.pop(id)) {
            runs[id].fetch_add(1, std::memory_order_relaxed);
            ++mine;
        }
        popped = mine;
        done.store(true, std::memory_order_release);
    }
    std::uint64_t never = 0, twice = 0;
    for (std::uint64_t i = 0; i < kTasks; ++i) {
        const unsigned r = runs[i].load();
        if (r == 0) ++never;
        if (r > 1) ++twice;
    }
    std::println("{} tasks, 1 owner + 3 thieves: every task executed exactly once: {}", kTasks,
                 never == 0 && twice == 0 ? "yes" : "NO");
    std::println("  owner popped {}, thieves stole {}; lost {}, duplicated {}", popped.load(), stolen.load(), never, twice);
}
#endif
```

Output (verified, GCC then Clang; the pop/steal split varies between runs):

```text
2000000 tasks, 1 owner + 3 thieves: every task executed exactly once: yes
  owner popped 778117, thieves stole 1221883; lost 0, duplicated 0
2000000 tasks, 1 owner + 3 thieves: every task executed exactly once: yes
  owner popped 975935, thieves stole 1024065; lost 0, duplicated 0
```

Clang 21 `-O3`, x86-64:

```asm
_Z9deque_popR13ChaseLevDequeImERm: # deque_pop(ChaseLevDeque<unsigned long>&, unsigned long&)
	movq	256(%rdi), %rdx
	leaq	-1(%rdx), %r8
	movq	%r8, 256(%rdi)
	lock	orl	$0, -64(%rsp)
	movq	128(%rdi), %rax
	cmpq	%rdx, %rax
	jge	.LBB0_1
	movq	(%rdi), %rcx
	andq	%r8, %rcx
	movq	8(%rdi), %r9
	movq	(%r9,%rcx,8), %rcx
	movq	%rcx, (%rsi)
	movb	$1, %cl
	cmpq	%r8, %rax
	jl	.LBB0_5
	leaq	1(%rax), %rcx
	lock	cmpxchgq	%rcx, 128(%rdi)
	sete	%cl
	jmp	.LBB0_4
.LBB0_1:
	xorl	%ecx, %ecx
.LBB0_4:
	movq	%rdx, 256(%rdi)
.LBB0_5:
	movl	%ecx, %eax
	retq

_Z11deque_stealR13ChaseLevDequeImERm: # deque_steal(ChaseLevDeque<unsigned long>&, unsigned long&)
	movq	128(%rdi), %rax
	lock	orl	$0, -64(%rsp)
	movq	256(%rdi), %rcx
	cmpq	%rcx, %rax
	jge	.LBB1_1
	movq	(%rdi), %rcx
	andq	%rax, %rcx
	movq	8(%rdi), %rdx
	movq	(%rdx,%rcx,8), %rcx
	movq	%rcx, (%rsi)
	leaq	1(%rax), %rcx
	lock	cmpxchgq	%rcx, 128(%rdi)
	sete	%al
	retq
.LBB1_1:
	xorl	%eax, %eax
	retq
```

AArch64:

```asm
_Z9deque_popR13ChaseLevDequeImERm: // deque_pop(ChaseLevDeque<unsigned long>&, unsigned long&)
	ldr	x9, [x0, #256]
	sub	x10, x9, #1
	str	x10, [x0, #256]
	dmb	ish
	ldr	x8, [x0, #128]
	cmp	x8, x9
	b.ge	.LBB0_3
	ldp	x11, x12, [x0]
	cmp	x8, x10
	and	x11, x11, x10
	ldr	x11, [x12, x11, lsl #3]
	str	x11, [x1]
	b.ge	.LBB0_4
	mov	w0, #1
	ret
.LBB0_3:
	mov	w8, wzr
	b	.LBB0_9
.LBB0_4:
	add	x10, x0, #128
	add	x11, x8, #1
.LBB0_5:
	ldaxr	x12, [x10]
	cmp	x12, x8
	b.ne	.LBB0_8
	stlxr	w12, x11, [x10]
	cbnz	w12, .LBB0_5
	mov	w8, #1
	b	.LBB0_9
.LBB0_8:
	mov	w8, wzr
	clrex
.LBB0_9:
	str	x9, [x0, #256]
	mov	w0, w8
	ret

_Z11deque_stealR13ChaseLevDequeImERm: // deque_steal(ChaseLevDeque<unsigned long>&, unsigned long&)
	add	x8, x0, #128
	add	x10, x0, #256
	ldar	x9, [x8]
	dmb	ish
	ldar	x10, [x10]
	cmp	x9, x10
	b.ge	.LBB1_5
	ldp	x10, x11, [x0]
	and	x10, x10, x9
	ldr	x10, [x11, x10, lsl #3]
	str	x10, [x1]
	add	x10, x9, #1
.LBB1_2:
	ldaxr	x11, [x8]
	cmp	x11, x9
	b.ne	.LBB1_6
	stlxr	w11, x10, [x8]
	cbnz	w11, .LBB1_2
	mov	w0, #1
	ret
.LBB1_5:
	mov	w0, wzr
	ret
.LBB1_6:
	mov	w0, wzr
	clrex
	ret
```

* **The common case has no RMW.** `push` is a store into the slot, a release fence (free on x86), and a store of
  `bottom`. `pop` decrements `bottom` and reads `top`. A CAS appears only when exactly one element is left (the owner
  and a thief may both want it) and in `steal`.
* **The fence in `pop` is the store-buffering pattern again** (Folder 07). The owner *stores* `bottom = b` and then
  *loads* `top`; a thief *loads* `top` and then *loads* `bottom`. Without a `seq_cst` fence between the owner's store
  and load, the owner could read a stale `top` while the thief reads the old `bottom`, and both would take the last
  element. That bug appears on x86 too, because SB is the one reordering TSO allows. In the asm it is `lock orl $0,
  -64(%rsp)` on x86 and `dmb ish` on AArch64. The C11 paper (Lê et al., PPoPP 2013) proves this placement correct; the
  original 2005 algorithm assumed sequential consistency.
* **Slots are atomics (relaxed).** A thief reads `buf[t]` while the owner may be overwriting that slot after wrapping
  around. The thief's CAS then fails, but the read must not be a data race.
* **Verified:** 2,000,000 tasks, every one executed exactly once on both compilers. The thieves took 1.02–1.22 million
  of them.
* **Fixed capacity.** The original deque grows by allocating a bigger array, but thieves may still be reading the old
  one, which is the memory-reclamation problem of Folder 09. Production deques keep old arrays alive (epochs, hazard
  pointers) or never shrink. Here `push` reports full and the pool falls back to the injection queue.

### 1.3 The pool, measured (Listing 10.4)

```cpp
// pool_bench.cpp - one mutex-protected task queue vs a work-stealing pool (per-worker Chase-Lev deques) on a spawn tree
#include "chase_lev.hpp"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

struct Task {
    void (*fn)(Task*);
    void* pool;
    int depth;
};

constexpr int kMaxWorkers = 8;
struct alignas(128) Counter {
    std::atomic<std::uint64_t> v{0};   // single writer (its worker): relaxed load + store, no RMW
};
inline Counter g_leaves[kMaxWorkers];
inline thread_local int t_worker = -1;  // index of the pool worker running on this thread, -1 outside pools

inline void leaf_work() {
    std::uint64_t x = 88172645463325252ULL;
    for (int i = 0; i < 16; ++i) x ^= x << 13, x ^= x >> 7, x ^= x << 17;   // ~10 ns of work
    if (x == 0) std::println("unreachable");
}

// Both pools let idle workers poll with yield() so the comparison is only about how tasks are handed out.
class CentralPool {
    std::mutex m_;
    std::deque<Task*> q_;
    std::atomic<bool> stop_{false};
    std::vector<std::jthread> threads_;

public:
    explicit CentralPool(int n) {
        for (int i = 0; i < n; ++i)
            threads_.emplace_back([this, i] {
                t_worker = i;
                while (!stop_.load(std::memory_order_acquire)) {
                    Task* t = nullptr;
                    {
                        std::scoped_lock lk(m_);
                        if (!q_.empty()) {
                            t = q_.front();
                            q_.pop_front();
                        }
                    }
                    if (t) t->fn(t);
                    else std::this_thread::yield();
                }
            });
    }
    ~CentralPool() { stop_.store(true, std::memory_order_release); }
    void submit(Task* t) {
        std::scoped_lock lk(m_);   // every spawn, from every worker, takes the same lock
        q_.push_back(t);
    }
    std::uint64_t steals() const { return 0; }
};

class WorkStealingPool {
    struct alignas(128) Worker {
        ChaseLevDeque<Task*> dq{1 << 16};
        std::uint64_t steals = 0;
    };
    std::vector<std::unique_ptr<Worker>> workers_;
    std::mutex inject_m_;              // only for tasks submitted from outside the pool
    std::deque<Task*> inject_;
    std::atomic<bool> stop_{false};
    std::vector<std::jthread> threads_;

    Task* find_work(int self) {
        Task* t = nullptr;
        if (workers_[static_cast<std::size_t>(self)]->dq.pop(t)) return t;   // own deque, LIFO: cache-warm
        const int n = static_cast<int>(workers_.size());
        for (int k = 1; k < n; ++k) {                                      // steal FIFO from the others
            if (workers_[static_cast<std::size_t>((self + k) % n)]->dq.steal(t)) {
                ++workers_[static_cast<std::size_t>(self)]->steals;
                return t;
            }
        }
        std::scoped_lock lk(inject_m_);
        if (inject_.empty()) return nullptr;
        t = inject_.front();
        inject_.pop_front();
        return t;
    }

public:
    explicit WorkStealingPool(int n) {
        for (int i = 0; i < n; ++i) workers_.push_back(std::make_unique<Worker>());
        for (int i = 0; i < n; ++i)
            threads_.emplace_back([this, i] {
                t_worker = i;
                while (!stop_.load(std::memory_order_acquire)) {
                    if (Task* t = find_work(i)) t->fn(t);
                    else std::this_thread::yield();
                }
            });
    }
    ~WorkStealingPool() { stop_.store(true, std::memory_order_release); }
    void submit(Task* t) {
        if (t_worker >= 0 && workers_[static_cast<std::size_t>(t_worker)]->dq.push(t)) return;   // no lock
        std::scoped_lock lk(inject_m_);
        inject_.push_back(t);
    }
    std::uint64_t steals() const {
        std::uint64_t s = 0;
        for (const auto& w : workers_) s += w->steals;   // read after the workers are idle
        return s;
    }
};

// The workload: a binary spawn tree. Each inner task spawns two children; leaves do ~10 ns of work.
template <class Pool>
void tree_task(Task* t) {
    auto* pool = static_cast<Pool*>(t->pool);
    const int d = t->depth;
    if (d == 0) {
        leaf_work();
        auto& c = g_leaves[t_worker].v;
        c.store(c.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
        delete t;
        return;
    }
    t->depth = d - 1;                                    // reuse this task object as the first child
    pool->submit(t);
    pool->submit(new Task{&tree_task<Pool>, pool, d - 1});
}

template <class Pool>
double run(int workers, int depth, std::uint64_t& steals) {
    for (Counter& c : g_leaves) c.v.store(0);
    const std::uint64_t leaves = std::uint64_t{1} << depth;
    const auto t0 = std::chrono::steady_clock::now();
    double ns = 0;
    {
        Pool pool(workers);
        pool.submit(new Task{&tree_task<Pool>, &pool, depth});
        for (;;) {
            std::uint64_t done = 0;
            for (const Counter& c : g_leaves) done += c.v.load(std::memory_order_relaxed);
            if (done == leaves) break;
            std::this_thread::yield();
        }
        const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
        ns = d.count() / static_cast<double>(2 * leaves - 1);   // per task (inner + leaf)
        steals = pool.steals();
    }
    return ns;
}

int main() {
    constexpr int kDepth = 19;   // 2^19 leaves, ~1M tasks
    std::println("spawn tree, {} tasks: ns per task (wall time / tasks); lower is better", (2u << kDepth) - 1);
    std::println("workers   one mutex-protected deque   work-stealing (Chase-Lev)   steals");
    for (int w : {1, 2, 4}) {
        std::uint64_t s0 = 0, s1 = 0;
        const double central = run<CentralPool>(w, kDepth, s0);
        const double ws = run<WorkStealingPool>(w, kDepth, s1);
        std::println("{:>7}   {:>25.1f}   {:>25.1f}   {:>6}", w, central, ws, s1);
    }
}
```

Output (verified, GCC then Clang):

```text
spawn tree, 1048575 tasks: ns per task (wall time / tasks); lower is better
workers   one mutex-protected deque   work-stealing (Chase-Lev)   steals
      1                        74.7                        53.3        0
      2                       164.8                        30.5        4
      4                       246.9                        19.6       35
spawn tree, 1048575 tasks: ns per task (wall time / tasks); lower is better
workers   one mutex-protected deque   work-stealing (Chase-Lev)   steals
      1                        58.7                        39.0        0
      2                       107.7                        24.8       12
      4                       168.5                        22.9       49
```

| workers | single mutex-protected queue | work-stealing (Chase-Lev) | steals per ~1M tasks |
|---|---|---|---|
| 1 | 59–124 ns per task | 39–53 ns | 0 |
| 2 | 108–176 ns | 21–34 ns | 4–12 |
| 4 | 169–248 ns | 9–23 ns | 30–49 |

(Two runs per compiler; ranges include both compilers. GCC is slower in both pools partly because `t_worker` is a
`thread_local`, emulated TLS on MinGW, Folder 08.)

* **The spawn tree is depth-first on each worker.** The owner pops its newest task (LIFO), so it keeps descending into
  one subtree with its data warm in the cache, and its deque never holds more than about *depth* tasks.
* **Thieves take the oldest task (FIFO)**, which sits near the root and is the *largest* remaining subtree. One steal
  gives a thief half a million tasks of work, which is why ~1M tasks needed only 4–49 steals. Steals are expensive (a
  CAS on another core's line), and the design makes them rare.
* **The injection queue** is still a mutex-protected queue, used only for tasks submitted from outside the pool. In
  this benchmark that's one task.

### 1.4 Task graphs

* **Fork-join** (this benchmark, Cilk, TBB's `task_group`): a parent spawns children and either continues without
  waiting (this tree), or waits. A *waiting* worker must not block its thread: it runs other tasks from its own deque or
  steals while it waits ("help while waiting"), or it uses continuation passing, where the last child to finish runs
  the parent's continuation.
* **DAGs with dependency counters:** each node holds an `atomic<int>` of unfinished predecessors. Finishing a node
  decrements its successors' counters, and whichever decrement reaches zero pushes that successor onto the *current*
  worker's deque. No locks, and ready work stays on the core that produced its inputs (Folder 11, problem 9).
* **Child stealing vs continuation stealing:** this pool lets thieves take *children* (TBB, most C++ pools). Cilk lets
  thieves take the parent's *continuation*, which gives tighter space bounds but needs compiler support for capturing
  continuations. C++20 coroutines make continuation stealing possible in libraries (file 03).

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| pools in the standard | none (`std::async` only) | — | parallel algorithms with execution policies (the pool is the implementation's) | `std::jthread`, `latch`, `barrier`, `counting_semaphore` | `move_only_function` for task storage | `std::execution` schedulers (P2300); `system_context`/`parallel_scheduler` (P2079) |
| algorithms | — | — | `std::execution::par`, `par_unseq` | `unseq` | — | parallel algorithms gain sender-based forms (proposals) |
| industry practice | TBB, PPL, Cilk | — | — | — | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| many small tasks | one `mutex` + `std::queue` + condition variable (slower with more workers, Listing 10.4) | per-worker Chase-Lev deques + an injection queue |
| a task waits for subtasks | `future.get()` inside a pool thread (starvation deadlock, file 01) | help while waiting, continuations, or `co_await` (file 03) |
| Chase-Lev from a paper or blog | the 2005 version with no fences, or acquire/release only | Lê et al.'s C11 orders: `seq_cst` fences in `pop` and `steal`, CAS on `top` |
| deque growth | `delete` the old array when growing | keep old arrays (epoch/hazard reclamation) or use a fixed capacity with an overflow queue |
| idle workers | spin forever | spin briefly, then park on `atomic::wait`/a futex with a "sleepers" counter so submitters notify only when needed |
| latency-sensitive request serving | pure LIFO local queues (old tasks can starve) | a FIFO per-worker queue plus a LIFO slot for the newest task (Tokio's design), or separate pools per priority |
| pool size | `hardware_concurrency()` threads that also block on I/O | CPU pool sized to cores (or physical cores); blocking work on a separate pool or async I/O |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| throughput falls as threads are added | one shared queue/lock (Listing 10.4) | ns/task vs worker count; lock-contention profiles |
| a task occasionally runs twice | last-element race without the `seq_cst` fence or CAS | exact-once stress test (Listing 10.3) on x86 and ARM |
| pool freezes under load | workers blocked waiting for tasks queued behind them | thread dumps show all workers in `get()`/`wait()` |
| crash after deque growth | old array freed while a thief reads it | ASan; deferred reclamation |
| tail latency spikes | LIFO scheduling starving old tasks | per-task queueing-time histograms |
| CPU at 100% with no work | idle workers spinning forever | park after a bounded spin |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Our pool doesn't scale past a few cores"</b></summary>

**Initial prompt.** "A pool with `std::mutex` + `std::queue<std::function<void()>>` and a condition variable gets
slower when we go from 8 to 64 threads on short tasks. Why, and what would you build?"

**L5 textbook answer.** "Use a lock-free queue instead of the mutex."

**Why L5 breaks.** The problem is the *single* queue, not the lock type. Every push and pop touches one hot cache line;
a lock-free MPMC queue still bounces that line between all cores (Folder 09: lock-free queues lost to a mutex under
contention). Listing 10.4 already shows the trend with 4 workers: 59–124 ns per task with one worker, 169–248 ns with
four. And `std::function` adds an allocation per task when the callable doesn't fit its small buffer (Folder 04).

**L7 principal defense.** "Per-worker Chase-Lev deques with stealing: the owner's push and pop don't touch shared
lines in the common case, and steals are rare (4–49 per million tasks here) because thieves take the oldest, biggest
tasks. An injection queue for external submissions, tasks stored without allocation where possible, and idle workers
that park instead of spinning. Measured: 9–23 ns per task at 4 workers, scaling the right way."
</details>

<details><summary><b>Chain 2 ⚡ "Why LIFO for the owner, FIFO for thieves?"</b></summary>

**Initial prompt.** "Why does a work-stealing deque pop from one end and steal from the other?"

**L5 textbook answer.** "To avoid conflicts between the owner and thieves."

**Why L5 breaks.** Avoiding conflicts is a side effect; the main reasons are locality and granularity. The owner pops
the task it spawned most recently, whose data is still in its cache, and descends depth-first, so its deque stays about
*depth* long. Thieves take the oldest task, which in fork-join code is the largest remaining subtree: one steal moves a
lot of work, so steals (each a CAS on another core's line) stay rare: 4–49 for ~1M tasks in Listing 10.4.

**L7 principal defense.** "LIFO-local keeps the cache warm and memory bounded; FIFO-steal maximizes work per steal.
The ends also only meet when the deque has about one element, which is exactly where the algorithm pays for a CAS."
</details>

<details><summary><b>Chain 3 🔥 "Why is there a seq_cst fence in pop?"</b></summary>

**Initial prompt.** "In Chase-Lev `pop`, the owner stores `bottom` and then reads `top`. It owns `bottom`, so why the
full fence? Release/acquire should do."

**L5 textbook answer.** "The fence is conservative; acquire/release is enough because the owner's store is a release."

**Why L5 corrupts memory on ARM64.** It's the SB pattern: owner *store bottom, load top*; thief *load top, load
bottom*. Release/acquire doesn't order a store before a *later* load, so the owner can read the old `top` while the thief
reads the old `bottom`. Both conclude the last element is theirs, the owner without a CAS, and the task runs twice: a
corrupted result or a double free. This can happen on x86 too (SB is the reordering TSO allows), and on ARM64 more
easily. Lê et al. needed exactly this fence to make the C11 version correct.

**L7 principal defense.** "The `seq_cst` fence between `bottom = b` and `load top` in `pop`, and between the loads in
`steal` (Listing 10.2), cost a `LOCK OR` or `DMB ISH` (asm above). Plus an exact-once stress test like Listing 10.3 on
ARM hardware in CI, because that's where the reorderings show."
</details>

<details><summary><b>Chain 4 🧊 "The owner doesn't need a CAS: it owns bottom"</b></summary>

**Initial prompt.** "Why does `pop` ever CAS? Only the owner changes `bottom`."

**L5 textbook answer.** "It doesn't need one; thieves only touch `top`."

**Why L5 breaks.** When one element is left (`top == bottom - 1`), a thief can be taking that same element by
incrementing `top`. The owner can't claim it by writing `bottom` alone, because the thief doesn't read `bottom` again
after its decision. Both sides must agree through `top`, so the owner CASes `top` from `t` to `t + 1`: whoever wins the
CAS gets the element (Listing 10.2: `if (t < b) return true;` is the no-race fast path, and the CAS is the slow path).

**L7 principal defense.** "The deque is wait-free for the owner except at the last element, where owner and thieves
race through one CAS on `top`. That's the whole algorithm in one sentence."
</details>

<details><summary><b>Chain 5 ⚡ "How many threads should the pool have?"</b></summary>

**Initial prompt.** "We size our pool to `std::thread::hardware_concurrency()`. Good default?"

**L5 textbook answer.** "Yes, one thread per hardware thread is optimal."

**Why L5 breaks.** It depends on what tasks do. Tasks that block on I/O or locks leave cores idle, so the pool is
undersized. CPU-bound tasks on SMT machines share a core's execution units, so 12 threads on 6 cores (this machine) may
not beat 6. Containers and CPU affinity masks give `hardware_concurrency()` values that don't match the CPUs the
process may use. And several pools in one process (a library's plus yours) oversubscribe.

**L7 principal defense.** "CPU pool = the cores this process may run on (affinity- and cgroup-aware), with blocking
work on a separate pool or async I/O. One pool per process where possible, shared by libraries. And measure:
ns/task vs workers, the shape of Listing 10.4."
</details>

<details><summary><b>Chain 6 🔥 "A task waits for its children"</b></summary>

**Initial prompt.** "Our parallel quicksort task spawns two subtasks and waits for both before returning. On a
work-stealing pool, is that safe?"

**L5 textbook answer.** "Yes, work stealing balances the load automatically."

**Why L5 deadlocks on ARM64.** Only if *waiting* doesn't block the worker thread. If the parent blocks (a future
`get()`, a condition variable), it holds a worker while its children may be queued in its own deque, which only it pops.
With deep recursion every worker ends up blocked on children nobody runs: a deadlock on any architecture.

**L7 principal defense.** "The wait executes work: pop own children first, then steal, until the join counter
reaches zero (TBB's `task_group::wait`, Cilk's sync). Or continuation passing: the parent returns, and the last child to
finish runs the continuation. Or coroutines: `co_await` suspends the *task* and frees the thread (file 03)."
</details>

<details><summary><b>Chain 7 🧊 "Make the deque growable"</b></summary>

**Initial prompt.** "Our Chase-Lev deque is fixed-size. Add growth when `push` finds it full."

**L5 textbook answer.** "Allocate a double-size array, copy the elements, swap the pointer, delete the old array."

**Why L5 corrupts memory on ARM64.** A thief may have loaded the old array pointer and be about to read a slot from it.
Deleting the old array is a use-after-free. And the new pointer must be published so that a thief that sees the new
`bottom` also sees the new array (release/acquire on the array pointer, as in the C11 algorithm's `array.load(consume)`,
which compilers treat as acquire).

**L7 principal defense.** "Never free the old array while thieves can read it: keep it until an epoch passes or no
thief protects it (Folder 09's EBR or hazard pointers), or keep retired arrays for the pool's lifetime (they're
geometrically sized, so the waste is bounded at 2×). Or don't grow: overflow to the injection queue, as Listing 10.4
does."
</details>

<details><summary><b>Chain 8 ⚡ "Work stealing for a request server?"</b></summary>

**Initial prompt.** "Our RPC server runs request handlers on a work-stealing pool. p99 latency is bad under load,
throughput is fine. Why?"

**L5 textbook answer.** "Work stealing is the fastest scheduler; add servers."

**Why L5 breaks.** Work stealing optimizes *throughput* of fork-join work. LIFO local popping always runs the
newest task first. Under sustained load, older tasks at the top of a busy worker's deque wait until someone steals
them, which in a balanced system rarely happens. The old requests, the ones already close to their deadline, wait
longest. That's good for cache warmth and bad for tail latency.

**L7 principal defense.** "For request handling: FIFO per-worker queues with stealing, plus a single 'LIFO slot' for
the most recently spawned task to keep message-passing chains hot (Tokio's scheduler does this), or deadline-aware
queues. CPU-heavy fork-join work goes to a separate work-stealing pool."
</details>

---

## 6. Invariants checklist

- [ ] No single shared task queue on the hot path; per-worker deques with stealing.
- [ ] Chase-Lev uses the Lê et al. orders: `seq_cst` fences in `pop` and `steal`, CAS on `top` for the last element
      and for steals, atomic slots.
- [ ] Old deque arrays are never freed while thieves may read them.
- [ ] No pool task blocks its thread waiting for work in the same pool.
- [ ] Idle workers park after a bounded spin.
- [ ] Pool scaling is measured as ns/task vs worker count.

## 7. References

- D. Chase, Y. Lev, "Dynamic Circular Work-Stealing Deque", SPAA 2005: <https://www.dre.vanderbilt.edu/~schmidt/PDF/work-stealing-dequeue.pdf>
- N. M. Lê, A. Pop, A. Cohen, F. Zappa Nardelli, "Correct and Efficient Work-Stealing for Weak Memory Models", PPoPP 2013: <https://fzn.fr/readings/ppopp13.pdf>
- R. Blumofe, C. Leiserson, "Scheduling Multithreaded Computations by Work Stealing", JACM 46(5), 1999, DOI 10.1145/324133.324234
- Tokio, "Making the Tokio scheduler 10x faster" (LIFO slot, work stealing): <https://tokio.rs/blog/2019-10-scheduler>
- P2079 (`std::execution` system context / parallel scheduler): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p2079r10.html>
