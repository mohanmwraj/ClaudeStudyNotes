# 6.5 Bar-Raiser Drill-Downs: Resilience and Caching

> Evidence: [6.1](01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)–[6.4](04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) (Resilience4j 2.4.0, Spring Framework 7.0.10, Caffeine 3.3.1, Lettuce 7.9.0 against jedis-mock, all run). These topics come up in system design *and* in "tell me about an incident" rounds. The bar-raiser keeps asking "and then what happens?" until your design either holds or breaks.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

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

# Round 2: resilience under measured load, Redis in production (Batch 3 deep dive)

> Evidence for Round 2 is in [6.6](06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md) (an open-loop chaos lab, Resilience4j 2.4.0), [6.7](07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md) (Redis 8.10.2 with Sentinel, Lettuce 7.5.2, Spring Data Redis 4.1.2) and the new deep sections of 6.1–6.4. 🎤 candidate · 🔍 probe · 🛡️ staff-level defense.

---

## Drill 8: "Our retries use exponential backoff with jitter, so retry storms can't happen" 🔥

🎤 *"Three attempts, base 100 ms, full jitter. That's the textbook."*

🔍 **Probe 1: The dependency is overloaded, not flaky. What do your retries do?**

<details><summary>🛡️ Defense</summary>

They multiply the overload. Measured in the chaos lab: open-loop 100 req/s against a dependency that could do 33 req/s in its slow phase. Three attempts with backoff and jitter put **2.72×** the load on it, grew its queue from 284 to **1,024**, and produced 1,733 units of work for clients that had already timed out. The error phase got worse than with no retries at all: 167 successes vs 184, at p50 ≈ 1 s instead of 31 ms. Jitter spreads retries in time but doesn't reduce their number. Retries help with independent transient failures and hurt with overload, and from the client you usually can't tell which one you're in.
</details>

🔍 **Probe 2: So no retries?**

<details><summary>🛡️ Defense</summary>

Retries under a **budget**: at most about 10 % extra load, never retrying a breaker or bulkhead rejection, with the retry outside the breaker so each attempt is counted. In the lab that stack (S5) was indistinguishable from the same stack without retries: dependency load 0.07×–0.09×, 0 failures thanks to the fallback. The budget lets retries absorb the occasional transient failure and switches them off precisely when the failure rate is high, which is the overload case.
</details>

🔍 **Probe 3 (L6): Where else in the stack are retries hiding?**

<details><summary>🛡️ Defense</summary>

Usually at three or four layers at once: the HTTP client, Resilience4j, a service mesh retry policy, the Kafka producer (`retries` defaults to `Integer.MAX_VALUE` within `delivery.timeout.ms`), and the user's browser. They multiply: 3 × 3 × 3 is 27 attempts per click. I'd inventory them, keep one layer with a budget (usually the client closest to the decision), make the mesh retry only connection failures, and propagate a deadline so downstream layers stop working on requests nobody is waiting for. In the lab, timeouts without deadline propagation wasted 430 responses in two phases.
</details>

---

## Drill 9: "The circuit breaker protects our latency" ⚡

🎤 *"When the dependency gets slow, the breaker opens and our p99 stays low."*

🔍 **Probe 1: Your timeout already bounds latency. What does the breaker add?**

<details><summary>🛡️ Defense</summary>

Capacity for the dependency. With a 300 ms timeout alone, client p99 was already ≈ 313 ms, so the breaker didn't buy latency. What it bought: dependency load fell to **0.13×** in the slow phase and **0.09×** in the error phase, its queue peaked at 22 instead of 284, and rejected calls failed in 0 ms. The breaker is load shedding on behalf of the downstream service, giving it room to drain its backlog. I'd describe it that way in a design review, because it changes how you set it: it's tuned to the dependency's recovery, not to your SLO.
</details>

🔍 **Probe 2: How do you pick the slow-call threshold?**

<details><summary>🛡️ Defense</summary>

Below the client timeout: 250 ms against 300 ms in the lab. Then the breaker opens on "getting slow" before calls turn into timeouts. If the threshold is at or above the timeout, slowness only registers once calls are already failing. Resilience4j's default `slowCallDurationThreshold` is 60 s, which in practice means "never" for an HTTP client with a sane timeout.
</details>

🔍 **Probe 3 (L6): What does recovery cost, and who pays?**

<details><summary>🛡️ Defense</summary>

In the lab, 57 of 400 requests in the recovery phase failed while the breaker waited out its 1 s open state and ran 5 half-open trial calls. That's the price of not hammering a recovering service. Across a fleet the trial calls multiply: 40 pods × 5 calls is 200 probes when the dependency comes back, all at roughly the same moment because the breakers opened together. A random jitter on the open duration, or fewer half-open calls per pod, spreads that out. And a fallback, where the product allows one, turns the 57 failures into degraded successes: the S4 stack had 0 failures in all phases.
</details>

---

## Drill 10: "Every pod has a bulkhead of 10, so the dependency is protected" ⚡

🎤 *"We sized it from the dependency's 20 workers, with headroom."*

🔍 **Probe 1: How many pods are there?**

<details><summary>🛡️ Defense</summary>

That's the question that breaks it. The HPA in [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) scales to 40, and 40 × 10 is 400 concurrent calls into a dependency with 20 workers. The bulkhead caps each pod; nothing caps the fleet. In the chaos lab one client with a bulkhead of 10 kept the dependency's queue at 2. Forty such clients would be back at the unprotected case.
</details>

🔍 **Probe 2: So what's the right size?**

<details><summary>🛡️ Defense</summary>

Dependency concurrency ÷ **maximum** replicas, rounded down. That's 20 ÷ 40 = 0 here, which tells you the static per-pod limit is the wrong tool at this scale. The options: an adaptive concurrency limit per pod (AIMD or gradient, reacting to latency), a shared limiter in front of the dependency, or admission control in the dependency itself, which is the only place that knows its own capacity. Static per-pod numbers work when the replica range is narrow.
</details>

🔍 **Probe 3 (L6): Rate limiters and retry budgets: same problem?**

<details><summary>🛡️ Defense</summary>

Yes. Every per-pod number multiplies with replicas: a 5 req/s Resilience4j limiter on 40 pods is 200 req/s against the partner's quota, and with the fixed-window behaviour I measured (10 permits in 54 ms across a boundary) bursts can briefly double it. Fleet-wide quotas need a shared counter (Redis, the gateway) or a per-pod share recomputed as the fleet scales. Retry budgets are safer because they're relative to each pod's own traffic. That's one reason I prefer budgets to fixed retry counts.
</details>

---

## Drill 11: "Redis with Sentinel is highly available, so our locks and sessions are safe" 🔥

🎤 *"If the primary dies, Sentinel promotes a replica within seconds."*

🔍 **Probe 1: What happens to writes the primary acknowledged just before it died?**

<details><summary>🛡️ Defense</summary>

Some are gone. Replication is asynchronous: I measured a Sentinel failover that **lost 38 acknowledged writes**. With `WAIT 1 …` after each write, **0 confirmed** writes were lost, at the cost of a round trip to a replica. For a cache, losing 38 entries is a few misses. For a lock it means a lock that was granted no longer exists, and a second client can take it. For a session it means a logged-in user is logged out. HA in Redis means availability of the service, not durability of every acknowledged write.
</details>

🔍 **Probe 2: "Within seconds": how long, measured?**

<details><summary>🛡️ Defense</summary>

1.75 s in one run, **17.5 s** in another. The difference was a failover attempt that timed out and was retried, plus the client's reconnect back-off. So I size everything that depends on Redis for the slow case: the miss bulkhead and the database's headroom for 17 s of correlated misses, client command timeouts at about 200 ms so threads don't wait out Lettuce's 60 s default, and a `CacheErrorHandler` so a stall degrades to a cache miss instead of a failed request.
</details>

🔍 **Probe 3 (L6): Then where do locks that guard money live?**

<details><summary>🛡️ Defense</summary>

Not only in Redis. A Redis lease prevents duplicate *work* and is fine for "only one pod rebuilds this cache entry". For correctness, I want the guard in the system of record: a unique constraint, a conditional `UPDATE … WHERE version = ?`, or a fencing token that the protected resource checks. Then a lost lease costs some duplicate work, never a double charge. The same goes for idempotency keys: they belong in the database transaction that does the work ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).
</details>

---

## Drill 12: "We cache with Spring's `@Cacheable` on Redis; a cache problem can't take us down" 🔥

🎤 *"Worst case it's a cache miss and we hit the database."*

🔍 **Probe 1: Redis stalls instead of failing. What does a request see?**

<details><summary>🛡️ Defense</summary>

Without configuration, a failed request. I measured it: with Redis stalled and no `CacheErrorHandler`, Spring's cache interceptor propagated `QueryTimeoutException` and the request failed. The cache had turned from an optimization into a hard dependency. With Lettuce's default 60 s command timeout, the request would also hold its thread for a minute first. Two settings fix it: a short command timeout (200 ms) and a `CacheErrorHandler` that logs and treats errors as misses.
</details>

🔍 **Probe 2: A user updates their profile and immediately reloads. Stale?**

<details><summary>🛡️ Defense</summary>

Possibly, and it isn't the database. Spring Data Redis 4 writes cache entries **asynchronously** by default: in my run 21–59 of 200 immediate re-reads after a `put` missed. For read-your-writes paths, configure immediate writes on the cache manager, or evict instead of putting and let the next read fill. It's the kind of default that never shows up in unit tests, only under concurrency.
</details>

🔍 **Probe 3 (L6): And caching "not found"?**

<details><summary>🛡️ Defense</summary>

Decide it deliberately. A method returning `null` into a cache that disallows null values **throws** (`IllegalArgumentException`, verified), so either allow nulls with a short TTL, which is the penetration defense from [6.4 §2](04-Cache-Stampede-Penetration-Avalanche-Invalidation.md), or return `Optional` and skip caching absence. Either is fine; an accidental exception on the read path isn't.
</details>

---

## Drill 13: "We set `maxmemory-policy volatile-lru` and a memory limit, so Redis evicts old keys" ⚡

🎤 *"It evicts least-recently-used keys when memory is full."*

🔍 **Probe 1: Do all your keys have a TTL?**

<details><summary>🛡️ Defense</summary>

If not, `volatile-*` can't evict them, and with nothing evictable it behaves exactly like `noeviction`: writes fail. I measured **14,760 failed `SET`s** that way. For a pure cache I use `allkeys-*`, so every key is a candidate, and I still set TTLs for freshness.
</details>

🔍 **Probe 2: LRU or LFU?**

<details><summary>🛡️ Defense</summary>

LFU for skewed access. On a Zipf workload, `allkeys-lfu` hit **83.1 %**, `allkeys-lru` 81.3 %, `allkeys-random` 78.2 %. Two points of hit rate at 80 % is a 10 % change in database load. That's the same frequency-over-recency argument as Caffeine's W-TinyLFU on the L1 side ([6.3 §1.2](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)).
</details>

🔍 **Probe 3 (L6): How much memory do you actually need?**

<details><summary>🛡️ Defense</summary>

More than the values suggest. A 40-byte value cost **110 bytes** as its own key and **44 bytes** inside a small hash (listpack encoding), measured with `MEMORY USAGE`. With millions of small entries, per-key overhead dominates. I'd measure a representative sample, group small related values into hashes where access patterns allow, and size `maxmemory` with headroom for replication buffers and fragmentation, not just the data.
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
| Resilience under load | Adds timeouts, retries and a breaker | Explains with numbers which layer protects whom: timeouts bound latency, breakers shed load for the dependency, retries amplify overload unless budgeted |
| Fleet limits | Per-pod bulkheads and limiters | Multiplies every per-pod limit by max replicas; reaches for adaptive limits or admission control at scale |
| Redis in production | Sentinel for HA, `maxmemory` set | Knows what failover loses, how long it takes, which eviction policy fits, what Spring's cache layer does on errors |

---

## Red flags

* "Default config is fine" for any resilience pattern.
* Retries on non-idempotent calls, or at every layer.
* A circuit breaker that counts 4xx or its own bulkhead rejections.
* Downstream health in readiness probes.
* "Our rate limiter is a token bucket" (without checking).
* Cache without TTLs, or "we'll just delete the key after update" as the whole consistency story.
* A Redis lock as the only guard on money movement.
* "Backoff with jitter prevents retry storms."
* A breaker whose slow-call threshold is above the client timeout (or left at 60 s).
* Per-pod concurrency or rate limits that ignore the HPA maximum.
* Locks or idempotency keys that live only in Redis.
* `@Cacheable` on Redis without a `CacheErrorHandler` and a short command timeout.
* `volatile-*` eviction with keys that have no TTL.

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

<details><summary>19. Retries ×3 with backoff + jitter on an overloaded dependency: measured load?</summary>2.72×, queue 284 → 1,024, and fewer successes than without retries (167 vs 184).</details>

<details><summary>20. What made retries safe in the chaos lab?</summary>A 10 % retry budget that never retries breaker or bulkhead rejections: load stayed at 0.07×–0.09×.</details>

<details><summary>21. What does a circuit breaker mainly protect?</summary>The dependency: load fell to 0.13× / 0.09× and its queue to 22 (vs 284). Latency was already bounded by the timeout.</details>

<details><summary>22. Where should `slowCallDurationThreshold` sit?</summary>Below the client timeout (250 ms vs 300 ms), so slowness counts before calls time out. The default is 60 s.</details>

<details><summary>23. What did breaker recovery cost in the lab?</summary>57 of 400 recovery-phase requests failed during OPEN (1 s) → HALF_OPEN (5 trial calls) → CLOSED.</details>

<details><summary>24. Per-pod bulkhead of 10, HPA max 40, dependency of 20 workers?</summary>400 concurrent calls: per-pod limits multiply with replicas. Size from max replicas or use adaptive limits.</details>

<details><summary>25. What did a Sentinel failover lose?</summary>38 acknowledged writes (asynchronous replication); `WAIT` lost 0 of the writes it confirmed.</details>

<details><summary>26. How long did Sentinel failover take?</summary>1.75 s in one run, 17.5 s in another (a retried failover plus client back-off).</details>

<details><summary>27. Lettuce's default command timeout?</summary>60 s. Set ~200 ms for a cache.</details>

<details><summary>28. `@Cacheable` on Redis, Redis stalls, no `CacheErrorHandler`?</summary>The request fails (`QueryTimeoutException`). With a handler it degrades to a miss.</details>

<details><summary>29. Spring Data Redis 4 cache writes are…?</summary>Asynchronous by default: 21–59 of 200 immediate re-reads missed. Use immediate writes for read-your-writes.</details>

<details><summary>30. `volatile-lru` with keys that have no TTL?</summary>Behaves like `noeviction`: 14,760 failed `SET`s in the lab.</details>

<details><summary>31. Best eviction policy on a Zipf workload?</summary>`allkeys-lfu` 83.1 % vs `allkeys-lru` 81.3 % vs `allkeys-random` 78.2 %.</details>

<details><summary>32. Memory for a 40-byte value?</summary>110 bytes as its own key, 44 bytes inside a listpack hash.</details>

**Kafka** has its own pillar now: read [10.1 producers](../10-Kafka-Production/01-Kafka-Producers-Batching-Idempotence-Ordering.md) through [10.5 Kafka drill-downs](../10-Kafka-Production/05-Bar-Raiser-Drill-Downs.md) before Pillar 7.

**Depth modules:** [6.6 chaos lab](06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md) · [6.7 Redis in production](07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–7) | Circuit breaker defaults, partner rate limits, retries, bulkheads with virtual threads, Redis caching, Caffeine vs LRU, Redis locks | The mechanics: windows and states, limiter algorithms, retry rules, admission policies, lease vs correctness |
| Round 2 (8–13) | Retry storms with jitter, what a breaker protects, fleet-wide bulkheads, Sentinel failover, Spring's Redis cache, eviction policies | Measured behaviour: amplification and budgets, load shedding for the dependency, per-pod limits × replicas, what HA loses, framework defaults on errors |

**Next pillar:** [7.1 JVM in containers: cgroups v2, memory, OOMKilled →](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)
