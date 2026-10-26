# 00 · How to Think Like a Staff Engineer (Read This First)

> The rest of the kit teaches mechanisms. This page teaches the **habits of reasoning** that make those mechanisms useful in an interview and in production. Every principle here links to a place in the kit where it was demonstrated with a real run.

---

## 1. Five constraints behind almost every backend question 🔥

Most "advanced" topics are the same few physical and logical constraints wearing different clothes. When a question feels new, ask which of these it really is.

### 1.1 Waiting holds resources (Little's law)

```text
things in flight = arrival rate × time each one takes
```

* 50 platform threads and 100 ms of blocking work cap you at 500 req/s; the kit measured 481 req/s with an 816 ms p50 because requests queued ([4.4](04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md)).
* A dependency that slows from 50 ms to 5 s multiplies in-flight calls by 100, which is why circuit breakers and bulkheads exist ([6.1 §0](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)).
* Connection pools, consumer counts, bulkheads and HPA targets are all sized with this one formula.

### 1.2 Shared mutable state is a serialization point

Anything many actors update (a row, a counter, a lock, a partition) is processed one at a time, however many machines you add.

* Lost updates and write skew ([2.6](02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)), the flash-sale hot row ([9.1 §4.3](09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md)), a Kafka partition's single consumer ([10.2](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)).
* The tools: avoid sharing (partition by key), make the shared step tiny (one atomic `UPDATE`, one CAS, as in HikariCP and Caffeine: [8.4](08-GitHub-Codebases-Study-Guide/04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)), or queue explicitly (`SKIP LOCKED`).

### 1.3 Failure is partial, and outcomes can be unknown

A timeout doesn't mean "it didn't happen". It means "I don't know".

* Every network write is **at-least-once** in practice, so receivers must be idempotent ([5.4](05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).
* Two systems can't commit atomically without coordination, hence the outbox and sagas ([5.3](05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)).
* A lease isn't a lock: a paused process can wake up believing it still owns something ([6.4](06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md), [6.5 drill 7](06-Resilience-Caching/05-Bar-Raiser-Drill-Downs.md)).

### 1.4 Memory and I/O come in blocks

Disks, pages, cache lines and network packets move data in chunks; sequential beats random; batching amortizes fixed costs.

* 8 KB pages, B+Trees vs LSM ([2.1](02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md), [9.2 §2](09-Staff-Capstone/02-Comparison-Matrices-Master-Sheet.md)); keyset pagination read 5 buffers instead of 16,615 ([2.4](02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)).
* JDBC batching (5–75× faster: [3.4](03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)), Kafka batching (3.7× with bigger batches: [10.1](10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)), Caffeine keeping a key's counters in one cache line ([8.4 §3](08-GitHub-Codebases-Study-Guide/04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)).

### 1.5 Coordination and ordering cost something

Agreement across machines needs round trips; order exists only within a single serialization point.

* Kafka orders per partition only, so the key is the ordering domain ([10.1 §5](10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)).
* `acks=all` waits for the in-sync replicas; synchronous replication trades latency for zero data loss ([10.1 §3](10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md), [2.7](02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)).
* Eager rebalancing stops every consumer to move three partitions ([10.2 §2](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)).

---

## 2. A method for any design question 🔥

1. **Restate the goal as correctness properties.** "No lost orders, no double charge, no oversell" beats a feature list ([9.1 §0](09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md)).
2. **Put numbers on it.** Back-of-envelope math finds where the scale really is.
3. **Choose the simplest shape that satisfies 1 and 2.** Usually fewer deployables than you'd think ([5.1](05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)).
4. **Walk the critical path** request by request, naming every synchronous dependency.
5. **Break it.** For each component: what happens when it's slow, down, duplicated, reordered, or lying?
6. **Say how you'll run it.** SLOs, alerts, rollout, rollback, capacity.
7. **Say what you'd build first, what you'd defer, and what would change your mind.**

---

## 3. Evidence beats assertion 🔥

The fastest way to sound senior is to say *how you know*. This kit treats every claim as something to check:

| Claim people repeat | What checking showed |
|---|---|
| "Resilience4j stores outcomes in a `RingBitBuffer`." | Not since 1.0; no such class in 2.4.0 ([6.1 §1](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)) |
| "Its rate limiter is a token bucket." | It's a fixed window: 10 permits in 54 ms with a limit of 5/s ([6.2 §2.1](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)) |
| "Hibernate paginates `JOIN FETCH` in memory." | Hibernate 7.4 pushes the limit into SQL for most shapes; a few still fall back ([3.3 §4](03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)) |
| "`orphanRemoval` deletes before inserting." | The ActionQueue runs inserts first ([3.2](03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md)) |
| "ZGC fixes latency." | Pauses totaled 20 ms, stalls still reached 69 ms on 2 CPUs ([7.4 §2.1](07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) |
| "Delete the cache key after the update and you're consistent." | A slow reader re-caches the old value; leases fix it ([6.4 §5](06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md)) |
| "Our config is fine; the app started." | Boot ignores unknown keys; a metadata check caught a property removed in 4.1 ([7.5 §0](07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md)) |

In an interview you rarely get to run code, but you can say: *"I'd verify that with X; I've seen Y happen when I measured it."* And when you don't know: *"I don't know; here's how I'd find out in ten minutes."*

---

## 4. Trade-off language

* **Name the cost before the benefit.** "The outbox costs a table, a relay and at-least-once delivery; in exchange we stop losing events."
* **Quantify where you can.** "Retry outside the breaker made 6 downstream calls; inside, 9" ([6.2 §5.2](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)).
* **Separate one-way from two-way doors.** Partition counts, primary-key types and event schemas are hard to undo; cache TTLs and pool sizes aren't. Spend design time accordingly.
* **State what would change your mind.** "If p99 must be under 10 ms at 30 GB heaps, I'd revisit ZGC with more CPU headroom."

---

## 5. What "staff" adds

| Habit | Looks like |
|---|---|
| Leverage | A paved road (service template, client library defaults, platform BOM) instead of advice to 40 teams ([7.5](07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md), [1.4](01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md)) |
| Deleting work | "Do we need Eureka on Kubernetes?" ([8.2 §1.3](08-GitHub-Codebases-Study-Guide/02-Microservices-and-Cloud-Native-Repos.md)) "Do we need twelve services?" |
| Making decisions durable | ADRs with context, options, decision, consequences ([9.1 §12](09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md)) |
| Migrations, not rewrites | Strangler fig, branch by abstraction, dual-running with verification ([5.1](05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)) |
| Operability as design | SLOs, failure-mode tables and game days before launch ([9.5](09-Staff-Capstone/05-Production-Readiness-Checklists.md)) |

---

## 6. Checking the premise

Interview prompts, design docs and even well-known repositories carry outdated or wrong premises. Building this kit found several in its own brief:

| Premise | Reality (verified 2026-10-25) |
|---|---|
| 9 pillars listed | The brief listed 8; Pillar 9 was added as the staff capstone |
| `jbubernik/modular-monolith-with-ddd` | Doesn't exist (GitHub 404); the reference is `kgrzybek/modular-monolith-with-ddd`, written in C# ([8.1](08-GitHub-Codebases-Study-Guide/01-Modular-Monolith-and-DDD-Repos.md)) |
| Resilience4j `RingBitBuffer`, "lock-free internals" | Replaced in 1.0; default windows use a `ReentrantLock`, lock-free is opt-in ([6.1](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)) |
| Resilience4j rate limiter = "token bucket" | Fixed window with reservations ([6.2](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)) |
| HHH90003004 always means in-memory pagination | Changed in Hibernate 7.4 ([3.3](03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)) |

The polite form: *"I think that changed. In version X it works like Y; here's how I'd confirm."* Correcting a premise with evidence is one of the strongest L6 signals there is.

---

## 7. How to use the rest of the kit

Start with the [README](README.md) to pick a study track. For each topic: read §0 (first principles) first, then the verified experiments, then close the file and answer its soundbites out loud. Finish each pillar with its bar-raiser file, where a partner reads the 🔍 probes. End with the [capstone](09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md).

**Next:** [README →](README.md)
