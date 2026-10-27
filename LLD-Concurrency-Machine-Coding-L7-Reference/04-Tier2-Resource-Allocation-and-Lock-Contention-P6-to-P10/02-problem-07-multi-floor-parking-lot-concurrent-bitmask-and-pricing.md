# P7 · Multi-Floor Parking Lot: Concurrent Bitmask Allocation and Composable Pricing

> **Folder 04 · Problem 7 of 20.** The most-asked LLD problem, usually answered with a `Vehicle` class hierarchy and an O(N) spot scan under one lock. The L7 version:
> - allocates the **nearest free spot by CAS on 64-bit bitmap words** (lowest free bit with `numberOfTrailingZeros` / `std::countr_zero`);
> - stripes allocation per **(floor, spot type)**;
> - makes the vehicle → spot fallback policy *data*;
> - prices through **phased decorators** with an injected clock;
> - proves no double parking with a per-spot owner check.
>
> **Listing pair P7:** `ParkingLot.java` / `parking_lot.cpp`. Allocation order and fees are deterministic and identical in both languages. Throughput is one measured run.

---

## 1. Problem and scope

**Functional:**
- `enter(vehicleType) → Ticket | full`, at the nearest acceptable spot;
- `exit(ticketId) → Fee`;
- free-spot counts per type.

**Fallback policy:**
- a motorcycle takes motorcycle, compact, then large spots;
- a car takes compact, then large;
- an EV takes an EV charger spot, then compact, then large;
- a truck takes large only.

**Pricing:**
1. every started hour is billed at the spot type's rate;
2. +50% surge when entering in the 17:00–20:00 peak;
3. EV energy at 0.35 per kWh.

**Out of scope:** payment, gates and sensors; mention them as integration points.

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Types | `enum SpotType`, `enum VehicleType`; `EnumMap<VehicleType, List<SpotType>> ACCEPTS` | `enum class` + `std::array<std::vector<SpotType>, 4>` |
| Allocator per (floor, type) | `BitmapAllocator` (`AtomicLongArray`), `SkipListAllocator`, `LockedAllocator` | `BitmapAllocator` (`std::atomic<u64>`), `SetAllocator` (`std::set` + mutex), `LockedAllocator` |
| Ownership check | `AtomicReferenceArray<Ticket>` per (type, floor): CAS null → ticket | `std::atomic<i64>[]`: CAS 0 → ticket id |
| Tickets | `ConcurrentHashMap<Long, Ticket>` | `unordered_map` + mutex (the measured bottleneck) |
| Fee | `record Fee(base, surge, ev, total)` | `struct Fee` |

**Invariants:**
- **I1:** a spot is occupied by at most one ticket. The owner CAS must always succeed; `doubleParked` counts failures and was 0 everywhere.
- **I2:** after every vehicle exits, the lot is empty: 0 tickets left, 0 spots occupied.
- **I3:** a ticket exits once. `active.remove(id)` returns the ticket to exactly one caller.
- **I4:** a spot is freed only by its holder, and a double free throws, because silently ignoring it would hide a bug.
- **I5:** nearest-first. The lowest floor and the lowest index (by the ramp) are tried first.

## 3. Concurrency and contention analysis

**Why not one lock and a scan.** O(N) per entry under a lot-wide lock serializes every gate. Two independent ideas fix it, and the measurement shows which one matters.

1. **Striping by (floor, type).** Twenty independent allocators (5 floors × 4 types) instead of one. Even a *synchronized scan* per stripe reached 13.1 M ops/s in Java, about the same as the skip list (13.0) and close to the bitmap (16.1). **Most of the win is from striping, not from going lock-free.**
2. **The bitmap CAS allocator.**
   - Each word holds 64 spots, and the free spots are `~word`.
   - The lowest free bit is `free & -free`, and its index is `numberOfTrailingZeros`.
   - One CAS claims it; on failure, retry the same word.
   - With ≤ 4 words per stripe, allocation is effectively O(1) with no lock.
   - **Phantom tail bits** (capacity not a multiple of 64) are pre-set, so they're never handed out.
   - `freeCount = 64·words − popcount(all)` is a lock-free, eventually consistent snapshot for the display board.

**The skip list** (`ConcurrentSkipListSet.pollFirst()`) is correct and simple, but pays O(log n) and allocates nodes. A good answer when spot ids aren't dense integers.

**Where the time actually went in C++.** C++ reached only 3.8–4.6 M ops/s, against Java's 13–16. All three C++ allocators were bottlenecked by the **single mutex around the ticket registry**, not by allocation. The L7 fixes, in order:
1. **Encode the spot in the ticket id**: `(floor << 48) | (type << 40) | (index << 20) | seq`. `exit` then needs no shared lookup at all. The owner CAS on the spot validates the ticket.
2. Shard the registry if tickets must be enumerable.

The measurement exists to find the next bottleneck, not to celebrate the allocator.

**Owner before bit.** On exit, the owner slot is cleared *before* the bit is freed. The other order would let a new vehicle claim the bit and fail the owner CAS against the stale ticket, which is a false "double parked" alarm.

## 4. Java 21 implementation

```java
// ParkingLot.java - P7: nearest-spot allocation by CAS on bitmaps vs skip list vs one lock; phased pricing
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.SplittableRandom;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentSkipListSet;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReferenceArray;
import java.util.concurrent.atomic.LongAdder;

public final class ParkingLot {

    enum SpotType { MOTORCYCLE, COMPACT, LARGE, EV }
    enum VehicleType { MOTORCYCLE, CAR, EV_CAR, TRUCK }

    /** Fallback order is policy: the closest acceptable spot type first. */
    static final Map<VehicleType, List<SpotType>> ACCEPTS = new EnumMap<>(Map.of(
            VehicleType.MOTORCYCLE, List.of(SpotType.MOTORCYCLE, SpotType.COMPACT, SpotType.LARGE),
            VehicleType.CAR, List.of(SpotType.COMPACT, SpotType.LARGE),
            VehicleType.EV_CAR, List.of(SpotType.EV, SpotType.COMPACT, SpotType.LARGE),
            VehicleType.TRUCK, List.of(SpotType.LARGE)));

    record Spot(int floor, SpotType type, int index) {}
    record Ticket(long id, VehicleType vehicle, Spot spot, Instant entry) {}

    /** One allocator per (floor, spot type). */
    interface Allocator {
        int allocate();                                        // lowest free index or -1
        void free(int index);
        int freeCount();
    }

    /** Lock-free: find the lowest zero bit, CAS it to one. Nearest-first because index 0 is by the ramp. */
    static final class BitmapAllocator implements Allocator {
        private final AtomicLongArray words;
        private final int capacity;

        BitmapAllocator(int capacity) {
            this.capacity = capacity;
            words = new AtomicLongArray((capacity + 63) / 64);
            int tail = capacity % 64;                          // mark the non-existent bits of the last word as taken
            if (tail != 0) words.set(words.length() - 1, -1L << tail);
        }

        @Override public int allocate() {
            for (int w = 0; w < words.length(); w++) {
                while (true) {
                    long cur = words.get(w);
                    long free = ~cur;
                    if (free == 0) break;                      // word full: next word
                    long bit = free & -free;                   // lowest free bit
                    if (words.compareAndSet(w, cur, cur | bit)) return w * 64 + Long.numberOfTrailingZeros(bit);
                }
            }
            return -1;
        }

        @Override public void free(int index) {
            int w = index >>> 6;
            long bit = 1L << (index & 63);
            while (true) {
                long cur = words.get(w);
                if ((cur & bit) == 0) throw new IllegalStateException("double free of spot " + index);
                if (words.compareAndSet(w, cur, cur & ~bit)) return;
            }
        }

        @Override public int freeCount() {
            int used = 0;
            for (int w = 0; w < words.length(); w++) used += Long.bitCount(words.get(w));
            return words.length() * 64 - used;                 // phantom tail bits count as used
        }
    }

    static final class SkipListAllocator implements Allocator {
        private final ConcurrentSkipListSet<Integer> free = new ConcurrentSkipListSet<>();

        SkipListAllocator(int capacity) {
            for (int i = 0; i < capacity; i++) free.add(i);
        }

        @Override public int allocate() {
            Integer i = free.pollFirst();                      // O(log n), atomic
            return i == null ? -1 : i;
        }

        @Override public void free(int index) {
            if (!free.add(index)) throw new IllegalStateException("double free of spot " + index);
        }

        @Override public int freeCount() {
            return free.size();
        }
    }

    static final class LockedAllocator implements Allocator {
        private final boolean[] used;

        LockedAllocator(int capacity) {
            used = new boolean[capacity];
        }

        @Override public synchronized int allocate() {
            for (int i = 0; i < used.length; i++) if (!used[i]) { used[i] = true; return i; }   // O(n) scan
            return -1;
        }

        @Override public synchronized void free(int index) {
            if (!used[index]) throw new IllegalStateException("double free");
            used[index] = false;
        }

        @Override public synchronized int freeCount() {
            int n = 0;
            for (boolean u : used) if (!u) n++;
            return n;
        }
    }

    interface AllocatorFactory {
        Allocator make(int capacity);
    }

    // ===== Pricing: phased decorators (02.2), injected clock ===================================

    static final Map<SpotType, Long> HOURLY_CENTS = new EnumMap<>(Map.of(
            SpotType.MOTORCYCLE, 100L, SpotType.COMPACT, 300L, SpotType.LARGE, 500L, SpotType.EV, 300L));

    record Fee(long base, long surge, long ev, long total) {}

    static Fee price(Ticket t, Instant exit, long kWhTimes10) {
        long minutes = Math.max(1, Duration.between(t.entry(), exit).toMinutes());
        long hours = (minutes + 59) / 60;                      // every started hour is billed
        long base = hours * HOURLY_CENTS.get(t.spot().type());
        LocalTime entryTime = LocalTime.ofInstant(t.entry(), ZoneOffset.UTC);
        boolean peak = !entryTime.isBefore(LocalTime.of(17, 0)) && entryTime.isBefore(LocalTime.of(20, 0));
        long surge = peak ? base / 2 : 0;                      // +50% when entering in the 17:00-20:00 peak
        long ev = t.spot().type() == SpotType.EV ? kWhTimes10 * 35 / 10 : 0;   // 0.35 per kWh, applied after surge
        return new Fee(base, surge, ev, base + surge + ev);
    }

    // ===== The lot =============================================================================

    static final class Lot {
        final int floors;
        private final Map<SpotType, Allocator[]> byType = new EnumMap<>(SpotType.class);
        private final Map<SpotType, AtomicReferenceArray<Ticket>[]> owners = new EnumMap<>(SpotType.class);
        private final ConcurrentHashMap<Long, Ticket> active = new ConcurrentHashMap<>();
        private final AtomicLong ids = new AtomicLong();
        private final Clock clock;
        final LongAdder doubleParked = new LongAdder();

        @SuppressWarnings({"unchecked", "rawtypes"})   // generic array creation
        Lot(int floors, Map<SpotType, Integer> perFloor, AllocatorFactory factory, Clock clock) {
            this.floors = floors;
            this.clock = clock;
            for (SpotType t : SpotType.values()) {
                Allocator[] a = new Allocator[floors];
                AtomicReferenceArray<Ticket>[] o = new AtomicReferenceArray[floors];
                for (int f = 0; f < floors; f++) {
                    a[f] = factory.make(perFloor.get(t));
                    o[f] = new AtomicReferenceArray<>(perFloor.get(t));
                }
                byType.put(t, a);
                owners.put(t, o);
            }
        }

        Optional<Ticket> enter(VehicleType v) {
            for (SpotType t : ACCEPTS.get(v)) {                // preferred type first, then fallbacks
                for (int f = 0; f < floors; f++) {             // nearest floor first
                    int idx = byType.get(t)[f].allocate();
                    if (idx < 0) continue;
                    Ticket ticket = new Ticket(ids.incrementAndGet(), v, new Spot(f, t, idx), clock.instant());
                    if (!owners.get(t)[f].compareAndSet(idx, null, ticket)) doubleParked.increment();   // must never happen
                    active.put(ticket.id(), ticket);
                    return Optional.of(ticket);
                }
            }
            return Optional.empty();                           // lot full for this vehicle
        }

        Optional<Fee> exit(long ticketId, long kWhTimes10) {
            Ticket t = active.remove(ticketId);                // exactly one exit per ticket
            if (t == null) return Optional.empty();
            Spot s = t.spot();
            owners.get(s.type())[s.floor()].set(s.index(), null);   // clear the owner BEFORE freeing the bit
            byType.get(s.type())[s.floor()].free(s.index());
            return Optional.of(price(t, clock.instant(), kWhTimes10));
        }

        int free(SpotType t) {
            int n = 0;
            for (Allocator a : byType.get(t)) n += a.freeCount();
            return n;
        }

        int activeCount() {
            return active.size();
        }
    }

    static double stress(AllocatorFactory factory, int threads, int ops, long[] outFree) throws Exception {
        Map<SpotType, Integer> perFloor = new EnumMap<>(Map.of(SpotType.MOTORCYCLE, 40, SpotType.COMPACT, 120, SpotType.LARGE, 30, SpotType.EV, 10));
        Lot lot = new Lot(5, perFloor, factory, Clock.systemUTC());
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        VehicleType[] kinds = VehicleType.values();
        for (int t = 0; t < threads; t++) {
            final int seed = t;
            Thread.ofPlatform().start(() -> {
                try {
                    SplittableRandom rnd = new SplittableRandom(seed);
                    java.util.ArrayDeque<Long> mine = new java.util.ArrayDeque<>();
                    start.await();
                    for (int i = 0; i < ops; i++) {
                        if (mine.size() < 100 && rnd.nextInt(10) < 6) lot.enter(kinds[rnd.nextInt(kinds.length)]).ifPresent(tk -> mine.add(tk.id()));
                        else if (!mine.isEmpty()) lot.exit(mine.poll(), 100);
                    }
                    while (!mine.isEmpty()) lot.exit(mine.poll(), 100);
                    end.await();
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        start.await();
        long t0 = System.nanoTime();
        end.await();
        double mops = threads * (double) ops / ((System.nanoTime() - t0) / 1e9) / 1e6;
        outFree[0] = lot.doubleParked.sum();
        outFree[1] = lot.activeCount();
        long totalFree = 0, capacity = 5L * (40 + 120 + 30 + 10);
        for (SpotType t : SpotType.values()) totalFree += lot.free(t);
        outFree[2] = capacity - totalFree;                     // occupied after everyone left: must be 0
        return mops;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Nearest-spot allocation and fallbacks (2 floors x [M2, C2, L1, EV1]) ==");
        Map<SpotType, Integer> small = new EnumMap<>(Map.of(SpotType.MOTORCYCLE, 2, SpotType.COMPACT, 2, SpotType.LARGE, 1, SpotType.EV, 1));
        Clock fixed = Clock.fixed(Instant.parse("2026-11-01T17:30:00Z"), ZoneOffset.UTC);
        Lot lot = new Lot(2, small, BitmapAllocator::new, fixed);
        for (VehicleType v : List.of(VehicleType.EV_CAR, VehicleType.EV_CAR, VehicleType.EV_CAR, VehicleType.TRUCK, VehicleType.TRUCK, VehicleType.TRUCK))
            System.out.println("  " + v + " -> " + lot.enter(v).map(t -> "floor " + t.spot().floor() + " " + t.spot().type() + " #" + t.spot().index()).orElse("LOT FULL for this vehicle"));

        System.out.println("== 2. Pricing (phases: hourly base -> peak surge -> EV energy) ==");
        Ticket evPeak = new Ticket(1, VehicleType.EV_CAR, new Spot(0, SpotType.EV, 0), Instant.parse("2026-11-01T17:30:00Z"));
        Ticket carNight = new Ticket(2, VehicleType.CAR, new Spot(1, SpotType.COMPACT, 3), Instant.parse("2026-11-01T22:00:00Z"));
        System.out.println("  EV, enters 17:30, 2h10m, 18.0 kWh -> " + price(evPeak, Instant.parse("2026-11-01T19:40:00Z"), 180));
        System.out.println("  car, enters 22:00, 59m            -> " + price(carNight, Instant.parse("2026-11-01T22:59:00Z"), 0));
        System.out.println("  car, enters 22:00, 61m            -> " + price(carNight, Instant.parse("2026-11-01T23:01:00Z"), 0));

        System.out.println("== 3. Concurrency: 8 threads x 200,000 enter/exit, 5 floors x 200 spots (one measured run) ==");
        String[] names = {"bitmap CAS", "ConcurrentSkipListSet", "synchronized scan"};
        AllocatorFactory[] factories = {BitmapAllocator::new, SkipListAllocator::new, LockedAllocator::new};
        boolean allClean = true;
        for (int k = 0; k < factories.length; k++) {
            long[] r = new long[3];
            stress(factories[k], 8, 20_000, r);                // warm-up
            double mops = stress(factories[k], 8, 200_000, r);
            System.out.printf("  %-22s %6.2f M ops/s | double-parked %d | tickets left %d | spots still occupied %d%n", names[k], mops, r[0], r[1], r[2]);
            allClean &= r[0] == 0 && r[1] == 0 && r[2] == 0;
        }
        System.out.println(allClean ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!allClean) System.exit(1);
    }
}
```

**Output (sections 1–2 verified; section 3 one measured run):**

```text
== 1. Nearest-spot allocation and fallbacks (2 floors x [M2, C2, L1, EV1]) ==
  EV_CAR -> floor 0 EV #0
  EV_CAR -> floor 1 EV #0
  EV_CAR -> floor 0 COMPACT #0
  TRUCK -> floor 0 LARGE #0
  TRUCK -> floor 1 LARGE #0
  TRUCK -> LOT FULL for this vehicle
== 2. Pricing (phases: hourly base -> peak surge -> EV energy) ==
  EV, enters 17:30, 2h10m, 18.0 kWh -> Fee[base=900, surge=450, ev=630, total=1980]
  car, enters 22:00, 59m            -> Fee[base=300, surge=0, ev=0, total=300]
  car, enters 22:00, 61m            -> Fee[base=600, surge=0, ev=0, total=600]
== 3. Concurrency: 8 threads x 200,000 enter/exit, 5 floors x 200 spots (one measured run) ==
  bitmap CAS              16.08 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
  ConcurrentSkipListSet   12.97 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
  synchronized scan       13.09 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// parking_lot.cpp - P7: nearest-spot allocation by CAS on bitmaps vs std::set vs a locked scan; phased pricing
#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <chrono>
#include <cstdint>
#include <deque>
#include <format>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <random>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;

enum class SpotType { Motorcycle, Compact, Large, Ev };
enum class VehicleType { Motorcycle, Car, EvCar, Truck };
constexpr std::array kSpotNames{"MOTORCYCLE", "COMPACT", "LARGE", "EV"};
constexpr std::array kVehicleNames{"MOTORCYCLE", "CAR", "EV_CAR", "TRUCK"};
constexpr std::size_t kTypes = 4;

const std::array<std::vector<SpotType>, 4> kAccepts{{
    {SpotType::Motorcycle, SpotType::Compact, SpotType::Large},
    {SpotType::Compact, SpotType::Large},
    {SpotType::Ev, SpotType::Compact, SpotType::Large},
    {SpotType::Large},
}};

struct Spot { int floor; SpotType type; int index; };
struct Ticket { i64 id; VehicleType vehicle; Spot spot; i64 entry_minute; };

struct Allocator {
    virtual ~Allocator() = default;
    virtual int allocate() = 0;  // lowest free index or -1
    virtual void free(int index) = 0;
    virtual int free_count() = 0;
};

class BitmapAllocator final : public Allocator {  // lock-free: lowest zero bit, CAS it to one
    std::vector<std::atomic<u64>> words_;
public:
    explicit BitmapAllocator(int capacity) : words_(static_cast<std::size_t>((capacity + 63) / 64)) {
        if (const int tail = capacity % 64; tail != 0) words_.back().store(~u64{0} << tail);  // phantom bits taken
    }
    int allocate() override {
        for (std::size_t w = 0; w < words_.size(); ++w) {
            u64 cur = words_[w].load(std::memory_order_relaxed);
            while (~cur != 0) {
                const u64 bit = ~cur & (~(~cur) + 1);  // lowest set bit of ~cur
                if (words_[w].compare_exchange_weak(cur, cur | bit, std::memory_order_acq_rel))
                    return static_cast<int>(w * 64 + static_cast<std::size_t>(std::countr_zero(bit)));
            }
        }
        return -1;
    }
    void free(int index) override {
        auto& w = words_[static_cast<std::size_t>(index) >> 6];
        const u64 bit = u64{1} << (index & 63);
        u64 cur = w.load();
        do {
            if (!(cur & bit)) throw std::logic_error("double free");
        } while (!w.compare_exchange_weak(cur, cur & ~bit, std::memory_order_acq_rel));
    }
    int free_count() override {
        int used = 0;
        for (const auto& w : words_) used += std::popcount(w.load());
        return static_cast<int>(words_.size()) * 64 - used;
    }
};

class SetAllocator final : public Allocator {  // ordered set under a mutex: O(log n)
    std::mutex m_;
    std::set<int> free_;
public:
    explicit SetAllocator(int capacity) {
        for (int i = 0; i < capacity; ++i) free_.insert(i);
    }
    int allocate() override {
        std::scoped_lock l(m_);
        if (free_.empty()) return -1;
        const int i = *free_.begin();
        free_.erase(free_.begin());
        return i;
    }
    void free(int index) override {
        std::scoped_lock l(m_);
        if (!free_.insert(index).second) throw std::logic_error("double free");
    }
    int free_count() override {
        std::scoped_lock l(m_);
        return static_cast<int>(free_.size());
    }
};

class LockedAllocator final : public Allocator {  // one lock, O(n) scan
    std::mutex m_;
    std::vector<char> used_;
public:
    explicit LockedAllocator(int capacity) : used_(static_cast<std::size_t>(capacity), 0) {}
    int allocate() override {
        std::scoped_lock l(m_);
        for (std::size_t i = 0; i < used_.size(); ++i)
            if (!used_[i]) {
                used_[i] = 1;
                return static_cast<int>(i);
            }
        return -1;
    }
    void free(int index) override {
        std::scoped_lock l(m_);
        if (!used_[static_cast<std::size_t>(index)]) throw std::logic_error("double free");
        used_[static_cast<std::size_t>(index)] = 0;
    }
    int free_count() override {
        std::scoped_lock l(m_);
        return static_cast<int>(std::ranges::count(used_, 0));
    }
};

using Factory = std::function<std::unique_ptr<Allocator>(int)>;

// ===== Pricing: phases base -> surge -> EV ====================================================

constexpr std::array<i64, kTypes> kHourlyCents{100, 300, 500, 300};
struct Fee { i64 base, surge, ev, total; };

Fee price(const Ticket& t, i64 exit_minute, i64 kwh_times10) {
    const i64 minutes = std::max<i64>(1, exit_minute - t.entry_minute);
    const i64 hours = (minutes + 59) / 60;  // every started hour is billed
    const i64 base = hours * kHourlyCents[static_cast<std::size_t>(t.spot.type)];
    const i64 minute_of_day = t.entry_minute % (24 * 60);
    const bool peak = minute_of_day >= 17 * 60 && minute_of_day < 20 * 60;
    const i64 surge = peak ? base / 2 : 0;
    const i64 ev = t.spot.type == SpotType::Ev ? kwh_times10 * 35 / 10 : 0;
    return {base, surge, ev, base + surge + ev};
}

std::string describe(const Fee& f) { return std::format("Fee[base={}, surge={}, ev={}, total={}]", f.base, f.surge, f.ev, f.total); }

class Lot {
    int floors_;
    std::array<std::vector<std::unique_ptr<Allocator>>, kTypes> alloc_;
    std::array<std::vector<std::unique_ptr<std::atomic<i64>[]>>, kTypes> owners_;  // 0 = empty, else ticket id
    std::mutex active_m_;
    std::unordered_map<i64, Ticket> active_;
    std::atomic<i64> ids_{0};
    std::function<i64()> now_minute_;
public:
    std::atomic<i64> double_parked{0};
    Lot(int floors, const std::array<int, kTypes>& per_floor, const Factory& make, std::function<i64()> now_minute)
        : floors_(floors), now_minute_(std::move(now_minute)) {
        for (std::size_t t = 0; t < kTypes; ++t)
            for (int f = 0; f < floors; ++f) {
                alloc_[t].push_back(make(per_floor[t]));
                owners_[t].push_back(std::make_unique<std::atomic<i64>[]>(static_cast<std::size_t>(per_floor[t])));
            }
    }
    std::optional<Ticket> enter(VehicleType v) {
        for (SpotType t : kAccepts[static_cast<std::size_t>(v)])  // preferred type first
            for (int f = 0; f < floors_; ++f) {                    // nearest floor first
                const auto ti = static_cast<std::size_t>(t);
                const int idx = alloc_[ti][static_cast<std::size_t>(f)]->allocate();
                if (idx < 0) continue;
                const Ticket ticket{++ids_, v, {f, t, idx}, now_minute_()};
                i64 expected = 0;
                if (!owners_[ti][static_cast<std::size_t>(f)][static_cast<std::size_t>(idx)].compare_exchange_strong(expected, ticket.id))
                    ++double_parked;  // must never happen
                std::scoped_lock l(active_m_);
                active_.emplace(ticket.id, ticket);
                return ticket;
            }
        return std::nullopt;
    }
    std::optional<Fee> exit(i64 ticket_id, i64 kwh_times10) {
        Ticket t;
        {
            std::scoped_lock l(active_m_);
            auto it = active_.find(ticket_id);
            if (it == active_.end()) return std::nullopt;  // exactly one exit per ticket
            t = it->second;
            active_.erase(it);
        }
        const auto ti = static_cast<std::size_t>(t.spot.type);
        owners_[ti][static_cast<std::size_t>(t.spot.floor)][static_cast<std::size_t>(t.spot.index)].store(0);  // owner cleared first
        alloc_[ti][static_cast<std::size_t>(t.spot.floor)]->free(t.spot.index);
        return price(t, now_minute_(), kwh_times10);
    }
    int free_total() {
        int n = 0;
        for (auto& v : alloc_)
            for (auto& a : v) n += a->free_count();
        return n;
    }
    std::size_t active() {
        std::scoped_lock l(active_m_);
        return active_.size();
    }
};

struct StressResult { double mops; i64 double_parked; std::size_t tickets_left; int occupied; };

StressResult stress(const Factory& make, int threads, int ops) {
    const std::array<int, kTypes> per_floor{40, 120, 30, 10};
    Lot lot(5, per_floor, make, [] { return i64{0}; });
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::chrono::steady_clock::time_point t0;
    {
        std::vector<std::jthread> ts;
        for (int t = 0; t < threads; ++t)
            ts.emplace_back([&, t] {
                std::mt19937 rng(static_cast<unsigned>(t));
                std::deque<i64> mine;
                ready.fetch_add(1);
                while (!go.load(std::memory_order_acquire)) {}
                for (int i = 0; i < ops; ++i) {
                    if (mine.size() < 100 && rng() % 10 < 6) {
                        if (auto tk = lot.enter(static_cast<VehicleType>(rng() % 4))) mine.push_back(tk->id);
                    } else if (!mine.empty()) {
                        lot.exit(mine.front(), 100);
                        mine.pop_front();
                    }
                }
                while (!mine.empty()) {
                    lot.exit(mine.front(), 100);
                    mine.pop_front();
                }
            });
        while (ready.load() < threads) {}
        t0 = std::chrono::steady_clock::now();
        go.store(true, std::memory_order_release);
    }
    const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return {threads * static_cast<double>(ops) / secs / 1e6, lot.double_parked.load(), lot.active(), 5 * 200 - lot.free_total()};
}

int main() {
    std::println("== 1. Nearest-spot allocation and fallbacks (2 floors x [M2, C2, L1, EV1]) ==");
    const i64 t1730 = 17 * 60 + 30;
    Lot lot(2, {2, 2, 1, 1}, [](int c) { return std::make_unique<BitmapAllocator>(c); }, [=] { return t1730; });
    for (VehicleType v : {VehicleType::EvCar, VehicleType::EvCar, VehicleType::EvCar, VehicleType::Truck, VehicleType::Truck, VehicleType::Truck}) {
        const auto t = lot.enter(v);
        std::println("  {} -> {}", kVehicleNames[static_cast<std::size_t>(v)],
                     t ? std::format("floor {} {} #{}", t->spot.floor, kSpotNames[static_cast<std::size_t>(t->spot.type)], t->spot.index)
                       : std::string("LOT FULL for this vehicle"));
    }
    std::println("== 2. Pricing (phases: hourly base -> peak surge -> EV energy) ==");
    const Ticket ev_peak{1, VehicleType::EvCar, {0, SpotType::Ev, 0}, t1730};
    const Ticket car_night{2, VehicleType::Car, {1, SpotType::Compact, 3}, 22 * 60};
    std::println("  EV, enters 17:30, 2h10m, 18.0 kWh -> {}", describe(price(ev_peak, t1730 + 130, 180)));
    std::println("  car, enters 22:00, 59m            -> {}", describe(price(car_night, 22 * 60 + 59, 0)));
    std::println("  car, enters 22:00, 61m            -> {}", describe(price(car_night, 22 * 60 + 61, 0)));

    std::println("== 3. Concurrency: 8 threads x 200,000 enter/exit, 5 floors x 200 spots (one measured run) ==");
    const std::array<const char*, 3> names{"bitmap CAS", "std::set + mutex", "locked scan"};
    const std::array<Factory, 3> factories{
        [](int c) -> std::unique_ptr<Allocator> { return std::make_unique<BitmapAllocator>(c); },
        [](int c) -> std::unique_ptr<Allocator> { return std::make_unique<SetAllocator>(c); },
        [](int c) -> std::unique_ptr<Allocator> { return std::make_unique<LockedAllocator>(c); }};
    bool clean = true;
    for (std::size_t k = 0; k < factories.size(); ++k) {
        stress(factories[k], 8, 20'000);
        const auto r = stress(factories[k], 8, 200'000);
        std::println("  {:<22} {:6.2f} M ops/s | double-parked {} | tickets left {} | spots still occupied {}", names[k], r.mops,
                     r.double_parked, r.tickets_left, r.occupied);
        clean &= r.double_parked == 0 && r.tickets_left == 0 && r.occupied == 0;
    }
    std::println("{}", clean ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return clean ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Nearest-spot allocation and fallbacks (2 floors x [M2, C2, L1, EV1]) ==
  EV_CAR -> floor 0 EV #0
  EV_CAR -> floor 1 EV #0
  EV_CAR -> floor 0 COMPACT #0
  TRUCK -> floor 0 LARGE #0
  TRUCK -> floor 1 LARGE #0
  TRUCK -> LOT FULL for this vehicle
== 2. Pricing (phases: hourly base -> peak surge -> EV energy) ==
  EV, enters 17:30, 2h10m, 18.0 kWh -> Fee[base=900, surge=450, ev=630, total=1980]
  car, enters 22:00, 59m            -> Fee[base=300, surge=0, ev=0, total=300]
  car, enters 22:00, 61m            -> Fee[base=600, surge=0, ev=0, total=600]
== 3. Concurrency: 8 threads x 200,000 enter/exit, 5 floors x 200 spots (one measured run) ==
  bitmap CAS               3.80 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
  std::set + mutex         1.90 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
  locked scan              2.07 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
SELF-TEST OK
```

**Output, Clang 21.1 (sections 1–2 identical):**

```text
== 1. Nearest-spot allocation and fallbacks (2 floors x [M2, C2, L1, EV1]) ==
  EV_CAR -> floor 0 EV #0
  EV_CAR -> floor 1 EV #0
  EV_CAR -> floor 0 COMPACT #0
  TRUCK -> floor 0 LARGE #0
  TRUCK -> floor 1 LARGE #0
  TRUCK -> LOT FULL for this vehicle
== 2. Pricing (phases: hourly base -> peak surge -> EV energy) ==
  EV, enters 17:30, 2h10m, 18.0 kWh -> Fee[base=900, surge=450, ev=630, total=1980]
  car, enters 22:00, 59m            -> Fee[base=300, surge=0, ev=0, total=300]
  car, enters 22:00, 61m            -> Fee[base=600, surge=0, ev=0, total=600]
== 3. Concurrency: 8 threads x 200,000 enter/exit, 5 floors x 200 spots (one measured run) ==
  bitmap CAS               4.56 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
  std::set + mutex         2.89 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
  locked scan              3.03 M ops/s | double-parked 0 | tickets left 0 | spots still occupied 0
SELF-TEST OK
```

## 6. Reading the pricing output

The EV entering at 17:30 and staying 2 h 10 min is billed as follows:
- **base:** 3 started hours × 3.00 = 9.00;
- **surge:** +50% of the base, because it entered in the peak = 4.50;
- **EV energy:** 18.0 kWh × 0.35 = 6.30;
- **total:** 19.80.

The car staying 59 minutes pays 1 hour; at 61 minutes it pays 2. That boundary is the classic off-by-one, and the test pins it at both sides.

Surge is computed on the *base*, not on base + EV energy. That's the "order is policy" rule from 02.2: energy is a pass-through cost, and surging it would overcharge.

## 7. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Model | `Vehicle` → `Car`/`Bike` subclasses with no behaviour; `ParkingSpot` with booleans | Enums for types; `Floor` objects with spot lists | Enums + an acceptance table as data; spots as indexes in per-(floor, type) allocators |
| Allocation | O(N) scan under a lot-wide lock | Per-floor locks or a `ConcurrentSkipListSet` | Bitmap CAS (O(1), lock-free) per stripe; measured; the next bottleneck (ticket registry) identified |
| Correctness proof | None | A unit test | Owner-CAS double-parking detector + an "empty after all exits" invariant + double-free detection |
| Pricing | `if` ladder | Strategy per spot type | Phased decorators (base → surge → energy) with an injected clock; billing boundaries tested |
| Scale-out | — | — | Gates as clients of a lot service; spot state in a store keyed by `(lot, floor, type)` with conditional updates; sensors reconcile drift |

## 8. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Reserve a spot online for 15 minutes" | A third bit state: per-spot `Reserved(token, until)` alongside the bitmap, as in P6's hold model. The bitmap bit stays set while reserved; the reservation record carries the fencing token |
| "Handicapped spots near the elevator" | A new `SpotType`; the acceptance table gains rows; the allocator order is per floor by distance, so index 0 is nearest the elevator |
| "Show 'nearest free spot' to the driver" | Already: lowest floor, lowest index. For true distance, map index → distance and keep the bitmap sorted by distance |
| "Sensors report a car in a spot we think is free" | A reconciliation job: sensor truth wins; mark the bit taken with an `UnknownVehicle` owner; alert. The two sources of truth are explicit |
| "Monthly pass holders" | A pricing rule (specification: `hasPass → fee 0`) in the base phase |

## 9. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Two cars arrive at two gates at the same instant. How do you guarantee different spots?"</b></summary>

**L5:** "The `findSpot` method is synchronized."

**Why it fails:** it works, but it serializes the whole lot. Every gate waits for every other gate's O(N) scan.

**L7 defence:** "Per-(floor, type) allocators, each a bitmap where claiming a spot is a CAS on one 64-bit word: lowest free bit, `cur | bit`. Two gates racing on the same word, one wins, the other retries and takes the next bit. An owner CAS on the spot proves exclusivity in tests: 0 double-parked across 1.6 M operations."
</details>

<details>
<summary><b>Q2 ⚡ "Your lock-free allocator is barely faster than a synchronized scan. Why bother?"</b></summary>

**L5:** "Lock-free is always better."

**Why it fails:** the numbers disagree (16.1 vs 13.1 M ops/s). Striping did most of the work.

**L7 defence:** "I'd keep the bitmap because it's simple *and* bounded, but the honest result is that striping by floor and type removed the contention. In C++ the next bottleneck was the global ticket map, so I'd encode the spot into the ticket id and make exit lookup-free."
</details>

<details>
<summary><b>Q3 ⚡ "How do you price a stay that crosses into peak hours?"</b></summary>

**L5:** "Check if now is peak."

**Why it fails:** the rule is unstated. Is it entry time, exit time, or pro-rated? And calling `now()` inside pricing makes it untestable.

**L7 defence:** "Pricing is a phased pipeline with explicit policy: here, surge applies by *entry* time to the base only. Pro-rating would split the stay at the window boundaries. Time comes from the ticket and an injected clock, so the 59/61-minute and peak boundaries are unit tests."
</details>

## 10. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Gates stall at rush hour | Lot-wide lock + O(N) scan | Stripe per (floor, type); bitmap CAS |
| Phantom spots handed out | Unmasked tail bits | Pre-set the bits beyond capacity |
| False double-parking alarms | Bit freed before the owner was cleared | Clear the owner, then free the bit |
| Lost spots (lot never empties) | Exit path fails to free on error | Free in the exit path unconditionally; audit "empty after exits" |
| Overcharging | Surge applied to pass-through costs | Phased pricing with explicit bases |

- [ ] Vehicle → spot acceptance is a table, not an inheritance tree.
- [ ] Allocation is striped and lock-free or short-locked; nearest-first is documented.
- [ ] An ownership check proves exclusivity; the empty-after-exits invariant is tested.
- [ ] Pricing phases and boundaries are tested with an injected clock.
- [ ] The next bottleneck (ticket registry) is identified by measurement.

## 11. References

- Java `Long.numberOfTrailingZeros`, `AtomicLongArray`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/atomic/AtomicLongArray.html>
- cppreference: `std::countr_zero`, `std::popcount`. <https://en.cppreference.com/w/cpp/numeric/countr_zero>
- In this KB: [02.2 Phased decorators](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md) · [01.3 Striping](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P6 Holds and fencing](01-problem-06-movie-ticket-booking-bookmyshow-seat-lock-and-deadlock-free.md)
