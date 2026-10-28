# 01 · Debugging concurrency: ThreadSanitizer, ASan, UBSan, Helgrind and rr

> **Scope.** Folders 07–11 built concurrent code and proved it with stress runs, invariants and object code. This file
> is about what you do when that code is wrong in production. It answers three questions. What does each tool actually
> insert into your program, and so what can it see? Which class of concurrency bug does each tool find, and which does
> it miss by construction? What does each tool cost and need, on this KB's Windows toolchain and on Linux x86-64 and
> AArch64? The proofs are the instrumented object code of four one-line functions, a UBSan run on both compilers, and a
> race that ThreadSanitizer is *guaranteed* not to report, caught three other ways.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 12.1 | `sanitizer_codegen.cpp` | TSan turns each plain access into a `__tsan_read`/`__tsan_write` call and each atomic into a runtime call that carries its memory order (a read followed by a write in one block keeps only the write check). ASan puts a shadow-byte check before each load, at `(addr >> 3) + 0x7fff8000`. UBSan puts a `jo` and a handler call after each signed add. TSan receives fences as calls the runtime doesn't model, and annotations repair that. The same fences are *no instructions* on x86 but `dmb ish` / `dmb ishld` on ARM64 | asm, Clang 21 targeting x86-64 Linux: plain, `-fsanitize=thread`, `=address`, `=signed-integer-overflow`; the fence pair also for AArch64 |
| 12.2 | `ubsan_run.cpp` | signed overflow at run time: GCC/MinGW has only trap mode (`ud2`, exit `0xC000001D`, no message); zig's Clang ships a UBSan runtime that names the operation, the values, the type, the line and the stack | run, both compilers (thread id differs per run) |
| 12.3 | `race_stress.cpp` | check-then-act on a `std::atomic`: no data race, so TSan *cannot* report it. Plain stress found it in 0 of 300 rounds; yield injection in the window found it in about half of them; a latch-forced replay reproduces it every time; the CAS fix never overdraws | run, both compilers (timing-dependent counts) |

**Verification line.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (zig, libc++), `-O2 -Wall -Wextra -Wpedantic
-Werror -Wshadow -Wconversion -Wsign-conversion` for the runs. The instrumented assembly comes from Clang 21 at `-O3`
targeting `x86_64-linux-gnu` and `aarch64-linux-gnu` (compile only). The TSan and ASan *runtimes* don't exist for this
Windows toolchain (§1.10), so their run-time behaviour below is quoted from their documentation and source, and labelled
as such.

---

## 1. First principles

### 1.1 Two different bugs: a data race and a race condition

The C++ standard defines exactly one concurrency bug. **A data race** is two conflicting accesses (same memory location,
at least one a write) from different threads, *at least one of them not atomic*, with neither happening before the other
([intro.races]). It is undefined behaviour. A **race condition** is everything else: the program has no undefined
behaviour, but some interleaving of well-defined atomic operations breaks an invariant. That second kind is a logic bug,
and the language has no opinion on it.

The distinction decides which tool can help you:

| Bug class | Example in this KB | Data race? | Who finds it | Who cannot |
|---|---|---|---|---|
| unsynchronized plain access | `++counter` from two threads (Folder 07, Listing 7.1: an un-LOCKed `addl`) | yes | TSan, Helgrind/DRD, model checkers | ASan, UBSan, tests that only look at results |
| missing acquire/release on a flag guarding a plain payload | MP with a relaxed flag (Folder 07) | **yes, on the payload** | TSan, even on x86, where the hardware never shows the reordering | x86 stress tests (TSO hides it) |
| ordering bug among atomics only | SB pattern with release/acquire where seq_cst is needed (hazard publication, Folder 09) | no | model checkers (GenMC, CDSChecker, CppMem); litmus runs on ARM64 or POWER hardware | TSan, ASan, UBSan, x86 stress |
| check-then-act on atomics | Listing 12.3; `if (!q.empty()) q.pop()` style APIs | no | invariant checks plus stress, delay injection, deterministic replay, model checkers | TSan, by definition |
| lock-order inversion | A→B in one thread, B→A in another (Folder 08) | no | TSan's deadlock detector, Helgrind's lock-order graph, lock-hierarchy assertions | anything that waits for the deadlock to happen |
| use-after-free from premature reclamation | the Treiber-stack free without hazard pointers (Folder 09) | sometimes | ASan (quarantine), hazard-pointer/EBR debug modes | TSan reports only the racy part, if any |
| lost wakeup | predicate changed outside the mutex (Folder 08) | often yes (the predicate) | TSan, if the predicate is a plain variable; a timeout plus a stack dump otherwise | UBSan, ASan |
| counter overflow | `serving.load() + 1` computed in plain `int` (the atomic `fetch_add` itself wraps by definition) | no | UBSan (`signed-integer-overflow`) | TSan |

Everything below explains *why* each tool lands where the table puts it.

### 1.2 What ThreadSanitizer compiles into your code (Listing 12.1)

```cpp
// sanitizer_codegen.cpp - what -fsanitize=thread / address / undefined insert into ordinary code (compile-only view)
#include <atomic>

// Sanitizer detection: Clang spells it __has_feature(thread_sanitizer), GCC defines __SANITIZE_THREAD__.
#if defined(__has_feature)
#if __has_feature(thread_sanitizer)
#define KB_TSAN 1
#endif
#endif
#if defined(__SANITIZE_THREAD__)
#define KB_TSAN 1
#endif

#if defined(KB_TSAN)
extern "C" void __tsan_acquire(void* addr);   // both declared in <sanitizer/tsan_interface.h>
extern "C" void __tsan_release(void* addr);
#define KB_HAPPENS_BEFORE(p) __tsan_release(p)
#define KB_HAPPENS_AFTER(p) __tsan_acquire(p)
#else
#define KB_HAPPENS_BEFORE(p) ((void)0)
#define KB_HAPPENS_AFTER(p) ((void)0)
#endif

int g_plain = 0;
std::atomic<int> g_atomic{0};

void bump_plain() { ++g_plain; }                                          // TSan: one __tsan_write4 (see text)
void bump_atomic() { g_atomic.fetch_add(1, std::memory_order_relaxed); }  // TSan: __tsan_atomic32_fetch_add
int read_at(const int* p, long i) { return p[i]; }                        // ASan: shadow-byte check + report
int add(int a, int b) { return a + b; }                                   // UBSan: overflow check + handler

// Fence-based publication. TSan does not model std::atomic_thread_fence, so without the annotations it would
// report a race on g_payload; the annotations tell it about the happens-before edge the fences create.
int g_payload = 0;
std::atomic<bool> g_ready{false};

void fence_publish(int v) {
    g_payload = v;
    std::atomic_thread_fence(std::memory_order_release);
    KB_HAPPENS_BEFORE(&g_ready);
    g_ready.store(true, std::memory_order_relaxed);
}
int fence_consume() {
    while (!g_ready.load(std::memory_order_relaxed)) {
    }
    std::atomic_thread_fence(std::memory_order_acquire);
    KB_HAPPENS_AFTER(&g_ready);
    return g_payload;
}
```

The plain build, for reference (x86-64; the two fence functions also for AArch64 right after):

```text
_Z10bump_plainv:                   # bump_plain()
	movq	g_plain@GOTPCREL(%rip), %rax
	addl	$1, (%rax)
	retq

_Z11bump_atomicv:                  # bump_atomic()
	movq	g_atomic@GOTPCREL(%rip), %rax
	lock	addl	$1, (%rax)
	retq

_Z7read_atPKil:                    # read_at(int const*, long)
	movl	(%rdi,%rsi,4), %eax
	retq

_Z3addii:                          # add(int, int)
	leal	(%rdi,%rsi), %eax
	retq

_Z13fence_publishi:                # fence_publish(int)
	movq	g_payload@GOTPCREL(%rip), %rax
	movl	%edi, (%rax)
	movq	g_ready@GOTPCREL(%rip), %rax
	movb	$1, (%rax)
	retq

_Z13fence_consumev:                # fence_consume()
	movq	g_ready@GOTPCREL(%rip), %rax
.LBB5_1:
	movzbl	(%rax), %ecx
	cmpb	$1, %cl
	jne	.LBB5_1
	movq	g_payload@GOTPCREL(%rip), %rax
	movl	(%rax), %eax
	retq
```

```text
_Z13fence_publishi:                // fence_publish(int)
	adrp	x8, :got:g_payload
	adrp	x9, :got:g_ready
	ldr	x8, [x8, :got_lo12:g_payload]
	ldr	x9, [x9, :got_lo12:g_ready]
	str	w0, [x8]
	mov	w8, #1
	dmb	ish
	strb	w8, [x9]
	ret

_Z13fence_consumev:                // fence_consume()
	adrp	x8, :got:g_ready
	ldr	x8, [x8, :got_lo12:g_ready]
.LBB5_1:
	ldrb	w9, [x8]
	cmp	w9, #1
	b.ne	.LBB5_1
	adrp	x8, :got:g_payload
	ldr	x8, [x8, :got_lo12:g_payload]
	dmb	ishld
	ldr	w0, [x8]
	ret
```

The same source with `-fsanitize=thread`:

```text
_Z10bump_plainv:                   # bump_plain()
	pushq	%rbp
	pushq	%rbx
	pushq	%rax
	movq	24(%rsp), %rdi
	callq	__tsan_func_entry@PLT
	movq	g_plain@GOTPCREL(%rip), %rbx
	movl	(%rbx), %ebp
	addl	$1, %ebp
	movq	%rbx, %rdi
	callq	__tsan_write4@PLT
	movl	%ebp, (%rbx)
	callq	__tsan_func_exit@PLT
	addq	$8, %rsp
	popq	%rbx
	popq	%rbp
	retq

_Z11bump_atomicv:                  # bump_atomic()
	pushq	%rax
	movq	8(%rsp), %rdi
	callq	__tsan_func_entry@PLT
	movq	g_atomic@GOTPCREL(%rip), %rdi
	movl	$1, %esi
	xorl	%edx, %edx
	callq	__tsan_atomic32_fetch_add@PLT
	callq	__tsan_func_exit@PLT
	popq	%rax
	retq

_Z7read_atPKil:                    # read_at(int const*, long)
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	movq	%rsi, %rbx
	movq	%rdi, %r14
	movq	24(%rsp), %rdi
	callq	__tsan_func_entry@PLT
	leaq	(%r14,%rbx,4), %rdi
	callq	__tsan_read4@PLT
	movl	(%r14,%rbx,4), %ebx
	callq	__tsan_func_exit@PLT
	movl	%ebx, %eax
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	retq

_Z3addii:                          # add(int, int)
	leal	(%rdi,%rsi), %eax
	retq

_Z13fence_publishi:                # fence_publish(int)
	pushq	%r14
	pushq	%rbx
	pushq	%rax
	movl	%edi, %ebx
	movq	24(%rsp), %rdi
	callq	__tsan_func_entry@PLT
	movq	g_payload@GOTPCREL(%rip), %r14
	movq	%r14, %rdi
	callq	__tsan_write4@PLT
	movl	%ebx, (%r14)
	movl	$3, %edi
	callq	__tsan_atomic_thread_fence@PLT
	movq	g_ready@GOTPCREL(%rip), %rdi
	callq	__tsan_release@PLT
	movq	g_ready@GOTPCREL(%rip), %rdi
	movl	$1, %esi
	xorl	%edx, %edx
	callq	__tsan_atomic8_store@PLT
	callq	__tsan_func_exit@PLT
	addq	$8, %rsp
	popq	%rbx
	popq	%r14
	retq
.Ltmp2:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rbx
	callq	__tsan_func_exit@PLT
	movq	%rbx, %rdi
	callq	_Unwind_Resume@PLT

_Z13fence_consumev:                # fence_consume()
	pushq	%rbx
	movq	8(%rsp), %rdi
	callq	__tsan_func_entry@PLT
	movq	g_ready@GOTPCREL(%rip), %rbx
.LBB5_1:
	movq	%rbx, %rdi
	xorl	%esi, %esi
	callq	__tsan_atomic8_load@PLT
	testb	$1, %al
	je	.LBB5_1
	movl	$2, %edi
	callq	__tsan_atomic_thread_fence@PLT
	movq	g_ready@GOTPCREL(%rip), %rdi
	callq	__tsan_acquire@PLT
	movq	g_payload@GOTPCREL(%rip), %rbx
	movq	%rbx, %rdi
	callq	__tsan_read4@PLT
	movl	(%rbx), %ebx
	callq	__tsan_func_exit@PLT
	movl	%ebx, %eax
	popq	%rbx
	retq
.Ltmp5:                                     # landing pad (entered only via the LSDA)
	movq	%rax, %rbx
	callq	__tsan_func_exit@PLT
	movq	%rbx, %rdi
	callq	_Unwind_Resume@PLT
```

Reading the TSan build line by line:

* **Every plain access becomes a call that runs before it.** `read_at` calls `__tsan_read4(&p[i])` and then does the
  load. `bump_plain`'s `++g_plain` is a read and a write, but only `__tsan_write4` appears. The instrumentation pass
  (`llvm/lib/Transforms/Instrumentation/ThreadSanitizer.cpp`) drops a read check when a write to the same address follows
  in the same basic block with no call in between ("read-before-write (within same BB, no calls between)"). A write
  conflicts with every access that the read conflicts with, so the write check is enough. That's why the source comment
  says "one `__tsan_write4`" and not two calls.
* **Every atomic operation becomes a runtime call that carries its memory order.** `bump_atomic` is no longer `lock
  addl`. It is `__tsan_atomic32_fetch_add(&g_atomic, 1, 0)`, and `%edx = 0` is `memory_order_relaxed`. The runtime's
  order encoding is 0–5 for relaxed, consume, acquire, release, acq_rel and seq_cst. Look at `fence_publish`: the store
  passes `xorl %edx, %edx` (relaxed), the release fence passes `$3`, and in `fence_consume` the acquire fence passes `$2`.
  The runtime performs the operation *and* updates its happens-before state: a release merges the thread's vector clock
  into the location's sync object, and an acquire merges that back into the thread's. A relaxed operation does neither. That one rule is how
  TSan "knows" the C++ memory model.
* **`__tsan_func_entry(return address)` / `__tsan_func_exit`** maintain a shadow call stack, so a report can print both
  stacks. `fence_publish` gains a landing pad that calls `__tsan_func_exit` during unwinding. `add` touches no memory,
  so it's left alone: no entry, no exit, no checks.
* **The runtime** (not part of this toolchain; documented behaviour). It keeps shadow memory: for each 8 bytes of
  application memory, a few shadow cells recording recent accesses (which bytes, which thread, that thread's clock,
  read or write, atomic or not). Each new access is compared against those cells. If a conflicting access is not ordered
  before the current one by happens-before, it is a race and the runtime prints both stacks. The Clang documentation gives
  a typical slowdown of 5×–15× and a memory overhead of 5×–10×.

**The fence gap.** Look at `fence_publish` / `fence_consume` in the plain x86 build: no fence instructions at all. A
release fence and an acquire fence are compiler barriers on x86-TSO. On AArch64 they are `dmb ish` before the flag store
and `dmb ishld` after the flag load, and they are what makes the payload visible. TSan receives them as
`__tsan_atomic_thread_fence(3)` and `(2)`, and the runtime source then does this (`compiler-rt/lib/tsan/rtl/
tsan_interface_atomic.cpp`, `struct OpFence`):

```text
  static void Atomic(ThreadState *thr, uptr pc, morder mo) {
    // FIXME(dvyukov): not implemented.
    __sync_synchronize();
  }
```

It executes a real barrier but records **no** happens-before edge. So without help, TSan would see `g_payload = v` and
`return g_payload` ordered only by two *relaxed* operations on `g_ready`, and report a data race that does not exist.
GCC warns about exactly this at compile time. Compiling the same pattern with GCC 16.2 and `-fsanitize=thread` (verified
here; the link then fails for lack of a runtime) prints:

```text
warning: 'atomic_thread_fence' is not supported with '-fsanitize=thread' [-Wtsan]
```

The repair is in Listing 12.1. `KB_HAPPENS_BEFORE(&g_ready)` → `__tsan_release(&g_ready)` right before the publishing
store, and `KB_HAPPENS_AFTER(&g_ready)` → `__tsan_acquire(&g_ready)` right after the observing load. Those two calls
(declared in `<sanitizer/tsan_interface.h>`) tell the runtime about the edge the fences create. In the TSan build they
appear between the fence call and the relaxed store, and in a normal build they compile to nothing. The same two calls
annotate *any* synchronization TSan cannot see: a futex-based lock you wrote yourself (Folder 08), an `mprotect` or
`membarrier` trick, a message passed through a pipe. For a whole custom mutex the header also offers
`__tsan_mutex_create` / `__tsan_mutex_pre_lock` / `__tsan_mutex_post_lock` and friends. Detection uses both spellings,
because Clang's documentation says the `__has_feature(thread_sanitizer)` test "is deprecated" and that Clang will support
GCC's `__SANITIZE_THREAD__` style.

### 1.3 What TSan proves, and its blind spots

**It doesn't need the bad interleaving to happen.** Happens-before detection reports a race when two conflicting accesses
both *executed* without an ordering edge between them. Neither has to corrupt anything. One run in which the two accesses
merely occurred close enough (the older one still in the shadow cells) is enough. That's why TSan finds in seconds the
races that stress tests need weeks for.

**It checks the C++ model, not your CPU.** A relaxed flag guarding a plain payload never misbehaves on x86, because TSO
keeps stores in order. TSan still reports the payload race *on x86*, because relaxed creates no happens-before in its
model. This is the most valuable property for an ARM64 deployment: an x86 CI machine running TSan catches the data-race
class of ARM-only bugs.

**What it can't see, by construction:**

1. **Race conditions without a data race** (Listing 12.3). Every access is atomic, so nothing is reported.
2. **Ordering bugs among atomics only.** If every shared access is atomic and the bug is that the orders are too weak
   (SB with acquire/release), there is no data race to report. TSan also runs on real hardware and does not *simulate*
   weaker outcomes, so a stale value the x86 hardware never produces is never observed.
3. **Fences**, unless annotated (above).
4. **Synchronization in code it can't see**: uninstrumented libraries, inline assembly, raw futex syscalls, kernel
   objects. The documentation is blunt: TSan "generally requires all code to be compiled with `-fsanitize=thread`". The
   symptom is false positives (it misses the edge) or false negatives (it misses the access).
5. **Accidental happens-before.** If both threads also lock an unrelated mutex in between (a logging mutex, a test
   harness's `join`), TSan sees a genuine ordering edge and stays silent about a race that production, without the
   logging, will hit. Hidden races are the reason to run TSan with logging off and with the stress harness, not only the
   unit tests.
6. **Paths not executed.** It's dynamic: a race in code that didn't run in the test is invisible.

### 1.4 AddressSanitizer: the shadow byte (Listing 12.1, ASan view)

```text
_Z10bump_plainv:                   # bump_plain()
	movq	g_plain@GOTPCREL(%rip), %rax
	addl	$1, (%rax)
	retq

_Z11bump_atomicv:                  # bump_atomic()
	movq	g_atomic@GOTPCREL(%rip), %rax
	lock	addl	$1, (%rax)
	retq

_Z7read_atPKil:                    # read_at(int const*, long)
	pushq	%rax
	leaq	(%rdi,%rsi,4), %rdi
	movq	%rdi, %rax
	shrq	$3, %rax
	movzbl	2147450880(%rax), %eax
	testb	%al, %al
	jne	.LBB2_1
.LBB2_2:
	movl	(%rdi), %eax
	popq	%rcx
	retq
.LBB2_1:
	movl	%edi, %ecx
	andb	$7, %cl
	addb	$3, %cl
	cmpb	%al, %cl
	jl	.LBB2_2
	callq	__asan_report_load4@PLT
```

* `shrq $3` then `movzbl 2147450880(%rax)`: the shadow byte for address `a` is at `(a >> 3) + 0x7fff8000` (2147450880),
  the x86-64 Linux shadow offset. One shadow byte describes 8 application bytes. **0** means all 8 are addressable, and
  the fast path (`testb; jne`) falls straight through to the load. **1–7** means only the first *k* are addressable.
  **Negative** means poisoned: `0xfa` heap redzone, `0xfd` freed memory, `0xf1`–`0xf3` stack redzones, `0xf5` stack after
  return, `0xfc` container overflow.
* The slow path computes the last byte this 4-byte load touches, `(a & 7) + 3`, and compares it against the shadow value
  with a *signed* `jl`. A negative shadow byte therefore always fails, and a partial granule fails only past its end.
  `__asan_report_load4` never returns.
* `bump_plain` and `bump_atomic` aren't instrumented: an access to a scalar global at a constant offset is in bounds by
  construction, and ASan leaves it alone.

Concurrency bugs ASan finds: **use-after-free from premature reclamation**. A lock-free stack that frees a node another
thread is still reading (Folder 09) crashes rarely in production, but under ASan the freed block sits in a quarantine
(poisoned `0xfd`, not reused for a while), so the late read is reported with three stacks: the access, the `free`, and
the allocation. It also finds **stack use after return** in callbacks and coroutines that captured locals by reference
(enable it with `ASAN_OPTIONS=detect_stack_use_after_return=1`), and **container overflow** inside a vector's spare
capacity. libc++ annotates its containers under ASan, and libstdc++ does with `_GLIBCXX_SANITIZE_VECTOR`. The
documentation's typical slowdown is 2×.

**ASan and TSan can't share a binary**: both own the same shadow address range. Run them as separate CI jobs. UBSan
combines with either.

### 1.5 UndefinedBehaviorSanitizer (Listings 12.1 and 12.2)

```text
_Z10bump_plainv:                   # bump_plain()
	pushq	%rbp
	pushq	%rbx
	pushq	%rax
	movq	g_plain@GOTPCREL(%rip), %rbx
	movl	(%rbx), %esi
	movl	%esi, %ebp
	incl	%ebp
	jo	.LBB0_1
.LBB0_2:
	movl	%ebp, (%rbx)
	addq	$8, %rsp
	popq	%rbx
	popq	%rbp
	retq
.LBB0_1:
	leaq	.L__unnamed_1(%rip), %rdi
	movl	$1, %edx
	callq	__ubsan_handle_add_overflow@PLT
	jmp	.LBB0_2

_Z3addii:                          # add(int, int)
	movl	%edi, %eax
	addl	%esi, %eax
	jo	.LBB3_1
	retq
.LBB3_1:
	pushq	%rbx
	movl	%edi, %ecx
	movl	%esi, %edx
	leaq	.L__unnamed_2(%rip), %rdi
	movq	%rcx, %rsi
	movl	%eax, %ebx
	callq	__ubsan_handle_add_overflow@PLT
	movl	%ebx, %eax
	popq	%rbx
	retq
```

`add` becomes `addl; jo` with a cold block that calls `__ubsan_handle_add_overflow(&descriptor, lhs, rhs)`. The
descriptor (`.L__unnamed_2`) holds the source location and the type. Then the block *returns the wrapped result*: by
default UBSan reports and continues (`-fno-sanitize-recover=all` makes it abort). `bump_plain` is checked too, with
`incl; jo`, because `++` on a signed `int` can overflow. The cost on the hot path is one `jo` that is never taken. That
is why selected UBSan checks are cheap enough to keep in production builds, in trap mode.

Now run it: `scale(1073741824, 2)` is `INT_MAX + 1`.

```cpp
// ubsan_run.cpp - UndefinedBehaviorSanitizer at run time: signed overflow on a value the optimizer can't see
#include <climits>
#include <cstdio>

int scale(int quantity, int lot_size) { return quantity * lot_size; }   // the overflow the test feeds it

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    volatile int quantity = INT_MAX / 2 + 1, lot = 2;   // volatile: the compiler cannot fold or prove anything
    std::printf("computing %d * %d ...\n", quantity, lot);
    const int notional = scale(quantity, lot);          // UB: INT_MAX + 1; -fsanitize=undefined stops here
    std::printf("notional = %d (only printed if nothing stopped the program)\n", notional);
}
```

GCC 16.2 / MinGW (`-fsanitize=undefined -fsanitize-trap=all`; this MinGW build has no UBSan runtime library):

```text
computing 1073741824 * 2 ...
[exit code] 0xc000001d
```

Clang 21.1 / zig (`-fsanitize=undefined`; zig links its own UBSan runtime):

```text
computing 1073741824 * 2 ...
[stderr] thread 23144 panic: signed integer overflow: 1073741824 * 2 cannot be represented in type 'int'
[exit code] 0x3
```

* **Trap mode** replaces each handler call with `ud2`. The process dies at the faulting instruction with
  `STATUS_ILLEGAL_INSTRUCTION` (`0xC000001D`; `SIGILL` on Linux). There is no message, but a crash dump points at the
  exact instruction, and no runtime is needed. It's the right production mode.
* **Runtime mode** names the operation, both values and the type. The captured line above is the first one. Kept in
  full, the same run continues with `ubsan_run.cpp:5: … in scale`, the offending source line, `ubsan_run.cpp:11: … in
  main`, and the CRT frames, and then exits with code 3.

Concurrency-relevant UBSan checks: `signed-integer-overflow` on plain counter arithmetic. `std::atomic<int>::fetch_add`
itself wraps by definition ([atomics.types.int]), but `load() + 1` in `int` doesn't; Folder 11's ticket lock uses
`uint32_t` for that reason. `alignment` on atomics reached through `reinterpret_cast`. A misaligned atomic RMW that crosses a
cache line is a *split lock* on x86: it takes a bus lock and stalls every core, and Linux's split-lock detection can warn
or kill the process. On AArch64 a misaligned exclusive or LSE atomic is an alignment fault, apart from what FEAT_LSE2
relaxes inside a 16-byte block. Also `unreachable`, which catches a `std::unreachable()` that was reachable after all.

### 1.6 The race TSan cannot see (Listing 12.3)

```cpp
// race_stress.cpp - finding a race condition TSan cannot see: invariants, delay injection, deterministic replay
#include <atomic>
#include <latch>
#include <print>
#include <thread>
#include <vector>

// The bug: check-then-act on an atomic balance. Every access is atomic, so there is NO data race and TSan stays
// silent; the race is in the logic (two threads both pass the check before either subtracts).
std::atomic<long long> g_balance{0};

template <class Hook>
bool withdraw_buggy(long long amount, Hook between_check_and_act) {
    if (g_balance.load() >= amount) {
        between_check_and_act();
        g_balance.fetch_sub(amount);
        return true;
    }
    return false;
}
bool withdraw_fixed(long long amount) {   // check and act in ONE atomic step
    long long cur = g_balance.load();
    while (cur >= amount)
        if (g_balance.compare_exchange_weak(cur, cur - amount)) return true;
    return false;
}

// 4 threads drain a balance of 100 in steps of 1; a round "fails" if the balance ever ends below zero.
template <class Withdraw>
int failing_rounds(int rounds, Withdraw withdraw) {
    int bad = 0;
    for (int r = 0; r < rounds; ++r) {
        g_balance = 100;
        {
            std::vector<std::jthread> ts;
            for (int t = 0; t < 4; ++t)
                ts.emplace_back([&] {
                    while (withdraw()) {
                    }
                });
        }
        if (g_balance.load() < 0) ++bad;   // the invariant: never overdrawn
    }
    return bad;
}

int main() {
    constexpr int kRounds = 300;
    // 1. Plain stress: the window between check and act is a few nanoseconds.
    const int plain = failing_rounds(kRounds, [] { return withdraw_buggy(1, [] {}); });
    // 2. Delay injection: yield inside the window, which makes the bad interleaving common.
    const int injected = failing_rounds(kRounds, [] { return withdraw_buggy(1, [] { std::this_thread::yield(); }); });
    // 3. The fix under the same injected pressure (it has no window to inject into).
    const int fixed = failing_rounds(kRounds, [] {
        std::this_thread::yield();
        return withdraw_fixed(1);
    });
    std::println("{} rounds of 4 threads draining 100: overdrawn rounds  plain {:>3}  with yield injected {:>3}  fixed {:>3}",
                 kRounds, plain, injected, fixed);
    // 4. Deterministic replay: force both threads through the check before either acts.
    {
        g_balance = 1;
        std::latch both_checked(2);
        {
            std::jthread a([&] { (void)withdraw_buggy(1, [&] { both_checked.arrive_and_wait(); }); });
            std::jthread b([&] { (void)withdraw_buggy(1, [&] { both_checked.arrive_and_wait(); }); });
        }
        std::println("deterministic replay (balance 1, both threads pass the check first): final balance {} -> bug "
                     "reproduced: {}",
                     g_balance.load(), g_balance.load() < 0 ? "yes" : "no");
    }
    std::println("fixed version never overdrew under injection: {}", fixed == 0 ? "yes" : "NO");
}
```

GCC 16.2 / libstdc++:

```text
300 rounds of 4 threads draining 100: overdrawn rounds  plain   0  with yield injected 156  fixed   0
deterministic replay (balance 1, both threads pass the check first): final balance -1 -> bug reproduced: yes
fixed version never overdrew under injection: yes
```

Clang 21.1 / libc++:

```text
300 rounds of 4 threads draining 100: overdrawn rounds  plain   0  with yield injected 169  fixed   0
deterministic replay (balance 1, both threads pass the check first): final balance -1 -> bug reproduced: yes
fixed version never overdrew under injection: yes
```

* **TSan would report nothing.** `g_balance` is a `std::atomic`, so every access is atomic and there is no data race. The
  bug is that `load() >= amount` and `fetch_sub(amount)` are two atomic steps, and another thread can pass the check
  between them. This is the bug class TSan cannot see by definition (§1.1).
* **Plain stress didn't find it: 0 of 300 rounds on both compilers.** The window between check and act is a few
  nanoseconds, and four threads draining 100 units seldom line up inside it. This is the result that ships the bug.
* **Delay injection in the window found it in about half the rounds** (156 and 169 of 300 in the captured run; the
  counts vary from run to run). The `Hook` template parameter is a seam that costs nothing in production (an empty lambda inlines away)
  and that a test can fill with `yield()`, a sleep, or a random delay. Inject at every *gap between two synchronization
  operations* in the code under test.
* **Deterministic replay reproduced it every time.** A `std::latch(2)` placed between check and act forces *both* threads
  through the check before either acts: balance 1, two withdrawals succeed, final balance −1. A schedule forced like
  this is a regression test that fails reliably, which no amount of stress can promise.
* **The fix** makes check and act one atomic step: a CAS loop that retries with the fresh value (or a mutex). It has no
  window to inject into, and it never overdrew, even with the yield moved in front of every attempt.

The general method, in order of cost: write the **invariant** down and check it after every round (never overdrawn,
every item consumed once, the sum preserved). **Stress** with more threads than cores. **Inject delays** at the gaps.
**Force the schedule** you suspect. **Model-check** the core when the state space is small (§1.9).

### 1.7 Helgrind and DRD: dynamic binary instrumentation

Valgrind's two thread checkers need no recompilation. They translate the binary as it runs.

* **Helgrind** detects races by happens-before, as TSan does. It builds a **lock-order graph** and reports potential
  deadlocks from a run that never deadlocked, and it reports POSIX misuse: unlocking a mutex you don't hold, waiting on
  a condition variable with the wrong mutex, destroying a locked mutex. **DRD** is the lighter-memory sibling, with a
  similar scope.
* **Valgrind runs one thread at a time** (it serializes all threads under a global lock). It explores interleavings,
  but no two threads ever run in parallel, so weak-memory effects never occur. It is also far slower than TSan.
* **C++11 atomics** are not modelled as synchronization by default. Lock-free code, and libstdc++'s `shared_ptr`
  reference count, produce false positives. libstdc++'s debugging documentation describes the fix: define
  `_GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE(A)` / `_GLIBCXX_SYNCHRONIZATION_HAPPENS_AFTER(A)` to Valgrind's
  `ANNOTATE_HAPPENS_BEFORE` / `ANNOTATE_HAPPENS_AFTER` client requests (`<valgrind/helgrind.h>`).
* Use it when you can't recompile (a vendor binary), or for its POSIX-misuse checks. For your own code, TSan sees more,
  faster.

### 1.8 Record and replay: rr and WinDbg Time Travel Debugging

A concurrency bug you can't reproduce is a bug you can't fix. Record-and-replay turns "once a week" into "every time,
from the same recording".

**rr** (Linux) records every nondeterministic input: syscall results, signals, `rdtsc`. It uses the hardware counter of
retired conditional branches to place asynchronous events (signal delivery, preemption) at the exact instruction they
hit. All threads of the recorded process run on **one core**, so the interleaving is a sequence rr can replay exactly.
`rr replay` gives a gdb session that can run backwards. `reverse-continue` to the last hit of a breakpoint. A hardware
watchpoint on a corrupted field followed by `reverse-continue` stops at **the last write to it**, which answers "which
thread wrote this, and when?". `rr record --chaos` randomizes scheduling decisions to make rare interleavings appear.

Requirements, per its README: Linux ≥ 4.7, and an Intel CPU from Nehalem on, certain AMD Zen parts, or certain AArch64
cores (Neoverse N1, Apple M-series under Linux). In a VM, the hypervisor must virtualize the performance counters. On
AArch64, rr's 5.6.0 release notes state that **LL/SC exclusives are not supported: user code must use LSE atomics**.
Folder 07 showed what that means. A baseline ARMv8.0 build compiles `compare_exchange` into an `ldaxr`/`stlxr` loop,
while `-march=armv8.1-a` (or a CPU with LSE and outline atomics) uses `casal`. Build what you record with LSE.

The limit is also the point: one core means **no weak-memory reorderings are ever recorded**. rr finds *scheduling* bugs
(Listing 12.3's class, lost wakeups, use-after-free across threads), not the store-buffer outcome of Folder 07.

**WinDbg TTD** (Windows) records a user-mode process and replays it forwards and backwards. Microsoft's overview gives a
typical recording overhead of 10×–20× and trace files of several gigabytes for a few minutes. It needs an elevated
debugger, works in user mode only, and can't record protected processes. Its data model lets you *query* a trace (every
write to an address range, every call to a function) instead of stepping. It records each thread's execution and orders
threads relative to each other at its sequencing points. That is very good for "what did each thread do just before the
crash", but, like rr, it is not a memory-model oracle. This is the record-and-replay tool for this KB's own Windows
toolchain.

### 1.9 Model checkers and litmus tools: the only way to see what your hardware won't show

Stress, sanitizers and record-replay all observe executions your machine *produced*. A model checker enumerates the
executions the *memory model allows*.

| Tool | Checks | Use it for |
|---|---|---|
| **CppMem** (Cambridge) | every execution of a tiny C11 program under the C11 model | settling a litmus test (MP, SB, IRIW) in minutes |
| **herd7 / diy7 / litmus7** (INRIA) | litmus tests against formal models of x86-TSO, ARMv8, POWER and the Linux-kernel model; `litmus7` runs them on real hardware | "can this outcome happen on ARM64?", answered formally and then measured |
| **GenMC** (MPI-SWS) | stateless model checking of C/C++ programs under RC11 and IMM (a hardware-level model), with optimal exploration | the core of a lock-free structure, a few threads and operations |
| **CDSChecker** (UC Irvine) | C11 atomics model checker for concurrent data structures (OOPSLA 2013) | the same job; historically the first practical one |
| **Relacy** (Vyukov) | a C++ library: swap `std::atomic` for `rl::atomic` and it explores schedules, including relaxed behaviours | unit-testing a queue's memory orders at the source level |
| **loom** (Rust/tokio) | C11-model exhaustive exploration for Rust | the same idea, used to verify tokio and crossbeam-style code |

The workflow that finds ARM-only bugs without an ARM machine: extract the synchronization skeleton (Folder 09's SPSC
indices, Chase-Lev's `top`/`bottom` and fences), model-check it with 2–3 threads, then run the real code with
`litmus7` or a stress harness on Graviton or Apple silicon.

### 1.10 What this toolchain can run (verified)

| Sanitizer | GCC 16.2, MinGW-w64 | Clang 21.1 via zig, `x86_64-windows-gnu` | Linux x86-64 / AArch64 (GCC or Clang) | MSVC (documented, not tested here) |
|---|---|---|---|---|
| TSan | compiles and instruments, link fails: `cannot find -ltsan` | `unsupported option '-fsanitize=thread' for target 'x86_64-unknown-windows-gnu'` | full (Listing 12.1 is this target's object code) | none |
| ASan | link fails: `cannot find -lasan` | no runtime (`__asan_init` undefined at link) | full | `/fsanitize=address` |
| UBSan | trap mode only (`-fsanitize-trap=all`; plain `-fsanitize=undefined` fails with `cannot find -lubsan`) | works: zig's own runtime (Listing 12.2) | full | none |
| MSan | (not in GCC) | `unsupported option '-fsanitize=memory'` | Clang only | none |

So on this machine the sanitizer run is UBSan (both compilers), and TSan/ASan are read as object code. A real CI runs
them on Linux, which is exactly the layout of the blueprint in §3.1.

---

## 2. Evolution table

| Standard | What changed for debugging concurrent code | Where it shows up here |
|---|---|---|
| C++11 | The memory model: a data race is undefined behaviour ([intro.races]), and happens-before is defined. That precise definition is what TSan implements. `std::thread`, `std::atomic`, `std::mutex` | §1.1–1.3 |
| C++14 | `std::shared_timed_mutex`; nothing new for debugging | — |
| C++17 | `std::shared_mutex`; `hardware_destructive_interference_size` (Folder 07); `memory_order_consume` "temporarily discouraged" (P0371), so tools treat it as acquire; `[[nodiscard]]` | Folder 07 |
| C++20 | `std::latch` / `std::barrier`, the tools for *forcing* a schedule in tests (Listing 12.3's replay). `std::jthread` + `stop_token`, `std::atomic_ref`, `atomic::wait/notify`. `std::source_location` for cheap trace points. `constexpr` grows enough (allocation, virtual calls) that `static_assert` over real code becomes a compile-time UB detector, because UB is never a constant expression (true since C++11) | Listing 12.3; Folders 06, 08 |
| C++23 | `std::stacktrace` (`__cpp_lib_stacktrace`, **not shipped by either library here**, Listing 12.4); `std::unreachable()` and `[[assume]]` (UB by contract, which UBSan's `unreachable` check can catch); `std::expected` for error paths that don't unwind across threads | Listing 12.4 |
| C++26 | **Erroneous behaviour** (P2795): reading an uninitialized automatic variable is no longer UB. It is erroneous behaviour: the variable holds an implementation-chosen erroneous value, and the implementation may diagnose the read (`[[indeterminate]]` opts out). **Contracts** (P2900): `pre`, `post`, `contract_assert` with ignore / observe / enforce / quick-enforce semantics; GCC 16 defines `__cpp_lib_contracts` = 202502L, libc++ 21 doesn't (Listing 12.4). The **hardened standard library** (P3471): bounds and precondition checks on `operator[]`, `front()` etc. as contract violations. **`<debugging>`** (P2546): `std::breakpoint()`, `std::is_debugger_present()`; GCC 16 ships it (202403L). `std::hazard_pointer` / `rcu` are in the standard but not shipped by either library here | Listing 12.4; Folder 09 |

---

## 3. Production blueprints

### 3.1 The sanitizer matrix in CI

| Job | Build | Runs | Catches |
|---|---|---|---|
| `tsan` | Clang, `-O1 -g -fsanitize=thread`, **every** library rebuilt with it; logging compiled out | unit tests + the stress harness (more threads than cores, delay injection on); `TSAN_OPTIONS=halt_on_error=1:second_deadlock_stack=1` | data races, lock-order inversions, races on payloads guarded by too-weak atomics |
| `asan-ubsan` | `-O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer` | the same suite; `ASAN_OPTIONS=detect_stack_use_after_return=1:detect_leaks=1` | use-after-free from reclamation bugs, dangling captures in callbacks and coroutines, overflow, misaligned atomics |
| `release-trap` | production flags plus `-fsanitize=signed-integer-overflow,bounds -fsanitize-trap=all` | canary deployment | overflow in production, with a crash dump at the exact instruction |
| `arm64-stress` | release build on Graviton / Apple silicon, with an LSE build and a v8.0 (LL/SC) build | the stress harness and litmus tests | ordering bugs among atomics that x86 hides |
| `model-check` | the synchronization skeleton under GenMC or CDSChecker | 2–3 threads, bounded operations | everything the memory model allows, including outcomes no machine you own produces |

### 3.2 Check-then-act: buggy vs hardened

```cpp
// BUGGY: two atomic steps; another thread fits between them. TSan is silent (no data race).
if (balance.load() >= amount) { balance.fetch_sub(amount); return true; }

// HARDENED: one atomic step. A failed CAS refreshes `cur`, and the check is re-evaluated against the fresh value.
long long cur = balance.load();
while (cur >= amount)
    if (balance.compare_exchange_weak(cur, cur - amount)) return true;
return false;
```

The same shape covers `if (!map.contains(k)) map.insert(...)` (use `try_emplace`), `if (q.size()) q.pop()` (make `pop`
return `optional<T>`, Folder 11), and `if (!initialized) init()` (use `call_once` or a static, Folder 08).

### 3.3 Telling TSan about synchronization it cannot see

Listing 12.1's macros are the pattern. Detect TSan with both spellings, declare the two annotation functions (or include
`<sanitizer/tsan_interface.h>`), and compile them to nothing otherwise. Put `HAPPENS_BEFORE(obj)` *before* the operation
that publishes and `HAPPENS_AFTER(obj)` *after* the operation that observes, on the same address. Annotate the primitive
once, inside the primitive (your futex lock's `unlock`/`lock`, your fence-based queue's `push`/`pop`), never at the call
sites. And never suppress a report you haven't understood. A suppression hides every future race in that function, not
only the false one.

### 3.4 Making a race reproducible

1. A **hook parameter** at each gap between synchronization operations, compiled empty in production (Listing 12.3's
   `Hook`).
2. A **stress test** that injects `yield` / random sleeps through the hooks and checks the invariant every round.
3. A **forced schedule** with `std::latch` once the interleaving is known, kept as the regression test.
4. A **recording** (rr on Linux, TTD on Windows) of the failing run, then a watchpoint plus reverse-continue on the
   corrupted state.

---

## 4. Failure modes

| Symptom | Cause | Tool that shows it | Fix |
|---|---|---|---|
| TSan clean, invariant still broken in production | race condition on atomics (check-then-act) | invariant check plus delay injection; forced schedule | one atomic step (CAS loop) or a lock |
| TSan reports a race in fence-based code that model-checks fine | TSan doesn't model `atomic_thread_fence` (GCC says so: `-Wtsan`) | GCC's warning; reading the runtime's `OpFence` | `__tsan_release` / `__tsan_acquire` annotations, or operation-level orders under TSan |
| TSan reports races inside your own futex mutex | the syscall-based synchronization is invisible to it | — | annotate the primitive (`__tsan_mutex_*` or acquire/release) |
| bug disappears when logging is added | the logger's mutex creates happens-before and changes timing | TSan with logging compiled out; rr chaos mode | per-thread lock-free trace buffers instead of a locked logger |
| crash once a week, never under the debugger | scheduling-dependent bug | rr / TTD recording; delay injection | record, watchpoint, reverse-continue |
| correct on x86, corrupt on ARM64 | memory orders too weak: a data race on a payload, or an atomic-only ordering bug | TSan for the first; GenMC / herd7 / ARM64 stress for the second | the orders the model checker demands |
| rr won't record correctly on ARM64 | LL/SC exclusives in the code | rr's documented limitation | build with LSE (`-march=armv8.1-a` or later) |
| Helgrind floods reports on `shared_ptr` copies | atomics not modelled by Helgrind | — | `_GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE/AFTER` annotations, or use TSan |
| exit code `0xC000001D` / `SIGILL` with no message | UBSan trap mode fired (or a real `ud2` from `__builtin_trap`/`std::unreachable`) | the crash dump's faulting instruction | read the instruction's source line; fix the overflow |
| ASan and TSan in one build fails | both need the same shadow region | — | separate jobs |
| a deadlock is reported that never happened | lock-order inversion seen across two different moments | TSan's deadlock detector / Helgrind | a global lock order, `std::scoped_lock` for multi-lock sections (Folder 08) |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "TSan is clean. Is the code race-free?"</b></summary>

**Initial prompt.** "Our service passes the full test suite under ThreadSanitizer with zero reports. Can we say it has
no races?"

**L5 textbook answer.** "Yes. TSan detects races dynamically, so a clean run means no races."

**Why L5 breaks.** TSan finds *data races*, conflicting accesses with at least one non-atomic and no happens-before. It
says nothing about race conditions built entirely from atomic operations. Listing 12.3 is a check-then-act on a
`std::atomic` that overdraws the account in about half the rounds under delay injection, and by definition TSan reports
nothing for it. TSan also sees only executed paths, and an accidental happens-before (a shared logging mutex) can hide
a real data race in the tests that production then hits.

**L7 principal defense.** "A clean TSan run means no data races *on the executed paths, with these synchronization
edges*. Race conditions need invariants checked under stress, with delay injection at every gap between atomic steps,
and model checking of the synchronization core. I'd also run TSan with logging compiled out, so the logger's lock can't
hide anything."
</details>

<details><summary><b>Chain 2 🧊 "We only have x86 CI. How do we catch ARM64 bugs?"</b></summary>

**Initial prompt.** "We're moving to Graviton. All CI is x86. What catches the bugs that only appear on ARM64?"

**L5 textbook answer.** "Run TSan; it finds memory-ordering bugs."

**Why L5 corrupts memory on ARM64.** That is half right. TSan checks the C++ model, so a relaxed flag guarding a plain
payload is reported on x86 even though TSO never reorders it. But an ordering bug *among atomics only* (SB-style hazard
publication with release/acquire instead of seq_cst, Folder 09) has no data race, so TSan is silent. The x86 hardware
also never produces the outcome, so stress is silent too. On ARM64 the reader re-loads a stale pointer, the reclaimer
frees the node, and the reader touches freed memory.

**L7 principal defense.** "Three layers. TSan on x86 catches the data-race class, because it is model-based. Model
checking (GenMC under RC11 and IMM, or herd7 for the skeleton) catches what the model allows and x86 never shows.
Then the stress harness and `litmus7` on real ARM64, in both an LL/SC and an LSE build, because a v8.0 CAS loop and
`casal` fail differently. The lock-free core doesn't ship until all three agree."
</details>

<details><summary><b>Chain 3 🔥 "TSan reports a race in our Chase-Lev deque"</b></summary>

**Initial prompt.** "TSan reports a data race on the deque's buffer slot between `steal` and `push`. The algorithm is
from the paper and uses `seq_cst` fences exactly as published. Do we suppress it?"

**L5 textbook answer.** "It's a known false positive with lock-free code; add a suppression for that function."

**Why L5 breaks.** It *is* probably a false positive, but for a specific reason. The TSan runtime's fence handler is
literally `// FIXME(dvyukov): not implemented.` plus a real barrier: fences create no happens-before edge in TSan, so
every fence-synchronized access looks unordered. GCC even warns at compile time (`'atomic_thread_fence' is not supported
with '-fsanitize=thread' [-Wtsan]`). But a suppression covers the whole function, so the next real race introduced
there will be silenced as well.

**L7 principal defense.** "Fix the model, not the report. Annotate the edge the fences create, `__tsan_release(&slot)`
before the publishing operation and `__tsan_acquire(&slot)` after the observing one (Listing 12.1), compiled only
under TSan. Or, under `__SANITIZE_THREAD__`, give the operations the equivalent release/acquire orders so TSan sees the
edge directly. Then the deque is checked like everything else, and a new race in it will still be reported."
</details>

<details><summary><b>Chain 4 ⚠️ "Adding a printf makes the bug go away"</b></summary>

**Initial prompt.** "The corruption disappears whenever we add logging. How do you debug that?"

**L5 textbook answer.** "Add more logging until it reproduces, or run it in a debugger."

**Why L5 breaks.** A logger takes a lock (stdout's, or the logger's own). That lock creates happens-before between the
threads and shifts their timing by microseconds, which is exactly what makes a heisenbug go away. A debugger breakpoint
does the same, only more so. More logging pushes the bug further out of reach.

**L7 principal defense.** "Record without perturbing. rr (with `--chaos` to make the interleaving likely) or TTD on
Windows, then a watchpoint on the corrupted field and reverse-continue to its last writer. If I need tracing, it goes
into per-thread lock-free ring buffers stamped with a cycle counter, dumped on crash: no shared lock, so no new edge. And
TSan runs with logging compiled out, for the same reason."
</details>

<details><summary><b>Chain 5 🧊 "rr on Graviton"</b></summary>

**Initial prompt.** "We record flaky tests with rr on x86. Can we do the same on our ARM64 fleet?"

**L5 textbook answer.** "Yes, rr supports AArch64 now."

**Why L5 breaks.** rr's AArch64 port works on certain cores (Neoverse N1, Apple M-series), but its 5.6.0 release
notes are explicit: LL/SC exclusives are not supported, and user code must use LSE atomics. A baseline ARMv8.0 build
compiles every `compare_exchange` and `fetch_add` into an `ldaxr`/`stlxr` retry loop (Folder 07), which is exactly what
rr can't handle. rr also runs every thread on one core, so the ARM64 weak-memory bugs you moved to ARM to find are never
recorded.

**L7 principal defense.** "Build what we record with LSE (`-march=armv8.1-a` or a later target), and check the binary
for `ldxr`/`ldaxr` before trusting the recording. Use rr for *scheduling* bugs, which it reproduces perfectly. The
*ordering* bugs go to the model checker and to multi-core stress on ARM64, because single-core replay can't show them."
</details>

<details><summary><b>Chain 6 🔥 "Can we have one sanitizer job?"</b></summary>

**Initial prompt.** "CI time is expensive. Let's build once with `-fsanitize=address,thread,undefined`."

**L5 textbook answer.** "Sure, combining them saves a build."

**Why L5 breaks.** ASan and TSan both reserve and own the same shadow address range, so they can't be linked into one
binary. MSan likewise. Only UBSan composes with either. Even where a combination is allowed, the overheads multiply
(TSan's 5–15× plus ASan's 2×), and timing-sensitive stress tests stop exercising the windows you care about.

**L7 principal defense.** "Two jobs: TSan alone, and ASan + UBSan, each with every library rebuilt. A third, cheap
'release + trap' build keeps selected UBSan checks in production. Running the stress harness in the TSan job matters
more than running all the unit tests there, because TSan needs the concurrent paths executed."
</details>

<details><summary><b>Chain 7 ⚠️ "UBSan in production? It's a debug tool"</b></summary>

**Initial prompt.** "Someone proposes shipping with `-fsanitize=signed-integer-overflow`. Isn't that too slow?"

**L5 textbook answer.** "Sanitizers are for testing; production should never run them."

**Why L5 breaks.** The cost depends on the check and the mode. Listing 12.1 shows signed-overflow checking as one `jo`
after the add, never taken on the hot path. In trap mode the handler is a `ud2`, with no runtime and no message: the
process stops at the exact instruction (`0xC000001D` in Listing 12.2) with a dump. Android has shipped integer-overflow
sanitization in its media components for years for exactly this reason. Silently wrapping a ticket or sequence counter
in production is worse than a clean crash.

**L7 principal defense.** "Selected checks in trap mode (overflow on counters and sizes, array bounds) belong in
production for code that parses untrusted input or maintains sequence numbers. The full runtime, with recovery and
messages, stays in CI. We measure the overhead per component and keep the checks where it's noise."
</details>

<details><summary><b>Chain 8 🧊 "Helgrind says every shared_ptr copy is a race"</b></summary>

**Initial prompt.** "We can't rebuild a vendor library, so we use Helgrind. It reports thousands of races in
`shared_ptr` copies. Is libstdc++ broken?"

**L5 textbook answer.** "Probably a libstdc++ bug; suppress `std::shared_ptr`."

**Why L5 breaks.** Helgrind doesn't model C++11 atomics as synchronization by default. The reference count is atomic,
and the object's destruction is ordered after the last decrement by an acq_rel RMW, but Helgrind doesn't see that edge,
so the destructor's accesses look racy. Suppressing `shared_ptr` also hides real races on the pointed-to object.

**L7 principal defense.** "Tell the tool about the edge. libstdc++ provides `_GLIBCXX_SYNCHRONIZATION_HAPPENS_BEFORE`
and `_AFTER` for this; define them to Valgrind's `ANNOTATE_HAPPENS_BEFORE` / `_AFTER` when building our side. Valgrind
also serializes threads, so it finds scheduling bugs and never weak-memory ones. For our own code, TSan is faster and
sees more. Helgrind earns its place for uninstrumentable binaries and for its POSIX misuse checks."
</details>

<details><summary><b>Chain 9 🔥 "Find the deadlock before it happens"</b></summary>

**Initial prompt.** "A deadlock hits once a month in production. How do you find it before the next one?"

**L5 textbook answer.** "Add a watchdog that dumps all stacks when the service hangs."

**Why L5 breaks.** The watchdog gives you the stacks *after* the outage. A lock-order inversion is visible long before
it deadlocks: thread 1 took A then B on Monday, thread 2 took B then A on Tuesday. No run ever deadlocked, but the
lock-order graph has a cycle.

**L7 principal defense.** "Detect the cycle, not the hang. TSan's deadlock detector (on by default; `second_deadlock_stack=1`
for both stacks) and Helgrind's lock-order graph report the inversion from a run that completed normally. In
production, a debug-build lock hierarchy (each mutex has a level, and acquiring out of order asserts, Folder 08) makes
the rule mechanical, and `std::scoped_lock` acquires multi-lock sections deadlock-free. The watchdog stays, as the last
line."
</details>

<details><summary><b>Chain 10 🧊 "The bug won't reproduce on Windows"</b></summary>

**Initial prompt.** "Our team is on Windows and the bug is intermittent. TSan doesn't run here. What do we do?"

**L5 textbook answer.** "Use MSVC's sanitizer; it has ASan now."

**Why L5 breaks.** MSVC ships ASan (`/fsanitize=address`), which catches use-after-free and overflow but no data race.
There's no TSan for MSVC, and on this KB's toolchain neither MinGW GCC (`cannot find -ltsan`) nor zig's Clang
(`unsupported option '-fsanitize=thread'`) can run it (§1.10).

**L7 principal defense.** "Split the problem. Portable code gets a Linux TSan job, in a container or a CI runner. That
covers the data-race class, and a Linux VM is enough. Windows-specific code gets TTD: record the failing run, query
every write to the corrupted object, and walk back from the crash. Delay-injection hooks and forced schedules work on
every platform, and they turn the reproduction into a test. UBSan in trap mode works on both compilers here."
</details>

---

## 6. Invariants checklist

- [ ] Every shared mutable location is either atomic or protected by one identified lock; no "benign" data races.
- [ ] Every compound action on shared state (check-then-act, read-modify-write) is one atomic step or one critical section.
- [ ] Every gap between two synchronization operations in a concurrent component has a test hook that can inject delay.
- [ ] Every known bad interleaving is a forced-schedule regression test (latches), not only a stress test.
- [ ] TSan runs on every concurrent component, with logging compiled out and the stress harness enabled.
- [ ] Every synchronization TSan cannot see (fences, futexes, OS primitives) is annotated inside the primitive; there
      are no suppressions without a written reason.
- [ ] ASan + UBSan run as a separate job; selected UBSan checks run in trap mode in production.
- [ ] The lock-free core is model-checked (GenMC / CDSChecker / Relacy) and stress-tested on ARM64, with LL/SC and LSE
      builds.
- [ ] Lock acquisition order is a documented hierarchy, enforced in debug builds.

## 7. References

- Clang, ThreadSanitizer documentation: <https://clang.llvm.org/docs/ThreadSanitizer.html>
- Clang, AddressSanitizer documentation: <https://clang.llvm.org/docs/AddressSanitizer.html>
- Clang, UndefinedBehaviorSanitizer documentation: <https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html>
- TSan runtime, atomic and fence handlers: <https://github.com/llvm/llvm-project/blob/main/compiler-rt/lib/tsan/rtl/tsan_interface_atomic.cpp>
- TSan instrumentation pass: <https://github.com/llvm/llvm-project/blob/main/llvm/lib/Transforms/Instrumentation/ThreadSanitizer.cpp>
- TSan annotation interface: <https://github.com/llvm/llvm-project/blob/main/compiler-rt/include/sanitizer/tsan_interface.h>
- Google sanitizers wiki, ThreadSanitizer C++ manual: <https://github.com/google/sanitizers/wiki/ThreadSanitizerCppManual>
- GCC instrumentation options (`-fsanitize`, `-fsanitize-trap`): <https://gcc.gnu.org/onlinedocs/gcc/Instrumentation-Options.html>
- libstdc++ manual, debugging support (data race hunting): <https://gcc.gnu.org/onlinedocs/libstdc++/manual/debug.html>
- Valgrind Helgrind manual: <https://valgrind.org/docs/manual/hg-manual.html>; DRD manual: <https://valgrind.org/docs/manual/drd-manual.html>
- rr project: <https://rr-project.org/>; repository and release notes: <https://github.com/rr-debugger/rr>
- R. O'Callahan et al., "Engineering Record and Replay for Deployability", USENIX ATC 2017: <https://www.usenix.org/conference/atc17/technical-sessions/presentation/ocallahan>
- Microsoft, Time Travel Debugging overview: <https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/time-travel-debugging-overview>
- K. Serebryany, T. Iskhodzhanov, "ThreadSanitizer: data race detection in practice", WBIA 2009 (paper)
- K. Serebryany et al., "AddressSanitizer: A Fast Address Sanity Checker", USENIX ATC 2012: <https://www.usenix.org/conference/atc12/technical-sessions/presentation/serebryany>
- GenMC model checker: <https://github.com/MPI-SWS/genmc>
- B. Norris, B. Demsky, "CDSChecker: Checking Concurrent Data Structures Written with C/C++ Atomics", OOPSLA 2013 (paper)
- Relacy Race Detector: <https://github.com/dvyukov/relacy>
- herd7 / diy7 / litmus7 tool suite: <https://diy.inria.fr/>
- loom (Rust): <https://github.com/tokio-rs/loom>
- J. Alglave, L. Maranget, M. Tautschnig, "Herding Cats: Modelling, Simulation, Testing, and Data Mining for Weak Memory", TOPLAS 2014 (paper)
