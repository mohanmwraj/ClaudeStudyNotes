# 3.4 Write Throughput: Why `IDENTITY` Kills Batching, Sequence Optimizers (pooled vs pooled-lo), StatelessSession, JDBC Batches, COPY, and Hybrid JPA + JDBC/jOOQ

> **Verified stack:** Hibernate ORM **7.4.13.Final**, pgjdbc **42.7.14**, Spring Framework **7.0.10**, jOOQ **3.21.9**, PostgreSQL **18.6** on localhost (so round trips are cheap here; in a real network the gaps below get **much** wider). Timings are one measured run; statement and round-trip counts are exact.

---

## 0. First principles: writes are dominated by round trips 🔥

Inserting one small row costs microseconds inside PostgreSQL. Sending it costs a **network round trip** plus statement parsing and executing. So write throughput is governed by:

1. **Round trips**: batch many rows into one JDBC execution.
2. **Per-row work in your process**: an ORM persistence context does identity mapping, snapshots and cascades for each entity.
3. **Server-side per-statement overhead**: one multi-row `INSERT` or a `COPY` stream beats 1,000 single-row statements.

And one ORM-specific constraint decides whether batching is possible at all: **when does the entity get its id?**

---

## 1. The benchmark (verified) 🔥

20,000 rows of `(name text, amount numeric)`, every variant in its own transaction:

**One measured run, `reWriteBatchedInserts=false`:**

```text
=== Inserting 20000 rows (reWriteBatchedInserts=false)
  Hibernate, IDENTITY ids, batch_size=50                       3309 ms   statements=20000  round trips=20000
  Hibernate, SEQUENCE ids (pooled, 50), batch_size=50           637 ms   statements=20401  round trips=801
  Hibernate StatelessSession, SEQUENCE ids, jdbc batch 50       416 ms   statements=20400  round trips=801
  JdbcTemplate.batchUpdate, batches of 1000                     240 ms   statements=20000  round trips=20
  PostgreSQL COPY FROM STDIN (pgjdbc CopyManager)                45 ms   statements=0      round trips=0
```

**One measured run, `jdbc:postgresql://…?reWriteBatchedInserts=true`:**

```text
=== Inserting 20000 rows (reWriteBatchedInserts=true)
  Hibernate, IDENTITY ids, batch_size=50                       3426 ms   statements=20000  round trips=20000
  Hibernate, SEQUENCE ids (pooled, 50), batch_size=50           524 ms   statements=20401  round trips=801
  Hibernate StatelessSession, SEQUENCE ids, jdbc batch 50       318 ms   statements=20400  round trips=801
  JdbcTemplate.batchUpdate, batches of 1000                     142 ms   statements=20000  round trips=20
  PostgreSQL COPY FROM STDIN (pgjdbc CopyManager)                41 ms   statements=0      round trips=0
```

*(COPY bypasses the `Statement` API, so the counting proxy doesn't see it.)*

| Variant | vs IDENTITY | Why |
|---|---|---|
| IDENTITY | 1× | One round trip **per row**. Batching silently disabled |
| SEQUENCE + batching | **5.2×–6.5× faster** | 400 batches of 50 + 401 `nextval` calls |
| StatelessSession | **8–11×** | Same batches, no persistence context work |
| JDBC batches of 1,000 (+ rewrite) | **14–24×** | 20 round trips; rewrite turns each batch into multi-row `INSERT … VALUES (…),(…)` |
| `COPY` | **~75×** | A streaming bulk-load protocol: no per-row statement at all |

---

## 2. Why `GenerationType.IDENTITY` disables JDBC batching 🔥

The persistence context is an identity map keyed by **(entity type, id)** ([3.1 §2](01-Persistence-Context-Entity-States-Dirty-Checking.md)). After `persist()` the entity must be managed *with its id*. With `IDENTITY`, the id exists only after the database executes the `INSERT` (a `bigserial` / `generated … as identity` column). So Hibernate must **execute the `INSERT` immediately at `persist()`**, one row at a time, to read the generated key back. There's nothing left to batch. Hibernate doesn't fail or warn; `hibernate.jdbc.batch_size` is simply ignored for those inserts, which is why it's a classic silent performance bug.

With `SEQUENCE`, Hibernate obtains ids **before** inserting (from a sequence, in blocks, §3), so inserts can wait in the `ActionQueue` and go out in batches at flush.

| Database | What to use |
|---|---|
| PostgreSQL, Oracle, SQL Server 2012+, H2, MariaDB 10.3+ | `SEQUENCE` with an allocation size |
| MySQL (no sequences) | `IDENTITY` (`AUTO_INCREMENT`) loses Hibernate batching. Options: JDBC batching outside Hibernate with `rewriteBatchedStatements=true`, application-generated ids (UUIDv7, Snowflake), or a table-based generator (a contention point, rarely worth it) |

---

## 3. Sequence optimizers: pooled vs pooled-lo (verified) ⚡

Calling `nextval` for every row would add a round trip per row. Hibernate allocates **blocks** of ids: with `allocationSize = 50` the database sequence's `INCREMENT BY` is 50, and one `nextval` reserves 50 ids. The **optimizer** decides how a sequence value maps to a block:

* **`pooled`** (the default): the sequence value is the **high end** of the block.
* **`pooled-lo`**: the sequence value is the **low end** of the block.

```java
@Id @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "w_seq_gen")
@SequenceGenerator(name = "w_seq_gen", sequenceName = "w_seq_ids", allocationSize = 50)
Long id;
```

**Output (verified, default `pooled`, fresh sequence):**

```text
  SQL> select nextval('w_seq_ids')
  persisted id=1
  SQL> select nextval('w_seq_ids')
  persisted id=2
  persisted id=3
  SQL> select last_value from w_seq_ids
  sequence last_value=51
```

On a fresh sequence starting at 1, `pooled` calls `nextval` **twice** (1, then 51) to establish its first block, and hands out 1, 2, 3, …

**Output (verified, `pooled-lo`):**

```text
  SQL> select nextval('w_seq_ids')
  persisted id=1
  persisted id=2
  persisted id=3
  SQL> select last_value from w_seq_ids
  sequence last_value=1
```

One `nextval` (1) reserves 1–50.

### ⚠️ The Hibernate 7 setting name (verified)

Older articles say `hibernate.id.optimizer.pooled.preferred_lo=true`. On Hibernate 7.4.13 that boolean is **silently ignored**. The setting is now `hibernate.id.optimizer.pooled.preferred` with a strategy name. Verified by inspecting the optimizer of the generator Hibernate actually built (two runs, one per setting style):

```text
preferred_lo=false -> PooledOptimizer
preferred_lo=true  -> PooledOptimizer           ← old boolean: no effect
pooled.preferred=pooled    -> PooledOptimizer
pooled.preferred=pooled-lo -> PooledLoOptimizer  ← works
```

### Why both are safe with other writers (and the legacy `hilo` wasn't)

Both optimizers derive ids **only from values the sequence itself handed out**, with `INCREMENT BY` equal to `allocationSize`. Another application doing `INSERT … VALUES (nextval('w_seq_ids'), …)` gets values that Hibernate will never use, under either optimizer. The legacy `hilo` algorithm computed ids as `hi × maxLo + lo` and **did** collide with external `nextval` users. The one hard rule: **`allocationSize` must equal the sequence's `INCREMENT BY`.** If a DBA recreates the sequence with increment 1 while the app says 50, you get duplicate keys.

Gaps are normal (a restarted JVM abandons the rest of its block). If the business needs gapless numbers (invoices), that's a separate, serialized counter, not your primary key.

---

## 4. Turning batching on, properly ⚡

```properties
hibernate.jdbc.batch_size=50            # 20–100; diminishing returns beyond
hibernate.order_inserts=true            # group by entity type so batches aren't broken up (see 3.2 §4)
hibernate.order_updates=true
hibernate.jdbc.batch_versioned_data=true   # allow batching of @Version-ed updates (on by default for most dialects)
```

```text
jdbc:postgresql://host/db?reWriteBatchedInserts=true     # pgjdbc: batch → multi-row INSERT
jdbc:mysql://host/db?rewriteBatchedStatements=true       # MySQL Connector/J equivalent
```

And the **batch-processing loop**, so the persistence context doesn't grow without bound:

```java
for (int i = 0; i < rows.size(); i++) {
    em.persist(toEntity(rows.get(i)));
    if (i % batchSize == batchSize - 1) {
        em.flush();   // send the batch
        em.clear();   // drop managed entities + snapshots (memory, dirty-checking cost)
    }
}
```

### StatelessSession (verified fastest Hibernate path)

```java
sf.inStatelessTransaction(ss -> {
    ss.setJdbcBatchSize(50);
    for (int i = 0; i < N; i++) ss.insert(new SeqRow("n" + i, BigDecimal.valueOf(i)));
});
```

No persistence context, no dirty checking, no cascades, no lifecycle events, no lazy loading: each call maps directly to SQL (`insert`, `update`, `delete`, `upsert`). 416 ms vs 637 ms here. It's ideal for imports and ETL that still want entity mappings.

---

### 4.1 Verified: Hibernate 7's `insertMultiple()` and `upsert()` on a StatelessSession 🧊

`StatelessSession` in Hibernate 7.4 has list operations (`insertMultiple`, `updateMultiple`, `deleteMultiple`, `upsertMultiple`, plus `getMultiple` for reads) and a single-row `upsert()` (all verified with `javap` on `hibernate-core-7.4.13.Final`):

```java
// hibernate.jdbc.batch_size = 50
sf.inStatelessTransaction(ss -> ss.insertMultiple(items));               // 100 items
sf.inStatelessTransaction(ss -> {
    ss.upsert(new Item(1L, "item 1 (changed)", BigDecimal.TEN, null));   // id 1 exists
    ss.upsert(new Item(1000L, "item 1000 (new)", BigDecimal.TEN, null)); // id 1000 doesn't
});
```

**Output (verified, Hibernate 7.4.13, PostgreSQL 18.6):**

```text
=== StatelessSession.insertMultiple(100 items) with jdbc.batch_size=50
  SQL> [batch x100] insert into d_item (name,note,price,id) values (?,?,?,?)
  statements=100 round trips=1
=== StatelessSession.upsert(): one existing id, one new id
  SQL> insert into d_item (name,note,price,id) values (?,?,?,?) on conflict (id) do update set name=excluded.name,note=excluded.note,price=excluded.price
  SQL> insert into d_item (name,note,price,id) values (?,?,?,?) on conflict (id) do update set name=excluded.name,note=excluded.note,price=excluded.price
  after upsert: [1:item 1 (changed), 1000:item 1000 (new)]
```

* **`insertMultiple` sent one JDBC batch of 100** although `hibernate.jdbc.batch_size = 50`: the operation batches the whole list itself. Chunk very large lists in your own code (the driver holds the whole batch in memory, and with `reWriteBatchedInserts` it becomes one huge multi-row `INSERT`).
* **`upsert()` renders PostgreSQL's `INSERT … ON CONFLICT (id) DO UPDATE`** (atomic on the unique index, [2.4 §4.2](../02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)), here one statement per call. It's an idempotent "write this row" for imports and replays (CDC, event consumers), without a select-then-insert race.
* Neither touches a persistence context: no cascades, no dirty checking, no second-level cache maintenance beyond what the stateless operation does. Use them in import jobs, not inside units of work that also hold managed copies of the same rows.

## 5. Bulk JPQL updates bypass the persistence context (verified) 🔥

```java
Item item = em.find(Item.class, 1L);
int n = em.createQuery("update Item i set i.status = 'ARCHIVED'").executeUpdate();
System.out.println("  bulk update touched " + n + " row(s); managed entity still says: " + item.status);
em.refresh(item);
System.out.println("  after em.refresh(item): " + item.status);
```

**Output (verified):**

```text
  bulk update touched 1 row(s); managed entity still says: NEW
  after em.refresh(item): ARCHIVED
```

A JPQL/HQL `update`/`delete` goes straight to SQL. Managed instances aren't updated, and worse, if one of them is dirty for another reason, its next flush **writes the stale `NEW` back**. In Spring Data use `@Modifying(flushAutomatically = true, clearAutomatically = true)`: flush pending changes before the bulk statement and clear the context after it. Also remember bulk statements skip `@Version` increments, entity listeners and cascades.

---

## 6. Hybrid architectures: JPA for aggregates, SQL for sets 🧊

A mature backend usually ends up with:

| Use case | Tool | Why |
|---|---|---|
| Load an aggregate, apply business rules, save | JPA / Hibernate | Dirty checking, optimistic locking, cascades |
| Read models, reports, search screens | DTO projections, `JdbcClient`, jOOQ | Exact SQL, window functions, no managed state |
| Bulk inserts and imports | JDBC batch (rewrite on), `COPY`, StatelessSession | 14–75× faster than entity-by-entity |
| Set-based updates ("archive all orders older than…") | One SQL `UPDATE`/`DELETE` (or partition drop) | One statement instead of N entity updates |

### 6.1 Mixing JPA and JDBC in one transaction (verified gotcha)

`JpaTransactionManager` exposes the JPA transaction's JDBC connection to `JdbcTemplate`/`JdbcClient`, so both run in **the same database transaction**. But a JDBC query doesn't trigger Hibernate's **auto-flush**:

```java
@Transactional
public void jdbcAfterPersist() {
    em.persist(new Item(1L, "NEW"));
    Integer seen = jdbc.queryForObject("select count(*) from h_item", Integer.class);
    System.out.println("  JdbcTemplate count right after em.persist(): " + seen + "   (same transaction, same connection)");
    em.flush();
    seen = jdbc.queryForObject("select count(*) from h_item", Integer.class);
    System.out.println("  JdbcTemplate count after em.flush():        " + seen);
}
```

**Output (verified):**

```text
  JdbcTemplate count right after em.persist(): 0   (same transaction, same connection)
  JdbcTemplate count after em.flush():        1
```

Rule: **flush the `EntityManager` before any JDBC/jOOQ statement that must see JPA changes**, and clear (or refresh) after JDBC writes that touched rows you hold as entities.

### 6.2 jOOQ for the queries JPQL can't express (verified)

```java
static final Table<?> ORDERS = table(name("orders"));
static final Field<Long> ID = field(name("id"), Long.class);
static final Field<Long> CUSTOMER_ID = field(name("customer_id"), Long.class);
static final Field<OffsetDateTime> CREATED_AT = field(name("created_at"), OffsetDateTime.class);
static final Field<BigDecimal> AMOUNT = field(name("amount"), BigDecimal.class);
static final Field<String> STATUS = field(name("status"), String.class);

// keyset page: (created_at, id) < (:ts, :id), newest first
var page = db.select(ID, CREATED_AT, AMOUNT)
        .from(ORDERS)
        .where(row(CREATED_AT, ID).lt(OffsetDateTime.parse("2026-06-23T09:10:30Z"), 500001L))
        .orderBy(CREATED_AT.desc(), ID.desc())
        .limit(3);

// reporting: top 3 customers by revenue in December with a window rank, one round trip
Field<BigDecimal> revenue = sum(AMOUNT).as("revenue");
var report = db.select(CUSTOMER_ID, revenue, rank().over(orderBy(sum(AMOUNT).desc())).as("rnk"))
        .from(ORDERS)
        .where(CREATED_AT.ge(OffsetDateTime.parse("2026-12-01T00:00:00Z")).and(STATUS.ne("CANCELLED")))
        .groupBy(CUSTOMER_ID)
        .orderBy(field(name("rnk")))
        .limit(3);
```

**Output (verified against the 1 M-row `orders` table from Pillar 2):**

```text
SQL: select "id", "created_at", "amount" from "orders" where ("created_at", "id") < (cast(? as timestamp with time zone), ?) order by "created_at" desc, "id" desc fetch next ? rows only
  500000 2026-06-23T09:10Z 19.21
  499999 2026-06-23T09:09:30Z 119.34
  499998 2026-06-23T09:09Z 368.75
SQL: select "customer_id", sum("amount") as "revenue", rank() over (order by sum("amount") desc) as "rnk" from "orders" where ("created_at" >= cast(? as timestamp with time zone) and "status" <> ?) group by "customer_id" order by "rnk" fetch next ? rows only
  customer 29066 revenue 1578.00 rank 1
  customer 36307 revenue 1572.56 rank 2
  customer 16697 revenue 1502.79 rank 3
```

This sample uses jOOQ's plain-SQL DSL (`table(name(...))`) to stay self-contained. In production, run jOOQ's **code generator** against your schema (or Flyway migrations), so table and column references are generated classes and a renamed column breaks the build.

---

## 7. ❌ Naïve vs ✅ production-hardened writes

| ❌ Naïve | ✅ Hardened |
|---|---|
| `@GeneratedValue(strategy = IDENTITY)` on PostgreSQL + `batch_size=50` "for performance" | `SEQUENCE` with `allocationSize` = the sequence's `INCREMENT BY`; verify batches with a statement counter |
| `hibernate.id.optimizer.pooled.preferred_lo=true` copied from a Hibernate 5 blog | `hibernate.id.optimizer.pooled.preferred=pooled-lo` (verified the old flag is ignored on 7.4) |
| Import 1 M rows with `save()` in one transaction | Batches + `flush()`/`clear()`, StatelessSession, JDBC batch with rewrite, or `COPY` |
| JPQL bulk update while holding entities | `@Modifying(flushAutomatically = true, clearAutomatically = true)`, or refresh |
| JDBC query after `persist()` in the same transaction | `em.flush()` first (verified: 0 rows otherwise) |
| Everything through the ORM | ORM for aggregates, SQL/jOOQ for sets and reports |

---

## 8. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [hibernate/hibernate-orm](https://github.com/hibernate/hibernate-orm) | `hibernate-core/src/main/java/org/hibernate/id/enhanced/PooledOptimizer.java` and `PooledLoOptimizer.java` | Block arithmetic; the "initial value" double call |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/id/enhanced/OptimizerFactory.java` | How the preferred optimizer is resolved |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/engine/jdbc/batch/internal/BatchImpl.java` | Batching mechanics |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/internal/StatelessSessionImpl.java` | What a stateless session skips |
| [pgjdbc/pgjdbc](https://github.com/pgjdbc/pgjdbc) | `pgjdbc/src/main/java/org/postgresql/copy/CopyManager.java` | The `COPY` streaming API |
| pgjdbc/pgjdbc | Search for `reWriteBatchedInserts` | How a batch becomes a multi-row `INSERT` |
| [jOOQ/jOOQ](https://github.com/jOOQ/jOOQ) | `jOOQ/src/main/java/org/jooq/impl/DSL.java` | The DSL entry points used above |

---

## 9. Interview soundbites

* "IDENTITY ids exist only after the INSERT runs, so Hibernate must insert at `persist()` and can't batch. 20,000 rows took 20,000 round trips and 3.3 s; SEQUENCE with batching took 801 round trips and 0.6 s."
* "The pooled optimizer reserves blocks of ids; `allocationSize` must match the sequence increment. On Hibernate 7 pooled-lo is `hibernate.id.optimizer.pooled.preferred=pooled-lo`; the old boolean is ignored."
* "For imports I use StatelessSession, JDBC batches with `reWriteBatchedInserts`, or `COPY`, which was about 75 times faster than IDENTITY inserts."
* "Bulk JPQL updates bypass the persistence context; managed entities go stale until refresh or clear."
* "JDBC in the same transaction doesn't trigger Hibernate's auto-flush. I flush first."
* "Hibernate 7's `insertMultiple` batches the whole list (one batch of 100 despite `batch_size=50`), and `upsert()` is `INSERT … ON CONFLICT DO UPDATE` on PostgreSQL."

---

## Summary

| Path | Round trips for 20,000 rows | Verified evidence |
|---|---:|---|
| `IDENTITY` ids | 20,000 | Batching silently disabled: 3.3 s |
| `SEQUENCE` (pooled 50) + `batch_size = 50` | 801 | 0.52–0.64 s |
| StatelessSession, JDBC batch 50 | 801 | 0.32–0.42 s |
| `insertMultiple` (Hibernate 7) | 1 per list | One batch of 100 regardless of `batch_size` |
| JDBC `batchUpdate` 1,000 (+ `reWriteBatchedInserts`) | 20 | 0.14–0.24 s |
| `COPY FROM STDIN` | streaming | ~75× faster than IDENTITY |
| `upsert()` | 1 per row | `INSERT … ON CONFLICT (id) DO UPDATE` |
| Sequence optimizers | pooled vs pooled-lo; `allocationSize` = increment | Hibernate 7 ignores the old boolean; use `…pooled.preferred=pooled-lo` |
| Bulk JPQL | Bypasses the persistence context | Managed entities stale until `refresh`/`clear` |
| JPA + JDBC in one transaction | JDBC doesn't trigger auto-flush | Flush first |

**Next:** [3.5 `@Transactional` propagation, isolation & pitfalls →](05-Transactional-Propagation-Isolation-Pitfalls.md)
