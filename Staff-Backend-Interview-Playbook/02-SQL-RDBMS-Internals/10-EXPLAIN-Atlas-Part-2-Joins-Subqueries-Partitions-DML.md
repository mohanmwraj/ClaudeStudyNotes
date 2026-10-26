# 2.10 EXPLAIN Atlas, Part 2: Joins, Subqueries, Partitions, DML and the Newer `EXPLAIN` Options

> **Verified stack:** PostgreSQL **18.6**, the `atlas` database from [2.9 §0.2](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#02-the-dataset-run-it-yourself) (same settings). Unless a section says otherwise, the session ran with `max_parallel_workers_per_gather = 0` so that join mechanics aren't hidden behind `Gather` nodes. DML examples use scratch tables and `BEGIN … ROLLBACK`, so the dataset stays reproducible.
>
> **Evidence rule:** plans are complete outputs from one sequential capture on a fresh load. Shapes, row counts, `loops`, `Batches`, WAL record counts and cost estimates reproduce on the same dataset; times and `hit`/`read` splits vary.

---

## 0. First principles: a join is a choice of *who drives* and *how the other side is found* 🔥

Every two-input join node has an **outer** (first child, drives the loop) and an **inner** input (second child). The three algorithms differ only in how they find inner rows for each outer row:

| Algorithm | How the inner side is found | Needs | Startup | Fails when |
|---|---|---|---|---|
| Nested Loop | Re-run the inner plan once per outer row (`loops = outer rows`) | Cheap inner lookup (index), or tiny inner | Immediate | Outer is underestimated |
| Hash Join | Build a hash table on the inner (`Hash` node), probe it with each outer row | Equality condition, memory | After the build | Inner bigger than `work_mem × hash_mem_multiplier` (batches) |
| Merge Join | Walk both inputs in key order simultaneously | Both sides sorted (index or `Sort`) | Immediate if pre-sorted | Large explicit sorts |

Plan-reading shortcut: in a `Hash Join`, the input under `Hash` is the **build side**. The planner wants the smaller input there.

---

## 1. Nested Loop: loops are multiplication 🔥

```sql
set max_parallel_workers_per_gather = 0;
explain (analyze, buffers) select c.email, o.id, o.total from customers c join orders o on o.customer_id = c.id where c.id between 1000 and 1009;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Nested Loop  (cost=4.88..226.67 rows=45 width=36) (actual time=0.084..0.295 rows=50.00 loops=1)
   Buffers: shared hit=85 read=2
   ->  Index Scan using customers_pkey on customers c  (cost=0.42..8.60 rows=9 width=30) (actual time=0.050..0.052 rows=10.00 loops=1)
         Index Cond: ((id >= 1000) AND (id <= 1009))
         Index Searches: 1
         Buffers: shared hit=5 read=2
   ->  Bitmap Heap Scan on orders o  (cost=4.46..24.18 rows=5 width=22) (actual time=0.009..0.021 rows=5.00 loops=10)
         Recheck Cond: (c.id = customer_id)
         Heap Blocks: exact=50
         Buffers: shared hit=80
         ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..4.46 rows=5 width=0) (actual time=0.003..0.003 rows=5.00 loops=10)
               Index Cond: (customer_id = c.id)
               Index Searches: 10
               Buffers: shared hit=30
 Planning:
   Buffers: shared hit=310 read=9 dirtied=1
 Planning Time: 7.129 ms
 Execution Time: 0.351 ms
```

**Line by line:**

* Outer: 10 customers (estimated 9). Inner: the bitmap scan ran **`loops=10`**, once per customer, each returning 5 rows (`rows=5.00` is per loop): 10 × 5 = **50** rows out of the join.
* `Recheck Cond: (c.id = customer_id)`: a **parameterized** inner scan. `c.id` comes from the current outer row. That's what makes a nested loop with an indexed inner side cheap: each loop is one index probe.
* `Index Searches: 10` on the inner index = 10 descents. `Buffers: shared hit=80` on the inner side is the **total across all loops** (unlike `rows`, buffer counts are never averaged).
* Cost: `226.67 ≈ 8.60 (outer) + 9 × 24.18 (inner per loop) + join CPU`. When the outer estimate is wrong by 1,000×, so is this multiplication. That's [2.11 P3/P4](11-Plan-Pathologies-Diagnosis-Playbook.md).
* `Planning Time: 7.129 ms` > `Execution Time: 0.351 ms`: normal for a cold catalog cache on the first query of a session, and the reason OLTP apps use prepared statements.

---

## 2. Hash Join: the build side, buckets and batches 🔥

### 2.1 In memory

```sql
explain (analyze, buffers) select c.country, count(*), sum(o.total)
from orders o join customers c on c.id = o.customer_id where o.created_at >= '2025-10-01' group by c.country;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 HashAggregate  (cost=14251.44..14251.69 rows=20 width=43) (actual time=106.899..106.906 rows=20.00 loops=1)
   Group Key: c.country
   Batches: 1  Memory Usage: 32kB
   Buffers: shared hit=1498 read=2170
   ->  Hash Join  (cost=6414.11..13301.16 rows=126705 width=9) (actual time=33.621..88.931 rows=123658.00 loops=1)
         Hash Cond: (c.id = o.customer_id)
         Buffers: shared hit=1498 read=2170
         ->  Seq Scan on customers c  (cost=0.00..3870.00 rows=200000 width=11) (actual time=0.070..9.989 rows=200000.00 loops=1)
               Buffers: shared hit=1 read=1869
         ->  Hash  (cost=4830.29..4830.29 rows=126705 width=14) (actual time=33.372..33.373 rows=123658.00 loops=1)
               Buckets: 131072  Batches: 1  Memory Usage: 6821kB
               Buffers: shared hit=1497 read=301
               ->  Index Scan using orders_created_at on orders o  (cost=0.42..4830.29 rows=126705 width=14) (actual time=0.056..20.324 rows=123658.00 loops=1)
                     Index Cond: (created_at >= '2025-10-01 00:00:00+00'::timestamp with time zone)
                     Index Searches: 1
```

* The planner put the **123,658 recent orders** (estimated 126,705) on the build side and streamed **200,000 customers** through as the probe side: the build side is chosen by estimated size × width, not by which table is "the parent".
* `Hash … actual time=33.372..33.373`: the join can't emit anything until the build completes (the Hash Join's own `actual time` starts at 33.6 ms).
* `Buckets: 131072  Batches: 1  Memory Usage: 6821kB`: buckets are a power of two ≥ the expected rows; `Batches: 1` = fit in memory.
* **If the outer (probe) side is empty, the hash table is never built, so the inner side never runs.** We hit this by accident in this batch: `select * from pg_create_logical_replication_slot('cdc_demo', 'test_decoding') s join pg_replication_slots r using (slot_name)` returned 0 rows and **didn't create the slot**. The plan shows why, and a sequence proves the function was never called:

  ```sql
  create sequence side_effect_seq;
  explain (analyze, costs off, timing off, summary off)
  select * from (select nextval('side_effect_seq') as v) a join pg_replication_slots r on r.slot_name = a.v::text;
  select last_value, is_called from side_effect_seq;
  ```

  ```text
   Nested Loop Left Join (actual rows=0.00 loops=1)
     ->  Hash Join (actual rows=0.00 loops=1)
           Hash Cond: (l.slot_name = (((nextval('side_effect_seq'::regclass)))::text)::text)
           ->  Function Scan on pg_get_replication_slots l (actual rows=0.00 loops=1)
           ->  Hash (never executed)
                 ->  Result (never executed)
     ->  Seq Scan on pg_database d (never executed)

   last_value | is_called
  ------------+-----------
            1 | f
  ```

  The side-effecting expression sat on the **build** side. The executor fetches the first outer row before building the hash table (when that's cheap), found the slot view **empty**, and finished without ever executing the `Hash` subtree (`nodeHashjoin.c`: "outer relation is empty, skip building hash table"). `nextval()` was never called. Never rely on a query's join shape to execute a function with side effects; call it in its own statement ([2.5 §2.3](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md#23-verified-what-a-stale-logical-replication-slot-actually-blocks-) redoes the slot experiment that way).

### 2.2 Spilled to disk

```sql
set work_mem = '256kB';
explain (analyze, buffers, settings) select c.country, count(*), sum(o.total)
from orders o join customers c on c.id = o.customer_id where o.created_at >= '2025-10-01' group by c.country;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 HashAggregate  (cost=15675.19..15675.44 rows=20 width=43) (actual time=736.726..736.753 rows=20.00 loops=1)
   Group Key: c.country
   Batches: 1  Memory Usage: 32kB
   Buffers: shared hit=3668, temp read=1404 written=1404
   I/O Timings: temp read=5.686 write=16.929
   ->  Hash Join  (cost=7347.43..14724.90 rows=126705 width=9) (actual time=66.889..715.956 rows=123658.00 loops=1)
         Hash Cond: (o.customer_id = c.id)
         Buffers: shared hit=3668, temp read=1404 written=1404
         ->  Index Scan using orders_created_at on orders o  (cost=0.42..4830.29 rows=126705 width=14) (actual time=0.018..16.144 rows=123658.00 loops=1)
               Index Cond: (created_at >= '2025-10-01 00:00:00+00'::timestamp with time zone)
               Index Searches: 1
               Buffers: shared hit=1798
         ->  Hash  (cost=3870.00..3870.00 rows=200000 width=11) (actual time=59.791..59.792 rows=200000.00 loops=1)
               Buckets: 16384  Batches: 32  Memory Usage: 424kB
               Buffers: shared hit=1870, temp written=834
               ->  Seq Scan on customers c  (cost=0.00..3870.00 rows=200000 width=11) (actual time=0.015..13.232 rows=200000.00 loops=1)
                     Buffers: shared hit=1870
 Settings: work_mem = '256kB', jit = 'off', max_parallel_workers_per_gather = '0'
 Execution Time: 736.869 ms
```

* **The sides flipped**: with less memory the planner hashed `customers` (narrower rows: width 11 vs 14) and probed with orders.
* **`Batches: 32`**: both inputs were partitioned by hash value into 32 batches; batch 0 stays in memory, the other 31 are written to temp files (`temp written=1404`) and joined one at a time. `Memory Usage: 424kB` is under `work_mem × hash_mem_multiplier` (256 kB × 2).
* Time went from **107 ms to 737 ms** for the same rows. A hash join that spills is the most common "why is the report 7× slower in production than on my laptop": production has more rows, the same `work_mem`.
* `Batches: 32` printed at the end can also be **larger than planned**: if the plan said fewer, the executor doubled batches at run time because the estimate was low (`Batches: 32 (originally 8)` is printed in that case).

---

## 3. Merge Join, and the predicate PostgreSQL doesn't copy 🧊

### 3.1 The plan the optimizer chose

```sql
explain (analyze, buffers) select count(*) from orders o join order_lines ol on ol.order_id = o.id where o.id <= 200000;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Aggregate  (cost=97827.61..97827.62 rows=1 width=8) (actual time=659.980..659.983 rows=1.00 loops=1)
   Buffers: shared hit=1116 read=24434, temp read=5462 written=5462
   ->  Hash Join  (cost=9181.94..96293.98 rows=613452 width=0) (actual time=37.071..641.038 rows=600000.00 loops=1)
         Hash Cond: (ol.order_id = o.id)
         Buffers: shared hit=1116 read=24434, temp read=5462 written=5462
         ->  Seq Scan on order_lines ol  (cost=0.00..55000.00 rows=3000000 width=8) (actual time=0.009..153.076 rows=3000000.00 loops=1)
               Buffers: shared hit=632 read=24368
         ->  Hash  (cost=5826.90..5826.90 rows=204484 width=8) (actual time=36.760..36.761 rows=200000.00 loops=1)
               Buckets: 262144  Batches: 2  Memory Usage: 5966kB
               Buffers: shared hit=484 read=66, temp written=340
               ->  Index Only Scan using orders_pkey on orders o  (cost=0.42..5826.90 rows=204484 width=8) (actual time=0.014..12.707 rows=200000.00 loops=1)
                     Index Cond: (id <= 200000)
                     Heap Fetches: 0
                     Index Searches: 1
```

The filter `o.id <= 200000` is applied to `orders`, but **`order_lines` is read in full: 3,000,000 rows, 25,000 pages**, to produce 600,000 matches, and the hash spilled to 2 batches.

**Why:** the planner builds *equivalence classes* from join equalities (`ol.order_id = o.id`) and copies **equality** restrictions across them, but **not range restrictions**. With `o.id = 4242` it derives `ol.order_id = 4242` automatically:

```text
 Nested Loop
   ->  Index Only Scan using orders_pkey on orders o
         Index Cond: (id = 4242)
   ->  Index Scan using order_lines_pkey on order_lines ol
         Index Cond: (order_id = 4242)            ← derived, not written in the query
```

With `o.id <= 200000`, nothing is derived.

### 3.2 Forcing a merge join shows what was possible

```sql
set enable_hashjoin = off; set enable_nestloop = off;      -- diagnosis only
explain (analyze, buffers, settings) select count(*) from orders o join order_lines ol on ol.order_id = o.id where o.id <= 200000;
```

```text
 Aggregate  (cost=112834.47..112834.48 rows=1 width=8) (actual time=136.124..136.125 rows=1.00 loops=1)
   Buffers: shared hit=292 read=2569 written=2
   ->  Merge Join  (cost=6.39..111300.84 rows=613452 width=0) (actual time=0.022..115.430 rows=600000.00 loops=1)
         Merge Cond: (o.id = ol.order_id)
         ->  Index Only Scan using orders_pkey on orders o  (cost=0.42..5826.90 rows=204484 width=8) (actual time=0.014..15.295 rows=200000.00 loops=1)
               Index Cond: (id <= 200000)
               Heap Fetches: 0
         ->  Index Only Scan using order_lines_pkey on order_lines ol  (cost=0.43..91328.43 rows=3000000 width=8) (actual time=0.005..49.883 rows=600001.00 loops=1)
               Heap Fetches: 0
 Settings: jit = 'off', max_parallel_workers_per_gather = '0', enable_hashjoin = 'off', enable_nestloop = 'off'
```

* Both sides arrive sorted from their primary keys, so the merge walks them in lockstep. **The inner scan stopped after 600,001 rows** (`rows=600001.00` vs `rows=3000000` estimated): once the outer side is exhausted, a merge join ends. One extra row was read to discover the end.
* **136 ms vs 660 ms**, 2,861 pages vs 25,550 pages plus temp files. The cost model priced the merge join at 112,834 (above the hash join's 97,827) because it charged the inner index scan for all 3 M rows. Early termination is something the estimate doesn't fully see.

### 3.3 The production fix: write the redundant predicate

```sql
explain (analyze, buffers) select count(*) from orders o join order_lines ol on ol.order_id = o.id
where o.id <= 200000 and ol.order_id <= 200000;
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Aggregate  (cost=29306.10..29306.11 rows=1 width=8) (actual time=135.072..135.073 rows=1.00 loops=1)
   Buffers: shared hit=8 read=2853
   ->  Merge Join  (cost=1.07..28999.05 rows=122819 width=0) (actual time=0.036..117.089 rows=600000.00 loops=1)
         Merge Cond: (o.id = ol.order_id)
         ->  Index Only Scan using orders_pkey on orders o  (cost=0.42..5773.09 rows=202552 width=8) (actual time=0.012..14.944 rows=200000.00 loops=1)
               Index Cond: (id <= 200000)
               Heap Fetches: 0
         ->  Index Only Scan using order_lines_pkey on order_lines ol  (cost=0.43..19975.71 rows=606359 width=8) (actual time=0.017..53.266 rows=600000.00 loops=1)
               Index Cond: (order_id <= 200000)
               Heap Fetches: 0
```

The planner now chooses the merge join itself (cost 28,999). **The trade-off to mention in an interview:** the join estimate became **122,819 vs 600,000 actual**, 5× too low, because the planner multiplied the selectivity of two restrictions that are really the same restriction. Harmless here; under a further join it could pick a nested loop. Prefer the redundant predicate on the **largest** table only, and re-check the plan above it.

---

## 4. Semi joins, anti joins and the three subquery nodes ⚡

### 4.1 `EXISTS` → Hash Semi Join

```sql
explain (analyze, buffers) select count(*) from customers c
where exists (select 1 from orders o where o.customer_id = c.id and o.status = 'CANCELLED');
```

```text
 Aggregate  (cost=14961.10..14961.11 rows=1 width=8) (actual time=25.777..25.779 rows=1.00 loops=1)
   ->  Hash Semi Join  (cost=10374.26..14935.35 rows=10300 width=0) (actual time=8.358..25.703 rows=2000.00 loops=1)
         Hash Cond: (c.id = o.customer_id)
         ->  Seq Scan on customers c  (cost=0.00..3870.00 rows=200000 width=8) (actual time=0.008..6.346 rows=200000.00 loops=1)
         ->  Hash  (cost=10245.51..10245.51 rows=10300 width=8) (actual time=8.316..8.317 rows=10000.00 loops=1)
               Buckets: 16384  Batches: 1  Memory Usage: 519kB
               ->  Bitmap Heap Scan on orders o  (cost=284.25..10245.51 rows=10300 width=8) (actual time=2.198..7.345 rows=10000.00 loops=1)
                     Recheck Cond: (status = 'CANCELLED'::text)
                     Heap Blocks: exact=9412
```

A **semi** join emits each outer row at most once, at its first match: 10,000 cancelled orders belong to 2,000 customers, and the result is 2,000 rows, not 10,000. Writing the same thing as `JOIN … DISTINCT` would produce 10,000 rows and then deduplicate them. Note the estimate `rows=10300` for the semi join's output (actual 2,000): semi-join selectivity is hard to estimate.

### 4.2 `NOT EXISTS` → Anti Join

```sql
explain (analyze, buffers) select count(*) from products p where not exists (select 1 from order_lines ol where ol.product_id = p.id);
```

```text
 Aggregate  (cost=10163.71..10163.72 rows=1 width=8) (actual time=43.863..43.864 rows=1.00 loops=1)
   Buffers: shared hit=57640 read=2509
   ->  Nested Loop Anti Join  (cost=0.43..10163.27 rows=177 width=0) (actual time=43.861..43.861 rows=0.00 loops=1)
         ->  Seq Scan on products p  (cost=0.00..348.00 rows=20000 width=8) (actual time=0.007..0.943 rows=20000.00 loops=1)
         ->  Index Only Scan using order_lines_product on order_lines ol  (cost=0.43..3.58 rows=151 width=8) (actual time=0.002..0.002 rows=1.00 loops=20000)
               Index Cond: (product_id = p.id)
               Heap Fetches: 0
               Index Searches: 20000
```

An **anti** join emits outer rows with **no** match, and each inner probe stops at the first hit (`rows=1.00` per loop even though each product has ~150 lines). 20,000 index probes in 44 ms. Every product has been ordered, so the result is 0 (estimated 177).

### 4.3 `NOT IN (subquery)` → hashed SubPlan

```sql
explain (analyze, buffers) select count(*) from products p where p.id not in (select ol.product_id from order_lines ol where ol.order_id <= 1000);
```

```text
 Aggregate  (cost=5772.43..5772.44 rows=1 width=8) (actual time=3.499..3.500 rows=1.00 loops=1)
   ->  Seq Scan on products p  (cost=5349.43..5747.43 rows=10000 width=0) (actual time=0.926..2.944 rows=17000.00 loops=1)
         Filter: (NOT (ANY (id = (hashed SubPlan 1).col1)))
         Rows Removed by Filter: 3000
         SubPlan 1
           ->  Index Scan using order_lines_pkey on order_lines ol  (cost=0.43..5341.51 rows=3169 width=8) (actual time=0.037..0.613 rows=3000.00 loops=1)
                 Index Cond: (order_id <= 1000)
```

`NOT IN` is **not** turned into an anti join, because its SQL semantics differ when the subquery returns a `NULL` (then `NOT IN` is never true, [2.11 P5](11-Plan-Pathologies-Diagnosis-Playbook.md#p5-not-in-quadratic-time-and-a-null-that-returns-nothing-)). Here the subquery's 3,000 values fit in memory, so it ran **once** and was put in a hash table (`hashed SubPlan`). When the subquery result is larger than `work_mem`, the plan becomes a plain `SubPlan` re-scanned per outer row, and it goes quadratic: 9 seconds for 1,000 rows in [2.11 P5](11-Plan-Pathologies-Diagnosis-Playbook.md#p5-not-in-quadratic-time-and-a-null-that-returns-nothing-).

### 4.4 Correlated scalar subquery → SubPlan with loops

```sql
explain (analyze, buffers) select c.id, (select max(o.created_at) from orders o where o.customer_id = c.id) as last_order
from customers c where c.id <= 1000;
```

```text
 Index Only Scan using customers_pkey on customers c  (cost=0.42..22440.62 rows=926 width=16) (actual time=0.041..9.016 rows=1000.00 loops=1)
   Index Cond: (id <= 1000)
   Heap Fetches: 0
   Buffers: shared hit=8004 read=2
   SubPlan 1
     ->  Aggregate  (cost=24.19..24.20 rows=1 width=8) (actual time=0.009..0.009 rows=1.00 loops=1000)
           Buffers: shared hit=8000
           ->  Bitmap Heap Scan on orders o  (cost=4.46..24.18 rows=5 width=8) (actual time=0.003..0.006 rows=5.00 loops=1000)
                 Recheck Cond: (customer_id = c.id)
                 Heap Blocks: exact=5000
                 ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..4.46 rows=5 width=0) (actual time=0.001..0.001 rows=5.00 loops=1000)
                       Index Cond: (customer_id = c.id)
                       Index Searches: 1000
```

`SubPlan 1 … loops=1000`: the subquery ran once per customer: 8 buffers each, 8,000 total. Fine for 1,000 rows; for a 200,000-row report it's 1.6 M buffer touches. The set-based rewrite is `LEFT JOIN (SELECT customer_id, max(created_at) … GROUP BY customer_id)` or `LEFT JOIN LATERAL` with an index on `(customer_id, created_at)` ([2.4 §3.2](04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)).

### 4.5 Uncorrelated scalar subquery → InitPlan (runs once)

```sql
explain (analyze, buffers) select id, total from orders where total > (select avg(total) * 1.99 from orders where created_at >= '2025-12-28');
```

```text
 Seq Scan on orders  (cost=138.23..22050.23 rows=333333 width=14) (actual time=0.534..80.739 rows=4220.00 loops=1)
   Filter: (total > (InitPlan 1).col1)
   Rows Removed by Filter: 995780
   Buffers: shared hit=9460
   InitPlan 1
     ->  Aggregate  (cost=138.22..138.23 rows=1 width=32) (actual time=0.518..0.519 rows=1.00 loops=1)
           ->  Index Scan using orders_created_at on orders orders_1  (cost=0.42..130.51 rows=3084 width=6) (actual time=0.019..0.280 rows=2972.00 loops=1)
                 Index Cond: (created_at >= '2025-12-28 00:00:00+00'::timestamp with time zone)
```

* `InitPlan` = evaluated **once** before the parent starts (`loops=1`); its value is referenced as `(InitPlan 1).col1`.
* **The estimate is a default:** `rows=333333` = one third of the table, the planner's fixed guess for `>` against a value unknown at plan time (`DEFAULT_INEQ_SEL = 0.3333`). Actual 4,220. Any comparison against a subquery result, a `now()`-derived parameter in a generic plan, or a function result gets these default selectivities; if the query is important, compute the value first and pass it as a literal or a custom-plan parameter.

| Node | Correlated? | Runs | Typical source |
|---|---|---|---|
| `InitPlan` | No | Once | `WHERE x > (SELECT avg …)` |
| `SubPlan` | Yes | Once **per outer row** | Scalar subquery in the `SELECT` list, non-hashable `NOT IN` |
| `hashed SubPlan` | No | Once, then hash lookups | `NOT IN (SELECT …)` that fits in `work_mem` |
| Semi / Anti Join | Rewritten into a join | As a join | `EXISTS`, `NOT EXISTS`, `IN (SELECT …)` |

---

## 5. PostgreSQL 18 self-join elimination 🧊

ORMs and view stacking produce queries that join a table to itself on its primary key:

```sql
explain (costs off) select o1.id, o1.total from orders o1 join orders o2 on o2.id = o1.id
where o2.status = 'CANCELLED' and o1.customer_id = 17;
```

**Output (PostgreSQL 18.6, verified):**

```text
-- enable_self_join_elimination = on (default)          -- set enable_self_join_elimination = off
 Bitmap Heap Scan on orders o2                            Nested Loop
   Recheck Cond: (customer_id = 17)                         ->  Bitmap Heap Scan on orders o1
   Filter: (status = 'CANCELLED'::text)                           Recheck Cond: (customer_id = 17)
   ->  Bitmap Index Scan on orders_customer_id                    ->  Bitmap Index Scan on orders_customer_id
         Index Cond: (customer_id = 17)                                 Index Cond: (customer_id = 17)
                                                            ->  Index Scan using orders_pkey on orders o2
                                                                  Index Cond: (id = o1.id)
                                                                  Filter: (status = 'CANCELLED'::text)
```

PG 18 proves the join on a unique key returns each row matched to itself, removes one side, and merges the predicates (`customer_id = 17` **and** `status = 'CANCELLED'`) onto the remaining scan. Before 18 you'd see the nested loop. If you're on PG ≤ 17, look for this shape in ORM-generated SQL (Hibernate subquery-to-join rewrites, `exists` filters through views).

---

## 6. Partitioned tables: Append, pruning, Merge Append ⚡

### 6.1 Plan-time pruning

```sql
explain (analyze, buffers) select count(*) from events where occurred_at >= '2026-05-10' and occurred_at < '2026-05-12';
```

```text
 Aggregate  (cost=215.53..215.54 rows=1 width=8) (actual time=0.934..0.934 rows=1.00 loops=1)
   Buffers: shared read=21
   ->  Index Only Scan using events_2026_05_occurred_at_idx on events_2026_05 events  (cost=0.29..199.61 rows=6366 width=0) (actual time=0.213..0.730 rows=6647.00 loops=1)
         Index Cond: ((occurred_at >= '2026-05-10 00:00:00+00'::timestamp with time zone) AND (occurred_at < '2026-05-12 00:00:00+00'::timestamp with time zone))
         Heap Fetches: 0
         Index Searches: 1
 Planning:
   Buffers: shared hit=117 read=7 dirtied=1
 Planning Time: 4.335 ms
```

Eleven partitions disappeared **at plan time**; with one survivor, the planner even dropped the `Append` node. Notice `Planning Time` (4.3 ms) is larger than execution (0.9 ms): the planner opened partition metadata. With thousands of partitions, planning time is the bottleneck, which is why partition counts beyond a few thousand hurt OLTP.

### 6.2 Pruning defeated by a cast

```sql
explain (costs off) select count(*) from events where occurred_at::date = '2026-05-10';
```

```text
 Aggregate
   ->  Append
         ->  Seq Scan on events_2026_01 events_1
               Filter: ((occurred_at)::date = '2026-05-10'::date)
         ->  Seq Scan on events_2026_02 events_2
               Filter: ((occurred_at)::date = '2026-05-10'::date)
         …   (all 12 partitions, each a Seq Scan)
         ->  Seq Scan on events_2026_12 events_12
               Filter: ((occurred_at)::date = '2026-05-10'::date)
```

The partition key is `occurred_at`, not `occurred_at::date`. A function or cast on the key column prevents pruning **and** index use: all 12 partitions are seq-scanned. Rewrite as a half-open range on the raw column (§6.1). `timestamptz::date` also depends on the session `TimeZone`, so it isn't immutable: even an expression index can't be built on it.

### 6.3 Run-time pruning (generic plans, parameters)

```sql
prepare ev(timestamptz) as select count(*) from events where occurred_at >= $1 and occurred_at < $1 + interval '1 day';
set plan_cache_mode = force_generic_plan;       -- what a JDBC PreparedStatement gets after a few executions
explain (analyze, buffers) execute ev('2026-05-10');
```

```text
 Aggregate  (cost=264.46..264.47 rows=1 width=8) (actual time=0.437..0.437 rows=1.00 loops=1)
   Buffers: shared hit=12
   ->  Append  (cost=0.29..249.46 rows=5997 width=0) (actual time=0.013..0.332 rows=3323.00 loops=1)
         Buffers: shared hit=12
         Subplans Removed: 11
         ->  Index Only Scan using events_2026_05_occurred_at_idx on events_2026_05 events_1  (cost=0.29..18.60 rows=515 width=0) (actual time=0.012..0.212 rows=3323.00 loops=1)
               Index Cond: ((occurred_at >= $1) AND (occurred_at < ($1 + '1 day'::interval)))
```

The generic plan contains all 12 partitions (the value is unknown at plan time), and the executor pruned 11 of them during **initialization** once `$1` was known: `Subplans Removed: 11`. Pruning can also happen **during** execution (for example, per outer row of a nested loop); then the pruned children show `(never executed)`.

### 6.4 Merge Append, and `(never executed)` children

```sql
explain (analyze, buffers) select id, occurred_at from events where occurred_at >= '2026-04-30 23:00' order by occurred_at limit 5;
```

```text
 Limit  (cost=2.34..2.57 rows=5 width=16) (actual time=0.039..0.041 rows=5.00 loops=1)
   Buffers: shared hit=1 read=2
   ->  Append  (cost=2.34..37454.64 rows=801302 width=16) (actual time=0.038..0.040 rows=5.00 loops=1)
         ->  Index Scan using events_2026_05_occurred_at_idx on events_2026_05 events_1  (cost=0.29..4273.98 rows=102325 width=16) (actual time=0.038..0.039 rows=5.00 loops=1)
               Index Cond: (occurred_at >= '2026-04-30 23:00:00+00'::timestamp with time zone)
               Index Searches: 1
         ->  Index Scan using events_2026_06_occurred_at_idx on events_2026_06 events_2  (cost=0.29..4160.90 rows=99692 width=16) (never executed)
               Index Cond: (occurred_at >= '2026-04-30 23:00:00+00'::timestamp with time zone)
               Index Searches: 0
         …   (07 to 12: never executed)
```

Two things worth explaining in an interview:
* The planner used an **ordered `Append`** instead of `Merge Append`: range partitions don't overlap, so concatenating per-partition index scans in partition order is already sorted. A `Merge Append` (k-way merge) is needed only when partitions can interleave (list/hash partitioning, or `ORDER BY` a non-key column).
* **Why does the plan start at the May partition when the predicate begins on 30 April at 23:00 UTC?** Pruning works on partition **bounds**, so look at them:

  ```sql
  select relname, pg_get_expr(relpartbound, oid) from pg_class where relname in ('events_2026_04', 'events_2026_05');
  ```

  ```text
  events_2026_04 : FOR VALUES FROM ('2026-03-31 18:30:00+00') TO ('2026-04-30 18:30:00+00')
  events_2026_05 : FOR VALUES FROM ('2026-04-30 18:30:00+00') TO ('2026-05-31 18:30:00+00')
  ```

  The setup script built the bounds from `date` values with `format('%L')`. A literal without an offset is interpreted as a `timestamptz` **in the session's `TimeZone` at creation time**: the server default here is `Asia/Calcutta` (UTC+05:30), and `alter database … set timezone = 'UTC'` ran only at the end of the script. So "May" really starts at 18:30 UTC on 30 April, and the predicate falls entirely inside it. That's a real production bug class: monthly partitions that are off by the creator's UTC offset put the first hours of each month into the previous partition, and retention jobs drop the wrong rows. **Write partition bounds as explicit `timestamptz` literals with an offset (`'2026-05-01 00:00+00'`) and verify them with `pg_get_expr(relpartbound, oid)`.**
* The `LIMIT` stopped after 5 rows from the first child; the other 7 children were never started.

---

## 7. DML: ModifyTable, WAL, HOT, foreign-key triggers, ON CONFLICT 🔥

### 7.1 WAL per statement, and what fillfactor buys

Two identical 200,000-row tables, one packed (`fillfactor = 100`), one with 30 % free space per page (`fillfactor = 70`), each with a secondary index on `region`. Same update of a **non-indexed** column on 10,000 rows, right after a checkpoint:

```sql
explain (analyze, buffers, wal) update acct_full set balance = balance + 1 where id <= 10000;
explain (analyze, buffers, wal) update acct_hot  set balance = balance + 1 where id <= 10000;
select relname, n_tup_upd, n_tup_hot_upd from pg_stat_user_tables where relname in ('acct_full', 'acct_hot');
```

**Output (PostgreSQL 18.6, one measured run):**

```text
 Update on acct_full  (cost=0.42..396.97 rows=0 width=0) (actual time=55.842..55.842 rows=0.00 loops=1)
   Buffers: shared hit=90680 read=20 dirtied=208 written=98
   WAL: records=40401 fpi=110 bytes=3737346
   ->  Index Scan using acct_full_pkey on acct_full  (cost=0.42..396.97 rows=10069 width=22) (actual time=0.023..2.736 rows=10000.00 loops=1)
         Index Cond: (id <= 10000)

 Update on acct_hot  (cost=0.42..437.60 rows=0 width=0) (actual time=39.083..39.083 rows=0.00 loops=1)
   Buffers: shared hit=60028 read=20 dirtied=217 written=84
   WAL: records=27199 fpi=133 bytes=2880265
   ->  Index Scan using acct_hot_pkey on acct_hot  (cost=0.42..437.60 rows=10497 width=22) (actual time=0.019..2.615 rows=10000.00 loops=1)
         Index Cond: (id <= 10000)

  relname  | n_tup_upd | n_tup_hot_upd
-----------+-----------+---------------
 acct_full |     10000 |             0
 acct_hot  |     10000 |          4368
```

| | `fillfactor = 100` | `fillfactor = 70` |
|---|---:|---:|
| HOT updates | 0 of 10,000 | 4,368 of 10,000 |
| WAL records | 40,401 (≈ 4 per row) | 27,199 |
| WAL bytes | 3.74 MB | 2.88 MB |
| Buffers touched | 90,700 | 60,048 |
| Time | 55.8 ms | 39.1 ms |

* **`WAL: records=… fpi=… bytes=…`** (PG 13+): `fpi` = full-page images, the first modification of each page after a checkpoint writes the whole 8 KB page ([2.1 §4.2](01-Storage-Pages-Tuples-TOAST-WAL.md)).
* **What the 4 records per row are** (same experiment repeated with `pg_walinspect`, `pg_get_wal_stats(start_lsn, end_lsn, per_record => true)` between `pg_current_wal_insert_lsn()` calls):

  ```text
  -- fillfactor = 100                    -- fillfactor = 70
   Btree/INSERT_LEAF  | 19956             Btree/INSERT_LEAF  | 11224
   Heap/LOCK          | 10000             Heap/LOCK          |  5632
   Heap/UPDATE        |  9946             Heap/UPDATE        |  5588
   Btree/DEDUP        |   354             Heap/HOT_UPDATE    |  4368
   Heap/UPDATE+INIT   |    54             Btree/DEDUP        |   260
   Btree/INSERT_UPPER |    44             Heap/UPDATE+INIT   |    44
   Btree/SPLIT_L      |    36             Btree/INSERT_UPPER |    40
   Btree/SPLIT_R      |     8             Btree/SPLIT_L      |    36
  ```

  A non-HOT update whose new version must go to **another page** logs `Heap/LOCK` on the old tuple first (`heap_update` has to release the page lock while it finds a new page, so it marks the old version locked in a crash-safe way), then `Heap/UPDATE`, then one `Btree/INSERT_LEAF` **per index** (pkey and `region`): 4 records per row. A `Heap/HOT_UPDATE` is **one** record and touches no index. `UPDATE+INIT` = the new version started a fresh page; `SPLIT_L/R` and `DEDUP` are B-tree page maintenance caused by the index inserts.
* Not all 10,000 updates were HOT with `fillfactor = 70`: after a few updates per page the 30 % free space ran out (fillfactor buys a budget; pruning and VACUUM refill it). HOT also requires that **no indexed column changes**.
* `ModifyTable` shows `rows=0`: it returns nothing unless the statement has `RETURNING`.

### 7.2 The foreign key without an index: `Trigger for constraint`

```sql
create table shipment (id bigint primary key, created_at timestamptz default now());
create table parcel (id bigint primary key, shipment_id bigint not null references shipment(id) on delete cascade, weight int);
-- 50,000 shipments, 500,000 parcels, NO index on parcel.shipment_id
begin;
explain (analyze, buffers) delete from shipment where id <= 200;
rollback;
create index parcel_shipment on parcel (shipment_id);
-- same delete again
```

**Output (PostgreSQL 18.6, one measured run):**

```text
-- without an index on parcel(shipment_id)
 Delete on shipment  (cost=0.29..12.79 rows=0 width=0) (actual time=0.155..0.156 rows=0.00 loops=1)
   Buffers: shared hit=406
   ->  Index Scan using shipment_pkey on shipment  (cost=0.29..12.79 rows=200 width=6) (actual time=0.006..0.028 rows=200.00 loops=1)
         Index Cond: (id <= 200)
 Planning Time: 0.873 ms
 Trigger for constraint parcel_shipment_id_fkey: time=4184.941 calls=200
 Execution Time: 4185.255 ms

-- with the index
 Delete on shipment  (cost=0.29..12.79 rows=0 width=0) (actual time=0.153..0.154 rows=0.00 loops=1)
   Buffers: shared hit=404
   ->  Index Scan using shipment_pkey on shipment  (cost=0.29..12.79 rows=200 width=6) (actual time=0.006..0.031 rows=200.00 loops=1)
         Index Cond: (id <= 200)
 Planning Time: 0.094 ms
 Trigger for constraint parcel_shipment_id_fkey: time=5.037 calls=200
 Execution Time: 5.218 ms
```

* The plan tree is **identical and takes 0.15 ms** in both cases. All the time is in the line **after** the tree: `Trigger for constraint parcel_shipment_id_fkey: time=4184.941 calls=200`.
* Foreign keys are enforced by internal triggers (`RI_FKey_cascade_del`), which run one query **per deleted parent row** against the child table. Without an index on `parcel.shipment_id`, each of the 200 calls seq-scans 500,000 parcels. **4,185 ms vs 5.2 ms (800×).**
* PostgreSQL indexes the **referenced** side (it must be a unique key) but **never creates** an index on the **referencing** column. MySQL/InnoDB does create one automatically, so engineers moving from MySQL are bitten by this. Same cost for `UPDATE` of a parent key and for `ON DELETE RESTRICT/NO ACTION` checks.
* Trigger time also appears for your own triggers (`Trigger audit_trg: time=… calls=…`). `EXPLAIN` without `ANALYZE` can't show any of this.

### 7.3 `INSERT … ON CONFLICT`

```sql
explain (analyze, buffers, wal) insert into acct_hot (id, balance, region) select g, 1, 'r1' from generate_series(199990, 200010) g
on conflict (id) do update set balance = acct_hot.balance + excluded.balance;
```

```text
 Insert on acct_hot  (cost=0.00..0.27 rows=0 width=0) (actual time=0.112..0.112 rows=0.00 loops=1)
   Conflict Resolution: UPDATE
   Conflict Arbiter Indexes: acct_hot_pkey
   Tuples Inserted: 10
   Conflicting Tuples: 11
   Buffers: shared hit=148 dirtied=1
   WAL: records=62 fpi=1 bytes=7295
   ->  Function Scan on generate_series g  (cost=0.00..0.27 rows=21 width=56) (actual time=0.004..0.006 rows=21.00 loops=1)
```

`Conflict Arbiter Indexes` names the unique index used to detect conflicts (if you specify `ON CONFLICT (id)`, it's the index matching `id`); `Tuples Inserted` + `Conflicting Tuples` = input rows (10 new ids 200001–200010, 11 existing). For upserts in batch jobs, these two counters tell you the insert/update mix without touching the application.

---

## 8. The newer `EXPLAIN` options in practice 🧊

### 8.1 `GENERIC_PLAN` (PG 16): see what the prepared statement runs

```sql
explain (generic_plan) select * from orders where customer_id = $1 and status = $2;
```

```text
 Bitmap Heap Scan on orders  (cost=4.46..24.19 rows=1 width=94)
   Recheck Cond: (customer_id = $1)
   Filter: (status = $2)
   ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..4.46 rows=5 width=0)
         Index Cond: (customer_id = $1)
```

Copy a statement from `pg_stat_statements` (it already contains `$1`, `$2`) and plan it **without inventing values**. That's the plan a JDBC `PreparedStatement` ends up with after pgjdbc's `prepareThreshold` and PostgreSQL's five custom plans ([2.3 §5](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md)). It can't be combined with `ANALYZE`.

### 8.2 `SERIALIZE` (PG 17): the cost of sending the result

```sql
explain (analyze, serialize, buffers) select * from orders where customer_id between 1 and 2000;
```

```text
 Bitmap Heap Scan on orders  (cost=183.48..10245.16 rows=11225 width=94) (actual time=1.941..17.630 rows=10000.00 loops=1)
   Recheck Cond: ((customer_id >= 1) AND (customer_id <= 2000))
   Heap Blocks: exact=9330
   Buffers: shared hit=164 read=9183 written=3
   ->  Bitmap Index Scan on orders_customer_id  (cost=0.00..180.68 rows=11225 width=0) (actual time=0.953..0.954 rows=10000.00 loops=1)
 Planning Time: 0.081 ms
 Serialization: time=3.845 ms  output=714kB  format=text
 Execution Time: 22.159 ms
```

Plain `EXPLAIN ANALYZE` discards result rows **without converting them to text and without detoasting** large values. `SERIALIZE` performs that conversion and reports it: 714 kB for 10,000 rows, 3.8 ms. With wide `jsonb`/`text` columns stored out of line (TOAST), the detoasting cost appears here and nowhere else; it's the classic "the plan says 20 ms but the API takes 400 ms".

### 8.3 `MEMORY` (PG 17): planner memory

```text
 Nested Loop  (cost=0.84..16.88 rows=1 width=139)
   ->  Index Scan using orders_pkey on orders o  (cost=0.42..8.44 rows=1 width=94)
         Index Cond: (id = 1)
   ->  Index Scan using customers_pkey on customers c  (cost=0.42..8.44 rows=1 width=45)
         Index Cond: (id = o.customer_id)
 Planning:
   Memory: used=44kB  allocated=64kB
```

Useful when a query with a 50,000-element `IN` list or a join across hundreds of partitions makes the **planner** use hundreds of MB.

### 8.4 `FORMAT JSON`: what tools consume

```json
"Node Type": "Index Only Scan", "Index Name": "orders_customer_id", "Startup Cost": 0.42, "Total Cost": 4.51,
"Plan Rows": 5, "Actual Rows": 5.00, "Actual Loops": 1, "Heap Fetches": 0, "Index Searches": 1,
"Shared Hit Blocks": 3, "Shared Read Blocks": 1, "Shared I/O Read Time": 0.016, ...
"Planning Time": 0.048, "Triggers": [], "Execution Time": 0.038
```

(Excerpt of the verified output.) Every text line has a JSON key; `Triggers` holds the FK-trigger timings from §7.2. Feed it to a visualizer (explain.dalibo.com, pev2) or to your own regression check in CI ("fail the build if this query's plan contains `Seq Scan on orders`").

### 8.5 `auto_explain`: plans from production, without asking

```sql
load 'auto_explain';                                  -- per session; or shared_preload_libraries for all
set auto_explain.log_min_duration = 0; set auto_explain.log_analyze = on; set auto_explain.log_buffers = on;
select count(*) from orders where customer_id = 4242;
```

**Output (verified, from the server log):**

```text
LOG:  duration: 0.499 ms  plan:
	Query Text: select count(*) from orders where customer_id = 4242;
	Aggregate  (cost=4.52..4.53 rows=1 width=8) (actual time=0.492..0.493 rows=1.00 loops=1)
	  Buffers: shared hit=3 read=4
	  ->  Index Only Scan using orders_customer_id on orders  (cost=0.42..4.51 rows=5 width=0) (actual time=0.484..0.485 rows=5.00 loops=1)
	        Index Cond: (customer_id = 4242)
	        Heap Fetches: 0
	        Index Searches: 1
```

Production settings: `log_min_duration = '500ms'`, `log_analyze = on` with **`log_timing = off`** (per-node clock calls are the expensive part), `log_buffers = on`, `sample_rate = 0.1` on hot systems, `log_nested_statements = on` if you use functions. That's how you capture the generic-plan and stale-statistics regressions of [2.11](11-Plan-Pathologies-Diagnosis-Playbook.md) **as they happen**.

---

## 9. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| "The join is slow, add an index on the join column" | Identify the algorithm first; a hash join doesn't use the inner index at all |
| Filters only on the parent side of a join | Adds the redundant range predicate on the big side when the planner can't derive it (and re-checks estimates above) |
| `NOT IN (SELECT …)` | `NOT EXISTS`: correct with NULLs and always an anti join |
| Scalar subqueries in `SELECT` lists of reports | Set-based join or `LATERAL` with a matching composite index |
| `WHERE created_at::date = …` on a partitioned table | Half-open ranges on the raw partition key |
| Partition bounds from `date` arithmetic in an app session | Explicit `timestamptz` literals with offsets; verify with `pg_get_expr(relpartbound, …)` |
| Foreign keys without indexes on the referencing side | Index every FK column that's used for deletes/updates of the parent or for joins |
| Measures DML time with plain `EXPLAIN ANALYZE` and forgets triggers | Reads the `Trigger for constraint …` lines and `WAL:` counters |
| Debugs a JDBC query with literal values in psql | `EXPLAIN (GENERIC_PLAN)` with the `$n` text from `pg_stat_statements` |

---

## 10. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/optimizer/path/equivclass.c` | Equivalence classes: why `=` propagates across joins and ranges don't (§3) |
| postgres/postgres | `src/backend/optimizer/plan/analyzejoins.c` | `remove_useless_self_joins` (PG 18, §5), left-join removal |
| postgres/postgres | `src/backend/executor/nodeHashjoin.c`, `nodeHash.c` | Batching, `nbatch` doubling at run time |
| postgres/postgres | `src/backend/executor/nodeMergejoin.c` | The merge state machine, early termination |
| postgres/postgres | `src/backend/partitioning/partprune.c` | Plan-time and run-time pruning steps |
| postgres/postgres | `src/backend/utils/adt/ri_triggers.c` | The per-row FK check queries behind `Trigger for constraint` |
| postgres/postgres | `contrib/auto_explain/auto_explain.c` | What each `auto_explain.*` setting costs |

---

## 11. Interview soundbites

* "In a hash join the node under `Hash` is the build side. `Batches: 32` means both inputs were partitioned to disk: the same query went from 107 ms to 737 ms."
* "PostgreSQL copies equality restrictions across join keys but not ranges. A range filter on `orders.id` didn't reach `order_lines`, so it seq-scanned 3 M rows; adding the redundant predicate gave a merge join, 660 ms → 135 ms, at the price of a 5× underestimate."
* "`NOT IN` isn't an anti join because of NULL semantics. Hashed, it's fine; when the subquery outgrows `work_mem` it's re-scanned per row."
* "A delete that's fast in the plan tree but slow overall: look at `Trigger for constraint`. Without an index on the referencing column, 200 deletes took 4.2 s instead of 5 ms."
* "Partition pruning happens at plan time, at executor startup (`Subplans Removed`), or during execution (`never executed`). A cast on the key defeats all three."
* "PG 18 removes redundant self-joins on unique keys: `enable_self_join_elimination`."

---

## Summary

| Topic | Key line(s) in the plan | Verified number |
|---|---|---|
| Nested loop | inner `loops=N`, parameterized `Recheck Cond (c.id = …)` | 10 loops × 5 rows; buffers are totals |
| Hash join | `Buckets`, `Batches`, `Memory Usage` under `Hash` | 1 batch → 32 batches: 107 ms → 737 ms |
| Range predicates don't propagate | Seq Scan of the inner table despite a filter on the outer | 3 M rows read; redundant predicate: 660 → 135 ms |
| Merge join | `Merge Cond`; inner stops early | read 600,001 of 3 M rows |
| Semi / anti joins | `Hash Semi Join`, `Nested Loop Anti Join` | 2,000 customers (not 10,000 rows); 20,000 probes in 44 ms |
| SubPlan / InitPlan | `SubPlan … loops=N`, `(InitPlan 1).col1`, `hashed SubPlan` | default 1/3 selectivity for `> (subquery)` |
| Self-join elimination (PG 18) | one scan instead of a nested loop | toggled with `enable_self_join_elimination` |
| Partition pruning | missing children / `Subplans Removed: N` / `(never executed)` | cast on the key → all 12 partitions scanned |
| DML | `WAL: records fpi bytes`, `n_tup_hot_upd` | fillfactor 70: 4,368 HOT updates, 27,199 vs 40,401 WAL records |
| FK without index | `Trigger for constraint … time= calls=` | 4,185 ms vs 5.2 ms |
| ON CONFLICT | `Tuples Inserted`, `Conflicting Tuples` | 10 inserted, 11 updated |
| EXPLAIN options | `GENERIC_PLAN`, `SERIALIZE`, `MEMORY`, JSON, auto_explain | 714 kB serialized for 10,000 rows |

**Next:** [2.11 Plan pathologies: diagnosis playbook →](11-Plan-Pathologies-Diagnosis-Playbook.md)
