# PR07 · C++20 Coroutine Dangling Reference, `noexcept` Move and `weak_ptr` Leak

> **What this module is.** A media-service PR that moves thumbnail rendering onto C++20 coroutines so decoding stops blocking the event loop. It also adds a move constructor "to stop copying pixels," weak-pointer viewer subscriptions, and a self-retrying job. It hides **7 defects (3 Sev-1)**: lifetime and ownership bugs that compile cleanly under `-Wall -Wextra -Wpedantic -Werror` on both GCC 16 and Clang 21 and pass the author's tests. Several would be undefined behavior if executed. The probes *detect* each hazard (a dead argument, a doubly-released block, a pinned allocation) without executing UB.

| Artifact | What it is | Verified |
|---|---|---|
| `pr07-diff` | `buffer.hpp` (move ctor), new `task.hpp`, `thumbnails.hpp` rewritten (coroutines, viewers, jobs), test rewritten: 202 diff lines | `git diff --no-index` from compiled sources |
| `thumbnails_test.cpp` (author's) | 4 tests: async render + cache, viewer notification, buffers into containers, job runs once | **4/4 pass** on GCC and Clang (§4) |
| `probes.cpp` | 7 probes: temporaries passed to `render`, cancelled renders, corrupt input, vector growth, 1,000 closed viewers, released job, moved-from buffer | each shows the defect on the PR and its absence on the fix (§8) |
| Fixed code | Coroutine params by value, `Task` owns and destroys its frame, exceptions rethrown, `noexcept` move that empties its source, pruned weak observers, weak self-capture | fixed suite 5/5; PR's own tests against the fix 4/4 |

**Verification.** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (Zig 0.16, libc++), `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`. Each test and probe binary is built and run with **both** compilers, and the outputs are identical across them. The pixel pool is a test double of the production slab allocator: a naive free list, so a double release shows up as aliasing rather than as a crash.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L3 Lifetimes | F1 coroutine reference parameters, F2 `Task` never destroys its frame, F7 moved-from buffer still owns its block | Coroutines look like functions, and moves look like optimizations |
| L3 Failure paths | F3 `unhandled_exception` swallows decode errors | An empty function body reads as "nothing to do" |
| L7 Performance and memory | F4 non-`noexcept` move, so `vector` growth deep-copies, F5 unpruned `weak_ptr`s pin `make_shared` storage, F6 `shared_from_this` cycle | Weak pointers and `enable_shared_from_this` look like the cure for leaks |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "`const&` parameters avoid copies." | In a coroutine they outlive their referents. |
| "The handle is cleaned up somewhere." | `~Task() = default` on a raw handle cleans up nothing. |
| "We'll add error handling later." | `unhandled_exception() {}` *is* the error handling: silence. |
| "I added a move constructor, so vectors move." | Not unless it's `noexcept`. |
| "Weak pointers can't leak." | They pin the control block, and with `make_shared` the whole object's memory. |

---

## 1. First principles

1. **A coroutine outlives its call expression.** C++ Core Guidelines CP.53, *Parameters to coroutines should not be passed by reference*: "Once a coroutine reaches the first suspension point … any parameters passed by reference are dangling." With `initial_suspend` returning `suspend_always`, the body doesn't start until `start()`, by which time every temporary argument is already destroyed.
2. **A coroutine frame is a heap object with an owner.** Someone must call `handle.destroy()`. Destroying a *suspended* frame also runs the destructors of its live locals, which is how cancelled work releases resources.
3. **`unhandled_exception` decides your error semantics.** Store `std::current_exception()` and rethrow it on `result()`. An empty body turns every exception into a "successful" default-constructed value.
4. **`std::vector` moves only `noexcept` movers.** Reallocation uses `std::move_if_noexcept`: when the move constructor may throw and a copy constructor exists, elements are *copied* to keep the strong exception guarantee. Core Guidelines C.66: "A non-throwing move will be used more efficiently by standard-library and language facilities."
5. **A move must leave its source destructible and not owning.** If both objects still point at one resource after the move, both destructors release it.
6. **Weak pointers pin memory.** cppreference on `make_shared`: if any `weak_ptr` still references the control block after the last owner is gone, "the memory occupied by `T` persists until all weak owners get destroyed as well." A never-pruned observer list of `weak_ptr`s pins every closed viewer's full allocation.
7. **`shared_from_this` captured in a member is a cycle.** The object owns a callable that owns the object, and the reference count never reaches zero. Capture `weak_from_this()` instead.

---

## 2. The PR

> **MEDIA-77 · Async thumbnails on the media event loop**
>
> Thumbnail decoding blocks the media service's single event loop for 20–80 ms per image, and p99 latency for everything else on the loop is terrible. Move rendering to coroutines. While there: viewers (UI panels) want a callback when a thumbnail is ready, and failed renders should be retryable.
>
> **PR description, by the author:**
> - `Task<T>`: a minimal lazy coroutine task (`start()`, `done()`, `result()`).
> - `ThumbnailService::render` is now a coroutine; parameters stay `const&` "to avoid copying paths."
> - `Buffer` gets a move constructor, so `std::vector<Buffer>` stops copying 64 KiB blocks on growth.
> - Viewers subscribe with `weak_ptr`, so the service never keeps a closed viewer alive.
> - `ThumbnailJob` can re-run itself via a stored retry callback.
> - Errors: decode failures "surface as an empty result."
> - Tests: async render caches, viewers notified, buffers into vectors, job runs once. Green on GCC and Clang.
>
> **Context the reviewer can discover:** callers pass temporaries routinely (`svc.render(make_path(id), Options{w, h})`). On shutdown the loop cancels pending work. The viewer panel creates viewers with `std::make_shared` (16 KiB preview each) and opens and closes thousands per session. The thumbnail cache is served to the CDN. The pixel pool's free list trusts its callers.

---

## 3. The diff

```diff
diff --git a/media/thumbnails/include/buffer.hpp b/media/thumbnails/include/buffer.hpp
index 11d1330..ce5c2fe 100644
--- a/media/thumbnails/include/buffer.hpp
+++ b/media/thumbnails/include/buffer.hpp
@@ -14,6 +14,8 @@ public:
         std::copy_n(other.data_, size_, data_);
     }
 
+    Buffer(Buffer&& other) : data_(other.data_), size_(other.size_) {} // steal the block: no pixel copy
+
     Buffer& operator=(const Buffer& other) {
         Buffer copy(other);
         swap(copy);
diff --git a/media/thumbnails/include/task.hpp b/media/thumbnails/include/task.hpp
new file mode 100644
index 0000000..d16f4ad
--- /dev/null
+++ b/media/thumbnails/include/task.hpp
@@ -0,0 +1,32 @@
+#pragma once
+// task.hpp - a lazy coroutine task: starts on start(), result() after completion.
+#include <coroutine>
+#include <optional>
+#include <utility>
+
+template <typename T>
+class Task {
+public:
+    struct promise_type {
+        std::optional<T> value;
+
+        Task get_return_object() { return Task{std::coroutine_handle<promise_type>::from_promise(*this)}; }
+        std::suspend_always initial_suspend() noexcept { return {}; }
+        std::suspend_always final_suspend() noexcept { return {}; }
+        void return_value(T v) { value = std::move(v); }
+        void unhandled_exception() {} // errors surface as an empty result
+    };
+
+    explicit Task(std::coroutine_handle<promise_type> h) : handle_(h) {}
+    Task(Task&& other) noexcept : handle_(std::exchange(other.handle_, {})) {}
+    Task(const Task&) = delete;
+    Task& operator=(const Task&) = delete;
+    ~Task() = default;
+
+    void start() { handle_.resume(); }
+    bool done() const { return handle_.done(); }
+    T result() const { return handle_.promise().value.value_or(T{}); }
+
+private:
+    std::coroutine_handle<promise_type> handle_;
+};
diff --git a/media/thumbnails/include/thumbnails.hpp b/media/thumbnails/include/thumbnails.hpp
index 8f67bbc..28f815a 100644
--- a/media/thumbnails/include/thumbnails.hpp
+++ b/media/thumbnails/include/thumbnails.hpp
@@ -1,25 +1,70 @@
 #pragma once
-// thumbnails.hpp - thumbnail rendering (synchronous: blocks the media event loop while decoding).
+// thumbnails.hpp - thumbnail rendering as coroutines on the media event loop: decoding no longer blocks the loop.
 #include <cstddef>
+#include <functional>
 #include <map>
+#include <memory>
 #include <string>
+#include <vector>
 
 #include "buffer.hpp"
 #include "codec.hpp"
 #include "options.hpp"
+#include "scheduler.hpp"
+#include "task.hpp"
+
+struct Viewer {
+    virtual ~Viewer() = default;
+    virtual void on_ready(const std::string& path, const Thumbnail& t) = 0;
+};
 
 class ThumbnailService {
 public:
-    Thumbnail render(const std::string& path, const Options& opts) {
+    explicit ThumbnailService(Scheduler& sched) : sched_(sched) {}
+
+    Task<Thumbnail> render(const std::string& path, const Options& opts) {
         Buffer pixels(static_cast<std::size_t>(opts.width) * static_cast<std::size_t>(opts.height) * 4);
+        co_await sched_.schedule(); // the file read completes on a later loop turn
         decode(path, pixels.data(), pixels.size());
         Thumbnail t{opts.width, opts.height};
         cache_[path] = t;
-        return t;
+        notify(path, t);
+        co_return t;
     }
 
+    void subscribe(std::weak_ptr<Viewer> viewer) { viewers_.push_back(std::move(viewer)); } // weak: no ownership
+
     bool cached(const std::string& path) const { return cache_.contains(path); }
 
 private:
+    void notify(const std::string& path, const Thumbnail& t) {
+        for (const std::weak_ptr<Viewer>& w : viewers_) {
+            if (std::shared_ptr<Viewer> v = w.lock()) {
+                v->on_ready(path, t);
+            }
+        }
+    }
+
+    Scheduler& sched_;
     std::map<std::string, Thumbnail> cache_;
+    std::vector<std::weak_ptr<Viewer>> viewers_;
+};
+
+/** A render job that can re-run itself (retry after a transient decode failure). */
+class ThumbnailJob : public std::enable_shared_from_this<ThumbnailJob> {
+public:
+    explicit ThumbnailJob(std::string path) : path_(std::move(path)) {}
+
+    void start() {
+        retry_ = [self = shared_from_this()] { self->attempts_++; };
+        retry_();
+    }
+
+    int attempts() const { return attempts_; }
+
+private:
+    std::string path_;
+    Buffer scratch_{64 * 1024};
+    std::function<void()> retry_;
+    int attempts_ = 0;
 };
diff --git a/media/thumbnails/test/thumbnails_test.cpp b/media/thumbnails/test/thumbnails_test.cpp
index 6d0e5bb..5d17dd8 100644
--- a/media/thumbnails/test/thumbnails_test.cpp
+++ b/media/thumbnails/test/thumbnails_test.cpp
@@ -1,25 +1,54 @@
-// thumbnails_test.cpp - tests for the synchronous thumbnail service.
+// thumbnails_test.cpp - tests for the coroutine thumbnail service.
+#include <memory>
 #include <string>
+#include <vector>
 
 #include "check.hpp"
 #include "thumbnails.hpp"
 
-TEST(renders_and_caches) {
-    ThumbnailService svc;
-    Thumbnail t = svc.render("a.jpg", Options{120, 80});
-    CHECK(t.width == 120 && t.height == 80);
+struct CountingViewer : Viewer {
+    int notified = 0;
+    void on_ready(const std::string&, const Thumbnail&) override { ++notified; }
+};
+
+TEST(renders_asynchronously_and_caches) {
+    Scheduler loop;
+    ThumbnailService svc(loop);
+    std::string path = "a.jpg";
+    Options opts{120, 80};
+    Task<Thumbnail> task = svc.render(path, opts);
+    task.start();
+    CHECK(!task.done()); // suspended on the file read: the loop is free
+    loop.run();
+    CHECK(task.done());
+    CHECK(task.result().width == 120);
     CHECK(svc.cached("a.jpg"));
 }
 
-TEST(corrupt_input_throws) {
-    ThumbnailService svc;
-    bool threw = false;
-    try {
-        svc.render("corrupt.jpg", Options{10, 10});
-    } catch (const std::runtime_error&) {
-        threw = true;
-    }
-    CHECK(threw);
+TEST(notifies_subscribed_viewers) {
+    Scheduler loop;
+    ThumbnailService svc(loop);
+    auto viewer = std::make_shared<CountingViewer>();
+    svc.subscribe(viewer);
+    std::string path = "b.jpg";
+    Options opts{10, 10};
+    Task<Thumbnail> task = svc.render(path, opts);
+    task.start();
+    loop.run();
+    CHECK(viewer->notified == 1);
+}
+
+TEST(buffers_move_into_containers) {
+    std::vector<Buffer> frames;
+    frames.push_back(Buffer(1024));
+    frames.push_back(Buffer(1024));
+    CHECK(frames.size() == 2);
+}
+
+TEST(jobs_run_once_when_started) {
+    auto job = std::make_shared<ThumbnailJob>("c.jpg");
+    job->start();
+    CHECK(job->attempts() == 1);
 }
 
 int main() { return run_all(); }
```

---

## 4. The author's tests: green

```text
ok   renders_asynchronously_and_caches
ok   notifies_subscribed_viewers
ok   buffers_move_into_containers
ok   jobs_run_once_when_started
4 passed, 0 failed
```

Every render is given **lvalues** that outlive the coroutine. Every task is run to completion, never cancelled. No input is corrupt. The vector test pushes two buffers and checks only the size: it actually triggers F7's double release, but nothing observes it. The job test never checks that the job is freed. The PR's tests also pass against the fixed code (§7): none of them encodes a defect, and none could see one.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** argument lifetime (coroutine vs function), frame ownership, error semantics, move semantics of a pooled resource, observer ownership, and self-ownership.
- **Hunk scores:** `render` 8/8, `Task` 8/8, `Buffer(Buffer&&)` 6/8, `subscribe`/`notify` 4/8, `ThumbnailJob::start` 4/8.
- **Radar hits:** `const std::string& path, const Options& opts` on a coroutine (thumbnails 25). `~Task() = default;` on a raw handle (task 24). `unhandled_exception() {}` and `value_or(T{})` (task 17, 28). A move ctor without `noexcept` that doesn't null its source (buffer 17). `viewers_.push_back` with no removal anywhere (thumbnails 35–41). `[self = shared_from_this()]` stored in a member (59).

### Minute 10: one hop each

- Callers pass temporaries, and the body starts on `start()`: every such call dangles. F1.
- Who calls `destroy()` on the handle? Nobody. Cancelled renders keep their pixel buffers forever: F2.
- What does `result()` return after a decode throws? `Thumbnail{}`, which the CDN caches as a valid thumbnail: F3.
- Is the move `noexcept`? No, so `vector` copies on growth: F4.
- When are expired `weak_ptr`s removed? Never, and viewers are `make_shared`: F5.
- `retry_` holds `shared_from_this()`, and the job holds `retry_`: F6.
- After `Buffer b(std::move(a))`, who releases the block? Both destructors: F7.

### Minute 20: prove, unify, fix

- **Unify:** six of the seven are one question asked six times: *who owns this, and for how long?* The coroutine borrows what it should own (F1). The task owns what it never releases (F2). Two buffers own one block (F7). A service owns observers it should forget (F5). A job owns itself (F6). F3 is ownership of an *error*. F4 is the performance face of F7's move constructor.
- **Fix shape:** by-value coroutine params; RAII `Task` that destroys its frame; stored and rethrown exceptions; `noexcept` move via `std::exchange`; prune expired observers on subscribe and notify; capture `weak_from_this()`.

---

## 6. The L7 answer key, line by line

### F1 · L3 · Sev-1 · Coroutine parameters by reference dangle as soon as the call expression ends (thumbnails 25–28)

**Mechanism.** `render(const std::string& path, const Options& opts)` stores *references* in the coroutine frame. `initial_suspend` is `suspend_always`, so the body runs on `start()`, after `svc.render(make_path(id), Options{w, h})` has finished and destroyed both temporaries. Line 26 reads `opts.width` from a dead object, and line 28 reads `path` after another suspension. This is undefined behavior: garbage dimensions, a wild allocation size, or a crash in production. The author's test passes because it uses lvalues that happen to outlive the task.

**Evidence.** P1 passes a temporary `TrackedOptions` whose destructor is counted. On the PR: `options alive when the coroutine first runs = 0 -> it holds dangling references` (the probe does not resume, because resuming would read a destroyed object). Fix: `coroutine owns copies; resumed -> 200x200 thumbnail`.

```comment-l7
issue (blocking): render() is a coroutine with reference parameters, so callers that pass temporaries hand it dangling references

The frame stores references, and with suspend_always the body only starts at start(), after `svc.render(make_path(id), Options{...})` has destroyed both temporaries, which means line 26 reads a dead Options and line 28 a dead string (undefined behavior). The P1 probe confirms the Options temporary is destroyed before the coroutine's first instruction. Suggest taking path and opts by value (Core Guidelines CP.53); the copy is a few dozen bytes per render.
```

**Fix.**
```cpp
    Task<Thumbnail> render(std::string path, Options opts) {
```

### F2 · L3 · Sev-2 · `Task` never destroys its coroutine frame: every task leaks, cancelled ones leak their buffers too (task 24)

**Mechanism.** `std::coroutine_handle` is a raw, non-owning handle. `~Task() = default` therefore never calls `destroy()`. Completed tasks leak their frame. Tasks still suspended when the loop cancels them (shutdown, a closed panel) leak the frame *and* every live local, here a 64 KiB pixel block each. On a service that cancels thousands of renders per session, the pool drains.

**Evidence.** P2: `100 suspended renders cancelled at shutdown: pixel blocks still held = 100`. Fix: 0.

```comment-l7
issue (blocking): ~Task() = default never destroys the coroutine frame, so cancelled renders leak their pixel buffers

coroutine_handle doesn't own the frame; without handle_.destroy() in the destructor every task leaks its frame, and a task cancelled while suspended also leaks its live locals, which means each cancelled render keeps a 64 KiB block forever (P2 probe: 100 cancelled renders, 100 blocks held). Suggest an owning Task: destroy in the destructor, move-only, and documented "destroying a suspended task cancels it."
```

**Fix.**
```cpp
    ~Task() {
        if (handle_) {
            handle_.destroy(); // frees the frame and runs destructors of a suspended coroutine's locals
        }
    }
```

### F3 · L3 · Sev-1 · `unhandled_exception` swallows decode failures, and `result()` returns an empty thumbnail as success (task 17, 28)

**Mechanism.** When `decode` throws on a corrupt file, the empty `unhandled_exception()` discards the exception, the coroutine finishes normally, and `result()` returns `value_or(T{})`, a 0×0 `Thumbnail`. Callers can't distinguish "corrupt" from "rendered." The thumbnail tier serves that empty image to the CDN, which caches it, so every user sees a blank tile until manual purge. The PR description calls this "surface as an empty result."

**Evidence.** P3: `corrupt.jpg -> result 0x0 returned as success (ok() = false)`. Fix: `the caller receives the error: corrupt image: corrupt.jpg`.

```comment-l7
issue (blocking): unhandled_exception() discards errors, so a corrupt image comes back as a successful 0x0 thumbnail

With an empty unhandled_exception (line 17) and value_or(T{}) in result() (line 28), a decode failure is indistinguishable from success; the P3 probe returns a 0x0 thumbnail for corrupt.jpg with no error, which means the CDN caches a blank tile. Suggest storing std::current_exception() in the promise and rethrowing it from result(), plus a test with a corrupt input.
```

**Fix.**
```cpp
        void unhandled_exception() { error = std::current_exception(); } // rethrown by result()
```
```cpp
    T result() const {
        if (handle_.promise().error) {
            std::rethrow_exception(handle_.promise().error);
        }
        return *handle_.promise().value;
    }
```

### F4 · L7 · Sev-2 · The new move constructor isn't `noexcept`, so `vector` growth still deep-copies every buffer (buffer 17)

**Mechanism.** `std::vector` relocates elements with `std::move_if_noexcept`. `Buffer` has a copy constructor and a move constructor that isn't `noexcept`, so reallocation *copies*: each growth step deep-copies every existing 64 KiB block. The optimization the PR description promises doesn't happen.

**Evidence.** P4: `push_back 100 buffers into a vector: pixel blocks acquired = 227` (100 needed + 127 copies across reallocations at capacities 1, 2, 4 … 64). Fix: `100`. Identical on libstdc++ and libc++.

```comment-l7
issue (blocking): the move constructor isn't noexcept, so std::vector keeps copying buffers on reallocation

vector relocates with move_if_noexcept, which picks the copy constructor when a move might throw, which means the PR's optimization never runs: the P4 probe acquires 227 blocks for 100 push_backs (127 deep copies). Suggest marking the move constructor noexcept, which is honest here since it only swaps two scalars (Core Guidelines C.66), and the same fix as the next comment makes it correct too.
```

**Fix.** (Together with F7.)
```cpp
    Buffer(Buffer&& other) noexcept : data_(std::exchange(other.data_, nullptr)), size_(std::exchange(other.size_, 0)) {}
```

### F5 · L7 · Sev-2 · Expired `weak_ptr` observers are never removed, pinning every closed viewer's `make_shared` allocation (thumbnails 35–45)

**Mechanism.** `subscribe` appends and nothing ever erases. When a viewer closes, its `shared_ptr`s go away and its destructor runs, but the service's `weak_ptr` keeps the control block alive. Viewers are created with `make_shared`, so object and control block are one allocation, and the whole 16 KiB stays allocated until the weak pointer dies, which is never. The vector also grows without bound, and every `notify` walks every dead entry.

**Evidence.** P5: `1000 viewers subscribed then closed (16 KiB each): allocations freed = 0 of 1000`. Fix: `1000 of 1000`.

```comment-l7
issue (blocking): viewers_ only grows, and each expired weak_ptr pins its viewer's whole make_shared allocation

Viewers are created with make_shared (object and control block in one allocation), and a weak_ptr keeps that allocation alive after the viewer is destroyed, which means every closed panel's 16 KiB preview stays allocated (P5 probe: 0 of 1000 freed after all viewers closed). Suggest pruning expired entries in subscribe() and notify() (std::erase_if on expired()), or returning an RAII subscription token that unsubscribes in its destructor.
```

**Fix.**
```cpp
    void prune() { // expired weak_ptrs pin their control block (and a make_shared object's whole allocation)
        std::erase_if(viewers_, [](const std::weak_ptr<Viewer>& w) { return w.expired(); });
    }
```

### F6 · L7 · Sev-2 · `ThumbnailJob` stores a callable that owns the job: a reference cycle (thumbnails 59)

**Mechanism.** `retry_ = [self = shared_from_this()] { … }` is a member that holds a `shared_ptr` to its own object. When the last external owner releases the job, the count is still 1 (held by `retry_`), so the job and its 64 KiB scratch buffer are never freed. `enable_shared_from_this` makes this easy to write and impossible to notice.

**Evidence.** P6: `ThumbnailJob started and released: jobs still alive (scratch blocks held) = 1`. Fix: 0.

```comment-l7
issue (blocking): retry_ captures shared_from_this(), so every started job owns itself and is never freed

The job holds retry_, and retry_ holds a shared_ptr to the job; when callers release their pointer the count stays at 1, which means each job and its 64 KiB scratch buffer leak (P6 probe: 1 job alive after release). Suggest capturing weak_from_this() and locking inside the callback, so the retry runs only while someone still owns the job.
```

**Fix.**
```cpp
        retry_ = [weak = weak_from_this()] { // weak: the job must not own itself
            if (std::shared_ptr<ThumbnailJob> self = weak.lock()) {
                self->attempts_++;
            }
        };
```

### F7 · L3 · Sev-1 · The moved-from `Buffer` still owns its block: two releases, then two live buffers share memory (buffer 17)

**Mechanism.** The move constructor copies `data_` but doesn't clear `other.data_`, so both objects' destructors call `release` on the same block. The pool's free list (like the production slab allocator) trusts its callers, so the block goes on the list twice and the next two `acquire` calls hand out *the same memory*. Two thumbnails then decode into one buffer, giving silently corrupted images. With a real `delete[]` this would be a double free. The author's own vector test triggers it (pushing a temporary moves it, then destroys the temporary), and nothing notices.

**Evidence.** P7: `after one moved-from buffer is destroyed, two new buffers share one pixel block: true`. Fix: `false`.

```comment-l7
issue (blocking): the move constructor leaves the source owning its block, so the block is released twice and later handed out to two buffers

Line 17 copies data_ without nulling other.data_, so both destructors release the same block; the pool trusts its callers, which means the block lands on the free list twice and two later Buffers alias the same pixels (P7 probe: true). The existing test `buffers_move_into_containers` already triggers this. Suggest std::exchange(other.data_, nullptr) and std::exchange(other.size_, 0), with noexcept (see the previous comment), and a test that destroys a moved-from buffer.
```

**Fix.** The same `noexcept` move constructor as F4: `std::exchange` leaves the source empty, and `release(nullptr)` is a no-op.

### T1 · Tests

All four author tests pass on the fixed code too. They encode no defect, but they also exercise none of the risky paths: temporaries, cancellation, failure, many viewers, release of a job, or use of a moved-from object. The fixed suite adds one test per lifetime path. On a real CI, add an ASan/UBSan job (Linux): F1 and F7 are exactly what those sanitizers report on first run.

```comment-l7
todo (blocking): the tests use only long-lived lvalues and never cancel, fail, or release, so none of the lifetime paths is exercised

Suggest tests for: render() called with temporaries, a task destroyed while suspended, a corrupt input, 1,000 subscribe/close cycles, a released ThumbnailJob, and a destroyed moved-from Buffer; plus an ASan/UBSan CI job, which would flag the dangling reads and the double release immediately.
```

---

## 7. The refactored code

```cpp
// ===== media/thumbnails/include/buffer.hpp =====
#pragma once
// buffer.hpp - RGBA pixels in a PixelPool block. Copying deep-copies the pixels.
#include <algorithm>
#include <cstddef>
#include <utility>

#include "pixel_pool.hpp"

class Buffer {
public:
    explicit Buffer(std::size_t bytes) : data_(PixelPool::instance().acquire(bytes)), size_(bytes) {}

    Buffer(const Buffer& other) : data_(PixelPool::instance().acquire(other.size_)), size_(other.size_) {
        std::copy_n(other.data_, size_, data_);
    }

    Buffer(Buffer&& other) noexcept : data_(std::exchange(other.data_, nullptr)), size_(std::exchange(other.size_, 0)) {}

    Buffer& operator=(const Buffer& other) {
        Buffer copy(other);
        swap(copy);
        return *this;
    }

    ~Buffer() { PixelPool::instance().release(data_); }

    void swap(Buffer& other) noexcept {
        std::swap(data_, other.data_);
        std::swap(size_, other.size_);
    }

    std::byte* data() { return data_; }
    std::size_t size() const { return size_; }

private:
    std::byte* data_;
    std::size_t size_;
};

// ===== media/thumbnails/include/task.hpp =====
#pragma once
// task.hpp - a lazy coroutine task: starts on start(), result() after completion. Owns its frame.
#include <coroutine>
#include <exception>
#include <optional>
#include <utility>

template <typename T>
class Task {
public:
    struct promise_type {
        std::optional<T> value;
        std::exception_ptr error;

        Task get_return_object() { return Task{std::coroutine_handle<promise_type>::from_promise(*this)}; }
        std::suspend_always initial_suspend() noexcept { return {}; }
        std::suspend_always final_suspend() noexcept { return {}; }
        void return_value(T v) { value = std::move(v); }
        void unhandled_exception() { error = std::current_exception(); } // rethrown by result()
    };

    explicit Task(std::coroutine_handle<promise_type> h) : handle_(h) {}
    Task(Task&& other) noexcept : handle_(std::exchange(other.handle_, {})) {}
    Task(const Task&) = delete;
    Task& operator=(const Task&) = delete;
    ~Task() {
        if (handle_) {
            handle_.destroy(); // frees the frame and runs destructors of a suspended coroutine's locals
        }
    }

    void start() { handle_.resume(); }
    bool done() const { return handle_.done(); }
    T result() const {
        if (handle_.promise().error) {
            std::rethrow_exception(handle_.promise().error);
        }
        return *handle_.promise().value;
    }

private:
    std::coroutine_handle<promise_type> handle_;
};

// ===== media/thumbnails/include/thumbnails.hpp =====
#pragma once
// thumbnails.hpp - thumbnail rendering as coroutines on the media event loop: decoding no longer blocks the loop.
#include <cstddef>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "buffer.hpp"
#include "codec.hpp"
#include "options.hpp"
#include "scheduler.hpp"
#include "task.hpp"

struct Viewer {
    virtual ~Viewer() = default;
    virtual void on_ready(const std::string& path, const Thumbnail& t) = 0;
};

class ThumbnailService {
public:
    explicit ThumbnailService(Scheduler& sched) : sched_(sched) {}

    // Parameters by value: a coroutine outlives the call expression, so it must own what it reads after suspending.
    Task<Thumbnail> render(std::string path, Options opts) {
        Buffer pixels(static_cast<std::size_t>(opts.width) * static_cast<std::size_t>(opts.height) * 4);
        co_await sched_.schedule(); // the file read completes on a later loop turn
        decode(path, pixels.data(), pixels.size());
        Thumbnail t{opts.width, opts.height};
        cache_[path] = t;
        notify(path, t);
        co_return t;
    }

    void subscribe(std::weak_ptr<Viewer> viewer) {
        prune();
        viewers_.push_back(std::move(viewer));
    }

    bool cached(const std::string& path) const { return cache_.contains(path); }

private:
    void prune() { // expired weak_ptrs pin their control block (and a make_shared object's whole allocation)
        std::erase_if(viewers_, [](const std::weak_ptr<Viewer>& w) { return w.expired(); });
    }

    void notify(const std::string& path, const Thumbnail& t) {
        prune();
        for (const std::weak_ptr<Viewer>& w : viewers_) {
            if (std::shared_ptr<Viewer> v = w.lock()) {
                v->on_ready(path, t);
            }
        }
    }

    Scheduler& sched_;
    std::map<std::string, Thumbnail> cache_;
    std::vector<std::weak_ptr<Viewer>> viewers_;
};

/** A render job that can re-run itself (retry after a transient decode failure). */
class ThumbnailJob : public std::enable_shared_from_this<ThumbnailJob> {
public:
    explicit ThumbnailJob(std::string path) : path_(std::move(path)) {}

    void start() {
        retry_ = [weak = weak_from_this()] { // weak: the job must not own itself
            if (std::shared_ptr<ThumbnailJob> self = weak.lock()) {
                self->attempts_++;
            }
        };
        retry_();
    }

    int attempts() const { return attempts_; }

private:
    std::string path_;
    Buffer scratch_{64 * 1024};
    std::function<void()> retry_;
    int attempts_ = 0;
};
```

**Fixed suite: 5/5 on GCC (output, verified; the Clang run is identical).**

```text
ok   renders_from_temporaries
ok   corrupt_input_reaches_the_caller
ok   cancelled_tasks_release_their_buffers
ok   moves_do_not_copy_pixels
ok   jobs_are_freed_when_released
5 passed, 0 failed
```

**The PR's original tests against the fix (output, verified).** All pass. They never exercised the defects:

```text
ok   renders_asynchronously_and_caches
ok   notifies_subscribed_viewers
ok   buffers_move_into_containers
ok   jobs_run_once_when_started
4 passed, 0 failed
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Coroutine arguments | `const&` (borrowed) | By value (owned by the frame) |
| Frame ownership | Leaked | `Task` destroys it; destroying a suspended task cancels it |
| Errors | Swallowed into `T{}` | Stored `exception_ptr`, rethrown by `result()` |
| Move | Throwing, source still owns | `noexcept`, source emptied via `std::exchange` |
| Observers | Append-only `weak_ptr`s | Pruned on subscribe and notify (or RAII tokens) |
| Self-retry | `shared_from_this` captured (cycle) | `weak_from_this` captured |

---

## 8. Probe evidence

**Against the PR's code (output, verified, GCC 16.2):**

```text
PR07 probes against the PR's thumbnail service (GCC)
P1 F1 render(temporary path, temporary options): options alive when the coroutine first runs = 0 -> it holds dangling references (not resumed: resuming would read a destroyed object)
P2 F2 100 suspended renders cancelled at shutdown: pixel blocks still held = 100
P3 F3 corrupt.jpg -> result 0x0 returned as success (ok() = false)
P4 F4 push_back 100 buffers into a vector: pixel blocks acquired = 227 (100 needed; the rest are deep copies made on reallocation)
P5 F5 1000 viewers subscribed then closed (16 KiB each): allocations freed = 0 of 1000
P6 F6 ThumbnailJob started and released: jobs still alive (scratch blocks held) = 1
P7 F7 after one moved-from buffer is destroyed, two new buffers share one pixel block: true
```

**Against the PR's code (output, verified, Clang 21.1):**

```text
PR07 probes against the PR's thumbnail service (Clang)
P1 F1 render(temporary path, temporary options): options alive when the coroutine first runs = 0 -> it holds dangling references (not resumed: resuming would read a destroyed object)
P2 F2 100 suspended renders cancelled at shutdown: pixel blocks still held = 100
P3 F3 corrupt.jpg -> result 0x0 returned as success (ok() = false)
P4 F4 push_back 100 buffers into a vector: pixel blocks acquired = 227 (100 needed; the rest are deep copies made on reallocation)
P5 F5 1000 viewers subscribed then closed (16 KiB each): allocations freed = 0 of 1000
P6 F6 ThumbnailJob started and released: jobs still alive (scratch blocks held) = 1
P7 F7 after one moved-from buffer is destroyed, two new buffers share one pixel block: true
```

**Against the fixed code (output, verified, GCC 16.2; Clang identical except the compiler name):**

```text
PR07 probes against the fixed thumbnail service (GCC)
P1 F1 render(temporary path, temporary options): coroutine owns copies; resumed -> 200x200 thumbnail
P2 F2 100 suspended renders cancelled at shutdown: pixel blocks still held = 0
P3 F3 corrupt.jpg -> the caller receives the error: corrupt image: corrupt.jpg
P4 F4 push_back 100 buffers into a vector: pixel blocks acquired = 100 (100 needed; the rest are deep copies made on reallocation)
P5 F5 1000 viewers subscribed then closed (16 KiB each): allocations freed = 1000 of 1000
P6 F6 ThumbnailJob started and released: jobs still alive (scratch blocks held) = 0
P7 F7 after one moved-from buffer is destroyed, two new buffers share one pixel block: false
```

<details><summary><b>The probe harness (probes.cpp)</b></summary>

```cpp
// probes.cpp - lifetime, failure and memory probes for PR07. Every probe stays inside defined behavior: where the
// PR's code would read a dead object, the probe detects that the object is dead and does not resume the coroutine.
#include <memory>
#include <print>
#include <stdexcept>
#include <string>
#include <tuple>
#include <type_traits>
#include <vector>

#include "thumbnails.hpp"

namespace {

template <typename>
struct Params;
template <typename R, typename C, typename... A>
struct Params<R (C::*)(A...)> {
    using types = std::tuple<A...>;
};
constexpr bool kOptionsByReference =
    std::is_reference_v<std::tuple_element_t<1, Params<decltype(&ThumbnailService::render)>::types>>;

struct TrackedOptions : Options {
    static inline int alive = 0;
    TrackedOptions(int w, int h) : Options{w, h} { ++alive; }
    TrackedOptions(const TrackedOptions& o) : Options(o) { ++alive; }
    ~TrackedOptions() { --alive; }
};

struct TestViewer : Viewer {
    std::byte payload[16 * 1024]{}; // a viewer holds its decoded preview
    void on_ready(const std::string&, const Thumbnail&) override {}
};

inline long g_allocations = 0; // shared by every rebound instantiation (allocate_shared rebinds to its block type)
inline long g_deallocations = 0;

template <typename T>
struct CountingAlloc {
    using value_type = T;
    CountingAlloc() = default;
    template <typename U>
    CountingAlloc(const CountingAlloc<U>&) {}
    T* allocate(std::size_t n) {
        ++g_allocations;
        return std::allocator<T>{}.allocate(n);
    }
    void deallocate(T* p, std::size_t n) {
        ++g_deallocations;
        std::allocator<T>{}.deallocate(p, n);
    }
    template <typename U>
    bool operator==(const CountingAlloc<U>&) const { return true; }
};

PixelPool& pool() { return PixelPool::instance(); }

void dangling_arguments() {
    Scheduler loop;
    ThumbnailService svc(loop);
    Task<Thumbnail> task = svc.render(std::string("a.jpg"), TrackedOptions{200, 200}); // temporaries end here
    int alive = TrackedOptions::alive;
    if constexpr (kOptionsByReference) {
        std::println("P1 F1 render(temporary path, temporary options): options alive when the coroutine first runs = {}"
                     " -> it holds dangling references (not resumed: resuming would read a destroyed object)", alive);
    } else {
        task.start();
        loop.run();
        std::println("P1 F1 render(temporary path, temporary options): coroutine owns copies; resumed -> {}x{} thumbnail",
                     task.result().width, task.result().height);
    }
}

void cancelled_frames() {
    long before = pool().outstanding();
    {
        Scheduler loop;
        ThumbnailService svc(loop);
        std::vector<Task<Thumbnail>> tasks;
        for (int i = 0; i < 100; ++i) {
            tasks.push_back(svc.render("img" + std::to_string(i) + ".jpg", Options{32, 32}));
            tasks.back().start();
        }
        loop.cancel_all(); // shutdown with 100 renders suspended on their file reads
    }
    std::println("P2 F2 100 suspended renders cancelled at shutdown: pixel blocks still held = {}",
                 pool().outstanding() - before);
}

void swallowed_error() {
    Scheduler loop;
    ThumbnailService svc(loop);
    Task<Thumbnail> task = svc.render("corrupt.jpg", Options{64, 64});
    task.start();
    loop.run();
    try {
        Thumbnail t = task.result();
        std::println("P3 F3 corrupt.jpg -> result {}x{} returned as success (ok() = {})", t.width, t.height, t.ok());
    } catch (const std::runtime_error& e) {
        std::println("P3 F3 corrupt.jpg -> the caller receives the error: {}", e.what());
    }
}

void vector_growth() {
    long before = pool().acquires();
    {
        std::vector<Buffer> frames;
        for (int i = 0; i < 100; ++i) {
            frames.push_back(Buffer(1024));
        }
    }
    std::println("P4 F4 push_back 100 buffers into a vector: pixel blocks acquired = {} (100 needed; the rest are deep copies"
                 " made on reallocation)", pool().acquires() - before);
}

void observer_memory() {
    Scheduler loop;
    ThumbnailService svc(loop);
    using Alloc = CountingAlloc<TestViewer>;
    long allocs = g_allocations;
    long frees = g_deallocations;
    {
        std::vector<std::shared_ptr<TestViewer>> viewers;
        for (int i = 0; i < 1000; ++i) {
            viewers.push_back(std::allocate_shared<TestViewer>(Alloc{})); // object + control block: one allocation
            svc.subscribe(viewers.back());
        }
    } // every viewer window closed: all 1000 destructors run here
    Task<Thumbnail> task = svc.render("x.jpg", Options{8, 8}); // the next render notifies subscribers
    task.start();
    loop.run();
    std::println("P5 F5 1000 viewers subscribed then closed (16 KiB each): allocations freed = {} of {}",
                 g_deallocations - frees, g_allocations - allocs);
}

void job_cycle() {
    long before = pool().outstanding();
    {
        auto job = std::make_shared<ThumbnailJob>("c.jpg");
        job->start();
    } // the last external owner is gone
    std::println("P6 F6 ThumbnailJob started and released: jobs still alive (scratch blocks held) = {}",
                 pool().outstanding() - before);
}

void moved_from_buffer() {
    {
        Buffer a(4096);
        Buffer b(std::move(a));
    } // both destructors run
    Buffer x(4096);
    Buffer y(4096);
    std::println("P7 F7 after one moved-from buffer is destroyed, two new buffers share one pixel block: {}",
                 x.data() == y.data());
}

} // namespace

int main(int argc, char** argv) {
    std::println("PR07 probes against the {} thumbnail service ({})", argc > 1 ? argv[1] : "?",
#if defined(__clang__)
                 "Clang"
#else
                 "GCC"
#endif
    );
    dangling_arguments();
    cancelled_frames();
    swallowed_error();
    vector_growth();
    observer_memory();
    job_cycle();
    moved_from_buffer(); // last: on the PR's code it corrupts the pool's free list
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/media/thumbnails/include/buffer.hpp b/media/thumbnails/include/buffer.hpp
index ce5c2fe..c4574aa 100644
--- a/media/thumbnails/include/buffer.hpp
+++ b/media/thumbnails/include/buffer.hpp
@@ -14,7 +14,7 @@ public:
         std::copy_n(other.data_, size_, data_);
     }
 
-    Buffer(Buffer&& other) : data_(other.data_), size_(other.size_) {} // steal the block: no pixel copy
+    Buffer(Buffer&& other) noexcept : data_(std::exchange(other.data_, nullptr)), size_(std::exchange(other.size_, 0)) {}
 
     Buffer& operator=(const Buffer& other) {
         Buffer copy(other);
diff --git a/media/thumbnails/include/task.hpp b/media/thumbnails/include/task.hpp
index d16f4ad..f59dc48 100644
--- a/media/thumbnails/include/task.hpp
+++ b/media/thumbnails/include/task.hpp
@@ -1,6 +1,7 @@
 #pragma once
-// task.hpp - a lazy coroutine task: starts on start(), result() after completion.
+// task.hpp - a lazy coroutine task: starts on start(), result() after completion. Owns its frame.
 #include <coroutine>
+#include <exception>
 #include <optional>
 #include <utility>
 
@@ -9,23 +10,33 @@ class Task {
 public:
     struct promise_type {
         std::optional<T> value;
+        std::exception_ptr error;
 
         Task get_return_object() { return Task{std::coroutine_handle<promise_type>::from_promise(*this)}; }
         std::suspend_always initial_suspend() noexcept { return {}; }
         std::suspend_always final_suspend() noexcept { return {}; }
         void return_value(T v) { value = std::move(v); }
-        void unhandled_exception() {} // errors surface as an empty result
+        void unhandled_exception() { error = std::current_exception(); } // rethrown by result()
     };
 
     explicit Task(std::coroutine_handle<promise_type> h) : handle_(h) {}
     Task(Task&& other) noexcept : handle_(std::exchange(other.handle_, {})) {}
     Task(const Task&) = delete;
     Task& operator=(const Task&) = delete;
-    ~Task() = default;
+    ~Task() {
+        if (handle_) {
+            handle_.destroy(); // frees the frame and runs destructors of a suspended coroutine's locals
+        }
+    }
 
     void start() { handle_.resume(); }
     bool done() const { return handle_.done(); }
-    T result() const { return handle_.promise().value.value_or(T{}); }
+    T result() const {
+        if (handle_.promise().error) {
+            std::rethrow_exception(handle_.promise().error);
+        }
+        return *handle_.promise().value;
+    }
 
 private:
     std::coroutine_handle<promise_type> handle_;
diff --git a/media/thumbnails/include/thumbnails.hpp b/media/thumbnails/include/thumbnails.hpp
index 28f815a..9bf072d 100644
--- a/media/thumbnails/include/thumbnails.hpp
+++ b/media/thumbnails/include/thumbnails.hpp
@@ -22,7 +22,8 @@ class ThumbnailService {
 public:
     explicit ThumbnailService(Scheduler& sched) : sched_(sched) {}
 
-    Task<Thumbnail> render(const std::string& path, const Options& opts) {
+    // Parameters by value: a coroutine outlives the call expression, so it must own what it reads after suspending.
+    Task<Thumbnail> render(std::string path, Options opts) {
         Buffer pixels(static_cast<std::size_t>(opts.width) * static_cast<std::size_t>(opts.height) * 4);
         co_await sched_.schedule(); // the file read completes on a later loop turn
         decode(path, pixels.data(), pixels.size());
@@ -32,12 +33,20 @@ public:
         co_return t;
     }
 
-    void subscribe(std::weak_ptr<Viewer> viewer) { viewers_.push_back(std::move(viewer)); } // weak: no ownership
+    void subscribe(std::weak_ptr<Viewer> viewer) {
+        prune();
+        viewers_.push_back(std::move(viewer));
+    }
 
     bool cached(const std::string& path) const { return cache_.contains(path); }
 
 private:
+    void prune() { // expired weak_ptrs pin their control block (and a make_shared object's whole allocation)
+        std::erase_if(viewers_, [](const std::weak_ptr<Viewer>& w) { return w.expired(); });
+    }
+
     void notify(const std::string& path, const Thumbnail& t) {
+        prune();
         for (const std::weak_ptr<Viewer>& w : viewers_) {
             if (std::shared_ptr<Viewer> v = w.lock()) {
                 v->on_ready(path, t);
@@ -56,7 +65,11 @@ public:
     explicit ThumbnailJob(std::string path) : path_(std::move(path)) {}
 
     void start() {
-        retry_ = [self = shared_from_this()] { self->attempts_++; };
+        retry_ = [weak = weak_from_this()] { // weak: the job must not own itself
+            if (std::shared_ptr<ThumbnailJob> self = weak.lock()) {
+                self->attempts_++;
+            }
+        };
         retry_();
     }
 
diff --git a/media/thumbnails/test/thumbnails_test.cpp b/media/thumbnails/test/thumbnails_test.cpp
index 5d17dd8..dbfd0cf 100644
--- a/media/thumbnails/test/thumbnails_test.cpp
+++ b/media/thumbnails/test/thumbnails_test.cpp
@@ -1,4 +1,4 @@
-// thumbnails_test.cpp - tests for the coroutine thumbnail service.
+// thumbnails_test.cpp - tests for the coroutine thumbnail service, including lifetime and failure paths.
 #include <memory>
 #include <string>
 #include <vector>
@@ -11,44 +11,60 @@ struct CountingViewer : Viewer {
     void on_ready(const std::string&, const Thumbnail&) override { ++notified; }
 };
 
-TEST(renders_asynchronously_and_caches) {
+TEST(renders_from_temporaries) {
     Scheduler loop;
     ThumbnailService svc(loop);
-    std::string path = "a.jpg";
-    Options opts{120, 80};
-    Task<Thumbnail> task = svc.render(path, opts);
+    Task<Thumbnail> task = svc.render(std::string("a.jpg"), Options{120, 80}); // temporaries die here
     task.start();
-    CHECK(!task.done()); // suspended on the file read: the loop is free
     loop.run();
-    CHECK(task.done());
     CHECK(task.result().width == 120);
-    CHECK(svc.cached("a.jpg"));
 }
 
-TEST(notifies_subscribed_viewers) {
+TEST(corrupt_input_reaches_the_caller) {
     Scheduler loop;
     ThumbnailService svc(loop);
-    auto viewer = std::make_shared<CountingViewer>();
-    svc.subscribe(viewer);
-    std::string path = "b.jpg";
-    Options opts{10, 10};
-    Task<Thumbnail> task = svc.render(path, opts);
+    Task<Thumbnail> task = svc.render("corrupt.jpg", Options{10, 10});
     task.start();
     loop.run();
-    CHECK(viewer->notified == 1);
+    bool threw = false;
+    try {
+        task.result();
+    } catch (const std::runtime_error&) {
+        threw = true;
+    }
+    CHECK(threw);
+    CHECK(!svc.cached("corrupt.jpg"));
 }
 
-TEST(buffers_move_into_containers) {
+TEST(cancelled_tasks_release_their_buffers) {
+    long before = PixelPool::instance().outstanding();
+    {
+        Scheduler loop;
+        ThumbnailService svc(loop);
+        Task<Thumbnail> task = svc.render("a.jpg", Options{10, 10});
+        task.start();
+        loop.cancel_all();
+    }
+    CHECK(PixelPool::instance().outstanding() == before);
+}
+
+TEST(moves_do_not_copy_pixels) {
+    long before = PixelPool::instance().acquires();
     std::vector<Buffer> frames;
-    frames.push_back(Buffer(1024));
-    frames.push_back(Buffer(1024));
-    CHECK(frames.size() == 2);
+    for (int i = 0; i < 10; ++i) {
+        frames.push_back(Buffer(1024));
+    }
+    CHECK(PixelPool::instance().acquires() - before == 10);
 }
 
-TEST(jobs_run_once_when_started) {
-    auto job = std::make_shared<ThumbnailJob>("c.jpg");
-    job->start();
-    CHECK(job->attempts() == 1);
+TEST(jobs_are_freed_when_released) {
+    long before = PixelPool::instance().outstanding();
+    {
+        auto job = std::make_shared<ThumbnailJob>("c.jpg");
+        job->start();
+        CHECK(job->attempts() == 1);
+    }
+    CHECK(PixelPool::instance().outstanding() == before);
 }
 
 int main() { return run_all(); }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F1 | Coroutine reference parameters | Sev-1 (5) | 10 | L6+ (requires knowing CP.53, or reasoning about frames) |
| F3 | Swallowed exceptions | Sev-1 (5) | 2 | L5+ |
| F7 | Moved-from source still owns | Sev-1 (5) | 2 | L5+ C++ reviewers |
| F2 | Frame never destroyed | Sev-2 (3) | 10 | L6+ |
| F4 | Non-`noexcept` move | Sev-2 (3) | 2 | L6+ (it's an *omission*) |
| F5 | Unpruned weak observers pin memory | Sev-2 (3) | 20 | L7 (requires the `make_shared` storage subtlety) |
| F6 | `shared_from_this` cycle | Sev-2 (3) | 10 | L6+ |

Total **27**. L5s find F3 and F7. L6s add F1, F2, F4 and F6. L7s add F5 and say why the "weak pointers can't leak" intuition fails. They also tie F4 and F7 together: one constructor, two defects, one-line fix.

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| Fixing F1 with `std::ref`/lifetime comments | "Callers must keep arguments alive" | Every future caller must remember; temporaries are the natural call shape |
| Fixing F7 but not F4 | `other.data_ = nullptr;` | Correct, but vectors still copy; mark it `noexcept` too |
| "Use `std::shared_ptr<Buffer>` everywhere" | Avoids the move question | Atomic refcounts on the hot path; hides ownership |
| Replacing `weak_ptr` with raw pointers | "No control blocks" | Dangling observers instead of leaked ones |
| "Swallowing is fine, callers check `ok()`" | Relies on discipline | `ok()` can't distinguish failure from a legitimately empty image |
| Not asking about cancellation | Reviews the happy path | Frames leak exactly on cancel, which is common on shutdown and panel close |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Why is `const std::string&` fine for a function but wrong for a coroutine?"</b></summary>

**Initial Prompt.** Coroutine lifetime model.

**L5 Answer.** "It isn't wrong, it avoids a copy."

**Why L5 Stalls.** Misses that the coroutine's body executes after the call returns, here even its *first* statement.

**L7 Answer.** "A function finishes before its caller's full-expression ends, so references to temporaries are valid throughout. A coroutine returns to the caller at its first suspension, here immediately (`suspend_always`), and runs the rest later, when the temporaries are gone. The frame holds references, not objects. CP.53 says it directly: by-reference parameters dangle after the first suspension. Take by value. The copy is tens of bytes, and correctness doesn't depend on every caller remembering to pass lvalues."

</details>

<details><summary><b>Q2 · "How did you prove F1 without running undefined behavior?"</b></summary>

**Initial Prompt.** Evidence discipline in C++.

**L5 Answer.** "Run it and see if it crashes."

**Why L5 Stalls.** UB might not crash. It might print plausible garbage, or work by luck in tests. A non-crash proves nothing.

**L7 Answer.** "Instrument the argument, not the read. A `TrackedOptions` with a counted destructor shows the object is dead before the coroutine's first instruction, and a type trait confirms the parameter is a reference. Together they prove the frame holds a dangling reference, so the probe doesn't resume. In CI, ASan with `detect_stack_use_after_return` or UBSan on Linux catches the actual read. On this Windows toolchain, instrumentation is the defined-behavior route."

</details>

<details><summary><b>Q3 · "Isn't `noexcept` dangerous? If the move ever throws, the program terminates."</b></summary>

**Initial Prompt.** `noexcept` judgment.

**L5 Answer.** "Then leave it off to be safe."

**Why L5 Stalls.** Leaving it off costs a deep copy per element per reallocation, and here the move can't throw anyway.

**L7 Answer.** "Mark it `noexcept` exactly when it can't throw, which is true here: it exchanges a pointer and a size. If a move genuinely could throw (allocating), terminating is usually still better than silently falling back to copies. If not, provide `swap` and let containers copy. Static check: `static_assert(std::is_nothrow_move_constructible_v<Buffer>)` next to the class, so a future edit can't silently undo it."

</details>

<details><summary><b>Q4 · "Why do weak pointers keep memory alive at all?"</b></summary>

**Initial Prompt.** Control-block mechanics.

**L5 Answer.** "They don't; that's the point of weak_ptr."

**Why L5 Stalls.** Conflates "doesn't keep the object alive" with "doesn't keep memory alive."

**L7 Answer.** "The control block carries the strong and weak counts, so it must live while any `weak_ptr` exists. The object's *destructor* runs when the strong count hits zero. With `make_shared`, object and control block share one allocation, so the memory is freed only when the weak count also hits zero. cppreference warns that this 'may be undesirable if sizeof(T) is large.' An append-only list of weak pointers therefore leaks every observer's full footprint. The fixes: prune or unsubscribe, or allocate large observed objects with a separate control block."

</details>

<details><summary><b>Q5 · "Should destroying a suspended Task cancel the work?"</b></summary>

**Initial Prompt.** Cancellation semantics.

**L5 Answer.** "No, the work should finish anyway."

**Why L5 Stalls.** Without an owner, "finish anyway" means a leaked frame resumed by a scheduler that may outlive its service, or never resumed at all.

**L7 Answer.** "With a lazy, owning Task, yes: destroying it destroys the frame and runs the locals' destructors. That's structured cancellation, and it's what makes shutdown leak-free. The scheduler must not hold handles to destroyed frames, which is why `cancel_all()` drops the queue before tasks die. For 'fire and forget' work, use a separate detached type whose frame destroys itself at `final_suspend`, so ownership is explicit either way."

</details>

<details><summary><b>Q6 · "The pool would crash on a double release with real `delete[]`. Isn't the free list making F7 *less* severe?"</b></summary>

**Initial Prompt.** Failure mode of the allocator.

**L5 Answer.** "Yes, at least it doesn't crash."

**Why L5 Stalls.** A crash is detectable. Silent aliasing corrupts images and is far harder to find.

**L7 Answer.** "It makes it *worse*: a crash pages someone, while two thumbnails decoding into one buffer produce wrong images that get cached. Most production slab or free-list allocators don't validate releases for speed, so double releases become aliasing, and aliasing bugs show up far from their cause. That's why moves must empty their source, and why I'd add a debug-build check in the pool that asserts a released block isn't already free."

</details>

<details><summary><b>Q7 · "Rank the findings."</b></summary>

**Initial Prompt.** Prioritization.

**L5 Answer.** "F1 is UB, so first, then the rest in order."

**Why L5 Stalls.** Right first pick, but no reasoning about blast radius among the others.

**L7 Answer.** "F1 (UB on the natural call shape: crashes or wrong sizes immediately in production), F7 (silent image corruption, triggered by the author's own test pattern), F3 (blank thumbnails cached at the CDN, a user-visible incident), then F2 (leaks on every cancel; pool exhaustion over a session), F5 (memory growth with panel churn), F6, F4. F4 and F7 are one constructor, so fix them together."

</details>

<details><summary><b>Q8 · "What CI would you add for this codebase?"</b></summary>

**Initial Prompt.** Guardrails for C++ lifetimes.

**L5 Answer.** "More unit tests."

**Why L5 Stalls.** These are classes of bugs; tests catch instances.

**L7 Answer.** "A Linux job with ASan+UBSan running the unit tests (catches F1 and F7), and LSan (F2, F5, F6 as leaks at exit). A clang-tidy profile with `bugprone-use-after-move`, `cppcoreguidelines-avoid-reference-coroutine-parameters` (the CP.53 check), `performance-noexcept-move-constructor` and `bugprone-exception-escape`. Plus `static_assert(std::is_nothrow_move_constructible_v<Buffer>)`. Those turn this review's findings into build failures."

</details>

---

## 12. Checklist

- [ ] Coroutine parameters: by value unless the caller provably outlives the frame.
- [ ] Coroutine lambdas: no captures (CP.51); pass state as parameters.
- [ ] Task types: who calls `destroy()`? What happens when a suspended task is dropped?
- [ ] `unhandled_exception`: stores and rethrows, never swallows.
- [ ] Move constructors: `noexcept` when non-throwing, source emptied, and a `static_assert` on nothrow-move.
- [ ] Observer lists: pruned or RAII-unsubscribed; `make_shared` objects observed by long-lived `weak_ptr`s?
- [ ] `enable_shared_from_this`: any member storing `shared_from_this()` is a cycle.
- [ ] CI: ASan/UBSan/LSan job; clang-tidy lifetime checks.

---

## 13. References

- C++ Core Guidelines: CP.51 *Do not use capturing lambdas that are coroutines*; CP.53 *Parameters to coroutines should not be passed by reference*; C.66 *Make move operations `noexcept`*. https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
- cppreference: `std::make_shared` (notes on storage lifetime with weak references). https://en.cppreference.com/w/cpp/memory/shared_ptr/make_shared
- cppreference: `std::move_if_noexcept`. https://en.cppreference.com/w/cpp/utility/move_if_noexcept
- cppreference: Coroutines (C++20). https://en.cppreference.com/w/cpp/language/coroutines
- cppreference: `std::enable_shared_from_this`. https://en.cppreference.com/w/cpp/memory/enable_shared_from_this
- Clang-Tidy: `cppcoreguidelines-avoid-reference-coroutine-parameters`. https://clang.llvm.org/extra/clang-tidy/checks/cppcoreguidelines/avoid-reference-coroutine-parameters.html
- Within this KB: [PR08 Lock-free ring buffer](02-pr08-lock-free-ring-buffer-arm64-memory-order-and-aba-corruption.md) · [PR09 Embedded C](03-pr09-embedded-c-dma-cache-line-sharing-isr-deadlock-and-integer-overflow.md) · [01-02 Layer 3](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#5-layer-3-resource-lifecycle-and-failure-paths)
