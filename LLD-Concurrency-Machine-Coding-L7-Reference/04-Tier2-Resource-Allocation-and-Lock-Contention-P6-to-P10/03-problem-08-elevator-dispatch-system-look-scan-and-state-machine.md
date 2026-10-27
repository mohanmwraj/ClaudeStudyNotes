# P8 · Elevator Dispatch System: Car State Machines, LOOK vs SSTF vs Destination Dispatch

> **Folder 04 · Problem 8 of 20.** The interview version asks for classes. The L7 version asks:
> - which **dispatch policy** bounds the worst wait;
> - how the system handles **concurrent hall calls** without locking every car;
> - how you **measure starvation** rather than assert it.
>
> The design here is a **single-writer controller** (cars are mutated only on the controller thread, fed by an MPSC inbox), **pluggable strategies**, and a deterministic, virtual-time simulation.
>
> **Listing pair P8:** `ElevatorSystem.java` / `elevator_system.cpp`. Every metric is deterministic and **identical in Java and C++** (and in GCC vs Clang).

---

## 1. Problem and scope

**Functional:**
- hall calls (origin floor; with destination dispatch, also the destination);
- car calls (the destination inside the cabin);
- N cars, F floors, door dwell time, capacity.

**Non-functional:**
- **no starvation** (a bounded worst wait);
- reasonable average wait and ride time;
- safe under concurrent requests from many panels;
- testable without real time.

**Out of scope:**
- motion physics (acceleration);
- fire mode;
- energy optimization (§8 curveballs).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Car | `floor`, `Dir dir`, `doorTicks`, `TreeSet<Integer> stops`, `riders`, `assigned` | same with `std::set<int>` |
| States | implicit in `(doorTicks, dir)`: DoorsOpen → Idle / MovingUp / MovingDown | same |
| Policy | `interface DispatchStrategy { assign(passenger, cars); nextDirection(car) }` | abstract `DispatchStrategy` |
| Strategies | `Sstf`, `Look`, `DestinationDispatch extends Look` (cost override) | same |
| Inbox | `ConcurrentLinkedQueue<Passenger>` | `vector` + mutex, swapped per tick |

**Invariants:**
- **I1:** every passenger is delivered exactly once. 4,000 per strategy, plus 8,000 from 8 concurrent panel threads.
- **I2:** cars never exceed capacity. Passengers left behind are re-queued as pickups once there's room.
- **I3:** only the controller thread mutates cars (single writer), so there are no locks on car state.
- **I4:** the worst-case wait is bounded under LOOK by about one full sweep up and down, plus queueing behind capacity.

## 3. Concurrency and contention analysis

**Single writer beats fine-grained locks here.** Hall panels on 20 floors and cabin buttons in N cars produce requests concurrently, but *decisions* (assigning a call, choosing a direction) need a consistent view of every car. Locking cars individually invites deadlock (an assignment reads all cars) and still needs a global decision order. So:
- panels publish to an **MPSC inbox**;
- the controller drains it once per tick, assigns calls, then steps every car;
- car state needs no synchronization at all.

That's the actor model, or LMAX's single-writer principle (P12 uses it for the order book). The 8-thread test submits 8,000 passengers concurrently while the controller runs, and all 8,000 are delivered exactly once.

**Why SSTF starves.** Shortest seek time first always serves the nearest stop. With steady traffic in floors 0–5, a call from floor 19 is always the farthest, so it waits until the low zone goes quiet. Measured with one car:

| Strategy | Avg wait (ticks) | **Max wait** | Avg ride | Stops |
|---|---|---|---|---|
| SSTF | 1,003.5 | **13,701** | 27.1 | 3,396 |
| LOOK | 68.0 | **2,523** | 18.5 | 2,808 |
| Destination dispatch | 68.0 | 2,523 | 18.5 | 2,808 |

LOOK (the "elevator algorithm") keeps moving in its direction while there are stops ahead, then reverses. Every floor is passed within one sweep each way, which bounds the wait. With one car, destination dispatch equals LOOK, because there's no assignment choice to make.

**Three cars:**

| Strategy | Avg wait | Max wait | Avg ride | Stops |
|---|---|---|---|---|
| SSTF | 6.3 | 1,043 | 13.5 | 6,334 |
| LOOK | 2.5 | 25 | 7.8 | 7,076 |
| Destination dispatch | **2.3** | 27 | **7.5** | **6,724** |

Destination dispatch knows each passenger's destination at the hall. It prefers cars that already stop at the passenger's origin and destination, which grouped riders and saved 352 stops (5%) over LOOK with a lower average wait and ride. That's why modern high-rises use destination-dispatch panels.

**A livelock found while building this.** The first version, when a full car left passengers behind, re-added the *current* floor as a stop. After the doors closed, the car saw the stop again, opened its doors, couldn't load anyone, re-added the stop, and looped forever. The simulation guard ("did not drain") caught it. The fix: re-add left-behind pickups only once there's spare capacity, which happens after someone exits. A deterministic simulation with a termination guard is how you find this class of bug.

## 4. Java 21 implementation

```java
// ElevatorSystem.java - P8: event-driven cars, pluggable dispatch (SSTF vs LOOK vs destination), starvation measured
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;

public final class ElevatorSystem {

    enum Dir { UP, DOWN, IDLE }

    record Passenger(int id, int origin, int dest, int arrival) {}

    static final int DOOR_TICKS = 2, CAPACITY = 8;

    /** One car: all mutation happens on the controller thread (single writer), so no locks. */
    static final class Car {
        final int id;
        int floor;
        Dir dir = Dir.IDLE;
        int doorTicks;
        final TreeSet<Integer> stops = new TreeSet<>();
        final List<Passenger> riders = new ArrayList<>();
        final List<Passenger> assigned = new ArrayList<>();   // waiting passengers this car must pick up
        int stopsMade;

        Car(int id, int floor) {
            this.id = id;
            this.floor = floor;
        }
    }

    /** The pluggable part: who answers a hall call, and where a car heads next. */
    interface DispatchStrategy {
        int assign(Passenger p, Car[] cars, int floors);
        Dir nextDirection(Car c);
    }

    /** Shortest seek time first: nearest car, nearest stop. Efficient locally, starves far floors. */
    static final class Sstf implements DispatchStrategy {
        public int assign(Passenger p, Car[] cars, int floors) {
            int best = 0;
            for (int i = 1; i < cars.length; i++)
                if (Math.abs(cars[i].floor - p.origin()) < Math.abs(cars[best].floor - p.origin())) best = i;
            return best;
        }

        public Dir nextDirection(Car c) {
            if (c.stops.isEmpty()) return Dir.IDLE;
            Integer up = c.stops.ceiling(c.floor), down = c.stops.floor(c.floor);
            if (up == null) return Dir.DOWN;
            if (down == null) return Dir.UP;
            return up - c.floor <= c.floor - down ? Dir.UP : Dir.DOWN;
        }
    }

    /** LOOK: keep going while there are stops ahead, then reverse. Bounded wait: one sweep each way. */
    static class Look implements DispatchStrategy {
        int cost(Car c, Passenger p, int floors) {
            int d = Math.abs(c.floor - p.origin());
            boolean onTheWay = c.dir == Dir.IDLE || (c.dir == Dir.UP && p.origin() >= c.floor) || (c.dir == Dir.DOWN && p.origin() <= c.floor);
            return d + (onTheWay ? 0 : 2 * floors) + 2 * c.stops.size();
        }

        public int assign(Passenger p, Car[] cars, int floors) {
            int best = 0;
            for (int i = 1; i < cars.length; i++) if (cost(cars[i], p, floors) < cost(cars[best], p, floors)) best = i;
            return best;
        }

        public Dir nextDirection(Car c) {
            if (c.stops.isEmpty()) return Dir.IDLE;
            boolean ahead = switch (c.dir) {
                case UP -> c.stops.ceiling(c.floor + 1) != null;
                case DOWN -> c.stops.floor(c.floor - 1) != null;
                case IDLE -> false;
            };
            if (ahead) return c.dir;
            return c.stops.ceiling(c.floor) != null ? Dir.UP : Dir.DOWN;
        }
    }

    /** Destination dispatch: the hall panel knows the destination, so group riders who share stops. */
    static final class DestinationDispatch extends Look {
        @Override int cost(Car c, Passenger p, int floors) {
            int base = super.cost(c, p, floors);
            if (c.stops.contains(p.dest())) base -= 4;          // no extra stop for the destination
            if (c.stops.contains(p.origin())) base -= 2;        // no extra stop for the pickup
            return base;
        }
    }

    record Metrics(double avgWait, int maxWait, double avgTrip, int stops, int delivered) {}

    static final class Building {
        final int floors;
        final Car[] cars;
        final DispatchStrategy strategy;
        final ConcurrentLinkedQueue<Passenger> inbox = new ConcurrentLinkedQueue<>();   // hall panels -> controller
        final List<Integer> waits = new ArrayList<>(), trips = new ArrayList<>();
        final int[] boardedAt;
        int tick;

        Building(int floors, int cars, DispatchStrategy s, int maxPassengers) {
            this.floors = floors;
            this.cars = new Car[cars];
            for (int i = 0; i < cars; i++) this.cars[i] = new Car(i, 0);
            this.strategy = s;
            boardedAt = new int[maxPassengers];
        }

        void submit(Passenger p) {                              // any thread
            inbox.add(p);
        }

        void step() {                                           // the controller thread only
            for (Passenger p; (p = inbox.poll()) != null; ) {
                Car c = cars[strategy.assign(p, cars, floors)];
                c.assigned.add(p);
                c.stops.add(p.origin());
            }
            for (Car c : cars) {
                if (c.doorTicks > 0) {
                    c.doorTicks--;
                    continue;
                }
                if (c.stops.contains(c.floor)) {                 // arrive: open, unload, load
                    c.stops.remove(c.floor);
                    c.stopsMade++;
                    c.doorTicks = DOOR_TICKS;
                    for (int i = c.riders.size() - 1; i >= 0; i--) {
                        Passenger r = c.riders.get(i);
                        if (r.dest() == c.floor) {
                            c.riders.remove(i);
                            trips.add(tick - boardedAt[r.id()]);
                        }
                    }
                    for (int i = 0; i < c.assigned.size() && c.riders.size() < CAPACITY; ) {
                        Passenger w = c.assigned.get(i);
                        if (w.origin() == c.floor) {
                            c.assigned.remove(i);
                            c.riders.add(w);
                            boardedAt[w.id()] = tick;
                            waits.add(tick - w.arrival());
                            c.stops.add(w.dest());
                        } else i++;
                    }
                    // Pickups left behind because the car was full: re-add their floors only once there is room
                    // again. Re-adding the CURRENT floor while full makes the car stop here forever (a livelock).
                    if (c.riders.size() < CAPACITY) for (Passenger w : c.assigned) c.stops.add(w.origin());
                    continue;
                }
                c.dir = strategy.nextDirection(c);
                if (c.dir == Dir.UP) c.floor++;
                else if (c.dir == Dir.DOWN) c.floor--;
            }
            tick++;
        }

        boolean idle() {
            for (Car c : cars) if (!c.riders.isEmpty() || !c.assigned.isEmpty() || c.doorTicks > 0) return false;
            return inbox.isEmpty();
        }

        Metrics metrics() {
            int stops = Arrays.stream(cars).mapToInt(c -> c.stopsMade).sum();
            return new Metrics(waits.stream().mapToInt(Integer::intValue).average().orElse(0),
                    waits.stream().mapToInt(Integer::intValue).max().orElse(0),
                    trips.stream().mapToInt(Integer::intValue).average().orElse(0), stops, trips.size());
        }
    }

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    /** Busy low zone (floors 0-5) all the time, plus a call from floor 19 every 400 ticks. */
    static List<Passenger> workload(int n) {
        List<Passenger> ps = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            long r = mix64(i);
            int arrival = i * 3;                                 // one passenger every 3 ticks: busy, not saturated
            int origin, dest;
            if (i % 400 == 0) {
                origin = 19;
                dest = 0;
            } else {
                origin = (int) Long.remainderUnsigned(r, 6);
                dest = (int) Long.remainderUnsigned(r >>> 16, 6);
                if (dest == origin) dest = (dest + 1) % 6;
            }
            ps.add(new Passenger(i, origin, dest, arrival));
        }
        return ps;
    }

    static Metrics simulate(DispatchStrategy s, int cars, List<Passenger> ps) {
        Building b = new Building(20, cars, s, ps.size());
        int next = 0;
        while (next < ps.size() || !b.idle()) {
            while (next < ps.size() && ps.get(next).arrival() <= b.tick) b.submit(ps.get(next++));
            b.step();
            if (b.tick > 2_000_000) throw new IllegalStateException("simulation did not drain");
        }
        return b.metrics();
    }

    public static void main(String[] args) throws Exception {
        List<Passenger> ps = workload(4_000);
        System.out.println("== 1. One car, 20 floors, 4,000 passengers (busy floors 0-5, a call from floor 19 every 400) ==");
        String[] names = {"SSTF", "LOOK", "destination dispatch"};
        DispatchStrategy[] strategies = {new Sstf(), new Look(), new DestinationDispatch()};
        Metrics[] one = new Metrics[3];
        for (int k = 0; k < 3; k++) {
            one[k] = simulate(strategies[k], 1, ps);
            System.out.printf("  %-21s avg wait %7.1f | MAX wait %6d | avg ride %5.1f | stops %,6d | delivered %,d%n",
                    names[k], one[k].avgWait(), one[k].maxWait(), one[k].avgTrip(), one[k].stops(), one[k].delivered());
        }
        System.out.println("== 2. Three cars, same workload ==");
        Metrics[] three = new Metrics[3];
        for (int k = 0; k < 3; k++) {
            three[k] = simulate(strategies[k], 3, ps);
            System.out.printf("  %-21s avg wait %7.1f | MAX wait %6d | avg ride %5.1f | stops %,6d | delivered %,d%n",
                    names[k], three[k].avgWait(), three[k].maxWait(), three[k].avgTrip(), three[k].stops(), three[k].delivered());
        }

        System.out.println("== 3. Concurrent hall panels: 8 threads submit 1,000 passengers each; one controller thread ==");
        Building b = new Building(20, 3, new Look(), 8_000);
        CountDownLatch submitted = new CountDownLatch(8);
        for (int t = 0; t < 8; t++) {
            final int base = t * 1_000;
            Thread.ofPlatform().start(() -> {
                for (int i = 0; i < 1_000; i++) {
                    long r = mix64(base + i);
                    int o = (int) Long.remainderUnsigned(r, 20), d = (int) Long.remainderUnsigned(r >>> 20, 20);
                    b.submit(new Passenger(base + i, o, d == o ? (d + 1) % 20 : d, 0));
                }
                submitted.countDown();
            });
        }
        while (submitted.getCount() > 0 || !b.idle()) b.step();  // the controller keeps stepping while panels publish
        System.out.println("  delivered " + b.metrics().delivered() + " of 8000, each exactly once: "
                + (b.trips.size() == 8_000 && b.waits.size() == 8_000));

        boolean ok = one[0].maxWait() > one[1].maxWait() && Arrays.stream(one).allMatch(m -> m.delivered() == 4_000)
                && Arrays.stream(three).allMatch(m -> m.delivered() == 4_000) && b.trips.size() == 8_000;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (verified; section 3's counts are invariants):**

```text
== 1. One car, 20 floors, 4,000 passengers (busy floors 0-5, a call from floor 19 every 400) ==
  SSTF                  avg wait  1003.5 | MAX wait  13701 | avg ride  27.1 | stops  3,396 | delivered 4,000
  LOOK                  avg wait    68.0 | MAX wait   2523 | avg ride  18.5 | stops  2,808 | delivered 4,000
  destination dispatch  avg wait    68.0 | MAX wait   2523 | avg ride  18.5 | stops  2,808 | delivered 4,000
== 2. Three cars, same workload ==
  SSTF                  avg wait     6.3 | MAX wait   1043 | avg ride  13.5 | stops  6,334 | delivered 4,000
  LOOK                  avg wait     2.5 | MAX wait     25 | avg ride   7.8 | stops  7,076 | delivered 4,000
  destination dispatch  avg wait     2.3 | MAX wait     27 | avg ride   7.5 | stops  6,724 | delivered 4,000
== 3. Concurrent hall panels: 8 threads submit 1,000 passengers each; one controller thread ==
  delivered 8000 of 8000, each exactly once: true
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// elevator_system.cpp - P8: event-driven cars, pluggable dispatch (SSTF vs LOOK vs destination), starvation measured
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <latch>
#include <memory>
#include <mutex>
#include <numeric>
#include <print>
#include <set>
#include <stdexcept>
#include <thread>
#include <vector>

using u64 = std::uint64_t;

enum class Dir { Up, Down, Idle };
struct Passenger { int id, origin, dest, arrival; };
constexpr int kDoorTicks = 2, kCapacity = 8;

struct Car {  // all mutation on the controller thread (single writer)
    int floor = 0;
    Dir dir = Dir::Idle;
    int door_ticks = 0, stops_made = 0;
    std::set<int> stops;
    std::vector<Passenger> riders, assigned;
};

struct DispatchStrategy {
    virtual ~DispatchStrategy() = default;
    virtual std::size_t assign(const Passenger& p, const std::vector<Car>& cars, int floors) const = 0;
    virtual Dir next_direction(const Car& c) const = 0;
};

struct Sstf final : DispatchStrategy {  // nearest car, nearest stop: starves far floors
    std::size_t assign(const Passenger& p, const std::vector<Car>& cars, int) const override {
        std::size_t best = 0;
        for (std::size_t i = 1; i < cars.size(); ++i)
            if (std::abs(cars[i].floor - p.origin) < std::abs(cars[best].floor - p.origin)) best = i;
        return best;
    }
    Dir next_direction(const Car& c) const override {
        if (c.stops.empty()) return Dir::Idle;
        const auto up = c.stops.lower_bound(c.floor);
        const bool has_up = up != c.stops.end();
        auto down_it = c.stops.upper_bound(c.floor);
        const bool has_down = down_it != c.stops.begin();
        if (!has_up) return Dir::Down;
        if (!has_down) return Dir::Up;
        const int down = *std::prev(down_it);
        return *up - c.floor <= c.floor - down ? Dir::Up : Dir::Down;
    }
};

struct Look : DispatchStrategy {  // keep going while stops lie ahead, then reverse
    virtual int cost(const Car& c, const Passenger& p, int floors) const {
        const int d = std::abs(c.floor - p.origin);
        const bool on_the_way = c.dir == Dir::Idle || (c.dir == Dir::Up && p.origin >= c.floor) || (c.dir == Dir::Down && p.origin <= c.floor);
        return d + (on_the_way ? 0 : 2 * floors) + 2 * static_cast<int>(c.stops.size());
    }
    std::size_t assign(const Passenger& p, const std::vector<Car>& cars, int floors) const override {
        std::size_t best = 0;
        for (std::size_t i = 1; i < cars.size(); ++i)
            if (cost(cars[i], p, floors) < cost(cars[best], p, floors)) best = i;
        return best;
    }
    Dir next_direction(const Car& c) const override {
        if (c.stops.empty()) return Dir::Idle;
        bool ahead = false;
        switch (c.dir) {
            case Dir::Up: ahead = c.stops.lower_bound(c.floor + 1) != c.stops.end(); break;
            case Dir::Down: ahead = c.stops.lower_bound(c.floor) != c.stops.begin(); break;
            case Dir::Idle: break;
        }
        if (ahead) return c.dir;
        return c.stops.lower_bound(c.floor) != c.stops.end() ? Dir::Up : Dir::Down;
    }
};

struct DestinationDispatch final : Look {  // group riders who share stops
    int cost(const Car& c, const Passenger& p, int floors) const override {
        int base = Look::cost(c, p, floors);
        if (c.stops.contains(p.dest)) base -= 4;
        if (c.stops.contains(p.origin)) base -= 2;
        return base;
    }
};

struct Metrics { double avg_wait; int max_wait; double avg_trip; int stops; std::size_t delivered; };

class Building {
    int floors_;
    std::vector<Car> cars_;
    const DispatchStrategy& strategy_;
    std::mutex inbox_m_;  // hall panels -> controller (MPSC hand-off)
    std::vector<Passenger> inbox_;
    std::vector<int> boarded_at_;
public:
    std::vector<int> waits, trips;
    int tick = 0;
    Building(int floors, int cars, const DispatchStrategy& s, std::size_t max_passengers)
        : floors_(floors), cars_(static_cast<std::size_t>(cars)), strategy_(s), boarded_at_(max_passengers) {}
    void submit(const Passenger& p) {  // any thread
        std::scoped_lock l(inbox_m_);
        inbox_.push_back(p);
    }
    void step() {  // controller thread only
        std::vector<Passenger> fresh;
        {
            std::scoped_lock l(inbox_m_);
            fresh.swap(inbox_);
        }
        for (const auto& p : fresh) {
            Car& c = cars_[strategy_.assign(p, cars_, floors_)];
            c.assigned.push_back(p);
            c.stops.insert(p.origin);
        }
        for (Car& c : cars_) {
            if (c.door_ticks > 0) {
                --c.door_ticks;
                continue;
            }
            if (c.stops.contains(c.floor)) {
                c.stops.erase(c.floor);
                ++c.stops_made;
                c.door_ticks = kDoorTicks;
                for (std::size_t i = c.riders.size(); i-- > 0;)
                    if (c.riders[i].dest == c.floor) {
                        trips.push_back(tick - boarded_at_[static_cast<std::size_t>(c.riders[i].id)]);
                        c.riders.erase(c.riders.begin() + static_cast<std::ptrdiff_t>(i));
                    }
                for (std::size_t i = 0; i < c.assigned.size() && c.riders.size() < kCapacity;) {
                    const Passenger w = c.assigned[i];
                    if (w.origin == c.floor) {
                        c.assigned.erase(c.assigned.begin() + static_cast<std::ptrdiff_t>(i));
                        c.riders.push_back(w);
                        boarded_at_[static_cast<std::size_t>(w.id)] = tick;
                        waits.push_back(tick - w.arrival);
                        c.stops.insert(w.dest);
                    } else {
                        ++i;
                    }
                }
                // Left-behind pickups: re-add their floors only once there is room (re-adding the current floor
                // while full makes the car stop here forever).
                if (c.riders.size() < kCapacity)
                    for (const auto& w : c.assigned) c.stops.insert(w.origin);
                continue;
            }
            c.dir = strategy_.next_direction(c);
            if (c.dir == Dir::Up) ++c.floor;
            else if (c.dir == Dir::Down) --c.floor;
        }
        ++tick;
    }
    bool idle() {
        for (const Car& c : cars_)
            if (!c.riders.empty() || !c.assigned.empty() || c.door_ticks > 0) return false;
        std::scoped_lock l(inbox_m_);
        return inbox_.empty();
    }
    Metrics metrics() const {
        int stops = 0;
        for (const Car& c : cars_) stops += c.stops_made;
        const double aw = waits.empty() ? 0 : static_cast<double>(std::accumulate(waits.begin(), waits.end(), 0LL)) / static_cast<double>(waits.size());
        const double at = trips.empty() ? 0 : static_cast<double>(std::accumulate(trips.begin(), trips.end(), 0LL)) / static_cast<double>(trips.size());
        return {aw, waits.empty() ? 0 : *std::ranges::max_element(waits), at, stops, trips.size()};
    }
};

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

std::vector<Passenger> workload(int n) {  // busy floors 0-5 plus a call from floor 19 every 400 passengers
    std::vector<Passenger> ps;
    for (int i = 0; i < n; ++i) {
        const u64 r = mix64(static_cast<u64>(i));
        int origin, dest;
        if (i % 400 == 0) {
            origin = 19;
            dest = 0;
        } else {
            origin = static_cast<int>(r % 6);
            dest = static_cast<int>((r >> 16) % 6);
            if (dest == origin) dest = (dest + 1) % 6;
        }
        ps.push_back({i, origin, dest, i * 3});
    }
    return ps;
}

Metrics simulate(const DispatchStrategy& s, int cars, const std::vector<Passenger>& ps) {
    Building b(20, cars, s, ps.size());
    std::size_t next = 0;
    while (next < ps.size() || !b.idle()) {
        while (next < ps.size() && ps[next].arrival <= b.tick) b.submit(ps[next++]);
        b.step();
        if (b.tick > 2'000'000) throw std::logic_error("simulation did not drain");
    }
    return b.metrics();
}

int main() {
    const auto ps = workload(4'000);
    const Sstf sstf;
    const Look look;
    const DestinationDispatch dd;
    const std::vector<std::pair<const char*, const DispatchStrategy*>> strategies{{"SSTF", &sstf}, {"LOOK", &look}, {"destination dispatch", &dd}};
    bool ok = true;
    std::vector<Metrics> one;
    for (int cars : {1, 3}) {
        std::println("{}", cars == 1 ? "== 1. One car, 20 floors, 4,000 passengers (busy floors 0-5, a call from floor 19 every 400) =="
                                     : "== 2. Three cars, same workload ==");
        for (const auto& [name, s] : strategies) {
            const auto m = simulate(*s, cars, ps);
            if (cars == 1) one.push_back(m);
            std::println("  {:<21} avg wait {:7.1f} | MAX wait {:6} | avg ride {:5.1f} | stops {:6} | delivered {}", name, m.avg_wait, m.max_wait,
                         m.avg_trip, m.stops, m.delivered);
            ok &= m.delivered == 4'000;
        }
    }
    std::println("== 3. Concurrent hall panels: 8 threads submit 1,000 passengers each; one controller thread ==");
    Building b(20, 3, look, 8'000);
    std::atomic<int> done{0};
    {
        std::vector<std::jthread> panels;
        for (int t = 0; t < 8; ++t)
            panels.emplace_back([&, t] {
                for (int i = 0; i < 1'000; ++i) {
                    const int id = t * 1'000 + i;
                    const u64 r = mix64(static_cast<u64>(id));
                    const int o = static_cast<int>(r % 20), d = static_cast<int>((r >> 20) % 20);
                    b.submit({id, o, d == o ? (d + 1) % 20 : d, 0});
                }
                done.fetch_add(1);
            });
        while (done.load() < 8 || !b.idle()) b.step();
    }
    std::println("  delivered {} of 8000, each exactly once: {}", b.metrics().delivered, b.trips.size() == 8'000 && b.waits.size() == 8'000);
    ok &= one[0].max_wait > one[1].max_wait && b.trips.size() == 8'000;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2 (Clang 21.1 identical):**

```text
== 1. One car, 20 floors, 4,000 passengers (busy floors 0-5, a call from floor 19 every 400) ==
  SSTF                  avg wait  1003.5 | MAX wait  13701 | avg ride  27.1 | stops   3396 | delivered 4000
  LOOK                  avg wait    68.0 | MAX wait   2523 | avg ride  18.5 | stops   2808 | delivered 4000
  destination dispatch  avg wait    68.0 | MAX wait   2523 | avg ride  18.5 | stops   2808 | delivered 4000
== 2. Three cars, same workload ==
  SSTF                  avg wait     6.3 | MAX wait   1043 | avg ride  13.5 | stops   6334 | delivered 4000
  LOOK                  avg wait     2.5 | MAX wait     25 | avg ride   7.8 | stops   7076 | delivered 4000
  destination dispatch  avg wait     2.3 | MAX wait     27 | avg ride   7.5 | stops   6724 | delivered 4000
== 3. Concurrent hall panels: 8 threads submit 1,000 passengers each; one controller thread ==
  delivered 8000 of 8000, each exactly once: true
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Design | `Elevator` class with a `move()` loop per thread | One thread per car, a shared request queue | Single-writer controller + MPSC inbox; cars are plain state |
| Policy | "Nearest elevator" hard-coded | Strategy interface, LOOK | LOOK vs SSTF vs destination dispatch **measured**; starvation quantified by max wait; the cost function explains its terms |
| Concurrency | `synchronized` on every car | Locks per car | No locks on car state at all; concurrency at the boundary only |
| Testing | Watch it run | Unit tests of direction choice | Deterministic virtual-time simulation, a termination guard (caught a livelock), cross-language identical metrics |
| Extensions | — | — | Peak modes (up-peak lobby priority), energy, fire service as strategy and state overrides |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Morning up-peak: everyone at the lobby" | Up-peak mode: idle cars return to the lobby (a parking policy); assignment cost adds a lobby bias |
| "VIP floor gets priority" | A cost-function term; the max-wait SLO for other floors is still measured, so priority can't silently reintroduce starvation |
| "A car goes out of service mid-trip" | Re-assign its `assigned` pickups via the strategy; riders exit at the next floor; the invariant "every passenger delivered once" still holds |
| "Minimize energy" | Penalize direction reversals and empty runs in the cost; measure kWh vs wait as a Pareto pair |
| "Real time, not ticks" | Same controller driven by a timer; time injected (01.3 §8); the simulation stays the test harness |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Why not always send the nearest car to the nearest request?"</b></summary>

**L5:** "That minimizes travel."

**Why it fails:** it's SSTF, and it starves distant floors under steady local traffic. Measured: the worst wait was 13,701 ticks against 2,523 for LOOK, with one car.

**L7 defence:** "LOOK continues in its direction while stops lie ahead, then reverses, so every floor is served within a sweep. I'd report the max and p99 waits, not just the average, because starvation lives in the tail."
</details>

<details>
<summary><b>Q2 ⚡ "Twenty panels and three cars, all concurrent. Where do the locks go?"</b></summary>

**L5:** "One lock per elevator."

**Why it fails:** assignment needs a consistent view of all cars, so you either lock them all (in order) or decide on stale data.

**L7 defence:** "Concurrency only at the boundary: panels publish to an MPSC inbox, and one controller thread drains it each tick and mutates all cars. No locks on car state, deterministic decisions, and 8,000 concurrent submissions delivered exactly once in the test."
</details>

<details>
<summary><b>Q3 ⚡ "What does destination dispatch buy?"</b></summary>

**L5:** "Passengers choose their floor in the lobby."

**Why it fails:** that's the UI, not the benefit.

**L7 defence:** "Knowing the destination at assignment time lets you group riders who share stops. Measured with 3 cars: 352 fewer stops (5%), lower average wait and ride, and a similar max wait. Fewer stops is both throughput and energy."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Top floors wait forever | SSTF-style nearest-first | LOOK / SCAN; measure max wait |
| A car stuck opening its doors at one floor | Re-adding the current floor while full | Re-add pickups only when there's capacity |
| Inconsistent assignments | Decisions over individually locked cars | Single-writer controller |
| Passengers lost when a car fails | Assignments stored only in the car | Re-assign on failure; delivery invariant tested |

- [ ] The dispatch policy is a strategy; the worst-case wait is measured, not assumed.
- [ ] Car state has a single writer; concurrency at the inbox only.
- [ ] Capacity respected; left-behind pickups re-queued correctly.
- [ ] A deterministic simulation with a termination guard; metrics cross-checked.

## 10. References

- Gina Carol Barney, *Elevator Traffic Handbook*, 2nd ed., Routledge, 2016.
- LMAX, "The Single Writer Principle" (Martin Thompson). <https://mechanical-sympathy.blogspot.com/2011/09/single-writer-principle.html>
- In this KB: [02.1 State machines](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/01-state-machines-enum-vs-sealed-types-and-optimistic-transitions.md) · [02.2 Strategy](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md) · P12 single-writer order book (Folder 05)
