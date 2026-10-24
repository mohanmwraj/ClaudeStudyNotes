# 5.6 · Pillar 5 — Interview & Certification Question Bank (JDBC, Pooling, JPA/Hibernate, Transactions)

> **Use:** A = flashcards, B = senior and architect scenarios, C = certification-style code questions with verified answers.
> **Exam scope, stated honestly:** JDBC was **dropped from the Java SE 21 exam (1Z0-830)**. It was an objective of 1Z0-829 (Java 17), and secondary sources citing Oracle's 2024 objectives list it as removed. So nothing in this pillar is core 1Z0-830/831 material. Section C instead targets (1) **JDBC API fundamentals**, which interviews still probe and which 1Z0-829 tested, and (2) the **data-access and transaction area of the Spring Professional certification** (Broadcom 2V0-72.22; check the current exam guide on broadcom.com). All questions are original practice items, not real exam content, and **every program in C was run** (H2 2.4.240 in-memory, Hibernate 7.4.13, Spring 7.0.10, JDK 25).

---

## A. Rapid-fire

<details><summary><b>A1–A24</b></summary>

1. **What does HikariCP's `ConcurrentBag` optimize for?** Lock-free borrow and return. A thread first scans its **thread-local list** of recently used connections, then the shared list (CAS on each entry's state), then waits on a `SynchronousQueue` handoff ([5.1](01-JDBC-HikariCP-Connection-Pooling.md)).
2. **Default `maximumPoolSize` / `connectionTimeout` / `maxLifetime` / `keepaliveTime` in HikariCP 7?** 10 / 30 s / 30 min / 2 min.
3. **Pool-sizing starting point?** `connections ≈ (core_count × 2) + effective_spindle_count`, per database server, shared by the **whole fleet**. Then measure.
4. **When does pgjdbc stream a large result instead of buffering it?** Only with `autoCommit=false` **and** `fetchSize > 0`.
5. **What makes JDBC batch inserts fast on PostgreSQL?** `addBatch`/`executeBatch` plus `reWriteBatchedInserts=true` (multi-row `INSERT`).
6. **Persistence context in one sentence?** A per-session identity map of managed entities plus a loaded-state snapshot for dirty checking.
7. **When does Hibernate flush?** Before commit, before JPQL/HQL queries that touch tables with pending changes (`AUTO`), and on explicit `flush()`.
8. **Order of SQL at flush?** Inserts, updates, collection changes, then **deletes last** (`ActionQueue`).
9. **Why is `IDENTITY` bad for batching?** The ID only exists after the INSERT, so each INSERT executes immediately.
10. **Default `allocationSize` for `@SequenceGenerator`?** 50 (pooled optimizer).
11. **Since when does `hibernate.jdbc.batch_size` not apply to `StatelessSession`?** Hibernate 7. Use `insertMultiple` or `setJdbcBatchSize`.
12. **JPA default fetch type for `@ManyToOne`?** `EAGER`. Change it to `LAZY`.
13. **`MultipleBagFetchException` means?** Two `List` (bag) collections join-fetched in one query.
14. **Does Hibernate 6+ need `distinct` with a collection join fetch?** No. Root entities are deduplicated automatically.
15. **Batch fetching on PostgreSQL uses which SQL shape?** `where fk = any (?)` with one array parameter.
16. **Pagination + collection fetch join since Hibernate 7.4?** Paged in SQL via a derived table; before that it was in memory (`HHH90003004`).
17. **Closed vs open interface projection?** Closed: only the needed columns. Open (`@Value` SpEL): the full entity is loaded.
18. **Default isolation in PostgreSQL / MySQL InnoDB / Oracle?** READ COMMITTED / REPEATABLE READ / READ COMMITTED.
19. **PostgreSQL SQLState for a serialization failure / deadlock / NOWAIT?** `40001` / `40P01` / `55P03`.
20. **What does `PESSIMISTIC_WRITE` render to on PostgreSQL with Hibernate 7?** `for no key update`.
21. **Spring's default rollback rule?** Roll back on `RuntimeException` and `Error`; commit on checked exceptions.
22. **Spring 6.2 global switch for rollback on all exceptions?** `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)`.
23. **Where does Spring keep the current transaction?** In `ThreadLocal`s (`TransactionSynchronizationManager`). It doesn't cross thread boundaries.
24. **Spring Boot's `spring.jpa.open-in-view` default?** `true` (with a startup warning). Set it to `false` for APIs.

</details>

---

## B. Senior scenarios

<details><summary><b>B1. 🔥 A service with 40 pods × 20 connections hits PostgreSQL's <code>max_connections</code> after a scale-out. What do you do?</b></summary>

The fleet holds 800 connections. Each PostgreSQL backend is a process (memory, snapshot-scan cost), and past a few hundred connections throughput *drops*. Per pod, apply Little's law (connections ≈ throughput × hold time) instead of guessing; shorten hold times (OSIV off, no remote calls in transactions, lower `connectionTimeout`); shrink pools to the measured need (often 5–10 per pod). Put a transaction-mode pooler (PgBouncer/pgcat) in front if the fleet must grow. Note that transaction pooling breaks session state: no server-side prepared statements without driver support, no session-level `SET`, no advisory session locks. Budget `max_connections` per service and alert on `hikaricp.connections.pending`.
</details>

<details><summary><b>B2. 🔥 Design inventory reservation for a flash sale (one SKU, 50,000 buyers in 60 s).</b></summary>

Avoid read-modify-write on one hot row. Option 1: an atomic conditional update `update stock set qty = qty - 1 where sku = ? and qty > 0` (1 affected row = success). It is serialized on the row lock, but each transaction is microseconds long if nothing else happens inside it. Option 2: pre-split the stock into N bucket rows and pick a random bucket (`SKIP LOCKED` or a random start), which removes the single-row bottleneck. Option 3: a reservation queue (Kafka partitioned by SKU) with a single writer. Always keep the DB transaction tiny, put idempotency keys on the purchase request, and compensate (saga) for payment failure. Optimistic locking would cause retry storms here.
</details>

<details><summary><b>B3. ⚡ Your team wants to switch the whole application to SERIALIZABLE "to be safe". Your advice?</b></summary>

It is feasible on PostgreSQL (SSI doesn't block readers), but every transaction must be **retryable**: a central retry wrapper outside the transaction for `40001`, idempotent side effects only, and no remote calls inside. Expect higher abort rates under contention and with long transactions; mark read-only transactions `READ ONLY`. A targeted approach is often better: SERIALIZABLE (or explicit locks or constraints) only for the use cases with cross-row invariants (write skew), and READ COMMITTED with atomic updates or `@Version` elsewhere. On MySQL, SERIALIZABLE means locking reads, a very different cost profile.
</details>

<details><summary><b>B4. 🔥 A REST endpoint lists 50 orders with lines and products. It runs 151 queries. Walk through the fix and how you keep it fixed.</b></summary>

Diagnose with SQL logs or a trace: 1 query for orders, 50 for lines, 100 for products (an EAGER `@ManyToOne` or lazy-in-serializer). Fix for a list view: one DTO projection query (joins, only the needed columns), or two queries: page the order IDs, then fetch orders with lines in one query, with `default_batch_fetch_size` for products. Make every to-one `LAZY`, set `open-in-view=false`, and map to DTOs inside the transaction. Keep it fixed with an integration test that asserts the statement count (datasource-proxy `QueryCountHolder`) per endpoint, plus a span-count SLO in production.
</details>

<details><summary><b>B5. ⚡ Migrating a large app from Hibernate 5 (Boot 2) to Hibernate 7 (Boot 4). What persistence behaviours do you re-verify?</b></summary>

`javax` → `jakarta`; removed `Session.save/update/saveOrUpdate`; ID generator defaults (sequence naming `<entity>_SEQ`, increment 50) against existing sequences; automatic dedup of fetch joins (results change for code that relied on duplicates); `StatelessSession` batching (no longer driven by `batch_size`); pagination with collection fetch (in-memory before 7.4, SQL since); the stricter HQL parser and type checks; `@Where`/`@Loader` replacements; the Boot naming strategy; Jackson 3 for any entity-to-JSON paths. Run the performance suite with **JDBC round-trip and statement-count assertions**, not just functional tests.
</details>

<details><summary><b>B6. ⚡ Explain how you'd implement a reliable job queue on PostgreSQL without a broker.</b></summary>

A `job(id, status, run_at, attempts, payload, locked_by, locked_at)` table. Workers run `select … where status='NEW' and run_at <= now() order by run_at limit n for update skip locked`, process the claimed rows, and update their status in the same transaction (short jobs), or mark them `RUNNING` with a lease timestamp and commit, then heartbeat (long jobs). Retries use `attempts` + `run_at` back-off; a dead-letter status covers poison jobs; indexes go on `(status, run_at)`. Idempotent handlers are mandatory, because a crash after the side effect but before the commit re-runs the job. This is also the relay pattern for a transactional outbox.
</details>

<details><summary><b>B7. 🧊 Why might `@Transactional(readOnly = true)` make a query *faster* on one system and break another?</b></summary>

Faster: Hibernate skips snapshots and dirty checking (`FlushMode.MANUAL`, read-only session), and routing data sources can send the query to a replica. It breaks when the code (or a library, or a trigger-like listener) writes inside it: PostgreSQL rejects writes in a read-only transaction (`25006`), and replica routing returns stale data for read-your-own-writes flows. It also hides lazy-loading N+1 if OSIV is on. Use it deliberately per use case, and test replica lag behaviour.
</details>

<details><summary><b>B8. ⚡ How would you guarantee "exactly one charge per order" across retries, crashes and duplicate requests?</b></summary>

An idempotency key (client-supplied or derived from the order ID) stored with a **unique constraint** in the same transaction as the charge record. On a duplicate, `23505` means "already processed": return the stored response. Call the payment provider with the same idempotency key (providers dedupe on it). Use an outbox for downstream events, and keep retries outside the transaction. This is effectively-once behaviour built from at-least-once delivery plus idempotent processing ([6.3](../06-Spring-Microservices/03-Outbox-Saga-Idempotency.md)).
</details>

---

## C. Certification-style code questions (verified)

### C1 — `execute` vs `executeUpdate`, and `wasNull()`

<!-- run: cp=@p5 -->
```java
import java.sql.*;

public class Jdbc01 {
    public static void main(String[] args) throws SQLException {
        try (Connection c = DriverManager.getConnection("jdbc:h2:mem:c1");
             Statement s = c.createStatement()) {
            s.execute("create table t(id int primary key, qty int)");
            int inserted = s.executeUpdate("insert into t values (1, 5), (2, null), (3, 7)");
            boolean isResultSet = s.execute("update t set qty = qty + 1 where qty is not null");
            System.out.println(inserted + " " + isResultSet + " " + s.getUpdateCount());
            try (ResultSet rs = s.executeQuery("select id, qty from t order by id")) {
                StringBuilder sb = new StringBuilder();
                while (rs.next()) {
                    int qty = rs.getInt("qty");
                    sb.append(rs.getInt(1)).append(':').append(qty).append(rs.wasNull() ? "(null) " : " ");
                }
                System.out.println(sb.toString().trim());
            }
        }
    }
}
```

<details><summary>Answer</summary>

```
3 false 2
1:6 2:0 3:8
```

`executeUpdate` returns the row count (3). `execute` returns `true` only when the first result is a `ResultSet`; for an UPDATE it returns `false`, and `getUpdateCount()` gives the 2 updated rows (`NULL + 1` is skipped by `is not null`). JDBC column indexes are **1-based**, and `getInt` on SQL `NULL` returns `0`. The trap: `wasNull()` reports on the **last getter called**. Here that's `rs.getInt(1)` (the id, never null), so the `(null)` marker never prints. Call `wasNull()` immediately after the getter you care about, or use `rs.getObject("qty", Integer.class)`.
</details>

### C2 — Savepoints and switching auto-commit

<!-- run: cp=@p5 -->
```java
import java.sql.*;
import java.util.*;

public class Jdbc02 {
    static List<Integer> ids(Connection c) throws SQLException {
        List<Integer> ids = new ArrayList<>();
        try (Statement s = c.createStatement(); ResultSet rs = s.executeQuery("select id from t order by id")) {
            while (rs.next()) ids.add(rs.getInt(1));
        }
        return ids;
    }
    public static void main(String[] args) throws SQLException {
        try (Connection c = DriverManager.getConnection("jdbc:h2:mem:c2");
             Connection other = DriverManager.getConnection("jdbc:h2:mem:c2");
             Statement s = c.createStatement()) {
            s.execute("create table t(id int primary key)");
            c.setAutoCommit(false);
            s.executeUpdate("insert into t values (1)");
            Savepoint sp = c.setSavepoint();
            s.executeUpdate("insert into t values (2)");
            c.rollback(sp);
            s.executeUpdate("insert into t values (3)");
            System.out.println("before commit, other connection sees " + ids(other));
            c.commit();
            s.executeUpdate("insert into t values (4)");
            c.setAutoCommit(true);
            System.out.println("after setAutoCommit(true), other connection sees " + ids(other));
        }
    }
}
```

<details><summary>Answer</summary>

```
before commit, other connection sees []
after setAutoCommit(true), other connection sees [1, 3, 4]
```

Rolling back to a savepoint undoes only the work after it (row 2). Uncommitted rows are invisible to other connections. Per the JDBC spec, **changing auto-commit during an active transaction commits it**, so row 4 becomes visible. (The spec also says `rollback()` in auto-commit mode throws `SQLException`. H2 2.4 silently ignores it, which is why it isn't asked here. Don't rely on driver leniency.)
</details>

### C3 — `PreparedStatement` parameters and implicit `ResultSet` closing

<!-- run: cp=@p5 -->
```java
import java.sql.*;

public class Jdbc03 {
    public static void main(String[] args) throws SQLException {
        try (Connection c = DriverManager.getConnection("jdbc:h2:mem:c3"); Statement s = c.createStatement()) {
            s.execute("create table t(id int primary key, name varchar(10))");
            try (PreparedStatement ps = c.prepareStatement("insert into t(id, name) values (?, ?)")) {
                ps.setInt(1, 1); ps.setString(2, "a"); ps.executeUpdate();
                ps.setInt(1, 2);                     ps.executeUpdate();   // parameter 2 keeps its value
                ps.clearParameters();
                try { ps.setInt(1, 3); ps.executeUpdate(); } catch (SQLException e) { System.out.println("after clearParameters: SQLException"); }
                try { ps.setInt(0, 4); } catch (SQLException e) { System.out.println("index 0: SQLException"); }
            }
            ResultSet first = s.executeQuery("select count(*) from t");
            ResultSet second = s.executeQuery("select name from t where id = 2");
            second.next();
            System.out.println(first.isClosed() + " " + second.getString(1));
            s.close();
            System.out.println(second.isClosed());
        }
    }
}
```

<details><summary>Answer</summary>

```
after clearParameters: SQLException
index 0: SQLException
true a
true
```

Parameters keep their values between executions (row 2 got name `a`). `clearParameters()` unsets them, so executing with one unset parameter fails. Indexes start at **1**. Re-executing a `Statement` closes its previous `ResultSet` (`first.isClosed()` is `true`), and closing the `Statement` closes its current `ResultSet`.
</details>

### C4 — Entity lifecycle: `persist`, auto-flush, `detach`, `merge`

<!-- run: cp=@p5 -->
```java
import jakarta.persistence.*;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;

public class Jpa04 {
    @Entity(name = "Product")
    public static class Product {
        @Id Long id; String name;
        protected Product() {}
        Product(long id, String name) { this.id = id; this.name = name; }
    }
    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        try (EntityManagerFactory emf = new HibernatePersistenceConfiguration("q").managedClass(Product.class)
                .jdbcUrl("jdbc:h2:mem:c4").schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
            EntityManager em = emf.createEntityManager();
            em.getTransaction().begin();
            Product p = new Product(1, "pen");
            em.persist(p);
            long counted = em.createQuery("select count(p) from Product p", Long.class).getSingleResult();
            em.detach(p);
            p.name = "pencil";
            Product m = em.merge(p);
            System.out.println(counted + " " + (m == p) + " " + em.contains(p) + " " + em.contains(m) + " " + m.name);
            m.name = "marker";
            p.name = "crayon";
            em.getTransaction().commit();
            em.close();
            EntityManager em2 = emf.createEntityManager();
            System.out.println(em2.find(Product.class, 1L).name);
            em2.getTransaction().begin();
            try { em2.persist(p); em2.flush(); }
            catch (PersistenceException e) { System.out.println(e.getClass().getSimpleName()); }
            em2.getTransaction().rollback();
            em2.close();
        }
    }
}
```

<details><summary>Answer</summary>

```
1 false false true pencil
marker
EntityExistsException
```

The JPQL `count` triggered an **auto-flush**, so the persisted product was counted (1). `merge` copies the detached state onto a **managed copy** and returns it: `m != p`, `p` stays detached, and `m` is managed with name `pencil`. At commit only the managed instance matters, so `marker` is stored and `crayon` (set on the detached `p`) is ignored. Passing a detached instance to `persist` in a new persistence context fails with `EntityExistsException` ("detached entity passed to persist").
</details>

### C5 — Spring propagation, rollback rules and self-invocation (Spring Professional style)

<!-- run: javac cp=@p5 -->
```java
package quiz;

import java.util.List;
import javax.sql.DataSource;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.*;

public class Tx05 {
    public static class Audit {
        final JdbcTemplate jdbc; public Audit(JdbcTemplate j) { jdbc = j; }
        @Transactional(propagation = Propagation.REQUIRES_NEW)
        public void log(String msg) { jdbc.update("insert into audit(msg) values (?)", msg); }
    }
    public static class Orders {
        final JdbcTemplate jdbc; final Audit audit;
        public Orders(JdbcTemplate j, Audit a) { jdbc = j; audit = a; }
        @Transactional
        public void placeChecked(int id) throws Exception {
            jdbc.update("insert into orders values (?)", id); audit.log("order " + id);
            throw new Exception("checked");
        }
        @Transactional
        public void placeUnchecked(int id) {
            jdbc.update("insert into orders values (?)", id); audit.log("order " + id);
            throw new IllegalStateException("unchecked");
        }
        public void placeViaThis(int id) { placeUnchecked(id); }   // not @Transactional itself
    }

    @Configuration @EnableTransactionManagement
    static class Config {
        @Bean DataSource ds() { return new DriverManagerDataSource("jdbc:h2:mem:c5;DB_CLOSE_DELAY=-1"); }
        @Bean JdbcTemplate jdbc(DataSource ds) { return new JdbcTemplate(ds); }
        @Bean PlatformTransactionManager tm(DataSource ds) { return new DataSourceTransactionManager(ds); }
        @Bean Audit audit(JdbcTemplate j) { return new Audit(j); }
        @Bean Orders orders(JdbcTemplate j, Audit a) { return new Orders(j, a); }
    }

    public static void main(String[] args) {
        try (var ctx = new AnnotationConfigApplicationContext(Config.class)) {
            JdbcTemplate jdbc = ctx.getBean(JdbcTemplate.class);
            jdbc.execute("create table orders(id int primary key); create table audit(msg varchar(20))");
            Orders orders = ctx.getBean(Orders.class);
            try { orders.placeChecked(1); } catch (Exception ignored) { }
            try { orders.placeUnchecked(2); } catch (RuntimeException ignored) { }
            try { orders.placeViaThis(3); } catch (RuntimeException ignored) { }
            List<Integer> ids = jdbc.queryForList("select id from orders order by id", Integer.class);
            Integer audits = jdbc.queryForObject("select count(*) from audit", Integer.class);
            System.out.println("orders=" + ids + " audit rows=" + audits);
        }
    }
}
```

<details><summary>Answer</summary>

`orders=[1, 3] audit rows=3`

* `placeChecked(1)`: a checked exception, so the default rules **commit**. Order 1 is kept, and its audit row was committed separately (`REQUIRES_NEW`).
* `placeUnchecked(2)`: an unchecked exception rolls the order back, but the audit row survives (its own transaction).
* `placeViaThis(3)`: `placeViaThis` isn't transactional, and its call to `placeUnchecked` is **self-invocation**, so no proxy and no transaction. `JdbcTemplate` runs in auto-commit mode and the INSERT is committed immediately. The exception has nothing to roll back. The audit call still goes through the `Audit` proxy (another bean), so it also commits.
</details>

### C6 — Flush modes and bulk updates

<!-- run: cp=@p5 -->
```java
import jakarta.persistence.*;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;

public class Jpa06 {
    @Entity(name = "Item")
    public static class Item { @Id Long id; int qty; protected Item() {} Item(long id, int q) { this.id = id; qty = q; } }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        try (EntityManagerFactory emf = new HibernatePersistenceConfiguration("q").managedClass(Item.class)
                .jdbcUrl("jdbc:h2:mem:c6").schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
            emf.runInTransaction(em -> em.persist(new Item(1, 10)));
            emf.runInTransaction(em -> {
                Item i = em.find(Item.class, 1L);
                i.qty = 5;
                em.setFlushMode(FlushModeType.COMMIT);
                long low = em.createQuery("select count(i) from Item i where i.qty < 8", Long.class).getSingleResult();
                em.setFlushMode(FlushModeType.AUTO);
                long lowAuto = em.createQuery("select count(i) from Item i where i.qty < 8", Long.class).getSingleResult();
                int bulk = em.createQuery("update Item i set i.qty = i.qty + 100").executeUpdate();
                System.out.println(low + " " + lowAuto + " " + bulk + " " + i.qty + " " + em.find(Item.class, 1L).qty);
                em.refresh(i);
                System.out.println(i.qty);
            });
        }
    }
}
```

<details><summary>Answer</summary>

```
0 1 1 5 5
105
```

With `FlushModeType.COMMIT` the query runs without flushing, so the database still has `qty = 10` (count 0). With `AUTO`, Hibernate flushes `qty = 5` first (count 1). The bulk JPQL `update` executes directly in the database (1 row → 105) and **bypasses the persistence context**: the managed `i` still says 5, and `find` returns that same cached instance (5). Only `refresh` re-reads 105. Hence Spring Data's `@Modifying(clearAutomatically = true)`.
</details>

---

## D. Study map

| Topic | Files | Practise |
|---|---|---|
| JDBC API, pooling, batching, fetch size | [5.1](01-JDBC-HikariCP-Connection-Pooling.md) | C1, C2, C3, A1–A5, B1 |
| Persistence context, flush, IDs, L2C | [5.2](02-JPA-Hibernate-Persistence-Context-Internals.md) | C4, C6, A6–A11, B5 |
| N+1, Cartesian products, pagination, projections | [5.3](03-Performance-NPlus1-Cartesian-Projections.md) | A12–A17, B4 |
| Isolation, locking, Spring transactions, OSIV | [5.4](04-Transactions-Isolation-Locking-Spring-Transactional.md) | C5, A18–A24, B2, B3, B6–B8 |
| Incident response | [5.5](05-Production-Failure-Modes-Diagnostics.md) | Rehearse Stories 1–6 out loud: symptom → evidence → root cause → fix |
