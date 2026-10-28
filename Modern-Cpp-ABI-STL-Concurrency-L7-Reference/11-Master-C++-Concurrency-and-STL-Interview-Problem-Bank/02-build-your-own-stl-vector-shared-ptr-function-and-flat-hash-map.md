# 02 · Build your own STL: `vector`, `shared_ptr`/`weak_ptr`, `function`, and a flat hash map

> **Scope.** "Implement `std::vector`" is the interview question that separates people who use the STL from people
> who understand it. The four implementations here are small enough to write on a whiteboard and complete enough to
> pass differential tests against the real thing. Each one is built around the property interviewers actually probe:
> the vector's strong exception guarantee and aliasing safety, the shared pointer's two counts and their memory
> orders, `function`'s type erasure and small-buffer rules, and the flat map's tombstones and load factor. Folders
> 03–05 explain how libstdc++ and libc++ do the same; this file shows you can do it.

| # | Listing | What it proves | Verified by |
|---|---|---|---|
| 11.16 | `b01_vector.cpp` | growth ×2 with 1,023 moves and 0 copies for noexcept moves; **copies (not moves) when the move can throw, and the strong guarantee when a copy fails mid-growth**; `push_back(v[0])` safe across reallocation | run, both compilers |
| 11.17 | `b02_shared_ptr.cpp` | separate vs single-allocation (`MakeShared`) control blocks; weak → strong without resurrection; the aliasing constructor; 4M concurrent copies, destroyed exactly once | run, both compilers |
| 11.18 | `b03_function.cpp` | a hand-written vtable, 24-byte small buffer: 0 allocations for small callables, heap for large; deep copy, pointer-stealing move; `bad_function_call` | run, both compilers |
| 11.19 | `b04_flat_hash_map.cpp` | Swiss-style control bytes, tombstones, 7/8 load factor; 2M random operations with 0 mismatches against `std::unordered_map`; lookups 2–2.4× faster | run, both compilers |

**Verification line.** As in file 01; GCC with `-fno-assume-sane-operators-new-delete` so the counting `operator new`
sees every allocation (Folder 03).

---

## 1. First principles

### 1.1 `vector` (Listing 11.16)

```cpp
// b01_vector.cpp - build-your-own std::vector: growth, the strong exception guarantee, move_if_noexcept, aliasing
#include <cstddef>
#include <cstdlib>
#include <memory>
#include <new>
#include <print>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

template <class T>
class Vector {
    T* data_ = nullptr;
    std::size_t size_ = 0, cap_ = 0;

    static T* allocate(std::size_t n) { return static_cast<T*>(::operator new(n * sizeof(T), std::align_val_t{alignof(T)})); }
    static void deallocate(T* p) noexcept { ::operator delete(p, std::align_val_t{alignof(T)}); }

    // Reallocate to `n` slots, then construct the new element with `make(slot)`, keeping the strong guarantee:
    // if anything throws, *this is unchanged. The new element is built FIRST, so `v.push_back(v[0])` is safe
    // even though v[0] lives in the old buffer we are about to leave.
    template <class Make>
    void grow_and_emplace(std::size_t n, Make make) {
        T* fresh = allocate(n);
        std::size_t built = 0;
        try {
            make(fresh + size_);                                    // 1. the new element (may read old storage)
            built = 1;
            for (std::size_t i = 0; i < size_; ++i) {               // 2. move only if that cannot throw, else copy
                ::new (static_cast<void*>(fresh + i)) T(std::move_if_noexcept(data_[i]));
                ++built;
            }
        } catch (...) {
            if (built > 0) std::destroy_at(fresh + size_);         // undo: destroy what we built, free, rethrow
            for (std::size_t i = 0; built > 1 && i < built - 1; ++i) std::destroy_at(fresh + i);
            deallocate(fresh);
            throw;
        }
        std::destroy(data_, data_ + size_);
        deallocate(data_);
        data_ = fresh;
        cap_ = n;
        ++size_;
    }

public:
    Vector() = default;
    Vector(const Vector& o) : data_(allocate(o.cap_ ? o.cap_ : 1)), cap_(o.cap_ ? o.cap_ : 1) {
        try {
            for (; size_ < o.size_; ++size_) ::new (static_cast<void*>(data_ + size_)) T(o.data_[size_]);
        } catch (...) {
            std::destroy(data_, data_ + size_);
            deallocate(data_);
            throw;
        }
    }
    Vector(Vector&& o) noexcept
        : data_(std::exchange(o.data_, nullptr)), size_(std::exchange(o.size_, 0)), cap_(std::exchange(o.cap_, 0)) {}
    Vector& operator=(Vector o) noexcept {   // copy-and-swap: strong guarantee for copy assignment, free for move
        swap(o);
        return *this;
    }
    ~Vector() {
        std::destroy(data_, data_ + size_);
        deallocate(data_);
    }
    void swap(Vector& o) noexcept {
        std::swap(data_, o.data_);
        std::swap(size_, o.size_);
        std::swap(cap_, o.cap_);
    }

    template <class... A>
    T& emplace_back(A&&... args) {
        if (size_ < cap_) {
            ::new (static_cast<void*>(data_ + size_)) T(std::forward<A>(args)...);
            return data_[size_++];
        }
        grow_and_emplace(cap_ ? 2 * cap_ : 1, [&](T* slot) { ::new (static_cast<void*>(slot)) T(std::forward<A>(args)...); });
        return data_[size_ - 1];
    }
    void push_back(const T& v) { emplace_back(v); }
    void push_back(T&& v) { emplace_back(std::move(v)); }
    void pop_back() noexcept { std::destroy_at(data_ + --size_); }
    void reserve(std::size_t n) {
        if (n <= cap_) return;
        Vector tmp;
        tmp.data_ = allocate(n);
        tmp.cap_ = n;
        for (; tmp.size_ < size_; ++tmp.size_)
            ::new (static_cast<void*>(tmp.data_ + tmp.size_)) T(std::move_if_noexcept(data_[tmp.size_]));
        swap(tmp);   // tmp now owns the old buffer and destroys it
    }
    T& operator[](std::size_t i) noexcept { return data_[i]; }
    const T& operator[](std::size_t i) const noexcept { return data_[i]; }
    std::size_t size() const noexcept { return size_; }
    std::size_t capacity() const noexcept { return cap_; }
    T* begin() noexcept { return data_; }
    T* end() noexcept { return data_ + size_; }
};

// A type whose copy can be told to fail, and whose move is NOT noexcept: reallocation must copy it.
struct Fragile {
    static inline int copies = 0, moves = 0, fail_at = -1;
    std::string s;
    explicit Fragile(std::string v) : s(std::move(v)) {}
    Fragile(const Fragile& o) : s(o.s) {
        if (copies++ == fail_at) throw std::runtime_error("copy failed");
    }
    Fragile(Fragile&& o) : s(std::move(o.s)) { ++moves; }   // may throw (not noexcept)
};
struct Movable {
    static inline int copies = 0, moves = 0;
    int v;
    explicit Movable(int x) : v(x) {}
    Movable(const Movable& o) : v(o.v) { ++copies; }
    Movable(Movable&& o) noexcept : v(o.v) { ++moves; }
};

int main() {
    {
        Vector<Movable> v;
        for (int i = 0; i < 1000; ++i) v.emplace_back(i);
        std::println("1,000 emplace_backs of a noexcept-movable type: {} moves, {} copies during reallocations; capacity {}",
                     Movable::moves, Movable::copies, v.capacity());
    }
    {
        Vector<Fragile> v;
        for (int i = 0; i < 8; ++i) v.emplace_back("item" + std::to_string(i));   // size 8, capacity 8
        Fragile::copies = 0;
        Fragile::fail_at = 5;   // the 6th copy during the next reallocation throws
        bool threw = false;
        try {
            v.emplace_back("ninth");
        } catch (const std::runtime_error&) {
            threw = true;
        }
        bool intact = v.size() == 8 && v.capacity() == 8;
        for (int i = 0; i < 8; ++i) intact &= v[static_cast<std::size_t>(i)].s == "item" + std::to_string(i);
        std::println("type with a throwing (non-noexcept) move: reallocation copied, the 6th copy threw: {}; vector unchanged "
                     "(strong guarantee): {}; moves used: {}",
                     threw, intact, Fragile::moves);
    }
    {
        Vector<std::string> v;
        v.push_back("the first element, long enough to live on the heap");
        for (int i = 0; i < 6; ++i) v.push_back(v[0]);   // aliases the buffer that reallocation leaves behind
        bool ok = v.size() == 7;
        for (const std::string& s : v) ok &= s == "the first element, long enough to live on the heap";
        Vector<std::string> copy = v;
        Vector<std::string> moved = std::move(copy);
        std::println("push_back(v[0]) across reallocations: all copies correct: {}; copy + move round trip size {}", ok,
                     moved.size());
    }
}
```

```text
1,000 emplace_backs of a noexcept-movable type: 1023 moves, 0 copies during reallocations; capacity 1024
type with a throwing (non-noexcept) move: reallocation copied, the 6th copy threw: true; vector unchanged (strong guarantee): true; moves used: 0
push_back(v[0]) across reallocations: all copies correct: true; copy + move round trip size 7
```

* **Raw storage, then construction.** The buffer comes from `::operator new` (aligned for `T`), and elements are
  constructed with placement new and destroyed with `std::destroy`. `size_` constructed elements live in `cap_` slots,
  and the rest is uninitialized memory.
* **`move_if_noexcept` is the strong guarantee.** During reallocation, moving elements out of the old buffer is
  irreversible: if the fifth move throws, the first four are already gutted. So the vector moves only when the move
  constructor is `noexcept` and otherwise *copies*, leaving the originals intact. Run 1: a noexcept-movable type was
  moved 1,023 times and never copied. Run 2: a type with a throwing move was copied, the sixth copy threw, and the
  vector was unchanged (size 8, capacity 8, all values intact). This is why `noexcept` on move constructors matters
  for performance (Folder 01, file 02).
* **Aliasing.** `v.push_back(v[0])` passes a reference *into the buffer about to be abandoned*. The listing constructs
  the new element in the new buffer *first*, while the old one is still alive, and only then moves the old elements
  over. Doing it the other way round reads a moved-from or destroyed element. All 7 copies were correct.
* **Copy assignment by value** (copy-and-swap): the copy happens before `*this` changes, giving the strong guarantee
  for free; move assignment costs a swap.
* **Growth factor.** ×2 here, as in libstdc++ and libc++, which gives amortized O(1) `push_back`. MSVC and folly's
  `fbvector` use ×1.5, which lets a later allocation reuse the sum of earlier freed blocks.

### 1.2 `shared_ptr` and `weak_ptr` (Listing 11.17)

```cpp
// b02_shared_ptr.cpp - build-your-own shared_ptr/weak_ptr: control block, make_shared, aliasing, thread-safe counts
#include <atomic>
#include <cstdlib>
#include <new>
#include <print>
#include <thread>
#include <utility>
#include <vector>

#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wmismatched-new-delete"   // false positive with replaced new/delete (Folder 03)
#endif
std::atomic<int> g_allocs{0};
void* operator new(std::size_t n) {
    g_allocs.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(n)) return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

// The control block: strong count, weak count (+1 held collectively by all strong owners), and two virtual hooks.
struct ControlBlock {
    std::atomic<long> strong{1}, weak{1};
    virtual void destroy_object() noexcept = 0;   // runs when strong hits 0
    virtual void free_block() noexcept = 0;       // runs when weak hits 0
    void add_strong() noexcept { strong.fetch_add(1, std::memory_order_relaxed); }   // relaxed: we already own one
    void release_strong() noexcept {
        if (strong.fetch_sub(1, std::memory_order_acq_rel) == 1) {   // acq_rel: see every other owner's writes
            destroy_object();
            release_weak();                                          // drop the strong owners' collective weak ref
        }
    }
    void add_weak() noexcept { weak.fetch_add(1, std::memory_order_relaxed); }
    void release_weak() noexcept {
        if (weak.fetch_sub(1, std::memory_order_acq_rel) == 1) free_block();
    }
    bool try_add_strong() noexcept {   // weak -> strong: only if the object is still alive (never resurrect 0)
        long n = strong.load(std::memory_order_relaxed);
        while (n != 0)
            if (strong.compare_exchange_weak(n, n + 1, std::memory_order_acq_rel, std::memory_order_relaxed)) return true;
        return false;
    }

protected:
    ~ControlBlock() = default;
};

template <class T>
struct SeparateBlock final : ControlBlock {   // SharedPtr(new T): object and block are two allocations
    T* p;
    explicit SeparateBlock(T* q) : p(q) {}
    void destroy_object() noexcept override { delete p; }
    void free_block() noexcept override { delete this; }
};
template <class T>
struct InlineBlock final : ControlBlock {   // MakeShared: ONE allocation; the object lives inside the block
    alignas(T) unsigned char storage[sizeof(T)];
    template <class... A>
    explicit InlineBlock(A&&... a) {
        ::new (static_cast<void*>(storage)) T(std::forward<A>(a)...);
    }
    T* get() noexcept { return std::launder(reinterpret_cast<T*>(storage)); }
    void destroy_object() noexcept override { get()->~T(); }   // memory stays until the last weak_ptr goes
    void free_block() noexcept override { delete this; }
};

template <class T>
class WeakPtr;

template <class T>
class SharedPtr {
    T* ptr_ = nullptr;             // what get() returns (may point INTO the owned object: aliasing)
    ControlBlock* cb_ = nullptr;   // what is owned
    template <class U>
    friend class SharedPtr;
    friend class WeakPtr<T>;
    template <class U, class... A>
    friend SharedPtr<U> MakeShared(A&&...);

public:
    SharedPtr() = default;
    explicit SharedPtr(T* p) : ptr_(p) {
        try {
            cb_ = new SeparateBlock<T>(p);
        } catch (...) {
            delete p;   // the constructor owns p even if the block allocation fails
            throw;
        }
    }
    template <class U>
    SharedPtr(const SharedPtr<U>& owner, T* alias) noexcept : ptr_(alias), cb_(owner.cb_) {   // aliasing constructor
        if (cb_) cb_->add_strong();
    }
    SharedPtr(const SharedPtr& o) noexcept : ptr_(o.ptr_), cb_(o.cb_) {
        if (cb_) cb_->add_strong();
    }
    SharedPtr(SharedPtr&& o) noexcept : ptr_(std::exchange(o.ptr_, nullptr)), cb_(std::exchange(o.cb_, nullptr)) {}
    SharedPtr& operator=(SharedPtr o) noexcept {   // copy-and-swap handles self-assignment and both cases
        std::swap(ptr_, o.ptr_);
        std::swap(cb_, o.cb_);
        return *this;
    }
    ~SharedPtr() {
        if (cb_) cb_->release_strong();
    }
    T* get() const noexcept { return ptr_; }
    T& operator*() const noexcept { return *ptr_; }
    T* operator->() const noexcept { return ptr_; }
    long use_count() const noexcept { return cb_ ? cb_->strong.load(std::memory_order_relaxed) : 0; }
    explicit operator bool() const noexcept { return ptr_ != nullptr; }
};

template <class T>
class WeakPtr {
    T* ptr_ = nullptr;
    ControlBlock* cb_ = nullptr;

public:
    WeakPtr() = default;
    WeakPtr(const SharedPtr<T>& s) noexcept : ptr_(s.ptr_), cb_(s.cb_) {
        if (cb_) cb_->add_weak();
    }
    WeakPtr(const WeakPtr& o) noexcept : ptr_(o.ptr_), cb_(o.cb_) {
        if (cb_) cb_->add_weak();
    }
    WeakPtr(WeakPtr&& o) noexcept : ptr_(std::exchange(o.ptr_, nullptr)), cb_(std::exchange(o.cb_, nullptr)) {}
    WeakPtr& operator=(WeakPtr o) noexcept {
        std::swap(ptr_, o.ptr_);
        std::swap(cb_, o.cb_);
        return *this;
    }
    ~WeakPtr() {
        if (cb_) cb_->release_weak();
    }
    SharedPtr<T> lock() const noexcept {
        SharedPtr<T> s;
        if (cb_ && cb_->try_add_strong()) {
            s.ptr_ = ptr_;
            s.cb_ = cb_;
        }
        return s;
    }
    bool expired() const noexcept { return !cb_ || cb_->strong.load(std::memory_order_acquire) == 0; }
};

template <class T, class... A>
SharedPtr<T> MakeShared(A&&... args) {
    auto* blk = new InlineBlock<T>(std::forward<A>(args)...);
    SharedPtr<T> s;
    s.ptr_ = blk->get();
    s.cb_ = blk;
    return s;
}

struct Tracked {
    static inline std::atomic<int> alive{0}, destroyed{0};
    int x = 7, y = 9;
    Tracked() { alive.fetch_add(1); }
    ~Tracked() {
        alive.fetch_sub(1);
        destroyed.fetch_add(1);
    }
};

int main() {
    {
        const int a0 = g_allocs.load();
        SharedPtr<Tracked> sep(new Tracked);
        const int separate = g_allocs.load() - a0;
        const int a1 = g_allocs.load();
        SharedPtr<Tracked> one = MakeShared<Tracked>();
        const int inline_ = g_allocs.load() - a1;
        std::println("SharedPtr(new T): {} allocations; MakeShared<T>(): {} allocation", separate, inline_);
    }
    {
        WeakPtr<Tracked> w;
        {
            SharedPtr<Tracked> s = MakeShared<Tracked>();
            w = WeakPtr<Tracked>(s);
            SharedPtr<Tracked> again = w.lock();
            std::println("while owned: use_count {}, weak lock() works: {}", s.use_count(), again ? "yes" : "no");
        }
        std::println("after the last owner: object destroyed: {}, weak expired: {}, lock() -> {}",
                     Tracked::alive.load() == 0 ? "yes" : "no", w.expired(), w.lock() ? "an object" : "empty");
    }
    {
        SharedPtr<int> member;
        {
            SharedPtr<Tracked> parent = MakeShared<Tracked>();
            member = SharedPtr<int>(parent, &parent->y);   // aliasing: points at a member, owns the parent
        }
        std::println("aliasing SharedPtr<int> to a member keeps the parent alive: value {}, parent alive: {}", *member,
                     Tracked::alive.load() == 1 ? "yes" : "no");
    }
    {
        Tracked::destroyed = 0;
        SharedPtr<Tracked> shared = MakeShared<Tracked>();
        {
            std::vector<std::jthread> ts;
            for (int t = 0; t < 4; ++t)
                ts.emplace_back([shared] {   // each thread copies and drops the pointer a million times
                    for (int i = 0; i < 1'000'000; ++i) {
                        SharedPtr<Tracked> c = shared;
                        if (c->x != 7) std::abort();
                    }
                });
        }
        const long count_before = shared.use_count();
        shared = SharedPtr<Tracked>();
        std::println("4 threads x 1,000,000 copies: use_count back to {} before the reset; destroyed exactly once: {}",
                     count_before, Tracked::destroyed.load() == 1 ? "yes" : "NO");
    }
}
```

```text
SharedPtr(new T): 2 allocations; MakeShared<T>(): 1 allocation
while owned: use_count 2, weak lock() works: yes
after the last owner: object destroyed: yes, weak expired: true, lock() -> empty
aliasing SharedPtr<int> to a member keeps the parent alive: value 9, parent alive: yes
4 threads x 1,000,000 copies: use_count back to 1 before the reset; destroyed exactly once: yes
```

```text
   SharedPtr<T> { T* ptr; ControlBlock* cb; }          ControlBlock { strong, weak, vptr }
                     |                                   strong: number of SharedPtrs     -> 0: destroy the T
                     +-- ptr may point INTO the object   weak:   number of WeakPtrs + 1   -> 0: free the block
                         (aliasing constructor)          (the +1 is held collectively by all strong owners)

   SharedPtr(new T): two allocations, [block] -> [T]      MakeShared<T>(): one allocation, [block | T inline]
```

* **Two counts, and the +1.** The object dies when `strong` reaches 0. The *block* dies when `weak` reaches 0, and all
  strong owners together hold one weak reference. The last strong owner destroys the object and then drops that weak
  reference, so a `WeakPtr` can still safely inspect the block after the object is gone. With `MakeShared` the
  object's memory is part of the block and is freed only when the last `WeakPtr` goes, the "zombie" memory of Folder 05.
* **Memory orders:** increments are relaxed (the thread incrementing already owns a reference, so the object can't
  die meanwhile). Decrements are `acq_rel`: the release half publishes this owner's writes, and the acquire half,
  on the final decrement, sees every other owner's writes before the destructor runs. 4 threads × 1M copies, destroyed
  exactly once.
* **`lock()` must never resurrect.** Weak → strong is a CAS loop that refuses to increment from 0. A plain `fetch_add`
  would turn 0 into 1 on an object that is already being destroyed.
* **The aliasing constructor** shares ownership of one object and points at another, here a member. The parent stays
  alive (value 9, parent alive: yes) as long as the member pointer exists.
* **Exception safety in `SharedPtr(T*)`:** if allocating the control block throws, the constructor deletes `p`. The
  constructor took ownership, so it must not leak.

### 1.3 `function` (Listing 11.18)

```cpp
// b03_function.cpp - build-your-own std::function: type erasure through a static "vtable", small-buffer optimization
#include <atomic>
#include <cstddef>
#include <cstdlib>
#include <functional>
#include <memory>
#include <new>
#include <print>
#include <string>
#include <type_traits>
#include <utility>

#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC diagnostic ignored "-Wmismatched-new-delete"   // false positive with replaced new/delete (Folder 03)
#endif
std::atomic<int> g_allocs{0};
void* operator new(std::size_t n) {
    g_allocs.fetch_add(1, std::memory_order_relaxed);
    if (void* p = std::malloc(n)) return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

template <class Sig>
class Function;

template <class R, class... Args>
class Function<R(Args...)> {
    static constexpr std::size_t kBuf = 3 * sizeof(void*);   // 24 bytes of inline storage
    // One static table of function pointers per stored callable type: a hand-written vtable.
    struct Ops {
        R (*invoke)(void*, Args&&...);
        void (*copy)(const void* src, void* dst);   // copy-construct into dst's storage
        void (*move)(void* src, void* dst) noexcept;
        void (*destroy)(void*) noexcept;
    };
    template <class F>
    static constexpr bool kInline = sizeof(F) <= kBuf && alignof(F) <= alignof(std::max_align_t) &&
                                    std::is_nothrow_move_constructible_v<F>;   // move must not throw to stay inline

    template <class F>
    static F* target(void* storage) {
        if constexpr (kInline<F>) return std::launder(reinterpret_cast<F*>(storage));
        else return *static_cast<F**>(storage);   // heap: the buffer holds a pointer
    }
    template <class F>
    static constexpr Ops ops_for{
        [](void* s, Args&&... a) -> R { return std::invoke(*target<F>(s), std::forward<Args>(a)...); },
        [](const void* src, void* dst) {
            const F& f = *target<F>(const_cast<void*>(src));
            if constexpr (kInline<F>) ::new (dst) F(f);
            else *static_cast<F**>(dst) = new F(f);
        },
        [](void* src, void* dst) noexcept {
            if constexpr (kInline<F>) {
                ::new (dst) F(std::move(*target<F>(src)));
                target<F>(src)->~F();
            } else {
                *static_cast<F**>(dst) = *static_cast<F**>(src);   // steal the heap pointer
            }
        },
        [](void* s) noexcept {
            if constexpr (kInline<F>) target<F>(s)->~F();
            else delete target<F>(s);
        }};

    alignas(std::max_align_t) unsigned char buf_[kBuf];
    const Ops* ops_ = nullptr;

public:
    Function() = default;
    template <class F, class D = std::decay_t<F>>
        requires(!std::is_same_v<D, Function> && std::is_invocable_r_v<R, D&, Args...>)
    Function(F&& f) : ops_(&ops_for<D>) {
        if constexpr (kInline<D>) ::new (static_cast<void*>(buf_)) D(std::forward<F>(f));
        else *reinterpret_cast<D**>(buf_) = new D(std::forward<F>(f));
    }
    Function(const Function& o) : ops_(o.ops_) {
        if (ops_) ops_->copy(o.buf_, buf_);
    }
    Function(Function&& o) noexcept : ops_(std::exchange(o.ops_, nullptr)) {
        if (ops_) ops_->move(o.buf_, buf_);
    }
    Function& operator=(Function o) noexcept {
        this->~Function();
        ::new (this) Function(std::move(o));
        return *this;
    }
    ~Function() {
        if (ops_) ops_->destroy(buf_);
    }
    R operator()(Args... a) const {
        if (!ops_) throw std::bad_function_call();
        return ops_->invoke(const_cast<unsigned char*>(buf_), std::forward<Args>(a)...);
    }
    explicit operator bool() const noexcept { return ops_ != nullptr; }
};

int main() {
    int base = 10;
    auto small = [base](int x) { return base + x; };                    // 4 bytes of captures: inline
    auto large = [s = std::string(64, 'x'), base](int x) { return static_cast<int>(s.size()) + base + x; };
    std::println("sizeof: Function {} B, std::function {} B; small lambda {} B, large lambda {} B", sizeof(Function<int(int)>),
                 sizeof(std::function<int(int)>), sizeof(small), sizeof(large));
    int a0 = g_allocs.load();
    Function<int(int)> f1 = small;
    const int small_allocs = g_allocs.load() - a0;
    a0 = g_allocs.load();
    Function<int(int)> f2 = large;    // too big for 24 bytes: the callable goes to the heap
    const int large_allocs = g_allocs.load() - a0;
    std::println("constructing from the small lambda: {} allocations; from the large one: {} (its string's copy + the heap box)",
                 small_allocs, large_allocs);
    Function<int(int)> f3 = f2;                  // deep copy of the heap callable
    Function<int(int)> f4 = std::move(f2);       // steals the heap pointer: no allocation, no copy
    std::println("calls: f1(5) = {}, f3(5) = {}, f4(5) = {}; moved-from f2 is empty: {}", f1(5), f3(5), f4(5), !f2);
    Function<int(int)> empty;
    try {
        (void)empty(1);
    } catch (const std::bad_function_call&) {
        std::println("calling an empty Function throws std::bad_function_call, as std::function does");
    }
}
```

GCC, then Clang:

```text
sizeof: Function 32 B, std::function 32 B; small lambda 4 B, large lambda 40 B
constructing from the small lambda: 0 allocations; from the large one: 2 (its string's copy + the heap box)
calls: f1(5) = 15, f3(5) = 79, f4(5) = 79; moved-from f2 is empty: true
calling an empty Function throws std::bad_function_call, as std::function does
sizeof: Function 32 B, std::function 48 B; small lambda 4 B, large lambda 32 B
constructing from the small lambda: 0 allocations; from the large one: 2 (its string's copy + the heap box)
calls: f1(5) = 15, f3(5) = 79, f4(5) = 79; moved-from f2 is empty: true
calling an empty Function throws std::bad_function_call, as std::function does
```

* **Type erasure by hand:** one `static constexpr Ops` table per stored callable type, holding invoke, copy, move and
  destroy function pointers. `Function` stores a pointer to the table plus 24 bytes of inline storage, 32 bytes in
  total, the same as libstdc++'s `std::function` and smaller than libc++'s 48.
* **Inline only if moving can't throw.** A `Function`'s move is `noexcept`, so moving an inline callable must be too;
  types with throwing moves go to the heap, where moving is stealing a pointer. libstdc++ keeps a callable inline only if
  it is at most 16 bytes and trivially copyable; libc++ up to 24 bytes if nothrow-copyable (Folder 04, file 03).
* **Measured:** the 4-byte lambda allocated nothing. The 40-byte lambda (32 on libc++, whose `std::string` is 24
  bytes) allocated twice: the heap box and the copy of its string. The moved-from `Function` is empty, and calling an
  empty one throws `bad_function_call`.

### 1.4 A flat hash map (Listing 11.19)

```cpp
// b04_flat_hash_map.cpp - build-your-own flat hash map: open addressing with 1-byte control tags (Swiss-table style)
#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <print>
#include <random>
#include <unordered_map>
#include <utility>
#include <vector>

// Each slot has a control byte: kEmpty, kDeleted (a tombstone), or 0..127 = the low 7 bits of the hash ("H2").
// A lookup compares control bytes first (one byte per probe, mostly in one cache line) and touches a key only
// when its 7-bit tag matches: 1 in 128 false positives. The high bits ("H1") choose the starting slot.
template <class K, class V>
class FlatHashMap {
    static constexpr std::int8_t kEmpty = -128, kDeleted = -2;
    std::unique_ptr<std::int8_t[]> ctrl_;
    std::unique_ptr<std::optional<std::pair<K, V>>[]> slots_;
    std::size_t cap_ = 0, size_ = 0, used_ = 0;   // used_ = live + tombstones: what the load factor must bound

    static std::uint64_t hash(const K& k) {
        std::uint64_t h = std::hash<K>{}(k);   // identity for integers in both libraries: mix it (Folder 03)
        h ^= h >> 33;
        h *= 0xff51afd7ed558ccdULL;
        h ^= h >> 33;
        h *= 0xc4ceb9fe1a85ec53ULL;
        return h ^ (h >> 33);
    }
    static std::int8_t h2(std::uint64_t h) { return static_cast<std::int8_t>(h & 0x7F); }

    void rehash(std::size_t new_cap) {
        auto old_ctrl = std::move(ctrl_);
        auto old_slots = std::move(slots_);
        const std::size_t old_cap = cap_;
        ctrl_ = std::make_unique<std::int8_t[]>(new_cap);
        slots_ = std::make_unique<std::optional<std::pair<K, V>>[]>(new_cap);
        std::fill_n(ctrl_.get(), new_cap, kEmpty);
        cap_ = new_cap;
        size_ = used_ = 0;
        for (std::size_t i = 0; i < old_cap; ++i)
            if (old_ctrl[i] >= 0) insert_or_assign(std::move(old_slots[i]->first), std::move(old_slots[i]->second));
    }

public:
    FlatHashMap() { rehash(16); }
    bool insert_or_assign(K k, V v) {   // returns true if inserted, false if assigned
        if ((used_ + 1) * 8 > cap_ * 7) rehash(size_ * 2 >= cap_ ? cap_ * 2 : cap_);   // 7/8 max load (tombstones count)
        const std::uint64_t h = hash(k);
        std::size_t first_free = cap_;
        for (std::size_t i = (h >> 7) & (cap_ - 1);; i = (i + 1) & (cap_ - 1)) {   // linear probing
            const std::int8_t c = ctrl_[i];
            if (c == h2(h) && slots_[i]->first == k) {
                slots_[i]->second = std::move(v);
                return false;
            }
            if (c == kDeleted && first_free == cap_) first_free = i;   // reuse the first tombstone we passed
            if (c == kEmpty) {
                const std::size_t at = first_free != cap_ ? first_free : i;
                if (ctrl_[at] == kEmpty) ++used_;
                ctrl_[at] = h2(h);
                slots_[at].emplace(std::move(k), std::move(v));
                ++size_;
                return true;
            }
        }
    }
    V* find(const K& k) {
        const std::uint64_t h = hash(k);
        for (std::size_t i = (h >> 7) & (cap_ - 1);; i = (i + 1) & (cap_ - 1)) {
            const std::int8_t c = ctrl_[i];
            if (c == kEmpty) return nullptr;                         // probe chains end only at EMPTY, not DELETED
            if (c == h2(h) && slots_[i]->first == k) return &slots_[i]->second;
        }
    }
    bool erase(const K& k) {
        const std::uint64_t h = hash(k);
        for (std::size_t i = (h >> 7) & (cap_ - 1);; i = (i + 1) & (cap_ - 1)) {
            const std::int8_t c = ctrl_[i];
            if (c == kEmpty) return false;
            if (c == h2(h) && slots_[i]->first == k) {
                ctrl_[i] = kDeleted;                                 // a tombstone keeps later keys reachable
                slots_[i].reset();
                --size_;
                return true;
            }
        }
    }
    std::size_t size() const { return size_; }
    std::size_t capacity() const { return cap_; }
};

int main() {
    // Differential test: 2,000,000 random operations against std::unordered_map.
    FlatHashMap<std::uint64_t, std::uint64_t> mine;
    std::unordered_map<std::uint64_t, std::uint64_t> ref;
    std::mt19937_64 rng(1);
    std::uint64_t mismatches = 0;
    for (int op = 0; op < 2'000'000; ++op) {
        const std::uint64_t k = rng() % 50'000, r = rng() % 10;
        if (r < 5) {
            const bool a = mine.insert_or_assign(k, static_cast<std::uint64_t>(op));
            const bool b = ref.insert_or_assign(k, static_cast<std::uint64_t>(op)).second;
            mismatches += a != b;
        } else if (r < 8) {
            const std::uint64_t* a = mine.find(k);
            const auto it = ref.find(k);
            mismatches += (a == nullptr) != (it == ref.end()) || (a && *a != it->second);
        } else {
            mismatches += mine.erase(k) != (ref.erase(k) == 1);
        }
    }
    std::println("2,000,000 random insert/find/erase ops vs std::unordered_map: mismatches {}, final sizes {} / {}", mismatches,
                 mine.size(), ref.size());
    // Lookup speed on 1M keys (half hits, half misses).
    FlatHashMap<std::uint64_t, std::uint64_t> fm;
    std::unordered_map<std::uint64_t, std::uint64_t> um;
    for (std::uint64_t i = 0; i < 1'000'000; ++i) {
        fm.insert_or_assign(i * 2654435761ULL, i);
        um.insert_or_assign(i * 2654435761ULL, i);
    }
    auto time_lookups = [&](auto& m) {
        std::uint64_t hits = 0;
        std::mt19937_64 r2(9);
        const auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < 2'000'000; ++i) {
            const std::uint64_t k = (r2() % 2'000'000) * 2654435761ULL;   // half of these were inserted
            if constexpr (requires { m.find(k) == nullptr; }) hits += m.find(k) != nullptr;
            else hits += m.find(k) != m.end();
        }
        const std::chrono::duration<double, std::nano> d = std::chrono::steady_clock::now() - t0;
        return std::pair{d.count() / 2'000'000, hits};
    };
    const auto [flat_ns, flat_hits] = time_lookups(fm);
    const auto [std_ns, std_hits] = time_lookups(um);
    std::println("1M keys, 2M lookups: flat map {:.1f} ns, std::unordered_map {:.1f} ns; same hits: {}", flat_ns, std_ns,
                 flat_hits == std_hits ? "yes" : "NO");
}
```

GCC, then Clang:

```text
2,000,000 random insert/find/erase ops vs std::unordered_map: mismatches 0, final sizes 35902 / 35902
1M keys, 2M lookups: flat map 27.9 ns, std::unordered_map 55.9 ns; same hits: yes
2,000,000 random insert/find/erase ops vs std::unordered_map: mismatches 0, final sizes 35902 / 35902
1M keys, 2M lookups: flat map 33.9 ns, std::unordered_map 79.4 ns; same hits: yes
```

```text
   ctrl bytes:  [ 0x15 ][EMPTY ][ 0x3a ][DELETED][ 0x15 ][ 0x02 ][EMPTY ] ...    one byte per slot
   slots:       [k1,v1][      ][k2,v2][       ][k3,v3][k4,v4][      ] ...
   lookup(k): start at H1(hash) and probe linearly; compare the CONTROL byte with H2(hash) (7 bits) first,
              the key only on a match; stop at EMPTY (never at DELETED).
```

* **Control bytes do most of the work.** A probe reads one byte per slot, usually within one cache line, and touches
  a key only when its 7-bit tag matches (1 false positive in 128). Abseil's Swiss tables compare 16 control bytes with
  one SSE2 instruction; this scalar version keeps the same layout and decisions (Folder 03, file 03).
* **Tombstones.** Erasing writes `DELETED`, not `EMPTY`. An `EMPTY` in the middle of a probe chain would make later
  keys unreachable, the same rule as the lock-free map of Folder 09. Insert reuses the first tombstone it passes.
* **The load factor counts tombstones** (`used_`). Erase-heavy workloads otherwise fill the table with tombstones and
  lookups degrade toward O(n). When tombstones dominate, the map rehashes at the *same* capacity to clear them.
* **Differential testing:** 2M random inserts, finds and erases against `std::unordered_map`, with 0 mismatches and the
  same final size. Lookups: 25–34 ns vs 50–79 ns for `std::unordered_map` over two runs, because there is no pointer
  chase into a node per probe.

---

## 2. Evolution table

| Component | C++11 | C++14 | C++17 | C++20 | C++23 | C++26 |
|---|---|---|---|---|---|---|
| vector | move semantics, `move_if_noexcept`, `emplace_back` | — | `emplace_back` returns a reference; allocator-aware polymorphic `pmr::vector` | `constexpr` vector | `std::flat_map`/`flat_set` (sorted vector adaptors) | `std::inplace_vector` |
| shared_ptr | `shared_ptr`, `weak_ptr`, `make_shared` | — | `shared_ptr<T[]>`, `weak_from_this` | `make_shared` for arrays, `atomic<shared_ptr>` | — | — |
| function | `std::function` | — | — | — | `std::move_only_function` | `std::function_ref`, `std::copyable_function` |
| hash maps | `unordered_map` (node-based, stable references) | heterogeneous lookup for ordered containers | `try_emplace`, `insert_or_assign`, node handles | heterogeneous lookup for unordered containers | `flat_map` (sorted, not hashed) | — (flat hash maps remain library-provided: Abseil, Boost.Unordered) |

---

## 3. Production blueprints

| Situation | Subtle buggy way | Production-hardened way |
|---|---|---|
| element type stored in vectors | move constructor not `noexcept` (every reallocation copies) | `noexcept` moves (or `= default`), checked with `static_assert(std::is_nothrow_move_constructible_v<T>)` |
| custom container growth | move old elements, then construct the new one from a reference | construct the new element first (aliasing), copy if the move may throw |
| shared ownership | `SharedPtr(new T)` with a separately created block (2 allocations) | `make_shared` (1 allocation); but big objects observed by long-lived `weak_ptr`s use separate allocation |
| refcount decrement | relaxed `fetch_sub` | `acq_rel` (or release + acquire fence on zero) |
| weak → strong | `fetch_add` on the strong count | CAS loop that refuses 0 |
| storing callables on a hot path | `std::function` with captures that don't fit (heap per construction) | small captures, `function_ref` (no ownership), or `move_only_function` |
| erase-heavy hash maps | treat erased slots as empty, or ignore tombstones in the load factor | tombstones + load factor counting them + same-size rehash |
| hash map references kept across inserts | pointers into a flat map | flat maps invalidate on rehash; use node-based maps or indices when stability is needed |

---

## 4. Failure modes

| Symptom | Root cause | Detection |
|---|---|---|
| vector reallocation slow, profiles show copy constructors | `T`'s move constructor not `noexcept` | `static_assert`; count copies as Listing 11.16 does |
| corrupted element after `v.push_back(v[0])` | old elements moved before the new one was constructed | aliasing test |
| exception during growth leaves a half-moved vector | moves used for a type whose move can throw | strong-guarantee test with a failing copy |
| object destroyed twice or leaked | refcount races; resurrecting `lock()` | 4-thread copy stress; destroy counters |
| memory not returned long after the last `shared_ptr` | `make_shared` + lingering `weak_ptr`s | heap profiles (Folder 05) |
| hash map lookups slow after many erases | tombstones not counted, never cleared | probe-length metrics |
| dangling reference into a hash map | flat map rehashed | ASan; don't keep references across inserts |

---

## 5. Adversarial L7 bar-raiser chains

<details><summary><b>Chain 1 🔥 "Why does vector copy my type when it grows?"</b></summary>

**Initial prompt.** "Our `std::vector<Order>` reallocation shows millions of `Order` copy-constructor calls in the
profile, even though `Order` has a move constructor. Why?"

**L5 textbook answer.** "The vector must be using `push_back(const T&)`; use `emplace_back`."

**Why L5 breaks.** Growth uses `move_if_noexcept`: if `Order`'s move constructor isn't `noexcept`, the vector *copies*
the old elements, to keep the strong exception guarantee (Listing 11.16, run 2: copies, then a failed copy left the
vector untouched). A user-declared move constructor without `noexcept`, or a member whose move isn't `noexcept`,
triggers this.

**L7 principal defense.** "Make moves `noexcept` (or `= default` with noexcept members) and
`static_assert(std::is_nothrow_move_constructible_v<Order>)` next to the type. Run 1 shows the result: 1,023 moves, 0
copies for 1,000 insertions."
</details>

<details><summary><b>Chain 2 ⚡ "Implement push_back"</b></summary>

**Initial prompt.** "Write `push_back(const T& x)` for your vector, including reallocation."

**L5 textbook answer.** "If full, allocate double, move the old elements over, free the old buffer, then construct
`x` at the end."

**Why L5 corrupts memory on ARM64.** If `x` refers to an element of this vector (`v.push_back(v[0])`), it refers into
the old buffer, which this order of operations moves from (leaving a moved-from string) and frees before `x` is read: a
read of freed memory on any architecture. And if moving can throw, the strong guarantee is lost.

**L7 principal defense.** "Allocate, construct the new element from `x` in the new buffer *first* while the old buffer
is alive, then `move_if_noexcept` the old elements, then destroy and free the old buffer, with rollback if anything
throws (Listing 11.16's `grow_and_emplace`). Seven aliasing push_backs across reallocations stayed correct."
</details>

<details><summary><b>Chain 3 🧊 "Growth factor 2 or 1.5?"</b></summary>

**Initial prompt.** "libstdc++ and libc++ grow vectors ×2, MSVC ×1.5. Which is right?"

**L5 textbook answer.** "×2 is faster because it reallocates less."

**Why L5 breaks.** Both are amortized O(1). ×2 does fewer reallocations, but a new buffer of size 2^k can never fit in
the sum of the previously freed blocks (1 + 2 + … + 2^(k-1) < 2^k), so an allocator can't reuse them for the vector. With
×1.5 the freed blocks eventually sum to more than the next request. ×1.5 wastes less memory, ×2 copies less.

**L7 principal defense.** "It's a memory-vs-copies trade-off, and both are defensible. More important in practice:
`reserve()` when the size is known, `shrink_to_fit()` after a build phase, and `noexcept` moves so that each
reallocation is a move."
</details>

<details><summary><b>Chain 4 🔥 "Why does shared_ptr have two counts?"</b></summary>

**Initial prompt.** "Why does a control block keep a weak count at all, and why does `make_shared`'s memory sometimes
stay allocated after the object is destroyed?"

**L5 textbook answer.** "The weak count is just for `weak_ptr::use_count`."

**Why L5 corrupts memory on ARM64.** A `weak_ptr` must be able to ask "is the object alive?" after it died, which means
reading the strong count *in the block*. The block must outlive the object, until the last `weak_ptr` is gone. Without
the weak count, the last `shared_ptr` would free the block and every `weak_ptr` would read freed memory. With
`make_shared` the object lives inside the block, so its memory can't be freed until the last `weak_ptr` dies
(Folder 05's zombie memory).

**L7 principal defense.** "Strong count: object lifetime. Weak count + 1 for the strong owners: block lifetime
(Listing 11.17). Large objects with long-lived weak observers use separate allocation so their memory goes as soon as
the last strong owner does."
</details>

<details><summary><b>Chain 5 ⚡ "Which memory orders for the reference counts?"</b></summary>

**Initial prompt.** "Implement the counts with `std::atomic<long>`. Which orders for increment and decrement?"

**L5 textbook answer.** "`seq_cst` for both, to be safe."

**Why L5 breaks.** `seq_cst` is correct but pays for ordering nobody needs on increments; relaxed everywhere is
cheaper but wrong. Increments can be relaxed: the incrementing thread already holds a reference, so the object can't
die. The decrement must be release (this owner's writes happen before destruction), and the final one must acquire
(the destroying thread sees every owner's writes). With relaxed decrements on ARM64, the destructor can run while
another owner's last writes to the object are still in flight.

**L7 principal defense.** "Relaxed increment, `acq_rel` decrement, or release decrement plus an acquire fence only when
the count hits zero, the libstdc++/Folder 05 pattern. Weak→strong is a CAS that refuses 0. Listing 11.17's 4-thread
stress destroys the object exactly once."
</details>

<details><summary><b>Chain 6 🧊 "How does std::function store a lambda?"</b></summary>

**Initial prompt.** "How can `std::function<int(int)>` store any callable in a fixed-size object, and when does it
allocate?"

**L5 textbook answer.** "It stores a pointer to the lambda."

**Why L5 breaks.** It owns a *copy* of the callable, so a pointer to the caller's lambda would dangle. The callable's
type is erased behind a table of function pointers (invoke, copy, move, destroy). Small callables live in an inline
buffer, larger ones on the heap, and the threshold differs by library: libstdc++ inlines ≤16-byte trivially copyable
types, libc++ ≤24-byte nothrow-copyable ones (Folder 04). Listing 11.18: 0 allocations for a 4-byte lambda, 2 for a
40-byte one.

**L7 principal defense.** "Type erasure = a manual vtable + small-buffer optimization, with the 'inline only if move is
noexcept' rule so `function`'s own move can be `noexcept`. On hot paths: keep captures small, or use `function_ref`
(non-owning, 16 bytes) when the callable outlives the call, or `move_only_function` for move-only captures."
</details>

<details><summary><b>Chain 7 🔥 "Erase from an open-addressing hash map"</b></summary>

**Initial prompt.** "Implement `erase` for your linear-probing hash map."

**L5 textbook answer.** "Find the slot and mark it empty."

**Why L5 breaks.** Lookups stop at the first empty slot. Marking an erased slot empty cuts every probe chain that
passed through it, and keys stored after it become unreachable: `find` returns "absent" for keys that are present. The
differential test would show mismatches immediately.

**L7 principal defense.** "A tombstone (`DELETED`): lookups probe past it, inserts reuse it. Tombstones count toward the
load factor, and a same-size rehash clears them when they dominate (Listing 11.19: 0 mismatches in 2M random
operations against `std::unordered_map`). Alternatively backward-shift deletion for linear probing (no tombstones,
more moves)."
</details>

<details><summary><b>Chain 8 ⚡ "Why is a flat map faster than std::unordered_map?"</b></summary>

**Initial prompt.** "Your flat map does 25–34 ns lookups vs 50–79 ns for `std::unordered_map`. Where does the
difference come from, and what do you give up?"

**L5 textbook answer.** "Open addressing is just a better algorithm."

**Why L5 breaks.** The algorithmic complexity is the same. The difference is memory. `std::unordered_map` is
node-based: each element is a separate allocation, reached through a bucket pointer and a `next` chain, so a lookup
costs one or more cache misses into scattered nodes. The flat map probes a contiguous control-byte array and touches
the key only on a 7-bit tag match. What you give up: **reference and pointer stability** (a rehash moves every element),
cheap node extraction, and the guaranteed bucket interface that the standard specifies for `unordered_map` (which is
exactly why the standard containers can't switch).

**L7 principal defense.** "Use flat maps (Abseil, Boost.Unordered's `unordered_flat_map`) by default for
value-semantics lookups, and node-based maps when references must stay valid across inserts or when elements are huge
and not movable. And benchmark with realistic, scrambled keys (Folder 09, file 03)."
</details>

---

## 6. Invariants checklist

- [ ] Containers construct new elements before relocating old ones, and relocate with `move_if_noexcept`.
- [ ] Every operation has a stated exception guarantee, and the strong ones are tested with a throwing type.
- [ ] Reference counts: relaxed increments, `acq_rel` decrements, CAS-from-nonzero for weak→strong.
- [ ] Constructors that take ownership free the resource if they throw.
- [ ] Type-erased callables keep inline storage only for nothrow-movable types.
- [ ] Open-addressing maps use tombstones, count them in the load factor, and are differentially tested.

## 7. References

- [vector.modifiers], [util.smartptr.shared], [func.wrap.func]: <https://eel.is/c++draft/containers>
- A. Alexandrescu, folly `FBVector` (growth factor rationale): <https://github.com/facebook/folly/blob/main/folly/docs/FBVector.md>
- Abseil, "Swiss Tables Design Notes": <https://abseil.io/about/design/swisstables>
- M. Kulukundis, "Designing a Fast, Efficient, Cache-friendly Hash Table, Step by Step", CppCon 2017 (talk)
- H. Sutter, "GotW #102: Exception-Safe Function Calls" / exception-safety guarantees: <https://herbsutter.com/gotw/_102/>
