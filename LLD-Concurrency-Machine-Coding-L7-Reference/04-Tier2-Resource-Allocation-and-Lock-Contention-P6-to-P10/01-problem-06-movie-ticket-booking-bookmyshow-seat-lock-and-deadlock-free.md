# P6 · Movie Ticket Booking (BookMyShow): Seat Locks, Deadlock Freedom, Fenced Webhooks

> **Folder 04 · Problem 6 of 20.** File 01's calibration exhibit isolated the seat-hold core. This is the full problem:
> - tiered pricing;
> - a per-user seat limit, which turns out to need its **own atomicity unit**;
> - sorted per-seat locks (the multi-seat deadlock trap);
> - payment webhooks that arrive late, duplicated or after a release, made safe by **fencing tokens** and **remembered terminal outcomes**;
> - release and a sweeper, with quota returned **exactly once**;
> - a flash-crowd stress test with a full consistency audit.
>
> **Listing pair P6:** `BookMyShow.java` / `book_my_show.cpp`. Webhook scenarios are deterministic and identical in both languages. Race counts are one measured run, and the audit invariants are asserted.

---

## 1. Problem and scope

**Functional:**
- `hold(user, seats)` → `HoldOk(token, total, expiresAt) | Unavailable(taken) | LimitExceeded | Invalid`;
- `confirm(token, paymentId)` (the webhook) → `Confirmed | AlreadyConfirmed | Rejected(EXPIRED | SUPERSEDED | RELEASED | UNKNOWN_HOLD)`;
- `release(token)`;
- `sweep()`.

**Rules:** holds are all-or-nothing, the TTL is 5 minutes, at most 10 seats per user per show (held + booked), and prices by tier (standard 250, premium 400, recliner 750).

**Assumptions to say out loud:** one show is one aggregate (its own locks and state). Payment providers retry webhooks and may deliver them late or out of order. The clock is injected.

## 2. Domain model and invariants

| Type | Java | C++ |
|---|---|---|
| Seat state | `sealed SeatState permits Free, Held(token, user, expiresAt), Booked(token, user, bookingId)` | `std::variant<Free, Held, Booked>` |
| Hold record | `HoldRecord(token, user, seats[], total, expiresAt)` in `ConcurrentHashMap<Long, HoldRecord>` | `unordered_map<i64, HoldRecord>` under `book_m_` |
| Quota | `ConcurrentHashMap<String, AtomicInteger>` seats per user | `unordered_map<string, int>` under `book_m_` |
| Outcomes | `ConcurrentHashMap<Long, Object>`: token → bookingId \| Reason | `unordered_map<i64, variant<string, Reason>>` |
| Results | sealed `HoldResult`, `ConfirmResult` | `std::variant`s |

**Invariants (the audit checks all of them):**
- **I1:** a seat is booked by at most one hold, and every booked seat belongs to exactly one confirmed booking.
- **I2:** for every user, `quota == booked seats + seats under live holds`. No drift in either direction, ever.
- **I3:** `quota ≤ maxPerUser` at every instant, not just at rest.
- **I4:** a token's terminal outcome is decided **once**. Every later webhook for that token returns the same answer.
- **I5:** a hold's quota is returned **exactly once**, by whichever of {confirm-rejection, release, sweep, takeover} removes its record first.

## 3. Concurrency and contention analysis

**Two atomicity units, not one ⚡.** Seat locks make the *seat* check-and-claim atomic. The per-user limit is a constraint over a *different* set of things (all of a user's holds across any seats), and no seat lock covers it. A naive design checks `quota + n ≤ limit` before claiming seats and adds `n` after. Two concurrent holds by the same user for disjoint seats both pass the check:

| Start gate used by the test | Trials ending with 12 seats held (limit 10) |
|---|---|
| Java `CyclicBarrier` | 773 / 2,000 |
| C++ spin gate *without* a ready count (`go` flipped before thread 2 ran) | 0–5 / 2,000 |
| C++ spin gate *with* a ready count | **1,992–1,995 / 2,000** |
| Reserve-first quota (either language, any gate) | **0** |

The fix: **reserve the quota first** with one atomic add, which is the quota's own atomicity unit. Roll it back if the seats turn out to be unavailable. The table also teaches something about testing: whether the race shows up at all depends on the start gate. A gate that releases threads before they're scheduled makes a broken design look correct (01.3 §9).

**Lock order.** The order is the ascending global seat index, de-duplicated; the deadlock argument is file 01 §6. The bookkeeping mutex (C++) is always acquired *after* seat locks and never held while acquiring one, so the two lock classes can't form a cycle.

**The ~1 µs "pricing lookup" sits outside every lock.** A dynamic-pricing or eligibility call goes between the quota reservation and the seat locks. Holding seat locks across a remote call is red flag R8 (file 01 §9).

**Webhooks: fencing plus remembered outcomes.**
- `confirm` looks up the **token**, never the user.
- A seat that is no longer `Held(token)` gives `SUPERSEDED`. A hold past its TTL gives `EXPIRED`.
- The decision is written into `outcomes` **under the seat locks**, with a re-check after acquiring them, so two duplicate webhooks racing each other produce one `Confirmed` and one `AlreadyConfirmed`.
- A takeover of an expired hold records `SUPERSEDED` for the old token. Without that, Carol's late webhook (§4 output) would get `UNKNOWN_HOLD`, which is true but useless to the payment team. The listing's first draft did exactly that.
- `outcomes` is effectively an **idempotency table**, so it needs an expiry policy (keep it for the provider's retry window, typically 24–72 h).

**Exactly-once quota return.** `holds.remove(token)` returns the record to exactly one caller, and only that caller returns the quota. Confirm-success removes the record without returning the quota: the booking keeps consuming it.

## 4. Java 21 implementation

```java
// BookMyShow.java - P6: tiered seat holds, per-user limits, fenced idempotent payment webhooks, sweeper, flash crowd
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.SplittableRandom;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;

public final class BookMyShow {

    enum Tier {
        STANDARD(250_00), PREMIUM(400_00), RECLINER(750_00);
        final long cents;
        Tier(long cents) { this.cents = cents; }
    }

    record SeatId(int row, int col) {}

    sealed interface SeatState permits Free, Held, Booked {}
    record Free() implements SeatState {}
    record Held(long token, String user, Instant expiresAt) implements SeatState {}
    record Booked(long token, String user, String bookingId) implements SeatState {}

    sealed interface HoldResult permits HoldOk, Unavailable, LimitExceeded, Invalid {}
    record HoldOk(long token, List<SeatId> seats, long totalCents, Instant expiresAt) implements HoldResult {}
    record Unavailable(List<SeatId> taken) implements HoldResult {}
    record LimitExceeded(int wouldHave, int limit) implements HoldResult {}
    record Invalid(String why) implements HoldResult {}

    enum Reason { EXPIRED, SUPERSEDED, RELEASED, UNKNOWN_HOLD }
    sealed interface ConfirmResult permits Confirmed, AlreadyConfirmed, Rejected {}
    record Confirmed(String bookingId, long totalCents) implements ConfirmResult {}
    record AlreadyConfirmed(String bookingId) implements ConfirmResult {}
    record Rejected(Reason reason) implements ConfirmResult {}

    private record HoldRecord(long token, String user, int[] seats, long totalCents, Instant expiresAt) {}

    /** One show is one aggregate: its own seat locks, holds, quotas and outcomes. */
    static final class ShowInventory {
        final int rows, cols, maxPerUser;
        private final SeatState[] seats;                       // seats[i] guarded by locks[i]
        private final ReentrantLock[] locks;
        private final Clock clock;
        private final Duration ttl;
        private final boolean naiveQuota;
        private final AtomicLong tokens = new AtomicLong();
        private final ConcurrentHashMap<Long, HoldRecord> holds = new ConcurrentHashMap<>();
        private final ConcurrentHashMap<String, AtomicInteger> seatsPerUser = new ConcurrentHashMap<>();
        private final ConcurrentHashMap<Long, Object> outcomes = new ConcurrentHashMap<>();   // token -> bookingId | Reason
        final LongAdder swept = new LongAdder();

        ShowInventory(int rows, int cols, int maxPerUser, Duration ttl, Clock clock, boolean naiveQuota) {
            this.rows = rows;
            this.cols = cols;
            this.maxPerUser = maxPerUser;
            this.ttl = ttl;
            this.clock = clock;
            this.naiveQuota = naiveQuota;
            seats = new SeatState[rows * cols];
            locks = new ReentrantLock[rows * cols];
            Arrays.fill(seats, new Free());
            for (int i = 0; i < locks.length; i++) locks[i] = new ReentrantLock();
        }

        Tier tier(int idx) {
            int row = idx / cols;
            return row == rows - 1 ? Tier.RECLINER : row >= rows - 4 ? Tier.PREMIUM : Tier.STANDARD;
        }

        private AtomicInteger quota(String user) {
            return seatsPerUser.computeIfAbsent(user, u -> new AtomicInteger());
        }

        private void returnQuota(long token) {                 // exactly once per hold: whoever removes the record
            HoldRecord r = holds.remove(token);
            if (r != null) quota(r.user()).addAndGet(-r.seats().length);
        }

        private boolean available(SeatState s, Instant now) {
            return switch (s) {
                case Free f -> true;
                case Held h -> !now.isBefore(h.expiresAt());
                case Booked b -> false;
            };
        }

        HoldResult hold(String user, List<SeatId> wanted) {
            int[] order = wanted.stream().mapToInt(s -> s.row() * cols + s.col()).sorted().distinct().toArray();
            if (order.length != wanted.size() || order.length == 0) return new Invalid("empty or duplicate seats");
            if (order[0] < 0 || order[order.length - 1] >= seats.length) return new Invalid("seat out of range");
            AtomicInteger q = quota(user);
            if (naiveQuota) {                                  // L5: check now, add later -> two holds can both pass
                if (q.get() + order.length > maxPerUser) return new LimitExceeded(q.get() + order.length, maxPerUser);
            } else {                                           // reserve first: the quota is its own atomicity unit
                int after = q.addAndGet(order.length);
                if (after > maxPerUser) {
                    q.addAndGet(-order.length);
                    return new LimitExceeded(after, maxPerUser);
                }
            }
            for (int k = 0; k < 300; k++) Thread.onSpinWait();   // ~1 us dynamic-pricing lookup: outside every lock
            for (int i : order) locks[i].lock();               // global order: ascending seat index
            try {
                Instant now = clock.instant();
                List<SeatId> taken = new ArrayList<>();
                for (int i : order) if (!available(seats[i], now)) taken.add(new SeatId(i / cols, i % cols));
                if (!taken.isEmpty()) {
                    if (!naiveQuota) q.addAndGet(-order.length);
                    return new Unavailable(taken);
                }
                for (int i : order) {
                    if (seats[i] instanceof Held h) {                   // taking over an expired hold:
                        outcomes.putIfAbsent(h.token(), Reason.SUPERSEDED);   // its late webhook must learn why
                        returnQuota(h.token());
                    }
                }
                long token = tokens.incrementAndGet();         // fencing token: monotonic
                Instant expires = now.plus(ttl);
                long total = 0;
                for (int i : order) {
                    seats[i] = new Held(token, user, expires);
                    total += tier(i).cents;
                }
                if (naiveQuota) q.addAndGet(order.length);
                holds.put(token, new HoldRecord(token, user, order, total, expires));
                return new HoldOk(token, wanted, total, expires);
            } finally {
                for (int k = order.length - 1; k >= 0; k--) locks[order[k]].unlock();
            }
        }

        /** The payment webhook: idempotent by token; late, duplicate and out-of-order deliveries are safe. */
        ConfirmResult confirm(long token, String paymentId) {
            Object prior = outcomes.get(token);
            if (prior instanceof String booking) return new AlreadyConfirmed(booking);
            if (prior instanceof Reason r) return new Rejected(r);
            HoldRecord rec = holds.get(token);
            if (rec == null) return new Rejected(Reason.UNKNOWN_HOLD);
            int[] order = rec.seats();
            for (int i : order) locks[i].lock();
            try {
                Object again = outcomes.get(token);            // re-check under the locks: a racing duplicate may have won
                if (again instanceof String booking) return new AlreadyConfirmed(booking);
                if (again instanceof Reason r) return new Rejected(r);
                Instant now = clock.instant();
                for (int i : order) {
                    if (!(seats[i] instanceof Held h) || h.token() != token) {
                        outcomes.put(token, Reason.SUPERSEDED);
                        returnQuota(token);
                        return new Rejected(Reason.SUPERSEDED);
                    }
                    if (!now.isBefore(h.expiresAt())) {
                        outcomes.put(token, Reason.EXPIRED);
                        returnQuota(token);
                        return new Rejected(Reason.EXPIRED);
                    }
                }
                String bookingId = "BK-" + token + "-" + paymentId;
                for (int i : order) seats[i] = new Booked(token, rec.user(), bookingId);
                outcomes.put(token, bookingId);
                holds.remove(token);                           // quota stays consumed by the booking
                return new Confirmed(bookingId, rec.totalCents());
            } finally {
                for (int k = order.length - 1; k >= 0; k--) locks[order[k]].unlock();
            }
        }

        boolean release(long token) {
            HoldRecord rec = holds.get(token);
            if (rec == null) return false;
            for (int i : rec.seats()) locks[i].lock();
            try {
                if (outcomes.putIfAbsent(token, Reason.RELEASED) != null) return false;
                for (int i : rec.seats()) if (seats[i] instanceof Held h && h.token() == token) seats[i] = new Free();
                returnQuota(token);
                return true;
            } finally {
                for (int k = rec.seats().length - 1; k >= 0; k--) locks[rec.seats()[k]].unlock();
            }
        }

        /** Memory hygiene, not correctness: lazy expiry already makes expired seats available. */
        void sweep() {
            Instant now = clock.instant();
            for (HoldRecord rec : holds.values()) {
                if (now.isBefore(rec.expiresAt())) continue;
                for (int i : rec.seats()) locks[i].lock();
                try {
                    if (holds.get(rec.token()) != rec || outcomes.putIfAbsent(rec.token(), Reason.EXPIRED) != null) continue;
                    for (int i : rec.seats()) if (seats[i] instanceof Held h && h.token() == rec.token()) seats[i] = new Free();
                    returnQuota(rec.token());
                    swept.increment();
                } finally {
                    for (int k = rec.seats().length - 1; k >= 0; k--) locks[rec.seats()[k]].unlock();
                }
            }
        }

        /** Audit: every seat consistent; quotas equal booked + held seats; nobody over the limit. */
        List<String> audit() {
            List<String> problems = new ArrayList<>();
            Map<String, Integer> owned = new ConcurrentHashMap<>();
            Map<String, Integer> perBooking = new ConcurrentHashMap<>();
            for (int i = 0; i < seats.length; i++) {
                locks[i].lock();
                try {
                    switch (seats[i]) {
                        case Booked b -> {
                            owned.merge(b.user(), 1, Integer::sum);
                            perBooking.merge(b.bookingId(), 1, Integer::sum);
                        }
                        case Held h -> {
                            if (holds.containsKey(h.token())) owned.merge(h.user(), 1, Integer::sum);
                        }
                        case Free f -> { }
                    }
                } finally {
                    locks[i].unlock();
                }
            }
            for (var e : seatsPerUser.entrySet()) {
                int o = owned.getOrDefault(e.getKey(), 0);
                if (e.getValue().get() != o) problems.add("quota drift " + e.getKey() + ": " + e.getValue().get() + " vs " + o);
                if (o > maxPerUser) problems.add("limit exceeded " + e.getKey() + ": " + o);
            }
            return problems;
        }

        long seatsBooked() {
            return Arrays.stream(seats).filter(s -> s instanceof Booked).count();
        }

        int bookingsCount() {
            return (int) outcomes.values().stream().filter(o -> o instanceof String).count();
        }
    }

    static final class MutableClock extends Clock {
        private final AtomicReference<Instant> now;
        MutableClock(Instant start) { now = new AtomicReference<>(start); }
        void advance(Duration d) { now.updateAndGet(t -> t.plus(d)); }
        @Override public Instant instant() { return now.get(); }
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId z) { return this; }   // shares the instant; zone is irrelevant here
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
        Instant t0 = Instant.parse("2026-11-01T18:00:00Z");
        Duration ttl = Duration.ofMinutes(5);

        System.out.println("== 1. Webhook scenarios (deterministic) ==");
        MutableClock clock = new MutableClock(t0);
        ShowInventory show = new ShowInventory(10, 20, 10, ttl, clock, false);
        HoldOk a = (HoldOk) show.hold("alice", List.of(new SeatId(9, 0), new SeatId(9, 1), new SeatId(6, 5)));
        System.out.println("  alice holds 2 recliners + 1 premium -> total " + a.totalCents() / 100 + ".00 (750+750+400)");
        System.out.println("  confirm(pay-1)          -> " + show.confirm(a.token(), "pay-1"));
        System.out.println("  duplicate webhook       -> " + show.confirm(a.token(), "pay-1"));
        HoldOk b = (HoldOk) show.hold("bob", List.of(new SeatId(0, 0)));
        clock.advance(ttl);
        System.out.println("  bob's webhook at TTL    -> " + show.confirm(b.token(), "pay-2"));
        HoldOk c = (HoldOk) show.hold("carol", List.of(new SeatId(0, 1)));
        clock.advance(ttl.plusSeconds(1));
        HoldOk d = (HoldOk) show.hold("dave", List.of(new SeatId(0, 1)));   // takes over carol's expired seat
        System.out.println("  carol's late webhook    -> " + show.confirm(c.token(), "pay-3") + " (dave re-held the seat)");
        show.release(d.token());
        System.out.println("  dave releases, then webhook -> " + show.confirm(d.token(), "pay-4"));
        System.out.println("  alice asks for 8 more (limit 10, has 3) -> " + show.hold("alice", List.of(
                new SeatId(1, 0), new SeatId(1, 1), new SeatId(1, 2), new SeatId(1, 3), new SeatId(1, 4), new SeatId(1, 5), new SeatId(1, 6), new SeatId(1, 7))));
        System.out.println("  audit -> " + (show.audit().isEmpty() ? "consistent" : show.audit()));

        System.out.println("== 2. Per-user limit race: one user, two concurrent holds of 6 disjoint seats, limit 10, 2,000 trials ==");
        long[] violations = new long[2];
        for (int mode = 0; mode < 2; mode++) {
            final boolean naive = mode == 0;
            for (int trial = 0; trial < 2_000; trial++) {
                ShowInventory s = new ShowInventory(10, 20, 10, ttl, new MutableClock(t0), naive);
                parallel(2, t -> {
                    List<SeatId> six = new ArrayList<>();
                    for (int k = 0; k < 6; k++) six.add(new SeatId(t, k));
                    s.hold("u1", six);
                });
                long held = Arrays.stream(s.seats).filter(x -> x instanceof Held).count();
                if (held > 10) violations[mode]++;
            }
        }
        System.out.printf("  check-then-add quota : %,d trials ended with 12 seats held%n  reserve-first quota  : %,d%n", violations[0], violations[1]);

        System.out.println("== 3. Flash crowd: 8 threads x 5,000 attempts, 200 users, best 100 seats, 10% pay / 40% release / 50% abandon ==");
        MutableClock fc = new MutableClock(t0);
        ShowInventory hot = new ShowInventory(10, 20, 10, ttl, fc, false);
        LongAdder ok = new LongAdder(), unavailable = new LongAdder(), limited = new LongAdder(), confirmed = new LongAdder(), released = new LongAdder(), rejected = new LongAdder();
        parallel(8, t -> {
            SplittableRandom rnd = new SplittableRandom(t);
            for (int i = 0; i < 5_000; i++) {
                if (t == 0 && i % 10 == 0) fc.advance(Duration.ofSeconds(20));   // holds expire while others hold
                if (t == 1 && i % 200 == 0) hot.sweep();
                String user = "u" + rnd.nextInt(200);
                int n = 2 + rnd.nextInt(3);
                List<SeatId> want = new ArrayList<>();
                while (want.size() < n) {
                    SeatId s = new SeatId(5 + rnd.nextInt(5), rnd.nextInt(20));
                    if (!want.contains(s)) want.add(s);
                }
                switch (hot.hold(user, want)) {
                    case HoldOk h -> {
                        ok.increment();
                        int roll = rnd.nextInt(100);
                        if (roll < 10) {
                            if (hot.confirm(h.token(), "p" + h.token()) instanceof Confirmed) confirmed.increment();
                            else rejected.increment();
                            if (roll < 3) hot.confirm(h.token(), "p" + h.token());   // provider retry
                        } else if (roll < 50) {
                            if (hot.release(h.token())) released.increment();
                        }                                       // else: abandon, the hold expires
                    }
                    case Unavailable u -> unavailable.increment();
                    case LimitExceeded l -> limited.increment();
                    case Invalid v -> throw new IllegalStateException(v.why());
                }
            }
        });
        fc.advance(ttl.plusSeconds(1));
        hot.sweep();
        List<String> problems = hot.audit();
        long sold = hot.seatsBooked();
        System.out.printf("  holds ok %,d | unavailable %,d | per-user limit %,d | confirmed %,d | confirm rejected %,d | released %,d | swept %,d%n",
                ok.sum(), unavailable.sum(), limited.sum(), confirmed.sum(), rejected.sum(), released.sum(), hot.swept.sum());
        System.out.printf("  seats sold %d of 100 | bookings %d | audit: %s%n", sold, hot.bookingsCount(), problems.isEmpty() ? "consistent (no double booking, no quota drift)" : problems);

        boolean pass = violations[1] == 0 && problems.isEmpty() && show.audit().isEmpty() && confirmed.sum() == hot.bookingsCount() && sold <= 100;
        System.out.println(pass ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!pass) System.exit(1);
    }
}
```

**Output (section 1 verified; sections 2–3 one measured run with the invariants asserted):**

```text
== 1. Webhook scenarios (deterministic) ==
  alice holds 2 recliners + 1 premium -> total 1900.00 (750+750+400)
  confirm(pay-1)          -> Confirmed[bookingId=BK-1-pay-1, totalCents=190000]
  duplicate webhook       -> AlreadyConfirmed[bookingId=BK-1-pay-1]
  bob's webhook at TTL    -> Rejected[reason=EXPIRED]
  carol's late webhook    -> Rejected[reason=SUPERSEDED] (dave re-held the seat)
  dave releases, then webhook -> Rejected[reason=RELEASED]
  alice asks for 8 more (limit 10, has 3) -> LimitExceeded[wouldHave=11, limit=10]
  audit -> consistent
== 2. Per-user limit race: one user, two concurrent holds of 6 disjoint seats, limit 10, 2,000 trials ==
  check-then-add quota : 773 trials ended with 12 seats held
  reserve-first quota  : 0
== 3. Flash crowd: 8 threads x 5,000 attempts, 200 users, best 100 seats, 10% pay / 40% release / 50% abandon ==
  holds ok 388 | unavailable 39,588 | per-user limit 24 | confirmed 39 | confirm rejected 0 | released 147 | swept 37
  seats sold 94 of 100 | bookings 39 | audit: consistent (no double booking, no quota drift)
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// book_my_show.cpp - P6: tiered seat holds, per-user limits, fenced idempotent webhooks, sweeper, flash crowd
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <array>
#include <format>
#include <functional>
#include <optional>
#include <stdexcept>
#include <memory>
#include <mutex>
#include <print>
#include <random>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using Nanos = std::chrono::nanoseconds;
using namespace std::chrono_literals;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

enum class Tier { Standard, Premium, Recliner };
constexpr i64 kTierCents[] = {250'00, 400'00, 750'00};

struct SeatId { int row, col; };

struct Free {};
struct Held { i64 token; std::string user; i64 expires_at; };
struct Booked { i64 token; std::string user; std::string booking_id; };
using SeatState = std::variant<Free, Held, Booked>;

struct HoldOk { i64 token; i64 total_cents; i64 expires_at; };
struct Unavailable { std::size_t taken; };
struct LimitExceeded { int would_have, limit; };
struct Invalid { std::string why; };
using HoldResult = std::variant<HoldOk, Unavailable, LimitExceeded, Invalid>;

enum class Reason { Expired, Superseded, Released, UnknownHold };
constexpr const char* kReason[] = {"EXPIRED", "SUPERSEDED", "RELEASED", "UNKNOWN_HOLD"};
struct Confirmed { std::string booking_id; i64 total_cents; };
struct AlreadyConfirmed { std::string booking_id; };
struct Rejected { Reason reason; };
using ConfirmResult = std::variant<Confirmed, AlreadyConfirmed, Rejected>;

std::string describe(const ConfirmResult& r) {
    return std::visit(overloaded{
        [](const Confirmed& c) { return std::format("Confirmed[{}, {}]", c.booking_id, c.total_cents); },
        [](const AlreadyConfirmed& c) { return std::format("AlreadyConfirmed[{}]", c.booking_id); },
        [](const Rejected& c) { return std::format("Rejected[{}]", kReason[static_cast<int>(c.reason)]); },
    }, r);
}

class ShowInventory {
    struct HoldRecord { std::string user; std::vector<std::size_t> seats; i64 total, expires_at; };
    using Outcome = std::variant<std::string, Reason>;  // booking id | terminal reason
    int rows_, cols_, max_per_user_;
    std::vector<SeatState> seats_;                       // seats_[i] guarded by locks_[i]
    std::unique_ptr<std::mutex[]> locks_;
    std::function<i64()> now_;
    i64 ttl_;
    bool naive_quota_;
    std::atomic<i64> tokens_{0};
    std::mutex book_m_;                                  // holds_, quota_, outcomes_ (always AFTER seat locks)
    std::unordered_map<i64, HoldRecord> holds_;
    std::unordered_map<std::string, int> quota_;
    std::unordered_map<i64, Outcome> outcomes_;

    void lock_all(const std::vector<std::size_t>& order) {
        for (auto i : order) locks_[i].lock();
    }
    void unlock_all(const std::vector<std::size_t>& order) {
        for (auto it = order.rbegin(); it != order.rend(); ++it) locks_[*it].unlock();
    }
    void return_quota_locked(i64 token) {  // caller holds book_m_; exactly once per hold
        if (auto it = holds_.find(token); it != holds_.end()) {
            quota_[it->second.user] -= static_cast<int>(it->second.seats.size());
            holds_.erase(it);
        }
    }
    bool available(const SeatState& s, i64 now) const {
        return std::visit(overloaded{
            [](const Free&) { return true; },
            [&](const Held& h) { return now >= h.expires_at; },
            [](const Booked&) { return false; },
        }, s);
    }
public:
    std::atomic<i64> swept{0};
    ShowInventory(int rows, int cols, int max_per_user, Nanos ttl, std::function<i64()> now, bool naive)
        : rows_(rows), cols_(cols), max_per_user_(max_per_user), seats_(static_cast<std::size_t>(rows * cols), Free{}),
          locks_(std::make_unique<std::mutex[]>(static_cast<std::size_t>(rows * cols))), now_(std::move(now)), ttl_(ttl.count()), naive_quota_(naive) {}

    Tier tier(std::size_t idx) const {
        const int row = static_cast<int>(idx) / cols_;
        return row == rows_ - 1 ? Tier::Recliner : row >= rows_ - 4 ? Tier::Premium : Tier::Standard;
    }

    HoldResult hold(const std::string& user, const std::vector<SeatId>& wanted) {
        std::vector<std::size_t> order;
        for (const auto& s : wanted) {
            if (s.row < 0 || s.row >= rows_ || s.col < 0 || s.col >= cols_) return Invalid{"seat out of range"};
            order.push_back(static_cast<std::size_t>(s.row * cols_ + s.col));
        }
        std::ranges::sort(order);
        if (order.empty() || std::ranges::adjacent_find(order) != order.end()) return Invalid{"empty or duplicate seats"};
        const int n = static_cast<int>(order.size());
        {
            std::scoped_lock l(book_m_);
            int& q = quota_[user];
            if (q + n > max_per_user_) return LimitExceeded{q + n, max_per_user_};
            if (!naive_quota_) q += n;  // reserve first: the quota is its own atomicity unit
        }
        for (int k = 0; k < 300; ++k) {  // ~1 us dynamic-pricing lookup: outside every lock
#if defined(__x86_64__) || defined(__i386__)
            __builtin_ia32_pause();
#endif
        }
        lock_all(order);
        const i64 now = now_();
        std::size_t taken = 0;
        for (auto i : order) taken += !available(seats_[i], now);
        if (taken) {
            if (!naive_quota_) {
                std::scoped_lock l(book_m_);
                quota_[user] -= n;
            }
            unlock_all(order);
            return Unavailable{taken};
        }
        const i64 token = ++tokens_;
        i64 total = 0;
        {
            std::scoped_lock l(book_m_);
            for (auto i : order)
                if (const auto* h = std::get_if<Held>(&seats_[i])) {  // taking over an expired hold
                    outcomes_.try_emplace(h->token, Reason::Superseded);
                    return_quota_locked(h->token);
                }
            for (auto i : order) {
                seats_[i] = Held{token, user, now + ttl_};
                total += kTierCents[static_cast<int>(tier(i))];
            }
            if (naive_quota_) quota_[user] += n;  // L5: added late, after another hold also passed the check
            holds_.emplace(token, HoldRecord{user, order, total, now + ttl_});
        }
        unlock_all(order);
        return HoldOk{token, total, now + ttl_};
    }

    ConfirmResult confirm(i64 token, const std::string& payment_id) {
        std::vector<std::size_t> order;
        {
            std::scoped_lock l(book_m_);
            if (auto o = outcomes_.find(token); o != outcomes_.end()) {
                if (const auto* b = std::get_if<std::string>(&o->second)) return AlreadyConfirmed{*b};
                return Rejected{std::get<Reason>(o->second)};
            }
            auto it = holds_.find(token);
            if (it == holds_.end()) return Rejected{Reason::UnknownHold};
            order = it->second.seats;
        }
        lock_all(order);
        std::scoped_lock l(book_m_);
        ConfirmResult result = Rejected{Reason::UnknownHold};
        if (auto o = outcomes_.find(token); o != outcomes_.end()) {  // a racing duplicate already decided
            if (const auto* b = std::get_if<std::string>(&o->second)) result = AlreadyConfirmed{*b};
            else result = Rejected{std::get<Reason>(o->second)};
        } else {
            const i64 now = now_();
            std::optional<Reason> veto;
            for (auto i : order) {
                const auto* h = std::get_if<Held>(&seats_[i]);
                if (!h || h->token != token) veto = Reason::Superseded;
                else if (now >= h->expires_at) veto = veto.value_or(Reason::Expired);
            }
            if (veto) {
                outcomes_.emplace(token, *veto);
                return_quota_locked(token);
                result = Rejected{*veto};
            } else {
                const std::string id = std::format("BK-{}-{}", token, payment_id);
                const auto& rec = holds_.at(token);
                for (auto i : order) seats_[i] = Booked{token, rec.user, id};
                result = Confirmed{id, rec.total};
                outcomes_.emplace(token, id);
                holds_.erase(token);  // quota stays consumed by the booking
            }
        }
        unlock_all(order);
        return result;
    }

    bool release(i64 token) {
        std::vector<std::size_t> order;
        {
            std::scoped_lock l(book_m_);
            auto it = holds_.find(token);
            if (it == holds_.end()) return false;
            order = it->second.seats;
        }
        lock_all(order);
        bool done = false;
        {
            std::scoped_lock l(book_m_);
            if (outcomes_.try_emplace(token, Reason::Released).second) {
                for (auto i : order)
                    if (const auto* h = std::get_if<Held>(&seats_[i]); h && h->token == token) seats_[i] = Free{};
                return_quota_locked(token);
                done = true;
            }
        }
        unlock_all(order);
        return done;
    }

    void sweep() {
        std::vector<std::pair<i64, std::vector<std::size_t>>> expired;
        const i64 now = now_();
        {
            std::scoped_lock l(book_m_);
            for (const auto& [t, r] : holds_)
                if (now >= r.expires_at) expired.emplace_back(t, r.seats);
        }
        for (auto& [t, order] : expired) {
            lock_all(order);
            {
                std::scoped_lock l(book_m_);
                if (holds_.contains(t) && outcomes_.try_emplace(t, Reason::Expired).second) {
                    for (auto i : order)
                        if (const auto* h = std::get_if<Held>(&seats_[i]); h && h->token == t) seats_[i] = Free{};
                    return_quota_locked(t);
                    ++swept;
                }
            }
            unlock_all(order);
        }
    }

    std::vector<std::string> audit() {
        std::vector<std::string> problems;
        std::unordered_map<std::string, int> owned;
        for (std::size_t i = 0; i < seats_.size(); ++i) {
            std::scoped_lock s(locks_[i]);
            std::scoped_lock l(book_m_);
            if (const auto* b = std::get_if<Booked>(&seats_[i])) ++owned[b->user];
            else if (const auto* h = std::get_if<Held>(&seats_[i]); h && holds_.contains(h->token)) ++owned[h->user];
        }
        std::scoped_lock l(book_m_);
        for (const auto& [u, q] : quota_) {
            const int o = owned.contains(u) ? owned.at(u) : 0;
            if (q != o) problems.push_back(std::format("quota drift {}: {} vs {}", u, q, o));
            if (o > max_per_user_) problems.push_back(std::format("limit exceeded {}: {}", u, o));
        }
        return problems;
    }
    std::size_t count_held() const { return static_cast<std::size_t>(std::ranges::count_if(seats_, [](const SeatState& s) { return std::holds_alternative<Held>(s); })); }
    std::size_t seats_booked() const { return static_cast<std::size_t>(std::ranges::count_if(seats_, [](const SeatState& s) { return std::holds_alternative<Booked>(s); })); }
    std::size_t bookings() {
        std::scoped_lock l(book_m_);
        return static_cast<std::size_t>(std::ranges::count_if(outcomes_, [](const auto& kv) { return std::holds_alternative<std::string>(kv.second); }));
    }
};

/** Spin-gated start + jthread joins: std::barrier waits sleep ~15 ms in libc++ on Windows (02.1), 4,000 trials add up. */
template <class F>
void parallel(int threads, F body) {
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {}
            body(t);
        });
    while (ready.load() < threads) {}  // without this, `go` can flip before a thread is even scheduled
    go.store(true, std::memory_order_release);
}  // the jthreads join here

int main() {
    const Nanos ttl = 5min;
    std::println("== 1. Webhook scenarios (deterministic) ==");
    std::atomic<i64> clock{0};
    auto now = [&] { return clock.load(); };
    ShowInventory show(10, 20, 10, ttl, now, false);
    const auto a = std::get<HoldOk>(show.hold("alice", {{9, 0}, {9, 1}, {6, 5}}));
    std::println("  alice holds 2 recliners + 1 premium -> total {}.00 (750+750+400)", a.total_cents / 100);
    std::println("  confirm(pay-1)          -> {}", describe(show.confirm(a.token, "pay-1")));
    std::println("  duplicate webhook       -> {}", describe(show.confirm(a.token, "pay-1")));
    const auto b = std::get<HoldOk>(show.hold("bob", {{0, 0}}));
    clock += ttl.count();
    std::println("  bob's webhook at TTL    -> {}", describe(show.confirm(b.token, "pay-2")));
    const auto c = std::get<HoldOk>(show.hold("carol", {{0, 1}}));
    clock += (ttl + 1s).count();
    const auto d = std::get<HoldOk>(show.hold("dave", {{0, 1}}));
    std::println("  carol's late webhook    -> {} (dave re-held the seat)", describe(show.confirm(c.token, "pay-3")));
    show.release(d.token);
    std::println("  dave releases, then webhook -> {}", describe(show.confirm(d.token, "pay-4")));
    const auto more = show.hold("alice", {{1, 0}, {1, 1}, {1, 2}, {1, 3}, {1, 4}, {1, 5}, {1, 6}, {1, 7}});
    std::println("  alice asks for 8 more (limit 10, has 3) -> {}",
                 std::holds_alternative<LimitExceeded>(more) ? std::format("LimitExceeded[{} > 10]", std::get<LimitExceeded>(more).would_have) : "?");
    std::println("  audit -> {}", show.audit().empty() ? "consistent" : "PROBLEMS");

    std::println("== 2. Per-user limit race: one user, two concurrent holds of 6 disjoint seats, limit 10, 2,000 trials ==");
    std::array<int, 2> violations{};
    for (int mode = 0; mode < 2; ++mode)
        for (int trial = 0; trial < 2'000; ++trial) {
            ShowInventory s(10, 20, 10, ttl, [] { return i64{0}; }, mode == 0);
            parallel(2, [&](int t) {
                std::vector<SeatId> six;
                for (int k = 0; k < 6; ++k) six.push_back({t, k});
                s.hold("u1", six);
            });
            violations[static_cast<std::size_t>(mode)] += s.count_held() > 10;
        }
    std::println("  check-then-add quota : {} trials ended with 12 seats held\n  reserve-first quota  : {}", violations[0], violations[1]);

    std::println("== 3. Flash crowd: 8 threads x 5,000 attempts, 200 users, best 100 seats, 10% pay / 40% release / 50% abandon ==");
    std::atomic<i64> fc{0};
    ShowInventory hot(10, 20, 10, ttl, [&] { return fc.load(); }, false);
    std::atomic<i64> ok{0}, unavailable{0}, limited{0}, confirmed{0}, released{0}, rejected{0};
    parallel(8, [&](int t) {
        std::mt19937 rng(static_cast<unsigned>(t));
        for (int i = 0; i < 5'000; ++i) {
            if (t == 0 && i % 10 == 0) fc += Nanos(20s).count();
            if (t == 1 && i % 200 == 0) hot.sweep();
            const std::string user = "u" + std::to_string(rng() % 200);
            const int n = 2 + static_cast<int>(rng() % 3);
            std::vector<SeatId> want;
            while (static_cast<int>(want.size()) < n) {
                const SeatId s{5 + static_cast<int>(rng() % 5), static_cast<int>(rng() % 20)};
                if (std::ranges::none_of(want, [&](const SeatId& w) { return w.row == s.row && w.col == s.col; })) want.push_back(s);
            }
            std::visit(overloaded{
                [&](const HoldOk& h) {
                    ++ok;
                    const auto roll = rng() % 100;
                    if (roll < 10) {
                        if (std::holds_alternative<Confirmed>(hot.confirm(h.token, std::format("p{}", h.token)))) ++confirmed;
                        else ++rejected;
                        if (roll < 3) hot.confirm(h.token, std::format("p{}", h.token));  // provider retry
                    } else if (roll < 50) {
                        released += hot.release(h.token);
                    }
                },
                [&](const Unavailable&) { ++unavailable; },
                [&](const LimitExceeded&) { ++limited; },
                [&](const Invalid& v) { throw std::logic_error(v.why); },
            }, hot.hold(user, want));
        }
    });
    fc += (ttl + 1s).count();
    hot.sweep();
    const auto problems = hot.audit();
    std::println("  holds ok {} | unavailable {} | per-user limit {} | confirmed {} | confirm rejected {} | released {} | swept {}", ok.load(),
                 unavailable.load(), limited.load(), confirmed.load(), rejected.load(), released.load(), hot.swept.load());
    std::println("  seats sold {} of 100 | bookings {} | audit: {}", hot.seats_booked(), hot.bookings(),
                 problems.empty() ? "consistent (no double booking, no quota drift)" : problems.front());
    const bool pass = violations[1] == 0 && problems.empty() && show.audit().empty() &&
                      static_cast<std::size_t>(confirmed.load()) == hot.bookings() && hot.seats_booked() <= 100;
    std::println("{}", pass ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return pass ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Webhook scenarios (deterministic) ==
  alice holds 2 recliners + 1 premium -> total 1900.00 (750+750+400)
  confirm(pay-1)          -> Confirmed[BK-1-pay-1, 190000]
  duplicate webhook       -> AlreadyConfirmed[BK-1-pay-1]
  bob's webhook at TTL    -> Rejected[EXPIRED]
  carol's late webhook    -> Rejected[SUPERSEDED] (dave re-held the seat)
  dave releases, then webhook -> Rejected[RELEASED]
  alice asks for 8 more (limit 10, has 3) -> LimitExceeded[11 > 10]
  audit -> consistent
== 2. Per-user limit race: one user, two concurrent holds of 6 disjoint seats, limit 10, 2,000 trials ==
  check-then-add quota : 1992 trials ended with 12 seats held
  reserve-first quota  : 0
== 3. Flash crowd: 8 threads x 5,000 attempts, 200 users, best 100 seats, 10% pay / 40% release / 50% abandon ==
  holds ok 436 | unavailable 39539 | per-user limit 25 | confirmed 41 | confirm rejected 0 | released 176 | swept 41
  seats sold 90 of 100 | bookings 41 | audit: consistent (no double booking, no quota drift)
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Webhook scenarios (deterministic) ==
  alice holds 2 recliners + 1 premium -> total 1900.00 (750+750+400)
  confirm(pay-1)          -> Confirmed[BK-1-pay-1, 190000]
  duplicate webhook       -> AlreadyConfirmed[BK-1-pay-1]
  bob's webhook at TTL    -> Rejected[EXPIRED]
  carol's late webhook    -> Rejected[SUPERSEDED] (dave re-held the seat)
  dave releases, then webhook -> Rejected[RELEASED]
  alice asks for 8 more (limit 10, has 3) -> LimitExceeded[11 > 10]
  audit -> consistent
== 2. Per-user limit race: one user, two concurrent holds of 6 disjoint seats, limit 10, 2,000 trials ==
  check-then-add quota : 1995 trials ended with 12 seats held
  reserve-first quota  : 0
== 3. Flash crowd: 8 threads x 5,000 attempts, 200 users, best 100 seats, 10% pay / 40% release / 50% abandon ==
  holds ok 348 | unavailable 39613 | per-user limit 39 | confirmed 42 | confirm rejected 0 | released 135 | swept 25
  seats sold 96 of 100 | bookings 42 | audit: consistent (no double booking, no quota drift)
SELF-TEST OK
```

The first C++ draft used `std::barrier` to start each of the 4,000 trials, and the Clang/libc++ build took **119 s**: libc++ barrier waits sleep in ~15.6 ms quanta on this platform, as measured in 02.1. The spin gate with a ready count fixed both the speed and the race exposure.

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Atomicity | `synchronized` service or per-seat locks in request order | Sorted per-seat locks | Sorted per-seat locks **plus** a separate atomic reservation for cross-seat constraints (per-user limit), with rollback |
| Expiry | A background job | Lazy expiry + sweeper | Lazy expiry for correctness, sweeper for memory; exactly-once quota return across 4 racing removers |
| Webhook | Confirm by user + seat | Confirm by hold id, expiry checked | Fencing token; terminal outcomes remembered (SUPERSEDED/EXPIRED/RELEASED); duplicate webhooks idempotent under the locks |
| Pricing | Hard-coded | Tier map | Tier strategy; dynamic pricing called outside locks; the total locked in at hold time |
| Testing | Happy path | A few concurrent holds | Deterministic webhook scenarios + a limit race whose exposure depends on the start gate + a flash crowd with a full audit (I1–I5) |
| Scale-out | — | "Use Redis locks" | The seat row in the DB with a conditional update on `(state, token)`; the per-user limit as a conditional counter row; the outcomes table as the idempotency store |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Hold seats across two shows in one cart" | The lock order becomes `(showId, seatIndex)`; the quota per user per show is unchanged; or treat it as a saga (two holds, compensate on partial failure) |
| "VIP pre-sale window" | A specification on `hold`: `isVip ∨ now ≥ saleStart` (02.2). Time comes from the injected clock |
| "Seat map must stay consistent for viewers" | Readers get a snapshot of `SeatState[]` under no lock (states are immutable records, so a reader sees *some* valid state per seat). Display order doesn't need atomicity across seats |
| "Allow 'no single seat left between'" | A layout rule evaluated under the same sorted locks, extended to the neighbour seats (lock them too, in order) |
| "3 app servers" | `UPDATE seat SET state='HELD', token=?, expires=? WHERE show=? AND idx IN (…) AND (state='FREE' OR expires < now())` in one transaction, checking that the row count equals the request size; the quota is a conditional `UPDATE user_quota SET n = n + ? WHERE n + ? <= limit` |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Your seat locks are sorted and correct. Can a user still exceed 10 seats?"</b></summary>

**L5:** "No, we check the user's count before holding."

**Why it fails:** the count check isn't covered by any seat lock. Two holds for disjoint seats both pass the check, which showed up in 99.6% of trials with a proper start gate.

**L7 defence:** "The per-user limit is a different invariant with a different atomicity unit. I reserve quota with one atomic add before taking seat locks and roll it back on failure. In the database it's a conditional counter update."
</details>

<details>
<summary><b>Q2 ⚡ "A payment webhook arrives for a hold that expired and was re-held by someone else."</b></summary>

**L5:** "We reject it because the hold is gone."

**Why it fails:** "gone" isn't a reason. Support can't tell whether to refund, and if the check is by user (the same user re-held), it books the wrong hold (file 01 §5.4).

**L7 defence:** "The webhook carries the fencing token. A seat no longer held by that token gives `SUPERSEDED`, and a takeover records `SUPERSEDED` for the old token, so even after its record is reclaimed the late webhook gets a precise answer. The refund flow keys off that."
</details>

<details>
<summary><b>Q3 ⚡ "Confirm, release and the sweeper race on one hold. Who returns the quota?"</b></summary>

**L5:** "Each of them decrements the user's count."

**Why it fails:** up to three decrements for one hold, so the quota drifts negative and the user can then exceed the limit.

**L7 defence:** "Whoever removes the hold record returns the quota, and `remove` returns the record to exactly one caller. Successful confirm removes it *without* returning quota (the booking keeps it). The audit checks `quota == booked + live-held` for every user after a flash crowd."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Users with 12 seats | Cross-seat constraint checked without its own atomicity | Reserve-first quota |
| Double booking | Locks in request order / check-then-act | Sorted per-seat locks |
| Wrong payment bound to a hold | Confirm by user | Fencing token |
| "Unknown hold" for late webhooks | Outcome not recorded on takeover/expiry | Remember terminal outcomes |
| Quota slowly drifts | Multiple removers each return quota | Remove-record-then-return |
| Remote pricing call stalls the show | Pricing under seat locks | Price outside locks; lock in the total at hold |

- [ ] Every invariant has a named atomicity unit (seats, quota, outcomes).
- [ ] Lock order: seats ascending, bookkeeping after seats, nothing slow under locks.
- [ ] Webhooks identified by token; outcomes remembered for the provider's retry window.
- [ ] Quota returned exactly once; an audit compares quota with ownership.
- [ ] Race tests use a start gate that actually overlaps the threads.

## 10. References

- In this KB: [01.1 Seat-hold exhibit and correctness proof](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md) · [01.3 Start gates and the harness](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [02.1 libc++ barrier cost](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [P13 idempotency keys](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md)
- Martin Kleppmann, "How to do distributed locking" (fencing tokens). <https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html>
- Stripe API, Idempotent requests. <https://docs.stripe.com/api/idempotent_requests>
