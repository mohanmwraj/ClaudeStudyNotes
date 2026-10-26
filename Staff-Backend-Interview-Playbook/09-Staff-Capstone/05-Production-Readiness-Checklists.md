# 9.5 Production-Readiness Checklists

> Use these in three ways: as a **launch review** for a new service, as a **design-review** prompt list, and in interviews when asked *"how do you know a service is ready for production?"* Every item links to the section that explains it and, where the kit ran an experiment, shows the evidence. Copy the file into a PR or ADR and tick the boxes.

---

## 1. Build and supply chain ([Pillar 1](../01-Build-Systems/05-Bar-Raiser-Drill-Downs.md))

- [ ] Versions come from one BOM / platform; no hard-coded versions in modules ([1.3](../01-Build-Systems/03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md))
- [ ] Enforcer / Gradle checks: dependency convergence, banned dependencies (e.g. old `commons-logging`), plugin versions pinned ([1.4 §4](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md))
- [ ] Annotation processors declared explicitly (JDK 23+ no longer discovers them) ([1.4 §3](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md))
- [ ] `provided`-scope tools (Lombok) excluded from the runtime jar ([1.4 §4.1](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md))
- [ ] Reproducible builds verified (same inputs → same digest); build-info timestamps excluded from cache keys ([1.2](../01-Build-Systems/02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md))
- [ ] SBOM generated, image scanned, image signed, base image pinned by digest ([7.2 §6](../07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md))
- [ ] CI uses `verify`, not `install`; build time has an SLO ([1.1 §2.4](../01-Build-Systems/01-Maven-Internals-Lifecycle-Mojos-Reactor.md))

## 2. Database ([Pillar 2](../02-SQL-RDBMS-Internals/08-Bar-Raiser-Drill-Downs.md))

- [ ] Primary keys are time-ordered (sequence or UUIDv7), not UUIDv4 on hot tables ([2.2](../02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md))
- [ ] Every query on the hot path has a checked `EXPLAIN (ANALYZE, BUFFERS)` and a matching composite index in the right column order ([2.3](../02-SQL-RDBMS-Internals/03-Query-Planning-EXPLAIN-Statistics-Join-Algorithms.md))
- [ ] List endpoints use keyset pagination, not deep `OFFSET` ([2.4 §2](../02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md))
- [ ] Counters, balances and stock use atomic updates or `@Version`, never read-modify-write in Java ([2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md))
- [ ] Serializable / retryable transactions have a retry wrapper around the **whole** transaction ([2.6 §2](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md))
- [ ] `statement_timeout`, `idle_in_transaction_session_timeout` and `lock_timeout` set for the app role
- [ ] Autovacuum tuned for hot tables; alerts on dead tuples, oldest transaction age, XID age ([2.5](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md))
- [ ] Replication lag monitored; read-your-writes routed to the primary ([2.7](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md))
- [ ] Large tables partitioned with a retention plan; connection counts fit the DB (pooler if needed) ([2.7](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md))
- [ ] Schema migrations are backward compatible (expand → migrate → contract) and run with lock timeouts

## 3. Persistence layer ([Pillar 3](../03-JPA-Hibernate-Spring-Data/06-Bar-Raiser-Drill-Downs.md))

- [ ] `spring.jpa.open-in-view=false` ([3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md))
- [ ] Statement count per request is tested (no N+1); batch fetch size set ([3.3](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md))
- [ ] `hibernate.query.fail_on_pagination_over_collection_fetch=true` ([3.3 §4](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md))
- [ ] `SEQUENCE` ids with pooled-lo and JDBC batching for write-heavy entities ([3.4](../03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md))
- [ ] Read models use DTO projections / `JdbcClient` / jOOQ, not entity graphs ([3.4 §6](../03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md))
- [ ] `@Transactional` boundaries reviewed: no remote calls inside, no self-invocation, correct propagation ([3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md))
- [ ] Bag/`List` collections and unidirectional `@OneToMany` reviewed for delete-all/re-insert and extra UPDATEs ([3.2](../03-JPA-Hibernate-Spring-Data/02-ActionQueue-Flush-Ordering.md))

## 4. Spring application ([Pillar 4](../04-Spring-Boot-Internals/06-Bar-Raiser-Drill-Downs.md))

- [ ] No circular dependencies; `spring.main.allow-circular-references` stays false ([4.2](../04-Spring-Boot-Internals/02-Circular-References-Singleton-Caches-AOT-CDS.md))
- [ ] Proxy-based annotations (`@Transactional`, `@Cacheable`, `@CircuitBreaker`, `@Async`) are only on public methods called through the proxy ([4.3](../04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md))
- [ ] Concurrency model chosen deliberately (virtual threads on JDK 24+); downstream concurrency bounded by pools/semaphores ([4.4](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md))
- [ ] Security filter chain: stateless JWT validation, method security where needed, inbound rate limits ([4.5](../04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md))
- [ ] Startup measured; AOT cache / CDS considered where startup matters ([1.4 §2](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md))
- [ ] Every `application.yml` key validated against configuration metadata (unknown keys are silently ignored) ([7.5 §0](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md))

## 5. Boundaries and messaging ([Pillar 5](../05-Microservices-Patterns/08-Bar-Raiser-Drill-Downs.md))

- [ ] Module/service boundaries verified by tests (Spring Modulith `verify()` / ArchUnit) ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md))
- [ ] Each service owns its tables; no cross-service DB reads (enforced with roles) ([5.2](../05-Microservices-Patterns/02-Data-Ownership-Database-per-Service.md))
- [ ] Events published via the outbox (polling or CDC); no `send()` inside `@Transactional` ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md))
- [ ] Every consumer is idempotent (dedup row in the same transaction) ([5.4 §4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md))
- [ ] Multi-service flows have a saga with compensations, a pivot, timeouts and a durable log ([5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md))
- [ ] Contracts tested (consumer-driven), events versioned with compatibility rules ([5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md))
- [ ] CDC replication slots monitored (retained WAL, slot lag) ([5.4 §6](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md))

## 6. Resilience ([6.1](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [6.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md))

- [ ] Every outbound call has a client timeout below the breaker's slow-call threshold
- [ ] Breakers sized per pod from real traffic; slow-call thresholds from p99; `maxWaitDurationInHalfOpenState` set
- [ ] Breakers ignore client errors and self-inflicted rejections (`BulkheadFullException`, `RequestNotPermitted`)
- [ ] Retries only on transient errors of idempotent operations; exponential backoff **with jitter**; one retry layer
- [ ] Order is `Retry(CircuitBreaker(…))`; retries ignore `CallNotPermittedException`
- [ ] Bulkheads (semaphores) sized by Little's law and ≤ the pool beneath them
- [ ] Rate limits account for fixed-window bursts and the replica count; `429` + `Retry-After` honored
- [ ] Fallbacks are explicit business decisions, and their usage is a metric
- [ ] Breaker state on dashboards and alerts, **never** in probes

## 7. Caching ([6.3](../06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md), [6.4](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md))

- [ ] A staleness budget written down per cached data type; zero-staleness data never cached
- [ ] Bounded caches (Caffeine `maximumSize`/`maximumWeight`), sized inside the heap budget
- [ ] Single-flight loading (`cache.get(key, loader)` / `@Cacheable(sync = true)`), plus a fleet-wide lease for expensive keys
- [ ] TTL jitter; refresh-ahead for hot keys; negative caching / Bloom filter for unknown ids
- [ ] Invalidation after commit; leases or versioned fills against the stale-fill race
- [ ] Redis: `maxmemory-policy` set (not `noeviction`), command timeouts, breaker, miss bulkhead toward the DB
- [ ] Hit rate alerting (a hit-rate drop is a capacity incident)

## 8. Kafka ([10.1](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md), [10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md))

- [ ] Topics: RF 3, `min.insync.replicas=2`, racks = zones; partitions sized for peak consumer parallelism and fixed up front
- [ ] Keys = ordering domain; skew checked
- [ ] Producers: `acks=all`, idempotence on, `linger.ms`/`batch.size`/compression tuned with real payloads, `max.block.ms` bounded, send failures handled
- [ ] Consumers: `auto.offset.reset` chosen deliberately, container-managed commits, bounded `max.poll.records`, honest `max.poll.interval.ms`
- [ ] Cooperative-sticky or KIP-848 group protocol; dynamic membership on Deployments, static only with StatefulSet ids ([10.4](../10-Kafka-Production/04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md))
- [ ] Error handling: backoff + DLT + non-retryable classification; `ErrorHandlingDeserializer`; ordering decision for blocking vs non-blocking retries
- [ ] DLT alerting, retention and a replay tool
- [ ] Per-partition lag and lag growth alerts; LSO lag if transactions are used

## 9. Container and JVM ([7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md), [7.2](../07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md))

- [ ] Multi-stage build, layered jar (`jarmode=tools extract --layers`), non-root user, distroless or minimal base pinned by digest
- [ ] Exec-form `ENTRYPOINT` (Java is PID 1)
- [ ] Heap sized with headroom for measured non-heap (NMT baseline under load); `MaxDirectMemorySize` set
- [ ] GC chosen explicitly; `ActiveProcessorCount` matches the CPU the pod gets
- [ ] `ExitOnOutOfMemoryError` + heap dump to a volume
- [ ] AOT cache (if used) trained in the runtime image with production GC flags, checked in CI with `-XX:AOTMode=on`

## 10. Kubernetes runtime ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)–[7.5](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md))

- [ ] Startup, liveness and readiness probes on the main port; liveness checks only liveness state; JVM-friendly timeouts
- [ ] Warm-up in `ApplicationRunner`s (before readiness flips)
- [ ] `preStop` sleep; `terminationGracePeriodSeconds` ≥ preStop + drain + consumer shutdown + margin
- [ ] Memory request = limit; CPU policy chosen with throttling data
- [ ] `maxUnavailable: 0`, `minReadySeconds`, PDB, zone and host spread
- [ ] HPA on CPU vs honest requests or on RPS; KEDA for lag-driven consumers, capped at partitions; no memory-based HPA for JVMs
- [ ] SecurityContext: non-root, read-only root FS, capabilities dropped, seccomp; no SA token unless needed; NetworkPolicy
- [ ] Manifests validated against the cluster's schemas and CRDs in CI; `kubectl apply --dry-run=server` before deploy

## 11. Observability and SLOs ([5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md), [9.1 §9](01-Reference-Architecture-End-to-End-Order-Platform.md))

- [ ] SLIs and SLOs per user journey; burn-rate alerts
- [ ] Traces propagate across HTTP **and** Kafka; sampling decided (head vs tail)
- [ ] Structured logs with trace id, business ids (order id) and idempotency keys
- [ ] Dashboards: RED per endpoint, pool wait times, breaker states, cache hit rate, consumer lag, GC pauses vs request latency, CFS throttling
- [ ] Continuous JFR or profiling available in production

## 12. Operability

- [ ] Runbooks for the top five alerts, each with a "first five minutes" section
- [ ] Rollback tested (including schema compatibility with the previous version)
- [ ] Capacity plan with peak-event pre-scaling
- [ ] On-call ownership and escalation documented
- [ ] ADRs recorded for the decisions in [9.1 §12](01-Reference-Architecture-End-to-End-Order-Platform.md)

---

## 13. Game day: break it on purpose before production does

| Experiment | Expected behavior | If it fails, see |
|---|---|---|
| Kill a pod mid-traffic (`kubectl delete pod`) | Zero failed requests; consumers rebalance only the moved partitions | [7.3 §3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md), [10.2 §2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| Force-kill a pod (`--grace-period=0 --force`) | Duplicates possible, no loss; idempotent consumers absorb them | [5.4 §5](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| Rolling deploy under load | No 5xx / connection errors | [7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| Add 2 s latency to a dependency | Breaker opens on slow calls; fallbacks; no pool exhaustion | [6.1 §5.2](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md) |
| Stop one Kafka broker | Producers continue (RF 3, ISR 2); no acknowledged loss | [10.1 §3](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md) |
| Publish a poison message | DLT receives it; alert fires; replay works | [10.2 §4](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) |
| Flush Redis | DB load capped by the miss bulkhead; hit rate recovers | [6.4 §3.2](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |
| Stop the CDC connector for 30 min | Slot lag alert; events delayed, none lost; WAL growth bounded | [5.4 §6](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| Fail over the primary database | Brief write errors, retries, no data loss (synchronous standby) | [2.7](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md) |
| Hold a long transaction for 1 h | Vacuum blocked alert fires before bloat hurts | [2.5](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md) |
| Squeeze the pod's memory limit by 20 % | Either fine (headroom) or an OOMKill you now understand | [7.1 §4](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md) |

---

## 14. The two-minute interview answer

*"How do you know a service is production-ready?"*

> "I check six things. **Correctness under failure**: outbox, idempotent consumers, atomic updates, sagas with compensations. **Overload behavior**: timeouts, breakers, bulkheads, retry budgets, a miss bulkhead for caches. **Capacity**: memory and CPU budgets measured, pools sized from the database, partitions sized for peak. **Deployability**: probes, graceful shutdown, rollback with compatible schemas. **Observability**: SLOs with burn-rate alerts and traces across async hops. And **evidence**: a game day where we killed pods, brokers and Redis and watched the system do what the design says. A checklist without a game day is a hope."

**Back to:** [README](../README.md)
