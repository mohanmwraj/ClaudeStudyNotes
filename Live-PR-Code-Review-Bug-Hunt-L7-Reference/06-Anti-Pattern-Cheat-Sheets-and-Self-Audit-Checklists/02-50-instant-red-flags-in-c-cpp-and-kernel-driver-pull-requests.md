# 50 Instant Red Flags in C, C++ and Kernel-Driver Pull Requests

> **What this module is.** The minute-2 radar for modern C++, lock-free code, embedded firmware and Linux kernel drivers: 50 patterns you can see in a diff, each with the smell, why it fails in production, the one question to ask, the fix, and where it is proven. Twenty-two flags are demonstrated with compiled, probed code in this KB's PR07–PR09 (GCC 16 and Clang 21, with generated AArch64 and Cortex-M7 code). The kernel and C-safety flags cite the Linux kernel's own documentation, the C++ Core Guidelines and CWE. `redflags.py` implements the greppable ones and runs over PR07–PR09.

| Artifact | What it is | Verified |
|---|---|---|
| 50 flags (§2) | C01–C50 in six groups; 35 have scanner rules (C47 via the shared `T01`), 15 are judgment-only | in-KB flags link compiled findings; others cite primary docs |
| `redflags.py` (§3) | Shared with the Java sheet; the C/C++ rules run over the PR07–PR09 diffs and fixed sources | output, verified |
| Scanner report (§3) | Flags per PR, defects flagged, false alarms, flags on corrected code | output, verified |

**Verification.** `python src/redflags.py` over the PR07–PR09 diffs from the harness that built and probed them. On these three PRs every planted defect has a rule firing on its line (22/22). That is a *training-set* number, because the rules were derived from these PRs, and §3 says so. What generalizes: 15 false alarms on changed lines, 21 flags on the corrected code (relaxed loads of a thread's own index, `compare_exchange` in the correct tagged stack), and the 15 judgment-only flags that no regex can express.

---

## 0. Orientation

### 0.1 How to use this sheet

1. **Minute 2:** mark every smell as a question in the margin.
2. **Minute 10:** answer each with one hop: who else touches this memory, on which core or context, and with what ordering?
3. **Minute 20:** prove the survivors with a mechanism (and, where you can, the generated instruction), rank them by blast radius, and comment.

| Group | Flags | The question underneath |
|---|---|---|
| A. C++ lifetimes and ownership | C01–C09 | Who owns this, and does it outlive its referents? |
| B. Concurrency and the memory model | C10–C18 | What does this atomic *publish*, and to whom? |
| C. Embedded and interrupts | C19–C26 | Which views of memory exist (CPU cache, RAM, device), and who can preempt whom? |
| D. Integer and memory safety | C27–C36 | Can this arithmetic wrap, and can this copy exceed or leak? |
| E. Kernel and driver | C37–C46 | Which context is this (atomic, process, user pointer), and what may it do? |
| F. Process and evidence | C47–C50 | Is the evidence from the target, and is anything outside the diff completing the bug? |

### 0.2 What grep can and can't do (measured on PR07–PR09)

| Measured | Value | What it means |
|---|---|---|
| Planted defects | 22 | All F-findings of PR07, PR08 and PR09 |
| Flagged on their own line | 22 | Training-set recall: these rules were written from these defects |
| Other flags on changed lines | 19 | 15 false alarms plus 4 deleted-test flags (`T01`) |
| Flags on corrected code | 21 | The fixed ring still uses relaxed own-index loads (correct, PR08 D1) and `compare_exchange` (correct with tags) |
| Defects whose cause is outside the diff | 1 named (PR08 F7) | The mask line is flagged; the capacity `1000` that makes it fatal is an unchanged line |

---

## 1. First principles

1. **Lifetimes are the C++ bug class.** Most C++ Sev-1s are "this outlived that": coroutine frames vs arguments, pointers vs released slots, moved-from objects vs their resources.
2. **Atomics publish; plain memory follows.** An atomic store is only as good as the ordering that carries the *other* data with it. x86 hides missing ordering, and AArch64 doesn't.
3. **Hardware has more than one view of memory.** Caches, DMA engines and devices see different bytes at different times. Maintenance and barriers are the protocol between them.
4. **Context decides what's legal.** Interrupt context can't sleep or wait on the code it preempted. Atomic context can't allocate with `GFP_KERNEL`. User pointers can change between two reads.
5. **Arithmetic wraps silently.** Narrowing, unsigned wrap and multiplication overflow happen before any check that follows them.
6. **Evidence must come from the target.** A host test, an x86 run or a passing unit test isn't evidence for AArch64 ordering, D-cache coherency or interrupt timing.

---

## 2. The 50 flags

Legend: **[grep]** means `redflags.py` has a rule with this id. **[judgment]** means you find it by reading. Kernel API names are current mainline names, with older names noted where they changed.

### A. C++ lifetimes and ownership

#### C01 · A coroutine with reference parameters [grep]
**Smell.** `Task<T> f(const std::string& s, const Opts& o)`. **Why.** The frame stores references, and the body runs after the call expression ends, so temporaries are already destroyed (Core Guidelines CP.53). **Ask.** "Does anything the coroutine reads after its first suspension come by reference?" **Fix.** Take parameters by value. **Seen in:** [PR07 F1](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C02 · A handle-owning type with a defaulted destructor [grep]
**Smell.** `~Task() = default;` in a class holding a `coroutine_handle`, file descriptor or raw pointer. **Why.** Raw handles don't free themselves, so every object leaks its resource, and suspended coroutine frames keep their locals alive. **Ask.** "Who calls `destroy()`/`close()`/`delete`?" **Fix.** RAII: release in the destructor, move-only, and say what destroying a suspended task means. **Seen in:** [PR07 F2](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C03 · Swallowed exceptions or `value_or` defaults hiding failure [grep]
**Smell.** `void unhandled_exception() {}`, or `return opt.value_or(T{})` on a result path. **Why.** Failures become successful default values (a 0×0 thumbnail cached at the CDN). **Ask.** "How does the caller learn this failed?" **Fix.** Store `std::current_exception()` and rethrow, or return `expected<T, E>`. **Seen in:** [PR07 F3](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C04 · A move constructor that isn't `noexcept` [grep]
**Smell.** `T(T&& o) : …` without `noexcept`. **Why.** `std::vector` relocates with `move_if_noexcept`, so it *copies* on growth (227 block acquisitions for 100 pushes in PR07). **Ask.** "Can this move throw? If not, why isn't it `noexcept`?" **Fix.** `noexcept`, plus `static_assert(std::is_nothrow_move_constructible_v<T>)` (C.66). **Seen in:** [PR07 F4](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C05 · A move that leaves the source owning [grep]
**Smell.** `T(T&& o) : p_(o.p_) {}` with no reset of `o.p_`. **Why.** Both destructors release the same resource: a double free, or aliasing in a pool that trusts callers. **Ask.** "After the move, what does the source's destructor release?" **Fix.** `p_(std::exchange(o.p_, nullptr))`. **Seen in:** [PR07 F7](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C06 · Observers held as `weak_ptr`, never pruned [grep]
**Smell.** `std::vector<std::weak_ptr<T>>` with `push_back` and no erase. **Why.** Expired weak pointers keep the control block, and with `make_shared` the whole object's memory, alive: 0 of 1,000 viewers freed in PR07. **Ask.** "When are expired entries removed?" **Fix.** Prune on subscribe and notify, or use RAII subscription tokens. **Seen in:** [PR07 F5](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C07 · `shared_from_this()` captured into a member [grep]
**Smell.** `member_ = [self = shared_from_this()] { … };`. **Why.** The object owns a callable that owns the object: a reference cycle that is never freed. **Ask.** "Can this object ever reach use_count 0?" **Fix.** Capture `weak_from_this()` and lock inside the callback. **Seen in:** [PR07 F6](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md).

#### C08 · A pointer into a buffer escapes past the point it's released [grep]
**Smell.** `const T* v = &slots_[i]; head_.store(i + 1); return v;`. **Why.** The slot belongs to the producer as soon as it's handed back, so the caller reads memory being overwritten (PR08: a held tick changed from seq 0 to seq 8). **Ask.** "When does the owner get this memory back, relative to the last read?" **Fix.** Copy out before releasing, or split into `front()` and `pop()`. **Seen in:** [PR08 F6](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C09 · A reference or iterator held across a mutation that can reallocate [judgment]
**Smell.** `auto& first = v[0]; v.push_back(x); use(first);`, or erasing while iterating a `std::vector`/`unordered_map`. **Why.** Reallocation and rehashing invalidate references and iterators, so the code reads freed memory, often "working" until capacity is exceeded. **Ask.** "Can anything between taking this reference and using it grow or rehash the container?" **Fix.** Use indices, `reserve` with an asserted capacity, the `erase` return value, or a container with stable references. **Seen in:** cppreference, container iterator-invalidation rules.

### B. Concurrency and the memory model

#### C10 · A relaxed store that publishes data [grep]
**Smell.** `tail_.store(t + 1, std::memory_order_relaxed)` after writing a slot. **Why.** Relaxed gives no happens-before, so the slot write is a data race (UB). On AArch64 it compiles to a plain `str` and the consumer can see the index before the data, while x86 compiles both to `mov`. **Ask.** "What non-atomic data does this store make visible?" **Fix.** A release store paired with an acquire load. **Seen in:** [PR08 F1, F2](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C11 · A relaxed load of another thread's index [grep]
**Smell.** `tail_.load(relaxed)` on the consumer side, or `head_.load(relaxed)` on the producer side. **Why.** It's the other half of C10: without acquire, later reads of the slot can be satisfied early. Relaxed loads of a thread's *own* index are correct (the PR08 D1 decoy), which is why this rule is noisy. **Ask.** "Who writes this atomic: me or the other side?" **Fix.** Acquire on the other side's index; keep own-index loads relaxed. **Seen in:** [PR08 F1, F2](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C12 · Ordered comparison of wrapping indices [grep]
**Smell.** `if (h >= t)` on `uint32_t` sequence numbers. **Why.** After the wrap, `h >= t` says "empty" with N items queued, and the consumer stalls forever. **Ask.** "What happens at 2³²?" **Fix.** Compare only through unsigned subtraction (`t - h`); test seeded near the wrap. **Seen in:** [PR08 F3](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C13 · Atomics written by different cores on one cache line [grep]
**Smell.** `std::atomic<uint32_t> head_; std::atomic<uint32_t> tail_;` adjacent, with no `alignas`. **Why.** Every store moves the line between cores (false sharing), which is the cost lock-free code was meant to remove. **Ask.** "Which core writes each of these?" **Fix.** `alignas(128)` via a named constant (GCC warns that `hardware_destructive_interference_size` varies with `-mtune` in headers). **Seen in:** [PR08 F4](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C14 · A CAS loop on pointers with no ABA protection [grep]
**Smell.** `head_.compare_exchange_weak(top, top->next)` in a Treiber stack or free list. **Why.** If `top` is popped and pushed back between the read and the CAS, the CAS succeeds with a stale `next`, and two threads own one node. **Ask.** "What if the value changed and changed back?" **Fix.** A version tag in the CAS word (index + tag), hazard pointers or epochs. **Seen in:** [PR08 F5](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C15 · A mask that needs a power of two [grep]
**Smell.** `buf[i & (N - 1)]` with no `static_assert`. **Why.** With N = 1000, the mask clears bits and folds 1,000 indices onto 256 slots, overwriting unread data silently. **Ask.** "What is N in *every* instantiation, including the unchanged ones?" **Fix.** `static_assert(std::has_single_bit(N))`. **Seen in:** [PR08 F7](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C16 · A `try_*` result ignored [grep]
**Smell.** `ring.try_push(x);` as a statement. **Why.** The rejection path is silent: data is lost with no counter, and gap recovery never triggers. **Ask.** "What happens when this returns false?" **Fix.** `[[nodiscard]]`, and count and surface the rejections. **Seen in:** [PR08 F8](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

#### C17 · Hand-rolled double-checked locking [judgment]
**Smell.** `if (!ptr) { lock; if (!ptr) ptr = new T; }` with a plain or relaxed pointer. **Why.** Another thread can see the pointer before the object's construction is visible. Core Guidelines CP.110: "Do not write your own double-checked locking for initialization." **Ask.** "What orders the constructor's writes before the pointer's publication?" **Fix.** A function-local `static`, `std::call_once`, or acquire/release on the pointer. **Seen in:** C++ Core Guidelines CP.110.

#### C18 · `volatile` used for thread synchronization in C++ [grep]
**Smell.** `volatile bool ready;` shared between threads. **Why.** `volatile` gives neither atomicity nor inter-thread ordering. Core Guidelines CP.8: "Don't try to use `volatile` for synchronization"; CP.200: "Use `volatile` only to talk to non-C++ memory." **Ask.** "Is this memory-mapped hardware, or another thread?" **Fix.** `std::atomic` with explicit orders. (In C firmware, `volatile` for an ISR flag fixes the reload but not ordering, see C22.) **Seen in:** C++ Core Guidelines CP.8, CP.200.

### C. Embedded and interrupts

#### C19 · A DMA buffer that shares cache lines with other data [grep]
**Smell.** `struct { uint8_t seq; uint8_t dma_buf[24]; uint16_t errs; }`, "aligned" but not line-owning. **Why.** Maintenance works on whole 32-byte lines: invalidating the buffer discards the neighbours' updates (PR09: a STOP undone by a replay), and evicting a dirty neighbour overwrites received bytes. **Ask.** "Does this buffer own every line it touches?" **Fix.** Line-aligned start, size rounded up to whole lines, nothing else in those lines (or a non-cacheable MPU region). **Seen in:** [PR09 F1](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C20 · A DMA transfer without the matching cache maintenance [grep]
**Smell.** `dma_tx_start(buf)` right after the CPU writes `buf`, or reading an RX buffer with no invalidate. **Why.** The DMA reads RAM while the CPU's bytes sit in the cache: stale frames go out with valid CRCs. **Ask.** "Clean before TX, invalidate after RX: where are they?" **Fix.** `SCB_CleanDCache_by_Addr` before TX, `SCB_InvalidateDCache_by_Addr` after RX (never clean an RX buffer). **Seen in:** [PR09 F2](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C21 · A spinlock shared with an interrupt handler on one core [grep]
**Smell.** `spin_lock(&l)` in task code and in the ISR, with interrupts enabled in the task. **Why.** The ISR preempts the holder and spins on a lock that can't be released until the ISR returns. The result is a deadlock and a watchdog reset. **Ask.** "Can the ISR fire while the task holds this?" **Fix.** Mask the interrupt in the task (`spin_lock_irqsave` in Linux, PRIMASK on Cortex-M); no lock in the ISR on a single core. **Seen in:** [PR09 F3](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C22 · An ISR-written flag polled as a plain variable [grep]
**Smell.** `static bool done;` set in an ISR and `while (!done) {}` in task code. **Why.** The loop has no observable behavior, so the compiler may read the flag once. In PR09, GCC emits a jump-to-self (a hang) and Clang deletes the loop (flush returns early). **Ask.** "What forces a reload each iteration, and what orders the data behind the flag?" **Fix.** `atomic_bool` with release/acquire (or `volatile` for a pure event flag). **Seen in:** [PR09 F4](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C23 · Blocking or long work in interrupt context [judgment]
**Smell.** `printf`, `malloc`, mutex locks, flash writes or loops over buffers inside an ISR or hard-IRQ handler. **Why.** Interrupt context can't sleep, and long ISRs delay every lower-priority interrupt, missing deadlines and starving control loops. **Ask.** "What is this handler's worst-case execution time, and can anything in it block?" **Fix.** Acknowledge, capture minimal state, defer the rest (a task notification in an RTOS, threaded IRQs or workqueues in Linux). **Seen in:** Linux kernel, Unreliable Guide To Locking.

#### C24 · A tick or deadline compared across the wrap [grep]
**Smell.** `if (millis() > deadline)` with `deadline = now + timeout`. **Why.** Near the wrap the deadline is small while `now` is huge, so the failsafe trips 1 ms after a valid command (PR09), or misses entirely after a stall. **Ask.** "Is elapsed time computed by subtraction?" **Fix.** `now - start > timeout` (unsigned), `time_after()` in the kernel; tests seeded near the wrap. **Seen in:** [PR09 F6](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C25 · A struct `memcpy`'d as a wire format [grep]
**Smell.** `memcpy(frame + hdr, &rec, sizeof rec)`. **Why.** Padding and layout become the protocol: 12 bytes instead of 8, fields at the wrong offsets, and padding carrying stale memory. **Ask.** "Which document defines these bytes, and does `sizeof` match it?" **Fix.** Explicit little- or big-endian serialization, field by field; tests assert the protocol layout. **Seen in:** [PR09 F7](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C26 · No barrier between descriptor writes and the device doorbell [judgment]
**Smell.** Filling a DMA descriptor in coherent memory, then writing the device's doorbell register, with no barrier between. **Why.** The device can fetch the descriptor before the CPU's writes reach memory, so it processes garbage. **Ask.** "What orders these memory writes before the MMIO write?" **Fix.** `dma_wmb()`/`wmb()` (Linux), or `__DMB()`/`__DSB()` on Cortex-M, as the device's ordering model requires. **Seen in:** Linux kernel, memory-barriers documentation.

### D. Integer and memory safety

#### C27 · A narrowing cast in size arithmetic [grep]
**Smell.** `uint8_t total = (uint8_t)(4 + len + 2);`, often added to quiet `-Wconversion`. **Why.** The sum wraps before the bounds check: lengths 250–255 pass as 0–5, and a 250-byte `memcpy` hits an 18-byte struct. **Ask.** "Can this sum exceed the cast type, and why was the cast added?" **Fix.** Compute in `int`/`size_t` and compare before narrowing. **Seen in:** [PR09 F5](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C28 · Multiplication inside an allocation size [grep]
**Smell.** `kmalloc(n * sizeof(*p), …)`, `malloc(count * size)`. **Why.** The product wraps, so the allocation is small and the following writes overflow it. The kernel's deprecated-interfaces page says "Dynamic size calculations (especially multiplication) should not be performed in memory allocator" arguments. **Ask.** "Who bounds `n`?" **Fix.** `kmalloc_array`, `kcalloc`, `array_size()`, `struct_size()`; `calloc` in userspace. **Seen in:** Linux kernel, deprecated interfaces.

#### C29 · `strcpy`, `strcat`, `sprintf` or `gets` [grep]
**Smell.** Unbounded string functions. **Why.** "strcpy() performs no bounds checking on the destination buffer" (kernel docs), so any long input overflows. **Ask.** "What bounds the source?" **Fix.** `strscpy` (kernel), `snprintf`/`scnprintf` with checked results, or length-carrying string types. **Seen in:** Linux kernel, deprecated interfaces.

#### C30 · VLAs and `alloca` [grep]
**Smell.** `char buf[len];` with a runtime `len`, or `alloca(n)`. **Why.** Attacker-influenced stack size means stack exhaustion or a jump past guard pages, and the kernel notes VLAs also produce "much worse machine code." **Ask.** "What is the maximum of this size, and is it checked?" **Fix.** A fixed maximum with a check, or a heap allocation. **Seen in:** Linux kernel, deprecated interfaces.

#### C31 · Signed and unsigned lengths mixed [judgment]
**Smell.** `int len` from input compared with `sizeof`/`size_t`, or passed to `memcpy`. **Why.** A negative `int` becomes a huge `size_t` (CWE-195), so the check passes and the copy runs away. **Ask.** "Can this length be negative anywhere along the path?" **Fix.** Unsigned lengths from parse to use, with explicit range checks before conversion. **Seen in:** CWE-195.

#### C32 · Allocation results not checked [judgment]
**Smell.** `p = malloc(n); p->x = …` with no `NULL` check (or kernel `kmalloc` unchecked). **Why.** Under memory pressure this is a NULL dereference (CWE-690), and in the kernel, an oops. **Ask.** "What does this path do when allocation fails?" **Fix.** Check and unwind (see C42). **Seen in:** CWE-690.

#### C33 · Off-by-one bounds [judgment]
**Smell.** `for (i = 0; i <= len; i++)`, `if (idx <= ARRAY_SIZE(a))`. **Why.** One element past the end: a corrupted neighbour or a one-byte overflow (CWE-193). **Ask.** "Is the limit a count or a last index?" **Fix.** Half-open ranges (`<`), with the limit expressed as `ARRAY_SIZE`/`std::size`. **Seen in:** CWE-193.

#### C34 · `strncpy` assumed to terminate [grep]
**Smell.** `strncpy(dst, src, sizeof dst);` then `dst` used as a C string. **Why.** When `src` fills the buffer, no NUL is written, and later reads run past the end. The kernel deprecates `strncpy` for NUL-terminated destinations. **Ask.** "Is `dst` guaranteed to end in NUL?" **Fix.** `strscpy` (kernel), or `snprintf`, or explicit termination with a length check. **Seen in:** Linux kernel, deprecated interfaces.

#### C35 · A format string from a variable [grep]
**Smell.** `printf(buf)`, `syslog(LOG_ERR, msg)`. **Why.** `%n`/`%s` in data become reads and writes (CWE-134). **Ask.** "Can the data contain `%`?" **Fix.** `printf("%s", buf)`. **Seen in:** CWE-134.

#### C36 · Uninitialized bytes copied out [judgment]
**Smell.** A struct copied to the user, network or disk without zeroing padding or unset fields. **Why.** Stack or heap residue leaks (pointers, keys), defeating KASLR or exposing secrets (CWE-908). PR09's telemetry padding is the embedded version. **Ask.** "Is every byte of this object written before it leaves?" **Fix.** `memset`/`= {0}` before filling, or explicit serialization. **Seen in:** CWE-908, [PR09 F7](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

### E. Kernel and driver

#### C37 · User memory read twice, or sized by the user without validation [grep]
**Smell.** `copy_from_user(&hdr, …)` then `copy_from_user(buf, …, hdr.len)`, or a second fetch of the same field. **Why.** The user can change memory between the fetches (TOCTOU, CWE-367): the length you validated isn't the length you use. **Ask.** "Is every value used from user memory fetched exactly once and validated after that fetch?" **Fix.** Copy once into kernel memory, validate the copy, use only the copy. **Seen in:** CWE-367.

#### C38 · `GFP_KERNEL` in atomic context [grep]
**Smell.** `kmalloc(size, GFP_KERNEL)` under a spinlock, in an IRQ handler or in an RCU read section. **Why.** `GFP_KERNEL` may sleep, which isn't allowed in atomic context. The result is a "scheduling while atomic" splat or a deadlock. **Ask.** "Can this context sleep?" **Fix.** Allocate before taking the lock, or `GFP_ATOMIC`/`GFP_NOWAIT` with failure handling. **Seen in:** Linux kernel, memory allocation guide.

#### C39 · Sleeping while holding a spinlock [judgment]
**Smell.** `mutex_lock`, `msleep`, `copy_to_user` or `wait_event` between `spin_lock` and `spin_unlock`. **Why.** A sleeping holder blocks every CPU spinning on the lock, and preemption rules are violated. **Ask.** "Does anything inside this critical section block?" **Fix.** Use a mutex for sleepable sections, or move the blocking work outside the lock. **Seen in:** Linux kernel, Unreliable Guide To Locking.

#### C40 · Deleting list entries while iterating without `_safe` [grep]
**Smell.** `list_for_each_entry(pos, head, node) { list_del(&pos->node); kfree(pos); }`. **Why.** The iterator reads `pos->node.next` after `pos` is freed: a use-after-free. **Ask.** "Does the loop body remove or free `pos`?" **Fix.** `list_for_each_entry_safe`. **Seen in:** Linux kernel, kernel API (lists).

#### C41 · Lockless shared data without `READ_ONCE`/`WRITE_ONCE` [judgment]
**Smell.** A flag or pointer read in one context and written in another with plain accesses. **Why.** The compiler may tear, fuse or re-read the access, so checks and uses see different values. **Ask.** "Which contexts access this without a common lock?" **Fix.** `READ_ONCE`/`WRITE_ONCE`, plus the barriers the protocol needs (or a lock). **Seen in:** Linux kernel, memory-barriers documentation.

#### C42 · Error paths that leak references or memory [judgment]
**Smell.** Early `return -E…` after `get_device`, `kmalloc` or `request_irq` without the matching release. **Why.** Every failed probe or ioctl leaks, and refcount leaks keep devices from ever going away. **Ask.** "For each acquisition, where is its release on *every* exit?" **Fix.** Centralized `goto err_…` unwinding in reverse order (kernel coding style), or devres (`devm_*`). **Seen in:** Linux kernel, coding style.

#### C43 · Teardown without the `_sync` variants [grep]
**Smell.** `del_timer(&t)` / `cancel_work(&w)` followed by `kfree(obj)`. **Why.** The timer or work may be running on another CPU and touch the freed object: a use-after-free. **Ask.** "Can the callback still be running when we free?" **Fix.** `timer_delete_sync()` (older kernels: `del_timer_sync()`), `cancel_work_sync()`, and order teardown so that nothing re-arms it. **Seen in:** Linux kernel, Unreliable Guide To Locking.

#### C44 · `BUG_ON` for recoverable conditions [grep]
**Smell.** `BUG_ON(len > max)` on input validation. **Why.** It kills the machine (or the task) for a condition that should return an error. The kernel lists `BUG()` and `BUG_ON()` among deprecated interfaces. **Ask.** "Is this truly impossible, or merely unexpected?" **Fix.** `if (WARN_ON_ONCE(cond)) return -EINVAL;` and handle the error. **Seen in:** Linux kernel, deprecated interfaces.

#### C45 · Implicit `switch` fall-through [judgment]
**Smell.** A `case` without `break`/`return` and no `fallthrough;`. **Why.** Unintended execution of the next case; the kernel builds with `-Wimplicit-fallthrough` for this reason. **Ask.** "Intended?" **Fix.** The `fallthrough;` pseudo-keyword when intended, `break` when not. **Seen in:** Linux kernel, deprecated interfaces.

#### C46 · Raw kernel pointers in logs [grep]
**Smell.** `%px` in `printk`/`dev_info`. **Why.** It prints real addresses, which defeats KASLR for anyone who can read logs. The kernel's `%p` hashes by default for this reason. **Ask.** "Does anyone need the real address?" **Fix.** `%p` (hashed), or drop the pointer. **Seen in:** Linux kernel, deprecated interfaces.

### F. Process and evidence

#### C47 · Tests deleted, or sanitizer and target jobs dropped [grep: T01]
**Smell.** Removed `TEST(...)` or `static void test_…(void)`, or CI changes that drop ASan/TSan or the target build. **Why.** The deleted test is often the one that guarded the defect: PR07 `corrupt_input_throws`, PR08 `feed_handler_counts_drops`, PR09 `drops_duplicate_sequence`. **Ask.** "What did the old test assert, and what guarantees it now?" **Fix.** Restore it, or replace it with a stronger test linked in the PR. **Seen in:** [PR07](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md), [PR08](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md), [PR09](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C48 · Casts or pragmas added to silence warnings [judgment]
**Smell.** A new `(uint8_t)(…)`, `#pragma GCC diagnostic ignored`, or `(void)` on a result, in the same PR as new arithmetic or APIs. **Why.** The warning was a bug report. PR09's cast hid the exact wrap it warned about. **Ask.** "What did the warning say, and is it wrong?" **Fix.** Fix the cause; allow suppression only with a justification next to it. **Seen in:** [PR09 F5](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C49 · Ordering, cache or timing "verified" only on x86 or the host [judgment]
**Smell.** "Passes a two-thread test", "host tests green" for lock-free, DMA or ISR code. **Why.** x86-TSO hides missing acquire/release, and host builds have no D-cache, DMA or interrupt preemption. PR08's racy test passes on x86; PR09's defects need a model to appear. **Ask.** "Where was this run on the target, or under TSan?" **Fix.** TSan on x86, AArch64 runners, on-target runs with the cache enabled, and a host model for deterministic cases. **Seen in:** [PR08](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md), [PR09](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md).

#### C50 · A defect completed by an unchanged line [judgment]
**Smell.** A changed line whose correctness depends on a constant, type or instantiation outside the hunk: a mask and `N`, a shared annotation, an ISR elsewhere touching the same state. **Why.** Diff-only review approves code that is wrong in context: PR08's mask is fatal only because `TickRing` is `SpscRing<Tick, 1000>` on an unchanged line. **Ask.** "What outside this hunk must be true for this line to be correct?" **Fix.** Encode the assumption (`static_assert`, types), or change the context in the same PR. **Seen in:** [PR08 F7](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md).

---

## 3. The scanner, run over PR07–PR09

### 3.1 What it reports (output, verified)

```text
== pr07: 7 planted defects
flags on the PR's changed lines:
  C04  diff line 9    + Buffer(Buffer&& other) : data_(other.data_), size_(other.size_) {} // steal the block: no pixel 
  C05  diff line 9    + Buffer(Buffer&& other) : data_(other.data_), size_(other.size_) {} // steal the block: no pixel 
  C12  diff line 26   + template <typename T>
  C03  diff line 36   + void unhandled_exception() {} // errors surface as an empty result
  C02  diff line 43   + ~Task() = default;
  C03  diff line 47   + T result() const { return handle_.promise().value.value_or(T{}); }
  C02  diff line 74   + virtual ~Viewer() = default;
  C01  diff line 83   + Task<Thumbnail> render(const std::string& path, const Options& opts) {
  C06  diff line 109  + std::vector<std::weak_ptr<Viewer>> viewers_;
  C07  diff line 118  + retry_ = [self = shared_from_this()] { self->attempts_++; };
  T01  diff line 144  - TEST(renders_and_caches) {
  T01  diff line 167  - TEST(corrupt_input_throws) {
defects:
  F1  flagged by C01
  F2  flagged by C02
  F3  flagged by C03
  F4  flagged by C04, C05
  F5  flagged by C06
  F6  flagged by C07
  F7  flagged by C04, C05

== pr08: 8 planted defects
flags on the PR's changed lines:
  C16  diff line 14   + ring_.try_push(tick); // lock-free: never blocks the network thread
  C14  diff line 72   + if (head_.compare_exchange_weak(top, next, std::memory_order_acquire)) {
  C11  diff line 85   + s->next = head_.load(std::memory_order_relaxed);
  C14  diff line 86   + while (!head_.compare_exchange_weak(s->next, s, std::memory_order_release, std::memory_order_rel
  C11  diff line 122  + std::uint32_t t = tail_.load(std::memory_order_relaxed);
  C11  diff line 123  + std::uint32_t h = head_.load(std::memory_order_relaxed);
  C15  diff line 129  + slots_[t & (N - 1)] = value; // mask instead of %: no division on the hot path
  C10  diff line 130  + tail_.store(t + 1, std::memory_order_relaxed);
  C11  diff line 140  + std::uint32_t h = head_.load(std::memory_order_relaxed);
  C11  diff line 141  + std::uint32_t t = tail_.load(std::memory_order_relaxed);
  C12  diff line 142  + if (h >= t) {
  C08  diff line 147  + const T* value = &slots_[h & (N - 1)];
  C15  diff line 147  + const T* value = &slots_[h & (N - 1)];
  C10  diff line 148  + head_.store(h + 1, std::memory_order_relaxed);
  C11  diff line 156  + std::size_t size() const { return tail_.load(std::memory_order_relaxed) - head_.load(std::memory
  C13  diff line 163  + std::atomic<std::uint32_t> head_; // written by the consumer only
  C13  diff line 164  + std::atomic<std::uint32_t> tail_; // written by the producer only
  T01  diff line 182  - TEST(feed_handler_counts_drops) {
defects:
  F1  flagged by C10
  F2  flagged by C10
  F3  flagged by C12
  F4  flagged by C13
  F5  flagged by C14
  F6  flagged by C08, C15
  F7  flagged by C15
  F8  flagged by C16

== pr09: 7 planted defects
flags on the PR's changed lines:
  C19  diff line 20   + uint8_t dma_buf[UART_FRAME_LEN]; // the RX DMA writes each frame here
  C27  diff line 38   + uint8_t total = (uint8_t)(FRAME_HEADER_LEN + payload_len + FRAME_CRC_LEN);
  C28  diff line 70   + s_rx = hal_dma_alloc(sizeof *s_rx, DCACHE_LINE);
  C20  diff line 79   + hal_dma_rx_start(s_rx->dma_buf, UART_FRAME_LEN);
  C20  diff line 94   + hal_dma_rx_start(s_rx->dma_buf, UART_FRAME_LEN);
  C24  diff line 99   + if (hal_millis() > s_deadline_ms) {
  C20  diff line 109  + hal_dma_tx_start(s_tx_buf, UART_FRAME_LEN);
  C25  diff line 119  + memcpy(frame + FRAME_HEADER_LEN, t, sizeof *t); // one copy instead of field-by-field packing
  C21  diff line 122  + hal_spin_lock(&s_tx_lock);
  C21  diff line 133  + hal_spin_lock(&s_tx_lock);
  C22  diff line 145  + while (!s_tx_idle) {
  T01  diff line 205  - static void drops_duplicate_sequence(void) {
defects:
  F1  flagged by C19
  F2  flagged by C20
  F3  flagged by C21
  F4  flagged by C22
  F5  flagged by C27
  F6  flagged by C24
  F7  flagged by C25

== summary
PR     defects  flagged  judgment  other flags  flags on fixed code
pr07         7        7         0            5                    3
pr08         8        8         0            9                   15
pr09         7        7         0            5                    3
total       22       22         0           19                   21
```

### 3.2 How to read the numbers

| Observation | Number | Lesson |
|---|---|---|
| Defects flagged on their own line | 22 / 22 | Training-set recall: the C rules were written from these three PRs. Don't expect it on new code |
| False alarms on changed lines | 15 | Led by C11 (6): relaxed loads of a thread's *own* index, which are correct (PR08 D1); the rest are single hits such as C02 on `virtual ~Viewer() = default` |
| Flags on corrected code | 21 | C11 ×7 (own-index loads), C15 ×3 (masks, now `static_assert`ed), C20 ×3 (DMA starts, now with maintenance), C14 ×2 (the tagged CAS): the scanner can't tell PR08's fix from its bug |
| Cause outside the diff | PR08 F7 | C15 fires on the mask, but the fatal `N = 1000` is an unchanged line (C50); grep shows *where*, not *why* |
| Deleted tests | 4 | Three guarded a planted defect: PR07 `corrupt_input_throws` (F3), PR08 `feed_handler_counts_drops` (F8), PR09 `drops_duplicate_sequence` (F1) |

The rules are in the shared scanner listed in the [Java sheet](01-50-instant-red-flags-in-java-and-spring-pull-requests.md) §3.

---

## 4. Failure modes (using red-flag lists on systems code)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| "Use `seq_cst` everywhere" for C10/C11 | Blanket fix | Correct but slower on x86 and hides the protocol; pair release with acquire instead |
| "Add `volatile`" for C22 | Fixes the reload | Doesn't order the data behind the flag; in C++ threads, `volatile` isn't synchronization (CP.8) |
| Fixing C19 with `aligned(32)` | Start aligned | Size and neighbours still share lines; the buffer must own every line it touches |
| Disabling the D-cache "for DMA" | Works | Costs the whole system; hides the next maintenance bug |
| `BUG_ON` as validation | Crash on bad input | A user-triggerable machine crash; return errors (C44) |
| Trusting a host or x86 run | "Tests pass" | Missing ordering, cache effects and preemption don't exist there (C49) |
| Reviewing only the hunk | Misses C50 | The constant, ISR or instantiation that completes the bug is elsewhere |

---

## 5. Bar-raiser chains

<details><summary><b>Q1 · "memory_order_relaxed appears six times. Which ones are bugs?"</b></summary>

**Initial Prompt.** Distinguishing correct from incorrect relaxed atomics.

**L5 Answer.** "All of them; relaxed is dangerous."

**Why L5 Stalls.** Over-flags, and the fix becomes `seq_cst` everywhere.

**L7 Answer.** "Classify each by who writes the atomic and what data it publishes. A thread's loads of its *own* index (the producer reading `tail_`, the consumer reading `head_`) are correct relaxed. The store that hands a slot to the other side must be release, and the other side's load must be acquire. In PR08 that's two pairs, so four of the six change and two stay. On AArch64 the result is `stlr`/`ldar` on exactly those four accesses."

</details>

<details><summary><b>Q2 · "Why is a passing two-thread test on x86 weak evidence for lock-free code?"</b></summary>

**Initial Prompt.** Evidence quality.

**L5 Answer.** "Run it more times."

**Why L5 Stalls.** x86-TSO won't reorder stores with stores; more runs won't help.

**L7 Answer.** "x86 makes release and acquire free, so relaxed and release compile to the same `mov` and the test can't tell them apart. Use TSan, which models the C++ memory model rather than the CPU, AArch64 CI runners, and for the protocol itself, a model checker (CDSChecker, GenMC) or deterministic schedule points like PR08's pool hook."

</details>

<details><summary><b>Q3 · "C19 and C20 are both DMA. Why are they separate flags?"</b></summary>

**Initial Prompt.** Precision in cache reasoning.

**L5 Answer.** "Both mean 'do cache maintenance.'"

**Why L5 Stalls.** Different failure, different fix location.

**L7 Answer.** "C20 is the *operation*: clean before TX, invalidate after RX. C19 is the *layout*: even with perfect operations, a buffer that shares a line with other data gets its neighbours discarded on invalidate and its bytes overwritten on eviction. PR09 shows the second producing a replayed STOP command. Fixing operations without fixing layout leaves C19 live."

</details>

<details><summary><b>Q4 · "Is a spinlock in an interrupt handler always wrong?"</b></summary>

**Initial Prompt.** Context rules.

**L5 Answer.** "Yes."

**Why L5 Stalls.** Linux drivers take spinlocks in IRQ handlers routinely.

**L7 Answer.** "It's correct when every other taker disables local interrupts while holding it (`spin_lock_irqsave`), so the handler can only contend with *other* CPUs, which will release the lock. It's a deadlock when process context takes it with interrupts enabled on the same CPU, which is PR09's bug in firmware form. On a single-core MCU the lock adds nothing: masking the interrupt is the whole mechanism."

</details>

<details><summary><b>Q5 · "Which kernel flags would you automate, and how?"</b></summary>

**Initial Prompt.** Tooling for driver review.

**L5 Answer.** "checkpatch.pl."

**Why L5 Stalls.** checkpatch catches style and some deprecated APIs, but not context errors.

**L7 Answer.** "checkpatch for C29, C30, C34, C44, C45 and C46. Sparse annotations (`__user`, `__iomem`, lock context) for C37 and lock imbalance. Lockdep at runtime for C21, C39 and lock order. `CONFIG_DEBUG_ATOMIC_SLEEP` for C38 and C39. KASAN for C40, C43 and use-after-free. KCSAN for C41 data races. Coccinelle semantic patches for C28 (open-coded multiplication) and C42 (missing unwinding). Review attention goes to C26 and C50, which no tool sees."

</details>

<details><summary><b>Q6 · "A narrowing cast was added to silence -Wconversion. Accept it?"</b></summary>

**Initial Prompt.** Casts as signals.

**L5 Answer.** "If it compiles cleanly, fine."

**Why L5 Stalls.** The warning was the only thing pointing at the bug.

**L7 Answer.** "Ask what the warning said. In PR09 it said `int` to `uint8_t` may change value, which was exactly the wrap that let 250-byte payloads past the bounds check. My rule: a narrowing cast in size or length arithmetic needs a preceding check that makes it provably safe, adjacent to the cast. Otherwise compute in `int`/`size_t` and drop the cast."

</details>

<details><summary><b>Q7 · "How do you review C++ coroutine code quickly?"</b></summary>

**Initial Prompt.** A fast path for a newer feature.

**L5 Answer.** "Like normal functions."

**Why L5 Stalls.** Coroutines break the 'arguments outlive the call' assumption.

**L7 Answer.** "Four questions. Parameters: by value (C01)? The task type: who destroys the frame, and what does destroying a suspended one mean (C02)? Errors: `unhandled_exception` stores and rethrows (C03)? Captures: no capturing lambdas as coroutines (CP.51). Then the usual ownership checks on whatever the frame holds across suspensions. clang-tidy has `cppcoreguidelines-avoid-reference-coroutine-parameters` for the first."

</details>

<details><summary><b>Q8 · "Rank C21, C27, C37 and C43 by severity."</b></summary>

**Initial Prompt.** Prioritization across domains.

**L5 Answer.** "C27 first: buffer overflow."

**Why L5 Stalls.** Overflows are severe, but reachability matters.

**L7 Answer.** "C37 first if the double fetch is reachable from unprivileged userspace: it's a local privilege-escalation class. C27 next when the input comes from an external link (PR09's serial port), since that's memory corruption from outside the box. C43 next: a use-after-free on teardown, triggered by device removal or module unload, so exploitable when a user can trigger hot-unplug. C21 last of the four: a deadlock and watchdog reset is an availability incident, not a compromise. Unless it's in a safety function, in which case availability *is* safety."

</details>

---

## 6. Checklist (the minute-2 card)

- [ ] C++ lifetimes: coroutine parameters and frames (C01–C03), moves (C04, C05), observers and self-capture (C06, C07), escaping pointers and invalidation (C08, C09).
- [ ] Memory model: publish/consume pairs (C10, C11), wrap-safe indices (C12), padding (C13), ABA (C14), power-of-two masks (C15), ignored results (C16), DCLP and `volatile` (C17, C18).
- [ ] Embedded: DMA layout and maintenance (C19, C20), ISR locking and flags (C21, C22), ISR work (C23), tick wrap (C24), wire layout (C25), doorbell barriers (C26).
- [ ] C safety: narrowing (C27), allocation products (C28), string functions (C29, C34), stack sizes (C30), sign mixing (C31), unchecked allocations (C32), off-by-one (C33), format strings (C35), uninitialized copies (C36).
- [ ] Kernel: user memory (C37), atomic context (C38, C39), list deletion (C40), lockless accesses (C41), unwinding (C42), teardown (C43), `BUG_ON` (C44), fall-through (C45), pointer printing (C46).
- [ ] Evidence: deleted tests (C47), silenced warnings (C48), target vs host (C49), unchanged lines (C50).

---

## 7. References

- C++ Core Guidelines (CP.8, CP.51, CP.53, CP.110, CP.200, C.66). https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
- cppreference: `std::memory_order`. https://en.cppreference.com/w/cpp/atomic/memory_order
- cppreference: Containers library (iterator invalidation). https://en.cppreference.com/w/cpp/container
- The Linux Kernel: Deprecated Interfaces, Language Features, Attributes, and Conventions. https://www.kernel.org/doc/html/latest/process/deprecated.html
- The Linux Kernel: Unreliable Guide To Locking. https://www.kernel.org/doc/html/latest/kernel-hacking/locking.html
- The Linux Kernel: Memory Allocation Guide. https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html
- The Linux Kernel: Linux Kernel Memory Barriers. https://www.kernel.org/doc/html/latest/core-api/wrappers/memory-barriers.html
- The Linux Kernel: Linux kernel coding style. https://www.kernel.org/doc/html/latest/process/coding-style.html
- The Linux Kernel: Basic C Library Functions and list API. https://www.kernel.org/doc/html/latest/core-api/kernel-api.html
- CWE-195 Signed to Unsigned Conversion Error. https://cwe.mitre.org/data/definitions/195.html
- CWE-193 Off-by-one Error. https://cwe.mitre.org/data/definitions/193.html
- CWE-134 Use of Externally-Controlled Format String. https://cwe.mitre.org/data/definitions/134.html
- CWE-367 Time-of-check Time-of-use (TOCTOU) Race Condition. https://cwe.mitre.org/data/definitions/367.html
- CWE-690 Unchecked Return Value to NULL Pointer Dereference. https://cwe.mitre.org/data/definitions/690.html
- CWE-908 Use of Uninitialized Resource. https://cwe.mitre.org/data/definitions/908.html
- Arm CMSIS-Core: D-Cache functions. https://arm-software.github.io/CMSIS_5/Core/html/group__Dcache__functions__m7.html
- Within this KB: [PR07](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/01-pr07-cpp20-coroutine-dangling-reference-noexcept-move-and-weak-ptr-leak.md) · [PR08](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md) · [PR09](../04-C-and-Modern-CPP-Systems-and-Embedded-PR-Simulations/03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md) · [Java red flags](01-50-instant-red-flags-in-java-and-spring-pull-requests.md)
