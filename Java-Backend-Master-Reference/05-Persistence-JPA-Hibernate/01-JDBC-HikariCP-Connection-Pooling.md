# 5.1 · JDBC Internals, HikariCP & Connection-Pool Sizing

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** JDBC 4.3 specification; PostgreSQL JDBC driver (pgjdbc) docs: `prepareThreshold`, `reWriteBatchedInserts`, `defaultRowFetchSize`; HikariCP README, "About Pool Sizing" wiki and `CHANGES` file (6.x/7.x); PostgreSQL docs (connection model, `max_connections`, `statement_timeout`); Little's Law.
> **Verified stack (run 2):** JDK 25.0.4.1 · Spring Boot 4.1.2 BOM · **HikariCP 7.0.2** · **pgjdbc 42.7.14** · **PostgreSQL 18.6** (real server binaries, started embedded via `io.zonky.test:embedded-postgres` 2.2.2 on Windows). Numbers are from this laptop (12 logical CPUs). PostgreSQL runs on the same machine, so network latency is ~0 and real deployments are slower per round trip.

---

## 1. What a JDBC call really costs 🔥

```
 app thread ─► Connection (TCP socket + server session) ─► PostgreSQL BACKEND PROCESS (one OS process per connection!)
                     │
   new connection:   TCP handshake (+TLS) + startup packet + auth (SCRAM) + backend fork + session init  ≈ 1–20 ms+
   per statement:    1 network round trip (simple) or Parse/Bind/Execute (extended protocol, often pipelined)
   per transaction:  BEGIN … COMMIT  → WAL flush (fsync) at COMMIT ≈ 0.1–5 ms depending on storage
```

| JDBC concept | What it does underneath | Production rule |
|---|---|---|
| `DataSource.getConnection()` | With a pool: borrow an already-open session. Without: open a new socket + backend | Always pool. Never `DriverManager` in services |
| `PreparedStatement` | Extended protocol: `Parse` (plan template) → `Bind` (parameters) → `Execute`. pgjdbc switches to a **named server-side prepared statement** after `prepareThreshold=5` executions on the same `PreparedStatement` | Use parameters (security + plan reuse); keep statements stable (avoid dynamic SQL per call) |
| Batching (`addBatch`/`executeBatch`) | Many Bind/Execute messages in one network flush. With `reWriteBatchedInserts=true`, pgjdbc rewrites into multi-row `INSERT … VALUES (…),(…)` | Batch writes. Measured **15×** below |
| `setFetchSize(n)` | pgjdbc: **only honoured with `autoCommit=false`** (it needs a server-side portal inside a transaction); otherwise the **whole result set is loaded into memory** | Stream large reads inside a transaction with a fetch size |
| `setQueryTimeout(s)` | Driver sends a cancel request after `s` seconds | Also set server-side `statement_timeout`; and the socket `socketTimeout` |
| `Connection.setAutoCommit(false)` | Driver issues `BEGIN` before the first statement | Frameworks manage this (Spring `DataSourceTransactionManager`, JPA) |
| `Connection.isValid(timeout)` | JDBC4 validation (pgjdbc sends an empty query) | Hikari uses it instead of `connectionTestQuery` |

### 1.1 Runnable: batching and fetch size on real PostgreSQL

<!-- run: javac cp=@p5 jvm="-Xmx1g" timeout=300 -->
```java
package demo.jdbc;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.sql.ResultSet;
import org.slf4j.LoggerFactory;

public class BatchingAndFetchSize {
    static HikariDataSource pool(EmbeddedPostgres pg, String urlSuffix) {
        HikariConfig c = new HikariConfig();
        c.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres") + urlSuffix);
        c.setMaximumPoolSize(2);
        return new HikariDataSource(c);
    }
    static long usedHeapAfterGc() { System.gc(); Runtime r = Runtime.getRuntime(); return r.totalMemory() - r.freeMemory(); }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.WARN);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            try (var ds = pool(pg, ""); var c = ds.getConnection()) {
                c.createStatement().execute("create table item(id bigint primary key, payload text)");
            }
            // --- 1. write path: 20,000 inserts three ways
            for (String mode : new String[] {"row-by-row (autocommit)", "executeBatch (1000/batch)", "executeBatch + reWriteBatchedInserts"}) {
                try (var ds = pool(pg, mode.contains("reWrite") ? "&reWriteBatchedInserts=true" : ""); var c = ds.getConnection()) {
                    c.createStatement().execute("truncate item");
                    long t0 = System.nanoTime();
                    boolean batch = !mode.startsWith("row");
                    c.setAutoCommit(!batch);
                    try (var ps = c.prepareStatement("insert into item values (?, ?)")) {
                        for (int i = 0; i < 20_000; i++) {
                            ps.setLong(1, i); ps.setString(2, "x".repeat(50));
                            if (batch) { ps.addBatch(); if (i % 1000 == 999) ps.executeBatch(); } else ps.executeUpdate();
                        }
                    }
                    if (batch) c.commit();
                    System.out.printf("%-40s %5d ms%n", mode, (System.nanoTime() - t0) / 1_000_000);
                }
            }
            // --- 2. read path: 320,001 rows, with and without a server-side cursor
            try (var ds = pool(pg, ""); var c = ds.getConnection()) {
                c.createStatement().execute("insert into item select g, repeat('y', 200) from generate_series(20000, 320000) g");
            }
            for (int fetchSize : new int[] {0, 1000}) {
                try (var ds = pool(pg, ""); var c = ds.getConnection()) {
                    c.setAutoCommit(fetchSize == 0);                      // pgjdbc cursors REQUIRE autoCommit=false
                    long base = usedHeapAfterGc(), peak = 0, rows = 0;
                    try (var st = c.createStatement()) {
                        st.setFetchSize(fetchSize);
                        try (ResultSet rs = st.executeQuery("select id, payload from item")) {
                            peak = Math.max(peak, usedHeapAfterGc() - base);
                            while (rs.next()) if (++rows % 50_000 == 0) peak = Math.max(peak, usedHeapAfterGc() - base);
                        }
                    }
                    if (!c.getAutoCommit()) c.commit();
                    System.out.printf("fetchSize=%-5d autoCommit=%-5s rows=%d  retained heap while reading ≈ %d MB%n",
                        fetchSize, fetchSize == 0, rows, peak >> 20);
                }
            }
        }
    }
}
```

One measured run:

```
row-by-row (autocommit)                   1694 ms
executeBatch (1000/batch)                  202 ms
executeBatch + reWriteBatchedInserts       110 ms
fetchSize=0     autoCommit=true  rows=320001  retained heap while reading ≈ 87 MB
fetchSize=1000  autoCommit=false rows=320001  retained heap while reading ≈ 0 MB
```

* Row-by-row in autocommit pays a **round trip and a commit (WAL flush) per row**. Batching removes most round trips, and the multi-row rewrite removes most per-statement overhead: **15×** faster with zero schema change. Over a real network (0.5–1 ms RTT) the gap is far larger.
* The default PostgreSQL read **materializes the entire result set in the JVM** (87 MB retained here, gigabytes in production "export" endpoints, ending in `OutOfMemoryError`). A cursor with `fetchSize` streams rows in chunks. MySQL Connector/J has the same trap, with different switches (`useCursorFetch=true`, or `fetchSize=Integer.MIN_VALUE` for streaming).

---

## 2. HikariCP internals 🔥

### 2.1 Architecture

```
HikariDataSource ── getConnection() ──► HikariPool.getConnection(connectionTimeout)
                                            │
                    ┌───────────────────────▼────────────────────────┐
                    │ ConcurrentBag<PoolEntry>                         │
                    │  ① threadList  (ThreadLocal<List>): entries this │  borrow order:
                    │     thread used recently → try those first (CAS) │  ① own thread-local list (cache-hot, no contention)
                    │  ② sharedList (CopyOnWriteArrayList): all entries│  ② scan shared list, CAS NOT_IN_USE→IN_USE
                    │  ③ handoffQueue (SynchronousQueue): direct       │  ③ park on the hand-off queue until requite()
                    │     hand-off from a returning thread to a waiter │     hands one over, or connectionTimeout expires
                    │  entry state: NOT_IN_USE / IN_USE / RESERVED /   │
                    │               REMOVED  (AtomicInteger + CAS)     │
                    └───────────────────────┬────────────────────────┘
                                            │ returns a proxy:
          HikariProxyConnection ── (statements tracked in a FastList: an ArrayList without range checks,
                                    removing from the tail, because statements close in LIFO order)
          close() on the proxy → resets dirty state (autoCommit, isolation, readOnly, catalog, schema, network timeout),
                                 rolls back an open transaction, returns the entry to the bag (requite)
HouseKeeper (every 30 s): retire idle connections beyond minimumIdle after idleTimeout; refill to minimumIdle
Per-connection timers: maxLifetime (with 25% random variance since 6.1 → no "thundering herd" of reconnects),
                       keepaliveTime (default 2 min since 6.2.1: validate idle connections so NATs/firewalls don't drop them)
```

* **Why it's fast:** lock-free borrowing with CAS, thread-affinity (the thread-local list), direct hand-off to waiters, proxies generated **at build time** (no reflection proxies at run time), and a tiny amount of code on the hot path.
* **Virtual threads:** borrowing is lock-free, but the bag *yields* while spinning. HikariCP 7.0.1/7.0.2 reduced yield frequency, and **7.1.0 fixed a virtual-thread yield spin in `ConcurrentBag`** (per its CHANGES). Spring Boot 4.1.2 still manages 7.0.2, so pin `HikariCP:7.1.0` if you run heavy VT workloads. More importantly: **size the pool for the database, not for the thread count** ([§3](#3-pool-sizing--smaller-is-usually-faster-)).

### 2.2 The settings that matter

| Property | Default | Guidance |
|---|---|---|
| `maximumPoolSize` | 10 | Size from the DB's capacity (§3), not from request concurrency |
| `minimumIdle` | = max | Keep **fixed-size pools** (min = max) for services: no ramp-up latency, no churn |
| `connectionTimeout` | 30 s | **Lower it** (250 ms–2 s for request paths): fail fast with 503 instead of piling up requests |
| `maxLifetime` | 30 min | Set it **below** any DB, proxy or load-balancer connection-lifetime limit (e.g. PgBouncer `server_lifetime`, AWS RDS Proxy, firewall idle timeouts) |
| `keepaliveTime` | 2 min (6.2.1+) | Must be less than network idle timeouts |
| `idleTimeout` | 10 min | Only matters when `minimumIdle < maximumPoolSize` |
| `leakDetectionThreshold` | 0 (off) | Set it in non-prod and canaries (≥ 2 s): logs the borrower's stack trace when a connection is held too long |
| `validationTimeout` | 5 s | < `connectionTimeout` |
| `initializationFailTimeout` | 1 ms | Positive values fail startup fast if the DB is unreachable. `-1` skips the check |
| `transactionIsolation`, `autoCommit`, `readOnly` | driver defaults | Set them once at the pool level rather than per connection (avoids reset costs) |
| `dataSourceProperties` | — | Driver tuning: pgjdbc `reWriteBatchedInserts`, `prepareThreshold`, `preparedStatementCacheQueries`; MySQL `cachePrepStmts`, `prepStmtCacheSize`, `useServerPrepStmts` |
| `credentialsProvider` (7.0+) | — | Rotating credentials (vault, IAM tokens) without recreating the pool |

**Statement caching is the driver's job:** HikariCP deliberately has no statement cache. pgjdbc caches server-side prepared statements per connection (`preparedStatementCacheQueries=256`, `preparedStatementCacheSizeMiB=5`). With **PgBouncer in transaction mode**, named prepared statements historically broke (a statement is prepared on one server connection and executed on another). PgBouncer 1.21+ supports protocol-level prepared statements (`max_prepared_statements`); otherwise set `prepareThreshold=0`.

### 2.3 Runnable: exhaustion, leak detection and pool metrics

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.jdbc;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.sql.Connection;
import java.sql.SQLTransientConnectionException;
import org.slf4j.LoggerFactory;

public class PoolBehaviour {
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.WARN);
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("com.zaxxer.hikari.pool.ProxyLeakTask")).setLevel(Level.INFO);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig cfg = new HikariConfig();
            cfg.setPoolName("orders-db");
            cfg.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            cfg.setMaximumPoolSize(2);
            cfg.setConnectionTimeout(500);                        // fail fast
            cfg.setLeakDetectionThreshold(2_000);                  // minimum allowed is 2000 ms
            try (HikariDataSource ds = new HikariDataSource(cfg)) {
                Connection c1 = ds.getConnection(), c2 = ds.getConnection();
                var mx = ds.getHikariPoolMXBean();
                System.out.println("proxy class: " + c1.getClass().getSimpleName() + " | active=" + mx.getActiveConnections() + " idle=" + mx.getIdleConnections());
                long t0 = System.nanoTime();
                try (Connection c3 = ds.getConnection()) {
                    System.out.println("unexpected: got a third connection");
                } catch (SQLTransientConnectionException e) {
                    System.out.println("after " + (System.nanoTime() - t0) / 100_000_000 * 100 + " ms: " + e.getMessage());
                }
                c2.close();                                        // returned to the bag
                System.out.println("after c2.close(): active=" + mx.getActiveConnections() + " idle=" + mx.getIdleConnections());
                System.out.println("holding c1 for 2.5 s without closing it… (leak detector fires at 2 s)");
                Thread.sleep(2_500);
                c1.close();                                        // late close: the detector logs "Previously reported leaked connection … was returned"
                Thread.sleep(100);
            }
        }
    }
}
```

Output (one verified run; timestamps, ms values and object hashes vary):

```
proxy class: HikariProxyConnection | active=2 idle=0
after 500 ms: orders-db - Connection is not available, request timed out after 503ms (total=2, active=2, idle=0, waiting=0)
after c2.close(): active=1 idle=1
holding c1 for 2.5 s without closing it… (leak detector fires at 2 s)
14:52:33.542 [orders-db:housekeeper] WARN com.zaxxer.hikari.pool.ProxyLeakTask -- Connection leak detection triggered for org.postgresql.jdbc.PgConnection@f0f2775 on thread main, stack trace follows
java.lang.Exception: Apparent connection leak detected
	at com.zaxxer.hikari.HikariDataSource.getConnection(HikariDataSource.java:99)
	at demo.jdbc.PoolBehaviour.main(PoolBehaviour.java:23)
14:52:34.642 [main] INFO com.zaxxer.hikari.pool.ProxyLeakTask -- Previously reported leaked connection org.postgresql.jdbc.PgConnection@f0f2775 on thread main was returned to the pool (unleaked)
```

The leak report is logged by the pool's **housekeeper** thread, but the stack trace is the one captured **at borrow time** (`main`, line 23: the `getConnection()` call). That's exactly what you need to find the code that forgot to close.

**Reading the timeout message** (it's the most useful line in a DB incident): `total=2, active=2, idle=0, waiting=N`. Every connection is checked out, so either the pool is too small for the load, **or connections are held too long**: slow queries, transactions spanning remote calls, leaks, or open-session-in-view holding a connection through view rendering ([5.4 §6](04-Transactions-Isolation-Locking-Spring-Transactional.md)). Raising `maximumPoolSize` is the last fix, not the first.

---

## 3. Pool sizing — smaller is usually faster 🔥

### 3.1 The reasoning

* A database executes at most about **cores** queries *on CPU* at once. Extra concurrent connections add context switching, lock contention, cache thrashing and memory (PostgreSQL: a process with `work_mem` per sort or hash node, per connection).
* HikariCP's "About Pool Sizing" quotes the PostgreSQL project's rule of thumb:

```
connections = (core_count × 2) + effective_spindle_count
   core_count: physical cores of the DB server (not hyper-threads)
   effective_spindle_count: ~ number of disks the active data set forces I/O on (0 if fully cached; small for SSDs)
   e.g. an 8-core DB with a cached working set → ~16–20 connections serve thousands of users
```

* **Little's Law check** (from the app side): `connections needed = throughput × time each connection is held`. 2,000 req/s × 5 ms of DB time each = **10 connections** busy on average. If you need 200, connections are being held 100 ms per request: fix that first.
* **Fleet math:** `pool size × instances (× pools per instance) ≤ DB max_connections − headroom`. 30 pods × 20 = 600 connections against PostgreSQL's default `max_connections=100` gives `FATAL: sorry, too many clients already`. Use smaller pools, PgBouncer/RDS Proxy, or fewer, bigger instances.
* **Virtual threads don't change this.** With 10,000 VTs and a pool of 20, 9,980 wait in `getConnection()`. That's correct, as long as `connectionTimeout` is short and a bulkhead sheds load ([3.6 §5](../03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#5-limiting-concurrency-the-new-capacity-model-)).

### 3.2 Runnable: throughput vs pool size (64 virtual threads hammering the DB)

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.jdbc;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.LongAdder;
import org.slf4j.LoggerFactory;

public class PoolSizeScaling {
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.WARN);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            for (String q : new String[] {"select sum(i) from generate_series(1, 300000) i", "select pg_sleep(0.02)"}) {
                StringBuilder sb = new StringBuilder(q.contains("sleep") ? "waiting query (pg_sleep 20 ms)" : "CPU-heavy query               ");
                for (int size : new int[] {2, 4, 8, 16, 32}) {
                    HikariConfig c = new HikariConfig();
                    c.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
                    c.setMaximumPoolSize(size); c.setMinimumIdle(size); c.setConnectionTimeout(5_000);
                    try (var ds = new HikariDataSource(c)) {
                        LongAdder done = new LongAdder();
                        long end = System.nanoTime() + 2_000_000_000L;
                        try (var vts = Executors.newVirtualThreadPerTaskExecutor()) {
                            for (int t = 0; t < 64; t++) vts.submit(() -> {
                                while (System.nanoTime() < end)
                                    try (var con = ds.getConnection(); var st = con.createStatement()) { st.execute(q); done.increment(); }
                                return null;
                            });
                        }
                        sb.append(String.format(" | pool=%2d:%4d q/s", size, done.sum() / 2));
                    }
                }
                System.out.println(sb);
            }
        }
    }
}
```

Two measured runs (DB and app share a 12-logical-CPU laptop, so absolute numbers are noisy):

```
run 1  CPU-heavy query                | pool= 2:  36 q/s | pool= 4:  55 q/s | pool= 8:  62 q/s | pool=16:  60 q/s | pool=32:  61 q/s
run 1  waiting query (pg_sleep 20 ms) | pool= 2:  65 q/s | pool= 4: 123 q/s | pool= 8: 220 q/s | pool=16: 326 q/s | pool=32: 345 q/s
run 2  CPU-heavy query                | pool= 2:  60 q/s | pool= 4:  75 q/s | pool= 8:  78 q/s | pool=16:  81 q/s | pool=32:  84 q/s
run 2  waiting query (pg_sleep 20 ms) | pool= 2:  93 q/s | pool= 4: 153 q/s | pool= 8: 248 q/s | pool=16: 345 q/s | pool=32: 375 q/s
```

* **CPU-bound work saturates around the core count**: beyond a pool of ≈ 8, quadrupling connections bought 0–8% more throughput in both runs. Pools of 16 or 32 add nothing but queueing **inside the database** (and on a dedicated DB server, contention can make throughput *fall*).
* Work that **waits inside the DB** (locks, I/O, `pg_sleep`) scales further with more connections, but that's usually a symptom to fix (slow I/O, lock waits), not a reason for huge pools.
* The 64 virtual threads never needed 64 connections. The pool is the right throttle.

---

## 4. Production failure modes & diagnostics (JDBC / pool)

| Symptom | Likely cause | Diagnose | Fix |
|---|---|---|---|
| `Connection is not available, request timed out after …ms (total=N, active=N, idle=0, waiting=M)` | Connections held too long (slow SQL, transactions around HTTP calls, OSIV), leaks, or an undersized pool | Hikari metrics `hikaricp.connections.active/pending/usage`, `leakDetectionThreshold`, slow-query log, `pg_stat_activity` | Shorten hold time; fix leaks; then size |
| `FATAL: sorry, too many clients already` | Fleet × pool > `max_connections` | `select count(*) from pg_stat_activity` | Smaller pools, PgBouncer/RDS Proxy |
| OOM on exports or reports | Driver buffered the whole result set | Heap dump: `byte[][]` rows in `PgResultSet` | `autoCommit=false` + `fetchSize`, or streaming APIs (`Stream<T>` with Spring Data in a read-only transaction) |
| Slow bulk writes | Row-by-row commits; `IDENTITY` generation preventing JDBC batching in JPA ([5.2](02-JPA-Hibernate-Persistence-Context-Internals.md)) | Statement count per request | Batching + `reWriteBatchedInserts`; sequences |
| `Connection reset` / `This connection has been closed` after idle | NAT, firewall or LB idle timeout dropped the connection | Timing of errors vs idle periods | `keepaliveTime` < idle timeout; `maxLifetime` < infrastructure limits |
| Periodic latency spikes every ~30 min | All connections expiring at once (old Hikari without variance) | Connection creation metrics | Hikari 6.1+ (25% variance); stagger |
| `prepared statement "S_1" does not exist` | PgBouncer transaction pooling + server-side prepares | Error text | PgBouncer 1.21+ prepared-statement support, or `prepareThreshold=0` |
| Requests hang forever on DB issues | No socket or query timeouts | Thread dumps in `SocketInputStream.read` under pgjdbc | `socketTimeout`, `statement_timeout`, `setQueryTimeout`, plus the pool's `connectionTimeout` |

**PostgreSQL-side views:** `pg_stat_activity` (state, `wait_event`, `query_start`, `state = 'idle in transaction'` means an app holding a transaction open), `pg_locks`, `pg_stat_statements` (top SQL by total time), `log_min_duration_statement`.

---

## 5. Interview Q&A

<details><summary><b>Q1. 🔥 How does HikariCP's `ConcurrentBag` hand out connections?</b></summary>

It first tries the borrowing thread's thread-local list of recently used entries (CAS the entry state `NOT_IN_USE`→`IN_USE`), then scans the shared `CopyOnWriteArrayList`, and finally waits on a `SynchronousQueue` hand-off until a returning thread passes an entry directly, or `connectionTimeout` expires. Returning (`requite`) hands the entry to a waiter if there is one, else marks it free and adds it to the thread's local list. Lock-free CAS plus thread affinity keeps the hot path short.
</details>

<details><summary><b>Q2. 🔥 Your service has 40 pods × 50 connections and the DB is struggling. What do you do?</b></summary>

2,000 connections is far beyond what a database can execute concurrently (≈ 2 × cores). Reduce per-pod pools (to perhaps 5–10), measure connection hold times (slow queries, transactions spanning remote calls, OSIV), add PgBouncer or RDS Proxy if instance counts must stay high, set short `connectionTimeout`s and bulkheads so overload sheds instead of queuing, and check `max_connections` headroom for maintenance and replicas.
</details>

<details><summary><b>Q3. ⚡ Why might `setFetchSize(1000)` have no effect with PostgreSQL?</b></summary>

pgjdbc uses a server-side cursor (portal) only when `autoCommit=false` (inside a transaction), with a forward-only result set and a non-zero fetch size. In autocommit mode it reads the entire result set into memory regardless (measured: 87 MB retained vs ~0 MB with a cursor).
</details>

<details><summary><b>Q4. ⚡ Why doesn't HikariCP cache prepared statements?</b></summary>

Statement caching belongs in the driver, which knows how to manage server-side prepared statements per connection (pgjdbc's `prepareThreshold` and `preparedStatementCacheQueries`; MySQL's `cachePrepStmts`). A pool-level cache would duplicate that, leak statements across connection resets, and complicate the proxies.
</details>

<details><summary><b>Q5. 🔥 What does `leakDetectionThreshold` do and what does it cost?</b></summary>

When a connection is borrowed, Hikari schedules a task. If the connection isn't returned within the threshold, the task logs a WARN with the stack trace captured at borrow time ("Apparent connection leak detected"), and later logs "unleaked" if it comes back. The cost is a scheduled task plus a stack capture per borrow, which is acceptable in staging and canaries. It's a diagnostic and doesn't reclaim the connection.
</details>

<details><summary><b>Q6. ⚡ Explain the pool-sizing formula and when you'd deviate from it.</b></summary>

`connections ≈ 2 × DB cores + effective spindles` targets keeping the DB's CPUs busy while overlapping some I/O, without oversubscription. Deviate upward if queries spend most of their time waiting (remote storage, lock waits) and you've confirmed the waits can't be removed; downward for many app instances sharing one DB (divide the budget across the fleet). Validate with load tests: throughput plateaus while latency rises once the pool exceeds what the DB can run concurrently (measured plateau ≈ 8 for CPU-heavy queries).
</details>

<details><summary><b>Q7. 🧊 Why do `IDENTITY` primary keys hurt batch inserts in JPA?</b></summary>

Hibernate must know each entity's ID right after `persist()`. With `IDENTITY` the ID comes from the INSERT itself, so Hibernate executes each INSERT immediately and individually, which disables JDBC batching for those inserts. Sequences with a pooled optimizer (`allocationSize=50`) let Hibernate assign IDs in memory and batch the inserts at flush ([5.2](02-JPA-Hibernate-Persistence-Context-Internals.md)).
</details>
