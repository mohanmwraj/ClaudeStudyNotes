# 2.8 Bar-Raiser Drill-Downs: SQL & Relational Database Internals

> **How to use:** answer each probe out loud before opening the defense. The evidence (real PostgreSQL 18.6 and MySQL 8.4.13 output) is in [2.1](01-Storage-Pages-Tuples-TOAST-WAL.md)–[2.7](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md). Bar-raisers go deeper until you hit the edge of what you know, so the last probe in each chain is meant to be hard.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "p99 of one endpoint jumped 10× after Tuesday's deploy. The SQL didn't change." 🔥

🎤 *"Probably the database is overloaded; we should scale it up."*

🔍 **Probe 1: How do you prove whether it's the database, and which query?**

<details><summary>🛡️ Defense</summary>

Start from `pg_stat_statements`, comparing a snapshot before and after: `mean_exec_time`, `calls`, `rows/call`, `shared_blks_read/call`. A query whose *mean* rose while calls stayed flat is a **plan change**. If every query got slower, it's resource saturation. Then get the actual slow plan: `auto_explain` (`log_min_duration`, `log_analyze`, `log_buffers`) captures the plan of the slow *executions*, which can differ from what you get running `EXPLAIN` by hand.
</details>

🔍 **Probe 2: You run `EXPLAIN ANALYZE` by hand with the same parameter and it's fast. Explain.**

<details><summary>🛡️ Defense</summary>

Your hand-run statement gets a **custom plan** for that literal. The application uses a **prepared statement**: pgjdbc server-prepares after `prepareThreshold = 5` executions, and PostgreSQL may switch to a **generic plan** after five custom ones if the generic cost isn't worse than the average. With skewed data, the generic plan is right for the common value and terrible for rare ones. Verified ([2.3 §5](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md)): after warming up on `DELIVERED` (90% of rows), `CANCELLED` ran `Parallel Seq Scan … Filter: (status = $1)` in **95 ms** instead of a bitmap index scan in **8 ms**. The `$1` in the logged plan is the fingerprint. "After a deploy" fits: new pods, new connections, a different first-seen value mix.
</details>

🔍 **Probe 3: Fix it without disabling prepared statements globally.**

<details><summary>🛡️ Defense</summary>

Options from narrowest to broadest: `plan_cache_mode = force_custom_plan` for the role or transaction that runs the skewed query; split the query (rare values via a partial index and their own statement); `prepareThreshold=0` on a dedicated `DataSource` for that workload. Also check that the statistics are accurate (MCV list for the skewed column), because the generic plan's cost comes from them.
</details>

🔍 **Probe 4 (L6): How do you stop this class of regression from reaching production again?**

<details><summary>🛡️ Defense</summary>

A **plan regression gate**: run the top N queries from `pg_stat_statements` (with representative *and* skewed parameters) against a production-sized, production-distributed dataset in CI or staging, compare plan shapes and buffers per query, and fail on large regressions. Keep `auto_explain` sampling on in production, alert on a `mean_exec_time` change per `queryid`, and include "data distribution" in load-test design. Uniform synthetic data hides exactly this bug.
</details>

---

## Drill 2: "Design pagination for a 500 M-row activity feed" 🔥

🎤 *"`LIMIT 20 OFFSET page*20`, with an index on `created_at`."*

🔍 **Probe 1: What's the cost of page 25,000?**

<details><summary>🛡️ Defense</summary>

O(offset): the database produces and discards 500,000 rows. Verified on 1 M rows ([2.4 §2](04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)): `OFFSET 500000` touched **16,615 buffers in 140 ms** and even wrote 2,813 pages while evicting. Keyset on `(created_at, id)` touched **5 buffers in 0.02 ms**, and I checked it returned exactly the same rows.
</details>

🔍 **Probe 2: Two activities have the same `created_at`. What breaks?**

<details><summary>🛡️ Defense</summary>

With `WHERE created_at < :last`, rows sharing the boundary timestamp are skipped. With `<=`, they're duplicated. The sort key must be **unique**: add `id` as a tiebreaker, compare row values `(created_at, id) < (:ts, :id)`, and index `(created_at, id)` (or `(user_id, created_at, id)` for a per-user feed: equality first).
</details>

🔍 **Probe 3: Product wants "jump to page 437" and a total count.**

<details><summary>🛡️ Defense</summary>

Push back with data: exact `count(*)` on 500 M rows is a full scan (MVCC means no cached row count). Offer an estimate (`reltuples`, or `EXPLAIN` row estimates) or a capped count ("10,000+"). For random access, offer coarse jumps by time ("go to March 2026") which map onto keyset seeks. If deep random paging is truly a requirement, it's a search-engine feature.
</details>

🔍 **Probe 4 (L6): The feed is now sharded by user. Does keyset still work?**

<details><summary>🛡️ Defense</summary>

Per user, yes, because a user's feed lives on one shard. For a merged feed across shards, each shard serves a keyset page and a coordinator **merge-sorts** the top N, carrying a **composite cursor** (one position per shard, or a global `(ts, id)` that every shard can seek past). Globally unique, time-ordered IDs (UUIDv7, Snowflake) make the tiebreaker work across shards.
</details>

---

## Drill 3: "Our 200 GB table is 600 GB on disk and growing" ⚡

🔍 **Probe 1: Where does the extra 400 GB come from?**

<details><summary>🛡️ Defense</summary>

MVCC: every `UPDATE` and `DELETE` leaves a dead tuple version in the heap, plus index entries for non-HOT updates ([2.1 §1.2](01-Storage-Pages-Tuples-TOAST-WAL.md)). If VACUUM can't remove them fast enough, or **isn't allowed to**, the table and indexes bloat. Plain VACUUM makes space reusable but rarely shrinks files.
</details>

🔍 **Probe 2: Autovacuum runs constantly but bloat still grows. Why?**

<details><summary>🛡️ Defense</summary>

Something holds back the **xmin horizon**, so dead tuples are "dead but not yet removable". Verified ([2.5 §2.1](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)): one `idle in transaction` session made VACUUM report `10000 are dead but not yet removable`, and after it committed, `10000 removed`. Usual culprits: idle-in-transaction app connections, long analytics queries on the primary, **a stale replication slot** (a stopped Debezium connector), `hot_standby_feedback` with long replica queries, orphaned prepared transactions. Diagnose with `pg_stat_activity.backend_xmin`, `pg_replication_slots`, `pg_prepared_xacts`.
</details>

🔍 **Probe 3: The horizon is fine now. How do you get the space back and stop it recurring?**

<details><summary>🛡️ Defense</summary>

Reclaim online with `pg_repack` (or a planned `VACUUM FULL`, which takes `ACCESS EXCLUSIVE` for the whole rewrite). Prevent it: per-table autovacuum settings (`scale_factor` 0.01–0.05, a higher cost limit), `fillfactor` 80–90 and fewer indexes on churning columns so updates stay HOT (verified: fillfactor 90 → **100% HOT**, fillfactor 100 → **0%**), `idle_in_transaction_session_timeout`, alerts on slot lag and the oldest `backend_xmin` age. If the table is append-and-expire, partition it and drop old partitions instead of deleting.
</details>

---

## Drill 4: "We got 'database must be vacuumed within 10,000,000 transactions'" 🧊

🔍 **Probe 1: What's happening and what will happen next?**

<details><summary>🛡️ Defense</summary>

Transaction ID wraparound protection. XIDs are 32-bit and compared modulo 2^32, so tuples older than ~2 billion XIDs must be **frozen** or they'd look like they're in the future. Above `autovacuum_freeze_max_age` (200 M) autovacuum forces anti-wraparound vacuums. Near 2^31 − 40 M PostgreSQL warns, and at about 3 M before the limit it **stops assigning XIDs**: the database becomes effectively read-only.
</details>

🔍 **Probe 2: Anti-wraparound vacuum has been running for hours. Why isn't it fixing it?**

<details><summary>🛡️ Defense</summary>

Freezing can't advance `relfrozenxid` past the **xmin horizon** either. The same horizon-holders as Drill 3 (a stale slot, a forgotten prepared transaction) block it. Find and remove them first, then let the vacuum run (consider raising `maintenance_work_mem`, removing the vacuum cost delay for this run, and running a manual `VACUUM (FREEZE, VERBOSE)` on the oldest tables by `age(relfrozenxid)`).
</details>

🔍 **Probe 3 (L6): How would you have seen this coming three months earlier?**

<details><summary>🛡️ Defense</summary>

Alert on `age(datfrozenxid)` and the top tables' `age(relfrozenxid)` at ~40% and ~60% of 2 billion, on `mxid_age(datminmxid)` (multixacts wrap too), and on horizon age. Make sure insert-only tables are vacuumed (`autovacuum_vacuum_insert_threshold`, PG 13+). Capacity-plan XID consumption: XIDs per day × days to 200 M. High-XID-burn patterns (one transaction per row, `txid_current()` calls, savepoint-heavy code) are worth fixing at the source.
</details>

---

## Drill 5: "We oversold the last item in stock during a flash sale" 🔥

🎤 *"We check `stock > 0` before decrementing, inside `@Transactional`."*

🔍 **Probe 1: Why didn't the transaction protect you?**

<details><summary>🛡️ Defense</summary>

That's check-then-act under READ COMMITTED: both requests read `stock = 1`, both decide to sell, both write. Transactions don't serialize *decisions based on reads*. Verified lost update ([2.6 §1.1](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)): two increments of +10 and +20 produced 120 instead of 130.
</details>

🔍 **Probe 2: Give me the fastest correct fix.**

<details><summary>🛡️ Defense</summary>

A conditional atomic update: `UPDATE inventory SET qty = qty - :n WHERE sku = :sku AND qty >= :n`, and check the row count (0 = sold out). The row lock plus the re-check of the `WHERE` on the latest version make it correct under concurrency, in one round trip, with no retry loop. Add a `CHECK (qty >= 0)` constraint as a backstop.
</details>

🔍 **Probe 3: We're on MySQL with REPEATABLE READ, isn't that already safe?**

<details><summary>🛡️ Defense</summary>

No. Verified ([2.6 §7.3](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)): InnoDB RR serves plain `SELECT`s from a snapshot but applies `UPDATE`s to the **latest** version ("current read") **without** raising an error, so the lost update happened (result 110, not 130). PostgreSQL RR would have aborted the second writer with 40001. The conditional atomic update is correct on both engines.
</details>

🔍 **Probe 4 (L6): The flash sale has 50,000 requests/s on one SKU. Now what?**

<details><summary>🛡️ Defense</summary>

One row is a **hot spot**: every decrement serializes on its row lock (in [2.3 §7](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md), ten hot rows dominated `pg_stat_statements` total time). Options: split stock into N **buckets** (rows) and decrement a random bucket with stock; reserve stock in memory (Redis `DECR` with Lua, the source of truth for the sale) and reconcile asynchronously to the database; or put the purchase requests in a queue and process them in order (no lost updates, bounded rate, a "you're in line" UX). Choose by how much oversell (none, or a small, refundable amount) the business accepts.
</details>

---

## Drill 6: "Use Postgres as a job queue or adopt SQS/Kafka?" ⚡

🔍 **Probe 1: How do multiple workers pull jobs without double processing?**

<details><summary>🛡️ Defense</summary>

`SELECT … WHERE status = 'READY' ORDER BY run_at LIMIT :n FOR UPDATE SKIP LOCKED`. Verified ([2.6 §4](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)): worker A got jobs 1–2 and worker B got 3–4 with **no waiting**. A partial index `WHERE status = 'READY'` keeps the lookup small no matter how many done jobs pile up.
</details>

🔍 **Probe 2: A worker crashes mid-job. What happens?**

<details><summary>🛡️ Defense</summary>

If the work happens inside the claiming transaction, the transaction rolls back and the row lock is released, so the job becomes claimable again. That only works for short jobs. For long ones, claim by setting `status = 'RUNNING', lease_until = now() + 5 min`, **commit**, process, then mark `DONE`. A reaper re-queues expired leases. Handlers must be **idempotent**, because a job can run twice (crash after the side effect, before `DONE`).
</details>

🔍 **Probe 3 (L6): When do you outgrow it?**

<details><summary>🛡️ Defense</summary>

When queue writes compete with OLTP for WAL and vacuum (every claim is an update, so the queue table bloats), when you need fan-out to many independent consumers, replay of history, or very high throughput (tens of thousands per second sustained), or when consumers live in other teams' services. Then use Kafka for event streams or SQS/RabbitMQ for task queues, and keep **the transactional outbox** in Postgres to publish reliably ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)). Until then, the database queue gives you atomicity with your business data for free, which brokers can't.
</details>

---

## Drill 7: "A 50 ms `ALTER TABLE` took the site down for 4 minutes" 🔥

🔍 **Probe 1: How can a fast DDL cause a long outage?**

<details><summary>🛡️ Defense</summary>

The DDL needs `ACCESS EXCLUSIVE`, which waits behind any open transaction that touched the table, and **lock requests queue FIFO**: every new query, even plain `SELECT`s, queues behind the waiting DDL. Verified ([2.6 §6](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)): session A held `ACCESS SHARE` from an open transaction, B's `ALTER` waited, and C's `SELECT * FROM purchase WHERE id = 1` waited behind B. Connection pools fill up, health checks fail, pods restart.
</details>

🔍 **Probe 2: What's your migration policy?**

<details><summary>🛡️ Defense</summary>

1. Every migration session sets `lock_timeout` (1–3 s) and the tool **retries with backoff**.
2. Use non-blocking forms: `CREATE INDEX CONCURRENTLY` (and check `indisvalid`), `ADD CONSTRAINT … NOT VALID` then `VALIDATE`, `ADD COLUMN … DEFAULT const` (metadata-only since PG 11), no type changes that rewrite big tables.
3. Expand → migrate → contract across releases, so old and new code both work during rollout.
4. `idle_in_transaction_session_timeout` so a forgotten transaction can't hold `ACCESS SHARE` forever.
5. Lint migrations in CI (squawk, strong_migrations equivalents).
</details>

---

## Drill 8: "Users don't see their own updates after we added read replicas" 🔥

🔍 **Probe 1: Why, and how do you fix it precisely?**

<details><summary>🛡️ Defense</summary>

Asynchronous replication: the write commits on the primary and the next request reads a replica that hasn't **replayed** it yet. Verified ([2.7 §1.2](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)): the replica returned `Ada` right after the update to `Ada Lovelace`. Precise fix: **LSN fencing**. After the write, return `pg_current_wal_lsn()` to the client (cookie or header). Reads go to a replica only if `pg_last_wal_replay_lsn() >= lsn`, otherwise to the primary or after a short wait. Verified: `caught_up = f` → `Ada`, then `caught_up = t` → `Countess Ada`.
</details>

🔍 **Probe 2: Why not just alert when `replay_lag` > 1 s?**

<details><summary>🛡️ Defense</summary>

Because `replay_lag` is a sampled estimate. In the verified run it reported **0.3 ms while the replica was ≥1.5 s behind**. Alert on LSN distance (`pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)`) and on `now() - pg_last_xact_replay_timestamp()` on the replica (with care when the primary is idle).
</details>

🔍 **Probe 3: We already route `@Transactional(readOnly = true)` to replicas, yet replicas are idle and the primary is at 90% CPU.**

<details><summary>🛡️ Defense</summary>

Classic Spring bug: `AbstractRoutingDataSource` decides the target when the connection is obtained, and `DataSourceTransactionManager.doBegin()` obtains it **before** the read-only flag is bound to the thread. Verified: without a proxy, the read-only method printed `in_recovery=false (port 55432)`; with `LazyConnectionDataSourceProxy` around the router, `in_recovery=true (port 55433)`.
</details>

🔍 **Probe 4 (L6): Would you use `synchronous_commit = remote_apply` instead?**

<details><summary>🛡️ Defense</summary>

Only for narrow, critical paths. It guarantees the sync standby has **applied** the commit, so reads there see it, but every commit waits for that standby. Verified: with a slow replica, a commit took **1,503 ms** vs ~4 ms for `on`/`local`. A stalled sync standby stalls all writes, so use quorum (`ANY 1 (r1, r2)`) and keep `remote_apply` to sessions that need it.
</details>

---

## Drill 9: "UUID or bigint primary keys?" ⚡

🔍 **Probe 1: What does a random UUID do to a B-tree?**

<details><summary>🛡️ Defense</summary>

Inserts land on random leaves, so splits everywhere leave half-full pages, the working set is the whole index, and each insert dirties a different page (more full-page images in WAL). Verified on 1 M rows ([2.2 §1.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)): UUIDv4 leaves **71% dense, 50% fragmented, 38 MB**; UUIDv7 **90% dense, 30 MB**; bigint **90%, 21 MB**. Insert time (one run): 6.2 s vs 4.6 s vs 2.5 s, and that's with everything in memory.
</details>

🔍 **Probe 2: Does the answer change for MySQL?**

<details><summary>🛡️ Defense</summary>

It matters more. InnoDB stores rows **inside the PK B-tree** (clustered), so a random PK fragments the **table itself**, and every secondary index stores the PK, so a 16-byte PK inflates all of them ([2.1 §5](01-Storage-Pages-Tuples-TOAST-WAL.md)).
</details>

🔍 **Probe 3 (L6): Your IDs are public in URLs and generated by mobile clients offline. Decide.**

<details><summary>🛡️ Defense</summary>

Client-generated means a UUID. **UUIDv7** keeps index locality, but it embeds a millisecond timestamp (verified: `uuid_extract_timestamp` recovers it), which leaks creation time and lets someone estimate volume. If that's acceptable, use UUIDv7 as the PK. If not, use a bigint/UUIDv7 internal PK and a random public identifier (UUIDv4 or an opaque token) in a unique secondary column, and never expose the internal key.
</details>

---

## Drill 10: "MySQL deadlocks started after we added a uniqueness check on email" 🧊

🔍 **Probe 1: The code does `SELECT … FOR UPDATE WHERE email = ?` then `INSERT` if absent. Why deadlocks?**

<details><summary>🛡️ Defense</summary>

In InnoDB REPEATABLE READ, a locking read for an **absent** key takes a **gap lock**. Gap locks are compatible with each other, so two transactions both hold the gap. Each `INSERT` needs an **insert intention** lock, which conflicts with the *other* transaction's gap lock, so each waits for the other. Verified ([2.6 §7.4](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)): `Deadlock found when trying to get lock; try restarting transaction`.
</details>

🔍 **Probe 2: Fix it.**

<details><summary>🛡️ Defense</summary>

Remove the check: just `INSERT`, and let the unique index arbitrate. Catch the duplicate-key error (SQLState 23000 / error 1062) and map it to "already registered", or use `INSERT … ON DUPLICATE KEY UPDATE` for upserts. Optionally run READ COMMITTED for that workload, where gap locks aren't taken for these reads (verified: the `k = 17` insert succeeded under RC).
</details>

---

## Drill 11: "40 pods, HikariCP pool 50 each, and the database falls over at peak" ⚡

🔍 **Probe 1: Do the math.**

<details><summary>🛡️ Defense</summary>

40 × 50 = **2,000 potential connections**. PostgreSQL runs a process per connection, and useful concurrency is about the CPU count. Little's law: busy connections = TPS × transaction time. Verified pgbench curve ([2.7 §3.2](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)): peak **7,646 TPS at 12 clients**, **6,781 TPS at 32** with 3× latency. More connections past the knee reduce throughput.
</details>

🔍 **Probe 2: The pods genuinely need more concurrency at peak. Architecture?**

<details><summary>🛡️ Defense</summary>

Small per-pod pools (sized from Little's law per pod) plus **PgBouncer in transaction mode** to fan many client connections into a few server connections. Know what transaction pooling breaks: session `SET`, session advisory locks, `LISTEN/NOTIFY`, temp tables, and protocol-level prepared statements unless PgBouncer ≥ 1.21 with `max_prepared_statements`. Set Hikari `maxLifetime` below the pooler's and the load balancer's idle timeouts. Also shorten transactions: no remote calls inside them, which directly lowers W in L = λW.
</details>

---

## Drill 12: "When would you shard, and how?" 🧊

🔍 **Probe 1: What have you tried before sharding?**

<details><summary>🛡️ Defense</summary>

Vertical scaling (a big primary goes very far), query and index work (most capacity problems are plans), read replicas for reads, caching, partitioning for retention and maintenance, moving analytics off the primary (CDC → warehouse), and fixing hot rows in the data model. Shard when **write throughput or data size** truly exceeds one node, or for regulatory or tenant isolation.
</details>

🔍 **Probe 2: Choose the shard key for a B2B SaaS.**

<details><summary>🛡️ Defense</summary>

`tenant_id`: present in nearly every query, high cardinality, and it keeps transactions shard-local. Watch for whale tenants (give them a dedicated shard; directory-based placement makes that a metadata change). Use many logical shards mapped onto fewer physical nodes so rebalancing moves whole logical shards. Use UUIDv7 or Snowflake IDs for global uniqueness, CQRS or a warehouse for cross-tenant analytics, and sagas only for the rare cross-shard workflows. Evaluate Citus before building it yourself.
</details>

---

# Round 2: EXPLAIN-driven drill-downs (Batch 1 deep dive)

> In Round 2 the interviewer **hands you a plan** (or a symptom with a plan) and keeps asking "why". Every plan fragment below is real PostgreSQL 18.6 output from [2.9](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md), [2.10](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md) and [2.11](11-Plan-Pathologies-Diagnosis-Playbook.md).

---

## Drill 13: "Explain this plan. It's the 'latest open tickets' widget and it takes 110 ms." 🔥

```text
 Limit  (cost=0.42..36.06 rows=10 width=16) (actual time=110.772..110.775 rows=10.00 loops=1)
   ->  Index Scan Backward using ticket_created on ticket  (cost=0.42..36817.43 rows=10333 width=16) (actual time=110.770..110.772 rows=10.00 loops=1)
         Filter: (status = 'OPEN'::text)
         Rows Removed by Filter: 990000
```

🎤 *"It's using an index, so the index is fine. Maybe the table needs a VACUUM."*

🔍 **Probe 1: Why did the planner think this was cheap (36 out of 36,817)?**

<details><summary>🛡️ Defense</summary>

A **row goal**. With `LIMIT 10`, the planner costs the fraction of the index scan needed to find 10 matching rows. It estimates 1 % of tickets are `OPEN` (the estimate `rows=10333` is right) and assumes they're **spread uniformly** along `created_at`, so it expects 10 hits in the first ~1,000 entries of a backward scan: 36/36,817 of the cost. In reality all `OPEN` tickets were the oldest rows, so the scan walked and discarded 990,000 entries. The statistics are fine; the **independence of the filter and the sort order** is the false assumption, and no PostgreSQL statistic models it.
</details>

🔍 **Probe 2: Fix it. Then fix it without creating an index.**

<details><summary>🛡️ Defense</summary>

Index: `(status, created_at)`: the filter becomes an `Index Cond` and the order comes from the same index. Verified: **110.8 ms → 0.058 ms, 10,959 → 4 buffers**. Without an index: remove the row goal so the planner filters first (`ORDER BY created_at + interval '0'`, or a `MATERIALIZED` CTE that applies the filter, or a partial index if DDL is allowed but a full index isn't). All three are hacks; comment them, because a future "cleanup" will reintroduce the bug.
</details>

🔍 **Probe 3 (L6): The same shape is probably hiding in 50 other endpoints. How do you find them before customers do?**

<details><summary>🛡️ Defense</summary>

The signature is mechanical: `Limit` over an ordered `Index Scan` with a `Filter` and a large `Rows Removed by Filter`. Collect plans with `auto_explain` (`log_format = json`, sampled, `log_timing = off`), parse them, and alert on `Rows Removed by Filter / Actual Rows` above a threshold. In CI, run the top queries from `pg_stat_statements` against a production-distributed snapshot (data skew is the point), and diff plans and buffer counts. And design-review "newest N where X" queries: they need a `(X, sort_key)` index by default.
</details>

---

## Drill 14: "We vacuumed, but the index-only scan still reads the heap" 🧊

```text
 Index Only Scan using orders_vm_created on orders_vm  (… rows=19200.00 loops=1)
   Heap Fetches: 6500
   Buffers: shared hit=191
```

🎤 *"Autovacuum must not have run yet."*

🔍 **Probe 1: It did run. `VACUUM VERBOSE` says `tuples: 0 removed … 0 are dead but not yet removable`. Why are there still heap fetches?**

<details><summary>🛡️ Defense</summary>

Look further down the `VERBOSE` output: `index scan bypassed: 116 pages from table (1.22% of total) have 9600 dead item identifiers`. Since PG 14, when fewer than ~2 % of heap pages have dead items, VACUUM skips the index-vacuuming phase. The dead line pointers must stay on those pages until index entries pointing at them are removed, and a page with `LP_DEAD` items can't be marked all-visible. Verified ([2.9 §5](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#5-index-only-scan-the-visibility-map-and-the-vacuum-that-didnt-help-)): heap fetches 19,300 → **6,500** after a plain VACUUM → **0** after `VACUUM (INDEX_CLEANUP ON)`.
</details>

🔍 **Probe 2: Why didn't the cost estimate change between those three states?**

<details><summary>🛡️ Defense</summary>

The planner's input is `pg_class.relallvisible`, a number VACUUM and ANALYZE update; the estimate (`621`–`631`) doesn't see per-page visibility. Only `EXPLAIN ANALYZE` shows `Heap Fetches`. That's why you can't validate index-only-scan health from plans without `ANALYZE`, and why I monitor `Heap Fetches` from `auto_explain` for the endpoints that depend on covering indexes.
</details>

🔍 **Probe 3 (L6): Make this robust for a table that gets ~1 % updates per hour and serves a hot covering-index API.**

<details><summary>🛡️ Defense</summary>

Lower `autovacuum_vacuum_scale_factor` (or set a fixed threshold) for that table so vacuum runs often; schedule a periodic `VACUUM (INDEX_CLEANUP ON)`; make sure updates don't touch the covering index's columns (so they can be HOT and don't add index entries at all, [2.10 §7.1](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md#71-wal-per-statement-and-what-fillfactor-buys)); and alert on the all-visible ratio (`relallvisible / relpages`). If update churn is inherent, accept heap fetches and size for them rather than promising "index-only".
</details>

---

## Drill 15: "Deleting 200 shipments takes 4 seconds; EXPLAIN says the delete takes 0.15 ms" 🔥

```text
 Delete on shipment  (actual time=0.155..0.156 rows=0.00 loops=1)
   ->  Index Scan using shipment_pkey on shipment  (actual time=0.006..0.028 rows=200.00 loops=1)
 Trigger for constraint parcel_shipment_id_fkey: time=4184.941 calls=200
 Execution Time: 4185.255 ms
```

🎤 *"The plan is fast, so it must be lock waits."*

🔍 **Probe 1: Read the last lines. What runs 200 times?**

<details><summary>🛡️ Defense</summary>

The foreign-key enforcement trigger on `parcel.shipment_id` (`ON DELETE CASCADE`): one internal query per deleted parent row (`calls=200`). Without an index on the **referencing** column, each call seq-scans 500,000 parcels. PostgreSQL requires a unique index on the referenced side but **never** creates one on the referencing side (InnoDB does, which is why teams migrating from MySQL hit this). With the index: **4,185 ms → 5.2 ms**.
</details>

🔍 **Probe 2: Find every instance of this problem in a 400-table schema in one query.**

<details><summary>🛡️ Defense</summary>

Join `pg_constraint` (`contype = 'f'`) to `pg_index` and look for FKs whose columns aren't a leading prefix of any index on the child table; the query is in [2.11 P8](11-Plan-Pathologies-Diagnosis-Playbook.md#p8-the-delete-thats-slow-outside-the-plan-tree-unindexed-foreign-keys-). Then decide per FK: index it if parents are deleted/updated or if the column is joined on; skip it only for reference tables that are never deleted from (and document that).
</details>

🔍 **Probe 3 (L6): Why is this also a locking problem, not only a CPU problem?**

<details><summary>🛡️ Defense</summary>

During those 4 seconds the transaction holds row locks on the 200 shipments and is scanning `parcel` repeatedly; concurrent inserts of parcels for those shipments take `FOR KEY SHARE` on the parent and wait. A cascade across several levels multiplies it. Long FK checks also show up in `pg_stat_statements` under the **parent** statement, so the fix is easy to misattribute. Add a lint in CI: every new FK needs an index or an explicit exemption.
</details>

---

## Drill 16: "We filter `orders` to 200,000 rows and the join still reads all 3 M order lines" 🧊

```text
 Hash Join  (actual time=37.071..641.038 rows=600000.00 loops=1)
   Hash Cond: (ol.order_id = o.id)
   ->  Seq Scan on order_lines ol  (actual … rows=3000000.00 loops=1)
   ->  Hash  …  Batches: 2
         ->  Index Only Scan using orders_pkey on orders o  (… rows=200000.00 …)
               Index Cond: (id <= 200000)
```

🎤 *"Add an index on `order_lines.order_id`."* (It's already the leading column of the primary key.)

🔍 **Probe 1: Why isn't `id <= 200000` applied to `order_lines`?**

<details><summary>🛡️ Defense</summary>

The planner builds **equivalence classes** from join equalities and propagates **equality** constants through them (`o.id = 4242` produces `ol.order_id = 4242`; verified), but it doesn't derive **range** restrictions across a join. So `order_lines` has no restriction of its own, and a hash join with a full seq scan is the cheapest plan the planner can see.
</details>

🔍 **Probe 2: Fix it, and tell me the side effect.**

<details><summary>🛡️ Defense</summary>

Write the redundant predicate: `… and ol.order_id <= 200000`. Verified: the planner switches to a **merge join** over both primary keys, **660 ms → 135 ms**, 25,550 + temp → 2,861 buffers. Side effect: the planner multiplies the two (identical) restrictions as if independent, so the join estimate dropped to **122,819 vs 600,000 actual**. Harmless at the top of this query; dangerous if a nested loop sits above it. Re-check the plan above the join.
</details>

🔍 **Probe 3 (L6): The forced merge join (no redundant predicate) was also fast. Why did the cost model reject it?**

<details><summary>🛡️ Defense</summary>

A merge join stops when the outer side is exhausted: the inner index scan read **600,001 of 3 M** rows. The cost estimate charged the inner scan for all 3 M rows (cost 112,834 vs the hash join's 97,827), so the planner never chose it. That's a known limit: the estimate of merge-join early termination depends on histogram bounds, and it often underestimates the savings. The structural fix for very large parent/child tables is co-partitioning both tables by the parent key so `enable_partitionwise_join` and pruning apply to both sides.
</details>

---

## Drill 17: "The nightly 'customers without recent orders' report never finishes" 🔥

```text
 Seq Scan on customers c  (cost=0.42..1495118373.50 rows=100000 width=0)
   Filter: (NOT (ANY (id = (SubPlan 1).col1)))
   SubPlan 1
     ->  Materialize  (cost=0.42..14194.79 rows=302709 width=8)
```

🎤 *"Increase `work_mem`."*

🔍 **Probe 1: What does `SubPlan 1` (not `hashed SubPlan 1`) mean here?**

<details><summary>🛡️ Defense</summary>

The `NOT IN` subquery result (300,000 values) is too big for a hash table within `work_mem`, so for **every** customer the executor rescans the materialized list. Quadratic. Verified: **9.0 s for just 1,000 customers**, with the `Materialize` itself spilled (`Storage: Disk`, 1.7 GB of temp re-reads). The 1.5-billion cost estimate was the warning.
</details>

🔍 **Probe 2: More memory does make it hashed and fast. Why is that still the wrong fix?**

<details><summary>🛡️ Defense</summary>

It works until the subquery grows past the new limit, and it leaves a **correctness** bug: if the subquery ever returns a `NULL`, `NOT IN` returns **no rows at all** (verified: 0 vs 19,999 with `NOT EXISTS`). That's also why the planner can't rewrite `NOT IN` as an anti join. `NOT EXISTS` is correct with NULLs and always becomes an anti join: **200,000 customers in 160 ms** with a `Hash Anti Join` that can spill in batches and stays linear.
</details>

🔍 **Probe 3 (L6): How do you keep `NOT IN (SELECT …)` out of a 200-engineer codebase?**

<details><summary>🛡️ Defense</summary>

A SQL lint in CI (pattern match on `NOT IN (SELECT` in migrations, repositories and `@Query` strings), a code-review checklist item, and for ORM-generated SQL a test that logs statements and fails on the pattern. Also teach the rule's *reason* (three-valued logic), because people will otherwise "fix" it with `COALESCE` hacks.
</details>

---

## Drill 18: "Estimated 1 row, actual 143, and the query takes 1.4 seconds" 🧊

```text
 Nested Loop  (cost=0.00..25144.29 rows=29 width=0) (actual time=0.024..1391.752 rows=4147.00 loops=1)
   ->  Seq Scan on addr a  (cost=0.00..21370.00 rows=1 width=8) (actual … rows=143.00 loops=1)
         Filter: ((zip = 'zip42-0'::text) AND (city = 'city42'::text))
   ->  Seq Scan on visit v  (cost=0.00..3774.00 rows=29 width=8) (actual … rows=29.00 loops=143)
```

🎤 *"Add an index on `visit.zip`."*

🔍 **Probe 1: That would make this query fast. Why is it treating the symptom?**

<details><summary>🛡️ Defense</summary>

The error is the **outer estimate** (1 vs 143): `city` and `zip` are correlated (zip determines city), and the planner multiplied their selectivities as if independent (1/1000 × 1/7000). The inner estimate (29) is perfect. An index on `visit.zip` hides it in this query, but every other query filtering on `(city, zip)` is still misestimated and can pick a bad join.
</details>

🔍 **Probe 2: Fix the cause and show me the evidence.**

<details><summary>🛡️ Defense</summary>

`create statistics … (dependencies, mcv, ndistinct) on city, zip` + `ANALYZE`. Verified: the estimate became **143 exactly**, the join estimate **4,147 exactly**, and the planner added a `Materialize` so `visit` is scanned once instead of 143 times: **1,392 ms → 60 ms**. You can reproduce the original estimate by hand from `pg_stats` ([2.3 §2.3](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md#23-reproducing-the-planners-row-estimates-by-hand-verified-)).
</details>

🔍 **Probe 3 (L6): How do you find correlated columns systematically?**

<details><summary>🛡️ Defense</summary>

From the plans, not from intuition: collect `auto_explain` plans, compute estimate/actual ratios per scan node with multiple `AND`ed predicates on the same table, and investigate the worst ratios. Typical candidates: tenant id with everything, country/currency/locale, parent/child category columns, status with timestamps. `CREATE STATISTICS` is cheap at query time; the cost is `ANALYZE` time and catalog size, so add it where plans prove the need.
</details>

---

## Drill 19: "Walk me through the cost of a sequential scan. Then tell me when you'd change the cost constants." 🧊

🎤 *"Cost is an estimate of milliseconds."*

🔍 **Probe 1: It isn't. What is it, exactly, for `select … from orders where total > 490`?**

<details><summary>🛡️ Defense</summary>

Abstract units where reading one page sequentially costs 1.0: `relpages × seq_page_cost + reltuples × cpu_tuple_cost + reltuples × cpu_operator_cost × quals` = 9,412 + 10,000 + 2,500 = **21,912**, which is exactly what the plan showed ([2.9 §1](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#1-seq-scan-and-the-cost-formula-reproduced-)). In parallel, I/O isn't divided but CPU is divided by 2.4 for two workers (leader counts 0.4): **14,620.33**, also exact.
</details>

🔍 **Probe 2: And a primary-key lookup costs 8.44. Decompose it.**

<details><summary>🛡️ Defense</summary>

B-tree descent `ceil(log2 N) × cpu_operator_cost + (height + 1) × 50 × cpu_operator_cost` = 0.05 + 0.375 = 0.425 (startup `0.42`), plus one leaf page at `random_page_cost` (4), one index tuple (0.0075), one heap page (4) and one heap tuple (0.01) = **8.4425**. Physically it touched 4 pages in steady state (3 index levels + 1 heap page).
</details>

🔍 **Probe 3 (L6): When would you change `random_page_cost`, and how would you prove it helped?**

<details><summary>🛡️ Defense</summary>

When the working set is mostly cached or on SSDs and the planner keeps choosing seq scans or bitmaps where index scans are measurably faster. Change it **per database or tablespace**, never on a hunch: take the top queries from `pg_stat_statements`, capture plans and buffers before and after in staging with production-like data and cache state, and check that no plan got worse (lowering it makes index scans look cheaper everywhere, including the uncorrelated full-index scans of [2.11 P6](11-Plan-Pathologies-Diagnosis-Playbook.md#p6-a-full-table-aggregate-that-walks-an-uncorrelated-index-)). Also set `effective_cache_size` truthfully; it feeds the same index-cost model.
</details>

---

## Drill 20: "SERIALIZABLE aborts about 5 % of our transfers, and they never touch the same accounts" 🧊

🎤 *"SSI is just too pessimistic; switch to REPEATABLE READ."*

🔍 **Probe 1: How can disjoint transactions conflict under SSI?**

<details><summary>🛡️ Defense</summary>

SSI tracks what the executor **read** with `SIReadLock`s at tuple, page or relation granularity. Coarse locks make unrelated transactions look dependent. Verified ([2.6 §2.5](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md#25-verified-ssi-false-positives-come-from-predicate-lock-granularity-)): with a seq scan, both transactions held a **relation**-level SIRead lock and one aborted; with an index but neighbouring data, they shared an index leaf page and one aborted; with data clustered on separate pages, both committed. And a transaction that reads more than 32 pages of one table gets its page locks **promoted** to a relation lock (`max_pred_locks_per_relation = -2` → 64/2).
</details>

🔍 **Probe 2: Switching to REPEATABLE READ removes the aborts. What breaks?**

<details><summary>🛡️ Defense</summary>

Write skew: any invariant that spans rows (an overdraft limit across accounts, "one on-call doctor") silently breaks, because RR only detects write-write conflicts on the same row. If you drop SERIALIZABLE, you must materialize the conflict yourself (`SELECT … FOR UPDATE` on a guard row, or a constraint).
</details>

🔍 **Probe 3 (L6): Reduce the abort rate while keeping SERIALIZABLE.**

<details><summary>🛡️ Defense</summary>

Make reads touch fewer pages (indexes that match every predicate, no seq scans in the transfer path), keep transactions short, mark read-only work `READ ONLY` (and `DEFERRABLE` for long reports so they can't abort), raise `max_pred_locks_per_transaction` if `pg_locks` shows relation-level SIRead locks on big tables, and keep a retry loop around the whole transaction with jittered backoff. Measure the abort rate by SQLSTATE 40001 per endpoint; it's a function of data layout, so watch it after migrations.
</details>

---

## Drill 21: "Our Debezium connector was down all weekend. Is vacuum blocked?" ⚡

🎤 *"Yes, the replication slot holds back the xmin horizon for the whole database."*

🔍 **Probe 1: For a logical slot, that's only partly true. What exactly does it hold back?**

<details><summary>🛡️ Defense</summary>

A logical slot has `xmin = NULL` and a `catalog_xmin`. Verified ([2.5 §2.3](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md#23-verified-what-a-stale-logical-replication-slot-actually-blocks-)): with an inactive slot, VACUUM removed all 10,000 dead rows of a user table, but `pg_attribute` reported **4,000 dead but not yet removable** until the slot was dropped. It needs old catalog rows to decode old WAL with the schema of that time. The thing that holds back **every** table is a physical slot with `hot_standby_feedback`, or a long transaction.
</details>

🔍 **Probe 2: Then what takes the database down after a weekend?**

<details><summary>🛡️ Defense</summary>

**WAL retention.** The slot pins all WAL since its `restart_lsn` (31 MB after 200,000 small inserts in the lab; at production write rates, hundreds of GB over a weekend). When `pg_wal` fills the volume, the primary stops. Catalog bloat is the slower second effect.
</details>

🔍 **Probe 3 (L6): Design the guardrails.**

<details><summary>🛡️ Defense</summary>

`max_slot_wal_keep_size` (the slot is invalidated instead of the primary dying; the connector then needs a re-snapshot, which you plan for), PG 18's `idle_replication_slot_timeout`, alerts on `pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)` and `wal_status`, a runbook for re-snapshotting, and WAL on a volume sized for the longest tolerated outage of the consumer.
</details>

---

## Drill 22: "The finance team's big report makes the API slow every night" ⚡

🎤 *"The report's seq scans evict our cache."*

🔍 **Probe 1: Do they?**

<details><summary>🛡️ Defense</summary>

Not through `shared_buffers`: a seq scan of a table larger than a quarter of `shared_buffers` uses a small **ring buffer** (`BAS_BULKREAD`). Verified ([2.1 §4.6](01-Storage-Pages-Tuples-TOAST-WAL.md#46-verified-a-big-sequential-scan-doesnt-flush-shared_buffers-ring-buffers-)): after scanning 25,000 pages, only 397 stayed in `shared_buffers`; `pg_stat_io` shows the `bulkread` context reusing buffers. The OS page cache can still be churned, and the CPU, I/O bandwidth and `work_mem` the report uses are real contention.
</details>

🔍 **Probe 2: So what is slowing the API?**

<details><summary>🛡️ Defense</summary>

Measure: `pg_stat_activity` wait events during the window (I/O vs CPU vs locks), `pg_stat_io` evictions in the `normal` context, temp-file volume (`pg_stat_database.temp_bytes`) from spilling sorts and hashes, parallel workers consuming cores (`Workers Launched`), and lock waits if the report runs in a long transaction that also holds back vacuum.
</details>

🔍 **Probe 3 (L6): Fix it structurally.**

<details><summary>🛡️ Defense</summary>

Move the report off the primary: a replica (with `hot_standby_feedback` off and cancellations accepted, or a dedicated analytics replica), or CDC into a warehouse. If it must stay: a separate role with its own `work_mem` and `max_parallel_workers_per_gather`, `statement_timeout`, partition-wise aggregation for partitioned facts, and scheduling away from peak.
</details>

---

## L5 vs L6 signal

| Topic | L5 (senior) | L6 (staff) |
|---|---|---|
| Slow query | Reads `EXPLAIN ANALYZE`, adds the right composite index | Finds estimate errors, generic-plan traps and lock waits; builds plan-regression gates |
| Concurrency | Knows isolation levels and `FOR UPDATE` | Distinguishes PostgreSQL and InnoDB RR, write skew vs lost update, designs retries and hot-row strategies |
| MVCC | Knows VACUUM exists | Diagnoses the horizon (slots, idle transactions), plans for wraparound, tunes autovacuum per table |
| Scaling | "Add replicas" | Read-your-writes with LSN fencing, the routing proxy bug, sync-commit trade-offs, pooling math, when to shard |
| Migrations | Uses Flyway | Lock-queue awareness, `lock_timeout` + retry, expand/contract, linted migrations |
| Reading plans (Round 2) | Finds the slow node, adds an index | Reproduces costs and estimates by hand, recognizes row goals, VM bypass, FK triggers, non-hashed subplans, range-predicate propagation; turns signatures into fleet-wide detection |
| SSI | Retries 40001 | Explains predicate-lock granularity and promotion; reduces false positives by access path and layout |
| CDC slots | "They block vacuum" | Separates `catalog_xmin` from `xmin`, WAL retention from bloat; sets `max_slot_wal_keep_size` |

## Red flags

* "We use REPEATABLE READ so we're safe from lost updates" (on MySQL).
* "OFFSET pagination is fine, we have an index."
* "VACUUM FULL every night."
* "More connections = more throughput."
* "Replicas are always consistent within a few milliseconds."
* "The plan uses an index, so it's fine" (row goals, uncorrelated full-index scans).
* "Cost is milliseconds."
* "`NOT IN` and `NOT EXISTS` are the same thing."
* "PostgreSQL indexes foreign keys automatically."

---

## Rapid-fire flashcards

<details><summary>1. How big is a PostgreSQL page and an InnoDB page?</summary>8 KB and 16 KB.</details>

<details><summary>2. What's a `ctid`?</summary>(block number, line pointer) — the physical address an index stores.</details>

<details><summary>3. Tuple header size?</summary>23 bytes, padded to 24, plus a 4-byte line pointer.</details>

<details><summary>4. Two conditions for a HOT update?</summary>No indexed (or INCLUDE'd) column changes, and the new version fits on the same page.</details>

<details><summary>5. What's a full-page image and when is it written?</summary>A copy of the whole page in WAL on the first modification after a checkpoint, to survive torn writes.</details>

<details><summary>6. When does TOAST kick in?</summary>When a row exceeds about 2 KB: compress first, then move values out of line in ~2 KB chunks.</details>

<details><summary>7. E-S-R?</summary>Composite index column order: Equality, then Sort, then Range.</details>

<details><summary>8. What does `Index Searches: 5` mean in PG 18?</summary>Five index descents (e.g. a skip scan over 4 leading values + 1).</details>

<details><summary>9. Why can an index-only scan read the heap?</summary>Pages not marked all-visible in the visibility map need a visibility check (`Heap Fetches`).</details>

<details><summary>10. `jsonb_ops` vs `jsonb_path_ops`?</summary>`jsonb_path_ops` is smaller (40% in our test) but supports only `@>`.</details>

<details><summary>11. What's BRIN good for?</summary>Huge, physically ordered (append-only) tables queried by range: 24 kB vs 21 MB for the B-tree.</details>

<details><summary>12. What problem does `CREATE STATISTICS` solve?</summary>Misestimates from correlated columns (independence assumption): rows=1 → 142, actual 143.</details>

<details><summary>13. Three join algorithms and when each wins?</summary>Nested loop (small outer, indexed inner), hash (large unsorted equi-joins), merge (both sides sorted).</details>

<details><summary>14. What does `Batches: 16` on a Hash node mean?</summary>The hash table didn't fit in `work_mem × hash_mem_multiplier` and spilled to disk in 16 batches.</details>

<details><summary>15. After how many executions can a prepared statement go generic?</summary>After 5 custom plans (and pgjdbc server-prepares after 5 executions).</details>

<details><summary>16. Are CTEs optimization fences in PostgreSQL 12+?</summary>No, single-reference side-effect-free CTEs are inlined unless `MATERIALIZED`.</details>

<details><summary>17. What's the default window frame with ORDER BY?</summary>`RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` — ties are peers.</details>

<details><summary>18. Why does keyset need a tiebreaker?</summary>The sort key must be unique or rows at page boundaries are skipped or duplicated.</details>

<details><summary>19. How do you tell insert from update in `ON CONFLICT … RETURNING`?</summary>`(xmax = 0)` trick, or use `MERGE … RETURNING merge_action()` (PG 17+).</details>

<details><summary>20. What's the xmin horizon?</summary>The oldest snapshot anyone (sessions, slots, standbys) might still need; VACUUM can't remove versions newer than it.</details>

<details><summary>21. Why must tuples be frozen?</summary>32-bit XIDs wrap around; frozen tuples are "older than everything" forever.</details>

<details><summary>22. InnoDB equivalent of "dead but not yet removable"?</summary>A growing history list length (undo not purged).</details>

<details><summary>23. Which anomaly does SERIALIZABLE prevent that REPEATABLE READ doesn't (PostgreSQL)?</summary>Write skew.</details>

<details><summary>24. SQLStates to retry?</summary>40001 (serialization failure) and 40P01 (deadlock).</details>

<details><summary>25. Which row lock does an FK check take?</summary>`FOR KEY SHARE` on the referenced row — blocked by `FOR UPDATE`, not by `FOR NO KEY UPDATE`.</details>

<details><summary>26. What does `SKIP LOCKED` give up?</summary>Strict FIFO across workers.</details>

<details><summary>27. How does a 50 ms ALTER cause an outage?</summary>It waits for ACCESS EXCLUSIVE and every later query queues behind it.</details>

<details><summary>28. InnoDB next-key lock?</summary>A record lock plus the gap before it.</details>

<details><summary>29. LSN fencing in one line?</summary>Read a replica only when `pg_last_wal_replay_lsn() >= commit_lsn`.</details>

<details><summary>30. Why `LazyConnectionDataSourceProxy` with routing?</summary>So the routing decision happens after the read-only flag is set.</details>

<details><summary>31. Why can't you `DETACH PARTITION … CONCURRENTLY` sometimes?</summary>A default partition exists.</details>

<details><summary>32. Little's law?</summary>L = λW: busy connections = TPS × transaction time.</details>

<details><summary>33. Seq scan cost formula?</summary>`relpages × seq_page_cost + reltuples × (cpu_tuple_cost + cpu_operator_cost × quals)`: 21,912 for the atlas `orders` scan.</details>

<details><summary>34. Parallel divisor for 2 workers?</summary>2.4 (each worker 1, leader 1 − 0.3 × 2); CPU cost is divided, I/O isn't.</details>

<details><summary>35. Why can `Heap Fetches` stay high right after VACUUM?</summary>Index cleanup was bypassed (< ~2 % of pages with dead items); pages with `LP_DEAD` stubs can't be all-visible. `VACUUM (INDEX_CLEANUP ON)`.</details>

<details><summary>36. `Heap Blocks: lossy`?</summary>The bitmap didn't fit in `work_mem`; whole pages are rechecked (`Rows Removed by Index Recheck`).</details>

<details><summary>37. Signature of a row-goal trap?</summary>`Limit` → ordered `Index Scan` with a `Filter` and a huge `Rows Removed by Filter`.</details>

<details><summary>38. What does `(customer_id)::numeric = …` in a Filter tell you?</summary>The parameter was sent as numeric; the column is cast and its index can't be used (JDBC `BigDecimal` for a `bigint`).</details>

<details><summary>39. `Trigger for constraint … time=4184`?</summary>FK enforcement per row; the referencing column has no index.</details>

<details><summary>40. Does PostgreSQL derive range predicates across a join?</summary>No, only equalities (equivalence classes). Add the redundant predicate on the big side.</details>

<details><summary>41. `SubPlan` vs `hashed SubPlan` vs `InitPlan`?</summary>Per outer row / once into a hash table / once before the parent.</details>

<details><summary>42. Default selectivities when there are no statistics?</summary>1/3 for inequalities, 0.5 % for equalities.</details>

<details><summary>43. What does a logical replication slot hold back?</summary>`catalog_xmin` (catalog bloat) and WAL; not data-table vacuum.</details>

<details><summary>44. When are SSI page locks promoted?</summary>Beyond `max_pred_locks_per_relation` (default −2 → 64/2 = 32 pages) per relation.</details>

<details><summary>45. Why doesn't a big report seq scan wipe `shared_buffers`?</summary>Tables larger than ¼ of `shared_buffers` are scanned through a small ring buffer (`BAS_BULKREAD`).</details>

<details><summary>46. Four WAL records per non-HOT update with two indexes?</summary>`Heap/LOCK`, `Heap/UPDATE`, and one `Btree/INSERT_LEAF` per index; a HOT update is one `Heap/HOT_UPDATE`.</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–12) | p99 regression, feed pagination, bloat, wraparound, oversell, queue choice, migration outage, replica consistency, key choice, MySQL deadlocks, pool sizing, sharding | Breadth across storage, MVCC, concurrency and scaling |
| Round 2 (13–22) | Row goal, VM bypass, FK trigger cost, range-predicate propagation, NOT IN, correlated predicates, cost model, SSI false positives, CDC slots, report contention | Reading real plans, reproducing the planner's numbers, and turning one fix into fleet-wide prevention |

The pattern behind every L6 answer in Round 2: **name the mechanism, show the measured before/after, state the side effect, then make the fix systematic** (lint, alert, CI plan gate, runbook).

**Next pillar:** [3.1 Persistence context, entity states and dirty checking →](../03-JPA-Hibernate-Spring-Data/01-Persistence-Context-Entity-States-Dirty-Checking.md)
