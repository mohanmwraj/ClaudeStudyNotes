# 6.7 Bar-Raiser Drill-Downs: Resilience, Caching, Kafka

> Evidence: [6.1](01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)–[6.6](06-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) (Resilience4j 2.4.0, Spring Framework 7.0.10, Caffeine 3.3.1, Lettuce 7.9.0 against jedis-mock, Kafka 4.2.2, spring-kafka 4.1.2, all run). These topics come up in system design *and* in "tell me about an incident" rounds. The bar-raiser keeps asking "and then what happens?" until your design either holds or breaks.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "We added a circuit breaker to the inventory client" 🔥

🎤 *"We use Resilience4j with the default config."*

🔍 **Probe 1: Inventory starts failing 100 % of calls. Your pod handles 2 requests per second. When does the breaker open?**

<details><summary>🛡️ Defense</summary>

With defaults, not for a while. `minimumNumberOfCalls` is **100** and the window is count-based with 100 calls, so the breaker can't decide until about 50 s of traffic has failed. Defaults are tuned for nobody. I size the window and minimum **per pod** from real traffic: a time-based window of 20 s with a minimum of 20 calls decides within seconds at normal load and doesn't flap at night.
</details>

🔍 **Probe 2: Inventory doesn't fail; it answers in 4 seconds. Error rate is 0 %. What happens?**

<details><summary>🛡️ Defense</summary>

An error-rate breaker never opens, and Little's law fills my pools: 200 req/s × 4 s = 800 calls in flight. The defaults make it worse: `slowCallDurationThreshold` is 60 s and `slowCallRateThreshold` 100 %. I set the slow threshold to a small multiple of p99 and a rate like 60 %. Verified: four calls, two of them 150 ms with a 100 ms threshold, gave `slowCallRate=50.0% failureRate=0.0% state=OPEN`. And a client timeout below the slow threshold, so slow calls actually finish and get recorded.
</details>

🔍 **Probe 3: The breaker went HALF_OPEN and stayed there for an hour, rejecting everything. Why?**

<details><summary>🛡️ Defense</summary>

Half-open hands out N permits and waits for N outcomes. If those trial calls hang (no timeout), they never report and nobody else gets a permit. `maxWaitDurationInHalfOpenState` defaults to **0, which means wait forever**. Fix both sides: timeouts on the call, and a max wait in half-open that sends the breaker back to OPEN.
</details>

🔍 **Probe 4 (L6): Should the readiness probe report the breaker state?**

<details><summary>🛡️ Defense</summary>

Never. If inventory is down, every pod's breaker opens, every pod goes unready, Kubernetes removes them all from the Service, and a degraded feature becomes a total outage. Readiness answers "can this pod serve traffic?" Breaker state goes to dashboards and alerts. Also note that breakers are per JVM: per-host ejection of one bad inventory pod is the mesh's outlier detection, not my breaker.
</details>

---

## Drill 2: "The partner allows 100 requests per second, so we put a RateLimiter in front of it" ⚡

🔍 **Probe 1: Is that limiter a token bucket?**

<details><summary>🛡️ Defense</summary>

No. `AtomicRateLimiter` divides time into fixed cycles counted from its creation and resets permits at each boundary: a fixed window with reservations. Across a boundary it can admit up to 2× the limit in a short span. Verified: limit 5 per second, 5 calls just before a boundary and 5 just after, 54 ms apart, gave ✓✓✓✓✓✓✓✓✓✓. If the partner enforces "100 over any second", I configure below the limit, use a shorter period with a proportional limit, or use a real token bucket (Bucket4j).
</details>

🔍 **Probe 2: You run 20 pods.**

<details><summary>🛡️ Defense</summary>

A Resilience4j limiter is per JVM. "100 per second" at 20 pods is 5 per pod, and that share is wrong as soon as the HPA scales. Options: a central limiter (a Redis token bucket via Lua, or Bucket4j on Redis) with a deliberate fail-open or fail-closed decision; an egress gateway that owns the quota; or a per-pod share recomputed from the replica count. Regardless, I honor the partner's `429` + `Retry-After`, because their limiter is the real one.
</details>

🔍 **Probe 3: The limiter is inside the circuit breaker. Traffic spikes and the breaker opens. What went wrong?**

<details><summary>🛡️ Defense</summary>

A breaker records every exception by default, including `RequestNotPermitted` and `BulkheadFullException` thrown inside it. Those are **our** overload signals, not the partner's health. I add them to the breaker's `ignore-exceptions`, or put them outside the breaker.
</details>

---

## Drill 3: "The downstream is flaky, so we added retries" 🔥

🔍 **Probe 1: Which failures do you retry?**

<details><summary>🛡️ Defense</summary>

Transient ones only: timeouts, connection resets, 503, 429 with `Retry-After`, deadlocks or serialization failures. Never 400, 404 or validation errors. And only idempotent operations. A timeout on "charge card" means the outcome is unknown, so I retry only with an idempotency key the provider deduplicates.
</details>

🔍 **Probe 2: Edge, BFF and order-service each retry 3 times. Inventory is struggling. How many calls does it get per click?**

<details><summary>🛡️ Defense</summary>

3 × 3 × 3 = 27, arriving exactly when it's weakest. Retry at **one** layer (closest to the failure), fail fast elsewhere, use a **retry budget** (retries ≤ about 10–20 % extra load; Envoy/Istio support it), and propagate deadlines so nobody starts an attempt the caller will no longer wait for.
</details>

🔍 **Probe 3: You used Spring's new `@Retryable`. What does it do by default?**

<details><summary>🛡️ Defense</summary>

Read from Framework 7.0.10: `maxRetries = 3`, `delay = 1000` ms, `multiplier = 1.0`, `jitter = 0`. That's a fixed interval with no jitter, so every client that failed together retries together. I set `multiplier`, `jitter` and `maxDelay`. Resilience4j's own defaults are similar (3 attempts, fixed 500 ms); jitter is opt-in there too.
</details>

🔍 **Probe 4 (L6): Retry and circuit breaker: which goes outside?**

<details><summary>🛡️ Defense</summary>

Retry outside: `Retry(CB(fn))`, which is also the Resilience4j Spring default (aspect order Retry `MAX-5`, CB `MAX-4`, RateLimiter `MAX-3`, TimeLimiter `MAX-2`, Bulkhead `MAX-1`). Verified with an always-failing downstream and 3 logical calls: Retry(CB) made 6 downstream calls, the breaker recorded 6 failures and opened, and the third caller got `CallNotPermitted`. CB(Retry) made **9** downstream calls, the breaker saw only 3 failures, and stayed closed: it was blind to the amplification. And the retry must ignore `CallNotPermittedException`, or it backs off against a breaker that already decided.
</details>

---

## Drill 4: "With virtual threads we don't need bulkheads anymore" ⚡

🔍 **Probe 1: What's the scarce resource now?**

<details><summary>🛡️ Defense</summary>

Not threads. Connections (the HTTP client pool, HikariCP), the downstream's capacity, and memory. Ten thousand virtual threads can all block on a slow dependency, and the first visible symptom is pool timeouts everywhere. The bulkhead is still needed; it's just a **semaphore** now (`SemaphoreBulkhead` or Framework 7's `@ConcurrencyLimit`), which is exactly the JDK's guidance for virtual threads: limit concurrency with semaphores, don't pool threads.
</details>

🔍 **Probe 2: How do you size it?**

<details><summary>🛡️ Defense</summary>

Little's law: peak rate per pod × p99 latency × headroom, e.g. 150 × 0.2 s × 1.5 ≈ 45. Then make sure the bulkhead is ≤ the connection pool beneath it, otherwise callers pass the bulkhead and queue in the pool under a different, forgotten timeout. Verified behavior: a 3-slot semaphore bulkhead with 10 concurrent virtual threads completed 3 and rejected 7 immediately.
</details>

🔍 **Probe 3: When would you still use a thread-pool bulkhead?**

<details><summary>🛡️ Defense</summary>

When the caller must be able to *stop waiting* for code I can't interrupt or time out, like a legacy SDK without timeouts. The `ThreadPoolBulkhead` runs it on its own platform threads (verified: `bulkhead-legacy-client-1`) and returns a `CompletionStage` a `TimeLimiter` can abandon. The costs: a thread hop, context propagation (MDC, security, trace), and orphaned work that keeps running.
</details>

---

## Drill 5: "Cache product data in Redis to cut database load" 🔥

🔍 **Probe 1: The hottest product's key expires. What happens?**

<details><summary>🛡️ Defense</summary>

A stampede: every request in the reload window misses and queries the database. I layer: per-JVM coalescing (`cache.get(key, loader)`, verified 100 concurrent misses → 1 load), a fleet-wide lease (`SET NX PX`, verified 150 requests on 3 instances → 1 DB load), stale-while-revalidate (`refreshAfterWrite`: stale value in 13 ms instead of a 303 ms block), and XFetch for expensive values (in simulation, expired reads went from 100 to 0).
</details>

🔍 **Probe 2: Redis fails over and comes back empty. Your hit rate was 99 %.**

<details><summary>🛡️ Defense</summary>

DB load jumps up to 100×. The defenses: an L1 Caffeine cache that shields hot keys, a fast-failing Redis client with a breaker, and a **concurrency limit on cache-miss loads** per pod (the miss bulkhead), so DB load is capped at pods × N while everything else gets stale data or a degraded answer. Plus TTL jitter so the rebuilt keys don't all expire together again.
</details>

🔍 **Probe 3: You update the DB and then delete the key. Can the cache still serve the old price?**

<details><summary>🛡️ Defense</summary>

Yes. A reader that read the DB before the update can write the cache after the delete. I forced that interleaving: cache `price=100`, DB `price=80`, stale for the full 600 s TTL. A read replica makes the window bigger. Fix with **leases**: the miss takes a lease, the writer's delete revokes it, and a fill with a revoked lease is rejected (verified: the fill returned 0, and the next read loaded 80). Alternatives: versioned fills, or CDC-driven invalidation, which happens after commit by construction.
</details>

🔍 **Probe 4 (L6): Instances keep a local L1. How do they learn about the update?**

<details><summary>🛡️ Defense</summary>

Redis Pub/Sub (verified: B and C dropped their L1 copy and showed `price=80`). Pub/Sub is **at-most-once**: an instance that's disconnected misses the message. So L1 TTLs stay short (seconds), and if that's not enough: Redis client-side caching (server-tracked invalidation) or a durable channel such as Kafka or CDC. And I write the staleness budget per data type: checkout prices and stock reservations never come from a cache.
</details>

---

## Drill 6: "Why Caffeine instead of a `ConcurrentHashMap` or an LRU?" ⚡

🔍 **Probe 1: What does Caffeine do differently?**

<details><summary>🛡️ Defense</summary>

It's bounded, and its policy is **W-TinyLFU**: a 1 % window LRU, then an admission filter: a candidate enters the main segmented LRU only if its estimated frequency beats the victim's, using a Count-Min sketch of 4-bit counters that halve periodically. One-off scans lose that comparison. On my Zipf trace with periodic scans: LRU 29.7 %, Caffeine 38.5 %.
</details>

🔍 **Probe 2: How does it stay fast under concurrent reads if it maintains LRU and LFU order?**

<details><summary>🛡️ Defense</summary>

The map is exact (`ConcurrentHashMap`); the policy is approximate. Reads record into striped, **lossy** ring buffers; writes into a bounded MPSC buffer that's never lossy. One thread drains them under `tryLock`, so nobody waits for the policy (the BP-Wrapper idea).
</details>

🔍 **Probe 3 (L6): Any trap in `cache.get(key, loader)`?**

<details><summary>🛡️ Defense</summary>

The loader runs inside `ConcurrentHashMap.compute`, holding the bin lock. A slow loader blocks writers of other keys in that bin, and a loader that touches the same cache can deadlock. For I/O loads I use `AsyncCache`: the map holds a future, the load runs outside the lock, and callers still coalesce. And it's per JVM; cross-pod coalescing needs the lease.
</details>

---

## Drill 7: "We use a Redis lock so only one instance processes each payment" 🧊

🔍 **Probe 1: How do you release it?**

<details><summary>🛡️ Defense</summary>

Compare-and-delete in Lua with an owner token, never a plain `DEL`. Verified: holder 1 paused past its 100 ms lease, holder 2 acquired, and holder 1's compare-and-delete returned 0, leaving holder 2's lock intact.
</details>

🔍 **Probe 2: Holder 1 pauses for 10 s (GC, VM migration) after acquiring. What happens?**

<details><summary>🛡️ Defense</summary>

Its lease expires, holder 2 acquires, and holder 1 wakes up **still believing** it holds the lock. Both process the payment. A lease lock is an efficiency mechanism (avoid duplicate work), not a correctness mechanism. No timeout value fixes this, because pauses are unbounded.
</details>

🔍 **Probe 3: Then how do you make it correct?**

<details><summary>🛡️ Defense</summary>

Put the guard where the write happens. A **fencing token**: a monotonically increasing number issued with the lock that the resource checks ("reject writes with token ≤ the last one seen"). Or skip the distributed lock entirely: a unique constraint on the payment id, a conditional update (`update … where status = 'PENDING'`), `SELECT … FOR UPDATE SKIP LOCKED` for work queues ([2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)), or the provider's idempotency key. The Redlock debate (Kleppmann vs antirez) is worth knowing; the practical conclusion is the same.
</details>

---

## Drill 8: "We publish order events with `acks=1` because it's faster" 🔥

🔍 **Probe 1: What can you lose?**

<details><summary>🛡️ Defense</summary>

Any record the leader acknowledged but followers hadn't copied when the leader died. `acks=all` waits for the ISR. It only means something with `min.insync.replicas=2` on a replication factor of 3: one broker can die without losing acknowledged data, two make writes unavailable rather than unsafe. Since 3.0 `acks=all` is the default (verified in 4.2.2), so `acks=1` is a deliberate downgrade.
</details>

🔍 **Probe 2: A retry after a lost response. Duplicate? Reordered?**

<details><summary>🛡️ Defense</summary>

Neither, with idempotence (the default): the broker tracks producer id + per-partition sequence for the last 5 batches, acknowledges the duplicate without appending it, and rejects gaps. That's why `max.in.flight ≤ 5` keeps ordering. But a *restarted* producer has a new id, so re-sends after a crash are new records. Consumers stay idempotent.
</details>

🔍 **Probe 3: You need more throughput. What do you change?**

<details><summary>🛡️ Defense</summary>

Batching, not durability. One run on loopback, 100k × 200 B: linger 0 → 183k rec/s; linger 5 (the 4.x default) → 330k; 128 KB batches with linger 20 → 673k with 36 requests instead of 257. lz4 lost there (257k) because loopback has no network to save. With real payloads over a real network I'd expect compression to win, but I'd measure.
</details>

🔍 **Probe 4 (L6): Throughput still isn't enough, so someone proposes doubling partitions on the topic.**

<details><summary>🛡️ Defense</summary>

On a keyed topic, `murmur2(key) % n` changes, so keys move to new partitions. Records for the same order can be consumed out of order across the change, and any per-partition state in consumers is now wrong. Plan the partition count up front for peak throughput and consumer parallelism, or migrate to a new topic with a cutover.
</details>

---

## Drill 9: "Our consumer group keeps rebalancing" ⚡

🔍 **Probe 1: First thing you check?**

<details><summary>🛡️ Defense</summary>

Whether processing per poll exceeds `max.poll.interval.ms`. Reproduced: a 6 s batch with a 3 s limit gave `CommitFailedException`, `onPartitionsLost`, a rejoin, and the same batch delivered again. Fix: fewer records per poll, an honest interval, pause/resume for long work, and idempotent processing.
</details>

🔍 **Probe 2: Each rebalance pauses all 30 consumers for seconds. Why, and how do you fix it?**

<details><summary>🛡️ Defense</summary>

The default assignor list starts with the eager `RangeAssignor`, which revokes **everything** from everyone. Verified with one joiner: eager revoked all 6 partitions to move 3; cooperative-sticky and KIP-848 revoked only the 3 that moved, and the old member never stopped consuming the others. I migrate to cooperative (two rolling bounces) or to `group.protocol=consumer` on 4.x brokers.
</details>

🔍 **Probe 3: Rolling deploys cause a rebalance per pod. Can you avoid them?**

<details><summary>🛡️ Defense</summary>

Static membership: `group.instance.id` set to a stable pod identity. A restart within `session.timeout.ms` rejoins as the same member with no rebalance. And graceful shutdown: close the consumer in `preStop` so it leaves promptly instead of the group waiting 45 s.
</details>

---

## Drill 10: "We use Kafka exactly-once, so duplicates are impossible" 🧊

🔍 **Probe 1: Exactly-once for what?**

<details><summary>🛡️ Defense</summary>

Kafka transactions make **output records and input offsets** commit atomically for Kafka-to-Kafka processing, with `read_committed` consumers downstream. Verified building block: after an aborted and a committed transaction, `read_uncommitted` saw 5 records and `read_committed` saw 2. Aborted records are still in the log; they're filtered.
</details>

🔍 **Probe 2: The consumer writes to Postgres and calls a payment API.**

<details><summary>🛡️ Defense</summary>

Kafka transactions don't cover those. That's at-least-once delivery + idempotent effects: a dedup row in the same DB transaction as the business change ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)), and the provider's idempotency key derived from the event id.
</details>

🔍 **Probe 3 (L6): Downstream `read_committed` consumers stopped making progress, with no errors. What do you look for?**

<details><summary>🛡️ Defense</summary>

An open transaction. `read_committed` consumers can't read past the **last stable offset**, the start of the oldest open transaction on that partition. A hung producer freezes them until `transaction.timeout.ms` (60 s default) aborts it, or longer if it keeps the transaction alive. Alert on LSO lag. Zombie fencing (same `transactional.id` → epoch bump → `ProducerFencedException` for the old one) handles the restarted-instance case.
</details>

---

## Drill 11: "A poison message is blocking our consumer" ⚡

🔍 **Probe 1: What does Spring Kafka do by default?**

<details><summary>🛡️ Defense</summary>

`DefaultErrorHandler` with `FixedBackOff[interval=0, maxAttempts=9]` (read from a fresh 4.1.2 instance): 10 attempts with no delay, then it logs and **skips** the record. That's neither safe nor visible. I configure backoff, a `DeadLetterPublishingRecoverer`, and non-retryable exceptions. If the value can't even be deserialized, `ErrorHandlingDeserializer` turns it into a non-retryable exception that reaches the DLT.
</details>

🔍 **Probe 2: Blocking retries or retry topics?**

<details><summary>🛡️ Defense</summary>

It depends on whether order matters, and I measured both with the same records. Blocking kept order but stalled the partition: `next-1` waited about 3.7 s behind the poison pill. `@RetryableTopic` kept the main topic flowing but `next-1` **overtook** the poison pill at 731 ms. For account balances or state machines I use short blocking retries then the DLT; for independent work, retry topics. In spring-kafka 4 the DLT suffix is `-dlt` and retry topics are suffixed with the delay (`-retry-1000`, `-retry-2000`, `-retry-4000`).
</details>

🔍 **Probe 3 (L6): What happens to the DLT afterwards?**

<details><summary>🛡️ Defense</summary>

Alerts on arrival, retention of days, a dashboard with age and count, and a replay tool that republishes to the original topic (the headers carry original topic, partition, offset, consumer group and exception). Replays are duplicates by definition, so consumers must be idempotent first. A DLT nobody reads is just data loss with extra steps.
</details>

---

## Drill 12: "Consumer lag is growing; let's add pods" ⚡

🔍 **Probe 1: Will that help?**

<details><summary>🛡️ Defense</summary>

Only up to the partition count: one partition, one consumer per group. Past that, pods sit idle (KEDA's Kafka scaler caps replicas at the partition count unless told otherwise). Then I check **per-partition** lag: the total hides skew. Verified example: total lag 600 was 0 + 297 + 303.
</details>

🔍 **Probe 2: One partition has all the lag.**

<details><summary>🛡️ Defense</summary>

A hot key (key skew) or one slow record type. More consumers can't help; that partition has one owner. Options: a better key (more granular ordering domain), parallel processing per key inside the partition (commit only the contiguous completed prefix), or isolating the hot tenant to its own topic.
</details>

---

## L5 vs L6 signal

| Topic | L5 answer | L6 answer |
|---|---|---|
| Circuit breaker | Knows CLOSED/OPEN/HALF_OPEN, configures thresholds | Sizes windows per pod from traffic, slow-call thresholds from p99, half-open timeouts, keeps breakers out of probes, distinguishes breaker vs outlier detection |
| Rate limiting | Configures `limitForPeriod` | Knows it's a fixed window (2× burst), designs fleet-wide quotas that survive autoscaling, honors `Retry-After` |
| Retries | Exponential backoff | Jitter, idempotency keys, one retry layer, retry budgets, deadlines, Retry(CB) ordering with evidence |
| Bulkheads | Thread pool per dependency | Semaphore + virtual threads, Little's-law sizing aligned with connection pools |
| Caching | Cache-aside with TTL | Stampede/penetration/avalanche defenses, miss bulkhead, invalidation races and leases, staleness budgets per data type |
| Distributed locks | `SETNX` with expiry | Lease vs correctness, fencing tokens, prefers DB constraints |
| Kafka producer | `acks=all`, idempotence | ISR math, sequence numbers and the 5-in-flight limit, partition-count changes, transactions and LSO stalls |
| Kafka consumer | Consumer groups, commit after processing | Rebalance protocols with evidence, `max.poll.interval.ms` failure mode, retry strategy vs ordering, DLT operations, partition-capped scaling |

---

## Red flags

* "Default config is fine" for any resilience pattern.
* Retries on non-idempotent calls, or at every layer.
* A circuit breaker that counts 4xx or its own bulkhead rejections.
* Downstream health in readiness probes.
* "Our rate limiter is a token bucket" (without checking).
* Cache without TTLs, or "we'll just delete the key after update" as the whole consistency story.
* A Redis lock as the only guard on money movement.
* `acks=1` or idempotence disabled "for performance".
* "Exactly-once" without saying exactly-once *what*.
* Scaling consumers past partitions; alerting on total lag only.
* A DLT with no alerting and no replay path.

---

## Rapid-fire flashcards

<details><summary>1. What replaced `RingBitBuffer` in Resilience4j?</summary>The `Metrics` sliding windows in `resilience4j-core` (count- and time-based), since 1.0.</details>

<details><summary>2. Default sliding-window lock strategy in 2.4.0?</summary>`SYNCHRONIZED` (ReentrantLock). `LOCK_FREE` is opt-in.</details>

<details><summary>3. Default `minimumNumberOfCalls` and `slowCallDurationThreshold`?</summary>100 calls and 60 s.</details>

<details><summary>4. Why did OPEN→HALF_OPEN happen at 617 ms with a 500 ms wait?</summary>The transition is lazy: it happens on the first call after the wait, unless automatic transition is enabled.</details>

<details><summary>5. `maxWaitDurationInHalfOpenState` default?</summary>0, which means wait indefinitely.</details>

<details><summary>6. Resilience4j Spring aspect order, outer to inner?</summary>Retry → CircuitBreaker → RateLimiter → TimeLimiter → Bulkhead.</details>

<details><summary>7. `AtomicRateLimiter` algorithm?</summary>Fixed cycles with permit reservation; can admit 2× the limit across a boundary.</details>

<details><summary>8. Spring 7 `@Retryable` defaults?</summary>`maxRetries` 3, `delay` 1000 ms, `multiplier` 1.0, `jitter` 0.</details>

<details><summary>9. Bulkhead for virtual threads?</summary>A semaphore (`SemaphoreBulkhead`, `@ConcurrencyLimit`), sized by Little's law and ≤ the connection pool.</details>

<details><summary>10. W-TinyLFU admission rule in Caffeine 3.3.1?</summary>Admit if freq(candidate) > freq(victim); if freq(candidate) ≥ 6, admit with probability 1/128; else reject.</details>

<details><summary>11. Caffeine window and protected share?</summary>Window ~1 % (`PERCENT_MAIN = 0.99`), protected 80 % of main.</details>

<details><summary>12. `refreshAfterWrite` vs `expireAfterWrite`?</summary>Refresh serves stale and reloads asynchronously; expire blocks the reader on reload.</details>

<details><summary>13. Stampede defenses?</summary>Coalescing, distributed lease, stale-while-revalidate, XFetch.</details>

<details><summary>14. Bloom filter size for 1M items at 1 %?</summary>≈9.59M bits (1.1 MB), 7 hashes.</details>

<details><summary>15. Avalanche defenses?</summary>TTL jitter, L1 shield, fast-failing Redis client, miss bulkhead, HA/persistence, staggered rollouts.</details>

<details><summary>16. Fix for the cache-aside stale-fill race?</summary>Leases (delete revokes the lease), versioned fills, or CDC invalidation.</details>

<details><summary>17. Pub/Sub delivery guarantee?</summary>At-most-once; keep L1 TTLs short.</details>

<details><summary>18. Lease lock vs correctness?</summary>A lease prevents duplicate work, not concurrent writes; correctness needs fencing tokens or DB constraints.</details>

<details><summary>19. Kafka 4.x producer defaults for acks, idempotence, linger?</summary>`all`, `true`, 5 ms.</details>

<details><summary>20. Why `max.in.flight ≤ 5` with idempotence?</summary>The broker tracks the last 5 batch sequences per producer and partition.</details>

<details><summary>21. What does `read_committed` stop at?</summary>The last stable offset (start of the oldest open transaction).</details>

<details><summary>22. Consumer default `auto.offset.reset`?</summary>`latest`: new groups skip existing data.</details>

<details><summary>23. Eager vs cooperative vs KIP-848?</summary>Eager revokes all; cooperative revokes only moving partitions (two rounds); KIP-848 is broker-side, incremental, with no group barrier.</details>

<details><summary>24. `DefaultErrorHandler` default?</summary>`FixedBackOff(0, 9)`: 10 attempts, no delay, then log and skip.</details>

<details><summary>25. Spring Kafka 4 DLT suffix?</summary>`-dlt` (older versions used `.DLT`).</details>

<details><summary>26. Blocking vs non-blocking retries?</summary>Blocking keeps order but stalls the partition; non-blocking keeps throughput but breaks per-key order.</details>

<details><summary>27. Max useful consumers in a group?</summary>The partition count.</details>

**Next pillar:** [7.1 JVM in containers: cgroups v2, memory, OOMKilled →](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)
