# 3.5 Spring `@Transactional`: Proxies, Rollback Rules, Propagation, `readOnly`, Isolation, Timeouts, Retries — and the Traps

> **Verified stack:** Spring Framework **7.0.10** (`JpaTransactionManager`, `@EnableTransactionManagement`, `@EnableResilientMethods`), Hibernate ORM **7.4.13**, HikariCP **7.0.2**, PostgreSQL **18.6**. Every behavior below was printed by a running program; `TransactionSynchronizationManager.isActualTransactionActive()` reports whether a transaction really exists.
>
> **Builds on:** [4.3 AOP proxies](../04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md) (how the proxy works), [2.6 isolation](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md) (what isolation levels actually prevent).

---

## 0. First principles: what `@Transactional` actually is 🔥

`@Transactional` is **metadata**. Behavior comes from a **proxy** that Spring puts around your bean:

```text
caller ──► proxy (CGLIB subclass or JDK interface proxy)
             └─ TransactionInterceptor.invoke()
                  1. read @Transactional attributes for the method
                  2. PlatformTransactionManager.getTransaction(definition)
                       → get a Connection / EntityManager, setAutoCommit(false), apply isolation/readOnly/timeout
                       → bind resources to the current THREAD (TransactionSynchronizationManager, ThreadLocals)
                  3. call the real method
                  4. on return → commit (JPA: flush first);  on exception → rollback if the rule says so
             └─ your object's method (this.* calls never pass through the proxy)
```

Two consequences explain almost every trap in this file:

1. **Only calls that go through the proxy are transactional.** Calls on `this`, private methods, and objects you `new` yourself bypass it.
2. **The transaction is bound to the thread.** Code that hops threads (`@Async`, `CompletableFuture.supplyAsync`, a parallel stream, a reactive pipeline) doesn't carry it along.

---

## 1. Proxy traps (verified) 🔥

```java
public String outerWithoutTx() { return "self-invoked inner: " + this.inner(); }
@Transactional public String inner() { return tx(); }

@Transactional String packagePrivate() { return tx(); }
@Transactional private String privateMethod() { return tx(); }
public String callPrivate() { return privateMethod(); }
```

**Output (verified):**

```text
== 1. Self-invocation
  via proxy, inner(): tx ACTIVE (TxLab$AccountService.inner)
  self-invoked inner: NO transaction
== 2. Non-public methods (class-based CGLIB proxy)
  package-private @Transactional called from outside: tx ACTIVE (TxLab$AccountService.packagePrivate)
  private @Transactional (reached via a public method): NO transaction
```

| Situation | Transactional? | Why |
|---|---|---|
| External call to a public `@Transactional` method | ✅ | Goes through the proxy |
| `this.inner()` from another method of the same bean | ❌ | `this` is the target, not the proxy |
| Package-private / protected method on a **class-based** (CGLIB) proxy, called from outside (Spring 6+) | ✅ (verified) | Spring 6 extended interception to non-private methods for class-based proxies |
| `private` method | ❌ | A subclass can't override it |
| `final` method / `final` class | ❌ (method) / proxy creation fails (class) | CGLIB proxies are subclasses |
| JDK interface proxy, annotation only on a method not in the interface | ❌ | The proxy only implements the interface |

Fixes for self-invocation, best first: move the transactional method to **another bean**; use `TransactionTemplate` for programmatic boundaries; inject the bean's own proxy (`@Lazy` self-injection, a smell); AspectJ weaving (no proxies at all).

---

## 2. Rollback rules (verified) 🔥

Default rule (inherited from EJB): **roll back on `RuntimeException` and `Error`; commit on checked exceptions.**

```java
@Transactional
public void withdrawChecked(long id, long amount) throws BusinessException {      // BusinessException extends Exception
    em.find(Account.class, id).balance -= amount;
    throw new BusinessException("insufficient funds (checked)");
}

@Transactional(rollbackFor = BusinessException.class)
public void withdrawCheckedRollbackFor(long id, long amount) throws BusinessException { /* same body */ }
```

**Output (verified, balance starts at 100):**

```text
== 3. Checked exceptions commit by default
  threw: insufficient funds (checked)
  after: balance=70, audit rows=0
  threw: insufficient funds (checked, rollbackFor)
  after: balance=70, audit rows=0
```

The first call **threw and still committed** the −30 (balance 100 → 70). The second rolled back (balance stays 70). Teams either standardize on unchecked business exceptions, or set `rollbackFor = Exception.class` on a meta-annotation:

```java
@Target({ElementType.TYPE, ElementType.METHOD}) @Retention(RetentionPolicy.RUNTIME)
@Transactional(rollbackFor = Exception.class)
public @interface TransactionalService {}
```

---

## 3. Propagation ⚡

| Propagation | Existing transaction | No transaction | Typical use |
|---|---|---|---|
| `REQUIRED` (default) | Join it | Start one | Almost everything |
| `REQUIRES_NEW` | **Suspend** it, start an independent one (a **second connection**) | Start one | Audit logs that must survive rollback; isolated retries |
| `NESTED` | Savepoint inside it | Start one | Partial rollback (JDBC savepoints; with JPA the persistence context isn't rolled back with the savepoint, so use with care) |
| `SUPPORTS` | Join | Run without | Read helpers |
| `MANDATORY` | Join | **Throw** | Enforce "must be called inside a transaction" |
| `NOT_SUPPORTED` | Suspend, run without | Run without | Long non-DB work inside a transactional flow |
| `NEVER` | **Throw** | Run without | Enforce "must not be called inside a transaction" |

### 3.1 `UnexpectedRollbackException`: catching an inner failure doesn't save the outer transaction (verified)

```java
@Transactional                                     // AccountService
public void outerCatchesInnerFailure() {
    em.find(Account.class, 1L).balance += 1;
    try { audit.failInRequired(); } catch (RuntimeException e) { System.out.println("  outer caught: " + e.getMessage()); }
}

@Transactional                                     // AuditService (another bean, so the proxy applies), REQUIRED
public void failInRequired() { throw new IllegalArgumentException("audit failed in REQUIRED tx"); }
```

**Output (verified):**

```text
== 4. Inner REQUIRED failure caught by the outer method
  outer caught: audit failed in REQUIRED tx
  UnexpectedRollbackException: Transaction silently rolled back because it has been marked as rollback-only
  after: balance=70, audit rows=0
```

The inner method **joined** the outer transaction. When its exception crossed the inner proxy, the interceptor marked the *shared* transaction **rollback-only**. The outer method caught the exception and returned normally, so its proxy tried to commit, found the flag, rolled back, and threw `UnexpectedRollbackException`. The `+1` was lost. If the inner work should be allowed to fail independently, it needs **`REQUIRES_NEW`** (its own transaction), or the inner method shouldn't be transactional at all.

### 3.2 `REQUIRES_NEW` survives the outer rollback (verified)

```java
@Transactional
public void outerFailsAfterRequiresNew() {
    em.find(Account.class, 1L).balance += 1000;
    audit.logInNewTx("attempted +1000");                         // REQUIRES_NEW: commits on return
    throw new IllegalStateException("outer fails after audit");
}
```

```text
== 5. REQUIRES_NEW survives the outer rollback
  outer threw: outer fails after audit
  after: balance=70, audit rows=1
```

The +1000 rolled back. The audit row, committed in its own transaction, **stayed**. That's the intended behavior for audit trails, and a correctness bug if someone uses `REQUIRES_NEW` "to be safe" for business data.

### 3.3 `REQUIRES_NEW` can deadlock your connection pool (verified) 🧊

The outer transaction **keeps its connection** while the inner one needs **another**. With a pool of 1:

```text
== REQUIRES_NEW with a pool of 1 connection(s)
  CannotCreateTransactionException after 3038 ms: SQLTransientConnectionException: HikariPool-1 - Connection is not available, request timed out after 3002ms (total=1, active=1, idle=0, waiting=0)
```

With a pool of 10 and 10 concurrent requests that each hold one connection and wait for a second, it's the same **pool deadlock** at scale: every request waits for `connectionTimeout`, then fails. Rules: avoid `REQUIRES_NEW` on hot paths; size pools for the **maximum connections one request can hold** × concurrency; and alert on Hikari's `pending` threads metric.

---

## 4. `readOnly = true` (verified) ⚡

```java
@Transactional(readOnly = true)
public void modifyInReadOnly() { em.find(Account.class, 1L).balance = 999_999; }
```

```text
== 6. Writes inside readOnly = true
  after: balance=70, audit rows=1
```

The modification was **silently not persisted**. With Hibernate, Spring's `HibernateJpaDialect` sets the session's flush mode to `MANUAL` and makes loaded entities read-only (no snapshots kept), so no dirty checking happens. It also calls `Connection.setReadOnly(true)` (which drivers can use) and exposes the flag that read/write routing depends on ([2.7 §1.5](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)).

Use `readOnly = true` on every query-only service method: less memory, no accidental writes, replica routing. Don't rely on it as a security control: native `UPDATE` statements still execute unless the database rejects them (e.g. a read-only transaction mode in the driver, or a replica).

### 4.1 Verified: what PostgreSQL enforces for a read-only JDBC connection 🧊

Spring passes `readOnly` down to `Connection.setReadOnly(true)`. What pgjdbc does with that depends on its `readOnlyMode` (default `transaction`): it starts transactions as **read only**, and does nothing for autocommit statements.

```java
try (Connection c = dataSource.getConnection()) {
    c.setReadOnly(true);
    c.setAutoCommit(false);                                       // what a @Transactional method has
    c.createStatement().executeUpdate("update d_item set name = 'x' where id = 1");
    ...
    c.setAutoCommit(true);                                        // a statement outside any transaction
    c.createStatement().executeUpdate("update d_item set name = 'y' where id = 1");
}
```

**Output (verified, pgjdbc 42.7.14, PostgreSQL 18.6):**

```text
  readOnly + transaction: 25006 ERROR: cannot execute UPDATE in a read-only transaction
  readOnly + autocommit:  UPDATE succeeded, rows=1
```

* Inside a transaction the **database** refused the write (SQLSTATE **25006**), so even a native `UPDATE` in a `@Transactional(readOnly = true)` method fails loudly, as long as the driver keeps the default `readOnlyMode=transaction`.
* With autocommit on, the same read-only connection **wrote**. `readOnlyMode=always` makes pgjdbc mark autocommit sessions read-only too; `readOnlyMode=ignore` disables the protection entirely.
* Spring's `SQLExceptionTranslator` doesn't map 25006 to a specific exception type (it surfaces as an uncategorized SQL exception), so log the SQLSTATE: a 25006 in production usually means a write path accidentally ran under a read-only transaction or was routed to a replica.

---

## 5. Isolation and timeout (verified) ⚡

```java
@Transactional(isolation = Isolation.SERIALIZABLE)
public String isolation() { return (String) em.createNativeQuery("show transaction_isolation").getSingleResult(); }

@Transactional(timeout = 1)
public void slow() { em.createNativeQuery("select pg_sleep(2)").getSingleResult(); }
```

```text
== 7. Isolation and timeout attributes
  isolation=SERIALIZABLE -> server says: serializable
  timeout=1 with pg_sleep(2): PersistenceException after 1070 ms; root PSQLException: ERROR: canceling statement due to user request
```

* `JpaTransactionManager` + `HibernateJpaDialect` apply custom isolation levels on the underlying connection (and reset them afterwards). Isolation is only applied when **starting** a transaction: a `SERIALIZABLE` method that *joins* an existing `READ COMMITTED` transaction runs at `READ COMMITTED` (set `validateExistingTransaction` on the manager to fail fast instead).
* `timeout` becomes a **JDBC query timeout** on each statement (the remaining time). The driver cancels the statement on the server (`canceling statement due to user request`). It doesn't interrupt your Java code between statements, so a transaction that sleeps in Java or calls a slow HTTP API isn't stopped by it.
* `SERIALIZABLE` needs **retries** ([2.6 §2.4](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)), which brings us to §6.

---

## 6. Retries must wrap the transaction, not live inside it (verified) 🧊

A serialization failure (40001), deadlock (40P01) or optimistic-lock conflict (`@Version`) **dooms the current transaction**. Retrying inside it is pointless: the snapshot is stale and the transaction is rollback-only. The retry has to start a **new** transaction.

Spring Framework 7 ships core retry support (`@Retryable`, `@ConcurrencyLimit`, `@EnableResilientMethods`, `RetryTemplate`), so this no longer needs Spring Retry:

```java
@Configuration
@EnableTransactionManagement
@EnableResilientMethods
public class RetryTxLab { /* beans */ }

public static class StockTx {
    @PersistenceContext EntityManager em;

    @Transactional
    public void reserveOnce(long id, CyclicBarrier firstRound) {
        attempts.incrementAndGet();
        Stock s = em.find(Stock.class, id);
        try { firstRound.await(1, TimeUnit.SECONDS); } catch (Exception ignored) { }   // make both threads read version 0
        s.reserved++;
    }                                                                              // flush: UPDATE ... WHERE id=? AND version=?
}

public static class StockFacade {                     // a DIFFERENT bean: its proxy is outside StockTx's proxy
    StockTx tx;
    @Retryable(includes = OptimisticLockingFailureException.class, maxRetries = 3, delay = 20, jitter = 10)
    public void reserve(long id, CyclicBarrier firstRound) { tx.reserveOnce(id, firstRound); }   // each retry = a NEW transaction
}
```

Two threads call `facade.reserve(1L, …)` at the same time (`Stock` has `@Version int version`):

**Output (verified, two runs):**

```text
reserved=2 version=2 transaction attempts=3
reserved=2 version=2 transaction attempts=3
```

Both reads saw version 0. One commit succeeded, the other's `UPDATE … WHERE version = 0` matched 0 rows (`OptimisticLockingFailureException`), the retry ran in a **fresh** transaction, re-read version 1, and succeeded. Three attempts, no lost update.

Rules: the retry boundary is **outside** the transactional proxy (separate bean, or `RetryTemplate` around `TransactionTemplate`); retry only on retryable failures (40001, 40P01, optimistic locking, transient connection errors); cap attempts with jittered backoff; and keep non-idempotent side effects out of the retried block.

**What if both annotations sit on the same method?** Verified in [4.3 §4](../04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md): on Spring Framework 7.0.10, Spring's own `@Retryable` interceptor ends up **outermost** (outside the transaction interceptor and even outside `@Order(1)` aspects), so each attempt printed its own `[tx BEGIN]` … `[tx ROLLBACK]`. That's correct behavior, but it depends on how that particular retry mechanism registers its advice. With other retry libraries the order can differ, so a separate facade bean remains the explicit, portable choice.

---

## 7. Transaction boundaries and side effects 🔥

```java
@Transactional
public void placeOrder(Order o) {
    orders.save(o);
    paymentClient.charge(o);       // ❌ 1: remote call holding a DB connection + locks for its whole duration
    kafka.send("orders", o);       // ❌ 2: published before commit; if the commit fails, consumers saw a phantom order
}
```

| Problem | Consequence | ✅ Instead |
|---|---|---|
| Remote calls inside a transaction | Connections and row locks held for seconds; pool exhaustion; `idle in transaction` sessions blocking VACUUM ([2.5 §2.1](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)) | Call remote services outside the transaction (orchestrate around short transactions) |
| Publishing messages before commit | Phantom events on rollback, or lost events if publishing after commit fails | **Transactional outbox** ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)), or at least `@TransactionalEventListener(phase = AFTER_COMMIT)` for best-effort notifications |
| `@Async` method expecting the caller's transaction | Runs on another thread **without** it | Pass data, not managed entities; start its own transaction |
| Huge transactions (import 1 M rows in one) | Locks, WAL burst, long rollback, replication lag | Chunked transactions with checkpoints (resume from the last chunk) |

---

## 8. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| `@Transactional` on a private helper or called via `this` | Separate bean or `TransactionTemplate` |
| Checked business exceptions assumed to roll back | `rollbackFor = Exception.class` (meta-annotation) or unchecked exceptions |
| Catch an inner `REQUIRED` failure and continue | Let it propagate, or give the inner work `REQUIRES_NEW` if it may fail independently |
| `REQUIRES_NEW` everywhere "for safety" | Only for work that must commit independently; pool sized for it |
| Retry logic *inside* the transactional method (a loop around the failing statement) | Retry around the transaction: an outer bean, or Spring 7 `@Retryable` (verified outermost even on the same method); each attempt is a new transaction |
| Queries without `readOnly = true` | `readOnly = true` on read paths |
| HTTP or Kafka calls inside transactions | Outbox; remote calls outside the boundary |
| `timeout` expected to stop slow Java code | It cancels SQL statements only. Use client timeouts for remote calls |

---

## 9. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-framework](https://github.com/spring-projects/spring-framework) | `spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java` | `invokeWithinTransaction`, `completeTransactionAfterThrowing` (the rollback rule) |
| spring-projects/spring-framework | `spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java` | Propagation handling, `handleExistingTransaction`, `UnexpectedRollbackException` |
| spring-projects/spring-framework | `spring-orm/src/main/java/org/springframework/orm/jpa/vendor/HibernateJpaDialect.java` | What `readOnly` and isolation do to the Hibernate session and connection |
| spring-projects/spring-framework | `spring-tx/src/main/java/org/springframework/transaction/support/TransactionSynchronizationManager.java` | The ThreadLocals that bind a transaction to a thread |
| spring-projects/spring-framework | `spring-context/src/main/java/org/springframework/resilience/annotation/Retryable.java` | Spring 7 core retry |

---

## 10. Interview soundbites

* "`@Transactional` is a proxy around the bean. Self-invocation and private methods bypass it; I verified both printing whether a transaction was active."
* "Checked exceptions commit by default. A method threw and the −30 was still committed."
* "If an inner REQUIRED method fails and the outer catches it, the shared transaction is already rollback-only, so the outer commit throws `UnexpectedRollbackException`."
* "REQUIRES_NEW holds two connections per request. With a pool of 1 it deadlocked the pool until Hikari timed out."
* "Retries go around the transaction, not inside it. Spring 7's core `@Retryable` on an outer bean turned an optimistic-lock conflict into one extra attempt and a correct result."
* "No remote calls inside transactions, and events go through an outbox."
* "With pgjdbc's default `readOnlyMode=transaction`, a write inside a read-only transaction fails with 25006, but the same read-only connection in autocommit mode wrote happily."

---

## Summary

| Trap / rule | Mechanism | Verified evidence |
|---|---|---|
| Self-invocation, private methods | The proxy is bypassed | No active transaction printed |
| Checked exceptions commit | Default rollback rules: unchecked only | −30 committed despite the exception |
| `UnexpectedRollbackException` | Inner REQUIRED failure marks the shared transaction rollback-only | Outer commit threw |
| `REQUIRES_NEW` | A second connection per nesting level | Pool of 1 deadlocked until Hikari's timeout |
| `readOnly = true` | Hibernate flush `MANUAL` + read-only entities + `Connection.setReadOnly` | Silent no-op write; DB rejects writes in-transaction (25006) but not in autocommit |
| Isolation and timeout | Passed to the connection / statement | §5 |
| Retries | Around the transaction (Spring 7 `@Retryable` on an outer bean) | Optimistic-lock conflict → one retry, correct result |
| Side effects | Remote calls and events outside transactions; outbox | §7 |

**Next:** [3.6 Bar-raiser drill-downs →](06-Bar-Raiser-Drill-Downs.md)
