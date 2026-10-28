# 01 · Lock-free vs wait-free vs obstruction-free, and solving the ABA problem

> **Scope.** "Lock-free" is a *progress guarantee*, not a speed claim. It says what the other threads can still do
> when one thread stops at the worst possible moment. This file measures that property directly: a thread stalled
> inside a mutex stops everyone, a thread stalled inside a CAS loop stops no one. It then replays the **ABA problem**
> step by step on a stack that recycles nodes, so the failure happens on every run, and shows the tag that prevents
> it, down to the instructions. File 02 builds rings, file 03 builds stacks, queues and a hash map, and file 04 solves
> the memory-reclamation problem that ABA is one face of.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 9.1 | `progress.cpp` | while one thread is stalled mid-operation, 3 others complete **0** increments of a mutex counter and ~800,000–930,000 of a CAS-loop counter in 50 ms | run, 4 threads, both compilers |
| 9.2 | `aba_demo.cpp` | a CAS on a recycled pointer **succeeds** and installs a freed node as the head; a 16-bit version tag in the pointer's top bits makes the same CAS fail; both are one 64-bit `LOCK CMPXCHG` | deterministic replay, both compilers; asm x86-64 + AArch64 |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (zig, libc++), `-O2 -Wall -Wextra -Wpedantic
-Werror -Wshadow -Wconversion -Wsign-conversion`, on an Intel Core i5-11260H (6 cores / 12 threads). AArch64 code is
compiled, not run (⚠). Stress tests use at most 4 threads.

---

## 1. First principles

### 1.1 Progress guarantees (Listing 9.1)

| Guarantee | Definition (Herlihy) | Typical C++ realization | When a thread is suspended mid-operation |
|---|---|---|---|
| **blocking** | none: progress depends on the scheduler running the lock holder | `std::mutex`, spin locks, `shared_mutex` | everyone who needs the lock waits |
| **obstruction-free** | a thread completes if it runs **alone** for long enough | some STM and abort-and-retry designs | others still finish; contention can livelock |
| **lock-free** | **some** thread completes an operation in a finite number of steps, whatever the others do | CAS loops: Treiber stack, MS queue, most "lock-free" structures | others keep completing; one unlucky thread may retry forever (starvation) |
| **wait-free** | **every** thread completes in a bounded number of its own steps | a single hardware RMW (`LOCK XADD`, LSE `LDADD`), wait-free queues with helping | everyone finishes in bounded time |

```cpp
// progress.cpp - blocking vs lock-free: what the other threads achieve while one thread is stalled mid-operation
#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <print>
#include <thread>
#include <vector>

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;
constexpr auto rlx = std::memory_order_relaxed;

// Each counter offers inc(), and inc_stalled(), which stops for 100 ms in the middle of its increment:
// while HOLDING the lock, or between the CAS loop's load and its CAS. `inside` is set once it is stalled.
struct LockCounter {
    std::mutex m;
    std::int64_t v = 0;
    void inc() {
        std::scoped_lock lk(m);
        ++v;
    }
    void inc_stalled(std::atomic<bool>& inside) {
        std::scoped_lock lk(m);
        inside = true;
        std::this_thread::sleep_for(100ms);   // preempted, page fault, descheduled: the lock stays held
        ++v;
    }
};
struct CasCounter {
    std::atomic<std::int64_t> v{0};
    void inc() {
        std::int64_t c = v.load(rlx);
        while (!v.compare_exchange_weak(c, c + 1, rlx)) {
        }
    }
    void inc_stalled(std::atomic<bool>& inside) {
        std::int64_t c = v.load(rlx);
        inside = true;
        std::this_thread::sleep_for(100ms);   // stalled between load and CAS: holds nothing
        while (!v.compare_exchange_weak(c, c + 1, rlx)) {
        }
    }
};

// 3 threads increment for a 50 ms window that starts once the 4th thread is stalled inside its operation.
// Only increments that COMPLETE inside the window count.
template <class Counter>
std::int64_t others_progress() {
    Counter c;
    std::atomic<bool> inside{false};
    std::atomic<std::int64_t> completed{0};
    std::jthread staller([&] { c.inc_stalled(inside); });
    while (!inside.load()) {
    }
    const auto deadline = Clock::now() + 50ms;
    {
        std::vector<std::jthread> others;
        for (int i = 0; i < 3; ++i)
            others.emplace_back([&] {
                std::int64_t mine = 0;
                while (Clock::now() < deadline) {
                    c.inc();
                    if (Clock::now() < deadline) ++mine;
                }
                completed.fetch_add(mine);
            });
    }
    return completed.load();
}

int main() {
    const std::int64_t lock_ops = others_progress<LockCounter>();
    const std::int64_t cas_ops = others_progress<CasCounter>();
    std::println("increments completed by 3 threads in the 50 ms while a 4th was stalled mid-operation:");
    std::println("  mutex counter (blocking):   {:>9}  -> others made progress: {}", lock_ops, lock_ops > 0 ? "yes" : "no");
    std::println("  CAS-loop counter (lock-free): {:>7}  -> others made progress: {}", cas_ops, cas_ops > 0 ? "yes" : "no");
}
```

Output (verified, GCC then Clang):

```text
increments completed by 3 threads in the 50 ms while a 4th was stalled mid-operation:
  mutex counter (blocking):           0  -> others made progress: no
  CAS-loop counter (lock-free):  812884  -> others made progress: yes
increments completed by 3 threads in the 50 ms while a 4th was stalled mid-operation:
  mutex counter (blocking):           0  -> others made progress: no
  CAS-loop counter (lock-free):  804160  -> others made progress: yes
```

* The stalled thread holds the mutex for 100 ms, so the other three complete **0** increments during the 50 ms window.
  Over two runs per compiler the CAS counter's three threads completed 804,160–927,800 increments in the same window,
  because the stalled thread holds nothing: it is just a thread that will retry its CAS later.
* A "stall" in production is a page fault, a preemption, an interrupt, a GC pause in a host runtime, a signal handler,
  or a debugger breakpoint. Lock-freedom is what keeps a real-time thread, a signal handler or an interrupt-like context
  from waiting on a descheduled lock holder.
* **Lock-free is not wait-free.** The CAS loop guarantees that *someone* succeeds on every round. A particular thread
  can lose every round, and Folder 07 measured 0.4–1.2 failures per increment at 2–4 threads. On ARMv8.0 even
  `fetch_add` is an `LDXR`/`STXR` loop (Folder 07 Listing 7.4), lock-free in principle. A single hardware RMW (`LOCK
  XADD`, LSE `LDADD`) is commonly treated as wait-free.
* **Lock-free is not fast.** Files 02–03 measure lock-free stacks and queues 2–4× *slower* than a mutex when every
  thread hits one hot word, and a lock-free hash map 10–30× *faster* than mutex maps, because its threads don't share
  hot words. The guarantee is about progress; throughput comes from avoiding contention.
* `std::atomic<T>::is_lock_free()` is a different, narrower notion: whether the *implementation* of that one type
  uses locks (Folder 07, file 03).

### 1.2 The ABA problem, replayed (Listing 9.2)

```cpp
// aba_demo.cpp - the ABA problem replayed step by step on a Treiber stack that recycles nodes, and the tag that fixes it
#include <atomic>
#include <cstdint>
#include <print>
#include <string>

struct Node {
    int value;
    Node* next;
    bool freed = false;   // set when the node goes back to the allocator (for the printout only)
};

std::string show(Node* n) {
    std::string s = "[";
    for (int guard = 0; n && guard < 8; n = n->next, ++guard)
        s += std::to_string(n->value) + (n->freed ? "(FREED)" : "") + (n->next ? " " : "");
    return s + "]";
}

// ---------- 1. Naive: the head is a plain pointer ----------
struct NaiveStack {
    std::atomic<Node*> head{nullptr};
    void push(Node* n) {
        n->next = head.load();
        while (!head.compare_exchange_weak(n->next, n)) {
        }
    }
    Node* pop() {
        Node* h = head.load();
        while (h && !head.compare_exchange_weak(h, h->next)) {
        }
        return h;
    }
};

// ---------- 2. Tagged: pointer in the low 48 bits, a 16-bit version counter in the top 16 ----------
// x86-64 and AArch64 user-space addresses fit in 48 bits (47 on x86-64 with 4-level paging); every successful
// CAS increments the tag, so "same pointer value" no longer means "same head".
struct TaggedStack {
    static constexpr std::uint64_t kPtrMask = (std::uint64_t{1} << 48) - 1;
    std::atomic<std::uint64_t> head{0};
    static std::uint64_t pack(Node* p, std::uint64_t tag) {
        return (reinterpret_cast<std::uintptr_t>(p) & kPtrMask) | (tag << 48);
    }
    static Node* ptr(std::uint64_t w) { return reinterpret_cast<Node*>(w & kPtrMask); }
    static std::uint64_t tag(std::uint64_t w) { return w >> 48; }
    void push(Node* n) {
        std::uint64_t old = head.load();
        do n->next = ptr(old);
        while (!head.compare_exchange_weak(old, pack(n, tag(old) + 1)));
    }
    Node* pop() {
        std::uint64_t old = head.load();
        while (ptr(old) && !head.compare_exchange_weak(old, pack(ptr(old)->next, tag(old) + 1))) {
        }
        return ptr(old);
    }
};

Node* naive_pop(NaiveStack& s) { return s.pop(); }     // out-of-line copies for the assembly listing
Node* tagged_pop(TaggedStack& s) { return s.pop(); }

int main() {
    Node a{1, nullptr}, b{2, nullptr}, c{3, nullptr};

    // The interleaving, replayed on one thread so that it happens every time:
    //   T1: begins pop: reads head = A and A->next = B ... and is preempted before its CAS.
    //   T2: pops A, pops B (B is freed), pushes A back (the allocator handed out A's address again).
    //   T1: resumes: CAS(head: A -> B) succeeds, because head == A again.
    {
        NaiveStack s;
        s.push(&c), s.push(&b), s.push(&a);
        std::println("naive : start                         {}", show(s.head.load()));
        Node* t1_head = s.head.load();
        Node* t1_next = t1_head->next;                  // T1 has read head and next
        s.pop();                                        // T2: pop A
        Node* gone = s.pop();                           // T2: pop B ...
        gone->freed = true;                             // ... and free it
        s.push(&a);                                     // T2: push A again: head == A, A->next == C
        std::println("naive : after T2 (pop, pop, push A)    {}", show(s.head.load()));
        const bool ok = s.head.compare_exchange_strong(t1_head, t1_next);   // T1's CAS
        std::println("naive : T1's CAS(head A -> B)          {} -> head is now {}", ok ? "SUCCEEDS" : "fails",
                     show(s.head.load()));
        std::println("        the head is now freed node B: the next pop hands out freed memory (use-after-free)");
    }
    a = {1, nullptr}, b = {2, nullptr}, c = {3, nullptr};
    {
        TaggedStack s;
        s.push(&c), s.push(&b), s.push(&a);
        std::println("tagged: start                         {} tag {}", show(TaggedStack::ptr(s.head.load())),
                     TaggedStack::tag(s.head.load()));
        std::uint64_t t1_head = s.head.load();
        Node* t1_next = TaggedStack::ptr(t1_head)->next;
        s.pop();
        Node* gone = s.pop();
        gone->freed = true;
        s.push(&a);
        std::println("tagged: after T2 (pop, pop, push A)    {} tag {}", show(TaggedStack::ptr(s.head.load())),
                     TaggedStack::tag(s.head.load()));
        const bool ok = s.head.compare_exchange_strong(
            t1_head, TaggedStack::pack(t1_next, TaggedStack::tag(t1_head) + 1));
        const std::uint64_t tag_now = TaggedStack::tag(s.head.load());
        const int retried = s.pop()->value;   // sequenced: never put the pop inside the println arguments
        std::println("tagged: T1's CAS(head A/tag 3 -> B)    {} (head is A/tag {}); T1 retries and pops A: {}",
                     ok ? "SUCCEEDS" : "fails", tag_now, retried);
        std::println("        stack afterwards               {}", show(TaggedStack::ptr(s.head.load())));
    }
}
```

Output (verified, both compilers print exactly this):

```text
naive : start                         [1 2 3]
naive : after T2 (pop, pop, push A)    [1 3]
naive : T1's CAS(head A -> B)          SUCCEEDS -> head is now [2(FREED) 3]
        the head is now freed node B: the next pop hands out freed memory (use-after-free)
tagged: start                         [1 2 3] tag 3
tagged: after T2 (pop, pop, push A)    [1 3] tag 6
tagged: T1's CAS(head A/tag 3 -> B)    fails (head is A/tag 6); T1 retries and pops A: 1
        stack afterwards               [3]
```

```text
  T1: h = head (A), next = h->next (B) ....................... CAS(head: A -> B) succeeds!
  T2:              pop A, pop B, free B, push A again (same address)
                   head: A -> C                                    head: B (freed) -> C
  The CAS compares BITS. A is "the same" pointer, but the node it names now has a different `next`.
```

* **The two ingredients:** a CAS whose correctness depends on state read *earlier* (`next = h->next`), and the
  possibility that the compared value comes back (address reuse by an allocator or free list, or a counter wrapping).
  The naive CAS succeeds and installs freed node B as the head, so the next `pop` returns freed memory.
* **A version tag** turns "same pointer" into "same pointer *and* same version". Every successful CAS increments the
  tag, so T1's expected value `{A, tag 3}` no longer matches `{A, tag 6}`. T1's CAS fails, it re-reads, and it pops A
  correctly.
* Without recycling, plain `delete` makes it worse: T1's `h->next` would read freed memory, a use-after-free *before*
  any ABA. That is the memory-reclamation problem; file 04 solves it with hazard pointers, EBR and RCU.

The tagged pop is still one 64-bit CAS. Clang 21 `-O3`, x86-64:

```asm
_Z9naive_popR10NaiveStack:         # naive_pop(NaiveStack&)
	movq	(%rdi), %rcx
	testq	%rcx, %rcx
	je	.LBB2_1
.LBB2_3:
	movq	8(%rcx), %rdx
	movq	%rcx, %rax
	lock	cmpxchgq	%rdx, (%rdi)
	je	.LBB2_2
	movq	%rax, %rcx
	testq	%rax, %rax
	jne	.LBB2_3
.LBB2_2:
	movq	%rcx, %rax
	retq
.LBB2_1:
	xorl	%ecx, %ecx
	movq	%rcx, %rax
	retq

_Z10tagged_popR11TaggedStack:      # tagged_pop(TaggedStack&)
	movabsq	$281474976710655, %rdx
	movq	(%rdi), %rcx
	movq	%rcx, %r8
	andq	%rdx, %r8
	je	.LBB3_1
	movabsq	$-281474976710656, %rsi
.LBB3_4:
	movq	%rcx, %rax
	andq	%rsi, %rax
	movq	8(%r8), %r8
	andq	%rdx, %r8
	orq	%rdx, %rax
	addq	%rax, %r8
	addq	$1, %r8
	movq	%rcx, %rax
	lock	cmpxchgq	%r8, (%rdi)
	je	.LBB3_5
	movq	%rax, %r8
	movq	%rax, %rcx
	andq	%rdx, %r8
	jne	.LBB3_4
.LBB3_1:
	xorl	%ecx, %ecx
	movq	%rcx, %rax
	retq
.LBB3_5:
	andq	%rdx, %rcx
	movq	%rcx, %rax
	retq
```

AArch64:

```asm
_Z9naive_popR10NaiveStack:         // naive_pop(NaiveStack&)
	ldar	x8, [x0]
	cbz	x8, .LBB2_5
.LBB2_1:
	ldr	x10, [x8, #8]
	ldaxr	x9, [x0]
	cmp	x9, x8
	b.ne	.LBB2_3
	stlxr	w11, x10, [x0]
	cmp	w11, #0
	csetm	w10, eq
	tbz	w10, #0, .LBB2_4
	b	.LBB2_5
.LBB2_3:
	mov	w10, wzr
	clrex
	tbnz	w10, #0, .LBB2_5
.LBB2_4:
	mov	x8, x9
	cbnz	x9, .LBB2_1
.LBB2_5:
	mov	x0, x8
	ret

_Z10tagged_popR11TaggedStack:      // tagged_pop(TaggedStack&)
	ldar	x8, [x0]
	ands	x11, x8, #0xffffffffffff
	b.eq	.LBB3_6
	mov	x9, #281474976710656
.LBB3_2:
	ldr	x11, [x11, #8]
	ldaxr	x10, [x0]
	cmp	x10, x8
	b.ne	.LBB3_4
	mov	x12, x8
	bfxil	x12, x11, #0, #48
	add	x11, x12, x9
	stlxr	w12, x11, [x0]
	cmp	w12, #0
	csetm	w11, eq
	tbz	w11, #0, .LBB3_5
	b	.LBB3_7
.LBB3_4:
	mov	w11, wzr
	clrex
	tbnz	w11, #0, .LBB3_7
.LBB3_5:
	ands	x11, x10, #0xffffffffffff
	mov	x8, x10
	b.ne	.LBB3_2
.LBB3_6:
	mov	x0, xzr
	ret
.LBB3_7:
	and	x0, x8, #0xffffffffffff
	ret
```

### 1.3 Where the tag bits come from

| Technique | Bits for the tag | Atomic width | Caveats |
|---|---|---|---|
| top bits of a 64-bit pointer (Listing 9.2) | 16 on x86-64 with 4-level paging (user addresses < 2^47) and AArch64 with 48-bit VAs | 64-bit CAS | x86 5-level paging (LA57) allows 57-bit addresses when a program asks for them; AArch64 pointer authentication (PAC) and MTE use top bits (Folder 01); the tag wraps after 65,536 updates |
| index + tag (Listings 9.5, 9.6) | 32 (with a 32-bit node index into a pool) | 64-bit CAS | needs a node pool (type-stable memory); 2^32 updates before wrap |
| pointer + counter, 128-bit (DWCAS) | 64 | `CMPXCHG16B` / `CASP` (Folder 07 Listing 7.8) | 16-byte loads may be writes; GCC calls libatomic; needs `-mcx16` or ARMv8.1 |
| no tag: prevent reuse while referenced | — | 64-bit CAS | hazard pointers / EBR / RCU (file 04): a node cannot be reused while a thread may still compare against it |

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| building blocks | `std::atomic`, CAS weak/strong | — | `is_always_lock_free` | `atomic_ref`, `atomic<shared_ptr>`, `atomic::wait` | — | `fetch_max`/`fetch_min` |
| reclamation | none (hand-rolled) | — | — | — | — | `<hazard_pointer>` (P2530) and `<rcu>` (P2545): **in the standard, in neither library here** (file 04) |
| concurrent containers | none in the standard (Concurrency TS proposals) | — | — | — | — | — (still none; use folly, TBB, Abseil, libcds) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| "lock-free" structure with `new`/`delete` per operation | the allocator takes locks; `delete` in `pop` frees memory others still read | preallocated node pools (Listings 9.5–9.6) or per-thread caches, plus safe reclamation (file 04) |
| Treiber stack head as a raw `std::atomic<Node*>` | ABA under node reuse (Listing 9.2) | tagged head (index+tag or pointer+tag), or hazard pointers |
| tag in pointer top bits | assume 16 free bits everywhere | check the VA width at start-up; prefer index + 32-bit tag; never combine with PAC/MTE |
| code that must not block (signal handler, real-time thread, interrupt context) | `std::mutex` or a spin lock "held only briefly" | lock-free or wait-free structure, no allocation, only always-lock-free atomics |
| "lock-free is faster" rewrite | replace a well-sharded mutex design with a single-CAS-hotspot structure | measure: hot-spot lock-free structures lost 2–4× to a mutex here (files 02–03); design for low contention first |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| stack/queue corruption, nodes appearing twice or vanishing, only under load | ABA on a recycled node | deterministic replay as in Listing 9.2; tags; model checking (CDSChecker/GenMC, Folder 12) |
| sporadic crash reading `node->next` | use-after-free: node freed while another thread still holds it | ASan under stress; hazard pointers/EBR (file 04) |
| one thread's latency explodes under contention while throughput is fine | lock-free starvation: that thread loses every CAS | per-thread retry histograms; wait-free design or back-off |
| "lock-free" code hangs when a thread is preempted | hidden blocking: a spin lock, or a slot claimed but not published (file 02's MPMC queue) | stall injection as in Listing 9.1 |
| tagged pointers break on a new platform | 57-bit VAs, PAC or MTE using the tag bits | start-up assertion on the address range |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Our spin lock is lock-free, there is no mutex"</b></summary>

**Initial prompt.** "We replaced `std::mutex` with an `atomic<bool>` spin lock, so the queue is lock-free now, right?"

**L5 textbook answer.** "Yes. It only uses atomics and never calls into the OS, so it's lock-free."

**Why L5 deadlocks on ARM64.** Lock-freedom is about what happens when a thread stops, not about which instructions it
uses. A spin lock is blocking: if the holder is preempted, every other thread spins without progress, exactly like
Listing 9.1's mutex (0 operations in 50 ms). It's worse than a mutex, because the waiters burn CPU that the holder may
need to get rescheduled. With a priority scheduler, a high-priority spinner can starve a low-priority holder
indefinitely: a livelock that looks like a deadlock.

**L7 principal defense.** "Lock-free means a stalled thread can't stop the others; Listing 9.1 tests exactly that. A
spin lock is a lock. If the requirement is non-blocking, the algorithm has to work by CAS on the data itself, not on a
lock bit."
</details>

<details><summary><b>Chain 2 ⚡ "Lock-free is faster, so rewrite the queue"</b></summary>

**Initial prompt.** "Our mutex-protected queue is a bottleneck. Should we switch to a lock-free queue?"

**L5 textbook answer.** "Yes. Lock-free avoids lock overhead and context switches, so it's always faster."

**Why L5 breaks.** In files 02–03 on this machine, the Michael-Scott queue was 2× slower than `std::mutex` + `deque`, and
Treiber stacks 4× slower than `mutex` + `vector`, under 4-thread contention. Every operation CASes the same one or two
words, and each failed CAS is a cache-line round trip. The mutex serializes threads but wastes fewer coherence
transactions. What won by 10–30× was a hash map whose threads touch *different* slots.

**L7 principal defense.** "First reduce contention: shard, batch, or use per-producer queues (SPSC rings, file 02). Use
lock-free when the requirement is a progress guarantee (no blocking on a preempted thread, signal-handler or real-time
safety), and then measure. Lock-free buys robustness, not throughput."
</details>

<details><summary><b>Chain 3 🔥 "Explain the ABA problem precisely"</b></summary>

**Initial prompt.** "What is ABA, exactly? Give a concrete interleaving and the consequence."

**L5 textbook answer.** "A value changes from A to B and back to A, so a CAS doesn't notice the change."

**Why L5 corrupts memory on ARM64.** It's incomplete: a value returning to A is harmless by itself. The bug needs a CAS
whose *new* value was computed from state read earlier, which is now stale. Listing 9.2: T1 reads `head = A` and
`next = B`; T2 pops A and B, frees B, and pushes A back; T1's `CAS(A → B)` succeeds and installs freed node B as the head.
The next pop returns freed memory. Nothing about this is architecture-specific: it happens on x86 and ARM64 alike,
under load, rarely enough to escape testing.

**L7 principal defense.** "Two fixes. Make 'same value' mean 'same version': a tag incremented on every successful CAS,
in the pointer's spare bits, an index + 32-bit tag, or a 128-bit pointer + counter. Or prevent reuse while anyone might
still compare against the old value, with hazard pointers or EBR (file 04). And I'd test it with a deterministic replay
like Listing 9.2, not just a stress test."
</details>

<details><summary><b>Chain 4 ⚡ "Put a 16-bit tag in the top of the pointer"</b></summary>

**Initial prompt.** "We pack a 16-bit counter into bits 48–63 of every head pointer. Any risks?"

**L5 textbook answer.** "No. x86-64 and ARM64 only use 48 bits of address space, so the top 16 are always free."

**Why L5 corrupts memory on ARM64.** Three risks. (1) Wrap-around: a 16-bit tag repeats after 65,536 successful updates,
and a thread preempted for a few milliseconds on a hot structure can see its tag come back: ABA again, just rarer.
(2) The address space: x86-64 5-level paging (LA57) permits 57-bit user addresses when a program requests them, and
AArch64 can use 52-bit VAs. (3) The bits may be taken: AArch64 pointer authentication signs pointers in the top bits,
and MTE uses bits 56–59 (Folder 01). Stripping or overwriting them breaks authentication or tagging, and raw pointer
stores bypass the signing.

**L7 principal defense.** "Assert the address range at start-up and keep tag width explicit. Prefer index + 32-bit tag
over a node pool (Listings 9.5–9.6, one portable 64-bit CAS), or hazard pointers, which need no tag at all."
</details>

<details><summary><b>Chain 5 🧊 "ARM's LL/SC can't suffer ABA, can it?"</b></summary>

**Initial prompt.** "ARM's exclusive monitor fails the store-exclusive if *any* write happened to the location, even
one that restored the old value. So isn't ARM immune to ABA?"

**L5 textbook answer.** "Yes, LL/SC detects intervening writes, so ABA is an x86 problem."

**Why L5 corrupts memory on ARM64.** The monitor is armed by the `LDXR` *inside* the CAS (Folder 07 Listing 7.7), long
after the code read `head` and `head->next` with ordinary loads. The ABA window is between those reads and the CAS, and
the monitor wasn't watching then. C++ can't express "load-linked here, compute, store-conditional there", and the
architecture doesn't let an LL/SC pair span arbitrary other memory accesses reliably anyway. The C++ Treiber stack is
exactly as ABA-prone on ARM64 as on x86.

**L7 principal defense.** "ABA is a property of the algorithm under value-comparing CAS, which is what C++ gives on
every target. The same tag or reclamation scheme is needed on ARM."
</details>

<details><summary><b>Chain 6 🧊 "Is fetch_add wait-free?"</b></summary>

**Initial prompt.** "Classify: a CAS-loop counter, `fetch_add`, and a mutex counter."

**L5 textbook answer.** "All atomics are wait-free, and the mutex is blocking."

**Why L5 breaks.** The CAS loop is **lock-free**: Listing 9.1 shows system-wide progress, but any one thread can fail
indefinitely. `fetch_add` depends on the hardware. On x86 it's one `LOCK XADD`, commonly treated as wait-free. On ARMv8.0
it compiles to an `LDXR`/`STXR` retry loop (lock-free in principle), and with LSE to one `LDADD`. The mutex is blocking.

**L7 principal defense.** "For a latency bound per thread, not just system throughput, I need wait-freedom: single
hardware RMWs, or algorithms with helping. And I'd verify the instruction on each target, because the same C++ line is
wait-free on one ISA and a retry loop on another."
</details>

<details><summary><b>Chain 7 ⚡ "Our queue is lock-free, it just calls new in push"</b></summary>

**Initial prompt.** "Push allocates a node with `new`, pop `delete`s it. The queue itself uses only CAS. Lock-free?"

**L5 textbook answer.** "Yes, the algorithm is lock-free; allocation is a separate concern."

**Why L5 corrupts memory on ARM64.** Two problems. General-purpose allocators take locks or use per-thread caches that
fall back to locks, so a preempted thread inside `malloc` can block others: the system isn't lock-free. Worse, `delete`
in `pop` frees a node that another thread may still be reading (`head->next`): a use-after-free, and with address reuse,
ABA (Listing 9.2).

**L7 principal defense.** "Nodes come from a preallocated pool or per-thread free lists (type-stable memory,
Listings 9.5–9.6), and if they must go back to the system, through safe memory reclamation (file 04). Lock-freedom is
a property of the whole operation, including memory management."
</details>

<details><summary><b>Chain 8 🔥 "Can a signal handler use our queue?"</b></summary>

**Initial prompt.** "A crash handler (a signal handler) wants to push a message into our logging queue, which is
protected by a `std::mutex`. Safe?"

**L5 textbook answer.** "Yes, use `try_lock` so it never blocks."

**Why L5 deadlocks on ARM64.** If the signal arrives on a thread that holds the queue's mutex, `try_lock` fails forever
on that thread, because the holder can't run until the handler returns, and plain `lock` deadlocks. Mutex functions
aren't async-signal-safe at all. Allocation inside the handler has the same problem. This is Listing 9.1's stalled
holder, with the stall being "interrupted by the handler".

**L7 principal defense.** "A preallocated lock-free ring (file 02) with only always-lock-free atomics, no allocation, no
locks. Better still, a per-thread SPSC ring that the handler writes and a normal thread drains. Async-signal-safety is the
textbook case for lock-free design."
</details>

---

## 6. Invariants checklist

- [ ] The required progress guarantee (blocking / lock-free / wait-free) is written down, and stall injection tests it.
- [ ] Every CAS whose new value depends on earlier reads is protected against ABA (tag or safe reclamation).
- [ ] Tag width and address-space assumptions are asserted at start-up.
- [ ] No allocation or locking inside operations that must be lock-free.
- [ ] Lock-free code is compared against a sharded-mutex baseline before it ships.
- [ ] Deterministic replays exist for the known dangerous interleavings.

## 7. References

- M. Herlihy, "Wait-Free Synchronization", TOPLAS 1991: <https://cs.brown.edu/~mph/Herlihy91/p124-herlihy.pdf>
- M. Michael, "Hazard Pointers: Safe Memory Reclamation for Lock-Free Objects", IEEE TPDS 15(6), 2004, DOI 10.1109/TPDS.2004.8
- Linux x86-64 5-level paging (address-space size): <https://www.kernel.org/doc/html/latest/arch/x86/x86_64/5level-paging.html>
- Linux AArch64 tagged addresses (TBI, MTE): <https://www.kernel.org/doc/html/latest/arch/arm64/tagged-address-abi.html>
- P2530R3 (hazard pointers for C++26): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2530r3.pdf>
- P2545R4 (read-copy update for C++26): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p2545r4.pdf>
