# 03 · 30 FAANG / NVIDIA / HFT bar-raiser questions: multithreading and the memory model

> **Scope.** Thirty questions in the form a bar-raiser actually asks them: a plausible first answer, then the follow-up
> that breaks it. Every answer here is backed by something this knowledge base *ran or compiled*, and each answer
> names the folder and listing, so it can be re-derived on a whiteboard and defended with evidence rather than
> folklore. Use it as a drill: read the prompt, answer aloud, then read why the textbook answer fails.

**How to use it.** Cover everything below the **Initial prompt**, answer, then compare. An L7 answer has three parts:
the mechanism (what the compiler or hardware does), the evidence (a measurement or the instructions), and the
engineering decision (what you would ship and how you'd verify it).

---

## 1. First principles

### 1.1 What the questions test

| Area | Questions | Evidence in this KB |
|---|---|---|
| data races, happens-before, coherence | Q1, Q2, Q3, Q6 | [Folder 07, file 01](../07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/01-happens-before-synchronizes-with-modification-orders-and-data-race-ub.md) |
| memory orders and hardware | Q4, Q5, Q7, Q8 | [Folder 07, files 02–03](../07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/02-the-6-memory-orders-relaxed-acq-rel-seq-cst-litmus-tests-and-x86-vs-arm64-asm.md) |
| caches and contention | Q9, Q23 | [Folder 07, file 04](../07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/04-atomic-thread-fence-compiler-barriers-false-sharing-and-cache-line-bouncing.md) |
| OS primitives | Q10–Q17, Q28 | [Folder 08](../08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/) |
| lock-free structures and reclamation | Q18–Q22, Q29 | [Folder 09](../09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/) |
| async execution | Q24–Q27, Q30 | [Folder 10](../10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/) |

### 1.2 The three moves of an L7 answer

1. **Name the mechanism precisely.** "Store→load reordering through the store buffer", not "the CPU reorders things".
2. **Bring evidence.** An instruction (`XCHG`, `LDAR`), a measurement with its conditions, or a reproducible
   interleaving.
3. **Decide.** What you'd ship, what it costs, how you'd test it (stress test, model checker, ARM CI lane).

---

## 2. Evolution table

| Topic | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| memory model | defined | — | `consume` discouraged | P0668 `seq_cst` repair, release sequences narrowed | — | `consume` deprecated |
| threads & sync | `thread`, `mutex`, `condition_variable`, `future` | `shared_timed_mutex` | `scoped_lock`, `shared_mutex` | `jthread`, stop tokens, `latch`, `barrier`, semaphores, `atomic::wait`, `atomic_ref` | `move_only_function` | — |
| lock-free & async | atomics | — | `is_always_lock_free` | `atomic<shared_ptr>`, coroutines | `std::generator` | hazard pointers, RCU, `std::execution`, `fetch_max` |

---

## 3. Production blueprints: how answers go wrong

| Interview anti-pattern | What it sounds like | What the L7 version sounds like |
|---|---|---|
| hand-waving the hardware | "the CPU might reorder" | "store→load via the store buffer on x86; any pair on AArch64 without `LDAR`/`STLR`/`DMB`" |
| testing on x86 only | "it passed a billion iterations" | "x86 can only expose SB; MP/LB need ARM hardware or a model checker" |
| lock-free as speed | "lock-free is faster" | "lock-free is a progress guarantee; contention decides speed (Folder 09 measured both directions)" |
| memorized numbers | "a mutex costs 25 ns" | "uncontended ~15 ns here, one CAS; contended cost is the wake-up, and it's platform-specific" |
| fixing timing bugs with sleeps | "add a small sleep" | "find the missing happens-before edge; the sleep just shrinks the window" |

---

## 4. Failure modes in the interview itself

| Symptom | Root cause | Remedy |
|---|---|---|
| an answer collapses at the first "why?" | rules without mechanism | always attach the hardware or compiler mechanism |
| the interviewer's ARM follow-up stumps you | x86-only mental model | think in the four litmus shapes: SB, MP, LB, IRIW |
| a design question becomes a lock-free rabbit hole | premature optimization | start with mutex + sharding, then justify atomics by measurement |
| numbers that can't be defended | quoting blog posts | quote what you measured, and the conditions |

---

## 5. The 30 questions

<details><summary><b>Q 1 🔥 "Data race or race condition?"</b></summary>

**Initial prompt.** "Two threads do `counter.store(counter.load() + 1)` on a `std::atomic<int>`. Is there a data
race? Is the program correct?"

**L5 textbook answer.** "It's atomic, so there's no race and the program is correct."

**Why L5 breaks.** No *data race* (every access is atomic, so the behaviour is defined), but a *race condition*: the
read-modify-write is split, and increments are lost. Folder 07 Listing 7.2 lost 47–74% of 8,000,000 increments with 4
threads. "Defined" and "correct" are different properties.

**L7 principal defense.** "A data race is two conflicting accesses, at least one non-atomic, not ordered by
happens-before: undefined behaviour. A race condition is a logic error in interleaving. Fix this one with one atomic
RMW (`fetch_add(1, relaxed)`), and if it's hot, shard the counter per thread (Folder 07, file 04)."
</details>

<details><summary><b>Q 2 🔥 "Why does my spin-wait hang only in release builds?"</b></summary>

**Initial prompt.** "`while (!ready) {}` on a plain `bool` set by another thread works at `-O0` and hangs at `-O2`.
Compiler bug?"

**L5 textbook answer.** "The compiler cached the value in a register; make it `volatile`."

**Why L5 breaks.** It's worse than caching: both GCC 16 and Clang 21 compile that loop to a bare `ret` (Folder 07
Listing 7.1). A data race is UB, so `ready` can't change, and a side-effect-free loop may be assumed to terminate
([intro.progress]). `volatile` brings back the load but gives no ordering for the data the flag guards, so on ARM64
the waiter can see the flag and stale data.

**L7 principal defense.** "`std::atomic<bool>`, release store, acquire load: `STLR`/`LDAR` on ARM, plain moves on x86.
For long waits `ready.wait(false)` / `notify_one()`. The fix is a happens-before edge, not an optimization flag."
</details>

<details><summary><b>Q 3 ⚡ "Explain acquire/release with a concrete example"</b></summary>

**Initial prompt.** "Show me where acquire and release are needed when one thread fills a buffer and another reads it."

**L5 textbook answer.** "Use release on the flag store and acquire on the flag load; that makes the flag visible."

**Why L5 breaks.** The flag is visible either way (coherence). What release/acquire add is the *buffer*: everything
sequenced before the release store happens before everything after the acquire load that reads it. And for a reused
buffer you need the edge in both directions (Folder 07 Listing 7.3 A uses an `ack` flag back to the producer), or the
producer's next write races with the consumer's read.

**L7 principal defense.** "Producer: write buffer, `flag.store(r, release)`. Consumer: `flag.load(acquire) == r`, read
buffer, `ack.store(r, release)`; producer acquires `ack` before reusing the buffer. Then the happens-before arrows:
writes → release → acquire → reads, verified with 100,000 rounds and 0 stale payloads."
</details>

<details><summary><b>Q 4 🔥 "When do you actually need seq_cst?"</b></summary>

**Initial prompt.** "Give a case where acquire/release is not enough."

**L5 textbook answer.** "When you want to be extra safe."

**Why L5 breaks.** The precise case is store-buffering, "set my flag, then read yours" (Dekker, Peterson, hazard
pointer publication). Release/acquire doesn't order a store before a *later* load. Folder 07 Listing 7.5 observed the
SB outcome with release/acquire in 0.7–3% of runs **on x86**, and never with `seq_cst`. The other case is IRIW, where
independent readers must agree on the order of independent writes.

**L7 principal defense.** "SB and IRIW need `seq_cst` (or `seq_cst` fences). On x86 the cost is the store: `XCHG`, 4.7–5.5
ns vs 0.12–0.26 ns for a release store (Listing 7.6). On AArch64, `LDAR` instead of the cheaper `LDAPR`. I use it where the
algorithm has the SB shape (hazard pointers in Folder 09, Chase-Lev in Folder 10) and nowhere else on hot paths."
</details>

<details><summary><b>Q 5 ⚡ "x86 is strongly ordered, so memory orders don't matter there?"</b></summary>

**Initial prompt.** "Since x86 is TSO, can we just use relaxed atomics on x86 builds?"

**L5 textbook answer.** "Yes, x86 never reorders, so relaxed behaves like seq_cst."

**Why L5 breaks.** Two errors. (1) x86 does reorder: a store followed by a load of another location (SB, observed in
Listing 7.5). (2) Memory orders also constrain the *compiler*. A relaxed store may be moved before earlier plain
writes even on x86, and code compiled for ARM later inherits the bug.

**L7 principal defense.** "Write the order the algorithm needs. On x86 acquire and release cost nothing (plain `MOV`s,
Listing 7.4), so there's no performance reason to cheat. The only expensive things are `seq_cst` stores and RMWs."
</details>

<details><summary><b>Q 6 🧊 "What does memory_order_relaxed guarantee?"</b></summary>

**Initial prompt.** "Is relaxed 'no guarantees at all'? Can a reader see a relaxed counter go backwards?"

**L5 textbook answer.** "Relaxed means anything goes."

**Why L5 breaks.** Relaxed still guarantees atomicity and **per-object coherence**: one modification order per atomic,
agreed by all threads. A reader can miss values but never sees the counter go backwards (Listing 7.3 D: 2M stores, 2
readers, 0 backward steps). What it gives up is ordering *between* different objects.

**L7 principal defense.** "Relaxed for counters, statistics, 'max seen so far', and for the index loads that a later
acquire or fence orders. Never to conclude something about another object from the value read."
</details>

<details><summary><b>Q 7 ⚡ "compare_exchange_weak or strong?"</b></summary>

**Initial prompt.** "When do you use weak vs strong CAS, and what does each compile to?"

**L5 textbook answer.** "Weak is faster; use it everywhere."

**Why L5 breaks.** On LL/SC (ARMv8.0), weak is one `LDAXR`/`STLXR` attempt that can fail spuriously; strong wraps it in an
inner retry loop (Folder 07 Listing 7.7). A single-shot weak CAS whose failure *means* something ("someone else took the
job") breaks on ARM. On x86 (`LOCK CMPXCHG`) and with LSE (`CASAL`), weak and strong are the same instruction.

**L7 principal defense.** "Weak inside retry loops; strong for one-shot decisions; LSE builds (`-march=armv8.1-a` or
outline atomics) to remove spurious failures."
</details>

<details><summary><b>Q 8 🧊 "Is std::atomic<T> always lock-free for small T?"</b></summary>

**Initial prompt.** "We share `std::atomic<Pair>` (16 bytes) and `std::atomic<Rgb>` (3 bytes) between processes in
shared memory. Fine?"

**L5 textbook answer.** "Yes, small types are atomic in hardware."

**Why L5 breaks.** Folder 07 Listing 7.9: libstdc++ makes neither always-lock-free; the 16-byte type is lock-free only
with Clang and `-mcx16`; libc++ makes the 3-byte atomic 4 bytes and 4-aligned, libstdc++ keeps 3/1, which is a layout
difference. A lock-based fallback keeps its lock inside each process, so two processes don't exclude each other.
16-byte "loads" are often writes (`CMPXCHG16B`, `LDAXP`/`STXP`).

**L7 principal defense.** "`static_assert(std::atomic_ref<T>::is_always_lock_free)` and explicit sizes/alignment for
anything shared across processes or library boundaries; plain fixed-width integers accessed through `atomic_ref`."
</details>

<details><summary><b>Q 9 ⚡ "Our per-thread counters don't scale. There's no sharing!"</b></summary>

**Initial prompt.** "Each thread increments its own element of `std::vector<std::atomic<int64_t>>`. Why does it slow
down with more threads?"

**L5 textbook answer.** "Atomics are slow; use plain ints."

**Why L5 breaks.** False sharing: eight counters per 64-byte line, and every increment needs the line exclusive.
Folder 07 Listing 7.15: 1.7–2.25 ns per increment at 8-byte spacing vs about 0.5 ns padded, with only 2–4 threads.
Plain ints change nothing about the cache line, and make the reader's sum a data race.

**L7 principal defense.** "One 128-byte-aligned slot per thread, single-writer relaxed load+store increments, relaxed
reads to sum; or `thread_local` accumulation flushed periodically. Verify with `perf c2c`."
</details>

<details><summary><b>Q 10 🔥 "Is locking a mutex a system call?"</b></summary>

**Initial prompt.** "Why is an uncontended `std::mutex` lock about 15 ns?"

**L5 textbook answer.** "The kernel's mutex is fast."

**Why L5 breaks.** No kernel involvement when uncontended: a futex-based lock is one CAS in user space; the system
call (`futex`, number 202 on x86-64, 98 on AArch64) appears only on contention (Folder 08 Listing 8.5: 0 slow-path
sleeps for 200,000 uncontended pairs). Windows' SRWLOCK works the same way.

**L7 principal defense.** "Fast path CAS 0→1; contended path sets 2 and `FUTEX_WAIT`s; unlock wakes only if it saw 2
(Drepper's three states). Contention is what costs: two system calls and context switches. That's why production
mutexes spin briefly before sleeping."
</details>

<details><summary><b>Q 11 🔥 "Why must condition-variable waits use a predicate?"</b></summary>

**Initial prompt.** "Our consumer calls `cv.wait(lk)` after the producer notifies. Why insist on a predicate?"

**L5 textbook answer.** "Because of spurious wakeups, which are rare."

**Why L5 breaks.** Three reasons, two of them common. A notification sent before the wait is lost (Folder 08 Listing
8.8: the predicate-less wait timed out). Another consumer can take the item first (1,190–2,198 'woke to nothing'
wakeups in 200,000 items). And spurious wakeups are permitted.

**L7 principal defense.** "`cv.wait(lk, pred)` always: the predicate is the state the condition variable doesn't
remember. Change that state under the same mutex."
</details>

<details><summary><b>Q 12 🔥 "The flag is atomic, so the producer doesn't need the mutex"</b></summary>

**Initial prompt.** "`ready` is `std::atomic<bool>`; the producer sets it and notifies without locking. Safe?"

**L5 textbook answer.** "Yes: atomic means no race."

**Why L5 deadlocks on ARM64.** No data race, but a lost wakeup: the consumer evaluates the predicate (false) under the
mutex, the producer sets the flag and notifies before the consumer blocks, and the consumer sleeps forever. The mutex
is what makes "check, then sleep" atomic with respect to the change.

**L7 principal defense.** "Set the state under the mutex (notify after unlocking), or use a primitive that checks and
sleeps atomically: `ready.wait(false)` / `notify_one()`."
</details>

<details><summary><b>Q 13 🧊 "Notify under the lock or after it?"</b></summary>

**Initial prompt.** "Does it matter whether `notify_one` is inside the critical section? Doesn't wait morphing make it
free?"

**L5 textbook answer.** "Inside is free thanks to wait morphing."

**Why L5 breaks.** glibc's condition variable, rewritten for 2.25 (2017), does not requeue waiters onto the mutex, so
there is no "wait morphing" help (⚠ from source). On this machine, notifying after unlock was faster with libc++/SRW
(0.61–0.64 vs 0.91 µs round trip), and winpthreads was 22–46 µs either way (Folder 08 Listing 8.9).

**L7 principal defense.** "After unlock, except when the woken thread may destroy the condition variable immediately
(a one-shot rendezvous on the stack); then notify under the lock. And measure on the target platform."
</details>

<details><summary><b>Q 14 ⚡ "Why does std::thread's destructor terminate?"</b></summary>

**Initial prompt.** "An exception before `join()` aborts our service. Why not just detach in the destructor?"

**L5 textbook answer.** "Detach is the safe default; terminating is a standard defect."

**Why L5 corrupts memory on ARM64.** Detaching leaves a thread using references into a destroyed scope:
use-after-free. Implicit join can hang during unwinding. So `std::thread` terminates (Folder 08 Listing 8.2); `std::jthread`
requests stop and joins. That only helps if the thread checks its token, and a `jthread` destroyed early stops its
thread immediately (Folder 11's timing-wheel demo hit exactly that).

**L7 principal defense.** "`jthread` members declared last, thread functions that take a `stop_token` and check it at
every blocking point, `condition_variable_any` stop-token waits, and `join()` when a thread must finish its work."
</details>

<details><summary><b>Q 15 🧊 "What happens if a call_once callable throws?"</b></summary>

**Initial prompt.** "Our init uses `std::call_once`; if it throws, the next call should retry. Correct?"

**L5 textbook answer.** "Yes, the standard guarantees the retry."

**Why L5 deadlocks on ARM64.** The standard does, and libc++ does it. On this MinGW GCC 16, the second `call_once` blocked
forever (Folder 08 Listing 8.11): libstdc++ uses `pthread_once` on gthreads targets, and its own header warns that
pthread_once doesn't reset the flag after an exception (GCC bug 66146). The same code is correct on one toolchain and
a production outage on another.

**L7 principal defense.** "No exceptions out of `call_once` in portable code: a function-local static (retried
correctly on both toolchains) or an explicit mutex + state flag."
</details>

<details><summary><b>Q 16 ⚡ "shared_mutex for a read-mostly map?"</b></summary>

**Initial prompt.** "99% reads. Is `std::shared_mutex` the right lock?"

**L5 textbook answer.** "Yes, readers run in parallel."

**Why L5 breaks.** Readers still *write* the lock's reader count; libc++ even takes an internal mutex per
`lock_shared`. Folder 08 Listing 8.7: 2–11× slower than `std::mutex` with empty read sections; 3.7–4.6× faster at 4
threads only with 1–3 µs reads. Writer preference also differs between libraries.

**L7 principal defense.** "Short lookups: a sharded mutex, or readers that write nothing (RCU/hazard pointers, an
immutable snapshot). Long read sections: `shared_mutex`, with an explicit fairness requirement. Measure first."
</details>

<details><summary><b>Q 17 🔥 "Design a deadlock-free bank transfer"</b></summary>

**Initial prompt.** "`transfer(from, to)` must lock both accounts. How do you avoid deadlock?"

**L5 textbook answer.** "Lock `from`, then `to`."

**Why L5 deadlocks on ARM64.** Opposite transfers each hold one lock and wait for the other (Folder 08 Listing 8.6
forces it: both time out).

**L7 principal defense.** "`std::scoped_lock(from.m, to.m)`, whose `std::lock` algorithm never blocks while holding a
contested lock, or a global id order; handle `from == to`. For cross-module nesting, a documented lock hierarchy.
And the shape of the code matters most: never call unknown code while holding a lock."
</details>

<details><summary><b>Q 18 🔥 "Lock-free, wait-free, obstruction-free: define them by behaviour"</b></summary>

**Initial prompt.** "What's the difference, and how would you test that a structure is lock-free?"

**L5 textbook answer.** "Lock-free means no mutex."

**Why L5 breaks.** It's about progress when a thread stalls. A spin lock has no mutex and is blocking. Folder 09
Listing 9.1: with one thread stalled mid-operation, 3 others completed **0** mutex-counter increments and 800,000–930,000
CAS-loop increments in 50 ms. Lock-free: someone always progresses. Wait-free: everyone does, in bounded steps.

**L7 principal defense.** "Test by stall injection, as Listing 9.1 does: suspend a thread at the worst point and
measure the others. And lock-freedom includes memory management: no `malloc` locks, safe reclamation."
</details>

<details><summary><b>Q 19 🔥 "Walk me through ABA"</b></summary>

**Initial prompt.** "What exactly goes wrong in a Treiber stack without tags?"

**L5 textbook answer.** "A value goes A→B→A and the CAS doesn't notice."

**Why L5 corrupts memory on ARM64.** The precise failure: T1 reads head A and next B; T2 pops A and B, frees B, pushes A
back; T1's CAS(A→B) succeeds and installs freed B as the head (Folder 09 Listing 9.2 replays it deterministically).
LL/SC doesn't help, because C++'s CAS arms the monitor *after* the earlier loads (the AArch64 asm shows `LDR` of
`next` before `LDAXR`).

**L7 principal defense.** "A version tag in the CAS-ed word (index + 32-bit tag, pointer top bits with care, or 128-bit
DWCAS), or prevent reuse with hazard pointers/EBR. Test with a deterministic replay of the interleaving."
</details>

<details><summary><b>Q 20 🔥 "Hazard pointers, EBR or RCU?"</b></summary>

**Initial prompt.** "Our lock-free routing table's readers sometimes hold a snapshot for a whole request. Which
reclamation scheme?"

**L5 textbook answer.** "EBR: it's the fastest."

**Why L5 breaks.** EBR pins everything retired since the slowest reader entered. Folder 09 Listing 9.10: with one
stalled reader, EBR freed **0 of 10,000** versions and hazard pointers freed 9,999. Read costs (3 readers, aggregate):
QSBR 0.33–0.46 ns, hazard pointers 1.8–2.1 ns, EBR 3.9–19.6 ns.

**L7 principal defense.** "Hazard pointers for long-held references (bounded memory), EBR/RCU for short sections and
long traversals, and monitoring of retired-but-not-freed memory either way. Hazard publication must be `seq_cst` (or
asymmetric fences): it's the SB pattern."
</details>

<details><summary><b>Q 21 ⚡ "Design an SPSC queue for a market-data handler"</b></summary>

**Initial prompt.** "One feed thread, one strategy thread. Design the queue and tell me what limits its throughput."

**L5 textbook answer.** "A lock-free queue with CAS on head and tail."

**Why L5 breaks.** No CAS is needed: each index has one writer (release store, acquire load). The throughput limit is
cache traffic and regime. Folder 09 Listing 9.3: cross-core 5.4–9.2 ns per item with cached indices while the ring
flows, 47–61 ns for every variant once it runs full; 2.3–5 ns on hyper-thread siblings.

**L7 principal defense.** "Padded producer and consumer lines, cached indices, 64-bit indices, back-off when full, and
pinning both threads to cores on the same socket. Size the ring and the consumer so it flows, and count refreshes to
see which regime production is in."
</details>

<details><summary><b>Q 22 🧊 "Is Vyukov's MPMC queue lock-free?"</b></summary>

**Initial prompt.** "It uses only CAS and stores. Lock-free?"

**L5 textbook answer.** "Yes."

**Why L5 breaks.** A producer that has claimed a slot but not yet published it makes consumers report "empty" even if
later slots are full (Folder 09 Listing 9.4's stall demo). That is a blocking window without a lock.

**L7 principal defense.** "Excellent and practical, but not lock-free in the formal sense. If producers can be
preempted for long, or run in signal handlers, use per-producer SPSC rings or a lock-free queue with helping."
</details>

<details><summary><b>Q 23 ⚡ "Our lock-free stack is slower than the mutex version"</b></summary>

**Initial prompt.** "We replaced a mutex stack with Treiber and got 4× slower. Explain."

**L5 textbook answer.** "The implementation must be buggy."

**Why L5 breaks.** Folder 09 Listing 9.5: 206–291 ns per round lock-free vs 52–59 ns with a mutex, 4 threads on one
head. Each failed CAS costs a line transfer; a mutex serializes with fewer wasted transactions. The same folder's
lock-free hash map, whose threads don't share hot words, was 10–30× faster than mutex maps.

**L7 principal defense.** "Contention decides throughput; lock-freedom decides progress. Reduce contention first
(sharding, elimination back-off, per-thread caches), then pick the synchronization."
</details>

<details><summary><b>Q 24 🔥 "Why the seq_cst fence in Chase-Lev's pop?"</b></summary>

**Initial prompt.** "The owner owns `bottom`. Why is there a full fence between storing `bottom` and loading `top`?"

**L5 textbook answer.** "To be conservative."

**Why L5 corrupts memory on ARM64.** The owner stores `bottom` and then loads `top`, while a thief loads `top` and then
`bottom`: the SB shape. Without the fence, both can take the last element, and the task runs twice. The fence is `LOCK
OR` on x86 and `DMB ISH` on AArch64 (Folder 10 Listing 10.3, which verified exactly-once execution of 2M tasks).

**L7 principal defense.** "Lê et al.'s C11 orders: `seq_cst` fences in `pop` and `steal`, CAS on `top` for the last
element. Plus an exact-once stress test on ARM hardware."
</details>

<details><summary><b>Q 25 ⚡ "Why is our std::async code serial?"</b></summary>

**Initial prompt.** "We launch 8 `std::async(launch::async, ...)` calls in a loop and ignore the results. 8× slower than
expected. Why?"

**L5 textbook answer.** "Thread creation overhead."

**Why L5 breaks.** The future returned by `std::async` blocks in its destructor. Discarding it makes each call
synchronous (Folder 10 Listing 10.1: the statement took at least 100 ms for a 100 ms task). Both libraries mark
`std::async` `[[nodiscard]]` for this reason.

**L7 principal defense.** "Keep the futures and `get()` them after starting all work, or use a pool plus a latch or a
sender. And always pass `launch::async`: the default policy may defer."
</details>

<details><summary><b>Q 26 🔥 "Do coroutines allocate? Why did our chain overflow the stack?"</b></summary>

**Initial prompt.** "Two problems: an allocation profile full of coroutine frames, and a stack overflow in a loop
awaiting cached results."

**L5 textbook answer.** "Coroutines are stackless and zero-cost, so neither should happen."

**Why L5 breaks.** Frames are heap-allocated unless HALO elides them. GCC 16 never did; Clang only when the lifetime was
local to the caller (Folder 10 Listing 10.5: 56- and 576-byte frames). The overflow comes from awaiters that call
`resume()` themselves, which nests a native call per await: `0xC00000FD` after a few thousand hops (Listing 10.6).

**L7 principal defense.** "A custom `promise_type::operator new` (pool or arena) for hot coroutines, and symmetric
transfer (`await_suspend` returns the next handle): the resume clone ends in a tail jump (`jmpq *(%rdi)`, `br x1`), so
a million synchronous awaits completed in constant stack."
</details>

<details><summary><b>Q 27 🧊 "What do senders buy over futures?"</b></summary>

**Initial prompt.** "C++26 `std::execution` vs `std::future`: what's the measurable difference?"

**L5 textbook answer.** "Senders are much faster."

**Why L5 breaks.** Per hop onto a pool, Folder 10 Listing 10.9 measured the *same* latency (0.89–0.93 vs 0.68–0.95 µs on
libc++), because both wait on a condition variable. The differences are elsewhere: 0 allocations per hop vs 2–3, a
whole `when_all` in one 136-byte operation state, an inline pipeline that compiles to `mov $42`, explicit schedulers,
and a stopped channel.

**L7 principal defense.** "Senders win on allocation-free composition, structured lifetimes and cancellation, not on raw
wake-up latency. Benchmark with the same blocking primitive on both sides."
</details>

<details><summary><b>Q 28 ⚡ "Is thread_local free?"</b></summary>

**Initial prompt.** "Our allocator's per-thread cache lives in a `thread_local`. On the MinGW build it's 10× slower.
Why?"

**L5 textbook answer.** "TLS is one `%fs`-relative instruction everywhere."

**Why L5 breaks.** Only in the local-exec model. Shared libraries use general-dynamic (`__tls_get_addr` or TLS
descriptors). This MinGW GCC uses emulated TLS: 12.95–13.58 ns per access vs 0.96–1.00 ns with Clang's native TLS
(Folder 08 Listing 8.3). Dynamic-init `thread_local`s add an init call or guard to every access.

**L7 principal defense.** "`constinit thread_local` POD, address fetched once per operation, `-ftls-model=initial-exec`
for libraries never `dlopen`ed, and per-toolchain measurement."
</details>

<details><summary><b>Q 29 🧊 "Is std::atomic<std::shared_ptr> lock-free?"</b></summary>

**Initial prompt.** "Our config is an `atomic<shared_ptr>` read millions of times per second. Lock-free? Fast?"

**L5 textbook answer.** "Yes, it's `std::atomic`."

**Why L5 breaks.** libstdc++'s implementation is a spinlock in the low bit of the control-block pointer
(`is_lock_free() == false`, Folder 07 §1.6's excerpt), and libc++ 21 doesn't provide it at all. Under 3 readers it cost
109–119 ns per read, aggregate, vs 1.8–2.1 ns for a hazard pointer (Folder 09 Listing 9.10).

**L7 principal defense.** "Fine for occasional reads. For hot reads: RCU/QSBR or hazard pointers to an immutable
snapshot, or a thread-local cached `shared_ptr` refreshed on a version change."
</details>

<details><summary><b>Q 30 ⚡ "Design a thread pool for short tasks at 64 cores"</b></summary>

**Initial prompt.** "Design a pool for millions of 1 µs tasks on a 64-core box."

**L5 textbook answer.** "One task queue with a mutex and a condition variable, 64 threads."

**Why L5 breaks.** A single queue gets slower with every added worker. Folder 10 Listing 10.4 already shows it at 4
workers: 59–124 ns per task with one worker, 169–248 ns with four. At 64 cores it becomes a lock convoy (⚠ not measured
here).

**L7 principal defense.** "Per-worker Chase-Lev deques (LIFO local, FIFO steal), an injection queue for external
submits, idle workers that park after a bounded spin, tasks without per-task allocation, and help-while-waiting for
joins. Measured: 9–23 ns per task at 4 workers with only 4–49 steals per million tasks."
</details>

---

## 6. Invariants checklist

- [ ] Every answer names the mechanism, the evidence, and the decision.
- [ ] Every concurrency claim maps to one of the litmus shapes (SB, MP, LB, IRIW) or a happens-before chain.
- [ ] Every performance claim comes with its conditions (threads, placement, platform).
- [ ] Every fix is a missing happens-before edge or a contention reduction, never a sleep.

## 7. References

- This KB, Folders [07](../07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/), [08](../08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/), [09](../09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/), [10](../10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/)
- A. Williams, *C++ Concurrency in Action*, 2nd ed., Manning 2019
- M. Herlihy, N. Shavit, *The Art of Multiprocessor Programming*, 2nd ed., Morgan Kaufmann 2020
- P. McKenney, *Is Parallel Programming Hard, And, If So, What Can You Do About It?*: <https://mirrors.edge.kernel.org/pub/linux/kernel/people/paulmck/perfbook/perfbook.html>
