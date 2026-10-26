# Staff Backend Engineer Master Reference & Interview Playbook

A first-principles, **verified** reference for Senior (L5) and Staff (L6) backend interviews on the Java / Spring / PostgreSQL / Kafka / Kubernetes stack, and a production reference you can keep using after the interview.

* **75 Markdown files in 10 pillars + an introduction**, about 33,000 lines.
* **Batch 1 deep dive (2026-10-25):** Pillars 1–3 were deepened: five new modules (1.6 platform and quality-gate blueprints, 2.9–2.10 a line-by-line EXPLAIN atlas, 2.11 plan pathologies, 3.7 high-scale persistence), new verified sections and a **Summary** in every module, and a Round 2 of bar-raiser drills in 1.5, 2.8 and 3.6.
* **Batch 2 deep dive (2026-10-25):** Pillars 4–5 were deepened: five new modules (4.7 auto-configuration internals and a production starter blueprint, 4.8 request lifecycle, events, `@Async` and graceful shutdown, 5.9 an exhaustive patterns catalog with failure modes and Spring code, 5.10 a saga + Kafka + outbox/inbox + CQRS reference implementation broken eleven ways, 5.11 a modular-monolith blueprint with Kafka-externalized events and an extraction path), a verified deep-dive section and a **Summary** in every module, and a Round 2 of bar-raiser drills in 4.6 and 5.8.
* **Batch 3 deep dive (2026-10-25/26):** Pillars 6–7 were deepened, and **Kafka got its own pillar (10)**:
  * **Seven new modules:** 6.6 a chaos lab measuring each resilience layer under open-loop load; 6.7 Redis in production on a real Redis 8.10.2 with Sentinel; 7.7 jlink runtimes, the AOT cache and per-workload JVM profiles; 7.8 a Kustomize platform blueprint with guardrails, a KEDA consumer, Jobs, a canary and promtool-tested alerts, rendered, validated and audited; 10.3 a three-broker cluster with a Strimzi blueprint; 10.4 consumer scaling (static membership vs KIP-848, KEDA, rolling deploys); 10.5 Kafka drills.
  * **In every existing module:** a deep-dive section and a **Summary**.
  * **Round 2 drills** in 6.5, 7.6 and 10.5.
  * **Three earlier claims corrected in place:** static membership on Deployments, `InitialRAMPercentage` "committing" the heap, and `minAvailable: 75%` PDBs.
* Every pillar: first principles → under-the-hood mechanics → ❌ naïve vs ✅ production-hardened → **experiments that were actually run** → source code to read → interview soundbites → a **bar-raiser drill-down** file.
* **Verified stack (2026-10-25):** JDK 25 (Temurin 25.0.4.1) · Spring Boot 4.1.2 (Framework 7.0.10, Security 7.1.2, Data 4.1.2) · Hibernate 7.4.13 · HikariCP 7.0.2 · PostgreSQL 18.6 · MySQL 8.4.13 · Kafka 4.2.2 · spring-kafka 4.1.2 · Debezium 3.7.0 · Spring Modulith 2.1.2 · Resilience4j 2.4.0 · Caffeine 3.3.1 · Lettuce 7.9.0 (Boot-managed 7.5.2 in 6.7) · Redis 8.10.2 · Flyway 12.4.0 · Maven 3.10.0 / 4.0.0-rc-7 · Gradle 9.8.2 · Kubernetes v1.37.1 · KEDA v2.21.0 · Strimzi 1.3.0 · kustomize 5.8.3 · promtool 3.15.1 · hadolint 2.15.1 · cel-java 0.10.1.

**Start here:** [00 · How to Think Like a Staff Engineer](00-How-to-Think-Like-a-Staff-Engineer.md)

Sibling kits referenced throughout (not duplicated): [Java Backend Master Reference](../Java-Backend-Master-Reference/README.md) (JVM, concurrency, persistence, Spring, observability) · [CP / Codeforces kit, FAANG DSA section](../CP-Codeforces-Master-Kit/17-FAANG-Interview-DSA/01-interview-framework-and-communication.md) (coding rounds) · [CKAD exam prep](../CKAD-Exam-Prep/03-Application-Observability-and-Maintenance/02-probes-and-health-checks.md) (Kubernetes objects).

---

## Map of the kit

Legend: 🔥 must-know · ⚡ senior (L5) depth · 🧊 staff (L6) depth. Files marked **BR** are the bar-raiser drill-downs.

### Pillar 1 · Build systems
| # | File |
|---|---|
| 1.1 | [Maven internals: lifecycle, mojos, POM model, reactor, Maven 4](01-Build-Systems/01-Maven-Internals-Lifecycle-Mojos-Reactor.md) |
| 1.2 | [Gradle internals: phases, task DAG, build cache, configuration cache, daemon](01-Build-Systems/02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md) |
| 1.3 | [Dependency resolution & jar hell: nearest vs highest wins, BOMs, platforms, catalogs, shading](01-Build-Systems/03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md) |
| 1.4 | [Enterprise builds: OCI images, AOT cache, annotation processors, Enforcer, **verified Maven + Gradle blueprints**](01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md) |
| 1.5 | [BR: build systems & dependency engineering (Round 1 + Round 2)](01-Build-Systems/05-Bar-Raiser-Drill-Downs.md) |
| 1.6 | [**Blueprints II**: a published platform (BOM + catalog + library) consumed from Maven and Gradle, quality gates (JaCoCo, `dependency:analyze`), reproducibility check, CI](01-Build-Systems/06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md) |

### Pillar 2 · SQL and relational database internals
| # | File |
|---|---|
| 2.1 | [Storage: pages, tuples, HOT, TOAST, WAL](02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md) |
| 2.2 | [Indexes: B+Tree internals, UUIDv4 vs v7, composite order, skip scan, covering, GIN, GiST, BRIN](02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md) |
| 2.3 | [Query planning: `EXPLAIN (ANALYZE, BUFFERS)`, statistics, join algorithms, generic plans](02-SQL-RDBMS-Internals/03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md) |
| 2.4 | [Advanced SQL: window functions, keyset pagination, top-N per group, upsert, recursive CTEs](02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md) |
| 2.5 | [MVCC, visibility, VACUUM, wraparound vs InnoDB undo](02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md) |
| 2.6 | [Isolation anomalies, row locks, `SKIP LOCKED`, gap locks, deadlocks](02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md) |
| 2.7 | [Scaling: replicas & read-your-writes, partitioning, pooling math, sharding](02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md) |
| 2.8 | [BR: SQL & RDBMS internals (Round 1 + EXPLAIN-driven Round 2)](02-SQL-RDBMS-Internals/08-Bar-Raiser-Drill-Downs.md) |
| 2.9 | [**EXPLAIN atlas I**: every scan, sort, aggregate and parallel node, line by line, with cost formulas reproduced](02-SQL-RDBMS-Internals/09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md) |
| 2.10 | [**EXPLAIN atlas II**: joins, subqueries, self-join elimination, partitions, DML (WAL, FK triggers, ON CONFLICT), newer `EXPLAIN` options](02-SQL-RDBMS-Internals/10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md) |
| 2.11 | [**Plan pathologies**: eleven before/after diagnoses (row goals, type mismatch, correlated predicates, stale stats, `NOT IN`, …)](02-SQL-RDBMS-Internals/11-Plan-Pathologies-Diagnosis-Playbook.md) |

### Pillar 3 · JPA, Hibernate, Spring Data
| # | File |
|---|---|
| 3.1 | [Persistence context, entity states, dirty checking](03-JPA-Hibernate-Spring-Data/01-Persistence-Context-Entity-States-Dirty-Checking.md) |
| 3.2 | [The ActionQueue and flush ordering](03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md) |
| 3.3 | [N+1, fetch plans, pagination with collections (Hibernate 7.4), projections](03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md) |
| 3.4 | [Write throughput: IDENTITY vs SEQUENCE, pooled-lo, batching, COPY, hybrid JDBC/jOOQ](03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md) |
| 3.5 | [`@Transactional`: propagation, isolation, pitfalls, retries](03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md) |
| 3.6 | [BR: JPA, Hibernate & Spring Data (Round 1 + Round 2)](03-JPA-Hibernate-Spring-Data/06-Bar-Raiser-Drill-Downs.md) |
| 3.7 | [**High-scale persistence**: streaming 1 M rows in 256 MB, second-level cache invalidation and staleness, batch-fetch and IN-list SQL, `@TenantId`, EXPLAIN of ORM SQL](03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md) |

### Pillar 4 · Spring and Spring Boot internals
| # | File |
|---|---|
| 4.1 | [IoC container: bean definitions, post-processors, lifecycle, auto-configuration](04-Spring-Boot-Internals/01-IoC-Container-Startup-BeanDefinition-PostProcessors.md) |
| 4.2 | [Circular references, the three singleton caches, AOT and CDS](04-Spring-Boot-Internals/02-Circular-References-Singleton-Caches-AOT-CDS.md) |
| 4.3 | [AOP proxies: JDK vs CGLIB, self-invocation, advice ordering](04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md) |
| 4.4 | [Web concurrency: Tomcat threads vs virtual threads vs WebFlux, measured](04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md) |
| 4.5 | [Spring Security filter chain, JWT, method security, rate limiting](04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md) |
| 4.6 | [BR: Spring & Boot internals (Round 1 + Round 2)](04-Spring-Boot-Internals/06-Bar-Raiser-Drill-Downs.md) |
| 4.7 | [**Auto-configuration internals + a production starter blueprint**: conditions, ordering traps, generated metadata, `SmartLifecycle`, `ApplicationContextRunner` tests](04-Spring-Boot-Internals/07-Auto-Configuration-Internals-Production-Starter-Blueprint.md) |
| 4.8 | [**Request lifecycle, events, `@Async`, graceful shutdown**: what each layer sees, `AFTER_COMMIT` write trap, executor back-off, shutdown phases](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md) |

### Pillar 5 · Microservices patterns
| # | File |
|---|---|
| 5.1 | [Decomposition: modular monolith (Spring Modulith), strangler fig, branch by abstraction](05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md) |
| 5.2 | [Data ownership: database per service](05-Microservices-Patterns/02-Data-Ownership-Database-per-Service.md) |
| 5.3 | [Sagas: choreography vs orchestration, compensation, semantic locks](05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md) |
| 5.4 | [**Transactional outbox + idempotent consumer: complete, verified implementation** (polling + Debezium)](05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| 5.5 | [CQRS & event sourcing](05-Microservices-Patterns/05-CQRS-and-Event-Sourcing.md) |
| 5.6 | [Edge patterns: gateway, BFF, aggregator, service mesh](05-Microservices-Patterns/06-Edge-Patterns-Gateway-BFF-Aggregator-Service-Mesh.md) |
| 5.7 | [Observability (OpenTelemetry, correlation ids) & contract testing (Pact)](05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md) |
| 5.8 | [BR: microservices design patterns (Round 1 + Round 2)](05-Microservices-Patterns/08-Bar-Raiser-Drill-Downs.md) |
| 5.9 | [**The patterns catalog**: 42 patterns with flows, failure modes, Spring code and evidence; failure-mode matrix; decision guide](05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md) |
| 5.10 | [**Reference implementation**: orchestrated saga + Kafka + outbox/inbox + timeouts + CQRS, 11 failure modes run, every message reconciled](05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md) |
| 5.11 | [**Modular monolith blueprint**: Spring Modulith named interfaces, module tests, `@Externalized` Kafka events, outage drill, extraction path](05-Microservices-Patterns/11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md) |

### Pillar 6 · Resilience and caching
Kafka moved to its own [Pillar 10](#pillar-10--kafka-in-production) on 2026-10-26; old numbers 6.5/6.6/6.10 are now 10.1/10.2/10.3.

| # | File |
|---|---|
| 6.1 | [Resilience4j circuit breaker internals and sliding windows](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md) |
| 6.2 | [Bulkheads, rate limiters, retries with jitter, decorator order](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |
| 6.3 | [Caching: Caffeine W-TinyLFU and Redis/Lettuce L1/L2](06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md) |
| 6.4 | [Cache stampede, penetration, avalanche, hot keys, invalidation races](06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| 6.5 | [BR: resilience and caching (Round 1 + Round 2)](06-Resilience-Caching/05-Bar-Raiser-Drill-Downs.md) |
| 6.6 | [**Resilience under load**: a chaos lab measuring timeouts, retries, breakers, bulkheads, fallbacks and retry budgets in four failure phases](06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md) |
| 6.7 | [**Redis in production**: memory per key, eviction policies, client-side caching, pipelining, Sentinel failover, Spring's Redis cache (real Redis 8.10.2)](06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md) |

### Pillar 7 · Docker, the JVM, Kubernetes
| # | File |
|---|---|
| 7.1 | [The JVM in containers: cgroups v2, ergonomics, native memory, OOMKilled](07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |
| 7.2 | [Container images: multi-stage, layers, distroless, PID 1, AOT cache, buildpacks, Jib](07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md) |
| 7.3 | [Kubernetes probes and graceful shutdown](07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| 7.4 | [CPU throttling, GC choice, HPA and KEDA](07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |
| 7.5 | [**Production blueprints: `application.yml`, Dockerfile, Kubernetes manifests (validated)**](07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) |
| 7.6 | [BR: Docker, JVM, Kubernetes (Round 1 + Round 2)](07-Docker-JVM-Kubernetes/06-Bar-Raiser-Drill-Downs.md) |
| 7.7 | [**Blueprints II, images and JVM profiles**: jdeps/jlink runtimes and their blind spots, the AOT cache on jlink, per-workload flags measured with NMT, heap pinning](07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) |
| 7.8 | [**Blueprints II, the platform**: Kustomize base/overlays, namespace guardrails, admission policy (CEL), KEDA consumer, migration Job + CronJob, Gateway API canary, tested alerts, audited budgets](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |

### Pillar 8 · Reading real codebases
| # | File |
|---|---|
| 8.1 | [Modular monolith & DDD: Spring Modulith, kgrzybek (C#), ddd-by-examples/library](08-GitHub-Codebases-Study-Guide/01-Modular-Monolith-and-DDD-Repos.md) |
| 8.2 | [Microservices & cloud-native: petclinic microservices, Larsson's book repos](08-GitHub-Codebases-Study-Guide/02-Microservices-and-Cloud-Native-Repos.md) |
| 8.3 | [Sagas, outbox, CDC, Kafka internals: Eventuate, FTGO, debezium-examples, Apache Kafka, spring-kafka](08-GitHub-Codebases-Study-Guide/03-Saga-Outbox-Event-Driven-Repos.md) |
| 8.4 | [High-performance internals: HikariCP, Resilience4j, Caffeine source](08-GitHub-Codebases-Study-Guide/04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md) |
| 8.5 | [Code-reading plan + BR](08-GitHub-Codebases-Study-Guide/05-Code-Reading-Plan-and-Bar-Raiser-Drill-Downs.md) |

### Pillar 9 · Staff capstone
| # | File |
|---|---|
| 9.1 | [Reference architecture: an end-to-end order platform](09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md) |
| 9.2 | [Comparison matrices master sheet (Maven vs Gradle, B+Tree vs LSM, sagas, locking, G1 vs ZGC, and 20+ more)](09-Staff-Capstone/02-Comparison-Matrices-Master-Sheet.md) |
| 9.3 | [Mock interview loops, L5 vs L6 (scripts, rubrics, a flawed design to review)](09-Staff-Capstone/03-Mock-Interview-Loops-L5-vs-L6.md) |
| 9.4 | [330 rapid-fire flashcards](09-Staff-Capstone/04-Rapid-Fire-Flashcards.md) |
| 9.5 | [Production-readiness checklists + game days](09-Staff-Capstone/05-Production-Readiness-Checklists.md) |

### Pillar 10 · Kafka in production
Read it right after Pillar 6 (it was part of it until 2026-10-26).

| # | File |
|---|---|
| 10.1 | [Kafka producers: batching, durability, idempotence, ordering, transactions](10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md) |
| 10.2 | [Kafka consumers: lag, rebalancing (eager vs cooperative vs KIP-848), EOS, retries, DLQs](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| 10.3 | [**Production Kafka**: a real 3-broker cluster, durability under broker loss, topics as code, partition planning, a Strimzi blueprint validated against its CRDs](10-Kafka-Production/03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) |
| 10.4 | [**Consumer scaling**: static membership vs KIP-848, KEDA scale-down, rolling deploys, the 45-second stall](10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| 10.5 | [BR: Kafka in production (Round 1 + Round 2)](10-Kafka-Production/05-Bar-Raiser-Drill-Downs.md) |

---

## Study tracks

| Track | For | Path |
|---|---|---|
| **A · Two weeks to a senior loop** | L5 interview soon | [00](00-How-to-Think-Like-a-Staff-Engineer.md) → 🔥 sections of 2.2, 2.3, 2.4, 2.6 → 3.3, 3.4, 3.5 → 4.3, 4.4, 4.8 → 5.3, 5.4, 5.10 → 6.1, 6.2, 10.1, 10.2 → 7.1, 7.3 → every BR file → [9.3 Loop A](09-Staff-Capstone/03-Mock-Interview-Loops-L5-vs-L6.md) → [9.4](09-Staff-Capstone/04-Rapid-Fire-Flashcards.md) daily |
| **B · Six weeks to a staff loop** | L6 interview | Pillars 1–8 in order, with Pillar 10 right after 6 (one pillar every ~5 days, including 🧊 sections and the [8.5 reading plan](08-GitHub-Codebases-Study-Guide/05-Code-Reading-Plan-and-Bar-Raiser-Drill-Downs.md)) → [9.1](09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md) practiced three times → [9.3 Loop B and C](09-Staff-Capstone/03-Mock-Interview-Loops-L5-vs-L6.md) |
| **C · Production reference** | On the job | Use the symptom index below, then the matching ❌/✅ table and [9.5 checklists](09-Staff-Capstone/05-Production-Readiness-Checklists.md) |

### Symptom → where to look

| Symptom | Read |
|---|---|
| A query got slow as the table grew | [2.3](02-SQL-RDBMS-Internals/03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md), [2.2](02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md), [2.4 §2](02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md) |
| I have a plan and can't tell what's wrong | [2.11](02-SQL-RDBMS-Internals/11-Plan-Pathologies-Diagnosis-Playbook.md) (signature table), then [2.9](02-SQL-RDBMS-Internals/09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md) / [2.10](02-SQL-RDBMS-Internals/10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md) for the node |
| A delete or update is slow but its plan is fast | [2.10 §7.2](02-SQL-RDBMS-Internals/10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md#72-the-foreign-key-without-an-index-trigger-for-constraint) (unindexed foreign keys) |
| An export or batch job runs out of memory | [3.7 §1](03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#1-streaming-1000000-rows-in-a-256-mb-heap-verified-) |
| Second-level cache is stale or useless | [3.7 §2](03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#2-the-second-level-cache-hits-invalidation-and-staleness-verified-) |
| Many repositories, inconsistent dependency versions | [1.6](01-Build-Systems/06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md) |
| Hundreds of SQL statements per request | [3.3](03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md) |
| Bulk inserts are slow | [3.4](03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md) |
| Table and disk keep growing, vacuum warnings | [2.5](02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md), [5.4 §6](05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) (replication slots) |
| Lost updates, double bookings, deadlocks | [2.6](02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md) |
| `@Transactional` "doesn't work" | [3.5](03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md), [4.3](04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md) |
| Connection-pool timeouts after enabling virtual threads | [4.4](04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md), [8.4 §1](08-GitHub-Codebases-Study-Guide/04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md) |
| Events lost or duplicated between services | [5.4](05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md), [5.10 §5](05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#5-reading-each-failure-mode-) |
| Customer charged although the order was rejected after a timeout | [5.10 scenario 7](05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-7-a-timeout-during-the-pivot-) |
| Overselling under concurrent orders | [5.10 scenario 10](05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-10-contention-without-distributed-locks) |
| "Can we take orders while Kafka is down?" | [5.11 §4](05-Microservices-Patterns/11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md#4-outage-and-restart-drill-verified-) |
| Which pattern addresses this failure? | [5.9 §7](05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md#7-failure-mode--pattern-matrix-) |
| A platform starter's bean is missing in some services | [4.7 §5.2](04-Spring-Boot-Internals/07-Auto-Configuration-Internals-Production-Starter-Blueprint.md#52-ordering-trap-1-an-auto-configuration-without-after-verified-) |
| Dashboards show few 5xx, but users see errors | [4.8 §1](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#1-the-request-lifecycle-verified-) |
| A write in an `AFTER_COMMIT` listener sometimes vanishes | [4.8 §2.1](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#21-the-after_commit-write-trap-proven-both-ways-) |
| Request ids missing from `@Async` logs | [4.8 §3](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#3-async-which-executor-what-context-where-exceptions-go-verified-) |
| A feature flag stopped working after enabling Spring AOT | [4.2 §9.1](04-Spring-Boot-Internals/02-Circular-References-Singleton-Caches-AOT-CDS.md#91-what-the-bean-graph-is-fixed-at-build-time-means-in-practice-verified) |
| Authorization failures show up as 500s | [4.5 §9](04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md#9-deep-dive-who-writes-your-401-and-403-and-why-a-catch-all-handler-turns-403-into-500-verified-) |
| A slow dependency takes the whole service down | [6.1](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [6.2](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |
| Database melts when the cache restarts | [6.4 §3](06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| Stale prices after updates | [6.4 §5](06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| Consumer group keeps rebalancing | [10.2 §1–2](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| A poison message blocks a partition | [10.2 §4](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| Pods OOMKilled (exit 137) | [7.1](07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |
| 502s during every deploy | [7.3](07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| p99 spikes with low average CPU | [7.4](07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |
| Builds are slow or flaky; dependency conflicts | [1.2](01-Build-Systems/02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md), [1.3](01-Build-Systems/03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md) |
| Image push takes minutes per commit | [7.2 §2](07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md) |
| Retries made an incident worse | [6.6 §1–2](06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md), [6.2 §10](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |
| Redis failover lost writes or took far longer than expected | [6.7 §7](06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md) |
| `@Cacheable` errors fail requests, or a read right after a write is stale | [6.7 §8](06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md) |
| Producers block for two minutes when brokers are down | [10.3 §3](10-Kafka-Production/03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) |
| Partitions stall ~45 s after every deploy or scale-down | [10.4 §1–2](10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| KEDA adds consumers but lag doesn't drop | [10.4 §3](10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| A jlink image prints dates in English or loses CPU metrics | [7.7 §1](07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) |
| The heap shrinks after startup; memory alerts fire on idle pods | [7.7 §4](07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) |
| Node drains or cluster upgrades hang | [7.8 §5.2](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| The HPA can't create pods during a deploy (`FailedCreate`) | [7.8 §5.3](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| A migration Job retried a SQL typo until the deploy timed out | [7.8 §4](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| A CronJob can't reach its database | [7.8 §5.1](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |

---

## How this kit was verified

Labels used in the files:

* **Output (verified …)**: produced by running the code or command shown, on the stated versions. Deterministic outputs (counts, SQL, states, defaults) are reproducible.
* **One measured run**: timings from a single run on one Windows 11 laptop. They show *direction and mechanism*, not capacity.
* No number in the kit was written before it was measured. Where something wasn't run, the file says so.

| Pillar | What was run |
|---|---|
| 1 | Maven 3.10.0 and 4.0.0-rc-7, Gradle 9.8.2 builds; both blueprints built and verified; Jib image to a tarball; AOT cache startup measured. Batch 1: a Gradle platform (BOM, catalog, library) published and consumed from Maven and Gradle; JaCoCo 0.8.14 and `dependency:analyze` gates run failing and passing; jar SHA-256 compared across builds; configuration-cache invalidation reproduced |
| 2 | PostgreSQL 18.6 (primary + streaming replica) and MySQL 8.4.13; `EXPLAIN (ANALYZE, BUFFERS)`; multi-session interleavings for locks, anomalies and deadlocks. Batch 1: a deterministic `atlas` dataset (1 M orders, 3 M lines, 12 partitions) captured in one sequential session; cost and row estimates reproduced by hand; `pg_walinspect`, `pg_visibility`, `pageinspect`, `pg_buffercache`, `pg_stat_io` |
| 3 | Hibernate 7.4.13 with statement counting; Spring Data 4.1.2; jOOQ 3.21.9. Batch 1: streaming variants each in a 256 MB JVM, JCache/Caffeine second-level cache with statistics, `pg_stat_statements` 1.12 |
| 4 | Spring Framework 7.0.10 / Boot 4.1.2 labs: lifecycle, circular references, AOP ordering, load tests of the three concurrency models, the security chain. Batch 2: a two-module starter built with Maven (8 `ApplicationContextRunner`/end-to-end tests, generated metadata, `javac -proc` comparison); a request/event/async/shutdown trace lab with variant runs (Hikari auto-commit, `spring.task.execution.mode`); `process-aot` JVM vs AOT runs; security error paths in three advice variants; property-source precedence; `javap` of Boot/Spring classes |
| 5 | Spring Modulith 2.1.2, embedded Kafka 4.2.2, embedded Debezium 3.7.0, Pact 4.7.5, crash and duplicate scenarios. Batch 2: a four-service saga reference implementation (Boot 4.1.2, 3 partitions × 3 consumers per group, PostgreSQL 18.6) through 11 failure scenarios, run twice with identical deterministic output and fully reconciled message counts; a Modulith 2.1.2 + `spring-modulith-events-kafka` outage-and-restart drill and module tests (`mvn test`); catalog snippets compiled and three of them run |
| 6 | Resilience4j 2.4.0 (plus `javap` of the jars), Caffeine 3.3.1, Lettuce 7.9.0. Batch 3: an open-loop chaos lab (six client stacks × four dependency phases, run twice); a real Redis 8.10.2: the 6.3/6.4 labs re-run (identical), `MEMORY USAGE`, eviction policies, RESP3 client-side caching, pipelining, Sentinel failovers with and without `WAIT`; Spring Data Redis cache behaviours; `redis.conf`/ACL/Sentinel blueprints started and enforced |
| 7 | JDK 25 ergonomics and NMT, a GC comparison pinned to 2 CPUs, Boot probes and graceful shutdown, layer extraction, AOT-cache flag mismatch; registry metadata for base images; `application.yml` checked against Boot metadata and manifests against Kubernetes v1.37.1 OpenAPI + KEDA/Gateway API CRDs. Batch 3: six jdeps/jlink runtimes started and probed; startup timed 5× per variant; eleven JVM profiles measured with NMT and working set; hadolint; kustomize renders of five targets validated (60 documents) and audited, 12 negative tests; promtool rule tests; the admission policy's CEL evaluated with cel-java; a Flyway migration entry point run against PostgreSQL 18.6 in six scenarios |
| 10 | Kafka 4.2.2 + spring-kafka 4.1.2 (rebalance protocols, transactions, retry topics, lag). Batch 3: a KRaft cluster with three brokers (RF 3, min ISR 2, broker loss, `KafkaAdmin` behaviours); a Strimzi 1.3.0 blueprint validated against its CRDs; a scale-down/rolling-deploy lab (15 scenarios); `KafkaConsumer` config validation; `javap` of spring-kafka; KEDA 2.21.0 source read |
| 8 | GitHub API, file trees and raw-file checks for every referenced repo and path; source excerpts read from the default branches |
| 9 | Synthesis; flashcards generated from the Pillar 1–8 and 10 files |

**Limits, stated plainly:**

* **Redis:** the original 6.3/6.4 labs ran against **jedis-mock 1.1.20** (a real Redis binary was blocked at the time). In Batch 3 a real **Redis 8.10.2** started: the same labs gave identical output, and 6.7 measured what a mock can't (memory, eviction, failover).
* **No Docker, WSL or Kubernetes cluster** on the test machine. Dockerfiles weren't built, and cgroup/kernel behavior (OOM kill, CFS throttling) is explained from first principles. JVM ergonomics were verified with the same inputs (`-XX:MaxRAM`, `-XX:ActiveProcessorCount`).
* **Manifests:** schema-validated, and in 7.8 audited. No admission plugin ran: the Pod Security check is our own implementation of the documented controls (the Kyverno CLI wasn't permitted on this machine), and the CEL engine is cel-java, not the API server's.
* **Kafka log compaction** wasn't run: Kafka's log cleaner fails on Windows ([10.3 §4](10-Kafka-Production/03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md)).
* **B+Tree vs LSM** ([9.2 §2](09-Staff-Capstone/02-Comparison-Matrices-Master-Sheet.md)) is first-principles, with sources; no LSM engine was run.
* Lab harness code lived in a temporary workspace; the code that matters is shown inline in each section.

All GitHub repository and path references were verified to resolve: 158 at the Batch 2 check; the 70 unique GitHub URLs re-checked on 2026-10-26.

---

## Corrections to common premises (found while building this kit)

* The brief listed **8** pillars under a "9 pillars" heading; **Pillar 9** is the staff capstone.
* `jbubernik/modular-monolith-with-ddd` doesn't exist; the reference is **kgrzybek/modular-monolith-with-ddd**, in C# ([8.1](08-GitHub-Codebases-Study-Guide/01-Modular-Monolith-and-DDD-Repos.md)).
* Resilience4j has no `RingBitBuffer` since 1.0, its default windows use a lock, and its rate limiter is a **fixed window**, not a token bucket ([6.1](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [6.2](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)).
* Hibernate 7.4 changed when `JOIN FETCH` + pagination happens in memory (HHH90003004) ([3.3](03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md)).
* Spring's documentation says data access in an `AFTER_COMMIT` callback is not committed. With Hikari's default auto-commit it **was** committed (the transaction manager restores auto-commit during cleanup); with `auto-commit=false` it was lost. Rely on neither: use `REQUIRES_NEW` ([4.8 §2.1](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#21-the-after_commit-write-trap-proven-both-ways-)).
* **Corrected in this kit (Batch 3):** `group.instance.id: ${POD_NAME}` on Deployments, which stalled partitions 45 s per rollout ([10.4 §4](10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)); `InitialRAMPercentage = MaxRAMPercentage` as a way to commit the heap, which G1 undid at 0.85 s ([7.7 §4.2](07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)); and `minAvailable: 75%` PDBs, which allow 0 evictions at 2–3 replicas ([7.8 §5.2](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)). Each is fixed in place where it appeared.

## Verified surprises worth knowing

| Finding | Where |
|---|---|
| Maven 3.10 makes builds reproducible by default; JDK 23+ no longer runs classpath-discovered annotation processors | [1.1](01-Build-Systems/01-Maven-Internals-Lifecycle-Mojos-Reactor.md), [1.4 §3](01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md) |
| Boot repackaging includes `provided`-scope Lombok unless excluded | [1.4 §4.1](01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md) |
| PostgreSQL 18: B-tree skip scan, `BUFFERS` on by default in `EXPLAIN ANALYZE`, built-in `uuidv7()`, data checksums on by default | [2.2](02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md), [2.3](02-SQL-RDBMS-Internals/03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md) |
| Hibernate 7 ignores `…pooled.preferred_lo`; the setting is `hibernate.id.optimizer.pooled.preferred=pooled-lo` | [3.4](03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md) |
| `orphanRemoval` doesn't delete before insert; bag removals delete all rows and re-insert | [3.2](03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md) |
| Spring 7's core `@Retryable` runs outside `@Transactional` even on the same method; defaults have no jitter | [3.5](03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md), [6.2 §3.4](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |
| Boot 4 renamed starters (`-aspectj`; `-web` deprecated for `-webmvc`) and removed `spring.data.redis.lettuce.cluster.refresh.adaptive` in 4.1 | [6.1 §6.1](06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [7.5](07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) |
| Debezium's insert-then-delete outbox works; an inactive replication slot retains WAL | [5.4 §6](05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| Event-store projectors can skip events on out-of-order commits; fix with `pg_snapshot_xmin` | [5.5](05-Microservices-Patterns/05-CQRS-and-Event-Sourcing.md) |
| Retry outside the breaker: 6 downstream calls; inside: 9 with the breaker still closed | [6.2 §5.2](06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) |
| Kafka 4.x: `linger.ms` defaults to 5; eager rebalancing revoked 6 partitions to move 3 | [10.1](10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md), [10.2](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| spring-kafka 4: DLT suffix `-dlt`; `DefaultErrorHandler` = 10 instant attempts then skip; retry topics broke per-key order | [10.2 §4](10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| One CPU → SerialGC at any memory size; a small Boot app had ~165 MB outside a 68 MB heap | [7.1](07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |
| VACUUM skips index cleanup when < ~2 % of pages have dead items, so index-only scans keep heap-fetching | [2.9 §5](02-SQL-RDBMS-Internals/09-EXPLAIN-Atlas-Part-1-Scans-Sorts-Aggregates-Parallelism.md#5-index-only-scan-the-visibility-map-and-the-vacuum-that-didnt-help-) |
| Range predicates don't propagate across joins (equalities do): 660 ms → 135 ms with a redundant predicate | [2.10 §3](02-SQL-RDBMS-Internals/10-EXPLAIN-Atlas-Part-2-Joins-Subqueries-Partitions-DML.md#3-merge-join-and-the-predicate-postgresql-doesnt-copy-) |
| A stale logical replication slot blocks catalog vacuum and retains WAL, not data-table vacuum | [2.5 §2.3](02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md#23-verified-what-a-stale-logical-replication-slot-actually-blocks-) |
| PostgreSQL 18's `pg_stat_statements` folds IN lists of any length into one entry | [3.7 §3.3](03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#33-how-postgresql-18s-pg_stat_statements-sees-in-lists) |
| A native SQL update without `addSynchronizedEntityClass` evicts the entire Hibernate second-level cache | [3.7 §2](03-JPA-Hibernate-Spring-Data/07-High-Scale-Persistence-Streaming-L2-Cache-Batch-Fetch-Multitenancy-EXPLAIN.md#2-the-second-level-cache-hits-invalidation-and-staleness-verified-) |
| `@Fetch(SUBSELECT)` drops the page limit: a page of 5 parents loaded 15 parents' children | [3.3 §2.4](03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md#24-verified-fetchsubselect-re-runs-your-query-without-the-page-limit-) |
| `dependency:analyze` found code compiling against a transitive slf4j version nobody chose | [1.6 §3.3](01-Build-Systems/06-Build-Script-Blueprints-Platform-Publishing-Quality-Gates-CI.md#33-gate-5-failing-what-dependencyanalyze-catches-verified) |
| A G1-trained AOT cache is silently ignored under ZGC | [7.2 §4.3](07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md) |
| Boot 4.1.2: graceful shutdown is the default; readiness flips only after `ApplicationRunner`s | [7.3](07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| Spring AOT: with a runtime flag `true` and profile `eu` active, both conditional beans were absent, silently | [4.2 §9.1](04-Spring-Boot-Internals/02-Circular-References-Singleton-Caches-AOT-CDS.md#91-what-the-bean-graph-is-fixed-at-build-time-means-in-practice-verified) |
| `@ConditionalOnBean` without `after` lost to alphabetical ordering; in application config it never matches | [4.7 §5.2–5.3](04-Spring-Boot-Internals/07-Auto-Configuration-Internals-Production-Starter-Blueprint.md#52-ordering-trap-1-an-auto-configuration-without-after-verified-) |
| A servlet filter recorded **200** for an unhandled 500; handled exceptions reach interceptors as `ex=null` | [4.8 §1](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#1-the-request-lifecycle-verified-) |
| One extra `Executor` bean displaced Boot's `applicationTaskExecutor` and its MDC `TaskDecorator` | [4.8 §3](04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#3-async-which-executor-what-context-where-exceptions-go-verified-) |
| A catch-all `@ExceptionHandler` turned method-security 403s into 500s; filter-chain denials never reach advice | [4.5 §9](04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md#9-deep-dive-who-writes-your-401-and-403-and-why-a-catch-all-handler-turns-403-into-500-verified-) |
| `SpringApplicationBuilder.properties()` are default properties: the lowest precedence | [4.1 §8.1](04-Spring-Boot-Internals/01-IoC-Container-Startup-BeanDefinition-PostProcessors.md#81-where-a-property-value-actually-comes-from-verified) |
| A pivot that succeeded after its timeout needed a refund (`REFUNDED 40.00`) | [5.10 scenario 7](05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#scenario-7-a-timeout-during-the-pivot-) |
| Modulith's Kafka externalization: commit in 14 ms with Kafka down; records carry `__TypeId__` with the producer's class name | [5.11 §4](05-Microservices-Patterns/11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md#4-outage-and-restart-drill-verified-) |
| Retries ×3 with backoff and jitter put 2.72× the load on an overloaded dependency; a 10 % retry budget looked like no retries at all | [6.6 §1](06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md) |
| A Sentinel failover lost 38 acknowledged writes and took 1.75 s once, 17.5 s another time; Lettuce waits 60 s by default | [6.7 §6–7](06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md) |
| Spring Data Redis 4 writes cache entries asynchronously: 21–59 of 200 immediate re-reads missed | [6.7 §8](06-Resilience-Caching/07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md) |
| Two brokers down: `acks=all` refused, surfacing as a `TimeoutException` after 120 s; `acks=1` accepted with one copy | [10.3 §3](10-Kafka-Production/03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) |
| A static member's `close()` doesn't leave the group (45 s); spring-kafka only calls plain `close()`; KIP-848 rejects `session.timeout.ms` | [10.4 §1](10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) |
| jdeps' module list silently printed German dates in English; Paketo's default jlink broke CPU metrics and JFR | [7.7 §1](07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) |
| G1 uncommitted 674 MB of a 718 MB initial heap 0.85 s into startup; only `AlwaysPreTouch` made a pinned heap resident | [7.7 §4](07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) |
| Spring Boot exits 1 for every startup failure: `ExitCodeExceptionMapper`s aren't consulted when refresh fails | [7.8 §4.1](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| `> on (namespace)` stripped the `job` label from a canary alert (caught by a promtool test) | [7.8 §6.2](07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) |
| `jsonb` rewrote the outbox payload text; Jackson's default tree parsing turned `25.00` into `25.0` | [4.7 §5.4](04-Spring-Boot-Internals/07-Auto-Configuration-Internals-Production-Starter-Blueprint.md#54-end-to-end-the-starter-with-a-real-database-and-broker-verified), [5.9 §8](05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md#8-spring-code-sheet-the-patterns-not-implemented-elsewhere-in-the-kit) |

---

## Conventions

* Each topic file: header (verified stack, prerequisites, go-deeper links) → **§0 first principles** → numbered sections → ❌ naïve vs ✅ production-hardened → source to read → interview soundbites → deep-dive section (Batches 1–3) → **Summary** table → **Next** link.
* Bar-raiser files: 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense (hidden in a click-to-expand block), then an L5 vs L6 table, red flags and flashcards.
* Versions drift. Before quoting a default in an interview, check it on the version you'll be asked about; the kit shows how (`javap -constants`, `PrintFlagsFinal`, configuration metadata, `ConfigDef`).

*Last verified: 2026-10-26.*
