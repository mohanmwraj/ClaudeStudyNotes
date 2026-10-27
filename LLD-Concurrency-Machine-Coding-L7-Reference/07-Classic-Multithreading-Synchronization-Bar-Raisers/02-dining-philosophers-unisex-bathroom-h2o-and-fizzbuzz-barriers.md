# 07.2 · Dining Philosophers, Unisex Bathroom, H2O and FizzBuzz: the Classic Coordination Puzzles, Verified

> **Folder 07 · File 2 of 3.** These four puzzles test whether a candidate can name the property being protected (deadlock freedom, mutual exclusion with fairness, group composition, turn order), choose the primitive that expresses it, and **prove it with a harness**.
>
> Two of this file's lessons were found the hard way while writing it:
> - a timeout turns deadlock into **livelock** unless backoff is random;
> - a fixed per-thread work split **deadlocks H2O at the tail**.
>
> **Listing pair 07.2:** `ClassicSync.java` / `classic_sync.cpp`. The correctness lines (meals, violations, molecules, FizzBuzz output) are identical in every build; timings and wait counts are one measured run.

---

## 1. The puzzles and the property each one protects

| Puzzle | Property | Primitive that expresses it |
|---|---|---|
| Dining philosophers | No deadlock (and no livelock), everyone eats | A global lock order, or a semaphore limiting contenders |
| Unisex bathroom | Never mixed, at most 3 inside, **no starvation** of either group | A monitor with a turn-taking admission rule |
| H2O | Every group is exactly H, H, O | Two semaphores (2 and 1) + a 3-party barrier |
| FizzBuzz (4 threads) | Output order 1..n by kind | A turn variable (monitor), or a semaphore handoff per thread |

## 2. Dining philosophers: from deadlock to livelock to neither

**Left fork, then right fork** deadlocks as soon as all five hold their left fork. The listing makes that survivable with a bounded try on the right fork. On failure: put the left fork back, back off, retry.

**The first version backed off by a *fixed* amount, and hung the test for 240 s.** All five philosophers timed out, released and retried **in lockstep**: textbook livelock. Random backoff breaks the symmetry, and it completed with 280 / 199 / 153 broken waits (Java / GCC / Clang).

**Two correct designs never need to break a wait:**
- **Lower-numbered fork first.** A global lock order means no cycle can form. Philosopher 4 picks fork 0 before fork 4: the asymmetry is the fix.
- **A waiter seating four.** A `Semaphore(4)` guarantees at least one philosopher can take both forks.

| 5 × 2,000 meals | Java | GCC | Clang |
|---|---|---|---|
| Left then right, bounded try + random backoff | 280 broken waits, 176 ms | 199, 169 ms | 153, 203 ms |
| Lower fork first | 0, 121 ms | 0, 116 ms | 0, 114 ms |
| Waiter (4 seats) | 0, 131 ms | 0, 120 ms | 0, 119 ms |

## 3. Unisex bathroom: exclusion is easy, fairness is the question

The naive admission rule is "empty, or same gender with room". It never mixes, but a busy group can keep the room by always having one more member join. The fair rule adds: **same gender may join only if nobody of the other gender is waiting**. The current group drains, and the waiting group gets the room.

| 4 men + 4 women × 3,000 visits | Java (men / women longest wait) | GCC | Clang |
|---|---|---|---|
| Naive | 16.2 / 10.5 ms | 6.1 / 9.3 ms | 2.6 / 2.7 ms |
| Fair | **3.9 / 2.4 ms** | **2.6 / 3.5 ms** | **1.2 / 1.1 ms** |
| Mixing or over-capacity violations | 0 / 0 | 0 / 0 | 0 / 0 |

**Two details:**
- **Violations are checked independently** of the monitor, with atomic per-gender counters inside the critical region. A monitor that is wrong can't grade itself.
- **Fairness costs throughput:** 416 ms vs 296 ms in Java, because the room is handed over half-empty. That's the usual trade, and you should say so.

## 4. H2O: two semaphores and a barrier, and the tail deadlock

**The design:**
- `hydrogen = Semaphore(2)` and `oxygen = Semaphore(1)` cap how many atoms of each kind can be "in the molecule" at once.
- A `CyclicBarrier(3)` (in C++, a mutex/cv barrier with a completion action) bonds them.
- The barrier action, which runs once per generation after all three arrived, checks the composition. Next-generation atoms can't increment the counters early, because they need the permits that are only released after `await` returns.

**The first version deadlocked.** Each thread was given a fixed **500 atoms**. When the other hydrogen threads finished, the last molecule needed **two H atoms at once**. The only H thread left was already parked at the barrier with its first atom, so it could never supply the second. The thread dump showed two threads waiting for a third party that couldn't exist.

**The fix: atoms are claimed dynamically** from a shared counter, so any free thread supplies the next atom. Result: **1,000 molecules, 0 malformed**, in all three builds.

The general lesson: static partitioning of work can deadlock when progress needs several units **concurrently**.

## 5. FizzBuzz: turn order, and the cost of `notifyAll`

**The monitor version:** one `current` counter; each thread waits until `kind(current)` is its own. Each step wakes all three other threads to tell them "not yet": **~320,000 useless wake-ups** for n = 200,000.

**The semaphore version:** each printer releases exactly the semaphore of the thread that owns `current + 1`.

| n = 200,000 | Java | GCC (libstdc++ / winpthreads) | Clang (libc++) |
|---|---|---|---|
| Monitor + `notifyAll` | 1,309 ms | **3,136 ms** | **177 ms** |
| Semaphore handoff | 762 ms | 776 ms | 550 ms |

**Precise handoff wins on the JVM and on MinGW.** On libc++ the wake-all variant was **3× faster** than the handoff. Its condition variable makes a mass wake-up cheap, while the handoff pays a full sleep/wake per step on per-thread semaphores.

The robust statement is "precise wake-ups remove 320,000 useless wake-ups", not "always faster". What those wake-ups cost is a property of the runtime, so measure on the target.

**C++ note:** the listing's `Semaphore` and `Barrier` are mutex + condition-variable based. `std::counting_semaphore` and `std::barrier` exist, but libc++ builds them on atomic wait, which sleeps ~15.6 ms on Windows once its spin phase ends (measured in P6).

## 6. Java 21 implementation

```java
// ClassicSync.java - 07.2: dining philosophers, unisex bathroom, H2O barrier, FizzBuzz handoff, each with a verifying harness
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Semaphore;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;

public final class ClassicSync {

    interface Body {
        void run(int thread) throws Exception;
    }

    /** Starts all threads together, joins them, rethrows the first failure. Returns wall time in ms. */
    static long parallel(int threads, Body body) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        List<Thread> ts = new ArrayList<>();
        for (int t = 0; t < threads; t++) {
            final int id = t;
            ts.add(Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    body.run(id);
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                }
            }));
        }
        start.await();
        long t0 = System.nanoTime();
        for (Thread t : ts) t.join();
        if (failure.get() != null) throw new IllegalStateException(failure.get());
        return (System.nanoTime() - t0) / 1_000_000;
    }

    static void spin(int n) {
        for (int i = 0; i < n; i++) Thread.onSpinWait();
    }

    static boolean trySpin(ReentrantLock l) {
        for (int i = 0; i < 20_000; i++) {
            if (l.tryLock()) return true;
            Thread.onSpinWait();
        }
        return false;
    }

    static void await(Object monitor) {
        try {
            monitor.wait();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // ---- 1. dining philosophers

    enum Table { LEFT_THEN_RIGHT, LOWER_FORK_FIRST, WAITER_SEATS_FOUR }

    record Dinner(long ms, long brokenWaits, int minMeals, int maxMeals) {}

    static Dinner dine(Table table) throws Exception {
        ReentrantLock[] forks = new ReentrantLock[5];
        for (int i = 0; i < 5; i++) forks[i] = new ReentrantLock();
        Semaphore waiter = new Semaphore(4);                           // at most 4 of 5 may reach for forks: no cycle
        int[] meals = new int[5];
        LongAdder broken = new LongAdder();
        long ms = parallel(5, p -> {
            ReentrantLock left = forks[p], right = forks[(p + 1) % 5];
            for (int meal = 0; meal < 2_000; meal++) {
                switch (table) {
                    case LEFT_THEN_RIGHT -> {
                        for (;;) {                                     // all five hold their left fork = deadlock;
                            left.lock();                               // the bounded try is the only way out...
                            spin(200);
                            if (trySpin(right)) break;
                            broken.increment();
                            left.unlock();
                            spin(ThreadLocalRandom.current().nextInt(20_000));   // ...and only RANDOM backoff avoids livelock
                        }
                    }
                    case LOWER_FORK_FIRST -> {                         // a global order on forks: no cycle can form
                        ReentrantLock first = p < (p + 1) % 5 ? left : right, second = first == left ? right : left;
                        first.lock();
                        spin(200);
                        second.lock();
                    }
                    case WAITER_SEATS_FOUR -> {
                        waiter.acquire();
                        left.lock();
                        spin(200);
                        right.lock();
                    }
                }
                meals[p]++;
                spin(100);                                             // eat
                right.unlock();
                left.unlock();
                if (table == Table.WAITER_SEATS_FOUR) waiter.release();
            }
        });
        return new Dinner(ms, broken.sum(), Arrays.stream(meals).min().orElse(0), Arrays.stream(meals).max().orElse(0));
    }

    // ---- 2. unisex bathroom: capacity 3, never mixed

    static final class Bathroom {
        final boolean fair;
        final int[] waiting = new int[2];                              // guarded by this
        int inside, gender = -1;
        final AtomicInteger[] present = {new AtomicInteger(), new AtomicInteger()};   // independent invariant check
        final LongAdder violations = new LongAdder();

        Bathroom(boolean fair) {
            this.fair = fair;
        }

        synchronized void enter(int g) {
            waiting[g]++;
            // naive: join whenever it's empty or same gender with room. Fair: same gender joins only if nobody of the
            // other gender is waiting, so a waiting group gets the room as soon as the current group drains.
            while (!(inside == 0 || (gender == g && inside < 3 && (!fair || waiting[1 - g] == 0)))) await(this);
            waiting[g]--;
            gender = g;
            inside++;
        }

        synchronized void leave() {
            if (--inside == 0) gender = -1;
            notifyAll();
        }

        void visit(int g) {
            enter(g);
            if (present[g].incrementAndGet() > 3 || present[1 - g].get() > 0) violations.increment();
            spin(300);
            present[g].decrementAndGet();
            leave();
        }
    }

    record Visits(long violations, long maxWaitMenUs, long maxWaitWomenUs, long ms) {}

    static Visits bathroom(boolean fair) throws Exception {
        Bathroom b = new Bathroom(fair);
        AtomicLong[] maxWait = {new AtomicLong(), new AtomicLong()};
        long ms = parallel(8, t -> {
            int g = t % 2;
            for (int i = 0; i < 3_000; i++) {
                long t0 = System.nanoTime();
                b.visit(g);
                long waited = System.nanoTime() - t0;
                maxWait[g].accumulateAndGet(waited, Math::max);
                spin(t < 6 ? 0 : 2_000);                               // threads 6 (a man) and 7 (a woman) visit occasionally
            }
        });
        return new Visits(b.violations.sum(), maxWait[0].get() / 1_000, maxWait[1].get() / 1_000, ms);
    }

    // ---- 3. H2O: exactly two hydrogens and one oxygen bond together

    record Water(int molecules, int badMolecules) {}

    static Water h2o() throws Exception {
        Semaphore hydrogen = new Semaphore(2), oxygen = new Semaphore(1);
        AtomicInteger h = new AtomicInteger(), o = new AtomicInteger(), molecules = new AtomicInteger(), bad = new AtomicInteger();
        CyclicBarrier bond = new CyclicBarrier(3, () -> {             // runs once per molecule, after all three arrived
            if (h.get() != 2 || o.get() != 1) bad.incrementAndGet();
            h.set(0);
            o.set(0);
            molecules.incrementAndGet();
        });
        AtomicInteger hLeft = new AtomicInteger(2_000), oLeft = new AtomicInteger(1_000);
        parallel(6, t -> {                                              // 4 hydrogen threads, 2 oxygen threads, atoms claimed dynamically:
            boolean isO = t >= 4;                                       // with 500 atoms PER thread, the last H thread can be left needing
            while ((isO ? oLeft : hLeft).getAndDecrement() > 0) {      // two H at once while it sits at the barrier with one: deadlock
                (isO ? oxygen : hydrogen).acquire();
                (isO ? o : h).incrementAndGet();
                bond.await();
                (isO ? oxygen : hydrogen).release();
            }
        });
        return new Water(molecules.get(), bad.get());
    }

    // ---- 4. FizzBuzz with 4 threads: whose turn is it?

    static int kind(int i) {
        return i % 15 == 0 ? 3 : i % 5 == 0 ? 2 : i % 3 == 0 ? 1 : 0;   // 0 number, 1 fizz, 2 buzz, 3 fizzbuzz
    }

    static String word(int i) {
        return switch (kind(i)) {
            case 1 -> "fizz";
            case 2 -> "buzz";
            case 3 -> "fizzbuzz";
            default -> Integer.toString(i);
        };
    }

    /** Monitor + notifyAll: correct, but every step wakes all three other threads to find out it's not their turn. */
    static final class MonitorFizzBuzz {
        final int n;
        int current = 1;
        final StringBuilder out = new StringBuilder();
        long wakeups;

        MonitorFizzBuzz(int n) {
            this.n = n;
        }

        synchronized void run(int k) {
            for (;;) {
                while (current <= n && kind(current) != k) {
                    await(this);
                    wakeups++;
                }
                if (current > n) return;
                out.append(word(current)).append(' ');
                current++;
                notifyAll();
            }
        }
    }

    /** One semaphore per thread: the printer of i hands the turn exactly to the thread that owns i + 1. */
    static final class SemaphoreFizzBuzz {
        final int n;
        final Semaphore[] turn = {new Semaphore(1), new Semaphore(0), new Semaphore(0), new Semaphore(0)};
        final StringBuilder out = new StringBuilder();
        int current = 1;                                               // handed over with the semaphore (happens-before)

        SemaphoreFizzBuzz(int n) {
            this.n = n;
        }

        void run(int k) throws InterruptedException {
            for (;;) {
                turn[k].acquire();
                if (current > n) {
                    for (Semaphore s : turn) s.release();              // wake everyone so they can see the end
                    return;
                }
                out.append(word(current)).append(' ');
                current++;
                turn[current > n ? 0 : kind(current)].release();
            }
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Dining philosophers: 5 philosophers x 2,000 meals ==");
        Dinner[] d = new Dinner[3];
        for (Table t : Table.values()) {
            d[t.ordinal()] = dine(t);
            System.out.printf("  %-20s meals per philosopher %d..%d | waits broken by a bounded try %d | %d ms%n", t, d[t.ordinal()].minMeals(),
                    d[t.ordinal()].maxMeals(), d[t.ordinal()].brokenWaits(), d[t.ordinal()].ms());
        }

        System.out.println("== 2. Unisex bathroom: capacity 3, 4 men + 4 women (one of each visits occasionally), 3,000 visits each ==");
        Visits naive = bathroom(false), fair = bathroom(true);
        for (Visits v : List.of(naive, fair))
            System.out.printf("  %-44s mixing/capacity violations %d | longest wait: men %d us, women %d us | %d ms%n",
                    v == naive ? "join if empty or same gender with room:" : "same gender joins only if nobody else waits:", v.violations(),
                    v.maxWaitMenUs(), v.maxWaitWomenUs(), v.ms());

        System.out.println("== 3. H2O: 2,000 H + 1,000 O atoms claimed by 4 + 2 threads, semaphores (2, 1) + a 3-party barrier ==");
        Water w = h2o();
        System.out.printf("  molecules %d | molecules that were not exactly H, H, O: %d%n", w.molecules(), w.badMolecules());

        System.out.println("== 4. FizzBuzz with 4 threads ==");
        MonitorFizzBuzz m15 = new MonitorFizzBuzz(15);
        parallel(4, m15::run);
        System.out.println("  n = 15: " + m15.out.toString().trim());
        StringBuilder expected = new StringBuilder();
        for (int i = 1; i <= 200_000; i++) expected.append(word(i)).append(' ');
        MonitorFizzBuzz mon = new MonitorFizzBuzz(200_000);
        long monMs = parallel(4, mon::run);
        SemaphoreFizzBuzz sem = new SemaphoreFizzBuzz(200_000);
        long semMs = parallel(4, sem::run);
        boolean monOk = mon.out.toString().contentEquals(expected), semOk = sem.out.toString().contentEquals(expected);
        System.out.printf("  n = 200,000: monitor + notifyAll %d ms (%d wake-ups that weren't its turn), correct %b | semaphore handoff %d ms, correct %b%n",
                monMs, mon.wakeups, monOk, semMs, semOk);

        boolean ok = Arrays.stream(d).allMatch(x -> x.minMeals() == 2_000 && x.maxMeals() == 2_000) && d[1].brokenWaits() == 0 && d[2].brokenWaits() == 0
                && naive.violations() == 0 && fair.violations() == 0 && w.molecules() == 1_000 && w.badMolecules() == 0
                && m15.out.toString().trim().equals("1 2 fizz 4 buzz fizz 7 8 fizz buzz 11 fizz 13 14 fizzbuzz") && monOk && semOk;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (correctness lines deterministic; timings one measured run):**

```text
== 1. Dining philosophers: 5 philosophers x 2,000 meals ==
  LEFT_THEN_RIGHT      meals per philosopher 2000..2000 | waits broken by a bounded try 274 | 170 ms
  LOWER_FORK_FIRST     meals per philosopher 2000..2000 | waits broken by a bounded try 0 | 121 ms
  WAITER_SEATS_FOUR    meals per philosopher 2000..2000 | waits broken by a bounded try 0 | 129 ms
== 2. Unisex bathroom: capacity 3, 4 men + 4 women (one of each visits occasionally), 3,000 visits each ==
  join if empty or same gender with room:      mixing/capacity violations 0 | longest wait: men 11437 us, women 13771 us | 290 ms
  same gender joins only if nobody else waits: mixing/capacity violations 0 | longest wait: men 2226 us, women 2421 us | 408 ms
== 3. H2O: 2,000 H + 1,000 O atoms claimed by 4 + 2 threads, semaphores (2, 1) + a 3-party barrier ==
  molecules 1000 | molecules that were not exactly H, H, O: 0
== 4. FizzBuzz with 4 threads ==
  n = 15: 1 2 fizz 4 buzz fizz 7 8 fizz buzz 11 fizz 13 14 fizzbuzz
  n = 200,000: monitor + notifyAll 1309 ms (319995 wake-ups that weren't its turn), correct true | semaphore handoff 762 ms, correct true
SELF-TEST OK
```

## 7. C++23 implementation

```cpp
// classic_sync.cpp - 07.2: dining philosophers, unisex bathroom, H2O barrier, FizzBuzz handoff, each with a verifying harness
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <mutex>
#include <print>
#include <random>
#include <string>
#include <thread>
#include <vector>

using i64 = std::int64_t;
using sz = std::size_t;

void pause_spin(int n) {
    for (int k = 0; k < n; ++k) {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#endif
    }
}

i64 now_ns() { return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

template <class F>
i64 parallel(int threads, F body) {  // spin gate with a ready count (see P6); returns wall ms
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    i64 t0 = 0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                body(t);
            });
        while (ready.load() < threads) {}
        t0 = now_ns();
        go.store(true, std::memory_order_release);
    }
    return (now_ns() - t0) / 1'000'000;
}

/**
 * A counting semaphore on mutex + condition variable. std::counting_semaphore exists (C++20), but libc++ builds it on
 * atomic wait, which sleeps ~15.6 ms on Windows once its spin phase ends (measured in P6); this one wakes promptly.
 */
class Semaphore {
    std::mutex m_;
    std::condition_variable cv_;
    int permits_;

public:
    explicit Semaphore(int p) : permits_(p) { std::scoped_lock warm(m_); }
    void acquire() {
        std::unique_lock l(m_);
        cv_.wait(l, [&] { return permits_ > 0; });
        --permits_;
    }
    void release() {
        {
            std::scoped_lock l(m_);
            ++permits_;
        }
        cv_.notify_one();
    }
};

/** A cyclic barrier with a completion action, like java.util.concurrent.CyclicBarrier (generation-counted). */
class Barrier {
    std::mutex m_;
    std::condition_variable cv_;
    const int parties_;
    int arrived_ = 0;
    i64 generation_ = 0;
    std::function<void()> action_;

public:
    Barrier(int parties, std::function<void()> action) : parties_(parties), action_(std::move(action)) { std::scoped_lock warm(m_); }
    void arrive_and_wait() {
        std::unique_lock l(m_);
        const i64 gen = generation_;
        if (++arrived_ == parties_) {
            action_();  // runs once per generation, after all parties arrived
            arrived_ = 0;
            ++generation_;
            cv_.notify_all();
            return;
        }
        cv_.wait(l, [&] { return generation_ != gen; });
    }
};

bool try_spin(std::mutex& m) {
    for (int i = 0; i < 20'000; ++i) {
        if (m.try_lock()) return true;
        pause_spin(1);
    }
    return false;
}

// ---- 1. dining philosophers

enum class Table { LeftThenRight, LowerForkFirst, WaiterSeatsFour };
constexpr std::array<const char*, 3> kTableNames{"LEFT_THEN_RIGHT", "LOWER_FORK_FIRST", "WAITER_SEATS_FOUR"};

struct Dinner { i64 ms, broken_waits; int min_meals, max_meals; };

Dinner dine(Table table) {
    std::array<std::mutex, 5> forks;
    for (auto& f : forks) std::scoped_lock warm(f);
    Semaphore waiter(4);  // at most 4 of 5 may reach for forks: no cycle
    std::array<int, 5> meals{};
    std::atomic<i64> broken{0};
    const i64 ms = parallel(5, [&](int p) {
        std::mutex& left = forks[static_cast<sz>(p)];
        std::mutex& right = forks[static_cast<sz>((p + 1) % 5)];
        std::minstd_rand rng(static_cast<unsigned>(p + 1));
        for (int meal = 0; meal < 2'000; ++meal) {
            switch (table) {
                case Table::LeftThenRight:
                    for (;;) {  // all five hold their left fork = deadlock; the bounded try is the only way out...
                        left.lock();
                        pause_spin(200);
                        if (try_spin(right)) break;
                        broken.fetch_add(1);
                        left.unlock();
                        pause_spin(static_cast<int>(rng() % 20'000));  // ...and only RANDOM backoff avoids livelock
                    }
                    break;
                case Table::LowerForkFirst: {  // a global order on forks: no cycle can form
                    std::mutex& first = p < (p + 1) % 5 ? left : right;
                    std::mutex& second = &first == &left ? right : left;
                    first.lock();
                    pause_spin(200);
                    second.lock();
                    break;
                }
                case Table::WaiterSeatsFour:
                    waiter.acquire();
                    left.lock();
                    pause_spin(200);
                    right.lock();
                    break;
            }
            ++meals[static_cast<sz>(p)];
            pause_spin(100);  // eat
            right.unlock();
            left.unlock();
            if (table == Table::WaiterSeatsFour) waiter.release();
        }
    });
    return {ms, broken.load(), *std::ranges::min_element(meals), *std::ranges::max_element(meals)};
}

// ---- 2. unisex bathroom: capacity 3, never mixed

class Bathroom {
    std::mutex m_;
    std::condition_variable cv_;
    const bool fair_;
    std::array<int, 2> waiting_{};
    int inside_ = 0, gender_ = -1;

public:
    std::array<std::atomic<int>, 2> present{};  // independent invariant check
    std::atomic<i64> violations{0};
    explicit Bathroom(bool fair) : fair_(fair) { std::scoped_lock warm(m_); }

    void enter(int g) {
        std::unique_lock l(m_);
        ++waiting_[static_cast<sz>(g)];
        // naive: join whenever it's empty or same gender with room. Fair: same gender joins only if nobody of the
        // other gender is waiting, so a waiting group gets the room as soon as the current group drains.
        cv_.wait(l, [&] { return inside_ == 0 || (gender_ == g && inside_ < 3 && (!fair_ || waiting_[static_cast<sz>(1 - g)] == 0)); });
        --waiting_[static_cast<sz>(g)];
        gender_ = g;
        ++inside_;
    }
    void leave() {
        {
            std::scoped_lock l(m_);
            if (--inside_ == 0) gender_ = -1;
        }
        cv_.notify_all();
    }
    void visit(int g) {
        enter(g);
        if (present[static_cast<sz>(g)].fetch_add(1) + 1 > 3 || present[static_cast<sz>(1 - g)].load() > 0) violations.fetch_add(1);
        pause_spin(300);
        present[static_cast<sz>(g)].fetch_sub(1);
        leave();
    }
};

struct Visits { i64 violations, max_wait_men_us, max_wait_women_us, ms; };

Visits bathroom(bool fair) {
    Bathroom b(fair);
    std::array<std::atomic<i64>, 2> max_wait{};
    const i64 ms = parallel(8, [&](int t) {
        const int g = t % 2;
        for (int i = 0; i < 3'000; ++i) {
            const i64 t0 = now_ns();
            b.visit(g);
            const i64 waited = now_ns() - t0;
            for (i64 cur = max_wait[static_cast<sz>(g)].load(); waited > cur && !max_wait[static_cast<sz>(g)].compare_exchange_weak(cur, waited);) {}
            pause_spin(t < 6 ? 0 : 2'000);  // threads 6 (a man) and 7 (a woman) visit occasionally
        }
    });
    return {b.violations.load(), max_wait[0].load() / 1'000, max_wait[1].load() / 1'000, ms};
}

// ---- 3. H2O: exactly two hydrogens and one oxygen bond together

struct Water { int molecules, bad_molecules; };

Water h2o() {
    Semaphore hydrogen(2), oxygen(1);
    std::atomic<int> h{0}, o{0}, molecules{0}, bad{0};
    Barrier bond(3, [&] {  // runs once per molecule, after all three arrived
        if (h.load() != 2 || o.load() != 1) bad.fetch_add(1);
        h.store(0);
        o.store(0);
        molecules.fetch_add(1);
    });
    std::atomic<int> h_left{2'000}, o_left{1'000};
    parallel(6, [&](int t) {  // atoms claimed dynamically: a fixed 500 PER thread can strand the last H thread needing two H at once
        const bool is_o = t >= 4;
        Semaphore& slots = is_o ? oxygen : hydrogen;
        while ((is_o ? o_left : h_left).fetch_sub(1) > 0) {
            slots.acquire();
            (is_o ? o : h).fetch_add(1);
            bond.arrive_and_wait();
            slots.release();
        }
    });
    return {molecules.load(), bad.load()};
}

// ---- 4. FizzBuzz with 4 threads: whose turn is it?

int kind(int i) { return i % 15 == 0 ? 3 : i % 5 == 0 ? 2 : i % 3 == 0 ? 1 : 0; }  // 0 number, 1 fizz, 2 buzz, 3 fizzbuzz
std::string word(int i) {
    switch (kind(i)) {
        case 1: return "fizz";
        case 2: return "buzz";
        case 3: return "fizzbuzz";
        default: return std::to_string(i);
    }
}

/** Monitor + notify_all: correct, but every step wakes all three other threads to find out it's not their turn. */
class MonitorFizzBuzz {
    std::mutex m_;
    std::condition_variable cv_;
    const int n_;
    int current_ = 1;

public:
    std::string out;
    i64 wakeups = 0;
    explicit MonitorFizzBuzz(int n) : n_(n) { std::scoped_lock warm(m_); }
    void run(int k) {
        std::unique_lock l(m_);
        for (;;) {
            while (current_ <= n_ && kind(current_) != k) {
                cv_.wait(l);
                ++wakeups;
            }
            if (current_ > n_) return;
            out += word(current_) + ' ';
            ++current_;
            cv_.notify_all();
        }
    }
};

/** One semaphore per thread: the printer of i hands the turn exactly to the thread that owns i + 1. */
class SemaphoreFizzBuzz {
    const int n_;
    std::array<Semaphore, 4> turn_{Semaphore(1), Semaphore(0), Semaphore(0), Semaphore(0)};
    int current_ = 1;  // handed over with the semaphore (happens-before)

public:
    std::string out;
    explicit SemaphoreFizzBuzz(int n) : n_(n) {}
    void run(int k) {
        for (;;) {
            turn_[static_cast<sz>(k)].acquire();
            if (current_ > n_) {
                for (auto& s : turn_) s.release();  // wake everyone so they can see the end
                return;
            }
            out += word(current_) + ' ';
            ++current_;
            turn_[static_cast<sz>(current_ > n_ ? 0 : kind(current_))].release();
        }
    }
};

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Dining philosophers: 5 philosophers x 2,000 meals ==");
    std::array<Dinner, 3> d{};
    for (sz t = 0; t < 3; ++t) {
        d[t] = dine(static_cast<Table>(t));
        std::println("  {:<20} meals per philosopher {}..{} | waits broken by a bounded try {} | {} ms", kTableNames[t], d[t].min_meals, d[t].max_meals,
                     d[t].broken_waits, d[t].ms);
    }

    std::println("== 2. Unisex bathroom: capacity 3, 4 men + 4 women (one of each visits occasionally), 3,000 visits each ==");
    const Visits naive = bathroom(false), fair = bathroom(true);
    for (const Visits* v : {&naive, &fair})
        std::println("  {:<44} mixing/capacity violations {} | longest wait: men {} us, women {} us | {} ms",
                     v == &naive ? "join if empty or same gender with room:" : "same gender joins only if nobody else waits:", v->violations,
                     v->max_wait_men_us, v->max_wait_women_us, v->ms);

    std::println("== 3. H2O: 2,000 H + 1,000 O atoms claimed by 4 + 2 threads, semaphores (2, 1) + a 3-party barrier ==");
    const Water w = h2o();
    std::println("  molecules {} | molecules that were not exactly H, H, O: {}", w.molecules, w.bad_molecules);

    std::println("== 4. FizzBuzz with 4 threads ==");
    MonitorFizzBuzz m15(15);
    parallel(4, [&](int k) { m15.run(k); });
    std::string trimmed = m15.out;
    trimmed.pop_back();
    std::println("  n = 15: {}", trimmed);
    std::string expected;
    for (int i = 1; i <= 200'000; ++i) expected += word(i) + ' ';
    MonitorFizzBuzz mon(200'000);
    const i64 mon_ms = parallel(4, [&](int k) { mon.run(k); });
    SemaphoreFizzBuzz sem(200'000);
    const i64 sem_ms = parallel(4, [&](int k) { sem.run(k); });
    const bool mon_ok = mon.out == expected, sem_ok = sem.out == expected;
    std::println("  n = 200,000: monitor + notifyAll {} ms ({} wake-ups that weren't its turn), correct {} | semaphore handoff {} ms, correct {}", mon_ms,
                 mon.wakeups, mon_ok, sem_ms, sem_ok);

    const bool ok = std::ranges::all_of(d, [](const Dinner& x) { return x.min_meals == 2'000 && x.max_meals == 2'000; }) && d[1].broken_waits == 0 &&
                    d[2].broken_waits == 0 && naive.violations == 0 && fair.violations == 0 && w.molecules == 1'000 && w.bad_molecules == 0 &&
                    trimmed == "1 2 fizz 4 buzz fizz 7 8 fizz buzz 11 fizz 13 14 fizzbuzz" && mon_ok && sem_ok;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Dining philosophers: 5 philosophers x 2,000 meals ==
  LEFT_THEN_RIGHT      meals per philosopher 2000..2000 | waits broken by a bounded try 199 | 169 ms
  LOWER_FORK_FIRST     meals per philosopher 2000..2000 | waits broken by a bounded try 0 | 116 ms
  WAITER_SEATS_FOUR    meals per philosopher 2000..2000 | waits broken by a bounded try 0 | 120 ms
== 2. Unisex bathroom: capacity 3, 4 men + 4 women (one of each visits occasionally), 3,000 visits each ==
  join if empty or same gender with room:      mixing/capacity violations 0 | longest wait: men 6116 us, women 9290 us | 365 ms
  same gender joins only if nobody else waits: mixing/capacity violations 0 | longest wait: men 2579 us, women 3509 us | 556 ms
== 3. H2O: 2,000 H + 1,000 O atoms claimed by 4 + 2 threads, semaphores (2, 1) + a 3-party barrier ==
  molecules 1000 | molecules that were not exactly H, H, O: 0
== 4. FizzBuzz with 4 threads ==
  n = 15: 1 2 fizz 4 buzz fizz 7 8 fizz buzz 11 fizz 13 14 fizzbuzz
  n = 200,000: monitor + notifyAll 3136 ms (326304 wake-ups that weren't its turn), correct true | semaphore handoff 776 ms, correct true
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Dining philosophers: 5 philosophers x 2,000 meals ==
  LEFT_THEN_RIGHT      meals per philosopher 2000..2000 | waits broken by a bounded try 153 | 203 ms
  LOWER_FORK_FIRST     meals per philosopher 2000..2000 | waits broken by a bounded try 0 | 114 ms
  WAITER_SEATS_FOUR    meals per philosopher 2000..2000 | waits broken by a bounded try 0 | 119 ms
== 2. Unisex bathroom: capacity 3, 4 men + 4 women (one of each visits occasionally), 3,000 visits each ==
  join if empty or same gender with room:      mixing/capacity violations 0 | longest wait: men 2628 us, women 2676 us | 274 ms
  same gender joins only if nobody else waits: mixing/capacity violations 0 | longest wait: men 1202 us, women 1064 us | 350 ms
== 3. H2O: 2,000 H + 1,000 O atoms claimed by 4 + 2 threads, semaphores (2, 1) + a 3-party barrier ==
  molecules 1000 | molecules that were not exactly H, H, O: 0
== 4. FizzBuzz with 4 threads ==
  n = 15: 1 2 fizz 4 buzz fizz 7 8 fizz buzz 11 fizz 13 14 fizzbuzz
  n = 200,000: monitor + notifyAll 177 ms (321778 wake-ups that weren't its turn), correct true | semaphore handoff 550 ms, correct true
SELF-TEST OK
```

## 8. L5 → L6 → L7

| Puzzle | L5 | L6 | L7 |
|---|---|---|---|
| Philosophers | Left then right | `tryLock` + retry | Global order or seat-limiting semaphore; knows timeout + fixed backoff = livelock; random backoff only as a fallback |
| Bathroom | One lock: one person at a time | Gender + count, no mixing | Turn-taking admission against starvation; invariants checked outside the monitor; states the throughput cost |
| H2O | `synchronized` counters | Semaphores + barrier | Knows why next-generation atoms can't corrupt counts; dynamic work claiming avoids the tail deadlock |
| FizzBuzz | Busy-wait on a volatile | Monitor + `notifyAll` | Precise handoff; counts wake-ups; measures that their cost is runtime-dependent |

## 9. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Add a timeout so the philosophers can't deadlock."</b></summary>

**L5:** "Use `tryLock(timeout)` and retry."

**Why it fails:** with fixed backoff all five retry in lockstep. That's livelock, and the first version of this test hung for 240 s.

**L7 defence:** "Prevent, don't detect: order the forks globally (lower first) or seat at most four. If a retry loop is unavoidable, use randomized backoff to break symmetry, and count the broken waits."
</details>

<details>
<summary><b>Q2 ⚡ "Your bathroom never mixes genders. Is it correct?"</b></summary>

**L5:** "Yes, exclusion holds."

**Why it fails:** correctness includes progress. A busy group keeps the room (16 ms worst-case waits here, and unbounded in principle).

**L7 defence:** "Admit the same group only while nobody from the other group waits, so the waiting group is served at the next drain. Verify with independent counters, and accept lower throughput for bounded waits."
</details>

<details>
<summary><b>Q3 ⚡ "Your H2O works with one thread per atom. Use a thread pool instead."</b></summary>

**L5:** "Split the atoms evenly across the threads."

**Why it fails:** the last H thread can be left needing two H atoms at once while it sits at the barrier with one: deadlock. A thread dump shows two parties waiting for a third.

**L7 defence:** "Claim atoms dynamically from a shared counter, so any free thread supplies the next one. Then the only way to stall is a global count mismatch, which is checked up front."
</details>

## 10. Checklist and references

- [ ] Name the property (deadlock freedom, fairness, composition, order) before the primitive.
- [ ] Prevent deadlock by ordering or by limiting contenders; random backoff only as a fallback.
- [ ] Check invariants independently of the mechanism; measure worst-case waits.
- [ ] Dynamic work claiming when progress needs several units at once.
- [ ] Count wake-ups; measure their cost on the target runtime.

**References:**
- E. W. Dijkstra, *Hierarchical ordering of sequential processes* (dining philosophers, 1971). <https://www.cs.utexas.edu/users/EWD/ewd03xx/EWD310.PDF>
- Allen B. Downey, *The Little Book of Semaphores* (unisex bathroom, H2O, barriers). <https://greenteapress.com/wp/semaphores/>
- Java `CyclicBarrier` and `Semaphore`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/CyclicBarrier.html>
- In this KB: [P13 Lock ordering in a ledger](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md) · [P6 Spin gates vs barriers in tests](../04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/01-problem-06-movie-ticket-booking-bookmyshow-seat-lock-and-deadlock-free.md)
