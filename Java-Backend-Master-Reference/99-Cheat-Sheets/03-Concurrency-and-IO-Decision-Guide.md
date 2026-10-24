# 99.3 · Concurrency & I/O Decision Guide (one page)

> "Which construct do I use?" Answers backed by the measurements in Pillars 2–4. Follow the links for the evidence.

---

## 1. Shared state

| You need… | Use | Not | Why (measured) |
|---|---|---|---|
| A counter hammered by many threads | `LongAdder` | `AtomicLong`, `synchronized` | 8 threads: 711M vs 81M vs 30M ops/s ([3.3](../03-Concurrency-Loom/03-Lock-Free-CAS-Atomics.md#32-measured-scaling-opss-all-threads-hammering-one-counter)) |
| Unique IDs / exact current value | `AtomicLong.getAndIncrement` | `LongAdder` | `sum()` isn't a snapshot |
| A flag read in a loop by another thread | `volatile` / `AtomicBoolean` (better: interrupts) | Plain field | JIT hoisting hung the loop forever ([3.1](../03-Concurrency-Loom/01-Java-Memory-Model.md#3-demo-1--visibility-the-loop-that-never-ends-)) |
| Publish an immutable object | `final` fields, a `volatile` reference, or a concurrent collection | Plain field | Partially constructed objects on ARM |
| A concurrent map | `ConcurrentHashMap` (`compute*`/`merge`; short functions) | `synchronizedMap`, a shared `HashMap` | Check-then-act races: 449 duplicates measured ([3.5](../03-Concurrency-Loom/05-Concurrent-Collections-Synchronizers-ThreadLocal.md#23-collectionssynchronizedx-and-vectorhashtable)) |
| A read-mostly snapshot (config, routes) | Immutable object in an `AtomicReference`/`volatile`; `CopyOnWriteArrayList` for small lists | `ReentrantReadWriteLock` for tiny sections | COW writes are O(n): 336 ms for 50k adds |
| A sorted concurrent map | `ConcurrentSkipListMap` | Locks around `TreeMap` | Lock-free, O(log n) |
| Request-scoped context | `ScopedValue` (JDK 25) | `ThreadLocal` without `remove()` | Measured tenant bleed on pooled threads ([3.5 §4.2](../03-Concurrency-Loom/05-Concurrent-Collections-Synchronizers-ThreadLocal.md#42-runnable-context-bleeding-between-pooled-tasks-the-mdc-bug)) |

## 2. Mutual exclusion

| Situation | Use |
|---|---|
| Simple critical section | `synchronized` (JDK 24+: no VT pinning) |
| Need `tryLock`, timeouts, interruptible acquire, or multiple conditions | `ReentrantLock` (non-fair! fair was ~230× slower) |
| Long reads, rare writes, reentrancy | `ReentrantReadWriteLock` (never upgrade read→write) |
| Tiny, very hot reads; rare writes | `StampedLock` optimistic read (~470× the RW-lock read throughput measured) |
| Bounding concurrency to a resource | `Semaphore` / bulkhead |
| Waiting for N events | `CountDownLatch` (one-shot), `Phaser` (dynamic) |
| N threads in lock-step | `CyclicBarrier` |

## 3. Executing work

| Work type | Use | Avoid |
|---|---|---|
| Blocking I/O, request/response (DB, HTTP, files on Linux) | **Virtual threads** (`newVirtualThreadPerTaskExecutor`, Spring `spring.threads.virtual.enabled`) plus per-resource semaphores | Big platform pools as implicit limits |
| Fan-out of a request to N services | `StructuredTaskScope` (preview) or a VT executor + `invokeAll`; `Gatherers.mapConcurrent` in streams | `parallelStream()`; `CompletableFuture.anyOf` without cancellation |
| CPU-bound parallel computation | Bounded platform `ThreadPoolExecutor`, `ForkJoinPool`/`RecursiveTask`, parallel streams **in batch jobs** | Virtual threads (no time slicing: 507 ms delay measured) |
| Scheduled / periodic | `ScheduledThreadPoolExecutor` with try/catch in the task, or a scheduler framework | Uncaught exceptions (silently cancel all future runs) |
| Callback-style integration (async APIs) | `CompletableFuture` with explicit executors | Default commonPool for blocking stages |
| Streams of events with backpressure | Reactor/RxJava/Kafka consumers, or bounded `BlockingQueue` pipelines | Unbounded queues |

**Pool construction checklist:** explicit `ThreadPoolExecutor`, **bounded** queue, named threads, an explicit rejection policy (no silent discard), metrics, shutdown on application stop.

## 4. I/O model

| Situation | Use |
|---|---|
| A typical REST/JSON service (JDK 21+) | Spring MVC / plain servers on **virtual threads** with blocking clients |
| A gateway/proxy, a custom binary protocol, 100k+ mostly idle connections | **Netty** (event loops, pooled buffers, zero-copy) |
| Large static file delivery (plaintext) | `FileChannel.transferTo` / Netty `FileRegion` (sendfile on Linux; measure on your OS) |
| Random access to huge files | FFM `FileChannel.map(…, Arena)` → `MemorySegment` |
| Big JSON payloads | Jackson streaming (`JsonParser`), `InputStream` body handlers |
| Local IPC with a sidecar | Unix-domain sockets (JEP 380) |

## 5. Serialization

| Situation | Use | Never |
|---|---|---|
| Public API | JSON (Jackson; set strictness explicitly, especially on Jackson 3) | Java serialization |
| Internal RPC | Protobuf + gRPC | Reusing Protobuf field numbers |
| Kafka/data platform events | Avro (+ schema registry) or Protobuf | Untyped JSON blobs without schemas |
| Ultra-low-latency messaging | SBE / FlatBuffers / Chronicle Wire | Reflection-heavy mappers in the hot path |
| Untrusted input with Java serialization (legacy) | JEP 290 allow-list filter, then migrate | Unfiltered `ObjectInputStream` |

## 6. Timeouts (every network call)

```
connect timeout  +  read / response-header timeout  +  overall deadline (incl. retries)  +  bounded concurrency
retries: idempotent only, exponential back-off + jitter, within the deadline
```
