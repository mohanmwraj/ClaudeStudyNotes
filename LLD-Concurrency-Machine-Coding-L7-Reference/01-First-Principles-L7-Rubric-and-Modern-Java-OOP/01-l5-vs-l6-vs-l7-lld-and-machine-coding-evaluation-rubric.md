# 01 · The L5 / L6 / L7 Rubric for LLD and Concurrency Machine Coding

> **Folder 01 · File 1 of 3.** This file covers what the low-level-design (LLD) and machine-coding rounds actually measure, the full rubric across levels, how panels turn evidence into a level, and one calibration exhibit. In that exhibit, one problem is written five ways (L5a, L5b, L5c, L6, L7) in **Java 21 and C++23**, and all five run through the same test battery.
>
> **Verified:** both listings compile warning-free (`javac --release 21 -Xlint:all -Werror`; `g++ 16.2` and `clang++ 21.1` with `-std=c++23 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`). The outputs below are real runs on an Intel i5-11260H (6C/12T), Windows 11, Temurin 25.0.4.1. Race counts vary run to run and are labelled *one measured run*. PASS/FAIL verdicts are deterministic.

**Tags used throughout this KB:** 🔥 asked constantly · ⚡ high-leverage differentiator (where L6/L7 separate from L5) · 🧊 deep cut (rarely asked, decisive when it is) · ⚠ verify (release- or company-dependent).

---

## Contents

1. [What the round measures: first principles](#1-what-the-round-measures-first-principles)
2. [The master rubric: 14 dimensions × three levels](#2-the-master-rubric-14-dimensions--three-levels)
3. [Scoring mechanics: gates, weights, and how a level is decided](#3-scoring-mechanics-gates-weights-and-how-a-level-is-decided)
4. [Calibration exhibit: one seat-hold service, five levels](#4-calibration-exhibit-one-seat-hold-service-five-levels)
5. [Reading the results](#5-reading-the-results)
6. [Correctness argument for the L7 design](#6-correctness-argument-for-the-l7-design)
7. [Curveballs: how each level responds](#7-curveballs-how-each-level-responds)
8. [The 60/90-minute budget by level](#8-the-6090-minute-budget-by-level)
9. [Red-flag catalogue (Java and C++)](#9-red-flag-catalogue-java-and-c)
10. [What each level sounds like](#10-what-each-level-sounds-like)
11. [Self-assessment scorecard](#11-self-assessment-scorecard)
12. [Bar-raiser chains](#12-bar-raiser-chains)
13. [Invariants checklist for any submission](#13-invariants-checklist-for-any-submission)
14. [References](#14-references)

---

## 1. What the round measures: first principles

### 1.1 The interviewer's estimation problem 🔥

An interviewer has 45–90 minutes to estimate one hidden variable: **if this person owned the core module of a service I depend on, how often would I be paged because of their design decisions?** The code you write is evidence for that variable. It is not the deliverable. Three consequences follow, and most candidates miss them:

1. **Signal per minute is the currency.** A feature that demonstrates nothing new (a fifth `VehicleType`, a third getter) costs minutes and earns zero signal. A two-line comment that names the unit of atomicity ("the hold is all-or-nothing across seats; the lock order is ascending seat id") earns a lot.
2. **Defects are weighted by blast radius, not by count.** A misspelt method name is noise. A check-then-act race on the booking path is a production incident. Panels are trained to spend their attention accordingly.
3. **The interviewer is testing the *evolution path* as much as the snapshot.** The curveball halfway through ("now payments can arrive late", "now there are three app servers") is the real interview. The first 30 minutes mostly buy the right to be asked it.

### 1.2 The four round formats

Companies name these rounds differently and change them often (⚠ ask your recruiter for the exact format). The underlying formats are stable, though:

| Format | Typical shape | What is actually graded | Where L7 separates |
|---|---|---|---|
| **LLD / OOD whiteboard** | 45–60 min; classes, interfaces, sequence of calls; little or no compiled code | Decomposition, responsibilities, extension axes, state model | Picks *which* axis is open (types vs operations) and says why; names invariants and the consistency boundary |
| **Machine coding** | 60–120 min; runnable, often demo-driven code in an IDE; requirements drip-fed | Working code, modularity, correctness, time management | Correct by construction: illegal states unrepresentable, deterministic tests, concurrency designed rather than patched |
| **Concurrency coding** | 45–60 min; "implement a thread-safe X" (cache, limiter, pool, scheduler, bounded queue) | Atomicity unit, visibility, deadlock freedom, contention, testing under threads | Explains the *memory model* reason a fix works; measures or bounds contention; knows how production libraries solved it |
| **Code review / extension** | 45 min; read existing code, find defects, extend it | Reading speed, defect triage by severity, safe refactoring | Finds the *systemic* defect (the identity bug, the time source, the lock order), not only the local ones |

The five-level exhibit in §4 is deliberately usable in all four formats: as a whiteboard design, as machine coding, as a concurrency problem, and as a code-review exercise (hand someone the L6 version and ask what is wrong).

### 1.3 Level names across companies ⚠

| This KB | Google | Meta | Amazon | Microsoft | Typical expectation in an LLD round |
|---|---|---|---|---|---|
| **L5** (Senior) | L5 | E5 | L6 (SDE III) | 63–64 | Correct, clean, finishes, handles the obvious races when prompted |
| **L6** (Staff) | L6 | E6 | L7 (Principal) | 65–66 ⚠ | Designs for the change axes; concurrency correct without prompting; deterministic tests; explicit trade-offs |
| **L7** (Senior Staff / Principal) | L7 | E7 | L8 (Senior Principal) ⚠ | 67+ ⚠ | Reasons from invariants and failure semantics, picks the *minimum* mechanism, knows how production systems (Caffeine, Disruptor, Kafka, Postgres) solved the same problem, and shows the path from in-process to distributed |

Level ladders are not isomorphic across companies. Treat the table as the conventional mapping candidates use, and check it against current data (levels.fyi, your recruiter) before you rely on it.

### 1.4 What "L7 in a machine-coding round" means ⚡

Many loops don't run machine coding for very senior candidates at all. When they do, the round is a **depth probe** inside a broader loop, and three things change:

- **The bar on correctness doesn't rise, the bar on *why* does.** An L5 who writes sorted lock acquisition and an L7 who writes it produce identical code. The L7 also states the wait-for-graph argument (§6), notes the case where the order is unknown up front (lock-coupling, §7), and names the production analogue (Postgres row locks plus deadlock detection, or a fencing token at the storage layer).
- **Fewer mechanisms, chosen deliberately.** L7 code is often *smaller* than L6 code. A global lock is the correct first answer for a 60-minute round with low contention, and saying so (with the condition under which it stops being correct) is stronger than reflexively striping everything.
- **Evolution is narrated, not just performed.** "In-process this is a per-seat lock. Across three replicas the lock moves into the database as a conditional `UPDATE … WHERE state='HELD' AND token=?`, and the token becomes the fencing token the payment provider echoes back." That one sentence earns the cross-system signal the round exists to find.

---

## 2. The master rubric: 14 dimensions × three levels

Each row describes **observable behaviour**: what an interviewer can see in the code or hear in the explanation. "Red flags" are behaviours that typically cap the level, whatever else happens.

| # | Dimension | L5 (Senior) | L6 (Staff) | L7 (Principal) | Red flags (cap the level) |
|---|---|---|---|---|---|
| D1 | **Requirements & scope** 🔥 | Asks clarifying questions; lists functional requirements | Separates functional from non-functional; states scale and contention assumptions ("one hot show, 50k users") | Identifies the 1–2 requirements that *decide the design* (e.g. "late webhooks exist" → identity of a hold must be a token) and parks the rest explicitly | Starts coding at minute 2; no stated assumptions; gold-plates a requirement nobody asked for |
| D2 | **Domain modelling & invariants** 🔥 | Sensible nouns → classes; getters/setters; some validation | Value objects (Money, SeatId); enums for state; invariants in constructors | **Illegal states unrepresentable**: sealed state ADTs carrying per-state data; invariants stated as predicates and enforced by types; identity vs value made explicit | `boolean isPaid, isCancelled` soup; `double` for money; public mutable collections; anemic models with logic in "managers" |
| D3 | **API & contract design** | Methods that work for the happy path | Return types that encode outcomes (`Optional`, result types); checked preconditions | Outcomes as a closed set (`Confirmed`/`AlreadyConfirmed`/`Rejected(reason)`); idempotency designed into the contract; the API states its atomicity ("all seats or none") | Exceptions for control flow; `null` returns meaning three different things; boolean success flags without reasons |
| D4 | **State & lifecycle** ⚡ | A status enum; transitions spread across methods | One transition function; illegal transitions rejected | Transition function is total and exhaustive (`switch` over sealed types with no `default`); idempotent replays are explicit; terminal states are terminal by construction | Transitions by field assignment from anywhere; "we'll check the status in the UI" |
| D5 | **Concurrency correctness** 🔥 | Adds `synchronized`/`ConcurrentHashMap` when prompted; may leave check-then-act races | Identifies the unit of atomicity; no compound operations across separate atomic calls; deadlock-free lock order | Argues correctness: linearization point, lock order as a total order (wait-for-graph is acyclic), happens-before for publication; knows when a lock is *cheaper* than CAS | "ConcurrentHashMap so it's thread-safe"; locks taken in request order; `volatile` used as a lock |
| D6 | **Contention & performance** | Big-O of the core operation | Per-key locking/striping where contention is real; avoids `O(n)` scans on hot paths | Quantifies: critical-section length × arrival rate; knows false sharing, hot-key mitigation (sub-bucketing), and when a single-writer event loop beats locks entirely | Premature lock-free code with no contention model; a global lock with remote calls inside |
| D7 | **Extensibility (the right axes)** | Strategy/factory where the interviewer hints | Extension points at the axes that actually vary (pricing, dispatch, matching rules) | States which axis is **open** (new strategies) and which is **closed** (sealed states: adding one should break the build); avoids speculative generality | An interface per class "for testability"; inheritance hierarchies with no behavioural difference; `AbstractFactoryFactory` |
| D8 | **Time, randomness & I/O determinism** ⚡ | Calls `System.currentTimeMillis()` / `Instant.now()` inline | Injects `java.time.Clock`; seeds randomness | Distinguishes wall time (`Clock`) from durations (monotonic `Ticker`/`nanoTime`); tests TTL boundaries to the nanosecond; virtual-time schedulers; knows clock steps (NTP) break wall-clock TTLs | `Thread.sleep()` in tests; `new Date()` inside domain logic; `Random()` without a seed in tests |
| D9 | **Testing & verification** 🔥 | A `main` with happy-path prints | Unit tests for edge cases; a multi-threaded test with a `CountDownLatch` | A stress harness with invariants (not counts), spin-gated starts, round timeouts and deadlock diagnosis; deterministic tests for time; knows jcstress/Lincheck/TSan exist and what each proves | "It works on my machine" after one run; asserting exact interleaving counts; no test for the concurrency claim |
| D10 | **Failure semantics** ⚡ | Handles invalid input | Timeouts, retries, error results | Idempotency keys, fencing tokens, at-least-once delivery, out-of-order callbacks, partial failure of multi-resource operations, compensation | Retries without idempotency; "the webhook will arrive in order" |
| D11 | **Code quality & idiom** | Readable, consistent naming | Modern idiom (records, sealed, pattern matching / `std::variant`, `std::expected`); small functions; no duplication | Code reads as a *specification*: the types tell the reader the rules; comments explain *why* (lock order, linearization point), never *what* | Copy-pasted blocks per variant; 200-line methods; commented-out code |
| D12 | **Language & runtime mastery (Java + C++)** 🧊 | Knows the collections and `synchronized` | Knows `java.util.concurrent` and the C++ `<atomic>`/`<mutex>` toolkits | Knows what the JMM guarantees and C++ leaves undefined (a data race is UB in C++, merely surprising in Java); memory-order costs on x86 vs ARM; AQS/CHM internals; ABI-level pitfalls (`long` is 32-bit on Windows) | Assumes `long` is 64-bit everywhere; `std::mutex` locked twice; detached threads touching stack memory |
| D13 | **Operability** | Prints logs | Metrics hooks for key counters (holds, rejections); structured errors | Designs for diagnosis: the reason codes *are* the metric labels; backpressure and admission control; what to alert on | Silent catch-and-ignore; `e.printStackTrace()`; swallowed `InterruptedException` |
| D14 | **Communication & curveball handling** 🔥 | Explains code when asked; can extend with help | Narrates decisions and trade-offs; handles a requirement change in place | Frames changes as "which invariant moved?"; refactors in under 5 minutes because the design anticipated the axis; teaches the interviewer something true and precise | Defensive arguing; rewriting from scratch on every change; silence for 10 minutes |

> **How to use the table.** Pick a practice problem. After you finish, score yourself on each row from 1 to 4 (§3.1). Then look at the **red flags** column first: one red flag in D2, D5 or D8 costs more than any amount of polish elsewhere.

---

## 3. Scoring mechanics: gates, weights, and how a level is decided

### 3.1 The 1–4 scale

| Score | Meaning | What it looks like |
|---|---|---|
| **1** | No-hire signal on this dimension | A red-flag behaviour, or the dimension is absent |
| **2** | Leaning no | Present but incomplete, or needed heavy prompting |
| **3** | Solid at the target level | The level-appropriate column of §2, unprompted |
| **4** | Above level | The next column up, unprompted; or teaches the interviewer |

### 3.2 Hard gates (apply before any weighting) ⚡

Most panels apply these whether or not they're written down:

| Gate | Statement | Why it is a gate |
|---|---|---|
| **G1 Runs** | The submission compiles and the demo path executes | In machine coding, uncompilable code makes every other score hypothetical |
| **G2 Race-free core** | No data race or check-then-act race on the primary mutation path (booking, transfer, decrement) | The defect class with the largest blast radius, and the one the round exists to detect |
| **G3 No reachable illegal state** | No sequence of public-API calls produces a state the domain forbids (double-booked seat, negative balance, refunded-but-not-captured) | It's the definition of "correct" for a stateful component |
| **G4 Honest time** | Expiry and timeouts are testable without sleeping, and no wall clock is used where a duration is meant | TTL bugs are the classic "passes the demo, fails at 3 a.m." defect |

Failing G1 or G2 usually caps the outcome at "no hire" regardless of level. Failing G3 or G4 usually caps it at L5.

### 3.3 Weights by round type

The weights describe where interviewers spend their attention. They are not a formula anyone runs.

| Dimension group | LLD whiteboard | Machine coding | Concurrency coding |
|---|---|---|---|
| D1 Requirements, D14 Communication | 25% | 15% | 10% |
| D2 Modelling, D3 API, D4 State | 35% | 25% | 10% |
| D5 Concurrency, D6 Contention | 10% | 20% | 45% |
| D7 Extensibility | 20% | 15% | 5% |
| D8 Time, D9 Testing, D10 Failure | 10% | 20% | 25% |
| D11–D13 Quality, Language, Operability | — | 5% | 5% |

### 3.4 How a level is decided 🔥

- **Consistency beats spikes.** A candidate with 4s on D5/D6 and 2s on D2/D4 reads as "strong L5 concurrency engineer" more often than "L6". Staff-level judgment is supposed to show up everywhere, not only in the candidate's favourite topic.
- **The floor matters more than the ceiling.** One red flag in a gate dimension outweighs a brilliant aside. "An L7 spike with an L5 floor is an L6 at best" is a common calibration heuristic.
- **Prompting is evidence.** A behaviour that appears only after a hint scores one point lower than the same behaviour unprompted.
- **The curveball is weighted heavily.** How you change the design when a requirement moves is the closest proxy for how you'll behave on the job. A candidate who rewrites from scratch loses more than one who adapts a slightly worse design in place.
- **The bar raiser's question is "would this person raise the average of the team at this level?"** Bar raisers, the extra calibrated interviewer some loops include, can veto, and they focus on D2, D5 and D14.

---
## 4. Calibration exhibit: one seat-hold service, five levels

### 4.1 The problem (as an interviewer would state it)

> A cinema show has `N` seats. A user can **hold** one or more seats for 5 minutes while paying. Holding is all-or-nothing. When the payment provider calls our **webhook**, we **confirm** the hold and the seats become booked. If the hold has expired, the seats must be available to other users. Make it correct under concurrent users.

Two sentences in that prompt decide the design, and the L7 candidate says so up front:

1. **"All-or-nothing across seats"** makes the unit of atomicity a *set* of seats, so multi-resource locking and a global order are needed (or a single lock).
2. **"Webhook" plus "expired"** means the confirmation arrives *asynchronously and possibly late*, and possibly more than once (providers retry). A hold therefore needs an **identity that survives expiry and re-hold**: a monotonically increasing token, not "the user who holds the seat".

### 4.2 The five designs at a glance

| Variant | State model | Atomicity mechanism | Lock order | Time source | Identity of a hold on confirm | Expected verdict |
|---|---|---|---|---|---|---|
| **L5a** `CheckThenActMap` | Two `ConcurrentHashMap`s | Each call is atomic; the *sequence* isn't | n/a | `System.currentTimeMillis()` | user id | Double holds and double bookings |
| **L5b** `GlobalLock` | Booleans + nullable fields | One `synchronized` (one `std::mutex`) | trivially total | wall clock | user id | Correct, serialized, untestable TTL |
| **L5c** `UnorderedSeatLocks` | Booleans + nullable fields | Per-seat locks | **request order** | wall clock | user id | Deadlock |
| **L6** `OrderedSeatLocks` | `enum` status + nullable fields | Per-seat locks | ascending seat id, de-duplicated | injected `Clock` | **user id** | Passes races and TTL; **fails the stale webhook (ABA)** |
| **L7** `FencedSeatHolds` | `sealed` `Free \| Held \| Booked` (C++: `std::variant`) | Per-seat locks | ascending seat id, de-duplicated | injected `Clock` | **fencing token** | Passes everything; idempotent retries |

The test battery is the same for every variant:

- **T1 race.** 4 threads × 3 attempts × 20,000 rounds on 12 seats. Each round uses a fresh service, and workers are released by a **spin gate** so they really overlap. Each attempt requests two seats in random order, which makes about half of all requests "descending". The harness counts rounds where any seat was held twice or confirmed twice, and declares a deadlock if a round makes no progress for 2 s.
- **T2 TTL boundary.** The seat must still be blocked at `TTL − 1 ns` and free at exactly `TTL`. That is only possible with an injected clock.
- **T3 stale webhook.** Alice holds seat 7 (hold h1). The hold expires. Alice re-holds seat 7 from a second tab (h2). Then the webhook for h1 arrives, then the webhook for h2, then the provider retries h2's webhook.

### 4.3 Java 21 listing

```java
// SeatHoldLevels.java - one seat-hold problem written at L5, L6 and L7, run through one test battery
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadInfo;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicIntegerArray;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.Function;

public final class SeatHoldLevels {

    // ===== Shared contract: every level implements the same API ===============================

    /** Returned by a successful hold. At L7 the token is also the fencing token. */
    record Hold(long token, String userId, List<Integer> seats) {
        Hold {
            seats = List.copyOf(seats);
        }
    }

    sealed interface ConfirmResult permits Confirmed, AlreadyConfirmed, Rejected {}
    record Confirmed(String paymentId) implements ConfirmResult {}
    record AlreadyConfirmed(String paymentId) implements ConfirmResult {}
    record Rejected(String reason) implements ConfirmResult {}

    interface SeatHoldService {
        Optional<Hold> hold(String userId, List<Integer> seats);  // all seats or none
        ConfirmResult confirm(Hold hold, String paymentId);       // the payment webhook
    }

    static final Duration TTL = Duration.ofMinutes(5);

    // ===== L5-a: "ConcurrentHashMap is thread-safe, so my service is" ===========================

    static final class CheckThenActMap implements SeatHoldService {
        private record HoldRec(String userId, long expiresAtMillis) {}
        private final ConcurrentHashMap<Integer, HoldRec> holds = new ConcurrentHashMap<>();
        private final ConcurrentHashMap<Integer, String> booked = new ConcurrentHashMap<>();
        private final AtomicLong ids = new AtomicLong();

        @Override public Optional<Hold> hold(String userId, List<Integer> seats) {
            long now = System.currentTimeMillis();                 // wall clock, hard-wired
            for (int s : seats) {                                   // CHECK ...
                HoldRec r = holds.get(s);
                if (booked.containsKey(s) || (r != null && r.expiresAtMillis() > now)) return Optional.empty();
            }
            for (int s : seats) holds.put(s, new HoldRec(userId, now + TTL.toMillis()));  // ... THEN ACT
            return Optional.of(new Hold(ids.incrementAndGet(), userId, seats));
        }

        @Override public ConfirmResult confirm(Hold hold, String paymentId) {
            for (int s : hold.seats()) {
                HoldRec r = holds.get(s);
                if (r == null || !r.userId().equals(hold.userId())) return new Rejected("NOT_HELD");
            }
            for (int s : hold.seats()) booked.put(s, paymentId);
            return new Confirmed(paymentId);
        }
    }

    // ===== L5-b: one big lock, boolean flags, wall clock ======================================

    static final class GlobalLock implements SeatHoldService {
        private static final class Seat {          // 2 flags + 3 nullable fields: most combinations are illegal
            boolean isHeld, isBooked;
            String heldBy, paymentId;
            long heldUntilMillis;
        }
        private final Seat[] seats;
        private long ids;

        GlobalLock(int n) {
            seats = new Seat[n];
            for (int i = 0; i < n; i++) seats[i] = new Seat();
        }

        @Override public synchronized Optional<Hold> hold(String userId, List<Integer> req) {
            long now = System.currentTimeMillis();
            for (int s : req) {
                Seat x = seats[s];
                if (x.isBooked || (x.isHeld && x.heldUntilMillis > now)) return Optional.empty();
            }
            for (int s : req) {
                Seat x = seats[s];
                x.isHeld = true;
                x.heldBy = userId;
                x.heldUntilMillis = now + TTL.toMillis();
            }
            return Optional.of(new Hold(++ids, userId, req));
        }

        @Override public synchronized ConfirmResult confirm(Hold hold, String paymentId) {
            long now = System.currentTimeMillis();
            for (int s : hold.seats()) {
                Seat x = seats[s];
                if (!x.isHeld || !hold.userId().equals(x.heldBy) || x.heldUntilMillis <= now) return new Rejected("NOT_HELD");
            }
            for (int s : hold.seats()) {
                Seat x = seats[s];
                x.isBooked = true;
                x.isHeld = false;                     // forget this line and isHeld && isBooked is "legal"
                x.paymentId = paymentId;
            }
            return new Confirmed(paymentId);
        }
    }

    // ===== L5-c: per-seat locks taken in request order (the multi-seat deadlock trap) ===========

    static final class UnorderedSeatLocks implements SeatHoldService {
        private final GlobalLock.Seat[] seats;
        private final ReentrantLock[] locks;
        private final AtomicLong ids = new AtomicLong();

        UnorderedSeatLocks(int n) {
            seats = new GlobalLock.Seat[n];
            locks = new ReentrantLock[n];
            for (int i = 0; i < n; i++) {
                seats[i] = new GlobalLock.Seat();
                locks[i] = new ReentrantLock();
            }
        }

        @Override public Optional<Hold> hold(String userId, List<Integer> req) {
            for (int s : req) locks[s].lock();                     // [3,7] vs [7,3] -> deadlock
            try {
                long now = System.currentTimeMillis();
                for (int s : req) {
                    GlobalLock.Seat x = seats[s];
                    if (x.isBooked || (x.isHeld && x.heldUntilMillis > now)) return Optional.empty();
                }
                for (int s : req) {
                    GlobalLock.Seat x = seats[s];
                    x.isHeld = true;
                    x.heldBy = userId;
                    x.heldUntilMillis = now + TTL.toMillis();
                }
                return Optional.of(new Hold(ids.incrementAndGet(), userId, req));
            } finally {
                for (int s : req) locks[s].unlock();
            }
        }

        @Override public ConfirmResult confirm(Hold hold, String paymentId) {
            for (int s : hold.seats()) locks[s].lock();
            try {
                long now = System.currentTimeMillis();
                for (int s : hold.seats()) {
                    GlobalLock.Seat x = seats[s];
                    if (!x.isHeld || !hold.userId().equals(x.heldBy) || x.heldUntilMillis <= now) return new Rejected("NOT_HELD");
                }
                for (int s : hold.seats()) {
                    GlobalLock.Seat x = seats[s];
                    x.isBooked = true;
                    x.isHeld = false;
                    x.paymentId = paymentId;
                }
                return new Confirmed(paymentId);
            } finally {
                for (int s : hold.seats()) locks[s].unlock();
            }
        }
    }

    // ===== Lock-order helpers shared by L6 and L7 ===============================================

    /** Sorted, de-duplicated, range-checked: the one global lock order. */
    static int[] lockOrder(List<Integer> req, int n) {
        if (req.isEmpty()) throw new IllegalArgumentException("no seats requested");
        int[] order = req.stream().mapToInt(Integer::intValue).sorted().distinct().toArray();
        if (order[0] < 0 || order[order.length - 1] >= n) throw new IllegalArgumentException("seat out of range: " + req);
        return order;
    }

    static void lockAll(ReentrantLock[] locks, int[] order) {
        for (int s : order) locks[s].lock();
    }

    static void unlockAll(ReentrantLock[] locks, int[] order) {
        for (int i = order.length - 1; i >= 0; i--) locks[order[i]].unlock();
    }

    // ===== L6: deadlock-free, injected Clock, enum status + nullable fields =====================

    static final class OrderedSeatLocks implements SeatHoldService {
        enum Status { FREE, HELD, BOOKED }
        private static final class Seat {
            Status status = Status.FREE;
            String holder;           // non-null iff HELD or BOOKED -- by convention only
            Instant expiresAt;       // meaningful iff HELD          -- by convention only
            String paymentId;        // non-null iff BOOKED          -- by convention only
        }
        private final Seat[] seats;
        private final ReentrantLock[] locks;
        private final Clock clock;
        private final AtomicLong ids = new AtomicLong();

        OrderedSeatLocks(int n, Clock clock) {
            this.clock = clock;
            seats = new Seat[n];
            locks = new ReentrantLock[n];
            for (int i = 0; i < n; i++) {
                seats[i] = new Seat();
                locks[i] = new ReentrantLock();
            }
        }

        @Override public Optional<Hold> hold(String userId, List<Integer> req) {
            int[] order = lockOrder(req, seats.length);
            lockAll(locks, order);
            try {
                Instant now = clock.instant();
                for (int s : order) {
                    Seat x = seats[s];
                    boolean free = x.status == Status.FREE
                            || (x.status == Status.HELD && !now.isBefore(x.expiresAt));
                    if (!free) return Optional.empty();
                }
                for (int s : order) {
                    Seat x = seats[s];
                    x.status = Status.HELD;
                    x.holder = userId;
                    x.expiresAt = now.plus(TTL);
                }
                return Optional.of(new Hold(ids.incrementAndGet(), userId, req));
            } finally {
                unlockAll(locks, order);
            }
        }

        @Override public ConfirmResult confirm(Hold hold, String paymentId) {
            int[] order = lockOrder(hold.seats(), seats.length);
            lockAll(locks, order);
            try {
                Instant now = clock.instant();
                for (int s : order) {
                    Seat x = seats[s];
                    // "Is this seat still held by this user and not expired?" -- the question is wrong:
                    // it identifies the hold by WHO, not by WHICH hold.
                    if (x.status != Status.HELD || !x.holder.equals(hold.userId()) || !now.isBefore(x.expiresAt))
                        return new Rejected("NOT_HELD");
                }
                for (int s : order) {
                    Seat x = seats[s];
                    x.status = Status.BOOKED;
                    x.paymentId = paymentId;
                }
                return new Confirmed(paymentId);
            } finally {
                unlockAll(locks, order);
            }
        }
    }

    // ===== L7: sealed states (illegal states unrepresentable) + fencing token + idempotency =====

    static final class FencedSeatHolds implements SeatHoldService {
        sealed interface SeatState permits Free, Held, Booked {}
        record Free() implements SeatState {}
        record Held(long token, String userId, Instant expiresAt) implements SeatState {}
        record Booked(long token, String userId, String paymentId) implements SeatState {}

        enum Verdict { OK, ALREADY_MINE, SOLD, SUPERSEDED, EXPIRED, NOT_HELD }

        private final SeatState[] seats;              // seats[i] guarded by locks[i]
        private final ReentrantLock[] locks;
        private final Clock clock;
        private final AtomicLong fencing = new AtomicLong();   // a newer hold always has a larger token

        FencedSeatHolds(int n, Clock clock) {
            this.clock = clock;
            seats = new SeatState[n];
            locks = new ReentrantLock[n];
            Arrays.fill(seats, new Free());
            for (int i = 0; i < n; i++) locks[i] = new ReentrantLock();
        }

        private static boolean available(SeatState st, Instant now) {
            return switch (st) {                       // exhaustive: a 4th state is a compile error here
                case Free f -> true;
                case Held h -> !now.isBefore(h.expiresAt());   // lazy expiry: expired == free
                case Booked b -> false;
            };
        }

        private static Verdict judge(SeatState st, Hold hold, Instant now) {
            return switch (st) {
                case Booked b when b.token() == hold.token() -> Verdict.ALREADY_MINE;
                case Booked b -> Verdict.SOLD;
                case Held h when h.token() != hold.token() -> Verdict.SUPERSEDED;
                case Held h when !now.isBefore(h.expiresAt()) -> Verdict.EXPIRED;
                case Held h -> Verdict.OK;
                case Free f -> Verdict.NOT_HELD;
            };
        }

        @Override public Optional<Hold> hold(String userId, List<Integer> req) {
            int[] order = lockOrder(req, seats.length);
            lockAll(locks, order);
            try {
                Instant now = clock.instant();
                for (int s : order) if (!available(seats[s], now)) return Optional.empty();
                long token = fencing.incrementAndGet();
                Held held = new Held(token, userId, now.plus(TTL));
                for (int s : order) seats[s] = held;
                return Optional.of(new Hold(token, userId, req));
            } finally {
                unlockAll(locks, order);
            }
        }

        @Override public ConfirmResult confirm(Hold hold, String paymentId) {
            int[] order = lockOrder(hold.seats(), seats.length);
            lockAll(locks, order);
            try {
                Instant now = clock.instant();
                int ok = 0, mine = 0;
                for (int s : order) {
                    Verdict verdict = judge(seats[s], hold, now);
                    switch (verdict) {
                        case OK -> ok++;
                        case ALREADY_MINE -> mine++;
                        case SOLD, SUPERSEDED, EXPIRED, NOT_HELD -> {
                            return new Rejected(verdict.name());
                        }
                    }
                }
                if (mine == order.length && seats[order[0]] instanceof Booked b) return new AlreadyConfirmed(b.paymentId());
                if (ok != order.length) throw new IllegalStateException("torn hold " + hold);  // cannot happen
                Booked booked = new Booked(hold.token(), hold.userId(), paymentId);
                for (int s : order) seats[s] = booked;
                return new Confirmed(paymentId);
            } finally {
                unlockAll(locks, order);
            }
        }
    }

    // ===== Deterministic time ===================================================================

    /** A test clock: thread-safe, honours the Clock contract (withZone returns a view, never throws). */
    static final class MutableClock extends Clock {
        private final AtomicReference<Instant> now;
        private final ZoneId zone;

        MutableClock(Instant start) {
            this(new AtomicReference<>(start), ZoneOffset.UTC);
        }

        private MutableClock(AtomicReference<Instant> now, ZoneId zone) {
            this.now = now;
            this.zone = zone;
        }

        void advance(Duration d) {
            now.updateAndGet(t -> t.plus(d));
        }

        @Override public Instant instant() {
            return now.get();
        }

        @Override public ZoneId getZone() {
            return zone;
        }

        @Override public Clock withZone(ZoneId z) {
            return new MutableClock(now, z);
        }
    }

    // ===== Test battery ===========================================================================

    record Variant(String name, Function<Clock, SeatHoldService> factory, boolean clockInjected) {}

    static final int SEATS = 12, THREADS = 4, ATTEMPTS = 3, ROUNDS = 20_000;
    static final long ROUND_TIMEOUT_NANOS = 2_000_000_000L;

    static long mix64(long z) {                    // SplitMix64 finaliser: same stream in Java and C++
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    /** Two distinct seats in random order: about half of all requests are "descending". */
    static List<Integer> request(int thread, int round, int attempt) {
        long x = mix64(((long) thread << 40) ^ ((long) round << 8) ^ attempt);
        int a = (int) Long.remainderUnsigned(x, SEATS);
        int b = (a + 1 + (int) Long.remainderUnsigned(x >>> 32, SEATS - 1)) % SEATS;
        return List.of(a, b);
    }

    record Round(int no, SeatHoldService svc, AtomicIntegerArray held, AtomicIntegerArray confirmed) {}

    record RaceReport(int roundsRun, int doubleHeld, int doubleConfirmed, String deadlock) {}

    /** T1: spin-gated rounds. Every round is a fresh service; all workers start within ~100 ns. */
    static RaceReport race(Variant v) {
        MutableClock clock = new MutableClock(Instant.parse("2026-01-01T00:00:00Z"));
        AtomicReference<Round> current = new AtomicReference<>(new Round(0, null, null, null));
        AtomicInteger finished = new AtomicInteger();
        AtomicInteger abort = new AtomicInteger();
        List<Thread> workers = new ArrayList<>();
        for (int t = 0; t < THREADS; t++) {
            final int tid = t;
            workers.add(Thread.ofPlatform().daemon().name("w" + t).start(() -> {
                for (int r = 1; r <= ROUNDS; r++) {
                    Round round;
                    while ((round = current.get()).no() < r) {      // volatile read: sees svc published by main
                        if (abort.get() != 0) return;
                        Thread.onSpinWait();
                    }
                    for (int a = 0; a < ATTEMPTS; a++) {
                        List<Integer> seats = request(tid, r, a);
                        Optional<Hold> h = round.svc().hold("u" + tid, seats);
                        if (h.isEmpty()) continue;
                        for (int s : seats) round.held().incrementAndGet(s);
                        if (round.svc().confirm(h.get(), "pay-" + tid + "-" + r + "-" + a) instanceof Confirmed)
                            for (int s : seats) round.confirmed().incrementAndGet(s);
                    }
                    finished.incrementAndGet();
                }
            }));
        }
        int doubleHeld = 0, doubleConfirmed = 0;
        for (int r = 1; r <= ROUNDS; r++) {
            Round round = new Round(r, v.factory().apply(clock), new AtomicIntegerArray(SEATS), new AtomicIntegerArray(SEATS));
            current.set(round);                                       // publish (volatile write)
            long deadline = System.nanoTime() + ROUND_TIMEOUT_NANOS;
            while (finished.get() < r * THREADS) {
                if (System.nanoTime() > deadline) {
                    abort.set(1);
                    return new RaceReport(r - 1, doubleHeld, doubleConfirmed, "round " + r + ": " + deadlockGraph());
                }
                Thread.onSpinWait();
            }
            boolean dh = false, dc = false;
            for (int s = 0; s < SEATS; s++) {
                dh |= round.held().get(s) > 1;
                dc |= round.confirmed().get(s) > 1;
            }
            if (dh) doubleHeld++;
            if (dc) doubleConfirmed++;
        }
        for (Thread w : workers) {
            try {
                w.join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException(e);
            }
        }
        return new RaceReport(ROUNDS, doubleHeld, doubleConfirmed, "none");
    }

    /** What the JVM itself can tell you: ThreadMXBean finds cycles over ReentrantLock owners too. */
    static String deadlockGraph() {
        var mx = ManagementFactory.getThreadMXBean();
        long[] ids = mx.findDeadlockedThreads();
        if (ids == null) return "stalled, no lock cycle";
        List<String> edges = new ArrayList<>();
        for (ThreadInfo ti : mx.getThreadInfo(ids)) edges.add(ti.getThreadName() + "->" + ti.getLockOwnerName());
        edges.sort(null);
        return "lock cycle " + String.join(" ", edges);
    }

    /** T2: the TTL boundary, tested in nanoseconds instead of a 5-minute sleep. */
    static String ttlBoundary(Variant v) {
        MutableClock clock = new MutableClock(Instant.parse("2026-01-01T00:00:00Z"));
        SeatHoldService svc = v.factory().apply(clock);
        svc.hold("alice", List.of(1, 2)).orElseThrow();
        clock.advance(TTL.minusNanos(1));
        boolean blockedJustBefore = svc.hold("bob", List.of(2)).isEmpty();
        clock.advance(Duration.ofNanos(1));
        boolean freeAtExpiry = svc.hold("bob", List.of(2)).isPresent();
        return (blockedJustBefore && freeAtExpiry ? "PASS" : "FAIL")
                + "  blocked@TTL-1ns=" + blockedJustBefore + " free@TTL=" + freeAtExpiry;
    }

    /** T3: hold expires, the same user re-holds, then the webhook for the dead hold arrives. */
    static String staleWebhook(Variant v) {
        MutableClock clock = new MutableClock(Instant.parse("2026-01-01T00:00:00Z"));
        SeatHoldService svc = v.factory().apply(clock);
        Hold h1 = svc.hold("alice", List.of(7)).orElseThrow();
        clock.advance(TTL.plusSeconds(1));                      // alice's first payment is slow
        Hold h2 = svc.hold("alice", List.of(7)).orElseThrow();  // alice retries from a second tab
        ConfirmResult late = svc.confirm(h1, "pay-1");          // webhook for the dead hold
        ConfirmResult live = svc.confirm(h2, "pay-2");          // webhook for the live hold
        ConfirmResult dup = svc.confirm(h2, "pay-2");           // provider retries the webhook
        boolean pass = late instanceof Rejected && live instanceof Confirmed && dup instanceof AlreadyConfirmed;
        return (pass ? "PASS" : "FAIL") + "  late=" + late + " live=" + live + " retry=" + dup;
    }

    public static void main(String[] args) {
        List<Variant> variants = List.of(
                new Variant("L5a CheckThenActMap", c -> new CheckThenActMap(), false),
                new Variant("L5b GlobalLock", c -> new GlobalLock(SEATS), false),
                new Variant("L5c UnorderedSeatLocks", c -> new UnorderedSeatLocks(SEATS), false),
                new Variant("L6  OrderedSeatLocks", c -> new OrderedSeatLocks(SEATS, c), true),
                new Variant("L7  FencedSeatHolds", c -> new FencedSeatHolds(SEATS, c), true));
        List<String> broken = new ArrayList<>();

        System.out.printf("== T1 race: %d threads x %d attempts x %,d rounds, %d seats, spin-gated ==%n",
                THREADS, ATTEMPTS, ROUNDS, SEATS);
        for (Variant v : variants) {
            RaceReport r = race(v);
            System.out.printf("%-23s rounds=%,6d  double-held=%,5d  double-confirmed=%,5d  deadlock=%s%n",
                    v.name(), r.roundsRun(), r.doubleHeld(), r.doubleConfirmed(), r.deadlock());
            boolean guaranteed = !v.name().startsWith("L5a") && !v.name().startsWith("L5c");
            if (guaranteed && (r.doubleHeld() + r.doubleConfirmed() > 0 || !r.deadlock().equals("none")))
                broken.add(v.name() + " T1");
        }

        System.out.println("== T2 TTL boundary: expired iff now >= expiresAt ==");
        for (Variant v : variants) {
            String res = v.clockInjected() ? ttlBoundary(v) : "N/A   wall clock hard-wired: the test needs Thread.sleep(300_000)";
            System.out.printf("%-23s %s%n", v.name(), res);
            if (v.clockInjected() && !res.startsWith("PASS")) broken.add(v.name() + " T2");
        }

        System.out.println("== T3 stale webhook: expire -> same user re-holds -> old webhook arrives ==");
        for (Variant v : variants) {
            String res = v.clockInjected() ? staleWebhook(v) : "N/A   wall clock hard-wired";
            System.out.printf("%-23s %s%n", v.name(), res);
            if (v.name().startsWith("L7") && !res.startsWith("PASS")) broken.add(v.name() + " T3");
            if (v.name().startsWith("L6") && !res.startsWith("FAIL")) broken.add("L6 T3 expected to expose the ABA bug");
        }
        System.out.println(broken.isEmpty() ? "SELF-TEST OK: guarantees hold, L6 ABA bug reproduced" : "SELF-TEST FAILED " + broken);
        if (!broken.isEmpty()) System.exit(1);
    }
}
```

**Output (one measured run: T1 counts and the deadlock round vary; T2/T3 verdicts are deterministic). JDK 25.0.4.1, `--release 21`:**

```text
== T1 race: 4 threads x 3 attempts x 20,000 rounds, 12 seats, spin-gated ==
L5a CheckThenActMap     rounds=20,000  double-held=14,511  double-confirmed=2,211  deadlock=none
L5b GlobalLock          rounds=20,000  double-held=    0  double-confirmed=    0  deadlock=none
L5c UnorderedSeatLocks  rounds=     3  double-held=    0  double-confirmed=    0  deadlock=round 4: lock cycle w0->w2 w1->w0 w2->w1
L6  OrderedSeatLocks    rounds=20,000  double-held=    0  double-confirmed=    0  deadlock=none
L7  FencedSeatHolds     rounds=20,000  double-held=    0  double-confirmed=    0  deadlock=none
== T2 TTL boundary: expired iff now >= expiresAt ==
L5a CheckThenActMap     N/A   wall clock hard-wired: the test needs Thread.sleep(300_000)
L5b GlobalLock          N/A   wall clock hard-wired: the test needs Thread.sleep(300_000)
L5c UnorderedSeatLocks  N/A   wall clock hard-wired: the test needs Thread.sleep(300_000)
L6  OrderedSeatLocks    PASS  blocked@TTL-1ns=true free@TTL=true
L7  FencedSeatHolds     PASS  blocked@TTL-1ns=true free@TTL=true
== T3 stale webhook: expire -> same user re-holds -> old webhook arrives ==
L5a CheckThenActMap     N/A   wall clock hard-wired
L5b GlobalLock          N/A   wall clock hard-wired
L5c UnorderedSeatLocks  N/A   wall clock hard-wired
L6  OrderedSeatLocks    FAIL  late=Confirmed[paymentId=pay-1] live=Rejected[reason=NOT_HELD] retry=Rejected[reason=NOT_HELD]
L7  FencedSeatHolds     PASS  late=Rejected[reason=SUPERSEDED] live=Confirmed[paymentId=pay-2] retry=AlreadyConfirmed[paymentId=pay-2]
SELF-TEST OK: guarantees hold, L6 ABA bug reproduced
```

### 4.4 C++23 listing

The C++ version keeps the same five designs and the same request stream (SplitMix64 seeded identically), with idiomatic substitutions:

- `std::variant` + `std::visit(overloaded{…})` for the sealed state.
- `std::optional` for the L6 "nullable by convention" fields.
- An RAII `LockAll` that unlocks in reverse order.
- A virtual `Clock` with a `ManualClock`.
- A `SyncMap` wrapper that locks every *call*, the C++ spelling of "ConcurrentHashMap is thread-safe".

Two C++-only obligations show up:

- **`std::mutex` is not recursive.** De-duplicating the lock order is mandatory, not hygiene: locking the same `std::mutex` twice is undefined behaviour.
- **A deadlocked `std::thread` can never be joined.** The harness detaches it, keeps everything the thread touches alive through `shared_ptr` captures, and ends with `std::quick_exit` so no destructor runs under a blocked thread.

```cpp
// seat_hold_levels.cpp - one seat-hold problem written at L5, L6 and L7, run through one test battery
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

using namespace std::chrono_literals;
using Nanos = std::chrono::nanoseconds;

// ===== Shared contract =========================================================================

struct Hold {
    std::uint64_t token;  // at L7 this is also the fencing token
    std::string user;
    std::vector<int> seats;
};

struct Confirmed { std::string payment_id; };
struct AlreadyConfirmed { std::string payment_id; };
struct Rejected { std::string reason; };
using ConfirmResult = std::variant<Confirmed, AlreadyConfirmed, Rejected>;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

std::string describe(const ConfirmResult& r) {
    return std::visit(overloaded{
        [](const Confirmed& c) { return "Confirmed[" + c.payment_id + "]"; },
        [](const AlreadyConfirmed& c) { return "AlreadyConfirmed[" + c.payment_id + "]"; },
        [](const Rejected& c) { return "Rejected[" + c.reason + "]"; },
    }, r);
}

class SeatHoldService {
public:
    virtual ~SeatHoldService() = default;
    virtual std::optional<Hold> hold(const std::string& user, const std::vector<int>& seats) = 0;  // all or none
    virtual ConfirmResult confirm(const Hold& hold, const std::string& payment_id) = 0;           // the webhook
};

constexpr auto kTtl = std::chrono::minutes(5);

std::int64_t wall_millis() {  // what L5 calls directly
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

// ===== Injectable time =========================================================================

class Clock {
public:
    using time_point = std::chrono::time_point<std::chrono::steady_clock, Nanos>;
    virtual ~Clock() = default;
    virtual time_point now() const = 0;
};

class ManualClock final : public Clock {
    std::atomic<std::int64_t> nanos_{0};
public:
    time_point now() const override { return time_point(Nanos(nanos_.load(std::memory_order_acquire))); }
    void advance(Nanos d) { nanos_.fetch_add(d.count(), std::memory_order_acq_rel); }
};

// ===== L5-a: "every call on my map is locked, so my service is thread-safe" =====================

template <class K, class V>
class SyncMap {  // each call is atomic; a sequence of calls is not
    mutable std::mutex m_;
    std::unordered_map<K, V> map_;
public:
    std::optional<V> get(const K& k) const {
        std::scoped_lock lock(m_);
        auto it = map_.find(k);
        return it == map_.end() ? std::nullopt : std::optional<V>(it->second);
    }
    bool contains(const K& k) const {
        std::scoped_lock lock(m_);
        return map_.contains(k);
    }
    void put(const K& k, V v) {
        std::scoped_lock lock(m_);
        map_.insert_or_assign(k, std::move(v));
    }
};

class CheckThenActMap final : public SeatHoldService {
    struct HoldRec { std::string user; std::int64_t expires_at_ms; };
    SyncMap<int, HoldRec> holds_;
    SyncMap<int, std::string> booked_;
    std::atomic<std::uint64_t> ids_{0};
public:
    std::optional<Hold> hold(const std::string& user, const std::vector<int>& seats) override {
        const std::int64_t now = wall_millis();  // wall clock, hard-wired
        for (int s : seats) {                    // CHECK ...
            auto r = holds_.get(s);
            if (booked_.contains(s) || (r && r->expires_at_ms > now)) return std::nullopt;
        }
        for (int s : seats) holds_.put(s, HoldRec{user, now + std::chrono::milliseconds(kTtl).count()});  // ... ACT
        return Hold{++ids_, user, seats};
    }
    ConfirmResult confirm(const Hold& hold, const std::string& payment_id) override {
        for (int s : hold.seats) {
            auto r = holds_.get(s);
            if (!r || r->user != hold.user) return Rejected{"NOT_HELD"};
        }
        for (int s : hold.seats) booked_.put(s, payment_id);
        return Confirmed{payment_id};
    }
};

// ===== L5-b: one big lock, boolean flags, wall clock ===========================================

struct FlagSeat {  // 2 flags + 3 "maybe meaningful" fields: most combinations are illegal
    bool is_held = false, is_booked = false;
    std::string held_by, payment_id;
    std::int64_t held_until_ms = 0;
};

class GlobalLock final : public SeatHoldService {
    std::mutex m_;
    std::vector<FlagSeat> seats_;
    std::uint64_t ids_ = 0;
public:
    explicit GlobalLock(int n) : seats_(static_cast<std::size_t>(n)) {}
    std::optional<Hold> hold(const std::string& user, const std::vector<int>& req) override {
        std::scoped_lock lock(m_);
        const std::int64_t now = wall_millis();
        for (int s : req) {
            const FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            if (x.is_booked || (x.is_held && x.held_until_ms > now)) return std::nullopt;
        }
        for (int s : req) {
            FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            x.is_held = true;
            x.held_by = user;
            x.held_until_ms = now + std::chrono::milliseconds(kTtl).count();
        }
        return Hold{++ids_, user, req};
    }
    ConfirmResult confirm(const Hold& hold, const std::string& payment_id) override {
        std::scoped_lock lock(m_);
        const std::int64_t now = wall_millis();
        for (int s : hold.seats) {
            const FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            if (!x.is_held || x.held_by != hold.user || x.held_until_ms <= now) return Rejected{"NOT_HELD"};
        }
        for (int s : hold.seats) {
            FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            x.is_booked = true;
            x.is_held = false;  // forget this line and is_held && is_booked is "legal"
            x.payment_id = payment_id;
        }
        return Confirmed{payment_id};
    }
};

// ===== RAII multi-lock: locks in the given order, unlocks in reverse ===========================

class LockAll {
    std::mutex* locks_;
    std::vector<int> order_;
public:
    LockAll(std::mutex* locks, std::vector<int> order) : locks_(locks), order_(std::move(order)) {
        for (int s : order_) locks_[s].lock();
    }
    ~LockAll() {
        for (auto it = order_.rbegin(); it != order_.rend(); ++it) locks_[*it].unlock();
    }
    LockAll(const LockAll&) = delete;
    LockAll& operator=(const LockAll&) = delete;
    const std::vector<int>& order() const { return order_; }
};

/** Sorted, de-duplicated, range-checked: the one global lock order (std::mutex is not recursive). */
std::vector<int> lock_order(const std::vector<int>& req, int n) {
    if (req.empty()) throw std::invalid_argument("no seats requested");
    std::vector<int> order = req;
    std::ranges::sort(order);
    order.erase(std::ranges::unique(order).begin(), order.end());
    if (order.front() < 0 || order.back() >= n) throw std::out_of_range("seat out of range");
    return order;
}

// ===== L5-c: per-seat locks in request order (the multi-seat deadlock trap) ====================

class UnorderedSeatLocks final : public SeatHoldService {
    std::vector<FlagSeat> seats_;
    std::unique_ptr<std::mutex[]> locks_;
    std::atomic<std::uint64_t> ids_{0};
public:
    explicit UnorderedSeatLocks(int n)
        : seats_(static_cast<std::size_t>(n)), locks_(std::make_unique<std::mutex[]>(static_cast<std::size_t>(n))) {}
    std::optional<Hold> hold(const std::string& user, const std::vector<int>& req) override {
        LockAll guard(locks_.get(), req);  // [3,7] vs [7,3] -> deadlock
        const std::int64_t now = wall_millis();
        for (int s : req) {
            const FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            if (x.is_booked || (x.is_held && x.held_until_ms > now)) return std::nullopt;
        }
        for (int s : req) {
            FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            x.is_held = true;
            x.held_by = user;
            x.held_until_ms = now + std::chrono::milliseconds(kTtl).count();
        }
        return Hold{++ids_, user, req};
    }
    ConfirmResult confirm(const Hold& hold, const std::string& payment_id) override {
        LockAll guard(locks_.get(), hold.seats);
        const std::int64_t now = wall_millis();
        for (int s : hold.seats) {
            const FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            if (!x.is_held || x.held_by != hold.user || x.held_until_ms <= now) return Rejected{"NOT_HELD"};
        }
        for (int s : hold.seats) {
            FlagSeat& x = seats_[static_cast<std::size_t>(s)];
            x.is_booked = true;
            x.is_held = false;
            x.payment_id = payment_id;
        }
        return Confirmed{payment_id};
    }
};

// ===== L6: deadlock-free, injected Clock, enum status + optional fields ========================

class OrderedSeatLocks final : public SeatHoldService {
    enum class Status { Free, Held, Booked };
    struct Seat {
        Status status = Status::Free;
        std::optional<std::string> holder;            // engaged iff Held or Booked -- by convention only
        std::optional<Clock::time_point> expires_at;  // meaningful iff Held        -- by convention only
        std::optional<std::string> payment_id;        // engaged iff Booked         -- by convention only
    };
    std::vector<Seat> seats_;
    std::unique_ptr<std::mutex[]> locks_;
    const Clock& clock_;
    std::atomic<std::uint64_t> ids_{0};
    int n_;
public:
    OrderedSeatLocks(int n, const Clock& clock)
        : seats_(static_cast<std::size_t>(n)), locks_(std::make_unique<std::mutex[]>(static_cast<std::size_t>(n))),
          clock_(clock), n_(n) {}
    std::optional<Hold> hold(const std::string& user, const std::vector<int>& req) override {
        LockAll guard(locks_.get(), lock_order(req, n_));
        const auto now = clock_.now();
        for (int s : guard.order()) {
            const Seat& x = seats_[static_cast<std::size_t>(s)];
            const bool free = x.status == Status::Free || (x.status == Status::Held && now >= *x.expires_at);
            if (!free) return std::nullopt;
        }
        for (int s : guard.order()) {
            Seat& x = seats_[static_cast<std::size_t>(s)];
            x.status = Status::Held;
            x.holder = user;
            x.expires_at = now + kTtl;
        }
        return Hold{++ids_, user, req};
    }
    ConfirmResult confirm(const Hold& hold, const std::string& payment_id) override {
        LockAll guard(locks_.get(), lock_order(hold.seats, n_));
        const auto now = clock_.now();
        for (int s : guard.order()) {
            const Seat& x = seats_[static_cast<std::size_t>(s)];
            // Identifies the hold by WHO holds the seat, not by WHICH hold: the ABA bug.
            if (x.status != Status::Held || *x.holder != hold.user || now >= *x.expires_at) return Rejected{"NOT_HELD"};
        }
        for (int s : guard.order()) {
            Seat& x = seats_[static_cast<std::size_t>(s)];
            x.status = Status::Booked;
            x.payment_id = payment_id;
        }
        return Confirmed{payment_id};
    }
};

// ===== L7: variant states (illegal states unrepresentable) + fencing token + idempotency =======

class FencedSeatHolds final : public SeatHoldService {
    struct Free {};
    struct Held { std::uint64_t token; std::string user; Clock::time_point expires_at; };
    struct Booked { std::uint64_t token; std::string user; std::string payment_id; };
    using SeatState = std::variant<Free, Held, Booked>;
    enum class Verdict { Ok, AlreadyMine, Sold, Superseded, Expired, NotHeld };

    std::vector<SeatState> seats_;  // seats_[i] guarded by locks_[i]
    std::unique_ptr<std::mutex[]> locks_;
    const Clock& clock_;
    std::atomic<std::uint64_t> fencing_{0};  // a newer hold always has a larger token
    int n_;

    static bool available(const SeatState& st, Clock::time_point now) {
        return std::visit(overloaded{  // a 4th alternative without a lambda is a compile error
            [](const Free&) { return true; },
            [&](const Held& h) { return now >= h.expires_at; },  // lazy expiry: expired == free
            [](const Booked&) { return false; },
        }, st);
    }
    static Verdict judge(const SeatState& st, const Hold& hold, Clock::time_point now) {
        return std::visit(overloaded{
            [&](const Booked& b) { return b.token == hold.token ? Verdict::AlreadyMine : Verdict::Sold; },
            [&](const Held& h) {
                if (h.token != hold.token) return Verdict::Superseded;
                return now >= h.expires_at ? Verdict::Expired : Verdict::Ok;
            },
            [](const Free&) { return Verdict::NotHeld; },
        }, st);
    }
    static const char* name(Verdict v) {
        switch (v) {
            case Verdict::Ok: return "OK";
            case Verdict::AlreadyMine: return "ALREADY_MINE";
            case Verdict::Sold: return "SOLD";
            case Verdict::Superseded: return "SUPERSEDED";
            case Verdict::Expired: return "EXPIRED";
            case Verdict::NotHeld: return "NOT_HELD";
        }
        return "?";
    }
public:
    FencedSeatHolds(int n, const Clock& clock)
        : seats_(static_cast<std::size_t>(n), Free{}), locks_(std::make_unique<std::mutex[]>(static_cast<std::size_t>(n))),
          clock_(clock), n_(n) {}
    std::optional<Hold> hold(const std::string& user, const std::vector<int>& req) override {
        LockAll guard(locks_.get(), lock_order(req, n_));
        const auto now = clock_.now();
        for (int s : guard.order())
            if (!available(seats_[static_cast<std::size_t>(s)], now)) return std::nullopt;
        const std::uint64_t token = ++fencing_;
        for (int s : guard.order()) seats_[static_cast<std::size_t>(s)] = Held{token, user, now + kTtl};
        return Hold{token, user, req};
    }
    ConfirmResult confirm(const Hold& hold, const std::string& payment_id) override {
        LockAll guard(locks_.get(), lock_order(hold.seats, n_));
        const auto now = clock_.now();
        std::size_t ok = 0, mine = 0;
        for (int s : guard.order()) {
            const Verdict v = judge(seats_[static_cast<std::size_t>(s)], hold, now);
            switch (v) {
                case Verdict::Ok: ++ok; break;
                case Verdict::AlreadyMine: ++mine; break;
                case Verdict::Sold:
                case Verdict::Superseded:
                case Verdict::Expired:
                case Verdict::NotHeld: return Rejected{name(v)};
            }
        }
        const auto first = static_cast<std::size_t>(guard.order().front());
        if (mine == guard.order().size()) return AlreadyConfirmed{std::get<Booked>(seats_[first]).payment_id};
        if (ok != guard.order().size()) throw std::logic_error("torn hold");  // cannot happen
        for (int s : guard.order()) seats_[static_cast<std::size_t>(s)] = Booked{hold.token, hold.user, payment_id};
        return Confirmed{payment_id};
    }
};

// ===== Test battery ============================================================================

constexpr int kSeats = 12, kThreads = 4, kAttempts = 3, kRounds = 20'000;

inline void cpu_relax() {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#else
    std::this_thread::yield();
#endif
}

std::uint64_t mix64(std::uint64_t z) {  // SplitMix64 finaliser: same stream as the Java listing
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

std::vector<int> request(int thread, int round, int attempt) {  // two distinct seats, random order
    const std::uint64_t x = mix64((static_cast<std::uint64_t>(thread) << 40) ^ (static_cast<std::uint64_t>(round) << 8) ^
                                  static_cast<std::uint64_t>(attempt));
    const int a = static_cast<int>(x % kSeats);
    const int b = (a + 1 + static_cast<int>((x >> 32) % (kSeats - 1))) % kSeats;
    return {a, b};
}

struct Variant {
    std::string name;
    std::function<std::unique_ptr<SeatHoldService>(const Clock&)> make;
    bool clock_injected;
};

struct Round {
    int no = 0;
    std::shared_ptr<const Clock> clock;   // declared before svc: destroyed after the service using it
    std::unique_ptr<SeatHoldService> svc;
    std::array<std::atomic<int>, kSeats> held{}, confirmed{};
};

struct RaceReport { int rounds_run, double_held, double_confirmed; std::string deadlock; };

bool g_leaked_threads = false;  // a deadlocked std::thread can never be joined

/** T1: spin-gated rounds. Every round is a fresh service; all workers start within ~100 ns. */
RaceReport race(const Variant& v) {
    auto clock = std::make_shared<ManualClock>();
    auto current = std::make_shared<std::atomic<Round*>>(new Round{});
    auto finished = std::make_shared<std::atomic<int>>(0);
    auto stop = std::make_shared<std::atomic<bool>>(false);
    std::vector<std::thread> workers;
    for (int t = 0; t < kThreads; ++t) {
        workers.emplace_back([=] {  // shared_ptr captures outlive race() if this thread deadlocks
            for (int r = 1; r <= kRounds; ++r) {
                Round* round;
                while ((round = current->load(std::memory_order_acquire))->no < r) {  // acquire: sees svc
                    if (stop->load(std::memory_order_relaxed)) return;
                    cpu_relax();
                }
                for (int a = 0; a < kAttempts; ++a) {
                    const auto seats = request(t, r, a);
                    auto h = round->svc->hold("u" + std::to_string(t), seats);
                    if (!h) continue;
                    for (int s : seats) round->held[static_cast<std::size_t>(s)].fetch_add(1);
                    const auto pay = "pay-" + std::to_string(t) + "-" + std::to_string(r) + "-" + std::to_string(a);
                    if (std::holds_alternative<Confirmed>(round->svc->confirm(*h, pay)))
                        for (int s : seats) round->confirmed[static_cast<std::size_t>(s)].fetch_add(1);
                }
                finished->fetch_add(1, std::memory_order_acq_rel);
            }
        });
    }
    int double_held = 0, double_confirmed = 0;
    Round* previous = current->load();
    for (int r = 1; r <= kRounds; ++r) {
        auto* round = new Round{};
        round->no = r;
        round->clock = clock;
        round->svc = v.make(*clock);
        current->store(round, std::memory_order_release);  // publish
        const auto deadline = std::chrono::steady_clock::now() + 2s;
        while (finished->load(std::memory_order_acquire) < r * kThreads) {
            if (std::chrono::steady_clock::now() > deadline) {
                stop->store(true);
                for (auto& w : workers) w.detach();  // blocked forever: leak the threads and the round
                g_leaked_threads = true;
                return {r - 1, double_held, double_confirmed,
                        "round " + std::to_string(r) + ": no progress for 2 s (std::mutex has no owner introspection)"};
            }
            cpu_relax();
        }
        delete previous;  // every worker has finished round r-1 (acquire above)
        previous = round;
        bool dh = false, dc = false;
        for (int s = 0; s < kSeats; ++s) {
            dh |= round->held[static_cast<std::size_t>(s)].load() > 1;
            dc |= round->confirmed[static_cast<std::size_t>(s)].load() > 1;
        }
        double_held += dh;
        double_confirmed += dc;
    }
    for (auto& w : workers) w.join();
    delete previous;
    return {kRounds, double_held, double_confirmed, "none"};
}

std::string ttl_boundary(const Variant& v) {  // T2: nanosecond-exact, no sleeping
    ManualClock clock;
    auto svc = v.make(clock);
    (void)svc->hold("alice", {1, 2}).value();
    clock.advance(kTtl - 1ns);
    const bool blocked_just_before = !svc->hold("bob", {2}).has_value();
    clock.advance(1ns);
    const bool free_at_expiry = svc->hold("bob", {2}).has_value();
    return std::string(blocked_just_before && free_at_expiry ? "PASS" : "FAIL") +
           "  blocked@TTL-1ns=" + (blocked_just_before ? "true" : "false") +
           " free@TTL=" + (free_at_expiry ? "true" : "false");
}

std::string stale_webhook(const Variant& v) {  // T3: expire -> same user re-holds -> old webhook
    ManualClock clock;
    auto svc = v.make(clock);
    const Hold h1 = svc->hold("alice", {7}).value();
    clock.advance(kTtl + 1s);
    const Hold h2 = svc->hold("alice", {7}).value();
    const auto late = svc->confirm(h1, "pay-1");
    const auto live = svc->confirm(h2, "pay-2");
    const auto dup = svc->confirm(h2, "pay-2");
    const bool pass = std::holds_alternative<Rejected>(late) && std::holds_alternative<Confirmed>(live) &&
                      std::holds_alternative<AlreadyConfirmed>(dup);
    return std::string(pass ? "PASS" : "FAIL") + "  late=" + describe(late) + " live=" + describe(live) +
           " retry=" + describe(dup);
}

int main() {
    const std::vector<Variant> variants = {
        {"L5a CheckThenActMap", [](const Clock&) { return std::make_unique<CheckThenActMap>(); }, false},
        {"L5b GlobalLock", [](const Clock&) { return std::make_unique<GlobalLock>(kSeats); }, false},
        {"L5c UnorderedSeatLocks", [](const Clock&) { return std::make_unique<UnorderedSeatLocks>(kSeats); }, false},
        {"L6  OrderedSeatLocks", [](const Clock& c) { return std::make_unique<OrderedSeatLocks>(kSeats, c); }, true},
        {"L7  FencedSeatHolds", [](const Clock& c) { return std::make_unique<FencedSeatHolds>(kSeats, c); }, true},
    };
    std::vector<std::string> broken;

    std::println("== T1 race: {} threads x {} attempts x {} rounds, {} seats, spin-gated ==", kThreads, kAttempts,
                 kRounds, kSeats);
    for (const auto& v : variants) {
        const auto r = race(v);
        std::println("{:<23} rounds={:>6}  double-held={:>5}  double-confirmed={:>5}  deadlock={}", v.name,
                     r.rounds_run, r.double_held, r.double_confirmed, r.deadlock);
        const bool guaranteed = !v.name.starts_with("L5a") && !v.name.starts_with("L5c");
        if (guaranteed && (r.double_held + r.double_confirmed > 0 || r.deadlock != "none")) broken.push_back(v.name + " T1");
    }
    std::println("== T2 TTL boundary: expired iff now >= expiresAt ==");
    for (const auto& v : variants) {
        const auto res = v.clock_injected ? ttl_boundary(v)
                                          : std::string("N/A   wall clock hard-wired: the test needs a 5-minute sleep");
        std::println("{:<23} {}", v.name, res);
        if (v.clock_injected && !res.starts_with("PASS")) broken.push_back(v.name + " T2");
    }
    std::println("== T3 stale webhook: expire -> same user re-holds -> old webhook arrives ==");
    for (const auto& v : variants) {
        const auto res = v.clock_injected ? stale_webhook(v) : std::string("N/A   wall clock hard-wired");
        std::println("{:<23} {}", v.name, res);
        if (v.name.starts_with("L7") && !res.starts_with("PASS")) broken.push_back(v.name + " T3");
        if (v.name.starts_with("L6") && !res.starts_with("FAIL")) broken.push_back("L6 T3 expected to expose the ABA bug");
    }
    std::println("{}", broken.empty() ? std::string("SELF-TEST OK: guarantees hold, L6 ABA bug reproduced")
                                      : "SELF-TEST FAILED " + std::to_string(broken.size()));
    std::fflush(stdout);
    const int code = broken.empty() ? 0 : 1;
    if (g_leaked_threads) std::quick_exit(code);  // never run destructors under blocked detached threads
    return code;
}
```

**Output, GCC 16.2 / libstdc++ (one measured run):**

```text
== T1 race: 4 threads x 3 attempts x 20000 rounds, 12 seats, spin-gated ==
L5a CheckThenActMap     rounds= 20000  double-held=10974  double-confirmed= 7453  deadlock=none
L5b GlobalLock          rounds= 20000  double-held=    0  double-confirmed=    0  deadlock=none
L5c UnorderedSeatLocks  rounds=    25  double-held=    0  double-confirmed=    0  deadlock=round 26: no progress for 2 s (std::mutex has no owner introspection)
L6  OrderedSeatLocks    rounds= 20000  double-held=    0  double-confirmed=    0  deadlock=none
L7  FencedSeatHolds     rounds= 20000  double-held=    0  double-confirmed=    0  deadlock=none
== T2 TTL boundary: expired iff now >= expiresAt ==
L5a CheckThenActMap     N/A   wall clock hard-wired: the test needs a 5-minute sleep
L5b GlobalLock          N/A   wall clock hard-wired: the test needs a 5-minute sleep
L5c UnorderedSeatLocks  N/A   wall clock hard-wired: the test needs a 5-minute sleep
L6  OrderedSeatLocks    PASS  blocked@TTL-1ns=true free@TTL=true
L7  FencedSeatHolds     PASS  blocked@TTL-1ns=true free@TTL=true
== T3 stale webhook: expire -> same user re-holds -> old webhook arrives ==
L5a CheckThenActMap     N/A   wall clock hard-wired
L5b GlobalLock          N/A   wall clock hard-wired
L5c UnorderedSeatLocks  N/A   wall clock hard-wired
L6  OrderedSeatLocks    FAIL  late=Confirmed[pay-1] live=Rejected[NOT_HELD] retry=Rejected[NOT_HELD]
L7  FencedSeatHolds     PASS  late=Rejected[SUPERSEDED] live=Confirmed[pay-2] retry=AlreadyConfirmed[pay-2]
SELF-TEST OK: guarantees hold, L6 ABA bug reproduced
```

**Output, Clang 21.1 / libc++ (one measured run):**

```text
== T1 race: 4 threads x 3 attempts x 20000 rounds, 12 seats, spin-gated ==
L5a CheckThenActMap     rounds= 20000  double-held=12858  double-confirmed= 9873  deadlock=none
L5b GlobalLock          rounds= 20000  double-held=    0  double-confirmed=    0  deadlock=none
L5c UnorderedSeatLocks  rounds=     2  double-held=    0  double-confirmed=    0  deadlock=round 3: no progress for 2 s (std::mutex has no owner introspection)
L6  OrderedSeatLocks    rounds= 20000  double-held=    0  double-confirmed=    0  deadlock=none
L7  FencedSeatHolds     rounds= 20000  double-held=    0  double-confirmed=    0  deadlock=none
== T2 TTL boundary: expired iff now >= expiresAt ==
L5a CheckThenActMap     N/A   wall clock hard-wired: the test needs a 5-minute sleep
L5b GlobalLock          N/A   wall clock hard-wired: the test needs a 5-minute sleep
L5c UnorderedSeatLocks  N/A   wall clock hard-wired: the test needs a 5-minute sleep
L6  OrderedSeatLocks    PASS  blocked@TTL-1ns=true free@TTL=true
L7  FencedSeatHolds     PASS  blocked@TTL-1ns=true free@TTL=true
== T3 stale webhook: expire -> same user re-holds -> old webhook arrives ==
L5a CheckThenActMap     N/A   wall clock hard-wired
L5b GlobalLock          N/A   wall clock hard-wired
L5c UnorderedSeatLocks  N/A   wall clock hard-wired
L6  OrderedSeatLocks    FAIL  late=Confirmed[pay-1] live=Rejected[NOT_HELD] retry=Rejected[NOT_HELD]
L7  FencedSeatHolds     PASS  late=Rejected[SUPERSEDED] live=Confirmed[pay-2] retry=AlreadyConfirmed[pay-2]
SELF-TEST OK: guarantees hold, L6 ABA bug reproduced
```

---

## 5. Reading the results

### 5.1 L5a: "every call is atomic" does not compose 🔥

In the Java run, **14,511 of 20,000 rounds (72.6%)** produced a seat held by two users at once, and **2,211 rounds (11.1%)** produced a seat *confirmed* twice: a real double booking. The C++ runs show the same disease at different rates (GCC: 10,974 / 7,453; Clang: 12,858 / 9,873).

The mechanism:

```text
T1: holds.get(3) == null ✓          T2: holds.get(3) == null ✓      ← both CHECK pass
T1: holds.put(3, T1) ;              T2: holds.put(3, T2)             ← both ACT; T2 overwrites
T1: confirm: holds.get(3).user == T1 ✓ (read before T2's put landed)
T2: confirm: holds.get(3).user == T2 ✓ → both write booked[3]     ← double booking
```

Every individual `ConcurrentHashMap` method is linearizable. **Linearizability is a property of single operations, and it doesn't extend to sequences of operations.** The fix is never "a more concurrent map". It is to make the whole compound action one atomic step: either a lock around the sequence, or a single atomic map operation (`compute`) that covers *all* seats, which is impossible here because the operation spans several keys.

### 5.2 L5b: correct, and the problems are elsewhere ⚡

The global lock passes T1 with zero violations. That is worth saying out loud in an interview: **a single lock is a correct baseline, and for a 60-minute round with one show and modest load it may be the right design.** Its defects are not races:

- **Every show in the system serializes on one monitor.** The critical section is short (~100 ns), so this only matters at real contention, and the honest L7 framing is "the lock boundary should be the *aggregate* (one show), and only a flash sale on one show justifies per-seat locks".
- **The clock is welded in.** T2 and T3 can't even be written without `Thread.sleep(300_000)`. That fails gate G4 (§3.2) on its own.
- **Booleans admit illegal states.** `isHeld && isBooked` is representable, and forgetting one assignment in `confirm` produces it silently.

### 5.3 L5c: the multi-seat deadlock trap 🔥

Per-seat locks taken in *request* order deadlocked in **round 4** of the Java run. `ThreadMXBean.findDeadlockedThreads()` names the cycle exactly: `w0→w2, w1→w0, w2→w1`, a **three-thread** cycle, not just the textbook A↔B pair. The C++ runs stalled in rounds 26 and 3. `std::mutex` has no owner introspection, so the C++ harness can only report "no progress for 2 s". That gap is a good reason C++ codebases add lock-order instrumentation in debug builds.

Two-seat requests in random order give a deadlock within a handful of rounds. In production that means within seconds of a popular show opening.

### 5.4 L6: the ABA bug at the business level ⚡

L6 passes T1 (zero violations, no deadlock) and T2 (the TTL boundary holds to the nanosecond, thanks to the injected `Clock`). Then T3 shows this:

```text
L6  late=Confirmed[pay-1]   live=Rejected[NOT_HELD]   retry=Rejected[NOT_HELD]
```

1. h1 (Alice, seat 7) expires.
2. Alice re-holds seat 7 (h2).
3. The webhook for **h1** arrives. L6 asks "is seat 7 held by Alice and unexpired?" The answer is yes, because of *h2*, so it confirms seat 7 against **pay-1**.
4. The webhook for h2 is then rejected, because the seat is already booked.

Alice paid twice, the booking is tied to the wrong payment intent (which may carry a different amount or currency), and support has to issue a manual refund.

This is **ABA**: the state went *held-by-Alice → expired → held-by-Alice*, and a check on "who" can't tell the two holds apart. It's the same structure as the lock-free ABA problem in §3 of [file 03](03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md), at the business layer.

### 5.5 L7: identity by token, outcomes as data

```text
L7  late=Rejected[SUPERSEDED]   live=Confirmed[pay-2]   retry=AlreadyConfirmed[pay-2]
```

Three small changes produce that line:

1. **The hold's identity is a fencing token**: a global, monotonically increasing `long` handed to the client and echoed back by the payment provider in the webhook metadata. Confirmation compares *tokens*, not users.
2. **The state is a sealed type whose variants carry exactly their data.** `Held(token, user, expiresAt)` and `Booked(token, user, paymentId)` make "booked without a payment id" or "held without an expiry" unrepresentable. Adding a fourth state (say `Released`) is a compile error in `available()` and `judge()` until it's handled.
3. **Outcomes are a closed set.** `Confirmed | AlreadyConfirmed | Rejected(reason)` makes the provider's retry an *idempotent success* rather than an error, and makes the reason code a ready-made metric label (D13).

---

## 6. Correctness argument for the L7 design

At L7 you should be able to state *why* the code is right in under two minutes. The argument for `FencedSeatHolds`:

**Deadlock freedom.**
- Every operation acquires its seat locks in strictly ascending seat order and holds no other lock while doing so.
- Suppose a cycle existed in the wait-for graph: T₁ holds s₁ and waits for s₂, T₂ holds s₂ and waits for s₃, …, Tₖ holds sₖ and waits for s₁.
- Ascending acquisition implies s₁ < s₂ < … < sₖ < s₁, which is a contradiction.
- De-duplication matters too: without it, a request `[3, 3]` would make a thread wait on a lock it already holds. With `ReentrantLock` that silently increments a hold count; with `std::mutex` it is undefined behaviour.

**Atomicity (all-or-nothing).**
- Both `hold` and `confirm` read and write their seats only while holding *all* of those seats' locks.
- Each operation **checks every seat before writing any seat**, so a failed check leaves no partial writes. That is why the code has a check loop and then a separate write loop.

**Linearizability.**
- Each operation's linearization point is its final write, performed while all of its locks are held.
- Two operations on overlapping seat sets are serialized by the shared lock. Operations on disjoint sets commute.

**No ABA on confirm.**
- Tokens are drawn from an `AtomicLong` that only increases, so a re-hold always carries a larger token than the hold it replaces.
- `judge` requires *equality* of the stored token with the presented token.
- A stale webhook therefore always sees `SUPERSEDED` (a newer hold), `SOLD` (booked under another token), `EXPIRED`, or `NOT_HELD`. It never sees `OK`.

**Lazy expiry is equivalent to eager expiry.**
- An expired `Held` is treated as `Free` by `available()` and as `EXPIRED` by `judge()`, which is exactly what a background sweeper would have produced.
- The sweeper becomes a memory optimization, not a correctness requirement. One fewer thread is one fewer failure mode.

**Publication.**
- The `seats[]` slots are plain fields guarded by `locks[i]`.
- An unlock happens-before every later lock of the same `ReentrantLock` (in C++, `std::mutex` unlock synchronizes-with the next lock), so a write made under the lock is visible to the next holder.
- Nothing reads a slot without its lock.

---

## 7. Curveballs: how each level responds

The full set of 25 curveballs with refactoring defences is in Folder 08. These eight are the ones this exhibit invites:

| # | Interviewer changes… | L5 response | L6 response | L7 response |
|---|---|---|---|---|
| C1 | "Add `release(hold)`" | Sets flags back to false | Checks the user before releasing | Releases only on token match (`Held h when h.token()==t`); a stale release is a no-op returning `SUPERSEDED`; one new arm in `judge` |
| C2 | "One cart can hold seats in **two shows**" | Nested `synchronized` on both shows | Locks shows in id order | The lock order becomes lexicographic `(showId, seatId)`, still one total order. Or the cart becomes a saga with per-show holds and compensation when the seat sets are large |
| C3 | "Flash sale: 200k users, one show" | "Use a faster lock" | Per-seat locks; measure contention | Most requests are for the best ~50 seats. Add admission control (queue/virtual waiting room) in front, reject fast on `SOLD`/`HELD` without blocking, and shard *inventory* not locks (Folder 05, P15) |
| C4 | "Webhooks can arrive **out of order** and **duplicated**" | Ignores duplicates by checking status | Idempotency key table | Already handled: token equality plus `AlreadyConfirmed`. Out-of-order arrival is ABA-safe by construction. Persist `(token → outcome)` for replay beyond process lifetime |
| C5 | "Now there are **three app servers**" | "Use Redis lock" | Redis `SET NX PX` per seat | The lock moves into the system of record: `UPDATE seat SET state='BOOKED', payment=? WHERE id=? AND state='HELD' AND token=? AND expires_at > now()`. A row count of 0 means `Rejected`. The token *is* the fencing token, and Redis locks without fencing are unsafe under GC pauses (Kleppmann) |
| C6 | "Extend a hold by 2 minutes once" | Adds `expiresAt += 2min` | Checks the user | A new state `Held(token, user, expiresAt, extended)` or a new token; extension is a transition with a guard, and the exhaustive switch shows every place that must decide |
| C7 | "VIP users can pre-empt a hold" | Overwrites the holder | Adds a priority field | Pre-emption is a transition `Held(t1) → Held(t2 > t1)`, and the old holder's confirm is then `SUPERSEDED` for free. The fencing design made the feature nearly free, and saying so is the point |
| C8 | "Audit every transition" | Logs inside each method | An `AuditService` call per method | Transitions are already pure functions `(state, cmd) → state`; emit `(old, new, token, reason)` events from the one place they happen (Folder 02, file 03: event bus) |

---
## 8. The 60/90-minute budget by level

Folder 08 has the full execution blueprint and code skeletons. These are the proportions that separate levels:

| Phase | 60-min round | 90-min round | L5 tendency | L7 practice |
|---|---|---|---|---|
| Clarify + state assumptions | 5 | 8 | Lists features | Names the 1–2 deciding requirements (§4.1) and the contention assumption |
| Model + API skeleton (types first) | 10 | 15 | Starts with a `Manager` class | Starts with the state ADT and the result types: the types *are* the spec |
| Core path, single-threaded, with a test | 15 | 20 | Builds many features shallowly | Builds the one critical path deeply, with a boundary test using the fake clock |
| Concurrency: atomicity unit, lock order, stress test | 15 | 20 | Adds `synchronized` at the end | Designs it in at the skeleton stage, then proves it with the harness |
| Curveball / extension | 10 | 15 | Rewrites | Locates the invariant that moved; adds one variant/arm; re-runs tests |
| Wrap-up: trade-offs, evolution path | 5 | 12 | Stops when time ends | Two sentences on scale-out (where the lock moves) and on operability |

---

## 9. Red-flag catalogue (Java and C++)

| # | Red flag | Why it caps the level | The replacement |
|---|---|---|---|
| R1 | `if (!map.containsKey(k)) map.put(k, v)` on a concurrent map | Check-then-act: §5.1 measured double bookings | `putIfAbsent`/`computeIfAbsent`, or a lock around the compound action |
| R2 | Locks acquired in request/argument order | Deadlock (§5.3) | Sort plus de-duplicate keys; one global order; or `std::scoped_lock(a, b)` |
| R3 | `boolean isPaid, isCancelled, isRefunded` | Illegal states representable | `sealed` ADT / `std::variant` with per-state data (file 02) |
| R4 | `double` for money | `0.1 + 0.2 != 0.3`; cents vanish | `BigDecimal` with currency scale / integer minor units (file 02) |
| R5 | `System.currentTimeMillis()` inside TTL logic | Untestable without sleep; breaks on NTP steps | Inject `Clock` for timestamps and a monotonic `Ticker` for durations (file 03) |
| R6 | `Thread.sleep(…)` in a test | Slow, flaky, proves nothing about boundaries | Fake clock plus virtual-time scheduler |
| R7 | Identity of a hold/request = "the user" | ABA on retries and re-holds (§5.4) | Fencing token / idempotency key |
| R8 | `synchronized` around a remote call | Holds the lock for network latency; convoys | Compute the decision under the lock; do the I/O outside; re-validate with a version |
| R9 | `catch (InterruptedException e) {}` | Destroys cancellation; threads can't be stopped | Restore the flag (`Thread.currentThread().interrupt()`) or propagate |
| R10 | `volatile int count; count++` | `++` is read-modify-write; `volatile` gives visibility, not atomicity | `AtomicInteger`/`LongAdder`; C++ `fetch_add` |
| R11 | Double-checked locking without `volatile` | Unsafe publication of a partially constructed object | Holder idiom / `volatile`; C++ function-local static or `std::call_once` |
| R12 | Slow work inside `ConcurrentHashMap.compute` | The bin lock is held: blocks bin-mates; recursion throws `IllegalStateException: Recursive update` | Compute the value outside; insert a future (`computeIfAbsent(k, k -> new CompletableFuture<>())`) |
| R13 | A fair lock "for fairness" without measurement | Hand-off on every release; file 03 measured ~4 µs vs ~25 ns per acquisition | Barging locks plus bounded waiting at the admission layer |
| R14 | Inheriting from `HashSet`/`std::unordered_set` to "add counting" | Fragile base class (Java double-counts, C++ silently bypasses) | Composition + forwarding (file 02) |
| R15 | Public mutable collections in a record/DTO | Callers mutate your invariants | `List.copyOf` in the compact constructor |
| R16 | `std::mutex` locked twice by one thread | Undefined behaviour | De-duplicate; `std::recursive_mutex` only with justification |
| R17 | A data race "because it's only a flag" (C++) | Undefined behaviour; the compiler may delete the loop | `std::atomic<bool>` with an explicit memory order |
| R18 | Assuming `long` is 64-bit (C++) | 32-bit on Windows (LLP64): file 03's GCC build caught `200000*200001` overflowing | `std::int64_t` and friends |
| R19 | Detached `std::thread` capturing stack references | Use-after-return | `std::jthread` + `stop_token`; or `shared_ptr` captures plus a documented leak policy |
| R20 | `notify()` instead of `notifyAll()` with multiple condition predicates | Lost wake-ups | Separate `Condition`s per predicate (`notFull`/`notEmpty`) |
| R21 | `while(!done)` on a plain field (Java) | The JIT may hoist the read: infinite loop | `volatile`/atomic; better, a latch |
| R22 | A singleton with mutable static state | Hidden global coupling; tests interfere | Constructor injection; state per instance |
| R23 | One interface per class "for mocking" | Speculative generality; hides the real seams | Interfaces at the axes of variation only; fakes for time and I/O |
| R24 | "I'll add tests later" | No evidence for the concurrency claim | The harness first: invariants, spin gate, timeout |
| R25 | Rewriting the design on each curveball | Signals the first design had no axes | Ask "which invariant moved?" and change only that |

---

## 10. What each level sounds like

| Moment | L5 says | L7 says |
|---|---|---|
| Opening | "So we need Seat, Show, User, Booking classes." | "Two requirements decide this: the hold is all-or-nothing across seats, and confirmation is an async webhook that can be late or duplicated. So I need a multi-seat atomicity unit and a hold identity that survives expiry." |
| Concurrency | "I'll make the methods synchronized." | "The atomicity unit is the set of seats in one request. I'll take per-seat locks in ascending id order, so the wait-for graph can't have a cycle. A global lock is correct too; it only loses when one show is hot." |
| State | "Status is an enum: AVAILABLE, HELD, BOOKED." | "State is a sealed interface: `Free`, `Held(token, user, expiresAt)`, `Booked(token, user, paymentId)`. A booked seat without a payment id can't be constructed, and adding a state breaks the build where it must be handled." |
| Time | "We'll check `System.currentTimeMillis()`." | "Expiry uses an injected clock, so I can test `TTL − 1 ns` and `TTL` without sleeping. In production the TTL should run on a monotonic source; wall clocks step." |
| Curveball (late webhook) | "We check the hold is still valid." | "Validity isn't enough: same user, new hold, old webhook is ABA. The webhook must present the token; equality of tokens identifies the hold. The provider's retry returns `AlreadyConfirmed`, idempotently." |
| Scale-out | "We'll use a distributed lock." | "Across replicas the lock moves into the system of record as a conditional update on `(state, token)`. A lease lock without a fencing token is unsafe under pauses." |

---

## 11. Self-assessment scorecard

Copy this into your practice notes after each mock. Score honestly, and record what you *would* have needed to say for a 4.

```text
Problem: ______________________   Format: LLD / machine coding / concurrency   Minutes: ___
Gates:  G1 runs [ ]   G2 race-free core [ ]   G3 no reachable illegal state [ ]   G4 honest time [ ]

| Dim | Score 1-4 | Evidence (what I did) | What a 4 would have done |
|-----|-----------|------------------------|--------------------------|
| D1 Requirements      |   |   |   |
| D2 Modelling         |   |   |   |
| D3 API/contract      |   |   |   |
| D4 State/lifecycle   |   |   |   |
| D5 Concurrency       |   |   |   |
| D6 Contention        |   |   |   |
| D7 Extensibility     |   |   |   |
| D8 Time/determinism  |   |   |   |
| D9 Testing           |   |   |   |
| D10 Failure semantics|   |   |   |
| D11 Code quality     |   |   |   |
| D12 Language/runtime |   |   |   |
| D13 Operability      |   |   |   |
| D14 Communication    |   |   |   |
Red flags hit (R#): ____________     Curveball and how I adapted: ______________________
```

---

## 12. Bar-raiser chains

Each chain has four parts: the prompt, a typical L5 answer, why that answer fails under production conditions, and the L7 defence.

<details>
<summary><b>Q1 🔥 "Your service uses ConcurrentHashMap. Is it thread-safe?"</b></summary>

**L5:** "Yes, ConcurrentHashMap is thread-safe, so every operation is safe."

**Why it fails:** thread-safety of a component is a property of its *operations' composition*, not of its fields. §5.1 measured double bookings in 72.6% of rounds using only CHM calls. Each call is linearizable; the check-then-act sequence isn't.

**L7 defence:** "The map's single-key operations are atomic. My booking spans several keys, so its atomicity must come from something that covers all of them: one lock over the sequence, or per-key locks in a global order. If the operation were single-key, I'd use `compute`/`merge` and keep the remapping function pure and fast, because CHM holds the bin lock while it runs."
</details>

<details>
<summary><b>Q2 ⚡ "Why not just one global lock?"</b></summary>

**L5:** "Because it's slow." (no model)

**Why it fails:** with a ~100 ns critical section, a single lock sustains millions of operations per second. "Slow" needs a contention model. Reflexive striping adds deadlock risk and code for no measured gain.

**L7 defence:** "A global lock is correct and is my baseline. It stops being right when arrival rate × critical-section length approaches 1 on the hot aggregate, for example one show in a flash sale, or when anything slow runs inside it. The natural first refinement is the aggregate boundary (lock per show). Per-seat locks are justified only for a hot single show, and then the hot spot is usually demand for the best seats, which needs admission control, not finer locks."
</details>

<details>
<summary><b>Q3 ⚡ "Your L6 version checks user and expiry on confirm. What's wrong?"</b></summary>

**L5:** "Nothing; it checks the hold is valid."

**Why it fails:** T3 in §4. Expire → same user re-holds → stale webhook. The check identifies the hold by *who* rather than *which*, and confirms the new hold with the old payment.

**L7 defence:** "It's ABA. The state returned to an equal-looking value. The fix is identity, not more checks: a monotonic token per hold, echoed back by the provider, compared by equality. Monotonicity guarantees a re-hold never reuses an old token, and the same token makes the provider's retries idempotent."
</details>

<details>
<summary><b>Q4 🧊 "Prove your lock order can't deadlock. What if a request's seats aren't known up front?"</b></summary>

**L5:** "We sort them, so it's fine."

**Why it fails:** sorting proves nothing if some path acquires a lock *outside* the order, or must discover the next resource while holding the current one (tree traversal, graph walk).

**L7 defence:** "A cycle in the wait-for graph would require s₁ < s₂ < … < s₁. When resources are discovered incrementally, I either (a) use lock-coupling in a fixed direction (parent before child, as in Folder 06's file-system problem), (b) acquire optimistically and validate, retrying on conflict, or (c) take `tryLock` with a timeout and back off with jitter. Option (c) trades deadlock for possible livelock, so it needs randomized backoff and a retry bound."
</details>

<details>
<summary><b>Q5 ⚡ "How do you test the 5-minute expiry?"</b></summary>

**L5:** "Set the TTL to 1 second in the test and sleep for 1.1 seconds."

**Why it fails:** slow, flaky under load, never tests the boundary (`TTL − 1 ns` vs `TTL`), and tests a different configuration than production.

**L7 defence:** "Time is a dependency: `Clock` injected, with a `MutableClock` in tests. T2 asserts blocked at `TTL − 1 ns` and free at `TTL`, which pins the `>=` vs `>` decision. For durations in production I'd use a monotonic ticker, since wall clocks step under NTP. File 03 shows a wall-clock TTL surviving an hour-long clock step."
</details>

<details>
<summary><b>Q6 🔥 "Three app servers now. What changes?"</b></summary>

**L5:** "Use a Redis distributed lock per seat."

**Why it fails:** a lease-based lock without fencing allows two holders when the first pauses (GC, VM migration) past its lease and then writes. Process-local locks no longer mean anything.

**L7 defence:** "The invariant must live in the system of record: a conditional update on `(seat, state, token)` whose row count decides the outcome, inside one transaction for the seat set. The token is the fencing token the storage layer checks. If I add Redis for speed, it's an optimization in front; the database predicate remains the authority."
</details>

---

## 13. Invariants checklist for any submission

- [ ] Every compound action (check + act, read + write, multi-key update) has exactly one named atomicity mechanism.
- [ ] Every multi-lock path acquires locks in one documented total order, and that order is de-duplicated.
- [ ] No lock is held across I/O, a remote call, a user callback, or a `compute` that can recurse.
- [ ] State is a closed set of types or enum constants, and the transition function is exhaustive with no `default`.
- [ ] Every externally retried operation has an identity (token/idempotency key) compared by equality.
- [ ] Money is never `double`; rounding mode and remainder distribution are explicit.
- [ ] Time comes from an injected source: `Clock` for timestamps, a monotonic ticker for durations; tests never sleep.
- [ ] Interrupts are restored or propagated; C++ threads are `jthread`s with a `stop_token`.
- [ ] The stress test asserts invariants (no double booking, conserved sums), not exact counts, and has a timeout plus deadlock diagnosis.
- [ ] C++: no data races (every shared mutable is atomic or guarded), no recursive `std::mutex`, fixed-width integers for arithmetic that can exceed 2³¹.

---

## 14. References

- Brian Goetz et al., *Java Concurrency in Practice*, Addison-Wesley, 2006: ch. 10 (lock-ordering deadlocks), ch. 12 (testing concurrent programs).
- Joshua Bloch, *Effective Java*, 3rd ed., 2018: Items 17 (minimize mutability), 18 (composition over inheritance), 78–84 (concurrency).
- Martin Kleppmann, "How to do distributed locking" (fencing tokens), 2016. <https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html>
- Maurice Herlihy and Jeannette Wing, "Linearizability: A Correctness Condition for Concurrent Objects", *TOPLAS* 1990. <https://doi.org/10.1145/78969.78972>
- Java SE `ThreadMXBean.findDeadlockedThreads()`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.management/java/lang/management/ThreadMXBean.html>
- cppreference, `std::scoped_lock` (deadlock-avoiding multi-lock). <https://en.cppreference.com/w/cpp/thread/scoped_lock>
- In this KB: [02 · SOLID, composition and data-oriented Java](02-solid-composition-and-data-oriented-java21-sealed-records.md) for the modelling techniques behind L7's state type, and [03 · Concurrency primitives](03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) for the memory-model and lock mechanics behind §6. The full BookMyShow problem (shows, pricing, payment flow, distributed variant) is P6 in Folder 04.
