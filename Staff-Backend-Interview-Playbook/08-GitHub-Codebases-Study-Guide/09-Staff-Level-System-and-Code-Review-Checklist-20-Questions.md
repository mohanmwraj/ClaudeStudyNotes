# 8.9 The Staff-Level System and Code Review Checklist: 20 Questions

> **Verified 2026-10-26.** Ten questions for a design review and ten for a code review. Each comes with the failure it prevents, what good looks like, how to verify it, and evidence from this kit or a pinned source line.
>
> The second half is a **worked review**: a deliberately flawed pull request (Spring Boot 4.1.2, Hibernate 7.4.13, HikariCP 7.0.2, PostgreSQL 18.6) with ten defects. Each defect was reproduced, and each fix was measured with the same harness. The lab ran twice with identical results, apart from timings and generated ids. One property-based fix was confirmed in a separate run.
>
> **Pairs with:** [9.5 production-readiness checklists](../09-Staff-Capstone/05-Production-Readiness-Checklists.md) (operations), [9.3 mock loops](../09-Staff-Capstone/03-Mock-Interview-Loops-L5-vs-L6.md) (a flawed design to review), [5.9 patterns catalog](../05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md), [8.7 the source behind the measurements](07-Source-Behind-the-Measurements-JDK-PostgreSQL-Redis-Kubernetes-Kafka.md).

---

## 0. How to use the checklist 🔥

* **Design review (S1–S10):** before code exists. The questions are about boundaries, failure and capacity. Ask them of every design doc; most bad incidents trace back to one of them never being answered.
* **Code review (C11–C20):** on the diff. Each question names a class of bug, not a single bug. Walk them in order; most take a minute.
* **In an interview code-review round:** read the change once for intent, ask what tests exist, then walk C11–C20 out loud. Report findings ranked by blast radius, each with a fix and the test that would have caught it. That last part separates L6 from L5.

| L5 review | L6 review |
|---|---|
| "This method isn't transactional" | "Self-invocation bypasses the proxy. Here's the failing row count, a fix, and an ArchUnit/test rule so it can't come back" |
| "Add a timeout" | "Boot sets no read timeout on this client; `spring.http.clients.read-timeout` sets it for every client. Measured: 3 s hang vs 1 s failure" |
| Finds the bug | Finds the bug, the default that caused it, and the review rule or test that prevents the class |

---

## 1. The 20 questions at a glance

| # | Question | The failure it prevents | Evidence |
|---|---|---|---|
| **S1** | Who owns each piece of data, and which invariants need a single transaction? | Two writers for one fact; distributed transactions by accident | [5.2](../05-Microservices-Patterns/02-Data-Ownership-Database-per-Service.md), [5.10 scenario 10](../05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-10-contention-without-distributed-locks) |
| **S2** | For each dependency: what happens when it's slow, down, or wrong? | Cascading failure, retry storms | [6.6](../06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md) |
| **S3** | What saturates first at peak, and how was it computed? | Pool, partition, quota or thread exhaustion | [2.7](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md), [7.8 §5.3](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| **S4** | What can be delivered twice, late, or out of order, and why is that safe? | Lost or duplicated business events | [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md), [10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| **S5** | How do schemas, APIs and events change without a lockstep deploy? | Broken consumers, failed rollbacks | [5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md), [7.8 §4](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| **S6** | What can't be rolled back, and what's the blast radius of a bad release? | Irreversible migrations and published events | [7.8 §3, §6](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| **S7** | How will we know it's broken before users do? | Silent fallbacks, untested alerts | [7.8 §6](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md), [4.8 §1](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md) |
| **S8** | What happens during a deploy, a scale-down, a node drain, a restart? | 502s, 45-second stalls, hung drains | [7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md), [10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| **S9** | Where are the trust boundaries, secrets, personal data and tenant boundaries? | Leaks across users or tenants | [4.5](../04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md), [3.7 §5](../03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md) |
| **S10** | What's the simplest design that meets the SLO, and who runs it at 3 a.m.? | Accidental complexity, unowned systems | [5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md), [00](../00-How-to-Think-Like-a-Staff-Engineer.md) |
| **C11** | Is every transactional method reached through the proxy, with nothing slow inside? | No transaction at all; connections held across remote calls | §4 R1, R2, R9 |
| **C12** | Does every remote call have a timeout, and does the request have a deadline? | Threads parked for minutes | §4 R3 |
| **C13** | Is anything sent, published or emailed before the commit? | Dual writes | §4 R4 |
| **C14** | How are read-modify-write races handled? | Lost updates, overselling | §4 R5 |
| **C15** | What happens when this request or message arrives twice? | Duplicate orders and charges | §4 R6 |
| **C16** | How many statements does one request issue, and how large can a result get? | N+1, unbounded result sets | §4 R7 |
| **C17** | Is every cache, queue, executor, pool and batch bounded? | Memory growth, latency without back-pressure | §4 R8, R10 |
| **C18** | Which exceptions are caught, and what state do they leave behind? | Silent rollbacks, swallowed failures | §4 R9 |
| **C19** | Which test fails if this breaks under concurrency or a dependency failure? | Happy-path-only test suites | §4 (the harness itself) |
| **C20** | Which library defaults does this code rely on, on the version we run? | Defaults nobody chose | §4 R3, R10; [8.7](07-Source-Behind-the-Measurements-JDK-PostgreSQL-Redis-Kubernetes-Kafka.md) |

---

## 2. Design review questions (S1–S10)

### S1. Who owns each piece of data, and which invariants need a single transaction?

* **Why:** an invariant that spans two owners can only be eventual. Saying so out loud forces either a different boundary or a saga with compensations.
* **Good:** one writer per table; the invariants written next to the boundary ("stock ≥ 0 is enforced by Inventory, in one transaction"); cross-boundary flows named as sagas, with their pivot step identified ([5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)).
* **Red flags:** two services writing one table; "we'll use a distributed lock"; a synchronous call chain that has to succeed end to end.
* **Verify:** for each invariant, name the transaction that enforces it. If you can't, it isn't enforced.

### S2. For each dependency: what happens when it's slow, down, or wrong?

* **Why:** slow is worse than down. Down fails fast; slow holds threads, connections and memory.
* **Good:** a timeout per call below the caller's deadline; one retrying layer with a budget; a breaker tuned to the dependency's recovery; a fallback where the product allows one, and counted ([6.6](../06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md): retries ×3 put 2.72× load on an overloaded dependency; a 10 % budget looked like no retries).
* **Red flags:** "it has a circuit breaker" with no timeout; retries at three layers; fallbacks that hide outages from dashboards.
* **Verify:** a fault-injection test per dependency (latency and errors), with the expected caller behaviour written down.

### S3. What saturates first at peak, and how was it computed?

* **Why:** capacity is a chain, and it fails at its narrowest link: threads → connection pool → database cores → partitions → namespace quota.
* **Good:** peak rate × latency = concurrency (Little's law), worked through each link; pools sized from the database, not the thread count; quotas computed including surge and terminating pods ([7.8 §5.3](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)); partitions ≥ maximum consumers ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)).
* **Red flags:** "we'll autoscale"; per-pod limits multiplied by maximum replicas never computed (40 pods × a bulkhead of 10 = 400 calls into a 20-worker dependency).
* **Verify:** a load test that reports which resource saturated first, not just the throughput.

### S4. What can be delivered twice, late, or out of order, and why is that safe?

* **Why:** every network hop retries somewhere. At-least-once is the default, so duplicates are a matter of when.
* **Good:** an outbox for events; idempotent consumers keyed by message id in the same transaction as the effect; per-key ordering where it matters, and an answer for what breaks it (retry topics, partition changes).
* **Red flags:** `send()` after `save()`; "Kafka has exactly-once" (it does within Kafka, not into your database); deduplication by "checking first".
* **Verify:** replay the same message twice in a test and assert one effect.

### S5. How do schemas, APIs and events change without a lockstep deploy?

* **Why:** during a rollout, old and new versions run side by side, and a rollback runs old code against the new schema.
* **Good:** expand/contract migrations run as a separate step before the rollout ([7.8 §4](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)); additive event changes, versioned when not; consumer-driven contract tests ([5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md)).
* **Red flags:** a migration that renames a column in the same release that stops reading it; a shared library of event classes that forces every consumer to upgrade together.
* **Verify:** run the previous release's tests against the new schema.

### S6. What can't be rolled back, and what's the blast radius of a bad release?

* **Why:** code rolls back; data and messages don't. Published events, sent emails and destructive migrations are forever.
* **Good:** a canary with an automated gate (the Gateway API split in [7.8 §3](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) and its tested alert in §6); feature flags around irreversible behaviour; destructive migrations a release after the code stopped needing the data.
* **Red flags:** "we'll roll back if it breaks" for a change that emits events or drops columns.
* **Verify:** write the rollback plan in the PR, including what *can't* be undone.

### S7. How will we know it's broken before users do?

* **Why:** the failures that hurt are the quiet ones: fallbacks firing, a consumer lagging, a filter that records 200 for a 500 ([4.8 §1](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md)).
* **Good:** SLOs with burn-rate alerts; saturation metrics for every pool and queue (Hikari pending threads, consumer lag, executor queue size); alerts unit-tested with `promtool` ([7.8 §6](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) caught a canary alert that dropped its `job` label).
* **Red flags:** dashboards with averages only; fallbacks that aren't counted; alerts nobody has seen fire.
* **Verify:** break it on purpose in staging and time how long until someone is paged.

### S8. What happens during a deploy, a scale-down, a node drain, a restart?

* **Why:** these happen every day, so their failure modes are daily too.
* **Good:** a shutdown budget written down (preStop + drain + margin < grace period, because [preStop time comes out of the grace period](https://github.com/kubernetes/kubernetes/blob/v1.37.1/pkg/kubelet/kuberuntime/kuberuntime_container.go#L897)); readiness that flips before the drain; consumers that leave the group cleanly ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)); PDBs that allow at least one eviction ([7.8 §5.2](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)).
* **Red flags:** `group.instance.id: ${POD_NAME}` on a Deployment; `minAvailable: 75%` at 2–3 replicas; the same preStop sleep for consumers as for HTTP pods.
* **Verify:** a rollout under load with an error-rate and lag gate.

### S9. Where are the trust boundaries, secrets, personal data and tenant boundaries?

* **Why:** security bugs are design bugs found late.
* **Good:** authorization at the boundary *and* on the object (not just "is logged in"); secrets from the platform, never in images or logs; personal data minimized in logs and events; tenant filters that also cover native SQL and caches ([3.7 §5](../03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md): `@TenantId` doesn't filter native queries).
* **Red flags:** cache keys without the tenant; events carrying full customer records; "internal" endpoints without auth.
* **Verify:** a test that reads another tenant's object id and expects 404 or 403.

### S10. What's the simplest design that meets the SLO, and who runs it at 3 a.m.?

* **Why:** every component is something to page someone about.
* **Good:** a modular monolith until a module has a reason to leave ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)); platform features over self-run infrastructure (Kubernetes discovery over Eureka, [8.2](02-Microservices-and-Cloud-Native-Repos.md)); an owner and a runbook per component.
* **Red flags:** a new datastore for one feature; a service per entity; no owner in the design doc.
* **Verify:** list the components and the on-call rotation for each. Any blank cell is a finding.

---

## 3. Code review questions (C11–C20)

The ❌ code is from the flawed PR in §4, abridged; ✅ is the reviewed version. "Measured" lines are the lab's output.

### C11. Is every transactional method reached through the proxy, with nothing slow inside?

```java
// ❌ R1: this.saveAll() never reaches the proxy
public void importFlawed(List<String> customers) { saveAll(customers); }

// ❌ R2: a pooled connection is held for the whole HTTP call
@Transactional
public void placeFlawed(String customer) {
    orders.save(new Order(customer));
    pricing.get().uri("/slow?ms=1500").retrieve().body(String.class);
}

// ✅ call through the proxy; do remote I/O before the transaction
public void importFixed(List<String> customers) { self.saveAll(customers); }
public void placeFixed(String customer) {
    pricing.get().uri("/slow?ms=1500").retrieve().body(String.class);
    self.saveOrder(customer);                          // @Transactional, short
}
```

Measured: R1 left **1 row** of a failed two-row import with `isActualTransactionActive() = false`; the fixed path left 0. R2, with a 2-connection pool and 4 concurrent requests, failed **2 of 4** with `CannotCreateTransactionException(SQLTransientConnectionException)` after the 1 s connection timeout; moving the HTTP call out made 4 of 4 succeed. Why the connection is held from the first line: [8.6 §4](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md).

* **Look for:** `this.` calls to annotated methods; private or `final` `@Transactional` methods; HTTP, Kafka `send().get()`, `Thread.sleep` or file I/O inside a transaction.
* **Related trap, hit while writing this lab:** reading a *field* through a CGLIB proxy (`svc.orders`) returned `null`, because proxies don't populate fields. Inject the collaborator, or call a method.

### C12. Does every remote call have a timeout, and does the request have a deadline?

```java
// ❌ R3: Boot's auto-configured builder, no timeout configured
RestClient client = restClientBuilder.baseUrl(stub).build();

// ✅ per client
RestClient bounded = RestClient.builder().baseUrl(stub)
        .requestFactory(ClientHttpRequestFactoryBuilder.detect()
                .build(HttpClientSettings.defaults().withTimeouts(Duration.ofMillis(500), Duration.ofSeconds(1))))
        .build();
// ✅ or for every auto-configured client:  spring.http.clients.read-timeout=1s
```

Measured against a downstream that takes 3 s: Boot picked `JdkClientHttpRequestFactoryBuilder` (no other HTTP library on the classpath). The default client **returned after 3006 ms**, so no read timeout applied. The bounded client failed with `ResourceAccessException(HttpTimeoutException)` after **1014 ms**, and `spring.http.clients.read-timeout=1s` on the auto-configured builder failed after **1069 ms**. Boot's [`readTimeout` property is `null` by default](https://github.com/spring-projects/spring-boot/blob/v4.1.2/module/spring-boot-http-client/src/main/java/org/springframework/boot/http/client/autoconfigure/HttpClientSettingsProperties.java#L37), under the [`spring.http.clients` prefix](https://github.com/spring-projects/spring-boot/blob/v4.1.2/module/spring-boot-http-client/src/main/java/org/springframework/boot/http/client/autoconfigure/HttpClientsProperties.java#L16).

* **Look for:** HTTP, Redis ([Lettuce: 60 s](https://github.com/redis/lettuce/blob/7.5.2.RELEASE/src/main/java/io/lettuce/core/RedisURI.java#L224)), JDBC ([Hikari connection timeout: 30 s](https://github.com/brettwooldridge/HikariCP/blob/HikariCP-7.0.2/src/main/java/com/zaxxer/hikari/HikariConfig.java#L50)), Kafka (`delivery.timeout.ms`: 120 s) timeouts that are defaults rather than decisions; no deadline propagated downstream.

### C13. Is anything sent, published or emailed before the commit?

```java
// ❌ R4: the notification leaves before the transaction decides
@Transactional
public void placeAndNotifyFlawed(String customer) {
    orders.save(new Order(customer));
    pricing.post().uri("/events").body("OrderPlaced " + customer).retrieve().toBodilessEntity();
    throw new IllegalStateException("credit check failed after notifying");
}

// ✅ write the event to an outbox in the same transaction; a relay publishes after commit
    outbox.save(new OutboxEvent("OrderPlaced", customer));
```

Measured: **0 orders, 1 event received downstream** (an HTTP stub counted POSTs), versus 0 orders, 0 outbox rows and 0 events with the outbox. The order didn't exist and the world was told it did. That's the dual write ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)); [Spring commits after your method returns](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/interceptor/TransactionAspectSupport.java#L408), so anything sent inside the method is sent before the outcome is known.

### C14. How are read-modify-write races handled?

```java
// ❌ R5: read, decide, write, with no version and no lock
@Transactional
public void reserveFlawed(long productId, int qty, CyclicBarrier bothRead) throws Exception {
    Product p = products.findById(productId).orElseThrow();
    bothRead.await();                 // the test forces both transactions to read before either writes
    p.stock -= qty;
}
// ✅ @Version on the entity (optimistic), and retry the loser once
```

Measured from stock 10, two concurrent reservations of 1: **final stock 9** with no version, a lost update. With `@Version`, one transaction failed with `ObjectOptimisticLockingFailureException`, retried once, and the final stock was **8**. Alternatives: a conditional `UPDATE … SET stock = stock - ? WHERE id = ? AND stock >= ?`, or `SELECT … FOR UPDATE` when contention is high ([2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)).

### C15. What happens when this request or message arrives twice?

```java
// ✅ R6: an Idempotency-Key with a unique constraint and ON CONFLICT DO NOTHING
@Transactional
public long placeIdempotent(String key, String customer) {
    jdbc.update("insert into orders (id, customer, idem_key) values (nextval('orders_seq'), ?, ?) "
            + "on conflict (idem_key) do nothing", customer, key);
    return jdbc.queryForObject("select id from orders where idem_key = ?", Long.class, key);
}
```

Measured over HTTP, with the client resending after a "lost" response: the plain `POST /v1/orders` created **2 orders**; `POST /v2/orders` with `Idempotency-Key: key-123` created **1**, and both responses carried the same id. The constraint is the guarantee; "check, then insert" isn't ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).

### C16. How many statements does one request issue, and how large can a result get?

Measured with Hibernate statistics, listing 50 orders and touching their lines: `findAll()` + lazy collections = **51 statements**; an `@EntityGraph(attributePaths = "lines")` query = **1 statement**, same 150 lines. Also look for: list endpoints without a page size; `findAll()` on growing tables; offset pagination on deep pages ([2.4](../02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)); open-in-view, which Boot [still enables with a warning](https://github.com/spring-projects/spring-boot/blob/v4.1.2/module/spring-boot-jpa/src/main/java/org/springframework/boot/jpa/autoconfigure/JpaBaseConfiguration.java#L250).

### C17. Is every cache, queue, executor, pool and batch bounded?

Measured: a `ConcurrentMapCache` keyed by user input held **200,000** entries after 200,000 distinct keys; Caffeine with `maximumSize(10_000)` held **10,000**. Boot's `applicationTaskExecutor`: core 8, max `2147483647`, queue capacity `2147483647`. After 400 tasks of 50 ms: **pool size 8, 392 queued**, last task done after **3133 ms**. `max-size` is never reached, because the queue never fills ([`queueCapacity = Integer.MAX_VALUE`](https://github.com/spring-projects/spring-boot/blob/v4.1.2/core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/task/TaskExecutionProperties.java#L133) in Boot's properties, [the same default in `ThreadPoolTaskExecutor`](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-context/src/main/java/org/springframework/scheduling/concurrent/ThreadPoolTaskExecutor.java#L94)). Bounded (core 8, max 16, queue 50): pool size 16, 50 queued, **334 rejected**, which is back-pressure you can handle.

### C18. Which exceptions are caught, and what state do they leave behind?

```java
// ❌ R9: "audit is best effort", but the inner REQUIRED transaction already marked ours rollback-only
@Transactional
public void placeWithAuditFlawed(String customer) {
    orders.save(new Order(customer));
    try { audit.recordRequired(customer); } catch (RuntimeException e) { }
}
// ✅ make it really independent: @Transactional(propagation = REQUIRES_NEW) on the audit method
```

Measured: the flawed method threw **`UnexpectedRollbackException: "Transaction silently rolled back because it has been marked as rollback-only"`** [(Spring's message)](https://github.com/spring-projects/spring-framework/blob/v7.0.10/spring-tx/src/main/java/org/springframework/transaction/support/AbstractPlatformTransactionManager.java#L804) at commit, and **0 orders** were saved. The order was lost because of a log line. With `REQUIRES_NEW` the audit failure stayed in its own transaction, and the order committed. Also look for `catch (Exception e) {}`, `catch (InterruptedException e)` without restoring the flag, and exceptions mapped to the wrong HTTP status ([4.5 §9](../04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md)).

### C19. Which test fails if this breaks under concurrency or a dependency failure?

Every finding in §4 has a test shape that would have caught it: a barrier to force an interleaving (R5); a pool of 2 and four threads (R2); a stub that is slow (R3) or that counts side effects (R4); the same request sent twice (R6); a statement counter (R7). None of them needs a cluster. A suite that only passes happy paths doesn't test the behaviour that pages people. Ask for the failing version of the test, not just the passing one.

### C20. Which library defaults does this code rely on, on the version we run?

The defaults behind this PR's defects: no HTTP read timeout, an unbounded executor queue, open-in-view on. Elsewhere in the kit: Lettuce 60 s, Hikari connection timeout 30 s, spring-kafka's error handler skipping after 10 attempts, Resilience4j's 60 s slow-call threshold. [8.7](07-Source-Behind-the-Measurements-JDK-PostgreSQL-Redis-Kubernetes-Kafka.md) links each to its line. The review question is: *did anyone choose this value?* And check it on the version you run: the Boot 4.1.2 BOM gives you HikariCP 7.0.2 and Caffeine 3.2.4, not what `main` says.

---

## 4. The worked review: a flawed pull request, reproduced 🧊

**The PR:** *"Order service v2: bulk import, price check on placement, stock reservation, order API, best-effort audit, async notifications."* It compiles, its happy-path tests pass, and it has ten defects.

**The harness:** one Spring Boot 4.1.2 application against PostgreSQL 18.6. Hikari has `maximum-pool-size=2` and `connection-timeout=1000`. A JDK `HttpServer` acts as the downstream service: `/slow?ms=N` sleeps, and `/events` counts POSTs. For each defect, the flawed method and the reviewed method ran through the same scenario. Output from the first of two identical runs:

| # | Finding | Flawed (measured) | Reviewed version (measured) |
|---|---|---|---|
| R1 | `this.saveAll()` bypasses the `@Transactional` proxy | transaction active in saveAll: false; rows left: 1 | transaction active: true; rows left: 0 |
| R2 | Remote call inside a transaction holds a pooled connection | 2 × `CannotCreateTransactionException(SQLTransientConnectionException)`, 2 ok, in 1636 ms | 4 ok in 1514 ms |
| R3 | No read timeout on the auto-configured `RestClient` | returned after 3006 ms | `ResourceAccessException(HttpTimeoutException)` after 1014 ms (property: 1069 ms) |
| R4 | Side effect sent before commit (dual write) | orders: 0, events received downstream: 1 | orders: 0, outbox rows: 0, events received: 0 |
| R5 | Read-modify-write without concurrency control | final stock 9 (expected 8) | 1 optimistic-lock retry; final stock 8 |
| R6 | Non-idempotent POST under client retry | orders created: 2 | orders created: 1; both responses `{"id":15}` |
| R7 | N+1 on a lazy collection | statements: 51 (lines read: 150) | statements: 1 (lines read: 150) |
| R8 | Unbounded cache | entries: 200000 | entries: 10000 |
| R9 | Catch-and-continue after an inner `REQUIRED` transaction failed | `UnexpectedRollbackException`; orders saved: 0 | committed; orders saved: 1 |
| R10 | Unbounded executor queue (max-size never used) | core 8, max/queue 2147483647: pool 8, queued 392, done after 3133 ms | core 8, max 16, queue 50: pool 16, queued 50, rejected 334 |

### 4.1 The review, as it would be written on the PR

Ranked by blast radius. Each comment names the finding, the evidence, the fix and the test.

| Severity | Comment | Checklist |
|---|---|---|
| 🔴 Blocking | **R4:** the event is sent before commit; a rolled-back order was announced. Use the outbox table in the same transaction; add a test that rolls back and asserts no message. | C13, S4 |
| 🔴 Blocking | **R9:** the "best effort" audit rolls back the order. `REQUIRES_NEW` on the audit (or move it after commit); test: audit throws → order exists. | C18, C11 |
| 🔴 Blocking | **R6:** retries create duplicate orders. Require `Idempotency-Key`, unique constraint, `ON CONFLICT DO NOTHING`; test: same key twice → one row, same id. | C15, S4 |
| 🔴 Blocking | **R5:** concurrent reservations lose updates. `@Version` + one retry, or a conditional `UPDATE`; test with a barrier. | C14, S1 |
| 🟠 Must fix | **R2:** the pricing call holds a DB connection for 1.5 s; at peak that's pool exhaustion. Call it before the transaction; test: pool 2, four concurrent requests. | C11, S3 |
| 🟠 Must fix | **R3:** the pricing client has no read timeout. Set `spring.http.clients.read-timeout` (and connect timeout) below our deadline; test against a slow stub. | C12, C20, S2 |
| 🟠 Must fix | **R1:** the import isn't transactional (self-invocation). Move `saveAll` to its own bean or call through the proxy; test: a bad row → zero rows. | C11 |
| 🟡 Should fix | **R7:** listing orders is N+1 (51 statements for 50 orders). Use an entity graph and a page size; assert the statement count in a test. | C16 |
| 🟡 Should fix | **R10:** notifications use the default executor: unbounded queue, max-size unused. Bound it and decide the rejection policy; alert on queue size. | C17, C20 |
| 🟡 Should fix | **R8:** the price cache is unbounded and keyed by user input. Caffeine with `maximumSize` and a TTL. | C17 |

### 4.2 The harness pieces worth reusing

The concurrency helper that made R2 and R5 deterministic: start N threads, collect each outcome by exception type, report counts and elapsed time.

```java
String concurrently(int n, Call call) throws Exception {
    Map<String, AtomicInteger> outcomes = new ConcurrentHashMap<>();
    List<Thread> ts = new ArrayList<>();
    long t0 = System.nanoTime();
    for (int i = 0; i < n; i++) {
        int k = i;
        ts.add(Thread.ofPlatform().start(() -> {
            String o;
            try { call.run(k); o = "ok"; }
            catch (Exception e) { o = e.getClass().getSimpleName() + "(" + root(e) + ")"; }
            outcomes.computeIfAbsent(o, x -> new AtomicInteger()).incrementAndGet();
        }));
    }
    for (Thread t : ts) t.join();
    return outcomes + " in " + (System.nanoTime() - t0) / 1_000_000 + " ms";
}
```

Statement counting for R7 used Hibernate's own statistics (`spring.jpa.properties.hibernate.generate_statistics=true`, then `SessionFactory.getStatistics().getPrepareStatementCount()`). The downstream stub is 25 lines of `com.sun.net.httpserver.HttpServer`.

---

## 5. Running a code-review round in an interview

1. **Two minutes on intent.** "What is this change for, what are the tests, what's the traffic?" Interviewers plant defects that only matter at scale; the traffic number tells you which.
2. **Walk C11–C20 aloud.** Say the question even when the answer is "fine here". It shows the checklist, and it finds the defect you'd otherwise skim past.
3. **Rank by blast radius**: data loss and money first, then availability, then performance, then style. Never spend the last ten minutes on naming.
4. **For each finding: evidence, fix, test.** "This would announce an order that rolled back. An outbox in the same transaction fixes it. The test rolls back and asserts no message."
5. **Name the default.** Half of the defects above come from a value nobody chose. Saying "Boot sets no read timeout here" is the L6 signal.

---

## 6. Interview soundbites

* "My review checklist has ten design questions and ten code questions. For each finding I give the evidence, the fix, and the test that would have caught it."
* "The four blocking classes are always the same: a side effect before commit, a swallowed failure that rolls back more than you think, a non-idempotent write under retry, and a read-modify-write without a version."
* "I reproduced them: an announced order that rolled back, a 'best effort' audit that lost the order with `UnexpectedRollbackException`, two orders from one retry, and stock 9 instead of 8."
* "Half of production defects are defaults nobody chose: no HTTP read timeout in Boot, an unbounded executor queue, Lettuce's 60 seconds. I ask 'who chose this value?' in every review."

---

## Summary

| Topic | Key point | Section |
|---|---|---|
| Design review | S1–S10: ownership, dependency failure, capacity, delivery, evolution, rollback, observability, lifecycle, security, simplicity | §2 |
| Transactions | Self-invocation (1 row left), remote call inside a transaction (2 of 4 timed out), catch-and-continue (`UnexpectedRollbackException`, 0 orders) | §3 C11, C18 |
| Timeouts | Boot's `RestClient` waited 3 s; 1 s with `spring.http.clients.read-timeout` | §3 C12 |
| Side effects | Event delivered for a rolled-back order; outbox fixes it | §3 C13 |
| Concurrency and idempotency | Stock 9 instead of 8 without `@Version`; 2 orders from one retry without a key | §3 C14, C15 |
| Queries and resources | 51 statements → 1; 200,000 cache entries → 10,000; 392 queued tasks behind 8 threads | §3 C16, C17 |
| Tests and defaults | Concurrency and failure tests without a cluster; ask who chose each default | §3 C19, C20 |
| Worked review | Ten defects reproduced and fixed, ranked as PR comments | §4 |

**Next:** [8.5 Bar-raiser drill-downs (Round 2 covers 8.6–8.9) →](05-Code-Reading-Plan-and-Bar-Raiser-Drill-Downs.md)
