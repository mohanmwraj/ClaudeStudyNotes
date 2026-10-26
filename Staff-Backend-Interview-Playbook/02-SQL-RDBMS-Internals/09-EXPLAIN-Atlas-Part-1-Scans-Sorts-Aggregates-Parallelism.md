# 2.9 EXPLAIN Atlas, Part 1: Every Scan, Sort, Aggregate and Parallel Node, Line by Line

> **Verified stack:** PostgreSQL **18.6** (`io_method = worker`, `track_io_timing = on`, `jit = off`, `shared_buffers = 128MB`, `work_mem = 4MB`, default cost constants). Dataset: the deterministic `atlas` database built by the script in §0.2 (1 M `orders`, 3 M `order_lines`, 200 k `customers`, 20 k `products`, 1.2 M `events` in 12 monthly partitions).
>
> **How to read the evidence:** every plan below is the complete output of one run, captured in one sequential session on a freshly loaded database. **Plan shapes, row counts, `Heap Fetches`, `Index Searches`, `Batches` and cost estimates reproduce exactly** on the same dataset; times and the `hit`/`read` split of `Buffers` vary from run to run. Where this file shows a cost formula, the formula was computed in SQL next to the plan, and the numbers match the planner's.
>
> **Prereqs:** [2.3 Query planning](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md) (statistics, join choice, generic plans). **Continues in:** [2.10 Atlas Part 2: joins, subqueries, partitions, DML](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md) and [2.11 Plan pathologies](11-Plan-Pathologies-Diagnosis-Playbook.md).

---

## 0. How to use this atlas 🔥

### 0.1 What one plan line carries

```text
 Index Scan using orders_created_at on orders  (cost=0.42..62.98 rows=1358 width=14) (actual time=0.073..0.360 rows=1371.00 loops=1)
 └─ node type ─┘ └──── access path ────────┘  └─startup..total─┘└ est ┘└avg B┘          └─ first row..last row ┘ └─ per loop ─┘ └ times run ┘
```

| Field | Unit | Exactly what it is | The trap |
|---|---|---|---|
| `cost=a..b` | Abstract units (1.0 = one sequential 8 KB page read) | `a` = cost before the first row can be emitted; `b` = cost to emit all rows | Costs are only comparable between alternative plans **for the same query**. A child's cost is *included* in its parent's |
| `rows=` (estimate) | Rows | Rows the planner expects this node to emit **per loop** | Compare with actual *per loop* |
| `width=` | Bytes | Average width of an output row | Drives sort/hash memory estimates |
| `actual time=x..y` | ms | Time to first row .. time to last row, **averaged per loop**, inclusive of children | Exclusive time of a node = its time − its children's time (×loops) |
| `rows=1371.00` (actual) | Rows | PostgreSQL 18 prints actual rows with two decimals: it's an **average per loop** | Multiply by `loops` for the total |
| `loops=` | Count | How many times the node was (re)started | `loops=20000` on an inner side is a database-side N+1 |
| `Buffers: shared hit/read/dirtied/written` | 8 KB pages | `hit` = found in `shared_buffers`; `read` = requested from the OS (page cache or disk); `dirtied` = this query modified a clean page; `written` = this backend had to evict a dirty page itself | **Inclusive of children**. Buffers are on by default with `ANALYZE` since PG 18 |
| `temp read/written` | 8 KB blocks | Spill files for sorts, hashes, materialize | Any `temp` = something didn't fit in `work_mem` |
| `I/O Timings` | ms | Time in read()/write() calls; requires `track_io_timing = on` | Low `read` time with many reads = OS page cache, not disk |

### 0.2 The dataset (run it yourself)

Everything is generated arithmetically (no `random()`), so your row counts will match these exactly.

```sql
-- psql -f atlas_setup.sql atlas      (about 70 s on a laptop)
create table customers (
    id bigint primary key, email text not null unique,
    country text not null,          -- skewed: US 40 %, IN 20 %, DE 10 %, GB 10 %, 16 others share 20 %
    tier text not null,             -- free 90 %, pro 9 %, enterprise 1 %
    created_at timestamptz not null);
insert into customers
select g, 'user' || g || '@example.com',
       case when g % 10 < 4 then 'US' when g % 10 < 6 then 'IN' when g % 10 = 6 then 'DE' when g % 10 = 7 then 'GB'
            else (array['FR','BR','JP','CA','AU','NL','SE','ES','IT','MX','PL','KR','SG','ZA','NZ','IE'])[1 + (g / 10) % 16] end,
       case when g % 100 = 0 then 'enterprise' when g % 100 < 10 then 'pro' else 'free' end,
       timestamptz '2021-01-01 00:00:00+00' + (g * interval '13 minutes')
from generate_series(1, 200000) g;

create table products (id bigint primary key, sku text not null unique, category text not null, price numeric(10,2) not null);
insert into products select g, 'SKU-' || lpad(g::text, 6, '0'), 'cat-' || (g % 50), round((5 + (g * 37 % 995))::numeric, 2)
from generate_series(1, 20000) g;

create table orders (
    id bigint primary key, customer_id bigint not null references customers(id),
    status text not null,           -- DELIVERED 90 %, SHIPPED 5 %, PENDING 4 %, CANCELLED 1 %
    created_at timestamptz not null,-- grows with id: physically ordered (correlation ≈ 1)
    total numeric(12,2) not null, note text);
insert into orders
select g, 1 + (g * 7919) % 200000,
       case when g % 100 = 0 then 'CANCELLED' when g % 100 < 5 then 'PENDING' when g % 100 < 10 then 'SHIPPED' else 'DELIVERED' end,
       timestamptz '2024-01-01 00:00:00+00' + (g * interval '63 seconds'),
       round(((g * 104729) % 50000 / 100.0 + 1)::numeric, 2),
       case when g % 50 = 0 then repeat('gift wrap please; ', 3) end
from generate_series(1::bigint, 1000000) g;

create table order_lines (
    order_id bigint not null references orders(id), line_no int not null,
    product_id bigint not null references products(id), qty int not null, price numeric(10,2) not null,
    primary key (order_id, line_no));
insert into order_lines
select o, l, 1 + (o * 31 + l * 7) % 20000, 1 + (o + l) % 5, round((5 + ((o * 31 + l * 7) % 20000) * 37 % 995)::numeric, 2)
from generate_series(1::bigint, 1000000) o, generate_series(1, (1 + o % 5)::int) l;   -- 1..5 lines per order, 3 M total

create table events (id bigint not null, occurred_at timestamptz not null, kind text not null, payload jsonb not null)
    partition by range (occurred_at);
do $$ declare m date := date '2026-01-01'; begin      -- bounds inherit the session TimeZone: see 2.10 §6.4 (a deliberate, verified gotcha)
  for i in 0..11 loop
    execute format('create table events_%s partition of events for values from (%L) to (%L)',
      to_char(m + make_interval(months => i), 'YYYY_MM'), m + make_interval(months => i), m + make_interval(months => i + 1));
  end loop; end $$;
insert into events select g, timestamptz '2026-01-01 00:00:00+00' + (g * interval '26 seconds'),
       (array['click','view','purchase','signup'])[1 + g % 4], jsonb_build_object('user', g % 50000, 'score', g % 97)
from generate_series(1, 1200000) g;
create index on events (occurred_at);

create index orders_customer_id    on orders (customer_id);
create index orders_created_at     on orders (created_at);
create index orders_status_created on orders (status, created_at);
create index customers_country     on customers (country);
create index order_lines_product   on order_lines (product_id);
vacuum (analyze) customers, products, orders, order_lines, events;
alter database atlas set timezone = 'UTC';
create extension pageinspect; create extension pg_visibility; create extension pg_buffercache; create extension pgstattuple;
```

**Output (verified, PostgreSQL 18.6):**

```text
    relname     |  rows   | pages |  size
----------------+---------+-------+---------
 customers      |  200000 |  1870 | 15 MB
 events_2026_01 |  102253 |  1345 | 11 MB
 order_lines    | 3000000 | 25000 | 195 MB
 orders         | 1000000 |  9412 | 74 MB
 products       |   20000 |   148 | 1184 kB
```

### 0.3 Which `EXPLAIN` options to use, and when

| Option | Since | Adds | Use it when |
|---|---|---|---|
| `ANALYZE` | always | Runs the query; actual rows, times, loops | Always for diagnosis (**it executes DML**: wrap in `BEGIN … ROLLBACK`) |
| `BUFFERS` | 9.0; **default with `ANALYZE` in 18** | Pages touched per node, planning buffers | Always. Buffers are more stable than time |
| `VERBOSE` | always | Output columns, schema-qualified names, **per-worker** stats, query identifier | Parallel plans, checking what columns flow up |
| `SETTINGS` | 12 | Every planner GUC that differs from default | Always when sharing a plan: "it's slow" may be someone's `SET` |
| `WAL` | 13 | WAL records, full-page images, bytes per node | DML tuning ([2.10 §7](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md#7-dml-modifytable-wal-hot-foreign-key-triggers-on-conflict-)) |
| `GENERIC_PLAN` | 16 | Plans a query containing `$1` without values | Reproducing what a prepared statement (JDBC) runs |
| `SERIALIZE` | 17 | Time and bytes to convert the result to wire format | "The query is fast but the endpoint is slow" (detoasting, wide rows) |
| `MEMORY` | 17 | Planner memory | Huge `IN` lists, many partitions |
| `FORMAT JSON` | 9.0 | Machine-readable plan | Tooling (explain.dalibo.com, auto_explain parsing) |
| `TIMING OFF` | 9.2 | Removes per-node clock calls | Measuring real runtime on machines where clock reads are expensive |

The rest of this file walks the node types bottom-up: scans (§1–§7), then nodes that reorder or reduce rows (§8–§10).

---

## 1. Seq Scan, and the cost formula reproduced 🔥

```sql
set max_parallel_workers_per_gather = 0;      -- keep this one serial so the formula is simple
explain (analyze, buffers, verbose, settings) select id, total from orders where total > 490;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Seq Scan on public.orders  (cost=0.00..21912.00 rows=22676 width=14) (actual time=0.085..74.395 rows=21980.00 loops=1)
   Output: id, total
   Filter: (orders.total > '490'::numeric)
   Rows Removed by Filter: 978020
   Buffers: shared read=9412
   I/O Timings: shared read=0.389
 Settings: jit = 'off', max_parallel_workers_per_gather = '0'
 Query Identifier: 7973034977459002510
 Planning:
   Buffers: shared hit=110 read=2 dirtied=2
   I/O Timings: shared read=1.091
 Planning Time: 4.425 ms
 Execution Time: 75.048 ms
```

```sql
select relpages, reltuples, relpages * 1.0 + reltuples * (0.01 + 0.0025) as seq_scan_cost_formula
from pg_class where relname = 'orders';
```

```text
 relpages | reltuples | seq_scan_cost_formula
----------+-----------+-----------------------
     9412 |   1000000 |                 21912
```

**Line by line:**

| Line | What it tells you |
|---|---|
| `cost=0.00..21912.00` | `seq_page_cost × relpages` (9,412 × 1.0) + `cpu_tuple_cost × reltuples` (1,000,000 × 0.01) + `cpu_operator_cost × reltuples × quals` (1,000,000 × 0.0025 × 1) = **21,912**, exactly. Startup is 0: a seq scan can emit its first row immediately |
| `rows=22676` vs `21980.00` | The `total > 490` estimate comes from the histogram on `total` (3 % error: healthy) |
| `width=14` | `id` (8 bytes) + `total` (`numeric`, ~6 bytes average): only the projected columns, thanks to `VERBOSE`'s `Output: id, total` |
| `Rows Removed by Filter: 978020` | 97.8 % of rows read were thrown away. On a hot query, that's the signal to look for an index |
| `Buffers: shared read=9412` | Every heap page was requested from the OS. All of them, because the table had just been loaded (cold `shared_buffers`) |
| `I/O Timings: shared read=0.389` | 9,412 reads took 0.4 ms in total: they came from the **OS page cache**, not the SSD. `read` ≠ disk |
| `Settings:` | Shows that `max_parallel_workers_per_gather` was changed. Without `SETTINGS`, a colleague reproducing this plan would get a parallel plan |
| `Query Identifier` | The same ID `pg_stat_statements.queryid` uses (printed with `VERBOSE` when `compute_query_id` is on). Join a plan to its statistics row with it |
| `Planning: Buffers: … dirtied=2` | Planning read catalog pages (statistics, index metadata). Planning time of 4.4 ms here is a cold catalog cache; repeated it's ~0.1 ms |

**Why the planner can't make a seq scan cheaper:** the only levers are fewer pages (smaller rows, less bloat, partitions) or fewer rows examined (an index). That's why bloat ([2.5](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)) is a performance problem, not just a disk problem.

---

## 2. Parallel Seq Scan, Gather, Partial and Finalize Aggregate ⚡

```sql
explain (analyze, buffers, verbose) select count(*) from orders where total > 490;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Finalize Aggregate  (cost=15644.17..15644.18 rows=1 width=8) (actual time=69.962..77.977 rows=1.00 loops=1)
   Output: count(*)
   Buffers: shared hit=132 read=9280
   I/O Timings: shared read=1.985
   ->  Gather  (cost=15643.95..15644.16 rows=2 width=8) (actual time=69.424..77.971 rows=3.00 loops=1)
         Output: (PARTIAL count(*))
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=132 read=9280
         I/O Timings: shared read=1.985
         ->  Partial Aggregate  (cost=14643.95..14643.96 rows=1 width=8) (actual time=28.768..28.768 rows=1.00 loops=3)
               Output: PARTIAL count(*)
               Buffers: shared hit=132 read=9280
               I/O Timings: shared read=1.985
               Worker 0:  actual time=2.999..2.999 rows=1.00 loops=1
                 Buffers: shared hit=11 read=186
                 I/O Timings: shared read=0.766
               Worker 1:  actual time=14.177..14.178 rows=1.00 loops=1
                 Buffers: shared hit=79 read=1440
                 I/O Timings: shared read=0.826
               ->  Parallel Seq Scan on public.orders  (cost=0.00..14620.33 rows=9448 width=0) (actual time=0.523..28.419 rows=7326.67 loops=3)
                     Output: id, customer_id, status, created_at, total, note
                     Filter: (orders.total > '490'::numeric)
                     Rows Removed by Filter: 326007
                     Buffers: shared hit=132 read=9280
                     I/O Timings: shared read=1.985
                     Worker 0:  actual time=0.730..2.968 rows=452.00 loops=1
                       Buffers: shared hit=11 read=186
                       I/O Timings: shared read=0.766
                     Worker 1:  actual time=0.776..14.003 rows=3541.00 loops=1
                       Buffers: shared hit=79 read=1440
                       I/O Timings: shared read=0.826
 Query Identifier: 1212200467760527892
 Planning:
   Buffers: shared hit=5 read=1
   I/O Timings: shared read=0.013
 Planning Time: 0.125 ms
 Execution Time: 78.012 ms
```

```sql
select relpages + (reltuples * (0.01 + 0.0025)) / (2 + (1 - 0.3 * 2)) as parallel_seq_scan_cost_formula
from pg_class where relname = 'orders';
```

```text
 parallel_seq_scan_cost_formula
--------------------------------
             14620.333333333334
```

**Line by line:**

| Line | What it tells you |
|---|---|
| `Parallel Seq Scan … cost=0.00..14620.33` | **Disk cost isn't divided, CPU cost is.** 9,412 pages + 12,500 CPU ÷ **2.4**. The parallel divisor for 2 workers is `2 + (1 − 0.3 × 2) = 2.4`: each worker counts as 1, and the leader counts as `1 − 0.3 × workers` because it also has to collect tuples (`costsize.c: get_parallel_divisor`). The formula reproduces 14,620.33 exactly |
| `rows=9448` (estimate) | Estimated rows **per process** (22,676 ÷ 2.4) |
| `rows=7326.67 loops=3` | Actual rows **averaged over 3 processes** (leader + 2 workers): 21,980 ÷ 3 |
| `Worker 0 … read=186`, `Worker 1 … read=1440` | Per-worker detail, printed only with `VERBOSE`. The workers scanned 197 + 1,519 pages; the **leader** scanned the other ~7,700 (82 %). Workers took a few ms to start, and the leader grabbed blocks in the meantime. `Workers Launched: 2` doesn't mean the work was split evenly |
| `Partial Aggregate … loops=3` | Each process counts its own rows (`PARTIAL count(*)`) |
| `Gather … rows=3.00` | Collects the 3 partial counts through shared-memory queues |
| `Finalize Aggregate` | Sums the partial counts. Aggregates need a combine function to be split this way (`count`, `sum`, `avg` have one; ordered-set aggregates don't) |
| `Gather cost … 15643.95` | Includes `parallel_setup_cost` (1,000) + `parallel_tuple_cost` (0.1 per row sent): that's why tiny queries stay serial |

**Production notes:** `Workers Planned > Workers Launched` means the server ran out of `max_parallel_workers` (or `max_worker_processes`) at that moment: the query then runs with fewer processes but the plan doesn't change. On busy OLTP primaries, parallelism multiplies CPU per query; many teams set `max_parallel_workers_per_gather = 0` for the application role and allow it only for reporting roles.

---

## 3. Index Scan: the B-tree descent priced exactly ⚡

```sql
select level as btree_height from bt_metap('orders_pkey');                 -- pageinspect
explain (analyze, buffers) select * from orders where id = 424242;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 btree_height
--------------
            2

 Index Scan using orders_pkey on orders  (cost=0.42..8.44 rows=1 width=94) (actual time=0.096..0.097 rows=1.00 loops=1)
   Index Cond: (id = 424242)
   Index Searches: 1
   Buffers: shared hit=3 read=4
   I/O Timings: shared read=0.072
 Planning:
   Buffers: shared hit=20
 Planning Time: 0.121 ms
 Execution Time: 0.105 ms
```

The cost is reproducible from `costsize.c: cost_index` and `selfuncs.c: btcostestimate`:

| Component | Formula | Value |
|---|---|---|
| Descent (startup) | `ceil(log2(1,000,000)) × cpu_operator_cost` + `(height + 1) × 50 × cpu_operator_cost` = 20 × 0.0025 + 3 × 50 × 0.0025 | **0.425** → shown as `0.42` |
| Leaf page | 1 page × `random_page_cost` | 4.0 |
| Index tuple | 1 × (`cpu_index_tuple_cost` 0.005 + qual 0.0025) | 0.0075 |
| Heap page | 1 page × `random_page_cost` | 4.0 |
| Heap tuple | 1 × `cpu_tuple_cost` | 0.01 |
| **Total** | | **8.4425** → shown as `8.44` |

```text
 descent | total
---------+--------
  0.4250 | 8.4425
```

**Reading the buffers:** this was the first lookup on a fresh connection: `hit=3 read=4` = 7 pages. Repeating it in the same session:

```text
-- same query again, same session            -- a different id, same session
   Buffers: shared hit=4                        Buffers: shared hit=2 read=2
```

The steady state is **4 pages = 3 B-tree levels (root, internal, leaf: `level = 2` counts the edges) + 1 heap page**. The first execution on a connection touches a few extra pages, starting with the index **metapage** (block 0), whose root pointer the backend then caches in its relcache. Two lessons: a 1-row primary-key lookup costs ~4 page touches regardless of table size (height 2 here holds 1 M keys; height 3 holds hundreds of millions), and **first-execution plans on new connections look worse** than steady state, so don't benchmark a pooled application with a fresh `psql` session.

**Interview point:** `random_page_cost = 4` assumes spinning disks with a cold cache. On SSDs with most of the working set cached, `1.1`–`1.5` is common and makes the planner choose index scans more often. Change it **per tablespace or per database** after measuring, not because a blog said so.

---

## 4. Index Scan vs Bitmap Heap Scan: `correlation` decides 🔥

```sql
select attname, round(correlation::numeric, 4) as correlation from pg_stats
where tablename = 'orders' and attname in ('created_at', 'customer_id');
explain (analyze, buffers) select id, total from orders where created_at >= '2025-06-01' and created_at < '2025-06-02';
explain (analyze, buffers) select id, total from orders where customer_id between 1000 and 1200;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
   attname   | correlation
-------------+-------------
 created_at  |      0.9997
 customer_id |      0.0005

 Index Scan using orders_created_at on orders  (cost=0.42..62.98 rows=1358 width=14) (actual time=0.073..0.360 rows=1371.00 loops=1)
   Index Cond: ((created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (created_at < '2025-06-02 00:00:00+00'::timestamp with time zone))
   Index Searches: 1
   Buffers: shared read=20
   I/O Timings: shared read=0.179

 Bitmap Heap Scan on orders  (cost=20.19..3267.31 rows=1148 width=14) (actual time=0.273..4.415 rows=1005.00 loops=1)
   Recheck Cond: ((customer_id >= 1000) AND (customer_id <= 1200))
   Heap Blocks: exact=1002
   Buffers: shared hit=59 read=947
   I/O Timings: shared read=0.901
   ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..19.91 rows=1148 width=0) (actual time=0.146..0.146 rows=1005.00 loops=1)
         Index Cond: ((customer_id >= 1000) AND (customer_id <= 1200))
         Index Searches: 1
         Buffers: shared hit=2 read=2
```

Both queries return ~1,000–1,400 rows, but:

| | `created_at` (correlation 0.9997) | `customer_id` (correlation 0.0005) |
|---|---|---|
| Where the rows live | ~15 consecutive heap pages | 1,002 different heap pages (one row each) |
| Plan | **Index Scan**: walk the index, fetch heap pages in index order | **Bitmap**: collect TIDs, sort by page, fetch each page once |
| Pages touched | **20** | **1,006** |
| Cost estimate | 62.98 | 3,267.31 |

`cost_index` interpolates heap I/O between "every row on a new random page" and "rows packed sequentially" using **correlation²**. Near 1, an index range scan is almost a sequential read; near 0, the planner switches to a bitmap so each heap page is read once and in physical order.

**`Heap Blocks: exact=1002`** says the bitmap held one bit per tuple (exact mode, it fit in `work_mem`). §6 shows what happens when it doesn't.

**Production lesson:** the same index on a time-ordered key is ~50× cheaper per row than on a random key. That's the physical reason behind "cluster/partition by the access pattern", UUIDv7 over v4 ([2.2 §1.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)), and `CLUSTER`/pg_repack for read-mostly tables.

---

## 5. Index Only Scan, the visibility map, and the VACUUM that didn't help 🧊

An index-only scan reads the heap only for pages **not** marked all-visible in the visibility map (VM). `Heap Fetches` counts those visits.

```sql
create table orders_vm as select * from orders;               -- scratch copy so the main table stays pristine
create index orders_vm_created on orders_vm (created_at);
vacuum (analyze) orders_vm;
select all_visible, all_frozen from pg_visibility_map_summary('orders_vm');     -- 9412 | 0
update orders_vm set note = 'touched' where created_at >= '2025-03-01' and created_at < '2025-03-08';  -- 9,600 rows
explain (analyze, buffers) select count(*) from orders_vm where created_at >= '2025-03-01' and created_at < '2025-03-15';
```

**Output 1: right after the update (PostgreSQL 18.6, one measured run):**

```text
 Aggregate  (cost=681.35..681.36 rows=1 width=8) (actual time=7.066..7.067 rows=1.00 loops=1)
   Buffers: shared hit=19259 read=25
   ->  Index Only Scan using orders_vm_created on orders_vm  (cost=0.42..631.18 rows=20070 width=0) (actual time=0.027..6.478 rows=19200.00 loops=1)
         Index Cond: ((created_at >= '2025-03-01 00:00:00+00'::timestamp with time zone) AND (created_at < '2025-03-15 00:00:00+00'::timestamp with time zone))
         Heap Fetches: 19300
         Index Searches: 1
         Buffers: shared hit=19259 read=25
```

`Heap Fetches: 19300` for 19,200 rows: the update dirtied the VM bits of the old pages and wrote new versions to pages that were never all-visible. The "index-only" scan touched **19,284 pages** for a count.

Now the obvious fix, a plain `VACUUM`:

```sql
vacuum (verbose) orders_vm;
```

```text
INFO:  finished vacuuming "atlas.public.orders_vm": index scans: 0
pages: 0 removed, 9510 remain, 218 scanned (2.29% of total), 0 eagerly scanned
tuples: 0 removed, 999338 remain, 0 are dead but not yet removable
visibility map: 99 pages set all-visible, 0 pages set all-frozen (0 were all-visible)
index scan bypassed: 116 pages from table (1.22% of total) have 9600 dead item identifiers
```

**Output 2: after plain `VACUUM` (one measured run):**

```text
 Aggregate  (cost=677.76..677.77 rows=1 width=8) (actual time=4.069..4.070 rows=1.00 loops=1)
   Buffers: shared hit=191
   ->  Index Only Scan using orders_vm_created on orders_vm  (cost=0.42..628.10 rows=19863 width=0) (actual time=0.012..3.464 rows=19200.00 loops=1)
         Heap Fetches: 6500
         Index Searches: 1
         Buffers: shared hit=191
```

Still **6,500 heap fetches**, and `pg_visibility_map` reports **116 pages not all-visible**. The `VERBOSE` line explains it: **`index scan bypassed: 116 pages … have 9600 dead item identifiers`**.

Since PostgreSQL 14, VACUUM skips the (expensive) index-vacuuming phase when fewer than ~2 % of heap pages have dead items (`BYPASS_THRESHOLD_PAGES` in `vacuumlazy.c`; `index_cleanup = auto` is the default). The dead **line pointers** (`LP_DEAD` stubs) stay on those 116 pages until a later VACUUM does index cleanup, and a page that still has `LP_DEAD` items **can't be marked all-visible**. Every index-only scan over those pages keeps visiting the heap.

```sql
vacuum (verbose, index_cleanup on) orders_vm;
```

```text
INFO:  finished vacuuming "atlas.public.orders_vm": index scans: 1
visibility map: 116 pages set all-visible, 90 pages set all-frozen (0 were all-visible)
index scan needed: 116 pages from table (1.22% of total) had 9600 dead item identifiers removed
```

**Output 3: after `INDEX_CLEANUP ON` (one measured run):**

```text
 Aggregate  (cost=671.34..671.35 rows=1 width=8) (actual time=1.705..1.706 rows=1.00 loops=1)
   Buffers: shared hit=83
   ->  Index Only Scan using orders_vm_created on orders_vm  (cost=0.42..621.68 rows=19863 width=0) (actual time=0.008..1.098 rows=19200.00 loops=1)
         Heap Fetches: 0
         Index Searches: 1
         Buffers: shared hit=83
```

| State | Heap Fetches | Buffers | Time |
|---|---:|---:|---:|
| After the update | 19,300 | 19,284 | 7.1 ms |
| After plain `VACUUM` (index cleanup bypassed) | 6,500 | 191 | 4.1 ms |
| After `VACUUM (INDEX_CLEANUP ON)` | **0** | **83** | **1.7 ms** |

**Staff-level takeaways:**
* The cost estimate (`621.68`–`631.18`) **barely moved** across the three states: the planner uses `relallvisible` from `pg_class`, updated only by VACUUM/ANALYZE. Estimates don't see heap fetches; `EXPLAIN ANALYZE` does.
* For tables whose hot queries depend on index-only scans (counts, covering indexes for APIs), schedule periodic `VACUUM (INDEX_CLEANUP ON)` or lower the update rate on those pages. Watch `Heap Fetches` in `auto_explain` output, not just latency.
* `VACUUM VERBOSE`'s last lines (`index scan bypassed` / `needed`) are the fastest way to explain "why isn't my index-only scan index-only?".

---

## 6. Bitmap scans: exact vs lossy, `BitmapOr` ⚡

### 6.1 Exact

```sql
explain (analyze, buffers) select count(*) from orders where status = 'PENDING' and total > 100;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Aggregate  (cost=11108.09..11108.10 rows=1 width=8) (actual time=31.995..31.996 rows=1.00 loops=1)
   Buffers: shared hit=1619 read=7949
   ->  Bitmap Heap Scan on orders  (cost=1043.85..11031.36 rows=30693 width=0) (actual time=4.235..30.729 rows=32080.00 loops=1)
         Recheck Cond: (status = 'PENDING'::text)
         Filter: (total > '100'::numeric)
         Rows Removed by Filter: 7920
         Heap Blocks: exact=9411
         Buffers: shared hit=1619 read=7949
         ->  Bitmap Index Scan on orders_status_created  (cost=0.00..1036.18 rows=38367 width=0) (actual time=3.241..3.241 rows=40000.00 loops=1)
               Index Cond: (status = 'PENDING'::text)
               Index Searches: 1
               Buffers: shared read=157
```

* **Two-phase execution:** the `Bitmap Index Scan` builds an in-memory TID bitmap (157 index pages, 40,000 TIDs) and returns *no rows* (`width=0`); the `Bitmap Heap Scan` then visits heap pages in physical order.
* `Recheck Cond` is printed always but only **executed** for lossy pages (§6.2) or index AMs that can return false positives (GIN, BRIN).
* `Filter: (total > '100')` wasn't in any index: 7,920 rows were removed after fetching. `Heap Blocks: exact=9411` = PENDING rows (4 %, evenly spread) live on **every** page of the table, so this "index" plan reads the whole heap. The planner knew (`cost 11031` vs seq scan `21912`): reading in page order is still cheaper than a seq scan because… it skips nothing here, but avoids evaluating the `total` filter on 960,000 rows.

### 6.2 Lossy: when the bitmap doesn't fit in `work_mem`

```sql
set work_mem = '64kB'; set enable_seqscan = off;     -- force the bitmap so it has to degrade
explain (analyze, buffers, settings) select count(*) from orders where status = 'PENDING' and total > 100;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Finalize Aggregate  (cost=17411.09..17411.10 rows=1 width=8) (actual time=70.621..78.165 rows=1.00 loops=1)
   Buffers: shared hit=9608
   ->  Gather  (cost=17410.87..17411.08 rows=2 width=8) (actual time=70.500..78.161 rows=3.00 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=9608
         ->  Partial Aggregate  (cost=16410.87..16410.88 rows=1 width=8) (actual time=27.572..27.573 rows=1.00 loops=3)
               Buffers: shared hit=9608
               ->  Parallel Bitmap Heap Scan on orders  (cost=1043.85..16378.90 rows=12789 width=0) (actual time=1.204..27.097 rows=10693.33 loops=3)
                     Recheck Cond: (status = 'PENDING'::text)
                     Rows Removed by Index Recheck: 297807
                     Filter: (total > '100'::numeric)
                     Rows Removed by Filter: 2640
                     Heap Blocks: exact=349 lossy=7778
                     Buffers: shared hit=9608
                     Worker 0:  Heap Blocks: exact=237 lossy=958
                     Worker 1:  Heap Blocks: exact=67 lossy=22
                     ->  Bitmap Index Scan on orders_status_created  (cost=0.00..1036.18 rows=38367 width=0) (actual time=1.602..1.602 rows=40000.00 loops=1)
                           Index Cond: (status = 'PENDING'::text)
                           Index Searches: 1
                           Buffers: shared hit=157
 Settings: work_mem = '64kB', jit = 'off', enable_seqscan = 'off'
 Planning Time: 0.103 ms
 Execution Time: 78.207 ms
```

* **`Heap Blocks: exact=349 lossy=7778`**: with only 64 kB, the bitmap gave up per-tuple bits for most pages and kept **one bit per page** ("lossy"). For a lossy page, every tuple on it must be **rechecked** against `status = 'PENDING'`: `Rows Removed by Index Recheck: 297807` is the waste.
* The **bitmap index scan ran once** (it isn't per-worker: the leader builds the shared bitmap) and the heap scan is split among 3 processes (`Parallel Bitmap Heap Scan`).
* Same rows, **2.4× slower** than §6.1, and twice the planner cost. In production you see this as high `Rows Removed by Index Recheck` on reporting queries with small `work_mem`.

### 6.3 `BitmapOr`: two indexes, one heap pass

```sql
explain (analyze, buffers) select id from orders where customer_id = 4242 or created_at >= '2025-12-29';
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Bitmap Heap Scan on orders  (cost=38.18..4334.73 rows=1666 width=8) (actual time=0.114..0.226 rows=1606.00 loops=1)
   Recheck Cond: ((customer_id = 4242) OR (created_at >= '2025-12-29 00:00:00+00'::timestamp with time zone))
   Heap Blocks: exact=25
   Buffers: shared hit=30 read=6
   ->  BitmapOr  (cost=38.18..38.18 rows=1666 width=0) (actual time=0.102..0.102 rows=0.00 loops=1)
         Buffers: shared hit=5 read=6
         ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..4.46 rows=5 width=0) (actual time=0.023..0.023 rows=5.00 loops=1)
               Index Cond: (customer_id = 4242)
               Index Searches: 1
         ->  Bitmap Index Scan on orders_created_at  (cost=0.00..32.88 rows=1661 width=0) (actual time=0.079..0.079 rows=1601.00 loops=1)
               Index Cond: (created_at >= '2025-12-29 00:00:00+00'::timestamp with time zone)
               Index Searches: 1
```

An `OR` across **different** columns can only use indexes through bitmaps: each index produces a bitmap, `BitmapOr` unions them (`BitmapAnd` intersects for `AND`), and the heap is read once. `rows=0.00` on `BitmapOr` is normal: bitmap nodes pass a bitmap, not rows. If either column had **no** index, the whole `OR` would fall back to a seq scan, which is the classic reason to rewrite as `UNION ALL` of two indexed queries.

---

## 7. PostgreSQL 18 index features you can see in a plan 🧊

### 7.1 Skip scan: a composite index used without its leading column

```sql
begin;
drop index orders_created_at;       -- only (status, created_at) is left
explain (analyze, buffers) select count(*) from orders where created_at >= '2025-12-01';
rollback;                           -- DDL is transactional in PostgreSQL: the index is back
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Aggregate  (cost=1638.74..1638.75 rows=1 width=8) (actual time=6.256..6.257 rows=1.00 loops=1)
   Buffers: shared hit=19 read=196
   ->  Index Only Scan using orders_status_created on orders  (cost=0.42..1534.66 rows=41631 width=0) (actual time=0.262..4.871 rows=40001.00 loops=1)
         Index Cond: (created_at >= '2025-12-01 00:00:00+00'::timestamp with time zone)
         Heap Fetches: 0
         Index Searches: 5
         Buffers: shared hit=19 read=196
```

`Index Cond` on the **second** column of `(status, created_at)` and **`Index Searches: 5`**: the scan descended once per distinct `status` value (4) plus one probe that found no further values. Before PG 18 this needed a full index scan or a seq scan. Skip scan pays off when the skipped leading column has **few distinct values**; with 100,000 distinct values it would be 100,000 descents and the planner won't choose it. ([2.2 §2.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md) covers the costing.)

### 7.2 `IN` lists: one descent per value

```sql
explain (analyze, buffers) select count(*) from orders where customer_id in (17, 4242, 99999, 123456);
```

```text
 Aggregate  (cost=18.10..18.11 rows=1 width=8) (actual time=0.263..0.263 rows=1.00 loops=1)
   Buffers: shared hit=9 read=4
   ->  Index Only Scan using orders_customer_id on orders  (cost=0.42..18.05 rows=20 width=0) (actual time=0.189..0.259 rows=20.00 loops=1)
         Index Cond: (customer_id = ANY ('{17,4242,99999,123456}'::bigint[]))
         Heap Fetches: 0
         Index Searches: 4
         Buffers: shared hit=9 read=4
```

`Index Searches` (new in PG 18) finally shows what a `= ANY` costs: 4 values, 4 descents. With a 5,000-element list from an ORM's `IN (:ids)`, you'll see `Index Searches: 5000`; whether that's fine depends on the buffers per search.

### 7.3 `OR` of equalities becomes `= ANY`

```sql
explain select id from orders where customer_id = 17 or customer_id = 4242 or customer_id = 99999;
```

```text
 Bitmap Heap Scan on orders  (cost=13.39..71.86 rows=15 width=8)
   Recheck Cond: ((customer_id = 17) OR (customer_id = 4242) OR (customer_id = 99999))
   ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..13.39 rows=15 width=0)
         Index Cond: (customer_id = ANY ('{17,4242,99999}'::integer[]))
```

PostgreSQL 18 transforms an `OR` of equalities on the same indexed column into one `= ANY` index condition (one bitmap index scan instead of three plus a `BitmapOr`). The recheck keeps the original `OR`.

---

## 8. Sort nodes: top-N, quicksort, external merge, incremental ⚡

```sql
set max_parallel_workers_per_gather = 0;
explain (analyze, buffers) select id, total from orders order by total desc limit 10;               -- 8.1
explain (analyze, buffers) select id, total from orders where customer_id < 5000 order by total;   -- 8.2
explain (analyze, buffers) select id, total from orders order by total, id;                         -- 8.3
explain (analyze, buffers) select id, created_at, total from orders
where created_at >= '2025-06-01' order by created_at, total limit 1000;                                -- 8.4
```

**Output 8.1: top-N heapsort (one measured run):**

```text
 Limit  (cost=41021.64..41021.67 rows=10 width=14) (actual time=164.011..164.013 rows=10.00 loops=1)
   Buffers: shared hit=9412
   ->  Sort  (cost=41021.64..43521.64 rows=1000000 width=14) (actual time=164.005..164.006 rows=10.00 loops=1)
         Sort Key: total DESC
         Sort Method: top-N heapsort  Memory: 25kB
         Buffers: shared hit=9412
         ->  Seq Scan on orders  (cost=0.00..19412.00 rows=1000000 width=14) (actual time=0.009..74.681 rows=1000000.00 loops=1)
               Buffers: shared hit=9412
```

**Output 8.2: in-memory quicksort (one measured run):**

```text
 Sort  (cost=12029.10..12094.88 rows=26313 width=14) (actual time=16.771..17.358 rows=24995.00 loops=1)
   Sort Key: total
   Sort Method: quicksort  Memory: 1550kB
   Buffers: shared hit=9418 read=32
   ->  Bitmap Heap Scan on orders  (cost=356.35..10097.26 rows=26313 width=14) (actual time=2.601..10.786 rows=24995.00 loops=1)
         Recheck Cond: (customer_id < 5000)
         Heap Blocks: exact=9412
         ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..349.77 rows=26313 width=0) (actual time=1.609..1.609 rows=24995.00 loops=1)
               Index Cond: (customer_id < 5000)
               Index Searches: 1
```

**Output 8.3: external merge (one measured run):**

```text
 Sort  (cost=136160.34..138660.34 rows=1000000 width=14) (actual time=345.716..574.343 rows=1000000.00 loops=1)
   Sort Key: total, id
   Sort Method: external merge  Disk: 24544kB
   Buffers: shared hit=9412, temp read=3068 written=3082
   I/O Timings: temp read=8.918 write=17.661
   ->  Seq Scan on orders  (cost=0.00..19412.00 rows=1000000 width=14) (actual time=0.009..69.119 rows=1000000.00 loops=1)
         Buffers: shared hit=9412
```

**Output 8.4: incremental sort (one measured run):**

```text
 Limit  (cost=0.47..83.46 rows=1000 width=22) (actual time=0.030..0.278 rows=1000.00 loops=1)
   Buffers: shared hit=15
   ->  Incremental Sort  (cost=0.47..24333.03 rows=293218 width=22) (actual time=0.030..0.244 rows=1000.00 loops=1)
         Sort Key: created_at, total
         Presorted Key: created_at
         Full-sort Groups: 32  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
         Buffers: shared hit=15
         ->  Index Scan using orders_created_at on orders  (cost=0.42..11138.22 rows=293218 width=22) (actual time=0.015..0.141 rows=1001.00 loops=1)
               Index Cond: (created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone)
               Index Searches: 1
               Buffers: shared hit=15
```

| Sort method | When | What the plan tells you |
|---|---|---|
| `top-N heapsort  Memory: 25kB` | `ORDER BY … LIMIT n` with small n | Keeps only n rows in a bounded heap: O(N log n) and tiny memory, **but it still reads all 1 M rows** (`Seq Scan … rows=1000000`, 164 ms). An index on `total` would make it ~0.1 ms |
| `quicksort  Memory: 1550kB` | Input fits in `work_mem` | Everything in memory |
| `external merge  Disk: 24544kB` | Input exceeds `work_mem` | Sorted runs written to temp files, then merged: `temp read=3068 written=3082` blocks (24 MB). Startup cost is high: **no row can be returned until the whole input is sorted** (`actual time=345.716..` for the first row) |
| `Incremental Sort … Presorted Key: created_at` | Input already sorted by a prefix of the sort key | Sorts small groups that share `created_at` (32 groups for 1,000 rows), streams them, and **stops early under `LIMIT`**: 15 buffers, 0.3 ms instead of sorting 293,218 rows |

Note how startup cost tells the story: `Sort` has startup ≈ total (`136160..138660`), `Incremental Sort` starts at `0.47`. A plan whose top node has a high **startup** cost can't stream: that's what makes a `LIMIT` or a cursor-based reader (JDBC fetch size) slow to return the first page.

---

## 9. Aggregation: HashAggregate, GroupAggregate, Partial ⚡

### 9.1 HashAggregate that fits

```sql
explain (analyze, buffers) select status, count(*), sum(total) from orders group by status;
```

```text
 HashAggregate  (cost=26912.00..26912.05 rows=4 width=49) (actual time=201.873..201.884 rows=4.00 loops=1)
   Group Key: status
   Batches: 1  Memory Usage: 32kB
   Buffers: shared hit=9412
   ->  Seq Scan on orders  (cost=0.00..19412.00 rows=1000000 width=15) (actual time=0.010..35.100 rows=1000000.00 loops=1)
         Buffers: shared hit=9412
```

4 groups, 32 kB, `Batches: 1`. The 200 ms is the aggregation work itself (1 M `numeric` additions); the scan took 35 ms.

### 9.2 HashAggregate that spills

```sql
set work_mem = '1MB'; set enable_indexscan = off; set enable_indexonlyscan = off; set enable_bitmapscan = off;
explain (analyze, buffers, settings) select customer_id, count(*), sum(total) from orders group by customer_id;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 HashAggregate  (cost=85974.50..98206.02 rows=197272 width=48) (actual time=284.164..540.916 rows=200000.00 loops=1)
   Group Key: customer_id
   Planned Partitions: 32  Batches: 161  Memory Usage: 2105kB  Disk Usage: 62536kB
   Buffers: shared hit=9412, temp read=5311 written=12919
   I/O Timings: temp read=17.212 write=69.776
   ->  Seq Scan on orders  (cost=0.00..19412.00 rows=1000000 width=14) (actual time=0.009..35.424 rows=1000000.00 loops=1)
         Buffers: shared hit=9412
 Settings: work_mem = '1MB', jit = 'off', max_parallel_workers_per_gather = '0', enable_indexscan = 'off', enable_indexonlyscan = 'off', enable_bitmapscan = 'off'
 Planning Time: 0.080 ms
 Execution Time: 560.755 ms
```

* **`Planned Partitions: 32`**: at plan time the planner already expected 200,000 groups not to fit, and planned to partition spilled groups 32 ways.
* **`Batches: 161`**: at run time, partitions themselves overflowed and were re-partitioned recursively (since PG 13 HashAggregate spills instead of exceeding memory).
* **`Memory Usage: 2105kB`** exceeds `work_mem = 1MB` because the limit for hash nodes is `work_mem × hash_mem_multiplier` (default **2.0**).
* `Disk Usage: 62536kB` and `temp written=12919` (≈ 101 MB written; spilled data is written, read back and partly re-written). Before PG 13, this query would have grown the hash table without bound and could OOM.

### 9.3 The plan the optimizer *preferred*: GroupAggregate over an uncorrelated index

```sql
explain (analyze, buffers) select customer_id, count(*), sum(total) from orders group by customer_id;   -- default settings
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 GroupAggregate  (cost=0.42..68318.32 rows=197272 width=48) (actual time=0.032..739.288 rows=200000.00 loops=1)
   Group Key: customer_id
   Buffers: shared hit=1000039 read=1381
   I/O Timings: shared read=14.079
   ->  Index Scan using orders_customer_id on orders  (cost=0.42..58352.42 rows=1000000 width=14) (actual time=0.019..519.071 rows=1000000.00 loops=1)
         Index Searches: 1
         Buffers: shared hit=1000039 read=1381
```

With the default 4 MB `work_mem`, the planner priced a spilling hash aggregate above a **GroupAggregate fed by a full index scan** (rows come out sorted by `customer_id`, so no sort and no hash table). The cost: **1,001,420 buffer touches**, because `customer_id` has correlation 0.0005, so almost every row is on a different heap page than the previous one. It took 744 ms, slower than the spilling hash aggregate (561 ms). [2.11 P6](11-Plan-Pathologies-Diagnosis-Playbook.md#p6-a-full-table-aggregate-that-walks-an-uncorrelated-index-) shows the two fixes (per-query `work_mem`, or a covering index) with their plans.

**How to spot it in any plan:** an `Index Scan` (not Index *Only*) with **buffers ≈ rows**. The index is being used to provide order, and the heap is being read randomly.

### 9.4 GroupAggregate done right: sorted input from an index-only scan

```sql
explain (analyze, buffers) select customer_id, count(*) from orders where customer_id between 1 and 50000 group by customer_id order by customer_id;
```

```text
 GroupAggregate  (cost=0.42..9212.67 rows=151562 width=16) (actual time=0.013..28.815 rows=50000.00 loops=1)
   Group Key: customer_id
   Buffers: shared hit=358
   ->  Index Only Scan using orders_customer_id on orders  (cost=0.42..6444.12 rows=250585 width=8) (actual time=0.009..11.730 rows=250000.00 loops=1)
         Index Cond: ((customer_id >= 1) AND (customer_id <= 50000))
         Heap Fetches: 0
         Index Searches: 1
         Buffers: shared hit=358
```

Same node, healthy: 250,000 rows from **358 pages** (index only, no heap), streamed in key order, no memory. Also note the estimate `rows=151562` vs 50,000 actual groups: `n_distinct` for `customer_id` is a *sample* estimate, and the range predicate's group count is extrapolated. Harmless here; inside a bigger query it would size the next hash table 3× too big.

### 9.5 Parallel aggregation: Partial HashAggregate + Gather Merge + Finalize GroupAggregate

```sql
explain (analyze, buffers) select status, count(*) from orders group by status;    -- parallelism allowed
```

```text
 Finalize GroupAggregate  (cost=16662.11..16663.36 rows=4 width=17) (actual time=169.277..175.581 rows=4.00 loops=1)
   Group Key: status
   Buffers: shared hit=9428
   ->  Gather Merge  (cost=16662.11..16663.27 rows=10 width=17) (actual time=169.268..175.571 rows=8.00 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=9428
         ->  Sort  (cost=15662.08..15662.09 rows=4 width=17) (actual time=55.066..55.067 rows=2.67 loops=3)
               Sort Key: status
               Sort Method: quicksort  Memory: 25kB
               Worker 0:  Sort Method: quicksort  Memory: 25kB
               Worker 1:  Sort Method: quicksort  Memory: 25kB
               ->  Partial HashAggregate  (cost=15662.00..15662.04 rows=4 width=17) (actual time=55.043..55.044 rows=2.67 loops=3)
                     Group Key: status
                     Batches: 1  Memory Usage: 32kB
                     Worker 0:  Batches: 1  Memory Usage: 32kB
                     Worker 1:  Batches: 1  Memory Usage: 32kB
                     ->  Parallel Seq Scan on orders  (cost=0.00..13578.67 rows=416667 width=9) (actual time=0.006..12.835 rows=333333.33 loops=3)
                           Buffers: shared hit=9412
```

Each process pre-aggregates its third of the table (`Partial HashAggregate`, 4 groups each), sorts its tiny result, `Gather Merge` merges the 3 sorted streams (8 rows arrived: not every process saw every status in its share), and `Finalize GroupAggregate` combines partial counts. Note `rows=416667` estimate per worker = 1,000,000 ÷ 2.4, the same divisor as §2.

---

## 10. Nodes that keep state: WindowAgg, Memoize, CTE Scan ⚡

### 10.1 WindowAgg (with PG 18's `Storage` line)

```sql
explain (analyze, buffers) select id, customer_id, row_number() over (partition by customer_id order by created_at)
from orders where customer_id between 1 and 2000;
```

```text
 WindowAgg  (cost=11000.29..11224.79 rows=11225 width=32) (actual time=8.978..10.933 rows=10000.00 loops=1)
   Window: w1 AS (PARTITION BY customer_id ORDER BY created_at ROWS UNBOUNDED PRECEDING)
   Storage: Memory  Maximum Storage: 17kB
   Buffers: shared hit=9347
   ->  Sort  (cost=11000.29..11028.35 rows=11225 width=24) (actual time=8.966..9.216 rows=10000.00 loops=1)
         Sort Key: customer_id, created_at
         Sort Method: quicksort  Memory: 775kB
         ->  Bitmap Heap Scan on orders  (cost=183.48..10245.16 rows=11225 width=24) (actual time=1.708..7.225 rows=10000.00 loops=1)
               Recheck Cond: ((customer_id >= 1) AND (customer_id <= 2000))
               Heap Blocks: exact=9330
               ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..180.68 rows=11225 width=0) (actual time=0.831..0.832 rows=10000.00 loops=1)
```

* The window definition is printed with the **effective frame**: `ROWS UNBOUNDED PRECEDING`. For `row_number()` the planner rewrote the default `RANGE` frame to the cheaper `ROWS` frame (PG 16+), because the result is the same. For `sum() over (order by …)` it can't, and peer rows matter ([2.4 §1.2](04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)).
* `Storage: Memory  Maximum Storage: 17kB`: the tuplestore holding the current partition (PG 18). A window over a huge partition shows `Storage: Disk`.
* The window needs input sorted by `(customer_id, created_at)`; the `Sort` provides it. An index on `(customer_id, created_at)` would remove the sort and the 9,330 random heap pages.

### 10.2 Memoize: caching the inner side of a nested loop

```sql
set enable_hashjoin = off; set enable_mergejoin = off;      -- the planner prefers a hash join here; force the nested loop to show Memoize
explain (analyze, buffers, settings) select p.category, sum(ol.qty) from order_lines ol join products p on p.id = ol.product_id
where ol.order_id between 1 and 20000 group by p.category;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 HashAggregate  (cost=35253.63..35254.13 rows=50 width=14) (actual time=56.339..56.344 rows=50.00 loops=1)
   Group Key: p.category
   Batches: 1  Memory Usage: 32kB
   ->  Nested Loop  (cost=1542.19..34954.38 rows=59850 width=10) (actual time=3.480..48.184 rows=60000.00 loops=1)
         ->  Bitmap Heap Scan on order_lines ol  (cost=1541.89..27439.64 rows=59850 width=12) (actual time=3.300..7.577 rows=60000.00 loops=1)
               Recheck Cond: ((order_id >= 1) AND (order_id <= 20000))
               Heap Blocks: exact=500
               ->  Bitmap Index Scan on order_lines_pkey  (cost=0.00..1526.93 rows=59850 width=0) (actual time=3.212..3.212 rows=60000.00 loops=1)
                     Index Cond: ((order_id >= 1) AND (order_id <= 20000))
         ->  Memoize  (cost=0.30..0.33 rows=1 width=14) (actual time=0.001..0.001 rows=1.00 loops=60000)
               Cache Key: ol.product_id
               Cache Mode: logical
               Hits: 40000  Misses: 20000  Evictions: 0  Overflows: 0  Memory Usage: 2344kB
               ->  Index Scan using products_pkey on products p  (cost=0.29..0.32 rows=1 width=14) (actual time=0.001..0.001 rows=1.00 loops=20000)
                     Index Cond: (id = ol.product_id)
                     Index Searches: 20000
 Settings: jit = 'off', max_parallel_workers_per_gather = '0', enable_hashjoin = 'off', enable_mergejoin = 'off'
```

* `Memoize` sits between the nested loop and its inner index scan and caches results **per `product_id`**. `loops=60000` on Memoize but `loops=20000` on the index scan: **40,000 probes were answered from the cache**.
* `Hits/Misses/Evictions/Overflows`: evictions mean the cache (bounded by `work_mem × hash_mem_multiplier`) was too small for the number of distinct keys; then the hit rate collapses.
* The planner chooses Memoize when its estimate of distinct inner keys (from `n_distinct`) is low relative to outer rows. A bad `n_distinct` estimate can make Memoize thrash; `enable_memoize = off` is the escape hatch while you fix the statistics.

### 10.3 CTE Scan over a `MATERIALIZED` CTE

```sql
explain (analyze, buffers) with recent as materialized (select * from orders where created_at >= '2025-12-20')
select count(*) from recent r1 join recent r2 on r2.customer_id = r1.customer_id;
```

```text
 Aggregate  (cost=2354.36..2354.37 rows=1 width=8) (actual time=6.828..6.829 rows=1.00 loops=1)
   CTE recent
     ->  Index Scan using orders_created_at on orders  (cost=0.42..570.72 rows=14314 width=94) (actual time=0.046..1.516 rows=13943.00 loops=1)
           Index Cond: (created_at >= '2025-12-20 00:00:00+00'::timestamp with time zone)
   ->  Hash Join  (cost=465.21..1602.26 rows=72553 width=0) (actual time=4.213..6.409 rows=13943.00 loops=1)
         Hash Cond: (r1.customer_id = r2.customer_id)
         ->  CTE Scan on recent r1  (cost=0.00..286.28 rows=14314 width=8) (actual time=0.047..0.606 rows=13943.00 loops=1)
               Storage: Memory  Maximum Storage: 1114kB
         ->  Hash  (cost=286.28..286.28 rows=14314 width=8) (actual time=4.127..4.127 rows=13943.00 loops=1)
               Buckets: 16384  Batches: 1  Memory Usage: 673kB
               ->  CTE Scan on recent r2  (cost=0.00..286.28 rows=14314 width=8) (actual time=0.001..3.046 rows=13943.00 loops=1)
                     Storage: Memory  Maximum Storage: 1114kB
```

* The CTE is evaluated **once** (the `CTE recent` sub-plan) and stored in a tuplestore (`Storage: Memory  Maximum Storage: 1114kB`), then read by two `CTE Scan`s. Referenced twice, a CTE is materialized even without the keyword.
* The join estimate is off by 5× (`72553` vs `13943`): **a CTE Scan has no statistics** beyond row count, so the planner assumes default selectivities for joins on its columns. Materialized CTEs are "statistics black boxes"; inlined CTEs aren't ([2.3 §6](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md)).

---

## 11. ❌ Naïve vs ✅ production-hardened plan reading

| ❌ Naïve | ✅ Hardened |
|---|---|
| Reads `actual time` of the top node only | Computes **exclusive** time per node (time − children, × loops) |
| Treats `rows=` as total | Knows both estimate and actual are **per loop**; multiplies by `loops` |
| "Buffers read = disk reads" | Checks `I/O Timings`: thousands of reads in under a millisecond = OS page cache |
| Shares plans without `SETTINGS` | `EXPLAIN (ANALYZE, BUFFERS, SETTINGS)`; adds `VERBOSE` for parallel plans |
| "Index Only Scan = no heap access" | Checks `Heap Fetches`; checks `VACUUM VERBOSE` for `index scan bypassed` |
| Sees `Index Scan` and relaxes | Compares buffers to rows: buffers ≈ rows on a heap-reading index scan = random I/O per row |
| Ignores `Workers Launched` | Compares with `Workers Planned`; checks per-worker split with `VERBOSE` |
| Raises `work_mem` globally after seeing `Disk:` | Raises it per transaction/role for the reporting query; checks `hash_mem_multiplier` |

---

## 12. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/optimizer/path/costsize.c` | `cost_seqscan`, `cost_index` (correlation² interpolation), `get_parallel_divisor`, `cost_sort` |
| postgres/postgres | `src/backend/utils/adt/selfuncs.c` | `btcostestimate`: the descent cost reproduced in §3 |
| postgres/postgres | `src/backend/commands/explain.c` | Where every line of `EXPLAIN` output is produced (`show_buffer_usage`, `show_hashagg_info`, `show_memoize_info`) |
| postgres/postgres | `src/backend/access/heap/vacuumlazy.c` | `BYPASS_THRESHOLD_PAGES` and the "index scan bypassed" decision in §5 |
| postgres/postgres | `src/backend/nodes/tidbitmap.c` | Exact vs lossy bitmap pages (§6.2) |
| postgres/postgres | `src/backend/executor/nodeAgg.c` | HashAggregate spilling: partitions, batches, `hash_mem_multiplier` |

---

## 13. Interview soundbites

* "A seq scan costs `relpages × seq_page_cost + reltuples × (cpu_tuple_cost + cpu_operator_cost × quals)`. I reproduced 21,912 exactly; when the number surprises you, check `relpages` for bloat."
* "In a parallel seq scan, I/O cost isn't divided but CPU cost is divided by 2.4 for two workers, because the leader counts as 0.4."
* "`Heap Fetches` on an index-only scan is the visibility map talking. A plain VACUUM can bypass index cleanup when under 2 % of pages have dead items, and those pages stay not-all-visible: `VACUUM (INDEX_CLEANUP ON)` took heap fetches from 6,500 to 0."
* "An `Index Scan` with buffers roughly equal to rows means random heap I/O per row. On an uncorrelated column that's often worse than a hash aggregate that spills."
* "`Heap Blocks: lossy` and `Rows Removed by Index Recheck` mean the bitmap didn't fit in `work_mem`."
* "PG 18 shows `Index Searches`: skip scan descended 5 times for 4 statuses; an `IN` list of 4 values descended 4 times."

---

## Summary

| Node / line | One-line meaning | Verified number in this file |
|---|---|---|
| Seq Scan cost | `pages × 1.0 + rows × (0.01 + 0.0025 × quals)` | 21,912 reproduced exactly |
| Parallel Seq Scan cost | I/O undivided, CPU ÷ (workers + 1 − 0.3 × workers) | 14,620.33 reproduced exactly; leader did 82 % of pages |
| Index Scan (pk) | Descent + leaf page + heap page | 0.425 + 4 + 0.0075 + 4 + 0.01 = 8.4425 (`8.44`) |
| Correlation | Index Scan when ≈ 1, Bitmap when ≈ 0 | 20 pages vs 1,006 pages for ~1,000 rows |
| Index Only Scan | Heap fetches for pages not all-visible | 19,300 → 6,500 (VACUUM bypassed index cleanup) → 0 |
| Bitmap Heap Scan | exact = 1 bit per tuple; lossy = 1 bit per page + recheck | lossy=7,778 pages, 297,807 rows rechecked at 64 kB |
| Skip scan (PG 18) | Composite index without its leading column | `Index Searches: 5` for 4 statuses |
| Sorts | top-N heapsort / quicksort / external merge / incremental | external merge spilled 24 MB; incremental sort 15 buffers vs full sort |
| HashAggregate spill | Partitions + batches; limit = `work_mem × hash_mem_multiplier` | 32 planned partitions, 161 batches, 62 MB disk |
| GroupAggregate via Index Scan | Order from an uncorrelated index = random I/O | 1,001,420 buffers, slower than the spilling hash |
| Memoize | Cache for a nested loop's inner side | 40,000 hits / 20,000 misses |
| CTE Scan | Materialized once, no statistics for joins | estimate 72,553 vs actual 13,943 |

**Next:** [2.10 EXPLAIN Atlas Part 2: joins, subqueries, partitions, DML →](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md)
