# 03 · Treiber lock-free stack, Michael-Scott queue, and lock-free hash tables

> **Scope.** The three classic lock-free structures, built so that they are correct in C++ and not just "usually
> works": tagged indices instead of raw pointers (no ABA), type-stable node pools (no use-after-free), and atomic
> fields wherever two threads can touch the same memory, even "benignly". The measurements are blunt. **Against a
> plain mutex, the lock-free stack and queue lose 2–4×**, because every thread hits the same one or two words. The
> lock-free hash map wins by 10–30×, because its threads don't share hot words. The lesson for interviews and for
> production is the same: contention decides throughput, and lock-freedom decides progress.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 9.5 | `treiber_stack.cpp` | Treiber stacks over an index + 32-bit-tag head (one 64-bit CAS): 2M rounds on 4 threads, every value consumed once, all nodes returned; **206–291 ns per round vs 52–59 ns with a mutex** | run, 4 threads, both compilers; asm x86-64 + AArch64 |
| 9.6 | `ms_queue.cpp` | the Michael-Scott queue with counted (tagged) indices, a dummy node, tail helping, value read before the CAS: every item once, FIFO per producer; **257–298 ns per item vs 126–143 ns with a mutex** | run, 2 producers + 2 consumers, both compilers |
| 9.7 | `lf_hash.cpp` | an insert/update/find lock-free map (linear probing, keys claimed by CAS): **9–12 ns inserts, 16–19 ns lookups vs 137–489 ns / 107–525 ns for mutex maps**; 1M keys found, 0 wrong answers | run, 4 threads, both compilers |

**Verification line.** As in file 01. Benchmarks are unpinned and use 4 threads; ranges are over two runs per
compiler.

---

## 1. First principles

### 1.1 The Treiber stack (Listing 9.5)

```cpp
// treiber_stack.cpp - a lock-free Treiber stack over a node pool: 32-bit index + 32-bit tag in one 64-bit CAS
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

constexpr std::uint32_t kNil = 0xFFFF'FFFF;

struct Node {
    std::atomic<std::uint32_t> next{kNil};   // atomic: a popper may read it while the node is being recycled
    std::uint64_t value = 0;                 // only touched by the thread that owns the node
};

// head = (tag << 32) | index. Indices instead of pointers: the tag gets 32 bits, any 64-bit CAS works
// (no CMPXCHG16B/CASP), and nodes live in a pool that is never returned to the OS ("type-stable memory"),
// so reading a recycled node's `next` is safe; the tag makes the CAS that would use it fail.
class IndexStack {
    std::atomic<std::uint64_t> head_{kNil};
    Node* nodes_;
    static std::uint32_t idx(std::uint64_t w) { return static_cast<std::uint32_t>(w); }
    static std::uint64_t tag(std::uint64_t w) { return w >> 32; }
    static std::uint64_t make(std::uint32_t i, std::uint64_t t) { return (t << 32) | i; }

public:
    explicit IndexStack(Node* nodes) : nodes_(nodes) {}
    void push(std::uint32_t i) {
        std::uint64_t old = head_.load(std::memory_order_relaxed);
        do nodes_[i].next.store(idx(old), std::memory_order_relaxed);
        while (!head_.compare_exchange_weak(old, make(i, tag(old) + 1), std::memory_order_release,
                                            std::memory_order_relaxed));
    }
    std::uint32_t pop() {
        std::uint64_t old = head_.load(std::memory_order_acquire);
        while (idx(old) != kNil) {
            const std::uint32_t next = nodes_[idx(old)].next.load(std::memory_order_relaxed);
            if (head_.compare_exchange_weak(old, make(next, tag(old) + 1), std::memory_order_acquire,
                                            std::memory_order_acquire))
                return idx(old);
        }
        return kNil;
    }
};

std::uint32_t stack_pop(IndexStack& s) { return s.pop(); }         // out-of-line copies for the asm listing
void stack_push(IndexStack& s, std::uint32_t i) { s.push(i); }

#ifndef ASM_VIEW
using Clock = std::chrono::steady_clock;

int main() {
    constexpr std::uint32_t kNodes = 1024;
    constexpr int kThreads = 4, kRounds = 500'000;
    // Lock-free: every thread repeatedly takes a node from the free stack, fills it, pushes it on the data stack,
    // pops some node from the data stack, consumes it, and returns it to the free stack.
    auto nodes = std::make_unique<Node[]>(kNodes);
    IndexStack free_stack(nodes.get()), data(nodes.get());
    for (std::uint32_t i = 0; i < kNodes; ++i) free_stack.push(i);
    std::atomic<std::uint64_t> produced{0}, consumed{0};
    auto t0 = Clock::now();
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < kThreads; ++t)
            ts.emplace_back([&, t] {
                std::uint64_t p = 0, c = 0;
                for (int r = 1; r <= kRounds; ++r) {
                    const std::uint32_t i = free_stack.pop();
                    nodes[i].value = static_cast<std::uint64_t>(t) * 1'000'000 + static_cast<std::uint64_t>(r);
                    p += nodes[i].value;
                    data.push(i);
                    const std::uint32_t j = data.pop();   // never empty: this thread just pushed one
                    c += nodes[j].value;
                    free_stack.push(j);
                }
                produced.fetch_add(p);
                consumed.fetch_add(c);
            });
    }
    std::chrono::duration<double, std::nano> d = Clock::now() - t0;
    const double lf_ns = d.count() / (kThreads * kRounds);
    std::uint32_t count = 0;
    while (free_stack.pop() != kNil) ++count;
    std::println("index+tag Treiber stacks, {} threads x {} rounds: {:5.1f} ns per round (4 CAS operations)", kThreads,
                 kRounds, lf_ns);
    std::println("  every value consumed exactly once: {}; all {} nodes back in the free stack: {}",
                 produced.load() == consumed.load() ? "yes" : "NO", kNodes, count == kNodes ? "yes" : "NO");

    // The same workload with one mutex around a std::vector stack.
    std::mutex m;
    std::vector<std::uint64_t> stack;
    t0 = Clock::now();
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < kThreads; ++t)
            ts.emplace_back([&, t] {
                for (int r = 1; r <= kRounds; ++r) {
                    {
                        std::scoped_lock lk(m);
                        stack.push_back(static_cast<std::uint64_t>(t) * 1'000'000 + static_cast<std::uint64_t>(r));
                    }
                    std::scoped_lock lk(m);
                    stack.pop_back();
                }
            });
    }
    d = Clock::now() - t0;
    std::println("std::mutex + std::vector, same pattern:           {:5.1f} ns per round (2 lock/unlock pairs)",
                 d.count() / (kThreads * kRounds));
}
#endif
```

Output (verified, GCC then Clang):

```text
index+tag Treiber stacks, 4 threads x 500000 rounds: 291.3 ns per round (4 CAS operations)
  every value consumed exactly once: yes; all 1024 nodes back in the free stack: yes
std::mutex + std::vector, same pattern:            53.9 ns per round (2 lock/unlock pairs)
index+tag Treiber stacks, 4 threads x 500000 rounds: 254.7 ns per round (4 CAS operations)
  every value consumed exactly once: yes; all 1024 nodes back in the free stack: yes
std::mutex + std::vector, same pattern:            52.2 ns per round (2 lock/unlock pairs)
```

Clang 21 `-O3`, x86-64:

```asm
_Z9stack_popR10IndexStack:         # stack_pop(IndexStack&)
	movq	(%rdi), %rcx
	movl	$-1, %eax
	cmpl	$-1, %ecx
	je	.LBB0_6
	movabsq	$-4294967296, %rdx
	movabsq	$4294967296, %rsi
.LBB0_2:
	movq	8(%rdi), %rax
	movl	%ecx, %r8d
	shlq	$4, %r8
	movl	(%rax,%r8), %r8d
	movq	%rcx, %rax
	andq	%rdx, %rax
	orq	%rax, %r8
	addq	%rsi, %r8
	movq	%rcx, %rax
	lock	cmpxchgq	%r8, (%rdi)
	je	.LBB0_3
	movq	%rax, %rcx
	cmpl	$-1, %eax
	jne	.LBB0_2
	movl	$-1, %eax
.LBB0_6:
	retq
.LBB0_3:
	movl	%ecx, %eax
	retq

_Z10stack_pushR10IndexStackj:      # stack_push(IndexStack&, unsigned int)
	movabsq	$-4294967296, %rcx
	movq	(%rdi), %rax
	movl	%esi, %edx
	movabsq	$4294967296, %rsi
	orq	%rdx, %rsi
	movq	8(%rdi), %r8
	shlq	$4, %rdx
.LBB1_2:
	movl	%eax, (%r8,%rdx)
	movq	%rax, %r8
	andq	%rcx, %r8
	addq	%rsi, %r8
	lock	cmpxchgq	%r8, (%rdi)
	je	.LBB1_3
	movq	8(%rdi), %r8
	jmp	.LBB1_2
.LBB1_3:
	retq
```

AArch64 (ARMv8.0):

```asm
_Z9stack_popR10IndexStack:         // stack_pop(IndexStack&)
	mov	x8, x0
	ldar	x0, [x0]
	cmn	w0, #1
	b.eq	.LBB0_6
	mov	x9, #4294967296
.LBB0_2:
	mov	w10, w0
	ldr	x11, [x8, #8]
	lsl	x10, x10, #4
	ldr	w11, [x11, x10]
	ldaxr	x10, [x8]
	cmp	x10, x0
	b.ne	.LBB0_4
	and	x12, x0, #0xffffffff00000000
	orr	x11, x12, x11
	add	x11, x11, x9
	stxr	w12, x11, [x8]
	cmp	w12, #0
	csetm	w11, eq
	tbz	w11, #0, .LBB0_5
	b	.LBB0_7
.LBB0_4:
	mov	w11, wzr
	clrex
	tbnz	w11, #0, .LBB0_7
.LBB0_5:
	cmn	w10, #1
	mov	x0, x10
	b.ne	.LBB0_2
.LBB0_6:
	mov	w0, #-1
.LBB0_7:
	ret

_Z10stack_pushR10IndexStackj:      // stack_push(IndexStack&, unsigned int)
	ldr	x11, [x0]
	ldr	x8, [x0, #8]
	ubfiz	x9, x1, #4, #32
	mov	w10, w1
	str	w11, [x8, x9]
	orr	x8, x10, #0x100000000
	ldxr	x9, [x0]
	cmp	x9, x11
	b.ne	.LBB1_2
	and	x11, x11, #0xffffffff00000000
	add	x11, x11, x8
	stlxr	w12, x11, [x0]
	cmp	w12, #0
	csetm	w11, eq
	tbz	w11, #0, .LBB1_3
	b	.LBB1_7
.LBB1_2:
	mov	w11, wzr
	clrex
	tbnz	w11, #0, .LBB1_7
.LBB1_3:
	lsl	x10, x10, #4
	b	.LBB1_5
.LBB1_4:
	mov	w12, wzr
	clrex
	mov	x9, x11
	tbnz	w12, #0, .LBB1_7
.LBB1_5:
	ldr	x11, [x0, #8]
	str	w9, [x11, x10]
	ldxr	x11, [x0]
	cmp	x11, x9
	b.ne	.LBB1_4
	and	x9, x9, #0xffffffff00000000
	add	x9, x9, x8
	stlxr	w12, x9, [x0]
	cmp	w12, #0
	csetm	w12, eq
	mov	x9, x11
	tbz	w12, #0, .LBB1_5
.LBB1_7:
	ret
```

* **Push** links the new node to the current head and CASes the head to it. **Pop** reads the head, reads its `next`,
  and CASes the head to `next`. Release on push and acquire on pop give the message-passing edge for the node's value.
* **Index + tag in 64 bits.** The head is `(tag << 32) | index`. Every successful CAS increments the tag (`addq %rsi`
  with `rsi = 1 << 32`), so the ABA of file 01 is impossible for 2^32 updates. It is one plain 64-bit `LOCK CMPXCHG`
  (`LDAXR`/`STXR` on ARMv8.0): no DWCAS, no top-bit tricks, portable everywhere. On AArch64 the `LDR` of `next` comes
  *before* the `LDAXR`, which is why LL/SC doesn't prevent ABA (file 01, Chain 5).
* **Type-stable memory.** Nodes live in a pool that is never returned to the OS, so a popper that reads a recycled
  node's `next` reads valid memory; the tag makes its CAS fail. `next` is `std::atomic<uint32_t>` (relaxed): a popper can
  read it while the node's new owner writes it, and a plain field there would be a data race even though the algorithm
  discards the value.
* **Why it lost to a mutex 4×.** Each round does 4 CASes on two heads that all 4 threads hit. Every failed CAS is a
  cache-line round trip, and contention makes failures likely. The mutex version also bounces its lock line, but it does
  only 2 lock/unlock pairs per round, and a thread that holds the lock finishes its tiny section without retrying. The known remedy for hot-spot
  stacks is not a better CAS but less contention: an elimination back-off array (a push and a pop that meet cancel out
  without touching the head), per-thread caches, or flat combining.

### 1.2 The Michael-Scott queue (Listing 9.6)

```cpp
// ms_queue.cpp - the Michael-Scott lock-free queue (1996): a dummy node, CAS on both ends, helping a lagging tail
#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

constexpr std::uint32_t kNil = 0xFFFF'FFFF;
using Tagged = std::uint64_t;   // (tag << 32) | node index, the paper's "counted pointer"
inline std::uint32_t idx(Tagged w) { return static_cast<std::uint32_t>(w); }
inline std::uint64_t tag(Tagged w) { return w >> 32; }
inline Tagged make(std::uint32_t i, std::uint64_t t) { return (t << 32) | i; }

struct Node {
    std::atomic<Tagged> next{make(kNil, 0)};
    std::atomic<std::uint64_t> value{0};   // atomic: a dequeuer reads it BEFORE its CAS, possibly from a recycled node
};

class MsQueue {
    std::unique_ptr<Node[]> nodes_;
    std::atomic<Tagged> free_{make(kNil, 0)};       // a Treiber stack of free node indices (file 03, Listing 9.5)
    alignas(128) std::atomic<Tagged> head_;
    alignas(128) std::atomic<Tagged> tail_;

    std::uint32_t alloc() {
        Tagged old = free_.load(std::memory_order_acquire);
        while (idx(old) != kNil) {
            const std::uint32_t next = idx(nodes_[idx(old)].next.load(std::memory_order_relaxed));
            if (free_.compare_exchange_weak(old, make(next, tag(old) + 1), std::memory_order_acquire)) return idx(old);
        }
        return kNil;
    }
    void release(std::uint32_t i) {
        Tagged old = free_.load(std::memory_order_relaxed);
        for (;;) {
            const Tagged n = nodes_[i].next.load(std::memory_order_relaxed);
            nodes_[i].next.store(make(idx(old), tag(n) + 1), std::memory_order_relaxed);   // keep next's tag rising
            if (free_.compare_exchange_weak(old, make(i, tag(old) + 1), std::memory_order_release)) return;
        }
    }

public:
    explicit MsQueue(std::uint32_t capacity) : nodes_(std::make_unique<Node[]>(capacity + 1)) {
        for (std::uint32_t i = 1; i <= capacity; ++i) release(i);
        head_.store(make(0, 0));   // node 0 is the initial dummy
        tail_.store(make(0, 0));
    }
    bool enqueue(std::uint64_t v) {
        const std::uint32_t n = alloc();
        if (n == kNil) return false;
        nodes_[n].value.store(v, std::memory_order_relaxed);
        const Tagged nn = nodes_[n].next.load(std::memory_order_relaxed);
        nodes_[n].next.store(make(kNil, tag(nn) + 1), std::memory_order_relaxed);
        for (;;) {
            Tagged tail = tail_.load(std::memory_order_acquire);
            Tagged next = nodes_[idx(tail)].next.load(std::memory_order_acquire);
            if (tail != tail_.load(std::memory_order_acquire)) continue;          // tail moved under us
            if (idx(next) == kNil) {                                              // tail is the last node: link n
                if (nodes_[idx(tail)].next.compare_exchange_weak(next, make(n, tag(next) + 1),
                                                                std::memory_order_release)) {
                    tail_.compare_exchange_strong(tail, make(n, tag(tail) + 1), std::memory_order_release);
                    return true;                                                  // (a failed swing is fine)
                }
            } else {                                                              // tail lags: help move it on
                tail_.compare_exchange_strong(tail, make(idx(next), tag(tail) + 1), std::memory_order_release);
            }
        }
    }
    bool dequeue(std::uint64_t& out) {
        for (;;) {
            Tagged head = head_.load(std::memory_order_acquire);
            Tagged tail = tail_.load(std::memory_order_acquire);
            Tagged next = nodes_[idx(head)].next.load(std::memory_order_acquire);
            if (head != head_.load(std::memory_order_acquire)) continue;
            if (idx(head) == idx(tail)) {
                if (idx(next) == kNil) return false;                              // empty
                tail_.compare_exchange_strong(tail, make(idx(next), tag(tail) + 1), std::memory_order_release);
            } else {
                // Read the value BEFORE the CAS: afterwards another dequeuer may recycle `next`.
                const std::uint64_t v = nodes_[idx(next)].value.load(std::memory_order_relaxed);
                if (head_.compare_exchange_weak(head, make(idx(next), tag(head) + 1), std::memory_order_acquire)) {
                    out = v;
                    release(idx(head));                                           // the old dummy is free now
                    return true;
                }
            }
        }
    }
};

using Clock = std::chrono::steady_clock;

template <class Push, class Pop>
double stress(std::uint64_t n, Push push, Pop pop, bool& ordered, bool& complete) {
    std::atomic<std::uint64_t> sum{0}, count{0};
    std::atomic<bool> order_ok{true};
    const auto t0 = Clock::now();
    {
        std::vector<std::jthread> ts;
        for (std::uint64_t p = 0; p < 2; ++p)
            ts.emplace_back([&, p] {
                for (std::uint64_t i = 1; i <= n;)
                    if (push((p << 32) | i)) ++i;
            });
        for (int c = 0; c < 2; ++c)
            ts.emplace_back([&] {
                std::uint64_t last[2] = {0, 0}, v = 0, local = 0;
                while (count.load(std::memory_order_relaxed) < 2 * n) {
                    if (!pop(v)) continue;
                    const std::uint64_t p = v >> 32, i = v & 0xFFFF'FFFF;
                    if (i <= last[p]) order_ok = false;
                    last[p] = i;
                    local += i;
                    count.fetch_add(1, std::memory_order_relaxed);
                }
                sum.fetch_add(local);
            });
    }
    const std::chrono::duration<double, std::nano> d = Clock::now() - t0;
    ordered = order_ok.load();
    complete = count.load() == 2 * n && sum.load() == n * (n + 1);
    return d.count() / static_cast<double>(2 * n);
}

int main() {
    constexpr std::uint64_t n = 500'000;
    bool ordered = false, complete = false;
    MsQueue q(1024);
    double ns = stress(n, [&](std::uint64_t v) { return q.enqueue(v); }, [&](std::uint64_t& v) { return q.dequeue(v); },
                       ordered, complete);
    std::println("Michael-Scott queue, 2P + 2C: {:6.1f} ns/item; every item once: {}; per-producer FIFO: {}", ns,
                 complete ? "yes" : "NO", ordered ? "yes" : "NO");
    std::mutex m;
    std::deque<std::uint64_t> dq;
    ns = stress(
        n,
        [&](std::uint64_t v) {
            std::scoped_lock lk(m);
            if (dq.size() >= 1024) return false;
            dq.push_back(v);
            return true;
        },
        [&](std::uint64_t& v) {
            std::scoped_lock lk(m);
            if (dq.empty()) return false;
            v = dq.front();
            dq.pop_front();
            return true;
        },
        ordered, complete);
    std::println("std::mutex + deque,  2P + 2C: {:6.1f} ns/item; every item once: {}; per-producer FIFO: {}", ns,
                 complete ? "yes" : "NO", ordered ? "yes" : "NO");
}
```

Output (verified, GCC then Clang):

```text
Michael-Scott queue, 2P + 2C:  259.2 ns/item; every item once: yes; per-producer FIFO: yes
std::mutex + deque,  2P + 2C:  126.3 ns/item; every item once: yes; per-producer FIFO: yes
Michael-Scott queue, 2P + 2C:  284.9 ns/item; every item once: yes; per-producer FIFO: yes
std::mutex + deque,  2P + 2C:  133.5 ns/item; every item once: yes; per-producer FIFO: yes
```

```text
   head_ ---> [dummy] ---> [ v1 ] ---> [ v2 ] ---> nil          tail_ points at v2, or (lagging) at v1
   enqueue(v):  1. CAS  last->next : nil -> n      (the linearization point)
                2. CAS  tail_      : last -> n     (may fail: someone helped already)
                   if tail_ lags (tail->next != nil): first help: CAS tail_ forward, then retry
   dequeue():   v = next->value  (READ BEFORE the CAS)
                CAS head_ : dummy -> next          (the linearization point; `next` becomes the new dummy)
                release the old dummy to the pool
```

* **The dummy node** means head and tail never have to change together: the empty queue is "head == tail, and
  `tail->next == nil`". Without it, enqueueing into an empty queue would have to update two words atomically.
* **Helping.** Enqueue is two steps (link, then swing the tail). If the linking thread stalls between them, the tail
  lags by one node. Any other enqueuer or dequeuer that notices (`next != nil`) swings it forward itself. Without
  helping, everyone would wait for the stalled thread, and the queue would be blocking.
* **Counted pointers everywhere.** `head_`, `tail_` and every `next` carry a tag. A recycled node's `next` gets a fresh
  tag on reuse (`release()` and `enqueue` both increment it), so a lagging enqueuer's CAS on a recycled node's `next`
  fails.
* **The value is read before the head CAS, and it's atomic.** After the CAS, `next` is the *new* dummy. Another
  dequeuer can dequeue past it and recycle it at once, so reading `value` afterwards could read a node already reused.
  Reading before the CAS can also see a recycled node; the CAS then fails and the value is discarded. A plain field would
  make that discarded read a data race, so `value` is `std::atomic<uint64_t>` with relaxed loads.
* **2× slower than `mutex` + `deque` here** (257–298 vs 126–143 ns per item): two hot words, two or three CASes per
  operation, and a free-list CAS on top. What it buys is lock-freedom: a stalled thread never blocks the others (file 01).

### 1.3 A lock-free hash map (Listing 9.7)

```cpp
// lf_hash.cpp - a lock-free hash map (insert/update/find, no erase, no resize): linear probing, keys claimed by CAS
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <thread>
#include <unordered_map>
#include <vector>

inline std::uint64_t mix(std::uint64_t k) {   // murmur3 fmix64: spread sequential keys over the table
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    return k ^ (k >> 33);
}

// Key 0 means "empty slot" and value 0 means "not yet published"; real keys and values are non-zero.
// A slot's key, once set, never changes: that monotonicity is what makes one CAS enough.
class LockFreeMap {
    struct alignas(16) Slot {
        std::atomic<std::uint64_t> key{0};
        std::atomic<std::uint64_t> value{0};
    };
    const std::size_t mask_;
    std::unique_ptr<Slot[]> slots_;

public:
    explicit LockFreeMap(std::size_t capacity_pow2) : mask_(capacity_pow2 - 1), slots_(new Slot[capacity_pow2]) {}
    bool insert_or_assign(std::uint64_t k, std::uint64_t v) {
        for (std::size_t i = mix(k), probes = 0; probes <= mask_; ++i, ++probes) {
            Slot& s = slots_[i & mask_];
            std::uint64_t cur = s.key.load(std::memory_order_acquire);
            if (cur != k) {
                if (cur != 0) continue;                                       // someone else's key: next slot
                if (!s.key.compare_exchange_strong(cur, k, std::memory_order_acq_rel) && cur != k)
                    continue;                                                 // lost the race to a different key
            }
            s.value.store(v, std::memory_order_release);                       // claimed (or already ours)
            return true;
        }
        return false;                                                         // full
    }
    std::optional<std::uint64_t> find(std::uint64_t k) const {
        for (std::size_t i = mix(k), probes = 0; probes <= mask_; ++i, ++probes) {
            const Slot& s = slots_[i & mask_];
            const std::uint64_t cur = s.key.load(std::memory_order_acquire);
            if (cur == k) {
                const std::uint64_t v = s.value.load(std::memory_order_acquire);
                return v ? std::optional{v} : std::nullopt;                   // key claimed, value not yet stored
            }
            if (cur == 0) return std::nullopt;                                // keys are never removed: stop here
        }
        return std::nullopt;
    }
};

class ShardedMap {   // the usual alternative: N mutex-protected std::unordered_maps
    struct alignas(128) Shard {
        std::mutex m;
        std::unordered_map<std::uint64_t, std::uint64_t> map;
    };
    std::unique_ptr<Shard[]> shards_;
    std::size_t n_;
    Shard& shard(std::uint64_t k) const { return shards_[mix(k) % n_]; }

public:
    explicit ShardedMap(std::size_t n) : shards_(std::make_unique<Shard[]>(n)), n_(n) {}
    bool insert_or_assign(std::uint64_t k, std::uint64_t v) {
        Shard& s = shard(k);
        std::scoped_lock lk(s.m);
        s.map.insert_or_assign(k, v);
        return true;
    }
    std::optional<std::uint64_t> find(std::uint64_t k) const {
        Shard& s = shard(k);
        std::scoped_lock lk(s.m);
        auto it = s.map.find(k);
        return it == s.map.end() ? std::nullopt : std::optional{it->second};
    }
};

using Clock = std::chrono::steady_clock;
constexpr int kThreads = 4;
// Scrambled keys: with sequential keys, std::hash<uint64_t> (the identity in both libraries) makes a single
// std::unordered_map walk memory in insertion order, which measured 4x faster than 64 shards even on ONE thread.
inline std::uint64_t key_of(std::uint64_t i) { return mix(i) | 1; }   // non-zero
constexpr std::uint64_t kPerThread = 250'000;

template <class Map>
void run(const char* name, Map& map) {
    auto timed = [&](auto body) {
        const auto t0 = Clock::now();
        {
            std::vector<std::jthread> ts;
            for (int t = 0; t < kThreads; ++t) ts.emplace_back(body, static_cast<std::uint64_t>(t));
        }
        const std::chrono::duration<double, std::nano> d = Clock::now() - t0;
        return d.count() / (kThreads * kPerThread);
    };
    const double ins = timed([&](std::uint64_t t) {
        for (std::uint64_t i = 1; i <= kPerThread; ++i) map.insert_or_assign(key_of(t * kPerThread + i), i);
    });
    std::atomic<std::uint64_t> hits{0}, wrong{0};
    const double look = timed([&](std::uint64_t t) {
        std::uint64_t h = 0, w = 0;
        for (std::uint64_t i = 1; i <= kPerThread; ++i) {
            const std::uint64_t n = ((t + 1) % kThreads) * kPerThread + i;   // other threads' keys
            if (auto v = map.find(key_of(n))) {
                ++h;
                if (*v != i) ++w;
            }
            if (map.find(key_of(n + 10 * kThreads * kPerThread))) ++w;      // a key that was never inserted
        }
        hits.fetch_add(h);
        wrong.fetch_add(w);
    });
    std::println("{:<34} insert {:6.1f} ns/op, lookup (hit + miss) {:6.1f} ns; all {} found: {}, wrong answers: {}",
                 name, ins, look, kThreads * kPerThread, hits.load() == kThreads * kPerThread ? "yes" : "NO", wrong.load());
}

int main() {
    LockFreeMap lf(std::size_t{1} << 21);   // 2M slots for 1M keys: load factor 0.48
    run("lock-free, linear probing", lf);
    ShardedMap sharded(64);
    run("64 shards x (mutex + unordered_map)", sharded);
    ShardedMap single(1);
    run("1 mutex + unordered_map", single);
}
```

Output (verified, GCC then Clang):

```text
lock-free, linear probing          insert    9.9 ns/op, lookup (hit + miss)   15.9 ns; all 1000000 found: yes, wrong answers: 0
64 shards x (mutex + unordered_map) insert  137.3 ns/op, lookup (hit + miss)  115.2 ns; all 1000000 found: yes, wrong answers: 0
1 mutex + unordered_map            insert  466.3 ns/op, lookup (hit + miss)  502.7 ns; all 1000000 found: yes, wrong answers: 0
lock-free, linear probing          insert    9.0 ns/op, lookup (hit + miss)   19.3 ns; all 1000000 found: yes, wrong answers: 0
64 shards x (mutex + unordered_map) insert  216.2 ns/op, lookup (hit + miss)  116.5 ns; all 1000000 found: yes, wrong answers: 0
1 mutex + unordered_map            insert  400.3 ns/op, lookup (hit + miss)  336.8 ns; all 1000000 found: yes, wrong answers: 0
```

* **The monotonic slot.** A slot's key goes from 0 to one key and never changes again. A thread claims an empty slot
  with one CAS on the key; if it loses to the *same* key, the slot is its key's slot anyway; if it loses to a different
  key, it probes on. The value is published with a release store, and a reader that sees the key but value 0 treats the
  insert as not yet having happened (its linearization point is the value store).
* **Why it wins 10–30×.** 4 threads inserting 1M scrambled keys touch 1M different slots: no shared hot word, no lock,
  no allocation. Over two runs: 8.6–12.0 ns per insert and 15.8–19.3 ns per lookup (a hit plus a miss), against
  137–216 / 107–117 ns for 64 mutex-protected shards and 400–489 / 337–525 ns for one mutex. The `unordered_map`
  versions also allocate a node per insert.
* **A benchmark artefact found while writing this.** With *sequential* keys, one `std::unordered_map` behind one mutex
  ran 4× faster than 64 shards **even with one thread**. `std::hash<uint64_t>` is the identity in both libraries
  (Folder 03), so sequential keys produce sequential buckets and nodes allocated in order: near-perfect locality. Real
  keys aren't sequential, and the listing scrambles them (`key_of`).
* **What it does not do.** Erasing by resetting the key to 0 would break probe chains: lookups stop at the first empty
  slot and would lose keys stored after it. Deletion needs tombstones. Growing needs cooperative migration while other
  threads keep inserting (Cliff Click's NonBlockingHashMap, split-ordered lists). Production code uses folly's
  `ConcurrentHashMap` (with hazard pointers), TBB's `concurrent_hash_map`, or sharded Abseil maps.

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| CAS-based structures | possible with `std::atomic` (raw-pointer versions need SMR) | — | — | `atomic_ref` for pool-resident fields | — | hazard pointers / RCU for reclamation (P2530, P2545; not shipped here) |
| standard concurrent containers | none | — | — | — | — | none (libraries: folly, TBB, libcds, Abseil) |
| 64-bit CAS everywhere | lock-free 64-bit atomics on all 64-bit targets | — | `is_always_lock_free` lets code assert it | — | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| Treiber stack head | `std::atomic<Node*>` + `delete` in `pop` (ABA + use-after-free) | index + tag over a node pool (Listing 9.5), or hazard pointers (file 04) |
| fields read by "losing" threads | plain `next`/`value` fields ("the CAS will fail anyway") | relaxed atomics: a discarded racy read is still a data race in C++ |
| a hot-spot stack or queue under heavy contention | lock-free CAS on one head | elimination back-off, per-thread caches, sharded queues; or a mutex (it won here) |
| MPMC queue with strict non-blocking needs | a mutex queue | MS queue (lock-free, Listing 9.6) or per-producer SPSC rings |
| concurrent map, read- and insert-heavy, no deletes | one mutex + `unordered_map` (400–525 ns) | open-addressing lock-free map (Listing 9.7) or many shards |
| concurrent map with deletes and growth | a home-grown lock-free map | folly `ConcurrentHashMap`, TBB, or sharded maps with a mutex per shard |
| benchmarking maps | sequential keys | scrambled keys; also report allocation counts |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| lost or duplicated stack nodes | untagged head (ABA) | tags; deterministic replay (file 01) |
| queue dequeues garbage values occasionally | value read after the head CAS | read before the CAS; atomic value field |
| queue enqueuers spin while tail lags | no tail helping | helping on `next != nil` |
| TSan reports races in a "correct" lock-free structure | plain fields read by threads that later fail their CAS | relaxed atomics for every concurrently-read field |
| lookups miss keys after a delete | key reset to 0 breaks probe chains | tombstones; insert-only design with periodic rebuild |
| lock-free version slower than the mutex version | single hot word under contention | measure; reduce contention before going lock-free |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Write Treiber pop"</b></summary>

**Initial prompt.** "Implement `pop()` for a lock-free stack of `Node*`."

**L5 textbook answer.**
`Node* h = head.load(); while (h && !head.compare_exchange_weak(h, h->next)) {} auto v = h->value; delete h; return v;`

**Why L5 corrupts memory on ARM64.** `h->next` is read while another thread may already have popped and deleted `h`:
a use-after-free. If the allocator reuses `h`'s address, the CAS succeeds against a recycled node: ABA (file 01, Listing
9.2), installing a freed `next` as the head. Both happen on every architecture. ARM64 just makes the interleavings
more likely.

**L7 principal defense.** "Either nodes never leave a type-stable pool and the head carries a tag (Listing 9.5: index
+ 32-bit tag, one 64-bit CAS), or nodes are freed through hazard pointers: protect `head`, read `next`, CAS, then
`retire()` instead of `delete` (file 04). `next` is a relaxed atomic in either case."
</details>

<details><summary><b>Chain 2 🧊 "Only the pusher writes next, so it can be a plain field"</b></summary>

**Initial prompt.** "In our Treiber stack, `node->next` is written only by the thread that pushes the node. Why would
it need to be atomic?"

**L5 textbook answer.** "One writer means no race. Atomics would just add overhead."

**Why L5 breaks.** The reader is the problem. A popper reads `next` of the node it *thinks* is the head; meanwhile
that node may have been popped, recycled, and be getting its `next` written by its new owner pushing it. The popper's
CAS will fail and the value is discarded, but the concurrent plain read and write are still a data race: undefined
behaviour, and TSan reports it. A relaxed atomic load costs nothing extra on x86 or ARM64: the `movl`/`ldr` in Listing
9.5's asm.

**L7 principal defense.** "Every field that a thread may read while another writes it is atomic, at least relaxed,
even when the algorithm discards the read. That's the difference between 'works on x86' and 'correct C++'."
</details>

<details><summary><b>Chain 3 ⚡ "Our lock-free stack is slower than the mutex one"</b></summary>

**Initial prompt.** "We replaced a mutex-protected `vector` stack with a lock-free Treiber stack and got slower. How is
that possible, and what would you do?"

**L5 textbook answer.** "The implementation must be wrong. Lock-free removes the lock, so it can't be slower."

**Why L5 breaks.** Listing 9.5: 206–291 ns per round lock-free vs 52–59 ns with a mutex, on 4 threads. Every operation
CASes the same head; under contention most CASes fail, and each failure costs a cache-line transfer plus a retry. A lock
serializes the threads, but each holder finishes its section without failed attempts. Lock-freedom doesn't remove the
serialization point; it moves it into the hardware.

**L7 principal defense.** "Keep lock-free for its progress guarantee if needed, but attack contention: an elimination
back-off array (matching pushes and pops pair off without touching the head), per-thread magazines with a shared
overflow stack, or flat combining (one thread applies a batch of operations under a lock). Or keep the mutex and shard."
</details>

<details><summary><b>Chain 4 🧊 "Why does the MS queue need a dummy node?"</b></summary>

**Initial prompt.** "Why does the Michael-Scott queue start with a dummy node instead of `head = tail = nullptr`?"

**L5 textbook answer.** "It simplifies the code by avoiding null checks."

**Why L5 breaks.** It's about atomicity, not convenience. Without a dummy, enqueue into an empty queue must set both
`head` and `tail`, and dequeueing the last element must clear both: two words that would have to change in one atomic
step. With a dummy, enqueue only touches `tail`'s `next` and `tail`, dequeue only touches `head`, and the empty state is
"`head == tail` and `next == nil`". Each step is one single-word CAS.

**L7 principal defense.** "The dummy decouples the two ends so that each operation's linearization point is one CAS:
the link CAS for enqueue, the head CAS for dequeue. The old dummy is freed on each dequeue, and the dequeued node
becomes the new dummy."
</details>

<details><summary><b>Chain 5 🔥 "Read the value after the CAS, when you own the node"</b></summary>

**Initial prompt.** "In MS-queue dequeue, why read `next->value` before the CAS? After a successful CAS the node is
ours."

**L5 textbook answer.** "Reading after the CAS is cleaner, because the node belongs to us then."

**Why L5 corrupts memory on ARM64.** After the CAS we own the *old dummy*, not `next`. `next` has become the new dummy,
and another dequeuer can immediately dequeue past it, release it to the pool, and an enqueuer can overwrite its value.
Reading after the CAS can return another item's value. Reading before the CAS may also see a recycled node, but then
the CAS fails and the value is thrown away; that's why `value` must be an atomic (relaxed) and not a plain field.

**L7 principal defense.** "Read first, validate with the CAS, keep the value only on success. It's the general pattern
for optimistic reads in lock-free code, and the read must be atomic because it can race with reuse."
</details>

<details><summary><b>Chain 6 ⚡ "Only the enqueuer that linked a node should move the tail"</b></summary>

**Initial prompt.** "Why do other threads swing `tail_` forward in the MS queue? Isn't that the enqueuer's job?"

**L5 textbook answer.** "For efficiency: helping makes the tail move faster."

**Why L5 deadlocks on ARM64.** It's for progress. If the enqueuer that linked a node is preempted before swinging the
tail, `tail_` lags. Every other enqueuer would find `tail->next != nil`, be unable to link, and wait for the stalled
thread: that's a lock in disguise. Helping (`CAS tail_` forward when `next != nil`) lets any thread repair the state and
continue, which is what makes the queue lock-free.

**L7 principal defense.** "Two-step operations in lock-free structures leave intermediate states that any thread must
be able to complete. Helping is how lock-freedom survives multi-step updates, and why the second CAS's failure is
harmless."
</details>

<details><summary><b>Chain 7 🔥 "Add erase to the lock-free hash map"</b></summary>

**Initial prompt.** "Our linear-probing lock-free map has insert and find. Add `erase` by CASing the key back to 0."

**L5 textbook answer.** "That works: the slot becomes empty and can be reused."

**Why L5 breaks.** `find` stops at the first empty slot (Listing 9.7: `if (cur == 0) return nullopt`). Emptying a slot
in the middle of a probe chain makes every key stored after it unreachable. And a concurrent `insert_or_assign` of the
same key may have read the key just before the erase and write its value into a slot that now belongs to nobody, or to a
different key that claims it next.

**L7 principal defense.** "Deletion marks the value with a tombstone and keeps the key, so probe chains stay intact.
Space is reclaimed by a cooperative rebuild into a new table (Click's NonBlockingHashMap). For general-purpose use with
erase and growth: folly's `ConcurrentHashMap` (hazard pointers) or sharded maps."
</details>

<details><summary><b>Chain 8 ⚡ "Our lock-free map is 30× faster: ship it"</b></summary>

**Initial prompt.** "A benchmark shows our lock-free map 30× faster than `mutex` + `unordered_map`. Trustworthy?"

**L5 textbook answer.** "Yes, that's what lock-free structures achieve."

**Why L5 breaks.** Maybe, but check the benchmark. With sequential keys, Listing 9.7's mutex maps behaved completely
differently: a single `unordered_map` was 4× faster than 64 shards on *one* thread, purely because identity hashing gives
sequential memory access. The `unordered_map` versions also allocate per insert, so allocator contention is part of the
number. Load factor matters for linear probing (0.48 here), and nothing here erases or resizes.

**L7 principal defense.** "Scrambled or production-sampled keys, the same load factor and allocation behaviour for
every candidate, the real read/write mix, and the missing features (erase, growth) priced in. Then the win is believable,
and here it held: 10–30× with scrambled keys."
</details>

---

## 6. Invariants checklist

- [ ] Every CAS-ed reference carries a tag, or reuse is prevented by safe memory reclamation.
- [ ] Every field read concurrently with a write is atomic (relaxed is enough for discarded optimistic reads).
- [ ] Multi-step updates leave states that other threads can complete (helping).
- [ ] Optimistic reads happen before the validating CAS and are used only on success.
- [ ] Lock-free structures are benchmarked against a mutex and a sharded-mutex baseline with realistic keys.
- [ ] Hash-map deletion uses tombstones; growth is cooperative or offline.

## 7. References

- R. K. Treiber, "Systems Programming: Coping with Parallelism", IBM RJ 5118, 1986 (the original stack; no public URL)
- M. Michael, M. Scott, "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms", PODC 1996: <https://www.cs.rochester.edu/u/scott/papers/1996_PODC_queues.pdf>
- D. Hendler, N. Shavit, L. Yerushalmi, "A Scalable Lock-free Stack Algorithm" (elimination back-off), SPAA 2004: <https://people.csail.mit.edu/shanir/publications/Lock_Free.pdf>
- O. Shalev, N. Shavit, "Split-Ordered Lists: Lock-Free Extensible Hash Tables", JACM 2006: <https://people.csail.mit.edu/shanir/publications/Split-Ordered_Lists.pdf>
- J. Preshing, "The World's Simplest Lock-Free Hash Table": <https://preshing.com/20130605/the-worlds-simplest-lock-free-hash-table/>
- folly `ConcurrentHashMap`: <https://github.com/facebook/folly/blob/main/folly/concurrency/ConcurrentHashMap.h>
