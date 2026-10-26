# 3.6 Bar-Raiser Drill-Downs: JPA, Hibernate & Spring Data

> Evidence for every defense is in [3.1](01-Persistence-Context-Entity-States-Dirty-Checking.md)–[3.5](05-Transactional-Propagation-Isolation-Pitfalls.md), run on Hibernate 7.4.13 / Spring 7.0.10 / PostgreSQL 18.6. Answer each probe aloud before opening the defense.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "The order-history endpoint takes 900 ms. It's simple CRUD." 🔥

🎤 *"We'll add a cache in front of it."*

🔍 **Probe 1: Before caching, what's your first measurement?**

<details><summary>🛡️ Defense</summary>

Count statements per request. A trace with one span per JDBC statement, or a datasource-proxy/Hibernate-statistics counter in a test. A "simple" endpoint that issues 151 statements is an N+1. Verified ([3.3 §1](03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)): 10 orders + a lazy `customer` = **11 statements**, and the same again for `lines`. At 0.5–1 ms per round trip across availability zones, that's hundreds of milliseconds of pure waiting. Caching would hide it until the cache misses.
</details>

🔍 **Probe 2: Fix it without rewriting every query.**

<details><summary>🛡️ Defense</summary>

Set `hibernate.default_batch_fetch_size` (16–64) globally: every lazy association loads in batches. Verified: **11 → 2 statements**, using one `= any(?)` array parameter on PostgreSQL. Then fix the hot path properly: an entity graph or `JOIN FETCH` for exactly what this endpoint needs, or better, a **DTO projection** (verified: only the needed columns, zero managed entities).
</details>

🔍 **Probe 3: The JSON shows customer data, but the service never touches `customer`. Where do the queries come from?**

<details><summary>🛡️ Defense</summary>

From the **serializer**, via **Open Session In View** (Spring Boot's default `spring.jpa.open-in-view=true`): the session stays open through view rendering, so Jackson's getter calls trigger lazy loads outside the service's transaction, each holding a pooled connection for the whole request. Turn OSIV off, return DTOs built inside the transaction, and add a test that asserts the statement count for the endpoint.
</details>

🔍 **Probe 4 (L6): How do you keep 40 teams from reintroducing N+1s?**

<details><summary>🛡️ Defense</summary>

Platform defaults (`open-in-view=false`, `default_batch_fetch_size`, `fail_on_pagination_over_collection_fetch=true`) in the shared starter; an ArchUnit rule that forbids returning entities from controllers; statement-count assertions in a shared test helper for the top endpoints; production tracing dashboards that flag requests with more than N DB spans. Make the right thing the default and the wrong thing visible.
</details>

---

## Drill 2: "Paginate orders with their lines in one query" ⚡

🎤 *"`JOIN FETCH o.lines` + `setMaxResults(20)`, but Hibernate paginates in memory, so we never do that."*

🔍 **Probe 1: Is that still true?**

<details><summary>🛡️ Defense</summary>

Not on Hibernate **7.4**. Verified ([3.3 §4](03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)): Hibernate now pages the **parent rows** in a derived table, `from (select … from f_order … where exists(…lines…) order by id offset ? rows fetch first ? rows only) po1_0 join f_line …`, with no `HHH90003004` warning. Up to 7.3 it dropped the `LIMIT`, loaded everything and paginated in memory.
</details>

🔍 **Probe 2: So can we drop the safety flag?**

<details><summary>🛡️ Defense</summary>

No. Some shapes still fall back. Verified: ordering by a collection column (`order by l.sku`) logged `HHH90003004 … applying in memory` and sent SQL without a limit. With `hibernate.query.fail_on_pagination_over_collection_fetch=true` that became an immediate `HibernateException`. Keep the flag: it's free for the shapes that now work and fatal (in tests) for the ones that don't.
</details>

🔍 **Probe 3: A colleague writes `join fetch o.lines l where l.qty > 1` with pagination. Review it.**

<details><summary>🛡️ Defense</summary>

Two problems. Semantically, filtering a fetched collection returns orders whose `lines` collections are **incomplete but look complete**, and the persistence context treats them as the real state. Practically, on 7.4.13 the pagination rewrite generated **invalid SQL** (`missing FROM-clause entry for table "l1_0"`). Rewrite: page order ids with a separate join alias for the filter (`where exists (select 1 from OrderLine l where l.order = o and l.qty > 1)`), then fetch complete lines for those ids. Or use a DTO if the filtered lines are the point.
</details>

---

## Drill 3: "Importing 5 M rows with `saveAll()` takes 3 hours" 🔥

🔍 **Probe 1: Where does the time go?**

<details><summary>🛡️ Defense</summary>

Round trips. With `GenerationType.IDENTITY`, Hibernate must execute each `INSERT` at `persist()` to learn the id, so `hibernate.jdbc.batch_size` is silently ignored. Verified ([3.4 §1](04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)): 20,000 rows = **20,000 round trips, 3.3 s**. If ids are assigned in Java, Spring Data's `save()` adds a hidden `SELECT` per row (it calls `merge()`, verified in [3.1 §6](01-Persistence-Context-Entity-States-Dirty-Checking.md)). And without `flush()`/`clear()`, the persistence context grows to 5 M entities plus snapshots.
</details>

🔍 **Probe 2: Fix it inside JPA.**

<details><summary>🛡️ Defense</summary>

`SEQUENCE` ids with `allocationSize = 50` (matching the sequence's `INCREMENT BY`), `hibernate.jdbc.batch_size=50`, `order_inserts=true`, pgjdbc `reWriteBatchedInserts=true`, `flush()` + `clear()` every batch, `Persistable.isNew()` for assigned ids. Verified: **801 round trips, ~0.5–0.6 s** for 20,000 rows. `StatelessSession` with a JDBC batch size went to **0.32–0.42 s**.
</details>

🔍 **Probe 3: And outside JPA?**

<details><summary>🛡️ Defense</summary>

`JdbcTemplate.batchUpdate` in batches of 1,000 with rewrite: **142 ms**. PostgreSQL `COPY FROM STDIN` through pgjdbc's `CopyManager`: **41–45 ms**, about 75× faster than IDENTITY inserts. For 5 M rows: `COPY` into a staging table, validate and merge in SQL (`INSERT … SELECT … ON CONFLICT`), in chunks with a checkpoint so a failure resumes instead of restarting.
</details>

🔍 **Probe 4 (L6): The DBA changed the sequence to `INCREMENT BY 1` "to avoid gaps". What happens?**

<details><summary>🛡️ Defense</summary>

Duplicate keys. With `allocationSize = 50`, the pooled optimizer assumes each `nextval` reserves a block of 50. With increment 1, two JVMs get adjacent `nextval` values whose blocks overlap. `allocationSize` must equal `INCREMENT BY`, and gaps are inherent to any scalable id allocation (a restart abandons a block). Gapless business numbers (invoices) need a separate, serialized counter. Also note the Hibernate 7 detail: pooled-lo is selected with `hibernate.id.optimizer.pooled.preferred=pooled-lo`; the old `preferred_lo=true` boolean is silently ignored (verified).
</details>

---

## Drill 4: "Replacing a line item throws a duplicate-key error, but we delete the old one first" 🔥

🔍 **Probe 1: Explain the error.**

<details><summary>🛡️ Defense</summary>

Hibernate executes the `ActionQueue` by **action type**, not call order: orphan actions, inserts, updates, collection actions, **deletes last** (read from `ActionQueue.ORDERED_OPERATIONS` on 7.4.13). So the new row's `INSERT` runs while the old row still exists. Verified: the `DELETE` was never even sent before the 23505 error.
</details>

🔍 **Probe 2: We use `orphanRemoval = true`. Doesn't that delete orphans first?**

<details><summary>🛡️ Defense</summary>

I tested exactly that ([3.2 §3](02-ActionQueue-Flush-Ordering.md)): removing the child from an `orphanRemoval` collection and adding a replacement with the same unique key, explicit `remove()`, and replacing a `@OneToOne(orphanRemoval = true)` child. **All three ran the INSERT first and failed.** Don't trust the action names; test the mapping you have.
</details>

🔍 **Probe 3: Fix options and trade-offs.**

<details><summary>🛡️ Defense</summary>

(1) `flush()` after the removal: two statements in the right order, same transaction. (2) Update the existing child in place: one `UPDATE`, which is usually the correct domain model anyway. (3) A **deferrable** unique constraint (`DEFERRABLE INITIALLY DEFERRED`) so the check happens at commit (PostgreSQL only; some overhead).
</details>

---

## Drill 5: "Two users reserved the last seat" 🔥

🔍 **Probe 1: You have `@Version`. Why did both succeed?**

<details><summary>🛡️ Defense</summary>

Check the details: `@Version` only protects the entity whose version is checked. If the reservation inserted a `Reservation` row and only *read* the `Seat`, no `UPDATE … WHERE version = ?` ran on the seat. Either change the seat in the same transaction (increment a counter, set status), which bumps its version, or use `LockModeType.OPTIMISTIC_FORCE_INCREMENT` / `PESSIMISTIC_WRITE` on the seat. Simplest: a unique constraint on `reservation(seat_id)` that the database enforces.
</details>

🔍 **Probe 2: Now one of them gets `OptimisticLockingFailureException`. Then what?**

<details><summary>🛡️ Defense</summary>

Retry in a **new** transaction, outside the transactional proxy. Verified ([3.5 §6](05-Transactional-Propagation-Isolation-Pitfalls.md)) with Spring Framework 7's core `@Retryable(includes = OptimisticLockingFailureException.class, maxRetries = 3, delay = 20, jitter = 10)` on a facade bean: two concurrent reservations ended `reserved=2 version=2` after **3 transaction attempts**. A retry inside the failed transaction can't work: it's rollback-only with a stale snapshot. For "last seat", the retry re-reads and correctly reports "sold out".
</details>

🔍 **Probe 3 (L6): A concert with 50,000 fans hitting 10,000 seats. Optimistic or pessimistic?**

<details><summary>🛡️ Defense</summary>

Neither per-row locking strategy is the bottleneck story; **contention** is. Optimistic locking under heavy contention means retry storms; pessimistic means queues on hot rows. Options: assign seats from a pre-shuffled pool with `SELECT … FOR UPDATE SKIP LOCKED` (each request grabs a *different* free seat with no waiting, [2.6 §4](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)); a virtual waiting room that admits users at a rate the database can serve; holds with expiry (`reserved_until`), so abandoned carts free seats.
</details>

---

## Drill 6: "`@Transactional` doesn't roll back" 🔥

🔍 **Probe: Give me four reasons, with how you'd prove each.**

<details><summary>🛡️ Defense</summary>

Each verified in [3.5](05-Transactional-Propagation-Isolation-Pitfalls.md), proven by printing `TransactionSynchronizationManager.isActualTransactionActive()` or by checking the data afterwards:

1. **Self-invocation:** `this.inner()` → `NO transaction`.
2. **Private method:** `NO transaction` (package-private works on class-based proxies since Spring 6, also verified).
3. **Checked exception:** the method threw `BusinessException` and the −30 **committed**. Fix: `rollbackFor`.
4. **Exception caught by the outer method:** in a shared `REQUIRED` transaction the inner failure marks it rollback-only, and the outer commit throws `UnexpectedRollbackException`. The opposite surprise.

Plus: work done on another thread (`@Async`, `CompletableFuture`) doesn't carry the thread-bound transaction, and with multiple transaction managers the annotation may name the wrong one.
</details>

---

## Drill 7: "We call the payment provider inside `@Transactional`" ⚡

🔍 **Probe 1: What can go wrong?**

<details><summary>🛡️ Defense</summary>

The connection and row locks are held for the whole HTTP call (seconds when the provider is slow), which exhausts the pool (Little's law: hold time goes up, needed connections go up). Idle-in-transaction sessions hold back VACUUM. And the money can move while the database transaction later rolls back (or the reverse).
</details>

🔍 **Probe 2: Someone suggests `REQUIRES_NEW` for the payment record. Thoughts?**

<details><summary>🛡️ Defense</summary>

It holds **two** connections per request. Verified: with a pool of 1, `REQUIRES_NEW` deadlocked the pool until Hikari's timeout (`total=1, active=1, idle=0`). At scale, N concurrent requests × 2 connections against a pool of N is the same deadlock. It also creates partial outcomes (payment row committed, order rolled back) that need reconciliation.
</details>

🔍 **Probe 3 (L6): Design it.**

<details><summary>🛡️ Defense</summary>

Short local transactions plus a **state machine**: (1) transaction: order `PENDING_PAYMENT` + outbox event; (2) outside any transaction: call the provider with an **idempotency key** = order id; (3) transaction: record the result, move the order to `PAID`/`FAILED`, outbox event. A reconciler polls `PENDING_PAYMENT` orders older than N minutes and asks the provider for their status, to cover crashes between steps. That's a saga ([5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)) with the outbox ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).
</details>

---

## Drill 8: "The nightly batch job dies with `OutOfMemoryError`" ⚡

🔍 **Probe: What's on the heap, and how do you fix it without a bigger heap?**

<details><summary>🛡️ Defense</summary>

The persistence context: every loaded or persisted entity, **plus a snapshot** of its state for dirty checking, plus the `ActionQueue` contents, all retained until the transaction ends. Fixes: `flush()` + `clear()` every N entities; `StatelessSession` for pure imports; `readOnly = true` / `setDefaultReadOnly(true)` for reads (no snapshots); stream query results (`getResultStream()` with a JDBC fetch size, which pgjdbc honors only inside a transaction with autocommit off); chunked transactions that commit every N rows with a resumable checkpoint. Verified cost of keeping things managed: a no-op flush over 20,004 entities took ~5 ms warm. Memory, not CPU, is usually what kills the job.
</details>

---

## Drill 9: "How do you implement `equals`/`hashCode` on entities?" 🧊

🔍 **Probe 1: What breaks with a Lombok `@Data` entity?**

<details><summary>🛡️ Defense</summary>

Several things. Field-based `equals` on a lazy **proxy** reads uninitialized proxy fields: verified, `o.customer.name` on the proxy was `null` while `getName()` returned `customer-1` ([3.1 §3](01-Persistence-Context-Entity-States-Dirty-Checking.md)). `getClass()` comparisons fail between proxy and entity. `hashCode` over mutable fields changes after an update, so the entity gets lost in a `HashSet`. `toString` walks lazy associations (N+1, or `LazyInitializationException`).
</details>

🔍 **Probe 2: What do you use instead?**

<details><summary>🛡️ Defense</summary>

A **business key** that's immutable and known before persist (ISBN, email if truly immutable): `equals` via `instanceof` + getters, `hashCode` from it. Or an **id-based** `equals` that treats transient (null-id) instances as unequal, with a **constant** `hashCode` (e.g. `getClass().hashCode()`, unproxied), so an entity keeps its hash bucket across `persist()`. Generating UUIDv7 ids in the constructor makes id-based equality simple, at the cost of the `merge`-instead-of-`persist` issue that `Persistable` solves ([3.1 §6](01-Persistence-Context-Entity-States-Dirty-Checking.md)).
</details>

---

## Drill 10: "JPA, jOOQ or plain JDBC for a new service?" 🧊

🔍 **Probe 1: Pick one and defend it.**

<details><summary>🛡️ Defense</summary>

It's not either/or. **JPA for aggregates** (load, apply invariants, save with optimistic locking and cascades); **SQL for sets** (reports, search screens, bulk updates, imports) through DTO projections, `JdbcClient` or jOOQ with code generation, where window functions, `LATERAL` and `ON CONFLICT` are first-class. Verified: one jOOQ query did keyset pagination and another a ranked aggregate in one round trip ([3.4 §6.2](04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)).
</details>

🔍 **Probe 2: What breaks when both run in one transaction?**

<details><summary>🛡️ Defense</summary>

Visibility in both directions. JDBC doesn't trigger Hibernate's auto-flush: verified, a `JdbcTemplate` count right after `em.persist()` saw **0** rows in the same transaction, then **1** after `em.flush()`. And JDBC or bulk JPQL writes don't update managed entities: verified, a bulk `update` left the entity showing `NEW` until `refresh()`. Rules: flush before SQL reads, clear or refresh after SQL writes, and keep the two styles in clearly separated methods.
</details>

---

# Round 2: high-scale persistence (Batch 1 deep dive)

> Evidence for Round 2 is in [3.7](07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md) and the new verified sections of 3.1–3.5 (Hibernate 7.4.13, pgjdbc 42.7.14, PostgreSQL 18.6). 🎤 candidate · 🔍 probe · 🛡️ staff-level defense.

---

## Drill 11: "The CSV export of all orders OOMs in production; it worked in staging" 🔥

🎤 *"We already use `getResultStream()`, so it's streaming. Give the pod more memory."*

🔍 **Probe 1: Does a `Stream` return type stream from PostgreSQL?**

<details><summary>🛡️ Defense</summary>

No. pgjdbc's default `fetchSize = 0` reads the **entire** result set into memory before the first row is returned. Verified in a 256 MB heap: `getResultList()` **and** `getResultStream()` without a fetch size both died with `OutOfMemoryError` at **row 0**. Staging had less data. Streaming needs a fetch size, and pgjdbc honours it **only inside a transaction** (autocommit off): plain JDBC with a fetch size and autocommit on also died at row 0.
</details>

🔍 **Probe 2: We added `setFetchSize(1000)` in a `@Transactional(readOnly = true)` method. It now dies at 393,216 rows. Why?**

<details><summary>🛡️ Defense</summary>

The driver now streams, but the **persistence context keeps every entity** it hydrated (identity map, `EntityEntry`, snapshot). Memory grows with rows processed, not with rows in flight. `readOnly` doesn't help much: it skips the dirty-check comparison, but 200,000 read-only entities still held 84 MB vs 91 MB (snapshots of immutable values share references). Fixes, verified to finish 1 M rows at ~80 MB: `clear()` every N rows, a `StatelessSession` with `scroll(FORWARD_ONLY)`, or a projection (3× faster than entities: 677 ms vs ~2 s).
</details>

🔍 **Probe 3 (L6): Design the export so it can't regress.**

<details><summary>🛡️ Defense</summary>

A dedicated read path: projection or `StatelessSession`, explicit fetch size, read-only transaction (ideally on a replica), streaming straight to the HTTP response or object storage with backpressure, and a `statement_timeout` sized for the export. Guard it with a test that runs the export in a JVM with a deliberately small heap against a large dataset: OOMs are deterministic, so the test is too. For very large exports, `COPY (SELECT …) TO STDOUT` through pgjdbc's `CopyManager` skips row objects altogether.
</details>

---

## Drill 12: "We turned on the second-level cache and products are sometimes stale" ⚡

🎤 *"Set a shorter TTL."*

🔍 **Probe 1: Where can staleness come from with `READ_WRITE` entity caching?**

<details><summary>🛡️ Defense</summary>

`READ_WRITE` coordinates writes **made through this SessionFactory**. A write that bypasses it (another service, a migration, a pricing job using JDBC, a DBA in `psql`) leaves the cache serving the old state: verified, the entity read **10.00** from L2 while the database held **999.00**. Multiple app instances with a **local** Caffeine cache have the same problem across nodes: instance A's update doesn't evict instance B's copy.
</details>

🔍 **Probe 2: The opposite complaint: "the cache hit ratio is terrible". What would you look for?**

<details><summary>🛡️ Defense</summary>

Invalidation storms. A JPQL bulk update evicts the **whole entity region** (verified: `Product 1` evicted by `update … where id = 2`) and bumps the region timestamp, so every cached query over that entity is invalidated. A native update **without** `addSynchronizedEntityClass` evicts **every region in the cache** (verified: an unrelated `Category` was evicted by an update to `c_product`). In a codebase with native SQL in hot paths, the L2 cache is cleared constantly. Statistics (`hibernate.generate_statistics`) show hit/miss/put per region.
</details>

🔍 **Probe 3 (L6): What are the right defaults if the team insists on an L2 cache?**

<details><summary>🛡️ Defense</summary>

Cache only reference data that this service owns; bounded, expiring regions with explicit names (Caffeine's JCache defaults are unbounded and eternal, verified in its `reference.conf`, and nested-class region names break its config lookup); a clustered or invalidating provider if there are several instances; `addSynchronizedEntityClass` on every native mutation; no query cache over frequently written entities; and a CDC-driven eviction (Debezium → evict by id) if other systems write the tables. Measure hit ratio per region and remove regions that don't pay.
</details>

---

## Drill 13: "Our dashboards show 3,000 distinct queries for the same repository method" ⚡

🎤 *"It's ad-hoc SQL from someone's script."*

🔍 **Probe 1: What in an ORM produces many SQL strings for one method?**

<details><summary>🛡️ Defense</summary>

`IN` lists. JPQL `where c.id in :ids` expands to `in (?,?,?)` with **one placeholder per element** (verified: 3, 5 and 9 ids produced three different SQL strings). Each length is a separate Hibernate query-plan-cache entry, a separate pgjdbc server-side prepared statement and, on PostgreSQL ≤ 17, a separate `pg_stat_statements` row.
</details>

🔍 **Probe 2: Fix it at three layers.**

<details><summary>🛡️ Defense</summary>

Hibernate: `hibernate.query.in_clause_parameter_padding=true` rounds to powers of two (verified 3/5/9 → 4/8/16 placeholders), so 1–1,000 ids give at most 10 shapes. SQL: pass an array (`= any(?)`), one shape for any size; that's what Hibernate's own batch fetching already does (verified `where c1_0.id = any (?)`). PostgreSQL 18: `pg_stat_statements` squashes IN lists (verified: lists of 3, 5 and 9 bind parameters and of literals all in one entry, `in ($1 /*, ... */)`), so the dashboard problem disappears on 18 even if the other two don't.
</details>

🔍 **Probe 3 (L6): Is `= any(?)` with 16 ids as fast as 16 primary-key lookups?**

<details><summary>🛡️ Defense</summary>

Faster: on PostgreSQL 17+, the B-tree scan advances through array elements on the same leaf page without re-descending. Verified on the atlas: 16 nearby customer ids → `Index Searches: 1`, **4 buffers**, vs ~4 buffers per id for one-by-one lookups plus 16 round trips. Widely spread ids still cost one descent each, but in one round trip.
</details>

---

## Drill 14: "We switched the lines collection to `SUBSELECT` fetching and memory exploded" 🧊

🎤 *"SUBSELECT is always 1 + 1 queries; it can't be worse than batch fetching."*

🔍 **Probe 1: Look at the second query. What's missing?**

<details><summary>🛡️ Defense</summary>

The page limit. Verified: for a page of 5 baskets (`fetch first ? rows only`), Hibernate loaded the lines with `where l1_0.basket_id in (select b1_0.id from d_basket b1_0 where b1_0.owner='odd')`: the original `WHERE` without the limit. Statistics: **45 lines** and **15 collections** loaded to show 5 baskets. With a million matching parents, a 20-row page loads every child of every matching parent.
</details>

🔍 **Probe 2: When is SUBSELECT the right choice?**

<details><summary>🛡️ Defense</summary>

Non-paginated loads where you want every child of every loaded parent (a batch job processing a bounded set, a report). For screens and APIs with pages, batch fetching (`= any(?)` per batch of loaded proxies) or a second query by the page's ids.
</details>

---

## Drill 15: "Hibernate flushes at strange times and our batch job is slow" 🧊

🎤 *"Flush happens at commit."*

🔍 **Probe 1: Name every flush trigger under `FlushMode.AUTO`, and the one people forget.**

<details><summary>🛡️ Defense</summary>

Commit, explicit `flush()`, a JPQL/HQL query whose **query spaces overlap** pending changes, and **any native query**: Hibernate can't parse native SQL, so it flushes everything. Verified: a pending `Item` insert was **not** flushed before a JPQL count on `Basket`, but **was** flushed before a native `select count(*) from d_basket`. In a batch job that issues a native query per item, every iteration dirty-checks the whole persistence context.
</details>

🔍 **Probe 2: Fix it without switching to `FlushMode.COMMIT` globally.**

<details><summary>🛡️ Defense</summary>

Declare what each native query touches: `createNativeQuery(sql, X.class).addSynchronizedEntityClass(Basket.class)` or `addSynchronizedQuerySpace("d_basket")`; then AUTO flush applies only to overlapping actions, and the same declaration keeps the second-level cache from being wiped by native mutations. Plus the usual batch hygiene: `flush()` + `clear()` every N items.
</details>

---

## Drill 16: "We use `@TenantId`, so tenants are isolated" 🔥

🎤 *"Hibernate adds the tenant filter everywhere."*

🔍 **Probe 1: Where does it, and where doesn't it?**

<details><summary>🛡️ Defense</summary>

Verified on 7.4.13: JPQL queries (`where i1_0.tenant = ?`), `find()` by id (another tenant's id returned `null`) and JPQL bulk updates are filtered. **Native SQL isn't**: `select count(*) from x_invoice` in the `acme` session returned 3, including `globex`'s row. So are JDBC/jOOQ paths, reporting jobs and ad-hoc SQL.
</details>

🔍 **Probe 2 (L6): Make isolation robust.**

<details><summary>🛡️ Defense</summary>

Defense in depth: PostgreSQL **row-level security** policies keyed on a per-transaction setting (`set_config('app.tenant', ?, true)` at transaction start), with `FORCE ROW LEVEL SECURITY` so even the owner role is filtered; tenant as the leading column of every index and unique constraint; tests that run every native query under two tenants and assert no cross-tenant rows; and a decision record on discriminator vs schema vs database per tenant based on isolation requirements, tenant count and per-tenant data size.
</details>

---

## Drill 17: "`@Transactional(readOnly = true)` protects us from accidental writes" ⚡

🎤 *"Yes, the database rejects writes."*

🔍 **Probe 1: Always?**

<details><summary>🛡️ Defense</summary>

Only inside a transaction. Spring calls `Connection.setReadOnly(true)`; with pgjdbc's default `readOnlyMode=transaction`, the driver begins transactions as read only, and a write fails with **25006** (verified). The same read-only connection in **autocommit** mode executed an `UPDATE` successfully (verified, `rows=1`). And for entity changes, Hibernate's read-only mode simply **doesn't flush** them: no error, the change is silently lost.
</details>

🔍 **Probe 2: So what do you tell a team that wants a hard guarantee?**

<details><summary>🛡️ Defense</summary>

Use database permissions, not annotations: a read-only role for read paths (`GRANT SELECT` only), or route read-only work to a replica where writes are impossible. Keep `readOnly = true` for its real benefits (less dirty-checking, no accidental flush, replica routing), and log SQLSTATE 25006 as a bug signal.
</details>

---

## Drill 18: "Hibernate 7 paginates fetch joins in SQL now, so deep pages are fine" 🧊

🎤 *"The in-memory pagination warning is gone, problem solved."*

🔍 **Probe 1: What does the database do for page 20,001 of `select o from Order o join fetch o.lines order by o.id`?**

<details><summary>🛡️ Defense</summary>

The 7.4 rewrite puts the parent page in a derived table: `select … from orders where exists(select 1 from order_lines …) order by id offset 100000 fetch first 5`. Verified with EXPLAIN on 1 M orders / 3 M lines: a **Merge Semi Join over 100,005 orders and 300,015 line-index entries**, 73.6 ms and 2,628 buffers, vs 0.15 ms for page 1. It's still `OFFSET`, and the `EXISTS` makes each skipped parent prove it has children.
</details>

🔍 **Probe 2: Fix it.**

<details><summary>🛡️ Defense</summary>

Keyset on the parent id with the same SQL shape (`where o.id > :lastSeen`): verified **0.06 ms, 43 buffers** at the same depth. Or the two-step pattern: page the parent ids (keyset), then fetch parents with lines by ids. Keep `fail_on_pagination_over_collection_fetch=true` for the shapes that still fall back to memory.
</details>

---

## L5 vs L6 signal

| Topic | L5 | L6 |
|---|---|---|
| N+1 | Recognizes it, uses `JOIN FETCH` | Statement-count tests, batch-fetch defaults, OSIV off, platform guardrails |
| Streaming (Round 2) | Uses `getResultStream()` | Knows the three conditions (fetch size, transaction, no retention); proves it with a small-heap test |
| Caching (Round 2) | Turns on L2 for "speed" | Knows region invalidation, native-SQL cache wipes, out-of-band staleness, unbounded defaults |
| SQL shape (Round 2) | Trusts the ORM's SQL | Reads batch-fetch arrays, IN-list cardinality, SUBSELECT limits and 7.4 pagination in EXPLAIN |
| Isolation (Round 2) | `@TenantId` | `@TenantId` + RLS + tests for native SQL |
| Pagination | Knows the in-memory warning | Knows the 7.4 change, the remaining fallbacks and the invalid-SQL edge case; prefers keyset |
| Writes | Knows IDENTITY breaks batching | Sizes allocation blocks, knows the optimizer settings by version, chooses COPY/StatelessSession for bulk |
| Transactions | Knows the proxy rules | Designs boundaries around remote calls, retries outside transactions, pool math for REQUIRES_NEW |
| Architecture | "We use Spring Data" | ORM for aggregates, SQL for sets, with explicit flush/clear rules where they meet |

## Red flags

* "`FetchType.EAGER` fixes `LazyInitializationException`."
* "`enable_lazy_load_no_trans=true`" as a fix.
* "We set `batch_size`, so inserts are batched" (with IDENTITY ids).
* "I always use `REQUIRES_NEW` to be safe."
* "Retry inside the transactional method."
* "`saveAll()` for a million rows."
* "We return a `Stream`, so it's streaming."
* "The second-level cache makes everything faster" (with native SQL and other writers).
* "`@TenantId` means tenants are isolated."
* "SUBSELECT fetching is always 1 + 1."

---

## Rapid-fire flashcards

<details><summary>1. Four entity states?</summary>Transient, managed, detached, removed.</details>

<details><summary>2. What does `merge()` return?</summary>A managed copy; the argument stays detached (and it SELECTs first).</details>

<details><summary>3. When does the INSERT happen after `persist()` with a SEQUENCE id?</summary>At flush; the id is fetched at persist.</details>

<details><summary>4. Default UPDATE shape?</summary>All columns; `@DynamicUpdate` for changed columns only.</details>

<details><summary>5. Why can field access on an association return null?</summary>It's a proxy; only methods are intercepted.</details>

<details><summary>6. ActionQueue order (simplified)?</summary>Orphan actions, inserts, updates, collection actions, deletes last.</details>

<details><summary>7. Does a native query trigger auto-flush in Hibernate 7?</summary>Yes (verified: pending insert flushed before native count).</details>

<details><summary>8. Does a JdbcTemplate query trigger Hibernate auto-flush?</summary>No (verified: 0 rows until `em.flush()`).</details>

<details><summary>9. SQL shape of batch fetching on PostgreSQL?</summary>`where id = any (?)` with one array parameter.</details>

<details><summary>10. Why MultipleBagFetchException?</summary>Two unordered `List` (bag) collections can't be de-duplicated from a Cartesian product.</details>

<details><summary>11. What did Hibernate 7.4 change about JOIN FETCH + limit?</summary>Paginates parent rows in a derived table in SQL; falls back to memory for shapes like ordering by a collection column.</details>

<details><summary>12. The safety flag?</summary>`hibernate.query.fail_on_pagination_over_collection_fetch=true`.</details>

<details><summary>13. Why does IDENTITY break batching?</summary>The id is known only after the INSERT, so Hibernate inserts at persist time.</details>

<details><summary>14. `allocationSize` rule?</summary>Must equal the sequence's INCREMENT BY.</details>

<details><summary>15. Hibernate 7 pooled-lo setting?</summary>`hibernate.id.optimizer.pooled.preferred=pooled-lo`.</details>

<details><summary>16. Fastest bulk load in PostgreSQL from Java?</summary>COPY via pgjdbc CopyManager (~75× IDENTITY inserts here).</details>

<details><summary>17. pgjdbc option that rewrites batches?</summary>`reWriteBatchedInserts=true`.</details>

<details><summary>18. What does a bulk JPQL update skip?</summary>The persistence context, @Version increments, listeners, cascades.</details>

<details><summary>19. Spring Data `save()` with an assigned id?</summary>Calls `merge()` → SELECT + INSERT; implement `Persistable`.</details>

<details><summary>20. Default rollback rule?</summary>RuntimeException and Error roll back; checked exceptions commit.</details>

<details><summary>21. Cause of UnexpectedRollbackException?</summary>A joined (REQUIRED) inner failure marked the transaction rollback-only and the outer tried to commit.</details>

<details><summary>22. REQUIRES_NEW cost?</summary>A second connection per request; pool deadlock risk.</details>

<details><summary>23. What does `readOnly = true` do with Hibernate?</summary>FlushMode MANUAL, read-only entities (no snapshots), `Connection.setReadOnly`, enables replica routing.</details>

<details><summary>24. What does `@Transactional(timeout = 1)` do?</summary>Sets JDBC query timeouts; the driver cancels long SQL statements.</details>

<details><summary>25. Spring 7 core retry annotation and enabler?</summary>`@Retryable` with `@EnableResilientMethods` (also `@ConcurrencyLimit`).</details>

<details><summary>26. Where must retries live?</summary>Outside the transactional proxy; each attempt is a new transaction.</details>

<details><summary>27. Three conditions for streaming rows from PostgreSQL through Hibernate?</summary>A fetch size, a transaction (pgjdbc ignores fetch size with autocommit on), and no retention (`clear()`, StatelessSession or projections).</details>

<details><summary>28. What does a query cache entry contain?</summary>The ids of the result; entities come from the entity cache.</details>

<details><summary>29. What does a JPQL bulk update do to the L2 cache?</summary>Evicts the whole region of the updated entity and invalidates cached queries over it.</details>

<details><summary>30. And a native update without `addSynchronizedEntityClass`?</summary>Evicts every region of the second-level cache.</details>

<details><summary>31. Caffeine JCache's default size bound?</summary>None: `maximum.size = null`, expiry `eternal`.</details>

<details><summary>32. SQL shape of Hibernate 7 batch fetching on PostgreSQL?</summary>`where id = any (?)` with one array parameter.</details>

<details><summary>33. What does `in_clause_parameter_padding` do?</summary>Rounds IN-list placeholders up to a power of two (3 → 4, 5 → 8, 9 → 16).</details>

<details><summary>34. How does PostgreSQL 18's `pg_stat_statements` record IN lists of different lengths?</summary>As one entry: `in ($1 /*, ... */)`, for both parameters and literals.</details>

<details><summary>35. What's wrong with `@Fetch(SUBSELECT)` on a paginated query?</summary>The subselect re-runs the parent `WHERE` without the limit: children of every matching parent are loaded.</details>

<details><summary>36. Which queries trigger an AUTO flush?</summary>JPQL whose query spaces overlap pending changes, and every native query (unless synchronized spaces are declared).</details>

<details><summary>37. What does `@TenantId` not filter?</summary>Native SQL (and anything outside Hibernate).</details>

<details><summary>38. SQLSTATE for a write in a read-only transaction?</summary>25006 (enforced by pgjdbc only inside transactions with the default `readOnlyMode=transaction`).</details>

<details><summary>39. What does `StatelessSession.upsert()` generate on PostgreSQL?</summary>`INSERT … ON CONFLICT (id) DO UPDATE SET …`.</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–10) | Slow CRUD, fetch-join pagination, 5 M-row import, delete/insert unique key, double booking, rollback rules, remote call in a transaction, batch OOM, `equals`/`hashCode`, JPA vs jOOQ vs JDBC | The ORM's mechanics: persistence context, flush order, fetch plans, transactions |
| Round 2 (11–18) | Export OOM, stale/thrashing L2 cache, IN-list cardinality, SUBSELECT memory, AUTO flush, `@TenantId` leaks, read-only guarantees, deep fetch-join pages | The ORM at scale: memory, caches, SQL shapes in EXPLAIN and `pg_stat_statements`, isolation |

**Next pillar:** [4.1 IoC container, startup & BeanDefinitions →](../04-Spring-Boot-Internals/01-IoC-Container-Startup-BeanDefinition-PostProcessors.md)
