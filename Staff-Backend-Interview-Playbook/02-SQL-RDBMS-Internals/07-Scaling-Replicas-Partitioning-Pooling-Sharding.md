# 2.7 Scaling Relational Databases: Read Replicas & Read-Your-Writes, Synchronous Commit, Partitioning, Connection Pooling Math, Sharding

> **Verified stack:** PostgreSQL **18.6** primary (port 55432) + a **streaming replica** built with `pg_basebackup` (port 55433, `recovery_min_apply_delay = 1500ms` to make lag visible), `pgbench` scale 10, Spring Framework **7.0.10** + HikariCP **7.0.2**. Session-tool conventions as in [2.6](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md): `P>` primary, `R>` replica. Timings are one measured run.

---

## 0. First principles: what actually limits one database 🔥

A single PostgreSQL primary is bounded by:

1. **CPU** for query execution, shared by all active connections;
2. **memory**: the working set that fits in `shared_buffers` plus the OS page cache decides whether reads are RAM-speed or disk-speed;
3. **WAL write and flush bandwidth**: every write funnels through one log;
4. **lock contention** on hot rows ([2.3 §7](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md): 10 hot rows dominated total time);
5. **connections**: each is an OS process with its own memory and snapshot work.

Each scaling technique attacks a different limit:

| Technique | Relieves | Doesn't help with |
|---|---|---|
| Read replicas | CPU and I/O for **reads** | Writes, hot rows, read-your-writes consistency |
| Partitioning | Index size, vacuum cost, retention (`DROP` vs `DELETE`), pruning for time-bounded queries | Total write throughput on one node |
| Connection pooling | Connection count, process overhead | Actual query cost |
| Caching ([6.3](../06-Resilience-Caching-Kafka/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)) | Repeated reads | Freshness |
| Sharding | **Write** throughput and data size beyond one node | Cross-shard queries, transactions and operational simplicity |

Scale **vertically and with replicas first**. A modern 64-core, 512 GB primary handles more than most companies ever need. Shard only when write volume or data size truly exceeds one node.

---

## 1. Read replicas and the consistency trap 🔥

### 1.1 How streaming replication works

The primary streams WAL to each standby (walsender → walreceiver). The standby writes it, flushes it, and **replays** it. Replay is what makes data visible to queries on the replica. Each stage has a position (LSN), and lag is the distance between the primary's current LSN and the replica's replay LSN.

```text
primary: commit ──► WAL ──► walsender ══network══► walreceiver ──► write ──► flush ──► REPLAY ──► visible on replica
                                                                    (write_lag) (flush_lag) (replay_lag)
```

### 1.2 Verified: read-your-writes breaks

```text
P> create table profile (id int primary key, display_name text)
P> insert into profile values (1, 'Ada')
R> select pg_is_in_recovery() as replica, display_name from profile where id = 1
   replica | display_name
   t       | Ada
P> update profile set display_name = 'Ada Lovelace' where id = 1
   UPDATE 1
# user is redirected to their profile page, which reads from the replica
R> select display_name from profile where id = 1
   display_name
   Ada
P> select client_addr, state, sync_state, write_lag, flush_lag, replay_lag from pg_stat_replication
   client_addr | state     | sync_state | write_lag       | flush_lag       | replay_lag
   ::1         | streaming | async      | 00:00:00.000286 | 00:00:00.000308 | 00:00:00.000308
```

The user saves their profile and sees the **old** name. Note the monitoring row: **`replay_lag` reported 0.3 ms while the replica was ≥1.5 s behind on replay**. The `*_lag` columns are computed from sampled round-trips and lag behind reality during bursts and after idle periods. **For correctness decisions, compare LSNs, never timings.**

### 1.3 Verified fix: LSN fencing

After a write, capture the primary's WAL position. Read from a replica only once it has **replayed** past it.

```text
P> update profile set display_name = 'Countess Ada' where id = 1
P> select pg_current_wal_lsn() as commit_lsn
   commit_lsn
   0/6902A2F0
R> select pg_last_wal_replay_lsn() >= '0/6902A2F0' as caught_up, display_name from profile where id = 1
   caught_up | display_name
   f         | Ada
   (1.8 s later)
R> select pg_last_wal_replay_lsn() >= '0/6902A2F0' as caught_up, display_name from profile where id = 1
   caught_up | display_name
   t         | Countess Ada
```

Production patterns for read-your-writes, from simplest to most precise:

| Pattern | How | Trade-off |
|---|---|---|
| **Read from the primary after a write** for N seconds (sticky session flag/cookie) | The router checks "did this user write recently?" | Simple. N must exceed the worst lag |
| **LSN fencing** | Return the commit LSN to the client (header or token), and have the reader wait for or pick a replica with `pg_last_wal_replay_lsn() >= lsn` | Exact; needs plumbing |
| `synchronous_commit = remote_apply` | The commit waits until a sync standby has **applied** it | Exact for that standby, but **every commit pays the replica's apply latency** (below) |
| Route the whole request to the primary | `@Transactional` read-write | Wastes primary capacity on reads |

### 1.4 Verified: what each `synchronous_commit` level costs

With the replica configured as a synchronous standby (`synchronous_standby_names = '*'`):

```text
 application_name |   state   | sync_state
------------------+-----------+------------
 walreceiver      | streaming | sync

set synchronous_commit = on;            -- wait for the standby to FLUSH the WAL
update profile set display_name = 'v-on' where id = 1;
Time: 3.812 ms
set synchronous_commit = remote_apply;  -- wait for the standby to APPLY it (visible to replica reads)
update profile set display_name = 'v-remote-apply' where id = 1;
Time: 1503.062 ms (00:01.503)
set synchronous_commit = local;         -- don't wait for the standby at all
update profile set display_name = 'v-local' where id = 1;
Time: 4.627 ms
```

| Level | Commit waits for | Survives primary crash? | Read-your-writes on the sync standby? |
|---|---|---|---|
| `off` | Nothing (WAL flushed shortly after) | May lose the last few hundred ms | No |
| `local` | Local WAL flush | Yes (single node) | No |
| `remote_write` | Standby received the WAL (OS cache) | Yes, unless both nodes fail together | No |
| `on` (with a sync standby) | Standby **flushed** the WAL | Yes, **zero data loss on failover** | No |
| `remote_apply` | Standby **applied** the WAL | Yes | **Yes** |

The 1.5 s `remote_apply` commit is the replica's artificial apply delay showing through: **synchronous replication couples your commit latency to your slowest synchronous replica**. A slow or stuck sync standby stalls all writes. Production setups use quorum commit (`synchronous_standby_names = 'ANY 1 (r1, r2)'`) so one healthy standby is enough.

### 1.5 Verified: routing reads in Spring (and the classic bug)

```java
/** Routes to "replica" when the current transaction is read-only. */
static class ReadWriteRoutingDataSource extends AbstractRoutingDataSource {
    @Override
    protected Object determineCurrentLookupKey() {
        return TransactionSynchronizationManager.isCurrentTransactionReadOnly() ? "replica" : "primary";
    }
}

@Bean
DataSource dataSource() {
    ReadWriteRoutingDataSource router = new ReadWriteRoutingDataSource();
    router.setTargetDataSources(Map.of("primary", pool("primary", 55432), "replica", pool("replica", 55433)));
    router.setDefaultTargetDataSource(pool("primary-default", 55432));
    router.afterPropertiesSet();
    // The transaction manager fetches a connection at BEGIN, before the read-only flag is exposed to
    // TransactionSynchronizationManager. The lazy proxy defers the real getConnection() to the first statement.
    return Boolean.getBoolean("lazy") ? new LazyConnectionDataSourceProxy(router) : router;
}
```

```java
@Transactional(readOnly = true)
public String whereDoReadsGo() {
    return "readOnly tx -> in_recovery=" + jdbc.queryForObject("select pg_is_in_recovery()", Boolean.class)
           + " (port " + jdbc.queryForObject("select current_setting('port')", String.class) + ")";
}
```

**Output (verified):**

```text
lazy proxy = false
readOnly tx -> in_recovery=false (port 55432)
read-write tx -> in_recovery=false (port 55432)
lazy proxy = true
readOnly tx -> in_recovery=true (port 55433)
read-write tx -> in_recovery=false (port 55432)
```

**Without** `LazyConnectionDataSourceProxy`, every "read-only" transaction silently ran on the **primary**. `DataSourceTransactionManager.doBegin()` obtains the connection *before* the read-only flag is bound to the thread, so the router sees `readOnly = false`. The app "has replicas", the dashboards show them idle, and the primary takes all the load. The lazy proxy hands out a placeholder and opens the real connection at the first statement, by which time the flag is set.

Other replica gotchas: **replica conflicts** (`canceling statement due to conflict with recovery`, when replay must remove rows a long replica query still needs; tune `max_standby_streaming_delay` or `hot_standby_feedback`, which in turn holds back vacuum on the primary, [2.5 §2.1](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)), and **failover** (clients must reconnect to the new primary; use `targetServerType=primary` in multi-host JDBC URLs, or a VIP/DNS managed by Patroni or your cloud).

---

## 2. Partitioning ⚡

### 2.1 What partitioning is for

Declarative partitioning splits one logical table into child tables by a **partition key**. Each partition has its own heap and its own indexes. The wins:

* **Retention**: drop a month with `DETACH`/`DROP` (metadata) instead of `DELETE`-ing 100 M rows (dead tuples, vacuum, WAL).
* **Pruning**: queries bounded on the key touch only the relevant partitions.
* **Maintenance**: vacuum, reindex and freeze work per partition, and old partitions can be frozen once and left alone.
* **Index size**: per-partition indexes are smaller, with hotter top levels.

It is **not** a general speed-up: queries that don't filter on the partition key scan every partition, and planning time grows with the partition count.

### 2.2 Verified: range partitioning by month

```sql
create table event_log (
  id         bigint generated always as identity,
  tenant_id  int not null,
  kind       text not null,
  created_at timestamptz not null,
  primary key (id, created_at)                     -- the partition key must be part of every unique constraint
) partition by range (created_at);
create table event_log_2026_10 partition of event_log for values from ('2026-10-01') to ('2026-11-01');
create table event_log_2026_11 partition of event_log for values from ('2026-11-01') to ('2026-12-01');
create table event_log_2026_12 partition of event_log for values from ('2026-12-01') to ('2027-01-01');
create table event_log_default partition of event_log default;
create index on event_log (tenant_id, created_at);  -- created on every partition
```

**Output (verified):**

```text
     partition     | count
-------------------+--------
 event_log_2026_10 | 101090
 event_log_2026_11 |  97830
 event_log_2026_12 | 101080

-- plan-time pruning: literal bounds on the key
explain (costs off) select count(*) from event_log where created_at >= '2026-11-10' and created_at < '2026-11-20';
 Aggregate
   ->  Seq Scan on event_log_2026_11 event_log
         Filter: ((created_at >= '2026-11-10 00:00:00+00'::timestamp with time zone) AND (created_at < '2026-11-20 00:00:00+00'::timestamp with time zone))

-- no partition key in the predicate: every partition
explain (costs off) select count(*) from event_log where tenant_id = 42;
 Aggregate
   ->  Append
         ->  Bitmap Heap Scan on event_log_2026_10 event_log_1  ...
         ->  Bitmap Heap Scan on event_log_2026_11 event_log_2  ...
         ->  Bitmap Heap Scan on event_log_2026_12 event_log_3  ...
         ->  Seq Scan on event_log_default event_log_4  ...

-- run-time pruning: the bound is only known at execution (generic plan / bind parameter)
explain (analyze, costs off, summary off, timing off, buffers off) execute recent('2026-12-15');
 ...
               ->  Parallel Append (actual rows=18475.33 loops=3)
                     Subplans Removed: 2
                     ->  Parallel Seq Scan on event_log_2026_12 event_log_1 (actual rows=55426.00 loops=1)
                           Filter: (created_at >= $1)
                     ->  Parallel Seq Scan on event_log_default event_log_2 (actual rows=0.00 loops=1)
```

`Subplans Removed: 2` is **run-time pruning**: with a parameter, the planner couldn't prune, so the executor did it at startup. Note the default partition always survives pruning on an open-ended range.

### 2.3 Verified gotcha: `DETACH … CONCURRENTLY` and the default partition

```text
alter table event_log detach partition event_log_2026_10 concurrently;
ERROR:  cannot detach partitions concurrently when a default partition exists
```

After dropping the default partition:

```text
alter table event_log detach partition event_log_2026_11 concurrently;
ALTER TABLE
 relname           | relispartition
 event_log_2026_11 | f
```

A default partition is convenient (rows outside every range don't fail inserts) and costly: it blocks concurrent detach, it's never pruned for open ranges, and **creating a new partition must scan the default** to prove no rows belong in the new range. The production pattern: **pre-create partitions ahead of time** (a scheduled job or `pg_partman`), alert when the newest partition is close to filling, and don't keep a default.

### 2.4 Partitioning rules of thumb

| Rule | Why |
|---|---|
| Partition key in **every** hot query's `WHERE` | Otherwise all partitions are scanned |
| PK/unique constraints must include the key | Uniqueness is enforced per partition (hence `primary key (id, created_at)`) |
| Tens to low thousands of partitions, not hundreds of thousands | Planning time and lock count grow with the partitions touched |
| Range by time for event/append data; list by tenant/region for isolation; hash for spreading writes evenly | Choose by retention and access pattern |
| Combine with BRIN on time inside partitions | Tiny indexes for append-only data ([2.2 §5.4](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)) |

The plan-level behavior of partitions (plan-time pruning, `Subplans Removed` at executor start, `(never executed)` children, pruning defeated by a cast, partition bounds silently built in the session's time zone) is verified line by line in [2.10 §6](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md#6-partitioned-tables-append-pruning-merge-append-).

### 2.5 Verified: partition-wise aggregation is off by default, and needs the *key*, not an expression of it 🧊

On the 12-month `events` table of the [atlas dataset](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#02-the-dataset-run-it-yourself) (1.2 M rows):

```sql
show enable_partitionwise_aggregate;                                     -- off
set enable_partitionwise_aggregate = on;
explain (analyze, costs off) select date_trunc('month', occurred_at) as m, count(*) from events group by 1;
explain (costs off) select kind, count(*) from events group by kind;
```

**Output (verified, PostgreSQL 18.6, excerpts):**

```text
-- GROUP BY date_trunc('month', occurred_at), partition-wise ON: still ONE aggregate above the Append
 HashAggregate (actual time=360.576..360.740 rows=12.00 loops=1)
   Group Key: (date_trunc('month'::text, events.occurred_at))
   Batches: 1  Memory Usage: 2081kB
   ->  Append (actual time=0.019..247.729 rows=1200000.00 loops=1)
         ->  Seq Scan on events_2026_01 events_1 …
         … 12 partitions

-- GROUP BY kind (not the partition key): PARTIAL partition-wise aggregation
 Finalize GroupAggregate
   Group Key: events.kind
   ->  Sort
         Sort Key: events.kind
         ->  Append
               ->  Partial HashAggregate
                     Group Key: events.kind
                     ->  Seq Scan on events_2026_01 events
               ->  Partial HashAggregate
                     Group Key: events_1.kind
                     ->  Seq Scan on events_2026_02 events_1
               … one Partial HashAggregate per partition
```

* **Full** partition-wise aggregation (each partition produces final groups, no combine step) requires the **partition key columns themselves** in `GROUP BY`. `date_trunc('month', occurred_at)` maps each partition to exactly one month, but the planner doesn't prove that, so it aggregated all 1.2 M rows above the `Append`.
* **Partial** partition-wise aggregation works for any grouping: each partition pre-aggregates (`Partial HashAggregate`: 4 groups each), and a `Finalize` step combines 48 partial rows. Each per-partition hash table is small, so on big grouped reports it's the difference between one huge spilling hash table and many small in-memory ones, and it's what lets per-partition work run in parallel.
* Both settings (`enable_partitionwise_aggregate`, `enable_partitionwise_join`) are **off by default** because they increase planning time and memory with many partitions. Turn them on per role or session for reporting queries over partitioned tables, and verify with `EXPLAIN`.

---

## 3. Connection pooling math 🔥

### 3.1 First principles: Little's law

> **L = λ × W**: average requests in the system = arrival rate × average time in the system.

For a database: **busy connections = transactions per second × average transaction time**. At 2,000 TPS and 5 ms per transaction, about **10** connections are busy on average. More connections than the database can run in parallel don't add throughput. They add queueing (inside PostgreSQL, as context switches and lock contention) and memory.

### 3.2 Verified: the throughput curve

`pgbench` (TPC-B-like, scale 10) on a 12-logical-CPU laptop:

**One measured run:**

```text
== clients=1     tps = 1154.7    latency average = 0.866 ms
== clients=4     tps = 3438.0    latency average = 1.163 ms
== clients=12    tps = 7645.6    latency average = 1.570 ms
== clients=32    tps = 6781.2    latency average = 4.719 ms
```

* Throughput **peaks around the CPU count** (12) and then **drops**, while latency triples.
* Little's law checks out exactly: 7,645.6 × 0.001570 ≈ **12.0**; 6,781.2 × 0.004719 ≈ **32.0**.
* Past the knee, extra connections only add waiting.

### 3.3 Sizing HikariCP

The PostgreSQL community's starting heuristic (from the HikariCP "About Pool Sizing" page) is `connections ≈ (cores × 2) + effective_spindle_count`, a **total for the database**, not per application instance. The arithmetic architects get wrong:

```text
pods × maximumPoolSize ≤ the database's useful concurrency (+ headroom for admin, migrations, replicas)
  30 pods × 20 = 600 connections   ❌ far past the knee (and 600 processes × ~10 MB)
  30 pods × 4  = 120 connections   ✅ with a pooler or a lower count, depending on the cores
```

If the pods' combined demand is legitimately higher, put **PgBouncer** in between: many client connections, few server connections. Deeper HikariCP internals (the `ConcurrentBag`, timeouts, leak detection) are in [8.4](../08-GitHub-Codebases-Study-Guide/04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md) and the sibling kit's [5.1](../../Java-Backend-Master-Reference/05-Persistence-JPA-Hibernate/01-JDBC-HikariCP-Connection-Pooling.md).

### 3.4 PgBouncer modes and what transaction pooling breaks

| Mode | Server connection held for | Multiplexing | Breaks |
|---|---|---|---|
| `session` | The whole client session | Low | Nothing |
| **`transaction`** | One transaction | **High** (the usual choice) | Session state across transactions: `SET` (use `SET LOCAL`), session advisory locks, `LISTEN/NOTIFY`, temp tables, `WITH HOLD` cursors; **protocol-level prepared statements** unless PgBouncer ≥ 1.21 with `max_prepared_statements > 0` |
| `statement` | One statement | Highest | Multi-statement transactions |

With pgjdbc behind transaction pooling, either enable PgBouncer's prepared-statement support or set `prepareThreshold=0`. Otherwise you'll see `prepared statement "S_1" does not exist` errors under load. Set Hikari's `maxLifetime` shorter than PgBouncer's `server_lifetime` and any load-balancer idle timeout, so the pool retires connections before something in the middle kills them.

---

## 4. Sharding 🧊

Sharding splits data **across independent databases** by a **shard key**. It's the only way to scale writes horizontally on a relational store, and it removes almost every convenience the single database gave you.

### 4.1 Strategies

| Strategy | Mapping | Pros | Cons |
|---|---|---|---|
| **Hash** (`hash(tenant_id) mod N`, better: consistent hashing or many virtual shards) | Even spread | No hotspots from key ranges | Range queries hit all shards; resharding moves data (mitigated by many logical shards mapped onto fewer physical ones) |
| **Range** (by id or time) | Contiguous key ranges | Range scans stay local; easy to add new ranges | Hotspots (all new writes hit the last range) |
| **Directory / lookup** | A table maps key → shard | Flexible placement, moving a tenant is a metadata change | The directory is critical infrastructure (cache it, replicate it) |
| **Geo / tenant** | By region or tenant tier | Data residency, noisy-neighbor isolation | Uneven shard sizes |

### 4.2 Choosing the shard key (the decision that matters)

A good shard key is **in almost every query** (so queries route to one shard), has **high cardinality** and **even distribution**, and **keeps transactions inside one shard**. For SaaS that's almost always `tenant_id`. Then design so that **one tenant's data lives on one shard**, and treat cross-tenant analytics as a separate pipeline (CDC → warehouse).

### 4.3 What you give up, and the replacements

| Lost | Replacement |
|---|---|
| Cross-shard joins | Denormalize; application-side joins; CQRS read models ([5.5](../05-Microservices-Patterns/05-CQRS-and-Event-Sourcing.md)) |
| Cross-shard transactions | Keep transactions shard-local by key design; sagas for the rest ([5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)) |
| Global unique constraints | Key design (uniqueness within a tenant); a global uniqueness service or table |
| Sequences | **UUIDv7** or Snowflake-style IDs (timestamp + shard + sequence), so IDs are globally unique and time-ordered ([2.2 §1.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)) |
| Simple operations | Per-shard migrations, backups, failovers. Automate everything |

Off-the-shelf options before building your own: **Citus** (PostgreSQL extension: distributed tables, co-location by tenant), Vitess (MySQL), and distributed SQL databases (CockroachDB, YugabyteDB, Spanner) that trade single-node latency for built-in sharding and consensus replication.

---

## 5. ❌ Naïve vs ✅ production-hardened scaling

| ❌ Naïve | ✅ Hardened |
|---|---|
| Route `@Transactional(readOnly = true)` with `AbstractRoutingDataSource` alone | `LazyConnectionDataSourceProxy` around the router (verified: otherwise reads hit the primary) |
| Read from a replica right after a write | Sticky-primary window, LSN fencing, or `remote_apply` for the critical path |
| Alert on `replay_lag` | Alert on LSN distance (`pg_wal_lsn_diff(sent_lsn, replay_lsn)`) and replica `now() - pg_last_xact_replay_timestamp()` |
| One synchronous standby | Quorum (`ANY 1 (r1, r2)`); know that sync replication couples commit latency to the standby |
| `DELETE FROM events WHERE created_at < now() - '90 days'` nightly | Monthly partitions, `DETACH CONCURRENTLY`, `DROP` |
| Default partition "just in case" | Pre-created partitions + alerts. A default blocks concurrent detach (verified) |
| `maximumPoolSize = 50` on 40 pods | Size from Little's law and the database's knee; PgBouncer for fan-in |
| Shard first, ask questions later | Vertical + replicas + partitioning + caching first; shard by tenant when writes truly exceed one node |

---

## 6. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/replication/walsender.c` | How lag columns are sampled (and why they lag) |
| postgres/postgres | `src/backend/replication/syncrep.c` | How commits wait for `remote_write`/`on`/`remote_apply` |
| postgres/postgres | `src/backend/partitioning/partprune.c` | Plan-time and run-time pruning |
| [spring-projects/spring-framework](https://github.com/spring-projects/spring-framework) | `spring-jdbc/src/main/java/org/springframework/jdbc/datasource/LazyConnectionDataSourceProxy.java` | How it defers the physical connection (and propagates read-only) |
| [pgbouncer/pgbouncer](https://github.com/pgbouncer/pgbouncer) | `src/server.c`, `src/client.c` | Pool modes and prepared-statement tracking |
| [citusdata/citus](https://github.com/citusdata/citus) | `src/backend/distributed/planner/` | How a distributed query is routed or fanned out |

---

## 7. Interview soundbites

* "Replicas scale reads, not writes, and break read-your-writes. I fence on LSNs: the replica must have replayed the commit LSN before I read from it."
* "`replay_lag` said 0.3 ms while the replica was 1.5 s behind. For correctness I compare LSNs, not timings."
* "`remote_apply` gives read-your-writes on the standby but made each commit take 1.5 s with a slow replica. Sync replication ties your write latency to your slowest synchronous standby."
* "With `AbstractRoutingDataSource`, read-only transactions went to the primary until I added `LazyConnectionDataSourceProxy`."
* "Partitioning is for retention, pruning and maintenance, not a general speed-up. And a default partition blocks `DETACH CONCURRENTLY`."
* "Little's law sizes pools: pgbench peaked at 12 clients on 12 CPUs; 32 clients gave lower throughput at three times the latency."
* "Partition-wise aggregation is off by default. Grouping by `date_trunc` of the partition key didn't qualify; grouping by another column got partial, per-partition aggregates with a finalize step."

---

## Summary

| Lever | What it scales | What it costs | Verified evidence |
|---|---|---|---|
| Read replicas | Reads | Read-your-writes breaks; lag | Stale read after commit; LSN fencing fixed it |
| `synchronous_commit` levels | Durability / consistency on standbys | Commit latency tied to the standby | `remote_apply` commits took 1.5 s with a delayed replica |
| Routing in Spring | Read traffic to replicas | Needs `LazyConnectionDataSourceProxy` | Without it, read-only transactions hit the primary |
| Partitioning | Retention, pruning, maintenance | Key in every query, uniqueness per partition, planning cost | `DETACH … CONCURRENTLY` blocked by a default partition |
| Partition-wise aggregation | Per-partition grouping | Off by default; full mode needs the raw key | Partial per-partition aggregates for `GROUP BY kind` |
| Connection pooling | Concurrency → the DB's knee | Queueing outside the DB | pgbench peaked at 12 clients on 12 CPUs |
| PgBouncer transaction mode | Fan-in of many app connections | Session features break; prepared statements need 1.21+ | — |
| Sharding | Writes beyond one node | Cross-shard joins/transactions, resharding | Strategy and shard-key rules (§4) |

**Next:** [2.8 Bar-raiser drill-downs →](08-Bar-Raiser-Drill-Downs.md)
