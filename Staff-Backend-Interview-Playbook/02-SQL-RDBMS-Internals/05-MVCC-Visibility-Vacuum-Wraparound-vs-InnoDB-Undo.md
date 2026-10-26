# 2.5 MVCC: Snapshots, Tuple Visibility, VACUUM, Freezing & Wraparound, vs InnoDB Undo and Purge

> **Verified stack:** PostgreSQL **18.6** and MySQL **8.4.13** (InnoDB). Multi-session scenarios ran through a small JDBC tool that interleaves sessions `A`, `B`, `M` (monitor) step by step. `A>` is a statement, the indented lines are its result, and `-- (not waiting)` marks a statement started asynchronously because it may block.
>
> **Builds on:** [2.1](01-Storage-Pages-Tuples-TOAST-WAL.md) (where `xmin`/`xmax` live in the tuple header).

---

## 0. First principles: why MVCC 🔥

Two transactions touch the same row: a report reading balances and a payment updating one. With **locking only**, the reader waits for the writer (or the writer waits for a long report). With **MVCC**, the writer creates a **new version** and the reader keeps reading the **old version that was current when its snapshot was taken**. Readers never block writers, and writers never block readers.

The price: **old versions pile up** and something must remove them once nobody can see them. In PostgreSQL that's **VACUUM**, cleaning the table itself. In InnoDB it's the **purge** thread, cleaning **undo logs**. Every MVCC operational problem (bloat, wraparound, "history list length") is that price showing up.

---

## 1. Snapshots and visibility in PostgreSQL ⚡

### 1.1 The rule

Each tuple version carries `xmin` (creating transaction) and `xmax` (deleting or updating transaction, 0 if none). A **snapshot** is `xmin:xmax:xip_list`:

* every XID **< snapshot.xmin** had finished when the snapshot was taken,
* every XID **≥ snapshot.xmax** hadn't started,
* XIDs in **`xip_list`** were in progress.

A tuple version is visible to a snapshot when **its `xmin` committed and is visible to the snapshot**, and **its `xmax` is 0, aborted, or not yet visible to the snapshot**. Commit status comes from `pg_xact` (the commit log), cached on the tuple as **hint bits** (`HEAP_XMIN_COMMITTED`…) after the first check.

When the snapshot is taken depends on the isolation level:

| Level | Snapshot taken |
|---|---|
| READ COMMITTED (default) | At the start of **each statement** |
| REPEATABLE READ / SERIALIZABLE | At the **first statement** of the transaction, then reused |

### 1.2 Verified: the old version stays visible to an older snapshot

```text
A> begin isolation level repeatable read
A> select pg_current_snapshot() as snapshot, txid_current() as my_xid
   snapshot | my_xid
   ---------+-------
   863:863: | 863
A> select id, balance, xmin, xmax from acct order by id
   id | balance | xmin | xmax
   ---+---------+------+-----
   1  | 100     | 862  | 0
   2  | 100     | 862  | 0
B> update acct set balance = balance - 30 where id = 1
   UPDATE 1
B> select id, balance, xmin, xmax from acct order by id
   id | balance | xmin | xmax
   ---+---------+------+-----
   1  | 70      | 864  | 0
   2  | 100     | 862  | 0
# A's snapshot was taken before B committed: A still sees the OLD version
A> select id, balance, xmin, xmax from acct order by id
   id | balance | xmin | xmax
   ---+---------+------+-----
   1  | 100     | 862  | 864
   2  | 100     | 862  | 0
A> commit
A> select id, balance, xmin, xmax from acct order by id
   id | balance | xmin | xmax
   ---+---------+------+-----
   1  | 70      | 864  | 0
```

Read the third result carefully. A sees `balance = 100` **with `xmax = 864`**: the version B superseded. XID 864 is B's update, which committed *after* A's snapshot (`863:863:`), so for A that deletion "hasn't happened yet". Both versions physically exist on the page at once.

And READ COMMITTED takes a new snapshot per statement:

```text
A> begin isolation level read committed
A> select balance from acct where id = 2
   100
B> update acct set balance = 150 where id = 2
A> select balance from acct where id = 2
   150
```

### 1.3 Hint bits: why a SELECT can write (verified)

```text
 lp | t_xmin | t_xmax |                                       raw_flags
----+--------+--------+---------------------------------------------------------------------------------------
  1 |    766 |    768 | {HEAP_HASVARWIDTH,HEAP_XMIN_COMMITTED,HEAP_XMAX_COMMITTED,HEAP_HOT_UPDATED}
  ...
  4 |    768 |      0 | {HEAP_HASVARWIDTH,HEAP_XMIN_COMMITTED,HEAP_XMAX_INVALID,HEAP_UPDATED,HEAP_ONLY_TUPLE}
  5 |    776 |      0 | {HEAP_HASVARWIDTH,HEAP_XMAX_INVALID,HEAP_UPDATED,HEAP_ONLY_TUPLE}
```

Tuple 4 has `HEAP_XMIN_COMMITTED` because some reader checked `pg_xact` and **cached the answer on the tuple**. Tuple 5 hasn't been read since its transaction committed, so it has no hint yet. The first reader after a bulk load sets hint bits on every tuple, dirtying every page, so **the first `SELECT` after a big `COPY` can generate heavy writes** (and full-page images in WAL when checksums are on). Vacuuming after bulk loads, or `COPY … FREEZE`, avoids that surprise.

---

## 2. VACUUM: reclaiming dead versions ⚡

A version is **dead** when its `xmax` committed and **no snapshot anywhere can still need it**. "Anywhere" means the **xmin horizon**: the oldest `xmin` among all running transactions, replication slots, and hot-standby feedback.

VACUUM (manual or autovacuum):

1. scans pages (skipping all-visible ones via the visibility map),
2. removes dead tuples **older than the horizon** and makes their line pointers reusable,
3. removes the matching index entries (index scan pass),
4. updates the **visibility map** (all-visible, all-frozen) and the **free space map**,
5. **freezes** old tuples (§3).

Plain VACUUM **does not shrink the file** (except for empty pages at the end). It makes the space reusable. `VACUUM FULL` (or `pg_repack`) rewrites the table and **takes an `ACCESS EXCLUSIVE` lock** for the whole rewrite.

### 2.1 Verified: one idle transaction blocks cleanup for the whole database

```text
B> create table hot_tbl (id int primary key, n int) with (autovacuum_enabled = false)
B> insert into hot_tbl select g, 0 from generate_series(1, 10000) g
B> vacuum hot_tbl
A> begin isolation level repeatable read
A> select count(*) from hot_tbl
   10000
# A is now "idle in transaction" with an old snapshot
B> update hot_tbl set n = n + 1
   UPDATE 10000
B> vacuum (verbose) hot_tbl
   finished vacuuming "lab.public.hot_tbl": index scans: 0
   pages: 0 removed, 89 remain, 89 scanned (100.00% of total), 0 eagerly scanned
   tuples: 0 removed, 20000 remain, 10000 are dead but not yet removable
   removable cutoff: 915, which was 1 XIDs old when operation ended
   ...
M> select pid, state, backend_xmin, age(backend_xmin) as xmin_age, now() - xact_start as xact_age from pg_stat_activity where backend_xmin is not null ...
   pid   | state               | backend_xmin | xmin_age | xact_age
   ------+---------------------+--------------+----------+----------------
   18116 | idle in transaction | 915          | 1        | 00:00:00.098563
A> commit
B> vacuum (verbose) hot_tbl
   finished vacuuming "lab.public.hot_tbl": index scans: 1
   pages: 0 removed, 89 remain, 89 scanned (100.00% of total), 0 eagerly scanned
   tuples: 10000 removed, 10000 remain, 0 are dead but not yet removable
   ...
   visibility map: 89 pages set all-visible, 44 pages set all-frozen (0 were all-visible)
   index scan needed: 45 pages from table (50.56% of total) had 10000 dead item identifiers removed
```

**`10000 are dead but not yet removable`** is the line to remember. Session A did nothing except hold a snapshot, and VACUUM could clean **nothing** updated after it, in **any table in the database**. In production the "session A" is:

| Culprit | How to spot it | Prevention |
|---|---|---|
| An app connection left `idle in transaction` (exception path didn't roll back, a debugger breakpoint, a long HTTP call inside `@Transactional`) | `pg_stat_activity.state = 'idle in transaction'`, `xact_start` old | `idle_in_transaction_session_timeout`; keep transactions short; no remote calls inside transactions ([3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md)) |
| A long analytical query on the primary | `pg_stat_activity` `backend_xmin` age | Run analytics on a replica or warehouse; `statement_timeout` |
| A **stale replication slot** (CDC connector down, Debezium stopped) | `pg_replication_slots.xmin` / `catalog_xmin`, `restart_lsn` far behind. **Logical** slots hold only `catalog_xmin` (system-catalog bloat) plus WAL; **physical** slots with `hot_standby_feedback` hold `xmin` (all tables). Verified in §2.3 | Alert on slot lag; `max_slot_wal_keep_size` |
| `hot_standby_feedback = on` with long replica queries | The replica's `backend_xmin` reported in `pg_stat_replication` | Accept query cancellations on replicas, or isolate analytics |
| Abandoned prepared (2PC) transactions | `pg_prepared_xacts` | Monitor; don't use 2PC casually |

Note the PostgreSQL 18 field `0 eagerly scanned`: PG 18 adds **eager freezing** during normal vacuums of all-visible pages, which spreads freeze work out before an expensive anti-wraparound vacuum is forced.

### 2.2 Autovacuum: when it runs, and why it falls behind

Autovacuum vacuums a table when `n_dead_tup > autovacuum_vacuum_threshold (50) + autovacuum_vacuum_scale_factor (0.2) × reltuples`. On a 500 M-row table that's **100 M dead tuples** before it starts. Big, hot tables need per-table settings:

```sql
alter table orders set (
  autovacuum_vacuum_scale_factor = 0.01,     -- 1% instead of 20%
  autovacuum_vacuum_cost_limit   = 2000,     -- let it work faster (I/O budget)
  autovacuum_analyze_scale_factor = 0.02
);
```

PostgreSQL 18 also adds `autovacuum_vacuum_max_threshold` (a cap on that formula) and `autovacuum_worker_slots` (changing the number of workers without a restart). Watch `pg_stat_user_tables` (`n_dead_tup`, `last_autovacuum`) and `pg_stat_progress_vacuum`.

One more reason a VACUUM can look like it did nothing for index-only scans: with fewer than ~2 % of pages holding dead items, VACUUM **bypasses index cleanup**, and those pages stay not-all-visible. Verified with `VACUUM VERBOSE` output in [2.9 §5](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#5-index-only-scan-the-visibility-map-and-the-vacuum-that-didnt-help-).

### 2.3 Verified: what a stale logical replication slot actually blocks 🧊

The CDC incident ("Debezium was down for a weekend") is usually described as "the slot blocks vacuum". The precise version is better interview material:

```sql
create table slotdemo (id int primary key, n int) with (autovacuum_enabled = false);
insert into slotdemo select g, 0 from generate_series(1, 10000) g;
vacuum slotdemo;
select * from pg_create_logical_replication_slot('cdc_demo', 'test_decoding');   -- a consumer that never connects
select slot_name, plugin, slot_type, active, xmin, catalog_xmin from pg_replication_slots;
update slotdemo set n = n + 1;
vacuum (verbose) slotdemo;                                                          -- 1: a user table
-- 200 × create/drop temp table (catalog churn, as an app or migration tool does)
vacuum (verbose) pg_attribute;                                                      -- 2: a system catalog
insert into slotdemo select g, 0 from generate_series(10001, 210000) g;
select slot_name, active, catalog_xmin, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as wal_retained, wal_status
from pg_replication_slots;                                                          -- 3: WAL
select pg_drop_replication_slot('cdc_demo');
vacuum (verbose) pg_attribute;                                                      -- 4: after dropping the slot
```

**Output (verified, PostgreSQL 18.6, excerpts):**

```text
 slot_name |    plugin     | slot_type | active | xmin | catalog_xmin
-----------+---------------+-----------+--------+------+--------------
 cdc_demo  | test_decoding | logical   | f      |      |       147340

-- 1: user table
INFO:  finished vacuuming "atlas.public.slotdemo": index scans: 1
tuples: 10000 removed, 10000 remain, 0 are dead but not yet removable

-- 2: catalog
INFO:  finished vacuuming "atlas.pg_catalog.pg_attribute": index scans: 0
tuples: 0 removed, 7245 remain, 4000 are dead but not yet removable

-- 3: WAL
 slot_name | active | catalog_xmin | wal_retained | wal_status
-----------+--------+--------------+--------------+------------
 cdc_demo  | f      |       147340 | 31 MB        | reserved

-- 4: after dropping the slot
INFO:  table "pg_attribute": truncated 132 to 68 pages
tuples: 4000 removed, 1569 remain, 0 are dead but not yet removable
```

| A stale **logical** slot… | Verified? |
|---|---|
| …does **not** hold back vacuum of your data tables (`xmin` is NULL) | Yes: 10,000 dead rows removed with the slot present |
| …**does** hold back vacuum of **system catalogs** (`catalog_xmin`): it needs old catalog versions to decode old WAL with the schema of that time | Yes: 4,000 dead `pg_attribute` rows not removable until the slot was dropped |
| …**retains all WAL** from its `restart_lsn`: the disk fills | Yes: 31 MB after 200,000 inserts, growing without limit |

So the real outage modes of an abandoned CDC slot are **`pg_wal` filling the disk** (primary stops) and **catalog bloat** (planning and DDL slow down in schemas with heavy temp-table or partition churn). A **physical** slot with `hot_standby_feedback = on` is the one that holds back `xmin` for **every** table. Defenses: alert on `pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)` and `wal_status` (`extended`/`unreserved`/`lost`), and set `max_slot_wal_keep_size`, which invalidates a slot that falls too far behind instead of letting it kill the primary. PG 18 also adds `idle_replication_slot_timeout`.

Finding whoever holds the horizon, in one query:

```sql
select 'backend' as holder, pid::text as id, state, age(backend_xmin) as xmin_age from pg_stat_activity where backend_xmin is not null
union all select 'slot', slot_name, slot_type, greatest(age(xmin), age(catalog_xmin)) from pg_replication_slots
union all select 'prepared xact', gid, 'prepared', age(transaction) from pg_prepared_xacts
order by xmin_age desc nulls last;
```

---

## 3. Freezing and transaction ID wraparound 🔥

### 3.1 The problem (first principles)

XIDs are **32-bit** counters (about 4.29 billion values) compared with **modular arithmetic**: for any XID, about 2.1 billion XIDs are "in the past" and 2.1 billion are "in the future". If a tuple's `xmin` were left untouched while the counter advanced 2.1 billion transactions, that tuple's creator would suddenly look like it's **in the future**, and the row would vanish from every query.

So VACUUM **freezes** old tuples: it marks them "committed, older than everything" (`HEAP_XMIN_FROZEN`), so their `xmin` no longer needs comparing. Each table tracks `relfrozenxid` (all XIDs older than this are frozen). `age(relfrozenxid)` measures how close it is to danger.

### 3.2 Verified: before and after `VACUUM (FREEZE)`

```text
select datname, datfrozenxid, age(datfrozenxid) as xid_age from pg_database order by datname;
  datname  | datfrozenxid | xid_age
-----------+--------------+---------
 lab       |          744 |     172
 ...
show autovacuum_freeze_max_age;   -- 200000000
show vacuum_freeze_min_age;       -- 50000000

 relname | relfrozenxid | age
---------+--------------+-----
 account |          765 | 151

vacuum (freeze) account;

 relname | relfrozenxid | age
---------+--------------+-----
 account |          916 |   0

 lp | t_xmin | t_xmax |   combined_flags
----+--------+--------+--------------------
  4 |    768 |      0 | {HEAP_XMIN_FROZEN}
  5 |    776 |      0 | {HEAP_XMIN_FROZEN}
  6 |    777 |      0 | {HEAP_XMIN_FROZEN}
```

Also notice: the superseded versions (`lp` 1–3 earlier) are **gone**. VACUUM pruned them, because no snapshot needed them anymore.

### 3.3 The escalation ladder (what happens if you ignore it)

| `age(relfrozenxid)` | What PostgreSQL does |
|---|---|
| > `autovacuum_freeze_max_age` (200 M) | Forces an **anti-wraparound autovacuum** on that table, even if autovacuum is disabled for it. It can't be cancelled by lock conflicts, and it scans the whole table |
| ~ 2^31 − 40 M (about 2.1 billion minus 40 million) | WARNINGs: "database must be vacuumed within N transactions" |
| ~ 2^31 − 3 M | **Refuses new XID assignment**: the database is effectively read-only until a manual VACUUM finishes |

**The incident pattern:** an insert-heavy table never accumulates dead tuples, so regular autovacuum rarely visits it. One day it hits 200 M age, a full-table anti-wraparound vacuum starts during peak hours, I/O spikes, and if something holds back the horizon (§2.1) the age keeps climbing toward a forced read-only outage.

**Defenses:** monitor `age(datfrozenxid)` and `age(relfrozenxid)` with alerts at ~40% and ~60% of 2 billion; make sure `autovacuum_vacuum_insert_threshold` (PG 13+) handles insert-only tables; remove horizon-holders; consider periodic `VACUUM (FREEZE)` in quiet windows for giant append-only tables. Multixact IDs (used for shared row locks, e.g. FK checks and `FOR SHARE`) wrap around too: watch `mxid_age(datminmxid)`.

---

## 4. InnoDB: undo logs and purge 🔥

### 4.1 Mechanism

* An `UPDATE` modifies the row **in place** in the clustered index and writes the **before-image** to an **undo log** record. Each row has a hidden `DB_TRX_ID` (last writer) and `DB_ROLL_PTR` (pointer into undo).
* A consistent read follows the row's **undo chain** backward until it finds a version visible to its **read view** (InnoDB's snapshot).
* Once no read view needs old undo records, the **purge** threads discard them and remove delete-marked index records.
* The **history list length** (HLL) counts committed transactions whose undo hasn't been purged yet.

### 4.2 Verified: a long transaction makes the history list grow

```text
M> select name, count from information_schema.innodb_metrics where name = 'trx_rseg_history_len'
   trx_rseg_history_len | 17
A> start transaction with consistent snapshot
A> select sum(n) from counter
   3000
# 5,000 small autocommit transactions while A's snapshot is open
B> call bump(5000)
M> select name, count from information_schema.innodb_metrics where name = 'trx_rseg_history_len'
   trx_rseg_history_len | 5001
A> commit
   (5 seconds later)
M> select name, count from information_schema.innodb_metrics where name = 'trx_rseg_history_len'
   trx_rseg_history_len | 0
```

The same disease as PostgreSQL's "dead but not yet removable", in a different organ. While A was open, **every** consistent read that needed an older version had to walk longer undo chains (slower `SELECT`s on hot rows), and undo tablespaces grew.

### 4.3 PostgreSQL vs InnoDB MVCC

| Concern | PostgreSQL | InnoDB |
|---|---|---|
| Where old versions live | In the **table** (heap) and index entries | In **undo logs** (rollback segments) |
| Cost of an update | New tuple (+ index entries unless HOT) | In-place change + undo record |
| Reading an old version | Direct (it's just another tuple) | Walk the undo chain (gets slower as the chain grows) |
| Reading the current version | May skip dead tuples and follow HOT chains | Direct |
| Rollback cost | Cheap (versions are just marked invisible) | **Expensive** (undo must be applied) |
| Cleanup | VACUUM / autovacuum | Purge threads |
| Long-transaction symptom | Bloat, "dead but not yet removable", wraparound risk | History list length, slow consistent reads, big undo tablespaces |
| Space reclaim | Space reused in place; `VACUUM FULL`/`pg_repack` to shrink | Undo truncation (`innodb_undo_log_truncate`) |
| XID wraparound | **Yes**: 32-bit XIDs, freezing required | No: 48-bit transaction IDs |

---

## 5. ❌ Naïve vs ✅ production-hardened MVCC operations

| ❌ Naïve | ✅ Hardened |
|---|---|
| Default autovacuum on a 1 B-row hot table | Per-table scale factors and cost limits; watch `n_dead_tup` and vacuum duration |
| `@Transactional` method that calls a payment API (30 s timeout) | Remote calls **outside** transactions; `idle_in_transaction_session_timeout` |
| CDC connector paused for a week "temporarily" | Alert on replication-slot lag; `max_slot_wal_keep_size` |
| Alert only on disk space | Alert on `age(datfrozenxid)`, `mxid_age`, oldest `backend_xmin` age, HLL in MySQL |
| `VACUUM FULL` at noon to "fix bloat" | `pg_repack` (online), or a planned maintenance window. Find the bloat's root cause first |
| Assume `DELETE` of 50 M rows frees disk | It creates 50 M dead tuples. Partition by time and `DROP`/`DETACH` partitions instead ([2.7](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)) |

---

## 6. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/access/heap/heapam_visibility.c` | `HeapTupleSatisfiesMVCC`: the visibility rules in §1.1, line by line |
| postgres/postgres | `src/backend/storage/ipc/procarray.c` | `GetSnapshotData`, how the xmin horizon is computed |
| postgres/postgres | `src/backend/access/heap/vacuumlazy.c` | The phases of VACUUM, PG 18 eager scanning, freezing decisions |
| postgres/postgres | `src/backend/postmaster/autovacuum.c` | Thresholds and anti-wraparound scheduling |
| [mysql/mysql-server](https://github.com/mysql/mysql-server) | `storage/innobase/read/read0read.cc` | InnoDB read views |
| mysql/mysql-server | `storage/innobase/trx/trx0purge.cc` | Purge and the history list |

---

## 7. Interview soundbites

* "PostgreSQL keeps old versions in the table; VACUUM removes them once no snapshot can see them. InnoDB keeps them in undo; purge removes them. Same contract, different places to get hurt."
* "One idle-in-transaction session made VACUUM report `10000 are dead but not yet removable`. The horizon is database-wide, so a single forgotten transaction bloats every busy table."
* "XIDs are 32-bit and compared modulo 2^32, so old tuples must be frozen. Past 200 M age autovacuum forces a full scan; near 2 billion the database stops assigning XIDs."
* "In MySQL I watch the history list length. A long consistent-snapshot transaction took it from 17 to 5,001; after commit purge brought it to 0."
* "A stale logical slot doesn't block vacuum of your tables: its `xmin` is NULL. It holds back the **catalogs** (`catalog_xmin`: 4,000 dead `pg_attribute` rows unremovable) and it retains **all WAL**, which is what actually takes the primary down. `max_slot_wal_keep_size` is the safety valve."

---

## Summary

| Concept | Key point | Verified evidence |
|---|---|---|
| Visibility | A version is visible if `xmin` committed before the snapshot and `xmax` didn't | Old version visible to an older snapshot (§1.2) |
| Hint bits | First reader stamps commit status on tuples: a `SELECT` can dirty pages | §1.3 |
| xmin horizon | Oldest snapshot among backends, physical slots (feedback), prepared xacts | One idle transaction: `10000 are dead but not yet removable` |
| Logical slots | Hold `catalog_xmin` and WAL, not data-table `xmin` | User table cleaned; 4,000 catalog rows stuck; 31 MB WAL retained |
| VACUUM | Removes dead versions, sets VM bits, freezes; doesn't shrink files | Index-cleanup bypass under 2 % dead pages ([2.9 §5](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#5-index-only-scan-the-visibility-map-and-the-vacuum-that-didnt-help-)) |
| Autovacuum | Threshold 50 + 20 % of rows: big tables need per-table settings | PG 18 `autovacuum_vacuum_max_threshold` |
| Wraparound | 32-bit XIDs; freeze; 200 M forced vacuum; ~2 B read-only | `relfrozenxid` age 151 → 0 after `VACUUM (FREEZE)` |
| InnoDB | In-place update + undo; purge; history list length | HLL 17 → 5,001 → 0 |

**Next:** [2.6 Isolation anomalies, row locks, SKIP LOCKED, gap locks, deadlocks →](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)
