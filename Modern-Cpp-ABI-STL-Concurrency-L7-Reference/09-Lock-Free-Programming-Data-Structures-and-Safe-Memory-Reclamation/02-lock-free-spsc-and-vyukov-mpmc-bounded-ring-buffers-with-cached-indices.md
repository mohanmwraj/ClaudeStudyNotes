# 02 · Lock-free SPSC and Vyukov MPMC bounded ring buffers with cached indices

> **Scope.** Bounded rings are the workhorses of low-latency systems: market-data handoff, audio, logging, NIC
> descriptor rings, actor mailboxes. The single-producer/single-consumer ring is **wait-free** and needs no
> read-modify-write at all, only a release store and (rarely) an acquire load. Dmitry Vyukov's bounded MPMC queue
> needs one CAS per operation. This file builds both, shows the SPSC fast path in assembly, and measures them with
> pinned threads. The measurements contain the most important lesson of this folder: **where the threads run and which
> regime the ring is in (flowing or full) changes the result by 10×.** Cached indices help only in one of those regimes.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 9.3 | `spsc_ring.cpp` | an SPSC ring with no RMW; cached indices remove the other side's index from the fast path; pinned measurements on two cores vs two hyper-threads; refresh counters reveal the ring's regime | run, 2 pinned threads, both compilers; asm x86-64 + AArch64 |
| 9.4 | `mpmc_vyukov.cpp` | Vyukov's queue with per-slot sequence numbers: every item exactly once, FIFO per producer; **a producer stalled between claim and publish makes the queue look empty**, so it is not lock-free | run, 2 producers + 2 consumers, both compilers; deterministic stall demo |

**Verification line.** As in file 01. The SPSC benchmark pins threads with `SetThreadAffinityMask` (Linux:
`pthread_setaffinity_np`). On this machine logical CPUs 2k and 2k+1 are the two hyper-threads of one core.

---

## 1. First principles

### 1.1 The SPSC ring (Listing 9.3)

```text
   producer-owned line (128 B)          consumer-owned line (128 B)          slots (power of two)
  +--------------------------+         +--------------------------+         +---+---+---+---+---+---+
  | tail_       (atomic)     |         | head_       (atomic)     |         |   | x | x | x |   |   |
  | head_cache_ (plain)      |         | tail_cache_ (plain)      |         +---+---+---+---+---+---+
  | producer_refreshes_      |         | consumer_refreshes_      |               ^head      ^tail
  +--------------------------+         +--------------------------+
   push: t = tail_ (relaxed: only we write it)          pop: h = head_ (relaxed)
         full if t - head_cache_ == N -> refresh:              empty if h == tail_cache_ -> refresh:
            head_cache_ = head_.load(acquire)                    tail_cache_ = tail_.load(acquire)
         slots[t & (N-1)] = v                                  v = slots[h & (N-1)]
         tail_.store(t + 1, release)   -- publishes the slot   head_.store(h + 1, release) -- returns the slot
```

```cpp
// spsc_ring.cpp - a wait-free single-producer/single-consumer ring: shared line vs padded vs padded + cached indices
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <print>
#include <queue>
#include <thread>
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__linux__)
#include <pthread.h>
#include <sched.h>
#endif
#if defined(__x86_64__)
#include <immintrin.h>
#endif

// Back off while the ring is full/empty: without it, a waiting side re-reads the other side's index in a tight
// loop and keeps stealing that cache line from the thread it is waiting for (runs varied 6-58 ns per item).
inline void cpu_relax() {
#if defined(__x86_64__)
    _mm_pause();
#elif defined(__aarch64__)
    asm volatile("yield");
#endif
}

// Pin the calling thread to one logical CPU: SPSC numbers depend completely on whether the two threads share a
// core (hyper-thread siblings share the L1) or not, and an unpinned run lands on either.
inline void pin_to_cpu(unsigned cpu) {
#if defined(_WIN32)
    SetThreadAffinityMask(GetCurrentThread(), DWORD_PTR{1} << cpu);
#elif defined(__linux__)
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    pthread_setaffinity_np(pthread_self(), sizeof set, &set);
#else
    (void)cpu;
#endif
}

template <class T, std::size_t N, bool Padded, bool CacheIndices>
class SpscRing {
    static_assert(N >= 2 && (N & (N - 1)) == 0, "capacity must be a power of two");
    static constexpr std::size_t kLine = Padded ? 128 : alignof(std::atomic<std::size_t>);
    // Producer-owned line: the index it publishes, its private copy of the consumer's index, its statistics.
    alignas(kLine) std::atomic<std::size_t> tail_{0};
    std::size_t head_cache_ = 0;
    std::uint64_t producer_refreshes_ = 0;
    // Consumer-owned line.
    alignas(kLine) std::atomic<std::size_t> head_{0};
    std::size_t tail_cache_ = 0;
    std::uint64_t consumer_refreshes_ = 0;
    alignas(kLine) T slots_[N];

public:
    bool try_push(const T& v) {
        const std::size_t t = tail_.load(std::memory_order_relaxed);          // only the producer writes tail_
        if constexpr (CacheIndices) {
            if (t - head_cache_ == N) {                                       // looks full: refresh the view
                head_cache_ = head_.load(std::memory_order_acquire);
                ++producer_refreshes_;
                if (t - head_cache_ == N) return false;
            }
        } else if (t - head_.load(std::memory_order_acquire) == N) {         // touches the consumer's line every time
            return false;
        }
        slots_[t & (N - 1)] = v;
        tail_.store(t + 1, std::memory_order_release);                        // publish the slot
        return true;
    }
    bool try_pop(T& v) {
        const std::size_t h = head_.load(std::memory_order_relaxed);
        if constexpr (CacheIndices) {
            if (h == tail_cache_) {                                           // looks empty: refresh the view
                tail_cache_ = tail_.load(std::memory_order_acquire);
                ++consumer_refreshes_;
                if (h == tail_cache_) return false;
            }
        } else if (h == tail_.load(std::memory_order_acquire)) {
            return false;
        }
        v = slots_[h & (N - 1)];
        head_.store(h + 1, std::memory_order_release);                        // hand the slot back
        return true;
    }
    std::uint64_t producer_refreshes() const { return producer_refreshes_; }
    std::uint64_t consumer_refreshes() const { return consumer_refreshes_; }
};

#ifdef ASM_VIEW
template class SpscRing<std::uint64_t, 1024, true, true>;   // emit the cached version's members for the listing
#else
using Clock = std::chrono::steady_clock;

struct Placement {
    unsigned producer_cpu, consumer_cpu;
};

template <class Ring>
double run_ring(std::uint64_t n, Placement where, double& push_refresh_pct, double& pop_refresh_pct) {
    auto ring = std::make_unique<Ring>();
    std::uint64_t sum = 0;
    pin_to_cpu(where.producer_cpu);
    const auto t0 = Clock::now();
    {
        std::jthread consumer([&] {
            pin_to_cpu(where.consumer_cpu);
            std::uint64_t v = 0;
            for (std::uint64_t got = 0; got < n;)
                if (ring->try_pop(v)) {
                    sum += v;
                    ++got;
                } else {
                    cpu_relax();
                }
        });
        for (std::uint64_t i = 1; i <= n;)
            if (ring->try_push(i)) ++i;
            else cpu_relax();
    }
    const std::chrono::duration<double, std::nano> d = Clock::now() - t0;
    if (sum != n * (n + 1) / 2) std::println("LOST OR DUPLICATED ITEMS");
    push_refresh_pct = 100.0 * static_cast<double>(ring->producer_refreshes()) / static_cast<double>(n);
    pop_refresh_pct = 100.0 * static_cast<double>(ring->consumer_refreshes()) / static_cast<double>(n);
    return d.count() / static_cast<double>(n);
}

double run_mutex_queue(std::uint64_t n, Placement where) {
    std::mutex m;
    std::queue<std::uint64_t> q;
    std::uint64_t sum = 0;
    pin_to_cpu(where.producer_cpu);
    const auto t0 = Clock::now();
    {
        std::jthread consumer([&] {
            pin_to_cpu(where.consumer_cpu);
            for (std::uint64_t got = 0; got < n;) {
                std::scoped_lock lk(m);
                while (!q.empty()) {
                    sum += q.front();
                    q.pop();
                    ++got;
                }
            }
        });
        for (std::uint64_t i = 1; i <= n; ++i) {
            std::scoped_lock lk(m);
            q.push(i);
        }
    }
    const std::chrono::duration<double, std::nano> d = Clock::now() - t0;
    if (sum != n * (n + 1) / 2) std::println("LOST OR DUPLICATED ITEMS");
    return d.count() / static_cast<double>(n);
}

int main() {
    constexpr std::uint64_t n = 20'000'000;
    // Logical CPUs 2k and 2k+1 are the two hyper-threads of one core on this Windows machine.
    const Placement placements[] = {{2, 4}, {2, 3}};
    const char* names[] = {"two different cores", "hyper-thread siblings of one core"};
    std::println("ns per item, 1 producer + 1 consumer, pinned, 1024-slot ring, {} items, all sums verified", n);
    for (int k = 0; k < 2; ++k) {
        const Placement w = placements[k];
        double pr = 0, cr = 0;
        std::println("-- {} (CPU {} -> CPU {})", names[k], w.producer_cpu, w.consumer_cpu);
        std::println("   indices on one cache line, no caching   {:6.2f}",
                     run_ring<SpscRing<std::uint64_t, 1024, false, false>>(n, w, pr, cr));
        std::println("   indices padded apart, no caching        {:6.2f}",
                     run_ring<SpscRing<std::uint64_t, 1024, true, false>>(n, w, pr, cr));
        const double cached = run_ring<SpscRing<std::uint64_t, 1024, true, true>>(n, w, pr, cr);
        std::println("   padded + cached indices                 {:6.2f}   (refreshed on {:.1f}% of pushes, {:.1f}% of pops)",
                     cached, pr, cr);
        std::println("   std::mutex + std::queue                 {:6.2f}", run_mutex_queue(n / 10, w));
    }
}
#endif
```

The cached fast path, Clang 21 `-O3`, x86-64:

```asm
_ZN8SpscRingImLm1024ELb1ELb1EE8try_pushERKm: # SpscRing<unsigned long, 1024ul, true, true>::try_push(unsigned long const&)
	movq	(%rdi), %rax
	movq	%rax, %rcx
	subq	8(%rdi), %rcx
	cmpq	$1024, %rcx
	jne	.LBB0_3
	movq	128(%rdi), %rcx
	movq	%rcx, 8(%rdi)
	addq	$1, 16(%rdi)
	movq	%rax, %rdx
	subq	%rcx, %rdx
	cmpq	$1024, %rdx
	jne	.LBB0_3
	xorl	%eax, %eax
	retq
.LBB0_3:
	movq	(%rsi), %rcx
	movl	%eax, %edx
	andl	$1023, %edx
	movq	%rcx, 256(%rdi,%rdx,8)
	addq	$1, %rax
	movq	%rax, (%rdi)
	movb	$1, %al
	retq

_ZN8SpscRingImLm1024ELb1ELb1EE7try_popERm: # SpscRing<unsigned long, 1024ul, true, true>::try_pop(unsigned long&)
	movq	128(%rdi), %rax
	cmpq	136(%rdi), %rax
	jne	.LBB1_3
	movq	(%rdi), %rcx
	movq	%rcx, 136(%rdi)
	addq	$1, 144(%rdi)
	cmpq	%rcx, %rax
	jne	.LBB1_3
	xorl	%eax, %eax
	retq
.LBB1_3:
	movl	%eax, %ecx
	andl	$1023, %ecx
	movq	256(%rdi,%rcx,8), %rcx
	movq	%rcx, (%rsi)
	addq	$1, %rax
	movq	%rax, 128(%rdi)
	movb	$1, %al
	retq
```

AArch64:

```asm
_ZN8SpscRingImLm1024ELb1ELb1EE8try_pushERKm: // SpscRing<unsigned long, 1024ul, true, true>::try_push(unsigned long const&)
	ldr	x8, [x0]
	ldr	x9, [x0, #8]
	sub	x9, x8, x9
	cmp	x9, #1024
	b.ne	.LBB0_3
	add	x9, x0, #128
	ldar	x9, [x9]
	ldr	x10, [x0, #16]
	sub	x11, x8, x9
	add	x10, x10, #1
	cmp	x11, #1024
	stp	x9, x10, [x0, #8]
	b.ne	.LBB0_3
	mov	w0, wzr
	ret
.LBB0_3:
	and	x9, x8, #0x3ff
	ldr	x10, [x1]
	add	x8, x8, #1
	add	x9, x0, x9, lsl #3
	str	x10, [x9, #256]
	stlr	x8, [x0]
	mov	w0, #1
	ret

_ZN8SpscRingImLm1024ELb1ELb1EE7try_popERm: // SpscRing<unsigned long, 1024ul, true, true>::try_pop(unsigned long&)
	ldr	x8, [x0, #128]
	ldr	x9, [x0, #136]
	cmp	x8, x9
	b.ne	.LBB1_3
	ldar	x9, [x0]
	ldr	x10, [x0, #144]
	add	x10, x10, #1
	cmp	x8, x9
	stp	x9, x10, [x0, #136]
	b.ne	.LBB1_3
	mov	w0, wzr
	ret
.LBB1_3:
	and	x9, x8, #0x3ff
	add	x8, x8, #1
	add	x10, x0, #128
	add	x9, x0, x9, lsl #3
	mov	w0, #1
	ldr	x9, [x9, #256]
	str	x9, [x1]
	stlr	x8, [x10]
	ret
```

* **No read-modify-write anywhere.** Each index has exactly one writer, so publishing is a plain store with release
  (`movq` on x86, `stlr` on AArch64). The acquire load of the *other* side's index (`movq 128(%rdi)`, `ldar`) appears
  only on the refresh path. Each operation is a bounded number of steps: **wait-free**.
* **Why cache the other index.** Without caching, every push reads `head_`, which lives on the consumer's line.
  Every consumer `head_` store then invalidates the producer's copy, so the line ping-pongs on every operation. With
  caching, the producer reads `head_` only when its stale view says "full". A stale view is always *safe*: the real
  head can only have moved further, so the ring has at least as much space as the cache says.
* **Why the slot write is plain.** The release store of `tail_` orders it before publication, and the consumer's
  acquire load of `tail_` (when it refreshes) orders the read after. The happens-before chain is the message-passing
  pattern of Folder 07, file 01.

Output (verified, GCC then Clang):

```text
ns per item, 1 producer + 1 consumer, pinned, 1024-slot ring, 20000000 items, all sums verified
-- two different cores (CPU 2 -> CPU 4)
   indices on one cache line, no caching    53.53
   indices padded apart, no caching         61.36
   padded + cached indices                  58.62   (refreshed on 91.4% of pushes, 0.6% of pops)
   std::mutex + std::queue                 118.34
-- hyper-thread siblings of one core (CPU 2 -> CPU 3)
   indices on one cache line, no caching     4.82
   indices padded apart, no caching          4.89
   padded + cached indices                   4.72   (refreshed on 0.2% of pushes, 19.6% of pops)
   std::mutex + std::queue                 184.92
ns per item, 1 producer + 1 consumer, pinned, 1024-slot ring, 20000000 items, all sums verified
-- two different cores (CPU 2 -> CPU 4)
   indices on one cache line, no caching    57.43
   indices padded apart, no caching         53.52
   padded + cached indices                  49.19   (refreshed on 87.7% of pushes, 0.8% of pops)
   std::mutex + std::queue                  58.72
-- hyper-thread siblings of one core (CPU 2 -> CPU 3)
   indices on one cache line, no caching     4.34
   indices padded apart, no caching          4.76
   padded + cached indices                   4.45   (refreshed on 0.2% of pushes, 16.1% of pops)
   std::mutex + std::queue                  39.16
```

| Placement | Regime (refreshes per push) | Measured range over 3 pinned runs per compiler (with back-off) |
|---|---|---|
| two hyper-threads of one core (shared L1) | any | **2.3–5.0 ns** per item for every ring variant; cached indices 2.3–4.7 |
| two different cores, ring **flowing** (8–13% refreshes) | consumer keeps up | **cached 5.4–9.2 ns** vs padded-uncached 13.8–15.1 and one-line 8.9–9.2 (Clang runs) |
| two different cores, ring **full** (88–91% refreshes) | producer outruns consumer | **47–61 ns for every variant**: caching cannot help |
| either | — | `std::mutex` + `std::queue`: 21–118 ns across cores, 39–197 ns on siblings (winpthreads worst) |

* **Placement dominates.** Hyper-thread siblings share an L1, so the "cache line transfer" costs almost nothing. Across
  cores, every handoff is a coherence transaction. Unpinned runs, before this listing pinned its threads, varied from 4
  to 57 ns per item for the same code.
* **The regime decides whether caching helps.** When the producer is faster, the ring is full, every `try_push` fails,
  and every retry refreshes. Without back-off a run reached 122% (several refreshes per successful push). The
  producer's loads then keep stealing the consumer's line. Cached indices pay off when the ring is neither full nor empty. The
  refresh counters say which regime a run was in. Without them, 5 ns and 55 ns results look like noise.
* **Back off when blocked.** The benchmark loops call `PAUSE` (`yield` on ARM) on failure. Without it, cross-core results
  varied 6–58 ns between runs even when pinned, because a spinning side hammers the other's line.

### 1.2 Vyukov's bounded MPMC queue (Listing 9.4)

```cpp
// mpmc_vyukov.cpp - Dmitry Vyukov's bounded MPMC queue: one CAS per operation, a sequence number per slot
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <latch>
#include <memory>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

template <class T>
class MpmcQueue {
    // seq == pos      : the slot is free for the producer that claims position pos
    // seq == pos + 1  : the slot holds the item of position pos, ready for the consumer that claims pos
    struct alignas(64) Cell {
        std::atomic<std::size_t> seq;
        T data;
    };
    const std::size_t mask_;
    std::unique_ptr<Cell[]> cells_;
    alignas(128) std::atomic<std::size_t> enqueue_pos_{0};
    alignas(128) std::atomic<std::size_t> dequeue_pos_{0};

public:
    explicit MpmcQueue(std::size_t capacity) : mask_(capacity - 1), cells_(new Cell[capacity]) {
        for (std::size_t i = 0; i < capacity; ++i) cells_[i].seq.store(i, std::memory_order_relaxed);
    }
    // `after_claim` runs between claiming a position and publishing the item (used only by the stall demo).
    template <class Hook = decltype([] {})>
    bool try_push(const T& v, Hook after_claim = {}) {
        std::size_t pos = enqueue_pos_.load(std::memory_order_relaxed);
        for (;;) {
            Cell& c = cells_[pos & mask_];
            const std::size_t seq = c.seq.load(std::memory_order_acquire);
            const auto diff = static_cast<std::intptr_t>(seq) - static_cast<std::intptr_t>(pos);
            if (diff == 0) {                                   // free slot for this position: claim it
                if (enqueue_pos_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                    after_claim();
                    c.data = v;
                    c.seq.store(pos + 1, std::memory_order_release);   // publish to the consumer of pos
                    return true;
                }
            } else if (diff < 0) {
                return false;                                  // the slot still holds an unconsumed item: full
            } else {
                pos = enqueue_pos_.load(std::memory_order_relaxed);   // another producer took pos: catch up
            }
        }
    }
    bool try_pop(T& v) {
        std::size_t pos = dequeue_pos_.load(std::memory_order_relaxed);
        for (;;) {
            Cell& c = cells_[pos & mask_];
            const std::size_t seq = c.seq.load(std::memory_order_acquire);
            const auto diff = static_cast<std::intptr_t>(seq) - static_cast<std::intptr_t>(pos + 1);
            if (diff == 0) {                                   // item ready for this position: claim it
                if (dequeue_pos_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
                    v = c.data;
                    c.seq.store(pos + mask_ + 1, std::memory_order_release);   // free for the next lap
                    return true;
                }
            } else if (diff < 0) {
                return false;                                  // not published yet: empty (or a stalled producer)
            } else {
                pos = dequeue_pos_.load(std::memory_order_relaxed);
            }
        }
    }
};

using Clock = std::chrono::steady_clock;

// 2 producers x n items tagged (producer << 32 | sequence); 2 consumers check per-producer order and the total.
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
                std::uint64_t last[2] = {0, 0}, v = 0, local_sum = 0;
                while (count.load(std::memory_order_relaxed) < 2 * n) {
                    if (!pop(v)) continue;
                    const std::uint64_t p = v >> 32, i = v & 0xFFFF'FFFF;
                    if (i <= last[p]) order_ok = false;        // FIFO per producer, as seen by one consumer
                    last[p] = i;
                    local_sum += i;
                    count.fetch_add(1, std::memory_order_relaxed);
                }
                sum.fetch_add(local_sum);
            });
    }
    const std::chrono::duration<double, std::nano> d = Clock::now() - t0;
    ordered = order_ok.load();
    complete = count.load() == 2 * n && sum.load() == n * (n + 1);
    return d.count() / static_cast<double>(2 * n);
}

int main() {
    constexpr std::uint64_t n = 1'000'000;
    bool ordered = false, complete = false;
    {
        MpmcQueue<std::uint64_t> q(1024);
        const double ns = stress(n, [&](std::uint64_t v) { return q.try_push(v); },
                                 [&](std::uint64_t& v) { return q.try_pop(v); }, ordered, complete);
        std::println("Vyukov MPMC (1024 slots), 2P + 2C: {:6.1f} ns/item; every item once: {}; per-producer FIFO: {}", ns,
                     complete ? "yes" : "NO", ordered ? "yes" : "NO");
    }
    {
        std::mutex m;
        std::deque<std::uint64_t> q;
        const double ns = stress(
            n,
            [&](std::uint64_t v) {
                std::scoped_lock lk(m);
                if (q.size() >= 1024) return false;
                q.push_back(v);
                return true;
            },
            [&](std::uint64_t& v) {
                std::scoped_lock lk(m);
                if (q.empty()) return false;
                v = q.front();
                q.pop_front();
                return true;
            },
            ordered, complete);
        std::println("std::mutex + deque (bounded 1024): {:6.1f} ns/item; every item once: {}; per-producer FIFO: {}", ns,
                     complete ? "yes" : "NO", ordered ? "yes" : "NO");
    }
    // Not lock-free: a producer stalled between claiming a position and publishing blocks the consumers at
    // that position, even though later positions hold ready items.
    {
        MpmcQueue<std::uint64_t> q(8);
        std::latch claimed(1), resume(1);
        std::jthread stalled([&] { q.try_push(100, [&] { claimed.count_down(); resume.wait(); }); });
        claimed.wait();                               // position 0 is claimed but not published
        const bool pushed = q.try_push(200);          // position 1: published normally
        std::uint64_t v = 0;
        const bool got = q.try_pop(v);
        std::println("stalled producer at position 0, item 200 ready at position 1: push ok = {}, try_pop -> {}", pushed,
                     got ? "an item" : "false (the queue looks empty)");
        resume.count_down();
        stalled.join();
        std::uint64_t a = 0, b = 0;
        const bool ga = q.try_pop(a), gb = q.try_pop(b);
        std::println("after the producer resumes: pops {} and {} ({}, {})", a, b, ga ? "ok" : "fail", gb ? "ok" : "fail");
    }
}
```

Output (verified, GCC then Clang):

```text
Vyukov MPMC (1024 slots), 2P + 2C:   91.3 ns/item; every item once: yes; per-producer FIFO: yes
std::mutex + deque (bounded 1024):  123.4 ns/item; every item once: yes; per-producer FIFO: yes
stalled producer at position 0, item 200 ready at position 1: push ok = true, try_pop -> false (the queue looks empty)
after the producer resumes: pops 100 and 200 (ok, ok)
Vyukov MPMC (1024 slots), 2P + 2C:   95.2 ns/item; every item once: yes; per-producer FIFO: yes
std::mutex + deque (bounded 1024):  161.5 ns/item; every item once: yes; per-producer FIFO: yes
stalled producer at position 0, item 200 ready at position 1: push ok = true, try_pop -> false (the queue looks empty)
after the producer resumes: pops 100 and 200 (ok, ok)
```

```text
  cell i, lap L (capacity N):    seq == L*N + i          free: a producer holding position L*N + i may claim it
                                 seq == L*N + i + 1      full: the consumer holding position L*N + i may take it
  producer: CAS enqueue_pos (pos -> pos+1); write data; seq.store(pos + 1, release)
  consumer: CAS dequeue_pos (pos -> pos+1); read data;  seq.store(pos + N, release)   -> free for lap L+1
```

* **One CAS per operation**, on the position counter, plus one release store on the cell. The sequence number is a
  per-slot handshake: it tells producers which lap a slot belongs to, so no ABA is possible on positions, and it
  publishes the data like the SPSC ring's index does.
* **Measured** (two runs per compiler, 2 producers + 2 consumers, unpinned): 74–108 ns per item against 121–174 ns for
  a bounded `mutex` + `deque`, with every item delivered exactly once and FIFO per producer.
* **Not lock-free.** The last two lines of the output: a producer that has claimed position 0 but not yet published it
  makes `try_pop` return `false` ("empty") even though position 1 holds a ready item. Consumers can't skip a claimed
  slot, so a producer preempted at that instant stalls every consumer until it runs again. The queue uses no locks but
  is formally *blocking* for that window. Vyukov describes it this way himself. It is still an excellent bounded queue.

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| ring building blocks | `std::atomic` loads/stores with orders | — | `hardware_destructive_interference_size` | `atomic::wait` for blocking consumers | — | — |
| standard concurrent queue | none | — | — | — | — | none shipped by either library here (P0260 proposes standard concurrent queues) |
| layout | `alignas` | — | over-aligned `new` | — | — | — |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| one producer, one consumer | an MPMC queue or a mutex queue | SPSC ring with padded, cached indices (Listing 9.3) |
| SPSC indices declared next to each other | `std::atomic<size_t> head, tail;` (one line) | producer line {tail, head cache} and consumer line {head, tail cache}, 128-byte aligned |
| waiting when full or empty | tight spin on `try_push`/`try_pop` | `PAUSE`/`yield` back-off, then `atomic::wait` on the index for long waits |
| benchmarking a ring | unpinned threads, no regime counters | pin threads (cores vs siblings), count refreshes, report the regime |
| many producers, many consumers, bounded | `mutex` + `deque` | Vyukov's queue; for strict non-blocking requirements, a lock-free design (MS queue, file 03) or per-producer SPSC rings |
| N producers, 1 consumer (logging) | one MPMC queue with a hot enqueue counter | one SPSC ring per producer, drained round-robin by the consumer (Folder 11, problem 8) |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| ring throughput varies 10× between runs | thread placement (siblings vs cores) or full/flowing regime | pin threads; refresh counters |
| consumers stall although items are queued (Vyukov) | a producer preempted between claim and publish | per-slot sequence inspection; accept or use per-producer rings |
| stale or torn items on ARM only | slot written after the index store, or index published with relaxed | release on the index store, acquire on the index load (Folder 07) |
| SPSC ring corrupts under a second producer | SPSC used as MPSC | assert the single-producer contract (thread id check in debug builds) |
| index overflow after years of uptime | 32-bit indices wrapping | 64-bit monotonically increasing indices, masked on use |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Why does an SPSC ring need no CAS?"</b></summary>

**Initial prompt.** "Implement a lock-free SPSC queue. Which atomic operations do you need?"

**L5 textbook answer.** "A CAS on head and tail, so concurrent push and pop don't collide."

**Why L5 breaks.** With one producer and one consumer, each index has exactly one writer. Nothing needs to be
*arbitrated*, only *published*: a release store of `tail_` after writing the slot, and an acquire load of it before
reading. Listing 9.3's asm has no `LOCK` prefix and no exclusive pair. A CAS would add a full barrier and a contended
RMW for no benefit, and with relaxed ordering instead of release/acquire the consumer could read the slot before its
contents on ARM64 (Folder 07).

**L7 principal defense.** "Single-writer indices, release/acquire publication, power-of-two masking, 64-bit
monotonic indices, the two indices on separate 128-byte lines, each with the writer's cached copy of the other side.
Wait-free, no RMW, and the slot accesses are plain because the index handshake orders them."
</details>

<details><summary><b>Chain 2 ⚡ "What do cached indices buy you?"</b></summary>

**Initial prompt.** "Rigtorp-style SPSC queues cache the other side's index. Quantify the benefit."

**L5 textbook answer.** "It avoids reading an atomic, so it's always about 2× faster."

**Why L5 breaks.** It depends on the regime. Listing 9.3, pinned to two cores: while the ring *flows* (8–13% of pushes
need a refresh), the cached ring ran 5.4–9.2 ns per item vs 8.9–15.1 ns for the uncached variants. When the producer
outruns the consumer and the ring stays *full* (88–91% refreshes), every variant ran 47–61 ns: each failed push
refreshes, and caching saves nothing. On hyper-thread siblings, all variants were 2.3–5 ns because the line never leaves the core.

**L7 principal defense.** "Caching removes coherence traffic from the steady state, so it helps when neither side is
saturated. I'd measure with pinned threads and refresh counters, and I'd size the ring and the consumer so the ring
flows. If the producer is structurally faster, the fix is consumer throughput or batching, not the queue."
</details>

<details><summary><b>Chain 3 🧊 "Benchmark results are all over the place"</b></summary>

**Initial prompt.** "Our SPSC benchmark gives 4 ns on one run and 55 ns on the next. Noise?"

**L5 textbook answer.** "Run it more times and take the average."

**Why L5 breaks.** The variation is two different experiments. Unpinned, the scheduler sometimes places the threads on
hyper-thread siblings (2.3–5 ns) and sometimes on different cores (5–60 ns), and on different cores the ring is either
flowing or full. Averaging bimodal data produces a number that matches neither. A spinning side without back-off
widens the spread further.

**L7 principal defense.** "Pin threads explicitly, report both placements, count refreshes to identify the regime,
back off with `PAUSE`, and report ranges or distributions, not one mean. Then match the placement to production: the
real producer and consumer are usually on different cores, often on different NUMA nodes."
</details>

<details><summary><b>Chain 4 🔥 "Is Vyukov's queue lock-free?"</b></summary>

**Initial prompt.** "Vyukov's bounded MPMC queue uses only CAS and atomic stores. Lock-free?"

**L5 textbook answer.** "Yes, there are no locks."

**Why L5 deadlocks on ARM64.** No locks, but not lock-free. A producer claims position p (CAS on `enqueue_pos_`) and
then writes the slot and publishes `seq = p + 1`. If it is preempted in between, consumers reaching position p see an
unpublished slot and report "empty", even though later positions are full (Listing 9.4's stall demo: `try_pop ->
false` with item 200 ready behind position 0). Every consumer is stuck behind the stalled producer until it runs again:
a blocking window, like a lock held across preemption.

**L7 principal defense.** "It's 'lock-less' with a small blocking window, and excellent in practice: one CAS per
operation, no ABA thanks to per-slot laps. If the system needs real non-blocking behaviour, for example producers in
signal handlers or with real-time priorities, I'd use per-producer SPSC rings or a lock-free queue with helping."
</details>

<details><summary><b>Chain 5 ⚡ "Walk through Vyukov's sequence numbers"</b></summary>

**Initial prompt.** "Explain how Vyukov's queue knows a slot is free or full without a flag per slot."

**L5 textbook answer.** "Each cell has a full/empty flag that producers and consumers toggle."

**Why L5 breaks.** A boolean flag can't distinguish laps: after wrap-around, a slow producer from lap L could mistake
lap L+1's free slot for its own. That is ABA on the flag. Vyukov stores a **sequence number**: `seq == pos` means free for
the producer of position `pos`, and `seq == pos + 1` means it holds that position's item. The consumer frees the slot for
the next lap by storing `pos + capacity`. Comparing `seq - pos` (signed) tells each side whether it's early, on time,
or behind.

**L7 principal defense.** "Per-slot laps make positions unique for 2^64 operations, so the only CAS is on the
position counters and no ABA can happen on slots. Release stores on `seq` publish data and free slots; acquire loads
read them."
</details>

<details><summary><b>Chain 6 🧊 "64-bit or 32-bit indices?"</b></summary>

**Initial prompt.** "Our SPSC ring uses `uint32_t` head/tail and `tail - head == N` for full. Any problem?"

**L5 textbook answer.** "No, unsigned subtraction wraps correctly."

**Why L5 breaks.** Unsigned subtraction is correct across wrap-around only while the capacity divides 2^32 and the
indices never get more than 2^32 apart, which a ring guarantees. The trap is elsewhere: at millions of messages per
second a 32-bit index wraps every ~70 minutes, so any code that compares indices directly (`head < tail`), stores them
as sequence numbers, or uses them as message IDs breaks after the first wrap, in production, months later.

**L7 principal defense.** "64-bit monotonic indices (`size_t` on 64-bit targets): they never wrap in practice, all
comparisons are differences, and masking happens only on slot access. Same for Vyukov's positions."
</details>

<details><summary><b>Chain 7 ⚡ "The consumer spins at 100% CPU when the ring is empty"</b></summary>

**Initial prompt.** "Our consumer loops on `try_pop` and burns a core even when idle. Fix it without losing latency."

**L5 textbook answer.** "Add `sleep_for(1ms)` when the ring is empty."

**Why L5 breaks.** A 1 ms sleep becomes ~1–16 ms on Windows timers, and a message arriving during the sleep waits that
long. Latency goes from nanoseconds to milliseconds. Pure spinning has its own cost: on a shared core it starves the
sibling hyper-thread, and it keeps reading the producer's line.

**L7 principal defense.** "Spin with `PAUSE` for a bounded time, then block on `tail_.wait(last_seen)`. The producer
calls `tail_.notify_one()` only if a 'consumer sleeping' flag is set, so the fast path stays notify-free (an
eventcount pattern). Check `atomic::wait`'s backend on each platform first: on this Windows toolchain it is a proxy pool
or a polling loop (Folder 08, file 03)."
</details>

<details><summary><b>Chain 8 🔥 "Use the SPSC ring with two producers, just this once"</b></summary>

**Initial prompt.** "A second thread occasionally needs to push into our SPSC ring. It's rare, so is that OK?"

**L5 textbook answer.** "It's rare enough that collisions are unlikely; it should be fine."

**Why L5 corrupts memory on ARM64.** Both producers read the same `tail_`, both write slot `t`, and both store `t + 1`:
one item is lost, and the consumer may read a slot one producer is still writing. That is a data race on the slot, and
on ARM64 a torn or stale item. "Rare" means it passes tests and fails in production.

**L7 principal defense.** "The contract is enforced: a debug-mode producer-thread-id check, and a second ring for the
second producer. N rings drained by one consumer are still faster than one MPMC queue, and there is no hot shared
counter."
</details>

---

## 6. Invariants checklist

- [ ] Each SPSC index has one writer; publication is release, observation is acquire; slots are written before
      publication.
- [ ] Producer- and consumer-owned fields live on separate 128-byte lines.
- [ ] Indices are 64-bit and monotonic; masking happens only on slot access.
- [ ] Waiting sides back off (`PAUSE`), then block; spinning never hammers the other side's line.
- [ ] Ring benchmarks pin threads and report placement and regime.
- [ ] The single-producer/single-consumer contract is asserted in debug builds.
- [ ] Vyukov's blocking window is acceptable for the system, or per-producer rings are used.

## 7. References

- D. Vyukov, "Bounded MPMC queue": <https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue>
- E. Rigtorp, `SPSCQueue` (cached indices): <https://github.com/rigtorp/SPSCQueue>
- E. Rigtorp, `MPMCQueue` (a Vyukov-style queue with ticket counters): <https://github.com/rigtorp/MPMCQueue>
- P0260 (C++ concurrent queues proposal): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p0260r7.html>
- M. Thompson et al., LMAX Disruptor (ring-buffer design and mechanical sympathy): <https://lmax-exchange.github.io/disruptor/disruptor.html>
