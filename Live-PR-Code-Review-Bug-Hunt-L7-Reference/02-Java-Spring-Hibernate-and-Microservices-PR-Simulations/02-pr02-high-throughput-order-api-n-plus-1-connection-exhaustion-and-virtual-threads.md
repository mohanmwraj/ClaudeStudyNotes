# PR02 · High-Throughput Order API: N+1, Connection Exhaustion and Virtual Threads

> **What this module is.** A merchant-dashboard PR on Hibernate ORM 7 and PostgreSQL 18 that "moves the order API to virtual threads for throughput." It hides **7 defects (3 Sev-1)** and **one decoy**. The decoy is a pattern that was a famous bug in older Hibernate versions and, as measured here, is *not* one on Hibernate 7.4. L7 reviewers check the version before asserting, and the decoy is there to test precision as much as recall. Production runs **JDK 21 LTS**, so tests and probes run on JDK 21 too, where `synchronized` still pins virtual threads.

| Artifact | What it is | Verified |
|---|---|---|
| `pr02-diff` | 5 files changed (2 entities modified, 3 new classes) + the new test class: 249 diff lines | `git diff --no-index` from the compiled sources |
| `DashboardServiceTest` (author's) | 4 JUnit tests on real Hibernate + PostgreSQL | **4/4 pass** (§4) |
| `Pr02Probes` | 8 probes: checkout with 2 lines, a 20-row page over 2,000 orders (entities + SQL), 8 concurrent dashboards, risk outage, carrier pinning, formatter churn, the recalc job | each defect shown on the PR and absent on the fix (§8) |
| Fixed code | Projection query, bulkhead with a latency budget, no DB work in fan-out tasks, scheduled tier refresh, null-safe entity equality, set-based recalculation | fixed suite 7/7; PR's own tests against the fix 4/4 |

**Verification.** Hibernate ORM 7.4.13.Final (JPA 3.2 `PersistenceConfiguration` bootstrap), HikariCP 7.0.2, PostgreSQL 18.6 (embedded) and the PostgreSQL JDBC driver 42.7.14. Compiled with JDK 25 `javac --release 21 -Xlint:all -Werror`; **tests and probes run on JDK 21.0.12.1** with `-Djdk.virtualThreadScheduler.parallelism=2 -Djdk.virtualThreadScheduler.maxPoolSize=2`, so carrier effects show at small scale. Statement counts come from Hibernate `Statistics`, SQL text from a `StatementInspector`, and pool state from `HikariPoolMXBean`. P4 and P6 are timing-dependent and labeled "one measured run".

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L1 Correctness | F2 entity `equals`/`hashCode` on a generated id inside a `Set` | The diff touches `OrderLine`; the damage happens in `OrderService.create`, which is not in the diff |
| L2 Concurrency | F5 `synchronized` around a remote refresh (pinning on JDK 21) | "It's a tiny cache, synchronized is fine," and it was, on platform threads |
| L3 Failure paths | F4 `EntityManager` not closed on the exception path | The happy path closes it |
| L4 I/O | F3 every fan-out task holds a pooled connection across an HTTP call | Virtual threads make the concurrency invisible: no pool size in sight |
| L7 Operability | F1 N+1 on customers, F6 `ThreadLocal` caching per virtual thread, F7 whole-table recalculation in one persistence context | Fine at test scale (3 orders) |
| Precision | D1 `join fetch` + `setMaxResults` | Was in-memory pagination on older Hibernate; Hibernate 7.4 paginates in SQL |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "Virtual threads remove the concurrency limit." | They move it to the next bounded resource: the connection pool. |
| "Hibernate requires equals/hashCode for Sets." | An id-based implementation silently merges unsaved entities. |
| "`try-with-resources` is for the happy path." | The fan-out task opens an `EntityManager` without it. |
| "I know this Hibernate gotcha." | Version-dependent knowledge, unverified, is a false positive. |
| "Cache expensive objects in a ThreadLocal." | With one virtual thread per task, every task gets its own copy. |

---

## 1. First principles

1. **Virtual threads are a scheduling change, not a capacity change.** They make *waiting* cheap. Every downstream resource (connections, sockets, API rate limits, memory) keeps its old limit. JEP 444's guidance: virtual threads "should never be pooled". To limit concurrency to a resource, use a semaphore around that resource.
2. **Pinning on JDK 21.** JEP 444 lists running code inside a `synchronized` block or method as a case where "a virtual thread cannot be unmounted during blocking operations because it is pinned," and warns that "frequent pinning for long durations can harm the scalability of an application by capturing carriers." JDK 24's JEP 491 removed pinning for `synchronized`. This service runs on 21.
3. **`ThreadLocal` is per thread, and there are now millions of threads.** JEP 444: "do not use thread locals to pool costly resources among multiple tasks."
4. **A resource-local transaction holds a pooled connection from `begin()` to `commit()`/`rollback()`.** Anything slow between them (an HTTP call) multiplies pool occupancy. Anything that throws between them without a `finally` leaks the connection: `close()` is never called.
5. **Entity identity in hash-based collections.** A generated id is `null` until `persist()`/flush. An `equals` that compares ids treats all unsaved instances as equal; a `hashCode` that hashes the id changes when the id is assigned. The common safe pattern is "equal only when both ids are non-null and equal, with a constant `hashCode`."
6. **N+1 is a property of access patterns, not of mappings.** A `LAZY` `@ManyToOne` touched in a loop issues one query per distinct target. Hibernate `Statistics` (`getPrepareStatementCount`) turns "probably" into a number.
7. **Bulk work belongs in SQL.** Loading a table into one persistence context makes memory and flush-time dirty checking scale with the table, inside one long transaction.

---

## 2. The PR

> **ORD-871 · Merchant dashboard: recent orders with risk badges; virtual threads for the order API**
>
> Merchants want a dashboard of their most recent orders: customer name, line count, total after the customer's tier discount, and a fraud-risk badge from risk-service. Also: the nightly job that repairs order totals after last year's pricing incident needs rewriting in Java (currently a SQL script someone runs by hand).
>
> **PR description, by the author:**
> - `DashboardService.recentOrders()`: lines are join-fetched in the same query (no N+1), customers initialized while the session is open.
> - Risk badges are fetched in parallel, one virtual thread per order. "Virtual threads are cheap, so no pool tuning needed." Each task records `risk_checked_at`.
> - Tier discounts cached for a minute (a tiny `synchronized` cache).
> - `Order.lines` changed from `List` to `Set`, because join-fetching a bag returns duplicate parents. Added `equals`/`hashCode` to `OrderLine`, as Hibernate requires for Sets.
> - `NumberFormat` is expensive and not thread-safe, so it's cached in a `ThreadLocal`.
> - `RecalculateTotalsJob`: loads orders, recomputes from lines, and lets dirty checking write the changes.
> - 4 new tests, all green.
>
> **Context the reviewer can discover:** production runs **JDK 21** (Temurin 21.0.12). 40 pods. HikariCP `maximumPoolSize=10` per pod (PostgreSQL `max_connections=500`). risk-service p50 30 ms, p99 400 ms. The `orders` table holds 180 M rows; large merchants have 2 M orders each. Checkout (`OrderService.create`, not in this diff) creates orders with multiple lines.

---

## 3. The diff

```diff
diff --git a/order-service/src/main/java/com/acme/orders/DashboardService.java b/order-service/src/main/java/com/acme/orders/DashboardService.java
new file mode 100644
index 0000000..f47041c
--- /dev/null
+++ b/order-service/src/main/java/com/acme/orders/DashboardService.java
@@ -0,0 +1,76 @@
+package com.acme.orders;
+
+import jakarta.persistence.EntityManager;
+import jakarta.persistence.EntityManagerFactory;
+import java.text.NumberFormat;
+import java.time.Instant;
+import java.util.ArrayList;
+import java.util.List;
+import java.util.Map;
+import java.util.concurrent.ExecutionException;
+import java.util.concurrent.ExecutorService;
+import java.util.concurrent.Executors;
+import java.util.concurrent.Future;
+import java.util.concurrent.TimeUnit;
+
+/** Merchant dashboard: newest orders with customer, line count, discounted total and risk badge. */
+public class DashboardService {
+    private static final ThreadLocal<NumberFormat> USD = ThreadLocal.withInitial(Formats::usd); // reuse per thread
+
+    private final EntityManagerFactory emf;
+    private final RiskClient risk;
+    private final PricingClient pricing;
+    private Map<String, Integer> tierDiscounts;
+    private long tiersExpireAt;
+
+    public DashboardService(EntityManagerFactory emf, RiskClient risk, PricingClient pricing) {
+        this.emf = emf;
+        this.risk = risk;
+        this.pricing = pricing;
+    }
+
+    public List<OrderSummary> recentOrders(long merchantId, int limit) throws InterruptedException, ExecutionException {
+        List<Order> orders;
+        try (EntityManager em = emf.createEntityManager()) {
+            orders = em.createQuery("""
+                    select o from Order o join fetch o.lines
+                    where o.merchantId = :merchant order by o.createdAt desc""", Order.class) // lines too: no N+1
+                    .setParameter("merchant", merchantId)
+                    .setMaxResults(limit)
+                    .getResultList();
+            orders.forEach(o -> o.getCustomer().getName()); // initialize while the session is open
+        }
+        try (ExecutorService perOrder = Executors.newVirtualThreadPerTaskExecutor()) { // cheap: one per order
+            List<Future<OrderSummary>> futures = new ArrayList<>();
+            for (Order o : orders) {
+                futures.add(perOrder.submit(() -> summarize(o)));
+            }
+            List<OrderSummary> result = new ArrayList<>();
+            for (Future<OrderSummary> f : futures) {
+                result.add(f.get());
+            }
+            return result;
+        }
+    }
+
+    private OrderSummary summarize(Order o) {
+        EntityManager em = emf.createEntityManager();
+        em.getTransaction().begin();
+        boolean risky = risk.isRisky(o.getId());
+        em.createQuery("update Order o set o.riskCheckedAt = :now where o.id = :id")
+                .setParameter("now", Instant.now()).setParameter("id", o.getId()).executeUpdate();
+        em.getTransaction().commit();
+        em.close();
+        long discounted = o.getTotalMinor() * (10_000 - tierDiscount(o.getCustomer().getTier())) / 10_000;
+        return new OrderSummary(o.getId(), o.getCustomer().getName(), o.getLines().size(),
+                USD.get().format(discounted / 100.0), risky);
+    }
+
+    private synchronized int tierDiscount(String tier) { // refresh at most once a minute
+        if (tierDiscounts == null || System.nanoTime() - tiersExpireAt > 0) {
+            tierDiscounts = pricing.fetchTierDiscounts();
+            tiersExpireAt = System.nanoTime() + TimeUnit.MINUTES.toNanos(1);
+        }
+        return tierDiscounts.getOrDefault(tier, 0);
+    }
+}
diff --git a/order-service/src/main/java/com/acme/orders/Order.java b/order-service/src/main/java/com/acme/orders/Order.java
index 75802cc..6f0b8ec 100644
--- a/order-service/src/main/java/com/acme/orders/Order.java
+++ b/order-service/src/main/java/com/acme/orders/Order.java
@@ -12,8 +12,8 @@ import jakarta.persistence.ManyToOne;
 import jakarta.persistence.OneToMany;
 import jakarta.persistence.Table;
 import java.time.Instant;
-import java.util.ArrayList;
-import java.util.List;
+import java.util.HashSet;
+import java.util.Set;
 
 @Entity
 @Table(name = "orders")
@@ -38,8 +38,9 @@ public class Order {
     @Column(name = "risk_checked_at")
     private Instant riskCheckedAt;
 
+    // Set, not List: the dashboard join-fetches lines, and a List (bag) yields one parent row per line
     @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
-    private List<OrderLine> lines = new ArrayList<>();
+    private Set<OrderLine> lines = new HashSet<>();
 
     protected Order() {
     }
@@ -63,7 +64,7 @@ public class Order {
         return customer;
     }
 
-    public List<OrderLine> getLines() {
+    public Set<OrderLine> getLines() {
         return lines;
     }
 
diff --git a/order-service/src/main/java/com/acme/orders/OrderLine.java b/order-service/src/main/java/com/acme/orders/OrderLine.java
index e535a69..25d2b96 100644
--- a/order-service/src/main/java/com/acme/orders/OrderLine.java
+++ b/order-service/src/main/java/com/acme/orders/OrderLine.java
@@ -9,6 +9,7 @@ import jakarta.persistence.Id;
 import jakarta.persistence.JoinColumn;
 import jakarta.persistence.ManyToOne;
 import jakarta.persistence.Table;
+import java.util.Objects;
 
 @Entity
 @Table(name = "order_lines")
@@ -47,4 +48,14 @@ public class OrderLine {
     public long getUnitPriceMinor() {
         return unitPriceMinor;
     }
+
+    @Override
+    public boolean equals(Object o) { // required for entities kept in a Set
+        return o instanceof OrderLine other && Objects.equals(id, other.id);
+    }
+
+    @Override
+    public int hashCode() {
+        return Objects.hashCode(id);
+    }
 }
diff --git a/order-service/src/main/java/com/acme/orders/OrderSummary.java b/order-service/src/main/java/com/acme/orders/OrderSummary.java
new file mode 100644
index 0000000..8dae779
--- /dev/null
+++ b/order-service/src/main/java/com/acme/orders/OrderSummary.java
@@ -0,0 +1,3 @@
+package com.acme.orders;
+
+public record OrderSummary(long orderId, String customer, int lineCount, String total, boolean risky) {}
diff --git a/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java b/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java
new file mode 100644
index 0000000..b37c47e
--- /dev/null
+++ b/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java
@@ -0,0 +1,26 @@
+package com.acme.orders;
+
+import jakarta.persistence.EntityManager;
+import jakarta.persistence.EntityManagerFactory;
+import java.util.List;
+
+/** Nightly: recompute order totals from their lines (repairs drift from the 2025 pricing incident). */
+public class RecalculateTotalsJob {
+    private final EntityManagerFactory emf;
+
+    public RecalculateTotalsJob(EntityManagerFactory emf) {
+        this.emf = emf;
+    }
+
+    public int run() {
+        try (EntityManager em = emf.createEntityManager()) {
+            em.getTransaction().begin();
+            List<Order> orders = em.createQuery("select o from Order o", Order.class).getResultList();
+            for (Order o : orders) {
+                o.setTotalMinor(o.getLines().stream().mapToLong(l -> l.getQty() * l.getUnitPriceMinor()).sum());
+            }
+            em.getTransaction().commit(); // dirty checking writes the changed totals
+            return orders.size();
+        }
+    }
+}
diff --git a/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java b/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java
new file mode 100644
index 0000000..c33b2e0
--- /dev/null
+++ b/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java
@@ -0,0 +1,58 @@
+package com.acme.orders;
+
+import static org.junit.jupiter.api.Assertions.assertEquals;
+import static org.junit.jupiter.api.Assertions.assertFalse;
+import static org.junit.jupiter.api.Assertions.assertTrue;
+
+import com.zaxxer.hikari.HikariDataSource;
+import jakarta.persistence.EntityManagerFactory;
+import java.time.Instant;
+import java.util.List;
+import java.util.Set;
+import org.junit.jupiter.api.BeforeEach;
+import org.junit.jupiter.api.Test;
+import org.springframework.jdbc.core.JdbcTemplate;
+
+class DashboardServiceTest {
+    private static final HikariDataSource DS = Db.pool(10, 5_000);
+    private static final EntityManagerFactory EMF = Db.emf(DS);
+    private final DashboardService dashboard = new DashboardService(EMF, new FakeRisk(0, Set.of(2L)), new FakePricing(0));
+
+    @BeforeEach
+    void seed() {
+        Db.reset(DS);
+        new JdbcTemplate(DS).update("INSERT INTO customers (name, tier) VALUES ('Ann', 'GOLD'), ('Bob', 'BRONZE')");
+        OrderService orders = new OrderService(EMF);
+        for (int i = 1; i <= 3; i++) {
+            orders.create(i == 2 ? 2 : 1, 7, Instant.parse("2026-10-0" + i + "T10:00:00Z"),
+                    List.of(new OrderService.LineInput("SKU-" + i, 2, 1_000)));
+        }
+    }
+
+    @Test
+    void newestFirstAndLimited() throws Exception {
+        assertEquals(List.of(3L, 2L), dashboard.recentOrders(7, 2).stream().map(OrderSummary::orderId).toList());
+    }
+
+    @Test
+    void showsCustomerLinesAndDiscountedTotal() throws Exception {
+        OrderSummary newest = dashboard.recentOrders(7, 1).get(0);
+        assertEquals("Ann", newest.customer());
+        assertEquals(1, newest.lineCount());
+        assertEquals("$18.00", newest.total()); // GOLD: 10 % off 20.00
+    }
+
+    @Test
+    void flagsRiskyOrders() throws Exception {
+        List<OrderSummary> all = dashboard.recentOrders(7, 10);
+        assertTrue(all.get(1).risky());
+        assertFalse(all.get(0).risky());
+    }
+
+    @Test
+    void recalculationRestoresTotals() {
+        new JdbcTemplate(DS).update("UPDATE orders SET total_minor = 0");
+        assertEquals(3, new RecalculateTotalsJob(EMF).run());
+        assertEquals(6_000, Db.count(DS, "SELECT sum(total_minor) FROM orders"));
+    }
+}
```

---

## 4. The author's tests: green

```text
├─ JUnit Jupiter ✔
│  └─ DashboardServiceTest ✔
│     ├─ recalculationRestoresTotals() ✔
│     ├─ showsCustomerLinesAndDiscountedTotal() ✔
│     ├─ flagsRiskyOrders() ✔
│     └─ newestFirstAndLimited() ✔
[         4 tests found           ]
[         4 tests successful      ]
[         0 tests failed          ]
```

Every seeded order has **one** line, so the `Set` equality bug never fires. The risk fake answers in 0 ms, so no connection is held long enough to matter. Three orders hide N+1 and the recalculation job's scaling. Nothing runs on more than one request at a time.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** a new read endpoint at merchant scale (2 M orders for big merchants). A fan-out to a remote service. A changed **entity identity contract** (`OrderLine.equals`), which affects every code path that adds lines, including checkout, outside the diff. A nightly job over 180 M rows.
- **Hunk scores:** `DashboardService.summarize` 8/8 (state, I/O, transaction, concurrency); `recentOrders` 6/8; `OrderLine.equals/hashCode` 6/8 (contract change with blast radius beyond the diff); `RecalculateTotalsJob.run` 6/8; `tierDiscount` 4/8.
- **Radar hits:** `newVirtualThreadPerTaskExecutor` + `createEntityManager` inside the task (43–46, 57). `begin()` … remote call … `close()` with no `finally` (58–63). `synchronized` + remote fetch on JDK 21 (69–71). `ThreadLocal.withInitial` next to virtual threads (18). `Objects.equals(id, other.id)` on a generated id (OrderLine 54). `select o from Order o` with no `where` in a job (Recalc 18). `join fetch` + `setMaxResults` (36–39), a known pattern to *check*, not to assert.

### Minute 10: one hop each

- What does `OrderService.create` do with two new lines in a `HashSet` whose `equals` compares `null` ids? It keeps one: F2.
- What does each fan-out task hold during `risk.isRisky`? A pooled connection, from `begin()`. Tasks per request = page size; per pod = page size × concurrent dashboards: F3.
- What if `risk.isRisky` throws? `close()` never runs and the connection stays checked out: F4.
- Which JDK? 21, so `synchronized` + a blocking call pins a carrier, and waiting to enter the monitor pins more: F5.
- `orders.forEach(o -> o.getCustomer().getName())`: one query per distinct customer, F1.
- `ThreadLocal` + one virtual thread per task: zero reuse, F6.
- The job: every order and line in one persistence context, then dirty checking at commit, F7.
- `join fetch` + `setMaxResults`: check the Hibernate version and the SQL before flagging (D1).

### Minute 20: prove, unify, fix

- **Unify:** F3, F4 and F5 share a root cause. *The fan-out tasks do resource-holding work (a transaction, a lock) around a remote call.* Make the tasks pure I/O (risk calls only, bounded by a semaphore with a latency budget) and do all database work in two short statements outside them. F1 and the decoy both disappear with a single projection query. F2 is an entity-identity rule. F6 and F7 are scaling rules.
- **Evidence:** §8 has every number.

---

## 6. The L7 answer key, line by line

Line numbers are within each new or changed file (`+` side). `DashboardService.java` numbering is the file's own.

### F1 · L7 · Sev-2 · N+1 on customers (DashboardService 41)

**Mechanism.** `customer` is `LAZY`. `orders.forEach(o -> o.getCustomer().getName())` initializes each proxy with its own `SELECT`: one per distinct customer on the page. On a 20-row page that's up to 20 extra round trips per dashboard load, plus 20 more `UPDATE`s from the tasks.

**Evidence.** P3: `same request: SQL statements = 41` (fix: 2).

```comment-l7
issue (blocking): line 41 issues one SELECT per customer on the page (N+1)

The customer association is LAZY, so initializing it in a loop costs a round trip per distinct customer; with the per-task UPDATEs the P3 probe counts 41 statements for a 20-row page, which means 40+ round trips per dashboard view across 40 pods. Suggest one projection query (`select new OrderRow(o.id, c.name, c.tier, size(o.lines), o.totalMinor) ... join o.customer c`) and one batched UPDATE: 2 statements, no entities.
```

**Fix.**
```java
            rows = em.createQuery("""
                    select new com.acme.orders.OrderRow(o.id, c.name, c.tier, size(o.lines), o.totalMinor)
                    from Order o join o.customer c
                    where o.merchantId = :merchant order by o.createdAt desc, o.id desc""", OrderRow.class)
```

### F2 · L1 · Sev-1 · `equals`/`hashCode` on a generated id silently drops order lines at checkout (OrderLine 53–59; Order 41–43)

**Mechanism.** New `OrderLine`s have `id == null` until persisted. `Objects.equals(null, null)` is `true`, so all unsaved lines are "equal", and `HashSet.add` keeps only the first. `OrderService.create` (not in this diff) adds every line of a new order, so a 2-line checkout persists **one** line while `total_minor` still reflects both. Revenue reports, fulfilment and refunds then disagree with the charged total, silently. And `hashCode` changes when the id is assigned, so even surviving lines sit in the wrong bucket after persist (`contains`/`remove` fail).

**Evidence.** P1: `checkout with 2 lines: order_lines rows = 1, total_minor = 7,000 (lines sum to 1,000)`.

```comment-l7
issue (blocking): OrderLine.equals compares null ids, so new orders keep only one line

Before persist every new OrderLine has id == null, and `Objects.equals(null, null)` is true, which means the HashSet in `Order.addLine` drops every line after the first. Checkout (OrderService.create, outside this diff) is affected: the P1 probe creates a 2-line order and finds 1 row in order_lines while total_minor still counts both. Suggest equality only when both ids are non-null and equal, with a constant hashCode (so it stays valid when persist assigns the id), plus a checkout test with two lines.
```

**Fix.**
```java
    @Override
    public boolean equals(Object o) { // identity is the database id: two unsaved lines are never equal
        return o instanceof OrderLine other && id != null && id.equals(other.id);
    }

    @Override
    public int hashCode() { // constant, so it stays valid when persist() assigns the id
        return OrderLine.class.hashCode();
    }
```

### F3 · L4 · Sev-1 · Every fan-out task holds a pooled connection across the risk call (DashboardService 43–46, 57–62)

**Mechanism.** `summarize` begins a transaction (taking a connection) *before* calling risk-service, and commits after. One dashboard request = 20 tasks = 20 connections held for risk latency. Virtual threads remove the old Tomcat-thread cap, so nothing bounds this but the pool (10). Eight concurrent dashboards want 160 connections for 250 ms each. The pool queues them, Hikari's `connectionTimeout` expires, and **every endpoint on the pod** starts failing, checkout included.

**Evidence.** P4: `8 concurrent dashboards x 20 orders, pool 10, risk 250 ms: N of 8 requests failed` (one measured run; the fix: 0 of 8).

```comment-l7
issue (blocking): each per-order virtual thread holds a pooled connection for the whole risk-service call

`summarize` calls begin() (line 58, which takes a connection) before `risk.isRisky` (line 59), so a 20-row dashboard holds 20 of the pod's 10 connections at risk latency, and nothing bounds the fan-out now that the request threads are virtual. The P4 probe (8 concurrent dashboards, risk 250 ms) fails most requests with Hikari timeouts, which means checkout on the same pod fails too. Suggest keeping the tasks free of DB work (risk calls only, behind a semaphore with a latency budget that renders "unknown" past it) and recording risk_checked_at with one batched UPDATE after the fan-out.
```

**Fix.**
```java
        Boolean risky = null; // "unknown" unless risk-service answers in budget; the dashboard always renders
        if (riskPermits.tryAcquire(RISK_WAIT_MILLIS, TimeUnit.MILLISECONDS)) { // bulkhead on the remote call
            try {
                risky = risk.isRisky(r.id());
            } catch (RuntimeException e) {
                risky = null;
            } finally {
                riskPermits.release();
            }
        }
```
```java
            em.createQuery("update Order o set o.riskCheckedAt = :now where o.id in :ids")
```

### F4 · L3 · Sev-1 · `EntityManager` leaked when risk-service throws (DashboardService 57–63)

**Mechanism.** `createEntityManager()` and `begin()` are not in `try-with-resources`. When `risk.isRisky` throws (risk-service 503), `close()` is skipped, the transaction stays open and its connection stays checked out. Forever: the `EntityManager` is unreachable, but Hikari counts the connection as active. Ten failures exhaust a pod's pool, and only a restart recovers it. A risk-service incident becomes an order-service outage that *outlives* the risk incident.

**Evidence.** P5: `risk-service outage: request FAILED; pool connections still checked out = 4 of 4; next unrelated query TIMED OUT`. Fix: `rendered 20 rows (20 risk unknown); … 0 of 4; next unrelated query ok`.

```comment-l7
issue (blocking): an exception from risk-service leaks the EntityManager and its connection

Lines 57-63 open the EntityManager and begin a transaction outside try-with-resources, so when `risk.isRisky` throws, close() never runs and the connection stays checked out until the pod restarts. In the P5 probe one dashboard during a risk outage leaves 4 of 4 connections checked out and the next unrelated query times out. Suggest try-with-resources for every EntityManager, and (with the F3 change) no EntityManager in the task at all; risk failures then degrade to an "unknown" badge.
```

**Fix.** The fixed task holds no `EntityManager`, and every remaining one is in `try-with-resources`:
```java
        try (EntityManager em = emf.createEntityManager()) {
            em.getTransaction().begin();
```

### F5 · L2 · Sev-2 · `synchronized` around a remote refresh pins carriers on JDK 21 (DashboardService 69–74)

**Mechanism.** On JDK 21 a virtual thread blocked inside `synchronized` pins its carrier, and so does one blocked *waiting to enter* the monitor. When the cache expires, the first task holds the monitor through a 200–300 ms pricing call, and every other task reaching `tierDiscount` blocks on monitor entry, pinned. With the default parallelism of one carrier per core, a page-size fan-out pins every carrier, and **all** virtual threads in the JVM (other requests, health checks) stall until the fetch returns. Once a minute, by design. (On JDK 24+, JEP 491 removes this pinning. The lock still serializes callers behind a remote call.)

**Evidence.** P6 (2 carriers): `unrelated virtual thread started during the tier refresh waited N ms to run` (≈ the pricing latency; fix: 0 ms). One measured run.

```comment-l7
issue (blocking): tierDiscount() makes a remote call inside synchronized, which pins carrier threads on JDK 21

We run 21, where a virtual thread blocked in a synchronized method, or waiting to enter it, cannot unmount, which means that when the cache expires the fan-out tasks pile up on the monitor while one of them waits on pricing-service, and with every carrier pinned, unrelated virtual threads (other requests, /healthz) stop running. The P6 probe shows an unrelated virtual thread waiting ~the full pricing latency. Suggest refreshing tiers off the request path (scheduled, swapping a volatile immutable map); if a lock is ever needed around I/O on 21, use ReentrantLock, as JEP 444 recommends.
```

**Fix.**
```java
    private volatile Map<String, Integer> tierDiscounts; // swapped whole by refreshTiers(); read without a lock
```
```java
    public void refreshTiers() {
        tierDiscounts = Map.copyOf(pricing.fetchTierDiscounts());
    }
```

### F6 · L7 · Sev-3 · `ThreadLocal` "reuse" under one-virtual-thread-per-task (DashboardService 18, 66)

**Mechanism.** With platform threads, a `ThreadLocal<NumberFormat>` amortized creation over thousands of requests per thread. With one virtual thread per task, every task is a new thread, so every call creates a formatter and drops it: 100% miss rate and pure allocation churn. JEP 444: "do not use thread locals to pool costly resources among multiple tasks." The `double` formatting of money (`discounted / 100.0`) is a further nit.

**Evidence.** P7: `5 dashboards x 20 orders: NumberFormat instances created = 100` (fix: 0).

```comment-l7
issue (non-blocking): the ThreadLocal formatter is created once per virtual thread, which is once per task

With one virtual thread per order, `USD.get()` never hits; the P7 probe counts 100 NumberFormat instances for 5 dashboards. Suggest formatting minor units directly (`BigDecimal.valueOf(minor, 2)`), which is cheap, thread-safe and avoids the double rounding in line 66.
```

**Fix.**
```java
        return new OrderSummary(r.id(), r.customer(), r.lineCount(), "$" + BigDecimal.valueOf(discounted, 2), risky);
```

### F7 · L7 · Sev-2 · The repair job loads the whole table into one persistence context and one transaction (RecalculateTotalsJob 15–24)

**Mechanism.** `select o from Order o` with no bound loads all 180 M orders, lazily loads each order's lines (N+1 again), keeps every entity managed until commit, and lets dirty checking compare every one of them at flush. That is memory proportional to the table, a transaction measured in hours, and lock and bloat pressure on the hottest table. At scale it OOMs. Before it OOMs, it holds a transaction open long enough to stall autovacuum on `orders`.

**Evidence.** P8: `recalculation over 2,000 orders: … SQL statements = 4,001, entities loaded = 8,000` (fix: 3 statements, 0 entities, same totals).

```comment-l7
issue (blocking): RecalculateTotalsJob loads every order and line into one persistence context inside one transaction

Line 18 has no bound and line 20 lazy-loads each order's lines, so the P8 probe needs 4,001 statements and 8,000 managed entities for 2,000 orders; at 180 M rows this means an OOM or an hours-long transaction on our hottest table. Suggest doing it in SQL (`UPDATE orders SET total_minor = (SELECT sum(...)) WHERE id > ? AND id <= ?`) in keyset batches, one short transaction per batch, so memory is constant and progress is resumable.
```

**Fix.**
```java
                updated += em.createNativeQuery("""
                        update orders o set total_minor = coalesce(
                            (select sum(l.qty * l.unit_price_minor) from order_lines l where l.order_id = o.id), 0)
                        where o.id > ?1 and o.id <= ?2""").setParameter(1, lastId).setParameter(2, hi).executeUpdate();
```

### D1 · The decoy · `join fetch` + `setMaxResults` (DashboardService 36–39): *not a bug on Hibernate 7.4*

**What reviewers expect.** On Hibernate 5.x and 6.x, combining a collection `join fetch` with `setMaxResults` triggered warning HHH90003004 and paginated **in memory**: every matching row was fetched, and the page was cut in Java. For a merchant with 2 M orders that is a classic Sev-1.

**What actually happens here (measured).** Hibernate ORM 7.4.13 wraps the paginated parent query in a derived table and joins the collection to it, so the page is applied in SQL. The statement captured by the probe's `StatementInspector`, with column lists elided:

```sql
select o1_0.id, ..., l1_0.id, ... from (
    select o1_0.id, ... from orders o1_0
    where o1_0.merchant_id=? and exists(select 1 from order_lines l1_0 where o1_0.id=l1_0.order_id)
    order by o1_0.created_at desc offset ? rows fetch first ? rows only
) o1_0(...) join order_lines l1_0 on o1_0.id=l1_0.order_id order by o1_0.created_at desc
```

P2 confirms it: a 20-row page over 2,000 orders loads **100 entities** (20 orders, 60 lines, 20 customers), not 8,000, with `page applied in SQL = true`. ⚠ The exact Hibernate release that introduced the rewrite was not verified here. The claim is about the version this service runs.

**What an L7 says instead.** Something like *"On Hibernate 6 this would paginate in memory. We're on 7.4, and the SQL shows the limit applied in a derived table, so it's fine. Note the `exists(...)`: the inner `join fetch` excludes orders with no lines, which is OK only if checkout guarantees ≥ 1 line."* That earns precision credit. A confident "this paginates in memory, blocking" costs it. The fix replaces the query anyway, for F1.

```comment-l7
question: is excluding orders with zero lines intended here?

On Hibernate 7.4 this join fetch + setMaxResults paginates in SQL (I checked the generated statement: the limit is applied in a derived table, unlike Hibernate 6's in-memory pagination), so no concern there. The inner join does add `exists(select 1 from order_lines ...)`, which means an order without lines never appears on the dashboard; fine if checkout guarantees at least one line, otherwise a left join would be needed.
```

### T1 · Tests

The author's 4 tests pass on both versions; none encodes a defect. They also cannot see any of them: one line per order (F2), 0 ms risk latency (F3, F5), no failures injected (F4), 3 orders (F1, F7). The fixed suite adds `ordersKeepEveryLine`, `listIsOneQueryPlusOneUpdate`, `riskOutageRendersUnknownAndHoldsNoConnection` and `recalculationRestoresTotalsWithoutLoadingEntities`, each a regression guard for one defect.

---

## 7. The refactored code

```java
// ===== order-service/src/main/java/com/acme/orders/DashboardService.java =====
package com.acme.orders;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

/** Merchant dashboard: newest orders with customer, line count, discounted total and risk badge. */
public final class DashboardService {
    private static final int MAX_CONCURRENT_RISK_CALLS = 16; // per pod, whatever the request rate
    private static final long RISK_WAIT_MILLIS = 250; // badge budget: past it, show "unknown" rather than wait

    private final EntityManagerFactory emf;
    private final RiskClient risk;
    private final PricingClient pricing;
    private final Semaphore riskPermits = new Semaphore(MAX_CONCURRENT_RISK_CALLS);
    private volatile Map<String, Integer> tierDiscounts; // swapped whole by refreshTiers(); read without a lock

    public DashboardService(EntityManagerFactory emf, RiskClient risk, PricingClient pricing) {
        this.emf = emf;
        this.risk = risk;
        this.pricing = pricing;
        refreshTiers(); // then once a minute from the application scheduler, never on the request path
    }

    public void refreshTiers() {
        tierDiscounts = Map.copyOf(pricing.fetchTierDiscounts());
    }

    public List<OrderSummary> recentOrders(long merchantId, int limit) throws InterruptedException {
        List<OrderRow> rows;
        try (EntityManager em = emf.createEntityManager()) { // one query: paginated in SQL, customer joined, lines counted
            rows = em.createQuery("""
                    select new com.acme.orders.OrderRow(o.id, c.name, c.tier, size(o.lines), o.totalMinor)
                    from Order o join o.customer c
                    where o.merchantId = :merchant order by o.createdAt desc, o.id desc""", OrderRow.class)
                    .setParameter("merchant", merchantId)
                    .setMaxResults(limit)
                    .getResultList();
        }
        List<Future<OrderSummary>> futures = new ArrayList<>();
        try (ExecutorService perOrder = Executors.newVirtualThreadPerTaskExecutor()) { // no DB work inside tasks
            for (OrderRow r : rows) {
                futures.add(perOrder.submit(() -> summarize(r)));
            }
        } // close() waits for every task
        markRiskChecked(rows);
        return futures.stream().map(Future::resultNow).toList();
    }

    private OrderSummary summarize(OrderRow r) throws InterruptedException {
        Boolean risky = null; // "unknown" unless risk-service answers in budget; the dashboard always renders
        if (riskPermits.tryAcquire(RISK_WAIT_MILLIS, TimeUnit.MILLISECONDS)) { // bulkhead on the remote call
            try {
                risky = risk.isRisky(r.id());
            } catch (RuntimeException e) {
                risky = null;
            } finally {
                riskPermits.release();
            }
        }
        long discounted = r.totalMinor() * (10_000 - tierDiscounts.getOrDefault(r.tier(), 0)) / 10_000;
        return new OrderSummary(r.id(), r.customer(), r.lineCount(), "$" + BigDecimal.valueOf(discounted, 2), risky);
    }

    private void markRiskChecked(List<OrderRow> rows) { // one short transaction, one statement
        if (rows.isEmpty()) {
            return;
        }
        try (EntityManager em = emf.createEntityManager()) {
            em.getTransaction().begin();
            em.createQuery("update Order o set o.riskCheckedAt = :now where o.id in :ids")
                    .setParameter("now", Instant.now())
                    .setParameter("ids", rows.stream().map(OrderRow::id).toList())
                    .executeUpdate();
            em.getTransaction().commit();
        }
    }
}

// ===== order-service/src/main/java/com/acme/orders/Order.java =====
package com.acme.orders;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.HashSet;
import java.util.Set;

@Entity
@Table(name = "orders")
public class Order {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "customer_id")
    private Customer customer;

    @Column(name = "merchant_id")
    private long merchantId;

    @Column(name = "created_at")
    private Instant createdAt;

    @Column(name = "total_minor")
    private long totalMinor;

    @Column(name = "risk_checked_at")
    private Instant riskCheckedAt;

    // Set, not List: the dashboard join-fetches lines, and a List (bag) yields one parent row per line
    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    private Set<OrderLine> lines = new HashSet<>();

    protected Order() {
    }

    public Order(Customer customer, long merchantId, Instant createdAt) {
        this.customer = customer;
        this.merchantId = merchantId;
        this.createdAt = createdAt;
    }

    public void addLine(OrderLine line) {
        lines.add(line);
        line.setOrder(this);
    }

    public Long getId() {
        return id;
    }

    public Customer getCustomer() {
        return customer;
    }

    public Set<OrderLine> getLines() {
        return lines;
    }

    public long getTotalMinor() {
        return totalMinor;
    }

    public void setTotalMinor(long totalMinor) {
        this.totalMinor = totalMinor;
    }
}

// ===== order-service/src/main/java/com/acme/orders/OrderLine.java =====
package com.acme.orders;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "order_lines")
public class OrderLine {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "order_id")
    private Order order;

    private String sku;
    private int qty;

    @Column(name = "unit_price_minor")
    private long unitPriceMinor;

    protected OrderLine() {
    }

    public OrderLine(String sku, int qty, long unitPriceMinor) {
        this.sku = sku;
        this.qty = qty;
        this.unitPriceMinor = unitPriceMinor;
    }

    void setOrder(Order order) {
        this.order = order;
    }

    public int getQty() {
        return qty;
    }

    public long getUnitPriceMinor() {
        return unitPriceMinor;
    }

    @Override
    public boolean equals(Object o) { // identity is the database id: two unsaved lines are never equal
        return o instanceof OrderLine other && id != null && id.equals(other.id);
    }

    @Override
    public int hashCode() { // constant, so it stays valid when persist() assigns the id
        return OrderLine.class.hashCode();
    }
}

// ===== order-service/src/main/java/com/acme/orders/OrderRow.java =====
package com.acme.orders;

/** Read model for the dashboard query: no entities, no lazy associations. */
public record OrderRow(Long id, String customer, String tier, Integer lineCount, Long totalMinor) {}

// ===== order-service/src/main/java/com/acme/orders/OrderSummary.java =====
package com.acme.orders;

/** {@code risky} is null when risk-service could not answer. */
public record OrderSummary(long orderId, String customer, int lineCount, String total, Boolean risky) {}

// ===== order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java =====
package com.acme.orders;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

/** Nightly: recompute order totals from their lines, in SQL, in keyset batches with one short transaction each. */
public class RecalculateTotalsJob {
    private static final int BATCH = 10_000;

    private final EntityManagerFactory emf;

    public RecalculateTotalsJob(EntityManagerFactory emf) {
        this.emf = emf;
    }

    public int run() {
        long lastId = 0;
        int updated = 0;
        while (true) {
            try (EntityManager em = emf.createEntityManager()) {
                em.getTransaction().begin();
                Object upTo = em.createNativeQuery(
                        "select max(id) from (select id from orders where id > ?1 order by id limit ?2) batch")
                        .setParameter(1, lastId).setParameter(2, BATCH).getSingleResult();
                if (upTo == null) {
                    em.getTransaction().commit();
                    return updated;
                }
                long hi = ((Number) upTo).longValue();
                updated += em.createNativeQuery("""
                        update orders o set total_minor = coalesce(
                            (select sum(l.qty * l.unit_price_minor) from order_lines l where l.order_id = o.id), 0)
                        where o.id > ?1 and o.id <= ?2""").setParameter(1, lastId).setParameter(2, hi).executeUpdate();
                em.getTransaction().commit();
                lastId = hi;
            }
        }
    }
}
```

**Fixed suite: 7/7 (output, verified, JDK 21).**

```text
├─ JUnit Jupiter ✔
│  └─ DashboardServiceTest ✔
│     ├─ ordersKeepEveryLine() ✔
│     ├─ riskOutageRendersUnknownAndHoldsNoConnection() ✔
│     ├─ showsCustomerLinesAndDiscountedTotal() ✔
│     ├─ listIsOneQueryPlusOneUpdate() ✔
│     ├─ flagsRiskyOrders() ✔
│     ├─ recalculationRestoresTotalsWithoutLoadingEntities() ✔
│     └─ newestFirstAndLimited() ✔
[         7 tests found           ]
[         7 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fix (output, verified).** All four pass; none of them encoded a defect, and none could see one:

```text
├─ JUnit Jupiter ✔
│  └─ DashboardServiceTest ✔
│     ├─ recalculationRestoresTotals() ✔
│     ├─ showsCustomerLinesAndDiscountedTotal() ✔
│     ├─ flagsRiskyOrders() ✔
│     └─ newestFirstAndLimited() ✔
[         4 tests found           ]
[         4 tests successful      ]
[         0 tests failed          ]
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Read path | Entities + lazy proxies + N+1 | One DTO projection: paginated in SQL, customer joined, lines counted |
| Fan-out tasks | Transaction + remote call + `synchronized` refresh + `ThreadLocal` | Remote call only, behind a 16-permit semaphore with a 250 ms acquire budget |
| Writes from the read path | One `UPDATE` per task, each in its own transaction | One batched `UPDATE … WHERE id IN (…)` |
| Failure of risk-service | Request fails, connection leaks | Badge renders "unknown", nothing held |
| Tier cache | `synchronized` lazy refresh on the request path | `volatile` immutable map, refreshed by a scheduler |
| Entity identity | Id-based `equals`, id-hash `hashCode` | Non-null-id equality, constant `hashCode` |
| Repair job | Whole table in one persistence context and transaction | Set-based SQL in keyset batches |

---

## 8. Probe evidence

**Against the PR's code (output, verified; P4 and P6 are one measured run):**

```text
PR02 probes against the PR's order service (Hibernate 7, PostgreSQL 18, JDK 21, 2 carrier threads)
P1 F2 checkout with 2 lines: order_lines rows = 1, total_minor = 7,000 (lines sum to 1,000)
P2 D1 (decoy) dashboard page of 20 from 2,000 orders: rendered 20 rows (0 risk unknown); entities loaded = 100; page applied in SQL = true
P3 F1 same request: SQL statements = 41
P4 F3 8 concurrent dashboards x 20 orders, pool 10, risk 250 ms: 6 of 8 requests failed (one measured run)
P5 F4 risk-service outage: request FAILED; pool connections still checked out = 4 of 4; next unrelated query TIMED OUT
P6 F5 unrelated virtual thread started during the tier refresh waited 283 ms to run (one measured run)
P7 F6 5 dashboards x 20 orders: NumberFormat instances created = 100
P8 F7 recalculation over 2,000 orders: updated 2,000, SQL statements = 4,001, entities loaded = 8,000, totals now 5,000,000
```

**Against the fixed code (output, verified; P4 and P6 are one measured run):**

```text
PR02 probes against the fixed order service (Hibernate 7, PostgreSQL 18, JDK 21, 2 carrier threads)
P1 F2 checkout with 2 lines: order_lines rows = 2, total_minor = 7,000 (lines sum to 7,000)
P2 D1 (decoy) dashboard page of 20 from 2,000 orders: rendered 20 rows (0 risk unknown); entities loaded = 0; page applied in SQL = true
P3 F1 same request: SQL statements = 2
P4 F3 8 concurrent dashboards x 20 orders, pool 10, risk 250 ms: 0 of 8 requests failed (one measured run)
P5 F4 risk-service outage: rendered 20 rows (20 risk unknown); pool connections still checked out = 0 of 4; next unrelated query ok
P6 F5 unrelated virtual thread started during the tier refresh waited 0 ms to run (one measured run)
P7 F6 5 dashboards x 20 orders: NumberFormat instances created = 0
P8 F7 recalculation over 2,000 orders: updated 2,000, SQL statements = 3, entities loaded = 0, totals now 5,000,000
```

<details><summary><b>The probe harness (Pr02Probes.java)</b></summary>

```java
package com.acme.orders;

import com.zaxxer.hikari.HikariDataSource;
import jakarta.persistence.EntityManagerFactory;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import org.hibernate.stat.Statistics;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Pr02Probes - production-shaped probes for PR02 on Hibernate 7 + PostgreSQL 18, run on JDK 21 with 2 carrier
 * threads (-Djdk.virtualThreadScheduler.parallelism=2) so carrier pinning is visible. Prints outcomes only.
 */
public final class Pr02Probes {
    private static String n(long v) {
        return String.format(Locale.ROOT, "%,d", v);
    }

    private record World(HikariDataSource ds, EntityManagerFactory emf, FakeRisk risk, FakePricing pricing,
                         DashboardService dashboard) implements AutoCloseable {
        static World of(int poolSize, long connTimeoutMillis, long riskLatency, long pricingLatency) {
            HikariDataSource ds = Db.pool(poolSize, connTimeoutMillis);
            EntityManagerFactory emf = Db.emf(ds);
            FakeRisk risk = new FakeRisk(riskLatency, Set.of());
            FakePricing pricing = new FakePricing(pricingLatency);
            return new World(ds, emf, risk, pricing, new DashboardService(emf, risk, pricing));
        }

        String render(long merchant, int limit) {
            try {
                List<OrderSummary> rows = dashboard.recentOrders(merchant, limit);
                long unknown = rows.stream().filter(r -> String.valueOf(r.risky()).equals("null")).count();
                return "rendered " + rows.size() + " rows (" + unknown + " risk unknown)";
            } catch (Exception e) {
                return "request FAILED";
            }
        }

        @Override
        public void close() {
            emf.close();
            ds.close();
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("PR02 probes against the " + args[0] + " order service (Hibernate 7, PostgreSQL 18, JDK "
                + Runtime.version().feature() + ", 2 carrier threads)");
        lostLines();
        dashboardQueries();
        poolUnderRiskLatency();
        riskOutageLeak();
        carrierPinning();
        formatterChurn();
        recalcJob();
    }

    static void lostLines() {
        try (World w = World.of(4, 5_000, 0, 0)) {
            new JdbcTemplate(w.ds).update("INSERT INTO customers (name, tier) VALUES ('Ann', 'GOLD')");
            long id = new OrderService(w.emf).create(1, 7, Instant.now(), List.of(
                    new OrderService.LineInput("SKU-A", 1, 1_000), new OrderService.LineInput("SKU-B", 3, 2_000)));
            System.out.println("P1 F2 checkout with 2 lines: order_lines rows = "
                    + Db.count(w.ds, "SELECT count(*) FROM order_lines WHERE order_id = " + id) + ", total_minor = "
                    + n(Db.count(w.ds, "SELECT total_minor FROM orders WHERE id = " + id)) + " (lines sum to "
                    + n(Db.count(w.ds, "SELECT coalesce(sum(qty * unit_price_minor), 0) FROM order_lines WHERE order_id = " + id)) + ")");
        }
    }

    static void dashboardQueries() {
        try (World w = World.of(10, 5_000, 0, 0)) {
            Db.seedMerchant(w.ds, 7, 2_000);
            Statistics stats = Db.stats(w.emf);
            stats.clear();
            SqlLog.STATEMENTS.clear();
            String r = w.render(7, 20);
            String first = SqlLog.STATEMENTS.get(0);
            System.out.println("P2 D1 (decoy) dashboard page of 20 from 2,000 orders: " + r + "; entities loaded = "
                    + n(stats.getEntityLoadCount()) + "; page applied in SQL = " + first.contains("fetch first ? rows only"));
            System.out.println("P3 F1 same request: SQL statements = " + n(stats.getPrepareStatementCount()));
        }
    }

    static void poolUnderRiskLatency() throws Exception {
        try (World w = World.of(10, 1_000, 250, 0)) {
            Db.seedMerchant(w.ds, 7, 200);
            List<Callable<String>> calls = new ArrayList<>();
            for (int i = 0; i < 8; i++) {
                calls.add(() -> w.render(7, 20));
            }
            long failed = race(calls).stream().filter(s -> s.contains("FAILED")).count();
            System.out.println("P4 F3 8 concurrent dashboards x 20 orders, pool 10, risk 250 ms: " + failed
                    + " of 8 requests failed (one measured run)");
        }
    }

    static void riskOutageLeak() {
        try (World w = World.of(4, 1_000, 0, 0)) {
            Db.seedMerchant(w.ds, 7, 50);
            w.risk.down = true;
            String r = w.render(7, 20);
            int active = w.ds.getHikariPoolMXBean().getActiveConnections();
            String next;
            try {
                Db.count(w.ds, "SELECT 1");
                next = "ok";
            } catch (RuntimeException e) {
                next = "TIMED OUT";
            }
            System.out.println("P5 F4 risk-service outage: " + r + "; pool connections still checked out = " + active
                    + " of 4; next unrelated query " + next);
        }
    }

    static void carrierPinning() throws Exception {
        try (World w = World.of(10, 5_000, 0, 300)) {
            Db.seedMerchant(w.ds, 7, 50);
            Thread request = Thread.ofPlatform().start(() -> w.render(7, 20));
            w.pricing.fetchStarted.await(2, TimeUnit.SECONDS);
            Thread.sleep(20);
            AtomicLong ranAt = new AtomicLong();
            long t0 = System.nanoTime();
            Thread health = Thread.ofVirtual().start(() -> ranAt.set(System.nanoTime())); // e.g. /healthz
            health.join();
            request.join();
            long waited = TimeUnit.NANOSECONDS.toMillis(ranAt.get() - t0);
            System.out.println("P6 F5 unrelated virtual thread started during the tier refresh waited " + waited
                    + " ms to run (one measured run)");
        }
    }

    static void formatterChurn() {
        try (World w = World.of(10, 5_000, 0, 0)) {
            Db.seedMerchant(w.ds, 7, 50);
            w.render(7, 20); // warm-up
            long before = Formats.created();
            for (int i = 0; i < 5; i++) {
                w.render(7, 20);
            }
            System.out.println("P7 F6 5 dashboards x 20 orders: NumberFormat instances created = " + (Formats.created() - before));
        }
    }

    static void recalcJob() {
        try (World w = World.of(4, 5_000, 0, 0)) {
            Db.seedMerchant(w.ds, 7, 2_000);
            new JdbcTemplate(w.ds).update("UPDATE orders SET total_minor = 0");
            Statistics stats = Db.stats(w.emf);
            stats.clear();
            int updated = new RecalculateTotalsJob(w.emf).run();
            System.out.println("P8 F7 recalculation over 2,000 orders: updated " + n(updated) + ", SQL statements = "
                    + n(stats.getPrepareStatementCount()) + ", entities loaded = " + n(stats.getEntityLoadCount())
                    + ", totals now " + n(Db.count(w.ds, "SELECT sum(total_minor) FROM orders")));
        }
    }

    private static List<String> race(List<Callable<String>> calls) throws Exception {
        CyclicBarrier start = new CyclicBarrier(calls.size());
        ExecutorService pool = Executors.newFixedThreadPool(calls.size());
        List<Future<String>> fs = new ArrayList<>();
        for (Callable<String> c : calls) {
            fs.add(pool.submit(() -> {
                start.await();
                return c.call();
            }));
        }
        List<String> out = new ArrayList<>();
        for (Future<String> f : fs) {
            out.add(f.get());
        }
        pool.shutdown();
        return out;
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/order-service/src/main/java/com/acme/orders/DashboardService.java b/order-service/src/main/java/com/acme/orders/DashboardService.java
index f47041c..d9e350e 100644
--- a/order-service/src/main/java/com/acme/orders/DashboardService.java
+++ b/order-service/src/main/java/com/acme/orders/DashboardService.java
@@ -2,75 +2,86 @@ package com.acme.orders;
 
 import jakarta.persistence.EntityManager;
 import jakarta.persistence.EntityManagerFactory;
-import java.text.NumberFormat;
+import java.math.BigDecimal;
 import java.time.Instant;
 import java.util.ArrayList;
 import java.util.List;
 import java.util.Map;
-import java.util.concurrent.ExecutionException;
 import java.util.concurrent.ExecutorService;
 import java.util.concurrent.Executors;
 import java.util.concurrent.Future;
+import java.util.concurrent.Semaphore;
 import java.util.concurrent.TimeUnit;
 
 /** Merchant dashboard: newest orders with customer, line count, discounted total and risk badge. */
-public class DashboardService {
-    private static final ThreadLocal<NumberFormat> USD = ThreadLocal.withInitial(Formats::usd); // reuse per thread
+public final class DashboardService {
+    private static final int MAX_CONCURRENT_RISK_CALLS = 16; // per pod, whatever the request rate
+    private static final long RISK_WAIT_MILLIS = 250; // badge budget: past it, show "unknown" rather than wait
 
     private final EntityManagerFactory emf;
     private final RiskClient risk;
     private final PricingClient pricing;
-    private Map<String, Integer> tierDiscounts;
-    private long tiersExpireAt;
+    private final Semaphore riskPermits = new Semaphore(MAX_CONCURRENT_RISK_CALLS);
+    private volatile Map<String, Integer> tierDiscounts; // swapped whole by refreshTiers(); read without a lock
 
     public DashboardService(EntityManagerFactory emf, RiskClient risk, PricingClient pricing) {
         this.emf = emf;
         this.risk = risk;
         this.pricing = pricing;
+        refreshTiers(); // then once a minute from the application scheduler, never on the request path
     }
 
-    public List<OrderSummary> recentOrders(long merchantId, int limit) throws InterruptedException, ExecutionException {
-        List<Order> orders;
-        try (EntityManager em = emf.createEntityManager()) {
-            orders = em.createQuery("""
-                    select o from Order o join fetch o.lines
-                    where o.merchantId = :merchant order by o.createdAt desc""", Order.class) // lines too: no N+1
+    public void refreshTiers() {
+        tierDiscounts = Map.copyOf(pricing.fetchTierDiscounts());
+    }
+
+    public List<OrderSummary> recentOrders(long merchantId, int limit) throws InterruptedException {
+        List<OrderRow> rows;
+        try (EntityManager em = emf.createEntityManager()) { // one query: paginated in SQL, customer joined, lines counted
+            rows = em.createQuery("""
+                    select new com.acme.orders.OrderRow(o.id, c.name, c.tier, size(o.lines), o.totalMinor)
+                    from Order o join o.customer c
+                    where o.merchantId = :merchant order by o.createdAt desc, o.id desc""", OrderRow.class)
                     .setParameter("merchant", merchantId)
                     .setMaxResults(limit)
                     .getResultList();
-            orders.forEach(o -> o.getCustomer().getName()); // initialize while the session is open
         }
-        try (ExecutorService perOrder = Executors.newVirtualThreadPerTaskExecutor()) { // cheap: one per order
-            List<Future<OrderSummary>> futures = new ArrayList<>();
-            for (Order o : orders) {
-                futures.add(perOrder.submit(() -> summarize(o)));
+        List<Future<OrderSummary>> futures = new ArrayList<>();
+        try (ExecutorService perOrder = Executors.newVirtualThreadPerTaskExecutor()) { // no DB work inside tasks
+            for (OrderRow r : rows) {
+                futures.add(perOrder.submit(() -> summarize(r)));
             }
-            List<OrderSummary> result = new ArrayList<>();
-            for (Future<OrderSummary> f : futures) {
-                result.add(f.get());
-            }
-            return result;
-        }
+        } // close() waits for every task
+        markRiskChecked(rows);
+        return futures.stream().map(Future::resultNow).toList();
     }
 
-    private OrderSummary summarize(Order o) {
-        EntityManager em = emf.createEntityManager();
-        em.getTransaction().begin();
-        boolean risky = risk.isRisky(o.getId());
-        em.createQuery("update Order o set o.riskCheckedAt = :now where o.id = :id")
-                .setParameter("now", Instant.now()).setParameter("id", o.getId()).executeUpdate();
-        em.getTransaction().commit();
-        em.close();
-        long discounted = o.getTotalMinor() * (10_000 - tierDiscount(o.getCustomer().getTier())) / 10_000;
-        return new OrderSummary(o.getId(), o.getCustomer().getName(), o.getLines().size(),
-                USD.get().format(discounted / 100.0), risky);
+    private OrderSummary summarize(OrderRow r) throws InterruptedException {
+        Boolean risky = null; // "unknown" unless risk-service answers in budget; the dashboard always renders
+        if (riskPermits.tryAcquire(RISK_WAIT_MILLIS, TimeUnit.MILLISECONDS)) { // bulkhead on the remote call
+            try {
+                risky = risk.isRisky(r.id());
+            } catch (RuntimeException e) {
+                risky = null;
+            } finally {
+                riskPermits.release();
+            }
+        }
+        long discounted = r.totalMinor() * (10_000 - tierDiscounts.getOrDefault(r.tier(), 0)) / 10_000;
+        return new OrderSummary(r.id(), r.customer(), r.lineCount(), "$" + BigDecimal.valueOf(discounted, 2), risky);
     }
 
-    private synchronized int tierDiscount(String tier) { // refresh at most once a minute
-        if (tierDiscounts == null || System.nanoTime() - tiersExpireAt > 0) {
-            tierDiscounts = pricing.fetchTierDiscounts();
-            tiersExpireAt = System.nanoTime() + TimeUnit.MINUTES.toNanos(1);
+    private void markRiskChecked(List<OrderRow> rows) { // one short transaction, one statement
+        if (rows.isEmpty()) {
+            return;
+        }
+        try (EntityManager em = emf.createEntityManager()) {
+            em.getTransaction().begin();
+            em.createQuery("update Order o set o.riskCheckedAt = :now where o.id in :ids")
+                    .setParameter("now", Instant.now())
+                    .setParameter("ids", rows.stream().map(OrderRow::id).toList())
+                    .executeUpdate();
+            em.getTransaction().commit();
         }
-        return tierDiscounts.getOrDefault(tier, 0);
     }
 }
diff --git a/order-service/src/main/java/com/acme/orders/OrderLine.java b/order-service/src/main/java/com/acme/orders/OrderLine.java
index 25d2b96..663b041 100644
--- a/order-service/src/main/java/com/acme/orders/OrderLine.java
+++ b/order-service/src/main/java/com/acme/orders/OrderLine.java
@@ -9,7 +9,6 @@ import jakarta.persistence.Id;
 import jakarta.persistence.JoinColumn;
 import jakarta.persistence.ManyToOne;
 import jakarta.persistence.Table;
-import java.util.Objects;
 
 @Entity
 @Table(name = "order_lines")
@@ -50,12 +49,12 @@ public class OrderLine {
     }
 
     @Override
-    public boolean equals(Object o) { // required for entities kept in a Set
-        return o instanceof OrderLine other && Objects.equals(id, other.id);
+    public boolean equals(Object o) { // identity is the database id: two unsaved lines are never equal
+        return o instanceof OrderLine other && id != null && id.equals(other.id);
     }
 
     @Override
-    public int hashCode() {
-        return Objects.hashCode(id);
+    public int hashCode() { // constant, so it stays valid when persist() assigns the id
+        return OrderLine.class.hashCode();
     }
 }
diff --git a/order-service/src/main/java/com/acme/orders/OrderRow.java b/order-service/src/main/java/com/acme/orders/OrderRow.java
new file mode 100644
index 0000000..8465571
--- /dev/null
+++ b/order-service/src/main/java/com/acme/orders/OrderRow.java
@@ -0,0 +1,4 @@
+package com.acme.orders;
+
+/** Read model for the dashboard query: no entities, no lazy associations. */
+public record OrderRow(Long id, String customer, String tier, Integer lineCount, Long totalMinor) {}
diff --git a/order-service/src/main/java/com/acme/orders/OrderSummary.java b/order-service/src/main/java/com/acme/orders/OrderSummary.java
index 8dae779..e5bcf32 100644
--- a/order-service/src/main/java/com/acme/orders/OrderSummary.java
+++ b/order-service/src/main/java/com/acme/orders/OrderSummary.java
@@ -1,3 +1,4 @@
 package com.acme.orders;
 
-public record OrderSummary(long orderId, String customer, int lineCount, String total, boolean risky) {}
+/** {@code risky} is null when risk-service could not answer. */
+public record OrderSummary(long orderId, String customer, int lineCount, String total, Boolean risky) {}
diff --git a/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java b/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java
index b37c47e..64c11cc 100644
--- a/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java
+++ b/order-service/src/main/java/com/acme/orders/RecalculateTotalsJob.java
@@ -2,10 +2,11 @@ package com.acme.orders;
 
 import jakarta.persistence.EntityManager;
 import jakarta.persistence.EntityManagerFactory;
-import java.util.List;
 
-/** Nightly: recompute order totals from their lines (repairs drift from the 2025 pricing incident). */
+/** Nightly: recompute order totals from their lines, in SQL, in keyset batches with one short transaction each. */
 public class RecalculateTotalsJob {
+    private static final int BATCH = 10_000;
+
     private final EntityManagerFactory emf;
 
     public RecalculateTotalsJob(EntityManagerFactory emf) {
@@ -13,14 +14,26 @@ public class RecalculateTotalsJob {
     }
 
     public int run() {
-        try (EntityManager em = emf.createEntityManager()) {
-            em.getTransaction().begin();
-            List<Order> orders = em.createQuery("select o from Order o", Order.class).getResultList();
-            for (Order o : orders) {
-                o.setTotalMinor(o.getLines().stream().mapToLong(l -> l.getQty() * l.getUnitPriceMinor()).sum());
+        long lastId = 0;
+        int updated = 0;
+        while (true) {
+            try (EntityManager em = emf.createEntityManager()) {
+                em.getTransaction().begin();
+                Object upTo = em.createNativeQuery(
+                        "select max(id) from (select id from orders where id > ?1 order by id limit ?2) batch")
+                        .setParameter(1, lastId).setParameter(2, BATCH).getSingleResult();
+                if (upTo == null) {
+                    em.getTransaction().commit();
+                    return updated;
+                }
+                long hi = ((Number) upTo).longValue();
+                updated += em.createNativeQuery("""
+                        update orders o set total_minor = coalesce(
+                            (select sum(l.qty * l.unit_price_minor) from order_lines l where l.order_id = o.id), 0)
+                        where o.id > ?1 and o.id <= ?2""").setParameter(1, lastId).setParameter(2, hi).executeUpdate();
+                em.getTransaction().commit();
+                lastId = hi;
             }
-            em.getTransaction().commit(); // dirty checking writes the changed totals
-            return orders.size();
         }
     }
 }
diff --git a/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java b/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java
index c33b2e0..7834e96 100644
--- a/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java
+++ b/order-service/src/test/java/com/acme/orders/DashboardServiceTest.java
@@ -2,6 +2,7 @@ package com.acme.orders;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
 import static org.junit.jupiter.api.Assertions.assertFalse;
+import static org.junit.jupiter.api.Assertions.assertNull;
 import static org.junit.jupiter.api.Assertions.assertTrue;
 
 import com.zaxxer.hikari.HikariDataSource;
@@ -9,6 +10,7 @@ import jakarta.persistence.EntityManagerFactory;
 import java.time.Instant;
 import java.util.List;
 import java.util.Set;
+import org.hibernate.stat.Statistics;
 import org.junit.jupiter.api.BeforeEach;
 import org.junit.jupiter.api.Test;
 import org.springframework.jdbc.core.JdbcTemplate;
@@ -16,7 +18,8 @@ import org.springframework.jdbc.core.JdbcTemplate;
 class DashboardServiceTest {
     private static final HikariDataSource DS = Db.pool(10, 5_000);
     private static final EntityManagerFactory EMF = Db.emf(DS);
-    private final DashboardService dashboard = new DashboardService(EMF, new FakeRisk(0, Set.of(2L)), new FakePricing(0));
+    private final FakeRisk risk = new FakeRisk(0, Set.of(2L));
+    private final DashboardService dashboard = new DashboardService(EMF, risk, new FakePricing(0));
 
     @BeforeEach
     void seed() {
@@ -39,7 +42,7 @@ class DashboardServiceTest {
         OrderSummary newest = dashboard.recentOrders(7, 1).get(0);
         assertEquals("Ann", newest.customer());
         assertEquals(1, newest.lineCount());
-        assertEquals("$18.00", newest.total()); // GOLD: 10 % off 20.00
+        assertEquals("$18.00", newest.total());
     }
 
     @Test
@@ -50,9 +53,34 @@ class DashboardServiceTest {
     }
 
     @Test
-    void recalculationRestoresTotals() {
+    void recalculationRestoresTotalsWithoutLoadingEntities() {
         new JdbcTemplate(DS).update("UPDATE orders SET total_minor = 0");
+        Statistics stats = Db.stats(EMF);
+        stats.clear();
         assertEquals(3, new RecalculateTotalsJob(EMF).run());
         assertEquals(6_000, Db.count(DS, "SELECT sum(total_minor) FROM orders"));
+        assertEquals(0, stats.getEntityLoadCount());
+    }
+
+    @Test
+    void ordersKeepEveryLine() {
+        long id = new OrderService(EMF).create(1, 7, Instant.now(), List.of(
+                new OrderService.LineInput("A", 1, 100), new OrderService.LineInput("B", 1, 200)));
+        assertEquals(2, Db.count(DS, "SELECT count(*) FROM order_lines WHERE order_id = " + id));
+    }
+
+    @Test
+    void listIsOneQueryPlusOneUpdate() throws Exception {
+        Statistics stats = Db.stats(EMF);
+        stats.clear();
+        dashboard.recentOrders(7, 10);
+        assertEquals(2, stats.getPrepareStatementCount());
+    }
+
+    @Test
+    void riskOutageRendersUnknownAndHoldsNoConnection() throws Exception {
+        risk.down = true;
+        assertNull(dashboard.recentOrders(7, 10).get(0).risky());
+        assertEquals(0, DS.getHikariPoolMXBean().getActiveConnections());
     }
 }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F2 | `equals` on a generated id drops checkout lines | Sev-1 (5) | 10 | L6+ (requires following the change outside the diff) |
| F3 | Connection held per fan-out task across HTTP | Sev-1 (5) | 10 | L6+ |
| F4 | `EntityManager` leaked on exception | Sev-1 (5) | 2 | L5+ |
| F5 | `synchronized` + remote call on JDK 21 | Sev-2 (3) | 10 | L6+ (requires knowing the runtime) |
| F7 | Whole-table repair job | Sev-2 (3) | 2 | L5+ |
| F1 | N+1 customers | Sev-2 (3) | 2 | L5+ |
| F6 | `ThreadLocal` under virtual threads | Sev-3 (1) | 10 | L6+ |
| D1 | Decoy: flagging it as a bug | **−3** if asserted confidently | — | — |

Total **25**, and the decoy can cost credit. A strong L6 finds F1, F4, F7, F3 and one of F2/F5 (≈ 19–21) and may flag D1 from memory. An L7 finds F2 by asking "what else adds to this `Set`?", ties F3, F4 and F5 to one rule ("no resource-holding work around remote calls in fan-out tasks"), checks the Hibernate version and the SQL before commenting on D1, and asks which JDK production runs before commenting on `synchronized`.

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| Reviewing only the diff | "OrderLine got equals/hashCode, good practice" | The blast radius is checkout, outside the diff |
| Thread-count thinking | "Virtual threads, so no pool to exhaust" | The connection pool is the pool now |
| Proposing a bigger pool | "Set maximumPoolSize to 100" | 40 pods × 100 = 4,000 > `max_connections=500` |
| Runtime-blind advice | "synchronized is fine since JEP 491" | JEP 491 shipped in JDK 24; production runs 21 |
| Stale ORM knowledge | "join fetch + maxResults paginates in memory" | Not on 7.4; a confident false positive |
| Fixing F4 alone | Add `finally { em.close(); }` | The leak stops, but each task still holds a connection across HTTP (F3) |
| Suggesting `@BatchSize` for F1 | Fewer queries, still entities | Better than N+1, but a projection is 1 query and no persistence context |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "Virtual threads were supposed to fix our throughput. Why is the pool the problem now?"</b></summary>

**Initial Prompt.** Capacity reasoning.

**L5 Answer.** "Virtual threads can block without cost, so it should scale."

**Why L5 Stalls.** Blocking is cheap; the *resources held while blocked* are not. Before, Tomcat's 200 platform threads limited how many requests could hold connections at once. Virtual threads removed that implicit bulkhead.

**L7 Answer.** "Little's law: connections in use = arrival rate × hold time. The PR multiplies both: each dashboard holds 20 connections, each for the risk latency. Virtual threads removed the accidental cap that used to keep that product under the pool size. The fix is to cut the hold time to zero for remote calls (no transaction around them) and to put an explicit bulkhead on the remote call (a semaphore), which JEP 444 recommends instead of pooling virtual threads."

</details>

<details><summary><b>Q2 · "Is `finally { em.close(); }` enough for F4?"</b></summary>

**Initial Prompt.** Partial fix.

**L5 Answer.** "Yes, the connection is always returned."

**Why L5 Stalls.** It fixes the leak but not the hold: every task still owns a connection for the full risk call (F3). Also, `close()` with an active transaction relies on provider behavior to roll back.

**L7 Answer.** "Use try-with-resources everywhere so leaks are structurally impossible, and remove the `EntityManager` from the task entirely, so a remote failure can't hold *or* leak a connection. Then add a pool metric alert: `hikaricp_connections_active` near max with `pending > 0` for more than a minute means something is holding connections. The leak would have paged before it took the pod down."

</details>

<details><summary><b>Q3 · "Why is `Objects.equals(id, other.id)` wrong? Lots of codebases do exactly this."</b></summary>

**Initial Prompt.** Entity identity depth.

**L5 Answer.** "It's fine as long as entities are persisted before being put in sets."

**Why L5 Stalls.** `OrderService.create` puts *new* lines into the set before persist, which is the normal cascade pattern. The precondition "persist first" is false in the codebase's own checkout.

**L7 Answer.** "Two failures. Unsaved entities all compare equal (`null == null`), so the set silently merges them. And the hash changes when `persist` assigns the id, so the element is in the wrong bucket afterwards and `remove`/`contains` fail, which breaks orphan removal. The standard fix is equality only for non-null equal ids, with a constant `hashCode`. Or use a natural key if the domain has one (a line number within the order). Then add the two-line checkout test, because the change's blast radius is outside the diff."

</details>

<details><summary><b>Q4 · "The author says JEP 491 fixed synchronized pinning. Withdraw F5?"</b></summary>

**Initial Prompt.** Runtime awareness.

**L5 Answer.** "Yes, if JEP 491 fixed it then it's fine."

**Why L5 Stalls.** JEP 491 was delivered in JDK 24. The service runs JDK 21. And even on 24+, a lock held across a remote call serializes callers.

**L7 Answer.** "Not on 21. JEP 491 is in 24+, and our base image is Temurin 21.0.12. The probe pins both carriers for the full pricing latency. When we move to 25 the pinning goes away, but every task still queues behind one HTTP call once a minute. The scheduled refresh removes the lock from the request path on any JDK, so it's the fix I'd want regardless."

</details>

<details><summary><b>Q5 · "You didn't flag `join fetch` + `setMaxResults`. Isn't that the in-memory pagination bug?"</b></summary>

**Initial Prompt.** Testing precision (the decoy).

**L5 Answer.** "Yes, you're right, Hibernate paginates in memory with collection fetches. Blocking."

**Why L5 Stalls.** Correct for Hibernate 5/6 and wrong for the 7.4 this service runs. Asserting it confidently is a false positive.

**L7 Answer.** "That was true on Hibernate 6 (warning HHH90003004). I checked the SQL on our 7.4: it paginates the parent query in a derived table with `fetch first ? rows only` and joins the lines to it, and the probe loads 100 entities for a 20-row page. So it's not the bug. The one semantic change worth asking about is the `exists(...)` from the inner join: orders without lines disappear. I'm replacing the query with a projection for the N+1 anyway."

</details>

<details><summary><b>Q6 · "How would you have caught F3 before production?"</b></summary>

**Initial Prompt.** Testing strategy for resource exhaustion.

**L5 Answer.** "Load test it."

**Why L5 Stalls.** Correct but vague. Load tests with a fast fake risk-service won't show it, as the author's tests prove.

**L7 Answer.** "A focused test with a *slow* dependency fake and concurrency greater than pool size / page size, asserting zero acquisition timeouts. That's the P4 probe as a test. In production terms, alert on Hikari `pending` and acquire-time p99. And in review, the rule: any task that runs in a fan-out must not hold a transaction, a lock or a connection across a remote call. That's checkable by eye."

</details>

<details><summary><b>Q7 · "The fixed version shows 'risk unknown' after 250 ms. Isn't that a product regression?"</b></summary>

**Initial Prompt.** Degradation semantics.

**L5 Answer.** "Maybe we should wait longer so all badges render."

**Why L5 Stalls.** Waiting longer reintroduces unbounded latency coupling to risk-service; the dashboard's availability becomes risk-service's availability.

**L7 Answer.** "It's a deliberate degradation: the dashboard is informational, and a badge is advisory. Under normal load all 20 badges render (16 permits, 30 ms p50). Under a risk-service brownout the page still loads in ~300 ms with unknown badges, instead of timing out and taking checkout down with it. I'd confirm the budget with product and expose a metric for the unknown rate."

</details>

<details><summary><b>Q8 · "Why not keep `RecalculateTotalsJob` in JPA and just call `em.clear()` every 1,000 orders?"</b></summary>

**Initial Prompt.** Batch-processing design.

**L5 Answer.** "Yes, flushing and clearing in batches fixes the memory problem."

**Why L5 Stalls.** It fixes memory, but still issues an N+1 for lines, moves every row over the network twice, and keeps one huge transaction unless you also commit per batch.

**L7 Answer.** "Clear-and-flush fixes memory; it doesn't fix 2 × 180 M round trips. The work is a pure set operation, so SQL does it in place: one `UPDATE … FROM (SELECT sum…)` per keyset batch, one short transaction each, resumable from the last id. In the probe that's 3 statements and 0 entities for 2,000 orders versus 4,001 and 8,000. JPA is the right tool for aggregates with behavior, not for bulk recomputation."

</details>

<details><summary><b>Q9 · "Rank the findings for a 30-minute fix window."</b></summary>

**Initial Prompt.** Prioritization.

**L5 Answer.** "N+1 first, it's the most visible performance issue."

**Why L5 Stalls.** N+1 costs latency. F2 corrupts orders silently, and F3/F4 can take down checkout.

**L7 Answer.** "F2 first: every multi-line checkout loses lines *as soon as this deploys*, silently, and it's a two-line fix. Then F4 + F3 together (no DB work in tasks), because together they turn any risk-service blip into a checkout outage. Then F5 (on 21 it stalls the JVM once a minute). F7 can't run in production as written, so keep it disabled until rewritten. F1 and F6 ride along with the projection rewrite."

</details>

---

## 12. Checklist

- [ ] Which JDK does production run? (Pinning advice differs between 21 and 24+.)
- [ ] Every fan-out: what does each task hold (transaction, connection, lock) while it waits on I/O?
- [ ] Every remote call in a fan-out: bounded by a semaphore and a latency budget? What renders on failure?
- [ ] Every `createEntityManager()` / `getConnection()`: in try-with-resources?
- [ ] Every entity `equals`/`hashCode` change: who adds unsaved instances to hash-based collections?
- [ ] Every `ThreadLocal` near virtual threads: is it a cache? (It won't hit.)
- [ ] Every lazy association touched in a loop: count the statements (Hibernate `Statistics`).
- [ ] Every batch job: bounded memory, short transactions, resumable, and set-based where possible.
- [ ] Every "known ORM gotcha": verified on *this* version, with the SQL?

---

## 13. References

- OpenJDK: *JEP 444: Virtual Threads* (pooling, thread locals, pinning). https://openjdk.org/jeps/444
- OpenJDK: *JEP 491: Synchronize Virtual Threads without Pinning* (JDK 24). https://openjdk.org/jeps/491
- Hibernate ORM 7.4 documentation. https://docs.hibernate.org/orm/7.4/
- Jakarta Persistence 3.2: `PersistenceConfiguration`. https://jakarta.ee/specifications/persistence/3.2/apidocs/jakarta.persistence/jakarta/persistence/PersistenceConfiguration.html
- HikariCP wiki: *About Pool Sizing*. https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing
- PostgreSQL documentation: *Routine Vacuuming* (long transactions and dead-tuple cleanup). https://www.postgresql.org/docs/current/routine-vacuuming.html
- Within this KB: [PR01](01-pr01-fintech-wallet-transfer-transactional-proxy-and-deadlock-traps.md) · [01-02 The 7-layer scan](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md) · [01-01 Grading (decoys and precision)](../01-The-L7-Code-Review-Mental-Model-and-Rubric/01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#42-severity-weighted-recall-precision-and-order)
