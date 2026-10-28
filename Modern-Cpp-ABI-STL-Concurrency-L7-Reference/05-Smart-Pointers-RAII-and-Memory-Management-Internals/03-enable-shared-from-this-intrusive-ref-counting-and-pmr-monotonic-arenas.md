# 03 · `enable_shared_from_this`, intrusive reference counting, and arena ownership

> **Scope.** Three ownership tools beyond the standard pair: `enable_shared_from_this` (how an object gets a `shared_ptr`
> to itself safely, and when it throws), intrusive reference counts (the count inside the object: 8-byte handles, one
> allocation, and the memory orders that make the decrement correct on ARM64), and arena ownership (one owner for a whole
> graph, released in O(1), plus the recursion trap of deep `unique_ptr` chains).

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 5.6 | `esft.cpp` | strong vs weak self-capturing callbacks; `bad_weak_ptr` on a non-owned object; `weak_from_this` | run, both libraries |
| 5.7 | `intrusive.cpp` | 8-byte handle, safe re-adoption from a raw pointer, 2-thread churn ends at the exact count; `release()` = `lock sub` (x86) vs `ldxr`/`stlxr` + `dmb ishld` / `ldaddl` + `dmb ishld` (ARM64) | run + asm |
| 5.8 | `graph_ownership.cpp` | a 1M-node `unique_ptr` chain **overflows the stack** when destroyed recursively (0xC00000FD); the iterative destructor; an arena is ~6–10× faster | run ×2 configurations, both compilers |

**Verification line.** As for files 01–02. The recursive-destruction run is expected to crash: its exit code is
recorded (0xC00000FD = `STATUS_STACK_OVERFLOW`).

---

## 1. First principles

### 1.1 `enable_shared_from_this` (Listing 5.6)

```text
 struct S : std::enable_shared_from_this<S> { ... };
   the base holds a hidden  mutable weak_ptr<S> weak_this;
 std::make_shared<S>() / shared_ptr<S>(new S): the shared_ptr constructor detects the base and assigns weak_this
 s->shared_from_this()  == weak_this.lock(), or throw std::bad_weak_ptr if weak_this is empty (C++17)
 s->weak_from_this()    == weak_this (C++17), never throws
```

```cpp
// esft.cpp - enable_shared_from_this: how it works, the bad_weak_ptr case, and keeping callbacks safe
#include <functional>
#include <memory>
#include <print>
#include <vector>

struct Session : std::enable_shared_from_this<Session> {
    int id;
    explicit Session(int i) : id(i) {}
    // Hands a strong reference to an async callback, so the session outlives the pending operation.
    std::function<void()> make_callback() {
        return [self = shared_from_this()] { std::println("  callback runs, session {} alive", self->id); };
    }
    // For callbacks that must NOT extend the lifetime: capture a weak_ptr and lock it when invoked.
    std::function<void()> make_weak_callback() {
        return [weak = weak_from_this()] {
            if (auto self = weak.lock()) std::println("  weak callback: session {} alive", self->id);
            else std::println("  weak callback: session already gone, skipping");
        };
    }
};

int main() {
    std::vector<std::function<void()>> pending;
    {
        auto s = std::make_shared<Session>(7);  // make_shared fills the hidden weak_ptr inside the base
        std::println("use_count after make_shared: {}", s.use_count());
        pending.push_back(s->make_callback());
        pending.push_back(s->make_weak_callback());
        std::println("use_count with one strong callback pending: {}", s.use_count());
    }                                            // our last named owner is gone
    for (auto& cb : pending) cb();               // strong callback keeps it alive; weak one sees it alive too
    pending.erase(pending.begin());              // drop the strong callback -> Session destroyed
    for (auto& cb : pending) cb();

    // shared_from_this() on an object NOT owned by a shared_ptr: the hidden weak_ptr is empty.
    Session stack_session(1);
    try {
        auto bad = stack_session.shared_from_this();
    } catch (const std::bad_weak_ptr& e) {
        std::println("shared_from_this on a non-owned object throws bad_weak_ptr (C++17): {}", e.what());
    }
    std::println("weak_from_this().expired() on it: {}", stack_session.weak_from_this().expired());
}
```

Output (verified; identical on both libraries):

```text
use_count after make_shared: 1
use_count with one strong callback pending: 2
  callback runs, session 7 alive
  weak callback: session 7 alive
  weak callback: session already gone, skipping
shared_from_this on a non-owned object throws bad_weak_ptr (C++17): bad_weak_ptr
weak_from_this().expired() on it: true
```

* **A strong self-capture extends the lifetime**: the session outlived its last named owner because the pending callback
  held a `shared_ptr` (use_count 2). That is the point for async operations (the session must exist when the I/O
  completes), and also the leak risk: a callback stored *inside* the session forms a cycle.
* **A weak self-capture does not**: once the strong callback was dropped, the weak one found the session gone and
  skipped. This is the right default for observer-style callbacks.
* **`shared_from_this()` on an object not owned by a `shared_ptr` throws `bad_weak_ptr`** (since C++17; before that it
  was UB). The hidden `weak_ptr` is assigned only by a `shared_ptr` constructor, so calling `shared_from_this()` in the
  **constructor** throws too, because the object is not yet owned.

### 1.2 Intrusive reference counting (Listing 5.7)

```cpp
// intrusive.cpp - an intrusive reference count: 8-byte handle, one allocation, and the memory orders that matter
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <print>
#include <thread>
#include <utility>

class RefCounted {
public:
    void add_ref() const noexcept { refs_.fetch_add(1, std::memory_order_relaxed); }  // (1) see the text
    void release() const noexcept {
        if (refs_.fetch_sub(1, std::memory_order_release) == 1) {                     // (2)
            std::atomic_thread_fence(std::memory_order_acquire);                       // (3)
            delete this;
        }
    }
    std::uint32_t use_count() const noexcept { return refs_.load(std::memory_order_relaxed); }

protected:
    RefCounted() = default;
    virtual ~RefCounted() = default;

private:
    mutable std::atomic<std::uint32_t> refs_{1};  // created owned by its first IntrusivePtr
};

template <class T>
class IntrusivePtr {
    T* p_ = nullptr;

public:
    IntrusivePtr() = default;
    static IntrusivePtr adopt(T* p) noexcept {  // takes the initial reference
        IntrusivePtr r;
        r.p_ = p;
        return r;
    }
    IntrusivePtr(const IntrusivePtr& o) noexcept : p_(o.p_) { if (p_) p_->add_ref(); }
    IntrusivePtr(IntrusivePtr&& o) noexcept : p_(std::exchange(o.p_, nullptr)) {}
    IntrusivePtr& operator=(IntrusivePtr o) noexcept {  // copy-and-swap: correct for self-assignment
        std::swap(p_, o.p_);
        return *this;
    }
    ~IntrusivePtr() { if (p_) p_->release(); }
    T* operator->() const noexcept { return p_; }
    T& operator*() const noexcept { return *p_; }
    // Re-adopting a raw pointer is safe: the count lives in the object (unlike shared_ptr(raw) twice).
    static IntrusivePtr from_raw(T* p) noexcept { p->add_ref(); return adopt(p); }
};

struct Node : RefCounted {
    int value = 0;
    explicit Node(int v) : value(v) {}
};

// For the assembly listing.
void release_one(const RefCounted* r) { r->release(); }

int main() {
    auto a = IntrusivePtr<Node>::adopt(new Node(5));
    auto b = a;
    auto c = IntrusivePtr<Node>::from_raw(&*a);
    std::println("sizeof(IntrusivePtr<Node>) = {} vs sizeof(shared_ptr<Node>) = {}; use_count = {}", sizeof(a),
                 sizeof(std::shared_ptr<Node>), a->use_count());

    // Two threads copying/destroying handles to the same object: the count must end exactly where it started.
    auto churn = [&] {
        for (int i = 0; i < 1'000'000; ++i) {
            IntrusivePtr<Node> tmp = a;
            (void)tmp;
        }
    };
    auto t0 = std::chrono::steady_clock::now();
    std::thread t1(churn), t2(churn);
    t1.join();
    t2.join();
    auto t3 = std::chrono::steady_clock::now();
    std::println("after 2 x 1M concurrent copies: use_count = {} (expected 3), {:.1f} ns per copy+release pair",
                 a->use_count(), std::chrono::duration<double, std::nano>(t3 - t0).count() / 2'000'000);
}
```

Output (one run; the count is verified, the time is a measurement):

```text
GCC 16.2:
sizeof(IntrusivePtr<Node>) = 8 vs sizeof(shared_ptr<Node>) = 16; use_count = 3
after 2 x 1M concurrent copies: use_count = 3 (expected 3), 24.6 ns per copy+release pair
```

```text
Clang 21.1:
sizeof(IntrusivePtr<Node>) = 8 vs sizeof(shared_ptr<Node>) = 16; use_count = 3
after 2 x 1M concurrent copies: use_count = 3 (expected 3), 23.1 ns per copy+release pair
```

`release()` compiled, x86-64, then AArch64 Armv8.0, then AArch64 with LSE (Neoverse N1):

```asm
_Z11release_onePK10RefCounted:     # release_one(RefCounted const*)
	lock	subl	$1, 8(%rdi)
	jne	.LBB0_1
	movq	(%rdi), %rax
	jmpq	*8(%rax)
.LBB0_1:
	retq
```

```asm
_Z11release_onePK10RefCounted:     // release_one(RefCounted const*)
	add	x8, x0, #8
.LBB0_1:
	ldxr	w9, [x8]
	subs	w9, w9, #1
	stlxr	w10, w9, [x8]
	cbnz	w10, .LBB0_1
	b.ne	.LBB0_4
	dmb	ishld
	ldr	x8, [x0]
	ldr	x1, [x8, #8]
	br	x1
.LBB0_4:
	ret
```

```asm
_Z11release_onePK10RefCounted:     // release_one(RefCounted const*)
	add	x8, x0, #8
	mov	w9, #-1
	ldaddl	w9, w8, [x8]
	cmp	w8, #1
	b.ne	.LBB0_2
	dmb	ishld
	ldr	x8, [x0]
	ldr	x1, [x8, #8]
	br	x1
.LBB0_2:
	ret
```

The three memory orders in the listing, and why each is exactly right:

1. **`add_ref` is relaxed.** A new reference can only be created from an existing one, which keeps the object alive.
   No other memory needs ordering with the increment.
2. **The decrement is release.** Everything this thread did to the object (writes through its reference) must
   happen-before the destruction that some *other* thread may perform after its own final decrement. Release on every
   decrement orders those writes before the count change.
3. **An acquire fence on the last decrement only.** The thread that sees the count reach zero must observe all other
   threads' writes before it runs the destructor. The fence pairs with their release decrements. Doing this only on the
   last reference avoids paying acquire on every release.

On x86-64 this is a single `lock subl` (every locked RMW is a full barrier, and the acquire fence costs nothing). On
ARM64 Armv8.0 it is an LL/SC loop with a **release** store-exclusive (`stlxr`) followed by `dmb ishld` (the load-load
and load-store barrier that implements acquire) on the last-reference path. With LSE it is one `ldaddl` (add with
release) plus the same `dmb ishld`. Writing `fetch_sub(1, relaxed)` instead would be correct on x86 by accident and
broken on ARM64. The same pattern is inside libc++'s and libstdc++'s `shared_ptr` (file 02) and Linux's `refcount_t`.

Why intrusive: the handle is **8 bytes** (vs 16), there is one allocation (the count is a member), and re-adopting a
raw pointer is safe (`from_raw`) because the count travels with the object. With `shared_ptr`, two `shared_ptr`s made
from the same raw pointer create two control blocks and a double free. The cost is that the type must cooperate (inherit
`RefCounted`), and there is no weak pointer unless you build one.

### 1.3 Graph ownership: recursion, iteration, arenas (Listing 5.8)

```cpp
// graph_ownership.cpp - owning a long chain: recursive unique_ptr destruction, the iterative fix, and an arena
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <memory_resource>
#include <print>

struct Node {
    std::int64_t value = 0;
    std::unique_ptr<Node> next;
#ifndef RECURSIVE_DESTROY
    // The default ~Node destroys 'next', whose ~Node destroys its 'next', ... one stack frame per element.
    // Unlinking iteratively keeps the depth at one frame, whatever the length.
    ~Node() {
        std::unique_ptr<Node> cur = std::move(next);
        while (cur) cur = std::move(cur->next);
    }
    Node() = default;
    Node(Node&&) = default;
#endif
};

struct ArenaNode {                     // trivially destructible: the arena can drop everything at once
    std::int64_t value = 0;
    ArenaNode* next = nullptr;
};

template <class F>
double ms(F f) {
    auto t0 = std::chrono::steady_clock::now();
    f();
    auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::milli>(t1 - t0).count();
}

int main() {
    constexpr std::int64_t kN = 1000000;
    std::int64_t sum = 0;  // not long: long is 32-bit on Windows (LLP64) and would overflow
    double owning = ms([&] {
        auto head = std::make_unique<Node>();
        Node* tail = head.get();
        for (std::int64_t i = 1; i < kN; ++i) {
            tail->next = std::make_unique<Node>();
            tail = tail->next.get();
            tail->value = i;
        }
        for (Node* p = head.get(); p; p = p->next.get()) sum += p->value;
    });                                // head destroyed here: 1M deletes
    std::println("unique_ptr chain of {} nodes, build + walk + destroy: {:.1f} ms (sum {})", kN, owning, sum);

    sum = 0;
    double arena = ms([&] {
        std::pmr::monotonic_buffer_resource pool;
        std::pmr::polymorphic_allocator<ArenaNode> alloc(&pool);
        ArenaNode* head = alloc.new_object<ArenaNode>();
        ArenaNode* tail = head;
        for (std::int64_t i = 1; i < kN; ++i) {
            tail->next = alloc.new_object<ArenaNode>();
            tail = tail->next;
            tail->value = i;
        }
        for (ArenaNode* p = head; p; p = p->next) sum += p->value;
    });                                // pool destroyed: a few chunk frees, no per-node work ("winking out")
    std::println("arena chain of {} nodes, build + walk + release:   {:.1f} ms (sum {})", kN, arena, sum);
}
```

Default build with the iterative destructor (one run):

```text
GCC 16.2:
unique_ptr chain of 1000000 nodes, build + walk + destroy: 69.6 ms (sum 499999500000)
arena chain of 1000000 nodes, build + walk + release:   7.8 ms (sum 499999500000)
```

```text
Clang 21.1:
unique_ptr chain of 1000000 nodes, build + walk + destroy: 66.9 ms (sum 499999500000)
arena chain of 1000000 nodes, build + walk + release:   9.7 ms (sum 499999500000)
```

`-DRECURSIVE_DESTROY` (the compiler-generated destructor), both compilers:

```text
[exit code] 0xc00000fd
[exit code] 0xc00000fd
```

* **The implicit destructor of a `unique_ptr`-linked node recurses**: `~Node` destroys `next`, which runs `~Node` on the
  next node, one stack frame per element. A 1M-node chain exhausted the default Windows thread stack (a few MB at most) and the process
  died with **0xC00000FD (stack overflow)** on both compilers. Linux's default 8 MB stack only moves the limit. The same
  recursion appears in linked trees and in `shared_ptr` chains.
* **The iterative destructor** unlinks the list one node at a time (`cur = std::move(cur->next)`), so the depth is one
  frame whatever the length.
* **An arena** (`pmr::monotonic_buffer_resource`) allocates nodes from bump-pointer chunks and frees the whole graph
  at once. Nodes are trivially destructible, so nothing runs per node ("winking out"). Build + walk + release took
  6–10 ms vs 59–68 ms for the owning chain. The price is that individual nodes cannot be freed early, and the nodes
  must not own anything that needs a destructor.
* The listing's first version summed into `long`, which is **32 bits on Windows (LLP64)**, and overflowed (UB) without
  any warning. All sums in this KB are now `std::int64_t`. That overflow hid in four earlier listings too, and was
  found and fixed in the same review.

---

## 2. Evolution table

| Feature | Standard (paper) | Notes |
|---|---|---|
| `enable_shared_from_this`, `shared_from_this` | C++11 | UB on non-owned objects |
| `bad_weak_ptr` from `shared_from_this` on a non-owned object, `weak_from_this` | C++17 (P0033R1) | well-defined failure |
| `std::atomic_thread_fence`, memory orders | C++11 | the intrusive-count pattern |
| `polymorphic_allocator::new_object`/`delete_object` | C++20 (P0339R6) | used by the arena in Listing 5.8 |
| intrusive pointer in the standard | — | proposals (P0468 `retain_ptr`) not adopted; use boost::intrusive_ptr or your own |
| hazard pointers / RCU for read-mostly shared data | C++26 (P2530, P2545) | not shipped by GCC 16 or libc++ 21; Folder 09 |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| async callback that needs the object | `[this]` (dangles if the object dies first) | `[self = shared_from_this()]` |
| observer callback | `[self = shared_from_this()]` stored in the object (cycle, leak) | `[weak = weak_from_this()]` + `lock()` |
| `shared_from_this()` in the constructor | throws `bad_weak_ptr` | a static factory: construct with `make_shared`, then register callbacks |
| many small shared objects in a hot path | `shared_ptr` (16-byte handles, separate counts) | intrusive refcount with relaxed add / release sub / acquire fence |
| refcount decrement written by hand | `fetch_sub(1)` with `relaxed` | `release` on every decrement + `acquire` fence before delete |
| long chains or deep trees of owning pointers | compiler-generated destructors | iterative destruction, or an arena that releases everything at once |
| request-scoped object graphs | one `new` per node | `pmr::monotonic_buffer_resource` + trivially destructible nodes |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| `bad_weak_ptr` thrown at start-up | `shared_from_this()` called in a constructor or on a stack object | factory functions; stack traces |
| leak of objects with self-capturing callbacks | strong self-capture stored in the object | leak sanitizer; weak capture |
| rare use-after-free in an intrusive-refcounted type, only on ARM64 | relaxed decrement (no release/acquire) | TSan; code review of memory orders |
| stack overflow while destroying a big structure | recursive destructors of linked owning pointers | crash dump with thousands of `~Node` frames; iterative destruction |
| sums or counters wrong only on Windows | `long` is 32-bit (LLP64) | `-Wconversion` does not catch it; use fixed-width types |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "How does shared_from_this work?"</b></summary>

**Initial prompt.** "How does `shared_from_this()` find the existing control block?"

**L5 textbook answer.** "It creates a new `shared_ptr` from `this`."

**Why L5 corrupts memory.** That is exactly the bug it prevents. `shared_ptr<S>(this)` creates a *second* control block,
so two counts each think they own the object, and the result is a double free. `enable_shared_from_this` stores a hidden
`weak_ptr`, filled in by the first owning `shared_ptr`'s constructor, and `shared_from_this()` locks it. On a non-owned
object, or inside the constructor, the `weak_ptr` is empty, and C++17 makes that throw `bad_weak_ptr` (Listing 5.6)
instead of UB.

**L7 principal defense.** "Never `shared_ptr(this)`. Types that need self-references derive from
`enable_shared_from_this`, have private constructors and a static `create()` that calls `make_shared`, and do any
callback registration after construction. Observers capture `weak_from_this()`."
</details>

<details><summary><b>Chain 2 🔥 "Write the decrement of a reference count"</b></summary>

**Initial prompt.** "Implement `release()` for an intrusive reference count."

**L5 textbook answer.** `if (--count == 0) delete this;` with `std::atomic<int> count`.

**Why L5 breaks on ARM64.** `--count` on an atomic is `fetch_sub(1, seq_cst)`: correct but stronger than needed. The real
bug appears when someone "optimizes" it to relaxed. Then thread A's writes to the object are not ordered before thread
B's `delete` after B's final decrement. On x86 every `lock` RMW is a full barrier, so it still works. On ARM64 the
relaxed `ldadd` lets B destroy (and reuse) memory while A's earlier stores are still landing. The result is a
use-after-free that only reproduces on Graviton or Apple silicon.

**L7 principal defense.** "`if (count.fetch_sub(1, std::memory_order_release) == 1) { std::atomic_thread_fence(
std::memory_order_acquire); delete this; }`, with a relaxed increment. Listing 5.7 shows what it compiles to: `lock subl`
on x86; `stlxr` + `dmb ishld`, or `ldaddl` + `dmb ishld` with LSE, on ARM64. Each order has a stated reason, and the
churn test must end at the exact count."
</details>

<details><summary><b>Chain 3 ⚡ "Intrusive or shared_ptr?"</b></summary>

**Initial prompt.** "When would you use an intrusive pointer instead of `shared_ptr`?"

**L5 textbook answer.** "Never, `shared_ptr` is standard."

**Why L5 breaks.** `shared_ptr` handles are 16 bytes, separately allocated objects touch two cache lines, and creating
two `shared_ptr`s from one raw pointer is a double free. An intrusive count gives 8-byte handles, one allocation, and safe
re-adoption from raw pointers (Listing 5.7: `from_raw`). That matters for objects that cross C APIs, live in very large
numbers, or are handed between threads as raw pointers (COM, Python objects, kernel objects, GPU resources).

**L7 principal defense.** "Intrusive when the type is ours, objects are numerous or cross FFI boundaries, and weak
references are not needed (or are built explicitly). `shared_ptr` when ownership is generic, the type is someone else's,
or weak references matter."
</details>

<details><summary><b>Chain 4 🧊 "Why did destroying my list crash?"</b></summary>

**Initial prompt.** "Our linked list of `unique_ptr<Node>` crashes when a list with a million elements is destroyed. Small
lists are fine."

**L5 textbook answer.** "Memory corruption somewhere; run ASan."

**Why L5 breaks.** There is no corruption. The compiler-generated `~Node` destroys `next` recursively, one stack frame per
node. Listing 5.8: 1M nodes overflowed the Windows default stack (0xC00000FD) on both compilers. The same applies to
binary trees with deep paths and to `shared_ptr` chains.

**L7 principal defense.** "A user-provided destructor that unlinks iteratively (`while (cur) cur = std::move(cur->next);`),
or an explicit work list for trees. Or store nodes in an arena or a vector with indices, where destruction is not
recursive at all. I add a test with a long chain, because the bug is invisible at small sizes."
</details>

<details><summary><b>Chain 5 ⚡ "Arena allocation for a parse tree"</b></summary>

**Initial prompt.** "A JSON parser builds 10⁶ nodes per request and frees them at the end. Optimize."

**L5 textbook answer.** "Use `unique_ptr` for every child so nothing leaks."

**Why L5 breaks.** Correct, but slow: 10⁶ allocations, 10⁶ frees, scattered nodes, and possibly a recursive destructor
(chain 4). Listing 5.8 measured the owning version at 59–68 ms against 6–10 ms for an arena with trivially destructible
nodes, where destruction is one chunk free per buffer.

**L7 principal defense.** "A per-request `monotonic_buffer_resource` (seeded with a stack buffer), nodes that hold
`string_view`s into the input instead of owning strings, so they stay trivially destructible, and no destructors at all
('wink out'). The constraint, nothing in the tree may outlive the request, is enforced by the API: the tree type is
not copyable out of the request scope."
</details>

<details><summary><b>Chain 6 🔥 "Callbacks and object lifetime"</b></summary>

**Initial prompt.** "A network session registers a read callback capturing `this`. Sometimes the callback runs after the
session is destroyed. Fix it."

**L5 textbook answer.** "Unregister the callback in the destructor."

**Why L5 breaks.** Unregistering helps only if no callback is *already executing or queued* on another thread when the
destructor runs: a race between "callback starts" and "destructor finishes". With asynchronous I/O the completion can be
queued before the unregister and run after it.

**L7 principal defense.** "The session is `enable_shared_from_this` and created via `make_shared`. In-flight
operations capture `shared_from_this()` (strong, the session must survive until completion), optional observers capture
`weak_from_this()`. Destruction happens when the last operation completes. I'd verify it with a stress test that cancels
sessions while completions are in flight, under TSan."
</details>

<details><summary><b>Chain 7 🧊 "Why is the acquire a fence and not part of the RMW?"</b></summary>

**Initial prompt.** "Why not just `fetch_sub(1, acq_rel)` in `release()`?"

**L5 textbook answer.** "It's the same thing."

**Why L5 breaks.** It is correct, just more expensive. Acquire is needed only by the thread that will destroy the object,
on the last reference. `acq_rel` makes *every* decrement pay for acquire semantics. A release RMW plus a conditional
acquire fence pays acquire only once per object lifetime (Listing 5.7: `dmb ishld` sits only on the `count == 1`
path). On x86 there is no difference in code; on ARM64 the difference is an `ldaddal` vs `ldaddl` on every release.

**L7 principal defense.** "Pay for ordering only where an edge is needed: release on every decrement (publish my writes),
acquire once, before destruction (observe everyone's). libc++ uses `acq_rel` on the decrement (file 02), which is the
simpler, slightly more expensive choice."
</details>

<details><summary><b>Chain 8 ⚡ "long, int64_t, size_t?"</b></summary>

**Initial prompt.** "Your benchmark sums 10 million squares into a `long`. Any portability problem?"

**L5 textbook answer.** "No, `long` is 64-bit."

**Why L5 breaks.** On LP64 (Linux, macOS) yes. On LLP64 (Windows, including MinGW here) `long` is **32 bits**. The sum
overflowed, which is signed overflow, which is UB, with no warning (`-Wconversion` does not warn about overflow at run
time). This KB found exactly that in four listings during review, after their outputs had been published. One of them
(the ranges benchmark in Folder 04) changed its *conclusion* once the arithmetic was correct.

**L7 principal defense.** "Fixed-width types (`std::int64_t`, `std::uint64_t`) for anything whose range matters, `size_t`
/ `ptrdiff_t` for sizes and differences, and UBSan's `signed-integer-overflow` check in CI. 'Correct on my platform' is
not a property of the code."
</details>

---

## 6. Invariants checklist

- [ ] Self-referencing types derive from `enable_shared_from_this`, are created by factories, and never call
      `shared_from_this()` in constructors.
- [ ] Async operations capture strong references; observers capture weak references; no strong self-capture is stored
      inside the object.
- [ ] Hand-written refcounts use relaxed increments, release decrements and an acquire fence before destruction; a
      multi-threaded churn test checks the final count.
- [ ] Linked owning structures have iterative destruction, or live in arenas.
- [ ] Request-scoped graphs use arenas with trivially destructible nodes.
- [ ] Integer types with range requirements are fixed-width.

## 7. References

- P0033R1 (`enable_shared_from_this` fixes, `weak_from_this`): <https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0033r1.html>
- Boost.SmartPtr `intrusive_ptr`: <https://www.boost.org/doc/libs/release/libs/smart_ptr/doc/html/smart_ptr.html#intrusive_ptr>
- Linux `refcount_t` and its memory ordering: <https://www.kernel.org/doc/html/latest/core-api/refcount-vs-atomic.html>
- Herb Sutter, "Leak-Freedom in C++... By Default", CppCon 2016: <https://www.youtube.com/watch?v=JfmTagWcqoE>
- Anthony Williams, *C++ Concurrency in Action*, 2nd ed., ch. 5 (memory model) and 7 (reference counting in lock-free code).
