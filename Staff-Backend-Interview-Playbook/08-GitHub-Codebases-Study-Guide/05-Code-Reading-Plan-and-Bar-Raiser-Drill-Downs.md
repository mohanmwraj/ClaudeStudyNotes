# 8.5 Code-Reading Plan and Bar-Raiser Drill-Downs

> Builds on [8.1](01-Modular-Monolith-and-DDD-Repos.md)–[8.4](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md). All repositories and paths referenced there were verified to exist on 2026-10-25, and re-checked against pinned release tags on 2026-10-26. **Round 2** (drills 10–15) builds on [8.6](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md)–[8.9](09-Staff-Level-System-and-Code-Review-Checklist-20-Questions.md); for a shorter plan than §1, use the four weeks in [8.8 §10.4](08-GitHub-Codebase-Study-Matrix-and-Master-Interview-Synthesis.md).
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## 0. How to read a large codebase without drowning 🔥

1. **Start from a question, not from `main()`.** "How does a connection get borrowed?" "When does the breaker go half-open?" A question tells you which 3 files out of 3,000 matter.
2. **Enter through the tests or the public API.** Tests show the intended use and the edge cases the authors worried about. In Spring Modulith, read `ApplicationModules` through the tests that call `verify()`.
3. **Follow one unit of work end to end**: one request, one record, one event. Write the call path down as you go (8.3's ten Kafka stops are an example).
4. **Write down the data structures and their invariants.** In HikariCP, "borrowed entries are never removed from `sharedList`" explains half the class.
5. **Verify your reading with a small experiment.** This kit read Resilience4j's defaults with `javap`, then ran a lab to watch the lazy OPEN→HALF_OPEN transition at 617 ms. If you can't predict the output, you haven't understood the code.
6. **Use history for the "why".** `git log -S 'aliveBypassWindowMs'`, `git blame`, linked issues and pull requests explain decisions the code can't.
7. **Finish with five bullets and one critique.** That's your interview answer.

Tools that pay off: IntelliJ "Find Usages" and "Call Hierarchy", `javap -c -p -constants` for checking defaults in the *jar you actually run*, `jdeps` for module dependencies, GitHub code search, and the `raw.githubusercontent.com/<owner>/<repo>/HEAD/<path>` trick for checking that a path still exists.

---

## 1. A six-week reading plan

| Week | Read | Lab (reuse the kit's) | Deliverable |
|---|---|---|---|
| 1 | HikariCP `ConcurrentBag`, `HikariPool`, `FastList` ([8.4 §1](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)) | Pool exhaustion and `connectionTimeout` under load ([4.4](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md)) | A one-page diagram of `borrow`/`requite`, plus the virtual-thread question answered |
| 2 | Resilience4j state machine, windows, rate limiter ([8.4 §2](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)) | `R4jLab`: breaker, boundary burst, decorator order ([6.1](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [6.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)) | Tuned breaker config for one real dependency, with the arithmetic |
| 3 | Caffeine sketch, admission, maintenance ([8.4 §3](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md)) | `CacheLab` LRU vs W-TinyLFU, coalescing ([6.3](../06-Resilience-Caching/03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)) | Explain the hit-rate gap on your own trace |
| 4 | Kafka stops 1–10, spring-kafka retry topics ([8.3 §4–5](03-Saga-Outbox-Event-Driven-Repos.md)) | Producer batching, rebalance protocols, retry vs DLT ([10.1](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md), [10.2](../10-Kafka-Production/02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)) | A retry/DLT policy for one topic, with the ordering decision |
| 5 | Eventuate sagas + core, FTGO `CreateOrderSaga`, debezium-examples `outbox/` and `saga/` ([8.3](03-Saga-Outbox-Event-Driven-Repos.md)) | Outbox + idempotent consumer + saga labs ([5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md), [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)) | A saga for your domain: steps, pivot, compensations, timeouts |
| 6 | Spring Modulith, ddd-by-examples/library, kgrzybek, petclinic, Larsson ([8.1](01-Modular-Monolith-and-DDD-Repos.md), [8.2](02-Microservices-and-Cloud-Native-Repos.md)) | Modulith boundary violation + event registry ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)) | An ADR: "modular monolith now, these extraction criteria later" |

---

## 2. How to talk about a codebase in an interview

```text
Context      "I wanted to understand why our p99 rose when we moved to virtual threads."
What I read  "HikariCP's ConcurrentBag: thread-local fast path, shared CAS scan, fair hand-off queue."
What I proved "With one virtual thread per request, the thread-local tier rarely hits; borrows go to the
              shared scan and, under pressure, the hand-off queue. The pool, not threads, was the limit."
What changed "We sized the pool from DB capacity and put a semaphore bulkhead in front of it."
Critique     "I'd want pool-wait time as a first-class SLO metric; it's the earliest saturation signal."
```

---

## Drill 1: "Tell me about a codebase you've studied deeply" 🔥

🔍 **Probe 1: Show me one design decision that surprised you.**

<details><summary>🛡️ Defense</summary>

Caffeine's read buffer is **lossy**: when the striped ring buffer is full, the access event is just dropped. `afterRead` offers the node and moves on, and maintenance drains later under a `tryLock`. It's surprising because it trades policy accuracy for read scalability, and it's safe because the map itself stays exact. Only LRU/LFU ordering gets slightly stale. Writes go to a buffer that's never lossy, because a lost write would leave the policy unaware of an entry.
</details>

🔍 **Probe 2: How do you know you understood it, not just read it?**

<details><summary>🛡️ Defense</summary>

I predicted behavior and checked it. For Caffeine I ran a Zipf trace with periodic scans: LRU hit 29.7 %, Caffeine 38.5 %, and I could explain the gap from the admission rule (scan keys have frequency 1 and lose to the victim). For Resilience4j I predicted the breaker would open on the 8th call (4/8 = 50 %) and that half-open would only start on the next call after the wait. Both showed up in the output.
</details>

🔍 **Probe 3 (L6): What would you change in it?**

<details><summary>🛡️ Defense</summary>

Have a real critique ready, and frame it as a trade-off. For Resilience4j: `stateTransition` runs `preTransitionHook()` inside `AtomicReference.getAndUpdate`, whose Javadoc says the updater should be side-effect-free because it can be re-applied under contention. I'd want to know whether concurrent transitions can run the hook twice and whether that's harmless. If not, I'd do the CAS first and the side effects after a successful swap. (I later measured it: [8.4 §6.2](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md), and Round 2 drill 13.)
</details>

---

## Drill 2: "How does HikariCP hand out connections so fast?" ⚡

🔍 **Probe 1: Walk me through `borrow`.**

<details><summary>🛡️ Defense</summary>

Three tiers. First, this thread's own list of recently returned connections: one CAS from `NOT_IN_USE` to `IN_USE`, no shared memory traffic. Second, a lock-free scan of a `CopyOnWriteArrayList` of all connections with the same CAS. Third, register as a waiter, ask the pool to add a connection, and poll a **fair** `SynchronousQueue`. A borrowed connection is never removed from any collection; borrowing is purely a state change.
</details>

🔍 **Probe 2: And `requite`?**

<details><summary>🛡️ Defense</summary>

Set the state back to `NOT_IN_USE`, and if anyone is waiting, offer the connection **directly** to a waiter through the hand-off queue, spinning briefly (with `parkNanos` when the returning thread is virtual). If nobody takes it, remember it in this thread's local list, up to 16 entries.
</details>

🔍 **Probe 3 (L6): What changes with virtual threads?**

<details><summary>🛡️ Defense</summary>

With a new virtual thread per request, the thread-local tier rarely helps (the thread that returned the connection is gone), so borrows hit the shared scan and the hand-off queue more. More importantly, there's no longer a thread-pool ceiling in front of the pool, so thousands of virtual threads can queue on `connectionTimeout`. The pool becomes the real bulkhead: size it from database capacity, put a semaphore in front, and alert on pool wait time.
</details>

---

## Drill 3: "Design a connection pool" 🧊

🔍 **Probe 1: Core data structures?**

<details><summary>🛡️ Defense</summary>

Steal HikariCP's: per-entry atomic state instead of moving entries between queues; a copy-on-write list (reads dominate, membership changes rarely); a fair hand-off for waiters; optional thread-local affinity. Plus a housekeeper for idle/lifetime eviction and an adder thread so borrowers never open connections themselves.
</details>

🔍 **Probe 2: Lifetimes and health checks?**

<details><summary>🛡️ Defense</summary>

`maxLifetime` below every network idle cut-off (load balancers, firewalls, the DB), **jittered** (HikariCP subtracts up to 25 %) so connections created together don't all expire together. Keepalive with jitter (up to 20 %). Skip validation for connections used in the last ~500 ms (HikariCP's `aliveBypassWindowMs`) to save a round trip on busy pools.
</details>

🔍 **Probe 3: How big?**

<details><summary>🛡️ Defense</summary>

From the database's capacity, divided across all pods, not from application threads. The DB has a finite number of useful concurrent queries, roughly tied to its cores and I/O. A pool of 20 per pod across 40 pods is 800 connections, which is often already too many: that's when you add PgBouncer or shrink pools ([2.7](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)).
</details>

---

## Drill 4: "Implement a rate limiter" ⚡

🔍 **Probe 1: Start simple.**

<details><summary>🛡️ Defense</summary>

Resilience4j's `AtomicRateLimiter` is a good model of a lock-free fixed window: an immutable `State(activeCycle, activePermissions, nanosToWait)` updated by CAS. On a new cycle, permissions refill to `min(current + elapsedCycles × perCycle, perCycle)`. Callers willing to wait reserve future permits (negative permissions) and park.
</details>

🔍 **Probe 2: What's wrong with it for a partner quota?**

<details><summary>🛡️ Defense</summary>

It's a fixed window: up to 2× the limit across a boundary, which I measured (10 permits in 54 ms with a limit of 5 per second). For "N per any sliding second", use a token bucket or GCRA, or configure below the limit with a shorter period. And it's per JVM; a fleet-wide quota needs a central limiter or an egress gateway ([6.2 §2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)).
</details>

---

## Drill 5: "Why is Caffeine faster and smarter than an LRU map?" ⚡

🔍 **Probe 1: Smarter how?**

<details><summary>🛡️ Defense</summary>

Admission, not just eviction. A candidate leaving the 1 % window must beat the main space's victim on estimated frequency. Frequencies come from a Count-Min sketch with depth 4 and 4-bit counters, sixteen per `long`, one `long` per cache entry, halved every 10 × max-size samples. If the candidate is warm (frequency ≥ 6) but loses, there's a 1/128 random admission to defeat hash-flooding attacks that keep a victim artificially hot.
</details>

🔍 **Probe 2: Faster how?**

<details><summary>🛡️ Defense</summary>

Reads are a `ConcurrentHashMap` lookup plus an offer into a striped, lossy buffer; nobody waits for the policy. The sketch keeps a key's four counters within one 64-byte cache line, so an increment is typically one memory access. Maintenance batches the policy work under a `tryLock`, so it's one thread at a time and nobody blocks.
</details>

---

## Drill 6: "Walk me through a saga framework you've read" 🧊

🔍 **Probe 1: What does it persist?**

<details><summary>🛡️ Defense</summary>

Eventuate Tram Sagas' PostgreSQL schema: `saga_instance` (`saga_type`, `saga_id`, `state_name`, `last_request_id`, `end_state`, `compensating`, `failed`, `saga_data_type`, `saga_data_json`), `saga_instance_participants`, and two lock tables: `saga_lock_table` (`target` as primary key) and `saga_stash_table`. FTGO's `CreateOrderSaga` defines the steps with a DSL: create order (compensate: reject), validate consumer, create ticket (compensate: cancel), **authorize card (the pivot, no compensation)**, then confirm ticket and approve order as retriable steps.
</details>

🔍 **Probe 2: How does it stop two sagas from interfering on the same order?**

<details><summary>🛡️ Defense</summary>

`SagaLockManagerImpl`: `claimLock` inserts a lock row for the target; if another saga owns it (checked with `select … for update`), the command is **stashed** in `saga_stash_table`. `unlock` either deletes the lock or hands it to the next stashed saga and returns that message. That's a semantic lock implemented as a per-resource queue in the database. The operational risk: a saga that never finishes keeps the queue blocked, so you need saga timeouts and lock-age monitoring.
</details>

---

## Drill 7: "Show me idempotent consumers in real code" ⚡

🔍 **Probe 1: Where have you seen it done?**

<details><summary>🛡️ Defense</summary>

Three places, same idea. Eventuate's `SqlTableBasedDuplicateMessageDetector` inserts `(consumer_id, message_id)` into `received_messages` and treats a duplicate-key exception as "already processed". Debezium's saga example keeps a `MessageLog`/`ConsumedMessage` table on both orchestrator and participants. This kit's `processed_message` table does `insert … on conflict do nothing` in the same transaction as the side effect, and the duplicate-delivery tests passed ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).
</details>

🔍 **Probe 2 (L6): Why must the dedup insert share the transaction with the side effect?**

<details><summary>🛡️ Defense</summary>

If they commit separately, a crash between them either loses the effect (dedup row committed first, then the message is skipped forever) or duplicates it (effect committed first, then reprocessed). One transaction makes "processed" and "effect applied" the same fact. Dedup rows also need retention: keep them at least as long as the broker can redeliver.
</details>

---

## Drill 8: "Modular monolith or microservices for a new product?" 🔥

🔍 **Probe 1: Which, and why?**

<details><summary>🛡️ Defense</summary>

Usually a modular monolith first, with boundaries enforced, not just drawn: Spring Modulith's `verify()` (cycles and `internal` access fail a test), events through the publication registry (an outbox inside the monolith), and tables owned per module. kgrzybek's C# reference and the ddd-by-examples library show the design side: business rules as objects or policies, aggregates returning events.
</details>

🔍 **Probe 2: When would you extract a module?**

<details><summary>🛡️ Defense</summary>

When there's a concrete reason (an independent scaling profile, a separate team, a fault-isolation need) **and** the module is already extractable: no cycles, communication only through its API and events, its own tables, flows across it already eventual (events or sagas). Then extraction is moving code and swapping in-process event delivery for Kafka ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)).
</details>

---

## Drill 9: "Here's a sample microservices repo. Is it production-ready?" ⚡

🔍 **Probe 1: What do you look for first?**

<details><summary>🛡️ Defense</summary>

The failure paths. In petclinic's gateway, the owner-details aggregator does several things right: one batched call for all pets' visits, and a breaker that degrades to an owner without visits. Then my checklist: per-call timeouts and an overall deadline, whether fallbacks are counted, outbox for events, idempotent consumers, contract tests, shutdown behavior, container sizing. Samples rarely cover those, and that list is the answer.
</details>

🔍 **Probe 2: It runs Eureka and Config Server on Kubernetes.**

<details><summary>🛡️ Defense</summary>

On Kubernetes they duplicate platform features (Services/DNS for discovery, ConfigMaps/Secrets for config) while adding components to run and secure. Larsson's book removes both between chapters 16 and 17. I'd keep a gateway at the edge and resilience in the services.
</details>

---

# Round 2: pinned source, thread dumps, a measured critique, and a code review (Batch 4 deep dive)

> Evidence for Round 2 is in:
> * [8.6](06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md): stacks captured from Boot 4.1.2 and spring-kafka 4.1.2, with 653 frames checked against their release tags;
> * [8.7](07-Source-Behind-the-Measurements-JDK-PostgreSQL-Redis-Kubernetes-Kafka.md): the source line behind each measured surprise;
> * [8.4 §6](04-High-Performance-Internals-HikariCP-Resilience4j-Caffeine.md): the Resilience4j race, measured;
> * [8.9](09-Staff-Level-System-and-Code-Review-Checklist-20-Questions.md): ten reproduced review findings.
>
> 🎤 candidate · 🔍 probe · 🛡️ staff-level defense.

---

## Drill 10: "I've read HikariCP's source on GitHub, so I know how our pool behaves" 🔥

🎤 *"`requite` parks when the returning thread is virtual, so virtual threads are handled."*

🔍 **Probe 1: Which version is on your classpath?**

<details><summary>🛡️ Defense</summary>

With Spring Boot 4.1.2, the BOM manages **HikariCP 7.0.2**. The virtual-thread back-off I quoted is on `dev` and first shipped in **7.1.0**. 7.0.2's `requite` parks only periodically and otherwise calls `Thread.yield()`, whatever the thread type. So the sentence is true of the code I read and false of the code we run. Same story for Caffeine: Boot ships 3.2.4 while most write-ups describe 3.3.x. There the admission rule happens to be identical, but I only know that because I checked both tags.
</details>

🔍 **Probe 2: How do you make sure you're reading the right code?**

<details><summary>🛡️ Defense</summary>

Three steps.
1. Get the version from the build (`dependency:tree`, or the BOM's managed versions), not from a blog.
2. Open the release tag, not `main`, and link to it with a line anchor.
3. Check one frame. A stack trace from the running service gives `ConcurrentBag.borrow(ConcurrentBag.java:163)`. If line 163 at the tag is inside `borrow` (it's `handoffQueue.poll`), the jar was built from that tag and every other line maps too. In 8.6, 653 frames passed that check.
</details>

🔍 **Probe 3 (L6): How do you keep this true after upgrades?**

<details><summary>🛡️ Defense</summary>

Keep an upgrade watchlist: the handful of lines our behaviour depends on, per dependency. For a Boot BOM bump that's the managed pool and cache versions, the exit-code mapping, `server.shutdown` and the executor's queue capacity. For kafka-clients it's the producer defaults and the leave-group rule. Re-read them on every bump, and turn the important ones into tests: config validation at startup, a statement-count assertion, a `promtool` test. Reading source is cheap; re-reading the right ten lines is the habit that pays.
</details>

---

## Drill 11: "Here's a thread dump from the outage. 180 threads are waiting" ⚡

🎤 *"Tomcat was saturated, so we doubled `server.tomcat.threads.max`."*

🔍 **Probe 1: What are those threads waiting on?**

<details><summary>🛡️ Defense</summary>

I'd look at the top frames first. If they're `ConcurrentBag.borrow` → `SynchronousQueue.poll` (on JDK 25, through `LinkedTransferQueue`), under `JpaTransactionManager.doBegin`, the pool was exhausted, not Tomcat. Doubling Tomcat's threads makes it worse: more requests queue on the same few connections. The next step is to find the **holders**: threads inside our own code, inside a transaction, doing something other than SQL.
</details>

🔍 **Probe 2: Why would a holder hold a connection while not using it?**

<details><summary>🛡️ Defense</summary>

Because with Hikari's default `auto-commit=true`, Spring takes the connection in `doBegin`, to switch auto-commit off. A `@Transactional` method therefore holds it from its first line, including an HTTP call made before any query. I reproduced it with a pool of 2: four concurrent requests with a 1.5 s pricing call inside the transaction, and two of them failed after the 1 s connection timeout. Moving the call out of the transaction fixed it. With `auto-commit=false` and `hibernate.connection.provider_disables_autocommit=true`, the borrow moves to the first SQL statement, which I also saw in a dump. The real fix is still no remote I/O inside transactions.
</details>

🔍 **Probe 3 (L6): After moving to virtual threads, the dump shows nothing waiting at all. Good news?**

<details><summary>🛡️ Defense</summary>

No. The blocked requests are probably virtual threads, and `Thread.getAllStackTraces()` doesn't return them. The Javadoc says it covers "all live platform threads… does not include virtual threads". I measured exactly that: the borrower was missing from the map. The JSON thread dump (`HotSpotDiagnosticMXBean.dumpThreads`, or `jcmd <pid> Thread.dump_to_file -format=json`) found it with the same Hikari frames. Even that dump only promises it "may" include virtual threads. With virtual threads I'd rather alert on Hikari's pending-threads and acquire-time metrics than depend on a dump during the incident.
</details>

---

## Drill 12: "Review this pull request" 🔥

🎤 *"It looks fine: tests pass, the code is clean. Maybe rename a few methods."*

🔍 **Probe 1: Where do you start?**

<details><summary>🛡️ Defense</summary>

With the classes of bug that lose data or money, in order: is anything sent before the commit? Are failures caught inside a transaction? What happens if the request arrives twice? Is there a read-modify-write without a version or lock? Then availability: remote calls inside transactions, missing timeouts. Then efficiency: N+1, unbounded caches and queues. In the 8.9 lab, a PR with clean code and passing happy-path tests had all of those. Measured:
* an order event delivered for an order that rolled back;
* 2 orders from one client retry;
* stock 9 instead of 8;
* 51 statements for one list.
</details>

🔍 **Probe 2: "The audit is best effort, so we catch its exception." Fine?**

<details><summary>🛡️ Defense</summary>

Not if the audit method is `@Transactional` with the default `REQUIRED`. Its exception marks the *shared* transaction rollback-only, and catching it doesn't undo that. At commit Spring throws `UnexpectedRollbackException: "Transaction silently rolled back because it has been marked as rollback-only"`. I reproduced it: the order was lost because a log line failed. `REQUIRES_NEW` on the audit makes it actually independent, and the order committed.
</details>

🔍 **Probe 3 (L6): How do you stop this class of bug from coming back?**

<details><summary>🛡️ Defense</summary>

A test shape per class, all runnable without a cluster:
* a `CyclicBarrier` to force the lost-update interleaving;
* a pool of 2 and four threads for connection holding;
* a slow HTTP stub for timeouts, and one that counts requests for side effects before commit;
* the same request twice for idempotency;
* Hibernate's statement counter for N+1.

Then make the defaults explicit in configuration, so a reviewer can see them: read timeout, executor queue capacity, `open-in-view`. Each review comment I leave has the finding, the evidence, the fix and the test.
</details>

---

## Drill 13: "Resilience4j's circuit breaker is lock-free, so it's correct under concurrency" 🧊

🎤 *"State lives in one `AtomicReference`, updated with `getAndUpdate`."*

🔍 **Probe 1: What does the `getAndUpdate` Javadoc ask of the function?**

<details><summary>🛡️ Defense</summary>

That it be side-effect-free, because it "may be re-applied when attempted updates fail due to contention". Resilience4j's updater calls the current state's `preTransitionHook()` and constructs the next state. Constructing an `OpenState` with automatic transition enabled **schedules** its OPEN → HALF_OPEN timer. The hook re-running is harmless; a discarded `OpenState` with a live timer may not be.
</details>

🔍 **Probe 2: Does the re-application actually happen?**

<details><summary>🛡️ Defense</summary>

I counted `OpenState` constructions against OPEN transitions with a counting interval function, in two kinds of traffic.
* **Normal failures:** 64 threads failing at once, 200 rounds, gave exactly 200 transitions and 200 states. The `isClosed.compareAndSet` guard lets one thread through.
* **Racing manual flips** (`transitionToOpenState`/`transitionToClosedState` from 8 threads): about 56,000 transitions built about 165,000 states, so roughly 110,000 discarded states, each with a scheduled timer.

Two runs, same picture.
</details>

🔍 **Probe 3 (L6): So what? Nothing uses a discarded state.**

<details><summary>🛡️ Defense</summary>

Its timer does. When it fires, the discarded state's own `isOpen` flag is still true, so it calls `transitionToHalfOpenState()` on the state machine, whatever the current state is. I forced a breaker OPEN for ten minutes after such a race, and it was HALF_OPEN within a second. `FORCED_OPEN` and `DISABLED` aren't safe either: `FORCED_OPEN_TO_HALF_OPEN` and `DISABLED_TO_HALF_OPEN` are legal transitions.

The operational rule is to serialize manual transitions: one controller, never a script racing live traffic. The upstream fix is to build the next state outside the updater, or cancel a discarded state's timer. That's the shape of a good library critique: the line, the reproduction, the scope ("not in normal traffic"), and the fix.
</details>

---

## Drill 14: "`@Cacheable(sync = true)` stops stampedes, so the cache layer is safe" ⚡

🎤 *"Only one thread loads a missing key; the others wait for it."*

🔍 **Probe 1: Where exactly does the loader run?**

<details><summary>🛡️ Defense</summary>

Inside `ConcurrentHashMap.compute`. The captured stack goes `CacheAspectSupport.executeSynchronized` → `CaffeineCache.get(key, loader)` → `BoundedLocalCache.computeIfAbsent` → `ConcurrentHashMap.compute` → your method. Your database call runs while that hash bin is locked. That's what makes same-key callers wait, and it's also why the loader must be short.
</details>

🔍 **Probe 2: What breaks?**

<details><summary>🛡️ Defense</summary>

A loader that asks the same cache for the same key, directly or through another cached method, fails with `IllegalStateException: Recursive update`, thrown from `ConcurrentHashMap.compute` (line 2007 on JDK 25). The `compute` Javadoc forbids modifying the map during computation. A nested load of a *different* key worked in my run, but it ran inside the outer bin lock. And a slow loader holds up other keys that happen to share its bin, not just its own.
</details>

🔍 **Probe 3: And plain `@Cacheable`?**

<details><summary>🛡️ Defense</summary>

No coalescing at all. The stack shows no cache frames while the method runs, so ten concurrent misses run the method ten times: the stampede from [6.4](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md). I use `sync = true` for expensive, non-recursive loaders with timeouts, and early refresh or jittered TTLs for hot keys.
</details>

---

## Drill 15: "spring-kafka retries ten times instantly, then we send to the DLT" ⚡

🎤 *"`FixedBackOff(0, 9)`: no delay, so a bad record costs us milliseconds."*

🔍 **Probe 1: How far apart are those retries?**

<details><summary>🛡️ Defense</summary>

Measured on a caught-up partition, about **515 ms** each: 10 attempts took 4.6 s. The handler seeks back and the record returns through a fresh `poll()`, but the consumer already has its next fetch in flight. The broker holds it for up to `fetch.max.wait.ms` (500 ms), and the client won't send another fetch to that broker while one is pending. With `fetch-max-wait=50ms` the gap fell to ~65 ms; with 20,000 records queued behind the poison, to 15–30 ms. "No back-off" describes the configuration, not the timing.
</details>

🔍 **Probe 2: Where does the DLT publish run?**

<details><summary>🛡️ Defense</summary>

On the consumer thread, inside the poll loop. The captured stack is `ListenerConsumer.pollAndInvoke` → `invokeErrorHandler` → `DefaultErrorHandler.handleRemaining` → `SeekUtils.seekOrRecover` → `FailedRecordTracker.recovered` → the recoverer. A slow or blocked DLT send stalls the partition and counts against `max.poll.interval.ms`. The DLT is `<topic>-dlt` on the **same partition number**, so it needs at least as many partitions as the source.
</details>

🔍 **Probe 3 (L6): What do you configure instead?**

<details><summary>🛡️ Defense</summary>

An `ExponentialBackOff` with a maximum elapsed time that fits inside `max.poll.interval.ms`. A `DeadLetterPublishingRecoverer`, with the DLT created alongside the source topic. Non-retryable exceptions for deserialization and validation failures. An alert on the DLT's message rate. And a replay procedure. I don't rely on the default's timing in either direction: it's slow when caught up and fast under backlog.
</details>

---

## L5 vs L6 signal

| Topic | L5 answer | L6 answer |
|---|---|---|
| "A codebase you studied" | Describes the architecture | Names a non-obvious decision, the trade-off behind it, how they verified it, and a critique |
| Connection pools | Configures HikariCP | Explains `ConcurrentBag` tiers, lifetime jitter, the validation bypass window, sizing from DB capacity, the virtual-thread interaction |
| Caches | Uses Caffeine | Explains admission, the sketch's memory layout and aging, lossy read buffers |
| Rate limiting | Uses a library | Reads the algorithm in code, knows its burst behavior, designs fleet-wide limits |
| Sagas | Draws boxes | Persisted saga log, pivot step, framework semantic locks and their failure mode |
| Samples | "It uses Spring Cloud" | A gap list: outbox, idempotency, contracts, shutdown, sizing |
| Which code | Reads `main` on GitHub | Reads the tag of the jar on the classpath (Boot 4.1.2 → HikariCP 7.0.2, Caffeine 3.2.4) and checks one stack frame against it |
| Thread dumps | Counts waiting threads | Recognises the pool-exhaustion signature, finds the holders, knows virtual threads are missing from `getAllStackTraces()` |
| Code review | Lists bugs as found | Ranks by blast radius; evidence, fix and test per finding; names the default that caused it |
| Library critique | "Well written" or "has bugs" | A line, a reproduction, a scope ("not in normal traffic"), and a fix |
| Retry timing | "10 instant retries" | Knows the fetch pipeline sets the interval (~0.5 s when caught up) and where the recoverer runs |

---

## Red flags

* Claiming to know a library from blog posts only ("Hikari is fast because it uses bytecode tricks") with nothing from the source.
* Citing repos or classes that don't exist (`jbubernik/…`, `RingBitBuffer` in Resilience4j 2.x).
* No critique: everything read is "great".
* No verification: can't say how they'd test their understanding.
* Quoting a library's `main` branch as the behaviour of the version in production.
* "The dump shows nothing stuck" on a service running virtual threads.
* A code review with no ranking, no tests, or no named defaults.
* `@Cacheable(sync = true)` around a loader that calls other cached methods.
* Treating "no back-off" as "instant", or as harmless.
* Scripts that force circuit breakers open concurrently with live traffic.

---

## Rapid-fire flashcards

<details><summary>1. Does `jbubernik/modular-monolith-with-ddd` exist?</summary>No (GitHub API 404). The reference is `kgrzybek/modular-monolith-with-ddd`, in C#.</details>

<details><summary>2. Spring Modulith's outbox mechanism?</summary>The event publication registry (`PersistentApplicationEventMulticaster` + `EventPublicationRegistry`), written in the publisher's transaction.</details>

<details><summary>3. `@ApplicationModuleListener` is?</summary>`@Async` + `@TransactionalEventListener` + `@Transactional(REQUIRES_NEW)`.</details>

<details><summary>4. ddd-by-examples `placeOnHold` returns?</summary>`Either<BookHoldFailed, BookPlacedOnHoldEvents>`.</details>

<details><summary>5. Petclinic microservices versions?</summary>Boot 4.0.1, Spring Cloud 2025.1.0, Java 17.</details>

<details><summary>6. Larsson Fourth Edition Spring Boot version?</summary>3.5.x (README: upgraded from 3.5.0 to 3.5.16).</details>

<details><summary>7. FTGO CreateOrderSaga pivot?</summary>Authorizing the card (`accountingService.authorize`).</details>

<details><summary>8. Eventuate semantic-lock tables?</summary>`saga_lock_table` and `saga_stash_table`.</details>

<details><summary>9. Eventuate dedup table?</summary>`received_messages` (`consumer_id`, `message_id`).</details>

<details><summary>10. Debezium's outbox router now lives in?</summary>The `debezium-connect-plugins` module (`io.debezium.transforms.outbox.EventRouter`).</details>

<details><summary>11. HikariCP borrow tiers?</summary>Thread-local list → shared CAS scan → fair hand-off queue.</details>

<details><summary>12. HikariCP entry states?</summary>NOT_IN_USE 0, IN_USE 1, REMOVED −1, RESERVED −2.</details>

<details><summary>13. HikariCP validation bypass window?</summary>500 ms (`com.zaxxer.hikari.aliveBypassWindowMs`).</details>

<details><summary>14. HikariCP maxLifetime jitter?</summary>Up to 25 % subtracted (keepalive up to 20 %).</details>

<details><summary>15. Why FastList scans from the end?</summary>Statements are usually closed in reverse order of creation.</details>

<details><summary>16. Resilience4j breaker state storage?</summary>An `AtomicReference<CircuitBreakerState>` swapped with `getAndUpdate`.</details>

<details><summary>17. Caffeine sketch memory?</summary>One `long` (16 × 4-bit counters) per entry, rounded up to a power of two.</details>

<details><summary>18. Caffeine sketch aging?</summary>Every 10 × max-size samples, halve all counters (shift + mask).</details>

<details><summary>19. Caffeine counters per key and locality?</summary>Depth 4, all within one 64-byte block.</details>

<details><summary>20. Where does Kafka keep per-producer sequence state on the broker?</summary>`ProducerStateManager` (storage module).</details>

<details><summary>21. Which HikariCP and Caffeine versions does the Boot 4.1.2 BOM manage?</summary>HikariCP 7.0.2 and Caffeine 3.2.4.</details>

<details><summary>22. HikariCP 7.0.2 vs 7.1.0 `requite`?</summary>7.1.0 parks whenever the returning thread is virtual; 7.0.2 has no virtual-thread case.</details>

<details><summary>23. Where does a `@Transactional` method take its connection (Hikari auto-commit on)?</summary>`JpaTransactionManager.doBegin` → `HibernateJpaDialect.beginTransaction`. With `auto-commit=false` + `provider_disables_autocommit=true`: at the first SQL.</details>

<details><summary>24. Pool exhaustion in a thread dump?</summary>Threads `TIMED_WAITING` in `ConcurrentBag.borrow` → `SynchronousQueue.poll` (line 163 in 7.0.2), under `doBegin`.</details>

<details><summary>25. Does `Thread.getAllStackTraces()` include virtual threads?</summary>No (Javadoc). The JSON dump (`dumpThreads`, `jcmd Thread.dump_to_file`) "may" include them; it did in the lab.</details>

<details><summary>26. Commit order with Spring + JPA?</summary>`beforeCommit` (774) → flush + commit in `doCommit` (794) → `afterCommit` (835) → `@TransactionalEventListener` in `afterCompletion` (838).</details>

<details><summary>27. Delete, then insert the same unique key, one transaction?</summary>Only the `INSERT` is sent (the ActionQueue runs inserts before deletes) → 23505. Fix: `flush()` after the delete.</details>

<details><summary>28. `@Cacheable(sync = true)` loader asks for the same key?</summary>`IllegalStateException: Recursive update` from `ConcurrentHashMap.compute`.</details>

<details><summary>29. spring-kafka default retries on a caught-up partition: timing?</summary>~515 ms apart (in-flight fetch, `fetch.max.wait.ms` 500); 10 attempts ≈ 4.6 s.</details>

<details><summary>30. Where does `DefaultErrorHandler`'s recoverer run?</summary>On the consumer thread, inside the poll loop: `handleRemaining` → `SeekUtils.seekOrRecover` → `FailedRecordTracker`.</details>

<details><summary>31. Resilience4j `getAndUpdate` race: normal traffic vs manual races?</summary>200/200 transitions vs states in normal traffic; ~3 `OpenState`s per transition under manual races, each with an orphaned OPEN→HALF_OPEN timer.</details>

<details><summary>32. The four blocking classes in a code review?</summary>Side effect before commit; catch-and-continue in a transaction; non-idempotent write under retry; read-modify-write without a version.</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| 1 | 1. A codebase you studied | A non-obvious decision, verified, with a critique |
| 1 | 2–5. HikariCP, a connection pool, a rate limiter, Caffeine | Data structures and concurrency techniques from source |
| 1 | 6–7. Saga framework, idempotent consumers | Persistence of saga state, semantic locks, dedup in the same transaction |
| 1 | 8–9. Modular monolith vs microservices, a sample repo | Boundaries, extraction criteria, the gap list |
| 2 | 10. Reading GitHub | The version you run vs `main`; checking a frame against the tag |
| 2 | 11. A thread dump | Pool exhaustion, holders, virtual threads missing from the dump |
| 2 | 12. A pull request | Ranked findings with evidence, fix and test |
| 2 | 13. A library critique | Resilience4j's side-effecting updater, measured, with scope and fix |
| 2 | 14. `@Cacheable(sync)` | The loader inside `ConcurrentHashMap.compute` |
| 2 | 15. spring-kafka retries | Fetch pipeline timing; recoverer on the consumer thread |

**Next pillar:** [9.1 Reference architecture: end-to-end order platform →](../09-Staff-Capstone/01-Reference-Architecture-End-to-End-Order-Platform.md)
