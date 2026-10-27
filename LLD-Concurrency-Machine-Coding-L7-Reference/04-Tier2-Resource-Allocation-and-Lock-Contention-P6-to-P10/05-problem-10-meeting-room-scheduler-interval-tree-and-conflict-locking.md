# P10 · Meeting Room Scheduler: Interval Checks in O(log n), Per-Room Locks, RRULE Series Across DST

> **Folder 04 · Problem 10 of 20.** The structure is simple: per-room sorted maps, half-open intervals, and only two neighbours to check. The traps are in the details:
> - check-then-insert races under read locks;
> - `TreeMap.put` silently **overwriting** a booking;
> - multi-room atomicity and lock order;
> - recurring meetings, which live in **local wall-clock time** and so move in UTC when daylight saving ends.
>
> Building the C++ version also surfaced a **toolchain bug**: freshly created `std::shared_mutex` objects in libstdc++/MinGW hang when several threads race on their first use.
>
> **Listing pair P10:** `MeetingRooms.java` / `meeting_rooms.cpp`. Sections 1–3 and 5 are deterministic and identical in both languages. Race counts are one measured run.

---

## 1. Problem and scope

**Functional:**
- `book(room, start, end)`;
- `bookAll(rooms, slots)`, all-or-nothing across rooms and occurrences;
- `bookSeries(room, RRULE)` with weekly `BYDAY` / `COUNT` in a time zone;
- `findAndBook(start, end)`, any free room.

**Rules:** intervals are half-open `[start, end)`, so back-to-back meetings don't conflict. A series is atomic: either every occurrence is booked or none is.

**Out of scope:** attendee calendars (a second index by person, same structure) and RRULE `EXDATE`/`RDATE` (§7).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Room index | `TreeMap<Instant, Booking>` + `ReentrantReadWriteLock` | `std::map<sys_seconds, Booking>` + `std::shared_mutex` |
| Value types | `record Booking`, `record Slot(start, end)` | `struct Booking`, `struct Slot` |
| Results | sealed `Result permits Booked, Conflict, SeriesBooked` | `std::variant` |
| Recurrence | `record RRule(firstWeek, EnumSet<DayOfWeek>, LocalTime, Duration, count, interval, ZoneId)` | `WeeklyRule` + `new_york_to_utc` (tzdb, or the US rule as a fallback) |

**Invariants:**
- **I1:** within a room, no two bookings overlap. With I1 holding, a new interval `[s, e)` can only conflict with `floorEntry(s)` (if its end > s) or `ceilingEntry(s)` (if its start < e): two O(log n) lookups.
- **I2:** every confirmed booking is stored. No silent overwrite.
- **I3:** a multi-room / multi-occurrence booking is all-or-nothing.
- **I4:** a series occurrence keeps its **local** time (09:00 New York) across DST changes.
- **I5:** every slot granted by `findAndBook` is distinct: 30 contenders for 10 rooms produce exactly 10 bookings.

## 3. Concurrency and contention analysis

**The naive design: check under a read lock, insert under a write lock.** A remote permission check sits between them, which is realistic. Two threads both see "free", and both insert. Results:

| Test (one measured run each) | Naive: Java / GCC / Clang | Write-locked check + insert |
|---|---|---|
| Random: 8 threads over 10 rooms × 5 days | 2 / 8 / 6 overlapping pairs stored; **4 / 10 / 14 confirmed bookings silently overwritten** | 0 everywhere |
| Hot room: 4 threads, overlapping hours, 2,000 rounds | 160 / **1,998 / 1,999** rounds with overlaps | 0 everywhere |

Before the hot-room test existed, the random test showed **0** overlaps for the naive design too: with 2,400 slots per room, two threads rarely want the same one at once. A random stress test at low contention proves nothing. You need a test that *makes* the threads collide.

**Silent overwrite.** `TreeMap.put` and `std::map::insert_or_assign` with an equal start key replace the existing booking. The naive racer "confirmed" two bookings and stored one. Correct code never reaches `put` without a conflict check under the same lock, and the stored-vs-confirmed audit catches regressions.

**The correct design:**
1. Do remote work (permissions) **before** taking any lock.
2. Write-lock the involved rooms **in room-id order**.
3. Check every room × occurrence.
4. Insert all, or return the first conflict having inserted nothing.

**Read locks are still useful** for queries: free/busy views and `findAndBook`'s candidate scan. `findAndBook` re-checks under the write lock inside `bookAll`, so the scan is only a hint (I5: exactly 10 bookings from 30 threads).

**Time zones.**
- **Recurrences:** a weekly 09:00 meeting is 13:00 UTC before 2026-11-01 and 14:00 UTC after. Adding 7 × 24 h to the previous instant gives **08:00 local** after the change. Recurrences must be expanded in the zone (`ZonedDateTime` / `zoned_time`) and stored as instants.
- **TTLs and timeouts are the opposite:** they're durations and use a monotonic clock (01.3 §8). Mixing these two semantics is a classic production bug.
- **C++ tzdb availability:** libstdc++ (GCC 16) ships the time-zone database. libc++ as packaged here doesn't provide `std::chrono::locate_zone`, so the listing falls back to the encoded US rule. Check `__cpp_lib_chrono` support for tzdb on your platform ⚠.

**The toolchain bug 🧊.** The first GCC build crashed (`std::bad_alloc`) or failed its own invariants in the concurrent sections, while Clang passed. The investigation:
1. **Unbuffered stdout** to see where it died: the concurrent section.
2. **`std::shared_mutex` → `std::mutex`:** 3/3 passes; the `shared_mutex` build failed or hung in the same session.
3. **A minimal reproducer** with one long-lived `shared_mutex` (4 writers + 4 readers × 200,000 operations): correct, 3/3.
4. **Many *fresh* `shared_mutex` objects, 4 threads racing on the first lock:** **hung in 5 of 5 runs** under libstdc++/MinGW; 0 failures in 5,000 rounds under libc++.
5. **The control:** lock/unlock each fresh mutex once on one thread first. The hang disappeared.

libstdc++ implements `shared_mutex` with a statically initialized winpthreads `pthread_rwlock`, which is created lazily on first use, and that lazy initialization is racy in this toolchain ⚠. Workaround: warm the lock in the `Room` constructor.

The general lesson is the process: when one platform fails, isolate with unbuffered output, swap primitives, write a minimal reproducer, then a control that confirms the mechanism.

## 4. Java 21 implementation

```java
// MeetingRooms.java - P10: TreeMap interval checks (floor/ceiling), per-room RW locks, RRULE series across DST
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.SplittableRandom;
import java.util.TreeMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public final class MeetingRooms {

    record Booking(long id, String room, Instant start, Instant end, String owner, long series) {}

    /** A value type, not an Instant[]: List.of(new Instant[]{s, e}) binds the array AS the varargs (javac caught it). */
    record Slot(Instant start, Instant end) {}

    sealed interface Result permits Booked, Conflict, SeriesBooked {}
    record Booked(List<Booking> bookings) implements Result {}
    record Conflict(String room, Booking existing, Instant wantedStart) implements Result {}
    record SeriesBooked(int occurrences) implements Result {}

    /** RRULE subset: FREQ=WEEKLY;INTERVAL;COUNT;BYDAY at a LOCAL time in a zone (wall-clock semantics). */
    record RRule(LocalDate firstWeek, EnumSet<DayOfWeek> byDay, LocalTime at, Duration length, int count, int intervalWeeks, ZoneId zone) {
        List<Slot> expand() {
            List<Slot> out = new ArrayList<>();
            LocalDate week = firstWeek.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            while (out.size() < count) {
                for (DayOfWeek d : byDay) {                     // EnumSet iterates Monday..Sunday
                    LocalDate date = week.with(TemporalAdjusters.nextOrSame(d));
                    if (date.isBefore(firstWeek) || out.size() == count) continue;
                    Instant s = ZonedDateTime.of(date, at, zone).toInstant();   // 09:00 LOCAL, whatever the offset
                    out.add(new Slot(s, s.plus(length)));
                }
                week = week.plusWeeks(intervalWeeks);
            }
            return out;
        }
    }

    static final class Room {
        final String id;
        final TreeMap<Instant, Booking> byStart = new TreeMap<>();   // invariant: no two bookings overlap
        final ReentrantReadWriteLock rw = new ReentrantReadWriteLock();

        Room(String id) {
            this.id = id;
        }

        /** Half-open [s, e). With non-overlapping contents only the two neighbours can conflict: O(log n). */
        Optional<Booking> conflict(Instant s, Instant e) {
            Map.Entry<Instant, Booking> before = byStart.floorEntry(s), after = byStart.ceilingEntry(s);
            if (before != null && before.getValue().end().isAfter(s)) return Optional.of(before.getValue());
            if (after != null && after.getValue().start().isBefore(e)) return Optional.of(after.getValue());
            return Optional.empty();
        }
    }

    static final class Scheduler {
        final TreeMap<String, Room> rooms = new TreeMap<>();    // sorted by id: the multi-room lock order
        final AtomicLong ids = new AtomicLong();
        final boolean naive;

        Scheduler(List<String> roomIds, boolean naive) {
            for (String r : roomIds) rooms.put(r, new Room(r));
            this.naive = naive;
        }

        Result book(String room, Instant s, Instant e, String owner) {
            return bookAll(List.of(room), List.of(new Slot(s, e)), owner, 0);
        }

        /** All-or-nothing over rooms x occurrences; rooms write-locked in id order (no deadlock). */
        static void permissionCheck() {                       // ~1 us: "may this owner book these rooms?"
            for (int k = 0; k < 300; k++) Thread.onSpinWait();
        }

        Result bookAll(List<String> roomIds, List<Slot> slots, String owner, long series) {
            List<Room> locked = roomIds.stream().sorted().distinct().map(rooms::get).toList();
            if (naive) {                                        // L5: check under READ locks, insert later
                for (Room r : locked) {
                    r.rw.readLock().lock();
                    try {
                        for (Slot sl : slots) {
                            Optional<Booking> c = r.conflict(sl.start(), sl.end());
                            if (c.isPresent()) return new Conflict(r.id, c.get(), sl.start());
                        }
                    } finally {
                        r.rw.readLock().unlock();
                    }
                }
                permissionCheck();                              // ...the window between check and insert
                List<Booking> made = new ArrayList<>();
                for (Room r : locked) {
                    r.rw.writeLock().lock();
                    try {
                        for (Slot sl : slots) made.add(insert(r, sl, owner, series));
                    } finally {
                        r.rw.writeLock().unlock();
                    }
                }
                return series == 0 ? new Booked(made) : new SeriesBooked(slots.size());
            }
            permissionCheck();                                  // remote work BEFORE taking any lock
            for (Room r : locked) r.rw.writeLock().lock();
            try {
                for (Room r : locked)
                    for (Slot sl : slots) {
                        Optional<Booking> c = r.conflict(sl.start(), sl.end());
                        if (c.isPresent()) return new Conflict(r.id, c.get(), sl.start());   // nothing inserted yet
                    }
                List<Booking> made = new ArrayList<>();
                for (Room r : locked) for (Slot sl : slots) made.add(insert(r, sl, owner, series));
                return series == 0 ? new Booked(made) : new SeriesBooked(slots.size());
            } finally {
                for (int i = locked.size() - 1; i >= 0; i--) locked.get(i).rw.writeLock().unlock();
            }
        }

        private Booking insert(Room r, Slot sl, String owner, long series) {
            Booking b = new Booking(ids.incrementAndGet(), r.id, sl.start(), sl.end(), owner, series);
            r.byStart.put(sl.start(), b);                           // (naive mode may overwrite or overlap here)
            return b;
        }

        Result bookSeries(String room, RRule rule, String owner) {
            return bookAll(List.of(room), rule.expand(), owner, ids.incrementAndGet());
        }

        /** Read-locked scan to find candidates, then a write-locked re-check inside bookAll (no TOCTOU). */
        Optional<Booking> findAndBook(Instant s, Instant e, String owner) {
            for (Room r : rooms.values()) {
                r.rw.readLock().lock();
                boolean free;
                try {
                    free = r.conflict(s, e).isEmpty();
                } finally {
                    r.rw.readLock().unlock();
                }
                if (free && book(r.id, s, e, owner) instanceof Booked b) return Optional.of(b.bookings().get(0));
            }
            return Optional.empty();
        }

        long overlaps() {
            long n = 0;
            for (Room r : rooms.values()) {
                Booking prev = null;
                for (Booking b : r.byStart.values()) {
                    if (prev != null && prev.end().isAfter(b.start())) n++;
                    prev = b;
                }
            }
            return n;
        }

        long lostToOverwrite(long attemptedOk) {               // naive put() on an equal start silently replaces
            long stored = 0;
            for (Room r : rooms.values()) stored += r.byStart.size();
            return attemptedOk - stored;
        }
    }

    public static void main(String[] args) throws Exception {
        Instant day = Instant.parse("2026-11-03T00:00:00Z");
        Instant h10 = day.plus(Duration.ofHours(10)), h11 = day.plus(Duration.ofHours(11)), h12 = day.plus(Duration.ofHours(12));

        System.out.println("== 1. Half-open intervals, O(log n) neighbour checks ==");
        Scheduler s = new Scheduler(List.of("A", "B"), false);
        System.out.println("  [10:00,11:00)               -> " + s.book("A", h10, h11, "ann").getClass().getSimpleName());
        System.out.println("  [11:00,12:00) back-to-back  -> " + s.book("A", h11, h12, "bob").getClass().getSimpleName());
        Result c = s.book("A", h10.plus(Duration.ofMinutes(30)), h11.plus(Duration.ofMinutes(30)), "cat");
        System.out.println("  [10:30,11:30) overlap       -> " + (c instanceof Conflict k ? "Conflict with booking " + k.existing().id() + " (" + k.existing().owner() + ")" : c));
        Result multi = s.bookAll(List.of("B", "A"), List.of(new Slot(h12, h12.plus(Duration.ofHours(1)))), "dan", 0);
        System.out.println("  rooms {B, A} at 12:00 (locked in order A, B) -> " + multi.getClass().getSimpleName());

        System.out.println("== 2. Weekly Monday 09:00 America/New_York across the DST change (2026-11-01) ==");
        ZoneId ny = ZoneId.of("America/New_York");
        RRule weekly = new RRule(LocalDate.of(2026, 10, 26), EnumSet.of(DayOfWeek.MONDAY), LocalTime.of(9, 0), Duration.ofHours(1), 3, 1, ny);
        List<Slot> occ = weekly.expand();
        Instant naiveNext = occ.get(0).start();
        for (int i = 0; i < occ.size(); i++) {
            System.out.printf("  occurrence %d: %s local = %s UTC | naive 'previous + 7 days' = %s local%n", i + 1,
                    occ.get(i).start().atZone(ny).toLocalDateTime(), occ.get(i).start(), naiveNext.atZone(ny).toLocalDateTime());
            naiveNext = naiveNext.plus(Duration.ofDays(7));
        }

        System.out.println("== 3. A series is all-or-nothing ==");
        Scheduler s3 = new Scheduler(List.of("A"), false);
        s3.book("A", occ.get(1).start(), occ.get(1).end(), "erin");     // occupies the 2nd occurrence
        Result series = s3.bookSeries("A", weekly, "fay");
        System.out.println("  3-week series where week 2 is taken -> " + (series instanceof Conflict k ? "Conflict at " + k.wantedStart() + "; bookings in room: " + s3.rooms.get("A").byStart.size() : series));

        System.out.println("== 4. 8 threads x 2,000 attempts, 10 rooms, 5 days of 30-min slots, 10% weekly series ==");
        long[] overlapCount = new long[2], lost = new long[2], okCount = new long[2];
        List<String> roomIds = List.of("R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9");
        for (int mode = 0; mode < 2; mode++) {
            Scheduler sc = new Scheduler(roomIds, mode == 0);
            LongAdder slotsBooked = new LongAdder();
            CyclicBarrier start = new CyclicBarrier(9), end = new CyclicBarrier(9);
            AtomicReference<Exception> failure = new AtomicReference<>();
            for (int t = 0; t < 8; t++) {
                final int seed = t;
                Thread.ofPlatform().start(() -> {
                    try {
                        SplittableRandom r = new SplittableRandom(seed);
                        start.await();
                        for (int i = 0; i < 2_000; i++) {
                            String room = roomIds.get(r.nextInt(10));
                            Instant st = day.plus(Duration.ofMinutes(30L * r.nextInt(5 * 48)));
                            Instant en = st.plus(Duration.ofMinutes(30L * (1 + r.nextInt(4))));
                            if (r.nextInt(10) == 0) {
                                List<Slot> weeks = new ArrayList<>();
                                for (int w = 0; w < 4; w++) weeks.add(new Slot(st.plus(Duration.ofDays(7L * w)), en.plus(Duration.ofDays(7L * w))));
                                if (sc.bookAll(List.of(room), weeks, "t" + seed, 1) instanceof SeriesBooked sb) slotsBooked.add(sb.occurrences());
                            } else if (sc.book(room, st, en, "t" + seed) instanceof Booked) slotsBooked.increment();
                        }
                    } catch (Exception e) {
                        failure.compareAndSet(null, e);
                    } finally {
                        try {
                            end.await();
                        } catch (Exception ignored) {
                        }
                    }
                });
            }
            start.await();
            end.await();
            if (failure.get() != null) throw new IllegalStateException(failure.get());
            overlapCount[mode] = sc.overlaps();
            okCount[mode] = slotsBooked.sum();
            lost[mode] = sc.lostToOverwrite(slotsBooked.sum());
            System.out.printf("  %-34s confirmed %,d slots | overlapping pairs stored %d | confirmed but silently overwritten %d%n",
                    mode == 0 ? "check under read lock, insert later" : "check + insert under room write locks", okCount[mode], overlapCount[mode], lost[mode]);
        }

        System.out.println("== 4b. Hot room: 4 threads, one room, each wants 1 h starting 10:00 / 10:30 / 11:00, 2,000 rounds ==");
        long[] hot = new long[2];
        for (int mode = 0; mode < 2; mode++) {
            for (int round = 0; round < 2_000; round++) {
                Scheduler sc = new Scheduler(List.of("A"), mode == 0);
                CyclicBarrier g = new CyclicBarrier(5), d = new CyclicBarrier(5);
                for (int t = 0; t < 4; t++) {
                    final int slot = (round + t) % 3;
                    Thread.ofPlatform().start(() -> {
                        try {
                            g.await();
                            Instant st = h10.plus(Duration.ofMinutes(30L * slot));
                            sc.book("A", st, st.plus(Duration.ofHours(1)), "x");
                            d.await();
                        } catch (Exception e) {
                            throw new IllegalStateException(e);
                        }
                    });
                }
                g.await();
                d.await();
                if (sc.overlaps() > 0 || sc.rooms.get("A").byStart.size() > 2) hot[mode]++;
            }
            System.out.printf("  %-34s rounds ending with overlapping bookings %,d of 2,000%n",
                    mode == 0 ? "check under read lock, insert later" : "check + insert under room write locks", hot[mode]);
        }

        System.out.println("== 5. findAndBook: 30 threads want the same hour; 10 rooms exist ==");
        Scheduler s5 = new Scheduler(roomIds, false);
        LongAdder got = new LongAdder();
        CyclicBarrier go = new CyclicBarrier(31), done = new CyclicBarrier(31);
        for (int t = 0; t < 30; t++) {
            Thread.ofPlatform().start(() -> {
                try {
                    go.await();
                    if (s5.findAndBook(h10, h11, "x").isPresent()) got.increment();
                    done.await();
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            });
        }
        go.await();
        done.await();
        System.out.println("  bookings made " + got.sum() + " (one per room), overlaps " + s5.overlaps());

        boolean ok = c instanceof Conflict && multi instanceof Booked && series instanceof Conflict && s3.rooms.get("A").byStart.size() == 1
                && overlapCount[1] == 0 && lost[1] == 0 && hot[1] == 0 && got.sum() == 10 && s5.overlaps() == 0
                && occ.get(1).start().equals(Instant.parse("2026-11-02T14:00:00Z"));
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1–3, 5 verified; sections 4–4b one measured run):**

```text
== 1. Half-open intervals, O(log n) neighbour checks ==
  [10:00,11:00)               -> Booked
  [11:00,12:00) back-to-back  -> Booked
  [10:30,11:30) overlap       -> Conflict with booking 1 (ann)
  rooms {B, A} at 12:00 (locked in order A, B) -> Booked
== 2. Weekly Monday 09:00 America/New_York across the DST change (2026-11-01) ==
  occurrence 1: 2026-10-26T09:00 local = 2026-10-26T13:00:00Z UTC | naive 'previous + 7 days' = 2026-10-26T09:00 local
  occurrence 2: 2026-11-02T09:00 local = 2026-11-02T14:00:00Z UTC | naive 'previous + 7 days' = 2026-11-02T08:00 local
  occurrence 3: 2026-11-09T09:00 local = 2026-11-09T14:00:00Z UTC | naive 'previous + 7 days' = 2026-11-09T08:00 local
== 3. A series is all-or-nothing ==
  3-week series where week 2 is taken -> Conflict at 2026-11-02T14:00:00Z; bookings in room: 1
== 4. 8 threads x 2,000 attempts, 10 rooms, 5 days of 30-min slots, 10% weekly series ==
  check under read lock, insert later confirmed 1,667 slots | overlapping pairs stored 2 | confirmed but silently overwritten 4
  check + insert under room write locks confirmed 1,624 slots | overlapping pairs stored 0 | confirmed but silently overwritten 0
== 4b. Hot room: 4 threads, one room, each wants 1 h starting 10:00 / 10:30 / 11:00, 2,000 rounds ==
  check under read lock, insert later rounds ending with overlapping bookings 160 of 2,000
  check + insert under room write locks rounds ending with overlapping bookings 0 of 2,000
== 5. findAndBook: 30 threads want the same hour; 10 rooms exist ==
  bookings made 10 (one per room), overlaps 0
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// meeting_rooms.cpp - P10: std::map interval checks, per-room shared_mutex, all-or-nothing series across DST
#include <algorithm>
#include <array>
#include <type_traits>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <format>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <random>
#include <shared_mutex>
#include <string>
#include <thread>
#include <variant>
#include <vector>

using namespace std::chrono;
using i64 = std::int64_t;
using Instant = sys_seconds;

struct Booking { i64 id; std::string room; Instant start, end; std::string owner; i64 series; };
struct Slot { Instant start, end; };

struct Booked { std::vector<Booking> bookings; };
struct Conflict { std::string room; Booking existing; Instant wanted; };
struct SeriesBooked { std::size_t occurrences; };
using Result = std::variant<Booked, Conflict, SeriesBooked>;

/**
 * Local wall time -> UTC for America/New_York. libstdc++ ships the IANA database (std::chrono::locate_zone);
 * libc++ as packaged here does not, so the fallback encodes the US rule (since 2007): EDT (UTC-4) from the
 * 2nd Sunday of March 02:00 to the 1st Sunday of November 02:00 local, EST (UTC-5) otherwise.
 */
Instant new_york_to_utc(local_days date, minutes at) {
#if defined(_GLIBCXX_RELEASE)
    static const time_zone* ny = locate_zone("America/New_York");
    return floor<seconds>(zoned_time(ny, local_seconds(date) + at).get_sys_time());
#else
    const year_month_day ymd(date);
    const local_days dst_start = local_days(ymd.year() / March / Sunday[2]);
    const local_days dst_end = local_days(ymd.year() / November / Sunday[1]);
    const auto local = local_seconds(date) + at;
    const bool dst = local >= local_seconds(dst_start) + 2h && local < local_seconds(dst_end) + 1h;
    return Instant((local - (dst ? -4h : -5h)).time_since_epoch());
#endif
}

struct WeeklyRule {  // FREQ=WEEKLY;BYDAY=<days>;COUNT=<n> at a LOCAL time
    local_days first_week;
    std::vector<weekday> by_day;  // Monday..Sunday order
    minutes at;
    minutes length;
    int count;
    std::vector<Slot> expand() const {
        std::vector<Slot> out;
        local_days week = first_week - (weekday(first_week) - Monday);  // back to Monday
        while (static_cast<int>(out.size()) < count) {
            for (const weekday d : by_day) {
                const local_days date = week + (d - Monday);
                if (date < first_week || static_cast<int>(out.size()) == count) continue;
                const Instant s = new_york_to_utc(date, at);  // 09:00 LOCAL, whatever the offset
                out.push_back({s, s + length});
            }
            week += weeks(1);
        }
        return out;
    }
};

class Room {
public:
    std::string id;
    std::map<Instant, Booking> by_start;  // invariant: no overlaps
    std::shared_mutex rw;
    explicit Room(std::string i) : id(std::move(i)) {
        // Workaround, measured on GCC 16.2 / MinGW: libstdc++'s shared_mutex is a statically initialised
        // winpthreads rwlock that is lazily created on FIRST use, and 4 threads racing on that first use hung
        // (5/5 runs) or broke exclusion. One uncontended lock/unlock here forces the init. libc++ is unaffected.
        { std::unique_lock warm(rw); }
    }
    /** Half-open [s, e): only the two neighbours can conflict, O(log n). */
    std::optional<Booking> conflict(Instant s, Instant e) const {
        auto after = by_start.lower_bound(s);
        if (after != by_start.begin()) {
            const auto& before = std::prev(after)->second;
            if (before.end > s) return before;
        }
        if (after != by_start.end() && after->second.start < e) return after->second;
        return std::nullopt;
    }
};

class Scheduler {
    std::map<std::string, std::unique_ptr<Room>> rooms_;  // sorted: the multi-room lock order
    std::atomic<i64> ids_{0};
    bool naive_;
    static void permission_check() {  // ~1 us remote "may this owner book?"
        for (int k = 0; k < 300; ++k) {
#if defined(__x86_64__) || defined(__i386__)
            __builtin_ia32_pause();
#endif
        }
    }
    Booking insert(Room& r, const Slot& sl, const std::string& owner, i64 series) {
        Booking b{++ids_, r.id, sl.start, sl.end, owner, series};
        r.by_start.insert_or_assign(sl.start, b);  // naive mode can overwrite an equal start here
        return b;
    }
public:
    Scheduler(const std::vector<std::string>& ids, bool naive) : naive_(naive) {
        for (const auto& i : ids) rooms_.emplace(i, std::make_unique<Room>(i));
    }
    Result book_all(std::vector<std::string> room_ids, const std::vector<Slot>& slots, const std::string& owner, i64 series) {
        std::ranges::sort(room_ids);
        room_ids.erase(std::ranges::unique(room_ids).begin(), room_ids.end());
        std::vector<Room*> locked;
        for (const auto& id : room_ids) locked.push_back(rooms_.at(id).get());
        std::vector<Booking> made;
        if (naive_) {  // L5: check under READ locks, permission call, insert later
            for (Room* r : locked) {
                std::shared_lock l(r->rw);
                for (const auto& sl : slots)
                    if (auto c = r->conflict(sl.start, sl.end)) return Conflict{r->id, *c, sl.start};
            }
            permission_check();
            for (Room* r : locked) {
                std::unique_lock l(r->rw);
                for (const auto& sl : slots) made.push_back(insert(*r, sl, owner, series));
            }
        } else {
            permission_check();  // remote work BEFORE any lock
            for (Room* r : locked) r->rw.lock();
            std::optional<Conflict> veto;
            for (Room* r : locked)
                for (const auto& sl : slots)
                    if (!veto)
                        if (auto c = r->conflict(sl.start, sl.end)) veto = Conflict{r->id, *c, sl.start};
            if (!veto)
                for (Room* r : locked)
                    for (const auto& sl : slots) made.push_back(insert(*r, sl, owner, series));
            for (auto it = locked.rbegin(); it != locked.rend(); ++it) (*it)->rw.unlock();
            if (veto) return *veto;
        }
        if (series == 0) return Booked{std::move(made)};
        return SeriesBooked{slots.size()};
    }
    Result book(const std::string& room, Instant s, Instant e, const std::string& owner) { return book_all({room}, {{s, e}}, owner, 0); }
    std::optional<Booking> find_and_book(Instant s, Instant e, const std::string& owner) {
        for (auto& [id, r] : rooms_) {
            bool free;
            {
                std::shared_lock l(r->rw);
                free = !r->conflict(s, e);
            }
            if (free)
                if (auto res = book(id, s, e, owner); std::holds_alternative<Booked>(res)) return std::get<Booked>(res).bookings.front();
        }
        return std::nullopt;
    }
    std::size_t overlaps() {
        std::size_t n = 0;
        for (auto& [id, r] : rooms_) {
            const Booking* prev = nullptr;
            for (const auto& [s, b] : r->by_start) {
                if (prev && prev->end > b.start) ++n;
                prev = &b;
            }
        }
        return n;
    }
    std::size_t stored() {
        std::size_t n = 0;
        for (auto& [id, r] : rooms_) n += r->by_start.size();
        return n;
    }
    std::size_t in_room(const std::string& id) { return rooms_.at(id)->by_start.size(); }
};

template <class F>
void parallel(int threads, F body) {  // spin gate with a ready count (see P6)
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::jthread> ts;
    for (int t = 0; t < threads; ++t)
        ts.emplace_back([&, t] {
            ready.fetch_add(1);
            while (!go.load(std::memory_order_acquire)) {}
            body(t);
        });
    while (ready.load() < threads) {}
    go.store(true, std::memory_order_release);
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);  // unbuffered: a crash can't swallow the last lines
    const Instant day = sys_days(2026y / November / 3);
    const Instant h10 = day + 10h, h11 = day + 11h, h12 = day + 12h;
    auto name = [](const Result& r) {
        return std::visit([](const auto& x) -> std::string {
            using T = std::decay_t<decltype(x)>;
            if constexpr (std::is_same_v<T, Booked>) return "Booked";
            else if constexpr (std::is_same_v<T, Conflict>) return std::format("Conflict with booking {} ({})", x.existing.id, x.existing.owner);
            else return "SeriesBooked";
        }, r);
    };

    std::println("== 1. Half-open intervals, O(log n) neighbour checks ==");
    Scheduler s({"A", "B"}, false);
    std::println("  [10:00,11:00)               -> {}", name(s.book("A", h10, h11, "ann")));
    std::println("  [11:00,12:00) back-to-back  -> {}", name(s.book("A", h11, h12, "bob")));
    const auto c = s.book("A", h10 + 30min, h11 + 30min, "cat");
    std::println("  [10:30,11:30) overlap       -> {}", name(c));
    const auto multi = s.book_all({"B", "A"}, {{h12, h12 + 1h}}, "dan", 0);
    std::println("  rooms {{B, A}} at 12:00 (locked in order A, B) -> {}", name(multi));

    std::println("== 2. Weekly Monday 09:00 America/New_York across the DST change (2026-11-01) ==");
    const WeeklyRule weekly{local_days(2026y / October / 26), {Monday}, 9h, 1h, 3};
    const auto occ = weekly.expand();
    Instant naive_next = occ[0].start;
    for (std::size_t i = 0; i < occ.size(); ++i) {
        const auto local = occ[i].start - 4h * (i == 0) - 5h * (i != 0);  // display only: offsets known for these dates
        const auto naive_local = naive_next - 4h * (i == 0) - 5h * (i != 0);
        std::println("  occurrence {}: {:%FT%H:%M} local = {:%FT%TZ} UTC | naive 'previous + 7 days' = {:%FT%H:%M} local", i + 1, local,
                     occ[i].start, naive_local);
        naive_next += days(7);
    }

    std::println("== 3. A series is all-or-nothing ==");
    Scheduler s3({"A"}, false);
    s3.book("A", occ[1].start, occ[1].end, "erin");
    const auto series = s3.book_all({"A"}, occ, "fay", 1);
    std::println("  3-week series where week 2 is taken -> {}; bookings in room: {}",
                 std::holds_alternative<Conflict>(series) ? std::format("Conflict at {:%FT%TZ}", std::get<Conflict>(series).wanted) : "?", s3.in_room("A"));

    const std::vector<std::string> ids{"R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9"};
    std::println("== 4. 8 threads x 2,000 attempts, 10 rooms, 5 days of 30-min slots, 10% weekly series ==");
    std::array<std::size_t, 2> overlap_count{}, lost{};
    for (int mode = 0; mode < 2; ++mode) {
        Scheduler sc(ids, mode == 0);
        std::atomic<std::size_t> booked{0};
        parallel(8, [&](int t) {
            std::mt19937 r(static_cast<unsigned>(t));
            for (int i = 0; i < 2'000; ++i) {
                const std::string room = ids[r() % 10];
                const Instant st = day + minutes(30 * static_cast<int>(r() % (5 * 48)));
                const Instant en = st + minutes(30 * (1 + static_cast<int>(r() % 4)));
                if (r() % 10 == 0) {
                    std::vector<Slot> wk;
                    for (int w = 0; w < 4; ++w) wk.push_back({st + days(7 * w), en + days(7 * w)});
                    if (auto res = sc.book_all({room}, wk, "t", 1); std::holds_alternative<SeriesBooked>(res)) booked += 4;
                } else if (std::holds_alternative<Booked>(sc.book(room, st, en, "t"))) {
                    ++booked;
                }
            }
        });
        overlap_count[static_cast<std::size_t>(mode)] = sc.overlaps();
        lost[static_cast<std::size_t>(mode)] = booked.load() - sc.stored();
        std::println("  {:<34} confirmed {} slots | overlapping pairs stored {} | confirmed but silently overwritten {}",
                     mode == 0 ? "check under read lock, insert later" : "check + insert under room write locks", booked.load(),
                     overlap_count[static_cast<std::size_t>(mode)], lost[static_cast<std::size_t>(mode)]);
    }

    std::println("== 4b. Hot room: 4 threads, one room, each wants 1 h starting 10:00 / 10:30 / 11:00, 2,000 rounds ==");
    std::array<int, 2> hot{};
    for (int mode = 0; mode < 2; ++mode) {
        for (int round = 0; round < 2'000; ++round) {
            Scheduler sc({"A"}, mode == 0);
            parallel(4, [&](int t) {
                const Instant st = h10 + minutes(30 * ((round + t) % 3));
                sc.book("A", st, st + 1h, "x");
            });
            hot[static_cast<std::size_t>(mode)] += sc.overlaps() > 0 || sc.in_room("A") > 2;
        }
        std::println("  {:<34} rounds ending with overlapping bookings {} of 2,000",
                     mode == 0 ? "check under read lock, insert later" : "check + insert under room write locks", hot[static_cast<std::size_t>(mode)]);
    }

    std::println("== 5. find_and_book: 30 threads want the same hour; 10 rooms exist ==");
    Scheduler s5(ids, false);
    std::atomic<int> got{0};
    parallel(30, [&](int) { got += s5.find_and_book(h10, h11, "x").has_value(); });
    std::println("  bookings made {} (one per room), overlaps {}", got.load(), s5.overlaps());

    const bool ok = std::holds_alternative<Conflict>(c) && std::holds_alternative<Booked>(multi) && std::holds_alternative<Conflict>(series) &&
                    s3.in_room("A") == 1 && overlap_count[1] == 0 && lost[1] == 0 && hot[1] == 0 && got.load() == 10 && s5.overlaps() == 0 &&
                    occ[1].start == sys_days(2026y / November / 2) + 14h;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Half-open intervals, O(log n) neighbour checks ==
  [10:00,11:00)               -> Booked
  [11:00,12:00) back-to-back  -> Booked
  [10:30,11:30) overlap       -> Conflict with booking 1 (ann)
  rooms {B, A} at 12:00 (locked in order A, B) -> Booked
== 2. Weekly Monday 09:00 America/New_York across the DST change (2026-11-01) ==
  occurrence 1: 2026-10-26T09:00 local = 2026-10-26T13:00:00Z UTC | naive 'previous + 7 days' = 2026-10-26T09:00 local
  occurrence 2: 2026-11-02T09:00 local = 2026-11-02T14:00:00Z UTC | naive 'previous + 7 days' = 2026-11-02T08:00 local
  occurrence 3: 2026-11-09T09:00 local = 2026-11-09T14:00:00Z UTC | naive 'previous + 7 days' = 2026-11-09T08:00 local
== 3. A series is all-or-nothing ==
  3-week series where week 2 is taken -> Conflict at 2026-11-02T14:00:00Z; bookings in room: 1
== 4. 8 threads x 2,000 attempts, 10 rooms, 5 days of 30-min slots, 10% weekly series ==
  check under read lock, insert later confirmed 1717 slots | overlapping pairs stored 8 | confirmed but silently overwritten 10
  check + insert under room write locks confirmed 1699 slots | overlapping pairs stored 0 | confirmed but silently overwritten 0
== 4b. Hot room: 4 threads, one room, each wants 1 h starting 10:00 / 10:30 / 11:00, 2,000 rounds ==
  check under read lock, insert later rounds ending with overlapping bookings 1998 of 2,000
  check + insert under room write locks rounds ending with overlapping bookings 0 of 2,000
== 5. find_and_book: 30 threads want the same hour; 10 rooms exist ==
  bookings made 10 (one per room), overlaps 0
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Half-open intervals, O(log n) neighbour checks ==
  [10:00,11:00)               -> Booked
  [11:00,12:00) back-to-back  -> Booked
  [10:30,11:30) overlap       -> Conflict with booking 1 (ann)
  rooms {B, A} at 12:00 (locked in order A, B) -> Booked
== 2. Weekly Monday 09:00 America/New_York across the DST change (2026-11-01) ==
  occurrence 1: 2026-10-26T09:00 local = 2026-10-26T13:00:00Z UTC | naive 'previous + 7 days' = 2026-10-26T09:00 local
  occurrence 2: 2026-11-02T09:00 local = 2026-11-02T14:00:00Z UTC | naive 'previous + 7 days' = 2026-11-02T08:00 local
  occurrence 3: 2026-11-09T09:00 local = 2026-11-09T14:00:00Z UTC | naive 'previous + 7 days' = 2026-11-09T08:00 local
== 3. A series is all-or-nothing ==
  3-week series where week 2 is taken -> Conflict at 2026-11-02T14:00:00Z; bookings in room: 1
== 4. 8 threads x 2,000 attempts, 10 rooms, 5 days of 30-min slots, 10% weekly series ==
  check under read lock, insert later confirmed 1710 slots | overlapping pairs stored 6 | confirmed but silently overwritten 14
  check + insert under room write locks confirmed 1692 slots | overlapping pairs stored 0 | confirmed but silently overwritten 0
== 4b. Hot room: 4 threads, one room, each wants 1 h starting 10:00 / 10:30 / 11:00, 2,000 rounds ==
  check under read lock, insert later rounds ending with overlapping bookings 1999 of 2,000
  check + insert under room write locks rounds ending with overlapping bookings 0 of 2,000
== 5. find_and_book: 30 threads want the same hour; 10 rooms exist ==
  bookings made 10 (one per room), overlaps 0
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Conflict check | Scan all bookings, O(n) | Sorted list / interval tree | `floorEntry`/`ceilingEntry` neighbours on a non-overlapping map, O(log n); half-open intervals |
| Concurrency | `synchronized` scheduler | Per-room locks | Per-room RW locks; check + insert under the write lock; remote work outside locks; multi-room in id order; free/busy under read locks |
| Recurrence | A loop adding 7 days to an instant | `ZonedDateTime` expansion | Wall-clock expansion in the zone, an all-or-nothing series, exceptions (`EXDATE`) and edits ("this and following") as separate series versions |
| Testing | Happy path | Concurrent random bookings | Hot-room collision tests, stored-vs-confirmed audit, DST boundary tests, cross-platform runs (found the rwlock bug) |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Cancel one occurrence of a series" | An `EXDATE` set on the series + removal of that booking. Expansion skips it; `seriesId` links them |
| "Edit this and all following" | Split the series: end the old one at the edit point (`UNTIL`), create a new series with the new rule. Both are atomic operations under the room lock |
| "Rooms have capacity; find the smallest room that fits" | Sort candidates by capacity, then by id (still a total lock order since one room is booked per attempt) |
| "Attendees can't be double-booked either" | A second index keyed by person; book room + attendee calendars all-or-nothing, locking rooms and persons in one global order (e.g. by `"R:" + id` / `"P:" + id`) |
| "Scale to a global company" | Per-room aggregates partitioned by building; series expansion bounded by a horizon (12 months) and extended by a background job |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "How do you check for a conflict in O(log n)?"</b></summary>

**L5:** "Loop over the room's bookings."

**Why it fails:** O(n) per booking, under the room's lock.

**L7 defence:** "Keep the room's bookings in a map ordered by start and non-overlapping. Then only the latest booking starting at or before `s` (it might end after `s`) and the first starting at or after `s` (it might start before `e`) can conflict: `floorEntry` and `ceilingEntry`, both O(log n), with half-open intervals so back-to-back meetings are fine."
</details>

<details>
<summary><b>Q2 ⚡ "Why not check under a read lock and only take the write lock to insert?"</b></summary>

**L5:** "Reads are more common, so it's faster."

**Why it fails:** check-then-act across two lock acquisitions. Measured: 1,998 of 2,000 hot-room rounds overlapped in C++, and confirmed bookings were silently overwritten by `put` with an equal key.

**L7 defence:** "The check and the insert are one atomic step under the room's write lock. Read locks serve read-only views. Remote work (permissions, notifications) happens outside the lock, before the check or after the commit."
</details>

<details>
<summary><b>Q3 ⚡ "A weekly 9 AM meeting: how do you store it?"</b></summary>

**L5:** "Store the first instant and add 7 days."

**Why it fails:** after the DST change it becomes 08:00 local. The listing shows it.

**L7 defence:** "Expand in the zone: 09:00 local on each date, converted to an instant per occurrence (13:00Z before 2026-11-01, 14:00Z after). Durations and timeouts use a monotonic clock. Calendar semantics use wall time in the zone. In C++ use `zoned_time` where the tzdb exists and test the fallback."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Double-booked rooms under load | Check under the read lock, insert later | Check + insert under the write lock |
| "Confirmed" meetings vanish | `put` overwrote an equal start key | Conflict check under the same lock; stored-vs-confirmed audit |
| Recurring meetings an hour off after DST | Instant + 7 days | Expand in the zone |
| Deadlock booking two rooms | Locks in request order | Room-id order |
| Hang/crash only on MinGW GCC | Racy lazy init of fresh `shared_mutex` | Warm the lock in the constructor; reproduce minimally |

- [ ] Half-open intervals; O(log n) neighbour checks on a non-overlapping ordered map.
- [ ] Check + insert atomic per room; multi-room locks in id order; remote work outside locks.
- [ ] Series expanded in the zone, booked all-or-nothing; DST boundaries tested.
- [ ] Hot-collision tests plus audits (overlaps, stored vs confirmed).
- [ ] Concurrency tests run on every target toolchain.

## 10. References

- RFC 5545, iCalendar (RRULE). <https://www.rfc-editor.org/rfc/rfc5545>
- Java `TreeMap.floorEntry` / `ceilingEntry`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/TreeMap.html>
- cppreference, `std::chrono::zoned_time` / `locate_zone`. <https://en.cppreference.com/w/cpp/chrono/zoned_time>
- mingw-w64 winpthreads (`pthread_rwlock` implementation). <https://github.com/mingw-w64/mingw-w64/tree/master/mingw-w64-libraries/winpthreads>
- In this KB: [01.3 Wall clock vs monotonic time](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P6 All-or-nothing holds](01-problem-06-movie-ticket-booking-bookmyshow-seat-lock-and-deadlock-free.md)
