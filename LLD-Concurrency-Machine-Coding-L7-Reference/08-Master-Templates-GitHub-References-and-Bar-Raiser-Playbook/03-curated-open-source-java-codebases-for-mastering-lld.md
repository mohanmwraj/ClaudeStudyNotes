# 08.3 · Curated Open-Source Codebases for Mastering LLD and Concurrency (Java and C++)

> **Folder 08 · File 3 of 3.** The twenty problems in this KB are small versions of real systems. The fastest way to reach the L7 bar is to read how production code solves the same problems:
> - Caffeine for P1;
> - the Disruptor for P12 and P17;
> - HikariCP for P5;
> - H2's MVStore for P16;
> - folly's `SharedMutex` for 07.1.
>
> Each entry names **what to read**, **the lesson**, and **which KB files** it deepens. Links go to the repositories; the class and file names are what to search for inside them.

---

## 1. How to read a concurrent codebase

1. **Start from the tests.** They show the intended semantics, and concurrency tests reveal which races the authors worried about.
2. **Trace one operation end to end** (one `get`, one `publish`, one `acquire`). Write down every shared field it touches.
3. **For each shared field, name its atomicity unit and its guard:** lock, CAS, single writer or immutability. That is the exercise this KB does in every "Concurrency and contention analysis" section.
4. **Find the slow path.** Production code is usually a fast path, plus a rare fallback that is correct but slow (Caffeine's drain, P15's collapse).
5. **Compare with the KB listing.** What did they do that the 300-line version skips: padding, pooling, back-pressure, metrics?

## 2. Java

| Repository | Read | Lesson | KB |
|---|---|---|---|
| [OpenJDK](https://github.com/openjdk/jdk) | `java.util.concurrent`: `AbstractQueuedSynchronizer`, `ConcurrentHashMap`, `StampedLock`, `CompletableFuture`, `ForkJoinPool` (under `src/java.base/share/classes/java/util/concurrent`) | One state word + a CLH-style queue builds every lock; CHM's per-bin locking and resize protocol; optimistic reads | [01.3](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md), [07.1](../07-Classic-Multithreading-Synchronization-Bar-Raisers/01-read-write-lock-with-writer-preference-and-custom-aqs-synchronizer.md), [07.3](../07-Classic-Multithreading-Synchronization-Bar-Raisers/03-parallel-dag-task-executor-with-completablefuture-and-virtual-threads.md) |
| [Caffeine](https://github.com/ben-manes/caffeine) | `BoundedLocalCache`, `FrequencySketch`, `BoundedBuffer` / `StripedBuffer`, `TimerWheel` | Data plane vs policy plane: lossy read buffers drained under a try-lock; W-TinyLFU admission; hierarchical expiry wheel | [P1](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/01-problem-01-thread-safe-lru-and-lfu-ttl-cache-caffeine-architecture.md), [P3](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/03-problem-03-delayed-job-scheduler-and-hierarchical-timing-wheel.md) |
| [LMAX Disruptor](https://github.com/LMAX-Exchange/disruptor) | `RingBuffer`, `MultiProducerSequencer`, `SequenceBarrier`, the wait strategies | Preallocated entries, sequence claiming, cache-line padding, batching consumers, wait-strategy trade-offs | [P12](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/02-problem-12-stock-exchange-limit-order-book-price-time-matching-engine.md), [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) |
| [JCTools](https://github.com/JCTools/JCTools) | `MpscArrayQueue`, `SpscArrayQueue`, the padding superclass chain | Specialized queues per producer/consumer count; field-layout tricks against false sharing | [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md), [01.3](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) |
| [Agrona](https://github.com/real-logic/agrona) | `Long2ObjectHashMap`, `ManyToOneRingBuffer`, `IdleStrategy` | Primitive-keyed collections (no boxing on the hot path); off-heap rings; backoff policies | [P12](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/02-problem-12-stock-exchange-limit-order-book-price-time-matching-engine.md) |
| [Netty](https://github.com/netty/netty) | `HashedWheelTimer`, `SingleThreadEventExecutor`, `Recycler` | The timing wheel in production; one event loop per channel (single writer); object pooling | [P3](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/03-problem-03-delayed-job-scheduler-and-hierarchical-timing-wheel.md), [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) |
| [HikariCP](https://github.com/brettwooldridge/HikariCP) | `ConcurrentBag`, `HikariPool` | A connection pool whose borrow path is mostly lock-free (thread-local list first, then shared, then a hand-off queue) | [P5](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/05-problem-05-bounded-blocking-connection-pool-and-circuit-breaker.md) |
| [Resilience4j](https://github.com/resilience4j/resilience4j) | `CircuitBreakerStateMachine`, the sliding-window metrics, `Bulkhead` | Breaker states as an atomic state machine; count- and time-based windows | [P5](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/05-problem-05-bounded-blocking-connection-pool-and-circuit-breaker.md) |
| [Guava](https://github.com/google/guava) | `Striped`, `SmoothRateLimiter`, `Monitor` | Lock striping as a reusable type; token-bucket arithmetic with warm-up | [P2](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/02-problem-02-pluggable-rate-limiter-token-bucket-sliding-window-cas.md), [P15](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/05-problem-15-ecommerce-flash-sale-inventory-reservation-and-cart-rules.md) |
| [Apache Kafka](https://github.com/apache/kafka) | Log segments and indexes, the purgatory timing wheel, the group coordinator | Append-only logs with offset indexes; generation-fenced group membership; delayed operations | [P4](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/04-problem-04-in-memory-kafka-pubsub-broker-offset-tracking-and-groups.md), [P3](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/03-problem-03-delayed-job-scheduler-and-hierarchical-timing-wheel.md) |
| [H2 Database](https://github.com/h2database/h2database) | `MVStore`, `MVMap`, the transaction store | Copy-on-write B-tree pages, MVCC, a real query planner over secondary indexes | [P16](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/01-problem-16-in-memory-relational-database-indexes-where-dsl-and-mvcc.md) |
| [Apache Log4j 2](https://github.com/apache/logging-log4j2) | `AsyncLoggerDisruptor`, `RingBufferLogEvent`, the garbage-free layouts, `ThreadContext` | Pooled events in a ring; per-level overflow policies; MDC maps and their copy semantics | [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) |
| [Chronicle Queue](https://github.com/OpenHFT/Chronicle-Queue) | Appenders and tailers over memory-mapped files | A journal that survives process death; a sequenced log as the system of record | [P12](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/02-problem-12-stock-exchange-limit-order-book-price-time-matching-engine.md), [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) |
| [Temporal Java SDK](https://github.com/temporalio/sdk-java) | The workflow worker, deterministic replay, activity retries | Durable execution: a history of events replayed to rebuild state; retries and timeouts as policy | [P20](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/05-problem-20-dynamic-rule-engine-and-json-Workflow-state-orchestrator.md) |

## 3. C++

| Repository | Read | Lesson | KB |
|---|---|---|---|
| [folly](https://github.com/facebook/folly) | `folly/SharedMutex.h`, `folly/MPMCQueue.h`, `folly/concurrency/ConcurrentHashMap.h`, `folly/synchronization/Hazptr.h` | A writer-priority RW lock with an inline fast path; turn-based MPMC; hazard-pointer reclamation | [07.1](../07-Classic-Multithreading-Synchronization-Bar-Raisers/01-read-write-lock-with-writer-preference-and-custom-aqs-synchronizer.md), [P4](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/04-problem-04-in-memory-kafka-pubsub-broker-offset-tracking-and-groups.md) |
| [Abseil](https://github.com/abseil/abseil-cpp) | `absl/synchronization/mutex.h` (`Mutex::Await`, `Condition`), `absl/container/flat_hash_map.h` | A mutex with declarative conditions (no lost wake-ups by construction); Swiss-table hashing | [07.2](../07-Classic-Multithreading-Synchronization-Bar-Raisers/02-dining-philosophers-unisex-bathroom-h2o-and-fizzbuzz-barriers.md), [P16](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/01-problem-16-in-memory-relational-database-indexes-where-dsl-and-mvcc.md) |
| [moodycamel::ConcurrentQueue](https://github.com/cameron314/concurrentqueue) | `concurrentqueue.h`, `blockingconcurrentqueue.h` | MPMC built from per-producer sub-queues: contention avoided by structure, not by a better CAS | [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) |
| [libcds](https://github.com/khizmax/libcds) | The intrusive containers, the `gc` namespace (hazard pointers, epoch-based reclamation) | Safe memory reclamation is the hard half of lock-free C++ | [P4](../03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/04-problem-04-in-memory-kafka-pubsub-broker-offset-tracking-and-groups.md) |
| [spdlog](https://github.com/gabime/spdlog) | `async_logger`, `details/thread_pool.h`, `async_overflow_policy` (block vs overrun-oldest) | P17's BLOCK/DROP decision as a shipped API; a bounded MPMC queue in front of sinks | [P17](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/02-problem-17-async-logging-framework-ring-buffer-appenders-and-mdc.md) |
| [Seastar](https://github.com/scylladb/seastar) | The reactor, `smp::submit_to`, futures and continuations | Shard-per-core share-nothing: no locks at all, message passing between cores | [P12](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/02-problem-12-stock-exchange-limit-order-book-price-time-matching-engine.md), [07.3](../07-Classic-Multithreading-Synchronization-Bar-Raisers/03-parallel-dag-task-executor-with-completablefuture-and-virtual-threads.md) |
| [oneTBB](https://github.com/uxlfoundation/oneTBB) | `flow_graph`, `task_arena`, `concurrent_hash_map` | DAG execution with dependency counting and work stealing as a library | [07.3](../07-Classic-Multithreading-Synchronization-Bar-Raisers/03-parallel-dag-task-executor-with-completablefuture-and-virtual-threads.md), [P20](../06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/05-problem-20-dynamic-rule-engine-and-json-Workflow-state-orchestrator.md) |
| [Asio](https://github.com/chriskohlhoff/asio) | Executors, `strand`, timers | A strand serializes handlers without a lock: the single-writer idea as a reusable executor | [P12](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/02-problem-12-stock-exchange-limit-order-book-price-time-matching-engine.md), [P14](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/04-problem-14-vending-machine-and-atm-dispense-chain-and-state-rollback.md) |
| [cppcoro](https://github.com/lewissbaker/cppcoro) | `task`, `when_all`, `async_mutex`, `static_thread_pool` | Building blocks for coroutine concurrency (what 07.3's single-thread loop grows into) | [07.3](../07-Classic-Multithreading-Synchronization-Bar-Raisers/03-parallel-dag-task-executor-with-completablefuture-and-virtual-threads.md) |

## 4. A four-week reading plan

| Week | Java | C++ | Do this |
|---|---|---|---|
| 1 | AQS, `ConcurrentHashMap` (OpenJDK) | `absl::Mutex`, `folly::SharedMutex` | Re-implement 07.1 using what you learned; compare writer wait under the same flood |
| 2 | Caffeine | moodycamel / spdlog | Add a lossy read buffer to P1; add an overrun-oldest policy to P17 and measure |
| 3 | Disruptor, JCTools, Agrona | Seastar / Asio strands | Pad P12's ring cells; replace boxed keys; compare ns per command |
| 4 | H2 MVStore, Temporal SDK | oneTBB flow graph | Add vacuum to P16; add replay-based recovery to P20 |

## 5. Checklist

- [ ] For each codebase: one operation traced, shared fields listed with their guards.
- [ ] Fast path vs slow path identified.
- [ ] One technique ported back into a KB listing and measured with its harness.

## 6. References

- Ben Manes, *Design of a Modern Cache* (Caffeine's architecture), on the Caffeine wiki. <https://github.com/ben-manes/caffeine/wiki/Design>
- Martin Thompson et al., *Disruptor: High performance alternative to bounded queues* (technical paper). <https://lmax-exchange.github.io/disruptor/disruptor.html>
- In this KB: [08.1 Blueprint](01-60-minute-machine-coding-execution-blueprint-and-code-skeletons.md) · [08.2 Requirement changes](02-25-lld-bar-raiser-requirement-changes-and-refactoring-defenses.md)
