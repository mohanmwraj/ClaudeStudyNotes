# 03 · C++20 coroutines in depth: symmetric transfer, awaitables, and async generators

> **Scope.** A C++20 coroutine is a function the compiler splits into a heap-allocated frame plus *resume* and
> *destroy* functions, driven by a promise type that you write. Nothing is scheduled, threaded or asynchronous
> unless your awaitables make it so. This file opens that machinery up. It traces exactly which awaitable members
> `co_await` calls, measures frame sizes and when the allocation disappears (HALO), crashes a coroutine chain with a
> stack overflow and fixes it with symmetric transfer (visible as a tail jump in the assembly), and builds an async
> generator on a deterministic event loop.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 10.5 | `coro_basics.cpp` | the `await_ready` → `await_suspend` → `await_resume` sequence; frames of 56 and 576 bytes (GCC); **Clang elides frames whose lifetime is local to the caller; GCC never does** | run, both compilers |
| 10.6 | `symmetric_transfer.cpp` | 1,000,000 synchronously-completing awaits: **nested `resume()` overflows the stack (0xC00000FD) on both compilers; returning a handle completes**; the resume function ends in a tail jump | run (both variants), both compilers; asm Clang x86-64/AArch64 and GCC |
| 10.7 | `async_generator.cpp` | an async generator that `co_await`s and `co_yield`s, on a virtual-time event loop: a pull model with no overlap between producer and consumer; C++23 `std::generator` in libstdc++ only | run, both compilers (deterministic trace) |

**Verification line.** As in file 01. Event-loop times are virtual ticks, so the trace is identical on every run.

---

## 1. First principles

### 1.1 What the compiler generates (Listing 10.5)

```text
  task f(args)                                 coroutine frame (heap, via promise_type::operator new)
  {                                            +---------------------------------------------------+
     ... co_await x ...                        | void (*resume)(frame*)   <- coroutine_handle points |
     co_return v;                              | void (*destroy)(frame*)     here                    |
  }                                            | promise_type promise                                |
                                               | copies of the parameters                            |
  becomes:                                     | locals that live across a suspension point          |
   1. allocate the frame, construct promise    | suspend-point index (which co_await we are at)      |
   2. ret = promise.get_return_object()        +---------------------------------------------------+
   3. co_await promise.initial_suspend()
   4. the body, where each  co_await x  is:
        auto&& a = x;   (or promise.await_transform(x))
        if (!a.await_ready()) {
            <save the suspend-point index>
            a.await_suspend(handle)  -> void:   suspend, return to whoever resumed us
                                     -> bool:   false = do not suspend after all, true = suspend
                                     -> handle: suspend, then TAIL-CALL handle.resume()  (symmetric transfer)
        }
        <resume point>  result = a.await_resume();
   5. co_return v  ->  promise.return_value(v);  co_await promise.final_suspend();
```

```cpp
// coro_basics.cpp - what co_await expands to, what a coroutine frame costs, and when the allocation disappears (HALO)
#include <atomic>
#include <coroutine>
#include <cstdlib>
#include <exception>
#include <new>
#include <print>
#include <string>
#include <utility>
#include <vector>

std::vector<std::string> g_trace;
std::atomic<long> g_frame_allocs{0};
std::size_t g_last_frame = 0;

// A lazily started task. Its promise allocates the frame through a counting operator new.
struct task {
    struct promise_type {
        int value = 0;
        std::coroutine_handle<> continuation = std::noop_coroutine();
        static void* operator new(std::size_t n) {
            g_frame_allocs.fetch_add(1);
            g_last_frame = n;
            if (void* p = std::malloc(n)) return p;
            throw std::bad_alloc();
        }
        static void operator delete(void* p) noexcept { std::free(p); }
        task get_return_object() { return task{std::coroutine_handle<promise_type>::from_promise(*this)}; }
        std::suspend_always initial_suspend() noexcept { return {}; }
        struct final_awaiter {
            bool await_ready() noexcept { return false; }
            std::coroutine_handle<> await_suspend(std::coroutine_handle<promise_type> self) noexcept {
                return self.promise().continuation;         // resume whoever awaited us (symmetric transfer)
            }
            void await_resume() noexcept {}
        };
        final_awaiter final_suspend() noexcept { return {}; }
        void return_value(int v) { value = v; }
        void unhandled_exception() { std::terminate(); }
    };
    std::coroutine_handle<promise_type> h;
    explicit task(std::coroutine_handle<promise_type> hh) : h(hh) {}
    task(task&& o) noexcept : h(std::exchange(o.h, {})) {}
    ~task() {
        if (h) h.destroy();
    }
    bool await_ready() const noexcept { return false; }
    std::coroutine_handle<> await_suspend(std::coroutine_handle<> caller) noexcept {
        h.promise().continuation = caller;
        return h;                                           // start the child right away, as a tail call
    }
    int await_resume() const noexcept { return h.promise().value; }
    int run() {                                             // drive a top-level task from normal code
        h.resume();
        return h.promise().value;
    }
};

// An awaitable that records the calls the compiler makes on it.
struct traced {
    const char* name;
    bool await_ready() {
        g_trace.push_back(std::string(name) + ".await_ready() -> false");
        return false;
    }
    bool await_suspend(std::coroutine_handle<> h) {
        g_trace.push_back(std::string(name) + ".await_suspend(h) -> false: do not suspend after all");
        (void)h;
        return false;                                       // bool overload: false = resume immediately
    }
    int await_resume() {
        g_trace.push_back(std::string(name) + ".await_resume() -> 7");
        return 7;
    }
};

task small_coro() { co_return co_await traced{"x"} + 1; }
task big_coro() {
    volatile char buffer[512] = {};                         // a local that lives across a suspension point
    const int v = co_await traced{"y"};
    co_return v + buffer[0];
}
task outer() { co_return co_await small_coro() + 100; }   // child created and awaited inside the parent

int main() {
    {
        task t = small_coro();
        g_trace.push_back("created: the body has not started (initial_suspend = suspend_always)");
        const int v = t.run();
        for (const auto& line : g_trace) std::println("  {}", line);
        std::println("small_coro() returned {}", v);
    }
    long a0 = g_frame_allocs.load();
    {
        task t = small_coro();
        (void)t.run();
    }
    std::println("frame of small_coro: {} heap allocation(s), {} bytes", g_frame_allocs.load() - a0, g_last_frame);
    a0 = g_frame_allocs.load();
    {
        task t = big_coro();
        (void)t.run();
    }
    std::println("frame of big_coro (512-byte local alive across co_await): {} allocation(s), {} bytes",
                 g_frame_allocs.load() - a0, g_last_frame);
    a0 = g_frame_allocs.load();
    int sum = 0;
    for (int i = 0; i < 1000; ++i) {
        task t = outer();
        sum += t.run();
    }
    std::println("1000 x outer() (each awaits a fresh small_coro): {} frame allocations (sum {})",
                 g_frame_allocs.load() - a0, sum);
}
```

Output (verified, GCC then Clang):

```text
  created: the body has not started (initial_suspend = suspend_always)
  x.await_ready() -> false
  x.await_suspend(h) -> false: do not suspend after all
  x.await_resume() -> 7
small_coro() returned 8
frame of small_coro: 1 heap allocation(s), 56 bytes
frame of big_coro (512-byte local alive across co_await): 1 allocation(s), 576 bytes
1000 x outer() (each awaits a fresh small_coro): 2000 frame allocations (sum 108000)
```

```text
  created: the body has not started (initial_suspend = suspend_always)
  x.await_ready() -> false
  x.await_suspend(h) -> false: do not suspend after all
  x.await_resume() -> 7
small_coro() returned 8
frame of small_coro: 0 heap allocation(s), 0 bytes
frame of big_coro (512-byte local alive across co_await): 0 allocation(s), 0 bytes
1000 x outer() (each awaits a fresh small_coro): 2000 frame allocations (sum 108000)
```

* **The trace** is the expansion above: `await_ready()` returned false, so `await_suspend(h)` was called; it returned
  `false`, which means "don't suspend after all", so `await_resume()` ran immediately in the same call.
* **Frames.** GCC allocated 56 bytes for `small_coro` (resume and destroy pointers, the promise, the awaiter, the
  index) and 576 for `big_coro`, whose 512-byte buffer lives across a `co_await`. A local that dies before the first
  suspension point doesn't need to be in the frame.
* **HALO (heap allocation elision).** Clang removed both allocations when `main` created, ran and destroyed the
  coroutine in one scope (0 allocations). In the `outer()` loop, where the child is awaited inside another coroutine,
  it still allocated both frames (2,000 allocations). GCC allocated every time. C++ gives no guarantee, so hot paths
  provide their own frame allocator through `promise_type::operator new`, as this listing does for counting (a free
  list, or an arena passed as a coroutine argument).

### 1.2 Symmetric transfer (Listing 10.6)

```cpp
// symmetric_transfer.cpp - a loop awaiting 1,000,000 synchronously-completing tasks: nested resume() vs symmetric transfer
#include <coroutine>
#include <cstdio>
#include <exception>
#include <utility>

// With -DNESTED the awaiters call resume() themselves: every hop is a nested native call that never returns
// until the whole chain is done. Without it, await_suspend RETURNS the next handle and the compiler resumes it
// with a tail call: the stack depth stays constant.
struct task {
    struct promise_type {
        std::coroutine_handle<> continuation;
        task get_return_object() { return task{std::coroutine_handle<promise_type>::from_promise(*this)}; }
        std::suspend_always initial_suspend() noexcept { return {}; }
        struct final_awaiter {
            bool await_ready() noexcept { return false; }
#ifdef NESTED
            void await_suspend(std::coroutine_handle<promise_type> self) noexcept { self.promise().continuation.resume(); }
#else
            std::coroutine_handle<> await_suspend(std::coroutine_handle<promise_type> self) noexcept {
                return self.promise().continuation;
            }
#endif
            void await_resume() noexcept {}
        };
        final_awaiter final_suspend() noexcept { return {}; }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }
    };
    std::coroutine_handle<promise_type> h;
    explicit task(std::coroutine_handle<promise_type> hh) : h(hh) {}
    task(task&& o) noexcept : h(std::exchange(o.h, {})) {}
    ~task() {
        if (h) h.destroy();
    }
    bool await_ready() noexcept { return false; }
#ifdef NESTED
    void await_suspend(std::coroutine_handle<> caller) noexcept {
        h.promise().continuation = caller;
        h.resume();                                   // nested call: this frame stays on the stack
    }
#else
    std::coroutine_handle<> await_suspend(std::coroutine_handle<> caller) noexcept {
        h.promise().continuation = caller;
        return h;                                     // symmetric transfer: the caller tail-calls h.resume()
    }
#endif
    void await_resume() noexcept {}
};

struct sync_root {                                    // a minimal eager wrapper so main() can run the loop
    struct promise_type {
        sync_root get_return_object() { return {}; }
        std::suspend_never initial_suspend() noexcept { return {}; }
        std::suspend_never final_suspend() noexcept { return {}; }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }
    };
};

long g_completed = 0;
task step() {
    ++g_completed;
    co_return;                                        // completes without ever suspending on I/O
}
sync_root run(long n) {
    for (long i = 0; i < n; ++i) co_await step();
    std::printf("completed %ld awaits\n", g_completed);
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("awaiting 1000000 tasks that complete synchronously (%s)\n",
#ifdef NESTED
                "nested resume()"
#else
                "symmetric transfer"
#endif
    );
    run(1'000'000);
}
```

Output (verified): symmetric transfer, GCC then Clang, then `-DNESTED`, GCC then Clang:

```text
awaiting 1000000 tasks that complete synchronously (symmetric transfer)
completed 1000000 awaits
awaiting 1000000 tasks that complete synchronously (symmetric transfer)
completed 1000000 awaits
awaiting 1000000 tasks that complete synchronously (nested resume())
[exit code] 0xc00000fd
awaiting 1000000 tasks that complete synchronously (nested resume())
[exit code] 0xc00000fd
```

The `step()` coroutine, Clang 21 `-O3` (x86-64, then AArch64), then GCC 16 (MinGW):

```asm
_Z4stepv:                          # step()
	pushq	%rbx
	movq	%rdi, %rbx
	movl	$32, %edi
	callq	_Znwm@PLT                            # operator new(unsigned long)
	leaq	_Z4stepv.resume(%rip), %rcx           # step() [clone .resume]
	movq	%rcx, (%rax)
	leaq	_Z4stepv.destroy(%rip), %rcx          # step() [clone .destroy]
	movq	%rcx, 8(%rax)
	movq	$0, 16(%rax)
	movq	%rax, (%rbx)
	movb	$0, 24(%rax)
	movq	%rbx, %rax
	popq	%rbx
	retq

_Z4stepv.resume:                   # step() [clone .resume]
	movq	g_completed@GOTPCREL(%rip), %rax
	addq	$1, (%rax)
	movq	$0, (%rdi)
	movb	$1, 24(%rdi)
	movq	16(%rdi), %rdi
	jmpq	*(%rdi)

_Z4stepv.destroy:                  # step() [clone .destroy]
	movl	$32, %esi
	jmp	_ZdlPvm@PLT                            # operator delete(void*, unsigned long)
```

```asm
_Z4stepv:                          // step()
	stp	x30, x19, [sp, #-16]!
	mov	w0, #32
	mov	x19, x8
	bl	_Znwm                                   // operator new(unsigned long)
	adrp	x8, _Z4stepv.resume                   // step() [clone .resume]
	add	x8, x8, :lo12:_Z4stepv.resume          // step() [clone .resume]
	adrp	x9, _Z4stepv.destroy                  // step() [clone .destroy]
	add	x9, x9, :lo12:_Z4stepv.destroy         // step() [clone .destroy]
	str	xzr, [x0, #16]
	stp	x8, x9, [x0]
	str	x0, [x19]
	strb	wzr, [x0, #24]
	ldp	x30, x19, [sp], #16
	ret

_Z4stepv.resume:                   // step() [clone .resume]
	adrp	x9, :got:g_completed
	mov	w11, #1
	ldr	x9, [x9, :got_lo12:g_completed]
	str	xzr, [x0]
	strb	w11, [x0, #24]
	ldr	x8, [x9]
	add	x10, x8, #1
	ldr	x8, [x0, #16]
	str	x10, [x9]
	ldr	x1, [x8]
	mov	x0, x8
	br	x1

_Z4stepv.destroy:                  // step() [clone .destroy]
	mov	w1, #32
	b	_ZdlPvm                                  // operator delete(void*, unsigned long)
```

```asm
_Z4stepP14_Z4stepv.Frame.actor:    # step(_Z4stepv.Frame*) [clone .actor]
	movzwl	24(%rcx), %eax
	testb	$1, %al
	je	.L2
	cmpw	$5, %ax
	ja	.L15
.L10:
	subw	$1, 26(%rcx)
	jne	.L1
	cmpb	$0, 28(%rcx)
	jne	.L16
.L1:
	ret
.L2:
	cmpw	$2, %ax
	je	.L8
	cmpw	$4, %ax
	je	.L10
	testw	%ax, %ax
	jne	.L3
	movl	$2, %edx
	addw	$1, 26(%rcx)
	movb	$0, 29(%rcx)
	movw	%dx, 24(%rcx)
	ret
.L8:
	movl	$4, %eax
	movb	$1, 29(%rcx)
	movq	$0, (%rcx)
	movw	%ax, 24(%rcx)
	movq	16(%rcx), %rcx
	addl	$1, g_completed(%rip)
	jmp	*(%rcx)
.L16:
	movl	$32, %edx
	jmp	_ZdlPvy                                # operator delete(void*, unsigned long long)
.L15:
	jmp	.L3

_Z4stepP14_Z4stepv.Frame.actor.cold: # step(_Z4stepv.Frame*) [clone .actor] [clone .cold]
	ud2

_Z4stepP14_Z4stepv.Frame.destroy:  # step(_Z4stepv.Frame*) [clone .destroy]
	movzwl	24(%rcx), %eax
	orl	$1, %eax
	movw	%ax, 24(%rcx)
	cmpw	$5, %ax
	ja	.L24
	subw	$1, 26(%rcx)
	jne	.L26
	cmpb	$0, 28(%rcx)
	jne	.L27
	ret
.L26:
	ret
.L27:
	movl	$32, %edx
	jmp	_ZdlPvy                                # operator delete(void*, unsigned long long)

_Z4stepP14_Z4stepv.Frame.destroy.cold: # step(_Z4stepv.Frame*) [clone .destroy] [clone .cold]
	ud2

_Z4stepv:                          # step()
	pushq	%rbx
	movq	%rcx, %rbx
	movl	$32, %ecx
	subq	$32, %rsp
	call	_Znwy                                 # operator new(unsigned long long)
	leaq	_Z4stepP14_Z4stepv.Frame.destroy(%rip), %rdx # step(_Z4stepv.Frame*) [clone .destroy]
	movq	.LC4(%rip), %xmm0
	movq	%rdx, %xmm1
	movl	$1, %edx
	movq	$0, 16(%rax)
	punpcklqdq	%xmm1, %xmm0
	movq	%rax, (%rbx)
	movw	%dx, 28(%rax)
	movl	$65538, 24(%rax)
	movups	%xmm0, (%rax)
	addq	$32, %rsp
	movq	%rbx, %rax
	popq	%rbx
	ret
```

* **The nested version** resumes the child inside `await_suspend` and, at the child's end, resumes the parent inside
  `final_suspend`'s `await_suspend`. Each hop is a nested native call that never returns, because the parent's loop
  immediately awaits the next child from inside that call. After a few thousand hops the 1 MB Windows stack is gone:
  `0xC00000FD`, stack overflow, on both compilers.
* **Symmetric transfer**: `await_suspend` *returns* the handle to run next, and the compiler resumes it with a **tail
  call**. Clang's `step()` resume clone ends with `jmpq *(%rdi)` (x86-64) and `br x1` (AArch64): jump to the
  continuation's resume function, which is the first word of its frame. GCC's `.actor` ends with `jmp *(%rcx)`. The
  stack depth stays constant: 1,000,000 awaits completed.
* The frame layout is visible in `step()`'s ramp: `operator new(32)`, then the resume pointer at offset 0, the destroy
  pointer at 8, the promise's continuation at 16, and the suspend-point index at 24.

### 1.3 Async generators (Listing 10.7)

```cpp
// async_generator.cpp - a coroutine that both co_awaits and co_yields, driven by a single-threaded virtual-time event loop
#include <coroutine>
#include <cstdint>
#include <exception>
#include <optional>
#include <print>
#include <queue>
#include <utility>
#include <vector>
#if __has_include(<generator>)
#include <generator>
#endif

// ---------- a deterministic event loop: timers in virtual ticks ----------
class Loop {
    struct Timer {
        std::uint64_t at, seq;
        std::coroutine_handle<> h;
        bool operator>(const Timer& o) const { return at != o.at ? at > o.at : seq > o.seq; }
    };
    std::priority_queue<Timer, std::vector<Timer>, std::greater<>> timers_;
    std::uint64_t now_ = 0, seq_ = 0;

public:
    std::uint64_t now() const { return now_; }
    void at(std::uint64_t t, std::coroutine_handle<> h) { timers_.push({t, seq_++, h}); }
    void run() {
        while (!timers_.empty()) {
            const Timer t = timers_.top();
            timers_.pop();
            now_ = t.at;
            t.h.resume();
        }
    }
};
inline Loop g_loop;

struct sleep_for {   // co_await sleep_for{n}: resume n virtual ticks later
    std::uint64_t ticks;
    bool await_ready() const noexcept { return ticks == 0; }
    void await_suspend(std::coroutine_handle<> h) const { g_loop.at(g_loop.now() + ticks, h); }
    void await_resume() const noexcept {}
};

// ---------- the async generator: co_yield hands a value to the awaiting consumer, co_await suspends freely --------
template <class T>
class async_gen {
public:
    struct promise_type {
        std::optional<T> current;
        std::coroutine_handle<> consumer;
        async_gen get_return_object() { return async_gen{std::coroutine_handle<promise_type>::from_promise(*this)}; }
        std::suspend_always initial_suspend() noexcept { return {}; }   // lazy: runs only when someone asks
        struct to_consumer {                                             // suspend, then resume the consumer
            bool await_ready() noexcept { return false; }
            std::coroutine_handle<> await_suspend(std::coroutine_handle<promise_type> self) noexcept {
                return self.promise().consumer;
            }
            void await_resume() noexcept {}
        };
        to_consumer yield_value(T v) {
            current = std::move(v);
            return {};
        }
        to_consumer final_suspend() noexcept {
            current.reset();                                             // end of sequence
            return {};
        }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }
    };
    struct next_awaiter {                                                // co_await gen.next() -> optional<T>
        std::coroutine_handle<promise_type> gen;
        bool await_ready() noexcept { return false; }
        std::coroutine_handle<> await_suspend(std::coroutine_handle<> consumer) noexcept {
            gen.promise().consumer = consumer;
            return gen;                                                  // run the producer until it yields
        }
        std::optional<T> await_resume() { return std::move(gen.promise().current); }
    };
    next_awaiter next() { return {h_}; }
    async_gen(async_gen&& o) noexcept : h_(std::exchange(o.h_, {})) {}
    ~async_gen() {
        if (h_) h_.destroy();
    }

private:
    explicit async_gen(std::coroutine_handle<promise_type> h) : h_(h) {}
    std::coroutine_handle<promise_type> h_;
};

struct detached {   // fire-and-forget top-level coroutine for the loop
    struct promise_type {
        detached get_return_object() { return {}; }
        std::suspend_never initial_suspend() noexcept { return {}; }
        std::suspend_never final_suspend() noexcept { return {}; }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }
    };
};

// A producer that must wait for its data (simulated I/O: 10 ticks per reading) and yields each reading.
async_gen<int> sensor(int readings) {
    for (int i = 1; i <= readings; ++i) {
        co_await sleep_for{10};
        std::println("  t={:>2}  producer: reading {} ready, yielding {}", g_loop.now(), i, i * i);
        co_yield i * i;
    }
    std::println("  t={:>2}  producer: done", g_loop.now());
}

detached consumer(async_gen<int> gen) {
    while (std::optional<int> v = co_await gen.next()) {
        std::println("  t={:>2}  consumer: got {}, processing for 3 ticks", g_loop.now(), *v);
        co_await sleep_for{3};
    }
    std::println("  t={:>2}  consumer: end of stream", g_loop.now());
}

#if defined(__cpp_lib_generator)
std::generator<std::uint64_t> fibonacci() {   // C++23 std::generator: synchronous, pull-based
    std::uint64_t a = 0, b = 1;
    for (;;) {
        co_yield a;
        a = std::exchange(b, a + b);
    }
}
#endif

int main() {
    std::println("async generator on a virtual-time event loop:");
    consumer(sensor(3));
    g_loop.run();
#if defined(__cpp_lib_generator)
    std::print("std::generator (C++23), first 10 Fibonacci numbers:");
    int n = 0;
    for (std::uint64_t f : fibonacci()) {
        if (n++ == 10) break;
        std::print(" {}", f);
    }
    std::println("");
#else
    std::println("std::generator (C++23): not provided by this library");
#endif
}
```

Output (verified, GCC; Clang prints the same trace and "std::generator: not provided by this library"):

```text
async generator on a virtual-time event loop:
  t=10  producer: reading 1 ready, yielding 1
  t=10  consumer: got 1, processing for 3 ticks
  t=23  producer: reading 2 ready, yielding 4
  t=23  consumer: got 4, processing for 3 ticks
  t=36  producer: reading 3 ready, yielding 9
  t=36  consumer: got 9, processing for 3 ticks
  t=39  producer: done
  t=39  consumer: end of stream
std::generator (C++23), first 10 Fibonacci numbers: 0 1 1 2 3 5 8 13 21 34
```

* **Two kinds of suspension in one coroutine.** `co_await sleep_for{10}` suspends the producer until the loop's timer
  fires. `co_yield v` suspends it *and* transfers to the consumer (symmetric transfer from `yield_value`'s awaiter).
* **It is pull-based.** The producer starts reading 2 only when the consumer asks for the next value (t = 13), so
  reading 2 is ready at t = 23, not t = 20: no overlap between producing and consuming. Overlap requires a buffer: a
  channel the producer fills ahead, bounded so it can't outrun the consumer forever.
* **`std::generator` (C++23)** is the synchronous counterpart: an input range of yielded values, with recursive
  composition through `std::ranges::elements_of`. libstdc++ 16 provides it; libc++ 21 does not.

---

## 2. Evolution table

| Feature | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| coroutines | — | — | Coroutines TS (N4680) | `co_await`/`co_yield`/`co_return`, `<coroutine>`, symmetric transfer (P0913), `noop_coroutine` | `std::generator` (P2502), `std::ranges::elements_of` | coroutine-based senders interop: awaitable senders, `as_awaitable`, `with_awaitable_senders` (P2300) |
| library task types | — | — | — | none in the standard (cppcoro, folly::coro, libunifex) | — | `std::execution::task` (P3552) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| chains of awaits that may complete synchronously | `await_suspend` calls `h.resume()` (stack overflow, Listing 10.6) | return the next `coroutine_handle` (symmetric transfer) |
| hot-path coroutine allocation | assume HALO (GCC never does it; Clang only sometimes) | `promise_type::operator new` with a free list or an arena |
| coroutine parameters | `task process(const std::string& s)` called with a temporary | take parameters by value; they are copied into the frame |
| coroutine lambdas | `[&]() -> task { co_await ...; }` stored and resumed later | no captures (pass by value as parameters), or keep the lambda alive longer than the coroutine |
| eager tasks | `initial_suspend = suspend_never`, continuation attached later (a race if the task completes on another thread) | lazy tasks + symmetric transfer, or an atomic handshake for eager ones |
| where a coroutine resumes | assume "the same thread" after `co_await` | resume where the awaited operation completes, unless an awaitable reschedules; make it explicit (`co_await schedule(pool)`) |
| async generator feeding slow I/O | pull-based generator (no overlap) | a bounded channel between producer and consumer |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| stack overflow deep inside resume calls | nested `resume()` instead of symmetric transfer | stack trace shows repeating `resume` frames |
| use-after-free after a `co_await` | reference parameter or reference capture outliving its referent | ASan; by-value parameters |
| `thread_local` values change across a `co_await` | the coroutine resumed on another thread | log thread ids before and after the await |
| allocation profile shows millions of tiny frames | no HALO (GCC, or non-local lifetimes) | count `promise_type::operator new` (Listing 10.5) |
| a task's continuation never runs | eager task completed before the awaiter registered | lazy start, or atomic exchange on the continuation |
| `co_await` inside `catch` / destructor rejected | language rules (`co_await` not allowed in handlers or destructors) | restructure: capture `exception_ptr`, await after the handler |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Coroutines are zero-overhead, right?"</b></summary>

**Initial prompt.** "Our team says C++ coroutines are zero-cost like stackless state machines. Do they allocate?"

**L5 textbook answer.** "No, they're stackless, so there's nothing to allocate."

**Why L5 breaks.** Stackless means the frame isn't a stack; the frame still exists, and by default it's heap-allocated
through `promise_type::operator new` or global `new`. Listing 10.5: GCC allocated 56 bytes for a tiny coroutine and 576
for one keeping a 512-byte local across a suspension point, every time. Clang's HALO removed the allocation only when
the coroutine's whole lifetime was visible and local to the caller (0 allocations in `main`, 2,000 in the nested loop).

**L7 principal defense.** "Coroutines are zero-overhead compared to the hand-written state machine *plus its heap
allocation*. For hot paths: a custom `promise_type::operator new` (pool or arena), keeping large locals out of the
suspension span, and measuring frame counts and sizes. Treat HALO as a bonus, never a guarantee."
</details>

<details><summary><b>Chain 2 🔥 "Our coroutine chain crashes with a stack overflow"</b></summary>

**Initial prompt.** "A loop `co_await`s a million cached reads that complete synchronously. It crashes with a stack
overflow. There's no recursion in our code. Why?"

**L5 textbook answer.** "Coroutines use the stack for each await; increase the stack size."

**Why L5 breaks.** The recursion is in the awaiters. If `await_suspend` calls `child.resume()` and the child's final
awaiter calls `parent.resume()`, every hop nests one more native call, and the parent's loop keeps awaiting from
inside the latest one (Listing 10.6, `-DNESTED`: `0xC00000FD` on both compilers). A bigger stack only moves the crash.

**L7 principal defense.** "Symmetric transfer: `await_suspend` returns the `coroutine_handle` to run next, and the
compiler resumes it with a tail call (`jmpq *(%rdi)` / `br x1` / `jmp *(%rcx)` in the asm above), so stack depth stays
constant: a million awaits completed. That's why P0913 added the handle-returning `await_suspend` to C++20, and why every
serious task type uses it."
</details>

<details><summary><b>Chain 3 ⚡ "What can await_suspend return?"</b></summary>

**Initial prompt.** "What are the three return types of `await_suspend`, and when do you use each?"

**L5 textbook answer.** "It returns void; the coroutine suspends."

**Why L5 breaks.** There are three forms. **`void`**: suspend unconditionally and return to whoever resumed us. **`bool`**:
`true` suspends; `false` means "the operation already completed, continue now", as in Listing 10.5's trace, which
avoids a resume round-trip when an operation finishes synchronously. **`coroutine_handle<>`**: suspend and transfer
control to that coroutine with a tail call (symmetric transfer); returning `std::noop_coroutine()` means "suspend and
return to the resumer".

**L7 principal defense.** "Handle-returning for continuations between coroutines (constant stack); bool for
operations that may complete immediately (`try_lock`, cached results); void for registering with an external event
source. And `await_ready` returns true for the 'already done' fast path, so the frame state isn't even saved."
</details>

<details><summary><b>Chain 4 🔥 "Pass the string by const reference to the coroutine"</b></summary>

**Initial prompt.** "`task<void> log_async(const std::string& msg) { co_await flush_queue(); write(msg); }` called as
`log_async("connected: " + host);` sometimes writes garbage. Why?"

**L5 textbook answer.** "A race on the string; add a mutex."

**Why L5 corrupts memory on ARM64.** The parameter copied into the frame is the *reference*. The temporary string dies
at the end of the full-expression that called `log_async`, but the coroutine suspends at `co_await flush_queue()` and
resumes later, reading the destroyed string: a use-after-free on any architecture. The same happens with lambda
coroutines that capture by reference, and with lambdas whose closure object is destroyed while their coroutine is
suspended.

**L7 principal defense.** "Coroutine parameters by value (`std::string msg`), because the frame copies them, and no
reference captures in coroutine lambdas. clang-tidy's `cppcoreguidelines-avoid-reference-coroutine-parameters` flags
the pattern."
</details>

<details><summary><b>Chain 5 🧊 "Which thread does the coroutine resume on?"</b></summary>

**Initial prompt.** "After `co_await socket.read()`, our handler reads a `thread_local` request context and gets
another request's data. How?"

**L5 textbook answer.** "Coroutines always resume on the thread that started them."

**Why L5 breaks.** A coroutine resumes wherever `resume()` is called: here the I/O thread that completed the read.
Nothing in the language moves it back. Thread-local state read before the `co_await` and after it may belong to
different threads (Folder 08, file 01, Chain 8).

**L7 principal defense.** "Make resumption explicit: awaitables that complete on a scheduler (`co_await
schedule(pool)`, or senders' `continues_on`), and pass request context in the coroutine's parameters or promise, never in
TLS. Logging thread ids around an await is the quickest way to see where code runs."
</details>

<details><summary><b>Chain 6 ⚡ "Lazy or eager tasks?"</b></summary>

**Initial prompt.** "Our `task<T>` starts running immediately (`initial_suspend` returns `suspend_never`). Occasionally
an awaiting coroutine never resumes. Why?"

**L5 textbook answer.** "Eager tasks are faster; the bug must be elsewhere."

**Why L5 breaks.** An eager task may finish, possibly on another thread, *before* the caller's `co_await` registers
its continuation. The final awaiter then finds no continuation and resumes nobody; or, if registration and completion
race, one side reads a half-written handle. Fixing that needs an atomic handshake on the continuation slot on every
await.

**L7 principal defense.** "Lazy tasks (`suspend_always` initially, Listing 10.5's `task`): the child only starts
when awaited, inside `await_suspend`, after the continuation is stored, so no synchronization is needed, and symmetric
transfer makes the start a tail call. It's the design of cppcoro, folly::coro and `std::execution::task`."
</details>

<details><summary><b>Chain 7 🧊 "Why doesn't the async generator overlap I/O with processing?"</b></summary>

**Initial prompt.** "Our async generator reads records from disk and yields them; the consumer processes each.
Throughput equals read time plus process time, not the maximum of the two. Why?"

**L5 textbook answer.** "Async means it overlaps automatically."

**Why L5 breaks.** A generator is *pull*-based: it runs only between the consumer's `co_await next()` and its own
`co_yield`. While the consumer processes a value, the producer is suspended at `co_yield` and issues no reads. Listing
10.7's trace: reading 2 completes at t = 23, ten ticks after the consumer asked at t = 13; with prefetching it could
have been ready at t = 20.

**L7 principal defense.** "Decouple them: the producer runs as its own task and pushes into a bounded channel; the
consumer pulls from the channel. Prefetch depth is the channel capacity, and the bound is backpressure. Or issue the
next read before yielding the current value."
</details>

<details><summary><b>Chain 8 ⚡ "Use std::generator everywhere instead of iterators"</b></summary>

**Initial prompt.** "C++23 has `std::generator`. Should we replace our custom iterators with it?"

**L5 textbook answer.** "Yes, it's simpler and just as fast."

**Why L5 breaks.** It is simpler. Whether it's as fast depends on the frame allocation per generator (no HALO on GCC,
Listing 10.5), an indirect resume per element, and a type-erased frame that blocks vectorization across elements.
Availability matters too: libstdc++ 16 has it, libc++ 21 does not (Listing 10.7).

**L7 principal defense.** "`std::generator` for irregular or recursive sequences (tree walks with `elements_of`,
parsers, lazy pipelines), where the code clarity is worth an allocation and an indirect call per element. Hand-written
iterators or plain loops for tight numeric loops. Check the toolchain first."
</details>

---

## 6. Invariants checklist

- [ ] Coroutine-to-coroutine transfers return handles from `await_suspend` (symmetric transfer).
- [ ] Coroutine parameters are taken by value; coroutine lambdas don't capture by reference.
- [ ] Tasks are lazy, or eager tasks synchronize continuation registration.
- [ ] Hot coroutines have an allocator strategy; frame counts are measured.
- [ ] Where a coroutine resumes is explicit (schedulers), and no state lives in `thread_local` across awaits.
- [ ] Generators that front I/O have a buffer or channel for overlap.

## 7. References

- [dcl.fct.def.coroutine], [expr.await]: <https://eel.is/c++draft/dcl.fct.def.coroutine>
- P0913R1 (symmetric control transfer): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0913r1.html>
- L. Baker, "C++ Coroutines: Understanding Symmetric Transfer": <https://lewissbaker.github.io/2020/05/11/understanding_symmetric_transfer>
- G. Nishanov, "Coroutines and HALO" (P0981R0, heap allocation elision): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0981r0.html>
- P2502R2 (`std::generator`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p2502r2.pdf>
- P3552 (`std::execution::task`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2025/p3552r3.html>
