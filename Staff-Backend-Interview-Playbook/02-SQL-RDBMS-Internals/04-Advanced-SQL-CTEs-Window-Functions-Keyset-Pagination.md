# 2.4 Advanced SQL for Backend Engineers: Window Functions, Frames, Keyset Pagination, Top-N per Group, Upsert/MERGE, Recursive CTEs

> **Verified stack:** PostgreSQL **18.6**, `orders` (1 M rows) and `customer` (100 k rows) from [2.2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)/[2.3](03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md). Every result below is real output.
>
> **Why this file exists:** senior interviews include a live SQL round, and production incidents often trace back to one query shape (`OFFSET` pagination, "latest row per group", read-then-write upserts). Each pattern here comes with its plan, not just its syntax.

---

## 0. First principles: think in sets, then think in access paths 🔥

1. **SQL is set algebra.** A window function adds a computed column *without collapsing rows*; `GROUP BY` collapses. Most "I need a loop in Java" problems are a window function.
2. **Every query shape implies an access path.** `ORDER BY created_at DESC LIMIT 20` is cheap *only* if an index can produce that order. `OFFSET 500000` is never cheap, because the database must produce and discard 500,000 rows.
3. **Do the work where the data is.** Shipping 100,000 rows to Java to keep 3 per customer costs network, memory and GC. The same filter in SQL can use an index and return 3,000 rows.

---

## 1. Window functions 🔥

### 1.1 Ranking functions on ties (verified)

```sql
create table score (player text, team text, points int);
insert into score values ('ana','red',50),('bo','red',40),('cy','red',40),('di','red',30),
                         ('ed','blue',70),('fu','blue',70),('gi','blue',10);
select team, player, points,
       row_number() over w as row_number,
       rank()       over w as rank,
       dense_rank() over w as dense_rank,
       lag(points)  over w as prev_points,
       points - lead(points) over w as gap_to_next
from score window w as (partition by team order by points desc) order by team, points desc, player;
```

**Output (verified):**

```text
 team | player | points | row_number | rank | dense_rank | prev_points | gap_to_next
------+--------+--------+------------+------+------------+-------------+-------------
 blue | ed     |     70 |          1 |    1 |          1 |             |           0
 blue | fu     |     70 |          2 |    1 |          1 |          70 |          60
 blue | gi     |     10 |          3 |    3 |          2 |          70 |
 red  | ana    |     50 |          1 |    1 |          1 |             |          10
 red  | bo     |     40 |          2 |    2 |          2 |          50 |           0
 red  | cy     |     40 |          3 |    2 |          2 |          40 |          10
 red  | di     |     30 |          4 |    4 |          3 |          40 |
```

| Function | On ties | Use for |
|---|---|---|
| `row_number()` | Arbitrary but unique (1, 2): **nondeterministic** unless `ORDER BY` is unique | Top-N, dedup |
| `rank()` | Same rank, then a gap (1, 1, 3) | Competition ranking |
| `dense_rank()` | Same rank, no gap (1, 1, 2) | "Nth highest distinct value" |
| `lag()` / `lead()` | Previous / next row in the partition | Deltas, time between events, change detection |
| `ntile(n)`, `percent_rank()`, `cume_dist()` | Bucketing | Quartiles, percentiles |
| `first_value()` / `last_value()` / `nth_value()` | Depend on the **frame** (§1.2) | "Price at start of day" |

### 1.2 The default frame trap (verified) 🧊

With `ORDER BY` in the window, the default frame is **`RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`**. `RANGE` treats rows with **equal `ORDER BY` values (peers)** as a single step.

```sql
select player, points,
       sum(points) over (order by points desc)                                                as default_frame,
       sum(points) over (order by points desc rows between unbounded preceding and current row) as rows_frame,
       sum(points) over (order by points desc, player rows unbounded preceding)                 as rows_frame_det
from score where team = 'red' order by points desc, player;
```

**Output (verified):**

```text
 player | points | default_frame | rows_frame | rows_frame_det
--------+--------+---------------+------------+----------------
 ana    |     50 |            50 |         50 |             50
 bo     |     40 |           130 |         90 |             90
 cy     |     40 |           130 |        130 |            130
 di     |     30 |           160 |        160 |            160
```

* `default_frame` gives **both** tied rows the *same* running total (130). A "running balance" built this way jumps when two transactions share a timestamp.
* `rows_frame` adds rows one at a time, but the order between the two 40-point rows is **arbitrary** (it happened to be `bo` first).
* `rows_frame_det` is the correct form: `ROWS` frame **plus a unique tiebreaker** in `ORDER BY`.

`last_value(x) over (order by t)` has the same trap: with the default frame it returns the *current* row (or its last peer), not the partition's last row. Use `rows between unbounded preceding and unbounded following`.

### 1.3 Running totals, moving averages and filling gaps (verified)

```sql
with daily as (
  select d::date as day, coalesce(sum(o.amount), 0) as revenue
  from generate_series(date '2026-12-08', date '2026-12-14', interval '1 day') d
  left join orders o on o.created_at >= d and o.created_at < d + interval '1 day'
  group by d)
select day, revenue,
       sum(revenue) over (order by day) as running_total,
       round(avg(revenue) over (order by day rows between 2 preceding and current row), 2) as moving_avg_3d
from daily order by day;
```

**Output (verified):**

```text
    day     |  revenue  | running_total | moving_avg_3d
------------+-----------+---------------+---------------
 2026-12-08 | 718550.37 |     718550.37 |     718550.37
 2026-12-09 | 724665.94 |    1443216.31 |     721608.16
 2026-12-10 | 725059.03 |    2168275.34 |     722758.45
 2026-12-11 | 712148.47 |    2880423.81 |     720624.48
 2026-12-12 | 722965.45 |    3603389.26 |     720057.65
 2026-12-13 | 714193.88 |    4317583.14 |     716435.93
 2026-12-14 |         0 |    4317583.14 |     479053.11
```

`generate_series` + `LEFT JOIN` makes **missing days appear as 0** instead of silently vanishing (the dataset ends on 13 December). Dashboards built without this draw a straight line across an outage. Here `day` is unique, so the default `RANGE` frame is safe for the running total.

### 1.4 Gaps and islands: consecutive streaks (verified)

```sql
select user_id, min(day) as streak_start, max(day) as streak_end, count(*) as days
from (select user_id, day, day - (row_number() over (partition by user_id order by day))::int as grp from login) s
group by user_id, grp order by user_id, streak_start;
```

**Output (verified):**

```text
 user_id | streak_start | streak_end | days
---------+--------------+------------+------
       1 | 2026-10-01   | 2026-10-03 |    3
       1 | 2026-10-07   | 2026-10-08 |    2
       2 | 2026-10-05   | 2026-10-06 |    2
       2 | 2026-10-09   | 2026-10-09 |    1
```

The trick: within a run of consecutive days, `day − row_number()` is **constant**, so it labels the island. The same idea finds sessions (gap > 30 min), uptime windows and consecutive failed logins.

### 1.5 Conditional aggregation and percentiles (verified)

```sql
select count(*) filter (where status = 'CANCELLED') as cancelled,
       round(100.0 * count(*) filter (where status = 'CANCELLED') / count(*), 2) as cancel_pct,
       percentile_cont(0.5)  within group (order by amount) as p50_amount,
       percentile_cont(0.99) within group (order by amount) as p99_amount
from orders where created_at >= '2026-12-01';
```

```text
 cancelled | cancel_pct | p50_amount | p99_amount
-----------+------------+------------+------------
       362 |       0.97 |     249.65 |     495.12
```

`FILTER` replaces `sum(case when … then 1 else 0 end)` and keeps several metrics in **one pass** over the data.

---

## 2. Pagination: `OFFSET` vs keyset (seek) 🔥

### 2.1 Why `OFFSET` degrades (first principles)

`LIMIT 20 OFFSET 500000` means "produce 500,020 rows in order, throw away 500,000". The work is **O(offset)**, so the last page of a big list is the slowest, and crawlers and "export all" jobs hit exactly those pages. It's also **unstable**: a row inserted on page 1 while the user reads page 2 shifts everything, and the user sees a duplicate or misses a row.

**Keyset (seek) pagination** remembers the last row's sort key and asks for "the next 20 after it". With an index on the sort key, that's one index descent plus 20 entries, **O(page size)** regardless of depth.

### 2.2 Verified on 1,000,000 rows

```sql
create index orders_created_id on orders (created_at, id);    -- sort key + unique tiebreaker
```

**Page 1 with `OFFSET` (verified):**

```text
 Limit (actual time=0.043..0.046 rows=20.00 loops=1)
   Buffers: shared hit=1 read=3
   ->  Index Scan Backward using orders_created_id on orders (actual time=0.041..0.043 rows=20.00 loops=1)
```

**Page 25,001 with `OFFSET 500000` (verified):**

```text
 Limit (actual time=139.856..139.860 rows=20.00 loops=1)
   Buffers: shared hit=11964 read=4651 written=2813
   ->  Index Scan Backward using orders_created_id on orders (actual time=0.006..129.690 rows=500020.00 loops=1)
```

**The same page with keyset (verified).** The cursor is the last row of the previous page:

```sql
select id, created_at from orders order by created_at desc, id desc limit 1 offset 499999;   -- (only to find the cursor for this demo)
--    id   |       created_at
-- --------+------------------------
--  500001 | 2026-06-23 09:10:30+00

select id, created_at, amount from orders
where (created_at, id) < ('2026-06-23 09:10:30+00', 500001)
order by created_at desc, id desc limit 20;
```

```text
 Limit (actual time=0.012..0.020 rows=20.00 loops=1)
   Buffers: shared hit=5
   ->  Index Scan Backward using orders_created_id on orders (actual time=0.012..0.018 rows=20.00 loops=1)
         Index Cond: (ROW(created_at, id) < ROW('2026-06-23 09:10:30+00'::timestamp with time zone, 500001))
```

And it returns **exactly the same rows** as `OFFSET 500000`:

```text
 same_page
-----------
 t
```

| | `OFFSET 500000` | Keyset |
|---|---|---|
| Rows produced | 500,020 | 20 |
| Buffers | 16,615 (and it **wrote** 2,813 pages, evicting dirty buffers) | 5 |
| Time | 139.9 ms | 0.02 ms |

### 2.3 Keyset rules that interviewers check

1. The sort key must be **unique**. Add the PK as a tiebreaker (`created_at, id`), or rows with equal timestamps are skipped or duplicated at page boundaries.
2. Use a **row-value comparison** `(created_at, id) < (?, ?)`. It matches the composite index directly. The expanded form `created_at < ? OR (created_at = ? AND id < ?)` is equivalent but easier to get wrong and harder for the planner.
3. **Index direction** must match: `(created_at, id)` serves both `ASC, ASC` and (scanned backward) `DESC, DESC`. Mixed directions (`created_at DESC, id ASC`) need an index declared that way.
4. The API returns an **opaque cursor** (e.g. base64 of `{created_at, id}`), not page numbers. "Jump to page 437" isn't supported. Product usually doesn't need it, and search engines are better at it.
5. With filters (`WHERE customer_id = ?`), the index must be `(customer_id, created_at, id)`: equality first, then the sort key (E-S-R, [2.2 §2](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)).

Spring Data supports it directly: `ScrollPosition.keyset()` / `Window<T>` (see [3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)).

---

## 3. Top-N per group 🔥

*"Show the 3 latest orders of each of our 1,000 GOLD customers."*

### 3.1 Window-function version (verified)

```sql
select customer_id, id, created_at from (
  select o.customer_id, o.id, o.created_at,
         row_number() over (partition by o.customer_id order by o.created_at desc) as rn
  from orders o join customer c on c.id = o.customer_id where c.tier = 'GOLD') x
where rn <= 3;
```

**Output (verified, excerpt):**

```text
 Subquery Scan on x (actual time=111.924..121.440 rows=3000.00 loops=1)
   Buffers: shared hit=14472 read=7936
   ->  WindowAgg (actual time=111.923..121.228 rows=3000.00 loops=1)
         Window: w1 AS (PARTITION BY o.customer_id ORDER BY o.created_at ROWS UNBOUNDED PRECEDING)
         Run Condition: (row_number() OVER w1 <= 3)
         ->  Gather Merge (actual time=111.913..120.069 rows=10113.00 loops=1)
               ->  Sort ...
                     ->  Hash Join ...
                           ->  Parallel Seq Scan on orders o (... rows=333333.33 loops=3)
```

It reads **all 1 M orders** (22,408 buffers). PostgreSQL 15+ adds the `Run Condition`, which stops computing `row_number()` for a partition after 3, but every row is still scanned and joined.

### 3.2 `LATERAL` version: N index probes (verified)

```sql
select c.id as customer_id, o.id, o.created_at
from customer c
cross join lateral (select id, created_at from orders o
                    where o.customer_id = c.id order by o.created_at desc limit 3) o
where c.tier = 'GOLD';
```

**Output (verified):**

```text
 Nested Loop (actual time=0.941..27.886 rows=3000.00 loops=1)
   Buffers: shared hit=5123 read=1610 written=4
   ->  Seq Scan on customer c (actual time=0.015..4.689 rows=1000.00 loops=1)
         Filter: (tier = 'GOLD'::text)
   ->  Limit (actual time=0.015..0.023 rows=3.00 loops=1000)
         ->  Index Scan using orders_cust_created_incl on orders o (actual time=0.014..0.022 rows=3.00 loops=1000)
               Index Cond: (customer_id = c.id)
               Index Searches: 1000
```

**28 ms and 6,733 buffers vs 121 ms and 22,408 buffers**: one index probe per group, each reading only 3 entries from `(customer_id, created_at desc)`.

| Use | When |
|---|---|
| `LATERAL` + index | Few groups relative to rows, and an index on `(group_key, sort_key)` |
| `row_number()` | Most groups, or no suitable index; also for "Top-N across a big report" |
| `DISTINCT ON` (N = 1) | "Latest row per group", concise PostgreSQL syntax (below) |

```sql
select distinct on (customer_id) customer_id, id, created_at, amount
from orders where customer_id in (4242, 4243, 4244)
order by customer_id, created_at desc;
```

```text
 customer_id |   id   |       created_at       | amount
-------------+--------+------------------------+--------
        4242 | 603468 | 2026-07-29 07:24:00+00 | 358.75
        4243 | 919166 | 2026-11-15 22:13:00+00 | 473.10
        4244 | 938613 | 2026-11-22 16:16:30+00 | 472.19
```

---

## 4. Upserts without races 🔥

### 4.1 ❌ The naïve upsert

```java
// ❌ check-then-act: two requests both see "absent" and both INSERT -> duplicate key error (or duplicates without a constraint)
if (repo.findBySku(sku).isEmpty()) repo.save(new Inventory(sku, qty));
else repo.incrementQty(sku, qty);
```

### 4.2 ✅ `INSERT … ON CONFLICT` (verified)

```sql
create table inventory (sku text primary key, qty int not null, updated_at timestamptz not null default now());
insert into inventory values ('A', 10), ('B', 5);
-- idempotent "add stock": insert or increment; xmax = 0 means the row was inserted
insert into inventory as i (sku, qty) values ('A', 3), ('C', 7)
on conflict (sku) do update set qty = i.qty + excluded.qty, updated_at = now()
returning sku, qty, (xmax = 0) as inserted;
```

**Output (verified):**

```text
 sku | qty | inserted
-----+-----+----------
 A   |  13 | f
 C   |   7 | t
```

* `ON CONFLICT` is **atomic** with respect to the unique index: concurrent upserts serialize on the index entry. No race, no exception, no retry loop.
* `excluded` is the row you tried to insert.
* `(xmax = 0) as inserted` is a well-known PostgreSQL trick to tell inserts from updates in `RETURNING` (an updated row version carries a non-zero `xmax` lock marker). It relies on an implementation detail, so prefer `MERGE … RETURNING merge_action()` when available.
* `ON CONFLICT DO NOTHING` + `RETURNING` returns nothing for skipped rows. That's the core of the **idempotent consumer** table in [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md).

### 4.3 `MERGE` with `RETURNING merge_action()` (PostgreSQL 17+, verified)

```sql
merge into inventory i
using (values ('B', -5), ('C', 2), ('D', 4)) as s(sku, delta) on i.sku = s.sku
when matched and i.qty + s.delta <= 0 then delete
when matched then update set qty = i.qty + s.delta
when not matched then insert (sku, qty) values (s.sku, s.delta)
returning merge_action() as action, s.sku, i.qty;
```

**Output (verified):**

```text
 action | sku | qty
--------+-----+-----
 DELETE | B   |   5
 UPDATE | C   |   9
 INSERT | D   |   4
```

`MERGE` handles multi-branch logic (including **delete**) in one statement. Caveat: unlike `ON CONFLICT`, `MERGE` in PostgreSQL doesn't take a speculative-insertion path. Two concurrent `MERGE`s inserting the same new key can still hit a unique-violation error under READ COMMITTED. For "insert or update one key" under concurrency, `ON CONFLICT` remains the safer tool.

### 4.4 `RETURNING OLD` / `NEW` (PostgreSQL 18, verified) 🧊

PostgreSQL 18 lets `RETURNING` of `INSERT`, `UPDATE`, `DELETE` and `MERGE` reference both row versions. It replaces the `(xmax = 0)` trick from §4.2, and it removes the read-before-write that audit trails and "return the previous value" APIs used to need.

```sql
create table wallet (id int primary key, balance numeric(12,2) not null);
insert into wallet values (1, 100), (2, 50);

update wallet set balance = balance - 30 where id in (1, 2) and balance >= 30
returning id, old.balance as before, new.balance as after, new.balance - old.balance as delta;

insert into wallet values (2, 10), (3, 70) on conflict (id) do update set balance = wallet.balance + excluded.balance
returning id, old.balance as before, new.balance as after, (old.id is null) as inserted;

delete from wallet where id = 3 returning old.*, new.id as new_id;
```

**Output (verified, PostgreSQL 18.6):**

```text
 id | before | after | delta
----+--------+-------+--------
  1 | 100.00 | 70.00 | -30.00
  2 |  50.00 | 20.00 | -30.00

 id | before | after | inserted
----+--------+-------+----------
  2 |  20.00 | 30.00 | f
  3 |        | 70.00 | t

 id | balance | new_id
----+---------+--------
  3 |   70.00 |
```

* For an upsert, `old` is all-`NULL` for inserted rows: `old.id is null` is now a **supported** way to tell inserts from updates.
* For a `DELETE`, `new` is all-`NULL`; for an `INSERT` without conflict, `old` is.
* Use case: an outbox or audit row built in the same statement (`WITH changed AS (UPDATE … RETURNING old.*, new.*) INSERT INTO audit SELECT …`), atomic and without a second round trip.

### 4.5 `JSON_TABLE` (PostgreSQL 17+, verified)

```sql
select jt.* from (select '{"order":42,"lines":[{"sku":"A-1","qty":2,"price":9.5},{"sku":"B-7","qty":1,"price":30}]}'::jsonb as doc) d,
json_table(d.doc, '$.lines[*]' columns (line_no for ordinality, sku text path '$.sku', qty int path '$.qty', price numeric path '$.price')) as jt;
```

```text
 line_no | sku | qty | price
---------+-----+-----+-------
       1 | A-1 |   2 |   9.5
       2 | B-7 |   1 |    30
```

SQL-standard shredding of JSON into typed rows (no more `jsonb_array_elements` + `->>` + casts). Useful for loading API payloads or event bodies into relational tables in one `INSERT … SELECT`, with types enforced by the column list.

---

## 5. Recursive CTEs: hierarchies and graphs (verified) ⚡

```sql
create table category (id int primary key, parent_id int, name text);
insert into category values (1, null, 'root'), (2, 1, 'electronics'), (3, 2, 'phones'), (4, 3, 'android'), (5, 2, 'laptops');
update category set parent_id = 4 where id = 1;   -- oops: a data bug creates a cycle
with recursive tree(id, name, depth) as (
  select id, name, 0 from category where id = 2
  union all
  select c.id, c.name, t.depth + 1 from category c join tree t on c.parent_id = t.id
) cycle id set is_cycle using path
select id, name, depth, is_cycle, path from tree order by depth, id;
```

**Output (verified):**

```text
 id |    name     | depth | is_cycle |         path
----+-------------+-------+----------+-----------------------
  2 | electronics |     0 | f        | {(2)}
  3 | phones      |     1 | f        | {(2),(3)}
  5 | laptops     |     1 | f        | {(2),(5)}
  4 | android     |     2 | f        | {(2),(3),(4)}
  1 | root        |     3 | f        | {(2),(3),(4),(1)}
  2 | electronics |     4 | t        | {(2),(3),(4),(1),(2)}
```

Without the `CYCLE` clause (PostgreSQL 14+), that query **never terminates**. Production hierarchy queries need cycle protection (`CYCLE`, or a depth limit) because data bugs happen. For deep, frequently read trees, consider the alternatives: materialized paths (`ltree`), closure tables, or nested sets.

### 5.1 Temporal primary keys: `WITHOUT OVERLAPS` (PostgreSQL 18, verified) 🧊

"No two bookings of the same room may overlap" used to need a hand-written `EXCLUDE USING gist` constraint ([2.2 §5.3](02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)). PostgreSQL 18 makes it a declarative key:

```sql
create extension if not exists btree_gist;        -- needed for the scalar part (room_id) in a GiST index
create table room_booking (room_id int, during tstzrange, guest text, primary key (room_id, during without overlaps));
insert into room_booking values (101, '[2026-11-01 14:00+00, 2026-11-03 11:00+00)', 'ada');
insert into room_booking values (101, '[2026-11-03 11:00+00, 2026-11-05 11:00+00)', 'bob');   -- touches, doesn't overlap: OK
insert into room_booking values (101, '[2026-11-04 14:00+00, 2026-11-06 11:00+00)', 'cy');    -- overlaps bob
```

**Output (verified, PostgreSQL 18.6):**

```text
ERROR:  conflicting key value violates exclusion constraint "room_booking_pkey"
DETAIL:  Key (room_id, during)=(101, ["2026-11-04 14:00:00+00","2026-11-06 11:00:00+00")) conflicts with existing key (room_id, during)=(101, ["2026-11-03 11:00:00+00","2026-11-05 11:00:00+00")).

            conname            |              pg_get_constraintdef
-------------------------------+------------------------------------------------
 room_booking_during_not_null  | NOT NULL during
 room_booking_pkey             | PRIMARY KEY (room_id, during WITHOUT OVERLAPS)
 room_booking_room_id_not_null | NOT NULL room_id

     indexrelid    | amname
-------------------+--------
 room_booking_pkey | gist
```

* The key is enforced by a **GiST** index (equality on `room_id`, overlap `&&` on `during`), the same machinery as `EXCLUDE`, but it's now a real primary key that foreign keys can reference with `PERIOD` (temporal foreign keys, also PG 18). Verified: with `rate (room_id, valid … primary key (room_id, valid without overlaps))` covering November and `foreign key (room_id, period during) references rate (room_id, period valid)`, a booking for 10–12 November was accepted and one for 29 November – 3 December was rejected: `Key (room_id, during)=(101, ["2026-11-29 …","2026-12-03 …")) is not present in table "rate"`. The referenced periods must **cover** the referencing range.
* Half-open ranges `[start, end)` let consecutive bookings touch without conflicting (`ada` → `bob` was accepted).
* Also visible: PostgreSQL 18 stores **`NOT NULL` as named constraints** in `pg_constraint` (`room_booking_during_not_null`).
* Interview angle: this is the race-free answer to "two users booked the same room": the database rejects the overlap even under concurrent inserts, no application lock needed ([2.6](06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)).

---

## 6. ❌ Naïve vs ✅ production-hardened SQL patterns

| ❌ Naïve | ✅ Hardened |
|---|---|
| `LIMIT ? OFFSET ?` for infinite scroll and exports | Keyset with a unique tiebreaker and a matching index (5 buffers vs 16,615) |
| Load all orders, keep 3 per customer in Java | `LATERAL` + `(customer_id, created_at desc)` index |
| `sum(...) over (order by ts)` for balances | `ROWS` frame + unique tiebreaker |
| Check-then-insert upsert in application code | `INSERT … ON CONFLICT`; `MERGE` for multi-branch logic |
| Recursive CTE without cycle protection | `CYCLE` clause or depth limit |
| Several queries for several metrics | One pass with `FILTER` |
| Daily report that hides missing days | `generate_series` + `LEFT JOIN` |

---

## 7. Interview soundbites

* "OFFSET is O(offset). Page 25,001 read 16,615 buffers in 140 ms; keyset read 5 in 0.02 ms and returned the same rows."
* "Keyset needs a unique sort key, so I add the id as a tiebreaker and compare row values."
* "The default window frame is RANGE, so tied rows share a running total. For balances I use ROWS with a unique ORDER BY."
* "Top-N per group: LATERAL with an index probe per group when groups are few, `row_number()` when they're many."
* "Upserts belong in the database: `ON CONFLICT` is atomic on the unique index, and `MERGE … RETURNING merge_action()` handles insert, update and delete in one statement."
* "PostgreSQL 18's `RETURNING old.*, new.*` gives before and after values in the same statement: audit rows and 'previous value' APIs without a read-before-write."
* "Double bookings: `PRIMARY KEY (room_id, during WITHOUT OVERLAPS)` in PG 18. The overlapping insert failed with a key violation; touching ranges were fine."

---

## Summary

| Pattern | Use it for | Verified evidence |
|---|---|---|
| Ranking functions | `row_number` / `rank` / `dense_rank` differ only on ties | tie behavior table (§1.1) |
| Window frames | Default `RANGE` frame makes peers share a running total; use `ROWS` + unique order | §1.2 |
| Gaps and islands | `value − row_number()` groups consecutive runs | §1.4 |
| `FILTER` aggregates | Several metrics in one pass | §1.5 |
| Keyset pagination | `(sort_key, id) > (?, ?)` with a matching index | 5 buffers vs 16,615 for OFFSET at page 25,001 |
| Top-N per group | `LATERAL` + index when groups are few; `row_number()` when many | §3 |
| Upsert | `INSERT … ON CONFLICT` (atomic); `MERGE … RETURNING merge_action()` (multi-branch) | §4.2–4.3 |
| `RETURNING OLD/NEW` (PG 18) | Before/after values; insert-vs-update detection | `old.id is null` = inserted |
| `JSON_TABLE` (PG 17) | Typed shredding of JSON into rows | 2 typed rows from a document |
| Recursive CTE | Hierarchies with `CYCLE` protection | cycle detected at depth 4 |
| `WITHOUT OVERLAPS` (PG 18) | Race-free non-overlapping ranges as a primary key | overlapping booking rejected; GiST-backed |

**Next:** [2.5 MVCC, vacuum and wraparound →](05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)
