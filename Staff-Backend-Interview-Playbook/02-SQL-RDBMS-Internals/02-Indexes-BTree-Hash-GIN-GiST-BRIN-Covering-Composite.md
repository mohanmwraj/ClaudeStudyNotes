# 2.2 Indexes: B+Tree Internals, Key Choice (UUIDv4 vs v7), Composite Ordering, Skip Scan, Covering, Partial, GIN, GiST, BRIN

> **Verified stack:** PostgreSQL **18.6**. The lab table `orders` has **1,000,000 rows** (157 MB heap): `customer_id` (≈100k distinct), `status` (90% `DELIVERED`, 5% `SHIPPED`, 4% `PENDING`, 1% `CANCELLED`), `created_at` (one row every 30 s through 2026, perfectly correlated with `id`), `email` (mixed case), `attrs` (`jsonb`).
>
> `EXPLAIN` blocks are real. Timings are one measured run on a laptop; **buffer counts** are the stable signal (a buffer is one 8 KB page touched).

---

## 0. First principles: an index is a second copy of your data, sorted for one question 🔥

* A table (heap) is unordered. Finding `customer_id = 4242` means reading all 20,194 pages.
* An index keeps **(key → row address)** pairs **sorted by key**, in a tree whose nodes are pages. Finding one key costs one page read per tree level.
* Every index is paid for on **every write** (insert, non-HOT update, delete cleanup), in **WAL**, in **memory** (it competes for `shared_buffers`) and in **vacuum** time.

So the design question is never "is this column queried?" but "**which access paths are hot enough to deserve a second (third, fourth…) sorted copy?**"

---

## 1. The B+tree, concretely ⚡

### 1.1 Shape and fan-out

```text
                       [ root ]                        level 2
               /          |          \
       [internal]    [internal]  … (11 pages)          level 1
       /   |   \
   [leaf][leaf][leaf] … (2,733 pages)                  level 0 → each leaf entry: key + ctid
     ↔     ↔     ↔      (leaves are doubly linked: range scans walk sideways)
```

**Output (verified, `bigint` primary key, 1,000,000 rows):**

```text
select * from bt_metap('k_bigint_pkey');
 magic  | version | root | level | fastroot | fastlevel | last_cleanup_num_delpages | last_cleanup_num_tuples | allequalimage
--------+---------+------+-------+----------+-----------+---------------------------+-------------------------+---------------
 340322 |       4 |  412 |     2 |      412 |         2 |                         0 |                      -1 | t

select tree_level, internal_pages, leaf_pages from pgstatindex('k_bigint_pkey');
 tree_level | internal_pages | leaf_pages
------------+----------------+------------
          2 |             11 |       2733
```

The math interviewers want:

* **≈366 keys per leaf** (1,000,000 / 2,733) for an 8-byte key at 90% fill, and roughly 250 downlinks per internal page.
* Height grows with log<sub>fan-out</sub>(N): 3 levels hold up to ≈ 250 × 250 × 366 ≈ 23 M keys (our 1 M rows use 3), and 4 levels hold ≈ 5.7 B. **A point lookup on a billion-row table touches about 4 pages**, and the top levels are almost always cached.
* That's why "add an index" turns O(N) into O(log N) with a base so large that in practice it's "a handful of page reads".

PostgreSQL's B-tree is a **Lehman–Yao** tree: every page has a *high key* and a *right-link*, so a reader that lands on a page that just split can move right instead of restarting. Readers never block on splits.

### 1.2 Page splits, density and key choice (verified)

When a leaf is full, it **splits**: about half the entries move to a new page. What happens next depends on where new keys land:

* **Monotonic keys** (identity, sequence, timestamp, UUIDv7) always insert at the **right-most leaf**. PostgreSQL detects this and splits unevenly ("fastpath" / rightmost split), so leaves stay ~90% full and only one leaf is hot in cache.
* **Random keys** (UUIDv4, hashes) land on **every leaf**. Each split leaves two half-full pages, the whole index must be in memory to avoid random reads, and every insert dirties a different page (more full-page images in WAL).

```sql
create table k_bigint (id bigint primary key, v int);
create table k_uuidv4 (id uuid primary key, v int);
create table k_uuidv7 (id uuid primary key, v int);
insert into k_bigint select g, g from generate_series(1, 1000000) g;
insert into k_uuidv4 select gen_random_uuid(), g from generate_series(1, 1000000) g;
insert into k_uuidv7 select uuidv7(), g from generate_series(1, 1000000) g;    -- uuidv7() is built into PostgreSQL 18
```

**Output (verified):**

```text
 key_type |  wal
----------+--------
 bigint   | 132 MB
 uuid v4  | 162 MB
 uuid v7  | 149 MB

     index     | size  | leaf_pages | avg_leaf_density | leaf_fragmentation
---------------+-------+------------+------------------+--------------------
 k_bigint_pkey | 21 MB |       2733 |             90.0 |                  0
 k_uuidv4_pkey | 38 MB |       4848 |             71.2 |              49.86
 k_uuidv7_pkey | 30 MB |       3832 |             90.0 |                  0
```

One measured run of insert time: bigint **2.5 s**, UUIDv4 **6.2 s**, UUIDv7 **4.6 s**.

How to read it:

* UUIDv7 and bigint both produce **90%-dense, unfragmented** leaves. UUIDv7 is bigger only because a UUID is 16 bytes vs 8.
* UUIDv4 needs **27% more leaf pages** than UUIDv7 for the same keys, with half its leaves out of physical order.
* This test is the *kind* case: a 38 MB index fits in `shared_buffers`. When a random-key index is **larger than memory**, every insert can cause a random read, and throughput falls off a cliff. In InnoDB, where the PK *is* the table ([2.1 §5](01-Storage-Pages-Tuples-TOAST-WAL.md)), the whole table fragments.

```sql
select uuidv7() as sample_v7, uuid_extract_timestamp(uuidv7()) as embedded_ts, gen_random_uuid() as sample_v4;
```

```text
              sample_v7               |        embedded_ts        |              sample_v4
--------------------------------------+---------------------------+--------------------------------------
 01a17157-bbba-7e85-bb92-73e77c059335 | 2026-10-25 04:35:37.53+00 | b39de890-5971-4082-9eff-c64c50a0aad5
```

### 1.3 Verified: deduplication (PG 13+) makes low-cardinality B-trees small 🧊

Before PostgreSQL 13, a B-tree stored one full `(key, ctid)` tuple per row, so an index on a 4-value column was as big as a unique one. Since 13, leaves store **posting-list tuples**: one key followed by a sorted array of `ctid`s. It's on by default; `deduplicate_items = off` turns it off per index.

```sql
-- on the atlas dataset (2.9 §0.2): 1 M orders, 4 statuses, 200,000 customers (~5 orders each), unique ids
create index ix_status_dedup   on orders (status);
create index ix_status_nodedup on orders (status) with (deduplicate_items = off);
create index ix_cust_dedup     on orders (customer_id);
create index ix_cust_nodedup   on orders (customer_id) with (deduplicate_items = off);
create index ix_id_dedup       on orders (id);
select c.relname, pg_size_pretty(pg_relation_size(c.oid)), s.leaf_pages, s.avg_leaf_density
from pg_class c cross join lateral pgstatindex(c.oid::regclass) s where c.relname like 'ix_%' order by 1;
```

**Output (verified, PostgreSQL 18.6):**

```text
       index       |  size   | leaf_pages | avg_leaf_density
-------------------+---------+------------+------------------
 ix_cust_dedup     | 11 MB   |       1419 |            90.15
 ix_cust_nodedup   | 21 MB   |       2733 |            90.09
 ix_id_dedup       | 21 MB   |       2733 |            90.01
 ix_status_dedup   | 6896 kB |        854 |            90.03
 ix_status_nodedup | 29 MB   |       3733 |            90.08
```

| Column | Rows per key | Without dedup | With dedup | Ratio |
|---|---:|---:|---:|---:|
| `status` (text, 4 values) | 250,000 | 29 MB | 6.9 MB | **4.3×** smaller |
| `customer_id` (bigint) | ~5 | 21 MB | 11 MB | 1.9× |
| `id` (unique) | 1 | — | 21 MB | nothing to deduplicate |

What this changes in design discussions:
* "Never index a low-cardinality column" was partly a size argument; deduplication removed most of it. The remaining argument is **selectivity**: a 90 %-frequent value is still a seq scan. Low-cardinality columns are useful as the **leading column of a composite** (`(status, created_at)`, now also skip-scannable) or in **partial indexes**.
* Deduplication is disabled automatically for types where "equal" values aren't byte-identical (`numeric` display scale, `float` `-0`/`+0`, nondeterministic collations), shown as `allequalimage = f` in `bt_metap()`. Those indexes stay big.
* A sibling feature, **bottom-up index deletion** (PG 14), removes duplicates created by non-HOT updates that didn't change the indexed value (version churn) before a leaf has to split. Together they're why B-tree bloat on update-heavy tables is much lower in PG ≥ 14.

**Staff-level key guidance:**

| Need | Choose |
|---|---|
| Single database, internal IDs | `bigint generated always as identity` (8 bytes, monotonic) |
| IDs generated by clients, offline, or across shards; no central sequence | **UUIDv7** (time-ordered, 16 bytes). It leaks creation time, which matters if IDs are public |
| Public IDs that must not leak time or volume | Random UUIDv4 or an opaque token as a *secondary* unique column, with a bigint/UUIDv7 PK |

---

## 2. Composite indexes: the rules, verified 🔥

### 2.1 Leftmost prefix, and equality before range

A composite B-tree on `(a, b)` is sorted by `a`, then by `b` within each `a`. So it can efficiently answer:

* `a = ?`, `a = ? AND b = ?`, `a = ? AND b > ?`, `a = ? ORDER BY b`, `a > ?` (range on the first column);
* **not** efficiently `b = ?` alone (historically), and **not** `a > ? AND b = ?` as a tight range (the `b` condition becomes a filter *inside* the scanned range).

Query: *pending orders from the last week* (`status = 'PENDING' AND created_at >= '2026-12-07'`, 761 rows).

| Plan | Index | Buffers touched | Time (one run) |
|---|---|---|---|
| Parallel seq scan | none | 20,097 | 95.9 ms |
| Index scan | `(created_at, status)` (range column first) | 448 | 2.5 ms |
| Index scan | `(status, created_at)` (**equality first**) | 345 | 0.4 ms |

To isolate the index work, the same predicate as `count(*)` (an index-only scan touches only index pages):

**Output (verified):**

```text
-- (status, created_at)
 Aggregate (actual time=0.274..0.274 rows=1.00 loops=1)
   Buffers: shared hit=7
   ->  Index Only Scan using orders_status_created on orders (actual time=0.190..0.239 rows=761.00 loops=1)
         Index Cond: ((status = 'PENDING'::text) AND (created_at >= '2026-12-07 00:00:00+00'::timestamp with time zone))
         Heap Fetches: 0
         Index Searches: 1
         Buffers: shared hit=7

-- (created_at, status)
 Aggregate (actual time=1.573..1.573 rows=1.00 loops=1)
   Buffers: shared hit=13 read=97
   ->  Index Only Scan using orders_created_status on orders (actual time=0.051..1.514 rows=761.00 loops=1)
         Index Cond: ((created_at >= '2026-12-07 00:00:00+00'::timestamp with time zone) AND (status = 'PENDING'::text))
         Heap Fetches: 0
         Index Searches: 1
         Buffers: shared hit=13 read=97
```

**7 pages vs 110 pages for the same 761 rows.** With the range column first, the scan walks **every** entry from 7 December onward (~20,000 entries across all statuses) and discards 96% of them. With equality first, the `PENDING` entries for that week are contiguous.

> **Rule (E-S-R):** order composite index columns **E**quality → **S**ort (`ORDER BY` columns) → **R**ange. Within equality columns, the order matters little for that query; choose the order that also serves your *other* queries' leftmost prefixes.

### 2.2 PostgreSQL 18 skip scan: the leftmost-prefix rule softens 🧊

Before PostgreSQL 18, a query on `created_at` alone couldn't use `(status, created_at)` efficiently. PostgreSQL 18 adds **B-tree skip scan**: when the leading column has **few distinct values**, the executor performs one descent per value ("skips" between them).

```sql
-- index: (status, created_at); no predicate on status
select count(*) from orders where created_at >= '2026-12-13' and created_at < '2026-12-14';
```

**Output (verified):**

```text
 Aggregate (actual time=0.599..0.600 rows=1.00 loops=1)
   Buffers: shared hit=11 read=26
   ->  Index Only Scan using orders_status_created on orders (actual time=0.086..0.509 rows=2861.00 loops=1)
         Index Cond: ((created_at >= '2026-12-13 00:00:00+00'::timestamp with time zone) AND (created_at < '2026-12-14 00:00:00+00'::timestamp with time zone))
         Heap Fetches: 0
         Index Searches: 5
         Buffers: shared hit=11 read=26
```

`Index Searches: 5`: one descent per status value (four values, plus one that finds nothing more). It touched **37 pages, vs 20,097** for the parallel seq scan the planner had to use with index scans disabled. Skip scan helps when the skipped column has **low cardinality**. With 100,000 distinct leading values it degrades into 100,000 descents and the planner won't pick it.

`Index Searches` is a new `EXPLAIN ANALYZE` field in PostgreSQL 18. It's how you confirm skip scans and how many descents a `= ANY(array)` or `IN (...)` performed.

---

## 3. Covering indexes and index-only scans ⚡

An **index-only scan** answers a query from the index alone, *if* the planner can also prove the rows are visible to the current snapshot without visiting the heap. It uses the **visibility map**: one bit per heap page saying "every tuple here is visible to everyone". VACUUM sets those bits, and any write to a page clears its bit.

`INCLUDE` adds **non-key payload columns** to the leaf entries. They aren't sorted and can't be searched, but they can be returned.

```sql
-- customer history: WHERE customer_id = ? ORDER BY created_at DESC LIMIT 20, returning amount
create index orders_cust_created on orders (customer_id, created_at desc);
-- vs
create index orders_cust_created_incl on orders (customer_id, created_at desc) include (amount);
```

**Output (verified):**

```text
-- without INCLUDE: index → bitmap → heap → sort
 Limit (actual time=0.244..0.245 rows=8.00 loops=1)
   Buffers: shared hit=7 read=7
   ->  Sort ...
         ->  Bitmap Heap Scan on orders ...
               Heap Blocks: exact=8
               ->  Bitmap Index Scan on orders_cust_created ...

-- with INCLUDE (amount)
 Limit (actual time=0.209..0.211 rows=8.00 loops=1)
   Buffers: shared hit=1 read=3
   ->  Index Only Scan using orders_cust_created_incl on orders (actual time=0.208..0.210 rows=8.00 loops=1)
         Index Cond: (customer_id = 4242)
         Heap Fetches: 0
```

Now dirty some pages and watch `Heap Fetches`:

```sql
update orders set amount = amount where customer_id between 4000 and 4500;
```

**Output (verified):**

```text
 all_visible_pages | pages
-------------------+-------
             15772 | 20194

   ->  Index Only Scan using orders_cust_created_incl on orders (actual time=0.022..0.046 rows=8.00 loops=1)
         Heap Fetches: 16
         Buffers: shared hit=20

vacuum orders;
 all_visible_pages | pages
-------------------+-------
             20194 | 20194

   ->  Index Only Scan using orders_cust_created_incl on orders (actual time=0.009..0.009 rows=8.00 loops=1)
         Heap Fetches: 0
         Buffers: shared hit=4
```

Lessons:

1. An "index-only scan" on a **write-heavy table that VACUUM can't keep up with** is really an index scan plus heap fetches. Check `Heap Fetches`, not the node name.
2. `Heap Fetches: 16` for 8 rows: the update created a second index entry per row (old and new version), and both needed a visibility check.
3. `INCLUDE`d columns count as indexed columns for HOT. Updating `amount` is no longer a HOT update ([2.1 §1.3](01-Storage-Pages-Tuples-TOAST-WAL.md)). Covering indexes trade write cost for read speed.

---

## 4. Partial and expression indexes ⚡

### 4.1 Partial: index only the rows the hot query wants

```sql
create index orders_pending_partial on orders (created_at) where status = 'PENDING';
```

**Output (verified, sizes of all indexes on `orders` at that moment):**

```text
          index           |  size
--------------------------+--------
 orders_cust_created_incl | 39 MB
 orders_status_created    | 38 MB
 orders_pkey              | 21 MB
 orders_pending_partial   | 896 kB

explain (costs off) select id from orders where status = 'PENDING' and created_at < '2026-01-02';
 Index Scan using orders_pending_partial on orders
   Index Cond: (created_at < '2026-01-02 00:00:00+00'::timestamp with time zone)
```

**896 kB instead of ~20 MB**, and writes to the 96% of rows that aren't `PENDING` never touch it. Classic uses: work queues (`WHERE status = 'READY'`), soft deletes (`WHERE deleted_at IS NULL`), "unique among active rows" (`CREATE UNIQUE INDEX … WHERE deleted_at IS NULL`).

The query's predicate must **imply** the index predicate. A parameterized `status = $1` can't use it in a generic plan, because the planner can't prove `$1 = 'PENDING'` ([2.3 §5](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md)).

### 4.2 Expression: index what you actually compare

**Output (verified):**

```text
explain (costs off) select id from orders where lower(email) = 'user4242@example.com';
 Gather
   Workers Planned: 2
   ->  Parallel Seq Scan on orders
         Filter: (lower(email) = 'user4242@example.com'::text)

create index orders_email_lower on orders (lower(email));
explain (costs off) select id from orders where lower(email) = 'user4242@example.com';
 Bitmap Heap Scan on orders
   Recheck Cond: (lower(email) = 'user4242@example.com'::text)
   ->  Bitmap Index Scan on orders_email_lower
         Index Cond: (lower(email) = 'user4242@example.com'::text)

explain (costs off) select id from orders where email = 'User4242@Example.com';
 Gather
   Workers Planned: 2
   ->  Parallel Seq Scan on orders
         Filter: (email = 'User4242@Example.com'::text)
```

The index matches only the **exact expression**. `email = …` doesn't use an index on `lower(email)`. The same trap appears when an ORM wraps a column in a function (`upper(name) LIKE ?`) or casts it (`created_at::date = ?`). Rewrite the predicate (`created_at >= ? AND created_at < ?`) or index the expression.

---

## 5. Beyond B-tree: pick the structure that matches the operator ⚡

| Index type | Data structure | Operators | Use for | Avoid when |
|---|---|---|---|---|
| **B-tree** | Sorted tree (Lehman–Yao) | `= < > BETWEEN IN`, `ORDER BY`, prefix `LIKE 'abc%'` (C collation) | Almost everything | Containment, overlap, infix search |
| **Hash** | Hash buckets | `=` only | Very long keys used only for equality | You need ranges or ordering (it can't do them) |
| **GIN** | Inverted index: element → posting list of row ids | `@>`, `?`, `@@` (full text), trigram `LIKE '%x%'` | `jsonb`, arrays, full text, infix search | Frequently updated rows (GIN writes are expensive; `fastupdate` pending lists help) |
| **GiST** | Balanced tree of bounding predicates (R-tree-like) | `&&` overlap, `@>` contains, nearest-neighbor `<->` | Ranges, geometry, **exclusion constraints** | Plain equality on scalars |
| **SP-GiST** | Space-partitioned tree (quad-tree, radix) | Points, IP ranges, prefixes | Non-balanced data (phone prefixes, points) | General use |
| **BRIN** | Min/max summary per block range (128 pages) | Ranges on **physically correlated** columns | Append-only time series, logs | Data that isn't stored in key order |

### 5.0 Hash vs B-tree on long equality-only keys (verified) ⚡

A hash index stores a **4-byte hash code** per entry, not the key. For long keys that are only ever compared with `=` (URLs, external tokens, content hashes), that's a big difference:

```sql
create table urls (id bigint primary key, url text not null);     -- 300,000 URLs, 175 characters on average
create index urls_btree on urls using btree (url);
create index urls_hash  on urls using hash  (url);
select relname, pg_size_pretty(pg_relation_size(oid)) from pg_class where relname in ('urls', 'urls_btree', 'urls_hash');
```

**Output (verified, PostgreSQL 18.6):**

```text
  relname   | pg_size_pretty
------------+----------------
 urls       | 63 MB
 urls_btree | 66 MB
 urls_hash  | 8208 kB
```

* The B-tree is **bigger than the table** (it stores every 175-byte key); the hash index is **8× smaller**. An equality lookup touched 3 pages through the hash index and 5 through the B-tree (`Index Searches: 1` both).
* Hash indexes are WAL-logged and crash-safe since PostgreSQL 10 (before that, they weren't, which is why older advice says "never use them").
* Limits: equality only (no ranges, no `ORDER BY`, no `LIKE 'prefix%'`), **can't be `UNIQUE`**, single column, no index-only scans. If you need uniqueness on a long key, the common pattern is a unique B-tree on a fixed-size digest column (`sha256(url)` stored as `bytea`) instead.

### 5.1 GIN on `jsonb` (verified)

**Output (verified):**

```text
-- no index
 Finalize Aggregate (actual time=155.173..161.506 rows=1.00 loops=1)
   ...  ->  Parallel Seq Scan on orders (actual time=0.294..58.370 rows=22222.33 loops=3)
               Filter: (attrs @> '{"channel": "store", "priority": true}'::jsonb)

         index         |  size
-----------------------+---------
 orders_attrs_gin      | 8232 kB
 orders_attrs_gin_path | 5040 kB

-- jsonb_path_ops GIN
 Aggregate (actual time=186.649..186.650 rows=1.00 loops=1)
   ->  Bitmap Heap Scan on orders (actual time=13.116..184.340 rows=66667.00 loops=1)
         Recheck Cond: (attrs @> '{"channel": "store", "priority": true}'::jsonb)
         Heap Blocks: exact=20192
         ->  Bitmap Index Scan on orders_attrs_gin_path (actual time=10.905..10.905 rows=66667.00 loops=1)
```

Two staff-level observations:

* `jsonb_path_ops` is **40% smaller** than the default `jsonb_ops` (it hashes whole paths) but supports only `@>`, not key-existence `?`.
* The index found 66,667 matches in 11 ms, but **the query was not faster**: 66,667 rows spread over all 20,192 heap pages is a full table read with extra steps. **Selectivity decides**, not the presence of an index. GIN shines for selective predicates (a rare tag), not for "a third of the table".

### 5.2 Trigram GIN for infix search (verified)

```text
explain (costs off) select count(*) from orders where email like '%4242@%';
   ->  Parallel Seq Scan on orders   Filter: (email ~~ '%4242@%'::text)

create index orders_email_trgm on orders using gin (email gin_trgm_ops);
 Aggregate (actual time=1.428..1.429 rows=1.00 loops=1)
   ->  Bitmap Heap Scan on orders (actual time=0.428..1.395 rows=103.00 loops=1)
         Recheck Cond: (email ~~ '%4242@%'::text)
         ->  Bitmap Index Scan on orders_email_trgm (actual time=0.356..0.357 rows=103.00 loops=1)
```

A leading-wildcard `LIKE` can't use a B-tree. A trigram index splits strings into 3-character pieces and intersects their posting lists: **1.4 ms**. It's the cheapest "search box" you can build before you need Elasticsearch/OpenSearch.

### 5.3 GiST exclusion constraint: business rules the database enforces (verified)

```sql
create table booking (
  room_id int not null,
  during  tstzrange not null,
  exclude using gist (room_id with =, during with &&)      -- needs btree_gist for the "=" on int
);
insert into booking values (101, '[2026-11-01 10:00, 2026-11-01 11:00)');
insert into booking values (101, '[2026-11-01 11:00, 2026-11-01 12:00)');   -- adjacent: fine
insert into booking values (102, '[2026-11-01 10:30, 2026-11-01 11:30)');   -- other room: fine
insert into booking values (101, '[2026-11-01 10:30, 2026-11-01 11:30)');   -- overlaps: rejected
```

**Output (verified):**

```text
ERROR:  conflicting key value violates exclusion constraint "booking_room_id_during_excl"
DETAIL:  Key (room_id, during)=(101, ["2026-11-01 10:30:00+00","2026-11-01 11:30:00+00")) conflicts with existing key (room_id, during)=(101, ["2026-11-01 10:00:00+00","2026-11-01 11:00:00+00")).
```

"No double booking" enforced **under concurrency** with no application locking, no `SERIALIZABLE`, no race window. It's the generalization of a unique constraint to *overlap*. Use it for reservations, price validity periods, shift schedules.

### 5.4 BRIN: tiny indexes for physically ordered data (verified)

```text
select correlation from pg_stats where tablename = 'orders' and attname = 'created_at';
 correlation
-------------
           1

        index         | size
----------------------+-------
 orders_created_brin  | 24 kB
 orders_created_btree | 21 MB
```

**Output (verified, one day of data, forced to use BRIN):**

```text
 Aggregate (actual time=2.626..2.626 rows=1.00 loops=1)
   ->  Bitmap Heap Scan on orders (actual time=1.151..2.405 rows=2880.00 loops=1)
         Rows Removed by Index Recheck: 8304
         Heap Blocks: lossy=226
         ->  Bitmap Index Scan on orders_created_brin (actual time=0.088..0.088 rows=2260.00 loops=1)
               Buffers: shared hit=8
```

The BRIN index is **~900× smaller** than the B-tree. It stores only min/max per 128-page range, so it returns *candidate block ranges* (`lossy=226` blocks) that must be rechecked (8,304 rows discarded). It's excellent for append-only time-series tables queried by time range, and useless as soon as rows aren't physically in key order (random updates, `CLUSTER` drift, mixed tenants).

---

## 6. The write side: what every index costs 🧊

| Cost | Mechanism | Mitigation |
|---|---|---|
| Insert amplification | Every index gets an entry, plus WAL | Drop unused indexes (`pg_stat_user_indexes.idx_scan = 0` over a full business cycle) |
| Lost HOT updates | Updating any indexed (or `INCLUDE`d) column forces index inserts in **all** indexes | Don't index churning columns; partial indexes; `fillfactor` |
| Bloat | Deleted and updated entries leave space. Random keys leave half-empty pages | `pgstatindex` (`avg_leaf_density`, `leaf_fragmentation`); `REINDEX CONCURRENTLY`; PG13+ deduplication and PG14+ bottom-up deletion reduce it |
| Lock impact of creating one | `CREATE INDEX` blocks writes for the whole build | `CREATE INDEX CONCURRENTLY` (two passes, can't run in a transaction block, leaves an `INVALID` index on failure: check `pg_index.indisvalid`) |
| Planning cost | More indexes mean more paths to cost | Usually minor. Matters for very high-QPS simple queries |

---

## 7. MySQL/InnoDB differences you'll be asked about

| Topic | InnoDB |
|---|---|
| Secondary index entry | Stores the **PK value**, so every secondary lookup is two descents, and a "covering" secondary index implicitly includes the PK columns |
| Partial indexes | Not supported. Functional (expression) indexes since 8.0.13 |
| Index-only scan | "Using index" in `EXPLAIN`. No visibility map: InnoDB checks visibility per record via undo if needed |
| Skip scan | "Using index for skip scan" (since 8.0.13) |
| Invisible indexes | `ALTER TABLE … ALTER INDEX i INVISIBLE`: test dropping an index safely (PostgreSQL has no direct equivalent; use `pg_stat_user_indexes` and a careful drop) |
| Locking | Indexes define **gap and next-key lock** ranges. A missing index can turn a row lock into locking a huge range ([2.6](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)) |

---

## 8. ❌ Naïve vs ✅ production-hardened indexing

| ❌ Naïve | ✅ Hardened |
|---|---|
| One single-column index per filtered column | Composite indexes designed per hot query, E-S-R ordered |
| `(created_at, status)` because "time is important" | `(status, created_at)` for `status = ? AND created_at > ?`: 7 vs 110 pages |
| UUIDv4 primary key "for distributed IDs" | bigint identity, or UUIDv7 (90% dense leaves vs 71%) |
| Expect an index-only scan because `EXPLAIN` says so | Check `Heap Fetches`; make sure (auto)vacuum keeps the visibility map fresh |
| `WHERE lower(email) = ?` with an index on `email` | Expression index on `lower(email)`, or a `citext`/case-insensitive collation column |
| GIN on a 30%-selective predicate | Real selectivity analysis; partial indexes for the selective slice |
| B-tree on a 2 TB append-only log's `created_at` | BRIN (+ partitioning, [2.7](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)) |
| `CREATE INDEX` on a busy table at noon | `CREATE INDEX CONCURRENTLY` + check `indisvalid` + `lock_timeout` |

---

## 9. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/access/nbtree/README` | Lehman–Yao, high keys, right-links, deduplication, the best design doc in the tree |
| postgres/postgres | `src/backend/access/nbtree/nbtinsert.c` | `_bt_split`, `_bt_findsplitloc` and the rightmost-split optimization |
| postgres/postgres | `src/backend/access/nbtree/nbtsearch.c` | `_bt_search`, `_bt_first`: one descent, then walking the leaves |
| postgres/postgres | `src/backend/access/nbtree/nbtutils.c` | Array keys and the PostgreSQL 18 skip-scan machinery |
| postgres/postgres | `src/backend/access/gin/README` | Posting lists, pending list (`fastupdate`) |
| postgres/postgres | `src/backend/access/brin/brin.c` | Range summaries and `brin_summarize_new_values` |
| postgres/postgres | `src/backend/access/heap/visibilitymap.c` | The all-visible and all-frozen bits that make index-only scans work |

---

## 10. Interview soundbites

* "A B-tree lookup costs one page per level. With ~250-way fan-out a billion rows is about four levels, and the top ones are cached."
* "Composite index order is equality, then sort, then range. Same 761 rows: 7 pages with `(status, created_at)`, 110 with `(created_at, status)`."
* "PostgreSQL 18 can skip-scan a low-cardinality leading column. `Index Searches: 5` in EXPLAIN shows it."
* "An index-only scan still visits the heap for pages that aren't all-visible. `Heap Fetches` tells you whether vacuum is keeping up."
* "Random UUIDv4 keys gave 71% leaf density and 50% fragmentation; UUIDv7 kept 90% like a bigint. In InnoDB, a random PK fragments the table itself."
* "The index only helps if the predicate is selective. GIN found a third of the table in 11 ms and the query was still a full heap read."
* "B-tree deduplication made a 4-value index 4.3× smaller (29 MB → 6.9 MB). Low cardinality is now a selectivity question, not a size one."
* "For long equality-only keys a hash index stores 4-byte codes: 8 MB vs a 66 MB B-tree that was bigger than its table. It can't be unique, though."

---

## Summary

| Concept | Rule | Verified evidence |
|---|---|---|
| B+tree shape | One page per level; ~250-way fan-out; Lehman–Yao right-links | 1 M keys: height 2, 2,733 leaves |
| Key choice | Monotonic keys split at the right edge | UUIDv4 71 % density / 50 % fragmentation vs UUIDv7 90 % / 0 % |
| Deduplication (PG 13+) | Posting lists for repeated keys | `status` index 29 MB → 6.9 MB |
| Composite order | Equality → Sort → Range | 7 vs 110 pages for the same 761 rows |
| Skip scan (PG 18) | Leading column with few values can be skipped | `Index Searches: 5` |
| Covering / index-only | `INCLUDE` payload; needs the visibility map | `Heap Fetches` decides ([2.9 §5](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#5-index-only-scan-the-visibility-map-and-the-vacuum-that-didnt-help-)) |
| Partial / expression | Index the hot slice / the exact expression you compare | `lower(email)` index unused by `email = …` |
| Hash | 4-byte codes, equality only, not unique | 8 MB vs 66 MB B-tree on 175-char URLs |
| GIN / GiST / BRIN | Inverted index / bounding predicates / per-block-range min-max | BRIN ~900× smaller than a B-tree, lossy blocks rechecked |
| Write cost | Every index costs inserts, WAL, lost HOT, vacuum | Drop indexes with `idx_scan = 0` over a full cycle |
| InnoDB difference | Secondary entries carry the PK; indexes define gap-lock ranges | — |

**Next:** [2.3 Query planning, EXPLAIN, statistics and joins →](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md)
