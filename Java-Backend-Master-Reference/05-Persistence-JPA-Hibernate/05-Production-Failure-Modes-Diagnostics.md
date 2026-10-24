# 5.5 · Pillar 5 — Production Failure Modes & Diagnostic Checklist (Persistence)

> Persistence incidents rarely look like database problems at first. They show up as **"the service is slow", "requests time out", "numbers don't add up" or "we ran out of memory"**, while the database CPU is fine. This file has the playbooks: composite war stories, each mechanism **reproduced in [5.1](01-JDBC-HikariCP-Connection-Pooling.md)–[5.4](04-Transactions-Isolation-Locking-Spring-Transactional.md)**. It also covers the diagnostic toolkit across JVM, pool, ORM and PostgreSQL, the metrics that catch problems early, and a code-review checklist.

---

## 1. Incident playbooks

### 🔥 Story 1 — "Connection is not available" during the sale, with DB CPU at 20%

* **Symptom:** p99 latency jumped to exactly the Hikari `connectionTimeout` (30 s by default), then a wave of `SQLTransientConnectionException: orders-db - Connection is not available, request timed out after 30000ms (total=20, active=20, idle=0, waiting=180)`.
* **Evidence:** a thread dump showed hundreds of request threads parked in `ConcurrentBag.borrow` (signature in §2.1). Hikari `hikaricp.connections.usage` p99 was 4 s, while the SQL itself was fast in `pg_stat_statements`.
* **Root causes (both reproduced):**
  1. OSIV on: every request kept its connection through JSON rendering and an outbound HTTP call ([5.4 §6](04-Transactions-Isolation-Locking-Spring-Transactional.md#6-open-session-in-view-osiv-)).
  2. An audit method with `REQUIRES_NEW` needed a **second** connection per request, so under load every connection was held by an outer transaction waiting for an inner one ([5.4 §4.1](04-Transactions-Isolation-Locking-Spring-Transactional.md#41-runnable-the-ten-behaviours-every-spring-developer-gets-bitten-by), line 7).
* **Fix:** `spring.jpa.open-in-view=false`; the remote call moved outside the transaction; the audit written after commit through an outbox; `connectionTimeout` lowered to 2–5 s so overload fails fast instead of queueing.
* **Prevention:** alert on `hikaricp.connections.pending > 0` sustained and on `hikaricp.connections.usage` p99 ≫ query time; run a load test with a deliberately small pool.

### 🔥 Story 2 — "The orders page takes 4 seconds, but every query is 1 ms"

* **Symptom:** a list endpoint slowed down linearly with page size; the database looked idle.
* **Evidence:** a trace with **312 JDBC spans** for one request; `pg_stat_statements` showed `select … from order_line where order_id=$1` with 40 million calls/day.
* **Root cause:** N+1. Jackson serialized `order.getLines()` (lazy, OSIV on) and `line.getProduct()` (default-EAGER `@ManyToOne`) per row ([5.3 §2](03-Performance-NPlus1-Cartesian-Projections.md#2-the-n1-select-problem-)).
* **Fix:** a DTO projection query for the list, a fetch join for the detail view, every to-one mapped `LAZY`, `hibernate.default_batch_fetch_size=50` as a safety net.
* **Prevention:** statement-count assertions in integration tests (`QueryCountHolder`), plus a span-count SLO per endpoint.

### 🔥 Story 3 — "Inventory went negative" / "a deposit disappeared"

* **Symptom:** rare reconciliation mismatches, only under concurrency, never reproducible locally.
* **Root cause:** `item.setStock(item.getStock() - qty)` inside `@Transactional` at READ COMMITTED: a lost update ([5.4 §2.1](04-Transactions-Isolation-Locking-Spring-Transactional.md#21-runnable-every-anomaly-reproduced-with-two-jdbc-connections): 100 + 10 + 10 = 110).
* **Fix:** atomic conditional update: `update item set stock = stock - :qty where id = :id and stock >= :qty` (check affected rows = 1), or `@Version` with retry.
* **Prevention:** concurrency tests that hammer one row from N threads and assert the invariant.

### 🔥 Story 4 — "Two doctors went off call at the same time" (double booking)

* **Root cause:** write skew. Each transaction checked an invariant over a set of rows and updated a different row. REPEATABLE READ didn't help ([5.4 §2.1](04-Transactions-Isolation-Locking-Spring-Transactional.md#21-runnable-every-anomaly-reproduced-with-two-jdbc-connections)).
* **Fix:** SERIALIZABLE for that use case with a retry on `40001`; or `select … for update` on the rows the decision reads; or a constraint that materializes the invariant (an exclusion constraint for bookings: `exclude using gist (room with =, during with &&)`).

### 🔥 Story 5 — "The import job is 10× slower after the Spring Boot 4 upgrade"

* **Symptom:** a nightly import that used `StatelessSession` went from 6 minutes to an hour. No errors.
* **Root cause:** Hibernate 7 no longer applies `hibernate.jdbc.batch_size` to stateless sessions, so each `insert()` became its own round trip ([5.2 §3.1](02-JPA-Hibernate-Persistence-Context-Internals.md#31-runnable-identity-vs-sequence-vs-statelesssession-counted-at-the-jdbc-layer): 5,100 vs 201 round trips).
* **Fix:** `insertMultiple(list)` in chunks, or `setJdbcBatchSize(n)`.
* **Prevention:** keep JDBC round-trip counts as a performance-test assertion, which catches ORM upgrade regressions.

### 🔥 Story 6 — "The API returns every line item 20 times"

* **Root cause:** a repository method join-fetched a `List` (bag) **and** a `Set`. Hibernate allows that combination and duplicates the bag's elements once per row of the Cartesian product ([5.3 §3.1](03-Performance-NPlus1-Cartesian-Projections.md#31-runnable-the-cartesian-product-measured-and-the-two-query-fix): 400 instead of 20).
* **Fix:** one collection per query; `Set` where order doesn't matter.
* **Prevention:** `size()` assertions in repository tests against seeded data.

### ⚡ Story 7 — "OOM on the admin page that shows 20 customers"

* **Root cause (Hibernate < 7.4):** `setMaxResults(20)` combined with a collection fetch join. Hibernate logged `HHH90003004` and loaded all 3 million rows to paginate in memory ([5.3 §3.2](03-Performance-NPlus1-Cartesian-Projections.md#32-pagination-with-a-collection-fetch-join-)).
* **Fix:** two-step paging (IDs, then fetch); `hibernate.query.fail_on_pagination_over_collection_fetch=true` everywhere; Hibernate 7.4+ pages the root rows in SQL.

### ⚡ Story 8 — "The export gets slower every night"

* **Root cause:** `OFFSET` pagination over a growing table (cost O(offset), so O(n²) for a full export), plus a missing index on the FK column the export filtered by ([5.3 §5.1](03-Performance-NPlus1-Cartesian-Projections.md#51-runnable-offset-vs-keyset-pagination-and-the-missing-fk-index): 131 ms per page at offset 990k; 101 ms vs 1.5 ms per FK lookup).
* **Fix:** keyset pagination (`where id > :last order by id limit n`) and FK indexes in the migration.

### ⚡ Story 9 — "The payment was saved even though validation failed"

* **Root cause:** the service threw a **checked** `PaymentRejectedException` from a `@Transactional` method. Spring's default rules commit on checked exceptions ([5.4 §4.1](04-Transactions-Isolation-Locking-Spring-Transactional.md#41-runnable-the-ten-behaviours-every-spring-developer-gets-bitten-by), line 2).
* **Fix:** `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)` (Spring 6.2+) application-wide, or `rollbackFor` on the method; make domain exceptions unchecked.

### ⚡ Story 10 — "`UnexpectedRollbackException` with no root cause in the logs"

* **Root cause:** a validator bean (`@Transactional`, REQUIRED) threw inside the caller's transaction, and the caller caught and ignored it. The transaction was already marked rollback-only, so the commit threw far away from the cause (line 5).
* **Fix:** log and propagate; validate before writing; give optional sub-work its own transaction.

### ⚡ Story 11 — "Deadlocks after we added transfers"

* **Evidence:** PostgreSQL log with `log_lock_waits=on`: `ERROR: deadlock detected … Process 4711 waits for ShareLock on transaction …`, `SQLState 40P01`.
* **Root cause:** transfer A→B locked A then B; a concurrent B→A locked B then A ([5.4 §3.2](04-Transactions-Isolation-Locking-Spring-Transactional.md#32-runnable-lock-sql-nowait-skip-locked-a-deadlock-and-optimistic-locking)).
* **Fix:** lock rows in ascending ID order; `lock_timeout`; retry `40P01`.

### ⚡ Story 12 — "Batch step slows to a crawl after the first 10,000 rows"

* **Root cause:** a single long transaction kept every processed entity managed. Each lookup query triggered an **auto-flush** that dirty-checked all of them: O(entities × queries) ([5.2 §2.1](02-JPA-Hibernate-Persistence-Context-Internals.md#21-runnable-what-a-big-persistence-context-really-costs): 3.5 s vs 80 ms).
* **Fix:** chunked transactions with `flush(); clear();`, read-only lookups, DTO projections, or `StatelessSession`.

### ⚡ Story 13 — "Prices differ between pods for minutes"

* **Root cause:** a Hibernate second-level cache with a **local** provider (Caffeine) on 6 pods. An update on one pod didn't invalidate the others ([5.2 §5](02-JPA-Hibernate-Persistence-Context-Internals.md#5-second-level-cache-l2c-)).
* **Fix:** remove the L2C for mutable entities, or use a clustered or invalidating cache; cache in the application with explicit TTLs and events.

### ⚡ Story 14 — "Every ~30 minutes a burst of `Connection reset` / `I/O error`"

* **Root cause:** a firewall/NAT or DB-proxy idle timeout shorter than Hikari's `maxLifetime` and `keepaliveTime`, which killed idle connections silently ([5.1](01-JDBC-HikariCP-Connection-Pooling.md)).
* **Fix:** `maxLifetime` a few minutes shorter than the shortest infrastructure timeout; `keepaliveTime` (default 2 min since HikariCP 6.2.1) below the idle timeout.

---

## 2. Diagnostic toolkit

### 2.1 What a pool-starved thread looks like (verified)

<!-- run: javac cp=@p5 timeout=200 -->
```java
package demo.diag;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.sql.Connection;
import java.util.Arrays;
import org.slf4j.LoggerFactory;

public class PoolStarvedThread {
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            hc.setPoolName("orders-db");
            hc.setMaximumPoolSize(1);
            hc.setConnectionTimeout(3000);
            try (HikariDataSource ds = new HikariDataSource(hc); Connection held = ds.getConnection()) {   // the only connection
                Thread waiter = Thread.ofPlatform().name("http-nio-8080-exec-7").start(() -> {
                    try (Connection c = ds.getConnection()) { } catch (Exception e) { }
                });
                Thread.sleep(500);                                                   // let it block inside getConnection
                System.out.println("\"" + waiter.getName() + "\" state=" + waiter.getState());
                Arrays.stream(waiter.getStackTrace()).limit(9)
                    .forEach(f -> System.out.println("    at " + f.getClassName() + "." + f.getMethodName()));
                System.out.println("pool: active=" + ds.getHikariPoolMXBean().getActiveConnections()
                    + " idle=" + ds.getHikariPoolMXBean().getIdleConnections()
                    + " pending=" + ds.getHikariPoolMXBean().getThreadsAwaitingConnection());
                waiter.join();
            }
        }
    }
}
```

Output (verified):

```
"http-nio-8080-exec-7" state=TIMED_WAITING
    at jdk.internal.misc.Unsafe.park
    at java.util.concurrent.locks.LockSupport.parkNanos
    at java.util.concurrent.LinkedTransferQueue$DualNode.await
    at java.util.concurrent.LinkedTransferQueue.xfer
    at java.util.concurrent.SynchronousQueue.xfer
    at java.util.concurrent.SynchronousQueue.poll
    at com.zaxxer.hikari.util.ConcurrentBag.borrow
    at com.zaxxer.hikari.pool.HikariPool.getConnection
    at com.zaxxer.hikari.pool.HikariPool.getConnection
pool: active=1 idle=0 pending=1
```

Count the threads with `ConcurrentBag.borrow` in a dump (`jcmd <pid> Thread.print`, or `jcmd <pid> Thread.dump_to_file -format=json` for virtual threads) and compare with the number of threads that *hold* connections: these are in `SocketInputStream`/`NioSocketImpl.read` under `org.postgresql` frames (waiting for the DB), or doing unrelated work while holding a connection (the bug). On recent JDKs (verified on 25) `SynchronousQueue` is implemented on top of `LinkedTransferQueue`, so older runbooks that grep for `TransferStack` need updating.

### 2.2 Layer-by-layer checklist

```text
JVM / app      jcmd <pid> Thread.print | grep -c ConcurrentBag.borrow           # threads waiting for a connection
               JFR: jdk.SocketRead (threshold 20 ms), jdk.JavaMonitorWait, jdk.ThreadPark
Pool           hikaricp.connections.{active,idle,pending,max}; .acquire (wait time); .usage (hold time); .timeout (count)
               leakDetectionThreshold=… (logs the stack that borrowed and didn't return)
ORM            hibernate.generate_statistics=true → queries, entity loads/fetches, flushes, L2C hit ratio
               logging.level.org.hibernate.SQL=debug (non-prod), hibernate.log_slow_query=<ms>
Transactions   logging.level.org.springframework.orm.jpa.JpaTransactionManager=debug (create/join/suspend/rollback)
PostgreSQL     pg_stat_activity (state, xact_start, wait_event_type), pg_blocking_pids(pid), pg_locks
               pg_stat_statements (calls, mean/total time, rows), auto_explain (log plans of slow statements)
               log_lock_waits=on, deadlock_timeout=1s, log_min_duration_statement=…
```

### 2.3 SQLStates worth branching on, and what Spring turns them into (verified)

<!-- run: javac cp=@p5 timeout=200 -->
```java
package demo.diag;

import ch.qos.logback.classic.Level;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.sql.*;
import java.util.concurrent.*;
import javax.sql.DataSource;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.SQLExceptionTranslator;
import org.springframework.jdbc.support.SQLStateSQLExceptionTranslator;

public class SqlStateTranslation {
    interface Failing { void run(DataSource ds) throws Exception; }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            DataSource ds = pg.getPostgresDatabase();
            JdbcTemplate jdbc = new JdbcTemplate(ds);
            jdbc.execute("create table parent(id int primary key); create table child(id int primary key, parent_id int references parent(id));"
                + "insert into parent values (1)");
            SQLExceptionTranslator byCode = jdbc.getExceptionTranslator(), byState = new SQLStateSQLExceptionTranslator();
            System.out.println("JdbcTemplate default translator: " + byCode.getClass().getSimpleName());
            System.out.printf("%-6s %-38s %-42s %s%n", "state", "provoked by", "JdbcTemplate default", "SQLState-based");

            show(ds, byCode, byState, "duplicate primary key", d -> exec(d, "insert into parent values (1)"));
            show(ds, byCode, byState, "FK to a missing parent", d -> exec(d, "insert into child values (1, 99)"));
            show(ds, byCode, byState, "statement_timeout", d -> exec(d, "set statement_timeout = 50; select pg_sleep(1)"));
            show(ds, byCode, byState, "write in READ ONLY tx", d -> exec(d, "begin read only; insert into parent values (2)"));
            show(ds, byCode, byState, "SELECT … FOR UPDATE NOWAIT", d -> {
                try (Connection holder = d.getConnection()) {
                    holder.setAutoCommit(false);
                    exec(holder, "select * from parent where id = 1 for update");
                    exec(d, "select * from parent where id = 1 for update nowait");
                }
            });
            show(ds, byCode, byState, "REPEATABLE READ conflict", d -> {
                try (Connection t1 = d.getConnection(); Connection t2 = d.getConnection()) {
                    for (Connection c : new Connection[] {t1, t2}) { c.setAutoCommit(false); c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ); }
                    exec(t2, "select * from parent");                          // t2 takes its snapshot
                    exec(t1, "update parent set id = id where id = 1"); t1.commit();
                    exec(t2, "update parent set id = id where id = 1");        // 40001
                }
            });
            show(ds, byCode, byState, "deadlock", d -> {
                exec(d, "insert into parent values (2) on conflict do nothing");
                CyclicBarrier barrier = new CyclicBarrier(2);
                try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
                    Future<?> a = pool.submit(() -> lockBoth(d, 1, 2, barrier));
                    Future<?> b = pool.submit(() -> lockBoth(d, 2, 1, barrier));
                    for (Future<?> f : new Future<?>[] {a, b}) {
                        try { f.get(); } catch (ExecutionException e) { throw (Exception) e.getCause(); }
                    }
                }
            });
        }
    }

    static Void lockBoth(DataSource d, int first, int second, CyclicBarrier barrier) throws Exception {
        try (Connection c = d.getConnection()) {
            c.setAutoCommit(false);
            exec(c, "select * from parent where id = " + first + " for update");
            barrier.await();
            exec(c, "select * from parent where id = " + second + " for update");
            c.commit();
        }
        return null;
    }

    static void show(DataSource ds, SQLExceptionTranslator byCode, SQLExceptionTranslator byState, String label, Failing f) {
        try {
            f.run(ds);
            System.out.println(label + ": no error?!");
        } catch (Exception e) {
            SQLException sql = (SQLException) e;
            System.out.printf("%-6s %-38s %-42s %s%n", sql.getSQLState(), label,
                name(byCode.translate("demo", null, sql)), name(byState.translate("demo", null, sql)));
        }
    }
    static String name(Object o) { return o == null ? "null (not translated)" : o.getClass().getSimpleName(); }
    static void exec(DataSource d, String sql) throws SQLException { try (Connection c = d.getConnection()) { exec(c, sql); } }
    static void exec(Connection c, String sql) throws SQLException { try (Statement s = c.createStatement()) { s.execute(sql); } }
}
```

Output (verified):

```
JdbcTemplate default translator: SQLExceptionSubclassTranslator
state  provoked by                            JdbcTemplate default                       SQLState-based
23505  duplicate primary key                  DuplicateKeyException                      DuplicateKeyException
23503  FK to a missing parent                 DataIntegrityViolationException            DataIntegrityViolationException
57014  statement_timeout                      QueryTimeoutException                      QueryTimeoutException
25006  write in READ ONLY tx                  null (not translated)                      null (not translated)
55P03  SELECT … FOR UPDATE NOWAIT             null (not translated)                      null (not translated)
40001  REPEATABLE READ conflict               CannotAcquireLockException                 CannotAcquireLockException
40P01  deadlock                               PessimisticLockingFailureException         PessimisticLockingFailureException
```

* Since Spring 6, `JdbcTemplate`/`JdbcClient` use `SQLExceptionSubclassTranslator` (JDBC 4 exception subclasses, then SQLState classes). The vendor-error-code translator only kicks in when **you** put an `sql-error-codes.xml` at the classpath root (verified in `JdbcAccessor`). pgjdbc throws plain `PSQLException`, so the SQLState fallback does the work.
* **`55P03` and `25006` come back untranslated**, so `JdbcTemplate` wraps them in `UncategorizedSQLException`. A `catch (CannotAcquireLockException e)` will **not** catch a `NOWAIT` failure on PostgreSQL. With JPA the same failures surface as `LockTimeoutException`/`PessimisticLockException` ([5.4 §3.2](04-Transactions-Isolation-Locking-Spring-Transactional.md#32-runnable-lock-sql-nowait-skip-locked-a-deadlock-and-optimistic-locking)).
* **Rule:** for retry and idempotency decisions, walk the cause chain to the root `SQLException` and **branch on `getSQLState()`**, not on the Spring exception type.

| SQLState | Meaning | Action |
|---|---|---|
| `40001` | Serialization failure | **Retry the whole transaction** with back-off |
| `40P01` | Deadlock victim | Retry; fix the lock ordering |
| `55P03` | Lock not available (`NOWAIT`, `lock_timeout`) | Fail fast to the caller, or retry later |
| `23505` | Unique violation | If the key is an idempotency key, the work was already done: return the stored result |
| `23503` | FK violation | Race with a delete, or a bug |
| `25006` | Write in a read-only transaction | Wrong transaction boundary or replica routing |
| `57014` | Statement cancelled (`statement_timeout`, query timeout) | Investigate the plan; don't retry blindly |
| `08xxx` | Connection failure | Retry idempotent reads only; check the pool and network |

---

## 3. Metrics and alerts

| Signal | Source | Alert / meaning |
|---|---|---|
| Connection wait | `hikaricp.connections.pending`, `hikaricp.connections.acquire` (timer) | Pending > 0 for minutes; acquire p99 > 50 ms |
| Connection hold time | `hikaricp.connections.usage` (timer) | p99 ≫ SQL time → work done while holding a connection (OSIV, remote calls) |
| Pool timeouts | `hikaricp.connections.timeout` (counter) | Any increase |
| Statements per request | OTel JDBC spans / `hibernate.*` query counts | > budget per endpoint (N+1) |
| Slow statements | `pg_stat_statements` mean/total time; `hibernate.log_slow_query` | Top-10 by total time changes after a deploy |
| Lock waits and deadlocks | PG log (`log_lock_waits`), `pg_stat_database.deadlocks` | Any deadlock; lock waits > 1 s |
| Long / idle-in-transaction sessions | `pg_stat_activity` exporter | Any transaction > 30 s or idle in transaction > 10 s |
| Retry counts | Spring `MethodRetryEvent` / Resilience4j retry metrics | Rising optimistic-lock or `40001` retries signal contention |
| L2C hit ratio | `hibernate.*` cache meters | A drop after deploy; or a high hit ratio on frequently updated entities (staleness risk) |

---

## 4. Code-review checklist (persistence)

- [ ] Every `@ManyToOne`/`@OneToOne` is `fetch = LAZY`; fetch plans are explicit per use case (join fetch, entity graph or DTO).
- [ ] No more than one collection fetched per query; no bag + collection fetches; `@OrderColumn` or `Set` chosen deliberately.
- [ ] Integration tests assert statement counts for key endpoints.
- [ ] `spring.jpa.open-in-view=false`; DTOs mapped inside the transaction.
- [ ] No remote calls, messaging or sleeps inside `@Transactional` methods; events published after commit or via an outbox.
- [ ] Read-modify-write on shared rows uses atomic SQL, `@Version` or a lock; invariants across rows use SERIALIZABLE, a lock or a constraint.
- [ ] Retries wrap the transaction (not inside it), are bounded, and only cover `40001`/`40P01`/optimistic-lock failures.
- [ ] Rollback rules are deliberate: domain exceptions are unchecked, or `rollbackOn = ALL_EXCEPTIONS`.
- [ ] No self-invocation of `@Transactional`/`@Retryable`/`@Async` methods; no field access through bean proxies.
- [ ] `REQUIRES_NEW` is justified, and the pool is sized for the nesting.
- [ ] IDs: `SEQUENCE` (pooled) or UUIDv7, not `IDENTITY`, for tables with bulk inserts; batching configured and verified.
- [ ] Batch jobs: chunked transactions with `clear()`, `insertMultiple`/`setJdbcBatchSize` for stateless sessions (Hibernate 7), and streaming reads with a fetch size inside a transaction.
- [ ] Pagination: keyset for deep or unbounded lists; never `setMaxResults` with a collection fetch on Hibernate < 7.4.
- [ ] Every FK column used for lookups or cascades has an index (created in migrations, not by `ddl-auto`).
- [ ] Hikari: `maximumPoolSize` from measurement (Little's law × fleet ≤ DB `max_connections` minus headroom), `connectionTimeout` of a few seconds, `maxLifetime` below infrastructure idle timeouts, `leakDetectionThreshold` in non-prod.
- [ ] PostgreSQL guard rails per role: `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`.
