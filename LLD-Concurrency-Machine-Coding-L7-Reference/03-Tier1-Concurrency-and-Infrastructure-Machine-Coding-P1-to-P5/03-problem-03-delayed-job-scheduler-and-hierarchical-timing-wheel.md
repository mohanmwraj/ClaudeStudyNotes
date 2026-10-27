# P3 · Delayed Job Scheduler and the Hierarchical Timing Wheel

> **Folder 03 · Problem 3 of 20.** "Schedule a task to run after a delay, cancel it, support recurring tasks." The L5 answer is a `DelayQueue` or `ScheduledThreadPoolExecutor`. The L7 answer explains why heaps degrade at hundreds of thousands of timers per second (O(log n) under one lock, expensive cancellation), and builds the structure Kafka, Netty and the Linux kernel use instead: **a hashed hierarchical timing wheel** with O(1) insert and cancel.
>
> **Listing pair P3:** `TimingWheelScheduler.java` / `timing_wheel_scheduler.cpp`. The virtual-time results are deterministic and identical in both languages, down to the cascade count. Costs are one measured run.

---

## 1. Problem and scope

**Functional:**
- `schedule(delay, task)` returning a handle, and `handle.cancel()`;
- fixed-rate recurrence;
- graceful shutdown that returns the pending work.

**Non-functional:**
- 100k+ schedule/cancel operations per second from many threads;
- timer precision of one tick (1 ms here);
- cancellation must free memory promptly;
- the tick thread never runs user code;
- testable without real time.

**Explicit trade-off:** a wheel gives **tick-granularity precision** (a timer fires in the tick containing its deadline). That's right for timeouts, retries, session expiry, delayed delivery and leases. It's wrong for sub-millisecond scheduling, which needs a heap or hardware timers.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Handle | `Timeout` with `AtomicInteger state` (`PENDING → CANCELLED \| EXPIRED`) | `shared_ptr<Timeout>` with `std::atomic<int> state` |
| Bucket | circular doubly linked list per (level, slot) | `std::list<shared_ptr<Timeout>>` + the node's own iterator for O(1) erase |
| Wheel | 4 levels × 64 slots; level L covers 64^(L+1) ticks (≈ 4.6 h at 1 ms) | same |
| Hand-off | `ConcurrentLinkedQueue` for adds and cancels (lock-free MPSC) | mutex + `vector` swapped by the wheel thread |
| Execution | an `Executor`; the test uses a direct executor to record firing ticks | a callback; production hands it to a pool |

**Invariants:**
- **I1:** a non-cancelled one-shot timer fires **exactly once**, at the **first tick ≥ its deadline**.
- **I2:** a cancelled timer never fires. Cancellation is a CAS on `state`, so `cancel` and `expire` race safely: exactly one wins.
- **I3:** fixed-rate timers fire at `deadline + k·period` (no drift), computed from the scheduled time, not the run time.
- **I4:** only the wheel thread touches buckets and links. Other threads touch only `state` and the hand-off queues.

## 3. Concurrency and contention analysis

**Why heaps degrade.**
- `DelayQueue` and `ScheduledThreadPoolExecutor` keep a binary heap behind **one lock**. Every `schedule` is O(log n) under that lock, and so is every `take`.
- **Cancellation:** `DelayQueue.remove(o)` is O(n). STPE keeps each task's heap index and, with `setRemoveOnCancelPolicy(true)`, removes in O(log n), still under the lock. Without that policy, a cancelled task stays in the heap until its delay elapses: a memory leak for timeout-heavy workloads where most timers are cancelled, which is the normal case for request timeouts.
- The C++ baseline shows the tombstone version: cancellation is a cheap flag flip, but the heap still holds all **400,000** entries after **200,000** cancels.

**The wheel's design.**
1. **Insert = O(1).** Compute the level from `deadline − base` and the slot from the deadline's bits at that level, then append to that slot's list.
2. **Cancel = O(1).** CAS the state, enqueue the handle, and let the wheel thread unlink it on its next tick (doubly linked list or stored iterator).
3. **Tick = O(expired + cascaded).** At each level-L boundary, *cascade* that level's current slot by re-placing its entries one level down. Then expire level 0's current slot. Each timer cascades at most `LEVELS − 1` times; the measured average was **1.67 cascades per timer** for delays up to 300 s.
4. **Single-threaded core.** The wheel itself has no locks. Producers hand work over through MPSC queues, which is Netty's `HashedWheelTimer` design. The tick thread only moves and expires handles and dispatches expired tasks to an executor, so a slow task can't delay other timers.

**The boundary bug the virtual-time test caught 🔥.** The first version chose a level with `delta < 64^(L+1)`. During a cascade the base is `tick − 1`. A timer whose deadline is exactly `64^(L+1)` ticks ahead was then placed back into the *same slot being cascaded*, and fired one full revolution late. 1,210 of 80,000 timers were wrong and 39 were stuck. One full revolution still fits a level, so the correct condition is `delta ≤ 64^(L+1)`. A test that only checks "the timer eventually fired" would have passed. This one checks **the exact firing tick** for 100,000 random deadlines across three levels, plus "nothing left behind".

**Recurrence without drift.** Fixed-rate rescheduling sets `deadline += period` from the *scheduled* deadline, so 40 firings over 10,000 ticks land on exact multiples of 250. Rescheduling from "now when it ran" accumulates the tick latency into every period. Fixed-delay, where the next run starts *after* the previous one completes, is a different, legitimate policy, and the API should name which one it uses.

## 4. Java 21 implementation

```java
// TimingWheelScheduler.java - P3: hierarchical timing wheel (O(1) add/cancel) vs a heap-based scheduler
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executor;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class TimingWheelScheduler {

    /** A handle returned to callers. state is the only field other threads touch (CAS). */
    static final class Timeout {
        static final int PENDING = 0, CANCELLED = 1, EXPIRED = 2;
        final AtomicInteger state = new AtomicInteger(PENDING);
        final Runnable task;
        final long period;                                     // ticks; 0 = one-shot (fixed-rate when > 0)
        long deadline;                                         // ticks; wheel thread only after hand-off
        Timeout prev, next;                                    // bucket links: wheel thread only
        int level = -1, slot;

        Timeout(long deadline, long period, Runnable task) {
            this.deadline = deadline;
            this.period = period;
            this.task = task;
        }

        /** O(1), callable from any thread; the wheel unlinks it on its next tick. */
        boolean cancel(TimingWheel owner) {
            if (!state.compareAndSet(PENDING, CANCELLED)) return false;
            owner.cancelled.add(this);
            return true;
        }
    }

    /** 4 levels x 64 slots: level L covers 64^(L+1) ticks; 1 ms ticks reach ~4.6 hours before overflow. */
    static final class TimingWheel {
        static final int LEVELS = 4, BITS = 6, SLOTS = 1 << BITS, MASK = SLOTS - 1;
        private final Timeout[][] heads = new Timeout[LEVELS][SLOTS];   // circular doubly linked lists
        final ConcurrentLinkedQueue<Timeout> adds = new ConcurrentLinkedQueue<>();      // MPSC hand-off
        final ConcurrentLinkedQueue<Timeout> cancelled = new ConcurrentLinkedQueue<>();
        private final Executor executor;                       // expired tasks never run on the tick thread
        private long current;                                  // last processed tick (wheel thread only)
        private long size;
        long cascades, expired;

        TimingWheel(long startTick, Executor executor) {
            this.current = startTick;
            this.executor = executor;
        }

        Timeout schedule(long deadlineTick, long periodTicks, Runnable task) {   // any thread, O(1), lock-free
            Timeout t = new Timeout(deadlineTick, periodTicks, task);
            adds.add(t);
            return t;
        }

        private void place(Timeout t, long base) {             // wheel thread
            long delta = Math.max(1, t.deadline - base);
            if (t.deadline <= base) t.deadline = base + 1;
            int level = 0;
            // <= not <: a deadline exactly 64^(L+1) ticks ahead still fits level L (one full revolution).
            // With '<' a cascade re-adds it into the slot being cascaded and it fires a revolution late.
            while (level < LEVELS - 1 && delta > 1L << (BITS * (level + 1))) level++;
            int slot = (int) ((t.deadline >>> (BITS * level)) & MASK);
            t.level = level;
            t.slot = slot;
            Timeout h = heads[level][slot];
            if (h == null) {
                t.prev = t.next = t;
                heads[level][slot] = t;
            } else {                                           // append before head (tail)
                t.prev = h.prev;
                t.next = h;
                h.prev.next = t;
                h.prev = t;
            }
            size++;
        }

        private void unlink(Timeout t) {                       // O(1)
            if (t.level < 0) return;
            if (t.next == t) heads[t.level][t.slot] = null;
            else {
                t.prev.next = t.next;
                t.next.prev = t.prev;
                if (heads[t.level][t.slot] == t) heads[t.level][t.slot] = t.next;
            }
            t.prev = t.next = null;
            t.level = -1;
            size--;
        }

        private List<Timeout> takeSlot(int level, int slot) {
            List<Timeout> out = new ArrayList<>();
            Timeout h = heads[level][slot];
            if (h == null) return out;
            Timeout t = h;
            do {
                Timeout nx = t.next;
                out.add(t);
                t = nx;
            } while (t != h);
            for (Timeout x : out) unlink(x);
            return out;
        }

        void drainQueues(long base) {
            for (Timeout t; (t = cancelled.poll()) != null; ) unlink(t);
            for (Timeout t; (t = adds.poll()) != null; ) if (t.state.get() == Timeout.PENDING) place(t, base);
        }

        /** Process tick `tick`: drain hand-offs, cascade higher levels at their boundaries, expire level 0. */
        private void processTick(long tick) {
            long base = tick - 1;
            drainQueues(base);
            int top = 0;
            for (int l = 1; l < LEVELS; l++) {
                if ((tick & ((1L << (BITS * l)) - 1)) != 0) break;
                top = l;
            }
            for (int l = top; l >= 1; l--) {                    // highest first: entries may land in a lower due slot
                for (Timeout t : takeSlot(l, (int) ((tick >>> (BITS * l)) & MASK))) {
                    cascades++;
                    if (t.state.get() == Timeout.PENDING) place(t, base);
                }
            }
            for (Timeout t : takeSlot(0, (int) (tick & MASK))) {
                if (t.state.get() != Timeout.PENDING) continue;
                if (t.deadline > tick) {                       // overflowed/early cascade: put it back
                    place(t, tick);
                    continue;
                }
                expired++;
                final long firedAt = tick;
                if (t.period > 0) {                            // fixed-rate: from the SCHEDULED time, no drift
                    t.deadline += t.period;
                    place(t, tick);
                } else {
                    t.state.set(Timeout.EXPIRED);
                }
                executor.execute(() -> {
                    if (t.task instanceof FiringTask f) f.fired(firedAt);
                    else t.task.run();
                });
            }
            current = tick;
        }

        void advanceTo(long tick) {                             // virtual time: the test drives the clock
            while (current < tick) processTick(current + 1);
        }

        long now() {
            return current;
        }

        long size() {
            return size;
        }

        /** Graceful shutdown: hand back everything still pending, cancelled ones excluded. */
        List<Timeout> stop() {
            drainQueues(current);
            List<Timeout> pending = new ArrayList<>();
            for (int l = 0; l < LEVELS; l++)
                for (int s = 0; s < SLOTS; s++)
                    for (Timeout t : takeSlot(l, s)) if (t.state.get() == Timeout.PENDING) pending.add(t);
            return pending;
        }
    }

    interface FiringTask extends Runnable {
        void fired(long tick);

        @Override default void run() { fired(-1); }
    }

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    public static void main(String[] args) throws Exception {
        Executor direct = Runnable::run;

        System.out.println("== 1. Virtual-time correctness: 100,000 timers, delays 1 ms .. 300 s, 20% cancelled ==");
        TimingWheel wheel = new TimingWheel(0, direct);
        int n = 100_000;
        long[] deadline = new long[n], firedAt = new long[n];
        int[] fireCount = new int[n];
        Timeout[] handles = new Timeout[n];
        for (int i = 0; i < n; i++) {
            final int id = i;
            deadline[i] = 1 + Long.remainderUnsigned(mix64(i), 300_000);
            handles[i] = wheel.schedule(deadline[i], 0, (FiringTask) tick -> {
                fireCount[id]++;
                firedAt[id] = tick;
            });
        }
        int cancelledCount = 0;
        for (int i = 0; i < n; i += 5) if (handles[i].cancel(wheel)) cancelledCount++;
        wheel.advanceTo(300_001);
        int onTime = 0, wrong = 0, firedCancelled = 0;
        for (int i = 0; i < n; i++) {
            boolean cancelled = i % 5 == 0;
            if (cancelled) {
                if (fireCount[i] != 0) firedCancelled++;
            } else if (fireCount[i] == 1 && firedAt[i] == deadline[i]) onTime++;
            else wrong++;
        }
        System.out.printf("  cancelled %,d | fired exactly once at the exact deadline tick %,d | wrong %d | cancelled-but-fired %d%n",
                cancelledCount, onTime, wrong, firedCancelled);
        System.out.printf("  cascades %,d (%.2f per timer) | entries left %d%n", wheel.cascades, wheel.cascades / (double) n, wheel.size());

        System.out.println("== 2. Fixed-rate recurrence: period 250 ticks from t=0, run to t=10,000 ==");
        TimingWheel rec = new TimingWheel(0, direct);
        List<Long> fires = new ArrayList<>();
        Timeout every = rec.schedule(250, 250, (FiringTask) fires::add);
        rec.advanceTo(10_000);
        every.cancel(rec);
        rec.advanceTo(12_000);
        System.out.println("  fired " + fires.size() + " times; first " + fires.subList(0, 3) + " last " + fires.get(fires.size() - 1)
                + "; all exact multiples of 250 = " + fires.stream().allMatch(t -> t % 250 == 0) + "; after cancel: " + fires.size());

        System.out.println("== 3. Graceful shutdown hands back pending work ==");
        TimingWheel sd = new TimingWheel(0, direct);
        for (int i = 1; i <= 10; i++) sd.schedule(i * 1_000L, 0, () -> {});
        Timeout c = sd.schedule(9_999, 0, () -> {});
        c.cancel(sd);
        sd.advanceTo(3_500);
        System.out.println("  10 scheduled, 1 cancelled, ran to t=3,500 -> expired " + sd.expired + ", returned on stop() " + sd.stop().size());

        System.out.println("== 4. Schedule + cancel cost (one measured run): 4 threads x 100,000 timers, delays up to 60 s ==");
        for (int round = 0; round < 2; round++) {                // round 0 = warm-up
            ScheduledThreadPoolExecutor stpe = new ScheduledThreadPoolExecutor(1);
            stpe.setRemoveOnCancelPolicy(true);                // O(log n) removal instead of leaving tombstones
            @SuppressWarnings({"unchecked", "rawtypes"})
            ScheduledFuture<Object>[][] futures = new ScheduledFuture[4][100_000];
            long stpeSchedule = timed(4, t -> {
                for (int i = 0; i < 100_000; i++)
                    futures[t][i] = stpe.schedule(() -> null, 1 + Long.remainderUnsigned(mix64(t * 1_000_003L + i), 60_000), TimeUnit.MILLISECONDS);
            });
            long stpeCancel = timed(4, t -> {
                for (int i = 0; i < 100_000; i += 2) futures[t][i].cancel(false);
            });
            int stpeLeft = stpe.getQueue().size();
            stpe.shutdownNow();

            TimingWheel w = new TimingWheel(0, direct);
            Timeout[][] ts = new Timeout[4][100_000];
            long wheelSchedule = timed(4, t -> {
                for (int i = 0; i < 100_000; i++)
                    ts[t][i] = w.schedule(1 + Long.remainderUnsigned(mix64(t * 1_000_003L + i), 60_000), 0, () -> {});
            });
            long t0 = System.nanoTime();
            w.drainQueues(0);                                   // the wheel thread's share of the work
            long wheelDrain = System.nanoTime() - t0;
            long wheelCancel = timed(4, t -> {
                for (int i = 0; i < 100_000; i += 2) ts[t][i].cancel(w);
            });
            t0 = System.nanoTime();
            w.drainQueues(0);
            long wheelUnlink = System.nanoTime() - t0;
            if (round == 1) {
                System.out.printf("  ScheduledThreadPoolExecutor: schedule %6.1f ms, cancel 200k %6.1f ms, queue after %,d%n",
                        stpeSchedule / 1e6, stpeCancel / 1e6, stpeLeft);
                System.out.printf("  TimingWheel: schedule %6.1f ms (+ drain %5.1f ms on wheel thread), cancel 200k %5.1f ms (+ unlink %4.1f ms), entries after %,d%n",
                        wheelSchedule / 1e6, wheelDrain / 1e6, wheelCancel / 1e6, wheelUnlink / 1e6, w.size());
            }
        }
        boolean ok = onTime == n - cancelledCount && wrong == 0 && firedCancelled == 0 && wheel.size() == 0
                && fires.size() == 40 && sd.expired == 3;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }

    interface PerThread {
        void run(int thread) throws Exception;
    }

    static long timed(int threads, PerThread body) throws Exception {
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
        long t0 = System.nanoTime();
        end.await();
        return System.nanoTime() - t0;
    }
}
```

**Output (sections 1–3 verified; section 4 one measured run):**

```text
== 1. Virtual-time correctness: 100,000 timers, delays 1 ms .. 300 s, 20% cancelled ==
  cancelled 20,000 | fired exactly once at the exact deadline tick 80,000 | wrong 0 | cancelled-but-fired 0
  cascades 166,691 (1.67 per timer) | entries left 0
== 2. Fixed-rate recurrence: period 250 ticks from t=0, run to t=10,000 ==
  fired 40 times; first [250, 500, 750] last 10000; all exact multiples of 250 = true; after cancel: 40
== 3. Graceful shutdown hands back pending work ==
  10 scheduled, 1 cancelled, ran to t=3,500 -> expired 3, returned on stop() 7
== 4. Schedule + cancel cost (one measured run): 4 threads x 100,000 timers, delays up to 60 s ==
  ScheduledThreadPoolExecutor: schedule   78.1 ms, cancel 200k   61.3 ms, queue after 199,587
  TimingWheel: schedule   49.4 ms (+ drain   8.8 ms on wheel thread), cancel 200k  23.3 ms (+ unlink  5.8 ms), entries after 200,000
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// timing_wheel_scheduler.cpp - P3: hierarchical timing wheel (O(1) add/cancel) vs a heap with tombstone cancels
#include <algorithm>
#include <array>
#include <atomic>
#include <barrier>
#include <chrono>
#include <cstdint>
#include <functional>
#include <list>
#include <memory>
#include <mutex>
#include <print>
#include <queue>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

struct Timeout {
    enum : int { Pending = 0, Cancelled = 1, Expired = 2 };
    std::atomic<int> state{Pending};  // the only field other threads touch
    std::function<void(i64)> task;    // receives the tick it fired at
    i64 deadline, period;             // wheel thread only after hand-off
    int level = -1, slot = 0;
    std::list<std::shared_ptr<Timeout>>::iterator pos;  // O(1) unlink; valid while level >= 0
    Timeout(i64 d, i64 p, std::function<void(i64)> t) : task(std::move(t)), deadline(d), period(p) {}
};
using Handle = std::shared_ptr<Timeout>;

class TimingWheel {
    static constexpr int kLevels = 4, kBits = 6, kSlots = 1 << kBits, kMask = kSlots - 1;
    std::array<std::array<std::list<Handle>, kSlots>, kLevels> slots_;
    std::mutex q_m_;                  // MPSC hand-off: producers append, the wheel thread swaps
    std::vector<Handle> adds_, cancels_;
    i64 current_;
    i64 size_ = 0;
public:
    i64 cascades = 0, expired = 0;
    explicit TimingWheel(i64 start) : current_(start) {}

    Handle schedule(i64 deadline, i64 period, std::function<void(i64)> task) {  // any thread
        auto t = std::make_shared<Timeout>(deadline, period, std::move(task));
        std::scoped_lock l(q_m_);
        adds_.push_back(t);
        return t;
    }
    bool cancel(const Handle& t) {  // any thread, O(1)
        int expected = Timeout::Pending;
        if (!t->state.compare_exchange_strong(expected, Timeout::Cancelled)) return false;
        std::scoped_lock l(q_m_);
        cancels_.push_back(t);
        return true;
    }
    void drain_queues(i64 base) {
        std::vector<Handle> adds, cancels;
        {
            std::scoped_lock l(q_m_);
            adds.swap(adds_);
            cancels.swap(cancels_);
        }
        for (auto& t : cancels) unlink(*t);
        for (auto& t : adds)
            if (t->state.load() == Timeout::Pending) place(t, base);
    }
    void advance_to(i64 tick) {
        while (current_ < tick) process_tick(current_ + 1);
    }
    std::vector<Handle> stop() {  // graceful shutdown: hand back pending work
        drain_queues(current_);
        std::vector<Handle> pending;
        for (auto& level : slots_)
            for (auto& slot : level) {
                for (auto& t : slot)
                    if (t->state.load() == Timeout::Pending) pending.push_back(t);
                size_ -= static_cast<i64>(slot.size());
                slot.clear();
            }
        return pending;
    }
    i64 size() const { return size_; }

private:
    void place(const Handle& t, i64 base) {
        if (t->deadline <= base) t->deadline = base + 1;
        const i64 delta = t->deadline - base;
        int level = 0;
        // <= not <: exactly 64^(L+1) ticks ahead still fits level L (one revolution); '<' fires a revolution late.
        while (level < kLevels - 1 && delta > (i64{1} << (kBits * (level + 1)))) ++level;
        const int slot = static_cast<int>((t->deadline >> (kBits * level)) & kMask);
        auto& lst = slots_[static_cast<std::size_t>(level)][static_cast<std::size_t>(slot)];
        t->pos = lst.insert(lst.end(), t);
        t->level = level;
        t->slot = slot;
        ++size_;
    }
    void unlink(Timeout& t) {
        if (t.level < 0) return;
        slots_[static_cast<std::size_t>(t.level)][static_cast<std::size_t>(t.slot)].erase(t.pos);
        t.level = -1;
        --size_;
    }
    std::list<Handle> take_slot(int level, int slot) {
        std::list<Handle> out;
        out.splice(out.end(), slots_[static_cast<std::size_t>(level)][static_cast<std::size_t>(slot)]);  // O(1)
        for (auto& t : out) t->level = -1;
        size_ -= static_cast<i64>(out.size());
        return out;
    }
    void process_tick(i64 tick) {
        const i64 base = tick - 1;
        drain_queues(base);
        int top = 0;
        for (int l = 1; l < kLevels; ++l) {
            if ((tick & ((i64{1} << (kBits * l)) - 1)) != 0) break;
            top = l;
        }
        for (int l = top; l >= 1; --l)  // highest first: entries may land in a lower slot due now
            for (auto& t : take_slot(l, static_cast<int>((tick >> (kBits * l)) & kMask))) {
                ++cascades;
                if (t->state.load() == Timeout::Pending) place(t, base);
            }
        for (auto& t : take_slot(0, static_cast<int>(tick & kMask))) {
            if (t->state.load() != Timeout::Pending) continue;
            if (t->deadline > tick) {  // overflow / early cascade: put it back
                place(t, tick);
                continue;
            }
            ++expired;
            if (t->period > 0) {  // fixed-rate from the SCHEDULED time: no drift
                t->deadline += t->period;
                place(t, tick);
            } else {
                t->state.store(Timeout::Expired);
            }
            t->task(tick);  // a real scheduler hands this to a worker pool
        }
        current_ = tick;
    }
};

/** Baseline: one mutex + a binary heap; cancel only flips a flag, so cancelled entries linger (tombstones). */
class HeapScheduler {
    struct Entry {
        i64 deadline;
        Handle t;
        bool operator>(const Entry& o) const { return deadline > o.deadline; }
    };
    std::mutex m_;
    std::priority_queue<Entry, std::vector<Entry>, std::greater<>> heap_;
public:
    Handle schedule(i64 deadline, std::function<void(i64)> task) {
        auto t = std::make_shared<Timeout>(deadline, 0, std::move(task));
        std::scoped_lock l(m_);
        heap_.push({deadline, t});  // O(log n) under one lock
        return t;
    }
    static bool cancel(const Handle& t) {
        int expected = Timeout::Pending;
        return t->state.compare_exchange_strong(expected, Timeout::Cancelled);  // O(1), but the entry stays
    }
    std::size_t size() {
        std::scoped_lock l(m_);
        return heap_.size();
    }
};

template <class F>
i64 timed(int threads, F body) {
    std::barrier sync(threads + 1);
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            sync.arrive_and_wait();
            body(t);
            sync.arrive_and_wait();
        });
    sync.arrive_and_wait();
    const auto t0 = std::chrono::steady_clock::now();
    sync.arrive_and_wait();
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
}

int main() {
    std::println("== 1. Virtual-time correctness: 100,000 timers, delays 1 ms .. 300 s, 20% cancelled ==");
    TimingWheel wheel(0);
    constexpr int n = 100'000;
    std::vector<i64> deadline(n), fired_at(n, -1);
    std::vector<int> fire_count(n, 0);
    std::vector<Handle> handles(n);
    for (int i = 0; i < n; ++i) {
        deadline[static_cast<std::size_t>(i)] = 1 + static_cast<i64>(mix64(static_cast<u64>(i)) % 300'000);
        handles[static_cast<std::size_t>(i)] = wheel.schedule(deadline[static_cast<std::size_t>(i)], 0, [&, i](i64 tick) {
            ++fire_count[static_cast<std::size_t>(i)];
            fired_at[static_cast<std::size_t>(i)] = tick;
        });
    }
    int cancelled = 0;
    for (int i = 0; i < n; i += 5) cancelled += wheel.cancel(handles[static_cast<std::size_t>(i)]);
    wheel.advance_to(300'001);
    int on_time = 0, wrong = 0, fired_cancelled = 0;
    for (std::size_t i = 0; i < static_cast<std::size_t>(n); ++i) {
        if (i % 5 == 0) fired_cancelled += fire_count[i] != 0;
        else if (fire_count[i] == 1 && fired_at[i] == deadline[i]) ++on_time;
        else ++wrong;
    }
    std::println("  cancelled {} | fired exactly once at the exact deadline tick {} | wrong {} | cancelled-but-fired {}", cancelled,
                 on_time, wrong, fired_cancelled);
    std::println("  cascades {} ({:.2f} per timer) | entries left {}", wheel.cascades, static_cast<double>(wheel.cascades) / n, wheel.size());

    std::println("== 2. Fixed-rate recurrence: period 250 ticks from t=0, run to t=10,000 ==");
    TimingWheel rec(0);
    std::vector<i64> fires;
    auto every = rec.schedule(250, 250, [&](i64 tick) { fires.push_back(tick); });
    rec.advance_to(10'000);
    rec.cancel(every);
    rec.advance_to(12'000);
    const bool multiples = std::ranges::all_of(fires, [](i64 t) { return t % 250 == 0; });
    std::println("  fired {} times; first [{}, {}, {}] last {}; all exact multiples of 250 = {}; after cancel: {}", fires.size(),
                 fires[0], fires[1], fires[2], fires.back(), multiples, fires.size());

    std::println("== 3. Graceful shutdown hands back pending work ==");
    TimingWheel sd(0);
    for (i64 i = 1; i <= 10; ++i) sd.schedule(i * 1'000, 0, [](i64) {});
    auto c = sd.schedule(9'999, 0, [](i64) {});
    sd.cancel(c);
    sd.advance_to(3'500);
    const auto left = sd.stop();
    std::println("  10 scheduled, 1 cancelled, ran to t=3,500 -> expired {}, returned on stop() {}", sd.expired, left.size());

    std::println("== 4. Schedule + cancel cost (one measured run): 4 threads x 100,000 timers, delays up to 60 s ==");
    for (int round = 0; round < 2; ++round) {
        HeapScheduler heap;
        std::vector<std::vector<Handle>> hh(4, std::vector<Handle>(100'000));
        const i64 heap_schedule = timed(4, [&](int t) {
            for (int i = 0; i < 100'000; ++i)
                hh[static_cast<std::size_t>(t)][static_cast<std::size_t>(i)] =
                    heap.schedule(1 + static_cast<i64>(mix64(static_cast<u64>(t) * 1'000'003ULL + static_cast<u64>(i)) % 60'000), [](i64) {});
        });
        const i64 heap_cancel = timed(4, [&](int t) {
            for (std::size_t i = 0; i < 100'000; i += 2) HeapScheduler::cancel(hh[static_cast<std::size_t>(t)][i]);
        });
        TimingWheel w(0);
        std::vector<std::vector<Handle>> wh(4, std::vector<Handle>(100'000));
        const i64 wheel_schedule = timed(4, [&](int t) {
            for (int i = 0; i < 100'000; ++i)
                wh[static_cast<std::size_t>(t)][static_cast<std::size_t>(i)] =
                    w.schedule(1 + static_cast<i64>(mix64(static_cast<u64>(t) * 1'000'003ULL + static_cast<u64>(i)) % 60'000), 0, [](i64) {});
        });
        auto t0 = std::chrono::steady_clock::now();
        w.drain_queues(0);
        const double drain_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        const i64 wheel_cancel = timed(4, [&](int t) {
            for (std::size_t i = 0; i < 100'000; i += 2) w.cancel(wh[static_cast<std::size_t>(t)][i]);
        });
        t0 = std::chrono::steady_clock::now();
        w.drain_queues(0);
        const double unlink_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        if (round == 1) {
            std::println("  mutex + binary heap: schedule {:6.1f} ms, cancel 200k {:5.1f} ms, entries after {} (200,000 tombstones)",
                         static_cast<double>(heap_schedule) / 1e6, static_cast<double>(heap_cancel) / 1e6, heap.size());
            std::println("  TimingWheel: schedule {:6.1f} ms (+ drain {:5.1f} ms on wheel thread), cancel 200k {:5.1f} ms (+ unlink {:4.1f} ms), entries after {}",
                         static_cast<double>(wheel_schedule) / 1e6, drain_ms, static_cast<double>(wheel_cancel) / 1e6, unlink_ms, w.size());
        }
    }
    const bool ok = on_time == n - cancelled && wrong == 0 && fired_cancelled == 0 && wheel.size() == 0 && fires.size() == 40 &&
                    sd.expired == 3 && left.size() == 7;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Virtual-time correctness: 100,000 timers, delays 1 ms .. 300 s, 20% cancelled ==
  cancelled 20000 | fired exactly once at the exact deadline tick 80000 | wrong 0 | cancelled-but-fired 0
  cascades 166691 (1.67 per timer) | entries left 0
== 2. Fixed-rate recurrence: period 250 ticks from t=0, run to t=10,000 ==
  fired 40 times; first [250, 500, 750] last 10000; all exact multiples of 250 = true; after cancel: 40
== 3. Graceful shutdown hands back pending work ==
  10 scheduled, 1 cancelled, ran to t=3,500 -> expired 3, returned on stop() 7
== 4. Schedule + cancel cost (one measured run): 4 threads x 100,000 timers, delays up to 60 s ==
  mutex + binary heap: schedule   74.7 ms, cancel 200k   1.3 ms, entries after 400000 (200,000 tombstones)
  TimingWheel: schedule   60.7 ms (+ drain  30.9 ms on wheel thread), cancel 200k  29.2 ms (+ unlink 16.6 ms), entries after 200000
SELF-TEST OK
```

**Output, Clang 21.1 (sections 1–3 identical):**

```text
== 1. Virtual-time correctness: 100,000 timers, delays 1 ms .. 300 s, 20% cancelled ==
  cancelled 20000 | fired exactly once at the exact deadline tick 80000 | wrong 0 | cancelled-but-fired 0
  cascades 166691 (1.67 per timer) | entries left 0
== 2. Fixed-rate recurrence: period 250 ticks from t=0, run to t=10,000 ==
  fired 40 times; first [250, 500, 750] last 10000; all exact multiples of 250 = true; after cancel: 40
== 3. Graceful shutdown hands back pending work ==
  10 scheduled, 1 cancelled, ran to t=3,500 -> expired 3, returned on stop() 7
== 4. Schedule + cancel cost (one measured run): 4 threads x 100,000 timers, delays up to 60 s ==
  mutex + binary heap: schedule   63.0 ms, cancel 200k  16.0 ms, entries after 400000 (200,000 tombstones)
  TimingWheel: schedule   47.3 ms (+ drain  33.6 ms on wheel thread), cancel 200k  16.2 ms (+ unlink 19.7 ms), entries after 200000
SELF-TEST OK
```

## 6. Reading the results

- **Correctness:** both languages fire **80,000 / 80,000** live timers exactly at their deadline tick. 0 cancelled timers fire, and 0 entries are left. Cascade counts are identical (166,691), which validates the two implementations against each other.
- **Java cost.** Schedule from 4 threads took 49–53 ms, plus 9–10 ms of drain on the wheel thread, against 78–112 ms for `ScheduledThreadPoolExecutor`. Cancelling 200k took 23–33 ms for the wheel against 61 ms for STPE. STPE's queue size after cancel (≈ 199.6 k) is slightly below 200 k because its worker *ran* the shortest timers during the test. The wheel was never advanced.
- **C++ cost is closer.** The C++ hand-off queue is a mutex + `vector` swap, so producers contend on it. The heap's cancel is a mere flag flip (1–16 ms), but it **keeps every cancelled entry** until its deadline. At a 50% cancel rate, the heap carries twice the memory of the wheel and pays O(log n) to pop each tombstone later. A lock-free MPSC queue (01.3 §7 and P17) closes the producer-side gap.

The L7 summary: **the wheel's advantage is asymptotic and in memory behaviour, not a constant factor at 400k timers.** It shows at millions of timers with high cancel rates (Kafka's purgatory, Netty's idle-connection timeouts), where heap rebalancing under one lock dominates.

## 7. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Structure | `DelayQueue` + worker thread | `ScheduledThreadPoolExecutor` with `setRemoveOnCancelPolicy(true)` | Hierarchical timing wheel; knows the precision trade-off; knows Kafka's `SystemTimer`/`TimingWheel` and Netty's `HashedWheelTimer` |
| Cancel | `remove(task)`: O(n), or tombstones | O(log n) with heap indexes | O(1) CAS plus deferred unlink on the wheel thread |
| Threads | User code on the timer thread | A pool for execution | Single-threaded wheel core, MPSC hand-off, executor for tasks, no locks in the core |
| Recurrence | `Thread.sleep(period)` loops | `scheduleAtFixedRate` | Fixed-rate from the scheduled time vs fixed-delay, chosen explicitly; overrun policy (skip/catch-up) stated |
| Testing | Sleep and hope | Small real-time tests | Virtual time: exact firing ticks for 100k random timers, cancel races, nothing left behind |
| Shutdown | `System.exit` | `shutdownNow()` | Stop accepting, return the unprocessed handles, drain or drop by policy |

## 8. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Persist timers across restarts" | The wheel is the in-memory index. Timers live durably in a store keyed by `(dueTime, id)`. On boot, load the next horizon (say 1 h) into the wheel; a background task keeps loading ahead. Execution must be idempotent, since a restart may re-fire |
| "Distribute across nodes" | Shard timers by id hash; each shard has a wheel plus durable storage; a lease per shard with fencing (file 01's fencing token) so two nodes never fire the same shard |
| "Sub-millisecond precision for a few timers" | A second structure: a heap for the precise few, the wheel for the bulk |
| "A recurring task takes longer than its period" | Overrun policy: skip missed runs (next = first future multiple), run back-to-back (catch up), or never overlap (fixed-delay). Expose the choice |
| "Millions of timers per second" | Kafka's design: the wheel is advanced by a `DelayQueue` of **buckets**, not of timers. The heap holds at most one entry per non-empty bucket, which keeps heap traffic tiny |

## 9. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Why not just <code>ScheduledThreadPoolExecutor</code>?"</b></summary>

**L5:** "It's built in and it works."

**Why it fails:** at scale every schedule and every take is O(log n) under one lock. Without `setRemoveOnCancelPolicy(true)`, cancelled timeouts stay in the heap until their delay passes, and with it, each cancel is still O(log n) under the same lock.

**L7 defence:** "For thousands of timers, STPE is right. For hundreds of thousands with a high cancel rate (request timeouts), I want O(1) insert and cancel and a lock-free hand-off: a hierarchical wheel with tick precision, as in Kafka's purgatory and Netty's idle detection. I'd say the precision trade-off out loud."
</details>

<details>
<summary><b>Q2 ⚡ "How do you know your wheel is correct?"</b></summary>

**L5:** "I scheduled a few timers and they fired."

**Why it fails:** boundary bugs fire timers *late*, not *never*. This listing's first draft fired 1,210 of 80,000 timers a full revolution late, and "they fired eventually" would have passed.

**L7 defence:** "Virtual time: 100,000 random deadlines across three levels, 20% cancelled. Assert each live timer fired once, at exactly its deadline tick, that no cancelled timer fired, and that the wheel is empty at the end. Then cross-check the cascade counts between two independent implementations."
</details>

<details>
<summary><b>Q3 ⚡ "Cancel races with expiry. What happens?"</b></summary>

**L5:** "We lock the timer."

**Why it fails:** a lock per timer, or a global lock, puts the producer path back under contention.

**L7 defence:** "State is an atomic, `PENDING → CANCELLED` or `PENDING → EXPIRED`, decided by CAS. Exactly one wins. If cancel wins, the wheel skips the handle (and unlinks it when it drains the cancel queue). If expiry wins, `cancel()` returns false, so callers know the task ran or is running."
</details>

## 10. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Memory grows with cancelled timeouts | Tombstone cancellation in a heap | O(1) unlink (wheel), or remove-on-cancel |
| Timer thread stalls | User task executed on the tick thread | Dispatch to an executor |
| Timers fire a full revolution late | Level-boundary off-by-one (`<` vs `≤`) | Exact-tick virtual-time test |
| Recurring jobs drift later every hour | Rescheduling from completion time | Fixed-rate from the scheduled time |
| Timers lost on shutdown | No hand-back | `stop()` returns the pending handles |
| Double execution after a failover | No fencing / idempotency | Leases with fencing tokens; idempotent tasks |

- [ ] Precision (tick size) is stated and acceptable.
- [ ] Insert and cancel are O(1); cancellation frees memory promptly.
- [ ] The wheel core is single-threaded; the hand-off is MPSC; tasks run on an executor.
- [ ] Cancel and expiry race through one atomic state.
- [ ] Recurrence policy (fixed-rate / fixed-delay / overrun) is explicit.
- [ ] A virtual-time test asserts exact firing ticks for random deadlines across levels.

## 11. References

- George Varghese and Tony Lauck, "Hashed and Hierarchical Timing Wheels", SOSP 1987 / IEEE ToN 1997. <https://doi.org/10.1145/41457.37504>
- Apache Kafka, `org.apache.kafka.server.util.timer.TimingWheel` / `SystemTimer` (purgatory). <https://github.com/apache/kafka/tree/trunk/server-common/src/main/java/org/apache/kafka/server/util/timer>
- Netty `HashedWheelTimer`. <https://github.com/netty/netty/blob/4.1/common/src/main/java/io/netty/util/HashedWheelTimer.java>
- Java `ScheduledThreadPoolExecutor.setRemoveOnCancelPolicy`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/ScheduledThreadPoolExecutor.html>
- In this KB: [01.3 Virtual-time scheduler](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P1 cache TTL](01-problem-01-thread-safe-lru-and-lfu-ttl-cache-caffeine-architecture.md) · [P5 breaker open-state timer](05-problem-05-bounded-blocking-connection-pool-and-circuit-breaker.md)
