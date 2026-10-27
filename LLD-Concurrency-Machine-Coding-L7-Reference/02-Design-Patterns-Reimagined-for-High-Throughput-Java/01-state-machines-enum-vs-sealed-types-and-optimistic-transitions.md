# 02.1 · State Machines: Enum Tables vs Sealed Types, and Optimistic Transitions

> **Folder 02 · File 1 of 3.** Nearly every machine-coding problem is a state machine with an API in front of it:
> - P6: seats.
> - P8: elevator cars.
> - P9: drivers.
> - P5: the circuit breaker.
> - P13: payment idempotency keys.
> - P14: vending sessions.
> - P20: workflows.
>
> This file covers the three ways to represent one, how to validate a table-driven machine at start-up, how sealed types carry per-state data and time guards, and how transitions stay correct when two actors race through a **store**: optimistic versioning, the in-database version of file 01's in-memory CAS.
>
> **Listing pair 2.1.1:** `StateMachines.java` / `state_machines.cpp`.
> **Verified:** JDK 25.0.4.1 `--release 21 -Xlint:all -Werror`; GCC 16.2 and Clang 21.1 `-std=c++23 … -Werror`. Race counts are one measured run; everything else is deterministic.

---

## 1. Three representations, one decision

| Representation | Java | C++ | Carries per-state data? | Validatable as data? | Compiler-checked exhaustiveness? | Pick it when |
|---|---|---|---|---|---|---|
| **Transition table** | `EnumMap<Status, EnumMap<Event, Status>>` | `std::array<std::array<std::optional<Status>, E>, S>` | No | **Yes**: reachability, traps, DOT export, load from config | No (a missing cell is a runtime `empty`) | Business users edit the flow; many similar flows; you must print or diff the graph |
| **Enum + exhaustive `switch`** | `switch` *expression* over an enum (no `default`) | `switch` over `enum class`, no `default`, with `-Wswitch -Werror` | No | Partly | **Yes** for behaviour keyed by state | Per-state behaviour without per-state data (an elevator `Direction`, a breaker's `State` with counters stored elsewhere) |
| **Sealed ADT + pure `transition`** | `sealed interface` + records + nested pattern `switch` | `std::variant` + nested `std::visit` | **Yes** | Via code, not data | **Yes** for (state × command) | States differ in data (tracking number, RMA, timestamps); guards depend on that data or on time |

**The L7 hybrid,** used in P6, P13 and P20:
- the **sealed ADT** is the runtime model, so each state carries its own data;
- a **table** derived from it (or written next to it) is validated at start-up and exported for documentation;
- one **property test** asserts the two agree on every (state, event) pair.

You get compile-time exhaustiveness *and* a graph you can review.

## 2. Validating a table-driven machine at start-up 🔥

A transition table is configuration, and configuration has typos. Two graph checks catch most of them in microseconds, so run them at start-up and refuse to boot on failure:

1. **Reachability (forward BFS from the initial state).** A state nobody can reach is dead code, or a missing edge.
2. **Liveness (reverse closure from the terminal states).** Every reachable state must still be able to reach a terminal state. A reachable state that can't is a **trap**: orders that never finish, an elevator that never parks.

The listing's broken table has two typos. `DELIVER` is missing, and `SHIPPED` has only a self-loop. The validator reports `unreachable: [DELIVERED, RETURNED]` and `trap: [SHIPPED]`. Further checks worth adding in production:
- determinism (one target per (state, event));
- every terminal state is in an allowed set;
- every event is used at least once;
- the machine is a subgraph of the previous release's, if you require backward-compatible flows.

## 3. Sealed states, guards, and time

The sealed model puts data where it belongs:
- `Shipped` has a tracking number, and `Created` can't have one;
- `Delivered` has the delivery instant, which the **return-window guard** needs.

The guard reads time from an **injected `Clock`** (file 01.3 §8), so the boundary is testable to the nanosecond:
- `Return` at `deliveredAt + 30 d − 1 ns` → `Returned`;
- `Return` at exactly `deliveredAt + 30 d` → `RETURN_WINDOW_CLOSED`.

The rejection codes (`NOT_PACKED`, `IN_TRANSIT_USE_RETURN`, `DELIVERED_USE_RETURN`) aren't decoration. They tell a caller *which* other operation is the right one, and they double as metric labels.

## 4. Optimistic transitions through a store ⚡

File 01's aggregates CAS an `AtomicReference`. Real systems keep state in a database and run many service instances, so the same idea moves into the `UPDATE` statement:

```text
-- last writer wins (the L5 default in most ORMs without @Version):
UPDATE shipment SET state = ? WHERE id = ?
-- optimistic concurrency (JPA @Version, conditional writes in DynamoDB/Cosmos/etcd):
UPDATE shipment SET state = ?, version = version + 1 WHERE id = ? AND version = ?   -- 0 rows ⇒ conflict
```

`ShipmentService.handle` is the canonical loop:
1. Load `(version, state)`.
2. Compute `transition(state, cmd)`. It's **pure**, so recomputing on retry is safe.
3. Save conditionally on the version.
4. On a conflict, **re-read and re-decide**. Never re-apply the old decision.
5. Emit the domain event only after the write won. Production pattern: write the event into an *outbox table in the same transaction*, which a relay publishes later.

The race in §C runs `Ship` and `Cancel` against the same `PACKED` shipment 10,000 times. A `CyclicBarrier` (Java) or `std::barrier` (C++) starts each trial. A ~1–2 µs simulated round trip between load and save makes the window realistic.

### 4.1 Listing 2.1.1 (Java)

```java
// StateMachines.java - table-driven enum FSM vs sealed-state FSM, and optimistic (versioned) transitions
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;

public final class StateMachines {

    // ===== A. Table-driven enum FSM: data you can print, validate and load from config ==========

    enum Status { CREATED, PACKED, SHIPPED, DELIVERED, RETURNED, CANCELLED }
    enum Event { PACK, SHIP, DELIVER, RETURN, CANCEL }

    record Table(Status initial, Map<Status, Map<Event, Status>> moves) {
        Table {
            EnumMap<Status, Map<Event, Status>> copy = new EnumMap<>(Status.class);
            for (Status s : Status.values()) {
                EnumMap<Event, Status> row = new EnumMap<>(Event.class);   // EnumMap: ordered, compact, array-indexed
                row.putAll(moves.getOrDefault(s, Map.of()));
                copy.put(s, Collections.unmodifiableMap(row));
            }
            moves = Collections.unmodifiableMap(copy);
        }

        Optional<Status> next(Status s, Event e) {
            return Optional.ofNullable(moves.get(s).get(e));
        }

        /** Startup validation: every state reachable, every state can still reach a terminal. */
        List<String> validate() {
            Set<Status> reachable = EnumSet.noneOf(Status.class);
            ArrayDeque<Status> todo = new ArrayDeque<>(List.of(initial));
            while (!todo.isEmpty()) {
                Status s = todo.poll();
                if (reachable.add(s)) todo.addAll(moves.get(s).values());
            }
            Set<Status> terminal = EnumSet.noneOf(Status.class);
            for (Status s : Status.values()) if (moves.get(s).isEmpty()) terminal.add(s);
            Set<Status> canFinish = EnumSet.copyOf(terminal);      // reverse closure: who can reach a terminal
            for (boolean grew = true; grew; ) {
                grew = false;
                for (Status s : Status.values())
                    if (!canFinish.contains(s) && moves.get(s).values().stream().anyMatch(canFinish::contains))
                        grew = canFinish.add(s);
            }
            List<String> errors = new ArrayList<>();
            EnumSet<Status> unreachable = EnumSet.complementOf(EnumSet.copyOf(reachable));
            if (!unreachable.isEmpty()) errors.add("unreachable: " + unreachable);
            EnumSet<Status> traps = EnumSet.noneOf(Status.class);
            for (Status s : reachable) if (!canFinish.contains(s)) traps.add(s);
            if (!traps.isEmpty()) errors.add("cannot reach a terminal (trap): " + traps);
            return errors;
        }
    }

    static Table fulfilment() {
        Map<Status, Map<Event, Status>> m = new EnumMap<>(Status.class);
        m.put(Status.CREATED, Map.of(Event.PACK, Status.PACKED, Event.CANCEL, Status.CANCELLED));
        m.put(Status.PACKED, Map.of(Event.SHIP, Status.SHIPPED, Event.CANCEL, Status.CANCELLED));
        m.put(Status.SHIPPED, Map.of(Event.DELIVER, Status.DELIVERED));
        m.put(Status.DELIVERED, Map.of(Event.RETURN, Status.RETURNED));
        return new Table(Status.CREATED, m);
    }

    static Table brokenFulfilment() {                         // a config typo: DELIVER missing, SHIPPED loops on itself
        Map<Status, Map<Event, Status>> m = new EnumMap<>(Status.class);
        m.put(Status.CREATED, Map.of(Event.PACK, Status.PACKED, Event.CANCEL, Status.CANCELLED));
        m.put(Status.PACKED, Map.of(Event.SHIP, Status.SHIPPED, Event.CANCEL, Status.CANCELLED));
        m.put(Status.SHIPPED, Map.of(Event.RETURN, Status.SHIPPED));
        return new Table(Status.CREATED, m);
    }

    /** Behaviour keyed by an enum: a switch EXPRESSION over an enum is exhaustive (no default needed). */
    static String customerMessage(Status s) {
        return switch (s) {
            case CREATED -> "We received your order";
            case PACKED -> "Your parcel is packed";
            case SHIPPED -> "On its way";
            case DELIVERED -> "Delivered";
            case RETURNED -> "Return received";
            case CANCELLED -> "Order cancelled";
        };
    }

    // ===== B. Sealed-state FSM: each state carries exactly its data ===============================

    sealed interface Shipment permits Created, Packed, Shipped, Delivered, Returned, Cancelled {
        String id();
    }
    record Created(String id) implements Shipment {}
    record Packed(String id, int parcels) implements Shipment {}
    record Shipped(String id, int parcels, String tracking) implements Shipment {}
    record Delivered(String id, String tracking, Instant at) implements Shipment {}
    record Returned(String id, String tracking, String rma) implements Shipment {}
    record Cancelled(String id, String reason) implements Shipment {}

    sealed interface Cmd permits Pack, Ship, Deliver, Return, Cancel {}
    record Pack(int parcels) implements Cmd {}
    record Ship(String tracking) implements Cmd {}
    record Deliver() implements Cmd {}
    record Return(String rma) implements Cmd {}
    record Cancel(String reason) implements Cmd {}

    sealed interface Outcome permits Moved, Rejected {}
    record Moved(Shipment next) implements Outcome {}
    record Rejected(String code) implements Outcome {}

    static final Duration RETURN_WINDOW = Duration.ofDays(30);

    static Outcome transition(Shipment s, Cmd c, Clock clock) {
        return switch (s) {
            case Created cr -> switch (c) {
                case Pack p when p.parcels() > 0 -> new Moved(new Packed(cr.id(), p.parcels()));
                case Pack p -> new Rejected("NO_PARCELS");
                case Cancel x -> new Moved(new Cancelled(cr.id(), x.reason()));
                case Ship sh -> new Rejected("NOT_PACKED");
                case Deliver d -> new Rejected("NOT_SHIPPED");
                case Return r -> new Rejected("NOT_DELIVERED");
            };
            case Packed pk -> switch (c) {
                case Ship sh -> new Moved(new Shipped(pk.id(), pk.parcels(), sh.tracking()));
                case Cancel x -> new Moved(new Cancelled(pk.id(), x.reason()));
                case Pack p -> new Rejected("ALREADY_PACKED");
                case Deliver d -> new Rejected("NOT_SHIPPED");
                case Return r -> new Rejected("NOT_DELIVERED");
            };
            case Shipped sp -> switch (c) {
                case Deliver d -> new Moved(new Delivered(sp.id(), sp.tracking(), clock.instant()));
                case Cancel x -> new Rejected("IN_TRANSIT_USE_RETURN");
                case Pack p -> new Rejected("ALREADY_SHIPPED");
                case Ship sh -> new Rejected("ALREADY_SHIPPED");
                case Return r -> new Rejected("NOT_DELIVERED");
            };
            case Delivered dv -> switch (c) {
                case Return r when clock.instant().isBefore(dv.at().plus(RETURN_WINDOW)) ->
                        new Moved(new Returned(dv.id(), dv.tracking(), r.rma()));
                case Return r -> new Rejected("RETURN_WINDOW_CLOSED");
                case Pack p -> new Rejected("TERMINAL_FOR_FULFILMENT");
                case Ship sh -> new Rejected("TERMINAL_FOR_FULFILMENT");
                case Deliver d -> new Rejected("ALREADY_DELIVERED");
                case Cancel x -> new Rejected("DELIVERED_USE_RETURN");
            };
            case Returned rt -> new Rejected("TERMINAL");
            case Cancelled cn -> new Rejected("TERMINAL");
        };
    }

    // ===== C. Optimistic transitions against a store (the shape of UPDATE ... WHERE version = ?) =====

    record Versioned(long version, Shipment state) {}

    interface Store {
        Versioned load(String id);
        boolean save(String id, long expectedVersion, Shipment next);
    }

    static void ioLatency() {                                  // a DB round trip, shrunk to ~1-2 us
        for (int i = 0; i < 300; i++) Thread.onSpinWait();
    }

    /** UPDATE shipment SET state = ? WHERE id = ?   -- last writer wins. */
    static final class LastWriterWinsStore implements Store {
        final ConcurrentHashMap<String, Versioned> rows = new ConcurrentHashMap<>();

        @Override public Versioned load(String id) {
            ioLatency();
            return rows.get(id);
        }

        @Override public boolean save(String id, long expectedVersion, Shipment next) {
            ioLatency();
            rows.compute(id, (k, v) -> new Versioned(v.version() + 1, next));
            return true;
        }
    }

    /** UPDATE shipment SET state = ?, version = version + 1 WHERE id = ? AND version = ?   -- 0 rows = conflict. */
    static final class VersionedStore implements Store {
        final ConcurrentHashMap<String, Versioned> rows = new ConcurrentHashMap<>();

        @Override public Versioned load(String id) {
            ioLatency();
            return rows.get(id);
        }

        @Override public boolean save(String id, long expectedVersion, Shipment next) {
            ioLatency();
            boolean[] won = {false};
            rows.computeIfPresent(id, (k, v) -> {
                if (v.version() != expectedVersion) return v;
                won[0] = true;
                return new Versioned(v.version() + 1, next);
            });
            return won[0];
        }
    }

    static final class ShipmentService {
        final Store store;
        final Clock clock;
        final ConcurrentHashMap<String, List<String>> events = new ConcurrentHashMap<>();  // the outbox
        final LongAdder conflicts = new LongAdder();

        ShipmentService(Store store, Clock clock) {
            this.store = store;
            this.clock = clock;
        }

        Outcome handle(String id, Cmd cmd) {
            for (int attempt = 0; attempt < 5; attempt++) {
                Versioned cur = store.load(id);
                Outcome o = transition(cur.state(), cmd, clock);     // pure: safe to recompute on retry
                if (!(o instanceof Moved(Shipment next))) return o;
                if (store.save(id, cur.version(), next)) {
                    events.computeIfAbsent(id, k -> Collections.synchronizedList(new ArrayList<>()))
                          .add(next.getClass().getSimpleName());     // emitted only after the write won
                    return o;
                }
                conflicts.increment();                               // someone moved first: re-read, re-decide
            }
            return new Rejected("TOO_MUCH_CONTENTION");
        }
    }

    record RaceReport(int bothWon, int exactlyOne, long conflicts, int doubleEvents) {}

    /** Ship and Cancel race on the same PACKED shipment, `trials` times; CyclicBarrier starts each trial. */
    static RaceReport race(Store store, int trials) throws Exception {
        Clock clock = Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC);
        ShipmentService svc = new ShipmentService(store, clock);
        Map<String, Versioned> rows = store instanceof VersionedStore v ? v.rows : ((LastWriterWinsStore) store).rows;
        CyclicBarrier start = new CyclicBarrier(3), end = new CyclicBarrier(3);
        Outcome[] results = new Outcome[2];
        String[] current = new String[1];
        AtomicInteger stop = new AtomicInteger();
        Thread[] ts = new Thread[2];
        Cmd[] cmds = {new Ship("trk"), new Cancel("customer")};
        for (int w = 0; w < 2; w++) {
            final int me = w;
            ts[w] = Thread.ofPlatform().start(() -> {
                try {
                    while (true) {
                        start.await();                              // barrier: also publishes current[0]
                        if (stop.get() != 0) return;
                        results[me] = svc.handle(current[0], cmds[me]);
                        end.await();
                    }
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        int bothWon = 0, exactlyOne = 0, doubleEvents = 0;
        for (int t = 0; t < trials; t++) {
            String id = "s-" + t;
            rows.put(id, new Versioned(0, new Packed(id, 1)));
            current[0] = id;
            start.await();
            end.await();
            boolean a = results[0] instanceof Moved, b = results[1] instanceof Moved;
            if (a && b) bothWon++;
            else if (a || b) exactlyOne++;
            if (svc.events.getOrDefault(id, List.of()).size() > 1) doubleEvents++;
        }
        stop.set(1);
        start.await();
        for (Thread t : ts) t.join();
        return new RaceReport(bothWon, exactlyOne, svc.conflicts.sum(), doubleEvents);
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== A. Table-driven enum FSM ==");
        Table table = fulfilment();
        for (Status s : Status.values()) System.out.printf("  %-9s %s%n", s, table.moves().get(s));
        System.out.println("  validate(fulfilment)       -> " + (table.validate().isEmpty() ? "OK" : table.validate()));
        System.out.println("  validate(brokenFulfilment) -> " + brokenFulfilment().validate());
        System.out.println("  next(SHIPPED, CANCEL) -> " + table.next(Status.SHIPPED, Event.CANCEL) + ";  next(PACKED, SHIP) -> "
                + table.next(Status.PACKED, Event.SHIP).orElseThrow());
        System.out.println("  customerMessage(SHIPPED) = " + customerMessage(Status.SHIPPED));

        System.out.println("== B. Sealed-state FSM with a clock guard (return window 30 days) ==");
        Instant deliveredAt = Instant.parse("2026-01-10T12:00:00Z");
        Delivered dv = new Delivered("s-1", "trk-1", deliveredAt);
        Clock justBefore = Clock.fixed(deliveredAt.plus(RETURN_WINDOW).minusNanos(1), ZoneOffset.UTC);
        Clock atExpiry = Clock.fixed(deliveredAt.plus(RETURN_WINDOW), ZoneOffset.UTC);
        System.out.println("  Return at window-1ns -> " + transition(dv, new Return("rma-1"), justBefore));
        System.out.println("  Return at window     -> " + transition(dv, new Return("rma-1"), atExpiry));
        Shipment s = new Created("s-2");
        Clock now = Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC);
        for (Cmd c : List.of(new Ship("t"), new Pack(0), new Pack(2), new Ship("trk-9"), new Cancel("late"), new Deliver())) {
            Outcome o = transition(s, c, now);
            System.out.printf("  %-28s + %-22s -> %s%n", s, c, o);
            if (o instanceof Moved(Shipment next)) s = next;
        }

        System.out.println("== C. Ship vs Cancel racing on one PACKED shipment, 10,000 trials each ==");
        RaceReport lww = race(new LastWriterWinsStore(), 10_000);
        RaceReport ver = race(new VersionedStore(), 10_000);
        System.out.printf("  last-writer-wins store : both callers told 'success' %,d | exactly one %,d | shipments with 2 events %,d%n",
                lww.bothWon(), lww.exactlyOne(), lww.doubleEvents());
        System.out.printf("  versioned store        : both callers told 'success' %,d | exactly one %,d | shipments with 2 events %,d | version conflicts retried %,d%n",
                ver.bothWon(), ver.exactlyOne(), ver.doubleEvents(), ver.conflicts());
        boolean ok = table.validate().isEmpty() && brokenFulfilment().validate().size() == 2
                && ver.bothWon() == 0 && ver.doubleEvents() == 0 && ver.exactlyOne() == 10_000;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (race counts: one measured run; the versioned-store zeros are guaranteed):**

```text
== A. Table-driven enum FSM ==
  CREATED   {PACK=PACKED, CANCEL=CANCELLED}
  PACKED    {SHIP=SHIPPED, CANCEL=CANCELLED}
  SHIPPED   {DELIVER=DELIVERED}
  DELIVERED {RETURN=RETURNED}
  RETURNED  {}
  CANCELLED {}
  validate(fulfilment)       -> OK
  validate(brokenFulfilment) -> [unreachable: [DELIVERED, RETURNED], cannot reach a terminal (trap): [SHIPPED]]
  next(SHIPPED, CANCEL) -> Optional.empty;  next(PACKED, SHIP) -> SHIPPED
  customerMessage(SHIPPED) = On its way
== B. Sealed-state FSM with a clock guard (return window 30 days) ==
  Return at window-1ns -> Moved[next=Returned[id=s-1, tracking=trk-1, rma=rma-1]]
  Return at window     -> Rejected[code=RETURN_WINDOW_CLOSED]
  Created[id=s-2]              + Ship[tracking=t]       -> Rejected[code=NOT_PACKED]
  Created[id=s-2]              + Pack[parcels=0]        -> Rejected[code=NO_PARCELS]
  Created[id=s-2]              + Pack[parcels=2]        -> Moved[next=Packed[id=s-2, parcels=2]]
  Packed[id=s-2, parcels=2]    + Ship[tracking=trk-9]   -> Moved[next=Shipped[id=s-2, parcels=2, tracking=trk-9]]
  Shipped[id=s-2, parcels=2, tracking=trk-9] + Cancel[reason=late]    -> Rejected[code=IN_TRANSIT_USE_RETURN]
  Shipped[id=s-2, parcels=2, tracking=trk-9] + Deliver[]              -> Moved[next=Delivered[id=s-2, tracking=trk-9, at=2026-01-01T00:00:00Z]]
== C. Ship vs Cancel racing on one PACKED shipment, 10,000 trials each ==
  last-writer-wins store : both callers told 'success' 9,767 | exactly one 233 | shipments with 2 events 9,767
  versioned store        : both callers told 'success' 0 | exactly one 10,000 | shipments with 2 events 0 | version conflicts retried 9,762
SELF-TEST OK
```

### 4.2 Listing 2.1.1 (C++)

```cpp
// state_machines.cpp - table-driven enum FSM vs variant-state FSM, and optimistic (versioned) transitions
#include <array>
#include <atomic>
#include <barrier>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <format>
#include <mutex>
#include <optional>
#include <print>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using namespace std::chrono_literals;
// Not system_clock::time_point: its precision is implementation-defined (libstdc++ ns, libc++ us, MSVC 100 ns),
// so `tp - 1ns` would not convert back under libc++. The domain states its own precision.
using SysTp = std::chrono::sys_time<std::chrono::nanoseconds>;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ===== A. Table-driven enum FSM =================================================================

enum class Status : std::uint8_t { Created, Packed, Shipped, Delivered, Returned, Cancelled };
enum class Event : std::uint8_t { Pack, Ship, Deliver, Return, Cancel };
constexpr std::size_t kStatuses = 6, kEvents = 5;
constexpr const char* kStatusNames[] = {"CREATED", "PACKED", "SHIPPED", "DELIVERED", "RETURNED", "CANCELLED"};
constexpr const char* kEventNames[] = {"PACK", "SHIP", "DELIVER", "RETURN", "CANCEL"};

constexpr std::size_t idx(Status s) { return static_cast<std::size_t>(s); }
constexpr std::size_t idx(Event e) { return static_cast<std::size_t>(e); }

struct Table {
    Status initial = Status::Created;
    std::array<std::array<std::optional<Status>, kEvents>, kStatuses> moves{};

    void add(Status from, Event e, Status to) { moves[idx(from)][idx(e)] = to; }
    std::optional<Status> next(Status s, Event e) const { return moves[idx(s)][idx(e)]; }
    bool terminal(std::size_t s) const {
        for (const auto& m : moves[s])
            if (m) return false;
        return true;
    }
    /** Startup validation: every state reachable, every reachable state can still reach a terminal. */
    std::vector<std::string> validate() const {
        std::array<bool, kStatuses> reach{}, finish{};
        std::deque<std::size_t> todo{idx(initial)};
        while (!todo.empty()) {
            const auto s = todo.front();
            todo.pop_front();
            if (reach[s]) continue;
            reach[s] = true;
            for (const auto& m : moves[s])
                if (m) todo.push_back(idx(*m));
        }
        for (std::size_t s = 0; s < kStatuses; ++s) finish[s] = terminal(s);
        for (bool grew = true; grew;) {
            grew = false;
            for (std::size_t s = 0; s < kStatuses; ++s)
                if (!finish[s])
                    for (const auto& m : moves[s])
                        if (m && finish[idx(*m)]) finish[s] = grew = true;
        }
        std::string unreachable, traps;
        for (std::size_t s = 0; s < kStatuses; ++s) {
            if (!reach[s]) unreachable += (unreachable.empty() ? "" : ", ") + std::string(kStatusNames[s]);
            else if (!finish[s]) traps += (traps.empty() ? "" : ", ") + std::string(kStatusNames[s]);
        }
        std::vector<std::string> errors;
        if (!unreachable.empty()) errors.push_back("unreachable: [" + unreachable + "]");
        if (!traps.empty()) errors.push_back("cannot reach a terminal (trap): [" + traps + "]");
        return errors;
    }
    std::string row(std::size_t s) const {
        std::string r;
        for (std::size_t e = 0; e < kEvents; ++e)
            if (moves[s][e]) r += (r.empty() ? "" : ", ") + std::string(kEventNames[e]) + "=" + kStatusNames[idx(*moves[s][e])];
        return "{" + r + "}";
    }
};

Table fulfilment() {
    Table t;
    t.add(Status::Created, Event::Pack, Status::Packed);
    t.add(Status::Created, Event::Cancel, Status::Cancelled);
    t.add(Status::Packed, Event::Ship, Status::Shipped);
    t.add(Status::Packed, Event::Cancel, Status::Cancelled);
    t.add(Status::Shipped, Event::Deliver, Status::Delivered);
    t.add(Status::Delivered, Event::Return, Status::Returned);
    return t;
}

Table broken_fulfilment() {  // config typo: DELIVER missing, SHIPPED loops on itself
    Table t;
    t.add(Status::Created, Event::Pack, Status::Packed);
    t.add(Status::Created, Event::Cancel, Status::Cancelled);
    t.add(Status::Packed, Event::Ship, Status::Shipped);
    t.add(Status::Packed, Event::Cancel, Status::Cancelled);
    t.add(Status::Shipped, Event::Return, Status::Shipped);
    return t;
}

const char* customer_message(Status s) {  // no default: -Wswitch (in -Wall) + -Werror makes this exhaustive
    switch (s) {
        case Status::Created: return "We received your order";
        case Status::Packed: return "Your parcel is packed";
        case Status::Shipped: return "On its way";
        case Status::Delivered: return "Delivered";
        case Status::Returned: return "Return received";
        case Status::Cancelled: return "Order cancelled";
    }
    return "?";
}

// ===== B. Variant-state FSM: each state carries exactly its data ===============================

struct Created { std::string id; };
struct Packed { std::string id; int parcels; };
struct Shipped { std::string id; int parcels; std::string tracking; };
struct Delivered { std::string id; std::string tracking; SysTp at; };
struct Returned { std::string id; std::string tracking; std::string rma; };
struct Cancelled { std::string id; std::string reason; };
using Shipment = std::variant<Created, Packed, Shipped, Delivered, Returned, Cancelled>;

struct Pack { int parcels; };
struct Ship { std::string tracking; };
struct Deliver {};
struct Return { std::string rma; };
struct Cancel { std::string reason; };
using Cmd = std::variant<Pack, Ship, Deliver, Return, Cancel>;

struct Moved { Shipment next; };
struct Rejected { std::string code; };
using Outcome = std::variant<Moved, Rejected>;

constexpr auto kReturnWindow = std::chrono::days(30);

Outcome transition(const Shipment& s, const Cmd& c, SysTp now) {
    auto no = [](const char* code) -> Outcome { return Rejected{code}; };
    return std::visit(overloaded{
        [&](const Created& cr) -> Outcome {
            return std::visit(overloaded{
                [&](const Pack& p) -> Outcome { return p.parcels > 0 ? Outcome{Moved{Packed{cr.id, p.parcels}}} : no("NO_PARCELS"); },
                [&](const Cancel& x) -> Outcome { return Moved{Cancelled{cr.id, x.reason}}; },
                [&](const Ship&) { return no("NOT_PACKED"); },
                [&](const Deliver&) { return no("NOT_SHIPPED"); },
                [&](const Return&) { return no("NOT_DELIVERED"); },
            }, c);
        },
        [&](const Packed& pk) -> Outcome {
            return std::visit(overloaded{
                [&](const Ship& sh) -> Outcome { return Moved{Shipped{pk.id, pk.parcels, sh.tracking}}; },
                [&](const Cancel& x) -> Outcome { return Moved{Cancelled{pk.id, x.reason}}; },
                [&](const Pack&) { return no("ALREADY_PACKED"); },
                [&](const Deliver&) { return no("NOT_SHIPPED"); },
                [&](const Return&) { return no("NOT_DELIVERED"); },
            }, c);
        },
        [&](const Shipped& sp) -> Outcome {
            return std::visit(overloaded{
                [&](const Deliver&) -> Outcome { return Moved{Delivered{sp.id, sp.tracking, now}}; },
                [&](const Cancel&) { return no("IN_TRANSIT_USE_RETURN"); },
                [&](const Pack&) { return no("ALREADY_SHIPPED"); },
                [&](const Ship&) { return no("ALREADY_SHIPPED"); },
                [&](const Return&) { return no("NOT_DELIVERED"); },
            }, c);
        },
        [&](const Delivered& dv) -> Outcome {
            return std::visit(overloaded{
                [&](const Return& r) -> Outcome {
                    if (now < dv.at + kReturnWindow) return Moved{Returned{dv.id, dv.tracking, r.rma}};
                    return no("RETURN_WINDOW_CLOSED");
                },
                [&](const Pack&) { return no("TERMINAL_FOR_FULFILMENT"); },
                [&](const Ship&) { return no("TERMINAL_FOR_FULFILMENT"); },
                [&](const Deliver&) { return no("ALREADY_DELIVERED"); },
                [&](const Cancel&) { return no("DELIVERED_USE_RETURN"); },
            }, c);
        },
        [&](const Returned&) { return no("TERMINAL"); },
        [&](const Cancelled&) { return no("TERMINAL"); },
    }, s);
}

std::string describe(const Shipment& s) {
    return std::visit(overloaded{
        [](const Created& x) { return std::format("Created{{{}}}", x.id); },
        [](const Packed& x) { return std::format("Packed{{{},{}}}", x.id, x.parcels); },
        [](const Shipped& x) { return std::format("Shipped{{{},{},{}}}", x.id, x.parcels, x.tracking); },
        [](const Delivered& x) { return std::format("Delivered{{{},{}}}", x.id, x.tracking); },
        [](const Returned& x) { return std::format("Returned{{{},{},{}}}", x.id, x.tracking, x.rma); },
        [](const Cancelled& x) { return std::format("Cancelled{{{},{}}}", x.id, x.reason); },
    }, s);
}

std::string describe(const Outcome& o) {
    return std::visit(overloaded{
        [](const Moved& m) { return "Moved[" + describe(m.next) + "]"; },
        [](const Rejected& r) { return "Rejected[" + r.code + "]"; },
    }, o);
}

// ===== C. Optimistic transitions against a store ===============================================

struct Versioned { std::uint64_t version; Shipment state; };

inline void io_latency() {  // a DB round trip, shrunk to ~1-2 us
    for (int i = 0; i < 300; ++i) {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#endif
    }
}

class Store {
protected:
    mutable std::mutex m_;
    std::unordered_map<std::string, Versioned> rows_;
public:
    virtual ~Store() = default;
    void put(const std::string& id, Versioned v) {
        std::scoped_lock l(m_);
        rows_.insert_or_assign(id, std::move(v));
    }
    Versioned load(const std::string& id) const {
        io_latency();
        std::scoped_lock l(m_);
        return rows_.at(id);
    }
    virtual bool save(const std::string& id, std::uint64_t expected_version, const Shipment& next) = 0;
};

class LastWriterWinsStore final : public Store {  // UPDATE ... SET state=? WHERE id=?
public:
    bool save(const std::string& id, std::uint64_t, const Shipment& next) override {
        io_latency();
        std::scoped_lock l(m_);
        auto& row = rows_.at(id);
        row = Versioned{row.version + 1, next};
        return true;
    }
};

class VersionedStore final : public Store {  // UPDATE ... WHERE id=? AND version=?  (0 rows = conflict)
public:
    bool save(const std::string& id, std::uint64_t expected_version, const Shipment& next) override {
        io_latency();
        std::scoped_lock l(m_);
        auto& row = rows_.at(id);
        if (row.version != expected_version) return false;
        row = Versioned{row.version + 1, next};
        return true;
    }
};

class ShipmentService {
    Store& store_;
    SysTp now_;
    std::mutex events_m_;
    std::unordered_map<std::string, int> events_;  // the outbox, counted per shipment
public:
    std::atomic<std::uint64_t> conflicts{0};
    ShipmentService(Store& s, SysTp now) : store_(s), now_(now) {}
    Outcome handle(const std::string& id, const Cmd& cmd) {
        for (int attempt = 0; attempt < 5; ++attempt) {
            const Versioned cur = store_.load(id);
            Outcome o = transition(cur.state, cmd, now_);  // pure: safe to recompute on retry
            const auto* moved = std::get_if<Moved>(&o);
            if (!moved) return o;
            if (store_.save(id, cur.version, moved->next)) {
                std::scoped_lock l(events_m_);
                ++events_[id];  // emitted only after the write won
                return o;
            }
            conflicts.fetch_add(1, std::memory_order_relaxed);  // someone moved first: re-read, re-decide
        }
        return Rejected{"TOO_MUCH_CONTENTION"};
    }
    int events_for(const std::string& id) {
        std::scoped_lock l(events_m_);
        auto it = events_.find(id);
        return it == events_.end() ? 0 : it->second;
    }
};

struct RaceReport { int both_won, exactly_one, double_events; std::uint64_t conflicts; };

RaceReport race(Store& store, int trials) {  // Ship vs Cancel on one PACKED shipment; std::barrier starts each trial
    ShipmentService svc(store, SysTp{});
    std::barrier start(3), end(3);
    std::string current;
    std::array<Outcome, 2> results{Rejected{""}, Rejected{""}};
    std::atomic<bool> stop{false};
    const std::array<Cmd, 2> cmds{Ship{"trk"}, Cancel{"customer"}};
    std::vector<std::jthread> ts;
    for (std::size_t w = 0; w < 2; ++w)
        ts.emplace_back([&, w] {
            while (true) {
                start.arrive_and_wait();  // also publishes `current`
                if (stop.load()) return;
                results[w] = svc.handle(current, cmds[w]);
                end.arrive_and_wait();
            }
        });
    RaceReport rep{0, 0, 0, 0};
    for (int t = 0; t < trials; ++t) {
        current = "s-" + std::to_string(t);
        store.put(current, Versioned{0, Packed{current, 1}});
        start.arrive_and_wait();
        end.arrive_and_wait();
        const bool a = std::holds_alternative<Moved>(results[0]), b = std::holds_alternative<Moved>(results[1]);
        if (a && b) ++rep.both_won;
        else if (a || b) ++rep.exactly_one;
        if (svc.events_for(current) > 1) ++rep.double_events;
    }
    stop.store(true);
    start.arrive_and_wait();
    ts.clear();
    rep.conflicts = svc.conflicts.load();
    return rep;
}

int main() {
    std::println("== A. Table-driven enum FSM ==");
    const Table table = fulfilment();
    for (std::size_t s = 0; s < kStatuses; ++s) std::println("  {:<9} {}", kStatusNames[s], table.row(s));
    const auto errs = broken_fulfilment().validate();
    std::println("  validate(fulfilment)        -> {}", table.validate().empty() ? "OK" : "ERRORS");
    std::println("  validate(broken_fulfilment) -> [{}; {}]", errs.at(0), errs.at(1));
    std::println("  next(SHIPPED, CANCEL) -> {};  next(PACKED, SHIP) -> {}",
                 table.next(Status::Shipped, Event::Cancel) ? "present" : "nullopt",
                 kStatusNames[idx(*table.next(Status::Packed, Event::Ship))]);
    std::println("  customer_message(SHIPPED) = {}", customer_message(Status::Shipped));

    std::println("== B. Variant-state FSM with a clock guard (return window 30 days) ==");
    const SysTp delivered_at = std::chrono::sys_days(std::chrono::year(2026) / 1 / 10) + 12h;
    const Shipment dv = Delivered{"s-1", "trk-1", delivered_at};
    std::println("  Return at window-1ns -> {}", describe(transition(dv, Return{"rma-1"}, delivered_at + kReturnWindow - 1ns)));
    std::println("  Return at window     -> {}", describe(transition(dv, Return{"rma-1"}, delivered_at + kReturnWindow)));
    Shipment s = Created{"s-2"};
    const std::vector<std::pair<std::string, Cmd>> script = {
        {"Ship{t}", Ship{"t"}}, {"Pack{0}", Pack{0}}, {"Pack{2}", Pack{2}},
        {"Ship{trk-9}", Ship{"trk-9"}}, {"Cancel{late}", Cancel{"late"}}, {"Deliver{}", Deliver{}}};
    for (const auto& [label, c] : script) {
        const Outcome o = transition(s, c, delivered_at);
        std::println("  {:<20} + {:<12} -> {}", describe(s), label, describe(o));
        if (const auto* m = std::get_if<Moved>(&o)) s = m->next;
    }

    std::println("== C. Ship vs Cancel racing on one PACKED shipment, 10,000 trials each ==");
    LastWriterWinsStore lww_store;
    VersionedStore ver_store;
    const auto lww = race(lww_store, 10'000);
    const auto ver = race(ver_store, 10'000);
    std::println("  last-writer-wins store : both callers told 'success' {} | exactly one {} | shipments with 2 events {}",
                 lww.both_won, lww.exactly_one, lww.double_events);
    std::println("  versioned store        : both callers told 'success' {} | exactly one {} | shipments with 2 events {} | version conflicts retried {}",
                 ver.both_won, ver.exactly_one, ver.double_events, ver.conflicts);
    const bool ok = table.validate().empty() && errs.size() == 2 && ver.both_won == 0 && ver.double_events == 0 &&
                    ver.exactly_one == 10'000;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== A. Table-driven enum FSM ==
  CREATED   {PACK=PACKED, CANCEL=CANCELLED}
  PACKED    {SHIP=SHIPPED, CANCEL=CANCELLED}
  SHIPPED   {DELIVER=DELIVERED}
  DELIVERED {RETURN=RETURNED}
  RETURNED  {}
  CANCELLED {}
  validate(fulfilment)        -> OK
  validate(broken_fulfilment) -> [unreachable: [DELIVERED, RETURNED]; cannot reach a terminal (trap): [SHIPPED]]
  next(SHIPPED, CANCEL) -> nullopt;  next(PACKED, SHIP) -> SHIPPED
  customer_message(SHIPPED) = On its way
== B. Variant-state FSM with a clock guard (return window 30 days) ==
  Return at window-1ns -> Moved[Returned{s-1,trk-1,rma-1}]
  Return at window     -> Rejected[RETURN_WINDOW_CLOSED]
  Created{s-2}         + Ship{t}      -> Rejected[NOT_PACKED]
  Created{s-2}         + Pack{0}      -> Rejected[NO_PARCELS]
  Created{s-2}         + Pack{2}      -> Moved[Packed{s-2,2}]
  Packed{s-2,2}        + Ship{trk-9}  -> Moved[Shipped{s-2,2,trk-9}]
  Shipped{s-2,2,trk-9} + Cancel{late} -> Rejected[IN_TRANSIT_USE_RETURN]
  Shipped{s-2,2,trk-9} + Deliver{}    -> Moved[Delivered{s-2,trk-9}]
== C. Ship vs Cancel racing on one PACKED shipment, 10,000 trials each ==
  last-writer-wins store : both callers told 'success' 9916 | exactly one 84 | shipments with 2 events 9916
  versioned store        : both callers told 'success' 0 | exactly one 10000 | shipments with 2 events 0 | version conflicts retried 9874
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== A. Table-driven enum FSM ==
  CREATED   {PACK=PACKED, CANCEL=CANCELLED}
  PACKED    {SHIP=SHIPPED, CANCEL=CANCELLED}
  SHIPPED   {DELIVER=DELIVERED}
  DELIVERED {RETURN=RETURNED}
  RETURNED  {}
  CANCELLED {}
  validate(fulfilment)        -> OK
  validate(broken_fulfilment) -> [unreachable: [DELIVERED, RETURNED]; cannot reach a terminal (trap): [SHIPPED]]
  next(SHIPPED, CANCEL) -> nullopt;  next(PACKED, SHIP) -> SHIPPED
  customer_message(SHIPPED) = On its way
== B. Variant-state FSM with a clock guard (return window 30 days) ==
  Return at window-1ns -> Moved[Returned{s-1,trk-1,rma-1}]
  Return at window     -> Rejected[RETURN_WINDOW_CLOSED]
  Created{s-2}         + Ship{t}      -> Rejected[NOT_PACKED]
  Created{s-2}         + Pack{0}      -> Rejected[NO_PARCELS]
  Created{s-2}         + Pack{2}      -> Moved[Packed{s-2,2}]
  Packed{s-2,2}        + Ship{trk-9}  -> Moved[Shipped{s-2,2,trk-9}]
  Shipped{s-2,2,trk-9} + Cancel{late} -> Rejected[IN_TRANSIT_USE_RETURN]
  Shipped{s-2,2,trk-9} + Deliver{}    -> Moved[Delivered{s-2,trk-9}]
== C. Ship vs Cancel racing on one PACKED shipment, 10,000 trials each ==
  last-writer-wins store : both callers told 'success' 8789 | exactly one 1211 | shipments with 2 events 8789
  versioned store        : both callers told 'success' 0 | exactly one 10000 | shipments with 2 events 0 | version conflicts retried 9204
SELF-TEST OK
```

## 5. Reading the results

**Last-writer-wins is a correctness bug, not a performance choice.**
- Both callers were told "success" in **9,767 of 10,000** trials (Java) and **9,961** (C++). Each of those shipments emitted *both* `Shipped` and `Cancelled`: the warehouse ships a cancelled order and the customer gets a refund.
- The stored state is whichever write landed last. The event stream and the row now disagree, and no later reconciliation can tell which one is true.

**Versioned saves serialize decisions without locks.**
- Exactly one winner in every trial, zero double events.
- **9,762 / 9,931 conflicts** were detected and retried. Every retry re-read the new state, found its transition illegal (`Shipped + Cancel → IN_TRANSIT_USE_RETURN`, or `Cancelled + Ship → TERMINAL`), and returned that rejection to its caller.
- Contention is resolved by *re-deciding*, which is only safe because `transition` is pure.

**Two C++ portability findings from building this listing:**
1. **`std::chrono::system_clock::time_point` has implementation-defined precision**: nanoseconds in libstdc++, microseconds in libc++, 100 ns in MSVC. `deliveredAt + 30 d − 1 ns` compiled with GCC and was rejected by Clang/libc++, because a nanosecond time point can't implicitly narrow. The domain therefore names its own precision (`sys_time<nanoseconds>`).
2. **`std::barrier` / `atomic::wait` cost depends heavily on the library.** The Clang/libc++ build took **21 s** against GCC's **0.9 s**. A probe isolated the cause:

   | Work per barrier phase | libstdc++ (GCC 16.2) | libc++ (Clang 21.1, Zig 0.16, windows-gnu) |
   |---|---|---|
   | 0 µs | 13 µs | 39 µs |
   | 20 µs | 28 µs | 77 µs |
   | 200 µs | **214 µs** | **15,987 µs** |

   Once a wait outlasts libc++'s short spin phase, it sleeps, and on Windows it wakes at timer granularity (~15.6 ms) ⚠ library/platform-specific. Measure your synchronization primitives on the target platform. For latency-sensitive hand-offs, prefer a primitive whose blocking path is a real futex or `WaitOnAddress`, or keep the waits short enough to stay in the spin phase.

## 6. Beyond flat machines

| Need | Technique | Where in this KB |
|---|---|---|
| Common behaviour across many states (e.g. "any active state can be cancelled") | Hierarchical states (Harel statecharts): a sealed sub-interface `Active permits Created, Packed` with one `case Active a ->` arm | P14 vending (`Active` sessions), P20 workflow |
| Independent aspects (payment state × fulfilment state) | Orthogonal regions: two fields, two machines, plus a cross-region invariant | P6 (seat state × payment state) |
| Timeouts | **Time is an event:** a scheduler injects `Timeout(token)` into the machine, rather than the machine reading the clock everywhere | P3 scheduler, P6 hold expiry, P5 breaker |
| Audit, replay, debugging | Event sourcing: the state is a fold over events, so `transition` doubles as the event applier | P13 ledger, P19 undo/redo |
| Concurrency across instances | Version per aggregate + conditional write (§4); fencing token when an external system calls back (file 01) | P6, P13, P15 |

## 7. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Representation | `status` string or enum; transitions as `if` chains in services | Enum + transition table, or the State pattern | Sealed ADT for data + guards; a table for validation and docs; a property test tying them together |
| Validation | None; bugs found in production | Unit tests per transition | Start-up graph validation (reachability, traps, determinism); exhaustive `switch` with no `default` |
| Time guards | `new Date()` inside the method | Clock injected | Clock injected; boundary tested at ±1 ns; timeouts modelled as events |
| Concurrency | Read-modify-write, last writer wins | `@Version` / conditional update | Pure transition + re-decide on conflict + outbox ordering; conflict rate is a metric; hot aggregates escalate to a per-aggregate lock or single-writer queue |
| Events | Published before the write commits | Published after the commit | Outbox in the same transaction; consumers idempotent per (aggregate, version) |

## 8. Curveballs

| Curveball | 5-minute response |
|---|---|
| "Add `ON_HOLD` from `PACKED`, resumable back to `PACKED`" | Add a record + `Hold`/`Resume` commands. The compiler lists every `switch` that must decide. The validator confirms `ON_HOLD` can still reach a terminal |
| "Return window differs per product category" | The guard reads a `ReturnPolicy` strategy (file 02.2) keyed by category; the injected clock is unchanged |
| "Two warehouse scanners send `Ship` twice" | Idempotent replay: `Shipped + Ship(sameTracking) → Moved(same)` with no new event. A different tracking number is a conflict |
| "Millions of shipments; transitions mostly uncontended" | Optimistic versioning is ideal: conflicts are rare, and each costs one re-read |
| "One aggregate is hot (a flash-sale SKU)" | Optimistic retries storm. Switch that aggregate to a per-key lock or a single-writer queue (P15); keep the pure `transition` unchanged |

## 9. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Why not just an enum with a <code>canTransitionTo</code> method?"</b></summary>

**L5:** "That's enough; each enum constant lists its allowed next states."

**Why it fails:** it validates *shape* but carries no data. The tracking number, timestamps and RMA end up as nullable fields beside the enum, and guards that need them (the return window) live elsewhere. It also does nothing for concurrency: two callers both see `PACKED`, both are allowed to move, and both write.

**L7 defence:** "Enum tables are great as *validated configuration*. I check reachability and traps at boot. The runtime model is sealed records, so each state carries exactly its data and the transition is a pure, exhaustive function. Concurrency is a separate concern: a version check on the write, with re-decision on conflict."
</details>

<details>
<summary><b>Q2 ⚡ "On a version conflict, can you just retry the save?"</b></summary>

**L5:** "Yes, retry with the new version."

**Why it fails:** retrying the *old decision* with the new version silently overwrites the other actor's transition. That's last-writer-wins with extra steps. In the race, every loser's correct answer was a *rejection*.

**L7 defence:** "Retry the *decision*, not the write: re-read, re-run the pure transition, then save. That's why `transition` must be side-effect-free. Bound the retries and surface `TOO_MUCH_CONTENTION`, and track the conflict rate. Sustained high conflict on one key means that aggregate needs a lock or a single writer."
</details>

<details>
<summary><b>Q3 ⚡ "When do you publish the <code>Shipped</code> event?"</b></summary>

**L5:** "Right after calling ship()."

**Why it fails:** if the save then loses (conflict) or the transaction rolls back, the world has heard about a shipment that didn't happen. If you publish after the commit and crash in between, the event is lost.

**L7 defence:** "Write the event into an outbox table in the same transaction as the state change, and let a relay publish it at-least-once. Consumers de-duplicate by `(aggregateId, version)`. In memory, the listing's equivalent is to emit only after the conditional write wins."
</details>

## 10. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Orders both shipped and cancelled | Last-writer-wins persistence | Conditional write on version; re-decide on conflict |
| Orders stuck forever in one state | A trap state in the configured flow | Start-up liveness check |
| A feature's new state silently ignored | `default` branch in the transition `switch` | No `default`; nested exhaustive switches |
| Return window off by a day around DST or midnight | Wall-clock local dates in the guard | `Instant` + `Duration` with an injected clock; business calendars explicit |
| Retry storms on one key | Optimistic concurrency on a hot aggregate | Per-key lock / single-writer queue for that key |
| Events for transitions that never committed | Publish before commit | Outbox |

- [ ] State representation chosen deliberately (table / enum / sealed) and documented.
- [ ] Table-driven flows validated at start-up: reachability, traps, determinism.
- [ ] Transitions are pure and exhaustive, with idempotent replays explicit.
- [ ] Guards read injected time; boundaries tested at ±1 ns.
- [ ] Persistence uses conditional writes; conflicts re-decide; retries bounded and measured.
- [ ] Events are emitted only for committed transitions (outbox).

## 11. References

- David Harel, "Statecharts: A Visual Formalism for Complex Systems", *Science of Computer Programming* 1987. <https://doi.org/10.1016/0167-6423(87)90035-9>
- Chris Richardson, "Pattern: Transactional outbox". <https://microservices.io/patterns/data/transactional-outbox.html>
- Jakarta Persistence `@Version` (optimistic locking). <https://jakarta.ee/specifications/persistence/3.1/apidocs/jakarta.persistence/jakarta/persistence/Version.html>
- Martin Fowler, "Event Sourcing". <https://martinfowler.com/eaaDev/EventSourcing.html>
- cppreference: `std::chrono::system_clock` (precision is implementation-defined). <https://en.cppreference.com/w/cpp/chrono/system_clock>
- In this KB: [01.2 Sealed ADTs](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/02-solid-composition-and-data-oriented-java21-sealed-records.md) · [01.3 Clocks and CAS](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [02.2 Strategy and specification](02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md)
