# P5 · Bounded Blocking Connection Pool and a Lock-Free Circuit Breaker

> **Folder 03 · Problem 5 of 20.** Two resilience primitives every backend owns: a **pool** that bounds how many connections are out, makes waiting finite, and never lends a connection twice; and a **circuit breaker** that stops calling a failing dependency, probes it carefully, and closes again. The L7 content is the invariants under races: exactly one transition per episode, exactly `k` half-open probes, an idempotent return, and bounded waits.
>
> **Listing pair P5:** `PoolAndBreaker.java` / `pool_and_breaker.cpp`. The state-machine sections are deterministic, and the invariants (≤ max out, 0 double lends, 1 open per episode, exactly 3 trials) are asserted. Counts are one measured run.

---

## 1. Problem and scope

**Pool:**
- `borrow(timeout) → Lease | timeout`; `lease.close()` returns it (idempotent);
- at most `max` connections out;
- LIFO reuse (the warmest connection first);
- validation of stale idle connections;
- leak detection for leases held too long.

**Breaker:**
- `call(backend)`: rejects fast while Open;
- moves Closed → Open when the failure rate over the last *N* calls reaches a threshold (once a minimum call count is met);
- after a wait, HalfOpen admits exactly *k* trials: all succeed → Closed, any failure → Open.

**Composition (state it):** the breaker goes **outside** the pool. A failing dependency then rejects callers *before* they occupy a connection or a pool waiter slot. Breaker inside the pool means every doomed call still waits for and holds a connection.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Capacity | `Semaphore(max, fair?)` | `std::counting_semaphore<1024>` |
| Idle set | `ConcurrentLinkedDeque` (LIFO via `pollFirst`/`offerFirst`) | `std::deque<Conn*>` under a mutex |
| Lease | `AutoCloseable`, `AtomicBoolean returned` | move-only RAII type with an idempotent `release()` |
| Breaker state | `sealed State permits Closed, Open, HalfOpen`; a fresh `Closed` (with its own ring) per episode; CAS on `AtomicReference<State>` | `StateNode` published through `std::atomic<StateNode*>`; every node kept alive (transitions are rare) |
| Ring | `AtomicLongArray` of outcome bits + `AtomicLong calls` + `AtomicInteger failures` | `std::vector<std::atomic<u64>>` + atomics |

**Invariants:**
- **P1:** connections out ≤ `max` at every instant. Measured `maxObservedOut` = 4 of 4.
- **P2:** a connection is never lent twice concurrently. A per-connection `inUse` CAS detector counted 0.
- **P3:** a lease returns its connection exactly once, however many times `close()` runs (exercised every 1,000 iterations).
- **P4:** every wait is bounded (`tryAcquire(timeout)`), and a failure after acquiring a permit releases it.
- **B1:** exactly one Closed → Open transition per failure episode, however many threads observe the threshold.
- **B2:** in HalfOpen, exactly `k` calls reach the backend. Others are rejected until the state changes, and calls *after* the breaker closes pass normally (the Clang run's 4th backend call).
- **B3:** a result recorded against an old Closed window can't affect a new one.

## 3. Concurrency and contention analysis

**The pool's two-step borrow.** First take a permit (capacity), then take or create a connection.
- The `Semaphore` enforces P1 without any lock around the deque.
- The deque is lock-free in Java; in C++ it's a short mutex section.
- **Creating a connection happens outside any lock.** A TCP + TLS handshake under a lock serializes every borrower (HikariCP adds connections from a separate thread).
- If anything throws after the permit is acquired, the permit is released. Otherwise the pool shrinks by one, permanently, per exception: a classic slow leak.

**Validation.** Validate on borrow only if the connection was idle longer than a threshold (`validateAfterIdle`). Validating every borrow doubles the round trips, and never validating hands out sockets the database killed long ago. The fake-clock test marks an idle connection broken, advances 1 minute, and borrows: the stale broken connection is discarded and a healthy one is used.

**Leaks.** `suspectedLeaks(threshold)` lists leases held longer than the threshold. In production that's HikariCP's `leakDetectionThreshold` log with the borrower's stack trace.

**Fair vs barging.**
- `Semaphore(max, true)` hands permits out in FIFO order, which bounds the worst-case wait but costs throughput.
- Barging (`false`) is faster on average (01.3 §4.2 measured fair locks at ~4 µs per hand-off).
- Pools usually choose barging plus a bounded timeout; the timeout is the fairness backstop.

**The breaker's races, and how CAS answers them:**
- **Many threads see the threshold at once.** Each tries `compareAndSet(closed, new Open(now))`. The CAS is on *identity*, so exactly one wins, and the transition log shows one `Closed->Open` per episode (B1). Measured: 80,000 calls against a dead backend, of which **27** (Java) / 20–27 (C++) reached it before the breaker opened. The rest were rejected without touching the network.
- **Many threads see the wait expire at once.** Each tries Open → HalfOpen. One wins, and losers re-read the state.
- **HalfOpen admission.** `permits.getAndDecrement() > 0` grants exactly `k = 3` trial calls from 8 simultaneous callers (B2, asserted). Without it, the recovering dependency gets the whole backlog at once: the thundering herd.
- **Stale recordings (B3).** A thread that started its call in Closed episode #1 may finish after the breaker opened and closed again. Recording into episode #2's ring would corrupt it, so each episode gets a fresh window object. Java uses a new `Closed` instance (and identity); C++ uses a new `StateNode` with its own `Window`. Either way, the old window becomes unreachable for decisions.

**C++ reclamation, again.** Freeing an old `StateNode` while a slow caller still holds a pointer to it is use-after-free. Transitions are rare, so the breaker keeps every node alive, the same policy as 02.2's rule snapshots. A long-running service would add epoch reclamation (P4) or `shared_ptr`.

## 4. Java 21 implementation

```java
// PoolAndBreaker.java - P5: bounded blocking connection pool (Semaphore + deque) and a lock-free ring-bit circuit breaker
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentLinkedDeque;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.Supplier;

public final class PoolAndBreaker {

    @FunctionalInterface
    interface Ticker {
        long read();
    }

    static final class FakeTicker implements Ticker {
        final AtomicLong nanos = new AtomicLong();
        void advance(Duration d) { nanos.addAndGet(d.toNanos()); }
        @Override public long read() { return nanos.get(); }
    }

    // ===== Connection pool ========================================================================

    static final class Conn {
        final int id;
        final AtomicBoolean inUse = new AtomicBoolean();      // double-lend detector
        volatile boolean broken;
        volatile long lastUsedNanos;

        Conn(int id) { this.id = id; }

        boolean isValid() { return !broken; }                 // a real pool sends a ping / JDBC isValid()
    }

    /** Returned exactly once, whatever the caller does: close() is idempotent. */
    static final class Lease implements AutoCloseable {
        final Conn conn;
        final long borrowedAt;
        private final ConnectionPool pool;
        private final AtomicBoolean returned = new AtomicBoolean();

        Lease(Conn c, long borrowedAt, ConnectionPool pool) {
            this.conn = c;
            this.borrowedAt = borrowedAt;
            this.pool = pool;
        }

        @Override public void close() {
            if (returned.compareAndSet(false, true)) pool.giveBack(this);
        }
    }

    static final class ConnectionPool {
        private final Semaphore permits;                       // capacity: max connections OUT at once
        private final ConcurrentLinkedDeque<Conn> idle = new ConcurrentLinkedDeque<>();
        private final java.util.Set<Lease> active = java.util.concurrent.ConcurrentHashMap.newKeySet();
        private final AtomicInteger created = new AtomicInteger(), out = new AtomicInteger();
        private final Ticker ticker;
        private final long validateAfterIdleNanos;
        final AtomicInteger maxObservedOut = new AtomicInteger();
        final LongAdder doubleLends = new LongAdder(), discardedInvalid = new LongAdder(), timeouts = new LongAdder();

        ConnectionPool(int max, Duration validateAfterIdle, Ticker ticker, boolean fair) {
            permits = new Semaphore(max, fair);
            this.ticker = ticker;
            this.validateAfterIdleNanos = validateAfterIdle.toNanos();
        }

        Optional<Lease> borrow(Duration timeout) throws InterruptedException {
            if (!permits.tryAcquire(timeout.toNanos(), TimeUnit.NANOSECONDS)) {
                timeouts.increment();
                return Optional.empty();                       // bounded wait: fail fast, never hang
            }
            try {
                Conn c;
                while ((c = idle.pollFirst()) != null) {       // LIFO: the warmest connection first
                    if (ticker.read() - c.lastUsedNanos < validateAfterIdleNanos || c.isValid()) break;
                    discardedInvalid.increment();              // stale + failed validation: drop and keep looking
                }
                if (c == null) c = new Conn(created.incrementAndGet());   // create outside any lock
                if (!c.inUse.compareAndSet(false, true)) doubleLends.increment();
                int now = out.incrementAndGet();
                maxObservedOut.accumulateAndGet(now, Math::max);
                Lease l = new Lease(c, ticker.read(), this);
                active.add(l);
                return Optional.of(l);
            } catch (RuntimeException e) {
                permits.release();                             // never leak a permit on failure
                throw e;
            }
        }

        private void giveBack(Lease l) {
            active.remove(l);
            Conn c = l.conn;
            c.lastUsedNanos = ticker.read();
            c.inUse.set(false);
            out.decrementAndGet();
            if (c.isValid()) idle.offerFirst(c);
            else discardedInvalid.increment();
            permits.release();
        }

        /** Housekeeping: leases held longer than the threshold are reported as probable leaks. */
        List<Integer> suspectedLeaks(Duration threshold) {
            long now = ticker.read();
            List<Integer> ids = new ArrayList<>();
            for (Lease l : active) if (now - l.borrowedAt > threshold.toNanos()) ids.add(l.conn.id);
            ids.sort(null);
            return ids;
        }

        int created() { return created.get(); }
        int idleCount() { return idle.size(); }
    }

    // ===== Circuit breaker: ring of outcome bits, states switched by CAS ==========================

    sealed interface State permits Closed, Open, HalfOpen {}

    /** A fresh Closed per episode: a late record() against an old window can't trip a new one. */
    static final class Closed implements State {
        final int size;
        final AtomicLongArray bits;                            // 1 = failure, one bit per call slot
        final AtomicLong calls = new AtomicLong();
        final AtomicInteger failures = new AtomicInteger();

        Closed(int size) {
            this.size = size;
            this.bits = new AtomicLongArray((size + 63) / 64);
        }

        /** Overwrite the oldest slot; returns {failures, callsInWindow}. Lock-free. */
        int[] record(boolean failed) {
            long i = calls.getAndIncrement() % size;
            int word = (int) (i >>> 6);
            long mask = 1L << (i & 63);
            while (true) {
                long cur = bits.get(word);
                long next = failed ? cur | mask : cur & ~mask;
                if (bits.compareAndSet(word, cur, next)) {
                    int delta = (failed ? 1 : 0) - ((cur & mask) != 0 ? 1 : 0);
                    int f = delta == 0 ? failures.get() : failures.addAndGet(delta);
                    return new int[] {f, (int) Math.min(calls.get(), size)};
                }
            }
        }
    }

    record Open(long since) implements State {}

    static final class HalfOpen implements State {
        final AtomicInteger permits, successes = new AtomicInteger();

        HalfOpen(int trials) {
            permits = new AtomicInteger(trials);
        }
    }

    static final class CircuitBreaker {
        final AtomicReference<State> state;
        private final int window, minCalls, failurePercent, trials;
        private final long openNanos;
        private final Ticker ticker;
        final List<String> transitions = java.util.Collections.synchronizedList(new ArrayList<>());
        final LongAdder rejected = new LongAdder(), trialCalls = new LongAdder();

        CircuitBreaker(int window, int minCalls, int failurePercent, Duration open, int trials, Ticker ticker) {
            this.window = window;
            this.minCalls = minCalls;
            this.failurePercent = failurePercent;
            this.openNanos = open.toNanos();
            this.trials = trials;
            this.ticker = ticker;
            this.state = new AtomicReference<>(new Closed(window));
        }

        private boolean move(State from, State to) {
            if (!state.compareAndSet(from, to)) return false;  // identity CAS: exactly one thread wins
            transitions.add(from.getClass().getSimpleName() + "->" + to.getClass().getSimpleName());
            return true;
        }

        <T> Optional<T> call(Supplier<T> backend) {
            while (true) {
                State s = state.get();
                switch (s) {
                    case Open o -> {
                        if (ticker.read() - o.since() < openNanos) {
                            rejected.increment();
                            return Optional.empty();           // fail fast: no thread, no connection used
                        }
                        move(o, new HalfOpen(trials));         // loser of the race just re-reads
                        continue;
                    }
                    case HalfOpen h -> {
                        if (h.permits.getAndDecrement() <= 0) {
                            rejected.increment();
                            return Optional.empty();           // only `trials` calls probe the backend
                        }
                        trialCalls.increment();
                        try {
                            T v = backend.get();
                            if (h.successes.incrementAndGet() == trials) move(h, new Closed(window));
                            return Optional.of(v);
                        } catch (RuntimeException e) {
                            move(h, new Open(ticker.read()));
                            return Optional.empty();
                        }
                    }
                    case Closed c -> {
                        boolean failed = false;
                        T v = null;
                        try {
                            v = backend.get();
                        } catch (RuntimeException e) {
                            failed = true;
                        }
                        int[] fc = c.record(failed);
                        if (fc[1] >= minCalls && fc[0] * 100 >= failurePercent * fc[1]) move(c, new Open(ticker.read()));
                        return failed ? Optional.empty() : Optional.of(v);
                    }
                }
            }
        }

        String name() {
            return state.get().getClass().getSimpleName();
        }
    }

    interface Body {
        void run(int thread) throws Exception;
    }

    static void parallel(int threads, Body body) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        for (int t = 0; t < threads; t++) {
            final int id = t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    body.run(id);
                    end.await();
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        start.await();
        end.await();
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Pool: 8 threads x 20,000 borrow/use/return, max 4 connections, 1 ms borrow timeout ==");
        ConnectionPool pool = new ConnectionPool(4, Duration.ofSeconds(30), System::nanoTime, false);
        LongAdder served = new LongAdder();
        parallel(8, t -> {
            for (int i = 0; i < 20_000; i++) {
                Optional<Lease> l = pool.borrow(Duration.ofMillis(1));
                if (l.isEmpty()) continue;
                try (Lease lease = l.get()) {
                    for (int k = 0; k < 20; k++) Thread.onSpinWait();   // "use" the connection
                    if (lease.conn.inUse.get()) served.increment();   // we hold it: it must be marked in use
                }
                if (i % 1_000 == 0) l.get().close();                   // a second close: must be harmless
            }
        });
        System.out.printf("  served %,d | timed out %,d | max connections out at once %d (limit 4) | created %d | double lends %d%n",
                served.sum(), pool.timeouts.sum(), pool.maxObservedOut.get(), pool.created(), pool.doubleLends.sum());

        System.out.println("== 2. Pool (max 2): stale validation, borrow timeout, leak detection (fake clock) ==");
        FakeTicker tk = new FakeTicker();
        ConnectionPool p2 = new ConnectionPool(2, Duration.ofSeconds(30), tk, true);   // max 2: the third borrow must wait
        Lease a = p2.borrow(Duration.ZERO).orElseThrow(), b = p2.borrow(Duration.ZERO).orElseThrow();
        a.close();
        b.close();
        p2.idle.peekFirst().broken = true;                     // the DB killed an idle socket
        tk.advance(Duration.ofMinutes(1));
        Lease c = p2.borrow(Duration.ZERO).orElseThrow();       // stale + invalid -> discarded, next one used
        Lease leaked = p2.borrow(Duration.ZERO).orElseThrow();
        tk.advance(Duration.ofMinutes(10));
        Optional<Lease> d = p2.borrow(Duration.ofMillis(5));
        System.out.println("  discarded invalid " + p2.discardedInvalid.sum() + ", connections created " + p2.created()
                + ", third borrow -> " + (d.isPresent() ? "ok" : "timeout") + ", suspected leaks (held > 5 min) " + p2.suspectedLeaks(Duration.ofMinutes(5)));
        c.close();
        d.ifPresent(Lease::close);
        leaked.close();

        System.out.println("== 3. Breaker state machine (window 10, min 10 calls, >=50% failures, open 30 s, 3 trials) ==");
        FakeTicker clock = new FakeTicker();
        CircuitBreaker cb = new CircuitBreaker(10, 10, 50, Duration.ofSeconds(30), 3, clock);
        AtomicBoolean failing = new AtomicBoolean(true);
        Supplier<String> backend = () -> {
            if (failing.get()) throw new IllegalStateException("503");
            return "ok";
        };
        for (int i = 0; i < 10; i++) {
            failing.set(i % 10 < 6);                           // 6 of 10 fail
            cb.call(backend);
        }
        System.out.println("  after 6/10 failures: " + cb.name() + "; call while open -> " + cb.call(backend).orElse("rejected"));
        clock.advance(Duration.ofSeconds(30));
        failing.set(false);
        for (int i = 0; i < 3; i++) cb.call(backend);
        System.out.println("  after 30 s and 3 successful trials: " + cb.name());
        for (int i = 0; i < 10; i++) {
            failing.set(true);
            cb.call(backend);
        }
        clock.advance(Duration.ofSeconds(30));
        cb.call(backend);                                      // half-open trial fails
        System.out.println("  failing trial in HalfOpen -> " + cb.name() + "; transitions " + cb.transitions);

        System.out.println("== 4. Breaker under contention: 8 threads, backend 100% failing, then recovering ==");
        FakeTicker c4 = new FakeTicker();
        CircuitBreaker hot = new CircuitBreaker(100, 20, 50, Duration.ofSeconds(10), 3, c4);
        LongAdder reachedBackend = new LongAdder();
        AtomicBoolean down = new AtomicBoolean(true);
        Supplier<String> flaky = () -> {
            reachedBackend.increment();
            for (int k = 0; k < 2_000; k++) Thread.onSpinWait();   // a slow-ish call widens the race windows
            if (down.get()) throw new IllegalStateException("down");
            return "ok";
        };
        parallel(8, t -> {
            for (int i = 0; i < 10_000; i++) hot.call(flaky);
        });
        long phase1 = reachedBackend.sum();
        c4.advance(Duration.ofSeconds(10));
        down.set(false);
        reachedBackend.reset();
        parallel(8, t -> hot.call(flaky));                     // 8 simultaneous callers right after the open period
        System.out.printf("  80,000 calls while down: %,d reached the backend, %,d rejected fast; opens recorded %d%n", phase1,
                hot.rejected.sum(), hot.transitions.stream().filter(s -> s.equals("Closed->Open")).count());
        System.out.println("  8 simultaneous callers after the wait: " + hot.trialCalls.sum() + " trial calls while HalfOpen (permits 3), "
                + reachedBackend.sum() + " reached the backend in total (after closing, calls pass); state " + hot.name()
                + "; transitions " + hot.transitions);

        boolean ok = pool.maxObservedOut.get() <= 4 && pool.doubleLends.sum() == 0 && p2.discardedInvalid.sum() == 1
                && d.isEmpty() && cb.name().equals("Open") && hot.trialCalls.sum() == 3 && hot.name().equals("Closed")
                && hot.transitions.stream().filter(s -> s.equals("Closed->Open")).count() == 1;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 2–3 deterministic; sections 1 and 4 one measured run with asserted invariants):**

```text
== 1. Pool: 8 threads x 20,000 borrow/use/return, max 4 connections, 1 ms borrow timeout ==
  served 159,992 | timed out 8 | max connections out at once 4 (limit 4) | created 4 | double lends 0
== 2. Pool (max 2): stale validation, borrow timeout, leak detection (fake clock) ==
  discarded invalid 1, connections created 3, third borrow -> timeout, suspected leaks (held > 5 min) [1, 3]
== 3. Breaker state machine (window 10, min 10 calls, >=50% failures, open 30 s, 3 trials) ==
  after 6/10 failures: Open; call while open -> rejected
  after 30 s and 3 successful trials: Closed
  failing trial in HalfOpen -> Open; transitions [Closed->Open, Open->HalfOpen, HalfOpen->Closed, Closed->Open, Open->HalfOpen, HalfOpen->Open]
== 4. Breaker under contention: 8 threads, backend 100% failing, then recovering ==
  80,000 calls while down: 27 reached the backend, 79,978 rejected fast; opens recorded 1
  8 simultaneous callers after the wait: 3 trial calls while HalfOpen (permits 3), 3 reached the backend in total (after closing, calls pass); state Closed; transitions [Closed->Open, Open->HalfOpen, HalfOpen->Closed]
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// pool_and_breaker.cpp - P5: bounded blocking pool (counting_semaphore) and a ring-bit circuit breaker
#include <algorithm>
#include <array>
#include <atomic>
#include <barrier>
#include <chrono>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <semaphore>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using namespace std::chrono_literals;

// ===== Connection pool ========================================================================

struct Conn {
    int id;
    std::atomic<bool> in_use{false};  // double-lend detector
    std::atomic<bool> broken{false};
    std::atomic<i64> last_used{0};
    explicit Conn(int i) : id(i) {}
    bool is_valid() const { return !broken.load(); }
};

class ConnectionPool;

class Lease {  // move-only RAII: the connection goes back exactly once
    ConnectionPool* pool_;
    Conn* conn_;
public:
    Lease(ConnectionPool* p, Conn* c) : pool_(p), conn_(c) {}
    Lease(Lease&& o) noexcept : pool_(std::exchange(o.pool_, nullptr)), conn_(o.conn_) {}
    Lease(const Lease&) = delete;
    Lease& operator=(const Lease&) = delete;
    Lease& operator=(Lease&&) = delete;
    ~Lease() { release(); }
    void release();  // idempotent
    Conn& conn() const { return *conn_; }
};

class ConnectionPool {
    std::counting_semaphore<1024> permits_;
    std::mutex m_;
    std::deque<Conn*> idle_;                      // front = warmest (LIFO)
    std::vector<std::unique_ptr<Conn>> all_;      // ownership
    std::unordered_map<int, i64> active_;         // conn id -> borrowed at
    std::function<i64()> now_;
    i64 validate_after_;
    std::atomic<int> out_{0};
public:
    std::atomic<int> max_observed_out{0}, created{0};
    std::atomic<u64> double_lends{0}, discarded_invalid{0}, timeouts{0};

    ConnectionPool(std::ptrdiff_t max, std::chrono::nanoseconds validate_after, std::function<i64()> now)
        : permits_(max), now_(std::move(now)), validate_after_(validate_after.count()) {}

    std::optional<Lease> borrow(std::chrono::nanoseconds timeout) {
        if (!permits_.try_acquire_for(timeout)) {
            timeouts.fetch_add(1);
            return std::nullopt;  // bounded wait: fail fast, never hang
        }
        Conn* c = nullptr;
        {
            std::scoped_lock l(m_);
            while (!idle_.empty()) {
                c = idle_.front();
                idle_.pop_front();
                if (now_() - c->last_used.load() < validate_after_ || c->is_valid()) break;
                discarded_invalid.fetch_add(1);  // stale and failed validation
                c = nullptr;
            }
            if (!c) {
                all_.push_back(std::make_unique<Conn>(created.fetch_add(1) + 1));  // a real pool connects OUTSIDE the lock
                c = all_.back().get();
            }
            active_[c->id] = now_();
        }
        if (c->in_use.exchange(true)) double_lends.fetch_add(1);
        const int now_out = out_.fetch_add(1) + 1;
        int seen = max_observed_out.load();
        while (now_out > seen && !max_observed_out.compare_exchange_weak(seen, now_out)) {}
        return Lease(this, c);
    }
    void give_back(Conn* c) {
        c->last_used.store(now_());
        c->in_use.store(false);
        out_.fetch_sub(1);
        {
            std::scoped_lock l(m_);
            active_.erase(c->id);
            if (c->is_valid()) idle_.push_front(c);
            else discarded_invalid.fetch_add(1);
        }
        permits_.release();
    }
    std::vector<int> suspected_leaks(std::chrono::nanoseconds threshold) {
        std::scoped_lock l(m_);
        std::vector<int> ids;
        for (const auto& [id, at] : active_)
            if (now_() - at > threshold.count()) ids.push_back(id);
        std::ranges::sort(ids);
        return ids;
    }
    void break_warmest_idle() {
        std::scoped_lock l(m_);
        if (!idle_.empty()) idle_.front()->broken.store(true);
    }
};

void Lease::release() {
    if (pool_) std::exchange(pool_, nullptr)->give_back(conn_);
}

// ===== Circuit breaker =========================================================================

enum class Kind { Closed, Open, HalfOpen };
constexpr const char* kKind[] = {"Closed", "Open", "HalfOpen"};

struct Window {  // one per Closed episode, so a late record() can't touch a newer window
    int size;
    std::vector<std::atomic<u64>> bits;
    std::atomic<u64> calls{0};
    std::atomic<int> failures{0};
    explicit Window(int n) : size(n), bits(static_cast<std::size_t>((n + 63) / 64)) {}
    std::pair<int, int> record(bool failed) {  // lock-free; returns {failures, calls in window}
        const u64 i = calls.fetch_add(1) % static_cast<u64>(size);
        auto& word = bits[static_cast<std::size_t>(i >> 6)];
        const u64 mask = u64{1} << (i & 63);
        u64 cur = word.load();
        while (!word.compare_exchange_weak(cur, failed ? cur | mask : cur & ~mask)) {}
        const int delta = (failed ? 1 : 0) - ((cur & mask) ? 1 : 0);
        const int f = delta == 0 ? failures.load() : failures.fetch_add(delta) + delta;
        return {f, static_cast<int>(std::min<u64>(calls.load(), static_cast<u64>(size)))};
    }
};

struct StateNode {
    Kind kind;
    i64 since = 0;
    std::unique_ptr<Window> window;  // Closed only
    std::atomic<int> permits{0}, successes{0};  // HalfOpen only
};

class CircuitBreaker {
    std::mutex alloc_m_;
    std::deque<std::unique_ptr<StateNode>> nodes_;  // every published state stays alive: transitions are rare
    std::atomic<StateNode*> state_;
    int window_, min_calls_, failure_percent_, trials_;
    i64 open_nanos_;
    std::function<i64()> now_;
    std::mutex log_m_;

    StateNode* make(Kind k) {
        std::scoped_lock l(alloc_m_);
        auto n = std::make_unique<StateNode>();
        n->kind = k;
        n->since = now_();
        if (k == Kind::Closed) n->window = std::make_unique<Window>(window_);
        if (k == Kind::HalfOpen) n->permits.store(trials_);
        nodes_.push_back(std::move(n));
        return nodes_.back().get();
    }
    void move(StateNode* from, Kind to) {
        StateNode* next = make(to);
        StateNode* expected = from;
        if (state_.compare_exchange_strong(expected, next)) {  // identity CAS: exactly one thread wins
            std::scoped_lock l(log_m_);
            transitions.push_back(std::string(kKind[static_cast<int>(from->kind)]) + "->" + kKind[static_cast<int>(to)]);
        }
    }
public:
    std::vector<std::string> transitions;
    std::atomic<u64> rejected{0}, trial_calls{0};
    CircuitBreaker(int window, int min_calls, int failure_percent, std::chrono::nanoseconds open, int trials, std::function<i64()> now)
        : window_(window), min_calls_(min_calls), failure_percent_(failure_percent), trials_(trials), open_nanos_(open.count()),
          now_(std::move(now)) {
        state_.store(make(Kind::Closed));
    }
    template <class F>
    std::optional<std::string> call(F&& backend) {
        while (true) {
            StateNode* s = state_.load();
            switch (s->kind) {
                case Kind::Open:
                    if (now_() - s->since < open_nanos_) {
                        rejected.fetch_add(1);
                        return std::nullopt;
                    }
                    move(s, Kind::HalfOpen);
                    continue;
                case Kind::HalfOpen:
                    if (s->permits.fetch_sub(1) <= 0) {
                        rejected.fetch_add(1);
                        return std::nullopt;
                    }
                    trial_calls.fetch_add(1);
                    try {
                        auto v = backend();
                        if (s->successes.fetch_add(1) + 1 == trials_) move(s, Kind::Closed);
                        return v;
                    } catch (const std::exception&) {
                        move(s, Kind::Open);
                        return std::nullopt;
                    }
                case Kind::Closed: {
                    std::optional<std::string> v;
                    bool failed = false;
                    try {
                        v = backend();
                    } catch (const std::exception&) {
                        failed = true;
                    }
                    const auto [f, n] = s->window->record(failed);
                    if (n >= min_calls_ && f * 100 >= failure_percent_ * n) move(s, Kind::Open);
                    return failed ? std::nullopt : v;
                }
            }
        }
    }
    const char* name() const { return kKind[static_cast<int>(state_.load()->kind)]; }
    i64 opens() {
        std::scoped_lock l(log_m_);
        return std::ranges::count(transitions, std::string("Closed->Open"));
    }
};

template <class F>
void parallel(int threads, F body) {
    std::barrier sync(threads + 1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            sync.arrive_and_wait();
            body(t);
            sync.arrive_and_wait();
        });
    sync.arrive_and_wait();
    sync.arrive_and_wait();
}

i64 real_now() { return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

std::string join(const std::vector<std::string>& v) {
    std::string s;
    for (const auto& x : v) s += (s.empty() ? "" : ", ") + x;
    return "[" + s + "]";
}

int main() {
    std::println("== 1. Pool: 8 threads x 20,000 borrow/use/return, max 4 connections, 1 ms borrow timeout ==");
    ConnectionPool pool(4, 30s, real_now);
    std::atomic<u64> served{0};
    parallel(8, [&](int) {
        for (int i = 0; i < 20'000; ++i) {
            auto lease = pool.borrow(1ms);
            if (!lease) continue;
            for (int k = 0; k < 20; ++k) {
#if defined(__x86_64__) || defined(__i386__)
                __builtin_ia32_pause();
#endif
            }
            if (lease->conn().in_use.load()) served.fetch_add(1);
            if (i % 1'000 == 0) lease->release();  // explicit release, then the destructor: must be harmless
        }
    });
    std::println("  served {} | timed out {} | max connections out at once {} (limit 4) | created {} | double lends {}", served.load(),
                 pool.timeouts.load(), pool.max_observed_out.load(), pool.created.load(), pool.double_lends.load());

    std::println("== 2. Pool (max 2): stale validation, borrow timeout, leak detection (fake clock) ==");
    std::atomic<i64> fake{0};
    ConnectionPool p2(2, 30s, [&] { return fake.load(); });
    {
        auto a = p2.borrow(0ns);
        auto b = p2.borrow(0ns);
    }
    p2.break_warmest_idle();  // the DB killed an idle socket
    fake += std::chrono::nanoseconds(1min).count();
    auto c = p2.borrow(0ns);
    auto leaked = p2.borrow(0ns);
    fake += std::chrono::nanoseconds(10min).count();
    auto d = p2.borrow(5ms);
    const auto leaks = p2.suspected_leaks(5min);
    std::println("  discarded invalid {}, connections created {}, third borrow -> {}, suspected leaks (held > 5 min) [{}, {}]",
                 p2.discarded_invalid.load(), p2.created.load(), d ? "ok" : "timeout", leaks.at(0), leaks.at(1));

    std::println("== 3. Breaker state machine (window 10, min 10 calls, >=50% failures, open 30 s, 3 trials) ==");
    std::atomic<i64> clock{0};
    CircuitBreaker cb(10, 10, 50, 30s, 3, [&] { return clock.load(); });
    bool failing = true;
    auto backend = [&]() -> std::string {
        if (failing) throw std::runtime_error("503");
        return "ok";
    };
    for (int i = 0; i < 10; ++i) {
        failing = i % 10 < 6;
        cb.call(backend);
    }
    std::println("  after 6/10 failures: {}; call while open -> {}", cb.name(), cb.call(backend).value_or("rejected"));
    clock += std::chrono::nanoseconds(30s).count();
    failing = false;
    for (int i = 0; i < 3; ++i) cb.call(backend);
    std::println("  after 30 s and 3 successful trials: {}", cb.name());
    failing = true;
    for (int i = 0; i < 10; ++i) cb.call(backend);
    clock += std::chrono::nanoseconds(30s).count();
    cb.call(backend);
    std::println("  failing trial in HalfOpen -> {}; transitions {}", cb.name(), join(cb.transitions));

    std::println("== 4. Breaker under contention: 8 threads, backend 100% failing, then recovering ==");
    std::atomic<i64> c4{0};
    CircuitBreaker hot(100, 20, 50, 10s, 3, [&] { return c4.load(); });
    std::atomic<u64> reached{0};
    std::atomic<bool> down{true};
    auto flaky = [&]() -> std::string {
        reached.fetch_add(1);
        for (int k = 0; k < 2'000; ++k) {
#if defined(__x86_64__) || defined(__i386__)
            __builtin_ia32_pause();
#endif
        }
        if (down.load()) throw std::runtime_error("down");
        return "ok";
    };
    parallel(8, [&](int) {
        for (int i = 0; i < 10'000; ++i) hot.call(flaky);
    });
    const u64 phase1 = reached.load();
    c4 += std::chrono::nanoseconds(10s).count();
    down.store(false);
    reached.store(0);
    parallel(8, [&](int) { hot.call(flaky); });
    std::println("  80,000 calls while down: {} reached the backend, {} rejected fast; opens recorded {}", phase1, hot.rejected.load(), hot.opens());
    std::println("  8 simultaneous callers after the wait: {} trial calls while HalfOpen (permits 3), {} reached the backend in total (after closing, calls pass); state {}; transitions {}",
                 hot.trial_calls.load(), reached.load(), hot.name(), join(hot.transitions));

    const bool ok = pool.max_observed_out.load() <= 4 && pool.double_lends.load() == 0 && p2.discarded_invalid.load() == 1 && !d &&
                    std::string(cb.name()) == "Open" && hot.trial_calls.load() == 3 && std::string(hot.name()) == "Closed" && hot.opens() == 1;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Pool: 8 threads x 20,000 borrow/use/return, max 4 connections, 1 ms borrow timeout ==
  served 160000 | timed out 0 | max connections out at once 4 (limit 4) | created 4 | double lends 0
== 2. Pool (max 2): stale validation, borrow timeout, leak detection (fake clock) ==
  discarded invalid 1, connections created 3, third borrow -> timeout, suspected leaks (held > 5 min) [2, 3]
== 3. Breaker state machine (window 10, min 10 calls, >=50% failures, open 30 s, 3 trials) ==
  after 6/10 failures: Open; call while open -> rejected
  after 30 s and 3 successful trials: Closed
  failing trial in HalfOpen -> Open; transitions [Closed->Open, Open->HalfOpen, HalfOpen->Closed, Closed->Open, Open->HalfOpen, HalfOpen->Open]
== 4. Breaker under contention: 8 threads, backend 100% failing, then recovering ==
  80,000 calls while down: 27 reached the backend, 79978 rejected fast; opens recorded 1
  8 simultaneous callers after the wait: 3 trial calls while HalfOpen (permits 3), 3 reached the backend in total (after closing, calls pass); state Closed; transitions [Closed->Open, Open->HalfOpen, HalfOpen->Closed]
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Pool: 8 threads x 20,000 borrow/use/return, max 4 connections, 1 ms borrow timeout ==
  served 159980 | timed out 20 | max connections out at once 3 (limit 4) | created 4 | double lends 0
== 2. Pool (max 2): stale validation, borrow timeout, leak detection (fake clock) ==
  discarded invalid 1, connections created 3, third borrow -> timeout, suspected leaks (held > 5 min) [2, 3]
== 3. Breaker state machine (window 10, min 10 calls, >=50% failures, open 30 s, 3 trials) ==
  after 6/10 failures: Open; call while open -> rejected
  after 30 s and 3 successful trials: Closed
  failing trial in HalfOpen -> Open; transitions [Closed->Open, Open->HalfOpen, HalfOpen->Closed, Closed->Open, Open->HalfOpen, HalfOpen->Open]
== 4. Breaker under contention: 8 threads, backend 100% failing, then recovering ==
  80,000 calls while down: 20 reached the backend, 79984 rejected fast; opens recorded 1
  8 simultaneous callers after the wait: 3 trial calls while HalfOpen (permits 3), 4 reached the backend in total (after closing, calls pass); state Closed; transitions [Closed->Open, Open->HalfOpen, HalfOpen->Closed]
SELF-TEST OK
```

The C++ leak list is `[2, 3]` where Java's is `[1, 3]`. In C++ the two scoped leases are destroyed in reverse declaration order, so `b` returns first and `a` ends up warmest. The breaking and discarding hit connection 1 instead of 2. Same behaviour, different RAII order.

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Pool bound | `synchronized` list + `wait/notify` | `Semaphore` + concurrent deque | Plus: bounded waits everywhere, permit released on failure, creation outside locks, LIFO for warm connections, idle validation by age, leak detection |
| Return | `release(conn)` callable twice | try/finally | Idempotent lease (`AutoCloseable` / RAII); double-lend detector in tests |
| Breaker counting | A shared `int failures` reset by a timer | Count/time window with a lock | Lock-free ring-bit window; a fresh window per episode; integer threshold math |
| Transitions | `if (failures > n) state = OPEN` | `synchronized` transitions | Identity CAS on an immutable state; one transition per episode; HalfOpen with exactly `k` permits |
| Composition | The breaker inside the pool call | Unspecified | The breaker outside the pool; timeouts inside the breaker's failure definition; metrics per state transition |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Slow calls should count as failures" | Measure call duration; record `failed = threw \|\| duration > slowThreshold` (Resilience4j's slow-call rate). Same ring, a second bit array |
| "Time-based window instead of count-based" | A ring of per-second buckets `(successes, failures)` advanced by the injected ticker; the CAS per bucket mirrors P2's windows |
| "The pool should grow and shrink" | `minIdle`/`maxPool`; a housekeeper retires idle connections beyond `minIdle` after an idle timeout (from the cold end of the deque: `pollLast`) |
| "Database failover: all connections die at once" | The breaker opens. On HalfOpen success, the pool must also **evict** idle connections created before the failover (a generation number per connection) |
| "Bulkhead per downstream" | A pool (or semaphore) per dependency, so a slow dependency can't absorb all threads. The breaker per dependency too |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "8 threads see the failure threshold at the same moment. How many times does the breaker open?"</b></summary>

**L5:** "Once, because we check the state first."

**Why it fails:** check-then-set from 8 threads opens it 8 times: 8 `Open` timestamps, 8 alert events, possibly 8 half-open schedules.

**L7 defence:** "The state is an immutable object behind an `AtomicReference`, and every transition is `compareAndSet(observedState, next)`. Identity makes exactly one thread win per episode, and the others re-read. The transition log shows one `Closed->Open` across 80,000 concurrent calls."
</details>

<details>
<summary><b>Q2 ⚡ "Half-open: how many requests reach the recovering service?"</b></summary>

**L5:** "One test request."

**Why it fails:** without an admission permit, every caller that sees `HalfOpen` calls through, and the recovering service gets the backlog. With exactly one probe, a single random failure re-opens the breaker for another full wait.

**L7 defence:** "HalfOpen carries `k` permits taken by `getAndDecrement`, so exactly `k` calls probe (asserted with 8 simultaneous callers). All `k` succeed → Closed. Any failure → Open again. After it closes, calls pass normally, which is why the Clang run saw a 4th backend call: correct behaviour, not a leak."
</details>

<details>
<summary><b>Q3 ⚡ "What happens if <code>borrow()</code> throws after acquiring the semaphore?"</b></summary>

**L5:** "The exception propagates."

**Why it fails:** the permit is never released, so the pool permanently loses one unit of capacity. A few hundred exceptions later, every borrow times out, and nobody can find the cause because nothing is "out".

**L7 defence:** "Acquire the permit, then `try { … } catch { release the permit; rethrow }`. Return through an idempotent lease so double closes are harmless. Count `maxObservedOut` and double lends in stress tests, and alert on pool-wait timeouts."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| All borrows time out, nothing is out | Permit leaked on an exception path | Release on failure; idempotent lease |
| Random "connection reset" on the first query | Stale idle sockets handed out | Validate by idle age |
| Pool exhausted during a dependency outage | Breaker inside the pool, or none | Breaker outside the pool; timeouts |
| Alert storm / repeated opens | Racy state transitions | Identity CAS on an immutable state |
| Recovering service flattened | Unbounded half-open admission | `k` trial permits |
| Breaker trips "for no reason" | Late results recorded into a new window | Fresh window per episode |

- [ ] Capacity enforced by a semaphore; every wait bounded; permits released on failure.
- [ ] Leases idempotent; double lends detected in tests; leaks reported.
- [ ] Idle connections validated by age; connections created outside locks.
- [ ] Breaker transitions by CAS on immutable states; exactly `k` half-open trials; fresh windows per episode.
- [ ] The breaker wraps the pool, not the reverse.

## 10. References

- Michael Nygard, *Release It!*, 2nd ed., 2018: Circuit Breaker, Bulkhead, Timeouts.
- Resilience4j CircuitBreaker (ring-bit buffer, sliding windows, half-open permits). <https://resilience4j.readme.io/docs/circuitbreaker>
- HikariCP (`ConcurrentBag`, `leakDetectionThreshold`, idle validation). <https://github.com/brettwooldridge/HikariCP>
- Martin Fowler, "CircuitBreaker". <https://martinfowler.com/bliki/CircuitBreaker.html>
- In this KB: [01.3 Fair vs barging locks](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [02.1 State machines](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [P2 windows](02-problem-02-pluggable-rate-limiter-token-bucket-sliding-window-cas.md)
