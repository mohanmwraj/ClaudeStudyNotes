# 3.3 N+1, Lazy Loading, Fetch Plans, Pagination with Collections (Hibernate 7.4 Changed It), and Projections

> **Verified stack:** Hibernate ORM **7.4.13.Final**, Spring Data JPA **4.1.2**, PostgreSQL **18.6**. Model: 10 `Customer`s, 50 `PurchaseOrder`s (each `@ManyToOne(fetch = LAZY) customer`, `List<OrderLine> lines` ×3, `List<Payment> payments` ×2). `SQL>` lines are what the driver received; "statements" counts JDBC executions.
>
> ⚠️ **Version note:** many articles (and the prompt that inspired this playbook) describe `HHH90003004: firstResult/maxResults specified with collection fetch; applying in memory!` as what *always* happens. **That's no longer true on Hibernate 7.4** for common query shapes. §4 shows exactly what changed and where the old behavior remains.

---

## 0. First principles: object graphs vs result sets 🔥

A relational query returns a **flat rectangle**. An object model is a **graph**. An ORM must decide, for every association, **when** and **how** to load it:

* **When**: eagerly (with the owner) or lazily (on first access).
* **How**: a join (one query, wider and possibly duplicated rows), a separate select (one query per owner, the "N" in N+1), or a batch select (one query per batch of owners).

Default JPA fetch types are **EAGER for `@ManyToOne`/`@OneToOne`** and LAZY for collections. **Make everything LAZY** and decide per use case with a fetch plan (`JOIN FETCH`, entity graph, batch size). Eager mappings can't be turned off per query, and they cause N+1s you never asked for.

---

## 1. N+1, reproduced (verified) 🔥

### 1.1 On a `@ManyToOne`

```java
List<PurchaseOrder> orders = s.createQuery("from PurchaseOrder o order by o.id", PurchaseOrder.class).setMaxResults(10).getResultList();
orders.forEach(o -> o.customer.getName());
```

**Output (verified):**

```text
  SQL> select po1_0.id,po1_0.customer_id from f_order po1_0 order by po1_0.id fetch first ? rows only
  SQL> select c1_0.id,c1_0.name from f_customer c1_0 where c1_0.id=?
  SQL> select c1_0.id,c1_0.name from f_customer c1_0 where c1_0.id=?
  ... (10 customer selects in total)
  statements: 11
```

### 1.2 On a collection

```java
orders.forEach(o -> o.lines.size());
```

```text
  SQL> select po1_0.id,po1_0.customer_id from f_order po1_0 order by po1_0.id fetch first ? rows only
  SQL> select l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku from f_line l1_0 where l1_0.order_id=?
  ... (10 line selects in total)
  statements: 11
```

**Why it's a production problem, not a style problem:** each lazy load is a network round trip (0.2–1 ms in a datacenter, more across zones). A page of 50 orders with 3 lazy associations is 151 round trips, and that's 150–750 ms of pure latency hidden inside innocent-looking getters, often in a JSON serializer far from the repository code.

### 1.3 Detecting it

* **In tests:** count statements. Hibernate statistics (`hibernate.generate_statistics`), datasource-proxy (as in these labs), or libraries like `hypersistence-utils`' `SQLStatementCountValidator`. Assert "this endpoint issues ≤ 3 statements".
* **In production:** traces with one span per JDBC statement (OpenTelemetry JDBC instrumentation, [5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md)). An N+1 looks like a comb of identical spans.

---

## 2. The fixes, compared (verified) 🔥

### 2.1 `JOIN FETCH`: one query

```java
s.createQuery("select o from PurchaseOrder o join fetch o.lines join fetch o.customer where o.id <= 10 order by o.id", PurchaseOrder.class)
```

```text
  SQL> select po1_0.id,c1_0.id,c1_0.name,l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku from f_order po1_0 join f_line l1_0 on po1_0.id=l1_0.order_id join f_cust...
  orders returned: 10, lines on first: 3
  statements: 1
```

The SQL returns 30 rows (10 orders × 3 lines), and since Hibernate 6 **entity results are de-duplicated automatically**: 10 orders, no `DISTINCT` needed (in Hibernate 5 you had to add it).

### 2.2 Entity graph: a fetch plan without changing the JPQL

```java
EntityGraph<PurchaseOrder> g = s.createEntityGraph(PurchaseOrder.class);
g.addAttributeNode("customer");
g.addAttributeNode("lines");
s.createQuery("from PurchaseOrder o where o.id <= 3", PurchaseOrder.class)
 .setHint("jakarta.persistence.fetchgraph", g).getResultList();
```

```text
  SQL> select po1_0.id,c1_0.id,c1_0.name,l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku from f_order po1_0 left join f_customer c1_0 on c1_0.id=po1_0.customer_id...
  statements: 1
```

In Spring Data: `@EntityGraph(attributePaths = {"customer", "lines"})` on a repository method. `fetchgraph` means "these attributes eagerly, everything else lazy". `loadgraph` means "these eagerly, the rest as mapped".

### 2.3 Batch fetching: N+1 becomes 1+1

```properties
hibernate.default_batch_fetch_size=16      # or @BatchSize(size = 16) per association/entity
```

**Output (verified):** the same two loops as §1.

```text
=== [default_batch_fetch_size=16] 1. Load 10 orders, then touch order.customer.getName()
  SQL> select po1_0.id,po1_0.customer_id from f_order po1_0 order by po1_0.id fetch first ? rows only
  SQL> select c1_0.id,c1_0.name from f_customer c1_0 where c1_0.id = any (?)
  statements: 2
=== [default_batch_fetch_size=16] 2. Load 10 orders, then touch order.lines
  SQL> select po1_0.id,po1_0.customer_id from f_order po1_0 order by po1_0.id fetch first ? rows only
  SQL> select l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku from f_line l1_0 where l1_0.order_id = any (?)
  statements: 2
```

On PostgreSQL, Hibernate (6.x and later; verified here on 7.4) binds the whole batch as **one array parameter** (`= any (?)`) instead of `IN (?, ?, …)` with padded parameter counts, so there's **one SQL string** whatever the batch size (good for the server's plan cache and the driver's statement cache).

**Batch fetching is the best default safety net**: set `default_batch_fetch_size` globally (16–64), and N+1 bugs degrade into "N/16+1" without code changes. It doesn't replace targeted `JOIN FETCH` on hot paths, but it caps the damage everywhere else.

| Fix | Queries | Row duplication | Works with pagination? | Best for |
|---|---|---|---|---|
| `JOIN FETCH` / entity graph | 1 | Yes (× children) | See §4 | One collection, small result |
| Batch fetching | 1 + ⌈N/batch⌉ per association | No | Yes | Default safety net, multiple collections |
| Separate queries per collection (§3) | 1 + per collection | No | Yes | Several collections on a page |
| DTO projection (§6) | 1 | Controlled | Yes | Read-only views and APIs |

---

### 2.4 Verified: `@Fetch(SUBSELECT)` re-runs your query *without* the page limit 🧊

Subselect fetching promises "one extra query for all collections of the parents you loaded". It keeps that promise by **re-embedding the original query's `WHERE`** as a subquery, and the limit doesn't come along:

```java
@OneToMany(mappedBy = "basket") @Fetch(FetchMode.SUBSELECT) List<Line> lines;

// 30 baskets (15 'odd'), 3 lines each; load ONE page of 5 odd baskets, then touch each basket's lines
List<Basket> page = s.createSelectionQuery("from Basket b where b.owner = 'odd' order by b.id", Basket.class)
        .setMaxResults(5).getResultList();
for (Basket b : page) n += b.lines.size();
```

**Output (verified, Hibernate 7.4.13, with `generate_statistics`):**

```text
  SQL> select b1_0.id,b1_0.owner from d_basket b1_0 where b1_0.owner='odd' order by b1_0.id fetch first ? rows only
  SQL> select l1_0.basket_id,l1_0.id,l1_0.sku from d_line l1_0 where l1_0.basket_id in (select b1_0.id from d_basket b1_0 where b1_0.owner='odd')
  baskets=5 lines in those baskets=15  statements=2  Line entities loaded=45  collections loaded=15
```

* Two statements, as advertised, but the second one has **no `fetch first`**: it loaded the lines of **all 15** odd baskets (**45** `Line` entities, **15** collections initialized) to serve a page of 5. With 1,000,000 matching parents, a page of 20 loads every child of every matching parent.
* It also re-executes the parent predicate, so an expensive parent query runs twice.
* Use batch fetching (§2.3) for paginated screens; reserve `SUBSELECT` for non-paginated loads where you really want every child of every loaded parent.

## 3. Two collections: `MultipleBagFetchException` and the Cartesian product (verified) ⚡

```java
s.createQuery("select o from PurchaseOrder o join fetch o.lines join fetch o.payments", PurchaseOrder.class).getResultList();
```

```text
  MultipleBagFetchException: cannot simultaneously fetch multiple bags: [FetchLab$PurchaseOrder.lines, FetchLab$PurchaseOrder.payments]
```

A `List` without `@OrderColumn` is a **bag**. Hibernate can't de-duplicate bag elements coming from a Cartesian product (a bag may legally hold duplicates), so it refuses. Switching to `Set` makes it *compile* but not *good*:

```text
  50 orders x 3 lines x 2 payments -> joined rows = 300
```

300 rows to build 50 orders with 250 children: rows = parents × children₁ × children₂. With 20 lines and 20 payments per order it's 400 rows **per order**. Correct fix, verified:

```java
List<Long> ids = s.createQuery("select o.id from PurchaseOrder o order by o.id", Long.class)
                  .setFirstResult(10).setMaxResults(5).getResultList();          // 1. page the parents
List<PurchaseOrder> orders = s.createQuery(
        "select o from PurchaseOrder o join fetch o.lines where o.id in :ids order by o.id", PurchaseOrder.class)
        .setParameter("ids", ids).getResultList();                                  // 2. collection #1
s.createQuery("select o from PurchaseOrder o join fetch o.payments where o.id in :ids", PurchaseOrder.class)
        .setParameter("ids", ids).getResultList();                                  // 3. collection #2 (same instances!)
```

```text
  SQL> select po1_0.id from f_order po1_0 order by po1_0.id offset ? rows fetch first ? rows only
  SQL> select po1_0.id,po1_0.customer_id,l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku from f_order po1_0 join f_line l1_0 on po1_0.id=l1_0.order_id where po1_0...
  SQL> select po1_0.id,po1_0.customer_id,p1_0.order_id,p1_0.id,p1_0.amount from f_order po1_0 join f_payment p1_0 on po1_0.id=p1_0.order_id where po1_0.id...
  page ids=[11, 12, 13, 14, 15] lines[0]=3 payments[0]=2
```

Query 3 returns the **same** `PurchaseOrder` instances (identity map, [3.1 §2](01-Persistence-Context-Entity-States-Dirty-Checking.md)) and fills their `payments`. Three queries, no Cartesian product, correct pagination.

---

## 4. Pagination with `JOIN FETCH`: what Hibernate 7.4 does now (verified) 🧊

### 4.1 The historical problem

`SELECT o FROM Order o JOIN FETCH o.lines` + `setMaxResults(5)`: SQL `LIMIT 5` would cut **rows**, not orders, leaving the 5th order with a partial collection. So Hibernate up to 7.3 dropped the `LIMIT`, **fetched every row** and paginated in memory, logging:

```text
HHH90003004: firstResult/maxResults specified with collection fetch; applying in memory
```

On a large table that's an outage: the whole join loaded into the heap for a 20-row page.

### 4.2 Hibernate 7.4: the limit is applied to the parents in a derived table

```java
s.createQuery("select o from PurchaseOrder o join fetch o.lines order by o.id", PurchaseOrder.class).setMaxResults(5)
```

**Output (verified, full SQL):**

```sql
select po1_0.id,po1_0.customer_id,l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku
from (select po1_0.id,po1_0.customer_id
      from f_order po1_0
      where exists(select 1 from f_line l1_0 where po1_0.id=l1_0.order_id)
      order by po1_0.id offset ? rows fetch first ? rows only) po1_0(id,customer_id)
join f_line l1_0 on po1_0.id=l1_0.order_id
order by po1_0.id
```

No warning, no in-memory pagination. The inner query pages **orders** (keeping inner-join semantics with `EXISTS`), and the outer query joins all lines of exactly those orders. Even `hibernate.query.fail_on_pagination_over_collection_fetch=true` doesn't throw, because there's nothing in memory to prevent.

### 4.3 Which shapes still fall back, and one that breaks (verified on 7.4.13)

`setFirstResult(10).setMaxResults(5)` on four shapes:

| Query | Result |
|---|---|
| `left join fetch o.lines order by o.id` | ✅ SQL pagination (derived table, no `EXISTS`) |
| `join fetch o.customer join fetch o.lines order by o.id` | ✅ SQL pagination (the to-one join moves into the derived table) |
| `join fetch o.lines l order by l.sku, o.id` (**ordering by a collection column**) | ⚠️ Falls back: `HHH90003004 … applying in memory`, SQL without a limit |
| `join fetch o.lines l where l.qty > 1 order by o.id` (**filtering the fetched collection**) | ❌ **Invalid SQL**: `ERROR: missing FROM-clause entry for table "l1_0"` (the rewrite moved `l1_0.qty>1` into the derived table where `l1_0` doesn't exist) |

**Output (verified, the fallback case):**

```text
WARN org.hibernate.orm.query -- HHH90003004: firstResult/maxResults specified with collection fetch; applying in memory
  SQL> select po1_0.id,po1_0.customer_id,l1_0.order_id,l1_0.id,l1_0.qty,l1_0.sku from f_order po1_0 join f_line l1_0 on po1_0.id=l1_0.order_id order by l1_0.sku,po1_0.id
```

…and with `fail_on_pagination_over_collection_fetch=true`:

```text
  HibernateException: setFirstResult() or setMaxResults() specified with collection fetch join (in-memory pagination was about to be applied, but 'hibernate.query.fail_on_pagination_over_collection_fetch' is enabled)
```

**Staff-level guidance:**

1. **Keep `hibernate.query.fail_on_pagination_over_collection_fetch=true`** in every environment. On 7.4 it costs nothing for the shapes that now paginate in SQL and turns the remaining fallbacks into immediate test failures instead of production heap blowups.
2. **Never filter a fetched collection** (`join fetch o.lines l where l.qty > 1`). Even without pagination it gives you entities with **incomplete collections** that look complete, and the persistence context will happily flush them. Filter with a separate join alias, or use a DTO.
3. On Hibernate ≤ 7.3, or for the fallback shapes, use the **two-step pattern** of §3 (page ids, then fetch by ids).
4. Prefer **keyset** pagination for deep pages anyway ([2.4](../02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)). The derived-table rewrite still uses `OFFSET`.

### 4.4 Keyset scrolling in Spring Data (verified)

```java
public interface EventRepo extends JpaRepository<Event, Long> {
    Window<Event> findFirst3ByKindOrderByIdAsc(String kind, ScrollPosition position);
}

Window<Event> w = events.findFirst3ByKindOrderByIdAsc("odd", ScrollPosition.keyset());
while (true) {
    System.out.println("  page: " + w.getContent().stream().map(e -> e.id).toList() + " hasNext=" + w.hasNext());
    if (!w.hasNext()) break;
    w = events.findFirst3ByKindOrderByIdAsc("odd", w.positionAt(w.size() - 1));
}
```

```text
  SQL> select e1_0.id,e1_0.kind from sd_event e1_0 where e1_0.kind=? order by e1_0.id fetch first ? rows only
  page: [1, 3, 5] hasNext=true
  SQL> select e1_0.id,e1_0.kind from sd_event e1_0 where (e1_0.kind=?) and (e1_0.id>?) order by e1_0.id fetch first ? rows only
  page: [7] hasNext=false
```

The second page is a **seek** (`id > ?`), not an offset. As with hand-written keyset queries, make the sort unique (end it with the id) so page boundaries can't skip or repeat rows.

---

## 5. `LazyInitializationException` and Open Session In View ⚡

```java
PurchaseOrder detached = sf.fromTransaction(s -> s.find(PurchaseOrder.class, 1L));
detached.lines.size();
```

```text
  LazyInitializationException: Cannot lazily initialize collection of role 'FetchLab$PurchaseOrder.lines' with key '1' (no session)
```

The collection is a `PersistentBag` that needs an open session to load. Wrong fixes and right fixes:

| ❌ "Fix" | Why it's wrong | ✅ Fix |
|---|---|---|
| `FetchType.EAGER` | Loads it **everywhere**, forever, often with N+1 | Fetch plan for *this* use case (`JOIN FETCH`, entity graph) |
| `hibernate.enable_lazy_load_no_trans=true` | Opens a **new connection and transaction per lazy access**, an N+1 with extra steps | Load what you need inside the transaction |
| Open Session In View (Spring Boot's default `spring.jpa.open-in-view=true`, with a startup warning) | Keeps a connection-bound session through view rendering. Lazy loads fire from JSON serialization **outside** your service's transaction, hold DB connections for the whole request, and hide N+1s | `spring.jpa.open-in-view=false` + DTOs built inside the service |
| `Hibernate.initialize(o.getLines())` in the controller | Works, but scatters fetch decisions | Fetch plans in the repository/query layer |

The sibling kit measures OSIV's effect on connection hold time: [Java-Backend-Master-Reference 5.4](../../Java-Backend-Master-Reference/05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md).

---

## 6. Projections: don't hydrate what you won't modify 🔥

```java
public record OrderSummary(Long orderId, String customerName, long lineCount) {}

s.createQuery("""
    select new FetchLab$OrderSummary(o.id, c.name, count(l))
    from PurchaseOrder o join o.customer c join o.lines l
    where o.id <= 3 group by o.id, c.name order by o.id""", OrderSummary.class)
```

**Output (verified):**

```text
  SQL> select po1_0.id,c1_0.name,count(l1_0.id) from f_order po1_0 join f_customer c1_0 on c1_0.id=po1_0.customer_id join f_line l1_0 on po1_0.id=l1_0.ord...
  OrderSummary[orderId=1, customerName=customer-1, lineCount=3]
  OrderSummary[orderId=2, customerName=customer-2, lineCount=3]
  OrderSummary[orderId=3, customerName=customer-3, lineCount=3]
  managed entities in session: 0
```

Exactly the needed columns, aggregation in SQL, and **zero managed entities**: no snapshots, no dirty checking, no lazy-loading surprises, nothing to accidentally flush. For read APIs this should be the **default**. Entities are for use cases that *change* state.

| Projection style | Notes |
|---|---|
| JPQL `select new pkg.Dto(...)` | Works everywhere. Fully qualified class name (here a nested class: `FetchLab$OrderSummary`) |
| Hibernate 6+ query-typed results | `createQuery("select o.id, c.name from …", OrderSummary.class)` matches the constructor by position |
| Spring Data interface projections | `interface OrderView { Long getId(); String getCustomerName(); }`. Closed projections select only those columns |
| Spring Data DTO (class/record) projections | Return type of a query method; constructor expression generated for you |
| Native SQL / `JdbcClient` / jOOQ | Window functions, CTEs, `LATERAL`, anything JPQL can't say ([3.4](04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)) |

---

## 7. ❌ Naïve vs ✅ production-hardened fetching

| ❌ Naïve | ✅ Hardened |
|---|---|
| `@ManyToOne` left at the default EAGER | Everything `LAZY`; fetch plans per use case |
| No statement-count assertions | Tests assert statement counts on hot endpoints |
| `JOIN FETCH` two `List`s, switch them to `Set` to silence the exception | Separate queries per collection, or batch fetching (no Cartesian product) |
| Trust "Hibernate paginates fetch joins in memory, always" | Know your version: 7.4 paginates most shapes in SQL. Keep `fail_on_pagination_over_collection_fetch=true` for the rest |
| `join fetch o.lines l where l.qty > 1` | Never filter a fetched collection (incomplete collections; invalid SQL with pagination on 7.4.13) |
| OSIV on, entities serialized to JSON | OSIV off; DTOs assembled in the transaction |
| Entities for every read | DTO projections for reads; entities for writes |
| No `default_batch_fetch_size` | 16–64 globally as a safety net |

---

## 8. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [hibernate/hibernate-orm](https://github.com/hibernate/hibernate-orm) | `hibernate-core/src/main/java/org/hibernate/loader/MultipleBagFetchException.java` | Where the bag check happens |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/query/sqm/internal/ConcreteSqmSelectQueryPlan.java` | Where in-memory pagination is decided (look for `HHH90003004` / `fail_on_pagination`) |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/loader/ast/internal/` (`*BatchLoader*`, `LoaderSelectBuilder`) | Batch loaders and the `= any(?)` array strategy |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/graph/` | Entity graph semantics (fetch vs load graph) |
| [spring-projects/spring-data-jpa](https://github.com/spring-projects/spring-data-jpa) | `spring-data-jpa/src/main/java/org/springframework/data/jpa/repository/query/KeysetScrollSpecification.java` | How `ScrollPosition.keyset()` becomes `id > ?` |
| [spring-projects/spring-boot](https://github.com/spring-projects/spring-boot) | Search for `JpaWebConfiguration` / `open-in-view` | The OSIV interceptor and its startup warning |

---

## 9. Interview soundbites

* "N+1 is a round-trip problem. Ten orders and a lazy customer were 11 statements; with `default_batch_fetch_size` it was 2, using one `= any(?)` array parameter on PostgreSQL."
* "Two `List` collections can't be join-fetched together. I page the parent ids, then fetch each collection in its own query; the identity map stitches them together without a Cartesian product."
* "Hibernate 7.4 paginates a collection fetch in SQL with a derived table of parent rows. It still falls back to memory when you order by a collection column, so I keep `fail_on_pagination_over_collection_fetch=true`."
* "Never filter a fetched collection. You get incomplete collections, and on 7.4.13 with pagination it even produced invalid SQL."
* "For reads I default to DTO projections: only the needed columns, zero managed entities."
* "`@Fetch(SUBSELECT)` re-runs the parent `WHERE` without the limit: a page of 5 baskets loaded 45 lines of 15 baskets. For pages I use batch fetching."

> **Go deeper in this batch:** what batch fetching, IN lists and the 7.4 pagination rewrite look like in `EXPLAIN` and in `pg_stat_statements` is in [3.7 §3–§4](07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#3-what-batch-fetching-and-in-lists-look-like-on-the-wire-verified-).

---

## Summary

| Fix / trap | Queries | Verified evidence |
|---|---|---|
| N+1 (lazy `@ManyToOne` / collection) | 1 + N | 10 orders → 11 statements |
| `JOIN FETCH` / entity graph | 1 | One query, rows × children |
| Batch fetching (`= any (?)`) | 1 + ⌈N / batch⌉ | 11 → 2 statements; one SQL shape for any batch size |
| `@Fetch(SUBSELECT)` | 1 + 1, **but children of every matching parent** | page of 5 → 45 lines of 15 baskets loaded |
| Two bags fetched together | `MultipleBagFetchException` / Cartesian product | Split into one query per collection |
| Fetch join + pagination (7.4) | Derived table of parents | Falls back to memory when ordering by a collection column; invalid SQL when filtering it |
| Keyset scrolling (Spring Data) | Seek on the sort key | §4.4 |
| `LazyInitializationException` / OSIV | Lazy access after the session closed | Turn OSIV off; fetch what the view needs |
| DTO projections | 1, no managed entities | Default for read paths |

**Next:** [3.4 Write throughput: batching, sequences, hybrid JDBC & jOOQ →](04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)
