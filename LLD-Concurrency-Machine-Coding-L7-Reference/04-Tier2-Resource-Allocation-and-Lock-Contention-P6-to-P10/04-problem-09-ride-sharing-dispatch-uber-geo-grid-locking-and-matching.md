# P9 · Ride-Sharing Dispatch (Uber): Geo-Grid Indexing, Ring Search, and CAS Driver States

> **Folder 04 · Problem 9 of 20.** Match a rider to the nearest available driver while thousands of drivers move and thousands of riders request at once. The L7 content:
> - a **ring search with the correct stop rule** (the naive one returns a farther driver about 11% of the time);
> - **atomic driver claims**: `AVAILABLE → OFFERED → ON_TRIP` by CAS, so two riders never get one driver;
> - **fenced offers** with expiry;
> - **moving drivers between cells without ever making them invisible.**
>
> Building it also surfaced a hard-to-spot concurrency bug: **sorting by live positions crashes TimSort**.
>
> **Listing pair P9:** `RideDispatch.java` / `ride_dispatch.cpp`. The ring-search and offer-lifecycle sections are deterministic per language (each uses its own RNG). Surge counts are one measured run.

---

## 1. Problem and scope

**Functional:**
- drivers report locations;
- riders request a ride at a position;
- the dispatcher offers the ride to the nearest available driver;
- the driver accepts within the offer TTL;
- the trip starts and later finishes.

**Non-functional:**
- a driver is never offered to two riders at once;
- "nearest" is exactly nearest within the search radius;
- location updates and matching run concurrently;
- latency is bounded under surges (a stadium emptying).

**Simplification:** positions are on a local plane in km. Production systems use H3 (hexagonal) or S2 cells, which have the same structure: cells, neighbour rings, and a stop rule.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Position | `record Pos(x, y)` in an `AtomicReference`: one consistent snapshot | `(float x, float y)` bit-packed in one `std::atomic<u64>` |
| Driver state | `sealed DriverState permits Available, Offered(rider, token, expiresAt), OnTrip(rider)` in an `AtomicReference` | `[kind:2 \| token:62]` packed in an `std::atomic<u64>`; expiry in a separate atomic written before the offer CAS |
| Index | `ConcurrentHashMap<cellKey, Set<driverId>>` (`newKeySet`) | 16 padded shards of `unordered_map<cellKey, unordered_set<int>>` |
| Match | `record Match(Driver, Offered)` | `struct Match { Driver*; u64 token; }` |

**Invariants:**
- **I1:** a driver holds at most one live offer or trip. Detected at claim time by an `active` counter: 0 violations with CAS, against 4,908 / 2,546–6,161 with check-then-set.
- **I2:** an accept succeeds only for the **current** offer token, before expiry. A stale token is rejected: shown deterministically.
- **I3:** the search returns the true nearest available driver within the radius. Verified against brute force on 10,000 random queries: 0 mismatches.
- **I4:** a moving driver is always findable. It is added to the new cell before being removed from the old, so it may briefly appear twice (deduplicated), never zero times.

## 3. Concurrency and contention analysis

**The ring-search stop rule 🔥.** Searching cells in rings of increasing Chebyshev radius, it's tempting to stop at the first ring containing anyone. But a driver in the *corner* of ring r can be farther away than one just across the border in ring r + 1. The correct rule:
- a point in ring r is at least `(r − 1) · cellSize` from any point of the centre cell;
- so stop only once `(r − 1) · cellSize > bestDistanceSoFar`.

Measured: the naive rule picked a farther driver in **1,085 / 1,118 of 10,000** queries (Java / C++), +0.22–0.23 km on average. The correct rule had 0 mismatches against brute force.

**Atomic claims.** Matching reads candidates without locks, then claims the chosen driver with `compareAndSet(Available, Offered(token))`. Two riders who pick the same driver race on one CAS: one wins, the other moves to its next candidate (793 / 169–238 lost races under the surge, all retried successfully). Check-then-set lets both "win". Under the stadium surge that produced **4,908 (Java) and 2,546–6,161 (C++) double claims**.

**Fenced offers.** Each offer has a token and an expiry. An expiry sweep CASes `Offered(token) → Available`. A driver who taps "accept" on a stale offer presents the old token and is rejected, even if a newer offer for the same driver exists. That's file 01's fencing token in a third problem.

**Two bugs found while building this listing:**
1. **Sorting by live positions.** The first version sorted candidates with `comparingDouble(d -> d.pos.get().dist(at))`. The mover thread changed positions during the sort, the comparator became inconsistent, and TimSort threw `IllegalArgumentException: Comparison method violates its general contract!` The exception killed a worker before it reached the `CyclicBarrier`, and the test **hung** until the runner's timeout killed it. Two fixes:
   - **sort on a snapshot:** capture each candidate's distance once (`record Cand(driver, dist)`);
   - **make harnesses fail loudly:** workers record exceptions and always reach the end barrier.
2. **Bookkeeping after publication.** `finishTrip` CASed the state to `Available` and *then* decremented the test's `active` counter. A new rider could claim the driver in between, so the counter showed 2 and the test reported 80 false double claims. The rule, the same as P7's "clear the owner, then free the bit": **update bookkeeping first, publish availability last.**

**Moving drivers between cells.** Add to the new cell, then remove from the old. The reverse order opens a window in which the driver is in no cell, and a rider next to them gets "no driver". Duplicates from the other order are harmless because candidates are deduplicated and claims are atomic.

## 4. Java 21 implementation

```java
// RideDispatch.java - P9: geo-grid buckets, correct ring search, CAS driver states (AVAILABLE -> OFFERED -> ON_TRIP)
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.SplittableRandom;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;

public final class RideDispatch {

    record Pos(double x, double y) {                           // km on a local plane (a real system: H3 / S2 cells)
        double dist(Pos o) { return Math.hypot(x - o.x, y - o.y); }
    }

    sealed interface DriverState permits Available, Offered, OnTrip {}
    record Available() implements DriverState {}
    record Offered(String rider, long token, long expiresAt) implements DriverState {}
    record OnTrip(String rider) implements DriverState {}

    static final DriverState AVAILABLE = new Available();

    record Match(Driver driver, Offered offer) {}

    static final class Driver {
        final int id;
        final AtomicReference<Pos> pos;                        // one atomic snapshot of (x, y)
        final AtomicReference<DriverState> state = new AtomicReference<>(AVAILABLE);
        final AtomicInteger activeTrips = new AtomicInteger(); // test-only: must never exceed 1

        Driver(int id, Pos p) {
            this.id = id;
            this.pos = new AtomicReference<>(p);
        }
    }

    static final class Grid {
        final double cell;
        final ConcurrentHashMap<Long, Set<Integer>> cells = new ConcurrentHashMap<>();

        Grid(double cell) {
            this.cell = cell;
        }

        long key(int cx, int cy) {
            return ((long) cx << 32) ^ (cy & 0xFFFF_FFFFL);
        }

        int cx(Pos p) { return (int) Math.floor(p.x() / cell); }
        int cy(Pos p) { return (int) Math.floor(p.y() / cell); }

        void add(Driver d, Pos p) {
            cells.computeIfAbsent(key(cx(p), cy(p)), k -> ConcurrentHashMap.newKeySet()).add(d.id);
        }

        /** Add to the new cell BEFORE removing from the old: briefly visible twice, never invisible. */
        void move(Driver d, Pos to) {
            Pos from = d.pos.getAndSet(to);
            long a = key(cx(from), cy(from)), b = key(cx(to), cy(to));
            if (a == b) return;
            add(d, to);
            Set<Integer> old = cells.get(a);
            if (old != null) old.remove(d.id);
        }
    }

    static final class Dispatcher {
        final Grid grid;
        final Driver[] drivers;
        final boolean naiveClaim;
        final AtomicLong tokens = new AtomicLong();
        final LongAdder casLost = new LongAdder(), doubleClaims = new LongAdder();

        Dispatcher(Grid g, Driver[] ds, boolean naiveClaim) {
            this.grid = g;
            this.drivers = ds;
            this.naiveClaim = naiveClaim;
        }

        /**
         * Ring search with the CORRECT stop rule: a point in Chebyshev ring r is at least (r-1)*cell away from
         * any point of the centre cell, so once (r-1)*cell > bestDistance no further ring can hold a closer driver.
         * The naive rule ("stop at the first ring that has anyone") misses closer drivers in the next ring.
         */
        record Cand(Driver driver, double dist) {}

        List<Driver> candidates(Pos at, int maxRing, boolean naiveStop, int keep) {
            int cx = grid.cx(at), cy = grid.cy(at);
            List<Cand> found = new ArrayList<>();
            java.util.HashSet<Integer> seen = new java.util.HashSet<>();   // a mover may list a driver in two cells
            for (int r = 0; r <= maxRing; r++) {
                if (!found.isEmpty()) {
                    double best = found.stream().mapToDouble(Cand::dist).min().orElseThrow();
                    if (naiveStop || (r - 1) * grid.cell > best) break;
                }
                for (int dx = -r; dx <= r; dx++) {
                    for (int dy = -r; dy <= r; dy++) {
                        if (Math.max(Math.abs(dx), Math.abs(dy)) != r) continue;   // ring border only
                        Set<Integer> ids = grid.cells.get(grid.key(cx + dx, cy + dy));
                        if (ids == null) continue;
                        for (int id : ids) {
                            Driver d = drivers[id];
                            if (seen.add(id) && d.state.get() instanceof Available) found.add(new Cand(d, d.pos.get().dist(at)));
                        }
                    }
                }
            }
            // Sort on the SNAPSHOT distance. Sorting by d.pos.get() while a mover thread updates positions gives an
            // inconsistent comparator: TimSort throws "Comparison method violates its general contract!" (it did).
            found.sort(Comparator.comparingDouble(Cand::dist));
            return found.stream().limit(keep).map(Cand::driver).toList();
        }

        /** Offer the ride to the nearest driver we can CLAIM; a lost CAS means someone else got them first. */
        Optional<Match> request(String rider, Pos at, long now, long offerTtl) {
            for (Driver d : candidates(at, 20, false, 8)) {
                Offered offer = new Offered(rider, tokens.incrementAndGet(), now + offerTtl);
                if (naiveClaim) {                              // L5: check, then set
                    if (d.state.get() instanceof Available) {
                        d.state.set(offer);
                        if (d.activeTrips.incrementAndGet() > 1) doubleClaims.increment();   // two riders, one driver
                        return Optional.of(new Match(d, offer));
                    }
                } else {
                    DriverState cur = d.state.get();
                    if (cur instanceof Available && d.state.compareAndSet(cur, offer)) {
                        if (d.activeTrips.incrementAndGet() > 1) doubleClaims.increment();
                        return Optional.of(new Match(d, offer));
                    }
                    casLost.increment();
                }
            }
            return Optional.empty();
        }

        /** The driver taps accept: valid only for the CURRENT offer token and before it expires. */
        boolean accept(Driver d, long token, long now) {
            DriverState cur = d.state.get();
            return cur instanceof Offered o && o.token() == token && now < o.expiresAt()
                    && d.state.compareAndSet(cur, new OnTrip(o.rider()));
        }

        /** Offer timeout sweep: an expired offer returns the driver to AVAILABLE (CAS on the exact offer). */
        boolean expire(Driver d, long now) {
            DriverState cur = d.state.get();
            if (!(cur instanceof Offered o) || now < o.expiresAt()) return false;
            d.activeTrips.decrementAndGet();                   // bookkeeping BEFORE publishing availability
            if (d.state.compareAndSet(cur, AVAILABLE)) return true;
            d.activeTrips.incrementAndGet();                   // lost the race (accepted meanwhile): undo
            return false;
        }

        void finishTrip(Driver d) {
            DriverState cur = d.state.get();
            if (!(cur instanceof OnTrip)) return;
            d.activeTrips.decrementAndGet();                   // publish AVAILABLE last: decrementing after the CAS let a new
            if (!d.state.compareAndSet(cur, AVAILABLE)) d.activeTrips.incrementAndGet();   // claim slip in (80 false alarms)
        }
    }

    static Driver[] city(int n, long seed, Grid g) {
        SplittableRandom rnd = new SplittableRandom(seed);
        Driver[] ds = new Driver[n];
        for (int i = 0; i < n; i++) {
            ds[i] = new Driver(i, new Pos(rnd.nextDouble(0, 20), rnd.nextDouble(0, 20)));
            g.add(ds[i], ds[i].pos.get());
        }
        return ds;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Ring-search stop rule vs brute force: 300 drivers, 20x20 km, 1 km cells, 10,000 queries ==");
        Grid g = new Grid(1.0);
        Driver[] ds = city(300, 1, g);
        Dispatcher disp = new Dispatcher(g, ds, false);
        SplittableRandom q = new SplittableRandom(2);
        int naiveWrong = 0, correctWrong = 0;
        double extraKm = 0;
        for (int i = 0; i < 10_000; i++) {
            Pos at = new Pos(q.nextDouble(0, 20), q.nextDouble(0, 20));
            Driver truth = ds[0];
            for (Driver d : ds) if (d.pos.get().dist(at) < truth.pos.get().dist(at)) truth = d;
            Driver naive = disp.candidates(at, 40, true, 1).get(0), correct = disp.candidates(at, 40, false, 1).get(0);
            if (naive != truth) {
                naiveWrong++;
                extraKm += naive.pos.get().dist(at) - truth.pos.get().dist(at);
            }
            if (correct != truth) correctWrong++;
        }
        System.out.printf("  naive 'first non-empty ring' picked a farther driver %,d times (avg +%.2f km) | correct rule: %d%n",
                naiveWrong, naiveWrong == 0 ? 0 : extraKm / naiveWrong, correctWrong);

        System.out.println("== 2. Offer lifecycle with fencing tokens (deterministic) ==");
        Grid g2 = new Grid(1.0);
        Driver[] two = {new Driver(0, new Pos(1, 1))};
        g2.add(two[0], two[0].pos.get());
        Dispatcher d2 = new Dispatcher(g2, two, false);
        Offered first = d2.request("r1", new Pos(1.2, 1.1), 0, 15).orElseThrow().offer();
        System.out.println("  r1 offered driver 0, token " + first.token() + "; r2 requests now -> " + d2.request("r2", new Pos(1.3, 1.3), 1, 15).map(o -> "OFFERED").orElse("no driver (driver 0 is OFFERED)"));
        System.out.println("  t=20: offer expired -> " + d2.expire(two[0], 20) + "; driver taps accept on stale token at t=21 -> " + d2.accept(two[0], first.token(), 21));
        Offered second = d2.request("r2", new Pos(1.3, 1.3), 22, 15).orElseThrow().offer();
        System.out.println("  r2 offered (token " + second.token() + "); accept with old token -> " + d2.accept(two[0], first.token(), 23)
                + "; with current token -> " + d2.accept(two[0], second.token(), 23) + "; state " + two[0].state.get());

        System.out.println("== 3. Stadium surge: 8 rider threads x 2,000 requests within 0.5 km, 1 thread moving 2,000 drivers (one measured run) ==");
        long[] doubles = new long[2];
        for (int mode = 0; mode < 2; mode++) {
            Grid g3 = new Grid(1.0);
            Driver[] fleet = city(2_000, 3, g3);
            Dispatcher d3 = new Dispatcher(g3, fleet, mode == 0);
            AtomicBoolean stop = new AtomicBoolean();
            Thread mover = Thread.ofPlatform().start(() -> {
                SplittableRandom r = new SplittableRandom(9);
                while (!stop.get()) {
                    Driver d = fleet[r.nextInt(fleet.length)];
                    Pos p = d.pos.get();
                    g3.move(d, new Pos(Math.clamp(p.x() + r.nextDouble(-0.3, 0.3), 0, 19.99), Math.clamp(p.y() + r.nextDouble(-0.3, 0.3), 0, 19.99)));
                }
            });
            LongAdder matched = new LongAdder(), noDriver = new LongAdder();
            CyclicBarrier start = new CyclicBarrier(9), end = new CyclicBarrier(9);
            AtomicReference<Exception> failure = new AtomicReference<>();
            for (int t = 0; t < 8; t++) {
                final int seed = t;
                Thread.ofPlatform().start(() -> {
                    try {
                        SplittableRandom r = new SplittableRandom(100 + seed);
                        start.await();
                        for (int i = 0; i < 2_000; i++) {
                            Pos at = new Pos(10 + r.nextDouble(-0.5, 0.5), 10 + r.nextDouble(-0.5, 0.5));   // stadium surge
                            Optional<Match> m = d3.request("r" + seed + "-" + i, at, i, 15);
                            if (m.isEmpty()) {
                                noDriver.increment();
                                continue;
                            }
                            matched.increment();
                            if (d3.accept(m.get().driver(), m.get().offer().token(), i)) d3.finishTrip(m.get().driver());
                        }
                    } catch (Exception e) {
                        failure.compareAndSet(null, e);               // record it ...
                    } finally {
                        try {
                            end.await();                              // ... and never strand the barrier
                        } catch (Exception ignored) {
                        }
                    }
                });
            }
            start.await();
            end.await();
            stop.set(true);
            if (failure.get() != null) throw new IllegalStateException("worker failed", failure.get());
            mover.join();
            doubles[mode] = d3.doubleClaims.sum();
            System.out.printf("  %-26s matched %,d | no driver %,d | driver claimed for 2 riders at once %,d | lost CAS races %,d%n",
                    mode == 0 ? "check-then-set claim" : "CAS claim", matched.sum(), noDriver.sum(), d3.doubleClaims.sum(), d3.casLost.sum());
        }
        boolean ok = correctWrong == 0 && naiveWrong > 0 && doubles[1] == 0 && two[0].state.get() instanceof OnTrip;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1–2 deterministic; section 3 one measured run):**

```text
== 1. Ring-search stop rule vs brute force: 300 drivers, 20x20 km, 1 km cells, 10,000 queries ==
  naive 'first non-empty ring' picked a farther driver 1,085 times (avg +0.23 km) | correct rule: 0
== 2. Offer lifecycle with fencing tokens (deterministic) ==
  r1 offered driver 0, token 1; r2 requests now -> no driver (driver 0 is OFFERED)
  t=20: offer expired -> true; driver taps accept on stale token at t=21 -> false
  r2 offered (token 2); accept with old token -> false; with current token -> true; state OnTrip[rider=r2]
== 3. Stadium surge: 8 rider threads x 2,000 requests within 0.5 km, 1 thread moving 2,000 drivers (one measured run) ==
  check-then-set claim       matched 16,000 | no driver 0 | driver claimed for 2 riders at once 4,908 | lost CAS races 0
  CAS claim                  matched 16,000 | no driver 0 | driver claimed for 2 riders at once 0 | lost CAS races 793
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// ride_dispatch.cpp - P9: geo-grid buckets, correct ring search, CAS driver states packed in one atomic word
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <random>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using u64 = std::uint64_t;
using i64 = std::int64_t;

struct Pos {
    float x, y;
    double dist(const Pos& o) const { return std::hypot(static_cast<double>(x - o.x), static_cast<double>(y - o.y)); }
};

/** (x, y) packed into one 64-bit word: a reader never sees x from one update and y from another. */
inline u64 pack(Pos p) { return (static_cast<u64>(std::bit_cast<std::uint32_t>(p.x)) << 32) | std::bit_cast<std::uint32_t>(p.y); }
inline Pos unpack(u64 w) { return {std::bit_cast<float>(static_cast<std::uint32_t>(w >> 32)), std::bit_cast<float>(static_cast<std::uint32_t>(w))}; }

/** Driver state packed as [kind:2 | token:62]. Every transition is one CAS on this word. */
enum Kind : u64 { kAvailable = 0, kOffered = 1, kOnTrip = 2 };
constexpr u64 word(Kind k, u64 token) { return (static_cast<u64>(k) << 62) | (token & ((u64{1} << 62) - 1)); }
constexpr Kind kind(u64 w) { return static_cast<Kind>(w >> 62); }
constexpr u64 token(u64 w) { return w & ((u64{1} << 62) - 1); }

struct Driver {
    int id = 0;
    std::atomic<u64> pos{0}, state{word(kAvailable, 0)};
    std::atomic<i64> offer_expires{0};  // written BEFORE the CAS that publishes the offer
    std::atomic<int> active{0};          // test-only: must never exceed 1
};

class Grid {
    struct alignas(64) Shard { std::mutex m; std::unordered_map<u64, std::unordered_set<int>> cells; };
    std::array<Shard, 16> shards_;
    Shard& shard(u64 key) { return shards_[key % shards_.size()]; }
public:
    double cell;
    explicit Grid(double c) : cell(c) {}
    static u64 key(int cx, int cy) { return (static_cast<u64>(static_cast<std::uint32_t>(cx)) << 32) | static_cast<std::uint32_t>(cy); }
    int cx(Pos p) const { return static_cast<int>(std::floor(p.x / cell)); }
    int cy(Pos p) const { return static_cast<int>(std::floor(p.y / cell)); }
    void add(int id, Pos p) {
        const u64 k = key(cx(p), cy(p));
        std::scoped_lock l(shard(k).m);
        shard(k).cells[k].insert(id);
    }
    void remove(int id, Pos p) {
        const u64 k = key(cx(p), cy(p));
        std::scoped_lock l(shard(k).m);
        shard(k).cells[k].erase(id);
    }
    std::vector<int> ids(int cx_, int cy_) {
        const u64 k = key(cx_, cy_);
        std::scoped_lock l(shard(k).m);
        auto it = shard(k).cells.find(k);
        return it == shard(k).cells.end() ? std::vector<int>{} : std::vector<int>(it->second.begin(), it->second.end());
    }
    void move(Driver& d, Pos to) {  // add to the new cell BEFORE removing from the old: never invisible
        const Pos from = unpack(d.pos.exchange(pack(to)));
        if (cx(from) == cx(to) && cy(from) == cy(to)) return;
        add(d.id, to);
        remove(d.id, from);
    }
};

struct Match { Driver* driver; u64 token; };

class Dispatcher {
    Grid& grid_;
    std::vector<std::unique_ptr<Driver>>& drivers_;
    bool naive_;
    std::atomic<u64> tokens_{0};
public:
    std::atomic<u64> cas_lost{0}, double_claims{0};
    Dispatcher(Grid& g, std::vector<std::unique_ptr<Driver>>& d, bool naive) : grid_(g), drivers_(d), naive_(naive) {}

    std::vector<Driver*> candidates(Pos at, int max_ring, bool naive_stop, std::size_t keep) {
        struct Cand { Driver* d; double dist; };
        std::vector<Cand> found;
        std::unordered_set<int> seen;
        const int cx = grid_.cx(at), cy = grid_.cy(at);
        for (int r = 0; r <= max_ring; ++r) {
            if (!found.empty()) {
                double best = found.front().dist;
                for (const auto& c : found) best = std::min(best, c.dist);
                if (naive_stop || (r - 1) * grid_.cell > best) break;  // the correct stop rule
            }
            for (int dx = -r; dx <= r; ++dx)
                for (int dy = -r; dy <= r; ++dy) {
                    if (std::max(std::abs(dx), std::abs(dy)) != r) continue;
                    for (int id : grid_.ids(cx + dx, cy + dy)) {
                        Driver& d = *drivers_[static_cast<std::size_t>(id)];
                        if (seen.insert(id).second && kind(d.state.load()) == kAvailable) found.push_back({&d, unpack(d.pos.load()).dist(at)});
                    }
                }
        }
        std::ranges::sort(found, {}, &Cand::dist);  // on the snapshot distance, never on live positions
        std::vector<Driver*> out;
        for (std::size_t i = 0; i < found.size() && i < keep; ++i) out.push_back(found[i].d);
        return out;
    }

    std::optional<Match> request(Pos at, i64 now, i64 ttl) {
        for (Driver* d : candidates(at, 20, false, 8)) {
            const u64 t = ++tokens_;
            if (naive_) {  // L5: check, then set
                if (kind(d->state.load()) == kAvailable) {
                    d->offer_expires.store(now + ttl);
                    d->state.store(word(kOffered, t));
                    if (d->active.fetch_add(1) + 1 > 1) ++double_claims;
                    return Match{d, t};
                }
            } else {
                u64 cur = d->state.load();
                if (kind(cur) == kAvailable) {
                    d->offer_expires.store(now + ttl);  // visible before the offer is (CAS is seq_cst)
                    if (d->state.compare_exchange_strong(cur, word(kOffered, t))) {
                        if (d->active.fetch_add(1) + 1 > 1) ++double_claims;
                        return Match{d, t};
                    }
                }
                ++cas_lost;
            }
        }
        return std::nullopt;
    }

    static bool accept(Driver& d, u64 t, i64 now) {  // only the CURRENT offer token, before it expires
        u64 cur = d.state.load();
        return kind(cur) == kOffered && token(cur) == t && now < d.offer_expires.load() && d.state.compare_exchange_strong(cur, word(kOnTrip, t));
    }
    static bool expire(Driver& d, i64 now) {
        u64 cur = d.state.load();
        if (kind(cur) != kOffered || now < d.offer_expires.load()) return false;
        d.active.fetch_sub(1);  // bookkeeping BEFORE publishing availability
        if (d.state.compare_exchange_strong(cur, word(kAvailable, 0))) return true;
        d.active.fetch_add(1);
        return false;
    }
    static void finish(Driver& d) {
        u64 cur = d.state.load();
        if (kind(cur) != kOnTrip) return;
        d.active.fetch_sub(1);
        if (!d.state.compare_exchange_strong(cur, word(kAvailable, 0))) d.active.fetch_add(1);
    }
};

std::vector<std::unique_ptr<Driver>> city(int n, unsigned seed, Grid& g) {
    std::mt19937 rng(seed);
    std::uniform_real_distribution<float> u(0.0f, 20.0f);
    std::vector<std::unique_ptr<Driver>> ds;
    for (int i = 0; i < n; ++i) {
        auto d = std::make_unique<Driver>();
        d->id = i;
        const Pos p{u(rng), u(rng)};
        d->pos.store(pack(p));
        g.add(i, p);
        ds.push_back(std::move(d));
    }
    return ds;
}

int main() {
    std::println("== 1. Ring-search stop rule vs brute force: 300 drivers, 20x20 km, 1 km cells, 10,000 queries ==");
    Grid g(1.0);
    auto ds = city(300, 1, g);
    Dispatcher disp(g, ds, false);
    std::mt19937 q(2);
    std::uniform_real_distribution<float> u(0.0f, 20.0f);
    int naive_wrong = 0, correct_wrong = 0;
    double extra = 0;
    for (int i = 0; i < 10'000; ++i) {
        const Pos at{u(q), u(q)};
        Driver* truth = ds[0].get();
        for (auto& d : ds)
            if (unpack(d->pos.load()).dist(at) < unpack(truth->pos.load()).dist(at)) truth = d.get();
        Driver* naive = disp.candidates(at, 40, true, 1).at(0);
        Driver* correct = disp.candidates(at, 40, false, 1).at(0);
        if (naive != truth) {
            ++naive_wrong;
            extra += unpack(naive->pos.load()).dist(at) - unpack(truth->pos.load()).dist(at);
        }
        correct_wrong += correct != truth;
    }
    std::println("  naive 'first non-empty ring' picked a farther driver {} times (avg +{:.2f} km) | correct rule: {}", naive_wrong,
                 naive_wrong ? extra / naive_wrong : 0.0, correct_wrong);

    std::println("== 2. Offer lifecycle with fencing tokens (deterministic) ==");
    Grid g2(1.0);
    std::vector<std::unique_ptr<Driver>> one;
    one.push_back(std::make_unique<Driver>());
    one[0]->pos.store(pack({1, 1}));
    g2.add(0, {1, 1});
    Dispatcher d2(g2, one, false);
    const auto first = d2.request({1.2f, 1.1f}, 0, 15).value();
    std::println("  r1 offered driver 0, token {}; r2 requests now -> {}", first.token,
                 d2.request({1.3f, 1.3f}, 1, 15) ? "OFFERED" : "no driver (driver 0 is OFFERED)");
    const bool expired = Dispatcher::expire(*one[0], 20);
    std::println("  t=20: offer expired -> {}; driver taps accept on stale token at t=21 -> {}", expired, Dispatcher::accept(*one[0], first.token, 21));
    const auto second = d2.request({1.3f, 1.3f}, 22, 15).value();
    const bool stale = Dispatcher::accept(*one[0], first.token, 23), current = Dispatcher::accept(*one[0], second.token, 23);
    std::println("  r2 offered (token {}); accept with old token -> {}; with current token -> {}; state {}", second.token, stale, current,
                 kind(one[0]->state.load()) == kOnTrip ? "OnTrip" : "?");

    std::println("== 3. Stadium surge: 8 rider threads x 2,000 requests within 0.5 km, 1 thread moving 2,000 drivers (one measured run) ==");
    std::array<u64, 2> doubles{};
    for (int mode = 0; mode < 2; ++mode) {
        Grid g3(1.0);
        auto fleet = city(2'000, 3, g3);
        Dispatcher d3(g3, fleet, mode == 0);
        std::atomic<bool> stop{false}, go{false};
        std::atomic<int> ready{0};
        std::atomic<u64> matched{0}, none{0};
        {
            std::jthread mover([&] {
                std::mt19937 r(9);
                std::uniform_real_distribution<float> step(-0.3f, 0.3f);
                while (!stop.load()) {
                    Driver& d = *fleet[r() % fleet.size()];
                    const Pos p = unpack(d.pos.load());
                    g3.move(d, {std::clamp(p.x + step(r), 0.0f, 19.99f), std::clamp(p.y + step(r), 0.0f, 19.99f)});
                }
            });
            {
                std::vector<std::jthread> riders;
                for (int t = 0; t < 8; ++t)
                    riders.emplace_back([&, t] {
                        std::mt19937 r(100u + static_cast<unsigned>(t));
                        std::uniform_real_distribution<float> near(-0.5f, 0.5f);
                        ready.fetch_add(1);
                        while (!go.load()) {}
                        for (int i = 0; i < 2'000; ++i) {
                            const auto m = d3.request({10 + near(r), 10 + near(r)}, i, 15);
                            if (!m) {
                                ++none;
                                continue;
                            }
                            ++matched;
                            if (Dispatcher::accept(*m->driver, m->token, i)) Dispatcher::finish(*m->driver);
                        }
                    });
                while (ready.load() < 8) {}
                go.store(true);
            }
            stop.store(true);
        }
        doubles[static_cast<std::size_t>(mode)] = d3.double_claims.load();
        std::println("  {:<26} matched {} | no driver {} | driver claimed for 2 riders at once {} | lost CAS races {}",
                     mode == 0 ? "check-then-set claim" : "CAS claim", matched.load(), none.load(), d3.double_claims.load(), d3.cas_lost.load());
    }
    const bool ok = correct_wrong == 0 && naive_wrong > 0 && doubles[1] == 0 && kind(one[0]->state.load()) == kOnTrip;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Ring-search stop rule vs brute force: 300 drivers, 20x20 km, 1 km cells, 10,000 queries ==
  naive 'first non-empty ring' picked a farther driver 1118 times (avg +0.22 km) | correct rule: 0
== 2. Offer lifecycle with fencing tokens (deterministic) ==
  r1 offered driver 0, token 1; r2 requests now -> no driver (driver 0 is OFFERED)
  t=20: offer expired -> true; driver taps accept on stale token at t=21 -> false
  r2 offered (token 2); accept with old token -> false; with current token -> true; state OnTrip
== 3. Stadium surge: 8 rider threads x 2,000 requests within 0.5 km, 1 thread moving 2,000 drivers (one measured run) ==
  check-then-set claim       matched 16000 | no driver 0 | driver claimed for 2 riders at once 2546 | lost CAS races 0
  CAS claim                  matched 16000 | no driver 0 | driver claimed for 2 riders at once 0 | lost CAS races 169
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Ring-search stop rule vs brute force: 300 drivers, 20x20 km, 1 km cells, 10,000 queries ==
  naive 'first non-empty ring' picked a farther driver 1118 times (avg +0.22 km) | correct rule: 0
== 2. Offer lifecycle with fencing tokens (deterministic) ==
  r1 offered driver 0, token 1; r2 requests now -> no driver (driver 0 is OFFERED)
  t=20: offer expired -> true; driver taps accept on stale token at t=21 -> false
  r2 offered (token 2); accept with old token -> false; with current token -> true; state OnTrip
== 3. Stadium surge: 8 rider threads x 2,000 requests within 0.5 km, 1 thread moving 2,000 drivers (one measured run) ==
  check-then-set claim       matched 16000 | no driver 0 | driver claimed for 2 riders at once 6161 | lost CAS races 0
  CAS claim                  matched 16000 | no driver 0 | driver claimed for 2 riders at once 0 | lost CAS races 238
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Index | Scan all drivers | Grid / geohash buckets | Grid or H3 rings with the **correct stop rule**, verified against brute force; cell size tuned to driver density |
| Claim | `if (available) assign` | `synchronized` on the driver | CAS on an immutable/packed state; losers retry the next candidate; offers carry fencing tokens and expiry |
| Movement | Update x, y fields | Lock while moving | Atomic position snapshot; add-then-remove across cells; duplicates deduplicated |
| Fairness | Nearest only | Nearest + rating | Batch matching (assign all requests in a 2 s window by min-cost matching) when the surge makes greedy globally bad |
| Testing | A demo | Unit tests | Brute-force oracle, a hotspot surge stress test, claim-time double-claim detection, a fail-loudly harness |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Use ETA, not straight-line distance" | Keep the grid for candidate generation (top-k by distance), then rank the k by an ETA service. Never call ETA for every driver |
| "Surge: greedy matching is globally bad" | Batch requests per area over a short window and solve an assignment problem (Hungarian / auction) on the candidate graph. The CAS claims stay as the commit step |
| "Pool rides (two riders, one car)" | Driver capacity becomes a counter in the state (`OnTrip(riders[], seatsLeft)`), with the CAS transitions extended; the detour constraint is a filter on candidates |
| "Cities with dense downtowns" | Hierarchical cells (H3 resolutions); search fine cells first, coarser ones outward |
| "Driver app offline mid-offer" | The offer expiry returns them to Available; a reconnect presents the old token and is rejected (I2) |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Your ring search stops at the first ring with a driver. Correct?"</b></summary>

**L5:** "Yes, rings are searched nearest-first."

**Why it fails:** ring order isn't distance order. A corner of ring r can be farther than the near edge of ring r + 1. Measured: wrong about 11% of the time.

**L7 defence:** "Points in ring r are at least (r − 1)·cell from the centre cell, so I keep expanding until (r − 1)·cell exceeds the best distance found. A brute-force oracle on 10,000 queries confirms 0 mismatches."
</details>

<details>
<summary><b>Q2 ⚡ "Two riders get matched to the same driver. How do you prevent it?"</b></summary>

**L5:** "Check the driver is available before assigning."

**Why it fails:** check-then-set under a surge produced thousands of double claims in both languages.

**L7 defence:** "The state is one atomic word or immutable object; the claim is `CAS(Available → Offered(token))`. Exactly one rider wins and the other retries its next candidate. The offer token fences a late accept."
</details>

<details>
<summary><b>Q3 🧊 "Your test hung. What happened?"</b></summary>

**L5:** "Probably a deadlock."

**Why it fails:** there were no locks to deadlock. A worker had died.

**L7 defence:** "Sorting by live positions gave an inconsistent comparator, so TimSort threw, and the dead worker never reached the barrier. I sort on a snapshot of the distances, and the harness now records worker exceptions and always reaches the barrier. Hangs become failures with stack traces."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Riders matched to farther drivers | Naive ring stop rule | `(r − 1)·cell > best` stop |
| Two riders, one driver | Check-then-set claim | CAS state transition |
| A stale accept starts a trip | No offer token | Fenced offers + expiry |
| A driver briefly unfindable | Remove-then-add on move | Add-then-remove |
| `Comparison method violates its general contract!` / hangs | Sorting on mutable data | Sort snapshots; fail-loud harness |
| Phantom double-claim alarms | Bookkeeping after publishing availability | Bookkeeping first, publish last |

- [ ] The candidate search is verified against a brute-force oracle.
- [ ] Driver state transitions are single CASes; positions are atomic snapshots.
- [ ] Offers carry fencing tokens and expiry; accepts validate both.
- [ ] Cell moves are add-before-remove; candidates are deduplicated.
- [ ] Surge stress tests use a hotspot, detect violations at claim time, and fail loudly.

## 10. References

- Uber Engineering, "H3: Uber's Hexagonal Hierarchical Spatial Index". <https://www.uber.com/blog/h3/>
- H3 documentation. <https://h3geo.org/docs/>
- Java `Comparator` contract and TimSort's `IllegalArgumentException`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Comparator.html>
- In this KB: [01.1 Fencing tokens](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md) · [P7 Publication order](02-problem-07-multi-floor-parking-lot-concurrent-bitmask-and-pricing.md) · [01.3 Stress harness](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md)
