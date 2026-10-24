# 5.4 · Transactions — ACID, Isolation Levels, Locking, Spring `@Transactional`

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** PostgreSQL 18 docs, ch. 13 "Concurrency Control" (MVCC, isolation, explicit locking, SSI); Ports & Grittner, *Serializable Snapshot Isolation in PostgreSQL* (VLDB 2012); Berenson et al., *A Critique of ANSI SQL Isolation Levels* (1995); Spring Framework 7 reference ("Transaction Management", "Resilience Features"); `RollbackOn` Javadoc (`@since 6.2`); Hibernate ORM 7 User Guide (locking); Kleppmann, *Designing Data-Intensive Applications*, ch. 7.
> **Verified stack:** PostgreSQL 18.6 (embedded), pgjdbc 42.7.14, Hibernate ORM 7.4.13.Final, Spring Framework 7.0.10 (`spring-tx`, `spring-orm`, core resilience), HikariCP 7.0.2. Every anomaly below was **reproduced on a real PostgreSQL server**, not described from memory.

---

## 1. ACID, mapped to mechanisms 🔥

| Property | Mechanism in PostgreSQL | What it does **not** give you |
|---|---|---|
| **Atomicity** | MVCC tuple versions plus the commit log (`pg_xact`): a transaction's row versions become visible all at once, or never | Atomicity across *systems* (DB + Kafka + HTTP). That needs the outbox or a saga ([6.3](../06-Spring-Microservices/03-Outbox-Saga-Idempotency.md)) |
| **Consistency** | Constraints (PK, FK, `CHECK`, `UNIQUE`, exclusion), triggers | Business invariants that span rows. Those are the job of isolation or locking (§2–3) |
| **Isolation** | Snapshots (MVCC) + row locks + SSI predicate tracking | Serializability by default: the default is **READ COMMITTED** |
| **Durability** | WAL flushed at commit (`synchronous_commit=on`), replicas (`synchronous_standby_names`) | Durability against losing the primary *with asynchronous replication*: the last commits can vanish on failover |

The JDBC contract on top: `setAutoCommit(false)` starts a transaction scope, and `commit()`/`rollback()` end it. Spring's transaction managers do exactly this on a pooled connection that is **bound to the current thread** for the transaction's duration.

---

## 2. Isolation levels and anomalies — what PostgreSQL really does 🔥

| Level (SQL name) | Dirty read | Non-repeatable read | Phantom | **Lost update** (read-modify-write) | **Write skew** | PostgreSQL implementation |
|---|---|---|---|---|---|---|
| READ UNCOMMITTED | — | possible | possible | possible | possible | Treated as READ COMMITTED (MVCC never shows uncommitted data) |
| **READ COMMITTED** (default) | no | **possible** | possible | **possible** | possible | A new snapshot **per statement**. An UPDATE that hits a row changed concurrently re-evaluates against the newest version ("EvalPlanQual") |
| REPEATABLE READ | no | no | **no** (stricter than the SQL standard) | **detected → `40001`** | **possible** | One snapshot **per transaction** = snapshot isolation; "first updater wins" |
| **SERIALIZABLE** | no | no | no | detected → `40001` | **detected → `40001`** | SSI: snapshot isolation plus tracking of read/write dependencies. Aborts one transaction of a dangerous structure |

**Other databases differ.** In MySQL/InnoDB the default is REPEATABLE READ, but UPDATEs read the latest committed row ("current read"), so an application read-modify-write still loses updates instead of failing. Oracle's "SERIALIZABLE" is snapshot isolation (it allows write skew). SQL Server's READ COMMITTED is lock-based unless `READ_COMMITTED_SNAPSHOT` is on. **Never assume isolation semantics carry over between databases.**

### 2.1 Runnable: every anomaly, reproduced with two JDBC connections

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.tx;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.sql.*;

public class IsolationAnomalies {
    static EmbeddedPostgres pg;

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.ERROR);
        pg = EmbeddedPostgres.builder().start();
        try (var db = pg) {
            nonRepeatableRead(Connection.TRANSACTION_READ_COMMITTED);
            nonRepeatableRead(Connection.TRANSACTION_REPEATABLE_READ);
            lostUpdate(Connection.TRANSACTION_READ_COMMITTED);
            lostUpdate(Connection.TRANSACTION_REPEATABLE_READ);
            atomicIncrement();
            writeSkew(Connection.TRANSACTION_REPEATABLE_READ);
            writeSkew(Connection.TRANSACTION_SERIALIZABLE);
        }
    }

    static void nonRepeatableRead(int isolation) throws SQLException {
        reset();
        try (Connection t1 = tx(isolation); Connection t2 = tx(Connection.TRANSACTION_READ_COMMITTED)) {
            long first = balance(t1);
            exec(t2, "update account set balance = 50 where id = 1"); t2.commit();       // concurrent committed change
            long second = balance(t1);
            t1.commit();
            System.out.printf("%-16s non-repeatable read: T1 read %d, then %d%s%n", name(isolation), first, second,
                first == second ? "  (stable snapshot)" : "  ← changed inside one transaction");
        }
    }

    static void lostUpdate(int isolation) throws SQLException {
        reset();
        try (Connection t1 = tx(isolation); Connection t2 = tx(isolation)) {
            long b1 = balance(t1), b2 = balance(t2);                                       // both read 100
            exec(t1, "update account set balance = " + (b1 + 10) + " where id = 1"); t1.commit();
            try {
                exec(t2, "update account set balance = " + (b2 + 10) + " where id = 1"); t2.commit();
                System.out.printf("%-16s lost update: two +10 deposits, final balance %d%s%n", name(isolation), committedBalance(),
                    committedBalance() == 120 ? "" : "  ← one deposit lost");
            } catch (SQLException e) {
                t2.rollback();
                System.out.printf("%-16s lost update: T2 failed with %s %s%n", name(isolation), e.getSQLState(), firstLine(e));
            }
        }
    }

    static void atomicIncrement() throws SQLException {
        reset();
        try (Connection t1 = tx(Connection.TRANSACTION_READ_COMMITTED); Connection t2 = tx(Connection.TRANSACTION_READ_COMMITTED)) {
            exec(t1, "update account set balance = balance + 10 where id = 1");
            Thread waiter = Thread.ofVirtual().start(() -> {                               // blocks on T1's row lock
                try { exec(t2, "update account set balance = balance + 10 where id = 1"); t2.commit(); }
                catch (SQLException e) { throw new RuntimeException(e); }
            });
            t1.commit();
            join(waiter);
            System.out.printf("%-16s atomic 'balance = balance + 10' twice: final balance %d%n", "READ COMMITTED", committedBalance());
        }
    }

    // Two doctors on call; each transaction checks "at least 2 on call" before going off call.
    static void writeSkew(int isolation) throws SQLException {
        try (Connection c = pg.getPostgresDatabase().getConnection(); Statement s = c.createStatement()) {
            s.execute("drop table if exists doctor; create table doctor(name text primary key, on_call boolean);"
                + "insert into doctor values ('alice', true), ('bob', true)");
        }
        try (Connection t1 = tx(isolation); Connection t2 = tx(isolation)) {
            long seen1 = count(t1), seen2 = count(t2);                                    // both see 2 on call
            if (seen1 >= 2) exec(t1, "update doctor set on_call = false where name = 'alice'");
            if (seen2 >= 2) exec(t2, "update doctor set on_call = false where name = 'bob'");
            t1.commit();
            try {
                t2.commit();
            } catch (SQLException e) {
                t2.rollback();
                System.out.printf("%-16s write skew: T2 commit failed with %s %s%n", name(isolation), e.getSQLState(), firstLine(e));
            }
            try (Connection c = pg.getPostgresDatabase().getConnection()) {
                System.out.printf("%-16s write skew: doctors still on call = %d%n", name(isolation), count(c));
            }
        }
    }

    static Connection tx(int isolation) throws SQLException {
        Connection c = pg.getPostgresDatabase().getConnection();
        c.setAutoCommit(false);
        c.setTransactionIsolation(isolation);
        return c;
    }
    static void reset() throws SQLException {
        try (Connection c = pg.getPostgresDatabase().getConnection(); Statement s = c.createStatement()) {
            s.execute("drop table if exists account; create table account(id int primary key, balance bigint); insert into account values (1, 100)");
        }
    }
    static void exec(Connection c, String sql) throws SQLException { try (Statement s = c.createStatement()) { s.executeUpdate(sql); } }
    static long balance(Connection c) throws SQLException { return single(c, "select balance from account where id = 1"); }
    static long count(Connection c) throws SQLException { return single(c, "select count(*) from doctor where on_call"); }
    static long committedBalance() throws SQLException { try (Connection c = pg.getPostgresDatabase().getConnection()) { return balance(c); } }
    static long single(Connection c, String sql) throws SQLException {
        try (Statement s = c.createStatement(); ResultSet rs = s.executeQuery(sql)) { rs.next(); return rs.getLong(1); }
    }
    static String name(int isolation) {
        return switch (isolation) {
            case Connection.TRANSACTION_READ_COMMITTED -> "READ COMMITTED";
            case Connection.TRANSACTION_REPEATABLE_READ -> "REPEATABLE READ";
            default -> "SERIALIZABLE";
        };
    }
    static String firstLine(SQLException e) { return e.getMessage().lines().findFirst().orElse(""); }
    static void join(Thread t) { try { t.join(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

Output (verified):

```
READ COMMITTED   non-repeatable read: T1 read 100, then 50  ← changed inside one transaction
REPEATABLE READ  non-repeatable read: T1 read 100, then 100  (stable snapshot)
READ COMMITTED   lost update: two +10 deposits, final balance 110  ← one deposit lost
REPEATABLE READ  lost update: T2 failed with 40001 ERROR: could not serialize access due to concurrent update
READ COMMITTED   atomic 'balance = balance + 10' twice: final balance 120
REPEATABLE READ  write skew: doctors still on call = 0
SERIALIZABLE     write skew: T2 commit failed with 40001 ERROR: could not serialize access due to read/write dependencies among transactions
SERIALIZABLE     write skew: doctors still on call = 1
```

What to take away:

1. **READ COMMITTED + read-modify-write in Java = lost updates.** This is the default isolation of almost every Spring app. `account.setBalance(account.getBalance() + 10)` without a lock or version **will** lose money under concurrency.
2. **Atomic SQL is safe even at READ COMMITTED.** `balance = balance + 10` takes the row lock, and the waiting UPDATE re-reads the newest version after the first commits (here 120). Prefer atomic updates (`@Modifying @Query("update … set balance = balance + :x")`) for counters and balances.
3. **REPEATABLE READ turns lost updates into errors** (`40001` on the second writer). You must **retry the whole transaction**.
4. **Write skew survives REPEATABLE READ.** Each transaction read the same snapshot and updated a **different** row, so no row conflict exists. Only SERIALIZABLE (SSI) or explicit locking of the rows you read (`SELECT … FOR UPDATE`) or a constraint catches it. Typical victims: "at least one on call", "no double booking", "balance across accounts ≥ 0".
5. **SERIALIZABLE is practical in PostgreSQL**, as long as every transaction is retryable. SSI doesn't block readers, but under contention the abort rate grows, and long transactions raise false-positive aborts. Keep transactions short, and mark read-only transactions `READ ONLY` (SSI can then skip some tracking).

---

## 3. Locking: pessimistic, optimistic, deadlocks, job queues 🔥

### 3.1 What JPA lock modes become on PostgreSQL (Hibernate 7.4)

| JPA | SQL (verified below) | Blocks | Use |
|---|---|---|---|
| `PESSIMISTIC_READ` | `for share` | Writers (UPDATE/DELETE and `FOR UPDATE`) | Read a row that must not change until commit |
| `PESSIMISTIC_WRITE` | **`for no key update`** | Other writers and lockers, but **not** FK checks | Read-modify-write on a hot row |
| `… , Timeouts.NO_WAIT` (JPA 3.2 `FindOption`) | `… nowait` | Fails immediately with `55P03` | Interactive paths that must not queue |
| query hint `jakarta.persistence.lock.timeout = -2` (`Timeouts.SKIP_LOCKED_MILLI`) | `… skip locked` | Skips locked rows | **Work queues**: N workers claim distinct rows |
| `OPTIMISTIC` / `@Version` | `update … where id=? and version=?` | Nothing; conflict detected at write | Low-contention updates, long "think time" |
| `PESSIMISTIC_FORCE_INCREMENT` / `OPTIMISTIC_FORCE_INCREMENT` | Lock or plain read, plus a version bump | — | Version an **aggregate root** when only children changed |

🧊 **Why `FOR NO KEY UPDATE` rather than `FOR UPDATE`?** A foreign-key check on a child insert takes `FOR KEY SHARE` on the parent row. `FOR UPDATE` conflicts with it, so locking an order would block inserting its order lines; `FOR NO KEY UPDATE` doesn't. Hibernate uses the weaker lock because a JPA write lock doesn't change the key.

### 3.2 Runnable: lock SQL, NOWAIT, SKIP LOCKED, a deadlock, and optimistic locking

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.tx;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.*;
import java.util.concurrent.*;
import net.ttddyy.dsproxy.ExecutionInfo;
import net.ttddyy.dsproxy.QueryInfo;
import net.ttddyy.dsproxy.listener.QueryExecutionListener;
import net.ttddyy.dsproxy.support.ProxyDataSourceBuilder;
import org.hibernate.SessionFactory;
import org.hibernate.Timeouts;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class Locking {
    @Entity(name = "Account") @Table(name = "account")
    public static class Account {
        @Id Long id; long balance;
        @Version int version;                                            // optimistic locking
        protected Account() {}
        Account(long id, long balance) { this.id = id; this.balance = balance; }
    }
    @Entity(name = "Job") @Table(name = "job")
    public static class Job { @Id Long id; String status; }

    static final List<String> sql = Collections.synchronizedList(new ArrayList<>());

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            var capturing = ProxyDataSourceBuilder.create(new HikariDataSource(hc)).listener(new QueryExecutionListener() {
                public void beforeQuery(ExecutionInfo e, List<QueryInfo> q) { sql.add(q.get(0).getQuery()); }
                public void afterQuery(ExecutionInfo e, List<QueryInfo> q) { }
            }).build();
            try (EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo").managedClasses(Account.class, Job.class)
                    .property("hibernate.connection.datasource", capturing)
                    .schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
                SessionFactory sf = emf.unwrap(SessionFactory.class);
                sf.inTransaction(s -> {
                    s.persist(new Account(1, 100)); s.persist(new Account(2, 100));
                    s.createNativeMutationQuery("insert into job(id, status) select g, 'NEW' from generate_series(1, 6) g").executeUpdate();
                });

                // 1. the SQL behind each JPA lock mode
                for (LockModeType mode : List.of(LockModeType.PESSIMISTIC_READ, LockModeType.PESSIMISTIC_WRITE)) {
                    sf.inTransaction(s -> { sql.clear(); s.find(Account.class, 1L, mode); System.out.println("1. " + mode + ": …" + tail(sql.getLast())); });
                }
                sf.inTransaction(s -> { sql.clear(); s.find(Account.class, 1L, LockModeType.PESSIMISTIC_WRITE, Timeouts.NO_WAIT);
                    System.out.println("1. PESSIMISTIC_WRITE + NO_WAIT: …" + tail(sql.getLast())); });

                // 2. NOWAIT against a row another transaction holds
                sf.inTransaction(holder -> {
                    holder.find(Account.class, 1L, LockModeType.PESSIMISTIC_WRITE);
                    try {
                        sf.inTransaction(s -> s.find(Account.class, 1L, LockModeType.PESSIMISTIC_WRITE, Timeouts.NO_WAIT));
                    } catch (PersistenceException e) {
                        System.out.println("2. NOWAIT on a locked row: " + e.getClass().getSimpleName() + " / SQLState " + sqlState(e));
                    }
                });

                // 3. SKIP LOCKED: two workers claim jobs concurrently without blocking each other
                sf.inTransaction(workerA -> {
                    List<Long> a = claim(workerA);
                    List<Long> b = sf.fromTransaction(Locking::claim);
                    System.out.println("3. SKIP LOCKED: worker A claimed " + a + ", worker B claimed " + b + " (no waiting, no overlap)");
                    System.out.println("   …" + tail(sql.stream().filter(q -> q.contains("skip")).findFirst().orElseThrow()));
                });

                // 4. deadlock: two transactions lock the same two rows in opposite order
                CyclicBarrier bothHoldFirstLock = new CyclicBarrier(2);
                try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
                    Future<String> t1 = pool.submit(() -> transfer(sf, 1L, 2L, bothHoldFirstLock));
                    Future<String> t2 = pool.submit(() -> transfer(sf, 2L, 1L, bothHoldFirstLock));
                    List<String> outcomes = new ArrayList<>(List.of(t1.get(), t2.get()));
                    Collections.sort(outcomes);
                    System.out.println("4. opposite lock order: " + outcomes);
                }

                // 5. optimistic locking: two sessions read version N, both write
                EntityManager alice = emf.createEntityManager(), bob = emf.createEntityManager();
                alice.getTransaction().begin(); bob.getTransaction().begin();
                Account a = alice.find(Account.class, 1L), b = bob.find(Account.class, 1L);
                System.out.println("5. both read version " + a.version + " and balance " + a.balance);
                a.balance += 10; sql.clear(); alice.getTransaction().commit();
                System.out.println("   alice commits: " + sql.stream().filter(q -> q.startsWith("update")).findFirst().orElseThrow());
                b.balance += 20;
                try { bob.getTransaction().commit(); }
                catch (RollbackException e) {
                    System.out.println("   bob commits:   " + e.getCause().getClass().getSimpleName() + ": " + e.getCause().getMessage().lines().findFirst().orElse(""));
                }
                alice.close(); bob.close();
                System.out.println("   final: " + sf.fromTransaction(s -> { var acc = s.find(Account.class, 1L); return "balance " + acc.balance + ", version " + acc.version; }));
            }
        }
    }

    static List<Long> claim(org.hibernate.Session s) {
        return s.createSelectionQuery("from Job j where j.status = 'NEW' order by j.id", Job.class)
            .setLockMode(LockModeType.PESSIMISTIC_WRITE)
            .setHint("jakarta.persistence.lock.timeout", Timeouts.SKIP_LOCKED_MILLI)
            .setMaxResults(2).getResultList().stream().map(j -> j.id).toList();
    }

    static String transfer(SessionFactory sf, long from, long to, CyclicBarrier barrier) {
        try {
            sf.inTransaction(s -> {
                s.find(Account.class, from, LockModeType.PESSIMISTIC_WRITE);
                await(barrier);                                               // both now hold their first row
                s.find(Account.class, to, LockModeType.PESSIMISTIC_WRITE);    // …and wait for each other's
            });
            return "committed";
        } catch (PersistenceException e) {
            return e.getClass().getSimpleName() + " (SQLState " + sqlState(e) + ")";
        }
    }

    static String sqlState(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) if (t instanceof java.sql.SQLException se) return se.getSQLState();
        return "?";
    }
    static String tail(String q) { return q.substring(q.indexOf(" where ")); }
    static void await(CyclicBarrier b) { try { b.await(); } catch (Exception e) { throw new RuntimeException(e); } }
}
```

Output (verified):

```
1. PESSIMISTIC_READ: … where a1_0.id=? for share of a1_0
1. PESSIMISTIC_WRITE: … where a1_0.id=? for no key update of a1_0
1. PESSIMISTIC_WRITE + NO_WAIT: … where a1_0.id=? for no key update of a1_0 nowait
2. NOWAIT on a locked row: LockTimeoutException / SQLState 55P03
3. SKIP LOCKED: worker A claimed [1, 2], worker B claimed [3, 4] (no waiting, no overlap)
   … where j1_0.status='NEW' order by j1_0.id fetch first ? rows only for no key update of j1_0 skip locked
4. opposite lock order: [PessimisticLockException (SQLState 40P01), committed]
5. both read version 0 and balance 100
   alice commits: update account set balance=?,version=? where id=? and version=?
   bob commits:   OptimisticLockException: Unexpected row count (expected row count 1 but was 0) [update account set balance=?,version=? where id=? and version=?] for entity [demo.tx.Locking$Account with id '1']
   final: balance 110, version 1
```

* **Deadlocks are detected, not prevented.** PostgreSQL waits `deadlock_timeout` (default 1 s), then runs the detector and aborts one victim with `40P01`, which Hibernate maps to `PessimisticLockException`. Prevent them by **locking in a consistent order** (sort IDs before locking, e.g. lower account ID first in transfers), keeping transactions short, and setting `lock_timeout` so waits fail fast.
* **`SKIP LOCKED` is how you build a correct DB-backed queue** (outbox relays, schedulers, batch workers): `select … where status = 'NEW' order by id limit n for update skip locked`, then process and update the claimed rows in the same transaction. Two workers never get the same row, and neither waits.
* **Optimistic locking costs nothing until there's a conflict.** The losing writer's `UPDATE … where version = 0` matches 0 rows, so Hibernate throws `OptimisticLockException` (Spring translates it to `ObjectOptimisticLockingFailureException`). The **only correct reaction is to retry the whole unit of work** (re-read, re-apply, re-validate), or to report the conflict to the user (HTTP `409`, or `412` with `If-Match` ETags derived from the version).

| Choose… | When |
|---|---|
| Atomic SQL (`set x = x + ?`) | Counters, balances, inventory decrements with `where stock >= ?` |
| Optimistic (`@Version`) | Contention is rare; user edits forms (think time); REST resources with ETags |
| Pessimistic (`FOR NO KEY UPDATE`) | Hot rows with frequent conflicts, where retries would waste work; short transactions only |
| `SKIP LOCKED` | Multiple consumers draining a work table |
| SERIALIZABLE | Invariants spanning rows or predicates (write skew) that you can't express as a constraint |
| Advisory locks (`pg_advisory_xact_lock(key)`) | Mutual exclusion on something that isn't a row (a tenant-wide job, a migration) |

---

## 4. Spring `@Transactional`: the proxy, the manager, the rules 🔥

```
caller ──► CGLIB proxy (bean "bank") ──► TransactionInterceptor ──► PlatformTransactionManager.getTransaction(def)
                                              │                          JpaTransactionManager: EntityManager + JDBC connection,
                                              │                          bound to the THREAD via TransactionSynchronizationManager
                                              ▼
                                         target.method()  ──► commit() / rollback() per rollback rules ──► unbind, release connection
```

* **It is AOP.** Only calls that **go through the proxy** are intercepted: `this.method()` inside the bean is a plain Java call (self-invocation). Spring Boot proxies classes with CGLIB by default. Since Spring 6.0, `@Transactional` also applies to `protected` and package-visible methods on class-based proxies, but never to `private` methods, and never to `final` methods or classes (CGLIB can't override them).
* **The transaction lives in `ThreadLocal`s** (`TransactionSynchronizationManager`). It does **not** follow you into `CompletableFuture.supplyAsync`, `@Async` methods, `parallelStream()` or new threads. Virtual threads are fine: one thread per request. Reactive code uses `ReactiveTransactionManager` with the Reactor `Context` instead.
* **Managers:** `JpaTransactionManager` (JPA/Hibernate, also exposes the connection to `JdbcTemplate`/`JdbcClient`), `JdbcTransactionManager`/`DataSourceTransactionManager` (plain JDBC), `JtaTransactionManager` (XA), and the R2DBC/Mongo/Kafka managers.

| Propagation | Existing tx? | Behaviour | Trap |
|---|---|---|---|
| `REQUIRED` (default) | join / create | One physical transaction; an inner failure marks it **rollback-only** | Catching the inner exception → `UnexpectedRollbackException` at commit (verified) |
| `REQUIRES_NEW` | suspend + create | A second, independent physical transaction **on a second connection** | Needs **two pooled connections per request**, so the pool can deadlock (verified) |
| `NESTED` | savepoint / create | Rollback to a savepoint | JDBC managers support it; with JPA the persistence context isn't rolled back to the savepoint |
| `SUPPORTS` | join / none | Runs non-transactionally if there's no tx | Lazy loading behaves differently depending on the caller |
| `NOT_SUPPORTED` | suspend | Runs without a tx | Also holds the suspended tx's connection |
| `MANDATORY` | join / **throw** | Asserts a tx exists | — |
| `NEVER` | **throw** / none | Asserts none exists | — |

**Rollback rules:** by default Spring rolls back on `RuntimeException` and `Error`, and **commits on checked exceptions** (the EJB heritage). Override per method with `rollbackFor`/`noRollbackFor`, or globally (Spring **6.2+**) with `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)`.

**`readOnly = true`** (verified below) does three things with `JpaTransactionManager` + Hibernate:

1. a read-only `Session`: no snapshots, no dirty checking ([5.2 §2](02-JPA-Hibernate-Persistence-Context-Internals.md#2-dirty-checking-cost-and-alternatives-));
2. `FlushMode.MANUAL`: no auto-flush before queries;
3. `Connection.setReadOnly(true)`, which pgjdbc turns into a read-only transaction, so **writes fail at the database** with `25006`. It is also the hook that routing data sources use to send reads to replicas.

### 4.1 Runnable: the ten behaviours every Spring developer gets bitten by

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.tx;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.sql.Connection;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import javax.sql.DataSource;
import org.hibernate.Session;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.*;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.orm.jpa.EntityManagerHolder;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.resilience.annotation.EnableResilientMethods;
import org.springframework.resilience.annotation.Retryable;
import org.springframework.transaction.annotation.*;
import org.springframework.transaction.support.TransactionSynchronizationManager;

public class SpringTransactions {
    @Entity(name = "Account") @Table(name = "account")
    public static class Account {
        @Id Long id; long balance; @Version int version;
        protected Account() {}
        Account(long id, long balance) { this.id = id; this.balance = balance; }
    }
    @Entity(name = "AuditEntry") @Table(name = "audit_entry")
    public static class AuditEntry {
        @Id @GeneratedValue Long id; String message;
        protected AuditEntry() {}
        AuditEntry(String m) { message = m; }
    }

    public static class AuditLog {
        @PersistenceContext EntityManager em;
        @Transactional(propagation = Propagation.REQUIRES_NEW)                // suspends the caller's tx, opens its own
        public void record(String message) { em.persist(new AuditEntry(message)); }
        @Transactional                                                         // REQUIRED: joins the caller's tx
        public void validate() { throw new IllegalStateException("validation failed"); }
    }

    public static class Bank {
        @PersistenceContext EntityManager em;
        final AuditLog audit;
        public Bank(AuditLog audit) { this.audit = audit; }

        @Transactional
        public void withdrawThenFail(long amount) {
            audit.record("withdrawal of " + amount + " requested");
            em.find(Account.class, 1L).balance -= amount;
            throw new IllegalStateException("fraud check failed");
        }
        @Transactional
        public void withdrawThenChecked(long amount) throws Exception {
            em.find(Account.class, 1L).balance -= amount;
            throw new Exception("missing paperwork");                          // checked exception
        }
        @Transactional(rollbackFor = Exception.class)
        public void withdrawThenCheckedRollbackFor(long amount) throws Exception {
            em.find(Account.class, 1L).balance -= amount;
            throw new Exception("missing paperwork");
        }
        @org.springframework.beans.factory.annotation.Autowired @Lazy Bank self; // self-injection: the proxy, not `this`

        @Transactional
        public String selfInvocation() {
            int outer = backendPid();
            int viaThis = this.requiresNew();                                  // plain Java call: no proxy, no interceptor
            int viaProxy = self.requiresNew();                                 // through the proxy: REQUIRES_NEW applies
            return "this.requiresNew() ran on the caller's connection: " + (viaThis == outer)
                + ", self.requiresNew() ran on the caller's connection: " + (viaProxy == outer);
        }
        @Transactional(propagation = Propagation.REQUIRES_NEW)
        public int requiresNew() { return backendPid(); }

        @Transactional
        public void swallowInnerFailure() {
            em.find(Account.class, 1L).balance += 1;
            try { audit.validate(); } catch (IllegalStateException ignored) { }  // inner REQUIRED marked the tx rollback-only
        }
        @Transactional(readOnly = true)
        public String readOnlyDetails() {
            Session s = em.unwrap(Session.class);
            return "session.defaultReadOnly=" + s.isDefaultReadOnly() + ", flushMode=" + s.getHibernateFlushMode()
                + ", connection.readOnly=" + s.doReturningWork(Connection::isReadOnly);
        }
        @Transactional(readOnly = true)
        public void writeInReadOnly() { em.createNativeQuery("update account set balance = 0").executeUpdate(); }
        @Transactional
        public void holdConnectionThenAudit(CyclicBarrier bothHoldOne) throws Exception {
            em.find(Account.class, 1L);                                         // this tx holds a pooled connection
            bothHoldOne.await();
            audit.record("needs a second connection");                         // REQUIRES_NEW needs another one
        }
        @Transactional
        public void deposit(long amount) { em.find(Account.class, 1L).balance += amount; }
        @Transactional(readOnly = true)
        public String state() {
            var a = em.find(Account.class, 1L);
            long audits = em.createQuery("select count(a) from AuditEntry a", Long.class).getSingleResult();
            return "balance=" + a.balance + ", audit rows=" + audits;
        }
        int backendPid() {                                                     // identifies the physical DB connection
            return em.unwrap(Session.class).doReturningWork(c -> {
                try (var st = c.createStatement(); var rs = st.executeQuery("select pg_backend_pid()")) { rs.next(); return rs.getInt(1); }
            });
        }
    }

    public static class Deposits {                                             // retry OUTSIDE the transaction
        final Bank bank; final AtomicInteger attempts = new AtomicInteger();
        public Deposits(Bank bank) { this.bank = bank; }
        @Retryable(includes = OptimisticLockingFailureException.class, maxRetries = 20, delay = 2, jitter = 2)
        public void deposit(long amount) { attempts.incrementAndGet(); bank.deposit(amount); }
        public int attempts() { return attempts.get(); }                      // never read fields through a CGLIB proxy
    }

    static EmbeddedPostgres pg;

    @Configuration
    static class Common {
        @Bean(destroyMethod = "close") DataSource dataSource() {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            hc.setMaximumPoolSize(2);
            hc.setConnectionTimeout(1000);
            return new HikariDataSource(hc);
        }
        @Bean LocalContainerEntityManagerFactoryBean entityManagerFactory(DataSource ds) {
            var f = new LocalContainerEntityManagerFactoryBean();
            f.setDataSource(ds);
            f.setManagedTypes(org.springframework.orm.jpa.persistenceunit.PersistenceManagedTypes.of(Account.class.getName(), AuditEntry.class.getName()));
            f.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
            f.setJpaPropertyMap(Map.of("hibernate.hbm2ddl.auto", "create-drop"));
            return f;
        }
        @Bean JpaTransactionManager transactionManager(EntityManagerFactory emf) { return new JpaTransactionManager(emf); }
        @Bean AuditLog auditLog() { return new AuditLog(); }
        @Bean Bank bank(AuditLog audit) { return new Bank(audit); }
        @Bean Deposits deposits(Bank bank) { return new Deposits(bank); }
    }
    @Configuration @EnableTransactionManagement @EnableResilientMethods @Import(Common.class)
    static class DefaultRules { }
    @Configuration @EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS) @Import(Common.class)
    static class RollbackOnAllExceptions { }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.OFF);
        pg = EmbeddedPostgres.builder().start();
        try (var db = pg) {
            try (var ctx = new AnnotationConfigApplicationContext(DefaultRules.class)) {
                Bank bank = ctx.getBean(Bank.class);
                ctx.getBean(EntityManagerFactory.class).unwrap(org.hibernate.SessionFactory.class).inTransaction(s -> s.persist(new Account(1, 100)));

                attempt(() -> bank.withdrawThenFail(30));
                System.out.println("1. RuntimeException + REQUIRES_NEW audit: " + bank.state());
                attempt(() -> bank.withdrawThenChecked(30));
                System.out.println("2. checked exception, default rules:     " + bank.state());
                attempt(() -> bank.withdrawThenCheckedRollbackFor(30));
                System.out.println("3. checked exception, rollbackFor:       " + bank.state());
                System.out.println("4. " + bank.selfInvocation());
                System.out.println("5. inner REQUIRED method failed, outer caught it and returned normally:");
                attempt(() -> bank.swallowInnerFailure());
                System.out.println("6. readOnly=true: " + bank.readOnlyDetails());
                attempt(() -> bank.writeInReadOnly());
                System.out.println("7. two concurrent REQUIRES_NEW callers, pool size 2:");

                CyclicBarrier barrier = new CyclicBarrier(2);
                try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
                    var f1 = pool.submit(() -> attempt(() -> bank.holdConnectionThenAudit(barrier)));
                    var f2 = pool.submit(() -> attempt(() -> bank.holdConnectionThenAudit(barrier)));
                    f1.get(); f2.get();
                }

                Deposits deposits = ctx.getBean(Deposits.class);
                long before = Long.parseLong(bank.state().replaceAll("balance=(\\d+).*", "$1"));
                try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
                    for (int t = 0; t < 4; t++) pool.submit(() -> { for (int i = 0; i < 25; i++) deposits.deposit(1); });
                }
                System.out.printf("8. 100 concurrent deposits with @Retryable: balance %d → %s, attempts=%d%n",
                    before, bank.state().replaceAll("balance=(\\d+).*", "$1"), deposits.attempts());

                // 9. Open Session in View: what OpenEntityManagerInViewInterceptor does around each web request
                var emf = ctx.getBean(EntityManagerFactory.class);
                var hikari = ((HikariDataSource) ctx.getBean(DataSource.class)).getHikariPoolMXBean();
                System.out.println("9. hibernate.connection.handling_mode set by Spring: " + emf.getProperties().get("hibernate.connection.handling_mode"));
                bank.state();
                System.out.println("    no OSIV:   after the @Transactional call returned, active connections = " + hikari.getActiveConnections());
                EntityManager requestScoped = emf.createEntityManager();
                TransactionSynchronizationManager.bindResource(emf, new EntityManagerHolder(requestScoped));   // interceptor preHandle
                try {
                    bank.state();
                    System.out.println("    with OSIV: after the @Transactional call returned, active connections = " + hikari.getActiveConnections()
                        + "  ← held while the view/JSON renders");
                } finally {
                    TransactionSynchronizationManager.unbindResource(emf);                                       // interceptor afterCompletion
                    requestScoped.close();
                }
                System.out.println("    with OSIV: after the request completed, active connections = " + hikari.getActiveConnections());
            }
            try (var ctx = new AnnotationConfigApplicationContext(RollbackOnAllExceptions.class)) {
                Bank bank = ctx.getBean(Bank.class);
                ctx.getBean(EntityManagerFactory.class).unwrap(org.hibernate.SessionFactory.class).inTransaction(s -> s.persist(new Account(1, 100)));
                attempt(() -> bank.withdrawThenChecked(30));
                System.out.println("10. checked exception, rollbackOn=ALL_EXCEPTIONS: " + bank.state());
            }
        }
    }

    interface Action { void run() throws Exception; }
    static Void attempt(Action a) {
        try { a.run(); }
        catch (Exception e) {
            Throwable root = e; while (root.getCause() != null) root = root.getCause();
            String msg = root.getMessage().lines().findFirst().orElse("");
            if (msg.contains("request timed out")) msg = msg.replaceAll(" after \\d+ms.*", " after ~1000ms");
            System.out.println("   threw " + e.getClass().getSimpleName() + (root != e ? " ← " + root.getClass().getSimpleName() : "") + ": " + msg);
        }
        return null;
    }
    static String sqlState(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) if (t instanceof java.sql.SQLException se) return se.getSQLState();
        return "?";
    }
}
```

One verified run (the attempt count in line 8 varies between runs; everything else is deterministic):

```
   threw IllegalStateException: fraud check failed
1. RuntimeException + REQUIRES_NEW audit: balance=100, audit rows=1
   threw Exception: missing paperwork
2. checked exception, default rules:     balance=70, audit rows=1
   threw Exception: missing paperwork
3. checked exception, rollbackFor:       balance=70, audit rows=1
4. this.requiresNew() ran on the caller's connection: true, self.requiresNew() ran on the caller's connection: false
5. inner REQUIRED method failed, outer caught it and returned normally:
   threw UnexpectedRollbackException: Transaction silently rolled back because it has been marked as rollback-only
6. readOnly=true: session.defaultReadOnly=true, flushMode=MANUAL, connection.readOnly=true
   threw GenericJDBCException ← PSQLException: ERROR: cannot execute UPDATE in a read-only transaction
7. two concurrent REQUIRES_NEW callers, pool size 2:
   threw CannotCreateTransactionException ← SQLTransientConnectionException: HikariPool-1 - Connection is not available, request timed out after ~1000ms
   threw CannotCreateTransactionException ← SQLTransientConnectionException: HikariPool-1 - Connection is not available, request timed out after ~1000ms
8. 100 concurrent deposits with @Retryable: balance 70 → 170, attempts=171
9. hibernate.connection.handling_mode set by Spring: DELAYED_ACQUISITION_AND_HOLD
    no OSIV:   after the @Transactional call returned, active connections = 0
    with OSIV: after the @Transactional call returned, active connections = 1  ← held while the view/JSON renders
    with OSIV: after the request completed, active connections = 0
   threw Exception: missing paperwork
10. checked exception, rollbackOn=ALL_EXCEPTIONS: balance=100, audit rows=0
```

Line by line:

1. **`REQUIRES_NEW` committed independently.** The audit row survived the outer rollback, and the balance was restored. This is the correct pattern for audit/attempt logs, and the mechanism behind the pool deadlock in line 7.
2. **A checked exception committed the withdrawal** (100 → 70) even though the method threw. This is a classic production bug.
3. **`rollbackFor = Exception.class`** rolled it back (still 70).
4. **Self-invocation ignored `REQUIRES_NEW`.** `this.requiresNew()` ran on the caller's connection (the same `pg_backend_pid()`). Through the injected proxy it got a new connection, so a new transaction. Fixes: move the method to another bean (cleanest), inject the proxy (`@Lazy` self-injection, as here), use `TransactionTemplate`, or use AspectJ weaving (`mode = ASPECTJ`).
5. **Swallowing an exception from an inner `REQUIRED` method doesn't save the transaction.** The inner interceptor already marked it rollback-only, so the outer commit throws `UnexpectedRollbackException`, and the caller learns about it far from the cause. Either let it propagate, or give the inner work its own transaction (`REQUIRES_NEW`/`NESTED`), or validate before writing.
6. **`readOnly = true`** set the Hibernate session read-only and `MANUAL`, and made the JDBC connection read-only. PostgreSQL then rejected a native UPDATE (`25006`, surfaced as `GenericJDBCException`). A failed statement inside a JPA transaction also marks it rollback-only.
7. **Pool deadlock from `REQUIRES_NEW`.** Two concurrent requests each held 1 of the 2 connections and each needed a second one for the audit. Both waited for `connectionTimeout` and failed. Under load this happens with any pool size: the rule is `maxPoolSize ≥ threads × (1 + nested REQUIRES_NEW depth)`, or avoid nested new transactions on hot paths ([5.1 §3](01-JDBC-HikariCP-Connection-Pooling.md)).
8. **Spring 7's built-in `@Retryable`** (`org.springframework.resilience`, enabled with `@EnableResilientMethods`) retried `OptimisticLockingFailureException`. 100 concurrent deposits all landed (+100); five runs needed 147–173 attempts, i.e. 47–73 optimistic-lock retries per 100 deposits with only 4 concurrent writers. **The retry must wrap the transaction, not run inside it**, which is why it sits on a separate `Deposits` bean that calls the `@Transactional` method. A retry inside the same transaction reuses a rollback-only transaction and stale persistence context.
9. **Open Session in View holds the connection** (see §6).
10. **`rollbackOn = ALL_EXCEPTIONS`** (in a second application context) made the same checked exception roll back (balance stayed 100).

🧊 **A trap this demo hit while being written:** reading or writing a **field** through a CGLIB proxy touches the *proxy's* copy of the field, which is never initialized, not the target bean's. `bank.self = bank` from outside and `deposits.attempts.get()` both failed (`NullPointerException`) until they were replaced with injection and a method call. Never access bean state through fields from outside the bean.

---

## 5. Transactions and the outside world ⚡

* **Never do remote I/O inside a database transaction** (HTTP calls, Kafka sends, email). The connection and its row locks are held for the duration of the remote call, and a commit failure after a successful remote call leaves the systems inconsistent ("dual write").
* **Publish after commit:** `@TransactionalEventListener(phase = AFTER_COMMIT)` or `TransactionSynchronization.afterCommit()`. This is still *not atomic* (the process can die between commit and publish). For guaranteed delivery, write an **outbox** row in the same transaction and relay it (the transactional outbox, [6.3](../06-Spring-Microservices/03-Outbox-Saga-Idempotency.md)).
* **Timeouts at every layer:**
  * `@Transactional(timeout = 5)` sets Hibernate/JDBC query timeouts for the remaining time;
  * PostgreSQL `statement_timeout`, `lock_timeout`, and `idle_in_transaction_session_timeout` (which kills sessions that went idle mid-transaction and still hold locks);
  * Hikari `connectionTimeout`.
* **Retries:** only retry **idempotent** units of work or failures with a known-safe SQLState: `40001` serialization failure, `40P01` deadlock, optimistic lock. Add back-off with jitter and a bounded attempt count.

---

## 6. Open Session in View (OSIV) ⚡

Spring Boot registers `OpenEntityManagerInViewInterceptor` for web apps unless you set `spring.jpa.open-in-view` (the property defaults to `true`). It logs this at startup (string verified in Boot 4.1.2):

> `spring.jpa.open-in-view is enabled by default. Therefore, database queries may be performed during view rendering. Explicitly configure spring.jpa.open-in-view to disable this warning`

**What it really costs (line 9 above).** Spring's `HibernateJpaVendorAdapter` configures `hibernate.connection.handling_mode = DELAYED_ACQUISITION_AND_HOLD`. With OSIV, the request-scoped `EntityManager` therefore **keeps the JDBC connection after the `@Transactional` method returns**: 1 active connection while the controller continues, Jackson serializes and lazy loads fire, versus 0 without OSIV. In practice:

* connection hold time = **whole request**, not just the transaction. A slow client, a remote call after the service layer, or a large JSON serialization multiplies the pool size you need;
* lazy loads during serialization run **outside any transaction** (auto-commit, one statement each). That is hidden N+1 ([5.3 §2](03-Performance-NPlus1-Cartesian-Projections.md#2-the-n1-select-problem-)).

**Recommendation:** `spring.jpa.open-in-view=false` for APIs. Fetch what each endpoint needs inside the service layer (join fetch, entity graph or DTO), and map to DTOs before leaving the transaction. Turning it off makes `LazyInitializationException` show you exactly where the plan was missing.

---

## 7. Production failure modes & diagnostics (transactions & locking)

| Symptom | Likely cause | Confirm with | Fix |
|---|---|---|---|
| Money/stock counts drift under load; no errors | Lost updates (read-modify-write at READ COMMITTED) | Reproduce with two transactions; audit trail | Atomic SQL, `@Version`, or `FOR NO KEY UPDATE` |
| Sporadic `40001 could not serialize access` | REPEATABLE READ/SERIALIZABLE conflicts | Logs by SQLState | Retry the whole transaction with back-off; reduce transaction scope |
| `40P01 deadlock detected` | Inconsistent lock order | PG log shows both statements (`log_lock_waits=on`) | Lock in sorted order; shorter transactions |
| Requests hang, then `Connection is not available, request timed out` | Pool exhausted: long transactions, OSIV, `REQUIRES_NEW` nesting | Hikari `active`/`pending` metrics, thread dump (threads in `HikariPool.getConnection`) | Shorter transactions, OSIV off, pool ≥ concurrency × nesting |
| `UnexpectedRollbackException: Transaction silently rolled back…` | Inner `REQUIRED` failure caught by the outer method | Stack trace of the inner exception (log it!) | Propagate, `REQUIRES_NEW`, or validate first |
| Data saved although the method threw | Checked exception + default rollback rules | Exception type | `rollbackFor`, or `RollbackOn.ALL_EXCEPTIONS` (6.2+) |
| `@Transactional` "doesn't work" | Self-invocation, `private`/`final` method, bean not a Spring bean, wrong manager | `AopUtils.isAopProxy(bean)`; `TransactionSynchronizationManager.isActualTransactionActive()` in the method | Call through the proxy; move to another bean |
| `idle in transaction` sessions holding locks | Remote calls or user think time inside a transaction; leaked connection | `pg_stat_activity` (state, `xact_start`), `pg_blocking_pids()` | Move I/O out of the transaction; `idle_in_transaction_session_timeout`; Hikari `leakDetectionThreshold` |
| Lock waits spike on one row | Hot row (global counter, "last ID" table) | `pg_locks` joined with `pg_stat_activity` | Atomic updates, sharded counters, sequences, `SKIP LOCKED` |
| Writes rejected with `25006` | Write in a `readOnly` transaction (or routed to a replica) | SQLState | Fix the transaction boundary |
| `ObjectOptimisticLockingFailureException` storms | High contention on versioned aggregates | Retry metrics | Smaller aggregates, pessimistic locking for hot rows, retry with jitter |

**PostgreSQL toolkit:**

```sql
-- who blocks whom
select pid, pg_blocking_pids(pid) as blocked_by, state, now() - xact_start as tx_age, left(query, 80)
from pg_stat_activity where datname = current_database() and state <> 'idle' order by xact_start;
-- long or idle-in-transaction sessions
select pid, usename, state, now() - state_change as idle_for from pg_stat_activity where state = 'idle in transaction';
-- per-role guard rails
alter role app set lock_timeout = '3s';
alter role app set statement_timeout = '15s';
alter role app set idle_in_transaction_session_timeout = '60s';
```

**Spring logging:** `logging.level.org.springframework.orm.jpa.JpaTransactionManager=debug` logs "Creating new transaction…", "Participating in existing transaction", "Suspending current transaction" and "Initiating transaction rollback", which are the fastest way to see propagation in action.

---

## 8. Interview Q&A

<details><summary><b>Q1. 🔥 What is a lost update? Show how it happens in a Spring/JPA app and three ways to prevent it.</b></summary>

Two transactions read the same value, compute a new value in the application, and both write: the second write overwrites the first. With JPA, `account.setBalance(account.getBalance() + x)` at READ COMMITTED does exactly this (measured: 100 + 10 + 10 = 110). Prevent it with an atomic SQL update (`set balance = balance + :x`), optimistic locking (`@Version`, then retry), a pessimistic lock (`find(…, PESSIMISTIC_WRITE)` → `for no key update`), or REPEATABLE READ on PostgreSQL (the second writer gets `40001`, then retry).
</details>

<details><summary><b>Q2. 🔥 What is write skew, and which isolation level prevents it in PostgreSQL?</b></summary>

Two transactions read an overlapping set (for example "2 doctors on call"), each decides based on it, and each updates a *different* row. There is no write-write conflict, so snapshot isolation (PostgreSQL's REPEATABLE READ, Oracle's SERIALIZABLE) lets both commit and the invariant breaks (measured: 0 on call). PostgreSQL SERIALIZABLE (SSI) detects the read/write dependency cycle and aborts one transaction with `40001`. Alternatives: lock the rows you read (`FOR UPDATE`), or materialize the conflict (a row or constraint both transactions must touch).
</details>

<details><summary><b>Q3. ⚡ Why does PostgreSQL's REPEATABLE READ throw where MySQL's REPEATABLE READ silently overwrites?</b></summary>

PostgreSQL's REPEATABLE READ is snapshot isolation with "first updater wins": updating a row that a concurrent committed transaction changed after your snapshot raises `40001`. InnoDB performs UPDATEs as "current reads" of the latest committed version, so the statement succeeds, and an application-level read-modify-write loses the other update. Same SQL name, different guarantees.
</details>

<details><summary><b>Q4. 🔥 Optimistic vs pessimistic locking: how does each work in JPA, and when do you pick which?</b></summary>

Optimistic: a `@Version` column, and every UPDATE includes `where version = ?`. Zero affected rows means a conflict (`OptimisticLockException`), and you retry or report `409`. There are no DB locks, so it suits low contention and long think times. Pessimistic: `PESSIMISTIC_WRITE` issues `SELECT … FOR NO KEY UPDATE` (PostgreSQL), and others wait (or fail with `NOWAIT`). It suits hot rows where retries would waste work, inside short transactions. Both need deadlock and timeout handling for pessimistic paths, and retry handling for optimistic ones.
</details>

<details><summary><b>Q5. 🔥 Explain `@Transactional` self-invocation. Why does it happen and how do you fix it?</b></summary>

Spring implements `@Transactional` with a proxy that wraps the bean. External calls go proxy → `TransactionInterceptor` → target. A call from inside the target (`this.other()`) never touches the proxy, so the annotation on `other()` is ignored (measured: same DB connection, no `REQUIRES_NEW`). Fixes: move the method to another bean, call through an injected proxy (`@Lazy` self-injection or `ObjectProvider`), use `TransactionTemplate`, or use AspectJ compile/load-time weaving.
</details>

<details><summary><b>Q6. ⚡ A method throws `IOException` inside `@Transactional`. Is the transaction rolled back?</b></summary>

Not by default. Spring rolls back on unchecked exceptions (`RuntimeException`, `Error`) and commits on checked ones (measured). Use `@Transactional(rollbackFor = Exception.class)`, or since Spring 6.2 `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)` for the whole application.
</details>

<details><summary><b>Q7. ⚡ What does `@Transactional(readOnly = true)` actually do with Hibernate and PostgreSQL?</b></summary>

`JpaTransactionManager`/`HibernateJpaDialect` set the session to default read-only (no snapshots, no dirty checking) and `FlushMode.MANUAL` (no flushes), and call `Connection.setReadOnly(true)`. pgjdbc turns that into a read-only transaction, so writes fail with `25006`. It is also the signal for replica routing (`AbstractRoutingDataSource` + `LazyConnectionDataSourceProxy`). All four effects were verified in §4.1.
</details>

<details><summary><b>Q8. 🔥 How can `REQUIRES_NEW` take down a service under load?</b></summary>

`REQUIRES_NEW` suspends the outer transaction **while keeping its connection checked out**, and needs a second connection. If every pool connection is held by an outer transaction waiting for its inner one, nobody can proceed until `connectionTimeout` (measured with pool size 2 and two concurrent requests: both failed). Size the pool for nesting, avoid `REQUIRES_NEW` on hot paths, or restructure (audit after commit, an outbox).
</details>

<details><summary><b>Q9. ⚡ Why should a retry for optimistic-lock failures be outside the transaction?</b></summary>

After the failure the transaction is rollback-only and the persistence context holds stale, possibly half-modified entities. Retrying inside it can't succeed. The retry must start a fresh transaction that re-reads the data: put `@Retryable` (Spring 7 core, or Spring Retry/Resilience4j) on a caller bean that invokes the `@Transactional` method. Retry only idempotent work, and bound it with back-off and jitter.
</details>

<details><summary><b>Q10. ⚡ What does Open Session in View cost, and what do you replace it with?</b></summary>

The `EntityManager` stays open for the whole request, and with Spring's `DELAYED_ACQUISITION_AND_HOLD` connection handling the **JDBC connection stays checked out** after the transaction ends (measured: 1 active connection until request completion vs 0). Lazy loads during serialization also run as auto-commit statements outside any transaction (hidden N+1). Replace it with explicit fetch plans in the service layer and DTO mapping inside the transaction, and set `spring.jpa.open-in-view=false`.
</details>

<details><summary><b>Q11. 🧊 Why does Hibernate lock with `FOR NO KEY UPDATE` instead of `FOR UPDATE` on PostgreSQL?</b></summary>

`FOR UPDATE` conflicts with the `FOR KEY SHARE` lock that PostgreSQL's foreign-key checks take on the referenced parent row. A `FOR UPDATE` on an order would block concurrent inserts of its order lines. A JPA write lock doesn't modify the primary key, so the weaker `FOR NO KEY UPDATE` gives the needed exclusion against other writers without blocking FK checks.
</details>
