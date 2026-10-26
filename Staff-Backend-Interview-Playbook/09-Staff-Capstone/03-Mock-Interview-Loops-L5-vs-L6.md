# 9.3 Mock Interview Loops: L5 vs L6

> How to use this file: run the loops with a partner who reads the **interviewer script** and the 🔍 probes, while you answer out loud with a timer. Each round lists what an L5 answer and an L6 answer sound like, and a 1–4 rubric. The technical content is in Pillars 1–8; this file is the practice harness.
>
> **Level naming varies by company.** This kit uses the Google-style ladder: **L5 = Senior**, **L6 = Staff**. Meta: E5 / E6. Amazon: L6 is Senior (SDE III) and L7 is Principal. Calibrate to the role, not the number.

---

## 0. What changes between L5 and L6 🔥

| Dimension | L5 (Senior) | L6 (Staff) |
|---|---|---|
| Scope | A service or a feature area, end to end | Several teams' systems; the platform and its standards |
| Ambiguity | Clarifies requirements, then executes | Finds the *right problem*, reframes it, kills bad projects |
| Technical depth | Correct mechanisms, good defaults | Mechanisms + numbers + failure modes + evidence ("I measured…") |
| Trade-offs | Names them | Quantifies them, picks one, says what would change the decision |
| Operations | Knows the dashboards | Defines SLOs, failure-mode analyses, migration and rollback plans |
| Influence | Mentors teammates | Aligns other teams through ADRs, reviews, paved roads |
| Signature phrase | "Here's how I'd build it." | "Here's what I'd build first, what I'd defer, and how we'd know we were wrong." |

---

## 1. Loop A: L5 backend engineer, product team (4 rounds)

### A1. Practical coding (45 min)

**Script:** *"Implement an in-memory cache for an expensive `PriceService.load(sku)`: bounded size, TTL, and when 100 threads ask for the same missing key, the loader runs once."*

| Minute | Expect |
|---|---|
| 0–5 | Clarify: size, TTL semantics, concurrency, eviction policy, null values |
| 5–30 | `ConcurrentHashMap<K, CompletableFuture<V>>` with `computeIfAbsent` (single flight), expiry timestamps, size bound with an access-ordered structure under a lock, or explain why you'd use Caffeine in production |
| 30–40 | Tests: concurrent misses → one load; expired entry → reload; loader failure → not cached |
| 40–45 | Probes below |

🔍 Probes: *"What if the loader takes 5 s and holds a lock?"* (the `ConcurrentHashMap.compute` bin-lock trap; futures outside the lock, [6.3 §1.4](../06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)) · *"Why does Caffeine beat LRU?"* ([6.3 §1.2](../06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)) · *"Readers block at expiry. Fix it."* (refresh-ahead).

DSA-style coding rounds are covered by the sibling kit: [FAANG interview framework](../../CP-Codeforces-Master-Kit/17-FAANG-Interview-DSA/01-interview-framework-and-communication.md) and [design problems (LRU, LFU, rate limiter)](../../CP-Codeforces-Master-Kit/17-FAANG-Interview-DSA/17-design-problems.md).

### A2. System design (45 min)

**Script:** *"Design an inventory reservation service for checkout. 300 orders/s at peak, a few SKUs get flash-sale traffic."*

| L5 answer | L6 answer adds |
|---|---|
| Reservation table, conditional `UPDATE … WHERE available >= qty`, reservation TTL with a sweeper, idempotency key per order | Hot-row math and three mitigations (bucketed stock, token pre-allocation with `SKIP LOCKED`, single-writer partition); reconciliation; how the saga compensates; what the oversell budget is, and who signs off on it ([9.1 §4.3](01-Reference-Architecture-End-to-End-Order-Platform.md)) |

🔍 Probes: *"Two requests read 1 unit left at the same time."* ([2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)) · *"The sweeper and a confirmation race."* · *"How do other services learn about stock changes?"* (outbox, compacted topic).

### A3. Domain deep dive: data access (45 min)

**Script:** *"This endpoint got slow after the order count passed 10 million."* Show the interviewer's prepared clues one at a time:

1. 51 SQL statements per request → N+1 ([3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)).
2. `OFFSET 400000` in the list endpoint → keyset pagination ([2.4](../02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md)).
3. `EXPLAIN` shows a sequential scan on `orders(customer_id, created_at)` → composite index in the right column order ([2.2](../02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)).
4. Writes slowed too: `IDENTITY` ids, no batching ([3.4](../03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md)).
5. Nightly job + `@Transactional` on a 2-hour method → long transaction, vacuum can't clean ([2.5](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md), [3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md)).

### A4. Behavioral (45 min)

Prompts: *"An incident you led."* · *"A time you pushed back on a deadline."* · *"A design you got wrong."* Use the story bank in §5.

---

## 2. Loop B: L6 staff backend (5 rounds)

### B1. System design (60 min): the order platform

**Script:** the [9.1](01-Reference-Architecture-End-to-End-Order-Platform.md) prompt. The interviewer stays quiet for 25 minutes, then drills into two rows of the failure-mode table.

| Rubric | 1 (no hire) | 2 (lean no) | 3 (hire) | 4 (strong hire) |
|---|---|---|---|---|
| Requirements | Starts drawing boxes | Lists features | States correctness properties and SLOs | Prioritizes them and shows how each drives a design choice |
| Scale | No numbers | Numbers without use | Back-of-envelope that finds the real hotspot | Same, plus what changes at 10× |
| Consistency | "Use a distributed transaction" | Saga named | Saga with pivot, compensations, idempotency | Plus unknown payment outcome, semantic locks, timeouts, reconciliation |
| Operations | None | Mentions monitoring | SLOs, failure modes | Error budgets, rollout/rollback, what to build first |

### B2. System design (60 min): event platform

**Script:** *"Twelve teams want to publish domain events. Design the platform: how events get out of services, how schemas evolve, how consumers fail safely, and how it's operated."*

Expected L6 content: outbox via CDC as a paved road, with a polling fallback ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)); topic naming, keys and partition policy ([10.1 §5](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md)); schema registry with compatibility rules; consumer library defaults (idempotency, retry/DLT policy, cooperative or KIP-848 groups; [10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)); replication-slot monitoring; DLT replay tooling; cost and ownership model.

🔍 Probes: *"A team's connector was down for a day."* · *"A producer changed a field type."* · *"One consumer group is 3 hours behind on one partition."* ([10.2 §1.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md))

### B3. Deep dive: "the most complex system you've worked on" (60 min)

The interviewer uses bar-raiser chains: every answer gets "why?", "what did you measure?", "what broke?", "what would you change?". Prepare **one** system so well that you can go five levels down on any component. The drill-down files are the practice material: [1.5](../01-Build-Systems/05-Bar-Raiser-Drill-Downs.md), [2.8](../02-SQL-RDBMS-Internals/08-Bar-Raiser-Drill-Downs.md), [3.6](../03-JPA-Hibernate-Spring-Data/06-Bar-Raiser-Drill-Downs.md), [4.6](../04-Spring-Boot-Internals/06-Bar-Raiser-Drill-Downs.md), [5.8](../05-Microservices-Patterns/08-Bar-Raiser-Drill-Downs.md), [6.5](../06-Resilience-Caching/05-Bar-Raiser-Drill-Downs.md), [7.6](../07-Docker-JVM-Kubernetes/06-Bar-Raiser-Drill-Downs.md), [8.5](../08-GitHub-Codebases-Study-Guide/05-Code-Reading-Plan-and-Bar-Raiser-Drill-Downs.md).

### B4. Design review: critique a flawed proposal (45 min)

The interviewer hands you this (read it in 5 minutes, then review it like a staff engineer):

> **Proposal: "Real-time loyalty points"**
> 1. When an order is saved, `OrderService` calls `kafkaTemplate.send("points", event)` inside the same `@Transactional` method.
> 2. The points service consumes with auto-commit, adds points with `UPDATE accounts SET points = :newTotal` (computed in Java from a prior `SELECT`).
> 3. To be safe, the consumer retries failures 10 times with no delay, then logs and skips.
> 4. Points are cached in Redis for 1 hour; on update we `SET` the new value in Redis before committing the DB transaction.
> 5. The points service's liveness probe calls the database.
> 6. We'll run it with `-Xmx` equal to the 1 GiB container limit and a 1-CPU limit.
> 7. To scale, the HPA targets 70 % memory.
> 8. The `points` topic has 3 partitions; we'll add more when we need them.
> 9. For exactly-once, we enabled Kafka transactions on the producer.
> 10. Rate limiting for the partner API uses Resilience4j's RateLimiter at the partner's limit, per pod.

<details><summary>Answer key (at least one finding per line)</summary>

| # | Problem | Fix | Reference |
|---|---|---|---|
| 1 | Dual write; the send happens before commit, so a rollback publishes a phantom event | Outbox | [5.4 §0](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| 2 | Auto-commit = possible loss or duplicates; read-modify-write loses updates; not idempotent | Container-managed commits; `points = points + ?` with a dedup row in the same transaction | [10.2 §3](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), [2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md) |
| 3 | That's the `DefaultErrorHandler` default behavior: retries with no back-off, then silent loss | Backoff + DLT + alerting + replay | [10.2 §4](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| 4 | Cache set before commit (rollback leaves wrong data); set-order races | Delete after commit; leases or versioned fills | [6.4 §5](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| 5 | Liveness checks a dependency → restart storms | Liveness = livenessState only | [7.3 §0](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| 6 | `-Xmx` = limit → OOMKilled; 1 CPU → SerialGC by default | Heap + non-heap budget; explicit GC; CPU policy | [7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |
| 7 | Memory-based HPA on a JVM never scales down | CPU against honest requests, or lag via KEDA | [7.4 §3.2](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |
| 8 | Adding partitions remaps keys (per-account ordering breaks); 3 partitions caps consumers at 3 | Size partitions up front | [10.1 §1.2](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md) |
| 9 | Kafka transactions don't cover the DB write; the consumer is the problem | Idempotent consumer | [10.1 §6](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md) |
| 10 | Fixed window allows 2× bursts; per-pod limit multiplies with replicas | Below the limit / central limiter / honor `Retry-After` | [6.2 §2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |

An L6 review also **prioritizes**: 1, 2 and 4 are correctness bugs (lost or wrong points); 5–7 are availability risks; 8–10 are scaling and cost risks. And it proposes the smallest change set that makes the design safe to ship.
</details>

### B5. Leadership and strategy (45 min)

Prompts:

* *"Your org has 40 services with five different retry and timeout conventions. What do you do?"* (paved road: a shared client library or platform defaults, ADR, migration plan, metrics to prove adoption; [6.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md))
* *"Leadership wants to split the monolith this year."* (modular monolith first, extraction criteria, strangler; [5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md))
* *"Tell me about a time you changed another team's direction without authority."*

---

## 3. Loop C: L6 data/infra flavor (3 rounds, swap into Loop B)

| Round | Script | Material |
|---|---|---|
| C1 | *"PostgreSQL CPU at 100 % every night at 3 AM, and disk keeps growing."* | Autovacuum vs a long transaction, wraparound warnings, replication slot retention, `pg_stat_statements` ([2.5](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md), [2.7](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md), [5.4 §6](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)) |
| C2 | *"Our Java services get OOMKilled after a Kubernetes upgrade; heap dashboards look fine."* | Exit 137 vs OOME, NMT, direct memory, cgroup v2, GC choice by CPU ([7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md), [7.4](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) |
| C3 | *"Design exactly-once processing for a payments ledger fed by Kafka."* | What EOS covers, idempotent effects, LSO stalls, reconciliation ([10.1 §6](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md), [10.2 §5](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)) |

---

## 4. Scoring sheet (copy per mock)

| Round | Requirements | Depth | Trade-offs | Failure modes | Communication | Overall (1–4) | Notes: what to re-study |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
| | | | | | | | |

Patterns that cost offers, in practice:

* Jumping to boxes before stating correctness properties.
* Naming patterns without mechanisms ("we'll use a saga") or mechanisms without numbers.
* Never saying "I don't know, here's how I'd find out."
* Defending every choice instead of naming its weakness first.
* Running out of time before failure modes. Budget for them explicitly.

---

## 5. Story bank (behavioral) ⚡

Prepare 6–8 stories in **STAR + reflection** form (Situation, Task, Action, Result, and what you'd do differently). Map each to several prompts:

| Story theme | Covers prompts like | Technical hook from this kit you can use |
|---|---|---|
| Led an incident | "Incident you led", "pressure", "communication" | A rollout causing 502s fixed with preStop + grace budget ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)) |
| Changed a decision with data | "Disagreed with a senior", "influence" | Retry outside the breaker: 6 vs 9 downstream calls ([6.2 §5.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)) |
| Raised the bar for many teams | "Impact beyond your team" | A paved-road service template (the [7.5](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) blueprint, config validated mechanically) |
| Killed or re-scoped a project | "Ambiguity", "saying no" | Microservices split replaced by a modular monolith with extraction criteria ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)) |
| Was wrong | "Mistake", "learning" | A cache-aside design that served stale prices until leases were added ([6.4 §5](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md)) |
| Mentored someone to independence | "Growing others" | Teaching `EXPLAIN (ANALYZE, BUFFERS)` reading ([2.3](../02-SQL-RDBMS-Internals/03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md)) |
| Long migration | "Execution over months" | Strangler + branch by abstraction ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)) |

Use **your own** experiences. The technical hooks are there to add precise, verifiable detail, which is what separates staff-level stories from generic ones.

---

## 6. Two-week mock schedule

| Day | Mock |
|---|---|
| 1 | A2 (L5 design), self-scored |
| 2 | A3 deep dive with a partner using the clue cards |
| 3 | B1 order platform (record yourself; watch for time budget) |
| 4 | Re-study weak rows; flashcards ([9.4](04-Rapid-Fire-Flashcards.md)) |
| 5 | B4 design review (cover the answer key) |
| 6 | B3 deep dive on your own system, partner uses the drill-down files |
| 7 | Rest / light review |
| 8 | B2 event platform |
| 9 | C1 + C2 |
| 10 | B5 leadership + 3 behavioral stories |
| 11 | Full Loop B back to back (fatigue matters) |
| 12 | Fix the two weakest rubric rows |
| 13 | A1 coding + C3 |
| 14 | Light review of [9.2](02-Comparison-Matrices-Master-Sheet.md) and [9.5](05-Production-Readiness-Checklists.md); sleep |

**Next:** [9.4 Rapid-fire flashcards →](04-Rapid-Fire-Flashcards.md)
