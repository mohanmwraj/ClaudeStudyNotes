# PR08 · Lock-Free Ring Buffer: ARM64 Memory Order and ABA Corruption

> **What this module is.** A market-data PR replaces the mutex-guarded feed → strategy hand-off with a lock-free single-producer/single-consumer ring. It also turns the snapshot-buffer pool into a lock-free Treiber stack. It hides **8 defects (6 Sev-1)**. All of them compile cleanly on GCC 16 and Clang 21 and pass the author's tests, including a two-thread transfer test on x86-64. Two would only misbehave on weakly ordered CPUs such as AArch64 (Graviton, Ampere, Apple silicon), and this module shows them in the generated instructions. Four are deterministic and fire on any CPU. The probes reproduce all of them single-threaded, inside defined behavior. The ABA interleaving is driven through the pool's schedule-point hook.

| Artifact | What it is | Verified |
|---|---|---|
| `pr08-diff` | `spsc_ring.hpp` (mutex → atomics), `snapshot_pool.hpp` (mutex → Treiber stack), `feed.hpp` (drop counter removed), test rewritten: 226 diff lines | `git diff --no-index` from compiled sources |
| `handoff_test.cpp` (author's) | 6 tests incl. a two-thread transfer of 1,000 ticks | **6/6 pass** on GCC and Clang (§4) |
| `probes.cpp` | 6 probes: sequence wrap, index layout, scripted ABA, slot reuse, production capacity, full-ring drops | each shows the defect on the PR and its absence on the fix (§8) |
| `asm_probe.cpp` | `ring_push`/`ring_pop` compiled by Clang 21 `-O2` for `aarch64-linux-gnu` and `x86_64-linux-gnu` | PR vs fix listings (§8.2) |
| Fixed code | Acquire/release hand-off, wrap-safe comparisons, padded indices, tagged free-list head, copy-out `try_pop` plus `front`/`pop`, power-of-two capacity, counted drops | fixed suite 12/12; PR's own tests against the fix 6/6 |

**Verification.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (Zig 0.16, libc++), `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`. Each test and probe binary is built and run with both compilers, with identical results. The AArch64 and x86-64 listings come from `clang -S` on the same headers, so the instructions shown are the compiler's actual output, not hand-written. No ARM hardware was used: the hardware reordering on AArch64 is argued from the instruction listings, the C++ memory model and the cited references, not observed.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L2 Concurrency (memory model) | F1 relaxed publication of the tail, F2 relaxed hand-back of the head, F5 ABA in the Treiber stack | Tests pass on x86, where relaxed and release compile to the same `mov` |
| L1 Correctness (arithmetic) | F3 `h >= t` across the 32-bit wrap, F7 `& (N - 1)` with `N = 1000` | Arithmetic looks right at small numbers, and `N = 1000` is on an unchanged line outside the diff |
| L3 Lifetimes and failure paths | F6 pointer into a slot that was already handed back, F8 dropped ticks with no counter | "Zero-copy" sounds like an optimization; "lock-free never blocks" sounds like a guarantee |
| L7 Performance | F4 head and tail on one cache line | Invisible in correctness tests; it's the reason the PR exists |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "Single writer per index, so relaxed is fine." | Atomicity of the index isn't the question; visibility of the *slot* is. |
| "It passed a two-thread test." | On x86-64, TSO hides missing acquire/release. AArch64 doesn't. |
| "CAS makes it safe." | CAS compares values, not histories: ABA. |
| "Indices are unsigned, so wrap is fine." | Only subtraction is wrap-safe; `>=` isn't. |
| "Masks are faster than modulo." | Only when `N` is a power of two. Nothing enforced that here. |
| "Review the diff." | F7's other half is an unchanged line. |

---

## 1. First principles

1. **Relaxed means atomic, not ordered.** cppreference on `memory_order_relaxed`: "there are no synchronization or ordering constraints imposed on other reads or writes, only this operation's atomicity is guaranteed." A relaxed tail store publishes the *index*, but says nothing about when the slot's bytes become visible.
2. **Release/acquire is the hand-off contract.** cppreference: if a release store is read by an acquire load, "the store in thread A *synchronizes-with* the load in thread B", and "all memory writes (including non-atomic and relaxed atomic) that *happened-before* the atomic store in thread A also *happened-before* the atomic load in thread B." Without that edge, the non-atomic slot accesses are a data race, which is undefined behavior.
3. **x86 hides it, AArch64 doesn't.** cppreference: "On strongly-ordered systems — x86, SPARC TSO, IBM mainframe, etc. — release-acquire ordering is automatic for the majority of operations. No additional CPU instructions are issued … On weakly-ordered systems (ARM, Itanium, PowerPC), special CPU load or memory fence instructions are used." The LLVM atomics guide says the same about acquire: "Architectures with weak memory ordering (essentially everything relevant today except x86 and SPARC) require some sort of fence."
4. **Modular indices compare by subtraction.** With `uint32_t` indices, `tail - head` is the queue length modulo 2³², correct across the wrap. `head >= tail` is not.
5. **Masking needs a power of two.** `i & (N - 1)` equals `i % N` only when `N` is a power of two. Otherwise the mask clears bits and folds many indices onto one slot.
6. **ABA.** Wikipedia: the ABA problem occurs "when a location is read twice, has the same value for both reads", and "the read value being the same twice is used to conclude that nothing has happened in the interim". A Treiber stack's `pop` reads `top`, reads `top->next`, then CASes `top → next`. If `top` was popped and pushed back in between, the CAS succeeds with a stale `next`. The common workaround: "add extra 'tag' or 'stamp' bits."
7. **False sharing.** Two indices written by two cores on one cache line force the line to move between cores on every operation. cppreference's `hardware_destructive_interference_size` is the "minimum offset between two objects to avoid false sharing". GCC warns against using that constant in a header ABI (§6, F4).

---

## 2. The PR

> **MD-412 · Lock-free feed → strategy hand-off**
>
> The mutex hand-off between the feed handler (network thread) and the strategy thread costs 2–5 µs at p99.9 under contention, and the strategy team's latency budget is 10 µs end to end. Replace it with a lock-free SPSC ring. While there, the snapshot pool's mutex shows up in strategy-thread profiles: make it lock-free too. Production is moving to AArch64 (Graviton) hosts next quarter.
>
> **PR description, by the author:**
> - `SpscRing`: two `std::atomic<uint32_t>` indices; "each index has exactly one writer, so relaxed loads and stores are enough."
> - Slot selection with `& (N - 1)` instead of `% N`: no division on the hot path.
> - `try_pop` is zero-copy: it returns a pointer into the ring.
> - `SnapshotPool`: Treiber stack with CAS; a `POOL_SCHEDULE_POINT()` hook for future interleaving tests.
> - `FeedHandler::on_tick` no longer branches: "a lock-free ring never blocks."
> - Tests: ordering, full ring, checkpoint resume, a two-thread transfer, feed publishing, pool uniqueness. Green on GCC and Clang (x86-64).
>
> **Context the reviewer can discover:** `feed.hpp` line 11 (unchanged): `using TickRing = SpscRing<Tick, 1000>;`. Sequence numbers are 32-bit and persist across restarts. At the 1M ticks/s peak the sequence space wraps every 2³² / 10⁶ s ≈ 71.6 minutes of peak traffic. The strategy resyncs from a snapshot when `dropped()` moves. The previous test `feed_handler_counts_drops` pushed 1,200 ticks and expected 200 drops. Production hardware: x86-64 today, AArch64 next quarter.

---

## 3. The diff

```diff
diff --git a/marketdata/handoff/include/feed.hpp b/marketdata/handoff/include/feed.hpp
index 13224dd..c4474b1 100644
--- a/marketdata/handoff/include/feed.hpp
+++ b/marketdata/handoff/include/feed.hpp
@@ -15,20 +15,15 @@ public:
     explicit FeedHandler(TickRing& ring) : ring_(ring) {}
 
     void on_tick(const Tick& tick) { // network thread
-        if (ring_.try_push(tick)) {
-            published_.fetch_add(1, std::memory_order_relaxed);
-        } else {
-            dropped_.fetch_add(1, std::memory_order_relaxed); // the strategy resyncs from a snapshot when this moves
-        }
+        ring_.try_push(tick); // lock-free: never blocks the network thread
+        published_.fetch_add(1, std::memory_order_relaxed);
     }
 
     std::uint64_t published() const { return published_.load(std::memory_order_relaxed); }
-    std::uint64_t dropped() const { return dropped_.load(std::memory_order_relaxed); }
 
 private:
     TickRing& ring_;
     std::atomic<std::uint64_t> published_{0};
-    std::atomic<std::uint64_t> dropped_{0};
 };
 
 // Strategy thread: drains everything queued and returns how many ticks it consumed.
diff --git a/marketdata/handoff/include/snapshot_pool.hpp b/marketdata/handoff/include/snapshot_pool.hpp
index b4db8c1..cc753ae 100644
--- a/marketdata/handoff/include/snapshot_pool.hpp
+++ b/marketdata/handoff/include/snapshot_pool.hpp
@@ -1,12 +1,17 @@
 #pragma once
-// snapshot_pool.hpp - fixed pool of order-book snapshot buffers, shared by the strategy threads.
+// snapshot_pool.hpp - fixed pool of order-book snapshot buffers, shared by the strategy threads. The free list is a
+// lock-free (Treiber) stack, so returning a buffer never waits on another strategy thread (MD-412).
 #include <array>
+#include <atomic>
 #include <cstddef>
 #include <cstdint>
-#include <mutex>
-#include <vector>
+
+#ifndef POOL_SCHEDULE_POINT
+#define POOL_SCHEDULE_POINT() ((void)0) // tests may define it to interleave operations deterministically
+#endif
 
 struct Snapshot {
+    Snapshot* next = nullptr; // free-list link, meaningful only while the snapshot is free
     std::array<std::int64_t, 512> levels{};
 };
 
@@ -14,29 +19,30 @@ template <std::size_t N>
 class SnapshotPool {
 public:
     SnapshotPool() {
-        free_.reserve(N);
         for (Snapshot& s : storage_) {
-            free_.push_back(&s);
+            release(&s);
         }
     }
 
     Snapshot* acquire() {
-        std::lock_guard<std::mutex> lock(mu_);
-        if (free_.empty()) {
-            return nullptr; // exhausted
+        Snapshot* top = head_.load(std::memory_order_acquire);
+        while (top != nullptr) {
+            Snapshot* next = top->next;
+            POOL_SCHEDULE_POINT();
+            if (head_.compare_exchange_weak(top, next, std::memory_order_acquire)) {
+                return top;
+            }
         }
-        Snapshot* s = free_.back();
-        free_.pop_back();
-        return s;
+        return nullptr; // exhausted
     }
 
     void release(Snapshot* s) {
-        std::lock_guard<std::mutex> lock(mu_);
-        free_.push_back(s);
+        s->next = head_.load(std::memory_order_relaxed);
+        while (!head_.compare_exchange_weak(s->next, s, std::memory_order_release, std::memory_order_relaxed)) {
+        }
     }
 
 private:
-    std::mutex mu_;
     std::array<Snapshot, N> storage_{};
-    std::vector<Snapshot*> free_;
+    std::atomic<Snapshot*> head_{nullptr};
 };
diff --git a/marketdata/handoff/include/spsc_ring.hpp b/marketdata/handoff/include/spsc_ring.hpp
index 969be6a..18b756d 100644
--- a/marketdata/handoff/include/spsc_ring.hpp
+++ b/marketdata/handoff/include/spsc_ring.hpp
@@ -1,10 +1,9 @@
 #pragma once
-// spsc_ring.hpp - the feed -> strategy hand-off: a fixed ring guarded by a mutex.
+// spsc_ring.hpp - the feed -> strategy hand-off: a lock-free single-producer/single-consumer ring (MD-412).
 #include <array>
+#include <atomic>
 #include <cstddef>
 #include <cstdint>
-#include <mutex>
-#include <optional>
 
 template <typename T, std::size_t N>
 class SpscRing {
@@ -13,34 +12,34 @@ public:
     // committed sequence.
     explicit SpscRing(std::uint32_t first_seq = 0) : head_(first_seq), tail_(first_seq) {}
 
-    bool try_push(const T& value) {
-        std::lock_guard<std::mutex> lock(mu_);
-        if (tail_ - head_ == N) {
+    // Each index has exactly one writer, so relaxed loads and stores are enough: no fences, no read-modify-writes.
+    bool try_push(const T& value) { // producer thread only
+        std::uint32_t t = tail_.load(std::memory_order_relaxed);
+        std::uint32_t h = head_.load(std::memory_order_relaxed);
+        if (t - h == N) {
             return false; // full
         }
-        slots_[tail_ % N] = value;
-        ++tail_;
+        slots_[t & (N - 1)] = value; // mask instead of %: no division on the hot path
+        tail_.store(t + 1, std::memory_order_relaxed);
         return true;
     }
 
-    std::optional<T> try_pop() {
-        std::lock_guard<std::mutex> lock(mu_);
-        if (tail_ == head_) {
-            return std::nullopt; // empty
+    // Zero-copy: hands out a pointer into the ring instead of copying the tick.
+    const T* try_pop() { // consumer thread only
+        std::uint32_t h = head_.load(std::memory_order_relaxed);
+        std::uint32_t t = tail_.load(std::memory_order_relaxed);
+        if (h >= t) {
+            return nullptr; // empty
         }
-        T value = slots_[head_ % N];
-        ++head_;
+        const T* value = &slots_[h & (N - 1)];
+        head_.store(h + 1, std::memory_order_relaxed);
         return value;
     }
 
-    std::size_t size() const {
-        std::lock_guard<std::mutex> lock(mu_);
-        return tail_ - head_;
-    }
+    std::size_t size() const { return tail_.load(std::memory_order_relaxed) - head_.load(std::memory_order_relaxed); }
 
 private:
-    mutable std::mutex mu_;
     std::array<T, N> slots_{};
-    std::uint32_t head_;
-    std::uint32_t tail_;
+    std::atomic<std::uint32_t> head_; // written by the consumer only
+    std::atomic<std::uint32_t> tail_; // written by the producer only
 };
diff --git a/marketdata/handoff/test/handoff_test.cpp b/marketdata/handoff/test/handoff_test.cpp
index ffd743d..70064e4 100644
--- a/marketdata/handoff/test/handoff_test.cpp
+++ b/marketdata/handoff/test/handoff_test.cpp
@@ -1,5 +1,6 @@
-// handoff_test.cpp - unit tests for the tick ring, the feed handler and the snapshot pool.
+// handoff_test.cpp - unit tests for the lock-free tick ring, the feed handler and the snapshot pool.
 #include <algorithm>
+#include <thread>
 #include <vector>
 
 #include "check.hpp"
@@ -31,14 +32,44 @@ TEST(full_ring_rejects_push) {
     CHECK(ring.size() == 4);
 }
 
-TEST(feed_handler_counts_drops) {
+TEST(resumes_from_checkpoint_sequence) {
+    SpscRing<Tick, 8> ring(5'000'000);
+    CHECK(ring.try_push(tick(5'000'000)));
+    CHECK(ring.size() == 1);
+    auto t = ring.try_pop();
+    CHECK(t && t->seq == 5'000'000);
+}
+
+TEST(transfers_across_threads) {
+    SpscRing<Tick, 1024> ring;
+    constexpr std::uint32_t kTicks = 1000;
+    std::thread producer([&] {
+        for (std::uint32_t i = 0; i < kTicks; ++i) {
+            while (!ring.try_push(tick(i))) {
+            }
+        }
+    });
+    std::uint32_t received = 0;
+    bool ordered = true;
+    while (received < kTicks) {
+        if (auto t = ring.try_pop()) {
+            ordered = ordered && t->seq == received;
+            ++received;
+        }
+    }
+    producer.join();
+    CHECK(ordered);
+}
+
+TEST(feed_handler_publishes_every_tick) {
     TickRing ring;
     FeedHandler feed(ring);
-    for (std::uint32_t i = 0; i < 1200; ++i) {
+    for (std::uint32_t i = 0; i < 100; ++i) {
         feed.on_tick(tick(i));
     }
-    CHECK(feed.published() == 1000);
-    CHECK(feed.dropped() == 200);
+    std::vector<Tick> out;
+    CHECK(drain(ring, out) == 100);
+    CHECK(feed.published() == 100);
 }
 
 TEST(pool_hands_out_each_snapshot_once) {
```

---

## 4. The author's tests: green

```text
ok   pushes_and_pops_in_order
ok   full_ring_rejects_push
ok   resumes_from_checkpoint_sequence
ok   transfers_across_threads
ok   feed_handler_publishes_every_tick
ok   pool_hands_out_each_snapshot_once
6 passed, 0 failed
```

The tests run on x86-64 only. The two-thread test transfers 1,000 ticks through a 1,024-slot ring, so the producer never laps the consumer and no slot is ever reused (F2 and F6 can't fire). It is itself a data race on the PR's code under the C++ memory model (F1): it passes because x86 keeps stores in order, and because both compilers emitted the slot stores before the tail store (§8.2). No test starts near the 32-bit wrap, instantiates the production `TickRing`, overfills the ring through `FeedHandler` (the test that did was rewritten from 1,200 ticks to 100), or interleaves pool operations, even though the PR adds a hook for exactly that. All six tests also pass against the fixed code (§7).

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** ordering of the slot hand-off (both directions), index arithmetic, slot selection, lifetime of popped data, free-list correctness under concurrency, and drop accounting.
- **Hunk scores:** `try_push`/`try_pop` 8/8, `SnapshotPool::acquire` 8/8, `on_tick` 6/8, member layout 4/8.
- **Radar hits:** six `memory_order_relaxed` with a comment justifying them by "one writer" (ring 15–35). `h >= t` (31). `& (N - 1)` with no `static_assert` (22, 34). `return value;` *after* `head_.store` (34–36). `Snapshot* next = top->next;` then CAS (pool 30–32). `ring_.try_push(tick);` with the result discarded and `dropped_` deleted (feed 18). The test rewritten from 1,200 ticks to 100.

### Minute 10: one hop each

- Who reads the slot after the tail store, and what orders that read? Nothing: F1. Who writes the slot after the head store? The producer, unordered: F2.
- What does `h >= t` do when `t` wraps to 8 and `h` is 4,294,967,288? It says "empty" forever: F3.
- Where do `head_` and `tail_` live? Adjacent, 8 bytes total: F4.
- What happens if `top` is popped and pushed back between line 30 and line 32? The CAS succeeds with a stale `next`: F5.
- After `try_pop` returns, can the producer write that slot? Yes, it was handed back on line 35: F6.
- What is `N` in production? Open `feed.hpp`: 1,000, not a power of two: F7.
- Where do rejected ticks go? Nowhere, uncounted: F8.

### Minute 20: prove, unify, fix

- **Unify:** the ring is a *protocol*: the producer owns a slot until it publishes it (release on `tail`), and the consumer owns it until it hands it back (release on `head`). The other side takes ownership with an acquire. F1 and F2 drop the ordering half of that protocol, and F6 hands a slot back while still using it. F3 and F7 break the index→slot mapping the protocol depends on. F5 is the same "who owns this node" question in the pool. F8 makes every failure silent.
- **Fix shape:** release stores and acquire loads on the *other* side's index (own index stays relaxed); `t - h` comparisons only; `static_assert(has_single_bit(N))` and `N = 1024`; padding of each index to 128 bytes; copy-out `try_pop` plus `front`/`pop` for zero-copy; a tagged 64-bit head (index plus version) for the pool; drops counted and surfaced.

---

## 6. The L7 answer key, line by line

### F1 · L2 · Sev-1 · The tail is published with relaxed ordering, so the consumer can see a slot before its contents (ring 23, 30)

**Mechanism.** The producer writes the 24-byte slot (line 22), then stores `tail = t + 1` with `memory_order_relaxed` (23). The consumer loads `tail` relaxed (30) and then reads the slot. Relaxed creates no happens-before edge, so in C++ terms the slot write and the slot read are a data race: undefined behavior. In hardware terms on AArch64, the plain `str` to the tail may become visible before the two `str`s to the slot, and the consumer's slot loads may be satisfied before its tail load. Either way the strategy reads the previous lap's tick or a torn one (the 16-byte and 8-byte halves are separate stores) and trades on a price that was never quoted. On x86-64 the hardware keeps stores in order and both compilers happened to emit them in source order, so every test passes.

**Evidence.** §8.2 listings, Clang 21 `-O2`. PR, AArch64 `ring_push`: slot `str x12, [x11, #16]` / `str q0, [x11]`, then `str w10, [x8, #4]` (plain store of the tail). PR `ring_pop`: `ldr w9, [x10, #4]` (plain load of the tail). Fix: `stlr w9, [x11]` (store-release) and `ldar w9, [x9]` (load-acquire). x86-64: `mov dword ptr [...], eax` for the tail store in **both** versions, which is cppreference's "no additional CPU instructions are issued" made visible.

```comment-l7
issue (blocking): the tail store and the consumer's tail load are relaxed, so on AArch64 the consumer can read a slot before the producer's write to it is visible

Relaxed gives atomicity of the index but no ordering of the slot write before it, which means the slot accesses are a data race (UB) and on weakly ordered CPUs the strategy can read the previous lap's tick or a torn one. The x86 test can't show it: the listings for x86-64 are a plain mov for relaxed and for release alike, while AArch64 emits str/ldr here and stlr/ldar with release/acquire (asm probe in the PR thread). Suggest tail_.store(..., memory_order_release) in try_push and tail_.load(memory_order_acquire) on the consumer side; the producer's load of its own tail can stay relaxed.
```

**Fix.**
```cpp
        tail_.store(t + 1, std::memory_order_release); // publishes the slot write to the consumer
```
```cpp
        std::uint32_t t = tail_.load(std::memory_order_acquire); // pairs with try_push(): the slot write is visible
```

### F2 · L2 · Sev-1 · The head is handed back with relaxed ordering, so the producer can overwrite a slot the consumer is still reading (ring 18, 35)

**Mechanism.** This is the mirror image of F1. The consumer's reads of a slot must finish before the producer reuses it. The producer learns that from `head`, but the consumer stores `head` relaxed (35) and the producer loads it relaxed (18). Armv8 permits a load to be ordered after a later store to a different address. So the consumer's slot read can be satisfied *after* its `head` store is visible, the producer laps around, and the read returns the new tick's bytes. F6 makes this worse in the PR (the read is after the store in program order). Even a copying `try_pop` would still need a release on `head`.

**Evidence.** PR AArch64 `ring_push`: `ldr w9, [x8]` (head, plain). `ring_pop`: `str w12, [x10]` (head, plain). Fix: `ldar w8, [x0]` in `ring_push`, and in `ring_pop` the slot loads (`ldr x12` / `ldrb` / `ldur q0`) come before `stlr w11, [x0]`.

```comment-l7
issue (blocking): the consumer releases the head relaxed and the producer reads it relaxed, so the producer can reuse a slot while the consumer's reads of it are still pending

Without release on head_ the consumer's slot loads aren't ordered before the hand-back, which means on AArch64 a lapping producer can overwrite the tick mid-read; the asm probe shows the producer side compiling to a plain ldr of head_ and the consumer side to a plain str. Suggest head_.store(..., memory_order_release) after the consumer is done with the slot and head_.load(memory_order_acquire) in try_push; together with the tail fix that's the complete SPSC protocol, and nothing needs seq_cst.
```

**Fix.**
```cpp
        std::uint32_t h = head_.load(std::memory_order_acquire); // pairs with pop(): the consumer is done with the slot
```
```cpp
        head_.store(head_.load(std::memory_order_relaxed) + 1, std::memory_order_release);
```

### F3 · L1 · Sev-1 · `h >= t` treats the ring as empty after the 32-bit index wraps: the consumer stalls (ring 31)

**Mechanism.** Indices start at the persisted sequence number and wrap modulo 2³². `try_push` checks fullness with `t - h == N`, which is wrap-safe. `try_pop` checks emptiness with `h >= t`, which isn't. Once `t` wraps past zero while `h` hasn't, `h >= t` is true and the consumer sees an empty ring with up to `N` ticks queued. The ring fills within a millisecond, and every later tick is rejected, silently (F8). The strategy trades on a frozen book. Because sequences persist across restarts, the wrap happens at some point in production, and at the 1M/s peak the 32-bit space lasts about 71.6 minutes.

**Evidence.** P3 seeds the ring at 4,294,967,288 and pushes 16 ticks across the wrap. PR: `consumer received 0, size() = 16`. Fix: `received 16, size() = 0`. Note that `size()` (subtraction) is right while `try_pop` (comparison) is wrong in the same class.

```comment-l7
issue (blocking): try_pop's `h >= t` breaks when the 32-bit index wraps, so the consumer reports empty while ticks are queued and the feed stalls

Indices start at the persisted sequence and wrap modulo 2^32; once tail wraps and head hasn't, `h >= t` is true, which means the strategy stops consuming and the ring then rejects every tick. The P3 probe seeds the ring 8 below the wrap and pushes 16: the consumer receives 0 while size() reports 16. Suggest comparing only through subtraction (`t - h == 0` for empty, as try_push already does for full), plus a test seeded near 0xFFFFFFF8.
```

**Fix.**
```cpp
        return t - h == 0 ? nullptr : &slots_[h & (N - 1)];
```

### F4 · L7 · Sev-2 · `head_` and `tail_` share a cache line, so every push and pop moves the line between cores (ring 42–44)

**Mechanism.** The consumer writes `head_` and the producer writes `tail_`. Each also reads the other's index on every operation. Packed into 8 bytes next to the last slot, they live on one line, so every store forces it to bounce between the two cores. That is the coherence traffic the PR was supposed to remove. On 128-byte-line systems (Apple M-series) and with Intel's adjacent-line prefetcher, 64-byte padding isn't enough either.

**Evidence.** P4: PR `bytes outside the slot array = 8, alignof = 8 -> head_ and tail_ share one cache line`. Fix: `256, alignof = 128 -> separate 128-byte blocks`. This module did not measure the throughput impact (see Q6 for how to). On `std::hardware_destructive_interference_size`: GCC 16.2 warns when it is used in a header (`-Winterference-size`): "its value can vary between compiler versions or with different '-mtune' or '-mcpu' flags", and "if this use is part of a public ABI, change it to instead use a constant variable you define" (compiler output, verified locally).

```comment-l7
issue (blocking): head_ and tail_ sit in the same 8 bytes, so the producer's and consumer's stores contend for one cache line on every operation

Each side writes its own index and reads the other's, which means the line ping-pongs between the two cores and we keep much of the coherence cost the mutex had (P4 probe: 8 bytes for both indices, alignof 8). Suggest alignas(128) on head_, tail_ and slots_ through a named constant rather than std::hardware_destructive_interference_size, which GCC warns about in headers because its value changes with -mtune.
```

**Fix.**
```cpp
inline constexpr std::size_t kFalseSharingRange = 128;
```
```cpp
    alignas(kFalseSharingRange) std::atomic<std::uint32_t> head_; // written by the consumer only
    alignas(kFalseSharingRange) std::atomic<std::uint32_t> tail_; // written by the producer only
    alignas(kFalseSharingRange) std::array<T, N> slots_{};
```

### F5 · L2 · Sev-1 · The Treiber stack's `acquire` is open to ABA: two strategy threads end up owning one snapshot buffer (pool 28–32)

**Mechanism.** Thread 1 reads `top = A` and `next = B` (line 30), then is preempted at line 31. Thread 2 pops A, pops B (keeps it) and pushes A back. The head is A again, so thread 1's CAS `A → B` succeeds (line 32) and installs B as the free-list head, but thread 2 owns B. The next `acquire` returns B, and two strategy threads write order-book levels into one buffer. There is a second defect on the same line: `top->next` is a non-atomic read of a field that another thread's `release` may be writing, which is a data race on its own.

**Evidence.** P5 runs thread 2's three operations at `POOL_SCHEDULE_POINT()`, between thread 1's read of `next` and its CAS. PR: `the next acquire() hands out B, which thread 2 still holds: true`. Fix: `false`. The fixed CAS fails on the changed tag, re-reads, and pops the correct node.

```comment-l7
issue (blocking): acquire() is vulnerable to ABA, so after a pop-pop-push interleaving two strategy threads can hold the same snapshot buffer

If thread 1 reads top=A and next=B, and thread 2 then pops A, pops B and pushes A back, thread 1's CAS still sees A and installs B, which thread 2 owns, so the next acquire hands B out twice. The P5 probe drives exactly this interleaving through the new POOL_SCHEDULE_POINT hook. Suggest a tagged head: a 64-bit word holding a 32-bit slot index and a 32-bit version bumped on every push and pop, with `next` stored as std::atomic<uint32_t> (the current non-atomic read of top->next is also a data race).
```

**Fix.**
```cpp
    std::atomic<std::uint32_t> next{0}; // free-list link (an index); read by acquire() while others may write it
```
```cpp
            std::uint32_t next = storage_[index(top)].next.load(std::memory_order_relaxed);
            POOL_SCHEDULE_POINT();
            // The head carries a tag bumped by every push and pop: if the top was popped and pushed back since our
            // load (ABA), the tag differs and this compare-exchange fails instead of installing a stale next.
            if (head_.compare_exchange_weak(top, pack(next, tag(top) + 1), std::memory_order_acquire)) {
                return &storage_[index(top)];
            }
```
```cpp
    static_assert(std::atomic<std::uint64_t>::is_always_lock_free, "the head must be one lock-free word");
```

### F6 · L3 · Sev-1 · Zero-copy `try_pop` hands back the slot, then returns a pointer to it (ring 34–36, feed 32)

**Mechanism.** `try_pop` stores `head = h + 1` (line 35), telling the producer the slot is free, and *then* returns a pointer into that slot. The consumer, including the PR's own `drain()`, reads through it after the producer is allowed to overwrite it. Under load, that's a lapping producer writing tick N + 1024 into the bytes the strategy is reading as tick N. The listings make it concrete: on both targets the PR's `ring_pop` stores the head *before* loading the slot.

**Evidence.** P6: the consumer holds tick 0, and the producer pushes tick 8 into the 8-slot ring (accepted, because the slot was handed back). PR: `the consumer's tick now reads seq 8`. Fix: `seq 0` (the consumer holds a copy). §8.2 PR `ring_pop`: `str w12, [x10]` (head) precedes `ldr x10, [x11, #16]` / `ldr q0, [x11]` (slot) on AArch64, and `mov dword ptr [rdi + 24576], r8d` precedes the slot loads on x86-64.

```comment-l7
issue (blocking): try_pop advances head_ before the caller reads the slot, so the producer may overwrite the tick the strategy is processing

Once head_ moves, the producer owns the slot, which means the returned pointer refers to memory that can change under the reader; the P6 probe shows the held tick changing from seq 0 to seq 8 after one more push, and the compiled ring_pop stores head_ before loading the slot on both targets. Suggest try_pop copy the 24-byte tick out before advancing (it is one cache line, cheaper than the risk), and for large T a front()/pop() pair where pop() is called after the consumer is done.
```

**Fix.**
```cpp
    [[nodiscard]] std::optional<T> try_pop() { // copies the element out before the slot is handed back
        const T* value = front();
        if (value == nullptr) {
            return std::nullopt;
        }
        std::optional<T> out(*value);
        pop();
        return out;
    }
```

### F7 · L1 · Sev-1 · `& (N - 1)` with the production `N = 1000` folds 1,000 indices onto 256 slots (ring 22, 34; feed 11, unchanged)

**Mechanism.** `i & 999` clears bits 3 and 4 (999 = `0b1111100111`), so only 256 distinct slots are ever used, and four indices share each one. `try_push` still believes it has 1,000 free slots, so it overwrites ticks that haven't been read yet, and the consumer receives the last writer of each slot repeatedly. Nothing crashes and nothing logs: the order book is silently wrong. The line that makes it fatal, `using TickRing = SpscRing<Tick, 1000>`, is unchanged and outside the diff. L7 aside: the old `% N` was correct for `N = 1000` until the 32-bit wrap, but 2³² mod 1000 = 296, so the mutex version had a latent slot collision at the wrap too. A power-of-two `N` fixes both.

**Evidence.** P7 on the production `TickRing`. PR: `capacity 1000 (power of two: false): 1000 pushed, 256 delivered in order, 256 distinct ticks delivered`, so 744 of 1,000 ticks were lost and replaced by duplicates. Fix: `capacity 1024: 1024 pushed, 1024 delivered in order, 1024 distinct`. In the fixed code, `SpscRing<Tick, 1000>` no longer compiles.

```comment-l7
issue (blocking): slots are now selected with `& (N - 1)`, but TickRing (feed.hpp line 11, unchanged) uses N = 1000, so 1,000 indices fold onto 256 slots and unread ticks get overwritten

The mask equals % N only for powers of two; with 999 it clears bits 3 and 4, which means a full ring delivers 256 distinct ticks out of 1,000 with no error (P7 probe on the production TickRing). Suggest static_assert(std::has_single_bit(N)) in SpscRing so this can't compile, and TickRing = SpscRing<Tick, 1024>; that also removes a latent collision the old % 1000 had at the 32-bit wrap.
```

**Fix.**
```cpp
    static_assert(std::has_single_bit(N), "N must be a power of two: slots are selected with index & (N - 1)");
```
```cpp
using TickRing = SpscRing<Tick, 1024>; // ~1 ms of ticks at the 1M/s peak; a power of two (see SpscRing)
```

### F8 · L3 · Sev-2 · `on_tick` discards `try_push`'s result and the drop counter is deleted, so a full ring loses ticks silently (feed 18–19)

**Mechanism.** "A lock-free ring never blocks" is true, and it also means a full ring *rejects*. The PR ignores the rejection, still counts the tick as published, and deletes `dropped()`, which the strategy uses to trigger a snapshot resync. Combined with F3, that is a frozen feed with a dashboard showing 100% published. The author also changed the one test that covered this (1,200 ticks → 100).

**Evidence.** P8: 1,500 ticks with no consumer. PR: `published() = 1500, queued = 1000, lost with no counter = 500`. Fix: `published() = 1024, queued = 1024, dropped() = 476`.

```comment-l7
issue (blocking): on_tick ignores try_push's result and the PR removes dropped(), so a full ring loses ticks with no signal and the strategy never resyncs

Lock-free means a full ring rejects instead of blocking, which means rejected ticks are lost while published() still counts them (P8 probe: 1,500 sent, 1,000 queued, published() = 1500, nothing records the 500). Suggest restoring the dropped_ counter and the branch, marking try_push [[nodiscard]], and restoring the 1,200-tick test that expected 200 drops.
```

**Fix.**
```cpp
    void on_tick(const Tick& tick) { // network thread
        if (ring_.try_push(tick)) {
            published_.fetch_add(1, std::memory_order_relaxed);
        } else {
            dropped_.fetch_add(1, std::memory_order_relaxed); // the strategy resyncs from a snapshot when this moves
        }
    }
```

### D1 · Decoy · The relaxed loads of a thread's *own* index are correct

`tail_.load(relaxed)` in `try_push` (line 17) and `head_.load(relaxed)` in `try_pop` (29) read a value that only the calling thread writes. No ordering is needed, and the fix keeps them relaxed. A review that "fixes" every atomic to `seq_cst` hides which edges matter, and costs a full barrier per store on x86 (`xchg`). The bar is naming *which* load pairs with *which* store.

### N1 · Non-blocking · `size()` can underflow when read from a third thread

The PR's `size()` loads `tail` and then `head`, both relaxed. Between the two loads, the producer can push and the consumer can pop past the `tail` value already read, so `tail - head` wraps to about 4.29 billion and the depth gauge spikes. The fix loads `head` first with acquire, then `tail` with acquire: by coherence, the tail read is at least as new as the tail the consumer saw when it released that head.

```comment-l7
suggestion (non-blocking): size() loads tail before head, so a metrics thread can read a head that has passed the tail it already loaded and report ~4.29 billion

Load head_ (acquire) first, then tail_ (acquire); the result is a snapshot but never negative.
```

### T1 · Tests

The two-thread test is the author's evidence of thread safety. On the PR's code it is a data race, and it passes because x86 keeps stores in order. It also never reuses a slot. ThreadSanitizer models the C++ memory model rather than the CPU, so a TSan run of that test on x86 would flag F1. With slot reuse (more ticks than slots), it would flag F2 and F6 too.

```comment-l7
todo (blocking): the tests can't fail for any of the ordering, wrap, capacity, ABA or drop defects, and the one test that covered drops was cut from 1,200 ticks to 100

This means every defect in this review would reach the AArch64 rollout with a green build. Suggest: a TSan CI job running the two-thread test with more ticks than slots; an AArch64 runner for the stress tests; a ring seeded near 0xFFFFFFF8; the production TickRing filled to capacity; the POOL_SCHEDULE_POINT hook used for a pop-pop-push interleaving; and the 1,200-tick drop test restored.
```

---

## 7. The refactored code

```cpp
// ===== marketdata/handoff/include/feed.hpp =====
#pragma once
// feed.hpp - the feed handler (network thread, producer) and the strategy drain (consumer) around the tick ring.
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "spsc_ring.hpp"
#include "tick.hpp"

using TickRing = SpscRing<Tick, 1024>; // ~1 ms of ticks at the 1M/s peak; a power of two (see SpscRing)

class FeedHandler {
public:
    explicit FeedHandler(TickRing& ring) : ring_(ring) {}

    void on_tick(const Tick& tick) { // network thread
        if (ring_.try_push(tick)) {
            published_.fetch_add(1, std::memory_order_relaxed);
        } else {
            dropped_.fetch_add(1, std::memory_order_relaxed); // the strategy resyncs from a snapshot when this moves
        }
    }

    std::uint64_t published() const { return published_.load(std::memory_order_relaxed); }
    std::uint64_t dropped() const { return dropped_.load(std::memory_order_relaxed); }

private:
    TickRing& ring_;
    std::atomic<std::uint64_t> published_{0};
    std::atomic<std::uint64_t> dropped_{0};
};

// Strategy thread: drains everything queued and returns how many ticks it consumed.
inline std::size_t drain(TickRing& ring, std::vector<Tick>& out) {
    std::size_t n = 0;
    while (auto tick = ring.try_pop()) {
        out.push_back(*tick);
        ++n;
    }
    return n;
}

// ===== marketdata/handoff/include/snapshot_pool.hpp =====
#pragma once
// snapshot_pool.hpp - fixed pool of order-book snapshot buffers, shared by the strategy threads. The free list is a
// lock-free (Treiber) stack, so returning a buffer never waits on another strategy thread (MD-412).
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

#ifndef POOL_SCHEDULE_POINT
#define POOL_SCHEDULE_POINT() ((void)0) // tests may define it to interleave operations deterministically
#endif

struct Snapshot {
    std::atomic<std::uint32_t> next{0}; // free-list link (an index); read by acquire() while others may write it
    std::array<std::int64_t, 512> levels{};
};

template <std::size_t N>
class SnapshotPool {
    static constexpr std::uint32_t kNil = UINT32_MAX;
    static_assert(N < kNil, "indices must fit below the nil marker");
    static_assert(std::atomic<std::uint64_t>::is_always_lock_free, "the head must be one lock-free word");

public:
    SnapshotPool() {
        for (Snapshot& s : storage_) {
            release(&s);
        }
    }

    Snapshot* acquire() {
        std::uint64_t top = head_.load(std::memory_order_acquire);
        while (index(top) != kNil) {
            std::uint32_t next = storage_[index(top)].next.load(std::memory_order_relaxed);
            POOL_SCHEDULE_POINT();
            // The head carries a tag bumped by every push and pop: if the top was popped and pushed back since our
            // load (ABA), the tag differs and this compare-exchange fails instead of installing a stale next.
            if (head_.compare_exchange_weak(top, pack(next, tag(top) + 1), std::memory_order_acquire)) {
                return &storage_[index(top)];
            }
        }
        return nullptr; // exhausted
    }

    void release(Snapshot* s) {
        auto i = static_cast<std::uint32_t>(s - storage_.data());
        std::uint64_t top = head_.load(std::memory_order_relaxed);
        do {
            s->next.store(index(top), std::memory_order_relaxed);
        } while (!head_.compare_exchange_weak(top, pack(i, tag(top) + 1), std::memory_order_release,
                                              std::memory_order_relaxed));
    }

private:
    static std::uint64_t pack(std::uint32_t index, std::uint32_t tag) { return (std::uint64_t{tag} << 32) | index; }
    static std::uint32_t index(std::uint64_t word) { return static_cast<std::uint32_t>(word); }
    static std::uint32_t tag(std::uint64_t word) { return static_cast<std::uint32_t>(word >> 32); }

    std::array<Snapshot, N> storage_{};
    std::atomic<std::uint64_t> head_{pack(kNil, 0)};
};

// ===== marketdata/handoff/include/spsc_ring.hpp =====
#pragma once
// spsc_ring.hpp - the feed -> strategy hand-off: a lock-free single-producer/single-consumer ring (MD-412).
#include <array>
#include <atomic>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <optional>

// Two 64-byte lines: Intel's adjacent-line prefetcher pulls lines in 128-byte pairs, and Apple M-series lines are
// 128 bytes, so indices written by different cores must be at least this far apart.
inline constexpr std::size_t kFalseSharingRange = 128;

template <typename T, std::size_t N>
class SpscRing {
    static_assert(std::has_single_bit(N), "N must be a power of two: slots are selected with index & (N - 1)");
    static_assert(N <= (std::size_t{1} << 31), "indices are compared modulo 2^32");

public:
    // Sequence numbers continue across restarts (downstream dedup keys on them), so the ring starts at the last
    // committed sequence. Indices wrap modulo 2^32: compare them only through unsigned subtraction.
    explicit SpscRing(std::uint32_t first_seq = 0) : head_(first_seq), tail_(first_seq) {}

    [[nodiscard]] bool try_push(const T& value) { // producer thread only
        std::uint32_t t = tail_.load(std::memory_order_relaxed); // our own index
        std::uint32_t h = head_.load(std::memory_order_acquire); // pairs with pop(): the consumer is done with the slot
        if (t - h == N) {
            return false; // full
        }
        slots_[t & (N - 1)] = value;
        tail_.store(t + 1, std::memory_order_release); // publishes the slot write to the consumer
        return true;
    }

    // Zero-copy access for large T: read *front(), then pop() to hand the slot back to the producer.
    [[nodiscard]] const T* front() const { // consumer thread only
        std::uint32_t h = head_.load(std::memory_order_relaxed); // our own index
        std::uint32_t t = tail_.load(std::memory_order_acquire); // pairs with try_push(): the slot write is visible
        return t - h == 0 ? nullptr : &slots_[h & (N - 1)];
    }

    void pop() { // consumer thread only, after front() returned non-null and the caller is done with it
        head_.store(head_.load(std::memory_order_relaxed) + 1, std::memory_order_release);
    }

    [[nodiscard]] std::optional<T> try_pop() { // copies the element out before the slot is handed back
        const T* value = front();
        if (value == nullptr) {
            return std::nullopt;
        }
        std::optional<T> out(*value);
        pop();
        return out;
    }

    std::size_t size() const { // any thread; a snapshot while producer and consumer run, never negative
        std::uint32_t h = head_.load(std::memory_order_acquire);
        std::uint32_t t = tail_.load(std::memory_order_acquire);
        return t - h;
    }

private:
    alignas(kFalseSharingRange) std::atomic<std::uint32_t> head_; // written by the consumer only
    alignas(kFalseSharingRange) std::atomic<std::uint32_t> tail_; // written by the producer only
    alignas(kFalseSharingRange) std::array<T, N> slots_{};
};
```

**Fixed suite: 12/12 on GCC (output, verified; the Clang run is identical).**

```text
ok   pushes_and_pops_in_order
ok   full_ring_rejects_push
ok   resumes_from_checkpoint_sequence
ok   indices_wrap_at_2_to_the_32
ok   production_capacity_keeps_every_tick
ok   popped_tick_survives_slot_reuse
ok   indices_live_on_separate_cache_lines
ok   transfers_across_threads
ok   feed_handler_publishes_every_tick
ok   full_ring_drops_are_counted
ok   pool_hands_out_each_snapshot_once
ok   pool_survives_aba_interleaving
12 passed, 0 failed
```

**The PR's original tests against the fix (output, verified).** All pass. None of them encodes a defect, and none could detect one:

```text
ok   pushes_and_pops_in_order
ok   full_ring_rejects_push
ok   resumes_from_checkpoint_sequence
ok   transfers_across_threads
ok   feed_handler_publishes_every_tick
ok   pool_hands_out_each_snapshot_once
6 passed, 0 failed
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Slot publication | Relaxed tail store/load | Release store / acquire load on `tail_` |
| Slot hand-back | Relaxed head store/load | Release store / acquire load on `head_` |
| Own-index loads | Relaxed | Relaxed (D1: correct) |
| Index comparison | `h >= t` | `t - h` only (wrap-safe modulo 2³²) |
| Slot selection | `& (N - 1)` for any `N` | `static_assert(has_single_bit(N))`, `TickRing` = 1024 |
| Layout | 8 bytes for both indices | Each index and the slots on their own 128-byte block |
| Popped data | Pointer into a released slot | Copy-out `try_pop`; `front()`/`pop()` for zero-copy |
| Pool | Raw-pointer Treiber stack (ABA, racy `next`) | 64-bit head = index + version tag; atomic `next` |
| Full ring | Silent loss | `dropped()` counted, `[[nodiscard]] try_push` |
| `size()` | `tail - head`, can underflow | `head` then `tail`, both acquire |

---

## 8. Probe evidence

### 8.1 Behavior probes

**Against the PR's code (output, verified, GCC 16.2):**

```text
PR08 probes against the PR's hand-off (GCC)
P3 F3 ring seeded at sequence 4294967288; 16 ticks pushed across the 32-bit wrap: consumer received 0, size() = 16
P4 F4 SpscRing<Tick, 1024>: bytes outside the slot array = 8, alignof = 8 -> head_ and tail_ share one cache line (written by two cores)
P5 F5 thread 2 pops A, pops B and pushes A back inside thread 1's acquire(): thread 1 and thread 2 hold different snapshots: true; the next acquire() hands out B, which thread 2 still holds: true
P6 F6 consumer holds tick 0; producer pushes tick 8 (accepted: true); the consumer's tick now reads seq 8
P7 F7 TickRing capacity 1000 (power of two: false): 1000 pushed, 256 delivered in order, 256 distinct ticks delivered
P8 F8 1500 ticks, no consumer: published() = 1500, queued = 1000, lost with no counter = 500
```

**Against the PR's code (output, verified, Clang 21.1):**

```text
PR08 probes against the PR's hand-off (Clang)
P3 F3 ring seeded at sequence 4294967288; 16 ticks pushed across the 32-bit wrap: consumer received 0, size() = 16
P4 F4 SpscRing<Tick, 1024>: bytes outside the slot array = 8, alignof = 8 -> head_ and tail_ share one cache line (written by two cores)
P5 F5 thread 2 pops A, pops B and pushes A back inside thread 1's acquire(): thread 1 and thread 2 hold different snapshots: true; the next acquire() hands out B, which thread 2 still holds: true
P6 F6 consumer holds tick 0; producer pushes tick 8 (accepted: true); the consumer's tick now reads seq 8
P7 F7 TickRing capacity 1000 (power of two: false): 1000 pushed, 256 delivered in order, 256 distinct ticks delivered
P8 F8 1500 ticks, no consumer: published() = 1500, queued = 1000, lost with no counter = 500
```

**Against the fixed code (output, verified, GCC 16.2; Clang identical except the compiler name):**

```text
PR08 probes against the fixed hand-off (GCC)
P3 F3 ring seeded at sequence 4294967288; 16 ticks pushed across the 32-bit wrap: consumer received 16, size() = 0
P4 F4 SpscRing<Tick, 1024>: bytes outside the slot array = 256, alignof = 128 -> head_ and tail_ sit on separate 128-byte blocks
P5 F5 thread 2 pops A, pops B and pushes A back inside thread 1's acquire(): thread 1 and thread 2 hold different snapshots: true; the next acquire() hands out B, which thread 2 still holds: false
P6 F6 consumer holds tick 0; producer pushes tick 8 (accepted: true); the consumer's tick now reads seq 0
P7 F7 TickRing capacity 1024 (power of two: true): 1024 pushed, 1024 delivered in order, 1024 distinct ticks delivered
P8 F8 1500 ticks, no consumer: published() = 1024, queued = 1024, dropped() = 476
```

### 8.2 Generated code: the PR's ring on AArch64 and x86-64

Clang 21 `-O2`, generic `armv8-a` (acquire loads are `ldar`; with `-mcpu` of Armv8.3 or later, many compilers emit `ldapr` instead). Read the index accesses: offsets `#4` and `[x8]`/`[x10]` in the PR (indices after the 24,576-byte slot array), `#128` and `[x0]` in the fix (indices padded to the front).

**The PR (output, verified):**

```text
== aarch64-linux-gnu · ring_push ==
    add     x8, x0, #6, lsl #12
    ldr     w10, [x8, #4]
    ldr     w9, [x8]
    sub     w9, w10, w9
    cmp     w9, #1024
    b.eq    .LBB0_2
    and     x11, x10, #0x3ff
    mov     w12, #24
    ldr     q0, [x1]
    umaddl  x11, w11, w12, x0
    ldr     x12, [x1, #16]
    add     w10, w10, #1
    str     x12, [x11, #16]
    str     q0, [x11]
    str     w10, [x8, #4]
.LBB0_2:
    cmp     w9, #1024
    cset    w0, ne
    ret

== aarch64-linux-gnu · ring_pop ==
    add     x10, x0, #6, lsl #12
    ldr     w8, [x10]
    ldr     w9, [x10, #4]
    cmp     w8, w9
    b.hs    .LBB1_2
    and     x11, x8, #0x3ff
    mov     w12, #24
    umaddl  x11, w11, w12, x0
    add     w12, w8, #1
    str     w12, [x10]
    ldr     x10, [x11, #16]
    ldr     q0, [x11]
    str     x10, [x1, #16]
    str     q0, [x1]
.LBB1_2:
    cmp     w8, w9
    cset    w0, lo
    ret

== x86_64-linux-gnu · ring_push ==
    mov     eax, dword ptr [rdi + 24580]
    mov     edx, dword ptr [rdi + 24576]
    mov     ecx, eax
    sub     ecx, edx
    cmp     ecx, 1024
    je      .LBB0_2
    mov     edx, eax
    and     edx, 1023
    lea     rdx, [rdx + 2*rdx]
    mov     r8, qword ptr [rsi + 16]
    mov     qword ptr [rdi + 8*rdx + 16], r8
    movups  xmm0, xmmword ptr [rsi]
    movups  xmmword ptr [rdi + 8*rdx], xmm0
    add     eax, 1
    mov     dword ptr [rdi + 24580], eax
.LBB0_2:
    cmp     ecx, 1024
    setne   al
    ret

== x86_64-linux-gnu · ring_pop ==
    mov     eax, dword ptr [rdi + 24576]
    mov     ecx, dword ptr [rdi + 24580]
    cmp     eax, ecx
    jae     .LBB1_2
    mov     edx, eax
    and     edx, 1023
    lea     rdx, [rdx + 2*rdx]
    lea     r8d, [rax + 1]
    mov     dword ptr [rdi + 24576], r8d
    mov     r8, qword ptr [rdi + 8*rdx + 16]
    mov     qword ptr [rsi + 16], r8
    movups  xmm0, xmmword ptr [rdi + 8*rdx]
    movups  xmmword ptr [rsi], xmm0
.LBB1_2:
    cmp     eax, ecx
    setb    al
    ret
```

**The fix (output, verified):**

```text
== aarch64-linux-gnu · ring_push ==
    ldr     w9, [x0, #128]
    ldar    w8, [x0]
    sub     w8, w9, w8
    cmp     w8, #1024
    b.eq    .LBB0_2
    mov     w10, #24
    and     x11, x9, #0x3ff
    ldr     q0, [x1]
    umaddl  x10, w11, w10, x0
    ldr     x11, [x1, #16]
    add     w9, w9, #1
    str     x11, [x10, #272]
    add     x11, x0, #128
    str     q0, [x10, #256]
    stlr    w9, [x11]
.LBB0_2:
    cmp     w8, #1024
    cset    w0, ne
    ret

== aarch64-linux-gnu · ring_pop ==
    add     x9, x0, #128
    ldr     w8, [x0]
    ldar    w9, [x9]
    cmp     w9, w8
    b.eq    .LBB1_2
    sub     sp, sp, #32
    mov     w10, #24
    and     x11, x8, #0x3ff
    umaddl  x10, w11, w10, x0
    add     x11, x10, #256
    ldr     x12, [x10, #272]
    ldrb    w10, [x10, #256]
    ldur    q0, [x11, #1]
    stur    x12, [sp, #15]
    str     q0, [sp]
    ldr     w11, [x0]
    add     w11, w11, #1
    stlr    w11, [x0]
    ldr     q0, [sp]
    strb    w10, [x1]
    ldur    x10, [sp, #15]
    stur    q0, [x1, #1]
    str     x10, [x1, #16]
    add     sp, sp, #32
.LBB1_2:
    cmp     w9, w8
    cset    w0, ne
    ret

== x86_64-linux-gnu · ring_push ==
    mov     eax, dword ptr [rdi + 128]
    mov     edx, dword ptr [rdi]
    mov     ecx, eax
    sub     ecx, edx
    cmp     ecx, 1024
    je      .LBB0_2
    mov     edx, eax
    and     edx, 1023
    lea     rdx, [rdx + 2*rdx]
    mov     r8, qword ptr [rsi + 16]
    mov     qword ptr [rdi + 8*rdx + 272], r8
    movups  xmm0, xmmword ptr [rsi]
    movups  xmmword ptr [rdi + 8*rdx + 256], xmm0
    add     eax, 1
    mov     dword ptr [rdi + 128], eax
.LBB0_2:
    cmp     ecx, 1024
    setne   al
    ret

== x86_64-linux-gnu · ring_pop ==
    mov     eax, dword ptr [rdi]
    mov     ecx, dword ptr [rdi + 128]
    cmp     ecx, eax
    je      .LBB1_2
    mov     edx, eax
    and     edx, 1023
    lea     rdx, [rdx + 2*rdx]
    movzx   r8d, byte ptr [rdi + 8*rdx + 256]
    mov     r9, qword ptr [rdi + 8*rdx + 272]
    mov     qword ptr [rsp - 9], r9
    movups  xmm0, xmmword ptr [rdi + 8*rdx + 257]
    movaps  xmmword ptr [rsp - 24], xmm0
    add     dword ptr [rdi], 1
    mov     byte ptr [rsi], r8b
    movaps  xmm0, xmmword ptr [rsp - 24]
    movups  xmmword ptr [rsi + 1], xmm0
    mov     rdx, qword ptr [rsp - 9]
    mov     qword ptr [rsi + 16], rdx
.LBB1_2:
    cmp     ecx, eax
    setne   al
    ret
```

What to read from these listings:

| Access | PR · AArch64 | Fix · AArch64 | PR and fix · x86-64 |
|---|---|---|---|
| Producer publishes tail | `str w10, [x8, #4]` | `stlr w9, [x11]` | `mov dword ptr [...], eax` (same instruction in both) |
| Producer reads head | `ldr w9, [x8]` | `ldar w8, [x0]` | `mov edx, dword ptr [...]` |
| Consumer reads tail | `ldr w9, [x10, #4]` | `ldar w9, [x9]` | `mov ecx, dword ptr [...]` |
| Consumer releases head | `str w12, [x10]`, **before** the slot loads (F6) | `stlr w11, [x0]`, after the slot loads | PR: store before slot loads; fix: after |

<details><summary><b>The probe harness (probes.cpp and asm_probe.cpp)</b></summary>

```cpp
// asm_probe.cpp - the ring's two hot paths as extern "C" functions, so the generated code can be read per target.
// tools/pr.py compiles this file with Clang 21 at -O2 for aarch64-linux-gnu and x86_64-linux-gnu.
#include "spsc_ring.hpp"
#include "tick.hpp"

extern "C" bool ring_push(SpscRing<Tick, 1024>& ring, const Tick& tick) { return ring.try_push(tick); }

extern "C" bool ring_pop(SpscRing<Tick, 1024>& ring, Tick& out) {
    auto tick = ring.try_pop();
    if (!tick) {
        return false;
    }
    out = *tick;
    return true;
}
// probes.cpp - wrap, layout, ABA, slot-reuse, capacity and drop probes for PR08. Single-threaded and inside defined
// behavior: the ABA interleaving runs "thread 2" at the pool's schedule point, between thread 1's read of the top
// node's link and its compare-exchange. The memory-order defects (F1, F2) are shown in the generated code instead
// (asm_probe.cpp).
#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <print>
#include <set>
#include <utility>

void probe_schedule_point();
#define POOL_SCHEDULE_POINT() probe_schedule_point()

#include "feed.hpp"
#include "snapshot_pool.hpp"

namespace {

Tick tick(std::uint32_t seq) { return Tick{seq, 7, 1'012'500, 300}; }

template <typename>
struct Capacity;
template <typename T, std::size_t N>
struct Capacity<SpscRing<T, N>> {
    static constexpr std::size_t value = N;
};

void (*g_interleave)() = nullptr; // runs once at the next schedule point: thread 2's operations
SnapshotPool<4>* g_pool = nullptr;
Snapshot* g_thread2_holds = nullptr;

} // namespace

void probe_schedule_point() {
    if (void (*f)() = std::exchange(g_interleave, nullptr)) {
        f();
    }
}

namespace {

void sequence_wrap() {
    constexpr std::uint32_t kFirst = 0xFFFF'FFF8u; // 8 ticks before the 32-bit sequence wraps
    static SpscRing<Tick, 1024> ring(kFirst);
    for (std::uint32_t i = 0; i < 16; ++i) {
        (void)ring.try_push(tick(kFirst + i));
    }
    int received = 0;
    while (received < 16 && ring.try_pop()) {
        ++received;
    }
    std::println("P3 F3 ring seeded at sequence {}; 16 ticks pushed across the 32-bit wrap: consumer received {},"
                 " size() = {}", kFirst, received, ring.size());
}

void index_layout() {
    using Ring = SpscRing<Tick, 1024>;
    std::size_t outside = sizeof(Ring) - sizeof(std::array<Tick, 1024>);
    std::println("P4 F4 SpscRing<Tick, 1024>: bytes outside the slot array = {}, alignof = {} -> head_ and tail_ {}",
                 outside, alignof(Ring),
                 outside < 64 ? "share one cache line (written by two cores)" : "sit on separate 128-byte blocks");
}

void aba() {
    static SnapshotPool<4> pool;
    g_pool = &pool;
    g_interleave = [] {
        Snapshot* a = g_pool->acquire();     // pops A, the top thread 1 has already read
        g_thread2_holds = g_pool->acquire(); // pops B, thread 1's saved `next`, and keeps it
        g_pool->release(a);                  // pushes A back: the head is the same address thread 1 read
    };
    Snapshot* thread1 = pool.acquire();
    Snapshot* next_request = pool.acquire();
    std::println("P5 F5 thread 2 pops A, pops B and pushes A back inside thread 1's acquire(): thread 1 and thread 2"
                 " hold different snapshots: {}; the next acquire() hands out B, which thread 2 still holds: {}",
                 thread1 != g_thread2_holds, next_request == g_thread2_holds);
}

void slot_reuse() {
    SpscRing<Tick, 8> ring;
    for (std::uint32_t i = 0; i < 8; ++i) {
        (void)ring.try_push(tick(i));
    }
    auto held = ring.try_pop(); // the consumer starts processing tick 0
    std::uint32_t seen = held->seq;
    bool accepted = ring.try_push(tick(8)); // the producer reuses the slot the consumer was given
    std::println("P6 F6 consumer holds tick {}; producer pushes tick 8 (accepted: {}); the consumer's tick now reads"
                 " seq {}", seen, accepted, held->seq);
}

void production_capacity() {
    static TickRing ring;
    constexpr auto n = static_cast<std::uint32_t>(Capacity<TickRing>::value);
    std::uint32_t accepted = 0;
    for (std::uint32_t i = 0; i < n; ++i) {
        accepted += ring.try_push(tick(i)) ? 1u : 0u;
    }
    std::uint32_t in_order = 0;
    std::set<std::uint32_t> distinct;
    for (std::uint32_t i = 0; i < n; ++i) {
        if (auto t = ring.try_pop()) {
            in_order += t->seq == i ? 1u : 0u;
            distinct.insert(t->seq);
        }
    }
    std::println("P7 F7 TickRing capacity {} (power of two: {}): {} pushed, {} delivered in order, {} distinct ticks"
                 " delivered", n, std::has_single_bit(n), accepted, in_order, distinct.size());
}

template <typename Feed>
void report_drops(const Feed& feed, const TickRing& ring) {
    if constexpr (requires { feed.dropped(); }) {
        std::println("P8 F8 1500 ticks, no consumer: published() = {}, queued = {}, dropped() = {}", feed.published(),
                     ring.size(), feed.dropped());
    } else {
        std::println("P8 F8 1500 ticks, no consumer: published() = {}, queued = {}, lost with no counter = {}",
                     feed.published(), ring.size(), std::size_t{1500} - ring.size());
    }
}

void silent_drops() {
    static TickRing ring;
    FeedHandler feed(ring);
    for (std::uint32_t i = 0; i < 1500; ++i) {
        feed.on_tick(tick(i));
    }
    report_drops(feed, ring);
}

} // namespace

int main(int argc, char** argv) {
    std::println("PR08 probes against the {} hand-off ({})", argc > 1 ? argv[1] : "?",
#if defined(__clang__)
                 "Clang"
#else
                 "GCC"
#endif
    );
    sequence_wrap();
    index_layout();
    aba();
    slot_reuse();
    production_capacity();
    silent_drops();
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/marketdata/handoff/include/feed.hpp b/marketdata/handoff/include/feed.hpp
index c4474b1..3a53da4 100644
--- a/marketdata/handoff/include/feed.hpp
+++ b/marketdata/handoff/include/feed.hpp
@@ -8,22 +8,27 @@
 #include "spsc_ring.hpp"
 #include "tick.hpp"
 
-using TickRing = SpscRing<Tick, 1000>; // ~1 ms of ticks at the 1M/s peak
+using TickRing = SpscRing<Tick, 1024>; // ~1 ms of ticks at the 1M/s peak; a power of two (see SpscRing)
 
 class FeedHandler {
 public:
     explicit FeedHandler(TickRing& ring) : ring_(ring) {}
 
     void on_tick(const Tick& tick) { // network thread
-        ring_.try_push(tick); // lock-free: never blocks the network thread
-        published_.fetch_add(1, std::memory_order_relaxed);
+        if (ring_.try_push(tick)) {
+            published_.fetch_add(1, std::memory_order_relaxed);
+        } else {
+            dropped_.fetch_add(1, std::memory_order_relaxed); // the strategy resyncs from a snapshot when this moves
+        }
     }
 
     std::uint64_t published() const { return published_.load(std::memory_order_relaxed); }
+    std::uint64_t dropped() const { return dropped_.load(std::memory_order_relaxed); }
 
 private:
     TickRing& ring_;
     std::atomic<std::uint64_t> published_{0};
+    std::atomic<std::uint64_t> dropped_{0};
 };
 
 // Strategy thread: drains everything queued and returns how many ticks it consumed.
diff --git a/marketdata/handoff/include/snapshot_pool.hpp b/marketdata/handoff/include/snapshot_pool.hpp
index cc753ae..eec40ef 100644
--- a/marketdata/handoff/include/snapshot_pool.hpp
+++ b/marketdata/handoff/include/snapshot_pool.hpp
@@ -11,12 +11,16 @@
 #endif
 
 struct Snapshot {
-    Snapshot* next = nullptr; // free-list link, meaningful only while the snapshot is free
+    std::atomic<std::uint32_t> next{0}; // free-list link (an index); read by acquire() while others may write it
     std::array<std::int64_t, 512> levels{};
 };
 
 template <std::size_t N>
 class SnapshotPool {
+    static constexpr std::uint32_t kNil = UINT32_MAX;
+    static_assert(N < kNil, "indices must fit below the nil marker");
+    static_assert(std::atomic<std::uint64_t>::is_always_lock_free, "the head must be one lock-free word");
+
 public:
     SnapshotPool() {
         for (Snapshot& s : storage_) {
@@ -25,24 +29,33 @@ public:
     }
 
     Snapshot* acquire() {
-        Snapshot* top = head_.load(std::memory_order_acquire);
-        while (top != nullptr) {
-            Snapshot* next = top->next;
+        std::uint64_t top = head_.load(std::memory_order_acquire);
+        while (index(top) != kNil) {
+            std::uint32_t next = storage_[index(top)].next.load(std::memory_order_relaxed);
             POOL_SCHEDULE_POINT();
-            if (head_.compare_exchange_weak(top, next, std::memory_order_acquire)) {
-                return top;
+            // The head carries a tag bumped by every push and pop: if the top was popped and pushed back since our
+            // load (ABA), the tag differs and this compare-exchange fails instead of installing a stale next.
+            if (head_.compare_exchange_weak(top, pack(next, tag(top) + 1), std::memory_order_acquire)) {
+                return &storage_[index(top)];
             }
         }
         return nullptr; // exhausted
     }
 
     void release(Snapshot* s) {
-        s->next = head_.load(std::memory_order_relaxed);
-        while (!head_.compare_exchange_weak(s->next, s, std::memory_order_release, std::memory_order_relaxed)) {
-        }
+        auto i = static_cast<std::uint32_t>(s - storage_.data());
+        std::uint64_t top = head_.load(std::memory_order_relaxed);
+        do {
+            s->next.store(index(top), std::memory_order_relaxed);
+        } while (!head_.compare_exchange_weak(top, pack(i, tag(top) + 1), std::memory_order_release,
+                                              std::memory_order_relaxed));
     }
 
 private:
+    static std::uint64_t pack(std::uint32_t index, std::uint32_t tag) { return (std::uint64_t{tag} << 32) | index; }
+    static std::uint32_t index(std::uint64_t word) { return static_cast<std::uint32_t>(word); }
+    static std::uint32_t tag(std::uint64_t word) { return static_cast<std::uint32_t>(word >> 32); }
+
     std::array<Snapshot, N> storage_{};
-    std::atomic<Snapshot*> head_{nullptr};
+    std::atomic<std::uint64_t> head_{pack(kNil, 0)};
 };
diff --git a/marketdata/handoff/include/spsc_ring.hpp b/marketdata/handoff/include/spsc_ring.hpp
index 18b756d..476c0b3 100644
--- a/marketdata/handoff/include/spsc_ring.hpp
+++ b/marketdata/handoff/include/spsc_ring.hpp
@@ -2,44 +2,65 @@
 // spsc_ring.hpp - the feed -> strategy hand-off: a lock-free single-producer/single-consumer ring (MD-412).
 #include <array>
 #include <atomic>
+#include <bit>
 #include <cstddef>
 #include <cstdint>
+#include <optional>
+
+// Two 64-byte lines: Intel's adjacent-line prefetcher pulls lines in 128-byte pairs, and Apple M-series lines are
+// 128 bytes, so indices written by different cores must be at least this far apart.
+inline constexpr std::size_t kFalseSharingRange = 128;
 
 template <typename T, std::size_t N>
 class SpscRing {
+    static_assert(std::has_single_bit(N), "N must be a power of two: slots are selected with index & (N - 1)");
+    static_assert(N <= (std::size_t{1} << 31), "indices are compared modulo 2^32");
+
 public:
     // Sequence numbers continue across restarts (downstream dedup keys on them), so the ring starts at the last
-    // committed sequence.
+    // committed sequence. Indices wrap modulo 2^32: compare them only through unsigned subtraction.
     explicit SpscRing(std::uint32_t first_seq = 0) : head_(first_seq), tail_(first_seq) {}
 
-    // Each index has exactly one writer, so relaxed loads and stores are enough: no fences, no read-modify-writes.
-    bool try_push(const T& value) { // producer thread only
-        std::uint32_t t = tail_.load(std::memory_order_relaxed);
-        std::uint32_t h = head_.load(std::memory_order_relaxed);
+    [[nodiscard]] bool try_push(const T& value) { // producer thread only
+        std::uint32_t t = tail_.load(std::memory_order_relaxed); // our own index
+        std::uint32_t h = head_.load(std::memory_order_acquire); // pairs with pop(): the consumer is done with the slot
         if (t - h == N) {
             return false; // full
         }
-        slots_[t & (N - 1)] = value; // mask instead of %: no division on the hot path
-        tail_.store(t + 1, std::memory_order_relaxed);
+        slots_[t & (N - 1)] = value;
+        tail_.store(t + 1, std::memory_order_release); // publishes the slot write to the consumer
         return true;
     }
 
-    // Zero-copy: hands out a pointer into the ring instead of copying the tick.
-    const T* try_pop() { // consumer thread only
-        std::uint32_t h = head_.load(std::memory_order_relaxed);
-        std::uint32_t t = tail_.load(std::memory_order_relaxed);
-        if (h >= t) {
-            return nullptr; // empty
+    // Zero-copy access for large T: read *front(), then pop() to hand the slot back to the producer.
+    [[nodiscard]] const T* front() const { // consumer thread only
+        std::uint32_t h = head_.load(std::memory_order_relaxed); // our own index
+        std::uint32_t t = tail_.load(std::memory_order_acquire); // pairs with try_push(): the slot write is visible
+        return t - h == 0 ? nullptr : &slots_[h & (N - 1)];
+    }
+
+    void pop() { // consumer thread only, after front() returned non-null and the caller is done with it
+        head_.store(head_.load(std::memory_order_relaxed) + 1, std::memory_order_release);
+    }
+
+    [[nodiscard]] std::optional<T> try_pop() { // copies the element out before the slot is handed back
+        const T* value = front();
+        if (value == nullptr) {
+            return std::nullopt;
         }
-        const T* value = &slots_[h & (N - 1)];
-        head_.store(h + 1, std::memory_order_relaxed);
-        return value;
+        std::optional<T> out(*value);
+        pop();
+        return out;
     }
 
-    std::size_t size() const { return tail_.load(std::memory_order_relaxed) - head_.load(std::memory_order_relaxed); }
+    std::size_t size() const { // any thread; a snapshot while producer and consumer run, never negative
+        std::uint32_t h = head_.load(std::memory_order_acquire);
+        std::uint32_t t = tail_.load(std::memory_order_acquire);
+        return t - h;
+    }
 
 private:
-    std::array<T, N> slots_{};
-    std::atomic<std::uint32_t> head_; // written by the consumer only
-    std::atomic<std::uint32_t> tail_; // written by the producer only
+    alignas(kFalseSharingRange) std::atomic<std::uint32_t> head_; // written by the consumer only
+    alignas(kFalseSharingRange) std::atomic<std::uint32_t> tail_; // written by the producer only
+    alignas(kFalseSharingRange) std::array<T, N> slots_{};
 };
diff --git a/marketdata/handoff/test/handoff_test.cpp b/marketdata/handoff/test/handoff_test.cpp
index 70064e4..96c3931 100644
--- a/marketdata/handoff/test/handoff_test.cpp
+++ b/marketdata/handoff/test/handoff_test.cpp
@@ -1,16 +1,30 @@
 // handoff_test.cpp - unit tests for the lock-free tick ring, the feed handler and the snapshot pool.
 #include <algorithm>
 #include <thread>
+#include <utility>
 #include <vector>
 
+void test_schedule_point();
+#define POOL_SCHEDULE_POINT() test_schedule_point()
+
 #include "check.hpp"
 #include "feed.hpp"
 #include "snapshot_pool.hpp"
 
 namespace {
 Tick tick(std::uint32_t seq) { return Tick{seq, 7, 1'012'500, 300}; }
+
+void (*g_interleave)() = nullptr; // runs once at the next schedule point: another thread's operations
+SnapshotPool<4>* g_pool = nullptr;
+Snapshot* g_other_thread_holds = nullptr;
 } // namespace
 
+void test_schedule_point() {
+    if (void (*f)() = std::exchange(g_interleave, nullptr)) {
+        f();
+    }
+}
+
 TEST(pushes_and_pops_in_order) {
     SpscRing<Tick, 8> ring;
     for (std::uint32_t i = 0; i < 5; ++i) {
@@ -40,6 +54,46 @@ TEST(resumes_from_checkpoint_sequence) {
     CHECK(t && t->seq == 5'000'000);
 }
 
+TEST(indices_wrap_at_2_to_the_32) {
+    SpscRing<Tick, 1024> ring(0xFFFF'FFF8u);
+    for (std::uint32_t i = 0; i < 16; ++i) {
+        CHECK(ring.try_push(tick(0xFFFF'FFF8u + i)));
+    }
+    for (std::uint32_t i = 0; i < 16; ++i) {
+        auto t = ring.try_pop();
+        CHECK(t && t->seq == 0xFFFF'FFF8u + i);
+    }
+    CHECK(ring.size() == 0);
+}
+
+TEST(production_capacity_keeps_every_tick) {
+    static TickRing ring;
+    for (std::uint32_t i = 0; i < 1024; ++i) {
+        CHECK(ring.try_push(tick(i)));
+    }
+    bool ordered = true;
+    for (std::uint32_t i = 0; i < 1024; ++i) {
+        auto t = ring.try_pop();
+        ordered = ordered && t && t->seq == i;
+    }
+    CHECK(ordered);
+}
+
+TEST(popped_tick_survives_slot_reuse) {
+    SpscRing<Tick, 8> ring;
+    for (std::uint32_t i = 0; i < 8; ++i) {
+        CHECK(ring.try_push(tick(i)));
+    }
+    auto held = ring.try_pop();
+    CHECK(ring.try_push(tick(8))); // reuses the slot `held` came from
+    CHECK(held && held->seq == 0);
+}
+
+TEST(indices_live_on_separate_cache_lines) {
+    CHECK(sizeof(SpscRing<Tick, 1024>) - sizeof(std::array<Tick, 1024>) >= 2 * kFalseSharingRange);
+    CHECK(alignof(SpscRing<Tick, 1024>) >= kFalseSharingRange);
+}
+
 TEST(transfers_across_threads) {
     SpscRing<Tick, 1024> ring;
     constexpr std::uint32_t kTicks = 1000;
@@ -62,7 +116,7 @@ TEST(transfers_across_threads) {
 }
 
 TEST(feed_handler_publishes_every_tick) {
-    TickRing ring;
+    static TickRing ring;
     FeedHandler feed(ring);
     for (std::uint32_t i = 0; i < 100; ++i) {
         feed.on_tick(tick(i));
@@ -72,6 +126,16 @@ TEST(feed_handler_publishes_every_tick) {
     CHECK(feed.published() == 100);
 }
 
+TEST(full_ring_drops_are_counted) {
+    static TickRing ring;
+    FeedHandler feed(ring);
+    for (std::uint32_t i = 0; i < 1500; ++i) {
+        feed.on_tick(tick(i));
+    }
+    CHECK(feed.published() == 1024);
+    CHECK(feed.dropped() == 476);
+}
+
 TEST(pool_hands_out_each_snapshot_once) {
     SnapshotPool<4> pool;
     std::vector<Snapshot*> got;
@@ -85,4 +149,19 @@ TEST(pool_hands_out_each_snapshot_once) {
     CHECK(pool.acquire() == got[0]);
 }
 
+TEST(pool_survives_aba_interleaving) {
+    static SnapshotPool<4> pool;
+    g_pool = &pool;
+    g_interleave = [] { // between our read of top->next and our compare-exchange: pop A, pop B, push A
+        Snapshot* a = g_pool->acquire();
+        g_other_thread_holds = g_pool->acquire();
+        g_pool->release(a);
+    };
+    Snapshot* mine = pool.acquire();
+    Snapshot* next = pool.acquire();
+    CHECK(mine != g_other_thread_holds);
+    CHECK(next != g_other_thread_holds);
+    CHECK(next != mine);
+}
+
 int main() { return run_all(); }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F1 | Relaxed tail publication | Sev-1 (5) | 10 | L6+ |
| F2 | Relaxed head hand-back | Sev-1 (5) | 20 | L7 (the reverse direction of the protocol) |
| F3 | `h >= t` across the wrap | Sev-1 (5) | 10 | L6+ |
| F5 | ABA in the Treiber stack | Sev-1 (5) | 20 | L6+ names it; L7 proves it with the hook |
| F6 | Pointer into a released slot | Sev-1 (5) | 2 | L5+ |
| F7 | Mask with `N = 1000` (outside the diff) | Sev-1 (5) | 10 | L7 (reads beyond the hunks) |
| F4 | False sharing of the indices | Sev-2 (3) | 2 | L6+ |
| F8 | Silent drops, counter deleted | Sev-2 (3) | 2 | L5+ |

Total **36**. L5s find F6 and F8. L6s add F1, F3, F4 and name ABA. L7s add F2 (the reverse hand-off), find F7 by opening `feed.hpp`, prove F5 with the hook the author added, and leave D1 relaxed.

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| "Make everything `seq_cst`" | Correct, and slower on x86 | Hides which edges matter; `xchg` per store on the hot path |
| Fixing F1 only | Release on tail, relaxed head | Slot reuse (F2) is still unordered |
| `std::atomic_thread_fence(seq_cst)` sprinkled in | Works on some hardware | Unreasoned fences are unreviewable; pair loads and stores explicitly |
| "Use `uint64_t` indices" for F3 | Wrap in 584,000 years at 1M/s | Hides the comparison bug; the persisted sequence is still 32-bit |
| "Use a mutex-free DWCAS (`cmpxchg16b`)" for F5 | Pointer + counter | Not portable across targets; the index+tag word is lock-free everywhere |
| Accepting "tests pass on two threads" | Approves | x86 TSO, no slot reuse, and a racy test |
| Reviewing only the diff | Misses F7 | The capacity is on an unchanged line |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Each index has exactly one writer. Why isn't relaxed enough?"</b></summary>

**Initial Prompt.** The author's own justification.

**L5 Answer.** "Relaxed might be reordered, so use seq_cst to be safe."

**Why L5 Stalls.** Right direction, no mechanism, and the wrong fix.

**L7 Answer.** "Single-writer means no read-modify-write is needed: the index never races with another writer. But the index isn't the payload. The tail store has to *carry* the slot write with it, and that's what release does, with the matching acquire load on the other side. Relaxed guarantees only the index's own atomicity, so the slot accesses become a data race. The same reasoning runs in reverse for the head: the consumer's reads must be done before the producer reuses the slot. So it's two release/acquire pairs, and the own-index loads stay relaxed."

</details>

<details><summary><b>Q2 · "The two-thread test passed 1,000 out of 1,000. Why doesn't that count?"</b></summary>

**Initial Prompt.** Evidence quality for concurrency.

**L5 Answer.** "Run it a million times."

**Why L5 Stalls.** A million runs on x86 still won't show it, because x86-TSO keeps stores in order and the compilers emitted them in order.

**L7 Answer.** "Three reasons. One: x86 doesn't reorder stores with stores or loads with loads. The listings show identical `mov`s for relaxed and release, so the test can't distinguish them. Two: 1,000 ticks through 1,024 slots never reuses a slot, so F2 and F6 can't fire. Three: on the PR's code the test is itself a data race, so 'passes' means 'UB that happened to work.' Better evidence: TSan on x86, which models the C++ memory model and flags the race regardless of hardware. Then stress tests on an AArch64 runner, plus a model checker (Relacy, CDSChecker) for the protocol itself."

</details>

<details><summary><b>Q3 · "Why not `seq_cst` everywhere and stop thinking about it?"</b></summary>

**Initial Prompt.** Cost and clarity of memory orders.

**L5 Answer.** "Because seq_cst is slow."

**Why L5 Stalls.** Half the answer. On AArch64 a seq_cst store is also `stlr`; the cost is mostly on x86.

**L7 Answer.** "Cost: on x86 a seq_cst store becomes `xchg`, a full barrier on every push and pop, which is the latency the PR exists to remove. On AArch64 acquire/release and seq_cst loads and stores are close, but seq_cst forbids the cheaper `ldapr`. Clarity matters more: an explicit pair (release on tail ↔ acquire on tail) documents the protocol, and a reviewer can check each edge. seq_cst everywhere says 'I don't know which edges matter.' SPSC needs no total order, only the two hand-offs."

</details>

<details><summary><b>Q4 · "What are the alternatives to a version tag for ABA?"</b></summary>

**Initial Prompt.** Lock-free memory reclamation.

**L5 Answer.** "Use a mutex."

**Why L5 Stalls.** Valid, but it doesn't engage with the design space.

**L7 Answer.** "A version tag in the CAS word (here: 32-bit index + 32-bit tag in one lock-free `uint64_t`; a thread would have to stall for exactly 2³² operations to alias). Double-width CAS on pointer + counter (`cmpxchg16b`, Armv8.1 `casp`), which is less portable. Hazard pointers or epoch-based reclamation, which prevent a node from being reused while any thread holds it. Those are needed when nodes are freed, not pooled. Or avoid the shared stack: per-thread free lists with batch transfer. LL/SC hardware doesn't save you, because C++ `compare_exchange` compares *values*, so ABA exists at the language level on every target. For a fixed pool of 64 buffers, the tagged index is the smallest correct change."

</details>

<details><summary><b>Q5 · "F7 never crashes. Why Sev-1?"</b></summary>

**Initial Prompt.** Severity of silent corruption.

**L5 Answer.** "Because data is lost."

**Why L5 Stalls.** True, but doesn't size it.

**L7 Answer.** "Because three quarters of the ticks are replaced by duplicates of others whenever the ring is full: 256 distinct of 1,000 in P7. The strategy doesn't see a gap (sequence numbers are present, just repeated), so it doesn't resync. It trades on a book that is wrong in a way no alert detects. A crash would page someone in seconds, while this loses money until someone reconciles fills. Silent wrong answers rank above loud failures."

</details>

<details><summary><b>Q6 · "How would you show F4 matters, and why 128 rather than 64?"</b></summary>

**Initial Prompt.** Performance evidence and portability.

**L5 Answer.** "Benchmark it."

**Why L5 Stalls.** Which benchmark, on what, and what would count as proof?

**L7 Answer.** "Structural evidence first: 8 bytes for both indices means one line. Then measure on the target hardware: a pinned producer/consumer pair on two physical cores, comparing ns per operation for packed vs padded. `perf c2c` on Linux attributes HITM (hit-modified) events to the exact cache line. I haven't measured it here, so I wouldn't quote a number. 128, because Apple M-series lines are 128 bytes and Intel's adjacent-line prefetcher pulls 64-byte lines in pairs. Use a named constant, not `std::hardware_destructive_interference_size`: GCC warns that its value varies with `-mtune`/`-mcpu`, which would make the class layout an ABI hazard in a header."

</details>

<details><summary><b>Q7 · "Should a full ring drop, block, or grow?"</b></summary>

**Initial Prompt.** Backpressure policy for market data.

**L5 Answer.** "Block the producer."

**Why L5 Stalls.** The producer is the network thread, and the exchange won't slow down for us. Blocking moves the loss into the kernel's socket buffer, where it's invisible.

**L7 Answer.** "Drop, *counted and surfaced*: the strategy treats any drop as a sequence gap and resyncs from a snapshot, which is how exchange feeds are designed to recover. Never grow on the hot path, because allocation breaks the latency budget. Never drop silently. So: `[[nodiscard]] try_push`, a `dropped()` counter, an alert on its rate, and a ring sized from measured burst depth, not '~1 ms'. And a test that overfills it."

</details>

<details><summary><b>Q8 · "Rank the findings and name the CI that would have caught them."</b></summary>

**Initial Prompt.** Prioritization and guardrails.

**L5 Answer.** "F6 first, it's the most obvious."

**Why L5 Stalls.** Obvious isn't the same as most damaging.

**L7 Answer.** "F7 (fires on every full ring on every CPU, today), F3 (a guaranteed stall at the wrap), F6 (fires whenever the producer laps), F5 (two threads write one buffer), then F1 and F2 (latent on x86, live on the AArch64 migration next quarter). Then F8, which makes F3 and F7 silent, then F4. CI: a TSan job (F1, F2, F6 as races), an AArch64 runner for stress tests, `static_assert(has_single_bit(N))` (F7 at compile time), a wrap test seeded at 0xFFFFFFF8 (F3), schedule-point interleaving tests using the hook (F5), and an overfill test asserting `dropped()` (F8)."

</details>

---

## 12. Checklist

- [ ] For every atomic: who writes it, who reads it, and what data does it publish? Pair each release with its acquire.
- [ ] Own-index loads relaxed; other-side loads acquire; publishing stores release.
- [ ] Modular indices: subtraction only, never `<`/`>=`; a test seeded near the wrap.
- [ ] `& (N - 1)`: a `static_assert` that `N` is a power of two, and grep the instantiations outside the diff.
- [ ] Never hand a slot back before the consumer is done reading it.
- [ ] CAS on pointers: what if the value was popped and pushed back? Tag, hazard pointers, or epochs.
- [ ] Indices written by different cores: padded to 128 bytes via a named constant.
- [ ] Every rejected push counted and surfaced.
- [ ] Tests: TSan on x86, an AArch64 runner, interleavings through schedule points.

---

## 13. References

- cppreference: `std::memory_order` (relaxed, release-acquire, and the hardware notes on x86 vs ARM). https://en.cppreference.com/w/cpp/atomic/memory_order
- LLVM: Atomic Instructions and Concurrency Guide (code generation notes for Acquire/Release on weakly ordered targets). https://llvm.org/docs/Atomics.html
- cppreference: `std::hardware_destructive_interference_size`. https://en.cppreference.com/w/cpp/thread/hardware_destructive_interference_size
- Wikipedia: ABA problem (definition and tagged-reference workaround). https://en.wikipedia.org/wiki/ABA_problem
- cppreference: `std::has_single_bit`. https://en.cppreference.com/w/cpp/numeric/has_single_bit
- Clang: ThreadSanitizer. https://clang.llvm.org/docs/ThreadSanitizer.html
- Within this KB: [PR07 Coroutines and lifetimes](01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md) · [PR09 Embedded C](03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md) · [01-02 Layer 2](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#4-layer-2-concurrency-and-atomicity)
