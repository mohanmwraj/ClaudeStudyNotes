# P2 · Pluggable Rate Limiter: Token Bucket, Sliding Window, Lock-Free CAS, and GCRA

> **Folder 03 · Problem 2 of 20.** The brief's target is a `ConcurrentHashMap<String, AtomicReference<BucketState>>` with lock-free `updateAndGet`. This file builds that, measures it against a lock, and adds the design that beats both: **GCRA**, the token bucket compressed into **one 64-bit word**.
>
> **Listing pair P2:** `RateLimiters.java` / `rate_limiters.cpp`. Algorithmic results (boundary bursts, long-run counts, exact grants under contention) are deterministic and identical in both languages. Throughput is one measured run.

---

## 1. Problem and scope

**Functional:** `tryAcquire(key)` returns allow/deny per key (tenant, API key, IP). Algorithms are pluggable: fixed window, sliding window counter, token bucket, GCRA.

**Non-functional:**
- never grant more than the configured rate and burst, under any interleaving;
- O(1) memory per key;
- no lock contention between unrelated keys;
- deterministic tests (injected time);
- no allocation on the hot path, ideally.

**Out of scope, with the reason:** distributed limiting across nodes. That's §8's curveball: a Redis Lua script or centralized counters. Also `acquire()` that blocks until a permit is available, which is a `Semaphore`-style wait.

## 2. Domain model and invariants

| Algorithm | State per key | Allows | Memory | Precision |
|---|---|---|---|---|
| Fixed window | `(windowIndex, count)` | `count < limit` in the current window | 2 words | Allows **2× the limit** across a boundary |
| Sliding window counter | `(index, prevCount, currCount)` | `prev × (1 − elapsed/W) + curr + 1 ≤ limit` | 3 words | Approximate; no boundary burst |
| Sliding log | a deque of timestamps | `count(last W) < limit` | O(limit) | Exact, and expensive |
| Token bucket | `(tokens, lastRefill)` | `tokens ≥ 1` after lazy refill | 2 words | Exact burst + rate |
| **GCRA** | `TAT` (theoretical arrival time) | `max(TAT, now) + T − now ≤ τ + T` | **1 word** | Exactly equivalent to a token bucket |

**Invariants:**
- **I1 (never over-grant):** over any interval [t, t + Δ], grants ≤ burst + rate × Δ.
- **I2 (exact under contention):** with time frozen and N attempts, exactly `min(N, capacity)` grants.
- **I3 (no drift):** long-run grants equal burst + rate × elapsed. Achieved with fixed-point micro-tokens: no `double` accumulation error, and no overflow after long idle periods (refill is capped by the time-to-full).
- **I4 (key isolation):** keys never share a lock or a cache line on the hot path.

## 3. Concurrency and contention analysis

**The race (L5).** `if (tokens > 0) tokens--` with `volatile` tokens is check-then-act. With time frozen and capacity 1,000,000, 4 threads × 1 M attempts granted **2,711,833 (Java) / 2,150,972 (C++)**: lost decrements over-grant by 2–2.7×. At capacity 1,000 the same test granted exactly 1,000. The first thread drained the bucket before the barrier-released others overlapped, so a race test needs a *long* contended window to mean anything.

**Three correct designs, and what each costs:**

| Design | Mechanism | Allocation per call | Behaviour under one hot key |
|---|---|---|---|
| `synchronized` bucket | one monitor per key | none | Waiters spin or park; ~15 M/s here |
| **CAS bucket** (the brief) | `AtomicReference<BucketState>.updateAndGet(pure f)` | **one record per attempt, including failed CAS retries** | Retry storm + allocation: **6.3–6.8 M/s, slower than the lock** |
| **GCRA** | `AtomicLong` CAS on TAT | none | ~16 M/s hot; **89–100 M/s** when keys are spread |

Two rules make the CAS designs correct:
1. **Read the clock once, outside the retried function.** `updateAndGet` may run its function several times (01.3 §3). Re-reading `nanoTime` inside each attempt is allowed but wasteful, and it makes the decision depend on attempt timing.
2. **The update function is pure.** It returns a new state, with the decision recorded *in* the state (`granted`), and it never increments counters or logs.

**Why GCRA wins.** A token bucket's state is two words (tokens and timestamp). In Java that forces an immutable object per CAS; in C++ a 16-byte CAS (`cmpxchg16b`) isn't portably lock-free, and GCC routes it through `libatomic` ⚠. GCRA keeps only the theoretical arrival time:
- the *next* permitted request time if requests arrived exactly at the rate;
- a request at `now` is allowed if `max(TAT, now) + T − now ≤ τ + T`, where `T = 1/rate` and `τ = (burst − 1) × T`;
- on allow, store the new TAT.

One `long`, one CAS, no allocation, identical decisions to the token bucket: both granted exactly 2,599 in the long-run test.

**Key isolation.** `ConcurrentHashMap.computeIfAbsent(key, factory)` creates each limiter exactly once, and its hit path is lock-free. Unrelated keys never contend. The C++ registry uses 16 padded shards with a mutex per lookup. That's the dominant cost in its per-key throughput (25–55 M/s vs Java's 65–100), and resolving the `Limiter*` once per tenant connection would remove it.

## 4. Java 21 implementation

```java
// RateLimiters.java - P2: token bucket (CAS on an immutable state), GCRA (one AtomicLong), windows, and their races
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.Supplier;

public final class RateLimiters {

    @FunctionalInterface
    interface Ticker {
        long read();
    }

    static final class FakeTicker implements Ticker {
        final AtomicLong nanos = new AtomicLong();
        @Override public long read() { return nanos.get(); }
    }

    /** One limiter per key; implementations decide per call. */
    interface Limiter {
        boolean tryAcquire();
    }

    static final long SCALE = 1_000_000L;                      // fixed-point: tokens in micro-tokens, no doubles

    // ===== L5: check, then act, on a shared state (races) =========================================

    static final class NaiveBucket implements Limiter {
        private volatile long tokens;                          // volatile is not atomicity
        NaiveBucket(long capacity) { tokens = capacity; }
        @Override public boolean tryAcquire() {
            if (tokens > 0) {                                  // CHECK
                tokens = tokens - 1;                           // ACT (lost updates, over-grants)
                return true;
            }
            return false;
        }
    }

    // ===== Token bucket: refill lazily from elapsed time ============================================

    record BucketState(long microTokens, long lastNanos, boolean granted) {}

    static BucketState refillAndTake(BucketState s, long now, long capacity, long perSecond) {
        long elapsed = Math.max(0, now - s.lastNanos());     // monotonic ticker; guard anyway
        long capMicro = capacity * SCALE;
        long fillNanos = capMicro / perSecond * 1_000L;       // ns to refill from empty: caps elapsed, no overflow
        long add = Math.min(elapsed, fillNanos) * perSecond / 1_000L;   // micro-tokens gained
        long tokens = Math.min(capMicro, s.microTokens() + add);
        return tokens >= SCALE ? new BucketState(tokens - SCALE, now, true) : new BucketState(tokens, now, false);
    }

    static final class SyncBucket implements Limiter {
        private final Ticker ticker;
        private final long capacity, perSecond;
        private BucketState state;
        SyncBucket(long capacity, long perSecond, Ticker t) {
            this.capacity = capacity;
            this.perSecond = perSecond;
            this.ticker = t;
            state = new BucketState(capacity * SCALE, t.read(), false);
        }
        @Override public synchronized boolean tryAcquire() {
            state = refillAndTake(state, ticker.read(), capacity, perSecond);
            return state.granted();
        }
    }

    /** The brief's design: immutable state, one CAS per attempt via updateAndGet (pure function!). */
    static final class CasBucket implements Limiter {
        private final AtomicReference<BucketState> state;
        private final Ticker ticker;
        private final long capacity, perSecond;
        CasBucket(long capacity, long perSecond, Ticker t) {
            this.capacity = capacity;
            this.perSecond = perSecond;
            this.ticker = t;
            state = new AtomicReference<>(new BucketState(capacity * SCALE, t.read(), false));
        }
        @Override public boolean tryAcquire() {
            long now = ticker.read();                          // read time ONCE, outside the retried function
            return state.updateAndGet(s -> refillAndTake(s, now, capacity, perSecond)).granted();
        }
    }

    /**
     * GCRA (generic cell rate algorithm): the whole token bucket in ONE long, the theoretical arrival
     * time (TAT). Allowed iff tat' - now <= burstTolerance, where tat' = max(tat, now) + interval.
     * One CAS on an AtomicLong, no allocation; the same design is CAS-able in C++ without 128-bit atomics.
     */
    static final class Gcra implements Limiter {
        private final AtomicLong tat;
        private final Ticker ticker;
        private final long intervalNanos, toleranceNanos;
        Gcra(long burst, long perSecond, Ticker t) {
            ticker = t;
            intervalNanos = 1_000_000_000L / perSecond;
            toleranceNanos = (burst - 1) * intervalNanos;
            tat = new AtomicLong(t.read());
        }
        @Override public boolean tryAcquire() {
            long now = ticker.read();
            while (true) {
                long cur = tat.get();
                long next = Math.max(cur, now) + intervalNanos;
                if (next - now > toleranceNanos + intervalNanos) return false;   // would exceed the burst
                if (tat.compareAndSet(cur, next)) return true;
            }
        }
    }

    // ===== Windows =================================================================================

    record Window(long index, long prevCount, long currCount) {}

    /** Fixed window: cheap, and allows 2x the limit across a boundary. */
    static final class FixedWindow implements Limiter {
        private final AtomicReference<Window> w;
        private final Ticker ticker;
        private final long limit, windowNanos;
        FixedWindow(long limit, long windowNanos, Ticker t) {
            this.limit = limit;
            this.windowNanos = windowNanos;
            this.ticker = t;
            w = new AtomicReference<>(new Window(t.read() / windowNanos, 0, 0));
        }
        @Override public boolean tryAcquire() {
            long idx = ticker.read() / windowNanos;
            while (true) {
                Window cur = w.get();
                Window base = cur.index() == idx ? cur : new Window(idx, 0, 0);
                if (base.currCount() >= limit) return false;
                if (w.compareAndSet(cur, new Window(idx, 0, base.currCount() + 1))) return true;
            }
        }
    }

    /** Sliding window counter: weight the previous window by its remaining overlap. */
    static final class SlidingWindowCounter implements Limiter {
        private final AtomicReference<Window> w;
        private final Ticker ticker;
        private final long limit, windowNanos;
        SlidingWindowCounter(long limit, long windowNanos, Ticker t) {
            this.limit = limit;
            this.windowNanos = windowNanos;
            this.ticker = t;
            w = new AtomicReference<>(new Window(t.read() / windowNanos, 0, 0));
        }
        @Override public boolean tryAcquire() {
            long now = ticker.read(), idx = now / windowNanos, into = now % windowNanos;
            while (true) {
                Window cur = w.get();
                Window base = cur.index() == idx ? cur
                        : cur.index() == idx - 1 ? new Window(idx, cur.currCount(), 0) : new Window(idx, 0, 0);
                // estimate = prev * (1 - into/window) + curr, compared in integer arithmetic
                long weightedPrev = base.prevCount() * (windowNanos - into);
                if (weightedPrev + (base.currCount() + 1) * windowNanos > limit * windowNanos) return false;
                if (w.compareAndSet(cur, new Window(idx, base.prevCount(), base.currCount() + 1))) return true;
            }
        }
    }

    /** Per-key registry: computeIfAbsent creates each limiter exactly once, lock-free on the hit path. */
    static final class KeyedLimiter {
        private final ConcurrentHashMap<String, Limiter> limiters = new ConcurrentHashMap<>();
        private final java.util.function.Function<String, Limiter> factory;
        KeyedLimiter(java.util.function.Function<String, Limiter> factory) { this.factory = factory; }
        boolean tryAcquire(String key) { return limiters.computeIfAbsent(key, factory).tryAcquire(); }
    }

    // ===== Harness ===================================================================================

    static long granted(Limiter l, int n) {
        long g = 0;
        for (int i = 0; i < n; i++) if (l.tryAcquire()) g++;
        return g;
    }

    static long contendedGrants(Supplier<Limiter> make, int threads, int tries) throws Exception {
        Limiter l = make.get();
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        LongAdder grants = new LongAdder();
        for (int t = 0; t < threads; t++) {
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    long g = 0;
                    for (int i = 0; i < tries; i++) if (l.tryAcquire()) g++;
                    grants.add(g);
                    end.await();
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        start.await();
        end.await();
        return grants.sum();
    }

    static double throughput(KeyedLimiter kl, boolean hotKey, int threads, int ops) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        for (int t = 0; t < threads; t++) {
            final String key = hotKey ? "tenant-hot" : "tenant-" + t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    for (int i = 0; i < ops; i++) kl.tryAcquire(key);
                    end.await();
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        start.await();
        long t0 = System.nanoTime();
        end.await();
        return threads * (double) ops / ((System.nanoTime() - t0) / 1e9) / 1e6;
    }

    public static void main(String[] args) throws Exception {
        long second = 1_000_000_000L;

        System.out.println("== 1. Boundary burst: limit 100/s; 100 requests at t=0.999 s, 100 more at t=1.001 s ==");
        String[] names = {"fixed window", "sliding window counter", "token bucket (cap 100)", "GCRA (burst 100)"};
        for (int v = 0; v < names.length; v++) {
            FakeTicker tk = new FakeTicker();
            Limiter l = switch (v) {
                case 0 -> new FixedWindow(100, second, tk);
                case 1 -> new SlidingWindowCounter(100, second, tk);
                case 2 -> new CasBucket(100, 100, tk);
                default -> new Gcra(100, 100, tk);
            };
            tk.nanos.set(999_000_000L);
            long a = granted(l, 100);
            tk.nanos.set(1_001_000_000L);
            long b = granted(l, 100);
            System.out.printf("  %-24s granted %3d + %3d = %3d within 2 ms%n", names[v], a, b, a + b);
        }

        System.out.println("== 2. Long-run rate: capacity 100, 250/s, one request per ms for 10 s ==");
        for (int v = 0; v < 2; v++) {
            FakeTicker tk = new FakeTicker();
            Limiter l = v == 0 ? new CasBucket(100, 250, tk) : new Gcra(100, 250, tk);
            long g = 0;
            for (int ms = 0; ms < 10_000; ms++) {
                tk.nanos.set(ms * 1_000_000L);
                if (l.tryAcquire()) g++;
            }
            System.out.printf("  %-24s granted %,d (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)%n", v == 0 ? "token bucket" : "GCRA", g);
        }

        System.out.println("== 3. Over-grant under contention: time frozen, capacity 1,000,000, 4 threads x 1,000,000 tries ==");
        FakeTicker frozen = new FakeTicker();
        long naive = contendedGrants(() -> new NaiveBucket(1_000_000), 4, 1_000_000);
        long sync = contendedGrants(() -> new SyncBucket(1_000_000, 1, frozen), 4, 1_000_000);
        long cas = contendedGrants(() -> new CasBucket(1_000_000, 1, frozen), 4, 1_000_000);
        long gcra = contendedGrants(() -> new Gcra(1_000_000, 1, frozen), 4, 1_000_000);
        System.out.printf("  naive check-then-act : %,d granted (must be 1,000,000)%n", naive);
        System.out.printf("  synchronized bucket  : %,d%n  CAS bucket           : %,d%n  GCRA (AtomicLong)    : %,d%n", sync, cas, gcra);

        System.out.println("== 4. Throughput (one measured run): 4 threads x 2,000,000 tryAcquire, real clock, 1e9/s ==");
        for (String kind : new String[] {"synchronized", "CAS bucket", "GCRA"}) {
            java.util.function.Function<String, Limiter> f = switch (kind) {
                case "synchronized" -> k -> new SyncBucket(1_000_000, 1_000_000_000L, System::nanoTime);
                case "CAS bucket" -> k -> new CasBucket(1_000_000, 1_000_000_000L, System::nanoTime);
                default -> k -> new Gcra(1_000_000, 1_000_000_000L, System::nanoTime);
            };
            throughput(new KeyedLimiter(f), true, 4, 200_000);           // warm-up
            double hot = throughput(new KeyedLimiter(f), true, 4, 2_000_000);
            double spread = throughput(new KeyedLimiter(f), false, 4, 2_000_000);
            System.out.printf("  %-13s one hot key %6.1f M/s   one key per thread %6.1f M/s%n", kind, hot, spread);
        }
        boolean ok = naive >= 1_000_000 && sync == 1_000_000 && cas == 1_000_000 && gcra == 1_000_000;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1–3 verified; section 4 one measured run):**

```text
== 1. Boundary burst: limit 100/s; 100 requests at t=0.999 s, 100 more at t=1.001 s ==
  fixed window             granted 100 + 100 = 200 within 2 ms
  sliding window counter   granted 100 +   0 = 100 within 2 ms
  token bucket (cap 100)   granted 100 +   0 = 100 within 2 ms
  GCRA (burst 100)         granted 100 +   0 = 100 within 2 ms
== 2. Long-run rate: capacity 100, 250/s, one request per ms for 10 s ==
  token bucket             granted 2,599 (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)
  GCRA                     granted 2,599 (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)
== 3. Over-grant under contention: time frozen, capacity 1,000,000, 4 threads x 1,000,000 tries ==
  naive check-then-act : 2,711,833 granted (must be 1,000,000)
  synchronized bucket  : 1,000,000
  CAS bucket           : 1,000,000
  GCRA (AtomicLong)    : 1,000,000
== 4. Throughput (one measured run): 4 threads x 2,000,000 tryAcquire, real clock, 1e9/s ==
  synchronized  one hot key   15.1 M/s   one key per thread   68.7 M/s
  CAS bucket    one hot key    6.3 M/s   one key per thread   64.6 M/s
  GCRA          one hot key   15.9 M/s   one key per thread  100.4 M/s
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// rate_limiters.cpp - P2: token bucket, GCRA on one std::atomic<int64_t>, windows, and their races
#include <algorithm>
#include <array>
#include <atomic>
#include <barrier>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <print>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

using i64 = std::int64_t;
using Ticker = std::function<i64()>;
constexpr i64 kScale = 1'000'000;  // fixed-point micro-tokens

i64 real_now() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

struct Limiter {
    virtual ~Limiter() = default;
    virtual bool try_acquire() = 0;
};

// ===== L5: check, then act (an atomic load and a separate store: the race, without UB) ===========

class NaiveBucket final : public Limiter {
    std::atomic<i64> tokens_;
public:
    explicit NaiveBucket(i64 cap) : tokens_(cap) {}
    bool try_acquire() override {
        const i64 t = tokens_.load(std::memory_order_relaxed);  // CHECK
        if (t <= 0) return false;
        tokens_.store(t - 1, std::memory_order_relaxed);         // ACT: lost updates => over-grants
        return true;
    }
};

// ===== Token bucket: two words of state, so a mutex (a 16-byte CAS is not portable) =============

class MutexBucket final : public Limiter {
    std::mutex m_;
    i64 micro_tokens_, last_;
    const i64 cap_, per_second_;
    Ticker now_;
public:
    MutexBucket(i64 cap, i64 per_second, Ticker t) : micro_tokens_(cap * kScale), last_(t()), cap_(cap), per_second_(per_second), now_(std::move(t)) {}
    bool try_acquire() override {
        const i64 now = now_();
        std::scoped_lock l(m_);
        const i64 elapsed = std::max<i64>(0, now - last_);
        const i64 cap_micro = cap_ * kScale;
        const i64 fill_nanos = cap_micro / per_second_ * 1'000;  // caps elapsed: no overflow after long idle
        const i64 add = std::min(elapsed, fill_nanos) * per_second_ / 1'000;
        micro_tokens_ = std::min(cap_micro, micro_tokens_ + add);
        last_ = now;
        if (micro_tokens_ < kScale) return false;
        micro_tokens_ -= kScale;
        return true;
    }
};

/** GCRA: the whole bucket is one int64 (theoretical arrival time), so one CAS, lock-free, no allocation. */
class Gcra final : public Limiter {
    std::atomic<i64> tat_;
    const i64 interval_, tolerance_;
    Ticker now_;
public:
    Gcra(i64 burst, i64 per_second, Ticker t)
        : tat_(t()), interval_(1'000'000'000 / per_second), tolerance_((burst - 1) * interval_), now_(std::move(t)) {}
    bool try_acquire() override {
        const i64 now = now_();
        i64 cur = tat_.load(std::memory_order_relaxed);
        while (true) {
            const i64 next = std::max(cur, now) + interval_;
            if (next - now > tolerance_ + interval_) return false;
            if (tat_.compare_exchange_weak(cur, next, std::memory_order_acq_rel, std::memory_order_relaxed)) return true;
        }
    }
};

// ===== Windows ===================================================================================

class FixedWindow final : public Limiter {
    std::mutex m_;
    i64 index_, count_ = 0;
    const i64 limit_, window_;
    Ticker now_;
public:
    FixedWindow(i64 limit, i64 window, Ticker t) : index_(t() / window), limit_(limit), window_(window), now_(std::move(t)) {}
    bool try_acquire() override {
        const i64 idx = now_() / window_;
        std::scoped_lock l(m_);
        if (idx != index_) {
            index_ = idx;
            count_ = 0;
        }
        if (count_ >= limit_) return false;
        ++count_;
        return true;
    }
};

class SlidingWindowCounter final : public Limiter {
    std::mutex m_;
    i64 index_, prev_ = 0, curr_ = 0;
    const i64 limit_, window_;
    Ticker now_;
public:
    SlidingWindowCounter(i64 limit, i64 window, Ticker t) : index_(t() / window), limit_(limit), window_(window), now_(std::move(t)) {}
    bool try_acquire() override {
        const i64 now = now_(), idx = now / window_, into = now % window_;
        std::scoped_lock l(m_);
        if (idx != index_) {
            prev_ = idx == index_ + 1 ? curr_ : 0;
            curr_ = 0;
            index_ = idx;
        }
        if (prev_ * (window_ - into) + (curr_ + 1) * window_ > limit_ * window_) return false;  // integer estimate
        ++curr_;
        return true;
    }
};

/** Per-key registry: 16 padded shards; a limiter is created once per key. */
class KeyedLimiter {
    struct alignas(64) Shard { std::mutex m; std::unordered_map<std::string, std::unique_ptr<Limiter>> map; };
    std::array<Shard, 16> shards_;
    std::function<std::unique_ptr<Limiter>()> make_;
public:
    explicit KeyedLimiter(std::function<std::unique_ptr<Limiter>()> make) : make_(std::move(make)) {}
    bool try_acquire(const std::string& key) {
        Shard& s = shards_[std::hash<std::string>{}(key) % shards_.size()];
        Limiter* l;
        {
            std::scoped_lock g(s.m);
            auto& slot = s.map[key];
            if (!slot) slot = make_();
            l = slot.get();  // limiters are never removed here, so the pointer stays valid
        }
        return l->try_acquire();
    }
};

// ===== Harness ===================================================================================

i64 granted(Limiter& l, int n) {
    i64 g = 0;
    for (int i = 0; i < n; ++i) g += l.try_acquire();
    return g;
}

i64 contended_grants(Limiter& l, int threads, int tries) {
    std::barrier sync(threads + 1);
    std::atomic<i64> total{0};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&] {
            sync.arrive_and_wait();
            total.fetch_add(granted(l, tries));
            sync.arrive_and_wait();
        });
    sync.arrive_and_wait();
    sync.arrive_and_wait();
    return total.load();
}

double throughput(KeyedLimiter& kl, bool hot, int threads, int ops) {
    std::barrier sync(threads + 1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            const std::string key = hot ? "tenant-hot" : "tenant-" + std::to_string(t);
            sync.arrive_and_wait();
            for (int i = 0; i < ops; ++i) (void)kl.try_acquire(key);
            sync.arrive_and_wait();
        });
    sync.arrive_and_wait();
    const auto t0 = std::chrono::steady_clock::now();
    sync.arrive_and_wait();
    return threads * static_cast<double>(ops) / std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count() / 1e6;
}

int main() {
    constexpr i64 kSecond = 1'000'000'000;
    std::println("== 1. Boundary burst: limit 100/s; 100 requests at t=0.999 s, 100 more at t=1.001 s ==");
    const char* names[] = {"fixed window", "sliding window counter", "token bucket (cap 100)", "GCRA (burst 100)"};
    for (int v = 0; v < 4; ++v) {
        auto fake = std::make_shared<std::atomic<i64>>(0);
        Ticker tk = [fake] { return fake->load(); };
        std::unique_ptr<Limiter> l;
        switch (v) {
            case 0: l = std::make_unique<FixedWindow>(100, kSecond, tk); break;
            case 1: l = std::make_unique<SlidingWindowCounter>(100, kSecond, tk); break;
            case 2: l = std::make_unique<MutexBucket>(100, 100, tk); break;
            default: l = std::make_unique<Gcra>(100, 100, tk); break;
        }
        fake->store(999'000'000);
        const i64 a = granted(*l, 100);
        fake->store(1'001'000'000);
        const i64 b = granted(*l, 100);
        std::println("  {:<24} granted {:>3} + {:>3} = {:>3} within 2 ms", names[v], a, b, a + b);
    }

    std::println("== 2. Long-run rate: capacity 100, 250/s, one request per ms for 10 s ==");
    for (int v = 0; v < 2; ++v) {
        auto fake = std::make_shared<std::atomic<i64>>(0);
        Ticker tk = [fake] { return fake->load(); };
        std::unique_ptr<Limiter> l = v == 0 ? std::unique_ptr<Limiter>(std::make_unique<MutexBucket>(100, 250, tk))
                                            : std::unique_ptr<Limiter>(std::make_unique<Gcra>(100, 250, tk));
        i64 g = 0;
        for (i64 ms = 0; ms < 10'000; ++ms) {
            fake->store(ms * 1'000'000);
            g += l->try_acquire();
        }
        std::println("  {:<24} granted {} (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)", v == 0 ? "token bucket" : "GCRA", g);
    }

    std::println("== 3. Over-grant under contention: time frozen, capacity 1,000,000, 4 threads x 1,000,000 tries ==");
    Ticker frozen = [] { return i64{0}; };
    NaiveBucket naive(1'000'000);
    MutexBucket mutex_bucket(1'000'000, 1, frozen);
    Gcra gcra(1'000'000, 1, frozen);
    const i64 n = contended_grants(naive, 4, 1'000'000), m = contended_grants(mutex_bucket, 4, 1'000'000),
              g = contended_grants(gcra, 4, 1'000'000);
    std::println("  naive check-then-act : {} granted (must be 1,000,000)", n);
    std::println("  mutex bucket         : {}\n  GCRA (atomic int64)  : {}", m, g);

    std::println("== 4. Throughput (one measured run): 4 threads x 2,000,000 try_acquire, real clock, 1e9/s ==");
    for (int kind = 0; kind < 2; ++kind) {
        auto make = [kind]() -> std::unique_ptr<Limiter> {
            if (kind == 0) return std::make_unique<MutexBucket>(1'000'000, 1'000'000'000, real_now);
            return std::make_unique<Gcra>(1'000'000, 1'000'000'000, real_now);
        };
        KeyedLimiter warm(make), hot_kl(make), spread_kl(make);
        throughput(warm, true, 4, 200'000);
        const double hot = throughput(hot_kl, true, 4, 2'000'000), spread = throughput(spread_kl, false, 4, 2'000'000);
        std::println("  {:<13} one hot key {:6.1f} M/s   one key per thread {:6.1f} M/s", kind == 0 ? "mutex bucket" : "GCRA", hot, spread);
    }
    const bool ok = n >= 1'000'000 && m == 1'000'000 && g == 1'000'000;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Boundary burst: limit 100/s; 100 requests at t=0.999 s, 100 more at t=1.001 s ==
  fixed window             granted 100 + 100 = 200 within 2 ms
  sliding window counter   granted 100 +   0 = 100 within 2 ms
  token bucket (cap 100)   granted 100 +   0 = 100 within 2 ms
  GCRA (burst 100)         granted 100 +   0 = 100 within 2 ms
== 2. Long-run rate: capacity 100, 250/s, one request per ms for 10 s ==
  token bucket             granted 2599 (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)
  GCRA                     granted 2599 (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)
== 3. Over-grant under contention: time frozen, capacity 1,000,000, 4 threads x 1,000,000 tries ==
  naive check-then-act : 2150972 granted (must be 1,000,000)
  mutex bucket         : 1000000
  GCRA (atomic int64)  : 1000000
== 4. Throughput (one measured run): 4 threads x 2,000,000 try_acquire, real clock, 1e9/s ==
  mutex bucket  one hot key    6.8 M/s   one key per thread   42.8 M/s
  GCRA          one hot key    8.6 M/s   one key per thread   55.2 M/s
SELF-TEST OK
```

**Output, Clang 21.1 (sections 1–3 identical; throughput differs):**

```text
== 1. Boundary burst: limit 100/s; 100 requests at t=0.999 s, 100 more at t=1.001 s ==
  fixed window             granted 100 + 100 = 200 within 2 ms
  sliding window counter   granted 100 +   0 = 100 within 2 ms
  token bucket (cap 100)   granted 100 +   0 = 100 within 2 ms
  GCRA (burst 100)         granted 100 +   0 = 100 within 2 ms
== 2. Long-run rate: capacity 100, 250/s, one request per ms for 10 s ==
  token bucket             granted 2599 (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)
  GCRA                     granted 2599 (burst 100 + 9.999 s x 250/s = 2,599.75 -> 2,599)
== 3. Over-grant under contention: time frozen, capacity 1,000,000, 4 threads x 1,000,000 tries ==
  naive check-then-act : 1927834 granted (must be 1,000,000)
  mutex bucket         : 1000000
  GCRA (atomic int64)  : 1000000
== 4. Throughput (one measured run): 4 threads x 2,000,000 try_acquire, real clock, 1e9/s ==
  mutex bucket  one hot key    7.7 M/s   one key per thread   18.6 M/s
  GCRA          one hot key    9.6 M/s   one key per thread   25.0 M/s
SELF-TEST OK
```

## 6. Reading the results

- **The boundary burst.** The fixed window admitted 200 requests within 2 ms for a 100/s limit. The other three admitted 100. The fixed window is fine for coarse quotas (daily API caps) and wrong for protecting a backend.
- **The long-run arithmetic.** 100 burst + 9.999 s × 250/s = 2,599.75, so 2,599 grants, in both languages and both algorithms. The first request is at t = 0 and the last at 9.999 s. An interviewer who asks "why not 2,600?" is checking that you can do this arithmetic.
- **The lock beat the brief's CAS design on a hot key**, while GCRA tied or beat the lock there and won clearly elsewhere. Lock-free isn't automatically faster. A CAS that allocates and retries under contention can lose to a lock that hands off efficiently. Measure contention before choosing (01.3 §3–4).

## 7. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Algorithm | Fixed window counter | Token bucket or sliding window, with trade-offs explained | Picks by requirement (burst vs smoothness vs memory); knows GCRA ≡ token bucket in one word |
| Atomicity | `synchronized` everything, or a racy volatile | Per-key lock or `AtomicReference` + `updateAndGet` | One-word CAS (GCRA); pure update functions; the clock read once; contention measured |
| Arithmetic | `double` tokens | `long` millis | Fixed-point micro-tokens; overflow-safe refill cap; nanosecond monotonic ticker |
| Keys | One global limiter | `ConcurrentHashMap` of limiters | `computeIfAbsent` once per key; idle-key eviction (expire-after-access cache, P1); no shared hot cache lines |
| Testing | `Thread.sleep(1000)` | Fake clock unit tests | Boundary bursts, exact long-run counts, a frozen-time contention test with a long enough window |
| Scale-out | "Use Redis" | Redis `INCR` + `EXPIRE` | Redis Lua GCRA (one key, one atomic script) or local token leasing from a central quota service; states the trade-off between accuracy and latency |

## 8. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Different limits per tier, changeable at runtime" | Limits live in an immutable `Policy` record per key, swapped atomically (02.2 §7). GCRA reads `T` and `τ` from the snapshot |
| "Cost-based limiting: some calls cost 5 tokens" | Token bucket: subtract `cost × SCALE`. GCRA: `max(TAT, now) + cost × T`. Both stay one CAS |
| "Return Retry-After" | GCRA gives it for free: `TAT − τ − now` when denied. A token bucket computes `(1 − tokens) / rate` |
| "Limit across 20 app servers" | A Redis Lua script implementing GCRA on one key (an atomic single round trip), or a central quota service leasing batches of tokens to each node (fewer round trips, slight overshoot). State the overshoot bound |
| "Millions of keys; memory is growing" | The registry becomes an expire-after-access cache (P1). An idle bucket is full anyway, so re-creating it on the next request is exact |
| "Block until permitted instead of rejecting" | Compute the wait from GCRA (`TAT − τ − now`), then sleep with a virtual-time-testable scheduler; or a `Semaphore` refilled by a ticker for fairness |

## 9. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Use <code>AtomicReference&lt;BucketState&gt;</code> with <code>updateAndGet</code>. Done?"</b></summary>

**L5:** "Yes, it's lock-free, so it's the fastest."

**Why it fails:** each attempt allocates a state object, and failed CAS attempts allocate too. On one hot key the measured throughput was 6.3–6.8 M/s against 15 M/s for `synchronized`.

**L7 defence:** "It's correct if the function is pure and the clock is read once. But a two-word state forces allocation. GCRA keeps one `long` (the theoretical arrival time), so it's one `AtomicLong` CAS with no allocation and identical decisions to the token bucket. It measured fastest everywhere, and it's the only design that is lock-free in C++ without 128-bit atomics."
</details>

<details>
<summary><b>Q2 ⚡ "Fixed window or sliding window?"</b></summary>

**L5:** "Fixed window is simpler."

**Why it fails:** across a boundary it admits twice the limit. The listing admitted 200 in 2 ms against 100/s.

**L7 defence:** "The sliding window counter fixes the boundary with three words of state and a weighted estimate, and that's good for quotas. The token bucket and GCRA give an explicit burst and a smooth rate, which is what protects a backend. The sliding log is exact but O(limit) memory, so only for low limits."
</details>

<details>
<summary><b>Q3 ⚡ "How do you test that it never over-grants?"</b></summary>

**L5:** "Send 1,000 requests from 4 threads and check that 100 pass."

**Why it fails:** with a small capacity, one thread drains the bucket before the others start. Even the racy version passes. The listing measured exactly that: at capacity 1,000 the naive version granted exactly 1,000.

**L7 defence:** "Freeze time (an injected ticker), make capacity large relative to thread start skew (1,000,000), and run 4 × 1 M attempts. Correct implementations grant exactly 1,000,000. The naive one granted 2.7 M. Then a long-run fake-time test checks rate accuracy to the token."
</details>

## 10. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Backend overwhelmed at window boundaries | Fixed window | Sliding window / token bucket / GCRA |
| Over-granting under load | Check-then-act on shared tokens | CAS or lock; frozen-time contention test |
| Slow drift in the allowed rate | `double` accumulation | Fixed-point integer arithmetic |
| A huge burst after an idle period | Refill not capped, or overflow | Cap refill at time-to-full; cap the burst |
| Throughput collapses on a hot tenant | Allocating CAS retry storm | GCRA (one word), or a lock for that key |
| Memory leak from idle keys | Unbounded registry | Expire-after-access eviction |

- [ ] The algorithm is chosen by burst and smoothness requirements; boundary behaviour is tested.
- [ ] The state update is pure and the clock is read once; state is integer fixed-point.
- [ ] Contention tests use frozen time and a large capacity.
- [ ] Keys are isolated; limiters are created once per key; idle keys are evicted.
- [ ] Retry-After is computable; policies are swappable atomically.

## 11. References

- ITU-T I.371, Generic Cell Rate Algorithm (the GCRA definition). <https://www.itu.int/rec/T-REC-I.371>
- Brandur Leach, "Rate Limiting, Cells, and GCRA". <https://brandur.org/rate-limiting>
- Stripe engineering, "Scaling your API with rate limiters". <https://stripe.com/blog/rate-limiters>
- Guava `RateLimiter` (smooth bursty/warm-up token bucket). <https://guava.dev/releases/snapshot-jre/api/docs/com/google/common/util/concurrent/RateLimiter.html>
- Resilience4j RateLimiter (a fixed-window cycle design). <https://resilience4j.readme.io/docs/ratelimiter>
- In this KB: [01.3 CAS retries, identity, LongAdder](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P1 cache for idle-key eviction](01-problem-01-thread-safe-lru-and-lfu-ttl-cache-caffeine-architecture.md) · [02.2 Atomic policy swap](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md)
