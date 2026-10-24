# 5.2 · JPA / Hibernate Internals — Persistence Context, Dirty Checking, Flush, IDs, Proxies, Second-Level Cache

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Jakarta Persistence 3.2 specification; Hibernate ORM 7 User Guide and Migration Guide (7.0); Hibernate source (`ActionQueue`, `DefaultFlushEntityEventListener`, `PooledOptimizer`); Vlad Mihalcea, *High-Performance Java Persistence*.
> **Verified stack:** Hibernate ORM **7.4.13.Final** (via the Spring Boot 4.1.2 BOM), Jakarta Persistence 3.2, PostgreSQL 18.6 (embedded), JDBC statements counted with `datasource-proxy` 1.11.1. Samples bootstrap JPA **without XML** using JPA 3.2's `PersistenceConfiguration` (Hibernate's `HibernatePersistenceConfiguration`).

---

## 1. The mental model 🔥

```
 EntityManager / Session  ═══ a unit of work, NOT thread-safe, usually = one transaction
   │
   ├── Persistence context (first-level cache)
   │     identity map: (EntityClass, id) → managed instance        ← "repeatable read" of entities within the session
   │     entity entries: status (MANAGED/DELETED/…), LOADED STATE SNAPSHOT (an Object[] copy of every column value)
   │     collection entries: snapshots of collections
   │
   ├── ActionQueue (write-behind): inserts, updates, deletes, collection actions queued until FLUSH
   │
   └── JDBC coordinator → borrowed Connection (from Hikari) while a transaction is active
```

| Entity state | How you get there | Tracked? | Flush effect |
|---|---|---|---|
| **Transient / new** | `new Customer()` | No | None |
| **Managed** | `persist()`, `find()`, query results, `merge()` result | **Yes**: snapshot + dirty checking | INSERT/UPDATE when needed |
| **Detached** | Session closed, `detach()`, `clear()`, serialization | No (changes are ignored) | None, unless `merge()`d |
| **Removed** | `remove(managed)` | Yes | DELETE at flush |

**Flush** synchronizes the context to the DB (it doesn't commit). `FlushModeType.AUTO` (the default) flushes **before commit**, and **before queries whose results could be affected** by pending changes. `COMMIT` flushes only at commit (Hibernate also has `MANUAL`).

### 1.1 Runnable: identity map, dirty checking, proxies, lazy loading, merge

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.jpa;

import ch.qos.logback.classic.Level;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.ArrayList;
import java.util.List;
import org.hibernate.SessionFactory;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.stat.Statistics;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class PersistenceContextBasics {
    @Entity(name = "Customer") @Table(name = "customer")
    public static class Customer {
        @Id @GeneratedValue(strategy = GenerationType.SEQUENCE) Long id;
        @Column(unique = true) String email;
        String tier = "BRONZE";
        @OneToMany(mappedBy = "customer") List<PurchaseOrder> orders = new ArrayList<>();
        protected Customer() {}
        Customer(String email) { this.email = email; }
    }
    @Entity(name = "PurchaseOrder") @Table(name = "purchase_order")
    public static class PurchaseOrder {
        @Id @GeneratedValue(strategy = GenerationType.SEQUENCE) Long id;
        @ManyToOne(fetch = FetchType.LAZY) Customer customer;
        protected PurchaseOrder() {}
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start();
             EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo")
                 .managedClass(Customer.class).managedClass(PurchaseOrder.class)
                 .jdbcUrl(pg.getJdbcUrl("postgres", "postgres")).jdbcCredentials("postgres", "postgres")
                 .schemaToolingAction(Action.CREATE_DROP)
                 .property("hibernate.generate_statistics", true)
                 .createEntityManagerFactory()) {
            SessionFactory sf = emf.unwrap(SessionFactory.class);
            Statistics stats = sf.getStatistics();
            Long id = sf.fromTransaction(s -> { Customer c = new Customer("ann@x.io"); s.persist(c); return c.id; });

            stats.clear();
            sf.inTransaction(s -> {
                Customer a = s.find(Customer.class, id), b = s.find(Customer.class, id);
                System.out.println("1. identity map: same instance=" + (a == b) + ", SELECTs=" + stats.getPrepareStatementCount());
                a.tier = "GOLD";                                          // no save()/update() call needed
            });
            System.out.println("2. dirty checking: UPDATEs at commit=" + stats.getEntityUpdateCount());

            sf.inTransaction(s -> {
                Customer ref = s.getReference(Customer.class, id);          // no SELECT yet
                System.out.println("3. getReference: class=" + ref.getClass().getSimpleName() + ", initialized=" + Persistence.getPersistenceUtil().isLoaded(ref));
            });

            Customer detached = sf.fromTransaction(s -> s.find(Customer.class, id));
            try { detached.orders.size(); }
            catch (org.hibernate.LazyInitializationException e) { System.out.println("4. " + e.getMessage()); }

            detached.tier = "PLATINUM";                                    // change on a DETACHED instance: ignored…
            Customer merged = sf.fromTransaction(s -> s.merge(detached));  // …until merged (copied onto a managed instance)
            System.out.println("5. merge returns a different instance=" + (merged != detached) + ", tier now=" + sf.fromTransaction(s -> s.find(Customer.class, id).tier));

            try {
                sf.inTransaction(s -> {
                    s.remove(s.find(Customer.class, id));
                    s.persist(new Customer("ann@x.io"));                   // re-create with the SAME unique email
                });
            } catch (RuntimeException e) {
                Throwable root = e; while (root.getCause() != null) root = root.getCause();
                System.out.println("6. delete-then-insert failed: " + root.getMessage().lines().findFirst().orElse("") + "  ← INSERTs flush before DELETEs");
            }
        }
    }
}
```

Output (verified):

```
1. identity map: same instance=true, SELECTs=1
2. dirty checking: UPDATEs at commit=1
3. getReference: class=PersistenceContextBasics$Customer$HibernateProxy, initialized=false
4. Cannot lazily initialize collection of role 'demo.jpa.PersistenceContextBasics$Customer.orders' with key '1' (no session)
5. merge returns a different instance=true, tier now=PLATINUM
6. delete-then-insert failed: ERROR: duplicate key value violates unique constraint "customer_email_key"  ← INSERTs flush before DELETEs
```

**What each line teaches:**

1. Within a persistence context, an entity is loaded **once**. The second `find` is a map lookup.
2. **Dirty checking:** at flush, Hibernate compares every managed entity's current field values with its **loaded-state snapshot**, field by field, and issues UPDATEs for changes. There's no `save()` call. (Hibernate 7 **removed** the legacy `Session.save()`/`update()`/`saveOrUpdate()`; they no longer compile. Use `persist`/`merge`.)
3. `getReference` returns an **uninitialized proxy** (a ByteBuddy-generated subclass, `…$HibernateProxy`), which hits the DB only when a non-id property is accessed.
4. Accessing a lazy association after the session closed throws `LazyInitializationException`. The fix is **fetching what the use case needs** (fetch joins and entity graphs, [5.3](03-Performance-NPlus1-Cartesian-Projections.md)), not open-session-in-view and not `hibernate.enable_lazy_load_no_trans`.
5. `merge` copies a detached instance's state onto a managed instance (loading it if needed) and **returns that managed copy**. The argument stays detached, a classic bug when code keeps using the old reference.
6. **Flush order is fixed by the `ActionQueue`, not by your call order:** orphan removals → **inserts** → updates → collection changes → **deletes**. Deleting and re-inserting a row with the same unique key in one flush violates the constraint. Fix: `flush()` after the delete, or update the existing row instead.

---

## 2. Dirty checking: cost and alternatives ⚡

* Each managed entity has an `EntityEntry` and a **loaded-state snapshot** (`Object[]` of column values). For immutable field types (`String`, boxed numbers, `java.time`) the snapshot holds **references to the same objects**, so it is cheaper than "a second copy of the data". Measured below: read-only saved only ~2 MB for 50,000 entities.
* **The real cost is that flushes are O(managed entities)**, and with `FlushMode.AUTO` a flush happens **before every query that touches affected tables**. A session holding 50,000 entities that then runs queries in a loop dirty-checks 50,000 entities **per query**.
* Mitigations: keep sessions small (`flush(); clear();` in loops); read-only sessions or queries (`session.setDefaultReadOnly(true)`, the hint `org.hibernate.readOnly`, Spring `@Transactional(readOnly = true)`, which Spring propagates to Hibernate as a read-only session and sets `FlushMode.MANUAL`); DTO projections that create no managed entities at all ([5.3 §4](03-Performance-NPlus1-Cartesian-Projections.md#4-projections-interface-vs-dto-vs-tuple-)); `StatelessSession` for batch jobs.
* **Bytecode enhancement** (Hibernate's build-time plugin): entities track their own dirty fields (`$$_hibernate_trackChange`), so flush needn't compare snapshots. It also enables lazy *attributes* (basic fields, LOBs) and lazy `@OneToOne` on the non-owning side. The cost is a build step plus instrumented classes.

### 2.1 Runnable: what a big persistence context really costs

<!-- run: javac cp=@p5 jvm="-Xmx1g" timeout=400 -->
```java
package demo.jpa;

import ch.qos.logback.classic.Level;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.List;
import java.util.function.Consumer;
import org.hibernate.FlushMode;
import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class DirtyCheckingCost {
    @Entity(name = "Reading") @Table(name = "reading")
    public static class Reading {
        @Id Long id; String sensor; double value; String unit; String note;
        protected Reading() {}
    }
    public record ReadingView(Long id, String sensor, double value, String unit, String note) {}

    static final int ROWS = 50_000, QUERIES = 500;

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start();
             EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo").managedClass(Reading.class)
                 .jdbcUrl(pg.getJdbcUrl("postgres", "postgres")).jdbcCredentials("postgres", "postgres")
                 .schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
            SessionFactory sf = emf.unwrap(SessionFactory.class);
            sf.inTransaction(s -> s.createNativeMutationQuery(
                "insert into reading(id, sensor, value, unit, note) select g, 'sensor-' || (g % 100), random(), 'kWh', repeat('n', 40) "
                + "from generate_series(1, " + ROWS + ") g").executeUpdate());

            for (int round = 0; round < 2; round++) {                       // round 0 = JIT warm-up, not printed
                boolean print = round == 1;
                if (print) System.out.printf("%-38s %8s %12s %9s %16s%n", "50,000 rows loaded as…", "load ms", "retained MB", "flush µs", QUERIES + " queries ms");
                measure(sf, print, "managed entities (FlushMode.AUTO)", s -> {}, false, false);
                measure(sf, print, "setDefaultReadOnly(true)", s -> s.setDefaultReadOnly(true), false, false);
                measure(sf, print, "read-only + FlushMode.MANUAL", s -> {
                    s.setDefaultReadOnly(true); s.setHibernateFlushMode(FlushMode.MANUAL); }, false, false);
                measure(sf, print, "managed entities, then clear()", s -> {}, true, false);
                measure(sf, print, "DTO record projection", s -> {}, false, true);
            }
        }
    }

    static void measure(SessionFactory sf, boolean print, String label, Consumer<Session> setup, boolean clear, boolean dto) {
        long base = heapAfterGc();
        sf.inTransaction(s -> {
            setup.accept(s);
            long t0 = System.nanoTime();
            List<?> rows = dto
                ? s.createSelectionQuery("select r.id, r.sensor, r.value, r.unit, r.note from Reading r", ReadingView.class).getResultList()
                : s.createSelectionQuery("from Reading", Reading.class).getResultList();
            long loadMs = (System.nanoTime() - t0) / 1_000_000;
            if (clear) s.clear();                                           // rows stay on the heap, but detached
            long retainedMb = (heapAfterGc() - base) >> 20;
            long t1 = System.nanoTime();
            s.flush();                                                      // explicit flush: dirty-check every managed entity
            long flushUs = (System.nanoTime() - t1) / 1_000;
            long t2 = System.nanoTime();
            for (int q = 0; q < QUERIES; q++)                               // each JPQL query on "reading" may auto-flush first
                s.createSelectionQuery("select r.sensor from Reading r where r.id = :id", String.class)
                 .setParameter("id", (long) q + 1).getSingleResult();
            long queriesMs = (System.nanoTime() - t2) / 1_000_000;
            if (rows.size() != ROWS) throw new IllegalStateException();
            if (print) System.out.printf("%-38s %8d %12d %,9d %16d%n", label, loadMs, retainedMb, flushUs, queriesMs);
        });
    }

    static long heapAfterGc() { System.gc(); Runtime r = Runtime.getRuntime(); return r.totalMemory() - r.freeMemory(); }
}
```

One measured run:

```
50,000 rows loaded as…                  load ms  retained MB  flush µs   500 queries ms
managed entities (FlushMode.AUTO)           135           26    10,678             3505
setDefaultReadOnly(true)                    147           24     5,356             2491
read-only + FlushMode.MANUAL                119           24     6,441               89
managed entities, then clear()              112           14        60               78
DTO record projection                       105           12        68               82
```

How to read it:

* **Loading isn't the problem.** All five variants load 50,000 rows in roughly the same 100–150 ms.
* **Bookkeeping memory ≈ the data itself.** Managed entities retain 26 MB. After `clear()` the same detached objects retain 14 MB, so `EntityEntry`, `EntityKey`, the identity map and the snapshots cost about 12 MB, or ~250 bytes per entity. The record projection retains 12 MB. Read-only only drops the snapshots (−2 MB), because snapshots point at the same immutable `String`/`Long` objects.
* **Auto-flush is the killer.** 500 primary-key lookups take **3.5 s** with 50,000 managed entities and **~80 ms** without them. Each JPQL query first runs an auto-flush that walks every managed entity (about 7 ms per query here). That is 45× slower for identical SQL.
* `setDefaultReadOnly(true)` alone skips the field comparison but **still walks the entries on every auto-flush** (2.5 s). Read-only **plus** `FlushMode.MANUAL`, which is what Spring's `@Transactional(readOnly = true)` sets on a Hibernate session ([5.4](04-Transactions-Isolation-Locking-Spring-Transactional.md)), removes the per-query cost.
* An explicit `flush()` still walks all managed entities in every mode (5–11 ms here), which is why commit becomes slow in big transactions.

**Production lesson:** a request or batch step that loads thousands of entities and then runs queries in a loop has a hidden O(entities × queries) cost. Profilers show it as `DefaultAutoFlushEventListener` / `AbstractFlushingEventListener.flushEntities`. Fix it with DTO projections, read-only transactions, `clear()` between chunks, or `StatelessSession`.

---

## 3. Identifier generation & JDBC batching 🔥

| Strategy | How IDs are obtained | Batch inserts? | Notes |
|---|---|---|---|
| `IDENTITY` (`bigserial`, auto-increment) | The DB assigns it during INSERT | **No.** Hibernate must execute each INSERT immediately to learn the ID | Simple; kills write batching |
| `SEQUENCE` + **pooled optimizer** (`allocationSize = 50`, the default) | One `nextval` per 50 IDs; the rest are assigned in memory | **Yes** | The default `@GeneratedValue(strategy = SEQUENCE)` uses `<entity>_SEQ` with increment 50 |
| `UUID` (`@UuidGenerator`, `GenerationType.UUID`) | In memory | Yes | Random UUIDv4 keys fragment B-tree indexes. Prefer time-ordered UUIDv7 (Hibernate 6.5+ `@UuidGenerator(style = VERSION_7)`) |
| `TABLE` | A row-locked table | Yes, but slow | Avoid |
| Assigned (natural key) | You set it | Yes | `persist` vs `merge` semantics matter (`merge` must SELECT first) |

Enable batching with `hibernate.jdbc.batch_size=50`, `hibernate.order_inserts=true`, `hibernate.order_updates=true` (group statements by table so batches don't break), and on PostgreSQL also `reWriteBatchedInserts=true` ([5.1 §1.1](01-JDBC-HikariCP-Connection-Pooling.md#11-runnable-batching-and-fetch-size-on-real-postgresql)).

### 3.1 Runnable: IDENTITY vs SEQUENCE vs `StatelessSession`, counted at the JDBC layer

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.jpa;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.concurrent.atomic.AtomicInteger;
import javax.sql.DataSource;
import net.ttddyy.dsproxy.listener.QueryExecutionListener;
import net.ttddyy.dsproxy.support.ProxyDataSourceBuilder;
import net.ttddyy.dsproxy.ExecutionInfo;
import net.ttddyy.dsproxy.QueryInfo;
import org.hibernate.SessionFactory;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class IdsAndBatching {
    @Entity(name = "IdentityRow") @Table(name = "identity_row")
    public static class IdentityRow { @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id; String v; }
    @Entity(name = "SequenceRow") @Table(name = "sequence_row")
    public static class SequenceRow { @Id @GeneratedValue(strategy = GenerationType.SEQUENCE) Long id; String v; }

    static final AtomicInteger roundTrips = new AtomicInteger(), batchedStatements = new AtomicInteger();

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres") + "&reWriteBatchedInserts=true");
            DataSource counting = ProxyDataSourceBuilder.create(new HikariDataSource(hc))
                .listener(new QueryExecutionListener() {                       // one callback per JDBC execute*/executeBatch
                    public void beforeQuery(ExecutionInfo e, java.util.List<QueryInfo> q) { }
                    public void afterQuery(ExecutionInfo e, java.util.List<QueryInfo> q) {
                        roundTrips.incrementAndGet();
                        if (e.isBatch()) batchedStatements.addAndGet(e.getBatchSize());
                    }
                }).build();
            try (EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo")
                    .managedClass(IdentityRow.class).managedClass(SequenceRow.class)
                    .property("hibernate.connection.datasource", counting)
                    .property("hibernate.jdbc.batch_size", 50).property("hibernate.order_inserts", true)
                    .schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
                SessionFactory sf = emf.unwrap(SessionFactory.class);
                run("IDENTITY, Session", () -> sf.inTransaction(s -> { for (int i = 0; i < 5000; i++) { var r = new IdentityRow(); r.v = "v" + i; s.persist(r); } }));
                run("SEQUENCE (pooled, 50), Session", () -> sf.inTransaction(s -> { for (int i = 0; i < 5000; i++) { var r = new SequenceRow(); r.v = "v" + i; s.persist(r); } }));
                run("SEQUENCE, StatelessSession", () -> sf.inStatelessTransaction(s -> { for (int i = 0; i < 5000; i++) { var r = new SequenceRow(); r.v = "v" + i; s.insert(r); } }));
                run("StatelessSession + setJdbcBatchSize", () -> sf.inStatelessTransaction(s -> {
                    s.setJdbcBatchSize(50);                                    // stateless sessions don't batch unless told to
                    for (int i = 0; i < 5000; i++) { var r = new SequenceRow(); r.v = "v" + i; s.insert(r); } }));
                run("StatelessSession.insertMultiple", () -> sf.inStatelessTransaction(s -> {
                    var rows = new java.util.ArrayList<SequenceRow>();
                    for (int i = 0; i < 5000; i++) { var r = new SequenceRow(); r.v = "v" + i; rows.add(r); }
                    s.insertMultiple(rows); }));
            }
        }
    }

    static void run(String label, Runnable work) {
        roundTrips.set(0); batchedStatements.set(0);
        long t0 = System.nanoTime();
        work.run();
        System.out.printf("%-32s 5,000 inserts → %,5d JDBC round trips (%,5d statements sent in batches) %5d ms%n",
            label, roundTrips.get(), batchedStatements.get(), (System.nanoTime() - t0) / 1_000_000);
    }
}
```

One measured run:

```
IDENTITY, Session                5,000 inserts → 5,000 JDBC round trips (    0 statements sent in batches)  1776 ms
SEQUENCE (pooled, 50), Session   5,000 inserts →   201 JDBC round trips (5,000 statements sent in batches)   262 ms
SEQUENCE, StatelessSession       5,000 inserts → 5,100 JDBC round trips (    0 statements sent in batches)   901 ms
StatelessSession + setJdbcBatchSize 5,000 inserts →   201 JDBC round trips (5,000 statements sent in batches)   105 ms
StatelessSession.insertMultiple  5,000 inserts →   201 JDBC round trips (5,000 statements sent in batches)    86 ms
```

What it shows:

* **IDENTITY disables batching entirely.** Hibernate must execute each INSERT to learn the generated key, so 5,000 inserts take 5,000 round trips, even with `hibernate.jdbc.batch_size=50`.
* **SEQUENCE with the pooled optimizer** needs 100 batches of 50 plus about 100 `nextval` calls (one per 50 IDs; the pooled optimizer makes one extra call on first use). That is ~200 round trips in total and about 7× faster.
* **`StatelessSession` does not batch by default.** Since Hibernate 7, `hibernate.jdbc.batch_size` "has no effect on a stateless session" (`StatelessSession` Javadoc), so each `insert()` executes immediately: 5,000 INSERTs + 100 `nextval` = 5,100 round trips. It batches only after `setJdbcBatchSize(n)` (which delays execution and so weakens the stateless session's synchronous semantics) or through the explicit `insertMultiple`/`updateMultiple`/`deleteMultiple`/`upsertMultiple(list)` methods (`@Incubating`, since 7.0), which the Javadoc names as the preferred approach. Batched, it is the fastest option, because there is no persistence context, snapshots or dirty checking.
* 🎓 **Migration trap:** a Hibernate 6 batch job built on `StatelessSession` + `hibernate.jdbc.batch_size` silently becomes ~10× slower on Hibernate 7 (901 ms vs 86–105 ms here) without failing.

---

## 4. Lazy loading, proxies and fetch types ⚡

| Mapping | JPA default fetch | Recommendation |
|---|---|---|
| `@ManyToOne`, `@OneToOne` | **EAGER** | Set **`LAZY`** explicitly. EAGER to-ones cause hidden extra SELECTs or joins everywhere |
| `@OneToMany`, `@ManyToMany` | LAZY | Keep it lazy, and fetch per use case |
| `@ElementCollection` | LAZY | Same |
| Basic fields | EAGER | Lazy basic fields need bytecode enhancement |

* A lazy to-one is a **proxy subclass** (ByteBuddy). `getClass()` returns the proxy class, `instanceof` checks against subclasses can fail with inheritance, and `final` entity classes or methods prevent proxying. Use `Hibernate.unproxy(x)`, `Hibernate.getClass(x)`, `Hibernate.isInitialized(x)`.
* A lazy collection is a `PersistentBag`/`PersistentSet`/`PersistentList` wrapper, initialized on first access (one SELECT), or batch-initialized with `@BatchSize`/`hibernate.default_batch_fetch_size` ([5.3 §2](03-Performance-NPlus1-Cartesian-Projections.md#2-the-n1-select-problem-)).
* **Open Session in View** (Spring Boot's `spring.jpa.open-in-view=true` default) keeps the persistence context **and its DB connection** open through view rendering and JSON serialization, so lazy loading "works". The cost is connections held for the whole request and N+1 queries hidden in serializers. Boot logs a warning at startup when you don't set it explicitly. **Set it to `false`** in APIs ([5.4 §6](04-Transactions-Isolation-Locking-Spring-Transactional.md)).

### 4.1 Entity `equals`/`hashCode`

Entities are mutable, have DB-generated IDs, and get proxied. Safe options:

1. A **natural business key** (immutable unique column, e.g. email or ISBN) for `equals`/`hashCode`.
2. **ID-based `equals` plus a constant `hashCode`** (`getClass().hashCode()`): correct across the transient→persistent transition, at the cost of hash buckets degrading for large sets of transient entities.
3. Never use `@Data`-style all-fields equality (lazy collections trigger loads and recursion), and never use an ID-based `hashCode` that changes when `persist` assigns the ID (the entity gets lost in a `HashSet`).
4. Compare with `instanceof` (or `Hibernate.getClass`), not `getClass() ==`, because of proxies.

---

## 5. Second-level cache (L2C) ⚡

```
find(Customer, 42):  1st-level (persistence context) ─miss─► 2nd-level (SessionFactory-wide, e.g. Caffeine/JCache, Infinispan,
                                                              Ehcache, Hazelcast) ─miss─► SELECT
L2C stores DEHYDRATED state (column values), not entity instances. Each session builds its own managed instance.
```

| Concurrency strategy | Semantics | Use for |
|---|---|---|
| `READ_ONLY` | Never updated (an update throws) | Reference data (countries, currencies) |
| `NONSTRICT_READ_WRITE` | Invalidate on update; brief staleness possible | Rarely updated, staleness tolerated |
| `READ_WRITE` | Soft locks during updates; consistent for a single JVM or a correctly clustered cache | Mostly-read entities |
| `TRANSACTIONAL` | XA/JTA cache transactions | JTA environments only |

* **The query cache** caches result **IDs** for a query plus its parameters, invalidated whenever *any* involved table changes (timestamps region). It's only useful for queries over rarely changing tables.
* **Distributed deployments:** a local cache per pod plus writes on other pods means **stale data**, unless you use a clustered or invalidating provider. Many teams skip L2C and use explicit application caches (Caffeine, Redis) with a defined invalidation strategy instead.
* Collections need their own cache regions (`@Cache` on the association).

### 5.1 Runnable: L2C hits with Caffeine (JCache)

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.jpa;

import ch.qos.logback.classic.Level;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import org.hibernate.SessionFactory;
import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.stat.Statistics;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class SecondLevelCache {
    @Entity(name = "Currency") @Table(name = "currency")
    @Cacheable @Cache(usage = CacheConcurrencyStrategy.READ_WRITE, region = "currency")
    public static class Currency {
        @Id String code; String name; int fractionDigits;
        protected Currency() {}
        Currency(String c, String n, int f) { code = c; name = n; fractionDigits = f; }
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start();
             EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo").managedClass(Currency.class)
                 .jdbcUrl(pg.getJdbcUrl("postgres", "postgres")).jdbcCredentials("postgres", "postgres")
                 .schemaToolingAction(Action.CREATE_DROP)
                 .sharedCacheMode(SharedCacheMode.ENABLE_SELECTIVE)
                 .property("hibernate.cache.region.factory_class", "jcache")
                 .property("hibernate.javax.cache.provider", "com.github.benmanes.caffeine.jcache.spi.CaffeineCachingProvider")
                 .property("hibernate.javax.cache.missing_cache_strategy", "create")
                 .property("hibernate.generate_statistics", true)
                 .createEntityManagerFactory()) {
            SessionFactory sf = emf.unwrap(SessionFactory.class);
            sf.inTransaction(s -> { s.persist(new Currency("EUR", "Euro", 2)); s.persist(new Currency("JPY", "Yen", 0)); });
            Statistics st = sf.getStatistics();
            sf.getCache().evictAll();                     // persist() already cached the rows at commit (READ_WRITE); start cold
            st.clear();
            for (int session = 1; session <= 3; session++) {
                long selectsBefore = st.getPrepareStatementCount();
                String name = sf.fromTransaction(s -> s.find(Currency.class, "JPY").name);
                System.out.printf("session %d: find(JPY)=%s  SELECTs=%d  L2C hits=%d misses=%d puts=%d%n", session, name,
                    st.getPrepareStatementCount() - selectsBefore, st.getSecondLevelCacheHitCount(), st.getSecondLevelCacheMissCount(), st.getSecondLevelCachePutCount());
            }
            sf.inTransaction(s -> s.find(Currency.class, "JPY").name = "Japanese Yen");      // READ_WRITE: cache updated after commit
            System.out.println("after update, new session sees: " + sf.fromTransaction(s -> s.find(Currency.class, "JPY").name)
                + " (hits=" + st.getSecondLevelCacheHitCount() + ")");
        }
    }
}
```

Output (verified):

```
session 1: find(JPY)=Yen  SELECTs=1  L2C hits=0 misses=1 puts=1
session 2: find(JPY)=Yen  SELECTs=0  L2C hits=1 misses=1 puts=1
session 3: find(JPY)=Yen  SELECTs=0  L2C hits=2 misses=1 puts=1
after update, new session sees: Japanese Yen (hits=4)
```

* Session 1 misses the cold cache, issues one SELECT and puts the dehydrated state into the `currency` region. Sessions 2 and 3 are served from the cache with **zero** SQL.
* The final line reports `hits=4`: the update transaction's `find` was a hit (3), and the new session's `find` after commit was a hit (4) **that returned the new name**. With `READ_WRITE`, the committed update replaces the cached entry (no stale read, no extra SELECT) in this single JVM.
* `persist()` already populates a `READ_WRITE` region at commit. That is why the demo calls `evictAll()` first: without it, session 1 would also be a hit.

---

## 6. Production failure modes & diagnostics (persistence context)

| Symptom | Cause | Fix |
|---|---|---|
| `LazyInitializationException` | Accessing lazy state after the session closed | Fetch per use case (join fetch, entity graph, DTO projection) |
| Changes "not saved" | Modified a **detached** instance, or kept using the `merge` argument instead of its return value | Modify managed instances; use the return value of `merge` |
| Unexpected UPDATEs | Dirty checking on entities you only read (`@PreUpdate`/converters producing new values, mutable `@Embeddable` without equals) | Read-only transactions; immutable value types; correct `equals` for embeddables and converters |
| Unique-constraint violation on delete + re-insert | ActionQueue order: inserts before deletes | `flush()` after the delete, or update in place |
| Slow commit after big reads | Flush walks thousands of managed entities | Read-only, projections, `StatelessSession`, `clear()` in loops |
| Every query slow inside one long transaction, fast in isolation | **Auto-flush** before each JPQL query walks every managed entity (measured 3.5 s vs 80 ms for 500 lookups) | Read-only + `FlushMode.MANUAL` (Spring `readOnly = true`), DTO projections, `clear()` between chunks; profile for `AbstractFlushingEventListener.flushEntities` |
| Bulk insert slow, no batching | `IDENTITY` IDs, no `batch_size`, unordered inserts; on Hibernate 7, a `StatelessSession` (ignores `batch_size`) | Sequences (pooled), `jdbc.batch_size`, `order_inserts`; `insertMultiple` or `setJdbcBatchSize` for stateless sessions |
| Memory growth in batch jobs | The persistence context grows without bound | `flush(); clear();` every N rows, or `StatelessSession` |
| Stale reads in clustered apps | Local L2C per node | Clustered or invalidating cache, or no L2C for mutable data |
| `HHH000104: firstResult/maxResults specified with collection fetch` | Pagination with a collection fetch join, applied **in memory** | Two-step: page IDs, then fetch ([5.3 §3](03-Performance-NPlus1-Cartesian-Projections.md#3-cartesian-products--multiple-bag-fetch-)) |

**Observability:** `hibernate.generate_statistics=true` (`Statistics`: entity loads, fetches, query counts, L2C hits; exported via Micrometer's Hibernate metrics), `logging.level.org.hibernate.SQL=debug` (+ `org.hibernate.orm.jdbc.bind=trace` for parameters, in non-prod only), datasource-proxy or p6spy for statement counting in tests (assert query counts!), and `hibernate.log_slow_query=<ms>` (the Hibernate 6+ name of the old 5.x `hibernate.session.events.log.LOG_QUERIES_SLOWER_THAN_MS`).

---

## 7. Interview Q&A

<details><summary><b>Q1. 🔥 Explain the persistence context and how dirty checking works.</b></summary>

A per-session identity map of managed entities plus a snapshot of each entity's loaded state. At flush (before commit and before affected queries in AUTO mode), Hibernate compares the current field values of every managed entity with its snapshot and enqueues UPDATEs for changed ones (all columns by default, or only changed columns with `@DynamicUpdate`). With bytecode enhancement, entities track their own dirty fields instead.
</details>

<details><summary><b>Q2. 🔥 `persist` vs `merge`?</b></summary>

`persist` makes a new (transient) instance managed. The same instance becomes managed, and the INSERT happens at flush (immediately with IDENTITY). `merge` copies the state of a detached (or new) instance onto a managed instance (loaded or created) and returns the managed copy. The argument itself stays detached. Using `merge` for new entities with assigned IDs costs an extra SELECT.
</details>

<details><summary><b>Q3. ⚡ Why does deleting and re-inserting the same unique key in one transaction fail?</b></summary>

Hibernate's `ActionQueue` executes inserts before deletes at flush, regardless of call order (measured: duplicate key violation). Flush explicitly after the delete, or update the existing row instead of delete-plus-insert.
</details>

<details><summary><b>Q4. 🔥 Why is `IDENTITY` bad for batch inserts? What's the pooled optimizer?</b></summary>

With IDENTITY the ID is produced by the INSERT, so Hibernate must execute each INSERT immediately to register the entity, which prevents JDBC batching. A `SEQUENCE` with the pooled optimizer fetches one value per `allocationSize` (default 50) and assigns IDs in memory, so inserts can be batched at flush.
</details>

<details><summary><b>Q5. ⚡ When would you use `StatelessSession`?</b></summary>

For bulk processing (imports, ETL, migrations): no persistence context, no dirty checking, no cascades, no L1/L2 caching, and explicit `insert`/`update`/`delete` calls. Memory stays flat, and statements map almost 1:1 to SQL. Caveat on Hibernate 7: `hibernate.jdbc.batch_size` no longer applies to stateless sessions, so each `insert()` is its own round trip unless you call `setJdbcBatchSize(n)` or use `insertMultiple(list)` (measured 5,100 vs 201 round trips for 5,000 rows).
</details>

<details><summary><b>Q6. ⚡ What does the second-level cache store, and what are the risks?</b></summary>

Dehydrated entity state (column values) by ID, shared across sessions in a `SessionFactory`, with concurrency strategies (read-only, nonstrict-read-write, read-write, transactional). Risks: stale data across nodes without a clustered or invalidating provider, memory pressure, and query-cache invalidation storms on frequently updated tables. It also does nothing for queries unless the query cache is enabled.
</details>

<details><summary><b>Q7. ⚡ How should you implement `equals`/`hashCode` for JPA entities?</b></summary>

Use an immutable natural key if one exists. Otherwise use ID-based `equals` (with an `instanceof` check, proxy-safe) and a constant `hashCode` per class, so the hash doesn't change when the ID is assigned at persist. Avoid all-fields equality (lazy-loading side effects, recursion) and Lombok `@Data` on entities.
</details>

<details><summary><b>Q8. 🔥 A service method loads 20,000 entities, then calls a repository query in a loop, and each query takes several milliseconds more than when run alone. Why?</b></summary>

`FlushMode.AUTO`: before running a JPQL query that touches tables with pending changes, Hibernate must make sure those changes are visible to the query, so it runs a flush first, and that flush dirty-checks **every** managed entity. The cost is O(managed entities) per query, so O(N × queries) overall (measured: 500 PK lookups took 3.5 s with 50,000 managed entities vs ~80 ms with none). Fixes: `@Transactional(readOnly = true)` (Spring sets a read-only session and `FlushMode.MANUAL`), DTO projections for the bulk read, `clear()` once the entities are no longer needed, or splitting the work into chunks.
</details>
