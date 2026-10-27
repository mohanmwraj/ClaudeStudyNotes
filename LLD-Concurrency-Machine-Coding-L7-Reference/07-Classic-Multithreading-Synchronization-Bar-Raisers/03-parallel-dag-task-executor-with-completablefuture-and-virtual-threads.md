# 07.3 · Parallel DAG Executor: CompletableFuture Composition vs Dependency Counters, Virtual Threads, Cancellation and Timeouts

> **Folder 07 · File 3 of 3.** [P20](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/05-problem-20-dynamic-rule-engine-and-json-Workflow-state-orchestrator.md) built a workflow engine's *semantics*. This file is about the *mechanics*:
> - how to express "run each task once all its parents are done" in Java two ways, with ordering verified;
> - what **virtual threads** buy (blocking) and don't buy (CPU);
> - what `CompletableFuture` does and **doesn't** do on failure and timeout;
> - the C++ toolbox when there is neither `CompletableFuture` nor a virtual thread: counters on a pool, and **C++20 coroutines** parked on one thread.
>
> **Listing pair 07.3:** `DagExecutor.java` / `dag_executor.cpp`. The graph is generated identically in both languages; the "366 dependents" analysis is identical; timings are one measured run on a 12-core machine.

---

## 1. Two ways to run a DAG

**Composition (Java):**

```java
f[v] = CompletableFuture.allOf(parents).thenRunAsync(task, executor)
```

The library keeps the bookkeeping. Failure propagates automatically: a node whose input completed exceptionally never runs.

**Dependency counters (Java and C++):**
- Each node holds an atomic count of unfinished parents.
- A finishing node decrements each child; **the decrement that reaches 0 submits the child**.
- This is the core of any task scheduler, and of P20.
- Failure needs explicit handling: a failed parent **poisons** its children before decrementing, so the last decrement sees it and the child completes as skipped. That reproduces `CompletableFuture`'s semantics exactly.

**Measured: 800-node layered DAG** (8 layers × 100, fan-in 3), 2 ms of blocking I/O per node:

| Executor | Runs | Order violations | Wall |
|---|---|---|---|
| Java, composition, virtual threads | 800 | 0 | 39 ms |
| Java, counters, virtual threads | 800 | 0 | 28 ms |
| C++, counters, pool of 64 | 800 | 0 | 195–199 ms |
| C++, counters, an OS thread per ready node | 800 | 0 | 126 ms |

**The C++ numbers are a platform fact, not slowness.** `std::this_thread::sleep_for(2ms)` rounds up to the Windows timer tick (~15.6 ms) unless `timeBeginPeriod` raises the resolution; the JVM's `Thread.sleep` uses a high-resolution timer. The DAG logic is the same.

## 2. Virtual threads: for blocking, not for computing

| Workload | Platform threads | Virtual threads / coroutines |
|---|---|---|
| Java: 10,000 tasks × 20 ms sleep | pool of 64: **3,229 ms** | a virtual thread per task: **47 ms** |
| Java: 64 CPU-bound tasks | pool of 12 (cores): 249 ms | 229 ms (no gain: 12 cores are 12 cores) |
| C++: 2,000 tasks × 20 ms sleep | pool of 64: 1,000–1,025 ms; an OS thread per task: 98–124 ms | — |
| C++: 10,000 × 20 ms `co_await` sleep | — | **one thread: 26–47 ms** |
| C++: 64 CPU-bound tasks | pool of 12: 205–249 ms | thread per task: 228–262 ms |

**A blocking task holds a platform thread for its whole wait.** 10,000 waits on 64 threads is 157 rounds of 20 ms.

**A virtual thread unmounts from its carrier while it blocks.** The carrier serves another virtual thread, so 10,000 waits overlap. Costs and limits:
- a virtual thread costs a heap-allocated stack chunk, not 1 MB of reserved stack;
- since JDK 24 (JEP 491) a `synchronized` block no longer *pins* the carrier, so the old advice to replace `synchronized` with `ReentrantLock` for virtual threads is mostly historical on JDK 25;
- native calls and some JNI still pin.

**C++ has no virtual threads.** The two options are OS threads (98–124 ms for 2,000, and 2,000 threads that exist at once), or **coroutines**:
- `co_await loop.sleep_for(20ms)` suspends a **stackless frame** onto a timer queue;
- one thread resumes whichever timer is due next;
- 10,000 concurrent waits completed in 26–47 ms on that single thread;
- the price: every blocking call must be an awaitable, and a coroutine that calls a real blocking function blocks the whole loop.

## 3. Failure and cancellation: what keeps running?

**Node 150 (layer 1) fails; 366 of the 800 nodes depend on it transitively:**

| Policy | Java | GCC | Clang |
|---|---|---|---|
| Dependents skipped, independents keep running (`CompletableFuture` / poisoned counters) | **434** ran (= 800 − 366) | 434 | 434 |
| + a cancellation token: nothing new starts after the failure | 201 | 199 | 215 |

`CompletableFuture` gives "dependents don't run" for free. It **does not stop independent work**, and `cancel(true)` on a `CompletableFuture` does **not** interrupt a running task. Fail-fast needs an explicit token checked before each task starts, plus interruption or cooperative checks inside long tasks.

Java 25's `StructuredTaskScope` (still a preview API) packages this. Subtasks of a failed scope are cancelled (interrupted), and the scope can't be left with work still running.

**Timeouts compose the same way.** `orTimeout(50 ms)` on a 500 ms node completes it with `TimeoutException`, and its dependent never runs. But the slow task itself **keeps running** to completion; `orTimeout` completes the *future*, it doesn't stop the *work*. Long tasks must check for cancellation, or be interruptible and given their own deadline.

## 4. Java 21 implementation

```java
// DagExecutor.java - 07.3: a DAG as CompletableFuture composition vs dependency counters; virtual threads vs a platform pool
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;

public final class DagExecutor {

    // ---- the graph: 8 layers x 100 nodes; each node depends on 3 nodes of the previous layer (deterministic)

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    record Graph(int n, int[][] parents, int[][] children) {
        static Graph layered(int layers, int width, int fanIn, long seed) {
            int n = layers * width;
            List<List<Integer>> kids = new ArrayList<>();
            int[][] parents = new int[n][];
            for (int i = 0; i < n; i++) kids.add(new ArrayList<>());
            long s = seed;
            for (int v = 0; v < n; v++) {
                int layer = v / width;
                if (layer == 0) {
                    parents[v] = new int[0];
                    continue;
                }
                java.util.TreeSet<Integer> ps = new java.util.TreeSet<>();
                while (ps.size() < fanIn) ps.add((layer - 1) * width + (int) Long.remainderUnsigned(mix64(s++), width));
                parents[v] = ps.stream().mapToInt(Integer::intValue).toArray();
                for (int p : parents[v]) kids.get(p).add(v);
            }
            int[][] children = new int[n][];
            for (int i = 0; i < n; i++) children[i] = kids.get(i).stream().mapToInt(Integer::intValue).toArray();
            return new Graph(n, parents, children);
        }
    }

    /** Records start/finish sequence numbers; a node that started before one of its parents finished is a violation. */
    static final class Trace {
        final AtomicLong clock = new AtomicLong();
        final AtomicLongArray started, finished;
        final AtomicInteger runs = new AtomicInteger();

        Trace(int n) {
            started = new AtomicLongArray(n);
            finished = new AtomicLongArray(n);
        }

        void run(int v, long sleepMs) {
            started.set(v, clock.incrementAndGet());
            runs.incrementAndGet();
            sleep(sleepMs);
            finished.set(v, clock.incrementAndGet());
        }

        int violations(Graph g) {
            int bad = 0;
            for (int v = 0; v < g.n(); v++)
                for (int p : g.parents()[v])
                    if (finished.get(p) == 0 || started.get(v) < finished.get(p)) bad++;
            return bad;
        }
    }

    static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** Style 1: each node's future is allOf(parents) followed by its task. The library does the bookkeeping. */
    static CompletableFuture<Void> composed(Graph g, ExecutorService exec, Trace t, long sleepMs, int failAt, AtomicBoolean cancelled) {
        @SuppressWarnings({"unchecked", "rawtypes"})                     // generic array creation
        CompletableFuture<Void>[] f = new CompletableFuture[g.n()];
        for (int v = 0; v < g.n(); v++) {                              // nodes are numbered in topological order (by layer)
            final int node = v;
            CompletableFuture<?>[] ps = new CompletableFuture<?>[g.parents()[v].length];
            for (int i = 0; i < ps.length; i++) ps[i] = f[g.parents()[v][i]];
            f[v] = CompletableFuture.allOf(ps).thenRunAsync(() -> {
                if (cancelled != null && cancelled.get()) throw new CompletionException(new IllegalStateException("cancelled"));
                t.run(node, sleepMs);
                if (node == failAt) {
                    if (cancelled != null) cancelled.set(true);         // tell everyone else to stop starting work
                    throw new IllegalStateException("node " + node + " failed");
                }
            }, exec);
        }
        return CompletableFuture.allOf(f);
    }

    /** Style 2: an atomic count of unfinished parents per node; the last parent to finish submits the child. */
    static CountDownLatch counted(Graph g, ExecutorService exec, Trace t, long sleepMs) {
        AtomicInteger[] waiting = new AtomicInteger[g.n()];
        for (int v = 0; v < g.n(); v++) waiting[v] = new AtomicInteger(g.parents()[v].length);
        CountDownLatch done = new CountDownLatch(g.n());
        Runnable[] task = new Runnable[g.n()];
        for (int v = 0; v < g.n(); v++) {
            final int node = v;
            task[v] = () -> {
                t.run(node, sleepMs);
                for (int c : g.children()[node])
                    if (waiting[c].decrementAndGet() == 0) exec.execute(task[c]);
                done.countDown();
            };
        }
        for (int v = 0; v < g.n(); v++)
            if (g.parents()[v].length == 0) exec.execute(task[v]);
        return done;
    }

    static long millis(long t0) {
        return (System.nanoTime() - t0) / 1_000_000;
    }

    public static void main(String[] args) throws Exception {
        Graph g = Graph.layered(8, 100, 3, 7);
        System.out.println("== 1. 800-node layered DAG (8 layers x 100, fan-in 3), 2 ms of blocking I/O per node, virtual threads ==");
        Trace t1 = new Trace(g.n()), t2 = new Trace(g.n());
        long t0 = System.nanoTime();
        try (ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor()) {
            composed(g, vt, t1, 2, -1, null).get(30, TimeUnit.SECONDS);
        }
        long composedMs = millis(t0);
        t0 = System.nanoTime();
        try (ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor()) {
            if (!counted(g, vt, t2, 2).await(30, TimeUnit.SECONDS)) throw new IllegalStateException("stuck");
        }
        long countedMs = millis(t0);
        System.out.printf("  CompletableFuture.allOf(parents).thenRunAsync: %d runs, %d order violations, %d ms (critical path 8 x 2 ms)%n", t1.runs.get(),
                t1.violations(g), composedMs);
        System.out.printf("  dependency counters, last parent submits:      %d runs, %d order violations, %d ms%n", t2.runs.get(), t2.violations(g), countedMs);

        System.out.println("== 2. Blocking vs CPU-bound tasks: a platform pool vs a virtual thread per task ==");
        long[] ioMs = new long[2], cpuMs = new long[2];
        int cores = Runtime.getRuntime().availableProcessors();
        for (int mode = 0; mode < 2; mode++) {
            t0 = System.nanoTime();
            try (ExecutorService ex = mode == 0 ? Executors.newFixedThreadPool(64) : Executors.newVirtualThreadPerTaskExecutor()) {
                for (int i = 0; i < 10_000; i++) ex.execute(() -> sleep(20));
            }
            ioMs[mode] = millis(t0);
            t0 = System.nanoTime();
            AtomicLong sink = new AtomicLong();
            try (ExecutorService ex = mode == 0 ? Executors.newFixedThreadPool(cores) : Executors.newVirtualThreadPerTaskExecutor()) {
                for (int i = 0; i < 64; i++)
                    ex.execute(() -> {
                        long x = 0;
                        for (int k = 0; k < 20_000_000; k++) x += mix64(k);
                        sink.addAndGet(x);
                    });
            }
            cpuMs[mode] = millis(t0);
        }
        System.out.printf("  10,000 tasks x 20 ms sleep: fixed pool of 64 platform threads %d ms | virtual thread per task %d ms%n", ioMs[0], ioMs[1]);
        System.out.printf("  64 CPU-bound tasks: fixed pool of %d (cores) %d ms | virtual thread per task %d ms%n", cores, cpuMs[0], cpuMs[1]);

        System.out.println("== 3. Node 150 (layer 1) fails: what still runs? ==");
        int[] ran = new int[2];
        String[] why = new String[2];
        for (int mode = 0; mode < 2; mode++) {
            Trace t = new Trace(g.n());
            AtomicBoolean token = mode == 1 ? new AtomicBoolean() : null;
            try (ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor()) {
                try {
                    composed(g, vt, t, 2, 150, token).get(30, TimeUnit.SECONDS);
                } catch (java.util.concurrent.ExecutionException e) {
                    why[mode] = e.getCause().getMessage();
                }
            }
            ran[mode] = t.runs.get();
        }
        long downstream = 0;
        boolean[] reach = new boolean[g.n()];
        reach[150] = true;
        for (int v = 151; v < g.n(); v++)
            for (int p : g.parents()[v]) reach[v] |= reach[p];
        for (int v = 151; v < g.n(); v++) if (reach[v]) downstream++;
        System.out.printf("  %d of 800 nodes depend (transitively) on node 150%n", downstream);
        System.out.printf("  CompletableFuture alone: %d nodes ran (dependents skipped, independent work kept going) | error: %s%n", ran[0], why[0]);
        System.out.printf("  + cancellation token:    %d nodes ran (nothing new starts after the failure) | error: %s%n", ran[1], why[1]);

        System.out.println("== 4. Timeouts compose: a slow node with orTimeout fails its dependents ==");
        CompletableFuture<String> slow = CompletableFuture.supplyAsync(() -> {
            sleep(500);
            return "late";
        }).orTimeout(50, TimeUnit.MILLISECONDS);
        CompletableFuture<String> dependent = slow.thenApply(s -> s + " + dependent");
        String outcome;
        try {
            outcome = dependent.get(5, TimeUnit.SECONDS);
        } catch (java.util.concurrent.ExecutionException e) {
            outcome = e.getCause().getClass().getSimpleName() + " (the dependent never ran)";
        }
        System.out.println("  slow node (500 ms) with orTimeout(50 ms) -> dependent: " + outcome);
        System.out.println("  note: orTimeout completes the future; it does NOT interrupt the task, which runs on to completion");

        boolean ok = t1.runs.get() == 800 && t1.violations(g) == 0 && t2.runs.get() == 800 && t2.violations(g) == 0 && ioMs[1] < ioMs[0]
                && ran[0] < 800 && ran[1] <= ran[0] && why[0] != null && why[0].contains("150") && outcome.startsWith(TimeoutException.class.getSimpleName());
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (one measured run):**

```text
== 1. 800-node layered DAG (8 layers x 100, fan-in 3), 2 ms of blocking I/O per node, virtual threads ==
  CompletableFuture.allOf(parents).thenRunAsync: 800 runs, 0 order violations, 39 ms (critical path 8 x 2 ms)
  dependency counters, last parent submits:      800 runs, 0 order violations, 28 ms
== 2. Blocking vs CPU-bound tasks: a platform pool vs a virtual thread per task ==
  10,000 tasks x 20 ms sleep: fixed pool of 64 platform threads 3229 ms | virtual thread per task 47 ms
  64 CPU-bound tasks: fixed pool of 12 (cores) 249 ms | virtual thread per task 229 ms
== 3. Node 150 (layer 1) fails: what still runs? ==
  366 of 800 nodes depend (transitively) on node 150
  CompletableFuture alone: 434 nodes ran (dependents skipped, independent work kept going) | error: node 150 failed
  + cancellation token:    201 nodes ran (nothing new starts after the failure) | error: node 150 failed
== 4. Timeouts compose: a slow node with orTimeout fails its dependents ==
  slow node (500 ms) with orTimeout(50 ms) -> dependent: TimeoutException (the dependent never ran)
  note: orTimeout completes the future; it does NOT interrupt the task, which runs on to completion
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// dag_executor.cpp - 07.3: a DAG on dependency counters (pool / thread-per-task), failure + cancellation, coroutines as cheap waits
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <coroutine>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <exception>
#include <functional>
#include <memory>
#include <mutex>
#include <print>
#include <queue>
#include <set>
#include <thread>
#include <utility>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;
using namespace std::chrono_literals;

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

// ---- the graph: 8 layers x 100 nodes; each node depends on 3 nodes of the previous layer (same as the Java listing)

struct Graph {
    sz n;
    std::vector<std::vector<sz>> parents, children;
    static Graph layered(sz layers, sz width, sz fan_in, u64 seed) {
        Graph g{layers * width, std::vector<std::vector<sz>>(layers * width), std::vector<std::vector<sz>>(layers * width)};
        u64 s = seed;
        for (sz v = 0; v < g.n; ++v) {
            const sz layer = v / width;
            if (layer == 0) continue;
            std::set<sz> ps;
            while (ps.size() < fan_in) ps.insert((layer - 1) * width + static_cast<sz>(mix64(s++) % width));
            g.parents[v].assign(ps.begin(), ps.end());
            for (const sz p : ps) g.children[p].push_back(v);
        }
        return g;
    }
};

/** Records start/finish sequence numbers; a node that started before one of its parents finished is a violation. */
struct Trace {
    std::atomic<i64> clock{0};
    std::vector<std::atomic<i64>> started, finished;
    std::atomic<int> runs{0};
    explicit Trace(sz n) : started(n), finished(n) {}
    void run(sz v, std::chrono::milliseconds sleep) {
        started[v].store(++clock);
        runs.fetch_add(1);
        std::this_thread::sleep_for(sleep);
        finished[v].store(++clock);
    }
    int violations(const Graph& g) const {
        int bad = 0;
        for (sz v = 0; v < g.n; ++v)
            for (const sz p : g.parents[v]) bad += finished[p].load() == 0 || started[v].load() < finished[p].load();
        return bad;
    }
};

// ---- executors

struct Executor {
    virtual ~Executor() = default;
    virtual void execute(std::function<void()> task) = 0;
};

class FixedPool final : public Executor {
    std::mutex m_;
    std::condition_variable cv_;
    std::deque<std::function<void()>> q_;
    bool stop_ = false;
    std::vector<std::jthread> workers_;

public:
    explicit FixedPool(int n) {
        std::scoped_lock warm(m_);
        for (int i = 0; i < n; ++i)
            workers_.emplace_back([this] {
                for (;;) {
                    std::function<void()> job;
                    {
                        std::unique_lock l(m_);
                        cv_.wait(l, [&] { return stop_ || !q_.empty(); });
                        if (q_.empty()) return;
                        job = std::move(q_.front());
                        q_.pop_front();
                    }
                    job();
                }
            });
    }
    void execute(std::function<void()> task) override {
        {
            std::scoped_lock l(m_);
            q_.push_back(std::move(task));
        }
        cv_.notify_one();
    }
    ~FixedPool() override {
        {
            std::scoped_lock l(m_);
            stop_ = true;
        }
        cv_.notify_all();
        workers_.clear();  // joins after the queue drains
    }
};

/** One OS thread per task: what "a thread per request" means without virtual threads. */
class ThreadPerTask final : public Executor {
    std::mutex m_;
    std::vector<std::jthread> threads_;

public:
    ThreadPerTask() { std::scoped_lock warm(m_); }
    void execute(std::function<void()> task) override {
        std::scoped_lock l(m_);
        threads_.emplace_back(std::move(task));
    }
    ~ThreadPerTask() override {
        std::vector<std::jthread> all;
        for (;;) {  // tasks may spawn tasks: keep joining until no new threads appear
            {
                std::scoped_lock l(m_);
                if (threads_.empty()) break;
                all = std::move(threads_);
                threads_.clear();
            }
            all.clear();
        }
    }
};

/** Countdown to zero with a timed wait (std::latch has no wait_for). */
class Done {
    std::mutex m_;
    std::condition_variable cv_;
    sz left_;

public:
    explicit Done(sz n) : left_(n) { std::scoped_lock warm(m_); }
    void count_down() {
        std::scoped_lock l(m_);
        if (--left_ == 0) cv_.notify_all();
    }
    bool wait_for(std::chrono::seconds s) {
        std::unique_lock l(m_);
        return cv_.wait_for(l, s, [&] { return left_ == 0; });
    }
};

/**
 * The counter executor: an atomic count of unfinished parents per node; the last parent to finish submits the child.
 * A failed (or skipped) parent poisons its children: they complete as skipped without running, like a
 * CompletableFuture whose input completed exceptionally. With `token`, nothing new starts after the first failure.
 */
struct CountedRun {
    const Graph& g;
    Executor& exec;
    Trace& trace;
    std::chrono::milliseconds sleep;
    sz fail_at;
    std::atomic<bool>* token;
    std::vector<std::atomic<int>> waiting;
    std::vector<std::atomic<bool>> poisoned;
    Done done;

    CountedRun(const Graph& graph, Executor& e, Trace& t, std::chrono::milliseconds s, sz fail, std::atomic<bool>* tok)
        : g(graph), exec(e), trace(t), sleep(s), fail_at(fail), token(tok), waiting(graph.n), poisoned(graph.n), done(graph.n) {
        for (sz v = 0; v < g.n; ++v) waiting[v].store(static_cast<int>(g.parents[v].size()));
    }

    void node(sz v) {
        bool failed = poisoned[v].load() || (token && token->load());
        if (!failed) {
            trace.run(v, sleep);
            if (v == fail_at) {
                failed = true;
                if (token) token->store(true);  // tell everyone else to stop starting work
            }
        }
        for (const sz c : g.children[v]) {
            if (failed) poisoned[c].store(true);  // before the decrement, so the last parent's decrement sees it
            if (waiting[c].fetch_sub(1) == 1) exec.execute([this, c] { node(c); });
        }
        done.count_down();
    }

    bool start_and_wait() {
        for (sz v = 0; v < g.n; ++v)
            if (g.parents[v].empty()) exec.execute([this, v] { node(v); });
        return done.wait_for(30s);
    }
};

// ---- coroutines: 10,000 concurrent waits on ONE thread (the stackless analog of virtual threads)

class Loop {
    using Clock = std::chrono::steady_clock;
    std::priority_queue<std::pair<Clock::time_point, std::coroutine_handle<>>, std::vector<std::pair<Clock::time_point, std::coroutine_handle<>>>,
                        std::greater<>>
        timers_;

public:
    struct Sleep {
        Loop& loop;
        Clock::duration d;
        bool await_ready() const noexcept { return false; }
        void await_suspend(std::coroutine_handle<> h) { loop.timers_.emplace(Clock::now() + d, h); }  // park the frame, not a thread
        void await_resume() const noexcept {}
    };
    Sleep sleep_for(Clock::duration d) { return {*this, d}; }
    void run() {  // one thread: resume whichever coroutine's timer is due next
        while (!timers_.empty()) {
            const auto [when, h] = timers_.top();
            timers_.pop();
            std::this_thread::sleep_until(when);
            h.resume();
        }
    }
};

struct Detached {  // fire-and-forget coroutine: starts eagerly, frees its frame when it finishes
    struct promise_type {
        Detached get_return_object() noexcept { return {}; }
        std::suspend_never initial_suspend() noexcept { return {}; }
        std::suspend_never final_suspend() noexcept { return {}; }
        void return_void() noexcept {}
        void unhandled_exception() noexcept { std::terminate(); }
    };
};

Detached io_task(Loop& loop, int& done) {
    co_await loop.sleep_for(20ms);  // "blocking" I/O that blocks nothing
    ++done;
}

i64 ms_since(std::chrono::steady_clock::time_point t0) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    const Graph g = Graph::layered(8, 100, 3, 7);
    std::println("== 1. 800-node layered DAG (8 layers x 100, fan-in 3), 2 ms of blocking I/O per node ==");
    Trace t1(g.n), t2(g.n);
    auto t0 = std::chrono::steady_clock::now();
    bool ok1 = false, ok2 = false;
    {
        FixedPool pool(64);
        CountedRun run(g, pool, t1, 2ms, g.n, nullptr);
        ok1 = run.start_and_wait();
    }
    const i64 pool_ms = ms_since(t0);
    t0 = std::chrono::steady_clock::now();
    {
        ThreadPerTask tpt;
        CountedRun run(g, tpt, t2, 2ms, g.n, nullptr);
        ok2 = run.start_and_wait();
    }
    const i64 tpt_ms = ms_since(t0);
    std::println("  dependency counters on a pool of 64:       {} runs, {} order violations, {} ms (critical path 8 x 2 ms)", t1.runs.load(), t1.violations(g),
                 pool_ms);
    std::println("  dependency counters, thread per ready node: {} runs, {} order violations, {} ms", t2.runs.load(), t2.violations(g), tpt_ms);

    std::println("== 2. Blocking vs CPU-bound tasks: a pool vs a thread per task vs coroutines on one thread ==");
    t0 = std::chrono::steady_clock::now();
    {
        FixedPool pool(64);
        for (int i = 0; i < 2'000; ++i) pool.execute([] { std::this_thread::sleep_for(20ms); });
    }
    const i64 io_pool = ms_since(t0);
    t0 = std::chrono::steady_clock::now();
    {
        ThreadPerTask tpt;
        for (int i = 0; i < 2'000; ++i) tpt.execute([] { std::this_thread::sleep_for(20ms); });
    }
    const i64 io_threads = ms_since(t0);
    t0 = std::chrono::steady_clock::now();
    int co_done = 0;
    {
        Loop loop;
        for (int i = 0; i < 10'000; ++i) io_task(loop, co_done);
        loop.run();
    }
    const i64 io_co = ms_since(t0);
    std::println("  2,000 tasks x 20 ms sleep: pool of 64 threads {} ms | an OS thread per task {} ms", io_pool, io_threads);
    std::println("  10,000 coroutines x 20 ms co_await sleep on ONE thread: {} ms ({} finished)", io_co, co_done);
    const int cores = static_cast<int>(std::thread::hardware_concurrency());
    std::array<i64, 2> cpu{};
    std::atomic<u64> sink{0};
    for (sz mode = 0; mode < 2; ++mode) {
        t0 = std::chrono::steady_clock::now();
        {
            std::unique_ptr<Executor> ex;
            if (mode == 0) ex = std::make_unique<FixedPool>(cores);
            else ex = std::make_unique<ThreadPerTask>();
            for (int i = 0; i < 64; ++i)
                ex->execute([&] {
                    u64 x = 0;
                    for (u64 k = 0; k < 20'000'000; ++k) x += mix64(k);
                    sink += x;
                });
        }
        cpu[mode] = ms_since(t0);
    }
    std::println("  64 CPU-bound tasks: pool of {} (cores) {} ms | thread per task {} ms", cores, cpu[0], cpu[1]);

    std::println("== 3. Node 150 (layer 1) fails: what still runs? ==");
    std::array<int, 2> ran{};
    for (sz mode = 0; mode < 2; ++mode) {
        Trace t(g.n);
        std::atomic<bool> token{false};
        {
            FixedPool pool(64);
            CountedRun run(g, pool, t, 2ms, 150, mode == 1 ? &token : nullptr);
            run.start_and_wait();
        }
        ran[mode] = t.runs.load();
    }
    std::vector<bool> reach(g.n);
    reach[150] = true;
    int downstream = 0;
    for (sz v = 151; v < g.n; ++v) {
        for (const sz p : g.parents[v]) reach[v] = reach[v] || reach[p];
        downstream += reach[v];
    }
    std::println("  {} of 800 nodes depend (transitively) on node 150", downstream);
    std::println("  poisoned dependents only: {} nodes ran (dependents skipped, independent work kept going)", ran[0]);
    std::println("  + cancellation token:     {} nodes ran (nothing new starts after the failure)", ran[1]);

    const bool ok = ok1 && ok2 && t1.runs.load() == 800 && t1.violations(g) == 0 && t2.runs.load() == 800 && t2.violations(g) == 0 && co_done == 10'000 &&
                    io_co < io_pool && ran[0] == 800 - downstream && ran[1] <= ran[0];
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. 800-node layered DAG (8 layers x 100, fan-in 3), 2 ms of blocking I/O per node ==
  dependency counters on a pool of 64:       800 runs, 0 order violations, 195 ms (critical path 8 x 2 ms)
  dependency counters, thread per ready node: 800 runs, 0 order violations, 126 ms
== 2. Blocking vs CPU-bound tasks: a pool vs a thread per task vs coroutines on one thread ==
  2,000 tasks x 20 ms sleep: pool of 64 threads 1025 ms | an OS thread per task 124 ms
  10,000 coroutines x 20 ms co_await sleep on ONE thread: 47 ms (10000 finished)
  64 CPU-bound tasks: pool of 12 (cores) 205 ms | thread per task 228 ms
== 3. Node 150 (layer 1) fails: what still runs? ==
  366 of 800 nodes depend (transitively) on node 150
  poisoned dependents only: 434 nodes ran (dependents skipped, independent work kept going)
  + cancellation token:     199 nodes ran (nothing new starts after the failure)
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. 800-node layered DAG (8 layers x 100, fan-in 3), 2 ms of blocking I/O per node ==
  dependency counters on a pool of 64:       800 runs, 0 order violations, 199 ms (critical path 8 x 2 ms)
  dependency counters, thread per ready node: 800 runs, 0 order violations, 126 ms
== 2. Blocking vs CPU-bound tasks: a pool vs a thread per task vs coroutines on one thread ==
  2,000 tasks x 20 ms sleep: pool of 64 threads 1000 ms | an OS thread per task 98 ms
  10,000 coroutines x 20 ms co_await sleep on ONE thread: 26 ms (10000 finished)
  64 CPU-bound tasks: pool of 12 (cores) 249 ms | thread per task 262 ms
== 3. Node 150 (layer 1) fails: what still runs? ==
  366 of 800 nodes depend (transitively) on node 150
  poisoned dependents only: 434 nodes ran (dependents skipped, independent work kept going)
  + cancellation token:     215 nodes ran (nothing new starts after the failure)
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Scheduling | Run layers one after another | `allOf(parents).thenRunAsync` | Composition or counters (last decrement schedules), with ordering verified by start/finish traces |
| Threads | Big fixed pool for everything | Separate pools for I/O and CPU | Virtual threads for blocking, a cores-sized pool for CPU; JEP 491 pinning changes known; in C++, coroutines for many waits |
| Failure | Exceptions lost in a pool | `exceptionally` handlers | Knows dependents vs independents; adds a cancellation token; knows `cancel`/`orTimeout` don't stop running work; uses structured concurrency where available |
| Measurement | Average task time | Wall time | Critical path vs wall, timer-resolution effects per platform, CPU-vs-blocking split |

## 7. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "We moved our I/O service to virtual threads. Will it be faster?"</b></summary>

**L5:** "Yes, virtual threads are faster."

**Why it fails:** they're cheaper to block, not faster to compute. CPU-bound tasks took 229 ms vs 249 ms on 12 cores, which is the same thing.

**L7 defence:** "For blocking work they remove the thread-count ceiling: 10,000 × 20 ms sleeps in 47 ms vs 3.2 s on 64 platform threads. CPU-bound work stays on a cores-sized pool. Watch remaining pinning sources (native frames) and resource limits that threads used to throttle implicitly, like connection pools."
</details>

<details>
<summary><b>Q2 ⚡ "A task failed. Did the rest of the DAG stop?"</b></summary>

**L5:** "Yes, the future completed exceptionally."

**Why it fails:** only *dependents* were skipped. 434 independent nodes still ran, and `cancel(true)` wouldn't have interrupted them.

**L7 defence:** "A cancellation token checked before each task starts (cut it to ~200 here), interruption or cooperative checks in long tasks, or a `StructuredTaskScope` that cancels its subtasks when one fails."
</details>

<details>
<summary><b>Q3 ⚡ "Do this in C++ without CompletableFuture."</b></summary>

**L5:** "`std::async` and `.get()` on each parent."

**Why it fails:** blocking `get()` inside tasks ties up a thread per waiting node, and `std::future` has no continuations.

**L7 defence:** "Dependency counters with last-decrement-schedules on a pool, with poisoning for failure propagation, identical to the Java semantics (434 / 366). For thousands of concurrent waits, C++20 coroutines on an event loop: 10,000 waits on one thread in 26–47 ms."
</details>

## 8. Checklist and references

- [ ] One scheduling rule (last decrement schedules); ordering verified with traces.
- [ ] Executor matched to the work: virtual threads or coroutines for blocking, a cores-sized pool for CPU.
- [ ] Failure: dependents skipped; independents stopped by an explicit token or structured scope.
- [ ] Timeouts: the future fails, *and* the work is told to stop.
- [ ] Platform timer resolution accounted for in measurements.

**References:**
- JEP 444, *Virtual Threads*. <https://openjdk.org/jeps/444>
- JEP 491, *Synchronize Virtual Threads without Pinning*. <https://openjdk.org/jeps/491>
- JEP 505, *Structured Concurrency (Fifth Preview)*. <https://openjdk.org/jeps/505>
- Java `CompletableFuture`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/CompletableFuture.html>
- cppreference, *Coroutines (C++20)*. <https://en.cppreference.com/w/cpp/language/coroutines>
- In this KB: [P20 Workflow semantics](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/05-problem-20-dynamic-rule-engine-and-json-Workflow-state-orchestrator.md) · [P3 Timer wheels](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/03-problem-03-delayed-job-scheduler-and-hierarchical-timing-wheel.md)
