# 2.6 Isolation Anomalies & Locking: Lost Update, Write Skew, SSI, Row-Lock Modes, `SKIP LOCKED`, DDL Lock Queues, InnoDB Gap/Next-Key Locks, Deadlocks

> **Verified stack:** PostgreSQL **18.6** and MySQL **8.4.13** (InnoDB, `REPEATABLE READ`, `innodb_lock_wait_timeout = 5`). Every scenario ran through an interleaving JDBC tool: `A>`/`B>`/`C>` are sessions, `M>` is a monitoring session, `-- (not waiting)` means the statement was started asynchronously, `... B is blocked` means it was still waiting 300 ms later, and `B<` is its eventual result.
>
> **Builds on:** [2.5 MVCC](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md). **Used by:** [3.5 `@Transactional`](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md), [5.4 Outbox](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md).

---

## 0. First principles: isolation = which interleavings the database forbids 🔥

Concurrent transactions interleave their reads and writes. An **anomaly** is an interleaving whose result couldn't happen if the transactions had run one after another. Isolation levels are contracts about **which anomalies are prevented**, and every level that prevents more costs more: more waiting (locks) or more aborts and retries (optimistic detection).

The SQL standard defines levels by three anomalies. Real systems care about more:

| Anomaly | Interleaving | Example |
|---|---|---|
| **Dirty read** | T1 reads T2's uncommitted write | You see a payment that's later rolled back |
| **Non-repeatable read** | T1 reads X twice, T2 commits a change in between | A report's two totals don't match |
| **Phantom** | T1 runs a range query twice, T2 inserts a row into the range | `count(*)` changes within one transaction |
| **Lost update** | T1 and T2 read X, both write X based on what they read; one write vanishes | Two +10/+20 increments produce +20 |
| **Write skew** | T1 and T2 read an overlapping set, each writes a *different* row; together they break an invariant | Two doctors both go off call |
| **Read skew** | T1 reads X, T2 updates X and Y and commits, T1 reads Y | Transfer appears to create or destroy money |

### What each engine actually prevents

| | Dirty read | Non-repeatable | Phantom | Lost update | Write skew |
|---|---|---|---|---|---|
| PostgreSQL **READ COMMITTED** (default) | ✅ | ❌ | ❌ | ❌ (with read-then-write in the app) | ❌ |
| PostgreSQL **REPEATABLE READ** (snapshot isolation) | ✅ | ✅ | ✅ | ✅ (aborts with **40001**) | ❌ |
| PostgreSQL **SERIALIZABLE** (SSI) | ✅ | ✅ | ✅ | ✅ | ✅ (aborts with **40001**) |
| MySQL InnoDB **READ COMMITTED** | ✅ | ❌ | ❌ | ❌ | ❌ |
| MySQL InnoDB **REPEATABLE READ** (default) | ✅ | ✅ for plain `SELECT` (snapshot) | ✅ for plain `SELECT`; next-key locks for locking reads | ❌ **(verified below)** | ❌ |
| MySQL InnoDB **SERIALIZABLE** | ✅ | ✅ | ✅ | ✅ (plain `SELECT` becomes a locking read) | ✅ (via locks, so more deadlocks) |

(PostgreSQL's READ UNCOMMITTED behaves as READ COMMITTED: MVCC never exposes uncommitted data.)

---

## 1. Lost update, and four fixes (PostgreSQL, verified) 🔥

### 1.1 The bug: read-modify-write in the application

```text
A> begin
B> begin
A> select balance from acct where id = 1
   100
B> select balance from acct where id = 1
   100
# both apps compute 100 + 10 and 100 + 20 in Java, then write back
A> update acct set balance = 110 where id = 1
   UPDATE 1
B> update acct set balance = 120 where id = 1   -- (not waiting)
   ... B is blocked
A> commit
B< UPDATE 1
B> commit
A> select balance from acct where id = 1
   120
# expected 130, got 120: A's +10 was LOST
```

B *was* blocked by A's row lock. But once A committed, READ COMMITTED **re-evaluated B's `WHERE` on the new row version and applied B's absolute value**, which was computed from stale data. Locks serialize *writes*. They don't protect a decision made from an earlier *read*.

### 1.2 Fix 1: an atomic update (let the database do the arithmetic)

```text
A> update acct set balance = balance + 10 where id = 1
   UPDATE 1
B> update acct set balance = balance + 20 where id = 1   -- (not waiting)
   ... B is blocked
A> commit
B< UPDATE 1
B> commit
A> select balance from acct where id = 1
   130
```

The `UPDATE` reads the **latest committed** version after acquiring the row lock (PostgreSQL's "EvalPlanQual" re-check). **Prefer this whenever the change can be expressed in SQL.** In JPA that's a bulk `@Modifying @Query("update … set qty = qty - :n where id = :id and qty >= :n")`.

### 1.3 Fix 2: pessimistic lock, `SELECT … FOR UPDATE`

```text
A> select balance from acct where id = 1 for update
   100
B> select balance from acct where id = 1 for update   -- (not waiting)
   ... B is blocked
A> update acct set balance = 110 where id = 1
A> commit
B< balance
   -------
   110
B> update acct set balance = 130 where id = 1
B> commit
```

B's read **waited** and then returned the fresh value (110). JPA: `@Lock(LockModeType.PESSIMISTIC_WRITE)`. Use it when contention is high, the critical section is short, and you'd rather wait than retry.

### 1.4 Fix 3: REPEATABLE READ detects the conflict

```text
A> begin isolation level repeatable read
B> begin isolation level repeatable read
A> select balance from acct where id = 1
   100
B> select balance from acct where id = 1
   100
A> update acct set balance = 110 where id = 1
B> update acct set balance = 120 where id = 1   -- (not waiting)
   ... B is blocked
A> commit
B< ERROR [40001] ERROR: could not serialize access due to concurrent update
B> rollback
```

Under snapshot isolation, B may not overwrite a row version newer than its snapshot. **The application must retry** (§3.3).

### 1.5 Fix 4: optimistic locking with a version column

```text
A> select balance, version from acct where id = 1
   100 | 0
B> select balance, version from acct where id = 1
   100 | 0
A> update acct set balance = 110, version = version + 1 where id = 1 and version = 0
   UPDATE 1
B> update acct set balance = 120, version = version + 1 where id = 1 and version = 0
   UPDATE 0
# B updated 0 rows -> the app throws OptimisticLockException and retries with fresh data
```

This is exactly what JPA's `@Version` generates. No locks are held between read and write, so it works across HTTP requests (user edits a form for 5 minutes) where a `FOR UPDATE` would be absurd.

### 1.6 Choosing

| Approach | Waits? | Retries? | Works across requests? | Best when |
|---|---|---|---|---|
| Atomic `UPDATE … SET x = x + ?` | Briefly (row lock) | No | n/a | The change is arithmetic or conditional |
| `SELECT … FOR UPDATE` | Yes | No | No | High contention, short critical section, complex logic |
| `@Version` (optimistic) | No | Yes (on conflict) | **Yes** | Low contention, long think-time edits |
| REPEATABLE READ / SERIALIZABLE | Sometimes | Yes | No | Multi-row invariants (SERIALIZABLE) |

---

## 2. Write skew and SSI 🧊

### 2.1 Verified: REPEATABLE READ lets the invariant break

Invariant: *at least one doctor must be on call.*

```text
A> begin isolation level repeatable read
B> begin isolation level repeatable read
A> select count(*) as on_call from doctor where on_call
   2
B> select count(*) as on_call from doctor where on_call
   2
# each sees 2, so each thinks it is safe to go off call
A> update doctor set on_call = false where name = 'alice'
   UPDATE 1
B> update doctor set on_call = false where name = 'bob'
   UPDATE 1
A> commit
B> commit
A> select * from doctor order by name
   alice | f
   bob   | f
# invariant broken: nobody is on call (they updated DIFFERENT rows, so no write-write conflict)
```

Snapshot isolation only detects **write-write** conflicts on the **same row**. Here each transaction wrote a different row, based on a read the other one invalidated.

### 2.2 Verified: SERIALIZABLE catches the dependency cycle

```text
A> begin isolation level serializable
B> begin isolation level serializable
A> select count(*) as on_call from doctor where on_call
   2
B> select count(*) as on_call from doctor where on_call
   2
A> update doctor set on_call = false where name = 'alice'
   UPDATE 1
B> update doctor set on_call = false where name = 'bob'
   UPDATE 1
A> commit
   COMMIT
B> commit
   ERROR [40001] ERROR: could not serialize access due to read/write dependencies among transactions Detail: Reason code: Canceled on identification as a pivot, during commit attempt. Hint: The transaction might succeed if retried.
A> select * from doctor order by name
   alice | f
   bob   | t
```

**How SSI works (first principles):** PostgreSQL's Serializable Snapshot Isolation runs on the same snapshots as REPEATABLE READ, but it also tracks **SIREAD "locks"**: markers of what each transaction *read*. They never block anyone. When transaction T1 reads something T2 later writes (an rw-antidependency, T1 → T2), and T2 reads something T3 writes (T2 → T3), T2 is a **"pivot"**: a *dangerous structure* that can produce a non-serializable result. SSI aborts one transaction in such structures. Note the failure happened **at commit**: your retry logic must cover `commit()`, not just the statements.

Costs: memory for predicate locks (`max_pred_locks_per_transaction`), **false positives** (page- or relation-level SIREAD locks can abort transactions that didn't really conflict), and mandatory retry logic everywhere.

### 2.3 Verified: or materialize the conflict with a lock

```text
A> begin
B> begin
A> select name from doctor where on_call for update
   bob
   alice
B> select name from doctor where on_call for update   -- (not waiting)
   ... B is blocked
A> update doctor set on_call = false where name = 'alice'
A> commit
B< name
   ----
   bob
   (1 row)
```

B's locking read waited, then re-evaluated and saw only **one** doctor on call, so the application logic stays on call. This works because the invariant's rows exist. For "insert if no conflicting row exists" (no row to lock yet), use a **unique or exclusion constraint** ([2.2 §5.3](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)), an advisory lock, or SERIALIZABLE.

### 2.4 The retry loop SERIALIZABLE requires (verified Java)

```java
interface TxBody<T> { T run(Connection c) throws SQLException; }

/** Runs body in a SERIALIZABLE transaction; retries on 40001 (serialization) and 40P01 (deadlock). */
static <T> T inSerializableTx(TxBody<T> body) throws SQLException {
    for (int attempt = 1; ; attempt++) {
        try (Connection c = DriverManager.getConnection(URL)) {
            c.setAutoCommit(false);
            c.setTransactionIsolation(Connection.TRANSACTION_SERIALIZABLE);
            try {
                T result = body.run(c);
                c.commit();                                   // SSI may also fail HERE, at commit
                return result;
            } catch (SQLException e) {
                c.rollback();
                boolean retryable = "40001".equals(e.getSQLState()) || "40P01".equals(e.getSQLState());
                if (!retryable || attempt == 5) throw e;
                retries.incrementAndGet();
                Thread.sleep(ThreadLocalRandom.current().nextLong(5, 20L * attempt));   // jittered backoff
            }
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            throw new SQLException("interrupted", ie);
        }
    }
}
```

Two threads ran `goOffCall("alice")` and `goOffCall("bob")` concurrently (a barrier forces both reads before either write).

**Output (verified, one of three runs; which doctor wins varies):**

```text
alice stays on call (only 1 on call)
bob went off call
on call now: 1, retries: 1
```

The loser was aborted, **retried with a fresh snapshot**, saw only one doctor on call, and kept the invariant. Rules: the **whole transaction** is the retry unit (re-read everything), cap the attempts, add jitter, and keep non-idempotent side effects (emails, HTTP calls) **outside** the retried block. In Spring, put the retry *around* the `@Transactional` boundary, never inside it ([3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md)).

---

### 2.5 Verified: SSI false positives come from predicate-lock *granularity* 🧊

SSI doesn't know which **rows** your transaction "logically" depended on. It records what the executor **read**, as `SIReadLock`s in `pg_locks`, at one of three granularities: **tuple**, **page** (heap or index), or **relation**. A later write by another transaction into something you read creates a read-write dependency; two of those in a cycle abort a transaction with 40001. The coarser the lock, the more **unrelated** transactions collide. Two transactions that each read one branch's total and then write only to their own branch:

```text
A> begin isolation level serializable
B> begin isolation level serializable
A> select sum(amount) from ledger where branch = 1
B> select sum(amount) from ledger where branch = 2      -- (or 5)
A> <write to branch 1>
B> <write to branch 2>
A> commit
B> commit
```

**Output (verified, PostgreSQL 18.6, four layouts of the same 10,000-row table):**

```text
-- 1. no index on branch (seq scan reads the whole table)
M> select locktype, relation::regclass, page, tuple, count(*) from pg_locks where mode = 'SIReadLock' group by …
   relation | ledger | null | null | 2
B> commit
   ERROR [40001] could not serialize access due to read/write dependencies among transactions
   Detail: Reason code: Canceled on identification as a pivot, during commit attempt.

-- 2. index on branch, rows of branch 1 and 2 adjacent, inserts as the writes
   page     | ledger        | 0 | null
   page     | ledger        | 1 | null      ← both transactions locked heap page 1
   page     | ledger        | 1 | null
   page     | ledger_branch | 1 | null      ← and the same index leaf page
   page     | ledger_branch | 1 | null
B> commit
   ERROR [40001] … Canceled on identification as a pivot, during commit attempt.

-- 3. index on branch, 1,000 rows per branch clustered on their own pages, HOT updates in the middle of each branch
   page     | ledger        | 13
   page     | ledger_branch |  4
   tuple    | ledger        |  2
A> commit   COMMIT
B> commit   COMMIT

-- 4. index on branch, but branch 1's 100 rows spread over 54 heap pages (one transaction alone)
   page     | ledger_branch | 1
   relation | ledger        | 1      ← 54 page locks were promoted to one relation lock
```

| Layout | What the read locked | Result |
|---|---|---|
| No index | The whole relation | Disjoint branches aborted (false positive) |
| Index, neighbours share pages | Shared heap page and index leaf page | Aborted (false positive) |
| Index, data clustered, writes in non-shared pages | 13 heap pages, 4 index pages, 2 tuples | **Both committed** |
| Index, rows scattered over 54 pages | Promoted to a relation lock | Same as no index |

Why case 4: SSI keeps predicate locks in a fixed shared-memory pool. `max_pred_locks_per_relation = -2` means "`max_pred_locks_per_transaction` (64) / 2 = 32 pages": a transaction holding more than 32 page locks on one relation gets a single relation lock instead (and too many tuple locks on a page become a page lock).

**What a staff engineer does with this:**
* Run SERIALIZABLE workloads with **indexes that match the predicates** and queries that touch few pages. A seq scan under SERIALIZABLE is a relation-wide predicate lock.
* Keep **retry-with-backoff around the whole transaction** ([§2.4](#24-the-retry-loop-serializable-requires-verified-java)), and budget for false positives: the abort rate depends on data layout, not only on real conflicts.
* Raise `max_pred_locks_per_transaction` (restart) or `max_pred_locks_per_relation` if `pg_locks` shows relation-level SIRead locks on big tables you only read a little of.
* Declare read-only transactions as such (`SET TRANSACTION READ ONLY`, Spring `@Transactional(readOnly = true)` with `SERIALIZABLE`): SSI can then skip work, and `DEFERRABLE` read-only transactions never abort.

## 3. PostgreSQL row-lock modes and foreign keys ⚡

| Lock (strongest first) | Taken by | Conflicts with |
|---|---|---|
| `FOR UPDATE` | `SELECT … FOR UPDATE`, `DELETE`, `UPDATE` of a **key** column | All four |
| `FOR NO KEY UPDATE` | `UPDATE` of non-key columns, `SELECT … FOR NO KEY UPDATE` | `FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE` |
| `FOR SHARE` | `SELECT … FOR SHARE` | `FOR UPDATE`, `FOR NO KEY UPDATE` |
| `FOR KEY SHARE` | **Foreign-key checks** on the referenced row | `FOR UPDATE` only |

### Verified: `FOR UPDATE` blocks child inserts; `FOR NO KEY UPDATE` doesn't

```text
B> set lock_timeout = '500ms'
# FOR UPDATE takes the strongest row lock: it conflicts with the FOR KEY SHARE lock an FK check needs
A> begin
A> select * from purchase where id = 1 for update
B> insert into order_line values (10, 1, 'sku-1')
   ERROR [55P03] ERROR: canceling statement due to lock timeout Where: while locking tuple (0,1) in relation "purchase" SQL statement "SELECT 1 FROM ONLY "public"."purchase" x WHERE "id" OPERATOR(pg_catalog.=) $1 FOR KEY SHARE OF x"
A> rollback
# FOR NO KEY UPDATE (what a plain UPDATE of non-key columns takes) lets FK checks through
A> begin
A> select * from purchase where id = 1 for no key update
B> insert into order_line values (11, 1, 'sku-2')
   INSERT 1
A> update purchase set status = 'PAID' where id = 1
A> commit
```

The error even shows the hidden FK-check query: `SELECT 1 FROM ONLY "public"."purchase" x WHERE "id" = $1 FOR KEY SHARE OF x`. **Production lesson:** `SELECT … FOR UPDATE` on an aggregate root (JPA `PESSIMISTIC_WRITE` on `Order`) blocks every concurrent insert of child rows (`OrderLine`) that reference it. If you only intend to update non-key columns, `FOR NO KEY UPDATE` gives the same protection without serializing child inserts.

---

## 4. Work queues with `FOR UPDATE SKIP LOCKED` 🔥

### 4.1 Verified: two workers, disjoint batches, no waiting

```sql
create table job (id bigint generated always as identity primary key, status text not null default 'READY',
                  payload text, locked_by text, created_at timestamptz not null default now());
create index job_ready on job (created_at) where status = 'READY';     -- partial: only the backlog
```

```text
A> begin
B> begin
A> select id, payload from job where status = 'READY' order by created_at, id limit 2 for update skip locked
   1 | task-1
   2 | task-2
B> select id, payload from job where status = 'READY' order by created_at, id limit 2 for update skip locked
   3 | task-3
   4 | task-4
# workers got DISJOINT batches without waiting on each other
A> update job set status = 'DONE', locked_by = 'worker-A' where id in (1, 2)
B> update job set status = 'DONE', locked_by = 'worker-B' where id in (3, 4)
A> commit
B> commit
```

And the two "fail fast" alternatives:

```text
A> begin
A> select id from job where id = 5 for update
B> select id from job where id = 5 for update nowait
   ERROR [55P03] ERROR: could not obtain lock on row in relation "job"
B> set lock_timeout = '200ms'
B> update job set status = 'DONE' where id = 5
   ERROR [55P03] ERROR: canceling statement due to lock timeout Where: while updating tuple (0,5) in relation "job"
```

### 4.2 Designing a real queue on PostgreSQL

| Concern | Design |
|---|---|
| Claim | `… WHERE status = 'READY' AND run_at <= now() ORDER BY run_at LIMIT :batch FOR UPDATE SKIP LOCKED` |
| Process **inside** the claiming transaction? | Only for short work. Otherwise set `status = 'RUNNING', lease_until = now() + interval '5 min'` and **commit**, process, then mark `DONE`. A reaper resets expired leases (crash safety) |
| Retries | `attempts` column, exponential `run_at`, `status = 'DEAD'` after N (a dead-letter table) |
| Hot-path index | Partial index `WHERE status = 'READY'` keeps it tiny as `DONE` rows accumulate |
| Bloat | Every claim is an update. Delete or archive `DONE` rows (partition by day and drop) and tune autovacuum on the queue table |
| Wake-ups | `LISTEN/NOTIFY` to avoid tight polling (it doesn't work through PgBouncer transaction pooling) |
| Ordering | `SKIP LOCKED` gives **no strict FIFO across workers**. If per-key ordering matters, partition the work by key |

This is exactly the **polling publisher** of the transactional outbox ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)). Libraries built on it: db-scheduler, JobRunr, Quartz (JDBC store), Spring Modulith's event publication registry.

---

## 5. Deadlocks ⚡

### 5.1 Verified: opposite lock order

```text
A> begin
B> begin
A> update acct set balance = balance - 10 where id = 1
B> update acct set balance = balance - 10 where id = 2
A> update acct set balance = balance + 10 where id = 2   -- (not waiting)
   ... A is blocked
B> update acct set balance = balance + 10 where id = 1
   UPDATE 1
A< ERROR [40P01] ERROR: deadlock detected Detail: Process 25652 waits for ShareLock on transaction 904; blocked by process 25332. Process 25332 waits for ShareLock on transaction 903; blocked by process 25652. Hint: See server log for query details. Where: while updating tuple (0,24) in relation "acct"
# A was chosen as the victim (after deadlock_timeout = 1s); its transaction is aborted
A> rollback
B> commit
A> select id, balance from acct order by id
   1 | 110
   2 | 90
```

* PostgreSQL doesn't check for deadlocks on every wait. A waiting backend runs the detector after **`deadlock_timeout`** (default 1 s), so every deadlock costs at least one second of latency for someone.
* "Waits for **ShareLock on transaction 904**": row locks are implemented as waiting for the *other transaction* to finish (its XID lock), which is why the message names transactions, not rows.
* Only the victim is aborted. The survivor (B) continues and commits.

### 5.2 Prevention

| Technique | Example |
|---|---|
| **Canonical lock order** | Always lock accounts in ascending id: `select id from acct where id in (2, 1) order by id for update` (verified to return `1, 2` in order) |
| Lock everything up front, in one statement | Above, instead of two separate updates |
| Shorter transactions | Fewer locks held for less time |
| Avoid lock upgrades | Don't `FOR SHARE` then `UPDATE` the same row from two transactions |
| Retry 40P01 | Same retry wrapper as 40001 (§2.4) |
| Batched updates in key order | Sort the batch by key in the application before issuing it, or lock first with `SELECT … ORDER BY id FOR UPDATE` |

---

## 6. Table locks and the migration outage (verified) 🔥

Every statement takes a **table-level** lock too: `SELECT` takes `ACCESS SHARE`; `ALTER TABLE` (most forms) needs `ACCESS EXCLUSIVE`, which conflicts with everything. Lock requests wait in a **FIFO queue**, so one waiting `ALTER` blocks everyone behind it, even plain reads that are compatible with the current holder.

```text
A> begin
A> select count(*) from purchase
   1
# A holds ACCESS SHARE on purchase (any open transaction that touched the table does)
B> alter table purchase add column note text   -- (not waiting)
   ... B is blocked
# B needs ACCESS EXCLUSIVE: it queues behind A ...
C> select * from purchase where id = 1   -- (not waiting)
   ... C is blocked
# ... and C (a plain read!) queues behind B. Every new query on the table now waits.
M> select pid, wait_event_type, wait_event, state, left(query, 45) as query from pg_stat_activity where datname = 'lab' and wait_event_type = 'Lock' order by query_start
   pid   | wait_event_type | wait_event | state  | query
   ------+-----------------+------------+--------+------------------------------------------
   9472  | Lock            | relation   | active | alter table purchase add column note text
   21672 | Lock            | relation   | active | select * from purchase where id = 1
A> commit
B< ALTER
C< id | status | note
   1  | PAID   | null
```

In production, A is a slow report or an idle-in-transaction connection, B is your Flyway/Liquibase migration, and C is **all of your traffic**: connection pools fill up within seconds and the service goes down. The `ADD COLUMN` itself would have taken milliseconds.

**Safe-migration rules:**

1. Run DDL with a **short `lock_timeout`** (`SET lock_timeout = '2s'`) and **retry** with backoff. A failed attempt costs nothing; a queued one costs an outage.
2. Prefer forms that don't rewrite the table: `ADD COLUMN … DEFAULT <constant>` is metadata-only since PG 11; `ADD CONSTRAINT … NOT VALID` then `VALIDATE CONSTRAINT` (weaker lock); `CREATE INDEX CONCURRENTLY`.
3. Kill or avoid long transactions before deploys (`idle_in_transaction_session_timeout`).
4. Expand → migrate → contract: add the new column, dual-write, backfill in batches, switch reads, drop the old column in a later release.

---

## 7. MySQL InnoDB: next-key locks, gap locks, and a different RR ⚡

### 7.1 Verified: a range locking read locks the gaps

```text
A> create table t (id int primary key, k int not null, key k_idx (k)) engine = InnoDB
A> insert into t values (1, 10), (2, 20), (3, 30)
A> start transaction
A> select id, k from t where k between 15 and 25 for update
   2 | 20
M> select index_name, lock_type, lock_mode, lock_status, lock_data from performance_schema.data_locks where object_name = 't' order by index_name, lock_data
   index_name | lock_type | lock_mode     | lock_status | lock_data
   -----------+-----------+---------------+-------------+----------
   null       | TABLE     | IX            | GRANTED     | null
   k_idx      | RECORD    | X             | GRANTED     | 20, 2
   k_idx      | RECORD    | X             | GRANTED     | 30, 3
   PRIMARY    | RECORD    | X,REC_NOT_GAP | GRANTED     | 2
   PRIMARY    | RECORD    | X,REC_NOT_GAP | GRANTED     | 3
# B inserts k = 17 (no row has k = 17, nobody "locked" it), but it falls in a locked GAP
B> insert into t values (4, 17)   -- (not waiting)
   ... B is blocked
B< ERROR [40001] Lock wait timeout exceeded; try restarting transaction
B> insert into t values (5, 29)   -- (not waiting)
   ... B is blocked
B< ERROR [40001] Lock wait timeout exceeded; try restarting transaction
B> insert into t values (6, 31)
   INSERT 1
```

Decoding `data_locks`:

* `X` on `k_idx (20, 2)` is a **next-key lock**: the record *plus the gap before it*, i.e. `(10, 20]`. That blocks `k = 17`.
* `X` on `k_idx (30, 3)`: InnoDB scanned one record **past** the range to know where the range ends, and locked it with its gap `(20, 30]`. That blocks `k = 29`, outside the query's range.
* `X,REC_NOT_GAP` on `PRIMARY`: plain record locks on the clustered-index rows.
* `k = 31` is beyond the last locked gap, so it's allowed.

This is how InnoDB's REPEATABLE READ prevents phantoms **for locking reads**. The cost is locking far more than the rows you read, especially when the index is missing or unselective: then the scan locks every record and gap it touches, effectively the table.

### 7.2 Verified: READ COMMITTED disables gap locking

```text
A> set session transaction isolation level read committed
A> start transaction
A> select id, k from t where k between 15 and 25 for update
   2 | 20
M> select … from performance_schema.data_locks …
   null       | TABLE     | IX            | GRANTED     | null
   k_idx      | RECORD    | X,REC_NOT_GAP | GRANTED     | 20, 2
   PRIMARY    | RECORD    | X,REC_NOT_GAP | GRANTED     | 2
B> insert into t values (7, 17)
   INSERT 1
```

Many high-throughput MySQL shops run **READ COMMITTED** precisely to avoid gap-lock contention and deadlocks (with row-based binlog replication, which RC requires).

### 7.3 Verified: InnoDB REPEATABLE READ allows the lost update

```text
A> start transaction
A> select balance from acct where id = 1
   100
B> update acct set balance = 120 where id = 1
# A's plain SELECT still reads its snapshot ...
A> select balance from acct where id = 1
   100
# ... but a locking read / UPDATE reads the LATEST committed version ("current read")
A> select balance from acct where id = 1 for update
   120
# lost update: A computed 100 + 10 in the app and writes it back. InnoDB RR does NOT raise an error
A> update acct set balance = 110 where id = 1
   UPDATE 1
A> commit
A> select balance from acct where id = 1
   110
```

**This is the single most important PostgreSQL-vs-MySQL difference in interviews.** Both call it REPEATABLE READ. PostgreSQL's aborts the second writer (40001, §1.4). InnoDB's mixes **snapshot reads** (plain `SELECT`) and **current reads** (`FOR UPDATE`, `UPDATE`, `DELETE`): writes always apply to the latest version, silently. Code ported from PostgreSQL that relies on RR to catch lost updates is **unsafe** on MySQL. Use atomic updates, `FOR UPDATE` before deciding, or `@Version`.

### 7.4 Verified: the check-then-insert deadlock

```text
A> create table users (id int primary key, email varchar(100) not null, unique key email_uq (email)) engine = InnoDB
A> insert into users values (1, 'a@x.io'), (10, 'z@x.io')
A> start transaction
B> start transaction
A> select * from users where email = 'm@x.io' for update
   (0 rows)
B> select * from users where email = 'n@x.io' for update
   (0 rows)
# both saw "no such user" and both hold a gap lock on the same gap
A> insert into users values (5, 'm@x.io')   -- (not waiting)
   ... A is blocked
B> insert into users values (6, 'n@x.io')
   ERROR [40001] Deadlock found when trying to get lock; try restarting transaction
A< INSERT 1
```

Gap locks are **compatible with each other** (both transactions can hold a gap lock on `('a@x.io', 'z@x.io')`), but an **insert intention** lock conflicts with another transaction's gap lock. Each insert waits for the other's gap lock, and that's a deadlock. The "lock it first, then insert if absent" pattern, which looks safe, is a deadlock generator in InnoDB. Fix: just `INSERT` and handle the duplicate-key error (or `INSERT … ON DUPLICATE KEY UPDATE`), and let the unique index arbitrate.

---

## 8. ❌ Naïve vs ✅ production-hardened concurrency

| ❌ Naïve | ✅ Hardened |
|---|---|
| Read balance in Java, write `balance = ?` | `UPDATE … SET balance = balance + ?` or `@Version` |
| "We use REPEATABLE READ, so lost updates can't happen" (MySQL) | Verified false on InnoDB. Use atomic updates or locking reads |
| Invariants across rows checked in Java under READ COMMITTED | SERIALIZABLE + retry, a materialized lock, or a constraint |
| SERIALIZABLE without retry logic | A retry wrapper covering the whole transaction, including `commit()` |
| `SELECT … FOR UPDATE` on the parent to "protect" children | `FOR NO KEY UPDATE` if no key changes |
| `SELECT … FOR UPDATE` + insert-if-absent (MySQL) | Insert and catch duplicate key, or upsert |
| Polling queue with plain `FOR UPDATE` | `FOR UPDATE SKIP LOCKED` + partial index + leases |
| Flyway migration with default settings | `lock_timeout` + retry, `CONCURRENTLY`, expand/contract |
| Deadlocks treated as bugs to never see | Canonical lock order + 40P01 retry + alert on the rate |

---

## 9. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/storage/lmgr/README-SSI` | The design of Serializable Snapshot Isolation (dangerous structures, SIREAD locks) |
| postgres/postgres | `src/backend/storage/lmgr/predicate.c` | SSI implementation |
| postgres/postgres | `src/backend/storage/lmgr/deadlock.c` | Deadlock detection after `deadlock_timeout` |
| postgres/postgres | `src/backend/access/heap/heapam.c` | `heap_lock_tuple` and the four row-lock modes |
| postgres/postgres | `src/backend/executor/nodeLockRows.c` | `SKIP LOCKED` / `NOWAIT` handling |
| [mysql/mysql-server](https://github.com/mysql/mysql-server) | `storage/innobase/lock/lock0lock.cc` | Record, gap and next-key locks; insert intention |

---

## 10. Interview soundbites

* "Locks serialize writes but don't protect a decision made from an earlier read. That's the lost update; I fix it with an atomic update, a locking read, or `@Version`."
* "PostgreSQL REPEATABLE READ aborts the second writer with 40001. MySQL's REPEATABLE READ lets it overwrite. I reproduced both."
* "Write skew needs SERIALIZABLE or a materialized conflict. SSI fails at commit, so the retry wraps the whole transaction including commit."
* "`SKIP LOCKED` gives each worker a disjoint batch without waiting; with leases and a partial index it's a production queue."
* "A migration waiting for `ACCESS EXCLUSIVE` blocks every reader queued behind it. I run DDL with a 2-second `lock_timeout` and retry."
* "InnoDB locks gaps for range locking reads. Two `FOR UPDATE` lookups of absent keys plus two inserts deadlock; just insert and handle the duplicate."
* "SSI false positives depend on lock granularity: a seq scan takes a relation-level SIRead lock, neighbours on one index page collide, and more than 32 page locks get promoted. With a matching index and clustered data, two disjoint SERIALIZABLE transactions both committed."

---

## Summary

| Problem | Mechanism | Fix | Verified evidence |
|---|---|---|---|
| Lost update | Read-modify-write in the app | Atomic update, `FOR UPDATE`, REPEATABLE READ (40001), `@Version` | Four fixes reproduced (§1) |
| Write skew | Disjoint writes from overlapping reads | SERIALIZABLE (SSI) or a materialized lock | Invariant broken under RR, caught under SERIALIZABLE |
| SSI false positives | SIRead locks at tuple / page / relation granularity, promotion past 32 pages | Matching indexes, clustered data, retries | Seq scan and shared pages aborted; clustered layout committed both |
| Row-lock modes | `FOR UPDATE` ⟂ FK `FOR KEY SHARE`; `FOR NO KEY UPDATE` isn't | Use `FOR NO KEY UPDATE` for non-key updates | Child insert blocked vs allowed |
| Work queue | `FOR UPDATE SKIP LOCKED` | Leases, partial index, batching | Disjoint batches, no waiting |
| Deadlock | Opposite lock order | Consistent ordering, short transactions, retries | `40P01` reproduced |
| DDL lock queue | `ACCESS EXCLUSIVE` waits FIFO and blocks everyone behind it | `lock_timeout` + retry, expand/contract | A plain `SELECT` blocked behind a queued `ALTER` |
| InnoDB gap locks | Next-key locks on range locking reads | READ COMMITTED, insert-and-catch-duplicate | Gap-lock deadlock reproduced on MySQL 8.4 |
| InnoDB RR lost update | Plain reads are snapshots; writes see latest | Locking reads or atomic updates | Second writer overwrote silently |

**Next:** [2.7 Scaling: replicas, partitioning, pooling, sharding →](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)
