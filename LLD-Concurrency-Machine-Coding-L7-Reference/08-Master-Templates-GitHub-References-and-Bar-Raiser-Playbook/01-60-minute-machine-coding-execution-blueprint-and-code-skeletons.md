# 08.1 · The 60-Minute Machine-Coding Blueprint and a Skeleton That Already Passes Its Own Stress Test

> **Folder 08 · File 1 of 3.** Twenty problems in this KB share one shape:
> 1. a closed set of domain types;
> 2. one or two **contention points** with a named **atomicity unit**;
> 3. a service that validates purely, then acts in one critical section (or one CAS, or on one writer thread);
> 4. a harness that starts threads together, captures failures, and checks invariants.
>
> This file turns that shape into a minute-by-minute plan and a **compilable, self-testing skeleton** in Java and C++. In an interview you start from structure, not from a blank file.
>
> **Listing pair 08.1:** `MachineCodingSkeleton.java` / `machine_coding_skeleton.cpp`. Section 1 is byte-identical in Java and GCC; the stress line is one measured run.

---

## 1. The plan, minute by minute

| Minutes | What you produce | What you say out loud | Signals it sends (see [01.1](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md)) |
|---|---|---|---|
| **0–5** Clarify | 5–8 bullet requirements, **non-goals**, scale and concurrency assumptions, what "done" means | "Who calls this concurrently? What must never happen? What's a retry?" | Scoping; invariants before code |
| **5–12** Types | Value objects (validated constructors), a sealed outcome set, state as types | "An X with Y can't be constructed, so it can't be stored" | Illegal states unrepresentable |
| **12–18** Concurrency model | The contention points; the atomicity unit for each; the mechanism (per-key lock / ordered locks / CAS / single writer); lock order | "Threads collide on Z; check and act happen in one critical section; locks are taken in id order" | The L6/L7 differentiator: named atomicity units |
| **18–40** Code | Domain → service → in-memory adapter, compiling at every step; functional checks in `main` | Narrate trade-offs as you choose them | Working code, small steps, no dead abstractions |
| **40–50** Prove it | Stress harness: N threads, a start gate, duplicates or races on purpose, invariant checks; run it | "If this were wrong, this number would be non-zero" | Evidence over assertion |
| **50–57** Evolve | One extension seam exercised (a new policy, a new outcome); the L7 path (scale, durability) | "To shard this, I'd…; for crash safety, a journal…" | Design for change without over-building |
| **57–60** Close | A three-sentence summary: guarantees, known limits, next steps | "It never oversells; it's per-key contended; next I'd add…" | Ownership of trade-offs |

**Rules that save the hour:**
- **Compile every ~5 minutes.** A skeleton that already runs is worth more than an elegant design that doesn't.
- **One mechanism per contention point.** Don't mix a lock and a CAS on the same state.
- **Tests live in `main`** with a printed `SELF-TEST OK`. The interviewer can see them run.
- **Write the stress test before you "finish".** Every problem in this KB found at least one bug that way, including in this KB's own listings (P9 TimSort, P10 `shared_mutex`, P13 boxed `Long`, P20 the cancel hang, 07.2 the livelock).

## 2. The skeleton

The listing is a generic **reservation service**: take *q* units of resource *R* for request *I*. It is the core of P6 (seats), P7 (parking), P13 (accounts) and P15 (inventory) with the domain stripped away. Rename the types and keep the structure.

| Piece | What it encodes | Where it reappears |
|---|---|---|
| `ResourceId` / `RequestId` value types | Validation in the constructor | Every problem |
| `sealed Outcome permits Granted, Rejected(Reason)` / `std::variant` | A closed, exhaustively handled result set | P6, P11, P13, P16 |
| Injected `Clock` / `std::function<sys_seconds()>` | Deterministic time in tests | P1–P3, P6, P13, P15 |
| Per-resource lock, check + decrement in one critical section | The atomicity unit is one key | P6, P7, P10, P13 |
| Idempotent `reserve(request…)`: the first outcome wins; a duplicate that also acquired gives it back | Retries are safe | P13, P15 |
| `stress(threads, body)`: start gate, failure capture, always-terminate | Evidence | Every problem |

**Measured:** 16 threads × 1,000 requests for 1 unit of a 5,000-unit resource, **each request sent twice**:
- 5,000 granted, 0 left;
- every duplicate got the same outcome as the original;
- 34 ms (Java), 55 ms (GCC), 60 ms (Clang).

**How the idempotency works under races:**
1. Fast path: a known request returns the stored outcome.
2. Otherwise `decide()` runs.
3. `putIfAbsent` / `try_emplace` lets the **first** outcome win.
4. A concurrent duplicate that *also* reserved gives its units back.

This is the in-memory version of P13's "claim then execute". In a database, the uniqueness constraint plays step 3's role.

## 3. Java 21 skeleton

```java
// MachineCodingSkeleton.java - 08.1: the 60-minute starter: types first, injected clock, per-key locks, idempotency, stress harness
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;

public final class MachineCodingSkeleton {

    // ---- minutes 5-12: the domain as types. Value objects validate in their constructor; outcomes are a closed set.

    record ResourceId(String value) {
        ResourceId {
            if (value == null || value.isBlank()) throw new IllegalArgumentException("resource id required");
        }
    }

    record RequestId(String value) {}

    enum Reason { UNKNOWN_RESOURCE, INSUFFICIENT_CAPACITY, INVALID_QUANTITY }

    sealed interface Outcome permits Granted, Rejected {}
    record Granted(RequestId request, ResourceId resource, int quantity, Instant at) implements Outcome {}
    record Rejected(RequestId request, Reason reason) implements Outcome {}

    // ---- minutes 12-18: the contention point is one resource's capacity. Atomicity unit: check + decrement of ONE key.

    /** In-memory adapter. A per-resource lock: contention is per key, never global. Swap for striping/CAS if needed. */
    static final class Inventory {
        static final class Slot {
            final ReentrantLock lock = new ReentrantLock();
            int available;                                             // guarded by lock

            Slot(int capacity) {
                available = capacity;
            }
        }

        final Map<ResourceId, Slot> slots = new ConcurrentHashMap<>();

        void add(ResourceId id, int capacity) {
            slots.put(id, new Slot(capacity));
        }

        int available(ResourceId id) {
            Slot s = slots.get(id);
            s.lock.lock();
            try {
                return s.available;
            } finally {
                s.lock.unlock();
            }
        }
    }

    // ---- minutes 18-40: the service. Pure validation first, then one critical section, then publish the outcome.

    static final class ReservationService {
        final Inventory inventory;
        final Clock clock;                                             // injected: tests control time
        final ConcurrentHashMap<RequestId, Outcome> outcomes = new ConcurrentHashMap<>();   // idempotency: one outcome per request

        ReservationService(Inventory inventory, Clock clock) {
            this.inventory = inventory;
            this.clock = clock;
        }

        Outcome reserve(RequestId request, ResourceId resource, int quantity) {
            Outcome prior = outcomes.get(request);
            if (prior != null) return prior;                           // a retry gets the original answer
            Outcome result = decide(request, resource, quantity);
            Outcome raced = outcomes.putIfAbsent(request, result);     // a concurrent duplicate keeps the first outcome
            if (raced != null && result instanceof Granted g) release(g);   // ...and gives back what it took
            return raced != null ? raced : result;
        }

        private Outcome decide(RequestId request, ResourceId resource, int quantity) {
            if (quantity <= 0) return new Rejected(request, Reason.INVALID_QUANTITY);
            Inventory.Slot slot = inventory.slots.get(resource);
            if (slot == null) return new Rejected(request, Reason.UNKNOWN_RESOURCE);
            slot.lock.lock();
            try {                                                      // check and act in ONE critical section
                if (slot.available < quantity) return new Rejected(request, Reason.INSUFFICIENT_CAPACITY);
                slot.available -= quantity;
                return new Granted(request, resource, quantity, clock.instant());
            } finally {
                slot.lock.unlock();
            }
        }

        private void release(Granted g) {
            Inventory.Slot slot = inventory.slots.get(g.resource());
            slot.lock.lock();
            try {
                slot.available += g.quantity();
            } finally {
                slot.lock.unlock();
            }
        }
    }

    // ---- minutes 40-50: the reusable stress harness. Start together, capture failures, always reach the end, check invariants.

    interface Body {
        void run(int thread) throws Exception;
    }

    static long stress(int threads, Body body) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1);
        CountDownLatch done = new CountDownLatch(threads);
        AtomicReference<Exception> failure = new AtomicReference<>();
        for (int t = 0; t < threads; t++) {
            final int id = t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    body.run(id);
                } catch (Exception e) {
                    failure.compareAndSet(null, e);                    // a dead worker must not hang the harness
                } finally {
                    done.countDown();
                }
            });
        }
        start.await();
        long t0 = System.nanoTime();
        done.await();
        if (failure.get() != null) throw new IllegalStateException(failure.get());
        return (System.nanoTime() - t0) / 1_000_000;
    }

    static final class FixedClock extends Clock {
        final Instant now;

        FixedClock(Instant now) {
            this.now = now;
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    static String show(Outcome o) {
        return switch (o) {
            case Granted g -> "Granted " + g.quantity() + " of " + g.resource().value() + " at " + g.at();
            case Rejected r -> "Rejected: " + r.reason();
        };
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Functional checks (fixed clock) ==");
        Inventory inv = new Inventory();
        ResourceId room = new ResourceId("room-1");
        inv.add(room, 10);
        ReservationService svc = new ReservationService(inv, new FixedClock(Instant.parse("2026-10-28T09:00:00Z")));
        List<String> lines = new ArrayList<>();
        lines.add("reserve 4            -> " + show(svc.reserve(new RequestId("r1"), room, 4)));
        lines.add("retry the same r1    -> " + show(svc.reserve(new RequestId("r1"), room, 4)) + " (available still " + inv.available(room) + ")");
        lines.add("reserve 7            -> " + show(svc.reserve(new RequestId("r2"), room, 7)));
        lines.add("reserve 0            -> " + show(svc.reserve(new RequestId("r3"), room, 0)));
        lines.add("unknown resource     -> " + show(svc.reserve(new RequestId("r4"), new ResourceId("nope"), 1)));
        for (String l : lines) System.out.println("  " + l);

        System.out.println("== 2. Stress: 16 threads x 1,000 requests for 1 unit of a 5,000-unit resource, every request sent twice ==");
        Inventory big = new Inventory();
        ResourceId hall = new ResourceId("hall");
        big.add(hall, 5_000);
        ReservationService s2 = new ReservationService(big, Clock.systemUTC());
        LongAdder granted = new LongAdder();
        long ms = stress(16, t -> {
            for (int i = 0; i < 1_000; i++) {
                RequestId id = new RequestId("t" + t + "-" + i);
                Outcome a = s2.reserve(id, hall, 1), b = s2.reserve(id, hall, 1);   // the duplicate must not double-book
                if (!a.equals(b)) throw new IllegalStateException("retry changed the outcome of " + id.value());
                if (a instanceof Granted) granted.increment();
            }
        });
        long left = big.available(hall);
        System.out.printf("  granted %d of 16000 | available %d | granted + available == 5000: %b | %d ms%n", granted.sum(), left,
                granted.sum() + left == 5_000, ms);

        boolean ok = lines.get(0).startsWith("reserve 4            -> Granted 4") && lines.get(1).contains("available still 6")
                && lines.get(2).endsWith("INSUFFICIENT_CAPACITY") && lines.get(3).endsWith("INVALID_QUANTITY") && lines.get(4).endsWith("UNKNOWN_RESOURCE")
                && granted.sum() == 5_000 && left == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output:**

```text
== 1. Functional checks (fixed clock) ==
  reserve 4            -> Granted 4 of room-1 at 2026-10-28T09:00:00Z
  retry the same r1    -> Granted 4 of room-1 at 2026-10-28T09:00:00Z (available still 6)
  reserve 7            -> Rejected: INSUFFICIENT_CAPACITY
  reserve 0            -> Rejected: INVALID_QUANTITY
  unknown resource     -> Rejected: UNKNOWN_RESOURCE
== 2. Stress: 16 threads x 1,000 requests for 1 unit of a 5,000-unit resource, every request sent twice ==
  granted 5000 of 16000 | available 0 | granted + available == 5000: true | 34 ms
SELF-TEST OK
```

## 4. C++23 skeleton

```cpp
// machine_coding_skeleton.cpp - 08.1: the 60-minute starter: types first, injected clock, per-key locks, idempotency, stress harness
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <format>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using namespace std::chrono;

// ---- minutes 5-12: the domain as types. Value objects validate on construction; outcomes are a closed set.

class ResourceId {
    std::string v_;

public:
    explicit ResourceId(std::string v) : v_(std::move(v)) {
        if (v_.empty()) throw std::invalid_argument("resource id required");
    }
    const std::string& value() const { return v_; }
    auto operator<=>(const ResourceId&) const = default;
};

struct RequestId {
    std::string value;
    auto operator<=>(const RequestId&) const = default;
};

enum class Reason { UnknownResource, InsufficientCapacity, InvalidQuantity };
constexpr const char* name(Reason r) {
    switch (r) {
        case Reason::UnknownResource: return "UNKNOWN_RESOURCE";
        case Reason::InsufficientCapacity: return "INSUFFICIENT_CAPACITY";
        case Reason::InvalidQuantity: return "INVALID_QUANTITY";
    }
    return "?";
}

struct Granted { RequestId request; ResourceId resource; int quantity; sys_seconds at; bool operator==(const Granted&) const = default; };
struct Rejected { RequestId request; Reason reason; bool operator==(const Rejected&) const = default; };
using Outcome = std::variant<Granted, Rejected>;

// ---- minutes 12-18: the contention point is one resource's capacity. Atomicity unit: check + decrement of ONE key.

/** In-memory adapter. A per-resource lock: contention is per key, never global. Swap for striping/CAS if needed. */
class Inventory {
public:
    struct Slot {
        std::mutex lock;
        int available;  // guarded by lock
        explicit Slot(int capacity) : available(capacity) { std::scoped_lock warm(lock); }
    };
    void add(const ResourceId& id, int capacity) { slots_.emplace(id, std::make_unique<Slot>(capacity)); }  // setup only, before threads
    Slot* find(const ResourceId& id) const {
        const auto it = slots_.find(id);
        return it == slots_.end() ? nullptr : it->second.get();
    }
    int available(const ResourceId& id) const {
        Slot* s = find(id);
        std::scoped_lock l(s->lock);
        return s->available;
    }

private:
    std::map<ResourceId, std::unique_ptr<Slot>> slots_;  // fixed after setup: lookups need no lock
};

using Clock = std::function<sys_seconds()>;  // injected: tests control time

// ---- minutes 18-40: the service. Pure validation first, then one critical section, then publish the outcome.

class ReservationService {
    Inventory& inventory_;
    Clock clock_;
    std::mutex om_;
    std::map<RequestId, Outcome> outcomes_;  // idempotency: one outcome per request (a striped map scales it, see P13)

    Outcome decide(const RequestId& request, const ResourceId& resource, int quantity) {
        if (quantity <= 0) return Rejected{request, Reason::InvalidQuantity};
        Inventory::Slot* slot = inventory_.find(resource);
        if (!slot) return Rejected{request, Reason::UnknownResource};
        std::scoped_lock l(slot->lock);  // check and act in ONE critical section
        if (slot->available < quantity) return Rejected{request, Reason::InsufficientCapacity};
        slot->available -= quantity;
        return Granted{request, resource, quantity, clock_()};
    }
    void release(const Granted& g) {
        Inventory::Slot* slot = inventory_.find(g.resource);
        std::scoped_lock l(slot->lock);
        slot->available += g.quantity;
    }

public:
    ReservationService(Inventory& inv, Clock clock) : inventory_(inv), clock_(std::move(clock)) { std::scoped_lock warm(om_); }

    Outcome reserve(const RequestId& request, const ResourceId& resource, int quantity) {
        {
            std::scoped_lock l(om_);
            if (const auto it = outcomes_.find(request); it != outcomes_.end()) return it->second;  // a retry gets the original answer
        }
        const Outcome result = decide(request, resource, quantity);
        std::scoped_lock l(om_);
        const auto [it, inserted] = outcomes_.try_emplace(request, result);  // a concurrent duplicate keeps the first outcome...
        if (!inserted)
            if (const auto* g = std::get_if<Granted>(&result)) release(*g);  // ...and gives back what it took
        return it->second;
    }
};

// ---- minutes 40-50: the reusable stress harness. Start together, capture failures, always reach the end, check invariants.

template <class F>
i64 stress(int threads, F body) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::exception_ptr failure;
    std::mutex fm;
    const auto t0 = steady_clock::now();
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}  // a spin gate WITH a ready count (P6): threads really overlap
                try {
                    body(t);
                } catch (...) {
                    std::scoped_lock l(fm);  // a dead worker must not hang the harness
                    if (!failure) failure = std::current_exception();
                }
            });
        while (ready.load() < threads) {}
        go.store(true, std::memory_order_release);
    }
    if (failure) std::rethrow_exception(failure);
    return duration_cast<milliseconds>(steady_clock::now() - t0).count();
}

std::string show(const Outcome& o) {
    if (const auto* g = std::get_if<Granted>(&o)) return std::format("Granted {} of {} at {:%FT%TZ}", g->quantity, g->resource.value(), g->at);
    return std::string("Rejected: ") + name(std::get<Rejected>(o).reason);
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Functional checks (fixed clock) ==");
    Inventory inv;
    const ResourceId room("room-1");
    inv.add(room, 10);
    const sys_seconds fixed = sys_days(2026y / October / 28) + 9h;
    ReservationService svc(inv, [fixed] { return fixed; });
    std::vector<std::string> lines;
    lines.push_back("reserve 4            -> " + show(svc.reserve({"r1"}, room, 4)));
    lines.push_back("retry the same r1    -> " + show(svc.reserve({"r1"}, room, 4)) + std::format(" (available still {})", inv.available(room)));
    lines.push_back("reserve 7            -> " + show(svc.reserve({"r2"}, room, 7)));
    lines.push_back("reserve 0            -> " + show(svc.reserve({"r3"}, room, 0)));
    lines.push_back("unknown resource     -> " + show(svc.reserve({"r4"}, ResourceId("nope"), 1)));
    for (const auto& l : lines) std::println("  {}", l);

    std::println("== 2. Stress: 16 threads x 1,000 requests for 1 unit of a 5,000-unit resource, every request sent twice ==");
    Inventory big;
    const ResourceId hall("hall");
    big.add(hall, 5'000);
    ReservationService s2(big, [] { return floor<seconds>(system_clock::now()); });
    std::atomic<i64> granted{0};
    const i64 ms = stress(16, [&](int t) {
        for (int i = 0; i < 1'000; ++i) {
            const RequestId id{std::format("t{}-{}", t, i)};
            const Outcome a = s2.reserve(id, hall, 1), b = s2.reserve(id, hall, 1);  // the duplicate must not double-book
            if (!(a == b)) throw std::logic_error("retry changed the outcome of " + id.value);
            if (std::holds_alternative<Granted>(a)) granted.fetch_add(1);
        }
    });
    const i64 left = big.available(hall);
    std::println("  granted {} of 16000 | available {} | granted + available == 5000: {} | {} ms", granted.load(), left, granted.load() + left == 5'000, ms);

    const bool ok = lines[0].starts_with("reserve 4            -> Granted 4") && lines[1].find("available still 6") != std::string::npos &&
                    lines[2].ends_with("INSUFFICIENT_CAPACITY") && lines[3].ends_with("INVALID_QUANTITY") && lines[4].ends_with("UNKNOWN_RESOURCE") &&
                    granted.load() == 5'000 && left == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Functional checks (fixed clock) ==
  reserve 4            -> Granted 4 of room-1 at 2026-10-28T09:00:00Z
  retry the same r1    -> Granted 4 of room-1 at 2026-10-28T09:00:00Z (available still 6)
  reserve 7            -> Rejected: INSUFFICIENT_CAPACITY
  reserve 0            -> Rejected: INVALID_QUANTITY
  unknown resource     -> Rejected: UNKNOWN_RESOURCE
== 2. Stress: 16 threads x 1,000 requests for 1 unit of a 5,000-unit resource, every request sent twice ==
  granted 5000 of 16000 | available 0 | granted + available == 5000: true | 55 ms
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Functional checks (fixed clock) ==
  reserve 4            -> Granted 4 of room-1 at 2026-10-28T09:00:00Z
  retry the same r1    -> Granted 4 of room-1 at 2026-10-28T09:00:00Z (available still 6)
  reserve 7            -> Rejected: INSUFFICIENT_CAPACITY
  reserve 0            -> Rejected: INVALID_QUANTITY
  unknown resource     -> Rejected: UNKNOWN_RESOURCE
== 2. Stress: 16 threads x 1,000 requests for 1 unit of a 5,000-unit resource, every request sent twice ==
  granted 5000 of 16000 | available 0 | granted + available == 5000: true | 60 ms
SELF-TEST OK
```

## 5. Choosing the mechanism at minute 15

| Situation | Mechanism | KB example |
|---|---|---|
| Independent keys, short critical sections | Per-key lock (or CHM `compute` for tiny updates) | P6 seats, this skeleton |
| An operation spans several keys | Ordered locks (sort ids), or `std::scoped_lock` | P13 transfers, P10 multi-room |
| One hot counter | Striped CAS buckets; never `LongAdder` for conditional decrements | P15 |
| Totally ordered semantics (priority, sequence) | Single writer + MPSC ring | P12, P17 |
| Read-mostly shared state | Immutable snapshot + CAS, or optimistic reads | P11, 07.1 |
| Readers must see a consistent multi-key state | One snapshot per consistency boundary (group, table) | P11, P16 |
| Many concurrent blocking waits | Virtual threads (Java) / coroutines (C++) | 07.3 |

## 6. Anti-patterns that cost the round

| Anti-pattern | Why it costs | Instead |
|---|---|---|
| Twenty interfaces in the first 15 minutes | No running code at minute 40 | Concrete types first; extract a seam when the second implementation appears |
| `synchronized` on every service method | Correct but serial; no L6 signal | Name the contention point; lock per key |
| `ConcurrentHashMap` "so it's thread-safe" | `get` then `put` is still a race | Atomic per-key operations or a lock around check + act |
| No concurrency test | "Should be fine" is not evidence | Stress harness with invariants |
| `Thread.sleep` to "fix" a race in a test | Hides the bug, slows the suite | A start gate and deliberate collisions |
| Wall-clock time in logic | Untestable expiry | An injected clock |

## 7. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "You have 60 minutes. Where do you start?"</b></summary>

**L5:** "With the classes: Parking lot, Floor, Spot…"

**Why it fails:** nouns without invariants or concurrency. Minute 45 arrives without a test.

**L7 defence:** "Five minutes of requirements and non-goals; types that make bad states unrepresentable; then the contention points and their atomicity units, said out loud. Code in compiling steps from a skeleton like this, and a stress test before I call it done."
</details>

<details>
<summary><b>Q2 ⚡ "How do you know it's thread-safe?"</b></summary>

**L5:** "I used concurrent collections."

**Why it fails:** collections make single operations atomic, not your invariant.

**L7 defence:** "I named the atomicity unit (check + decrement of one resource) and it's one critical section. And here's the test: 16 threads, every request duplicated, and granted + available stays exactly 5,000 with no duplicate changing its answer."
</details>

## 8. Checklist and references

- [ ] Requirements, non-goals and invariants written before code.
- [ ] Types: validated value objects, sealed outcomes, injected clock.
- [ ] Contention points and atomicity units named; mechanism chosen per point.
- [ ] Code compiles at every step; functional checks in `main`.
- [ ] Stress test with duplicates/collisions and invariant checks.
- [ ] One extension seam exercised; L7 evolution described.

**References:**
- In this KB: [01.1 Rubric](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md) · [01.3 Primitives and the stress harness](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [08.2 Requirement changes](02-25-lld-bar-raiser-requirement-changes-and-refactoring-defenses.md)
- Brian Goetz et al., *Java Concurrency in Practice* (atomicity units, invariants, testing concurrent programs).
- Anthony Williams, *C++ Concurrency in Action*, 2nd ed.
