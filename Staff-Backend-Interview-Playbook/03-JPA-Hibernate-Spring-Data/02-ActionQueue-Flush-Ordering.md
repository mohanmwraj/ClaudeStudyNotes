# 3.2 The `ActionQueue`: Why Hibernate Runs `INSERT` Before `DELETE`, and How to Control Flush Ordering

> **Verified stack:** Hibernate ORM **7.4.13.Final**, PostgreSQL **18.6**. The execution order below was read **from the running Hibernate** via reflection on `ActionQueue.ORDERED_OPERATIONS`, not copied from a blog.

---

## 0. First principles: a unit of work must pick an order 🔥

Between two flushes you may `persist` some entities, change others, `remove` a few and mutate collections. Hibernate records each as an **action** in the session's `ActionQueue`. At flush it must turn them into SQL **in some order**, and that order has to satisfy foreign keys (parents before children on insert, children before parents on delete) for *any* mix of operations, without knowing your business intent.

Hibernate's answer is a **fixed order by action type**, not the order of your method calls. Most of the time that's exactly right. The rest of the time it produces errors that look impossible ("I deleted it first!").

---

## 1. The order, as the running Hibernate reports it (verified) 🔥

```java
Field f = ActionQueue.class.getDeclaredField("ORDERED_OPERATIONS");
f.setAccessible(true);
System.out.println("  " + Arrays.toString((Object[]) f.get(null)));
```

**Output (verified, Hibernate 7.4.13.Final):**

```text
=== 4. ActionQueue execution order (Hibernate 7.4.13.Final)
  [OrphanCollectionRemoveAction, OrphanRemovalAction, EntityInsertAction, EntityUpdateAction, QueuedOperationCollectionAction, CollectionRemoveAction, CollectionUpdateAction, CollectionRecreateAction, EntityDeleteAction]
```

```text
flush()
  1. OrphanCollectionRemoveAction  ─┐ special orphan-removal actions (NOT the path every orphan takes:
  2. OrphanRemovalAction           ─┘ §3 shows orphaned children deleted AFTER inserts on 7.4.13)
  3. EntityInsertAction            ← INSERTs (topologically sorted by FK if hibernate.order_inserts)
  4. EntityUpdateAction            ← UPDATEs from dirty checking
  5. QueuedOperationCollectionAction (queued ops on lazy, uninitialized collections)
  6. CollectionRemoveAction        ┐
  7. CollectionUpdateAction        ├ join tables / element collections / one-to-many FK updates
  8. CollectionRecreateAction      ┘
  9. EntityDeleteAction            ← DELETEs, LAST
```

**Why deletes go last:** by the time deletes run, every update that might **remove references** to the doomed rows (setting a FK to null, moving a child to another parent) has been executed. Deleting first would violate FKs that the *same* flush was about to fix. Inserts go first so new rows exist before updates and collection rows reference them.

---

## 2. The trap: delete and re-insert the same unique key (verified) 🔥

A very common pattern: "replace the customer row" or "remove the old line and add a new one with the same natural key", in one transaction.

```java
sf.inTransaction(s -> {
    Customer old = s.createQuery("from Customer where email = 'ada@x.io'", Customer.class).getSingleResult();
    s.remove(old);
    s.persist(new Customer("ada@x.io", "Ada Lovelace", "London"));
});
```

**Output (verified):**

```text
  SQL> select c1_0.id,c1_0.city,c1_0.email,c1_0.name from pc_customer c1_0 where c1_0.email='ada@x.io'
  SQL> insert into pc_customer (city,email,name,id) values (?,?,?,?)
WARN org.hibernate.orm.jdbc.error -- HHH000247: ErrorCode: 0, SQLState: 23505
WARN org.hibernate.orm.jdbc.error -- ERROR: duplicate key value violates unique constraint "pc_customer_email_key"
  Detail: Key (email)=(ada@x.io) already exists.
  FAILED: RollbackException / root: ERROR: duplicate key value violates unique constraint "pc_customer_email_key"
```

Note what **didn't** happen: the `DELETE` was never even sent. Your code called `remove()` first, but the queue executed `EntityInsertAction` before `EntityDeleteAction`, so the new row collided with the old one.

### Fix 1: flush between the operations (verified)

```java
sf.inTransaction(s -> {
    Customer old = s.createQuery("from Customer where email = 'ada@x.io'", Customer.class).getSingleResult();
    s.remove(old);
    s.flush();                                   // execute the DELETE now
    s.persist(new Customer("ada@x.io", "Ada Lovelace", "London"));
});
```

```text
  SQL> select c1_0.id,c1_0.city,c1_0.email,c1_0.name from pc_customer c1_0 where c1_0.email='ada@x.io'
  SQL> delete from pc_customer where id=?
  SQL> insert into pc_customer (city,email,name,id) values (?,?,?,?)
```

Both statements run inside the same database transaction, so other sessions never see the gap.

### Fix 2 (often better): don't delete, update

If the "new" row is the same business entity, **mutate the managed instance** (one `UPDATE`, history preserved, no unique-key dance). Delete-and-reinsert usually means the domain model treats a value as an entity.

### Fix 3: deferrable constraints (PostgreSQL)

```sql
alter table customer add constraint customer_email_uk unique (email) deferrable initially deferred;
```

The uniqueness check moves to `COMMIT`, so any statement order inside the transaction works. It costs a little (deferred checks are tracked per transaction) and isn't available on every database or for every constraint type (MySQL has none).

---

## 3. The same trap with collections 🧊

Collections and orphan removal hit the same wall. The step names `OrphanRemovalAction` suggest orphans are deleted early, so I tested three spellings of "replace a child that has a unique key" on Hibernate 7.4.13 (unique `(basket_id, sku)` on items, unique `code` on a one-to-one coupon):

```text
=== A. basket.items.remove(old) + items.add(new same sku)  -> orphan removal (orphanRemoval = true)
  SQL> insert into o_item (basket_id,qty,sku,id) values (?,?,?,?)
  FAILED: ERROR: duplicate key value violates unique constraint "o_item_basket_id_sku_key"
=== B. session.remove(old) + persist(new same sku)  -> entity delete
  SQL> insert into o_item (basket_id,qty,sku,id) values (?,?,?,?)
  FAILED: ERROR: duplicate key value violates unique constraint "o_item_basket_id_sku_key"
=== C. replace a @OneToOne(orphanRemoval = true) child with a new one with the same unique code
  SQL> insert into o2_coupon (code,id) values (?,?)
  FAILED: ERROR: duplicate key value violates unique constraint "o2_coupon_code_key"
```

**All three failed the same way: the INSERT ran first.** Orphan removal doesn't save you here. Don't rely on a blog's description of which action type applies to your mapping; when two operations on the same unique key must happen in order, `flush()` between them (or update the existing child's fields instead of replacing it). Other collection behaviors worth knowing:
* **`@ElementCollection List<…>` without an order column** is a *bag*: rows have no identity, so Hibernate can't delete just one. Verified, removing **one** of five tags:

  ```text
  === remove ONE element from a List (bag) element collection
    SQL> delete from b_post_tag_list where Post_id=?
    SQL> insert into b_post_tag_list (Post_id,tagList) values (?,?)
    SQL> insert into b_post_tag_list (Post_id,tagList) values (?,?)
    SQL> insert into b_post_tag_list (Post_id,tagList) values (?,?)
    SQL> insert into b_post_tag_list (Post_id,tagList) values (?,?)
  === remove ONE element from a Set element collection
    SQL> delete from b_post_tag_set where Post_id=? and tagSet=?
  ```

  Delete everything, re-insert the 4 survivors: with 5,000 elements that's 5,001 statements for a one-element change. Use a `Set`, an `@OrderColumn`, or promote the element to an entity with its own id.
* **Unidirectional `@OneToMany` with `@JoinColumn`**: the FK is written by *collection* actions (steps 5–8), separately from the child's own `INSERT`. Verified, persisting an invoice with two lines:

  ```text
    SQL> insert into u_invoice (id) values (?)
    SQL> insert into u_line (sku,id) values (?,?)
    SQL> insert into u_line (sku,id) values (?,?)
    SQL> update u_line set invoice_id=? where id=?
    SQL> update u_line set invoice_id=? where id=?
  ```

  Each child row is inserted with a **null** FK and fixed by an extra `UPDATE` (so the FK column can't even be `NOT NULL` without extra mapping). Prefer **bidirectional** mappings owned by the `@ManyToOne` side, where the FK is part of the child's `INSERT`.

The rule that covers all of these: **when the order of two operations matters to a constraint, make it explicit with `flush()`**, or restructure so the order doesn't matter.

---

## 4. Ordering *within* a step: `order_inserts` / `order_updates` ⚡

Within step 3, inserts run in **the order you persisted them**. With JDBC batching that's a problem: alternating `persist(order); persist(line); persist(order); persist(line)` produces 4 batches of 1 instead of 2 batches of 2, because a batch holds a single SQL string.

```properties
hibernate.jdbc.batch_size=50
hibernate.order_inserts=true     # group inserts by entity type, topologically sorted by FK dependencies
hibernate.order_updates=true     # group updates by entity type, then by id (also reduces deadlocks: consistent lock order)
```

`order_updates` sorting by primary key has a second benefit: concurrent transactions updating overlapping rows lock them **in the same order**, which removes a whole class of deadlocks ([2.6 §5](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)). Batching itself, and why `IDENTITY` disables it, is in [3.4](04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md).

---

## 5. Flush timing in a Spring service 🔥

```java
@Transactional
public void rename(long id, String email) {
    Customer c = repo.findById(id).orElseThrow();
    c.setEmail(email);                      // nothing happens yet
    auditClient.send(new Audit(id, email)); // ❌ external side effect BEFORE the UPDATE ran (and before constraint checks)
}                                            // flush + commit here: the UPDATE may now fail on a unique constraint
```

The `UPDATE` (and any unique-constraint violation) happens **after your method returns**, inside the transaction interceptor. Two consequences:

1. **Side effects before the flush can't be undone** if the flush fails. Publish after commit with `@TransactionalEventListener(phase = AFTER_COMMIT)` or, better, an outbox ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).
2. **Constraint violations surface as `DataIntegrityViolationException` from the proxy**, not from the line that caused them. If you need to translate a specific violation (duplicate email → 409), call `repo.saveAndFlush(...)` / `em.flush()` inside the method, in a `try` block.

---

### 5.1 Verified: AUTO flush is per query space for JPQL, but global for native SQL 🧊

`FlushMode.AUTO` doesn't flush before every query. For JPQL/HQL, Hibernate flushes only if the query's **tables (query spaces)** overlap the pending actions. A native query is opaque, so Hibernate flushes **everything** first:

```java
sf.inTransaction(s -> {
    s.persist(new Item(1L, "a", BigDecimal.ONE, null));                                      // pending INSERT into d_item
    s.createSelectionQuery("select count(b) from Basket b", Long.class).getSingleResult();    // JPQL on d_basket
});
sf.inTransaction(s -> {
    s.persist(new Item(2L, "b", BigDecimal.ONE, null));
    s.createNativeQuery("select count(*) from d_basket", Long.class).getSingleResult();      // native, also on d_basket
});
```

**Output (verified, Hibernate 7.4.13):**

```text
=== persist an Item, then a JPQL query on a DIFFERENT entity (Basket)
  SQL> select count(b1_0.id) from d_basket b1_0
  basket count = 0
  -- (commit follows)
  SQL> [batch x1] insert into d_item (name,note,price,id) values (?,?,?,?)
=== persist an Item, then a native query on a DIFFERENT table (d_basket)
  SQL> [batch x1] insert into d_item (name,note,price,id) values (?,?,?,?)
  SQL> select count(*) from d_basket
  basket count = 0
```

* JPQL on `Basket` didn't flush the `Item` insert (it went out at commit, after the query); the native query flushed it **before** running, although it reads a different table.
* Consequences: in a unit of work with many pending changes, every native query triggers a full flush (dirty-checking every managed entity, sending batches early, possibly hitting constraint errors at an unexpected line). Declare what a native query reads: `createNativeQuery(sql, X.class).addSynchronizedEntityClass(Basket.class)` (or `addSynchronizedQuerySpace("d_basket")`) and Hibernate flushes only overlapping actions, the same rule that keeps the second-level cache intact ([3.7 §2](07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#2-the-second-level-cache-hits-invalidation-and-staleness-verified-)).
* The reverse trap: if a JPQL query reads data that a **native** write changed earlier in the same session, Hibernate doesn't know; query results and managed entities can disagree until you `refresh()` or `clear()`.

## 6. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| `remove(old); persist(newWithSameKey)`, or "orphanRemoval will delete it first" | `remove(old); flush(); persist(new)`, or update in place, or a deferrable constraint (all three replacement spellings failed on 7.4.13) |
| Assume SQL order = method call order | Know the 9-step order; force order with `flush()` |
| `@ElementCollection List<String>` holding thousands of entries | `Set`, `@OrderColumn`, or an entity with its own id |
| Unidirectional `@OneToMany` with `@JoinColumn` | Bidirectional, owned by `@ManyToOne` |
| Batching on, `order_inserts` off | `order_inserts`/`order_updates` on (fewer batches, consistent lock order) |
| Send messages inside `@Transactional` before commit | Outbox, or `AFTER_COMMIT` listener |
| Expect a duplicate-key error from the `save()` line | `saveAndFlush()` in a `try` where you translate it |

---

## 7. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [hibernate/hibernate-orm](https://github.com/hibernate/hibernate-orm) | [hibernate-core … org/hibernate/engine/spi/ActionQueue.java on the 7.4 branch](https://github.com/hibernate/hibernate-orm/blob/7.4/hibernate-core/src/main/java/org/hibernate/engine/spi/ActionQueue.java) (the class the 7.4.13 jar ships; it's no longer at that path on `main`) | `ORDERED_OPERATIONS`, `executeActions`, `InsertActionSorter` (the topological sort behind `order_inserts`) |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/event/internal/AbstractFlushingEventListener.java` | `flushEverythingToExecutions` then `performExecutions`: the two halves of a flush |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/action/internal/EntityDeleteAction.java` | What a delete action carries |
| hibernate/hibernate-orm | `hibernate-core/src/main/java/org/hibernate/event/internal/DefaultAutoFlushEventListener.java` | When a query triggers a flush |

---

## 8. Interview soundbites

* "Hibernate executes by action type, not call order: orphan removals, inserts, updates, collection changes, and deletes last. I read the order from `ActionQueue.ORDERED_OPERATIONS` on 7.4."
* "Delete-then-insert of the same unique key fails because the INSERT runs first. The DELETE wasn't even sent. I `flush()` between them, or better, update in place."
* "`order_inserts` and `order_updates` give bigger batches and a consistent lock order."
* "The UPDATE runs after my method returns, so constraint errors come from the proxy, and side effects sent before commit can't be rolled back."
* "AUTO flush is per query space for JPQL but global for native SQL: a native count on an unrelated table flushed my pending insert. `addSynchronizedEntityClass` scopes it."

---

## Summary

| Concept | One line | Verified evidence |
|---|---|---|
| Flush order | By action type: orphan removals, inserts, updates, collection changes, deletes last | `ActionQueue.ORDERED_OPERATIONS` on 7.4 |
| Delete + re-insert of a unique key | The INSERT runs before the DELETE | Duplicate-key error; fixed by `flush()` between or update-in-place |
| Collections | Same trap with element collections and orphan removal | §3 |
| `order_inserts` / `order_updates` | Group by entity: bigger batches, consistent lock order | §4 |
| Flush timing in Spring | SQL runs after your method returns, inside the proxy | Constraint errors surface at commit |
| AUTO flush scope | JPQL: only overlapping query spaces; native: everything | Native query on `d_basket` flushed an `Item` insert; JPQL didn't |

**Next:** [3.3 N+1, lazy loading, fetch plans, pagination & projections →](03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)
