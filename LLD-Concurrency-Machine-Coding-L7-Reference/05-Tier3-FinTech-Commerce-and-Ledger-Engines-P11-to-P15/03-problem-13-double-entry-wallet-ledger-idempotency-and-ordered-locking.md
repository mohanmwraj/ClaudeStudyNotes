# P13 · Double-Entry Wallet Ledger: Balanced Entries, Ordered Locking, and an Idempotency State Machine That Survives Crashes

> **Folder 05 · Problem 13 of 20.** Money questions have three layers, each with its own atomicity unit:
>
> | Layer | Atomicity unit |
> |---|---|
> | An **entry** must balance | the type |
> | A **transfer** must be atomic across accounts without deadlocking | ordered locks |
> | A **retried request** must move money exactly once, even when the first attempt crashed halfway or wakes up later as a zombie | a state machine plus a uniqueness constraint |
>
> All three are measured here.
>
> **Listing pair P13:** `WalletLedger.java` / `wallet_ledger.cpp`. Sections 1 and 5 are deterministic and byte-identical in Java and GCC. Sections 2–4 show one measured run.

---

## 1. Problem and scope

**Functional:**
- Customer wallets plus system accounts (`bank` for external money, `fees`).
- Transfers, and transfers with a fee (3 legs).
- Balance queries.
- A **payments API** that clients retry with an `Idempotency-Key`.

**Non-functional:**
- No double spend.
- No overdraft.
- No deadlock.
- Books always balance.
- A crashed request must be recoverable without guessing.

**Out of scope:** multi-currency entries (one currency per entry, FX as two entries via a conversion account), holds/authorizations (see [P6](../04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/01-problem-06-movie-ticket-booking-bookmyshow-seat-lock-and-deadlock-free.md)) and persistence (§7 maps every in-memory mechanism to its database equivalent).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Entry | `record Entry(txId, legs)`: the compact constructor rejects <2 legs, zero legs, duplicate accounts, Σ ≠ 0 | `class Entry` with a private constructor; `Entry::make` returns `std::expected<Entry, std::string>` |
| Result | `sealed Result permits Posted, Duplicate, Rejected(reason, retryable)` | `std::variant<Posted, Duplicate, Rejected>` |
| Account | `ReentrantLock` + `balance` (guarded) + `mayGoNegative` | `std::mutex` (warmed in the constructor) + `balance` |
| Journal | `ConcurrentHashMap<txId, Entry>`; **`putIfAbsent` is the uniqueness constraint** | `StripedMap<Entry>`, 64 mutex shards (C++'s CHM) |
| Idempotency | `sealed Idem permits InProgress(fp, attempt, leaseUntil), Completed(fp, entry), Failed(fp, reason, retryable)` | `std::variant` of the same, `operator==` defaulted for compare-and-replace |
| Time | injected `Clock` (`TestClock` moved by hand) | `Clock` interface, `TestClock` |

**Invariants:**
- **I1:** every entry balances. It cannot be constructed otherwise.
- **I2:** every account's balance = the sum of its legs in the journal (`journalMatches()`), and Σ over **all** accounts = 0. The bank's negative balance is the money issued into the system.
- **I3:** no customer account goes below zero.
- **I4:** at most one entry per tx id, ever, including from a zombie.
- **I5:** a given idempotency key moves money at most once and always returns the same answer. A different request body under the same key is rejected.

## 3. Concurrency and contention analysis

### 3.1 Deadlock: lock order is a global property

A transfer locks two accounts (three with a fee). Locking `from` then `to` deadlocks as soon as alice→bob and bob→alice run at once.

**Measured: 2 threads × 2,000 opposite transfers**, with ~1 µs of work while holding each lock (a limits lookup):

| Lock order | Java | GCC | Clang |
|---|---|---|---|
| `lock(from)` then `lock(to)` | **4,162** waits broken by a bounded try-lock | **4,219** | **4,060** |
| Sorted by account id | 0 | 0 | 0 |

Without the 1 µs window, the same naive code broke **0 to 254** waits depending on the run. **A latent deadlock passes tests.** Ordering is the guarantee; a timeout is only a smoke detector, and here it degrades into livelock-style retries.

- **Java:** sort the accounts by id, then `lock()` in that order. A three-leg fee entry just sorts three accounts.
- **C++ alternative:** `std::scoped_lock(m1, m2, m3)` uses `std::lock`'s deadlock-*avoidance* algorithm (lock one, try the rest, back off and retry). It needs no global order, but it can spin under contention. Sorted acquisition is deterministic and is what you'd also do in SQL (`UPDATE … ORDER BY id`).

### 3.2 Overdraft: check-then-act on a balance

**8 threads × 20 debits of 10 cents from 10.00** (exactly 100 can succeed), 300 rounds:
- An atomic `if (balance >= 10) balance -= 10` ended **below zero in 300 of 300 rounds**, lowest −70 cents: seven debits that should have failed.
- Check + debit under the account lock was exact in all 300.

The balance check and the debit are one atomicity unit. For a single account a CAS loop works too (`updateAndGet` with the check inside), but a transfer spans accounts, so it's locks.

### 3.3 Retries: an idempotency key needs a state machine and a uniqueness constraint

**8 threads each send the same 2,000 requests** in shuffled order, concurrently:

| Design | Executions | Ledger entries | Money moved vs requested (100,365 cents) |
|---|---|---|---|
| `if (!done(key)) { execute; remember }` with a fresh tx id per attempt | **2,014 / 2,015 / 2,020** | same | **+652 / +950 / +1,326 cents** (Java / GCC / Clang) |
| CAS state machine, tx id = key | **2,000** | 2,000 | exact; 14,000 replays, 7–263 "in flight" replies |

**Transitions:**
- **Claim:** `putIfAbsent(key, InProgress(fingerprint, attempt, now + lease))`.
- **Execute** outside the map. Never move money inside `ConcurrentHashMap.compute()`: it holds a bin lock, and [01.3](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) measured 200 ms vs 0.4 ms for neighbours in the same bin.
- **Finish:** `replace(key, mine, Completed|Failed)`. This succeeds only if we still own the key.
- **On a retry:**
  - `Completed` → replay the result;
  - `Failed` → replay it if non-retryable, or re-claim if retryable;
  - `InProgress` within the lease → **409, retry later**, never "execute again just in case";
  - a different fingerprint → 422 Mismatch.
- **Lease expired → takeover.** The new owner bumps `attempt` and **checks the journal first**. The dead owner may have committed before dying (section 5: `k1` is found in the ledger, not re-executed).
- **Zombies.** The original owner of `k2` wakes up after the takeover and tries to commit. The journal's `putIfAbsent(txId)` returns **Duplicate**. The idempotency table is an optimisation for answering retries; **the ledger's uniqueness constraint on tx id is the guarantee.** It is the in-memory version of a `UNIQUE` index, and it is what a fencing token is for.
- **Stored failures are replayed:** retrying `k3` after a top-up still fails. That's by design: the client sends a new key for a new attempt.

### 3.4 Bugs this listing caught in its own first draft

- **Java:** `a.getValue() != replayed.getOrDefault(...)` compared two **boxed `Long`s by identity**. Values outside −128…127 aren't cached, so the journal check said "mismatch" for correct books. The fix unboxes into `long`.
- **C++:** `(sys_days(…) + 12h).time_since_epoch().count()` is in **hours**. Read back as seconds, the test clock said 1970-01-06. `.count()` strips units; `duration_cast` first.

Both were caught by invariant checks, which is the point of writing them.

## 4. Java 21 implementation

```java
// WalletLedger.java - P13: double-entry ledger, ordered account locking, idempotency-key state machine with leases and fencing
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;

public final class WalletLedger {

    record Leg(String account, long cents) {
        @Override
        public String toString() {
            return account + " " + (cents > 0 ? "+" : "") + cents;
        }
    }

    /** Immutable and balanced: an entry whose legs do not sum to zero cannot be constructed. */
    record Entry(String txId, List<Leg> legs) {
        Entry {
            legs = List.copyOf(legs);
            if (legs.size() < 2) throw new IllegalArgumentException("an entry needs at least two legs");
            long sum = 0;
            Set<String> seen = new HashSet<>();
            for (Leg l : legs) {
                if (l.cents() == 0) throw new IllegalArgumentException("zero-amount leg");
                if (!seen.add(l.account())) throw new IllegalArgumentException("account " + l.account() + " appears twice");
                sum = Math.addExact(sum, l.cents());
            }
            if (sum != 0) throw new IllegalArgumentException("legs sum to " + sum + ", not 0");
        }
    }

    sealed interface Result permits Posted, Duplicate, Rejected {}
    record Posted(Entry entry) implements Result {}
    record Duplicate(Entry original) implements Result {}
    record Rejected(String reason, boolean retryable) implements Result {}

    static final class Account {
        final String id;
        final boolean mayGoNegative;                                    // external/settlement accounts only
        final ReentrantLock lock = new ReentrantLock();
        long balance;                                                   // guarded by lock

        Account(String id, boolean mayGoNegative) {
            this.id = id;
            this.mayGoNegative = mayGoNegative;
        }
    }

    enum LockOrder { REQUEST_ORDER, SORTED_BY_ID }

    static final class Ledger {
        final Map<String, Account> accounts = new HashMap<>();          // fixed after construction
        final ConcurrentHashMap<String, Entry> byTx = new ConcurrentHashMap<>();   // the uniqueness constraint on tx ids
        final LockOrder order;
        final LongAdder lockTimeouts = new LongAdder();
        int holdSpin;                                                   // work done while holding a lock (section 2 widens the window)

        Ledger(LockOrder order, List<String> customers) {
            this.order = order;
            accounts.put("bank", new Account("bank", true));
            accounts.put("fees", new Account("fees", false));
            for (String c : customers) accounts.put(c, new Account(c, false));
        }

        Result post(String txId, List<Leg> legs) {
            Entry e;
            try {
                e = new Entry(txId, legs);
            } catch (IllegalArgumentException ex) {
                return new Rejected(ex.getMessage(), false);
            }
            List<Account> involved = new ArrayList<>();
            for (Leg l : e.legs()) {
                Account a = accounts.get(l.account());
                if (a == null) return new Rejected("unknown account " + l.account(), false);
                involved.add(a);
            }
            if (order == LockOrder.SORTED_BY_ID) involved.sort(Comparator.comparing(a -> a.id));   // one global order: no cycle
            List<Account> held = new ArrayList<>();
            try {
                for (Account a : involved) {
                    if (order == LockOrder.SORTED_BY_ID) a.lock.lock();
                    else if (!trySpin(a.lock)) {                        // request order deadlocks; the bounded try is what rescues it
                        lockTimeouts.increment();
                        return new Rejected("lock timeout", true);
                    }
                    held.add(a);
                    spin(holdSpin);                                     // e.g. load this account's limits before taking the next lock
                }
                for (Leg l : e.legs()) {
                    Account a = accounts.get(l.account());
                    if (!a.mayGoNegative && a.balance + l.cents() < 0) return new Rejected("insufficient funds in " + a.id, false);
                }
                Entry prior = byTx.putIfAbsent(txId, e);               // at most one commit per tx id, ever (even from a zombie)
                if (prior != null) return new Duplicate(prior);
                for (Leg l : e.legs()) accounts.get(l.account()).balance += l.cents();
                return new Posted(e);
            } finally {
                for (int i = held.size() - 1; i >= 0; i--) held.get(i).lock.unlock();
            }
        }

        static boolean trySpin(ReentrantLock l) {
            for (int i = 0; i < 20_000; i++) {
                if (l.tryLock()) return true;
                Thread.onSpinWait();
            }
            return false;
        }

        Result transfer(String txId, String from, String to, long cents) {
            return post(txId, List.of(new Leg(from, -cents), new Leg(to, cents)));
        }

        /** Locks every account in id order: a consistent total that no in-flight transfer can tear. */
        Map<String, Long> snapshot() {
            List<Account> all = new ArrayList<>(accounts.values());
            all.sort(Comparator.comparing(a -> a.id));
            all.forEach(a -> a.lock.lock());
            try {
                Map<String, Long> out = new HashMap<>();
                for (Account a : all) out.put(a.id, a.balance);
                return out;
            } finally {
                all.forEach(a -> a.lock.unlock());
            }
        }

        /** Balances are a cache: replaying the journal from zero must reproduce them exactly. */
        boolean journalMatches() {
            Map<String, Long> replayed = new HashMap<>();
            for (Entry e : byTx.values())
                for (Leg l : e.legs()) replayed.merge(l.account(), l.cents(), Long::sum);
            Map<String, Long> snap = snapshot();
            for (var a : snap.entrySet()) {
                long have = a.getValue(), want = replayed.getOrDefault(a.getKey(), 0L);   // unbox: Long != Long compares identity
                if (have != want) return false;
            }
            return snap.values().stream().mapToLong(Long::longValue).sum() == 0;   // double entry: the books always balance
        }
    }

    // ---- idempotency keys: IN_PROGRESS -> COMPLETED | FAILED, with a lease so a dead owner can be taken over

    sealed interface Idem permits InProgress, Completed, Failed {}
    record InProgress(String fingerprint, long attempt, Instant leaseUntil) implements Idem {}
    record Completed(String fingerprint, Entry entry) implements Idem {}
    record Failed(String fingerprint, String reason, boolean retryable) implements Idem {}

    sealed interface Reply permits Ok, InFlight, Mismatch, Failure {}
    record Ok(Entry entry, boolean replayed) implements Reply {}
    record InFlight(Instant retryAfter) implements Reply {}
    record Mismatch(String why) implements Reply {}
    record Failure(String reason, boolean replayed) implements Reply {}

    record Transfer(String from, String to, long cents) {
        List<Leg> legs() {
            return List.of(new Leg(from, -cents), new Leg(to, cents));
        }

        String fingerprint() {                                          // canonical request: same key + different body = misuse
            return from + ">" + to + ":" + cents;
        }
    }

    static String fingerprint(Idem s) {
        return switch (s) {
            case InProgress p -> p.fingerprint();
            case Completed c -> c.fingerprint();
            case Failed f -> f.fingerprint();
        };
    }

    static final class Payments {
        final Ledger ledger;
        final Clock clock;
        final Duration lease;
        final ConcurrentHashMap<String, Idem> keys = new ConcurrentHashMap<>();
        final LongAdder executions = new LongAdder();
        final AtomicLong attempts = new AtomicLong();

        Payments(Ledger ledger, Clock clock, Duration lease) {
            this.ledger = ledger;
            this.clock = clock;
            this.lease = lease;
        }

        /** Every transition is one CAS on the key's state; the money moves outside the map (never inside compute()). */
        Reply handle(String key, Transfer t) {
            String fp = t.fingerprint();
            for (;;) {
                Instant now = clock.instant();
                Idem cur = keys.get(key);
                if (cur == null) {
                    InProgress mine = new InProgress(fp, 1, now.plus(lease));
                    if (keys.putIfAbsent(key, mine) == null) return execute(key, t, mine);
                    continue;                                          // lost the race: re-read
                }
                if (!fingerprint(cur).equals(fp)) return new Mismatch("key " + key + " was used for a different request");
                switch (cur) {
                    case Completed c -> {
                        return new Ok(c.entry(), true);
                    }
                    case Failed f when !f.retryable() -> {
                        return new Failure(f.reason(), true);
                    }
                    case Failed f -> {
                        InProgress mine = new InProgress(fp, 1, now.plus(lease));
                        if (keys.replace(key, f, mine)) return execute(key, t, mine);
                    }
                    case InProgress p when now.isBefore(p.leaseUntil()) -> {
                        return new InFlight(p.leaseUntil());
                    }
                    case InProgress p -> {                              // lease expired: the owner is presumed dead...
                        InProgress mine = new InProgress(fp, p.attempt() + 1, now.plus(lease));
                        if (keys.replace(key, p, mine)) {
                            Entry committed = ledger.byTx.get(key);    // ...but it may have committed before dying
                            if (committed == null) return execute(key, t, mine);
                            keys.replace(key, mine, new Completed(fp, committed));
                            return new Ok(committed, true);
                        }
                    }
                }
            }
        }

        Reply execute(String key, Transfer t, InProgress mine) {
            executions.increment();
            Result r = ledger.post(key, t.legs());                     // tx id = idempotency key: the ledger is the last line of defence
            Idem fin = switch (r) {
                case Posted p -> new Completed(mine.fingerprint(), p.entry());
                case Duplicate d -> new Completed(mine.fingerprint(), d.original());
                case Rejected x -> new Failed(mine.fingerprint(), x.reason(), x.retryable());
            };
            keys.replace(key, mine, fin);                              // only if we still own the key: a takeover fences us out
            return switch (fin) {
                case Completed c -> new Ok(c.entry(), r instanceof Duplicate);
                case Failed f -> new Failure(f.reason(), false);
                case InProgress p -> throw new AssertionError(p);
            };
        }

        /** The common bug: check, execute, then remember; and a fresh ledger id per attempt, so the ledger can't help. */
        Reply handleNaive(String key, Transfer t) {
            if (keys.get(key) instanceof Completed c) return new Ok(c.entry(), true);
            executions.increment();
            Result r = ledger.post(key + "#" + attempts.incrementAndGet(), t.legs());
            if (r instanceof Posted p) {
                keys.put(key, new Completed(t.fingerprint(), p.entry()));
                return new Ok(p.entry(), false);
            }
            return new Failure(r.toString(), false);
        }

        /** Test hook: claim the key, optionally commit, then die before recording the outcome. */
        void crash(String key, Transfer t, boolean afterCommit) {
            keys.putIfAbsent(key, new InProgress(t.fingerprint(), 1, clock.instant().plus(lease)));
            if (afterCommit) ledger.post(key, t.legs());
        }
    }

    /** A Clock the test moves by hand: lease expiry is tested in microseconds, without sleeping. */
    static final class TestClock extends Clock {
        volatile Instant now = Instant.parse("2026-10-27T12:00:00Z");

        void advance(Duration d) {
            now = now.plus(d);
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

    // ---- harness

    static long mix64(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    static final class Rng {
        private long s;

        Rng(long seed) {
            s = seed;
        }

        int below(int n) {
            return (int) Long.remainderUnsigned(mix64(s++), n);
        }
    }

    interface Body {
        void run(int thread) throws Exception;
    }

    static void parallel(int threads, Body body) throws Exception {
        CyclicBarrier start = new CyclicBarrier(threads + 1), end = new CyclicBarrier(threads + 1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        for (int t = 0; t < threads; t++) {
            final int id = t;
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    body.run(id);
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    try {
                        end.await();
                    } catch (Exception e) {
                        failure.compareAndSet(null, e);
                    }
                }
            });
        }
        start.await();
        end.await();
        if (failure.get() != null) throw new IllegalStateException(failure.get());
    }

    static void spin(int n) {                                          // ~1 us of "fraud check" between read and write
        for (int i = 0; i < n; i++) Thread.onSpinWait();
    }

    static List<String> customers(int n) {
        List<String> out = new ArrayList<>();
        for (int i = 0; i < n; i++) out.add(String.format("c%02d", i));
        return out;
    }

    static String show(Reply r) {
        return switch (r) {
            case Ok ok -> "Ok " + ok.entry().txId() + (ok.replayed() ? " (replayed)" : " (executed)");
            case InFlight f -> "InFlight, retry after " + f.retryAfter();
            case Mismatch m -> "Mismatch: " + m.why();
            case Failure f -> "Failure: " + f.reason() + (f.replayed() ? " (replayed)" : "");
        };
    }

    static String show(Result r) {
        return switch (r) {
            case Posted p -> "Posted " + p.entry().legs();
            case Duplicate d -> "Duplicate of " + d.original().txId();
            case Rejected x -> "Rejected: " + x.reason() + (x.retryable() ? " (retryable)" : "");
        };
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Entries are balanced by construction; balances are a cache of the journal ==");
        Ledger l1 = new Ledger(LockOrder.SORTED_BY_ID, List.of("alice", "bob"));
        Result fund = l1.transfer("fund-1", "bank", "alice", 10_000);
        Result pay = l1.post("tx-1", List.of(new Leg("alice", -2_100), new Leg("bob", 2_000), new Leg("fees", 100)));
        Result unbalanced = l1.post("tx-2", List.of(new Leg("alice", -500), new Leg("bob", 400)));
        Result single = l1.post("tx-3", List.of(new Leg("alice", -500)));
        Result twice = l1.post("tx-4", List.of(new Leg("alice", -500), new Leg("alice", 500)));
        Result overdraft = l1.transfer("tx-5", "bob", "alice", 5_000);
        Result again = l1.transfer("tx-1", "alice", "bob", 1);
        for (Object[] row : new Object[][]{{"fund alice 100.00 from bank", fund}, {"alice pays bob 20.00 + 1.00 fee", pay},
                {"legs -5.00 / +4.00", unbalanced}, {"single leg", single}, {"same account twice", twice},
                {"bob sends 50.00 (has 20.00)", overdraft}, {"reuse tx id tx-1", again}})
            System.out.printf("  %-32s -> %s%n", row[0], show((Result) row[1]));
        Map<String, Long> snap1 = l1.snapshot();
        System.out.printf("  balances bank %d alice %d bob %d fees %d | journal replay matches and books balance: %b%n", snap1.get("bank"),
                snap1.get("alice"), snap1.get("bob"), snap1.get("fees"), l1.journalMatches());

        System.out.println("== 2. Lock order: 2 threads x 2,000 opposite transfers alice<->bob ==");
        long[] timeouts = new long[2];
        boolean[] conserved = new boolean[2];
        for (LockOrder order : LockOrder.values()) {
            Ledger l = new Ledger(order, List.of("alice", "bob"));
            l.holdSpin = 300;
            l.transfer("f1", "bank", "alice", 1_000_000);
            l.transfer("f2", "bank", "bob", 1_000_000);
            parallel(2, t -> {
                for (int i = 0; i < 2_000; i++) {
                    String id = "t" + t + "-" + i;
                    while (l.transfer(id, t == 0 ? "alice" : "bob", t == 0 ? "bob" : "alice", 1) instanceof Rejected r && r.retryable()) {
                        Thread.onSpinWait();                           // back off and retry the same tx id
                    }
                }
            });
            timeouts[order.ordinal()] = l.lockTimeouts.sum();
            conserved[order.ordinal()] = l.journalMatches() && l.byTx.size() == 4_002;
            System.out.printf("  %-34s lock waits broken by the bounded try: %d | all 4,000 posted, journal matches: %b%n",
                    order == LockOrder.REQUEST_ORDER ? "lock(from) then lock(to):" : "lock(min id) then lock(max id):", timeouts[order.ordinal()],
                    conserved[order.ordinal()]);
        }
        Ledger many = new Ledger(LockOrder.SORTED_BY_ID, customers(16));
        for (String c : customers(16)) many.transfer("open-" + c, "bank", c, 100_000);
        LongAdder posted = new LongAdder(), rejected = new LongAdder();
        parallel(8, t -> {
            Rng r = new Rng(40 + t);
            for (int i = 0; i < 25_000; i++) {
                String from = String.format("c%02d", r.below(16)), to = String.format("c%02d", r.below(16));
                long cents = 1 + r.below(500);
                if (from.equals(to)) continue;
                if (r.below(10) == 0) {                                 // 10% carry a fee: a three-leg entry
                    if (many.post("m" + t + "-" + i, List.of(new Leg(from, -cents - 5), new Leg(to, cents), new Leg("fees", 5))) instanceof Posted)
                        posted.increment();
                    else rejected.increment();
                } else if (many.transfer("m" + t + "-" + i, from, to, cents) instanceof Posted) {
                    posted.increment();
                } else {
                    rejected.increment();
                }
            }
        });
        Map<String, Long> snapMany = many.snapshot();
        boolean noNegative = customers(16).stream().allMatch(c -> snapMany.get(c) >= 0) && snapMany.get("fees") >= 0;
        boolean manyOk = many.journalMatches();
        System.out.printf("  8 threads x 25,000 random 2- and 3-leg entries over 16 accounts: posted %d, rejected %d | no negative customer: %b | journal matches: %b%n",
                posted.sum(), rejected.sum(), noNegative, manyOk);

        System.out.println("== 3. Overdraft: 8 threads x 20 debits of 10 cents from 10.00 (exactly 100 can succeed), 300 rounds ==");
        int negativeRounds = 0;
        long minBalance = 0;
        for (int round = 0; round < 300; round++) {
            AtomicLong alice = new AtomicLong(1_000), bob = new AtomicLong();
            parallel(8, t -> {
                for (int i = 0; i < 20; i++)
                    if (alice.get() >= 10) {                            // check...
                        spin(300);
                        alice.addAndGet(-10);                          // ...then act: two threads both saw 10 cents
                        bob.addAndGet(10);
                    }
            });
            if (alice.get() < 0) negativeRounds++;
            minBalance = Math.min(minBalance, alice.get());
        }
        int lockedBad = 0;
        for (int round = 0; round < 300; round++) {
            Ledger l = new Ledger(LockOrder.SORTED_BY_ID, List.of("alice", "bob"));
            l.transfer("f", "bank", "alice", 1_000);
            LongAdder ok = new LongAdder();
            parallel(8, t -> {
                for (int i = 0; i < 20; i++)
                    if (l.transfer("d" + t + "-" + i, "alice", "bob", 10) instanceof Posted) ok.increment();
            });
            if (ok.sum() != 100 || l.snapshot().get("alice") != 0) lockedBad++;
        }
        System.out.printf("  AtomicLong check-then-act:        rounds ending below zero %d of 300 (lowest balance %d cents)%n", negativeRounds, minBalance);
        System.out.printf("  check + debit under the lock:     rounds with != 100 debits or a negative balance %d of 300%n", lockedBad);

        System.out.println("== 4. Retries: 8 threads each send the same 2,000 transfer requests (shuffled), concurrently ==");
        long[] execs = new long[2], entries = new long[2], movedCents = new long[2];
        long expectedCents = 0;
        List<Transfer> reqs = new ArrayList<>();
        Rng rq = new Rng(7);
        for (int i = 0; i < 2_000; i++) {
            int a = rq.below(16), b = (a + 1 + rq.below(15)) % 16;
            reqs.add(new Transfer(String.format("c%02d", a), String.format("c%02d", b), 1 + rq.below(100)));
            expectedCents += reqs.get(i).cents();
        }
        LongAdder fresh = new LongAdder(), replayed = new LongAdder(), inFlight = new LongAdder();
        for (int mode = 0; mode < 2; mode++) {
            Ledger l = new Ledger(LockOrder.SORTED_BY_ID, customers(16));
            for (String c : customers(16)) l.transfer("open-" + c, "bank", c, 10_000_000);
            Payments p = new Payments(l, Clock.systemUTC(), Duration.ofSeconds(30));
            final int m = mode;
            parallel(8, t -> {
                int[] order = new int[2_000];
                for (int i = 0; i < 2_000; i++) order[i] = i;
                Rng r = new Rng(500 + t);
                for (int i = 1_999; i > 0; i--) {
                    int j = r.below(i + 1), x = order[i];
                    order[i] = order[j];
                    order[j] = x;
                }
                for (int i : order) {
                    String key = "k" + i;
                    if (m == 0) {
                        p.handleNaive(key, reqs.get(i));
                        continue;
                    }
                    for (;;) {
                        Reply rep = p.handle(key, reqs.get(i));
                        if (rep instanceof InFlight) {
                            inFlight.increment();                      // a real client backs off; here we spin and retry
                            Thread.onSpinWait();
                            continue;
                        }
                        if (rep instanceof Ok ok) (ok.replayed() ? replayed : fresh).increment();
                        break;
                    }
                }
            });
            execs[mode] = p.executions.sum();
            entries[mode] = l.byTx.size() - 16;                         // minus the 16 opening entries
            for (Entry e : l.byTx.values())
                if (!e.txId().startsWith("open-")) movedCents[mode] += e.legs().get(1).cents();
            System.out.printf("  %-44s executions %d | ledger entries %d | money moved %d cents (requested %d)%s%n",
                    mode == 0 ? "check, execute, remember (fresh tx id per try):" : "CAS state machine + tx id = key:", execs[mode],
                    entries[mode], movedCents[mode], expectedCents,
                    mode == 1 ? String.format(" | replies: %d executed, %d replayed, %d told 'in flight'", fresh.sum(), replayed.sum(), inFlight.sum()) : "");
        }

        System.out.println("== 5. Crashes, leases and zombies (injected clock, lease 30 s) ==");
        TestClock clock = new TestClock();
        Ledger l5 = new Ledger(LockOrder.SORTED_BY_ID, List.of("alice", "bob", "carol"));
        l5.transfer("open-a", "bank", "alice", 10_000);
        Payments p5 = new Payments(l5, clock, Duration.ofSeconds(30));
        Transfer t1 = new Transfer("alice", "bob", 1_000), t2 = new Transfer("alice", "bob", 2_000);
        p5.crash("k1", t1, true);                                       // committed, then died before recording COMPLETED
        Reply r1 = p5.handle("k1", t1);
        clock.advance(Duration.ofSeconds(31));
        long execBefore = p5.executions.sum();
        Reply r2 = p5.handle("k1", t1);
        boolean notReExecuted = p5.executions.sum() == execBefore;
        p5.crash("k2", t2, false);                                      // died BEFORE committing
        clock.advance(Duration.ofSeconds(31));
        Reply r3 = p5.handle("k2", t2);
        Result zombie = l5.post("k2", t2.legs());                       // the original owner wakes up and finishes its work
        Reply r4 = p5.handle("k2", new Transfer("alice", "bob", 9_999));
        Reply r5 = p5.handle("k3", new Transfer("carol", "bob", 500));  // carol has nothing
        l5.transfer("open-c", "bank", "carol", 10_000);
        Reply r6 = p5.handle("k3", new Transfer("carol", "bob", 500));
        long aliceAfter = l5.snapshot().get("alice");
        System.out.println("  k1 crashed AFTER commit; retry inside the lease  -> " + show(r1));
        System.out.println("  k1 retry after the lease (takeover)             -> " + show(r2) + " | found in the ledger, not re-executed: " + notReExecuted);
        System.out.println("  k2 crashed BEFORE commit; retry after the lease -> " + show(r3));
        System.out.println("  k2's zombie owner wakes up and commits          -> " + show(zombie));
        System.out.println("  k2 reused with a different amount               -> " + show(r4));
        System.out.println("  k3 insufficient funds                           -> " + show(r5));
        System.out.println("  k3 retried after carol is topped up             -> " + show(r6) + " (a stored failure is replayed: use a new key)");
        System.out.printf("  alice %d cents (10000 - 1000 - 2000: each key moved money exactly once) | journal matches: %b%n", aliceAfter, l5.journalMatches());

        boolean ok = fund instanceof Posted && pay instanceof Posted && unbalanced instanceof Rejected && single instanceof Rejected
                && twice instanceof Rejected && overdraft instanceof Rejected && again instanceof Duplicate && l1.journalMatches()
                && snap1.get("alice") == 7_900 && snap1.get("fees") == 100
                && timeouts[1] == 0 && conserved[0] && conserved[1] && noNegative && manyOk && lockedBad == 0
                && execs[1] == 2_000 && entries[1] == 2_000 && movedCents[1] == expectedCents && fresh.sum() == 2_000
                && r1 instanceof InFlight && r2 instanceof Ok o2 && o2.replayed() && notReExecuted && r3 instanceof Ok o3 && !o3.replayed()
                && zombie instanceof Duplicate && r4 instanceof Mismatch && r5 instanceof Failure && r6 instanceof Failure f6 && f6.replayed()
                && aliceAfter == 7_000 && l5.journalMatches();
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1 and 5 deterministic; 2–4 one measured run):**

```text
== 1. Entries are balanced by construction; balances are a cache of the journal ==
  fund alice 100.00 from bank      -> Posted [bank -10000, alice +10000]
  alice pays bob 20.00 + 1.00 fee  -> Posted [alice -2100, bob +2000, fees +100]
  legs -5.00 / +4.00               -> Rejected: legs sum to -100, not 0
  single leg                       -> Rejected: an entry needs at least two legs
  same account twice               -> Rejected: account alice appears twice
  bob sends 50.00 (has 20.00)      -> Rejected: insufficient funds in bob
  reuse tx id tx-1                 -> Duplicate of tx-1
  balances bank -10000 alice 7900 bob 2000 fees 100 | journal replay matches and books balance: true
== 2. Lock order: 2 threads x 2,000 opposite transfers alice<->bob ==
  lock(from) then lock(to):          lock waits broken by the bounded try: 4162 | all 4,000 posted, journal matches: true
  lock(min id) then lock(max id):    lock waits broken by the bounded try: 0 | all 4,000 posted, journal matches: true
  8 threads x 25,000 random 2- and 3-leg entries over 16 accounts: posted 184916, rejected 2144 | no negative customer: true | journal matches: true
== 3. Overdraft: 8 threads x 20 debits of 10 cents from 10.00 (exactly 100 can succeed), 300 rounds ==
  AtomicLong check-then-act:        rounds ending below zero 300 of 300 (lowest balance -70 cents)
  check + debit under the lock:     rounds with != 100 debits or a negative balance 0 of 300
== 4. Retries: 8 threads each send the same 2,000 transfer requests (shuffled), concurrently ==
  check, execute, remember (fresh tx id per try): executions 2014 | ledger entries 2014 | money moved 101017 cents (requested 100365)
  CAS state machine + tx id = key:             executions 2000 | ledger entries 2000 | money moved 100365 cents (requested 100365) | replies: 2000 executed, 14000 replayed, 7 told 'in flight'
== 5. Crashes, leases and zombies (injected clock, lease 30 s) ==
  k1 crashed AFTER commit; retry inside the lease  -> InFlight, retry after 2026-10-27T12:00:30Z
  k1 retry after the lease (takeover)             -> Ok k1 (replayed) | found in the ledger, not re-executed: true
  k2 crashed BEFORE commit; retry after the lease -> Ok k2 (executed)
  k2's zombie owner wakes up and commits          -> Duplicate of k2
  k2 reused with a different amount               -> Mismatch: key k2 was used for a different request
  k3 insufficient funds                           -> Failure: insufficient funds in carol
  k3 retried after carol is topped up             -> Failure: insufficient funds in carol (replayed) (a stored failure is replayed: use a new key)
  alice 7000 cents (10000 - 1000 - 2000: each key moved money exactly once) | journal matches: true
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// wallet_ledger.cpp - P13: double-entry ledger, ordered account locking, idempotency-key state machine with leases and fencing
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <expected>
#include <format>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;
using namespace std::chrono;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

struct Leg {
    std::string account;
    i64 cents;
    bool operator==(const Leg&) const = default;
};

/** Immutable and balanced: the only way to get an Entry is make(), which rejects legs that don't sum to zero. */
class Entry {
    std::string tx_;
    std::vector<Leg> legs_;
    Entry(std::string tx, std::vector<Leg> legs) : tx_(std::move(tx)), legs_(std::move(legs)) {}

public:
    static std::expected<Entry, std::string> make(std::string tx, std::vector<Leg> legs) {
        if (legs.size() < 2) return std::unexpected(std::string("an entry needs at least two legs"));
        i64 sum = 0;
        std::set<std::string> seen;
        for (const auto& l : legs) {
            if (l.cents == 0) return std::unexpected(std::string("zero-amount leg"));
            if (!seen.insert(l.account).second) return std::unexpected(std::format("account {} appears twice", l.account));
            sum += l.cents;
        }
        if (sum != 0) return std::unexpected(std::format("legs sum to {}, not 0", sum));
        return Entry(std::move(tx), std::move(legs));
    }
    const std::string& tx() const { return tx_; }
    const std::vector<Leg>& legs() const { return legs_; }
    bool operator==(const Entry&) const = default;
};

std::string to_string(const std::vector<Leg>& legs) {
    std::string s = "[";
    for (const auto& l : legs) s += std::format("{}{} {}{}", s.size() > 1 ? ", " : "", l.account, l.cents > 0 ? "+" : "", l.cents);
    return s + "]";
}

struct Posted { Entry entry; };
struct Duplicate { Entry original; };
struct Rejected { std::string reason; bool retryable; };
using Result = std::variant<Posted, Duplicate, Rejected>;

std::string show(const Result& r) {
    return std::visit(overloaded{
                          [](const Posted& p) { return "Posted " + to_string(p.entry.legs()); },
                          [](const Duplicate& d) { return "Duplicate of " + d.original.tx(); },
                          [](const Rejected& x) { return "Rejected: " + x.reason + (x.retryable ? " (retryable)" : ""); },
                      },
                      r);
}

/**
 * C++ has no ConcurrentHashMap: a mutex-striped map gives the same per-key atomic operations (put_if_absent,
 * compare-and-replace). The shard mutexes are warmed once in the constructor (the MinGW lazy-init lesson from P10).
 */
template <class V> class StripedMap {
    struct Shard {
        std::mutex m;
        std::unordered_map<std::string, V> map;
    };
    std::array<Shard, 64> shards_;
    Shard& shard(const std::string& k) { return shards_[std::hash<std::string>{}(k) % shards_.size()]; }

public:
    StripedMap() {
        for (auto& s : shards_) std::scoped_lock warm(s.m);
    }
    std::optional<V> get(const std::string& k) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        const auto it = s.map.find(k);
        return it == s.map.end() ? std::nullopt : std::optional<V>(it->second);
    }
    /** Inserts and returns nullopt, or returns the value already there. */
    std::optional<V> put_if_absent(const std::string& k, const V& v) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        const auto [it, inserted] = s.map.try_emplace(k, v);
        return inserted ? std::nullopt : std::optional<V>(it->second);
    }
    bool replace(const std::string& k, const V& expected, const V& next) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        const auto it = s.map.find(k);
        if (it == s.map.end() || !(it->second == expected)) return false;
        it->second = next;
        return true;
    }
    void put(const std::string& k, const V& v) {
        auto& s = shard(k);
        std::scoped_lock l(s.m);
        s.map.insert_or_assign(k, v);
    }
    template <class F> void for_each(F f) {
        for (auto& s : shards_) {
            std::scoped_lock l(s.m);
            for (const auto& [k, v] : s.map) f(k, v);
        }
    }
    sz size() {
        sz n = 0;
        for (auto& s : shards_) {
            std::scoped_lock l(s.m);
            n += s.map.size();
        }
        return n;
    }
};

struct Account {
    std::string id;
    bool may_go_negative;  // external/settlement accounts only
    std::mutex m;
    i64 balance = 0;       // guarded by m
    Account(std::string i, bool neg) : id(std::move(i)), may_go_negative(neg) { std::scoped_lock warm(m); }
};

enum class LockOrder { RequestOrder, SortedById };

void pause_spin(int n) {
    for (int k = 0; k < n; ++k) {
#if defined(__x86_64__) || defined(__i386__)
        __builtin_ia32_pause();
#endif
    }
}

class Ledger {
    std::map<std::string, std::unique_ptr<Account>> accounts_;  // fixed after construction; iteration is in id order

    static bool try_spin(std::mutex& m) {
        for (int i = 0; i < 20'000; ++i) {
            if (m.try_lock()) return true;
            pause_spin(1);
        }
        return false;
    }

public:
    StripedMap<Entry> by_tx;  // the uniqueness constraint on tx ids
    LockOrder order;
    std::atomic<i64> lock_timeouts{0};
    int hold_spin = 0;  // work done while holding a lock (section 2 widens the window)

    Ledger(LockOrder o, const std::vector<std::string>& customers) : order(o) {
        accounts_.emplace("bank", std::make_unique<Account>("bank", true));
        accounts_.emplace("fees", std::make_unique<Account>("fees", false));
        for (const auto& c : customers) accounts_.emplace(c, std::make_unique<Account>(c, false));
    }

    Result post(const std::string& tx, std::vector<Leg> legs) {
        auto e = Entry::make(tx, std::move(legs));
        if (!e) return Rejected{e.error(), false};
        std::vector<Account*> involved;
        for (const auto& l : e->legs()) {
            const auto it = accounts_.find(l.account);
            if (it == accounts_.end()) return Rejected{"unknown account " + l.account, false};
            involved.push_back(it->second.get());
        }
        if (order == LockOrder::SortedById) std::ranges::sort(involved, {}, &Account::id);  // one global order: no cycle
        std::vector<Account*> held;
        struct Unlock {  // releases in reverse order on every return path
            std::vector<Account*>& h;
            ~Unlock() {
                for (auto it = h.rbegin(); it != h.rend(); ++it) (*it)->m.unlock();
            }
        } guard{held};
        for (Account* a : involved) {
            if (order == LockOrder::SortedById) {
                a->m.lock();
            } else if (!try_spin(a->m)) {  // request order deadlocks; the bounded try is what rescues it
                lock_timeouts.fetch_add(1);
                return Rejected{"lock timeout", true};
            }
            held.push_back(a);
            pause_spin(hold_spin);  // e.g. load this account's limits before taking the next lock
        }
        for (const auto& l : e->legs()) {
            const Account& a = *accounts_.at(l.account);
            if (!a.may_go_negative && a.balance + l.cents < 0) return Rejected{"insufficient funds in " + a.id, false};
        }
        if (auto prior = by_tx.put_if_absent(tx, *e)) return Duplicate{*prior};  // at most one commit per tx id, ever
        for (const auto& l : e->legs()) accounts_.at(l.account)->balance += l.cents;
        return Posted{*e};
    }

    Result transfer(const std::string& tx, const std::string& from, const std::string& to, i64 cents) {
        return post(tx, {{from, -cents}, {to, cents}});
    }

    /** Locks every account in id order: a consistent total that no in-flight transfer can tear. */
    std::map<std::string, i64> snapshot() {
        for (auto& [id, a] : accounts_) a->m.lock();
        std::map<std::string, i64> out;
        for (auto& [id, a] : accounts_) out[id] = a->balance;
        for (auto& [id, a] : accounts_) a->m.unlock();
        return out;
    }

    /** Balances are a cache: replaying the journal from zero must reproduce them exactly. */
    bool journal_matches() {
        std::map<std::string, i64> replayed;
        by_tx.for_each([&](const std::string&, const Entry& e) {
            for (const auto& l : e.legs()) replayed[l.account] += l.cents;
        });
        i64 total = 0;
        for (const auto& [id, bal] : snapshot()) {
            if (bal != replayed[id]) return false;
            total += bal;
        }
        return total == 0;  // double entry: the books always balance
    }
};

// ---- idempotency keys: IN_PROGRESS -> COMPLETED | FAILED, with a lease so a dead owner can be taken over

struct InProgress { std::string fingerprint; i64 attempt; sys_seconds lease_until; bool operator==(const InProgress&) const = default; };
struct Completed { std::string fingerprint; Entry entry; bool operator==(const Completed&) const = default; };
struct Failed { std::string fingerprint; std::string reason; bool retryable; bool operator==(const Failed&) const = default; };
using Idem = std::variant<InProgress, Completed, Failed>;

struct Ok { Entry entry; bool replayed; };
struct InFlight { sys_seconds retry_after; };
struct Mismatch { std::string why; };
struct Failure { std::string reason; bool replayed; };
using Reply = std::variant<Ok, InFlight, Mismatch, Failure>;

std::string show(const Reply& r) {
    return std::visit(overloaded{
                          [](const Ok& o) { return "Ok " + o.entry.tx() + (o.replayed ? " (replayed)" : " (executed)"); },
                          [](const InFlight& f) { return std::format("InFlight, retry after {:%FT%TZ}", f.retry_after); },
                          [](const Mismatch& m) { return "Mismatch: " + m.why; },
                          [](const Failure& f) { return "Failure: " + f.reason + (f.replayed ? " (replayed)" : ""); },
                      },
                      r);
}

struct Transfer {
    std::string from, to;
    i64 cents;
    std::vector<Leg> legs() const { return {{from, -cents}, {to, cents}}; }
    std::string fingerprint() const { return std::format("{}>{}:{}", from, to, cents); }  // same key + different body = misuse
};

/** A clock the test moves by hand: lease expiry is tested without sleeping. */
struct Clock {
    virtual ~Clock() = default;
    virtual sys_seconds now() const = 0;
};
struct SystemClock final : Clock {
    sys_seconds now() const override { return floor<seconds>(system_clock::now()); }
};
struct TestClock final : Clock {
    // duration_cast first: (sys_days + 12h).time_since_epoch().count() is in HOURS, and .count() strips the unit
    std::atomic<i64> t{duration_cast<seconds>((sys_days(2026y / October / 27) + 12h).time_since_epoch()).count()};
    sys_seconds now() const override { return sys_seconds(seconds(t.load())); }
    void advance(seconds d) { t.fetch_add(d.count()); }
};

const std::string& fingerprint(const Idem& s) {
    return std::visit([](const auto& x) -> const std::string& { return x.fingerprint; }, s);
}

class Payments {
    Ledger& ledger_;
    const Clock& clock_;
    seconds lease_;
    std::atomic<i64> attempts_{0};

public:
    StripedMap<Idem> keys;
    std::atomic<i64> executions{0};

    Payments(Ledger& l, const Clock& c, seconds lease) : ledger_(l), clock_(c), lease_(lease) {}

    /** Every transition is one compare-and-replace on the key's state; the money moves outside the map. */
    Reply handle(const std::string& key, const Transfer& t) {
        const std::string fp = t.fingerprint();
        for (;;) {
            const sys_seconds now = clock_.now();
            const auto cur = keys.get(key);
            if (!cur) {
                const Idem mine = InProgress{fp, 1, now + lease_};
                if (!keys.put_if_absent(key, mine)) return execute(key, t, std::get<InProgress>(mine));
                continue;  // lost the race: re-read
            }
            if (fingerprint(*cur) != fp) return Mismatch{std::format("key {} was used for a different request", key)};
            if (const auto* c = std::get_if<Completed>(&*cur)) return Ok{c->entry, true};
            if (const auto* f = std::get_if<Failed>(&*cur)) {
                if (!f->retryable) return Failure{f->reason, true};
                const Idem mine = InProgress{fp, 1, now + lease_};
                if (keys.replace(key, *cur, mine)) return execute(key, t, std::get<InProgress>(mine));
                continue;
            }
            const auto& p = std::get<InProgress>(*cur);
            if (now < p.lease_until) return InFlight{p.lease_until};
            const Idem mine = InProgress{fp, p.attempt + 1, now + lease_};  // lease expired: the owner is presumed dead...
            if (!keys.replace(key, *cur, mine)) continue;
            if (const auto committed = ledger_.by_tx.get(key)) {  // ...but it may have committed before dying
                keys.replace(key, mine, Completed{fp, *committed});
                return Ok{*committed, true};
            }
            return execute(key, t, std::get<InProgress>(mine));
        }
    }

    Reply execute(const std::string& key, const Transfer& t, const InProgress& mine) {
        executions.fetch_add(1);
        const Result r = ledger_.post(key, t.legs());  // tx id = idempotency key: the ledger is the last line of defence
        const Idem fin = std::visit(overloaded{
                                        [&](const Posted& p) -> Idem { return Completed{mine.fingerprint, p.entry}; },
                                        [&](const Duplicate& d) -> Idem { return Completed{mine.fingerprint, d.original}; },
                                        [&](const Rejected& x) -> Idem { return Failed{mine.fingerprint, x.reason, x.retryable}; },
                                    },
                                    r);
        keys.replace(key, Idem{mine}, fin);  // only if we still own the key: a takeover fences us out
        if (const auto* c = std::get_if<Completed>(&fin)) return Ok{c->entry, std::holds_alternative<Duplicate>(r)};
        return Failure{std::get<Failed>(fin).reason, false};
    }

    /** The common bug: check, execute, then remember; and a fresh ledger id per attempt, so the ledger can't help. */
    Reply handle_naive(const std::string& key, const Transfer& t) {
        if (const auto cur = keys.get(key); cur && std::holds_alternative<Completed>(*cur)) return Ok{std::get<Completed>(*cur).entry, true};
        executions.fetch_add(1);
        const Result r = ledger_.post(std::format("{}#{}", key, ++attempts_), t.legs());
        if (const auto* p = std::get_if<Posted>(&r)) {
            keys.put(key, Completed{t.fingerprint(), p->entry});
            return Ok{p->entry, false};
        }
        return Failure{show(r), false};
    }

    /** Test hook: claim the key, optionally commit, then die before recording the outcome. */
    void crash(const std::string& key, const Transfer& t, bool after_commit) {
        keys.put_if_absent(key, InProgress{t.fingerprint(), 1, clock_.now() + lease_});
        if (after_commit) ledger_.post(key, t.legs());
    }
};

// ---- harness

constexpr u64 mix64(u64 z) {
    z += 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

struct Rng {
    u64 s;
    int below(int n) { return static_cast<int>(mix64(s++) % static_cast<u64>(n)); }
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

std::vector<std::string> customers(int n) {
    std::vector<std::string> out;
    for (int i = 0; i < n; ++i) out.push_back(std::format("c{:02}", i));
    return out;
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Entries are balanced by construction; balances are a cache of the journal ==");
    Ledger l1(LockOrder::SortedById, {"alice", "bob"});
    const Result fund = l1.transfer("fund-1", "bank", "alice", 10'000);
    const Result pay = l1.post("tx-1", {{"alice", -2'100}, {"bob", 2'000}, {"fees", 100}});
    const Result unbalanced = l1.post("tx-2", {{"alice", -500}, {"bob", 400}});
    const Result single = l1.post("tx-3", {{"alice", -500}});
    const Result twice = l1.post("tx-4", {{"alice", -500}, {"alice", 500}});
    const Result overdraft = l1.transfer("tx-5", "bob", "alice", 5'000);
    const Result again = l1.transfer("tx-1", "alice", "bob", 1);
    const std::vector<std::pair<const char*, const Result*>> rows{{"fund alice 100.00 from bank", &fund}, {"alice pays bob 20.00 + 1.00 fee", &pay},
                                                                  {"legs -5.00 / +4.00", &unbalanced},     {"single leg", &single},
                                                                  {"same account twice", &twice},          {"bob sends 50.00 (has 20.00)", &overdraft},
                                                                  {"reuse tx id tx-1", &again}};
    for (const auto& [label, r] : rows) std::println("  {:<32} -> {}", label, show(*r));
    auto snap1 = l1.snapshot();
    const bool l1_ok = l1.journal_matches();
    std::println("  balances bank {} alice {} bob {} fees {} | journal replay matches and books balance: {}", snap1["bank"], snap1["alice"], snap1["bob"],
                 snap1["fees"], l1_ok);

    std::println("== 2. Lock order: 2 threads x 2,000 opposite transfers alice<->bob ==");
    std::array<i64, 2> timeouts{};
    std::array<bool, 2> conserved{};
    for (const LockOrder order : {LockOrder::RequestOrder, LockOrder::SortedById}) {
        Ledger l(order, {"alice", "bob"});
        l.hold_spin = 300;
        l.transfer("f1", "bank", "alice", 1'000'000);
        l.transfer("f2", "bank", "bob", 1'000'000);
        parallel(2, [&](int t) {
            for (int i = 0; i < 2'000; ++i) {
                const std::string id = std::format("t{}-{}", t, i);
                for (;;) {  // back off and retry the same tx id
                    const Result r = l.transfer(id, t == 0 ? "alice" : "bob", t == 0 ? "bob" : "alice", 1);
                    if (const auto* x = std::get_if<Rejected>(&r); !x || !x->retryable) break;
                }
            }
        });
        const sz k = order == LockOrder::RequestOrder ? 0 : 1;
        timeouts[k] = l.lock_timeouts.load();
        conserved[k] = l.journal_matches() && l.by_tx.size() == 4'002;
        std::println("  {:<34} lock waits broken by the bounded try: {} | all 4,000 posted, journal matches: {}",
                     k == 0 ? "lock(from) then lock(to):" : "lock(min id) then lock(max id):", timeouts[k], conserved[k]);
    }
    Ledger many(LockOrder::SortedById, customers(16));
    for (const auto& c : customers(16)) many.transfer("open-" + c, "bank", c, 100'000);
    std::atomic<i64> posted{0}, rejected{0};
    parallel(8, [&](int t) {
        Rng r{40 + static_cast<u64>(t)};
        for (int i = 0; i < 25'000; ++i) {
            const std::string from = std::format("c{:02}", r.below(16)), to = std::format("c{:02}", r.below(16));
            const i64 cents = 1 + r.below(500);
            if (from == to) continue;
            const std::string id = std::format("m{}-{}", t, i);
            std::vector<Leg> legs{{from, -cents}, {to, cents}};
            if (r.below(10) == 0) legs = {{from, -cents - 5}, {to, cents}, {"fees", 5}};  // 10% carry a fee: three legs
            const Result res = many.post(id, std::move(legs));
            (std::holds_alternative<Posted>(res) ? posted : rejected).fetch_add(1);
        }
    });
    auto snap_many = many.snapshot();
    bool no_negative = snap_many["fees"] >= 0;
    for (const auto& c : customers(16)) no_negative = no_negative && snap_many[c] >= 0;
    const bool many_ok = many.journal_matches();
    std::println("  8 threads x 25,000 random 2- and 3-leg entries over 16 accounts: posted {}, rejected {} | no negative customer: {} | journal matches: {}",
                 posted.load(), rejected.load(), no_negative, many_ok);

    std::println("== 3. Overdraft: 8 threads x 20 debits of 10 cents from 10.00 (exactly 100 can succeed), 300 rounds ==");
    int negative_rounds = 0, locked_bad = 0;
    i64 min_balance = 0;
    for (int round = 0; round < 300; ++round) {
        std::atomic<i64> alice{1'000}, bob{0};
        parallel(8, [&](int) {
            for (int i = 0; i < 20; ++i)
                if (alice.load() >= 10) {  // check...
                    pause_spin(300);
                    alice.fetch_sub(10);  // ...then act: two threads both saw 10 cents
                    bob.fetch_add(10);
                }
        });
        negative_rounds += alice.load() < 0;
        min_balance = std::min(min_balance, alice.load());
    }
    for (int round = 0; round < 300; ++round) {
        Ledger l(LockOrder::SortedById, {"alice", "bob"});
        l.transfer("f", "bank", "alice", 1'000);
        std::atomic<int> ok{0};
        parallel(8, [&](int t) {
            for (int i = 0; i < 20; ++i)
                if (std::holds_alternative<Posted>(l.transfer(std::format("d{}-{}", t, i), "alice", "bob", 10))) ok.fetch_add(1);
        });
        locked_bad += ok.load() != 100 || l.snapshot()["alice"] != 0;
    }
    std::println("  atomic check-then-act:            rounds ending below zero {} of 300 (lowest balance {} cents)", negative_rounds, min_balance);
    std::println("  check + debit under the lock:     rounds with != 100 debits or a negative balance {} of 300", locked_bad);

    std::println("== 4. Retries: 8 threads each send the same 2,000 transfer requests (shuffled), concurrently ==");
    std::array<i64, 2> execs{}, entries{}, moved{};
    i64 expected_cents = 0;
    std::vector<Transfer> reqs;
    Rng rq{7};
    for (int i = 0; i < 2'000; ++i) {
        const int a = rq.below(16), b = (a + 1 + rq.below(15)) % 16;
        const i64 cents = 1 + rq.below(100);
        reqs.push_back({std::format("c{:02}", a), std::format("c{:02}", b), cents});
        expected_cents += cents;
    }
    std::atomic<i64> fresh{0}, replayed{0}, in_flight{0};
    SystemClock sys;
    for (sz mode = 0; mode < 2; ++mode) {
        Ledger l(LockOrder::SortedById, customers(16));
        for (const auto& c : customers(16)) l.transfer("open-" + c, "bank", c, 10'000'000);
        Payments p(l, sys, 30s);
        parallel(8, [&](int t) {
            std::vector<int> order(2'000);
            for (int i = 0; i < 2'000; ++i) order[static_cast<sz>(i)] = i;
            Rng r{500 + static_cast<u64>(t)};
            for (int i = 1'999; i > 0; --i) std::swap(order[static_cast<sz>(i)], order[static_cast<sz>(r.below(i + 1))]);
            for (const int i : order) {
                const std::string key = std::format("k{}", i);
                const Transfer& req = reqs[static_cast<sz>(i)];
                if (mode == 0) {
                    p.handle_naive(key, req);
                    continue;
                }
                for (;;) {
                    const Reply rep = p.handle(key, req);
                    if (std::holds_alternative<InFlight>(rep)) {
                        in_flight.fetch_add(1);  // a real client backs off; here we spin and retry
                        continue;
                    }
                    if (const auto* o = std::get_if<Ok>(&rep)) (o->replayed ? replayed : fresh).fetch_add(1);
                    break;
                }
            }
        });
        execs[mode] = p.executions.load();
        entries[mode] = static_cast<i64>(l.by_tx.size()) - 16;  // minus the 16 opening entries
        l.by_tx.for_each([&](const std::string& tx, const Entry& e) {
            if (!tx.starts_with("open-")) moved[mode] += e.legs()[1].cents;
        });
        std::println("  {:<44} executions {} | ledger entries {} | money moved {} cents (requested {}){}",
                     mode == 0 ? "check, execute, remember (fresh tx id per try):" : "CAS state machine + tx id = key:", execs[mode], entries[mode],
                     moved[mode], expected_cents,
                     mode == 1 ? std::format(" | replies: {} executed, {} replayed, {} told 'in flight'", fresh.load(), replayed.load(), in_flight.load())
                               : "");
    }

    std::println("== 5. Crashes, leases and zombies (injected clock, lease 30 s) ==");
    TestClock clock;
    Ledger l5(LockOrder::SortedById, {"alice", "bob", "carol"});
    l5.transfer("open-a", "bank", "alice", 10'000);
    Payments p5(l5, clock, 30s);
    const Transfer t1{"alice", "bob", 1'000}, t2{"alice", "bob", 2'000};
    p5.crash("k1", t1, true);  // committed, then died before recording COMPLETED
    const Reply r1 = p5.handle("k1", t1);
    clock.advance(31s);
    const i64 exec_before = p5.executions.load();
    const Reply r2 = p5.handle("k1", t1);
    const bool not_re_executed = p5.executions.load() == exec_before;
    p5.crash("k2", t2, false);  // died BEFORE committing
    clock.advance(31s);
    const Reply r3 = p5.handle("k2", t2);
    const Result zombie = l5.post("k2", t2.legs());  // the original owner wakes up and finishes its work
    const Reply r4 = p5.handle("k2", Transfer{"alice", "bob", 9'999});
    const Reply r5 = p5.handle("k3", Transfer{"carol", "bob", 500});  // carol has nothing
    l5.transfer("open-c", "bank", "carol", 10'000);
    const Reply r6 = p5.handle("k3", Transfer{"carol", "bob", 500});
    const i64 alice_after = l5.snapshot()["alice"];
    std::println("  k1 crashed AFTER commit; retry inside the lease  -> {}", show(r1));
    std::println("  k1 retry after the lease (takeover)             -> {} | found in the ledger, not re-executed: {}", show(r2), not_re_executed);
    std::println("  k2 crashed BEFORE commit; retry after the lease -> {}", show(r3));
    std::println("  k2's zombie owner wakes up and commits          -> {}", show(zombie));
    std::println("  k2 reused with a different amount               -> {}", show(r4));
    std::println("  k3 insufficient funds                           -> {}", show(r5));
    std::println("  k3 retried after carol is topped up             -> {} (a stored failure is replayed: use a new key)", show(r6));
    const bool l5_ok = l5.journal_matches();
    std::println("  alice {} cents (10000 - 1000 - 2000: each key moved money exactly once) | journal matches: {}", alice_after, l5_ok);

    const auto* o2 = std::get_if<Ok>(&r2);
    const auto* o3 = std::get_if<Ok>(&r3);
    const auto* f6 = std::get_if<Failure>(&r6);
    const bool ok = std::holds_alternative<Posted>(fund) && std::holds_alternative<Posted>(pay) && std::holds_alternative<Rejected>(unbalanced) &&
                    std::holds_alternative<Rejected>(single) && std::holds_alternative<Rejected>(twice) && std::holds_alternative<Rejected>(overdraft) &&
                    std::holds_alternative<Duplicate>(again) && l1_ok && snap1["alice"] == 7'900 && snap1["fees"] == 100 && timeouts[1] == 0 &&
                    conserved[0] && conserved[1] && no_negative && many_ok && locked_bad == 0 && execs[1] == 2'000 && entries[1] == 2'000 &&
                    moved[1] == expected_cents && fresh.load() == 2'000 && std::holds_alternative<InFlight>(r1) && o2 && o2->replayed && not_re_executed &&
                    o3 && !o3->replayed && std::holds_alternative<Duplicate>(zombie) && std::holds_alternative<Mismatch>(r4) &&
                    std::holds_alternative<Failure>(r5) && f6 && f6->replayed && alice_after == 7'000 && l5_ok;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Entries are balanced by construction; balances are a cache of the journal ==
  fund alice 100.00 from bank      -> Posted [bank -10000, alice +10000]
  alice pays bob 20.00 + 1.00 fee  -> Posted [alice -2100, bob +2000, fees +100]
  legs -5.00 / +4.00               -> Rejected: legs sum to -100, not 0
  single leg                       -> Rejected: an entry needs at least two legs
  same account twice               -> Rejected: account alice appears twice
  bob sends 50.00 (has 20.00)      -> Rejected: insufficient funds in bob
  reuse tx id tx-1                 -> Duplicate of tx-1
  balances bank -10000 alice 7900 bob 2000 fees 100 | journal replay matches and books balance: true
== 2. Lock order: 2 threads x 2,000 opposite transfers alice<->bob ==
  lock(from) then lock(to):          lock waits broken by the bounded try: 4219 | all 4,000 posted, journal matches: true
  lock(min id) then lock(max id):    lock waits broken by the bounded try: 0 | all 4,000 posted, journal matches: true
  8 threads x 25,000 random 2- and 3-leg entries over 16 accounts: posted 184990, rejected 2070 | no negative customer: true | journal matches: true
== 3. Overdraft: 8 threads x 20 debits of 10 cents from 10.00 (exactly 100 can succeed), 300 rounds ==
  atomic check-then-act:            rounds ending below zero 300 of 300 (lowest balance -70 cents)
  check + debit under the lock:     rounds with != 100 debits or a negative balance 0 of 300
== 4. Retries: 8 threads each send the same 2,000 transfer requests (shuffled), concurrently ==
  check, execute, remember (fresh tx id per try): executions 2015 | ledger entries 2015 | money moved 101315 cents (requested 100365)
  CAS state machine + tx id = key:             executions 2000 | ledger entries 2000 | money moved 100365 cents (requested 100365) | replies: 2000 executed, 14000 replayed, 263 told 'in flight'
== 5. Crashes, leases and zombies (injected clock, lease 30 s) ==
  k1 crashed AFTER commit; retry inside the lease  -> InFlight, retry after 2026-10-27T12:00:30Z
  k1 retry after the lease (takeover)             -> Ok k1 (replayed) | found in the ledger, not re-executed: true
  k2 crashed BEFORE commit; retry after the lease -> Ok k2 (executed)
  k2's zombie owner wakes up and commits          -> Duplicate of k2
  k2 reused with a different amount               -> Mismatch: key k2 was used for a different request
  k3 insufficient funds                           -> Failure: insufficient funds in carol
  k3 retried after carol is topped up             -> Failure: insufficient funds in carol (replayed) (a stored failure is replayed: use a new key)
  alice 7000 cents (10000 - 1000 - 2000: each key moved money exactly once) | journal matches: true
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Entries are balanced by construction; balances are a cache of the journal ==
  fund alice 100.00 from bank      -> Posted [bank -10000, alice +10000]
  alice pays bob 20.00 + 1.00 fee  -> Posted [alice -2100, bob +2000, fees +100]
  legs -5.00 / +4.00               -> Rejected: legs sum to -100, not 0
  single leg                       -> Rejected: an entry needs at least two legs
  same account twice               -> Rejected: account alice appears twice
  bob sends 50.00 (has 20.00)      -> Rejected: insufficient funds in bob
  reuse tx id tx-1                 -> Duplicate of tx-1
  balances bank -10000 alice 7900 bob 2000 fees 100 | journal replay matches and books balance: true
== 2. Lock order: 2 threads x 2,000 opposite transfers alice<->bob ==
  lock(from) then lock(to):          lock waits broken by the bounded try: 4060 | all 4,000 posted, journal matches: true
  lock(min id) then lock(max id):    lock waits broken by the bounded try: 0 | all 4,000 posted, journal matches: true
  8 threads x 25,000 random 2- and 3-leg entries over 16 accounts: posted 184959, rejected 2101 | no negative customer: true | journal matches: true
== 3. Overdraft: 8 threads x 20 debits of 10 cents from 10.00 (exactly 100 can succeed), 300 rounds ==
  atomic check-then-act:            rounds ending below zero 300 of 300 (lowest balance -70 cents)
  check + debit under the lock:     rounds with != 100 debits or a negative balance 0 of 300
== 4. Retries: 8 threads each send the same 2,000 transfer requests (shuffled), concurrently ==
  check, execute, remember (fresh tx id per try): executions 2020 | ledger entries 2020 | money moved 101691 cents (requested 100365)
  CAS state machine + tx id = key:             executions 2000 | ledger entries 2000 | money moved 100365 cents (requested 100365) | replies: 2000 executed, 14000 replayed, 115 told 'in flight'
== 5. Crashes, leases and zombies (injected clock, lease 30 s) ==
  k1 crashed AFTER commit; retry inside the lease  -> InFlight, retry after 2026-10-27T12:00:30Z
  k1 retry after the lease (takeover)             -> Ok k1 (replayed) | found in the ledger, not re-executed: true
  k2 crashed BEFORE commit; retry after the lease -> Ok k2 (executed)
  k2's zombie owner wakes up and commits          -> Duplicate of k2
  k2 reused with a different amount               -> Mismatch: key k2 was used for a different request
  k3 insufficient funds                           -> Failure: insufficient funds in carol
  k3 retried after carol is topped up             -> Failure: insufficient funds in carol (replayed) (a stored failure is replayed: use a new key)
  alice 7000 cents (10000 - 1000 - 2000: each key moved money exactly once) | journal matches: true
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Model | `balance` field, `+=` / `-=` | Transfer record with two amounts | Immutable balanced entry (N legs, Σ = 0); journal is the truth, balances a cache verified by replay |
| Locking | `synchronized` service | Per-account locks | Sorted global order (or `std::scoped_lock`); check + debit in the same critical section; no I/O under locks |
| Retries | "The client shouldn't retry" | Dedup table, check-then-insert | Claim by CAS, lease + takeover that checks the journal, fingerprint mismatch, stored-failure replay, tx id = key with a uniqueness constraint that fences zombies |
| Evidence | Happy-path test | Concurrent test that happens to pass | Widened-window deadlock test, overdraft rounds, retry storms, crash/zombie scenarios on an injected clock |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Put it in Postgres" | Journal table with `UNIQUE(tx_id)`. Idempotency row inserted with `INSERT … ON CONFLICT DO NOTHING` in the **same transaction** as the entry. Lock with `SELECT … FOR UPDATE` ordered by account id. A balance check via `CHECK (balance >= 0)` or in the same transaction |
| "A merchant account receives 5,000 payments/s" | It's a hot row. Split it into K sub-accounts (credit a random one; the balance is the sum, as in [P15](05-problem-15-ecommerce-flash-sale-inventory-reservation-and-cart-rules.md)), or append credits to the journal and roll balances up asynchronously (credits can't overdraw) |
| "Refunds" | A new entry that reverses the original legs, referencing it. Never edit or delete an entry |
| "Holds / card authorizations" | A pending-hold account: authorize = entry customer → holds; capture = holds → merchant; void = holds → customer. Each step is an idempotent entry |
| "Exactly-once across services" | There's no such thing on the wire. Use at-least-once delivery + idempotent consumers keyed by the same id (an outbox table for publishing) |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Two transfers in opposite directions. What happens?"</b></summary>

**L5:** "Each locks its accounts; it's fine."

**Why it fails:** `lock(from); lock(to)` deadlocks. Measured: ~4,100 broken waits per 4,000 transfers once there's a 1 µs window, and 0–254 without it (so the test "passes" on a bad day).

**L7 defence:** "One global order: sort the account ids and lock ascending, for any number of legs. In C++ `std::scoped_lock` avoids deadlock by back-off instead; in SQL, update rows ordered by id. A timeout only detects; ordering prevents."
</details>

<details>
<summary><b>Q2 ⚡ "The client timed out and retried. Did we charge twice?"</b></summary>

**L5:** "We check whether the key was processed."

**Why it fails:** check-then-execute races. Measured: 14–20 double executions per 2,000 requests, moving up to 13.26 extra dollars.

**L7 defence:** "Claim the key with a CAS into IN_PROGRESS; a concurrent retry gets 409. Execute with tx id = key, so the ledger's uniqueness constraint makes a second commit impossible. Finish with a conditional replace, so only the owner records the outcome."
</details>

<details>
<summary><b>Q3 🔥 "The server died after debiting but before saving COMPLETED."</b></summary>

**L5:** "The retry will run it again."

**Why it fails:** double debit. Or, if you refuse to run it, the payment is stuck forever.

**L7 defence:** "IN_PROGRESS carries a lease on an injected clock. After it expires a retry takes over with attempt+1 and **asks the journal** whether tx = key exists. If yes, mark it COMPLETED and replay. If not, execute. If the old owner wakes up and commits, the uniqueness constraint returns Duplicate. That's fencing done by the data, not by trusting timeouts."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Threads stuck in transfers | Request-order locking | Sorted order |
| Negative balance | Check-then-debit split | One critical section |
| Charged twice on retry | Dedup by check-then-insert; fresh tx id per attempt | CAS claim; tx id = key; unique journal |
| Stuck "processing" forever | No lease on IN_PROGRESS | Lease + takeover that consults the journal |
| Zombie commit after takeover | Trusting the lease alone | Uniqueness constraint fences the commit |
| Audit says books don't balance (but they do) | `Long != Long` identity compare | Unbox; compare primitives |

- [ ] Balanced, immutable entries; journal replay equals balances; Σ all accounts = 0.
- [ ] Locks in one global order; balance check and mutation in one critical section.
- [ ] Idempotency: CAS claim, 409 while in flight, fingerprint check, lease + journal-checked takeover, stored-failure replay.
- [ ] Tx id derived from the key; uniqueness constraint as the final guard.
- [ ] Tests with widened windows, retry storms and crash points on an injected clock.

## 10. References

- Stripe, *Designing robust and predictable APIs with idempotency*. <https://stripe.com/blog/idempotency>
- IETF HTTPAPI, *The Idempotency-Key HTTP Header Field* (draft). <https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/>
- Martin Kleppmann, *How to do distributed locking* (fencing tokens). <https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html>
- cppreference, `std::lock` (deadlock avoidance). <https://en.cppreference.com/w/cpp/thread/lock>
- Java `ConcurrentHashMap` (`putIfAbsent`, `replace`, `compute`). <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/ConcurrentHashMap.html>
- In this KB: [P6 Seat holds and fencing](../04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/01-problem-06-movie-ticket-booking-bookmyshow-seat-lock-and-deadlock-free.md) · [P11 Exact money](01-problem-11-splitwise-expense-sharing-and-min-cash-flow-graph-simplifier.md) · [P15 Striped hot counters](05-problem-15-ecommerce-flash-sale-inventory-reservation-and-cart-rules.md)
