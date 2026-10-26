# 9.2 Comparison Matrices: Master Sheet

> One place for every "X vs Y" an interviewer can throw at you. Each matrix starts with **the deciding question** (the first-principles constraint that actually separates the options) and links to the section with the evidence. Numbers are from the kit's runs unless a matrix says otherwise. The **B+Tree vs LSM** matrix is the one exception: it was **not measured** in this kit (no LSM engine was run on this machine), so it's built from first principles and cites its sources.

**Contents:** [1 Maven vs Gradle](#1-maven-vs-gradle-) · [2 B+Tree vs LSM](#2-btree-vs-lsm-tree-) · [3 Choreography vs orchestration](#3-saga-choreography-vs-orchestration-) · [4 Optimistic vs pessimistic locking](#4-optimistic-vs-pessimistic-locking-) · [5 G1 vs ZGC in Kubernetes](#5-g1-vs-zgc-in-kubernetes-) · [6 More matrices](#6-more-matrices)

---

## 1. Maven vs Gradle 🔥

**Deciding question:** do you want a **fixed lifecycle** that every project follows, or a **task graph** you program, with finer-grained incrementality?

| Dimension | Maven (3.10 / 4.0) | Gradle (9.8) |
|---|---|---|
| Model | Declarative POM; fixed lifecycle phases; plugins bind mojos to phases ([1.1](../01-Build-Systems/01-Maven-Internals-Lifecycle-Mojos-Reactor.md)) | Programmable build: initialization → configuration → execution of a task DAG ([1.2](../01-Build-Systems/02-Gradle-Internals-Phases-Task-Graph-Caches-Daemon.md)) |
| Version conflict resolution | **Nearest wins** (depth in the tree), then first declaration | **Highest version wins**, with rich constraints and capabilities ([1.3](../01-Build-Systems/03-Dependency-Resolution-Jar-Hell-BOMs-Catalogs-Shading.md)) |
| Central version management | BOM import (`dependencyManagement`, scope `import`) | `platform()` / `enforcedPlatform()` + version catalogs (`libs.versions.toml`) |
| Incrementality | Module level (plus build-cache extension, mvnd) | **Task level**: up-to-date checks, build cache, compile avoidance, configuration cache ("preferred" since 9.0) |
| Reproducibility | Maven 3.10: reproducible builds **on by default** (verified) | Archives reproducible by default (fixed 1980-02-01 timestamps, verified) |
| Extensibility | Write a plugin (Java, mojo API) | Kotlin convention plugins in `build-logic`; anything is possible, including bad ideas |
| Uniformity / onboarding | **Very high**: every Maven project looks alike | Depends on platform discipline |
| Failure modes | Surprising nearest-wins picks; plugin versions drifting without Enforcer | Configuration-time side effects, non-cacheable tasks (verified: `buildInfo` time broke caching downstream) |
| Guardrails | Enforcer (`dependencyConvergence`, `requireUpperBoundDeps`, banned deps, plugin pinning) | Dependency verification, `failOnVersionConflict`, convention plugins |
| Best fit | Many teams, low build expertise, "boring is good" | Large monorepos with a build-platform team, heavy caching needs, Android/Kotlin |

Evidence and drill-downs: [1.4 blueprints](../01-Build-Systems/04-Enterprise-Builds-OCI-Images-Annotation-Processors-Enforcer.md), [1.5 drill 4](../01-Build-Systems/05-Bar-Raiser-Drill-Downs.md).

---

## 2. B+Tree vs LSM-Tree 🔥

**Deciding question:** do you update data **in place** (pay random I/O on writes to keep reads cheap) or **append and merge later** (pay background compaction and extra read work to make writes sequential)?

### 2.1 First principles

* A **B+Tree** keeps keys sorted in fixed-size pages (8 KB in PostgreSQL, 16 KB in InnoDB). An insert or update **finds the page and modifies it**, splitting pages when full. Reads are ~log_fanout(N) page visits (3–4 for billions of rows with fanout in the hundreds). Writes touch random pages and log every change in the WAL/redo log ([2.1](../02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md), [2.2](../02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md)).
* An **LSM-tree** (Log-Structured Merge) buffers writes in an in-memory sorted structure (**memtable**) plus a write-ahead log. When full, the memtable is flushed as an immutable sorted file (**SSTable**). Background **compaction** merges SSTables into larger levels, dropping overwritten and deleted (tombstoned) entries. A read checks the memtable, then SSTables from newest to oldest, using **Bloom filters** to skip files that can't contain the key ([6.4 §2.2](../06-Resilience-Caching-Kafka/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) has the Bloom filter math).
* The **RUM conjecture**: you can optimize two of **R**ead overhead, **U**pdate overhead and **M**emory/space overhead, never all three. B+Trees favor reads; LSMs favor updates and (with compaction) space.

### 2.2 Matrix

| Dimension | B+Tree (PostgreSQL, InnoDB, most RDBMS) | LSM-Tree (RocksDB, Cassandra, ScyllaDB, HBase, LevelDB; MyRocks for MySQL) |
|---|---|---|
| Write path | Find the page, modify in place (random I/O), WAL record | Append to WAL + memtable (sequential); flush to SSTables later |
| Write amplification | Page-sized writes for small changes, full-page images after checkpoints ([2.1](../02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md)) | Each byte rewritten once per compaction level; leveled compaction typically rewrites data many times over its life |
| Read path (point) | One root-to-leaf descent; usually cached upper levels | Memtable + possibly several SSTables; Bloom filters cut most misses |
| Read amplification | Low and predictable | Higher, and grows with the number of levels/files; depends on compaction health |
| Range scans | Excellent: leaves are sorted and linked | Good, but must merge iterators across levels |
| Space amplification | Page fill factor, fragmentation; MVCC bloat in PostgreSQL ([2.5](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md)) | Obsolete versions and tombstones until compaction; leveled compaction keeps it modest, size-tiered can temporarily double it |
| Background work | VACUUM (PostgreSQL) / purge (InnoDB), checkpoints | **Compaction**: competes for I/O and CPU; when it falls behind, writes stall |
| Tail latency risk | Page splits, checkpoint spikes, vacuum | Compaction debt, write stalls, tombstone-heavy reads |
| Deletes | Mark/remove in place (plus MVCC cleanup) | Tombstones, which reads must skip until compaction drops them |
| SSD friendliness | Random small writes | Large sequential writes, lower device write amplification |
| Transactions / secondary indexes | Mature (full ACID, many index types) | Engine-dependent; secondary indexes often costlier or eventual |
| Pick it when | Read-heavy or mixed OLTP, rich queries, joins, strong transactions | Write-heavy ingestion (events, time series, metrics, logs), huge key-value datasets, wide-column models |

### 2.3 Nuances worth saying

* PostgreSQL is a hybrid: its **heap** handles updates out of place (new tuple versions, cleaned by VACUUM), while its **indexes** are B-trees updated in place (unless a HOT update avoids touching them).
* A UUIDv4 primary key gives a B+Tree random inserts across the whole index. The kit measured the effect versus time-ordered UUIDv7 in [2.2](../02-SQL-RDBMS-Internals/02-Indexes-BTree-Hash-GIN-GiST-BRIN-Covering-Composite.md). LSMs don't mind random keys on write, but pay on reads and compaction.
* Kafka is **not** an LSM: it's an append-only log without merge or key-sorted files (compacted topics keep the latest value per key, which is related in spirit).

**Sources (not measured here):** O'Neil, Cheng, Gawlick, O'Neil, *The Log-Structured Merge-Tree* (Acta Informatica, 1996); Athanassoulis et al., *Designing Access Methods: The RUM Conjecture* (EDBT 2016); the [RocksDB wiki](https://github.com/facebook/rocksdb/wiki) (compaction and tuning pages); Kleppmann, *Designing Data-Intensive Applications*, chapter 3.

---

## 3. Saga choreography vs orchestration 🔥

**Deciding question:** where does the **control flow** live, and who can answer "where is order 42 right now?"

| | Choreography | Orchestration |
|---|---|---|
| Control flow | Implicit, spread across services' event subscriptions | Explicit, in one place (code, DSL or BPMN) |
| Coupling | Services know event types, not each other | The orchestrator knows every participant's commands |
| Visibility | Reconstruct from events/traces | Query the saga state |
| Adding a step | Touch several services | Change the orchestrator |
| Failure handling | Each service compensates on failure events it hears | Centralized compensation in reverse order (verified in [5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)) |
| Risks | Cyclic event chains, "event spaghetti" | A god-service orchestrator if it absorbs business logic |
| Testing | End-to-end across services | Orchestrator unit-testable with stubbed participants |
| Good fit | 2–4 linear steps, high autonomy | 4+ steps, branching, timeouts, a pivot, regulated processes (FTGO's `CreateOrderSaga`, [8.3](../08-GitHub-Codebases-Study-Guide/03-Saga-Outbox-Event-Driven-Repos.md)) |

Common hybrid: choreography *between* bounded contexts, orchestration *within* one complex business process ([9.1 §4](01-Reference-Architecture-End-to-End-Order-Platform.md)).

---

## 4. Optimistic vs pessimistic locking 🔥

**Deciding question:** is a conflict **rare** (detect it at the end and retry) or **likely** (prevent it up front by waiting)?

| Dimension | Optimistic (`@Version`, `WHERE version = ?`) | Pessimistic (`SELECT … FOR UPDATE`, `@Lock(PESSIMISTIC_WRITE)`) | Atomic conditional update (`SET x = x - ? WHERE x >= ?`) |
|---|---|---|---|
| Mechanism | Read without locks; the write checks the version; 0 rows updated = conflict (verified: second writer got `UPDATE 0`, [2.6 §1.5](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)) | Lock rows at read time; others wait | The database checks and modifies in one statement |
| Under low contention | Fastest: no locks held | Pays lock overhead for nothing | Fast |
| Under high contention | **Retry storms**, wasted work | Queueing (predictable), risk of deadlocks | Serializes on the row, no retries needed |
| Across HTTP requests (user think time) | **Yes**: version travels with the form/ETag | No: you can't hold a DB lock for minutes | n/a |
| Deadlocks | None | Possible; lock in a consistent order, use timeouts | Possible across multiple rows |
| Failure surfaced as | `OptimisticLockException` → retry or ask the user | Lock wait / `NOWAIT` error / deadlock victim | 0 rows → business failure ("insufficient stock") |
| Variants | ETag + `If-Match` over HTTP; CAS in Redis/DynamoDB | `NOWAIT`, `SKIP LOCKED` for work queues | — |
| Best for | Edits with think time, low conflict rates | Short critical sections with complex logic under contention | Counters, balances, stock reservations ([9.1 §4.3](01-Reference-Architecture-End-to-End-Order-Platform.md)) |

Rule of thumb: **prefer the atomic update** whenever the change can be expressed in one statement; then optimistic; pessimistic only for short, contended, multi-step logic. And remember that retries must wrap the **whole transaction** ([3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md)).

---

## 5. G1 vs ZGC in Kubernetes 🔥

**Deciding question:** is your latency target dominated by **GC pauses**, and do you have the **spare CPU and heap** that a concurrent collector needs?

| Dimension | G1 (default with ≥ 2 CPUs) | ZGC (generational; the non-generational mode was removed in JDK 24) |
|---|---|---|
| Pause behavior | Short stop-the-world young/mixed pauses; target via `MaxGCPauseMillis` (default 200 ms) | Sub-millisecond pauses; marking and relocation run concurrently |
| Verified on 2 pinned CPUs, 512 MB heap ([7.4 §2.1](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)) | 424 pauses, 2,095 ms total; app stalls p99 **23 ms**, max **25 ms**; lowest throughput | 4,221 pauses, **20 ms total**; app stalls p99 **17 ms**, but max **69 ms** |
| CPU needs | Moderate; bursty during pauses | Needs **headroom**: concurrent threads compete with the app on small pods |
| Heap headroom | Works well near full | Needs free heap so allocation doesn't outrun collection (allocation stalls) |
| Native memory | Remembered sets etc. (NMT: 55 MB "GC" at a 256 MB heap, [7.1 §3](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)) | Multi-mapping, colored pointers; plan memory explicitly |
| Compressed oops | Yes (heaps < 32 GB) | **No**: so an AOT cache trained with G1 is **rejected** under ZGC (verified, [7.2 §4.3](../07-Docker-JVM-Kubernetes/02-Dockerfiles-Multistage-Distroless-Layers-Buildpacks-Jib.md)) |
| CFS throttling sensitivity | Parallel pause bursts can exhaust a CPU quota | Continuous concurrent work spreads CPU use but needs quota headroom |
| Key knobs | `MaxGCPauseMillis`, `G1HeapRegionSize`, `InitiatingHeapOccupancyPercent` | `SoftMaxHeapSize`, heap size; few others |
| Pod sweet spot | 2–8 CPUs, heaps from hundreds of MB to tens of GB | Latency-critical services with ≥ 4 CPUs and multi-GB heaps |
| Avoid when | Strict sub-10 ms tail requirements at large heaps | 1–2 CPU pods with tight heaps (stalls show up anyway) |

Also: at **1 CPU** the JVM picks **SerialGC** by default (verified, [7.1 §2.2](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)). Set the collector explicitly, and judge by **request latency**, not GC logs.

---

## 6. More matrices

### 6.1 PostgreSQL vs MySQL InnoDB (storage and MVCC)

| | PostgreSQL | InnoDB |
|---|---|---|
| Table storage | Heap; all indexes secondary (point to `ctid`) | Clustered by primary key; secondary indexes store the PK |
| UPDATE | New tuple version (HOT if possible) | In place + undo record |
| Old versions | In the table → VACUUM | In undo logs → purge |
| Rollback | Cheap | Expensive (apply undo) |
| Random UUID PK | Hurts the PK index | Fragments **the table itself** |
| XID wraparound | Yes (32-bit, freezing) | No (48-bit) |
| Default isolation | READ COMMITTED | REPEATABLE READ (with gap/next-key locks) |

From [2.1 §5](../02-SQL-RDBMS-Internals/01-Storage-Pages-Tuples-TOAST-WAL.md), [2.5 §4.3](../02-SQL-RDBMS-Internals/05-MVCC-Visibility-Vacuum-Wraparound-vs-InnoDB-Undo.md), [2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md).

### 6.2 Pagination: `OFFSET` vs keyset ([2.4 §2](../02-SQL-RDBMS-Internals/04-Advanced-SQL-CTEs-Window-Functions-Keyset-Pagination.md))

| | `OFFSET 500000` | Keyset (`WHERE (created_at, id) < (?, ?)`) |
|---|---|---|
| Rows produced (verified) | 500,020 | 20 |
| Buffers | 16,615 | 5 |
| Time (one run) | 139.9 ms | 0.02 ms |
| Jump to page N | Yes | No (next/previous only) |
| Stable under inserts | No (rows shift) | Yes |

### 6.3 Fixing N+1 ([3.3 §2](../03-JPA-Hibernate-Spring-Data/03-NPlus1-Lazy-Loading-Fetch-Plans-Pagination-Projections.md))

| Fix | Queries | Row duplication | Pagination-safe | Best for |
|---|---|---|---|---|
| `JOIN FETCH` / entity graph | 1 | Yes | Careful (Hibernate 7.4 behavior in 3.3 §4) | One collection, small result |
| Batch fetching | 1 + ⌈N/batch⌉ | No | Yes | Default safety net |
| Separate query per collection | 1 + per collection | No | Yes | Several collections |
| DTO projection | 1 | Controlled | Yes | Read-only views and APIs |

### 6.4 ID generation and write throughput ([3.4](../03-JPA-Hibernate-Spring-Data/04-Write-Throughput-Batching-Sequences-Hybrid-JDBC-jOOQ.md))

| Variant | Speed vs `IDENTITY` (verified) | Why |
|---|---|---|
| `IDENTITY` | 1× | One round trip per row; batching disabled |
| `SEQUENCE` + batching (pooled-lo) | 5.2–6.5× | Batched inserts, few `nextval` calls |
| `StatelessSession` | 8–11× | No persistence-context work |
| JDBC batches of 1,000 + rewrite | 14–24× | Multi-row `INSERT` |
| `COPY` | ~75× | Streaming bulk load |

### 6.5 Proxies: JDK vs CGLIB ([4.3](../04-Spring-Boot-Internals/03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md))

| | JDK dynamic proxy | CGLIB |
|---|---|---|
| Mechanism | Implements the interfaces | Subclasses the class |
| Requires | An interface | Non-final class and methods |
| Boot default | — | `proxy-target-class=true` |
| Not intercepted | Self-invocation | Self-invocation, `final`/`private` methods (verified) |

### 6.6 Web concurrency: platform threads vs virtual threads vs WebFlux ([4.4](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md))

| Mode (100 ms blocking work, 400 concurrent clients) | Throughput (verified) | p50 | Ceiling |
|---|---|---|---|
| Platform threads, max 50 | 481 req/s | 816 ms | Thread pool (Little's law) |
| Virtual threads | 3,098 req/s | 108 ms | Downstream resources (the DB pool becomes the queue) |
| WebFlux, non-blocking | 2,959 req/s | 105 ms | CPU, if nothing blocks |
| WebFlux with a blocking call | 108 req/s, 92 % failed | 1,494 ms | Blocked event loops |

### 6.7 Outbox relay: polling vs CDC ([5.4 §7](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md))

| | Polling publisher (`SKIP LOCKED`) | Log tailing (Debezium) |
|---|---|---|
| Infrastructure | App + DB | Connect/Debezium + replication slot |
| Latency | Poll interval | Sub-second |
| DB load | Polling queries + updates (bloat) | Reads WAL, no extra writes |
| Ordering | Per relay; multiple relays can reorder an aggregate's events | WAL commit order |
| Failure mode | Events wait (safe) | Connector down → **WAL retention grows** |
| Fit | Most services | High volume, platform-run CDC |

### 6.8 Resilience primitives ([6.1](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [6.2](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md))

| Primitive | Limits | Protects | Key trap |
|---|---|---|---|
| Circuit breaker | Calls to a sick dependency | Caller capacity | Defaults (min calls 100, slow threshold 60 s); half-open with no timeout |
| Bulkhead | Concurrency | Caller resources | Larger than the pool beneath it |
| Rate limiter | Rate | Callee / quota | `AtomicRateLimiter` is a fixed window: 2× burst at boundaries (verified) |
| Retry | Nothing (adds load) | Success rate on transient faults | Non-idempotent calls, no jitter, retries at every layer |
| Time limiter | Latency | Caller wait | Doesn't stop blocking work without client timeouts |

| Window | Count-based | Time-based |
|---|---|---|
| Covers | Last N calls | Last N seconds |
| Coverage in time | Varies with traffic | Fixed |
| Fit | Steady, predictable traffic | Variable traffic, per-pod sizing |

### 6.9 Rate-limiting algorithms ([6.2 §2.2](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md))

| Algorithm | Burst behavior | Where |
|---|---|---|
| Fixed window | Up to 2× at boundaries | Resilience4j `AtomicRateLimiter`, `INCR`+`EXPIRE` |
| Sliding window log | Exact | Small limits |
| Sliding window counter | Approximate, smooth | Gateways |
| Token bucket | Bucket-size bursts, then refill rate | Bucket4j, Spring Cloud Gateway (Redis) |
| GCRA / leaky bucket | Smooth | NGINX `limit_req`, redis-cell |

### 6.10 Caching ([6.3](../06-Resilience-Caching-Kafka/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md), [6.4](../06-Resilience-Caching-Kafka/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md))

| Eviction | LRU | W-TinyLFU (Caffeine) |
|---|---|---|
| Admission | Everything | Only if more frequent than the victim |
| Scan resistance | None | Strong |
| Verified hit rate (Zipf + scans, size 1,000) | 29.7 % | 38.5 % |

| Pattern | Who loads | Write path | Main risk |
|---|---|---|---|
| Cache-aside | App | DB, then delete key | Stale-fill race (fix: leases, verified) |
| Read-through | Cache loader | Same | Same |
| Write-through | App/cache | Cache + DB synchronously | Partial failure |
| Write-behind | Cache | Async flush | Data loss |
| Refresh-ahead | Cache | Any | Wasted reloads |

| Local L1 (Caffeine) | Remote L2 (Redis) |
|---|---|
| ~100 ns, per pod, no network | Network hop, shared across pods |
| Inconsistent across pods (needs invalidation) | One copy (still stale vs the DB) |
| Shields L2 and hot keys | Survives pod restarts |

### 6.11 Kafka ([6.5](../06-Resilience-Caching-Kafka/05-Kafka-Producers-Batching-Idempotence-Ordering.md), [6.6](../06-Resilience-Caching-Kafka/06-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md))

| Delivery semantics | How | Cost |
|---|---|---|
| At-most-once | Commit, then process | Loss |
| At-least-once | Process, then commit | Duplicates → idempotent consumers |
| Exactly-once (Kafka→Kafka) | Transactions + `read_committed` | Latency; LSO stalls on open transactions |
| Exactly-once *effects* (Kafka→DB) | At-least-once + dedup row in the same DB tx | A dedup table |

| Rebalance protocol | Revokes | Barrier | Verified with one joiner |
|---|---|---|---|
| Eager (Range) | All partitions of all members | Group-wide | Revoked 6 to move 3 |
| Cooperative-sticky | Only moving partitions | Two rounds | Revoked 3; old member kept 0–2 |
| KIP-848 | Only moving partitions | None (heartbeat reconciliation) | Revoked 3; no barrier |

| Retry style | Order | Throughput | Verified |
|---|---|---|---|
| Blocking (`DefaultErrorHandler`) | Preserved | Partition stalls | `next-1` waited ~3.7 s |
| Non-blocking (`@RetryableTopic`) | Broken per key | Flows | `next-1` overtook the poison pill at 731 ms |

### 6.12 Containers and Kubernetes ([Pillar 7](../07-Docker-JVM-Kubernetes/06-Bar-Raiser-Drill-Downs.md))

| Image build | Dockerfile + `jarmode=tools` | Buildpacks | Jib |
|---|---|---|---|
| Daemon needed | Yes | Yes | No |
| Non-root by default | If you write it | Yes | No (verified `User: None`) |
| Control | Total | Opinionated | Medium |

| Probe | Answers | Action on failure | Must not check |
|---|---|---|---|
| Startup | Finished starting? | Wait, then restart | — |
| Liveness | Alive? | Restart | Dependencies |
| Readiness | Take traffic now? | Remove from endpoints | Shared dependencies |

| CPU policy | Pros | Cons |
|---|---|---|
| Limit = request | Predictable | CFS throttling on bursts |
| Request only + `ActiveProcessorCount` | Bursts use idle CPU | Noisy neighbors |
| Exclusive cores (static CPU manager) | Lowest jitter | Wasted capacity |

| Autoscaler | Signal | Can scale to zero | JVM caveat |
|---|---|---|---|
| HPA | CPU/memory vs **requests**, custom metrics | No | Startup CPU spikes; never on memory |
| KEDA | Lag, queue depth, Prometheus | Yes | Capped by partitions; each scale event is a rebalance |

**Next:** [9.3 Mock interview loops, L5 vs L6 →](03-Mock-Interview-Loops-L5-vs-L6.md)
