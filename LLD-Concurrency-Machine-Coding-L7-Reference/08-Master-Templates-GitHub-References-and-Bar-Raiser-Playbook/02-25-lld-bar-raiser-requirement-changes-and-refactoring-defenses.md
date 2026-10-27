# 08.2 · 25 Bar-Raiser Requirement Changes, and How to Absorb Each in Five Minutes

> **Folder 08 · File 2 of 3.** Around minute 45 the interviewer changes the requirements. They are not testing whether you predicted the change. They are testing:
> - whether your design has a **seam** where the change lands;
> - how big the **blast radius** is;
> - whether you **re-establish the invariants** afterwards (re-run the stress test).
>
> This file lists 25 changes that recur across the twenty problems. They are grouped by the kind of pressure they apply, each with the seam that makes it cheap and the trap that makes it expensive. Then come three worked defenses with short paired Java/C++ snippets, and a five-step script for answering any change.
>
> These are original formulations drawn from the KB's own problems, not recalled interview questions.

---

## 1. The 25 changes

### A. Policy changes: "do it differently"

| # | Change | Hits | Seam that makes it 5 minutes | Trap |
|---|---|---|---|---|
| 1 | "Use LFU instead of LRU" (or W-TinyLFU) | P1 | An eviction **policy** behind an interface, fed by the same access events (Caffeine's policy plane) | Eviction logic inlined in `get`/`put` |
| 2 | "Charge by the hour with a daily cap, plus weekend rates" | P7, P15 | Pricing as a composable **decorator/specification chain** over a base strategy ([02.2](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md)) | `if` ladders in the checkout method |
| 3 | "Switch the rate limiter to sliding window" | P2 | `RateLimiter` interface; state per key in one CAS-able value | State spread over several maps |
| 4 | "Elevator: optimise wait time, not travel" | P8 | Dispatch **strategy** scoring requests; the simulation harness compares strategies | Strategy coupled to car state mutation |
| 5 | "Coupons can't stack with sales" | P15 | Exclusive **groups** + best-combination search | Promotions applied in list order |

### B. Cardinality changes: "one becomes many"

| # | Change | Hits | Seam | Trap |
|---|---|---|---|---|
| 6 | "Book several seats / rooms atomically" | P6, P10 | Multi-key operation = **sorted lock acquisition** of the same per-key locks | Locking in request order (deadlock) |
| 7 | "Multi-currency" | P11, P13 | `Money(amount, currency)` value type; per-currency balances | `double` amounts, a currency field checked "later" |
| 8 | "Many symbols / tenants" | P12, P4 | **Shard** by key: one single-writer engine per symbol or partition | One global engine with a symbol map |
| 9 | "Recurring bookings" | P10 | An RRULE expanded in the **zone**, booked all-or-nothing as a series | Instant + 7 days (DST bug) |
| 10 | "Consumer groups" | P4 | Offsets per (group, partition) with generation fencing | Offsets per consumer |

### C. Concurrency changes: "more threads, more writers"

| # | Change | Hits | Seam | Trap |
|---|---|---|---|---|
| 11 | "It must be thread-safe now" | any | Named **atomicity units** already single critical sections; add a stress test | Sprinkling `synchronized` / `ConcurrentHashMap` |
| 12 | "1M requests/s on one hot key" | P15, P2 | **Striped** CAS buckets with a collapse slow path | One `AtomicLong` (a CPU hot row) |
| 13 | "Readers must never see a half-applied update" | P11, P16 | Consistency boundary = one **immutable snapshot** (or MVCC) | Per-key atomic maps |
| 14 | "Two clients may submit the same action at once" | P19, P13 | Expected-version / expected-ply token checked inside the critical section | Validate, unlock, then apply |
| 15 | "Logging must not slow the hot path" | P17 | **MPSC ring** of pooled events + a consumer; an explicit drop/block policy | Synchronous appenders under a lock |

### D. Durability and failure: "it must survive"

| # | Change | Hits | Seam | Trap |
|---|---|---|---|---|
| 16 | "Clients retry on timeout" | P13, P15, 08.1 | **Idempotency key** → claim, execute, record; the ledger's uniqueness constraint as the final guard | Check-then-insert dedup |
| 17 | "The process can crash mid-operation" | P20, P13 | A **journal** of state transitions; resume recomputes from it | In-memory progress only |
| 18 | "A step can fail after others succeeded" | P14, P20 | A **saga**: compensations in reverse order; the irreversible step last | Try/catch "rollback" of fields |
| 19 | "A paused node comes back after its lease expired" | P6, P13, P4 | **Fencing tokens** / generations checked at commit | Trusting lease timeouts |
| 20 | "Persist it in Postgres" | P13, P16 | The atomicity unit maps to a transaction: `UNIQUE`, `SELECT … FOR UPDATE` ordered by id, `ON CONFLICT` | ORM calls that read-modify-write without locks |

### E. Time, scale and operations

| # | Change | Hits | Seam | Trap |
|---|---|---|---|---|
| 21 | "Add TTL / expiry" | P1, P6, P15 | An injected **clock**; expiry decided by the same CAS as the competing action | `System.currentTimeMillis()` in logic; sleeping tests |
| 22 | "Schedule a million timers" | P3 | A **hierarchical timing wheel** (O(1) insert) instead of a heap | `DelayQueue` with millions of entries |
| 23 | "Show live counts on a dashboard" | P15, P16 | Read the snapshot / sum the stripes; approximate is fine with bands | Locking everything to count |
| 24 | "Audit every change" | P13, P17, P20 | Events emitted from the single place state changes (journal / event stream) | Logging from every caller |
| 25 | "It must work across 3 nodes" | P6, P13, P16 | Move the atomicity unit into the store's **conditional write** (version check / CAS) | Local locks pretending to be distributed |

## 2. Three worked defenses

### 2.1 A new policy without touching the service (#1, #2, #4)

The seam is an interface the service already depends on. The change is a new implementation and one line of wiring. The interviewer sees a diff of one new file.

```java
interface Pricing { long priceCents(Stay s); }
record Hourly(long perHour) implements Pricing { public long priceCents(Stay s) { return s.hours() * perHour; } }
record DailyCap(Pricing inner, long capPerDay) implements Pricing {           // decorator: composes, doesn't edit
    public long priceCents(Stay s) { return Math.min(inner.priceCents(s), s.days() * capPerDay); }
}
// wiring: new ParkingService(new DailyCap(new Hourly(300), 2_000))
```

```cpp
using Pricing = std::function<i64(const Stay&)>;
Pricing hourly(i64 per_hour) { return [=](const Stay& s) { return s.hours * per_hour; }; }
Pricing daily_cap(Pricing inner, i64 cap) {                                     // decorator: composes, doesn't edit
    return [=](const Stay& s) { return std::min(inner(s), s.days * cap); };
}
// wiring: ParkingService svc(daily_cap(hourly(300), 2'000));
```

### 2.2 A new outcome, and the compiler is the reviewer (#11, #16, any "new state")

Adding `Waitlisted` to a sealed outcome makes **every** exhaustive `switch` that doesn't handle it a compile error. In C++, `std::visit` with an `overloaded` set that lacks the new alternative fails to compile. Either way, the build lists every call site that must decide what `Waitlisted` means. You can't forget one.

```java
sealed interface Outcome permits Granted, Rejected, Waitlisted {}
record Waitlisted(RequestId request, int position) implements Outcome {}
String show(Outcome o) {
    return switch (o) {                                 // without the Waitlisted case: "the switch statement does not cover all possible input values"
        case Granted g -> "granted";
        case Rejected r -> "rejected: " + r.reason();
        case Waitlisted w -> "waitlisted #" + w.position();
    };
}
```

```cpp
struct Waitlisted { RequestId request; int position; };
using Outcome = std::variant<Granted, Rejected, Waitlisted>;
std::string show(const Outcome& o) {
    return std::visit(overloaded{                       // without the Waitlisted lambda: no matching call, compile error
        [](const Granted&) { return std::string("granted"); },
        [](const Rejected& r) { return std::string("rejected: ") + name(r.reason); },
        [](const Waitlisted& w) { return std::format("waitlisted #{}", w.position); },
    }, o);
}
```

### 2.3 From one process to three nodes (#20, #25)

The local design is "check + decrement under the resource's lock". Across nodes, that atomicity unit **moves into the store** as a conditional write. The service logic stays the same; only the adapter changes.

```java
// The store holds (available, version). The write succeeds only if nobody changed the row since we read it.
boolean tryReserve(ResourceId id, int q) {
    for (int attempt = 0; attempt < 5; attempt++) {
        Row r = store.read(id);                                       // SELECT available, version
        if (r.available() < q) return false;
        if (store.compareAndSet(id, r.version(), r.available() - q))  // UPDATE … SET available = ?, version = version + 1
            return true;                                              //   WHERE id = ? AND version = ?
    }
    return false;                                                     // contended: surface it, don't spin forever
}
```

```cpp
bool try_reserve(Store& store, const ResourceId& id, int q) {
    for (int attempt = 0; attempt < 5; ++attempt) {
        const Row r = store.read(id);
        if (r.available < q) return false;
        if (store.compare_and_set(id, r.version, r.available - q)) return true;  // version-checked conditional write
    }
    return false;
}
```

## 3. The five-step defense script

For **any** change, in this order:
1. **Restate the invariant that must survive.** "We still never oversell; a retry still returns the original outcome."
2. **Name the seam.** "Pricing is behind `Pricing`; this is a decorator." Or, if there's none: "This crosses my atomicity unit, so it's a design change, not a patch. Here's why."
3. **Show the diff size.** One new type plus one wiring line is a good answer. Edits in five places means the seam was missing; say so and extract it.
4. **Re-run the harness** and point at the invariant line. Adding a test for the new behaviour is a bonus.
5. **Name the residual risk.** "Best-combination search is exponential in groups; past ~20 I'd switch to branch-and-bound."

## 4. Checklist and references

- [ ] Every contention point has a named atomicity unit, so concurrency changes are local.
- [ ] Policies are behind interfaces; outcomes and states are sealed (compiler-enforced handling).
- [ ] Time is injected; retries are idempotent; multi-step work is journaled or saga-shaped.
- [ ] The answer to a change starts with the invariant and ends with the harness.

**References:**
- Michael Feathers, *Working Effectively with Legacy Code* (seams).
- Martin Fowler, *Refactoring*, 2nd ed.
- In this KB: [08.1 Blueprint](01-60-minute-machine-coding-execution-blueprint-and-code-skeletons.md) · [02.1 Sealed state machines](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [02.2 Strategy, decorator, specification](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md) · [P13 Idempotency and fencing](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md)
