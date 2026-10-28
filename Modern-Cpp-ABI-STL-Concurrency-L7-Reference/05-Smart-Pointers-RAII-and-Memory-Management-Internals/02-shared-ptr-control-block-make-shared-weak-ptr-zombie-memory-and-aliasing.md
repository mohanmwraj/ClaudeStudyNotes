# 02 · `shared_ptr`: the control block, `make_shared`, weak-pointer zombie memory, aliasing, and atomics

> **Scope.** `shared_ptr` is two pointers: one to the object, one to a *control block* holding the reference counts,
> the deleter, and sometimes the object itself. Every design decision follows from that block: one allocation or two,
> when memory is actually returned, what a copy costs (two atomic read-modify-writes), and how the aliasing constructor
> lets one owner be shared by pointers to different objects. This file measures each on both libraries and shows the
> atomic instructions on x86-64 and ARM64.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 5.3 | `sptr_layout.cpp` | `make_shared`: one 48-byte block (16-byte header + 32-byte object); `shared_ptr(new T)`: a separate 24-byte block; the aliasing constructor | run, recording allocator, both libraries |
| 5.4 | `weak_zombie.cpp` | after the last `shared_ptr` dies, a `weak_ptr` keeps **the whole 1 MiB** of a `make_shared` allocation alive | run, both libraries |
| 5.5 | `sptr_cost.cpp` | copy = 2 atomic RMWs (~10 ns), 41–62 ns contended; libc++ `lock add`/`lock xadd` vs `ldadd`/`ldaddal`; libstdc++'s same-block early exit and single-owner fast path | run + asm (x86-64, AArch64 v8.0/LSE, GCC) |

**Verification line.** As for file 01. Allocation sizes come from a recording allocator passed to `allocate_shared` /
the `shared_ptr(p, d, a)` constructor, so they show the control-block types each library builds.

---

## 1. First principles

### 1.1 The control block (Listing 5.3)

```text
 shared_ptr<T>  (16 bytes)                    control block (both libraries: 16-byte header measured)
 +-----------+-----------+                    +------+-----------+------------+----------------------------+
 | T* ptr    | ctrl* cb  |------------------> | vptr | use_count | weak_count | deleter / allocator / T    |
 +-----------+-----------+                    |  8   |  4 (atomic)| 4 (atomic) | (make_shared: T lives here)|
   ptr may point ANYWHERE (aliasing):          +------+-----------+------------+----------------------------+
   it is not required to be the managed object   dispose() when use_count -> 0 (destroys T)
                                                 destroy() when weak_count -> 0 (frees the block)
 libc++ stores (use_count - 1) and (weak_count - 1): "zero" means "one owner left"
```

```cpp
// sptr_layout.cpp - shared_ptr's control block: what make_shared vs shared_ptr(new T) allocate, and aliasing
#include <cstddef>
#include <cstdint>
#include <memory>
#include <new>
#include <print>
#include <vector>

struct Log {
    int allocs = 0;
    std::size_t sizes[4] = {};
};
inline Log g_log;
template <class T>
struct Recording {                     // sees the control-block type that shared_ptr rebinds it to
    using value_type = T;
    Recording() = default;
    template <class U>
    Recording(const Recording<U>&) noexcept {}
    T* allocate(std::size_t n) {
        if (g_log.allocs < 4) g_log.sizes[g_log.allocs] = n * sizeof(T);
        ++g_log.allocs;
        return static_cast<T*>(::operator new(n * sizeof(T)));
    }
    void deallocate(T* p, std::size_t) noexcept { ::operator delete(p); }
    friend bool operator==(const Recording&, const Recording&) { return true; }
};

struct Payload {
    std::int64_t v[4] = {1, 2, 3, 4};  // 32 bytes
};

int main() {
    std::println("sizeof(shared_ptr<T>) = {} (object pointer + control-block pointer), sizeof(weak_ptr<T>) = {}",
                 sizeof(std::shared_ptr<Payload>), sizeof(std::weak_ptr<Payload>));

    g_log = {};
    { auto p = std::allocate_shared<Payload>(Recording<Payload>{}); }
    std::println("allocate_shared<Payload>          : {} allocation of {} bytes (counts + object in ONE block)",
                 g_log.allocs, g_log.sizes[0]);

    g_log = {};
    { std::shared_ptr<Payload> p(new Payload, std::default_delete<Payload>{}, Recording<Payload>{}); }
    std::println("shared_ptr(new Payload, del, alloc): {} allocation of {} bytes for the control block "
                 "(+ the Payload itself from new)", g_log.allocs, g_log.sizes[0]);

    // Aliasing constructor: shares ownership of 'whole', points at one member. use_count proves the sharing.
    auto whole = std::make_shared<std::vector<int>>(std::vector<int>{10, 20, 30});
    std::shared_ptr<int> second(whole, &(*whole)[1]);
    std::println("aliasing: *second = {}, use_count = {}, owner_before agrees = {}", *second, whole.use_count(),
                 !whole.owner_before(second) && !second.owner_before(whole));
    whole.reset();
    std::println("after whole.reset(): *second = {} (the vector is kept alive by the alias)", *second);
}
```

Output (verified; identical on both libraries):

```text
sizeof(shared_ptr<T>) = 16 (object pointer + control-block pointer), sizeof(weak_ptr<T>) = 16
allocate_shared<Payload>          : 1 allocation of 48 bytes (counts + object in ONE block)
shared_ptr(new Payload, del, alloc): 1 allocation of 24 bytes for the control block (+ the Payload itself from new)
aliasing: *second = 20, use_count = 2, owner_before agrees = true
after whole.reset(): *second = 20 (the vector is kept alive by the alias)
```

* **`make_shared`/`allocate_shared` allocate once**: 48 bytes = a 16-byte header (vptr for the type-erased
  dispose/destroy functions + two 32-bit counts) + the 32-byte object. One allocation, and the object sits next to its
  counts in the same cache lines.
* **`shared_ptr(new T)` allocates twice**: the object by `new`, and a 24-byte control block (header + the pointer to
  delete; the empty deleter and allocator take no space). Two allocations, two cache lines touched on every copy and
  every dereference.
* **The aliasing constructor** `shared_ptr<int>(whole, &(*whole)[1])` shares `whole`'s control block but points at an
  element. `use_count` is 2, `owner_before` treats them as the same owner, and the element stays valid after `whole`
  resets. This is how you hand out a pointer to a member or a sub-object without separate ownership.

### 1.2 Weak pointers and "zombie" memory (Listing 5.4)

```cpp
// weak_zombie.cpp - make_shared + a lingering weak_ptr keeps the WHOLE allocation alive after the object dies
#include <array>
#include <cstddef>
#include <memory>
#include <new>
#include <print>

inline std::size_t g_live = 0;         // bytes currently allocated through Tracking
template <class T>
struct Tracking {
    using value_type = T;
    Tracking() = default;
    template <class U>
    Tracking(const Tracking<U>&) noexcept {}
    T* allocate(std::size_t n) {
        g_live += n * sizeof(T);
        return static_cast<T*>(::operator new(n * sizeof(T)));
    }
    void deallocate(T* p, std::size_t n) noexcept {
        g_live -= n * sizeof(T);
        ::operator delete(p);
    }
    friend bool operator==(const Tracking&, const Tracking&) { return true; }
};

inline bool g_destroyed = false;
struct Image {                         // 1 MiB payload
    std::array<unsigned char, 1 << 20> pixels{};
    ~Image() { g_destroyed = true; }
};

int main() {
    std::println("make_shared-style (one block for counts + object):");
    {
        g_destroyed = false;
        auto s = std::allocate_shared<Image>(Tracking<Image>{});
        std::weak_ptr<Image> w = s;    // e.g. a cache entry or an observer list
        std::println("  live bytes with s and w           : {}", g_live);
        s.reset();
        std::println("  after s.reset(): destroyed={} live bytes = {}  <- 1 MiB still held by the weak_ptr", g_destroyed,
                     g_live);
        w.reset();
        std::println("  after w.reset(): live bytes = {}", g_live);
    }
    std::println("shared_ptr(new T) (object and control block allocated separately):");
    {
        g_destroyed = false;
        Tracking<Image> alloc;
        Image* raw = alloc.allocate(1);
        ::new (static_cast<void*>(raw)) Image;
        auto del = [alloc](Image* p) mutable { p->~Image(); alloc.deallocate(p, 1); };
        std::shared_ptr<Image> s(raw, del, Tracking<Image>{});
        std::weak_ptr<Image> w = s;
        std::println("  live bytes with s and w           : {}", g_live);
        s.reset();
        std::println("  after s.reset(): destroyed={} live bytes = {}  <- only the control block remains", g_destroyed,
                     g_live);
        w.reset();
        std::println("  after w.reset(): live bytes = {}", g_live);
    }
}
```

Output (verified; identical on both libraries):

```text
make_shared-style (one block for counts + object):
  live bytes with s and w           : 1048592
  after s.reset(): destroyed=true live bytes = 1048592  <- 1 MiB still held by the weak_ptr
  after w.reset(): live bytes = 0
shared_ptr(new T) (object and control block allocated separately):
  live bytes with s and w           : 1048608
  after s.reset(): destroyed=true live bytes = 32  <- only the control block remains
  after w.reset(): live bytes = 0
```

* With `make_shared`, the object and the counts are **one allocation**. When the last `shared_ptr` dies, the object is
  destroyed (`destroyed=true`), but its memory cannot be freed, because the `weak_ptr` still needs the counts in the same
  block. **All 1 MiB stays allocated** until the last `weak_ptr` goes.
* With separate allocation, the object's memory is freed at the last `shared_ptr`, and only the 32-byte control block
  (header + pointer + deleter, here) remains for the weak pointers.
* Where it bites: caches and observer lists that hold `weak_ptr`s to large objects (images, buffers, documents). The
  heap stays full of destroyed-but-unfreed objects.

### 1.3 What a copy costs (Listing 5.5)

```cpp
// sptr_cost.cpp - what copying a shared_ptr costs: atomic increments, and libstdc++'s "no threads yet" shortcut
#include <chrono>
#include <memory>
#include <print>
#include <thread>
#include <utility>
#include <vector>

// The operations, isolated for the assembly listing.
void copy_assign(std::shared_ptr<int>& dst, const std::shared_ptr<int>& src) { dst = src; }
void move_assign(std::shared_ptr<int>& dst, std::shared_ptr<int>& src) { dst = std::move(src); }
long by_const_ref(const std::shared_ptr<int>& p) { return *p; }
long by_value(std::shared_ptr<int> p) { return *p; }

// Alternate between two owners: assigning a shared_ptr that already shares the same control block is a no-op
// in libstdc++ (it compares control-block pointers first), which would make the loop measure nothing.
[[gnu::noinline]] double copies_ns(const std::shared_ptr<int>& p, const std::shared_ptr<int>& q, int n) {
    std::vector<std::shared_ptr<int>> sink(1);
    auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < n; ++i) sink[0] = (i & 1) ? p : q;  // increment new, decrement old: two RMWs
    auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::nano>(t1 - t0).count() / n;
}

int main() {
    auto p = std::make_shared<int>(42), q = std::make_shared<int>(43);
    constexpr int kN = 20'000'000;
    double before = copies_ns(p, q, kN);
    std::thread([] {}).join();           // the program now "has threads"
    double after = copies_ns(p, q, kN);
    // Contended: two threads copying the same shared_ptr bounce one cache line (the control block).
    auto contended = [&] {
        auto t0 = std::chrono::steady_clock::now();
        std::thread a([&] { copies_ns(p, q, kN / 4); }), b([&] { copies_ns(p, q, kN / 4); });
        a.join();
        b.join();
        auto t1 = std::chrono::steady_clock::now();
        return std::chrono::duration<double, std::nano>(t1 - t0).count() / (kN / 4);
    }();
    std::println("shared_ptr copy-assign (inc + dec): {:.2f} ns before any thread, {:.2f} ns after a thread existed",
                 before, after);
    std::println("2 threads copying the same two shared_ptrs: {:.2f} ns per iteration (control blocks bounce between "
                 "cores)", contended);
}
```

GCC 16.2 + libstdc++ (one run):

```text
shared_ptr copy-assign (inc + dec): 9.99 ns before any thread, 9.99 ns after a thread existed
2 threads copying the same two shared_ptrs: 31.52 ns per iteration (control blocks bounce between cores)
```

Clang 21.1 + libc++ (one run):

```text
shared_ptr copy-assign (inc + dec): 9.66 ns before any thread, 9.42 ns after a thread existed
2 threads copying the same two shared_ptrs: 27.84 ns per iteration (control blocks bounce between cores)
```

libc++, Clang `-O3`, x86-64:

```asm
_Z11copy_assignRNSt3__110shared_ptrIiEERKS1_: # copy_assign(std::__1::shared_ptr<int>&, std::__1::shared_ptr<int> const&)
	pushq	%rbx
	movq	8(%rsi), %rax
	movups	(%rsi), %xmm0
	testq	%rax, %rax
	je	.LBB0_2
	lock	addq	$1, 8(%rax)
.LBB0_2:
	movq	8(%rdi), %rbx
	movups	%xmm0, (%rdi)
	testq	%rbx, %rbx
	je	.LBB0_4
	movq	$-1, %rax
	lock	xaddq	%rax, 8(%rbx)
	testq	%rax, %rax
	je	.LBB0_5
.LBB0_4:
	popq	%rbx
	retq
.LBB0_5:
	movq	(%rbx), %rax
	movq	%rbx, %rdi
	callq	*16(%rax)
	movq	%rbx, %rdi
	popq	%rbx
	jmp	_ZNSt3__119__shared_weak_count14__release_weakEv@PLT # std::__1::__shared_weak_count::__release_weak()

_Z12by_const_refRKNSt3__110shared_ptrIiEE: # by_const_ref(std::__1::shared_ptr<int> const&)
	movq	(%rdi), %rax
	movslq	(%rax), %rax
	retq

_Z8by_valueNSt3__110shared_ptrIiEE: # by_value(std::__1::shared_ptr<int>)
	movq	(%rdi), %rax
	movslq	(%rax), %rax
	retq
```

libc++, AArch64 Armv8.0 (LL/SC) and Neoverse N1 (LSE):

```asm
_Z11copy_assignRNSt3__110shared_ptrIiEERKS1_: // copy_assign(std::__1::shared_ptr<int>&, std::__1::shared_ptr<int> const&)
	stp	x30, x19, [sp, #-16]!
	ldr	x8, [x1, #8]
	ldr	q0, [x1]
	cbz	x8, .LBB0_3
	add	x8, x8, #8
.LBB0_2:
	ldxr	x9, [x8]
	add	x9, x9, #1
	stxr	w10, x9, [x8]
	cbnz	w10, .LBB0_2
.LBB0_3:
	ldr	x19, [x0, #8]
	str	q0, [x0]
	cbz	x19, .LBB0_7
	add	x8, x19, #8
.LBB0_5:
	ldaxr	x9, [x8]
	sub	x10, x9, #1
	stlxr	w11, x10, [x8]
	cbnz	w11, .LBB0_5
	cbz	x9, .LBB0_8
.LBB0_7:
	ldp	x30, x19, [sp], #16
	ret
.LBB0_8:
	ldr	x8, [x19]
	mov	x0, x19
	ldr	x8, [x8, #16]
	blr	x8
	mov	x0, x19
	ldp	x30, x19, [sp], #16
	b	_ZNSt3__119__shared_weak_count14__release_weakEv // std::__1::__shared_weak_count::__release_weak()

_Z12by_const_refRKNSt3__110shared_ptrIiEE: // by_const_ref(std::__1::shared_ptr<int> const&)
	ldr	x8, [x0]
	ldrsw	x0, [x8]
	ret

_Z8by_valueNSt3__110shared_ptrIiEE: // by_value(std::__1::shared_ptr<int>)
	ldr	x8, [x0]
	ldrsw	x0, [x8]
	ret
```

```asm
_Z11copy_assignRNSt3__110shared_ptrIiEERKS1_: // copy_assign(std::__1::shared_ptr<int>&, std::__1::shared_ptr<int> const&)
	stp	x30, x19, [sp, #-16]!
	ldr	q0, [x1]
	ldr	x8, [x1, #8]
	cbz	x8, .LBB0_2
	add	x8, x8, #8
	mov	w9, #1
	ldadd	x9, x8, [x8]
.LBB0_2:
	ldr	x19, [x0, #8]
	str	q0, [x0]
	cbz	x19, .LBB0_4
	add	x8, x19, #8
	mov	x9, #-1
	ldaddal	x9, x8, [x8]
	cbz	x8, .LBB0_5
.LBB0_4:
	ldp	x30, x19, [sp], #16
	ret
.LBB0_5:
	ldr	x8, [x19]
	mov	x0, x19
	ldr	x8, [x8, #16]
	blr	x8
	mov	x0, x19
	ldp	x30, x19, [sp], #16
	b	_ZNSt3__119__shared_weak_count14__release_weakEv // std::__1::__shared_weak_count::__release_weak()
```

libstdc++, GCC 16.2 `-O3` (Win64 calling convention), the fast paths:

```asm
_Z11copy_assignRSt10shared_ptrIiERKS0_: # copy_assign(std::shared_ptr<int>&, std::shared_ptr<int> const&)
	movq	%rcx, %rax
	movq	(%rdx), %rcx
	movq	8(%rdx), %r8
	movq	%rcx, (%rax)
	movq	8(%rax), %rcx
	cmpq	%rcx, %r8
	je	.L471
	testq	%r8, %r8
	je	.L450
	movl	$1, %edx
	lock	xaddl	%edx, 8(%r8)
	cmpl	$2147483647, %edx
	je	.L451
	movq	8(%rax), %rcx
.L450:
	testq	%rcx, %rcx
	je	.L472
	movabsq	$4294967297, %rdx
	subq	$56, %rsp
	movq	8(%rcx), %r9
	cmpq	%rdx, %r9
	je	.L475
	lock	subl	$1, 8(%rcx)
	je	.L476
.L452:
	movq	%r8, 8(%rax)
	addq	$56, %rsp
	ret
.L472:
	movq	%r8, 8(%rax)
	... (first 31 of 101 lines shown; the rest is the slow path)
```

* **A copy-assignment is two atomic RMWs**: increment the new block's count, decrement the old one's. libc++ uses a
  **relaxed** increment (`lock addq` / `ldadd`) and an **acq_rel** decrement (`lock xaddq` / `ldaddal`). The
  decrement needs release (so writes made through this owner happen before destruction) and acquire (so the destroying
  thread sees every other owner's writes). On x86 both compile to `lock`-prefixed instructions anyway. On ARM64 the
  orders are visible in the instruction suffixes, and on Armv8.0 without LSE they become LL/SC loops.
* **libc++ stores count − 1**: `testq %rax, %rax; je` after the decrement means "the old value was 0", i.e. this was
  the last owner. Then it calls `__on_zero_shared` through the vtable (`callq *16(%rax)`) and releases the weak count.
* **libstdc++ adds three fast paths**: (1) `cmpq %rcx, %r8; je` returns immediately if both `shared_ptr`s already share
  a control block, which made my first benchmark (assigning the same pointer repeatedly) measure *nothing* on GCC;
  (2) an overflow check on the 32-bit count (`cmpl $2147483647`); (3) a single-owner path: when use and weak counts are
  both 1 (one 8-byte compare with `0x100000001`), it skips the atomic decrement entirely, because no other thread can
  hold a reference.
* **Measured**: ~9–11 ns per inc + dec pair uncontended on both libraries. With two threads hammering the same two
  control blocks, **41–62 ns**, because the cache line holding the counts bounces between cores on every RMW. This is
  the hidden cost of passing `shared_ptr` by value through hot multi-threaded code.
* **By value vs by const reference**: the callee code is identical (`by_const_ref` and `by_value` both load through the
  pointer). The difference is in the *caller*, which for by-value must copy (2 RMWs) and later destroy the temporary.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| `shared_ptr`, `weak_ptr`, `make_shared`, `enable_shared_from_this` | C++11 (from TR1/Boost) | atomic counts mandated by the thread-safety rules |
| `shared_ptr<T[]>` | C++17 (P0414R2) | — |
| `weak_from_this`, `reinterpret_pointer_cast`, `owner_before` uses | C++17 | — |
| `make_shared<T[]>`, `make_shared_for_overwrite` | C++20 (P0674R1, P1020R1) | arrays in one allocation |
| `std::atomic<std::shared_ptr<T>>` | C++20 (P0718R2) | free functions `atomic_load(&sp)` deprecated (C++20), removed (C++26); Folder 07 |
| `owner_hash`, `owner_equal` | C++26 (P1901R2) | unordered containers keyed by ownership |
| non-atomic single-threaded counts | not standard | libstdc++ uses `__gthread_active_p()` to choose; ⚠ on this static MinGW build the copy cost was the same before and after a thread existed |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| creating shared objects | `shared_ptr<T>(new T(args))` (two allocations) | `std::make_shared<T>(args)` (one) |
| large objects observed through `weak_ptr` caches | `make_shared` (memory lingers while weak refs exist) | `shared_ptr<T>(new T)` or `allocate_shared` with a pool, so the object memory frees at the last strong ref |
| passing to a function that only reads | `void f(std::shared_ptr<T> p)` (2 RMWs per call) | `void f(const T&)` or `T*`; by value only to share ownership |
| hot multi-threaded fan-out of one shared object | every task copies the `shared_ptr` | copy once per thread, or use an epoch/RCU scheme (Folder 09) |
| exposing a member with shared lifetime | a second `shared_ptr` with its own count (double free) | the aliasing constructor |
| shared mutable config read by many threads | `shared_ptr<Config>` replaced without synchronization (data race on the pointer) | `std::atomic<std::shared_ptr<const Config>>` (Folder 07) or RCU (Folder 09) |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| memory high-water mark never drops | `make_shared` + lingering `weak_ptr`s | heap profiler showing destroyed objects' blocks |
| atomic RMW / cache-line contention in profiles | `shared_ptr` copies across threads on a hot path | perf `mem` / VTune; reduce copies |
| double free | two control blocks for one object (`shared_ptr(raw)` twice, or `shared_ptr(this)`) | ASan; `enable_shared_from_this` (file 03) |
| reference cycle leak | A owns B, B owns A | `weak_ptr` for back edges; leak sanitizer |
| torn `shared_ptr` read under concurrent reassignment | a plain `shared_ptr` written by one thread and read by another | TSan; `atomic<shared_ptr>` |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "make_shared or shared_ptr(new T)?"</b></summary>

**Initial prompt.** "Why prefer `make_shared`? Are there cases where you shouldn't?"

**L5 textbook answer.** "`make_shared` is faster and exception-safe. Always use it."

**Why L5 breaks.** Faster: one allocation instead of two (Listing 5.3: 48 bytes once vs 24 + 32 separately). But
`make_shared` couples the object's memory to the control block. With outstanding `weak_ptr`s, the destroyed object's
memory cannot be released (Listing 5.4: 1 MiB held after destruction). It also cannot use a custom deleter, and it needs
an accessible constructor.

**L7 principal defense.** "`make_shared` by default. Separate allocation (or `allocate_shared` with a pool) for large
objects referenced from `weak_ptr` caches or observer lists, and when a custom deleter or a private constructor is
required. The decision is about memory lifetime, not just speed."
</details>

<details><summary><b>Chain 2 🔥 "Is shared_ptr thread-safe?"</b></summary>

**Initial prompt.** "Is `std::shared_ptr` thread-safe?"

**L5 textbook answer.** "Yes, it uses atomic reference counting."

**Why L5 corrupts memory on ARM64.** The *control block* is thread-safe: different `shared_ptr` objects that share it may
be copied and destroyed concurrently. The `shared_ptr` *object itself* is not: one thread reassigning `p` while another
copies `p` is a data race on its two pointers. On x86 the 16-byte object is usually written in one `movups` in libc++'s
codegen (Listing 5.5), so the reader often sees either the old or the new pair. On ARM64, or on other code paths, the two
words can be observed torn: the new object pointer with the old control block, which leads to the wrong decrement and a
use-after-free. The pointee is not protected at all.

**L7 principal defense.** "Three levels: the counts are atomic, the `shared_ptr` object is not (use
`std::atomic<std::shared_ptr<T>>` or a mutex for a shared slot), and the pointee needs its own synchronization or must be
immutable (`shared_ptr<const T>`). TSan catches the middle case."
</details>

<details><summary><b>Chain 3 ⚡ "Pass shared_ptr by value or by const&?"</b></summary>

**Initial prompt.** "A function takes `std::shared_ptr<Widget>` by value and is called 10M times per second from 8 threads.
Problem?"

**L5 textbook answer.** "No, copying a shared_ptr is cheap: just a pointer copy and an increment."

**Why L5 breaks.** Each call costs an atomic increment and decrement (~10 ns uncontended in Listing 5.5), and when all
threads copy the *same* `shared_ptr`, they contend on one cache line: 41–62 ns per copy pair with only two threads. At
8 threads and 10M calls/s the reference count becomes a serialization point.

**L7 principal defense.** "By value only when the function stores or shares ownership. Otherwise `const Widget&` (or
`Widget*`). For hot fan-out, take one copy per thread or task, not per call. If the object is long-lived and read-only,
consider no counting at all for the read path (RCU, Folder 09)."
</details>

<details><summary><b>Chain 4 🧊 "What is the aliasing constructor for?"</b></summary>

**Initial prompt.** "Explain `shared_ptr<T>(const shared_ptr<U>& r, T* p)`."

**L5 textbook answer.** "It's a rarely used constructor; I don't know what it's for."

**Why L5 breaks.** It shares `r`'s ownership but points at `p`. That lets you hand out a `shared_ptr` to a member or
element that keeps the *whole* owner alive (Listing 5.3: the element stayed valid after `whole.reset()`). Without it,
people create a second, independent `shared_ptr` to the member, with its own count, and a double free follows. It also
makes `shared_ptr<void>` and type-punned views possible without copying.

**L7 principal defense.** "The aliasing constructor separates *what keeps it alive* from *what it points to*. I use it to
expose sub-objects of shared data (a column of a shared table, a node of a shared tree) and `owner_before` / C++26
`owner_hash` to key containers by owner rather than by address."
</details>

<details><summary><b>Chain 5 ⚡ "Why does libstdc++ skip the atomic decrement sometimes?"</b></summary>

**Initial prompt.** "In libstdc++'s generated code, the last release of a `shared_ptr` sometimes has no atomic
instruction. Is that safe?"

**L5 textbook answer.** "It must be a bug; decrements must be atomic."

**Why L5 breaks.** It is a deliberate fast path (Listing 5.5, libstdc++ asm): if use count and weak count are both 1,
checked with one 8-byte load, then this thread holds the only reference of either kind. No other thread can increment
(that would require a reference), so a plain store is safe. The same code shows the other fast path (assignment between
pointers that share a block does nothing) and a 32-bit overflow check.

**L7 principal defense.** "Ownership invariants enable non-atomic shortcuts: 'only owner' means 'no concurrent
observer'. The same reasoning justifies non-atomic refcounts in single-threaded subsystems (intrusive counts, file 03)
and the libstdc++ `__gthread_active_p` single-thread mode on platforms where it applies."
</details>

<details><summary><b>Chain 6 🔥 "Design an image cache with weak_ptr"</b></summary>

**Initial prompt.** "Cache decoded images: callers hold `shared_ptr<Image>`, the cache holds `weak_ptr` so unused images can
die. Problems?"

**L5 textbook answer.** "That's the standard pattern; when no caller holds the image, it's freed."

**Why L5 breaks.** With `make_shared<Image>`, it is destroyed but **not freed** while the cache's `weak_ptr` exists
(Listing 5.4: 1 MiB per image stays allocated). The cache's memory footprint is then the sum of all images ever cached,
until entries are evicted. Also: `lock()` on every lookup is an atomic RMW, and expired entries must be swept.

**L7 principal defense.** "Allocate images separately (`shared_ptr<Image>(new Image)` or `allocate_shared` with a pool
whose blocks are freed at dispose), sweep expired `weak_ptr` entries on insertion or with a periodic task, and bound the
cache by bytes. For very hot lookups, a strong-reference LRU with explicit eviction is simpler and faster than weak
references."
</details>

<details><summary><b>Chain 7 🧊 "How do you break a shared_ptr cycle?"</b></summary>

**Initial prompt.** "Parent and child objects hold `shared_ptr`s to each other. What happens?"

**L5 textbook answer.** "Use `weak_ptr` for one direction."

**Why L5 breaks.** That is the fix. The L7 additions: which direction (the non-owning one, usually child → parent);
that `weak_ptr::lock()` has a cost on each traversal (an atomic increment); that with `make_shared` the weak back-edge
keeps the parent's *memory* alive after its destruction (Listing 5.4); and that cycles also arise through captured
lambdas (`[self = shared_from_this()]` stored in a member).

**L7 principal defense.** "Ownership forms a tree, or a DAG: owners hold `shared_ptr`, everything else holds `weak_ptr` or
a raw/observer pointer whose lifetime is guaranteed by the structure. For graphs with arbitrary cycles, an arena owning
all nodes (file 03) is cleaner than reference counting."
</details>

<details><summary><b>Chain 8 ⚡ "What's inside the control block?"</b></summary>

**Initial prompt.** "Describe the memory layout of `std::shared_ptr`."

**L5 textbook answer.** "A pointer and a reference count."

**Why L5 breaks.** Two pointers (16 bytes), and the count is not inside the `shared_ptr`. The control block has a vptr
for type-erased `dispose`/`destroy`, two 32-bit atomic counts (use and weak), and the deleter and allocator, or the
object itself for `make_shared` (Listing 5.3: a 16-byte header on both libraries; 48 bytes with a 32-byte object). Two
counts exist because the block must outlive the object while weak references exist. libc++ even stores both counts
minus one.

**L7 principal defense.** "I'd draw the two-pointer handle, the control block with vptr + use + weak counts + deleter/
allocator or inline object, and explain dispose at use = 0 vs destroy at weak = 0. From that layout follow the costs:
two cache lines for separately allocated objects, zombie memory with `make_shared` + weak refs, and two atomics per copy."
</details>

---

## 6. Invariants checklist

- [ ] `make_shared` by default; separate allocation for large objects observed by long-lived `weak_ptr`s.
- [ ] Functions that don't share ownership take `T&`/`T*`, not `shared_ptr` by value.
- [ ] No `shared_ptr` object is written by one thread while read by another (use `atomic<shared_ptr>` or a mutex).
- [ ] Back-edges are `weak_ptr` or non-owning; no ownership cycles through stored lambdas.
- [ ] Sub-object pointers that need shared lifetime use the aliasing constructor.
- [ ] Hot multi-threaded paths are profiled for reference-count contention.

## 7. References

- P0718R2 (`atomic<shared_ptr>`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0718r2.html>
- P0674R1 (`make_shared` for arrays): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2017/p0674r1.html>
- P1901R2 (`owner_hash`, `owner_equal`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2023/p1901r2.html>
- libstdc++ `shared_ptr_base.h`: <https://github.com/gcc-mirror/gcc/blob/master/libstdc%2B%2B-v3/include/bits/shared_ptr_base.h>
- libc++ `shared_ptr.h`: <https://github.com/llvm/llvm-project/blob/main/libcxx/include/__memory/shared_ptr.h>
- Herb Sutter, "Back to the Basics! Essentials of Modern C++ Style", CppCon 2014 (parameter passing).
