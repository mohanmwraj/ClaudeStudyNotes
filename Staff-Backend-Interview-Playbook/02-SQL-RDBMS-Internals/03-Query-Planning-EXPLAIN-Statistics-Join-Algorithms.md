# 2.3 Query Planning: Reading `EXPLAIN (ANALYZE, BUFFERS)`, Statistics, Join Algorithms, Spills, Generic Plans

> **Verified stack:** PostgreSQL **18.6**, the 1 M-row `orders` table from [2.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md), a 100 k-row `customer` table, `pgbench` scale 10. Plans are real; timings are one measured run on a laptop.

---

## 0. First principles: the planner is a cost model fed by guesses 🔥

SQL says *what*, not *how*. For one query the planner enumerates many physical plans (scan methods × join orders × join algorithms × sort/hash strategies), estimates each plan's **cost**, and runs the cheapest.

```text
cost ≈ seq_page_cost   × pages read sequentially   (1.0)
     + random_page_cost × pages read randomly      (4.0; ~1.1 is common on SSDs)
     + cpu_tuple_cost   × rows processed           (0.01)
     + cpu_operator_cost × operator evaluations    (0.0025)
```

Every term depends on **row-count estimates**, and those come from **statistics** sampled by `ANALYZE`. Therefore:

> **Most bad plans are bad estimates, not bad planners.** Your first job reading a slow plan is to find the node where *estimated rows* and *actual rows* diverge, then explain why.

---

## 1. Reading a plan like a staff engineer 🔥

### 1.1 Anatomy

```text
 Aggregate  (cost=349.08..349.09 rows=1 width=8) (actual time=1.391..1.391 rows=1.00 loops=1)
   Buffers: shared hit=5 read=47
   I/O Timings: shared read=0.397
   ->  Index Only Scan using orders_status_created on orders  (cost=0.42..327.00 rows=8833 width=0) (actual time=0.019..1.057 rows=9909.00 loops=1)
         Index Cond: (status = 'CANCELLED'::text)
         Heap Fetches: 0
         Index Searches: 1
         Buffers: shared hit=5 read=47
         I/O Timings: shared read=0.397
 Planning Time: 0.070 ms
 Execution Time: 1.407 ms
```

*(verified: plain `EXPLAIN ANALYZE` in PostgreSQL 18 prints `Buffers` without asking. Buffers are on by default with `ANALYZE` since PG 18.)*

| Field | Meaning | What to check |
|---|---|---|
| `cost=0.42..327.00` | Estimated startup..total cost (arbitrary units) | Only compare costs *within* one plan |
| `rows=8833` (estimate) vs `rows=9909.00` (actual) | Planner's guess vs reality | **Off by 10× or more = a statistics problem** |
| `actual time=0.019..1.057` | ms to first row .. last row, **per loop** | Multiply by `loops` |
| `loops=1` | How many times the node ran (inner side of a nested loop runs once per outer row) | `loops=100000` × 0.01 ms = 1 s |
| `rows=253.67` | PostgreSQL 18 shows actual rows as an **average per loop** with decimals | Multiply by loops for the total |
| `Buffers: shared hit=5 read=47` | Pages found in `shared_buffers` vs read from the OS (page cache or disk) | `read` high and warm-cache slow = I/O-bound |
| `Rows Removed by Filter` | Rows fetched then discarded | Large = the access path doesn't match the predicate |
| `Heap Fetches` | Index-only scan had to visit the heap | Vacuum / visibility map ([2.2 §3](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)) |
| `Index Searches` (PG 18) | Number of index descents | Skip scans, `= ANY(...)` arrays |
| `Sort Method`, `Batches`, `Memory Usage`, `Disk:` | Whether sorts and hashes fit in `work_mem` | Spills (§4) |

### 1.2 The 7-step plan-reading checklist

1. Find the **slowest node by exclusive time** (its time minus its children's), multiplied by loops.
2. On that node, compare **estimated vs actual rows**. A big gap means fix statistics first (§2).
3. Look for **`Rows Removed by Filter`** on scans: the index doesn't match the predicate (wrong column order, a function wrapper, a type cast).
4. Check **loops** on the inner side of nested loops. That's an N+1 inside the database.
5. Check **spills**: `external merge Disk:`, `Batches: N > 1`.
6. Check **`Heap Fetches`** on index-only scans.
7. Check **buffers**: a plan reading 20,000 pages to return 761 rows is wrong even if it's fast today on a warm cache.

---

## 2. Statistics: where row estimates come from ⚡

### 2.1 Per-column statistics (`pg_stats`)

**Output (verified):**

```text
   attname   | n_distinct |           most_common_vals            |             most_common_freqs              | correlation
-------------+------------+---------------------------------------+--------------------------------------------+--------------
 customer_id |      92043 |                                       |                                            | 0.0015431368
 status      |          4 | {DELIVERED,SHIPPED,PENDING,CANCELLED} | {0.9002333,0.0513,0.039633334,0.008833333} |    0.8168054
```

| Statistic | Used for |
|---|---|
| `most_common_vals` / `most_common_freqs` (MCV list) | `status = 'CANCELLED'` → 0.88% of rows → the estimate of 8,833 (actual 9,909) above |
| `histogram_bounds` | Range predicates on non-MCV values (equal-frequency buckets) |
| `n_distinct` | Equality on non-MCV values (1/n_distinct), `GROUP BY` cardinality. It's sampled, so 92,043 vs ~100,000 real |
| `null_frac` | `IS NULL` predicates |
| `correlation` | Physical order vs logical order. Near ±1 makes index range scans cheap (sequential heap access) |

The sample size is governed by `default_statistics_target` (100 → about 30,000 sampled rows and up to 100 MCVs and histogram buckets). For skewed, high-cardinality columns that drive important plans, raise it per column: `ALTER TABLE orders ALTER COLUMN customer_id SET STATISTICS 1000; ANALYZE orders;`.

### 2.2 The independence assumption, and extended statistics (verified) 🧊

The planner multiplies selectivities as if columns were independent. In real data they often aren't (`city` and `zip`, `country` and `currency`, `tenant_id` and everything).

```sql
create table address (id int, city text, zip text);
insert into address select g, 'city' || (g % 1000), 'zip' || (g % 1000) || '-' || (g % 7)   -- zip determines city
from generate_series(1, 1000000) g;
analyze address;
explain (analyze) select * from address where city = 'city42' and zip = 'zip42-0';
```

**Output (verified):**

```text
 Gather  (cost=1000.00..13620.10 rows=1 width=19) (actual rows=143.00 loops=1)
   ->  Parallel Seq Scan on address  (cost=0.00..12620.00 rows=1 width=19) (actual rows=47.67 loops=3)
         Filter: ((city = 'city42'::text) AND (zip = 'zip42-0'::text))
```

Estimate **1**, actual **143**: P(city) × P(zip) = 1/1000 × 1/7000 × 1,000,000 ≈ 0.14. Inside a bigger query, "1 row" makes the planner choose a nested loop with this as the outer side, and 143 (or in real data, 143,000) iterations follow.

```sql
create statistics address_city_zip (dependencies, ndistinct, mcv) on city, zip from address;
analyze address;
```

**Output (verified):**

```text
 Gather  (cost=1000.00..13634.20 rows=142 width=19) (actual rows=143.00 loops=1)
   ->  Parallel Seq Scan on address  (cost=0.00..12620.00 rows=59 width=19) (actual rows=47.67 loops=3)
```

Estimate **142** vs actual 143. The `GROUP BY city, zip` estimate is also right: `rows=7007` estimated vs `7000` actual (`ndistinct` statistics).

### 2.3 Reproducing the planner's row estimates by hand (verified) 🧊

If you can compute an estimate yourself, you can tell *why* it's wrong. On the [atlas dataset](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#02-the-dataset-run-it-yourself) (1,000,000 orders), after a fresh `ANALYZE`, each estimate below was computed in SQL from `pg_stats` and matched the planner's number **exactly**:

| Predicate | Rule (`selfuncs.c`) | Inputs from `pg_stats` | By hand | Planner `rows=` |
|---|---|---|---:|---:|
| `status = 'CANCELLED'` (an MCV) | `reltuples × mcv_freq` | `most_common_freqs` for CANCELLED = 0.009233333 | 9,233 | **9233** |
| `customer_id = 4242` (not in the MCV list) | `reltuples × (1 − Σ mcv_freqs − null_frac) / (n_distinct − n_mcv)` | no MCV list; `n_distinct = −0.198508` (negative = fraction of rows, so 198,508 distinct) | 5.04 | **5** |
| `total > 490` | Histogram: fraction of the 100 equal-frequency buckets above 490, linear interpolation inside the bucket that contains it | 101 bounds from 1.01 to 500.98 | 22,136 | **22136** |

**Output (verified, PostgreSQL 18.6):**

```text
-- status
 most_common_vals = {DELIVERED,SHIPPED,PENDING,CANCELLED}
 most_common_freqs = {0.9028,0.049,0.038966667,0.009233333}      null_frac = 0   n_distinct = 4
 Bitmap Heap Scan on orders  (cost=251.98..10069.44 rows=9233 width=94)          by_hand = 9233

-- customer_id
 n_distinct = -0.198508   n_mcv = (none)   null_frac = 0
 Bitmap Heap Scan on orders  (cost=4.46..24.18 rows=5 width=94)                   by_hand = 5.0375805

-- total
 n_bounds = 101   lo = 1.01   hi = 500.98
 Parallel Seq Scan on orders  … rows=9223  /  Gather … rows=22136                 by_hand = 22136
```

Three lessons hide in this table:

* The sampled frequency of `CANCELLED` was 0.92 %, the truth is exactly 1.00 % (every 100th order). `ANALYZE` samples 30,000 rows (`300 × default_statistics_target`), so **MCV frequencies carry sampling error**; raising the statistics target for a column shrinks it.
* `n_distinct = −0.198508` means "the number of distinct values scales with the table: 19.85 % of rows". The truth is 200,000 / 1,000,000 = 20 %. Negative `n_distinct` is why estimates stay right as the table grows without re-analysis.
* When there's **no statistic to use**, the planner falls back to hard-coded defaults (`selfuncs.h`):

```text
-- total > (select 490): the value is unknown at plan time
 Seq Scan on orders  (cost=0.01..24412.01 rows=333333 width=94)        ← DEFAULT_INEQ_SEL = 1/3
-- lower(status) = 'cancelled': no statistics on the expression
 Gather  (cost=1000.00..17162.00 rows=5000 width=94)                   ← DEFAULT_EQ_SEL = 0.005
```

  Whenever you see a round **one third** or **0.5 %** of the table as an estimate, the planner is guessing. Fixes: an expression index (which gets its own statistics on `ANALYZE`), `CREATE STATISTICS` on an expression (PG 14+), or passing the value instead of a subquery.

---

## 3. Join algorithms 🔥

### 3.1 Nested loop: few outer rows, indexed inner side

```sql
select c.name, o.id, o.amount from customer c join orders o on o.customer_id = c.id where c.id between 1000 and 1004;
```

**Output (verified):**

```text
 Nested Loop (actual time=0.110..0.856 rows=48.00 loops=1)
   ->  Index Scan using customer_pkey on customer c (actual time=0.015..0.018 rows=5.00 loops=1)
         Index Cond: ((id >= 1000) AND (id <= 1004))
   ->  Bitmap Heap Scan on orders o (actual time=0.047..0.160 rows=9.60 loops=5)
         Recheck Cond: (c.id = customer_id)
         ->  Bitmap Index Scan on orders_customer (actual time=0.007..0.007 rows=9.60 loops=5)
               Index Cond: (customer_id = c.id)
               Index Searches: 5
```

Cost ≈ outer rows × (one index probe). It's ideal for small outer sets and catastrophic when the outer estimate is "1" but reality is 100,000. That's the extended-statistics story above.

### 3.2 Hash join: big unsorted inputs

```sql
select c.country, sum(o.amount) from customer c join orders o on o.customer_id = c.id group by c.country;
```

**Output (verified, excerpt):**

```text
                     ->  Hash Join (actual time=21.013..135.895 rows=333333.33 loops=3)
                           Hash Cond: (o.customer_id = c.id)
                           ->  Parallel Seq Scan on orders o (actual time=0.670..19.462 rows=333333.33 loops=3)
                           ->  Hash (actual time=20.153..20.154 rows=100000.00 loops=3)
                                 Buckets: 131072  Batches: 1  Memory Usage: 5712kB
                                 ->  Seq Scan on customer c (actual time=0.545..8.205 rows=100000.00 loops=3)
```

It builds an in-memory hash table on the **smaller** input (100,000 customers, 5.7 MB), then streams the bigger one past it. Each of the 3 parallel workers built its own copy here (`loops=3`). Cost is O(N + M), but it needs memory and can't return the first row before the build finishes.

### 3.3 The same hash join, spilling (verified)

```sql
set work_mem = '64kB';
select c.tier, count(*) from customer c join orders o on o.customer_id = c.id group by c.tier;
```

**Output (verified, excerpt):**

```text
                     ->  Hash Join (actual time=31.050..407.814 rows=333333.33 loops=3)
                           ->  Hash (actual time=27.638..27.639 rows=100000.00 loops=3)
                                 Buckets: 16384  Batches: 16  Memory Usage: 424kB
```

`Batches: 16`: the hash table didn't fit, so both inputs were partitioned into 16 batches and written to temp files. The total query went from about 235 ms (comparable query, 1 batch) to 513 ms.

### 3.4 Merge join: both sides already sorted

```sql
set enable_hashjoin = off; set enable_nestloop = off;      -- demonstration only
select count(*) from customer c join orders o on o.customer_id = c.id;
```

**Output (verified, excerpt):**

```text
               ->  Merge Join (actual time=2.430..47.948 rows=333333.33 loops=3)
                     Merge Cond: (o.customer_id = c.id)
                     ->  Parallel Index Only Scan using orders_customer on orders o (...)
                     ->  Index Only Scan using customer_pkey on customer c (...)
```

Both inputs come out of indexes already sorted by the join key, so the join is a single synchronized walk with no hash table and no sort.

### 3.5 Comparison

| | Nested Loop | Hash Join | Merge Join |
|---|---|---|---|
| Complexity | O(outer × cost of inner probe) | O(N + M) | O(N + M) if sorted, + sorts otherwise |
| Memory | None | Hash of the smaller input (`work_mem × hash_mem_multiplier`) | None (unless it sorts) |
| Join types | Any condition (including `<`, `LIKE`) | **Equality only** | Equality (sortable) |
| First row latency | Immediate | After the build | Immediate if inputs are pre-sorted |
| Typical failure | Outer underestimated → millions of probes | Spill to disk (`Batches > 1`) | Big explicit sorts |
| Best for | OLTP lookups, small outer, `LIMIT` | Reporting joins, no useful indexes | Pre-sorted inputs, very large joins, `ORDER BY` on the join key |

---

## 4. Memory: `work_mem` and spills ⚡

`work_mem` is a **per-operation** limit (each sort or hash node), per process, **per parallel worker**. A query with 3 hash joins and 2 sorts on 4 workers can use 5 × 5 × `work_mem`. Multiply by connections before raising it globally.

**Output (verified, sorting 1 M rows):**

```text
-- work_mem = 4MB (default in this lab)
 Limit (actual time=620.087..620.206 rows=10.00 loops=1)
   ->  Sort (actual time=400.883..605.624 rows=1000000.00 loops=1)
         Sort Key: amount DESC, id
         Sort Method: external merge  Disk: 24544kB

-- work_mem = 64MB
 Limit (actual time=714.250..714.252 rows=10.00 loops=1)
   ->  Sort (actual time=578.719..700.115 rows=1000000.00 loops=1)
         Sort Key: amount DESC, id
         Sort Method: quicksort  Memory: 55827kB
```

A surprise worth remembering: **the in-memory sort wasn't faster here** (714 ms vs 620 ms). The 24 MB of temp files stayed in the OS page cache, and comparing `numeric` values dominated the cost. The lesson isn't "spills are fine". It's **measure before tuning**. The fix for this query is an index that already provides the order, or keyset pagination ([2.4](04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)), not more memory.

Safe practice: keep the global `work_mem` modest (4–64 MB, depending on connection count) and raise it **per role or per transaction** for known reporting queries (`SET LOCAL work_mem = '256MB'`). Watch `temp_files` and `temp_bytes` in `pg_stat_database` and set `log_temp_files`.

---

## 5. Prepared statements: custom vs generic plans (the JDBC trap) 🧊

PostgreSQL caches plans for prepared statements. For the **first five executions** it builds a **custom plan** using the actual parameter values. From then on it also costs a **generic plan** (parameters unknown) and switches to it if the generic plan's estimated cost isn't worse than the average custom plan's. The generic plan is then reused for *every* value.

**pgjdbc (the PostgreSQL JDBC driver) turns a `PreparedStatement` into a server-side prepared statement after `prepareThreshold = 5` executions.** So a hot repository method can end up on a generic plan after ten calls.

### Verified: skewed data makes the generic plan wrong for rare values

```sql
prepare by_status(text) as select sum(amount) from orders where status = $1;
-- warm-up traffic is dominated by the common value
execute by_status('DELIVERED');   -- ×5 (custom plans: parallel seq scan, the right choice for 90% of the table)
select name, generic_plans, custom_plans from pg_prepared_statements;
explain (analyze) execute by_status('CANCELLED');
```

**Output (verified):**

```text
   name    | generic_plans | custom_plans
-----------+---------------+--------------
 by_status |             0 |            5

 Finalize Aggregate (actual time=86.285..94.972 rows=1.00 loops=1)
   ->  Gather (actual time=86.163..94.965 rows=3.00 loops=1)
         ->  Partial Aggregate (actual time=35.356..35.356 rows=1.00 loops=3)
               ->  Parallel Seq Scan on orders (actual time=0.363..34.870 rows=3303.00 loops=3)
                     Filter: (status = $1)
                     Rows Removed by Filter: 330030

   name    | generic_plans | custom_plans
-----------+---------------+--------------
 by_status |             1 |            5
```

`Filter: (status = $1)` is the giveaway: a **generic** plan. It seq-scans 1 M rows for a 1% value. Forcing custom plans:

```sql
set plan_cache_mode = force_custom_plan;
explain (analyze) execute by_status('CANCELLED');
```

```text
 Aggregate (actual time=8.115..8.116 rows=1.00 loops=1)
   ->  Bitmap Heap Scan on orders (actual time=1.896..7.268 rows=9909.00 loops=1)
         Recheck Cond: (status = 'CANCELLED'::text)
         ->  Bitmap Index Scan on orders_status_created (actual time=1.085..1.086 rows=9909.00 loops=1)
```

**95 ms vs 8 ms.** The opposite order (warming up with the rare value) kept custom plans in our run, because then the generic plan *looked* more expensive than the average custom plan. That's exactly why this bug appears only after a deploy, or only on some pods: it depends on **which values each connection saw first**.

Fixes, from narrowest to broadest:

| Fix | Where |
|---|---|
| `plan_cache_mode = force_custom_plan` for the specific role or transaction | `ALTER ROLE reporting SET plan_cache_mode = force_custom_plan` |
| Split the query: a separate statement or partial index for the rare values | Application |
| `prepareThreshold=0` (never server-prepare) for that `DataSource` | pgjdbc URL. Costs parse and plan time on every call |
| Know your pooler: PgBouncer in transaction mode needs `max_prepared_statements` (1.21+) to support protocol-level prepared statements | [2.7](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md) |

---

## 6. CTEs: inlined unless you say otherwise ⚡

Since PostgreSQL 12, a non-recursive, side-effect-free CTE referenced **once** is **inlined** (optimized as part of the outer query). `MATERIALIZED` restores the old "optimization fence".

**Output (verified):**

```text
-- with recent as (select * from orders where created_at >= '2026-12-01') select id from recent where customer_id = 4242;
 Index Scan using orders_cust_created_incl on orders
   Index Cond: ((customer_id = 4242) AND (created_at >= '2026-12-01 00:00:00+00'::timestamp with time zone))

-- with recent as MATERIALIZED (...) select id from recent where customer_id = 4242;
 CTE Scan on recent
   Filter: (customer_id = 4242)
   CTE recent
     ->  Bitmap Heap Scan on orders
           Recheck Cond: (created_at >= '2026-12-01 00:00:00+00'::timestamp with time zone)
           ->  Bitmap Index Scan on orders_created_brin
```

Inlined, the planner pushes `customer_id = 4242` into the index condition. Materialized, it computes **all of December** first and then filters. Use `MATERIALIZED` deliberately: to evaluate an expensive or volatile expression once, or to pin a plan shape you've proven is better.

---

## 7. Finding the queries worth fixing: `pg_stat_statements` 🔥

`pg_stat_statements` normalizes queries (literals become `$n`) and accumulates time, calls, rows and buffers per statement. After the `pgbench` runs in [2.7](07-Scaling-Replicas-Partitioning-Pooling-Sharding.md):

```sql
select left(regexp_replace(query, '\s+', ' ', 'g'), 60) as query, calls,
       round(total_exec_time::numeric, 1) as total_ms, round(mean_exec_time::numeric, 2) as mean_ms,
       rows, shared_blks_hit as hit, shared_blks_read as read
from pg_stat_statements where dbid = (select oid from pg_database where datname = 'bench')
order by total_exec_time desc limit 5;
```

**Output (verified):**

```text
                            query                             | calls  | total_ms | mean_ms |  rows   |  hit   | read
--------------------------------------------------------------+--------+----------+---------+---------+--------+-------
 UPDATE pgbench_branches SET bbalance = bbalance + $1 WHERE b | 145114 |  85018.2 |    0.59 |  145114 | 887586 |     6
 UPDATE pgbench_tellers SET tbalance = tbalance + $1 WHERE ti | 145114 |  35203.7 |    0.24 |  145114 | 636881 |     6
 UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE a | 145114 |   8425.1 |    0.06 |  145114 | 937160 | 41491
 SELECT abalance FROM pgbench_accounts WHERE aid = $1         | 145114 |   1483.9 |    0.01 |  145114 | 597787 |     0
 copy pgbench_accounts from stdin with (freeze on)            |      1 |   1341.4 | 1341.37 | 1000000 |  17137 |     0
```

How a staff engineer reads this: the **cheapest-looking statement is the most expensive**. Updating one of only **10 branch rows** consumed 85 seconds in total. That's not I/O (6 reads) and not CPU. It's **waiting on row locks**, because every transaction updates one of 10 hot rows. Execution time in `pg_stat_statements` includes lock waits. Hot-row contention is fixed in the *data model* (sharded counters, append-only ledger rows summed later, batching), not with indexes.

Pair it with `auto_explain` (`auto_explain.log_min_duration = '500ms'`, `log_analyze = on`, `log_buffers = on`) to capture real plans of slow executions in production, including the generic-plan cases from §5.

---

## 8. ❌ Naïve vs ✅ production-hardened query tuning

| ❌ Naïve | ✅ Hardened |
|---|---|
| "The query is slow, add an index" | Read the plan: estimate vs actual, `Rows Removed by Filter`, loops, buffers |
| `EXPLAIN` without `ANALYZE` to judge performance | `EXPLAIN (ANALYZE, BUFFERS)` on a production-like dataset (estimates alone can't show misestimates) |
| Raise `work_mem` globally to 1 GB | Per role or transaction; size it as connections × nodes × workers |
| `ANALYZE` only when someone remembers | Autovacuum analyze thresholds tuned per big table; `ANALYZE` after bulk loads |
| Ignore correlated columns | `CREATE STATISTICS (dependencies, mcv, ndistinct)` |
| Trust that a prepared statement's plan fits all values | Watch for `$1` in plans of skewed queries; `force_custom_plan` where it matters |
| Optimize by total time only | Break down by calls × mean, rows per call, buffers per call, and lock waits |
| Wrap CTEs everywhere "for readability" assuming a fence | They're inlined since PG 12. Add `MATERIALIZED` only on purpose |

---

## 9. MySQL notes

* `EXPLAIN ANALYZE` (MySQL 8.0.18+) prints an iterator tree with actual times and rows, similar in spirit to PostgreSQL. `EXPLAIN FORMAT=TREE` without executing.
* MySQL's optimizer has mostly nested-loop joins plus **hash join** (8.0.18+) for equi-joins without indexes. There's no merge join.
* Histograms are opt-in (`ANALYZE TABLE t UPDATE HISTOGRAM ON col`). There are no multi-column statistics comparable to `CREATE STATISTICS`.
* Optimizer hints (`/*+ INDEX(t idx) */`, `JOIN_ORDER`) are built in. PostgreSQL deliberately has none in core (the `pg_hint_plan` extension exists), and the community's answer is "fix the statistics".

---

## 10. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/optimizer/README` | Path generation, join search, the overall planner design |
| postgres/postgres | `src/backend/optimizer/path/costsize.c` | The cost formulas for every scan and join type |
| postgres/postgres | `src/backend/utils/adt/selfuncs.c` | Selectivity estimation: MCVs, histograms, `eqsel`, `scalarineqsel` |
| postgres/postgres | `src/backend/statistics/` (`dependencies.c`, `mcv.c`, `mvdistinct.c`) | Extended statistics |
| postgres/postgres | `src/backend/utils/cache/plancache.c` | `choose_custom_plan()`: the five-custom-plans rule from §5 |
| [pgjdbc/pgjdbc](https://github.com/pgjdbc/pgjdbc) | `pgjdbc/src/main/java/org/postgresql/jdbc/PgPreparedStatement.java` | Where `prepareThreshold` turns a statement into a server-side one |

---

## 11. Interview soundbites

* "Most bad plans are bad estimates. I find the node where estimated and actual rows diverge, then fix the statistics: a higher statistics target, extended statistics, or a fresh `ANALYZE`."
* "Nested loop for small outer sets with an indexed inner side, hash join for big unsorted equi-joins, merge join when both sides arrive sorted."
* "`work_mem` is per sort or hash node, per worker. I raise it per transaction, not globally."
* "pgjdbc server-prepares after five executions and PostgreSQL may switch to a generic plan after five more. With skewed data a rare value ran 95 ms instead of 8 ms; `$1` in the plan gave it away."
* "In `pg_stat_statements` the most expensive statement was a trivial update of ten hot rows. Execution time includes lock waits; that's a data-model problem, not an index problem."
* "I can reproduce an estimate from `pg_stats`: MCV frequency × rows for common values, (1 − Σ MCV) ÷ remaining distinct values otherwise, histogram interpolation for ranges. A round one-third or 0.5 % means the planner had nothing and guessed."

> **Go deeper in this batch:** every node type with its complete output and cost formula in [2.9 Atlas Part 1](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md) and [2.10 Atlas Part 2](10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md); eleven before/after diagnoses in [2.11 Plan pathologies](11-Plan-Pathologies-Diagnosis-Playbook.md).

---

## Summary

| Concept | Key point | Verified evidence |
|---|---|---|
| Cost model | `seq_page_cost`, `random_page_cost`, `cpu_*` × pages and rows | Formulas reproduced exactly in [2.9](09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md) |
| Plan reading | Find the node where estimate ≠ actual; multiply per-loop numbers by `loops` | 7-step checklist (§1.2) |
| Statistics | MCV list, histogram, `n_distinct`, `null_frac`, correlation | Estimates 9,233 / 5 / 22,136 reproduced by hand |
| Default selectivities | 1/3 for inequality vs unknown, 0.5 % for equality without statistics | `rows=333333`, `rows=5000` |
| Extended statistics | Fix the independence assumption | estimate 1 → 142 (actual 143) |
| Nested loop / hash / merge | Small indexed inner / big unsorted equi-join / pre-sorted inputs | Hash spill to 16 batches: 235 → 513 ms |
| `work_mem` | Per node, per process, × `hash_mem_multiplier` for hashes | In-memory sort wasn't faster than the 24 MB spill here |
| Generic plans | 5 custom plans, then generic if not costlier; pgjdbc `prepareThreshold = 5` | rare value 95 ms generic vs 8 ms custom |
| CTEs | Inlined since PG 12 unless `MATERIALIZED` or referenced twice | Predicate pushed into the index only when inlined |
| `pg_stat_statements` | Rank by total time; lock waits are included | 10 hot rows cost 85 s total |

**Next:** [2.4 Advanced SQL: CTEs, window functions, keyset pagination →](04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)
