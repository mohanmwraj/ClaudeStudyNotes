# 2.1 Storage Internals: 8 KB Pages, Tuple Headers, HOT, TOAST, and the Write-Ahead Log

> **Verified stack:** PostgreSQL **18.6** (EDB Windows x64 build, `io_method=worker`), extensions `pageinspect`, `pgstattuple`, `pg_walinspect`, `pg_visibility`. Every block labelled *Output (verified)* is real `psql` output. Timings are "one measured run" on a laptop.
>
> **Go deeper:** [2.5 MVCC & vacuum](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md) explains what `xmin`/`xmax` *mean*; this file shows where they *live*.

---

## 0. First principles: what a database does with your row 🔥

A relational engine must reconcile three facts of physics:

1. **Disks and SSDs read and write in blocks** (4 KB+), not rows. So the engine stores rows in fixed-size **pages** (PostgreSQL: 8 KB; InnoDB: 16 KB) and caches pages, not rows, in memory (`shared_buffers` / the buffer pool).
2. **Random writes are slow and not atomic.** A crash in the middle of writing an 8 KB page can leave half old, half new bytes (a *torn page*). So the engine first appends a description of each change to a **sequential log** (the WAL), forces *that* to disk at commit, and writes data pages lazily later.
3. **Readers and writers must not block each other** (MVCC). So an `UPDATE` in PostgreSQL doesn't overwrite the row. It writes a **new version** and marks the old one as superseded.

Everything in this file is a consequence of those three facts.

---

## 1. The heap page, byte by byte ⚡

```text
 0                      24          24+4·n
 ┌──────────────────────┬────────────┬───────────────────────────────┬───────────────────────────┐
 │ PageHeaderData (24 B)│ line ptrs →│        free space             │ ← tuples (grow downward)   │
 │ pd_lsn pd_checksum   │ lp1 lp2 lp3│                               │ tuple3  tuple2  tuple1     │
 │ pd_lower pd_upper …  │            │                               │                           │
 └──────────────────────┴────────────┴───────────────────────────────┴───────────────────────────┘
                                     ↑ pd_lower                      ↑ pd_upper              8192 = pd_special
```

* **Line pointers** (`ItemIdData`, 4 bytes each) grow from the front. Each holds the tuple's offset, length and a 2-bit state: `1` normal, `2` redirect, `3` dead.
* **Tuples** grow from the back. The page is full when `pd_lower` meets `pd_upper`.
* A row's physical address is its **`ctid` = (block number, line pointer number)**. Indexes store `ctid`s. Because indexes point at *line pointers*, the tuple can move inside the page (compaction) without touching any index.

### 1.1 Verified: three rows on a fresh page

```sql
create table account (id int primary key, owner text, balance numeric(12,2));
insert into account values (1,'ada',100),(2,'bob',200),(3,'cy',300);
select lower, upper, special, pagesize from page_header(get_raw_page('account', 0));
select lp, lp_off, lp_len, t_xmin, t_xmax, t_ctid, t_hoff from heap_page_items(get_raw_page('account', 0));
```

**Output (verified):**

```text
 lower | upper | special | pagesize
-------+-------+---------+----------
    36 |  8072 |    8192 |     8192

 lp | lp_off | lp_len | t_xmin | t_xmax | t_ctid | t_hoff
----+--------+--------+--------+--------+--------+--------
  1 |   8152 |     37 |    766 |      0 | (0,1)  |     24
  2 |   8112 |     37 |    766 |      0 | (0,2)  |     24
  3 |   8072 |     36 |    766 |      0 | (0,3)  |     24
```

Read it like an engine:

* `lower = 36` = 24-byte page header + 3 line pointers × 4 bytes.
* `upper = 8072`: the third tuple starts 120 bytes before the end of the page. Each 36–37-byte tuple occupies a 40-byte slot after 8-byte alignment.
* `t_hoff = 24`: the **tuple header** is 23 bytes (`t_xmin` 4, `t_xmax` 4, `t_cid` 4, `t_ctid` 6, `t_infomask2` 2, `t_infomask` 2, `t_hoff` 1), padded to 24. **Every row pays ~24 bytes of header + 4 bytes of line pointer before its first column.** For narrow rows (a join table of two `bigint`s), the overhead is larger than the data.
* `t_xmin = 766`: the transaction that created the version. `t_xmax = 0`: nobody has deleted or updated it yet.

### 1.2 Verified: an UPDATE writes a new version (a HOT chain)

```sql
select txid_current() as my_xid;          -- note: this call itself assigns (burns) XID 767
update account set balance = balance + 1 where id = 1;
select lp, lp_flags, t_xmin, t_xmax, t_ctid,
       (t_infomask2 & x'4000'::int) <> 0 as hot_updated,
       (t_infomask2 & x'8000'::int) <> 0 as heap_only
from heap_page_items(get_raw_page('account', 0));
select ctid, xmin, xmax, * from account order by id;
```

**Output (verified):**

```text
 lp | lp_flags | t_xmin | t_xmax | t_ctid | hot_updated | heap_only
----+----------+--------+--------+--------+-------------+-----------
  1 |        1 |    766 |    768 | (0,4)  | t           | f
  2 |        1 |    766 |      0 | (0,2)  | f           | f
  3 |        1 |    766 |      0 | (0,3)  | f           | f
  4 |        1 |    768 |      0 | (0,4)  | f           | t

 ctid  | xmin | xmax | id | owner | balance
-------+------+------+----+-------+---------
 (0,4) |  768 |    0 |  1 | ada   |  101.00
 (0,2) |  766 |    0 |  2 | bob   |  200.00
 (0,3) |  766 |    0 |  3 | cy    |  300.00
```

What happened:

1. Transaction 768 wrote a **new tuple** at `lp 4` with `t_xmin = 768`.
2. It stamped the **old** tuple (`lp 1`) with `t_xmax = 768` and pointed its `t_ctid` at `(0,4)`, the next version in the chain.
3. Because no *indexed* column changed and the new version fit on the **same page**, this was a **HOT update** (heap-only tuple). `lp 1` is flagged `HOT_UPDATED`, `lp 4` is `HEAP_ONLY`, and **the primary-key index was not touched**. The index entry still points to `(0,1)`, and readers follow the chain to `(0,4)`.

The old version stays on the page until **pruning** (opportunistic, during a later read or write of the page) or **VACUUM** removes it, once no running transaction can still see it ([2.5](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)). After pruning, `lp 1` becomes a *redirect* line pointer to `lp 4`, so the index entry stays valid.

### 1.3 Verified: HOT needs free space on the page (`fillfactor`)

Two identical tables, 100,000 rows each, then update a **non-indexed** column on 10% of the rows:

```sql
create table ff100 (id int primary key, counter int, note text) with (fillfactor = 100, autovacuum_enabled = false);
create table ff90  (id int primary key, counter int, note text) with (fillfactor = 90,  autovacuum_enabled = false);
-- 100,000 rows each, then:
update ff100 set counter = counter + 1 where id % 10 = 0;   -- non-indexed column: eligible for HOT
update ff90  set counter = counter + 1 where id % 10 = 0;
```

**Output (verified):**

```text
 relname | n_tup_upd | n_tup_hot_upd | hot_pct |  heap   |  pkey
---------+-----------+---------------+---------+---------+---------
 ff100   |     10000 |             0 |     0.0 | 8232 kB | 2208 kB
 ff90    |     10000 |         10000 |   100.0 | 8336 kB | 2208 kB
```

With `fillfactor = 100` the pages were packed full, so **every** update had to put the new version on another page. That's a non-HOT update, which also inserts a new entry into **every index** on the table. With 10% headroom, **100%** of the updates were HOT.

And updating an indexed column is never HOT:

```text
update ff90 set id = id + 1000000 where id = 5;
 relname | n_tup_upd | n_tup_hot_upd
---------+-----------+---------------
 ff90    |     10001 |         10000
```

**Staff-level takeaway:** on update-heavy tables (sessions, counters, job status), *every extra index* turns potential HOT updates into index writes, WAL and bloat. Lower `fillfactor` (80–90) on such tables and audit indexes on frequently updated columns. Monitor `n_tup_hot_upd / n_tup_upd` in `pg_stat_user_tables`.

### 1.4 Verified: a `SELECT` prunes the page, and redirect line pointers keep indexes valid 🧊

The old versions of a HOT chain don't wait for VACUUM. Any backend that pins a page whose free space is low (below `max(fillfactor target, 10 %)`) runs **opportunistic pruning** (`heap_page_prune_opt`), even a plain `SELECT`.

```sql
create table prunedemo (id int primary key, counter int, pad text) with (autovacuum_enabled = false);
insert into prunedemo select g, 0, repeat('x', 200) from generate_series(1, 30) g;     -- ~7 KB: one nearly full page
update prunedemo set counter = counter + 1 where id = 1;   -- ×3: three HOT versions of row 1
select lp, lp_flags, lp_off, t_ctid, (t_infomask2 & x'4000'::int) <> 0 as hot_updated, (t_infomask2 & x'8000'::int) <> 0 as heap_only
from heap_page_items(get_raw_page('prunedemo', 0)) where lp = 1 or lp > 30 order by lp;
select upper - lower as free_bytes from page_header(get_raw_page('prunedemo', 0));
select count(*) from prunedemo where id = 1;                -- a read
-- same two inspection queries again
```

**Output (verified, PostgreSQL 18.6):**

```text
-- after the three updates
 lp | lp_flags | lp_off | t_ctid | hot_updated | heap_only
----+----------+--------+--------+-------------+-----------
  1 |        2 |     32 |        |             |
 31 |        1 |    752 | (0,31) | f           | t
 32 |        1 |    992 | (0,31) | t           | t
 free_bytes = 600

-- after one SELECT
 lp | lp_flags | lp_off | lp_len | t_ctid
----+----------+--------+--------+--------
  1 |        2 |     31 |      0 |
 31 |        1 |    992 |    236 | (0,31)
 free_bytes = 844
```

Reading it:

* `lp 1` has `lp_flags = 2` (**redirect**) and no tuple (`lp_len = 0`): its `lp_off` field now holds the line-pointer number to follow. The primary-key index still points at `(0,1)`; following the redirect leads to the live version. Pruning already happened **during** the third update (the page was nearly full), which is why `lp 31` was reused for a newer version.
* The `SELECT` pruned again: the dead version at `lp 32` was removed, the redirect now points to `31`, and the trailing unused line pointer was **truncated** (it no longer appears). Free space went from 600 to **844 bytes** without any VACUUM.
* What pruning can't do: remove line pointers that indexes reference (only VACUUM, which also cleans the index entries, can), set visibility-map bits, or freeze. That's why HOT reduces vacuum work but doesn't remove the need for it.
* Interview point: "a `SELECT` can write" is true twice over in PostgreSQL: hint bits ([2.5 §1.3](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)) and pruning. On a replica, neither happens locally; the primary's pruning arrives through WAL.

---

## 2. Column order and alignment padding 🧊

Each fixed-width type has an alignment (`bigint`/`timestamptz` 8 bytes, `int` 4, `smallint` 2, `boolean` 1), and the engine inserts padding so each column starts on its boundary.

```sql
create table t_bad  (a boolean, b bigint, c boolean, d bigint, e boolean, f bigint);
create table t_good (b bigint, d bigint, f bigint, a boolean, c boolean, e boolean);
-- 1,000,000 rows each
```

**Output (verified):**

```text
 row_bytes_bad
---------------
            72
 row_bytes_good
----------------
             51
  bad  | good
-------+-------
 73 MB | 57 MB
```

Same data, **22% smaller table** just from ordering columns largest-alignment-first. Smaller tables mean more rows per page, so fewer pages to read, cache and vacuum. Cheap to apply in new schemas; rarely worth a rewrite of an existing big table.

---

## 3. TOAST: what happens to big values ⚡

A tuple must fit in a page, and PostgreSQL tries to keep at least four tuples per page. When a row exceeds roughly **2 KB** (`TOAST_TUPLE_THRESHOLD`), the engine:

1. **compresses** large variable-length values (`pglz` by default, or `lz4`), and if that's not enough,
2. **moves them out of line** into the table's TOAST relation (`pg_toast.pg_toast_<oid>`), in ~2 KB chunks, leaving an 18-byte pointer in the main tuple.

**Output (verified)** with 1,000 rows of 12.8 kB repetitive text and 1,000 rows of 12.8 kB random hex:

```text
 default_toast_compression
---------------------------
 pglz

 relname |  toast_table   |  heap  | toast
---------+----------------+--------+-------
 doc     | pg_toast_17262 | 280 kB | 13 MB

    kind    | logical_bytes | stored_bytes | compression
------------+---------------+--------------+-------------
 random     |         12800 |        12800 |
 repetitive |         12800 |          191 | pglz
```

* Repetitive text compressed from 12,800 to **191 bytes** and stayed **inline**.
* Random data didn't compress (pglz gives up when savings are small), so it went **out of line**, uncompressed, into the 13 MB TOAST table.

Consequences you should be able to explain:

| Behavior | Why it matters |
|---|---|
| `SELECT *` on a table with large JSON/text detoasts every value (extra I/O, decompression) | Select only the columns you need; ORMs that load whole entities pay this |
| Updating a non-TOASTed column doesn't rewrite the TOASTed value (the pointer is copied) | Big documents are cheap to *carry*, expensive to *change* |
| Updating a field **inside** a big `jsonb` rewrites the whole value | Hot, frequently updated fields don't belong inside a 50 KB document |
| `lz4` (where the build supports it) compresses and decompresses much faster than `pglz` | `ALTER TABLE … ALTER COLUMN … SET COMPRESSION lz4` affects new values only |

### 3.1 Verified: `lz4` vs `pglz` is a speed/ratio trade, not a free win ⚡

5,000 `jsonb` order documents (200 line items each, ~15 kB as text), loaded once with each algorithm:

```sql
create table doc_pglz (id int, body jsonb compression pglz);
create table doc_lz4  (id int, body jsonb compression lz4);
-- same INSERT … SELECT into each, then:
select pg_column_compression(body) as stored_as, avg(pg_column_size(body))::int as avg_stored_bytes,
       pg_size_pretty(pg_total_relation_size('doc_pglz')) as total from doc_pglz group by 1;   -- and the same for doc_lz4
```

**Output (verified, PostgreSQL 18.6; insert times are one measured run):**

```text
 algo | stored_as | avg_stored_bytes |  total
------+-----------+------------------+---------
 pglz | pglz      |             1081 | 5760 kB
 lz4  | lz4       |             1418 | 7464 kB

 INSERT 5,000 rows:  pglz 2098 ms   lz4 1776 ms
 SELECT sum(length(body::text)) (full detoast + decompress):  pglz 297 ms   lz4 294 ms
```

* On this repetitive JSON, **pglz compressed better** (1,081 vs 1,418 bytes per value, 23 % smaller table) and **lz4 wrote 15 % faster**. Reading was the same because converting 75 MB of `jsonb` to text dominated, not decompression.
* `pg_column_compression()` tells you what each stored value actually uses; changing the column's setting doesn't recompress existing values (`VACUUM FULL` or a rewrite does).
* Choose with data: lz4 for write-heavy, CPU-bound ingestion; pglz (or application-side compression) when storage and cache footprint matter more. Measure with your own documents.

---

## 4. The write-ahead log (WAL) 🔥

### 4.1 The rules

1. **Write-ahead rule:** a data page may be written to disk only after all WAL records describing its changes are on disk. Each page stores the LSN of its last change (`pd_lsn`) so the buffer manager can enforce this.
2. **Commit = WAL flush.** `COMMIT` returns after the commit record is `fsync`ed (with `synchronous_commit = on`). Data pages are written later by the background writer and checkpointer. A commit costs one *sequential* flush instead of many random page writes.
3. **Crash recovery = replay.** On restart, the engine replays WAL from the last checkpoint's **REDO** point, reapplying every change whose page LSN is older than the record.
4. **The LSN** (log sequence number) is simply a byte position in the WAL stream (`0/E331288`). Replication, point-in-time recovery and logical decoding (CDC with Debezium) all read this same stream.

```mermaid
sequenceDiagram
    participant C as Client
    participant B as Backend
    participant SB as shared_buffers
    participant W as WAL buffers / files
    participant D as Data files
    C->>B: UPDATE … ; COMMIT
    B->>SB: modify page in memory (dirty), set pd_lsn
    B->>W: append WAL record(s)
    B->>W: append COMMIT record, fsync WAL
    B-->>C: COMMIT returns
    Note over SB,D: later: checkpointer / bgwriter write dirty pages<br/>(only after WAL up to pd_lsn is durable)
```

### 4.2 Full-page images: the torn-page tax (verified)

A crash can tear an 8 KB page write (the OS and disk guarantee atomicity for 4 KB or 512 B at best). Replaying a small "change bytes 100–108" record onto a torn page would corrupt it. So, with `full_page_writes = on` (the default), **the first modification of each page after a checkpoint logs the entire page** (a full-page image, FPI). Recovery restores the image first, then replays the rest.

On a **nearly empty** page (the 3-row `account` table):

```sql
checkpoint;
update account set balance = balance + 1 where id = 2;      -- first change to this page since the checkpoint
update account set balance = balance + 1 where id = 3;      -- same page, second change
```

**Output (verified):**

```text
 wal_bytes_first_update | wal_bytes_second_update
------------------------+-------------------------
                    352 |                     112

 start_lsn | resource_manager | record_type | record_length | fpi_length
-----------+------------------+-------------+---------------+------------
 0/E331288 | Heap             | HOT_UPDATE  |           309 |        244
 0/E3313C0 | Transaction      | COMMIT      |            34 |          0
 0/E3313E8 | Heap             | HOT_UPDATE  |            70 |          0
 0/E331430 | Transaction      | COMMIT      |            34 |          0
```

The FPI was only 244 bytes because PostgreSQL omits the empty "hole" between `pd_lower` and `pd_upper`. On a **full** page (`events` table):

**Output (verified):**

```text
 record_type | record_length | fpi_length
-------------+---------------+------------
 LOCK        |            54 |          0
 UPDATE      |          7153 |       7080
 HOT_UPDATE  |           106 |          0
```

One logical update of a few bytes cost **7.1 kB of WAL**, because it was the first touch of that page since the checkpoint (and a non-HOT update: the page was full). The next update to the same page cost 106 bytes.

### 4.3 Verified: WAL amplification of a bulk load

```sql
create table events (id bigint generated always as identity primary key, kind text, payload text, created_at timestamptz default now());
insert into events (kind, payload) select 'k' || (g % 10), md5(g::text) from generate_series(1, 200000) g;
```

**Output (verified):**

```text
 wal_generated | heap_size | index_size
---------------+-----------+------------
 35 MB         | 16 MB     | 4408 kB
```

About **1.7 bytes of WAL per byte of table + index**. That WAL is also what your replicas and CDC pipeline must ship and apply.

### 4.4 Tuning knobs and their trade-offs

| Knob | Lower value | Higher value |
|---|---|---|
| `checkpoint_timeout` / `max_wal_size` | Faster crash recovery, **more FPIs** (more WAL, more I/O) | Fewer FPIs, smoother I/O, longer recovery |
| `wal_compression` (`lz4`/`zstd`) | — | Smaller FPIs for some CPU |
| `synchronous_commit` | `off`: commits return before the WAL flush (a crash may lose the last ~3×`wal_writer_delay` of commits, but **no corruption**) | `remote_apply`: wait for a replica to apply ([2.7](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md) measured 1.5 s with a delayed replica) |
| `commit_delay` / `commit_siblings` | — | Group commit: several transactions share one flush |
| `fillfactor` | — | More HOT updates, fewer index writes ([§1.3](#13-verified-hot-needs-free-space-on-the-page-fillfactor)) |

`synchronous_commit = off` per transaction is a legitimate tool for **losable** writes (click tracking, metrics), and it keeps durability for the rest.

### 4.5 PostgreSQL 18 storage changes worth knowing

| Change | Effect |
|---|---|
| **Asynchronous I/O** (`io_method` = `worker` (default), `io_uring` on Linux, or `sync`) | Read-ahead for sequential scans, bitmap heap scans and vacuum is issued asynchronously. This build reports `io_method = worker` |
| **Data checksums on by default** in `initdb` | Silent corruption is detected on read (`--no-data-checksums` to opt out) |
| `uuidv7()` built in | Time-ordered UUIDs that keep B-tree inserts at the right edge ([2.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)) |
| B-tree **skip scan**, `Index Searches` in `EXPLAIN` | Multi-column indexes usable without the leading column ([2.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)) |
| `EXPLAIN ANALYZE` shows **buffers by default** | Verified in [2.3](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md) |

### 4.6 Verified: a big sequential scan doesn't flush `shared_buffers` (ring buffers) 🧊

If every report that seq-scans a big table evicted the OLTP working set, caches would be useless. PostgreSQL protects the cache with **buffer access strategies**: a seq scan of a table larger than ¼ of `shared_buffers` reads through a small, private **ring** of buffers (`BAS_BULKREAD`) and recycles it, instead of claiming free buffers from the shared pool. `COPY`, `CREATE TABLE AS` (`BAS_BULKWRITE`) and VACUUM (`BAS_VACUUM`) use their own rings.

```sql
-- order_lines is 195 MB; shared_buffers is 128 MB
select count(*) as cached_before from pg_buffercache b join pg_class c on b.relfilenode = pg_relation_filenode(c.oid) where c.relname = 'order_lines';
select count(*) from order_lines;                      -- full seq scan, 25,000 pages
select count(*) as cached_after  from pg_buffercache b join pg_class c on b.relfilenode = pg_relation_filenode(c.oid) where c.relname = 'order_lines';
select backend_type, object, context, reads, hits, evictions, reuses from pg_stat_io
where backend_type = 'client backend' and object = 'relation' and context in ('normal', 'bulkread');
```

**Output (verified, PostgreSQL 18.6, `atlas` database from [2.9](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md)):**

```text
 cached_before = 1        cached_after = 397          (of 25,000 pages read)

  backend_type  |  object  | context  | reads  |   hits    | evictions | reuses
----------------+----------+----------+--------+-----------+-----------+--------
 client backend | relation | bulkread |  67925 |    421751 |     51655 | 450242
 client backend | relation | normal   | 195637 | 154714762 |    491439 |
```

* After reading **25,000 pages**, only **397** remained in `shared_buffers` (3 MB). The rest of the cache, holding whatever the OLTP workload uses, survived.
* `pg_stat_io` (PG 16+) splits I/O by **context**: `bulkread` rows with a large `reuses` count are ring-buffer recycling; `evictions` in the `normal` context are what really pushes pages out. (These are cumulative counters for the whole lab session.)
* Two consequences that confuse people reading plans: (1) repeating the same big seq scan shows `shared read=…` **every time**, because it never warms the shared cache (the OS page cache does help, as the tiny `I/O Timings` in [2.9 §1](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#1-seq-scan-and-the-cost-formula-reproduced-) show); (2) `pg_prewarm` is the way to deliberately load a big table into `shared_buffers`, for example after a failover.

---

## 5. PostgreSQL heap vs InnoDB clustered index 🔥

| | PostgreSQL | MySQL InnoDB |
|---|---|---|
| Page size | 8 KB | 16 KB |
| Table storage | **Heap**: rows in insertion/free-space order. Every index (including the PK) is secondary and points to a `ctid` | **Clustered index**: rows live **inside the primary-key B+tree leaves**, ordered by PK |
| Secondary index entry | Key → `ctid` (physical) | Key → **primary key value** (logical), so a secondary lookup is two B-tree descents |
| UPDATE | New tuple version in the heap (HOT if possible). Old version stays until vacuum | **In place** in the clustered index. The old version goes to the **undo log** |
| Old versions for MVCC | In the table itself (bloat, cleaned by VACUUM) | In undo segments (purged by the purge thread) |
| Torn-page protection | Full-page images in WAL | **Doublewrite buffer** (pages written twice) |
| Redo | WAL | Redo log |
| PK choice consequence | A random PK hurts only the PK index | A random PK (UUIDv4) **fragments the table itself**, because rows are ordered by PK |
| Wide PK consequence | Only the PK index grows | **Every** secondary index stores the PK, so they all grow |

Two interview-grade consequences:

* "Use an auto-increment or time-ordered PK in MySQL" isn't style advice. In InnoDB the PK *is* the table's physical order.
* PostgreSQL's update cost depends on HOT. InnoDB's depends on undo and purge. Each engine's "long-running transaction" problem shows up in a different place ([2.5](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)).

---

## 6. ❌ Naïve vs ✅ production-hardened storage design

| ❌ Naïve | ✅ Hardened |
|---|---|
| Default `fillfactor` on a table whose status column changes every minute | `fillfactor = 80–90` + no index on the churning column; watch the HOT ratio |
| Columns in "logical" order: `bool, bigint, bool, timestamptz` | Largest alignment first on big new tables (−22% in our test) |
| 50 KB `jsonb` document with a frequently updated counter inside | Hot fields as real columns; documents for cold, read-mostly data |
| `SELECT *` from tables with TOASTed columns | Project only needed columns or use DTO projections ([3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)) |
| Very short `checkpoint_timeout` "for safety" | 5–15 min with `max_wal_size` sized to avoid forced checkpoints. Watch `checkpoints_req` in `pg_stat_checkpointer` |
| `synchronous_commit = off` globally | Per transaction, only for losable writes |

---

## 7. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/include/storage/bufpage.h` | `PageHeaderData`, `pd_lower`/`pd_upper`, the page layout comment at the top |
| postgres/postgres | `src/include/access/htup_details.h` | `HeapTupleHeaderData`, the infomask bits (`HEAP_HOT_UPDATED`, `HEAP_ONLY_TUPLE`, `HEAP_XMIN_FROZEN`) |
| postgres/postgres | `src/backend/access/heap/heapam.c` | `heap_update()`: the HOT decision (`HeapSatisfiesHOTandKeyUpdate`, "same page?") |
| postgres/postgres | `src/backend/access/heap/pruneheap.c` | Opportunistic pruning and redirect line pointers |
| postgres/postgres | `src/backend/access/common/toast_internals.c`, `src/backend/access/heap/heaptoast.c` | TOAST thresholds, compression, chunking |
| postgres/postgres | `src/backend/access/transam/xloginsert.c` | `XLogInsert`, when an FPI is taken (`XLogRecordAssemble`) |
| postgres/postgres | `src/backend/access/heap/README.HOT` | The best plain-English explanation of HOT |

---

## 8. Interview soundbites

* "PostgreSQL never updates a row in place. It writes a new version and stamps the old one's `xmax`. If no indexed column changed and there's room on the page, it's a HOT update and the indexes aren't touched."
* "Commit means the WAL is on disk, not the table. Pages are written later, and recovery replays the WAL from the last checkpoint."
* "The first change to a page after a checkpoint logs the whole page to guard against torn writes. I measured a 3-byte update costing 7 kB of WAL. Checkpoint spacing is a WAL-volume decision."
* "In InnoDB the primary key is the physical order of the table and every secondary index carries it, so a random UUIDv4 PK hurts InnoDB far more than PostgreSQL."
* "Even a `SELECT` writes: it can prune a page's dead HOT versions into a redirect line pointer. I watched free space go from 600 to 844 bytes after one read."
* "A seq scan bigger than a quarter of `shared_buffers` uses a ring buffer: after scanning 25,000 pages only 397 stayed cached, so reports don't wipe the OLTP cache."

---

## Summary

| Concept | The mechanism in one line | Verified evidence |
|---|---|---|
| Page layout | 24 B header, 4 B line pointers growing forward, tuples growing back; `ctid` = (block, line pointer) | `lower=36`, `upper=8072` for 3 rows |
| Tuple overhead | 23 B header (padded to 24) + 4 B line pointer per row | `t_hoff = 24` |
| MVCC update | New version + old version's `xmax`/`t_ctid` link | HOT chain `(0,1)` → `(0,4)` |
| HOT | Same page + no indexed column changed → no index writes | fillfactor 90: 100 % HOT; fillfactor 100: 0 % |
| Pruning | Any backend (even `SELECT`) removes dead HOT versions; redirect keeps index entries valid | free space 600 → 844 B after one read |
| Alignment | Order columns by alignment (8 → 4 → 2 → 1) | 72 → 51 B per row, −22 % table size |
| TOAST | > ~2 KB: compress, then move out of line in chunks | 12,800 B → 191 B inline (pglz); random data out of line |
| lz4 vs pglz | lz4 faster to write, not necessarily smaller | pglz 1,081 B vs lz4 1,418 B avg; lz4 inserts 15 % faster |
| WAL | Commit = WAL flush; pages written later; recovery replays | — |
| Full-page images | First change of a page after a checkpoint logs the page | 3-byte change → 7.1 kB WAL |
| Ring buffers | Big seq scans/COPY/VACUUM recycle a small private ring | 25,000 pages scanned, 397 cached |
| PG vs InnoDB | Heap + secondary-only indexes vs clustered PK + undo | PK choice matters more in InnoDB |

**Next:** [2.2 Indexes →](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)
