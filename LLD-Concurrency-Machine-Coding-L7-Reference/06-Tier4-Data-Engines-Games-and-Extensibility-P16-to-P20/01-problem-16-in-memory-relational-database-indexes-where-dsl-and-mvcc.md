# P16 · In-Memory Relational Table: Schema, Indexes, a Predicate AST with a Planner, and MVCC

> **Folder 06 · Problem 16 of 20.** "Build a mini database" separates candidates fast. L7 answers rest on four claims:
> 1. **Schema validation is the row constructor.** A row that doesn't fit is never stored.
> 2. **Indexes return *candidates*.** Visibility plus a recheck of the predicate decide the answer.
> 3. **The planner turns a predicate tree into set operations** over indexes: intersect by probing the bigger set, union, or scan when an `OR` side has no index.
> 4. **MVCC gives readers lock-free snapshots and writers first-committer-wins.** Snapshot isolation still permits **write skew**. The listing reproduces it, then fixes it.
>
> **Listing pair P16:** `MiniDb.java` / `mini_db.cpp`. Sections 1–4 are deterministic: the planner's candidate counts and all MVCC outcomes are **identical in Java and C++**. Timings and section 5 are one measured run.

---

## 1. Problem and scope

**Functional:**
- A table with typed columns (INT, TEXT), NOT NULL and an INT primary key.
- A hash index (equality) and a range index (ordered).
- Queries as a predicate tree: `Eq`, `Between`, `And`, `Or`.
- Transactions: begin, get, insert, update, select, commit.
- Repeatable snapshot reads; write-write conflicts abort the later committer.

**Out of scope:**
- SQL parsing: the AST *is* the parsed form.
- Joins: hash join on the same index structures.
- Durability: a WAL in front of `commit`.
- Vacuum (§7).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Schema | `record Schema(table, columns)`; `validate(Map) → Object[]` throws on unknown column, NOT NULL or type mismatch | `validate → std::expected<Row, std::string>`; `Value = std::variant<monostate, i64, string>` |
| Predicate | `sealed interface Pred permits Eq, Between, And, Or` | recursive `struct Pred { std::variant<Eq, Between, And, Or> }`, children behind `shared_ptr` |
| Indexes | `ConcurrentHashMap<value, Set<id>>`, `ConcurrentSkipListMap<Long, Set<id>>` | `unordered_map` / `std::map` under one mutex (std C++ has no concurrent skip list) |
| Versions | `record Version(begin, row, prev)` chain per row in `AtomicReference` | `struct Version` in an append-only arena; `std::atomic<const Version*> head` |
| Transaction | `Tx(readTs, writes, readForUpdate)`; `commit()` = validate + install under `commitLock` | the same |

**Invariants:**
- **I1:** every stored row satisfies the schema. The only path to storage is `validate`.
- **I2:** a query returns exactly the rows a full scan of the same snapshot would. Asserted for every query.
- **I3:** a transaction sees one snapshot: committed versions with `begin ≤ readTs`, plus its own writes.
- **I4:** if two transactions write the same row concurrently, at most one commits.
- **I5:** a committed version is visible to new snapshots only once all its index entries exist. The version and indexes are published, *then* the clock.

## 3. Concurrency and contention analysis

### 3.1 The planner: predicate tree → set algebra

**200,000 rows**, hash index on `city` (50 values), range index on `age`. The candidate sizes are identical in both languages:

| Query | Plan | Examined | Full scan |
|---|---|---|---|
| `city = c07 AND age 30..39` | `INTERSECT[HASH (4,142), RANGE (31,617)]` → 659 | **659** | 200,000 |
| `city = c07 OR city = c11` | `UNION[HASH (4,142), HASH (3,956)]` → 8,098 | 8,098 | 200,000 |
| `age 30..31 AND name = n123456` | `RANGE (6,413) then FILTER` (name has no index) | 6,413 | 200,000 |
| `balance 0..99` | `SCAN` (no index) | 200,000 | 200,000 |
| `city = c07 AND city = c08` | `INTERSECT` → 0 | 0 | 200,000 |

Measured time: Java 0.5–5 ms planned vs 13–36 ms scanned; C++ 1–11 ms vs 33–72 ms.

**Rules:**
- **`AND`:** intersect by iterating the **smaller** candidate set and probing the larger, which is O(min). If one side has no index, use the indexed side and filter.
- **`OR`:** union. If either side has no index, the whole `OR` must scan.
- **Selectivity:** this listing uses exact candidate-set sizes. Real engines estimate from statistics and histograms, and may skip an intersection when one side is tiny.

**Why recheck?** Index entries are **not versioned**: an entry names every row that *ever* had the value. The planner produces candidates; `select()` fetches the **visible** version and re-tests the predicate. Postgres does the same "recheck", and needs a visibility map to skip the heap.

### 3.2 MVCC: readers never lock, writers race at commit

- **Each row is a newest-first version chain.** A reader at `readTs` walks to the first version with `begin ≤ readTs`. There is no lock and no copy; C++ returns a `const Row*` into the immutable arena.
- **Commit runs under one commit lock:**
  1. Abort if any written (or read-for-update) row has a version newer than `readTs`. That's first-committer-wins.
  2. Publish the new versions and index entries.
  3. **Then** advance the clock. Snapshots taken after the clock moves see everything; earlier snapshots skip the new versions by timestamp.

**Section 3 shows the deterministic interleaving:**
- T1 reads 100.
- T2 writes 150 and commits.
- T1 still reads 100 (repeatable).
- T1's write aborts: T2 won.

**Measured: 8 threads × 5,000 transfers over 64 accounts**, with an auditor summing all balances in a snapshot the whole time:

| Engine | Final total (expected 64,000) | Audits with total ≠ 64,000 | Aborts + retries |
|---|---|---|---|
| No isolation: latest reads, no validation | **57,609 / 64,796 / 60,170** (Java / GCC / Clang) | ≈ all | 0 |
| Snapshot isolation + first-committer-wins | 64,000 | **0** of 76,067 / 43,744 / 54,036 | 6,496 / 5,579 / 10,328 |

The retry loop is the price of optimism: about 15–25% extra work under heavy contention on 64 hot rows. Under lower contention it falls toward zero, and readers pay nothing either way.

### 3.3 Snapshot isolation is not serializable: write skew

Two doctors are on call. Each transaction reads "2 on call" and takes **itself** off. The writes touch different rows, so there's no write-write conflict: **both commit, and 0 doctors are on call.**

The fix promotes the reads into the conflict check (`getForUpdate`, an optimistic `SELECT … FOR UPDATE`). Bob's transaction read Alice's row, Alice committed a change to it, so Bob aborts and 1 doctor stays on call.

Real engines offer three options:
- **SSI**, which tracks read-write antidependencies (PostgreSQL `SERIALIZABLE`);
- explicit `FOR UPDATE`;
- **materializing the conflict**: a "roster" row every such transaction updates.

## 4. Java 21 implementation

```java
// MiniDb.java - P16: in-memory table, schema validation, hash + skip-list indexes, predicate AST + planner, MVCC snapshot isolation
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.ReentrantLock;

public final class MiniDb {

    // ---- schema: a row that doesn't fit cannot be written

    enum Type { INT, TEXT }

    enum Index { NONE, HASH, RANGE }

    record Column(String name, Type type, boolean notNull, Index index) {}

    record Schema(String table, List<Column> columns) {               // column 0 is the INT primary key
        int pos(String col) {
            for (int i = 0; i < columns.size(); i++)
                if (columns.get(i).name().equals(col)) return i;
            throw new IllegalArgumentException("unknown column " + col);
        }

        Object[] validate(Map<String, Object> values) {
            for (String k : values.keySet()) pos(k);                   // rejects unknown columns
            Object[] row = new Object[columns.size()];
            for (int i = 0; i < row.length; i++) {
                Column c = columns.get(i);
                Object v = values.get(c.name());
                if (v == null && (c.notNull() || i == 0)) throw new IllegalArgumentException("column " + c.name() + " is NOT NULL");
                if (v != null && (c.type() == Type.INT ? !(v instanceof Long) : !(v instanceof String)))
                    throw new IllegalArgumentException("column " + c.name() + " expects " + c.type() + ", got " + v.getClass().getSimpleName());
                row[i] = v;
            }
            return row;
        }
    }

    // ---- predicates: a sealed AST, evaluated per row and planned against indexes

    sealed interface Pred permits Eq, Between, And, Or {}
    record Eq(String col, Object value) implements Pred {}
    record Between(String col, long lo, long hi) implements Pred {}   // inclusive, INT columns
    record And(Pred l, Pred r) implements Pred {}
    record Or(Pred l, Pred r) implements Pred {}

    static boolean test(Pred p, Schema s, Object[] row) {
        return switch (p) {
            case Eq e -> e.value().equals(row[s.pos(e.col())]);
            case Between b -> row[s.pos(b.col())] instanceof Long v && v >= b.lo() && v <= b.hi();
            case And a -> test(a.l(), s, row) && test(a.r(), s, row);
            case Or o -> test(o.l(), s, row) || test(o.r(), s, row);
        };
    }

    // ---- MVCC storage: per-row version chains, newest first; versions are immutable once published

    record Version(long begin, Object[] row, Version prev) {}        // row == null: deleted

    static Object[] visible(Version head, long readTs) {
        for (Version v = head; v != null; v = v.prev())
            if (v.begin() <= readTs) return v.row();                   // the newest version committed at or before the snapshot
        return null;
    }

    /** What the planner decided: candidate row ids (null = full scan) and a human-readable plan. */
    record Access(String explain, Set<Long> ids) {}

    static final class Db {
        final Schema schema;
        final ConcurrentHashMap<Long, AtomicReference<Version>> rows = new ConcurrentHashMap<>();
        final Map<String, ConcurrentHashMap<Object, Set<Long>>> hash = new HashMap<>();
        final Map<String, ConcurrentSkipListMap<Long, Set<Long>>> range = new HashMap<>();
        final AtomicLong clock = new AtomicLong();                     // last committed timestamp
        final ReentrantLock commitLock = new ReentrantLock();          // commits are serialized; readers never lock
        final boolean isolation;                                       // false = the naive engine: latest reads, no validation
        final LongAdder aborts = new LongAdder();

        Db(Schema schema, boolean isolation) {
            this.schema = schema;
            this.isolation = isolation;
            for (Column c : schema.columns()) {
                if (c.index() == Index.HASH) hash.put(c.name(), new ConcurrentHashMap<>());
                if (c.index() == Index.RANGE) range.put(c.name(), new ConcurrentSkipListMap<>());
            }
        }

        Tx begin() {
            return new Tx(this, isolation ? clock.get() : Long.MAX_VALUE);
        }

        /** Index entries are not versioned: they name every row that ever had the value; visibility + recheck decide. */
        void index(long id, Object[] row) {
            for (var e : hash.entrySet()) {
                Object v = row[schema.pos(e.getKey())];
                if (v != null) e.getValue().computeIfAbsent(v, k -> ConcurrentHashMap.newKeySet()).add(id);
            }
            for (var e : range.entrySet()) {
                Object v = row[schema.pos(e.getKey())];
                if (v instanceof Long l) e.getValue().computeIfAbsent(l, k -> ConcurrentHashMap.newKeySet()).add(id);
            }
        }

        Access plan(Pred p) {
            return switch (p) {
                case Eq e when hash.containsKey(e.col()) -> {
                    Set<Long> ids = hash.get(e.col()).getOrDefault(e.value(), Set.of());
                    yield new Access("HASH " + e.col() + "=" + e.value() + " (" + ids.size() + ")", ids);
                }
                case Eq e when range.containsKey(e.col()) && e.value() instanceof Long v -> {
                    Set<Long> ids = range.get(e.col()).getOrDefault(v, Set.of());
                    yield new Access("RANGE " + e.col() + "=" + v + " (" + ids.size() + ")", ids);
                }
                case Between b when range.containsKey(b.col()) -> {
                    Set<Long> ids = new HashSet<>();
                    for (Set<Long> s : range.get(b.col()).subMap(b.lo(), true, b.hi(), true).values()) ids.addAll(s);
                    yield new Access("RANGE " + b.col() + " " + b.lo() + ".." + b.hi() + " (" + ids.size() + ")", ids);
                }
                case And a -> {
                    Access l = plan(a.l()), r = plan(a.r());
                    if (l.ids() == null && r.ids() == null) yield new Access("SCAN", null);
                    if (l.ids() == null || r.ids() == null) {
                        Access idx = l.ids() == null ? r : l;
                        yield new Access(idx.explain() + " then FILTER", idx.ids());
                    }
                    Set<Long> small = l.ids().size() <= r.ids().size() ? l.ids() : r.ids(), big = small == l.ids() ? r.ids() : l.ids();
                    Set<Long> ids = new HashSet<>();
                    for (Long id : small)
                        if (big.contains(id)) ids.add(id);                 // probe the bigger set: O(min)
                    yield new Access("INTERSECT[" + l.explain() + ", " + r.explain() + "] (" + ids.size() + ")", ids);
                }
                case Or o -> {
                    Access l = plan(o.l()), r = plan(o.r());
                    if (l.ids() == null || r.ids() == null) yield new Access("SCAN (an OR side has no index)", null);
                    Set<Long> ids = new HashSet<>(l.ids());
                    ids.addAll(r.ids());
                    yield new Access("UNION[" + l.explain() + ", " + r.explain() + "] (" + ids.size() + ")", ids);
                }
                default -> new Access("SCAN", null);
            };
        }
    }

    static final class Tx {
        final Db db;
        final long readTs;
        final Map<Long, Object[]> writes = new LinkedHashMap<>();      // id -> new row (null = delete)
        final Set<Long> readForUpdate = new HashSet<>();               // reads promoted into the conflict check
        final Set<Long> inserts = new HashSet<>();
        long examined;

        Tx(Db db, long readTs) {
            this.db = db;
            this.readTs = readTs;
        }

        Optional<Object[]> get(long id) {
            if (writes.containsKey(id)) return Optional.ofNullable(writes.get(id));
            AtomicReference<Version> head = db.rows.get(id);
            return head == null ? Optional.empty() : Optional.ofNullable(visible(head.get(), readTs));
        }

        Optional<Object[]> getForUpdate(long id) {                     // SELECT ... FOR UPDATE, optimistic flavour
            readForUpdate.add(id);
            return get(id);
        }

        String insert(Map<String, Object> values) {
            Object[] row;
            try {
                row = db.schema.validate(values);
            } catch (IllegalArgumentException e) {
                return "rejected: " + e.getMessage();
            }
            long id = (Long) row[0];
            if (get(id).isPresent()) return "rejected: duplicate primary key " + id;
            writes.put(id, row);
            inserts.add(id);
            return "ok";
        }

        void update(long id, String col, Object value) {
            Object[] row = get(id).orElseThrow().clone();
            row[db.schema.pos(col)] = value;
            writes.put(id, db.schema.validate(toMap(db.schema, row)));
        }

        List<Object[]> select(Pred p) {
            Access a = db.plan(p);
            Iterable<Long> ids = a.ids() == null ? db.rows.keySet() : a.ids();
            List<Object[]> out = new ArrayList<>();
            Set<Long> seen = new HashSet<>();
            for (Long id : ids) {
                examined++;
                if (!writes.isEmpty()) seen.add(id);                   // only needed to merge our own writes below
                get(id).filter(r -> test(p, db.schema, r)).ifPresent(out::add);   // index = candidates; visibility + recheck = truth
            }
            for (Long id : writes.keySet())                            // our own uncommitted rows are not in the indexes yet
                if (!seen.contains(id)) get(id).filter(r -> test(p, db.schema, r)).ifPresent(out::add);
            return out;
        }

        /** First committer wins: abort if anything we wrote (or read for update) was committed after our snapshot. */
        boolean commit() {
            db.commitLock.lock();
            try {
                if (db.isolation) {
                    Set<Long> check = new HashSet<>(writes.keySet());
                    check.addAll(readForUpdate);
                    for (Long id : check) {
                        AtomicReference<Version> head = db.rows.get(id);
                        if (head != null && head.get().begin() > readTs) {
                            db.aborts.increment();
                            return false;
                        }
                    }
                }
                long ts = db.clock.get() + 1;
                for (var w : writes.entrySet()) {
                    AtomicReference<Version> head = db.rows.computeIfAbsent(w.getKey(), k -> new AtomicReference<>());
                    head.set(new Version(ts, w.getValue(), head.get()));   // publish the version...
                    if (w.getValue() != null) db.index(w.getKey(), w.getValue());
                }
                db.clock.set(ts);                                      // ...then the timestamp: new snapshots see all of it
                return true;
            } finally {
                db.commitLock.unlock();
            }
        }
    }

    static Map<String, Object> toMap(Schema s, Object[] row) {
        Map<String, Object> m = new HashMap<>();
        for (int i = 0; i < row.length; i++)
            if (row[i] != null) m.put(s.columns().get(i).name(), row[i]);
        return m;
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

    static Map<String, Object> person(long id, String name, String city, long age, long balance) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("name", name);
        if (city != null) m.put("city", city);
        m.put("age", age);
        m.put("balance", balance);
        return m;
    }

    static final Schema PEOPLE = new Schema("people", List.of(new Column("id", Type.INT, true, Index.NONE), new Column("name", Type.TEXT, true, Index.NONE),
            new Column("city", Type.TEXT, true, Index.HASH), new Column("age", Type.INT, true, Index.RANGE), new Column("balance", Type.INT, true, Index.NONE)));

    static final Schema ACCOUNTS = new Schema("accounts", List.of(new Column("id", Type.INT, true, Index.NONE), new Column("balance", Type.INT, true, Index.NONE)));

    static long balance(Tx t, long id) {
        return (Long) t.get(id).orElseThrow()[1];
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. Schema validation ==");
        Db small = new Db(PEOPLE, true);
        Tx t0 = small.begin();
        Map<String, Object> badType = person(2, "bob", "c01", 30, 0);
        badType.put("age", "thirty");
        Map<String, Object> unknown = person(4, "dan", "c01", 30, 0);
        unknown.put("email", "d@x");
        String[][] rows = {{"insert 1 ann c01 age 30", t0.insert(person(1, "ann", "c01", 30, 100))},
                {"insert 2 with age 'thirty'", t0.insert(badType)}, {"insert 3 with no city", t0.insert(person(3, "cat", null, 30, 0))},
                {"insert 4 with column email", t0.insert(unknown)}, {"insert 1 again", t0.insert(person(1, "amy", "c02", 40, 0))}};
        for (String[] r : rows) System.out.printf("  %-30s -> %s%n", r[0], r[1]);
        t0.commit();

        System.out.println("== 2. 200,000 people; hash index on city, skip-list index on age; planner vs full scan ==");
        Db db = new Db(PEOPLE, true);
        Rng r = new Rng(16);
        Tx load = db.begin();
        for (long i = 0; i < 200_000; i++)
            load.insert(person(i, "n" + i, String.format("c%02d", r.below(50)), 18 + r.below(63), r.below(10_000)));
        load.commit();
        List<Map.Entry<String, Pred>> queries = List.of(
                Map.entry("city = c07 AND age 30..39", new And(new Eq("city", "c07"), new Between("age", 30, 39))),
                Map.entry("city = c07 OR city = c11", new Or(new Eq("city", "c07"), new Eq("city", "c11"))),
                Map.entry("age 30..31 AND name = n123456", new And(new Between("age", 30, 31), new Eq("name", "n123456"))),
                Map.entry("balance 0..99 (no index)", new Between("balance", 0, 99)),
                Map.entry("city = c07 AND city = c08", new And(new Eq("city", "c07"), new Eq("city", "c08"))));
        boolean plansAgree = true;
        long plannedExamined = 0;
        for (int pass = 0; pass < 2; pass++)                           // pass 0 warms the JIT; pass 1 is printed
        for (var q : queries) {
            Tx planned = db.begin(), scan = db.begin();
            long t1 = System.nanoTime();
            int n = planned.select(q.getValue()).size();
            long t2 = System.nanoTime();
            int full = 0;
            for (Long id : db.rows.keySet()) {
                scan.examined++;
                if (scan.get(id).filter(x -> test(q.getValue(), PEOPLE, x)).isPresent()) full++;
            }
            long t3 = System.nanoTime();
            plansAgree &= n == full;
            if (pass == 0) continue;
            plannedExamined += planned.examined;
            System.out.printf("  %-30s %s%n  %-30s   -> %d rows | examined %d vs %d for a full scan | %.1f ms vs %.1f ms | same result: %b%n", q.getKey(),
                    db.plan(q.getValue()).explain(), "", n, planned.examined, scan.examined, (t2 - t1) / 1e6, (t3 - t2) / 1e6, n == full);
        }

        System.out.println("== 3. MVCC: snapshot reads, first committer wins ==");
        Db bank = new Db(ACCOUNTS, true);
        Tx setup = bank.begin();
        setup.insert(Map.of("id", 1L, "balance", 100L));
        setup.commit();
        Tx t1 = bank.begin();
        long seen1 = balance(t1, 1);
        Tx t2 = bank.begin();
        t2.update(1, "balance", 150L);
        boolean c2 = t2.commit();
        long seen2 = balance(t1, 1);
        t1.update(1, "balance", seen2 + 10);
        boolean c1 = t1.commit();
        long after = balance(bank.begin(), 1);
        System.out.printf("  T1 reads %d | T2 writes 150 and commits: %b | T1 reads again: %d (its snapshot) | T1 writes %d: commit %b (T2 won) | new snapshot: %d%n",
                seen1, c2, seen2, seen2 + 10, c1, after);

        System.out.println("== 4. Write skew: snapshot isolation lets two doctors both go off call ==");
        boolean[] skewOk = new boolean[2];
        for (int mode = 0; mode < 2; mode++) {
            Db doctors = new Db(ACCOUNTS, true);                       // id = doctor, column 'balance' = on_call (1/0)
            Tx s = doctors.begin();
            s.insert(Map.of("id", 1L, "balance", 1L));
            s.insert(Map.of("id", 2L, "balance", 1L));
            s.commit();
            Tx alice = doctors.begin(), bob = doctors.begin();
            long onCallA = 0, onCallB = 0;
            for (long id = 1; id <= 2; id++) {
                onCallA += (Long) (mode == 1 ? alice.getForUpdate(id) : alice.get(id)).orElseThrow()[1];
                onCallB += (Long) (mode == 1 ? bob.getForUpdate(id) : bob.get(id)).orElseThrow()[1];
            }
            if (onCallA >= 2) alice.update(1, "balance", 0L);              // "someone else is on call, I can leave"
            if (onCallB >= 2) bob.update(2, "balance", 0L);
            boolean ca = alice.commit(), cb = bob.commit();
            Tx check = doctors.begin();
            long onCall = balance(check, 1) + balance(check, 2);
            skewOk[mode] = onCall >= 1;
            System.out.printf("  %-38s alice commits %b, bob commits %b -> doctors on call: %d%n",
                    mode == 0 ? "plain snapshot reads:" : "reads promoted (getForUpdate):", ca, cb, onCall);
        }

        System.out.println("== 5. 8 threads x 5,000 transfers over 64 accounts + an auditor summing balances in snapshots ==");
        long[] finalTotal = new long[2], tornAudits = new long[2], audits = new long[2], aborts = new long[2];
        for (int mode = 0; mode < 2; mode++) {
            Db acc = new Db(ACCOUNTS, mode == 1);
            Tx s = acc.begin();
            for (long id = 0; id < 64; id++) s.insert(Map.of("id", id, "balance", 1_000L));
            s.commit();
            CyclicBarrier start = new CyclicBarrier(10);
            CountDownLatch writers = new CountDownLatch(8), auditorDone = new CountDownLatch(1);
            AtomicBoolean running = new AtomicBoolean(true);
            AtomicReference<Exception> failure = new AtomicReference<>();
            long[] seen = new long[2];
            for (int t = 0; t < 8; t++) {
                final int id = t;
                Thread.ofPlatform().start(() -> {
                    try {
                        start.await();
                        Rng rr = new Rng(200 + id);
                        for (int i = 0; i < 5_000; i++) {
                            long a = rr.below(64), b = (a + 1 + rr.below(63)) % 64, x = 1 + rr.below(50);
                            for (;;) {                                 // retry on a first-committer-wins abort
                                Tx tx = acc.begin();
                                tx.update(a, "balance", balance(tx, a) - x);
                                tx.update(b, "balance", balance(tx, b) + x);
                                if (tx.commit()) break;
                            }
                        }
                    } catch (Exception e) {
                        failure.compareAndSet(null, e);
                    } finally {
                        writers.countDown();
                    }
                });
            }
            Thread.ofPlatform().start(() -> {
                try {
                    start.await();
                    while (running.get()) {
                        Tx tx = acc.begin();
                        long sum = 0;
                        for (long id = 0; id < 64; id++) sum += balance(tx, id);
                        seen[0]++;
                        if (sum != 64_000) seen[1]++;
                    }
                } catch (Exception e) {
                    failure.compareAndSet(null, e);
                } finally {
                    auditorDone.countDown();
                }
            });
            start.await();
            writers.await();
            running.set(false);
            auditorDone.await();
            if (failure.get() != null) throw new IllegalStateException(failure.get());
            Tx fin = acc.begin();
            for (long id = 0; id < 64; id++) finalTotal[mode] += balance(fin, id);
            audits[mode] = seen[0];
            tornAudits[mode] = seen[1];
            aborts[mode] = acc.aborts.sum();
            System.out.printf("  %-44s final total %d (expected 64000) | audits that saw a total != 64000: %d of %d | aborts+retries %d%n",
                    mode == 0 ? "no isolation (latest reads, no validation):" : "snapshot isolation + first committer wins:", finalTotal[mode],
                    tornAudits[mode], audits[mode], aborts[mode]);
        }

        boolean ok = rows[0][1].equals("ok") && rows[1][1].startsWith("rejected") && rows[2][1].startsWith("rejected") && rows[3][1].startsWith("rejected")
                && rows[4][1].startsWith("rejected") && plansAgree && plannedExamined < 5 * 200_000
                && seen1 == 100 && c2 && seen2 == 100 && !c1 && after == 150 && !skewOk[0] && skewOk[1]
                && finalTotal[1] == 64_000 && tornAudits[1] == 0;
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 1–4 deterministic apart from timings; 5 one measured run):**

```text
== 1. Schema validation ==
  insert 1 ann c01 age 30        -> ok
  insert 2 with age 'thirty'     -> rejected: column age expects INT, got String
  insert 3 with no city          -> rejected: column city is NOT NULL
  insert 4 with column email     -> rejected: unknown column email
  insert 1 again                 -> rejected: duplicate primary key 1
== 2. 200,000 people; hash index on city, skip-list index on age; planner vs full scan ==
  city = c07 AND age 30..39      INTERSECT[HASH city=c07 (4142), RANGE age 30..39 (31617)] (659)
                                   -> 659 rows | examined 659 vs 200000 for a full scan | 12.5 ms vs 16.5 ms | same result: true
  city = c07 OR city = c11       UNION[HASH city=c07 (4142), HASH city=c11 (3956)] (8098)
                                   -> 8098 rows | examined 8098 vs 200000 for a full scan | 5.6 ms vs 55.2 ms | same result: true
  age 30..31 AND name = n123456  RANGE age 30..31 (6413) then FILTER
                                   -> 0 rows | examined 6413 vs 200000 for a full scan | 4.2 ms vs 30.1 ms | same result: true
  balance 0..99 (no index)       SCAN
                                   -> 2014 rows | examined 200000 vs 200000 for a full scan | 16.2 ms vs 28.5 ms | same result: true
  city = c07 AND city = c08      INTERSECT[HASH city=c07 (4142), HASH city=c08 (3963)] (0)
                                   -> 0 rows | examined 0 vs 200000 for a full scan | 0.7 ms vs 28.4 ms | same result: true
== 3. MVCC: snapshot reads, first committer wins ==
  T1 reads 100 | T2 writes 150 and commits: true | T1 reads again: 100 (its snapshot) | T1 writes 110: commit false (T2 won) | new snapshot: 150
== 4. Write skew: snapshot isolation lets two doctors both go off call ==
  plain snapshot reads:                  alice commits true, bob commits true -> doctors on call: 0
  reads promoted (getForUpdate):         alice commits true, bob commits false -> doctors on call: 1
== 5. 8 threads x 5,000 transfers over 64 accounts + an auditor summing balances in snapshots ==
  no isolation (latest reads, no validation):  final total 57609 (expected 64000) | audits that saw a total != 64000: 48190 of 48194 | aborts+retries 0
  snapshot isolation + first committer wins:   final total 64000 (expected 64000) | audits that saw a total != 64000: 0 of 76067 | aborts+retries 6496
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// mini_db.cpp - P16: in-memory table, schema validation, hash + ordered indexes, predicate AST + planner, MVCC snapshot isolation
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <expected>
#include <format>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

// ---- schema: a row that doesn't fit cannot be written

using Value = std::variant<std::monostate, i64, std::string>;  // monostate = NULL
using Row = std::vector<Value>;

std::string to_string(const Value& v) {
    return std::visit(overloaded{[](std::monostate) { return std::string("NULL"); }, [](i64 x) { return std::to_string(x); },
                                 [](const std::string& s) { return s; }},
                      v);
}

enum class Type { Int, Text };
enum class Index { None, Hash, Range };
struct Column { std::string name; Type type; bool not_null; Index index; };

struct Schema {
    std::string table;
    std::vector<Column> columns;  // column 0 is the INT primary key
    sz pos(const std::string& col) const {
        for (sz i = 0; i < columns.size(); ++i)
            if (columns[i].name == col) return i;
        return columns.size();
    }
    std::expected<Row, std::string> validate(const std::map<std::string, Value>& values) const {
        for (const auto& [k, v] : values)
            if (pos(k) == columns.size()) return std::unexpected("unknown column " + k);
        Row row(columns.size());
        for (sz i = 0; i < columns.size(); ++i) {
            const Column& c = columns[i];
            const auto it = values.find(c.name);
            const Value v = it == values.end() ? Value{} : it->second;
            if (std::holds_alternative<std::monostate>(v)) {
                if (c.not_null || i == 0) return std::unexpected("column " + c.name + " is NOT NULL");
                continue;
            }
            if (c.type == Type::Int ? !std::holds_alternative<i64>(v) : !std::holds_alternative<std::string>(v))
                return std::unexpected(std::format("column {} expects {}, got {}", c.name, c.type == Type::Int ? "INT" : "TEXT",
                                                   std::holds_alternative<i64>(v) ? "Long" : "String"));
            row[i] = v;
        }
        return row;
    }
};

// ---- predicates: a recursive variant (children behind shared_ptr), evaluated per row and planned against indexes

struct Pred;
using P = std::shared_ptr<const Pred>;
struct Eq { std::string col; Value value; };
struct Between { std::string col; i64 lo, hi; };  // inclusive, INT columns
struct And { P l, r; };
struct Or { P l, r; };
struct Pred { std::variant<Eq, Between, And, Or> v; };

P eq(std::string c, Value v) { return std::make_shared<const Pred>(Pred{Eq{std::move(c), std::move(v)}}); }
P between(std::string c, i64 lo, i64 hi) { return std::make_shared<const Pred>(Pred{Between{std::move(c), lo, hi}}); }
P and_(P l, P r) { return std::make_shared<const Pred>(Pred{And{std::move(l), std::move(r)}}); }
P or_(P l, P r) { return std::make_shared<const Pred>(Pred{Or{std::move(l), std::move(r)}}); }

bool test(const Pred& p, const Schema& s, const Row& row) {
    return std::visit(overloaded{
                          [&](const Eq& e) { return row[s.pos(e.col)] == e.value; },
                          [&](const Between& b) {
                              const auto* v = std::get_if<i64>(&row[s.pos(b.col)]);
                              return v && *v >= b.lo && *v <= b.hi;
                          },
                          [&](const And& a) { return test(*a.l, s, row) && test(*a.r, s, row); },
                          [&](const Or& o) { return test(*o.l, s, row) || test(*o.r, s, row); },
                      },
                      p.v);
}

// ---- MVCC storage: per-row version chains, newest first; versions are immutable once published

struct Version { i64 begin; std::optional<Row> row; const Version* prev; };  // row == nullopt: deleted

const Row* visible(const Version* head, i64 read_ts) {
    for (const Version* v = head; v; v = v->prev)
        if (v->begin <= read_ts) return v->row ? &*v->row : nullptr;  // the newest version committed at or before the snapshot
    return nullptr;
}

struct Slot { std::atomic<const Version*> head{nullptr}; };

/** What the planner decided: candidate row ids (nullopt = full scan) and a human-readable plan. */
struct Access { std::string explain; std::optional<std::unordered_set<i64>> ids; };

class Db {
public:
    const Schema schema;
    const bool isolation;  // false = the naive engine: latest reads, no validation
    std::atomic<i64> clock{0};
    std::atomic<i64> aborts{0};
    std::mutex commit_lock;  // commits are serialized; readers never take it

    Db(Schema s, bool iso) : schema(std::move(s)), isolation(iso) {
        std::scoped_lock warm(commit_lock);
        for (auto& sh : shards_) std::scoped_lock w(sh.m);
    }

    Slot* slot(i64 id) {
        auto& sh = shards_[static_cast<u64>(id) % shards_.size()];
        std::scoped_lock l(sh.m);
        const auto it = sh.map.find(id);
        return it == sh.map.end() ? nullptr : it->second;
    }
    Slot* slot_or_create(i64 id) {  // called under commit_lock only
        auto& sh = shards_[static_cast<u64>(id) % shards_.size()];
        std::scoped_lock l(sh.m);
        auto& s = sh.map[id];
        if (!s) s = &slots_.emplace_back();
        return s;
    }
    std::vector<i64> all_ids() {
        std::vector<i64> out;
        for (auto& sh : shards_) {
            std::scoped_lock l(sh.m);
            for (const auto& [id, s] : sh.map) out.push_back(id);
        }
        return out;
    }
    const Version* publish(i64 begin, std::optional<Row> row, const Version* prev) {  // under commit_lock: the arena never frees
        return &versions_.emplace_back(Version{begin, std::move(row), prev});
    }

    /** Index entries are not versioned: they name every row that ever had the value; visibility + recheck decide. */
    void index(i64 id, const Row& row) {
        std::scoped_lock l(index_m_);
        for (sz i = 0; i < schema.columns.size(); ++i) {
            if (schema.columns[i].index == Index::Hash) hash_[i][row[i]].insert(id);
            if (schema.columns[i].index == Index::Range)
                if (const auto* v = std::get_if<i64>(&row[i])) range_[i][*v].insert(id);
        }
    }

    Access plan(const Pred& p) {
        return std::visit(overloaded{
                              [&](const Eq& e) -> Access {
                                  const sz c = schema.pos(e.col);
                                  std::scoped_lock l(index_m_);
                                  if (schema.columns[c].index == Index::Hash) {
                                      const auto it = hash_[c].find(e.value);
                                      auto ids = it == hash_[c].end() ? std::unordered_set<i64>{} : it->second;
                                      return {std::format("HASH {}={} ({})", e.col, to_string(e.value), ids.size()), std::move(ids)};
                                  }
                                  if (schema.columns[c].index == Index::Range && std::holds_alternative<i64>(e.value)) {
                                      const auto it = range_[c].find(std::get<i64>(e.value));
                                      auto ids = it == range_[c].end() ? std::unordered_set<i64>{} : it->second;
                                      return {std::format("RANGE {}={} ({})", e.col, to_string(e.value), ids.size()), std::move(ids)};
                                  }
                                  return {"SCAN", std::nullopt};
                              },
                              [&](const Between& b) -> Access {
                                  const sz c = schema.pos(b.col);
                                  if (schema.columns[c].index != Index::Range) return {"SCAN", std::nullopt};
                                  std::scoped_lock l(index_m_);
                                  std::unordered_set<i64> ids;
                                  for (auto it = range_[c].lower_bound(b.lo); it != range_[c].end() && it->first <= b.hi; ++it)
                                      ids.insert(it->second.begin(), it->second.end());
                                  return {std::format("RANGE {} {}..{} ({})", b.col, b.lo, b.hi, ids.size()), std::move(ids)};
                              },
                              [&](const And& a) -> Access {
                                  Access l = plan(*a.l), r = plan(*a.r);
                                  if (!l.ids && !r.ids) return {"SCAN", std::nullopt};
                                  if (!l.ids || !r.ids) {
                                      Access& idx = l.ids ? l : r;
                                      return {idx.explain + " then FILTER", std::move(idx.ids)};
                                  }
                                  const auto& small = l.ids->size() <= r.ids->size() ? *l.ids : *r.ids;
                                  const auto& big = &small == &*l.ids ? *r.ids : *l.ids;
                                  std::unordered_set<i64> ids;
                                  for (const i64 id : small)
                                      if (big.contains(id)) ids.insert(id);  // probe the bigger set: O(min)
                                  return {std::format("INTERSECT[{}, {}] ({})", l.explain, r.explain, ids.size()), std::move(ids)};
                              },
                              [&](const Or& o) -> Access {
                                  Access l = plan(*o.l), r = plan(*o.r);
                                  if (!l.ids || !r.ids) return {"SCAN (an OR side has no index)", std::nullopt};
                                  std::unordered_set<i64> ids = *l.ids;
                                  ids.insert(r.ids->begin(), r.ids->end());
                                  return {std::format("UNION[{}, {}] ({})", l.explain, r.explain, ids.size()), std::move(ids)};
                              },
                          },
                          p.v);
    }

private:
    struct Shard {
        std::mutex m;
        std::unordered_map<i64, Slot*> map;
    };
    std::array<Shard, 64> shards_;
    std::deque<Slot> slots_;        // stable addresses
    std::deque<Version> versions_;  // append-only until a vacuum (which would need epoch reclamation, see P4)
    std::mutex index_m_;            // std C++ has no concurrent skip list; Java uses ConcurrentSkipListMap here
    std::map<sz, std::unordered_map<Value, std::unordered_set<i64>>> hash_;
    std::map<sz, std::map<i64, std::unordered_set<i64>>> range_;
};

class Tx {
    Db& db_;
    std::map<i64, std::optional<Row>> writes_;  // id -> new row (nullopt = delete)
    std::set<i64> read_for_update_;             // reads promoted into the conflict check

public:
    const i64 read_ts;
    i64 examined = 0;
    explicit Tx(Db& db) : db_(db), read_ts(db.isolation ? db.clock.load() : INT64_MAX) {}

    /** No copy: committed versions are immutable and never freed, and our own writes live as long as the Tx. */
    const Row* get(i64 id) {
        if (const auto it = writes_.find(id); it != writes_.end()) return it->second ? &*it->second : nullptr;
        const Slot* s = db_.slot(id);
        return s ? visible(s->head.load(std::memory_order_acquire), read_ts) : nullptr;
    }

    const Row* get_for_update(i64 id) {  // SELECT ... FOR UPDATE, optimistic flavour
        read_for_update_.insert(id);
        return get(id);
    }

    std::string insert(const std::map<std::string, Value>& values) {
        auto row = db_.schema.validate(values);
        if (!row) return "rejected: " + row.error();
        const i64 id = std::get<i64>((*row)[0]);
        if (get(id)) return std::format("rejected: duplicate primary key {}", id);
        writes_[id] = std::move(*row);
        return "ok";
    }

    void update(i64 id, const std::string& col, Value v) {
        Row row = *get(id);
        row[db_.schema.pos(col)] = std::move(v);
        writes_[id] = std::move(row);
    }

    std::vector<Row> select(const Pred& p) {
        Access a = db_.plan(p);
        std::vector<i64> ids = a.ids ? std::vector<i64>(a.ids->begin(), a.ids->end()) : db_.all_ids();
        std::vector<Row> out;
        std::unordered_set<i64> seen;
        for (const i64 id : ids) {
            ++examined;
            if (!writes_.empty()) seen.insert(id);  // only needed to merge our own writes below
            if (const Row* r = get(id); r && test(p, db_.schema, *r)) out.push_back(*r);  // index = candidates; visibility + recheck = truth
        }
        for (const auto& [id, w] : writes_)  // our own uncommitted rows are not in the indexes yet
            if (!seen.contains(id) && w && test(p, db_.schema, *w)) out.push_back(*w);
        return out;
    }

    /** First committer wins: abort if anything we wrote (or read for update) was committed after our snapshot. */
    bool commit() {
        std::scoped_lock l(db_.commit_lock);
        if (db_.isolation) {
            std::set<i64> check = read_for_update_;
            for (const auto& [id, w] : writes_) check.insert(id);
            for (const i64 id : check)
                if (const Slot* s = db_.slot(id); s && s->head.load()->begin > read_ts) {
                    db_.aborts.fetch_add(1);
                    return false;
                }
        }
        const i64 ts = db_.clock.load() + 1;
        for (auto& [id, w] : writes_) {
            Slot* s = db_.slot_or_create(id);
            s->head.store(db_.publish(ts, w, s->head.load()), std::memory_order_release);  // publish the version...
            if (w) db_.index(id, *w);
        }
        db_.clock.store(ts);  // ...then the timestamp: new snapshots see all of it
        return true;
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

std::map<std::string, Value> person(i64 id, std::string name, std::optional<std::string> city, i64 age, i64 balance) {
    std::map<std::string, Value> m{{"id", id}, {"name", std::move(name)}, {"age", age}, {"balance", balance}};
    if (city) m["city"] = *city;
    return m;
}

const Schema kPeople{"people",
                     {{"id", Type::Int, true, Index::None},
                      {"name", Type::Text, true, Index::None},
                      {"city", Type::Text, true, Index::Hash},
                      {"age", Type::Int, true, Index::Range},
                      {"balance", Type::Int, true, Index::None}}};
const Schema kAccounts{"accounts", {{"id", Type::Int, true, Index::None}, {"balance", Type::Int, true, Index::None}}};

i64 balance(Tx& t, i64 id) { return std::get<i64>((*t.get(id))[1]); }

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

double ms_between(std::chrono::steady_clock::time_point a, std::chrono::steady_clock::time_point b) {
    return std::chrono::duration<double, std::milli>(b - a).count();
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. Schema validation ==");
    Db small(kPeople, true);
    Tx t0(small);
    auto bad_type = person(2, "bob", "c01", 30, 0);
    bad_type["age"] = std::string("thirty");
    auto unknown = person(4, "dan", "c01", 30, 0);
    unknown["email"] = std::string("d@x");
    const std::vector<std::pair<const char*, std::string>> rows{{"insert 1 ann c01 age 30", t0.insert(person(1, "ann", "c01", 30, 100))},
                                                                {"insert 2 with age 'thirty'", t0.insert(bad_type)},
                                                                {"insert 3 with no city", t0.insert(person(3, "cat", std::nullopt, 30, 0))},
                                                                {"insert 4 with column email", t0.insert(unknown)},
                                                                {"insert 1 again", t0.insert(person(1, "amy", "c02", 40, 0))}};
    for (const auto& [label, out] : rows) std::println("  {:<30} -> {}", label, out);
    t0.commit();

    std::println("== 2. 200,000 people; hash index on city, ordered index on age; planner vs full scan ==");
    Db db(kPeople, true);
    Rng r{16};
    {
        Tx load(db);
        for (i64 i = 0; i < 200'000; ++i) {
            const std::string city = std::format("c{:02}", r.below(50));
            const i64 age = 18 + r.below(63), bal = r.below(10'000);
            load.insert(person(i, std::format("n{}", i), city, age, bal));
        }
        load.commit();
    }
    const std::vector<std::pair<const char*, P>> queries{
        {"city = c07 AND age 30..39", and_(eq("city", std::string("c07")), between("age", 30, 39))},
        {"city = c07 OR city = c11", or_(eq("city", std::string("c07")), eq("city", std::string("c11")))},
        {"age 30..31 AND name = n123456", and_(between("age", 30, 31), eq("name", std::string("n123456")))},
        {"balance 0..99 (no index)", between("balance", 0, 99)},
        {"city = c07 AND city = c08", and_(eq("city", std::string("c07")), eq("city", std::string("c08")))},
    };
    bool plans_agree = true;
    i64 planned_examined = 0;
    const auto ids = db.all_ids();
    for (const auto& [label, q] : queries) {
        Tx planned(db), scan(db);
        const auto t1 = std::chrono::steady_clock::now();
        const sz n = planned.select(*q).size();
        const auto t2 = std::chrono::steady_clock::now();
        sz full = 0;
        for (const i64 id : ids) {
            ++scan.examined;
            if (const Row* row = scan.get(id); row && test(*q, kPeople, *row)) ++full;
        }
        const auto t3 = std::chrono::steady_clock::now();
        plans_agree = plans_agree && n == full;
        planned_examined += planned.examined;
        std::println("  {:<30} {}\n  {:<30}   -> {} rows | examined {} vs {} for a full scan | {:.1f} ms vs {:.1f} ms | same result: {}", label,
                     db.plan(*q).explain, "", n, planned.examined, scan.examined, ms_between(t1, t2), ms_between(t2, t3), n == full);
    }

    std::println("== 3. MVCC: snapshot reads, first committer wins ==");
    Db bank(kAccounts, true);
    {
        Tx setup(bank);
        setup.insert({{"id", i64{1}}, {"balance", i64{100}}});
        setup.commit();
    }
    Tx t1(bank);
    const i64 seen1 = balance(t1, 1);
    Tx t2(bank);
    t2.update(1, "balance", i64{150});
    const bool c2 = t2.commit();
    const i64 seen2 = balance(t1, 1);
    t1.update(1, "balance", seen2 + 10);
    const bool c1 = t1.commit();
    Tx t3(bank);
    const i64 after = balance(t3, 1);
    std::println("  T1 reads {} | T2 writes 150 and commits: {} | T1 reads again: {} (its snapshot) | T1 writes {}: commit {} (T2 won) | new snapshot: {}",
                 seen1, c2, seen2, seen2 + 10, c1, after);

    std::println("== 4. Write skew: snapshot isolation lets two doctors both go off call ==");
    std::array<bool, 2> skew_ok{};
    for (sz mode = 0; mode < 2; ++mode) {
        Db doctors(kAccounts, true);  // id = doctor, column 'balance' = on_call (1/0)
        {
            Tx s(doctors);
            s.insert({{"id", i64{1}}, {"balance", i64{1}}});
            s.insert({{"id", i64{2}}, {"balance", i64{1}}});
            s.commit();
        }
        Tx alice(doctors), bob(doctors);
        i64 on_a = 0, on_b = 0;
        for (i64 id = 1; id <= 2; ++id) {
            on_a += std::get<i64>((*(mode == 1 ? alice.get_for_update(id) : alice.get(id)))[1]);
            on_b += std::get<i64>((*(mode == 1 ? bob.get_for_update(id) : bob.get(id)))[1]);
        }
        if (on_a >= 2) alice.update(1, "balance", i64{0});  // "someone else is on call, I can leave"
        if (on_b >= 2) bob.update(2, "balance", i64{0});
        const bool ca = alice.commit(), cb = bob.commit();
        Tx check(doctors);
        const i64 on_call = balance(check, 1) + balance(check, 2);
        skew_ok[mode] = on_call >= 1;
        std::println("  {:<38} alice commits {}, bob commits {} -> doctors on call: {}", mode == 0 ? "plain snapshot reads:" : "reads promoted (get_for_update):",
                     ca, cb, on_call);
    }

    std::println("== 5. 8 threads x 5,000 transfers over 64 accounts + an auditor summing balances in snapshots ==");
    std::array<i64, 2> final_total{}, torn{}, audits{}, aborts{};
    for (sz mode = 0; mode < 2; ++mode) {
        Db acc(kAccounts, mode == 1);
        {
            Tx s(acc);
            for (i64 id = 0; id < 64; ++id) s.insert({{"id", id}, {"balance", i64{1'000}}});
            s.commit();
        }
        std::atomic<int> writers_done{0};
        i64 seen = 0, seen_torn = 0;  // written by the auditor only; read after parallel() joins
        parallel(9, [&](int t) {
            if (t == 8) {
                while (writers_done.load() < 8) {
                    Tx tx(acc);
                    i64 sum = 0;
                    for (i64 id = 0; id < 64; ++id) sum += balance(tx, id);
                    ++seen;
                    seen_torn += sum != 64'000;
                }
                return;
            }
            Rng rr{200 + static_cast<u64>(t)};
            for (int i = 0; i < 5'000; ++i) {
                const i64 a = rr.below(64), b = (a + 1 + rr.below(63)) % 64, x = 1 + rr.below(50);
                for (;;) {  // retry on a first-committer-wins abort
                    Tx tx(acc);
                    tx.update(a, "balance", balance(tx, a) - x);
                    tx.update(b, "balance", balance(tx, b) + x);
                    if (tx.commit()) break;
                }
            }
            writers_done.fetch_add(1);
        });
        Tx fin(acc);
        for (i64 id = 0; id < 64; ++id) final_total[mode] += balance(fin, id);
        audits[mode] = seen;
        torn[mode] = seen_torn;
        aborts[mode] = acc.aborts.load();
        std::println("  {:<44} final total {} (expected 64000) | audits that saw a total != 64000: {} of {} | aborts+retries {}",
                     mode == 0 ? "no isolation (latest reads, no validation):" : "snapshot isolation + first committer wins:", final_total[mode], torn[mode],
                     audits[mode], aborts[mode]);
    }

    const bool ok = rows[0].second == "ok" && rows[1].second.starts_with("rejected") && rows[2].second.starts_with("rejected") &&
                    rows[3].second.starts_with("rejected") && rows[4].second.starts_with("rejected") && plans_agree && planned_examined < 5 * 200'000 &&
                    seen1 == 100 && c2 && seen2 == 100 && !c1 && after == 150 && !skew_ok[0] && skew_ok[1] && final_total[1] == 64'000 && torn[1] == 0;
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. Schema validation ==
  insert 1 ann c01 age 30        -> ok
  insert 2 with age 'thirty'     -> rejected: column age expects INT, got String
  insert 3 with no city          -> rejected: column city is NOT NULL
  insert 4 with column email     -> rejected: unknown column email
  insert 1 again                 -> rejected: duplicate primary key 1
== 2. 200,000 people; hash index on city, ordered index on age; planner vs full scan ==
  city = c07 AND age 30..39      INTERSECT[HASH city=c07 (4142), RANGE age 30..39 (31617)] (659)
                                   -> 659 rows | examined 659 vs 200000 for a full scan | 6.9 ms vs 44.9 ms | same result: true
  city = c07 OR city = c11       UNION[HASH city=c07 (4142), HASH city=c11 (3956)] (8098)
                                   -> 8098 rows | examined 8098 vs 200000 for a full scan | 7.8 ms vs 62.1 ms | same result: true
  age 30..31 AND name = n123456  RANGE age 30..31 (6413) then FILTER
                                   -> 0 rows | examined 6413 vs 200000 for a full scan | 4.9 ms vs 37.3 ms | same result: true
  balance 0..99 (no index)       SCAN
                                   -> 2014 rows | examined 200000 vs 200000 for a full scan | 52.1 ms vs 34.5 ms | same result: true
  city = c07 AND city = c08      INTERSECT[HASH city=c07 (4142), HASH city=c08 (3963)] (0)
                                   -> 0 rows | examined 0 vs 200000 for a full scan | 1.2 ms vs 43.2 ms | same result: true
== 3. MVCC: snapshot reads, first committer wins ==
  T1 reads 100 | T2 writes 150 and commits: true | T1 reads again: 100 (its snapshot) | T1 writes 110: commit false (T2 won) | new snapshot: 150
== 4. Write skew: snapshot isolation lets two doctors both go off call ==
  plain snapshot reads:                  alice commits true, bob commits true -> doctors on call: 0
  reads promoted (get_for_update):       alice commits true, bob commits false -> doctors on call: 1
== 5. 8 threads x 5,000 transfers over 64 accounts + an auditor summing balances in snapshots ==
  no isolation (latest reads, no validation):  final total 64796 (expected 64000) | audits that saw a total != 64000: 32260 of 32310 | aborts+retries 0
  snapshot isolation + first committer wins:   final total 64000 (expected 64000) | audits that saw a total != 64000: 0 of 43744 | aborts+retries 5579
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. Schema validation ==
  insert 1 ann c01 age 30        -> ok
  insert 2 with age 'thirty'     -> rejected: column age expects INT, got String
  insert 3 with no city          -> rejected: column city is NOT NULL
  insert 4 with column email     -> rejected: unknown column email
  insert 1 again                 -> rejected: duplicate primary key 1
== 2. 200,000 people; hash index on city, ordered index on age; planner vs full scan ==
  city = c07 AND age 30..39      INTERSECT[HASH city=c07 (4142), RANGE age 30..39 (31617)] (659)
                                   -> 659 rows | examined 659 vs 200000 for a full scan | 9.3 ms vs 36.8 ms | same result: true
  city = c07 OR city = c11       UNION[HASH city=c07 (4142), HASH city=c11 (3956)] (8098)
                                   -> 8098 rows | examined 8098 vs 200000 for a full scan | 8.1 ms vs 53.7 ms | same result: true
  age 30..31 AND name = n123456  RANGE age 30..31 (6413) then FILTER
                                   -> 0 rows | examined 6413 vs 200000 for a full scan | 5.1 ms vs 31.3 ms | same result: true
  balance 0..99 (no index)       SCAN
                                   -> 2014 rows | examined 200000 vs 200000 for a full scan | 44.3 ms vs 30.6 ms | same result: true
  city = c07 AND city = c08      INTERSECT[HASH city=c07 (4142), HASH city=c08 (3963)] (0)
                                   -> 0 rows | examined 0 vs 200000 for a full scan | 1.6 ms vs 36.1 ms | same result: true
== 3. MVCC: snapshot reads, first committer wins ==
  T1 reads 100 | T2 writes 150 and commits: true | T1 reads again: 100 (its snapshot) | T1 writes 110: commit false (T2 won) | new snapshot: 150
== 4. Write skew: snapshot isolation lets two doctors both go off call ==
  plain snapshot reads:                  alice commits true, bob commits true -> doctors on call: 0
  reads promoted (get_for_update):       alice commits true, bob commits false -> doctors on call: 1
== 5. 8 threads x 5,000 transfers over 64 accounts + an auditor summing balances in snapshots ==
  no isolation (latest reads, no validation):  final total 60170 (expected 64000) | audits that saw a total != 64000: 30966 of 31025 | aborts+retries 0
  snapshot isolation + first committer wins:   final total 64000 (expected 64000) | audits that saw a total != 64000: 0 of 54036 | aborts+retries 10328
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| Rows | `Map<String, Object>` per row | Typed columns, checked on insert | Schema validation *is* the row constructor; unknown columns rejected; PK enforced in the snapshot and at commit |
| Queries | Loop + `if` | Index lookup for equality | Predicate AST → plan (intersect smaller-probes-bigger, union, filter, scan), EXPLAIN, results asserted equal to a full scan |
| Indexes | One `HashMap` | Hash + `TreeMap` | Concurrent hash + skip list (Java); entries unversioned, so recheck against the visible version |
| Concurrency | `synchronized` table | Table `ReadWriteLock` | MVCC: lock-free snapshot readers, first-committer-wins commits, publication order (versions/indexes then clock), write skew understood and fixed |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Versions pile up" | Vacuum: track the oldest active `readTs` (a low watermark) and unlink versions older than the newest one visible to it. In C++, readers walk raw pointers, so freeing needs epoch-based reclamation ([P4](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/04-problem-04-in-memory-kafka-pubsub-broker-offset-tracking-and-groups.md)) |
| "Stale index entries slow queries" | Vacuum also prunes index entries whose row no longer has the value at any live version |
| "ORDER BY age LIMIT 10" | Walk the skip list in order, recheck visibility, stop after 10: index order instead of a sort |
| "Range on TEXT" | Generalize the range index key to `Comparable` (Java) or `Value` with `operator<=>` (C++) |
| "Commit lock is a bottleneck" | Per-row write intents (locks) acquired in id order during the transaction, plus a timestamp oracle (`AtomicLong`) at commit; validation stays per row |
| "Crash safety" | Append the write set to a WAL and fsync before publishing; recovery replays the WAL into version chains |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Your index says row 17 matches, but row 17 doesn't. Bug?"</b></summary>

**L5:** "The index is out of date."

**Why it fails:** that answer treats the index as the truth. Under MVCC, index entries outlive the versions that put them there.

**L7 defence:** "The index produces candidates. For each candidate I fetch the version visible to my snapshot and recheck the predicate; the listing asserts every result equals a full scan of the same snapshot. Vacuum later prunes entries no live version needs."
</details>

<details>
<summary><b>Q2 🔥 "Snapshot isolation is serializable, right?"</b></summary>

**L5:** "Yes, every transaction sees a consistent snapshot."

**Why it fails:** write skew. Both doctors went off call, because their writes touched different rows.

**L7 defence:** "SI prevents lost updates (first committer wins) but not write skew. Fixes: SSI, which tracks rw-antidependencies; `SELECT … FOR UPDATE` on what the decision read (shown: the second doctor aborts); or materialize the conflict on a shared row."
</details>

<details>
<summary><b>Q3 ⚡ "`city = X AND age BETWEEN …`: which index?"</b></summary>

**L5:** "The first one in the WHERE clause."

**Why it fails:** clause order is not selectivity.

**L7 defence:** "Both: iterate the smaller candidate set and probe the larger, O(min); 4,142 ∩ 31,617 gives 659 rows examined instead of 200,000. With statistics, if one side is tiny I'd skip the intersection and just filter. An `OR` with an unindexed side forces a scan."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| Wrong rows from an index | No recheck against the visible version | Candidates → visibility → predicate |
| Reader sees half a commit | Clock advanced before versions/indexes were published | Publish, then advance the clock |
| Lost update | No write-write validation | First-committer-wins (or row write locks) |
| Invariant across rows broken under SI | Write skew | SSI / `FOR UPDATE` / materialized conflict |
| Memory grows forever | No vacuum | Low watermark of active snapshots; EBR in C++ |

- [ ] Schema validation is the only path to storage.
- [ ] Planner: AND intersects smaller-into-bigger, OR unions, scan when unavoidable; EXPLAIN; results == full scan.
- [ ] MVCC: readers lock-free; commit validates and publishes in the right order.
- [ ] Write skew demonstrated and closed.

## 10. References

- Berenson et al., *A Critique of ANSI SQL Isolation Levels* (snapshot isolation, write skew). <https://doi.org/10.1145/223784.223785>
- Ports and Grittner, *Serializable Snapshot Isolation in PostgreSQL* (VLDB 2012). <https://doi.org/10.14778/2367502.2367523>
- PostgreSQL documentation, *Transaction Isolation*. <https://www.postgresql.org/docs/current/transaction-iso.html>
- Java `ConcurrentSkipListMap`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/ConcurrentSkipListMap.html>
- In this KB: [P4 Epoch-based reclamation](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/04-problem-04-in-memory-kafka-pubsub-broker-offset-tracking-and-groups.md) · [P13 First committer wins on a ledger](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/03-problem-13-double-entry-wallet-ledger-idempotency-and-ordered-locking.md) · [02.2 Specification DSL](../02-Design-Patterns-Reimagined-for-High-Throughput-Java/02-strategy-chain-of-responsibility-decorator-and-specification-dsl.md)
