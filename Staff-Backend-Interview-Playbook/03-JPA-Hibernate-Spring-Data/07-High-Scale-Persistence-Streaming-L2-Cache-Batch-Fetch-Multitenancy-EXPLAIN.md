# 3.7 High-Scale Persistence: Streaming Millions of Rows, the Second-Level Cache, Batch-Fetch SQL, Multi-Tenancy, and EXPLAIN of ORM-Generated SQL

> **Verified stack:** Hibernate ORM **7.4.13.Final**, pgjdbc **42.7.14**, HikariCP **7.0.2**, Caffeine JCache **3.2.4** (`hibernate-jcache`), PostgreSQL **18.6** with `pg_stat_statements` 1.12, JDK 25. Every lab ran in its own JVM, one at a time. SQL lines are what Hibernate sent (captured through a counting `DataSource` proxy); out-of-memory outcomes, statement counts and cache statistics are deterministic; times are one measured run.
>
> **Prereqs:** [3.1 Persistence context](01-Persistence-Context-Entity-States-Dirty-Checking.md), [3.3 Fetching](03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md), [3.4 Write throughput](04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md) (bulk inserts, `COPY`, StatelessSession writes are there; this file is about **reads, caching and isolation at scale**). Plan reading: [2.9](../02-SQL-RDBMS-Internals/09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md)/[2.10](../02-SQL-RDBMS-Internals/10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md).

---

## 0. First principles: an ORM at scale fails on memory and on invisible state 🔥

An ORM is optimized for a **unit of work**: load a small graph, change it, flush. At scale, three things break that model:

1. **Memory is proportional to what you touched, not what you kept.** Every managed entity carries an identity-map entry, an `EntityEntry` and a **snapshot** for dirty checking ([3.1](01-Persistence-Context-Entity-States-Dirty-Checking.md)), and the JDBC driver may have buffered the whole result before your loop even starts.
2. **Caches and filters are invisible state.** A second-level cache, a tenant filter or a query cache changes what SQL runs (or whether any runs) without the code at the call site changing.
3. **The database sees the ORM's SQL, not your intent.** IN lists, batch fetches and pagination rewrites produce SQL shapes whose plans, plan caches and statistics you must read like any other SQL.

---

## 1. Streaming 1,000,000 rows in a 256 MB heap (verified) 🔥

`s_purchase`: 1,000,000 rows (id, customer_id, status, total, created_at, note). Each variant reads all rows and sums `total`, in its **own JVM with `-Xmx256m`**, reporting peak heap (sum of heap pools' peak usage) or the error:

```java
// the eight variants; each loop body only sums p.total, and each variant ran in a fresh JVM
s.createSelectionQuery("from Purchase", Purchase.class).getResultList()                                   // getResultList
s.createSelectionQuery("from Purchase", Purchase.class).getResultStream()                                  // stream
s.createSelectionQuery("from Purchase", Purchase.class).setFetchSize(1000).getResultStream()               // stream+fetchSize
...setFetchSize(1000).getResultStream() + s.clear() every 1,000 rows                                        // stream+fetchSize+clear
ss.createSelectionQuery("from Purchase", Purchase.class).setFetchSize(1000).scroll(ScrollMode.FORWARD_ONLY) // StatelessSession
s.createSelectionQuery("select p.total from Purchase p", BigDecimal.class).setFetchSize(1000).getResultStream() // projection
plain JDBC: st.setFetchSize(1000) with autocommit ON  /  with autocommit OFF (inside a transaction)
```

**Output (verified, one JVM per line, `-Xmx256m`):**

```text
getResultList                FAIL rows=        0  time= 6,770 ms  peak heap= 247 MB  OutOfMemoryError: Java heap space
stream                       FAIL rows=        0  time= 7,490 ms  peak heap= 247 MB  OutOfMemoryError: Java heap space
stream+fetchSize             FAIL rows=  393,216  time= 5,814 ms  peak heap= 247 MB  OutOfMemoryError: Java heap space
stream+fetchSize+clear       OK   rows=1,000,000  time= 2,090 ms  peak heap=  83 MB
stateless+scroll             OK   rows=1,000,000  time= 2,059 ms  peak heap=  82 MB
dto-projection+fetchSize     OK   rows=1,000,000  time=   677 ms  peak heap=  80 MB
jdbc fetchSize, autocommit   FAIL rows=        0  time= 6,092 ms  peak heap= 247 MB  OutOfMemoryError: Java heap space
jdbc fetchSize, in tx        OK   rows=1,000,000  time=   702 ms  peak heap=  79 MB
```

Reading it, failure by failure:

| Variant | Where the memory went | Mechanism |
|---|---|---|
| `getResultList` | Died at **row 0** | pgjdbc's default `fetchSize = 0` means "read the **entire** result into memory" before returning the first row |
| `getResultStream()` | Also **row 0** | A `Stream` API doesn't change the driver: without a fetch size it's the same full read. Streaming is a JDBC setting, not a return type |
| `+ setFetchSize(1000)` | Died at **393,216 rows** | The driver now streams 1,000 rows at a time (a server-side cursor), but the **persistence context keeps every entity and its snapshot**. Memory grows with rows processed |
| `+ clear()` every 1,000 | **83 MB, OK** | Detaching processed entities lets the GC reclaim them |
| StatelessSession + scroll | **82 MB, OK** | No persistence context at all: entities are plain objects, nothing is retained |
| Projection | **80 MB, 677 ms** | No entities, no snapshots: **3× faster** than entity streaming |
| JDBC, fetch size, autocommit **on** | Died at **row 0** | **pgjdbc ignores the fetch size when autocommit is on**: the cursor (portal) must live inside a transaction |
| JDBC, fetch size, autocommit **off** | **79 MB, 702 ms** | Real cursor-based streaming |

**Production rules this proves:**
* "Streaming" in PostgreSQL needs **three** things: a fetch size, a transaction (autocommit off), and code that doesn't retain what it processed. Spring's `@Transactional(readOnly = true)` gives you the transaction; `Stream`/`ScrollableResults` without `setFetchSize` gives you nothing. (Spring Data's `Stream<T>` repository methods need a `@QueryHints(@QueryHint(name = HINT_FETCH_SIZE, value = "1000"))` for the same reason.)
* For exports and batch jobs, prefer **projections or StatelessSession** to entities; entities are for units of work.
* A `-Xmx256m` lab makes the failure obvious. In production the same mistake shows up as GC pressure and a 4 GB heap that "needed to be 8 GB".

---

## 2. The second-level cache: hits, invalidation and staleness (verified) ⚡

Setup: `Product` (`@Cacheable`, `@Cache(usage = READ_WRITE)`, `@NaturalId sku`, `@NaturalIdCache`) and an unrelated cached `Category`, with JCache backed by Caffeine:

```properties
hibernate.cache.use_second_level_cache=true
hibernate.cache.use_query_cache=true
hibernate.cache.region.factory_class=jcache
hibernate.javax.cache.provider=com.github.benmanes.caffeine.jcache.spi.CaffeineCachingProvider
hibernate.javax.cache.missing_cache_strategy=create
hibernate.generate_statistics=true
```

Each step runs in a **new session** (new persistence context), after `Statistics.clear()`:

**Output (verified):**

```text
1. find(Product, 1) in session A                               SQL=1  L2 hit/miss/put=0/1/1  query-cache hit/miss=0/0  natural-id hit/miss=0/0
2. find(Product, 1) in a new session B                         SQL=0  L2 hit/miss/put=1/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
3. bySimpleNaturalId(Product).load("SKU-1"), new session       SQL=0  L2 hit/miss/put=1/0/0  query-cache hit/miss=0/0  natural-id hit/miss=1/0
4. same natural-id load again, new session                     SQL=0  L2 hit/miss/put=1/0/0  query-cache hit/miss=0/0  natural-id hit/miss=1/0
5. cacheable query 'price > 15', first run                     SQL=1  L2 hit/miss/put=0/0/2  query-cache hit/miss=0/1  natural-id hit/miss=0/0
6. same cacheable query, second run                            SQL=0  L2 hit/miss/put=0/0/0  query-cache hit/miss=1/0  natural-id hit/miss=0/0
7. JPQL bulk update of Product id=2 (same tx: nothing read)    SQL=1  L2 hit/miss/put=0/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
8. cached query again after the bulk update                    SQL=1  L2 hit/miss/put=0/0/2  query-cache hit/miss=0/1  natural-id hit/miss=0/0
9. find(Product, 1) after the bulk update                      SQL=1  L2 hit/miss/put=0/1/1  query-cache hit/miss=0/0  natural-id hit/miss=0/0
10. find(Category, 1): unrelated region, still cached?         SQL=0  L2 hit/miss/put=1/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
11. native UPDATE c_product (no synchronization declared)      SQL=1  L2 hit/miss/put=0/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
12. find(Category, 1) after the native update                  SQL=1  L2 hit/miss/put=0/1/1  query-cache hit/miss=0/0  natural-id hit/miss=0/0
13. native UPDATE with addSynchronizedEntityClass(Product)     SQL=1  L2 hit/miss/put=0/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
14. find(Category, 1) after the synchronized native update     SQL=0  L2 hit/miss/put=1/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
15. find(Product, 1) after an out-of-band JDBC update          SQL=0  L2 hit/miss/put=1/0/0  query-cache hit/miss=0/0  natural-id hit/miss=0/0
    entity price via Hibernate (L2) = 10.00, price in the database = 999.00
```

### 2.1 What each line teaches

* **1–2: the entity cache.** Session A missed and put; session B got the entity with **zero SQL**. The L2 cache stores entities in a **disassembled** form (arrays of property values), not your Java objects, so each session gets its own instance.
* **3–4: natural-id cache.** Loading by `sku` cost zero SQL: the natural-id → id resolution was cached when the entity was loaded, then the entity itself came from the entity cache. This is the cache that makes "look up product by SKU" cheap.
* **5–6: query cache.** The second run executed **no SQL**: the query cache stores the **ids** of the result and re-reads each entity from the entity cache (`put=2` on the first run). A cached query whose entities aren't in the entity cache would do one SQL per row: the query cache **requires** the entity cache.
* **7–9: bulk JPQL invalidates by region.** After `update Product …`, the cached query re-ran (`query-cache miss`) and even `Product 1`, which the update didn't touch, was **evicted** (`miss`): Hibernate can't know which rows a bulk statement changed, so it evicts the whole `Product` region and bumps its update timestamp (which invalidates every cached query that read `Product`).
* **10: other regions survive** a JPQL bulk update: Hibernate knows the statement only touched `Product`.
* **11–12: a native `UPDATE` without synchronization evicts the entire second-level cache.** `Category` was evicted by an update to `c_product`. Hibernate can't parse arbitrary SQL, so it plays safe and clears **every** region. In a system with heavy native SQL, the L2 cache may be useless and nobody notices.
* **13–14: `addSynchronizedEntityClass(Product.class)`** (on `NativeQuery`; Hibernate 7's `createNativeMutationQuery` returns a `MutationQuery` without it) limits eviction to `Product`; `Category` stayed cached.
* **15: the cache is only as correct as the writers you control.** An update through plain JDBC (another service, a migration, a `psql` session) left the cache returning **10.00** while the database said **999.00**. `READ_WRITE` concurrency only coordinates writers **inside this JVM**.

### 2.2 Operational facts verified in the same lab

* **Caffeine's JCache defaults are unbounded:** its `reference.conf` sets `maximum.size = null` and expiry `eternal` for the default cache. Without configuration, every L2 region grows forever. Configure `caffeine.jcache.<region> { maximum.size = …, expire-after-write = … }`.
* **Region names come from the entity's class name.** For nested classes (`CacheLab$Product`) Caffeine's Typesafe-config lookup logged `ConfigException$BadPath: … Token not allowed in path expression: 'P' ('$' not followed by {…` and silently fell back to defaults. Name regions explicitly: `@Cache(region = "product", usage = READ_WRITE)`.

### 2.3 When to use it (and when not)

| Good fit | Poor fit |
|---|---|
| Reference data read by id or natural id (products, currencies, configuration) | Data also written by other services or SQL scripts (stale reads, §2 line 15) |
| One application owns all writes, or a clustered/invalidating cache (Infinispan, Hazelcast) with the same guarantees | Tables updated with native SQL or bulk statements (whole-region or whole-cache evictions) |
| Read-mostly, small to medium entities | Huge collections; per-user data; anything needing strong cross-node consistency |

The query cache in particular: useful for **small, rarely changing result sets** (lookup lists); harmful for queries over frequently updated entities, because every write to the region invalidates them and you pay put/invalidation overhead on every request.

---

## 3. What batch fetching and IN lists look like on the wire (verified) ⚡

### 3.1 Batch fetching sends `= any (?)`

```java
// default_batch_fetch_size = 16; 40 orders with 40 distinct lazy customers
List<SalesOrder> orders = s.createSelectionQuery("from SalesOrder o where o.id <= 40 order by o.id", SalesOrder.class).getResultList();
orders.forEach(o -> o.customer.getName().length());
```

**Output (verified, Hibernate 7.4.13):**

```text
  SQL> select so1_0.id,so1_0.customer_id,so1_0.total from x_order so1_0 where so1_0.id<=40 order by so1_0.id
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id = any (?)
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id = any (?)
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id = any (?)
  round trips: 4
```

* 1 + **3** queries (16 + 16 + 8 customers) instead of 1 + 40. On PostgreSQL, Hibernate 7 binds the ids as **one array parameter** (`= any (?)`), so the SQL text is **identical for every batch size**: one entry in Hibernate's query plan cache, one server-side prepared statement in pgjdbc, one row in `pg_stat_statements`.
* (A side note the lab reproduced by accident: reading `o.customer.name` as a **field** returned `null` from the uninitialized proxy and threw an NPE; calling `getName()` initializes it. That's the trap in [3.1 §3](01-Persistence-Context-Entity-States-Dirty-Checking.md).)

What PostgreSQL does with it (atlas `customers`, 16 ids):

```sql
explain (generic_plan) select c1_0.id, c1_0.email from customers c1_0 where c1_0.id = any ($1);
explain (analyze, buffers) select c1_0.id, c1_0.email from customers c1_0
where c1_0.id = any ('{38,75,12,49,86,23,60,97,34,71,8,45,82,19,56,93}'::bigint[]);
```

```text
 Index Scan using customers_pkey on customers c1_0  (cost=0.42..48.38 rows=10 width=30)
   Index Cond: (id = ANY ($1))

 Index Scan using customers_pkey on customers c1_0  (cost=0.42..75.00 rows=16 width=30) (actual time=0.060..0.062 rows=16.00 loops=1)
   Index Cond: (id = ANY ('{38,75,12,49,86,23,60,97,34,71,8,45,82,19,56,93}'::bigint[]))
   Index Searches: 1
   Buffers: shared read=4
```

* The generic plan (what the prepared statement converges to) is the right one: an index scan with `= ANY ($1)`; its estimate is a default (10 rows) since the array is unknown.
* **16 rows, 1 index descent, 4 buffers.** Since PostgreSQL 17, the B-tree scan of a `= ANY` array advances through array values on the same leaf page without re-descending; ids that are close together cost one descent. The same 16 customers loaded one by one (N+1) would cost 16 round trips × 4 buffers. Widely spread ids still need one descent each ([2.9 §7.2](../02-SQL-RDBMS-Internals/09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#72-in-lists-one-descent-per-value): 4 values, `Index Searches: 4`).

### 3.2 JPQL `in :ids` expands; padding buckets it

```java
s.createSelectionQuery("from Customer c where c.id in :ids", Customer.class).setParameter("ids", ids)   // 3, 5, 9 ids
```

**Output (verified):**

```text
-- default
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id in (?,?,?)
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id in (?,?,?,?,?)
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id in (?,?,?,?,?,?,?,?,?)
-- hibernate.query.in_clause_parameter_padding = true
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id in (?,?,?,?)
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id in (?,?,?,?,?,?,?,?)
  SQL> select c1_0.id,c1_0.name from x_customer c1_0 where c1_0.id in (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
```

Without padding, every distinct list length is a **different SQL string**: a new entry in Hibernate's query plan cache and a new pgjdbc server-side prepared statement per length (an API that accepts 1–1,000 ids creates up to 1,000 of each). Padding rounds up to the next power of two (repeating the last value), so 1–1,000 ids produce at most 10 shapes. The alternative that needs no setting: pass an array (`where c.id = any(:ids)` via a native query or a typed array parameter) so there's only one shape.

### 3.3 How PostgreSQL 18's `pg_stat_statements` sees IN lists

The same three list lengths, sent as bind parameters, as literals, and as one array parameter:

```text
B. pg_stat_statements after IN lists of 3, 5 and 9 bind parameters, and of 3, 5 and 9 literals
  calls=3  select count(*) from x_probe /*array*/ where id = any ($1)
  calls=6  select count(*) from x_probe /*bind*/ where id in ($1 /*, ... */)
```

**PostgreSQL 18 squashes IN lists** in `pg_stat_statements`: lists of 3, 5 and 9 bind parameters **and** of 3, 5 and 9 literals all landed in **one** entry (`in ($1 /*, ... */)`, 6 calls; the literal variant's comment was ignored because comments aren't part of the query id). On PG ≤ 17 each length is a separate entry, which is how monitoring dashboards end up with thousands of "different" queries. Padding still matters on PG 18 for Hibernate's own plan cache and pgjdbc's prepared statements; for `pg_stat_statements` it no longer does.

---

## 4. Pagination SQL from the ORM, through EXPLAIN (verified) 🧊

[3.3 §4.2](03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md) showed that Hibernate 7.4 paginates `join fetch` queries with a derived table. The same SQL shape on the atlas dataset (1 M orders, 3 M lines):

```sql
select po1_0.id, po1_0.customer_id, l1_0.order_id, l1_0.line_no, l1_0.qty, l1_0.product_id
from (select po1_0.id, po1_0.customer_id from orders po1_0
      where exists(select 1 from order_lines l1_0 where po1_0.id = l1_0.order_id)
      order by po1_0.id offset 100000 rows fetch first 5 rows only) po1_0(id, customer_id)
join order_lines l1_0 on po1_0.id = l1_0.order_id order by po1_0.id;
```

**Output (PostgreSQL 18.6, one measured run, page 20,001):**

```text
 Nested Loop  (cost=21066.38..21135.95 rows=19 width=40) (actual time=73.532..73.548 rows=15.00 loops=1)
   Buffers: shared hit=231 read=2397 written=2
   ->  Limit  (cost=21065.95..21067.00 rows=5 width=16) (actual time=72.793..72.798 rows=5.00 loops=1)
         ->  Merge Semi Join  (cost=12.32..166741.69 rows=791927 width=16) (actual time=0.017..70.827 rows=100005.00 loops=1)
               Merge Cond: (po1_0.id = l1_0_1.order_id)
               ->  Index Scan using orders_pkey on orders po1_0  (… rows=100005.00 loops=1)
               ->  Index Only Scan using order_lines_pkey on order_lines l1_0_1  (… rows=300015.00 loops=1)
   ->  Index Scan using order_lines_pkey on order_lines l1_0  (cost=0.43..13.75 rows=4 width=24) (actual time=0.148..0.148 rows=3.00 loops=5)
         Index Cond: (order_id = po1_0.id)
```

| Page | Plan of the derived table | Time | Buffers |
|---|---|---:|---:|
| 1 (`offset 0`) | Nested Loop Semi Join, stops after 5 orders | 0.15 ms | 40 |
| 20,001 (`offset 100000`) | **Merge Semi Join over 100,005 orders and 300,015 lines** | 73.6 ms | 2,628 |
| Keyset (`where po1_0.id > 100000`, no offset) | Nested Loop Semi Join, 5 orders | **0.06 ms** | 43 |

* The derived table fixes Hibernate's in-memory pagination, but it's still **`OFFSET`**: to skip 100,000 orders the database must also prove each one has lines (`EXISTS`), so it walks 300,015 line-index entries too. Deep pages of fetch-joined entities are more expensive than deep pages of plain rows.
* `rows=791927` on the semi join is an estimate artifact: the planner assumes ~79 % of orders have lines (here every order does); the `EXISTS` only makes sense for an inner `join fetch` (a `left join fetch` drops it).
* Keyset with the same SQL shape (`id > :lastSeen`) costs the same on page 20,001 as on page 1.

---

## 5. Discriminator multi-tenancy with `@TenantId` (verified) ⚡

```java
@Entity @Table(name = "x_invoice")
public class Invoice { @Id Long id; @TenantId String tenant; String number; }

try (var s = sf.withOptions().tenantIdentifier((Object) "acme").openSession()) { ... }   // in Spring: a CurrentTenantIdentifierResolver
```

Two `acme` invoices and one `globex` invoice; then, in an `acme` session:

**Output (verified, Hibernate 7.4.13):**

```text
  SQL> select i1_0.id,i1_0.number,i1_0.tenant from x_invoice i1_0 where i1_0.tenant = ? order by i1_0.id
  JPQL 'from Invoice' -> [ACME-1, ACME-2]
  SQL> select i1_0.id,i1_0.number,i1_0.tenant from x_invoice i1_0 where i1_0.id=? and i1_0.tenant = ?
  find(Invoice, 3) [globex's row] -> null
  SQL> update x_invoice i1_0 set number=(i1_0.number||'*') where i1_0.tenant = ?
  JPQL bulk update -> 2 rows
  SQL> select count(*) from x_invoice
  native 'select count(*) from x_invoice' -> 3
```

* `@TenantId` sets the column on `persist` and adds `tenant = ?` to **JPQL queries, `find()` by id, and bulk updates**. `find()` of another tenant's id returned `null`, not the row.
* **Native SQL isn't filtered**: `select count(*)` saw all 3 rows. Every native query, every JDBC/jOOQ path, every reporting job and every `psql` session is outside the guarantee.
* **Defense in depth:** PostgreSQL **row-level security** keyed on a session setting (`create policy tenant_isolation on x_invoice using (tenant = current_setting('app.tenant'))`, with the app setting `app.tenant` per transaction) enforces isolation for native SQL too, and FORCE ROW LEVEL SECURITY covers the table owner. Index every tenant-scoped table with `tenant` as the **leading** column, and include it in unique constraints.
* Choosing a model: discriminator column (cheapest, weakest isolation, one schema to migrate) → schema per tenant (stronger, migrations × tenants, catalog bloat with thousands of schemas) → database per tenant (strongest, connection-pool fan-out problem). Hibernate supports all three (`@TenantId`; `MultiTenantConnectionProvider` for schema/database).

---

## 6. Observability for ORM SQL at scale ⚡

| Tool | What it gives you | Verified |
|---|---|---|
| `hibernate.log_slow_query = 25` (ms) | `org.hibernate.SQL_SLOW` log line with the SQL | `Slow query took 67 milliseconds [select pg_sleep(0.05)]` |
| `hibernate.generate_statistics = true` | Per-session-factory counters: queries, entity loads, L2 hit/miss/put, query-cache hit/miss | §2 output |
| A counting `DataSource` proxy (datasource-proxy, p6spy) | Exact statements and round trips per request; N+1 detection in tests | Used for every count in this file |
| `pg_stat_statements` (PG 18 squashes IN lists) | Server-side cost per normalized statement | §3.3 |
| `EXPLAIN (GENERIC_PLAN)` on the logged SQL | The plan a prepared statement will use | §3.1 |

Turn statistics into **assertions** in integration tests: "this endpoint issues ≤ 3 statements" catches N+1 regressions at build time, which is cheaper than finding them in `pg_stat_statements` later.

---

## 7. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| `getResultList()` / `findAll()` for exports | Projection or StatelessSession + `setFetchSize`, inside a read-only transaction |
| "We return a `Stream`, so it streams" | Fetch size **and** a transaction **and** no retention (`clear()` or stateless): three verified OOMs otherwise |
| JDBC `setFetchSize` with autocommit on | Autocommit off (pgjdbc ignores fetch size otherwise) |
| Enable L2 cache with defaults | Bounded, expiring regions with explicit names; measure hit ratios |
| Native SQL updates with L2 enabled | `addSynchronizedEntityClass` on every native mutation, or no L2 for those entities |
| L2 cache on data other services write | No L2, or a cache with external invalidation (CDC → evict) |
| Cache every query | Query cache only for small, rarely changing results |
| IN lists of arbitrary length | Array parameters, or `in_clause_parameter_padding` |
| `@TenantId` as the only isolation | + RLS policies, tenant-leading indexes, tests that run every native query per tenant |
| Deep `join fetch` pagination with offset | Keyset on the parent id; two-step (ids, then fetch) |

---

## 8. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [hibernate/hibernate-orm](https://github.com/hibernate/hibernate-orm) | `hibernate-core/src/main/java/org/hibernate/engine/spi/BatchFetchQueue.java` | How pending proxies are grouped into batches |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/loader/ast/internal/` (`EntityBatchLoaderArrayParam`) | The `= any (?)` array batch loader |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/cache/spi/` and `…/action/internal/BulkOperationCleanupAction.java` | Region eviction for bulk and native statements (§2 lines 7–14) |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/binder/internal/TenantIdBinder.java` | How `@TenantId` becomes a filter |
| [pgjdbc/pgjdbc](https://github.com/pgjdbc/pgjdbc) | `pgjdbc/src/main/java/org/postgresql/jdbc/PgStatement.java` | Where `fetchSize` is ignored unless autocommit is off |
| [ben-manes/caffeine](https://github.com/ben-manes/caffeine) | `jcache/src/main/resources/reference.conf` | The unbounded, eternal defaults (§2.2) |
| [postgres/postgres](https://github.com/postgres/postgres) | `src/backend/nodes/queryjumblefuncs.c` (+ `contrib/pg_stat_statements/`) | PG 18's squashing of constant/parameter lists in the query id: why IN lists of any length share one entry |

---

## 9. Interview soundbites

* "Streaming in PostgreSQL needs a fetch size, a transaction and no retention. In a 256 MB heap, `getResultList`, a `Stream` without fetch size, and JDBC with autocommit on all died before the first row; fetch size alone died at 393,216 rows; adding `clear()` or a StatelessSession finished at 83 MB."
* "A cached query stores ids; a bulk JPQL update evicts the whole entity region; a native update without `addSynchronizedEntityClass` evicts the entire L2 cache. And a write that bypasses Hibernate leaves the cache serving stale data: we saw 10.00 against 999.00."
* "Caffeine's JCache defaults are unbounded and never expire. Configure every region."
* "Hibernate 7 batch-fetches with `= any (?)`: one SQL shape for every batch size. PG 17+ resolved 16 nearby ids in one index descent and 4 buffers."
* "PostgreSQL 18's `pg_stat_statements` folds IN lists of any length into one entry; padding still helps Hibernate's plan cache and pgjdbc's prepared statements."
* "`@TenantId` filters JPQL, `find` and bulk updates, but a native count saw every tenant's rows. Row-level security is the backstop."

---

## Summary

| Topic | The rule | Verified evidence |
|---|---|---|
| Streaming reads | Fetch size + transaction + no retention | 4 OOM variants vs 4 OK variants at `-Xmx256m`; projections 3× faster than entities |
| L2 entity cache | Disassembled state per region; `READ_WRITE` coordinates only in-JVM writers | 0 SQL on hit; stale 10.00 vs 999.00 after an out-of-band write |
| Natural-id cache | Natural id → id → entity, no SQL | 2 loads by SKU, 0 SQL |
| Query cache | Caches ids; needs the entity cache; invalidated by region timestamps | 0 SQL on hit; re-executed after a bulk update |
| Invalidation | Bulk JPQL: whole region; native SQL: whole cache unless synchronized | `Category` evicted by an unsynchronized native update to `c_product` |
| Caffeine JCache | Defaults unbounded and eternal; `$` in region names breaks config | `maximum.size = null`; `ConfigException$BadPath` |
| Batch fetching | `= any (?)` array parameter, one SQL shape | 1 + 3 queries for 40 proxies; 1 descent, 4 buffers for 16 ids |
| IN lists | Expand per length; padding rounds to powers of two | 3/5/9 → 4/8/16 parameters |
| `pg_stat_statements` (PG 18) | IN lists squashed into one entry | 6 calls (3 lengths × bind/literal) in one row |
| Fetch-join pagination | 7.4's derived table still uses OFFSET + EXISTS | page 20,001: 73.6 ms / 2,628 buffers vs keyset 0.06 ms / 43 |
| `@TenantId` | Filters JPQL, `find`, bulk updates; not native SQL | `find` of another tenant → null; native count → 3 |
| Slow-query log | `hibernate.log_slow_query` | `Slow query took 67 milliseconds` |

**Next:** [3.6 Bar-raiser drill-downs (Round 2 covers this file) →](06-Bar-Raiser-Drill-Downs.md)
