# 6.2 Bulkheads, Rate Limiters, Retries with Jitter, and Decorator Order

> **Verified stack:** Resilience4j **2.4.0** (`resilience4j-bulkhead`, `-ratelimiter`, `-retry`, `-all` for `Decorators`), Spring Framework **7.0.10** core resilience (`@Retryable`, `@ConcurrencyLimit`), JDK **25.0.4.1** (virtual threads). Defaults and aspect orders were read from the jars with `javap`; every scenario was run (`R4jLab.java`).
>
> **Prereqs:** [6.1 circuit breaker internals](01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md), [4.4 Tomcat vs virtual threads](../04-Spring-Boot-Internals/04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md). **Related:** [3.5 retry + `@Transactional`](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md), [4.5 inbound rate limiting](../04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md).

---

## 0. First principles: three different things are being limited 🔥

| Pattern | Limits | Protects | Physical analogy |
|---|---|---|---|
| **Bulkhead** | **Concurrency**: calls in flight right now | *Your* resources (threads, connections, memory) from one dependency | Watertight compartments in a ship's hull |
| **Rate limiter** | **Rate**: calls per unit of time | The *callee's* capacity or a contract (partner quota), or you from abusive clients | A turnstile that lets N people through per minute |
| **Retry** | Nothing; it **adds** load | Success rate against *transient* faults | Redialing a busy number |
| **Time limiter / timeout** | **Latency** of one call | The caller's wait (and, through Little's law, its concurrency) | Hanging up after 10 rings |

Little's law ties the first two together: **concurrency = rate × latency**. A concurrency limit is *self-adjusting*: when the dependency slows down, the same limit admits fewer calls per second automatically. A rate limit is *blind to latency*: at 100 req/s, a dependency that slows from 50 ms to 5 s goes from 5 to 500 calls in flight. So the bulkhead protects you and the rate limiter protects the other side. You often need both.

---

## 1. Bulkheads 🔥

### 1.1 Two implementations

```text
SemaphoreBulkhead                                  FixedThreadPoolBulkhead (ThreadPoolBulkhead)
  runs YOUR code on YOUR thread                      runs your code on ITS OWN platform threads
  a (fair) Semaphore: maxConcurrentCalls=25,         ThreadPoolExecutor: core = CPUs − 1, max = CPUs
  maxWaitDuration=0 (defaults, 2.4.0)                (availableProcessors(), so container CPU limits apply),
                                                     queueCapacity = 100, keep-alive 20 ms (defaults, 2.4.0)
  rejection: BulkheadFullException                   returns CompletionStage<T>; rejection when pool+queue full
  cost: one CAS                                      cost: thread hop, context propagation (MDC, security,
                                                       trace) via ContextPropagator, a second pool to size
```

**One measured run:**

```text
== 4. Semaphore bulkhead (max 3 concurrent, no waiting) with 10 virtual threads
  completed=3 rejected(BulkheadFullException)=7
== 5. ThreadPoolBulkhead runs your code on ITS OWN platform threads
  caller: Thread[#3,main,5,main]
  ran on: Thread[#54,bulkhead-legacy-client-1,5,main]
```

### 1.2 Bulkheads in the virtual-thread era ⚡

With platform threads, the Tomcat pool (200 threads) was an accidental global bulkhead, and the thread-pool bulkhead was the standard way to isolate a slow dependency. With virtual threads there is no thread scarcity. Ten thousand requests can all block on the slow dependency at once, and the scarce resource becomes **the connection pool, the downstream's capacity and memory**.

The JDK's guidance for virtual threads is: *don't pool virtual threads; limit concurrency with a semaphore*. That's exactly a `SemaphoreBulkhead`, or Spring Framework 7's built-in equivalent:

```java
@Configuration
@EnableResilientMethods                      // Spring Framework 7: enables @Retryable and @ConcurrencyLimit
class ResilienceConfig { }

@Service
class ReportService {
    @ConcurrencyLimit(limit = 10, policy = ConcurrencyLimit.ThrottlePolicy.REJECT)   // or BLOCK (wait)
    public Report render(ReportRequest r) { ... }                                    // max 10 in flight
}
```

Use a **thread-pool bulkhead** only when you need the *caller* to stop waiting on code that can't be interrupted or timed out (a legacy blocking SDK with no timeout settings), because a `TimeLimiter` needs a `Future` it can abandon.

### 1.3 Sizing ⚡

```text
limit ≈ peak rate per pod × p99 latency × headroom
      = 150 req/s × 0.200 s × 1.5  ≈ 45

Then align with the pool underneath:
  bulkhead limit ≤ HTTP client max connections per route (or HikariCP maximumPoolSize)
  otherwise callers pass the bulkhead and queue inside the pool, under a different timeout you forgot about.
```

---

## 2. Rate limiters 🔥

### 2.1 Correcting the premise: `AtomicRateLimiter` is not a token bucket 🧊

The default `RateLimiter` implementation is `AtomicRateLimiter`. Its whole state is one immutable object in an `AtomicReference`, updated with CAS (fields verified in 2.4.0):

```text
AtomicRateLimiter.State { RateLimiterConfig config; long activeCycle; int activePermissions; long nanosToWait }

time since creation (nanoTimeStart) is cut into fixed cycles of limitRefreshPeriod:

   cycle 0              cycle 1              cycle 2
 |--------------------|--------------------|--------------------|
   5 permits            5 permits            5 permits      ← refilled to limitForPeriod at each boundary,
                                                               never accumulated beyond it

acquire:  compute current cycle → if it moved, activePermissions = limitForPeriod
          activePermissions - 1 ≥ 0 → granted
          otherwise, if timeoutDuration allows, RESERVE a permit from a future cycle
          (activePermissions goes negative), compute nanosToWait, and park that long
```

That's a **fixed window** with reservations. A token bucket refills continuously and caps bursts at the bucket size. A fixed window allows up to **2× the limit** in a short span across a boundary. Verified:

```text
== 3. RateLimiter: 5 permits per 1 s cycle, no waiting (AtomicRateLimiter: fixed cycles, not a token bucket)
  8 calls at the start of a cycle : ✓✓✓✓✓✗✗✗
  5 calls just before + 5 just after a boundary (54 ms apart): ✓✓✓✓✓✓✓✓✓✓  <- 10 permits in a short window
```

If a partner enforces "5 per second over any 1-second span", this limiter **will** get you 429s at boundaries. Fixes: configure the limit lower (for example 4 per second); use a smaller period with a proportional limit (1 per 200 ms smooths the bursts); or use a real token bucket (Bucket4j).

`SemaphoreBasedRateLimiter` is the other implementation: a semaphore whose permits a scheduler thread refreshes each period. It has the same fixed-window semantics.

### 2.2 Algorithms compared

| Algorithm | State | Burst behavior | Where you meet it |
|---|---|---|---|
| Fixed window counter | count per window | up to 2× at boundaries | R4j `AtomicRateLimiter`, simple Redis `INCR`+`EXPIRE` |
| Sliding window log | timestamp per request | exact | small limits only (memory) |
| Sliding window counter | two counters, weighted | approximate, smooth | many API gateways |
| **Token bucket** | tokens + last refill time | bursts up to bucket size, then the refill rate | Bucket4j, Spring Cloud Gateway's Redis rate limiter, Envoy local rate limit |
| Leaky bucket / GCRA | "theoretical arrival time" | smooth, no burst beyond tolerance | NGINX `limit_req`, redis-cell |

### 2.3 Distributed limits 🧊

Resilience4j limiters are **per JVM**. "100 req/s to the partner" across 10 pods means 10 per pod. That share silently changes when the HPA scales to 20 pods (now 200 req/s and 429s) or down to 3. Options:

* **Central limiter**: a Redis token bucket (atomic Lua script) or Bucket4j with Redis/Hazelcast. This is exact but adds a network hop and a dependency. Fail **open** or **closed** deliberately when Redis is down.
* **Egress gateway or mesh** rate limiting for all calls to that host.
* **Per-pod share computed from replica count** (downward API or config refresh). It's cheap, but stale during scaling.
* Honor **`429` + `Retry-After`** from the partner regardless. Their limiter is the real one.

---

## 3. Retries 🔥

### 3.1 When a retry is safe

Retry only if **both** hold:

1. **The failure is transient**: timeouts, connection resets, `503`, `429` (respecting `Retry-After`), deadlocks or serialization failures in the DB. Not `400`/`401`/`404`/`422`, and not validation errors.
2. **The operation is idempotent**, or made idempotent: GET, PUT of a full resource, DELETE, or POST **with an idempotency key** the server deduplicates ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)). A timeout on "charge card" means *unknown outcome*, not failure.

### 3.2 Backoff with jitter

Without jitter, 1,000 clients that failed at the same moment retry at the same moments: a **synchronized retry wave** that knocks the recovering service over again.

```java
IntervalFunction backoff = IntervalFunction.ofExponentialRandomBackoff(Duration.ofMillis(100), 2.0, 0.5);
// attempt n waits 100 ms × 2^(n-1), randomized ±50 %:
//   [50,150]  [100,300]  [200,600]  [400,1200] ms
Retry retry = Retry.of("payments", RetryConfig.custom()
        .maxAttempts(4)                                   // 4 attempts total = 1 call + 3 retries
        .intervalFunction(backoff)
        .retryExceptions(IllegalStateException.class)     // transient
        .ignoreExceptions(IllegalArgumentException.class) // permanent: never retried
        .build());
```

**One measured run:**

```text
== 6. Retry: exponential backoff with jitter (initial 100 ms, x2, randomization 0.5)
  waits before attempts 2..5 (ms): [116, 158, 561, 841]
  transient error: 4 attempts in 677 ms
  non-retryable error (ignored exception): 1 attempt
```

Each wait falls inside its band, and the spread between clients is what breaks up the wave. Other jitter schemes: **full jitter** (`random(0, base × 2^n)`, which spreads the most) and **decorrelated jitter** (`min(cap, random(base, previous × 3))`). Resilience4j's `RetryConfig` defaults are 3 attempts and a fixed 500 ms wait (`DEFAULT_MAX_ATTEMPTS = 3`, `DEFAULT_WAIT_DURATION = 500`), so jitter is opt-in.

### 3.3 Retry amplification and retry budgets 🧊

Retries multiply across layers:

```text
edge (3 attempts) → BFF (3) → order-service (3) → inventory-service
worst case at inventory: 3 × 3 × 3 = 27 calls for one user click, arriving exactly when inventory is struggling
```

Rules that keep this bounded:

* **Retry at one layer**, usually the one closest to the failing dependency, or at the edge for idempotent reads. Other layers fail fast.
* **Retry budgets**: retries may add at most X % (say 10–20 %) extra load. Envoy and Istio support retry budgets. In-app, you can approximate one with a rate limiter that only retries consume.
* **Deadline propagation**: if the caller's remaining budget is 300 ms and a call takes 250 ms, don't start another attempt. gRPC propagates deadlines; over HTTP, pass a header.
* **Open breakers stop retries**: `ignoreExceptions(CallNotPermittedException.class)` on the retry, or the retry keeps backing off against a breaker that has already decided.

### 3.4 Spring Framework 7's built-in `@Retryable`

Since Framework 7 the core has `org.springframework.resilience.annotation.Retryable`. Defaults read from 7.0.10: `maxRetries = 3`, `delay = 1000` ms, `multiplier = 1.0` (**fixed** delay), `jitter = 0` (**no** jitter), `maxDelay = Long.MAX_VALUE`, and `timeout = 0`.

```java
@Retryable(includes = TransientDataAccessException.class, maxRetries = 3,
           delay = 100, multiplier = 2.0, jitter = 50, maxDelay = 2000)
public void reserve(...) { ... }
```

Copying the annotation without `multiplier` and `jitter` gives you a synchronized fixed-interval retry storm. Retry around a transaction must start a **new transaction per attempt**. The interceptor ordering for that case was verified in [3.5](../03-JPA-Hibernate-Spring-Data/05-Transactional-Propagation-Isolation-Pitfalls.md): retry outermost.

---

## 4. Timeouts and the `TimeLimiter` ⚡

* A `TimeLimiter` works on a `Future`/`CompletionStage`: it stops *waiting* and can `cancel(true)` the future. Whether the work actually stops depends on whether it responds to interruption.
* For synchronous code, prefer **timeouts inside the client** (HTTP connect/read/response timeouts, JDBC `queryTimeout`, Kafka `delivery.timeout.ms`). These release the socket and the server-side work. A `TimeLimiter` on top of a blocking call without its own timeout just leaves an orphaned thread behind.
* Budget the layers: `client timeout < slowCallDurationThreshold < TimeLimiter < caller's deadline`.

---

## 5. Decorator order: the interview question 🔥

### 5.1 What the Spring aspects do by default (verified)

The `resilience4j-spring6` configuration properties hold these aspect orders (lower = higher precedence = **outer**):

| Aspect | Order value | Position |
|---|---|---|
| Retry | `Integer.MAX_VALUE - 5` (2147483642) | outermost |
| CircuitBreaker | `MAX - 4` | |
| RateLimiter | `MAX - 3` | |
| TimeLimiter | `MAX - 2` | |
| Bulkhead | `MAX - 1` (2147483646) | innermost |

```text
Retry ( CircuitBreaker ( RateLimiter ( TimeLimiter ( Bulkhead ( yourMethod ) ) ) ) )
```

Why each position makes sense:

* **Bulkhead innermost**: a slot is held only while the real call runs, not while you back off or get rate-limited.
* **TimeLimiter outside the bulkhead**: the timeout includes time spent waiting for a slot.
* **CircuitBreaker outside those**: it records timeouts as failures and short-circuits before you take a permit or a slot.
* **Retry outermost**: every attempt passes through the breaker, so the breaker counts every attempt, and once it opens the retries get `CallNotPermittedException` immediately.

Change the order with `resilience4j.retry.retry-aspect-order`, `resilience4j.circuitbreaker.circuit-breaker-aspect-order` and similar properties, or compose explicitly with `Decorators` (the first `with*` call is the innermost).

### 5.2 Verified: why Retry goes outside the breaker

Same always-failing downstream, 3 logical calls, retry 3 attempts, breaker window 6 / minimum 6 / 50 %:

```java
Decorators.ofSupplier(fn).withCircuitBreaker(cb).withRetry(retry).decorate();   // Retry( CB( fn ) )
Decorators.ofSupplier(fn).withRetry(retry).withCircuitBreaker(cb).decorate();   // CB( Retry( fn ) )
```

```text
== 7. Decorator order with an always-failing downstream, 3 logical calls
  Retry(CB(fn))      downstream calls=6  CB recorded failures=6  CB state=OPEN  callers got CallNotPermitted=1
  CB(Retry(fn))      downstream calls=9  CB recorded failures=3  CB state=CLOSED  callers got CallNotPermitted=0
```

With the breaker inside, it saw every attempt, opened after 6, and stopped the third logical call. With the breaker outside, it saw **one failure per three attempts**: the downstream took 9 calls (3× amplification) while the breaker stayed closed, blind to the load the retries were causing.

### 5.3 One more trap: your own rejections opening your breaker 🧊

By default a breaker **records every exception**. That includes `BulkheadFullException` and `RequestNotPermitted` (rate limiter) thrown from *inside* it, which are **your** overload signals, not the dependency's. A traffic spike that fills your bulkhead can open the circuit to a perfectly healthy dependency. Add them to the breaker's `ignore-exceptions`, or put the bulkhead outside the breaker.

---

## 6. Production configuration (Spring Boot 4 + `resilience4j-spring-boot4`)

```yaml
resilience4j:
  circuitbreaker:
    instances:
      partner-api:
        base-config: default                    # from 6.1
        ignore-exceptions:
          - org.springframework.web.client.HttpClientErrorException
          - io.github.resilience4j.bulkhead.BulkheadFullException
          - io.github.resilience4j.ratelimiter.RequestNotPermitted
  retry:
    instances:
      partner-api:
        max-attempts: 3
        wait-duration: 100ms
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2
        enable-randomized-wait: true
        randomized-wait-factor: 0.5
        retry-exceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - org.springframework.web.client.HttpServerErrorException
        ignore-exceptions:
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
  ratelimiter:
    instances:
      partner-api:
        limit-for-period: 4                     # partner allows 5/s: leave room for the boundary burst
        limit-refresh-period: 1s
        timeout-duration: 200ms                 # wait briefly for a permit, then fail fast
  bulkhead:
    instances:
      partner-api:
        max-concurrent-calls: 40                # 150 req/s × 0.2 s × ~1.3
        max-wait-duration: 0
```

```java
@Service
public class PartnerClient {
    @Retry(name = "partner-api")
    @CircuitBreaker(name = "partner-api", fallbackMethod = "quoteFallback")
    @RateLimiter(name = "partner-api")
    @Bulkhead(name = "partner-api")
    public Quote quote(QuoteRequest req) { ... }              // idempotent: same request id → same quote

    private Quote quoteFallback(QuoteRequest req, CallNotPermittedException e) { return Quote.unavailable(req); }
}
```

The annotation order in source code **doesn't matter**. The aspect orders in §5.1 decide.

---

## 7. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| Thread-pool bulkhead everywhere "for isolation" | Semaphore bulkhead / `@ConcurrencyLimit` with virtual threads; a thread pool only for uninterruptible legacy calls |
| Bulkhead larger than the connection pool beneath it | Bulkhead ≤ pool size, sized by Little's law |
| "Our rate limiter is a token bucket" | `AtomicRateLimiter` is a fixed window: limit set with boundary bursts in mind |
| Per-pod limiter for a global partner quota | Central limiter, egress gateway, or a share computed from the replica count, plus `Retry-After` |
| Retry on every exception | Retry only transient errors on idempotent operations |
| Fixed delays (Spring `@Retryable` defaults) | Exponential backoff + jitter + max delay |
| Retries at every layer | One retry layer, a retry budget, deadline propagation |
| CB(Retry(fn)) | Retry(CB(fn)), the Resilience4j default |
| Breaker counts `BulkheadFullException` | Breaker ignores self-inflicted rejections |
| `TimeLimiter` on blocking code without client timeouts | Client-level timeouts first; `TimeLimiter` only for real async work |

---

## 8. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [resilience4j/resilience4j](https://github.com/resilience4j/resilience4j) | `resilience4j-ratelimiter/src/main/java/io/github/resilience4j/ratelimiter/internal/AtomicRateLimiter.java` | `calculateNextState`, `reservePermissions`, negative permits, `nanosToWait` |
| same | `resilience4j-bulkhead/src/main/java/io/github/resilience4j/bulkhead/internal/SemaphoreBulkhead.java` | `tryAcquirePermission` with fair semaphore and wait |
| same | `resilience4j-bulkhead/src/main/java/io/github/resilience4j/bulkhead/internal/FixedThreadPoolBulkhead.java` | Executor, queue, `ContextPropagator` |
| same | `resilience4j-retry/src/main/java/io/github/resilience4j/retry/internal/RetryImpl.java` | Attempt loop, exception/result predicates, `IntervalBiFunction` |
| same | `resilience4j-core/src/main/java/io/github/resilience4j/core/IntervalFunction.java` | Exponential, randomized and exponential-random backoff math |
| [spring-projects/spring-framework](https://github.com/spring-projects/spring-framework) | `spring-context/src/main/java/org/springframework/resilience/` | Framework 7 `@Retryable`, `@ConcurrencyLimit`, the interceptors |

---

## 9. Interview soundbites

* "A bulkhead caps concurrency and protects me; a rate limiter caps rate and protects them. By Little's law a concurrency limit adapts to latency and a rate limit doesn't."
* "With virtual threads the thread pool stops being a bulkhead. I limit concurrency with a semaphore sized to the connection pool."
* "Resilience4j's default rate limiter is a fixed-cycle limiter with reservations, not a token bucket. I measured 10 permits in 54 ms with a 5-per-second limit across a boundary."
* "I retry only transient failures on idempotent operations, with exponential backoff and jitter, at one layer, under a budget."
* "Retry goes outside the breaker: the breaker counts each attempt and stops the retries. Inside-out, I measured 9 downstream calls with the breaker still closed."
* "A breaker records every exception by default, including my own bulkhead rejections. I tell it to ignore those."

---

## 10. Deep dive: retries, bulkheads and budgets in the chaos lab (verified) 🔥

The [6.6 chaos lab](06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md) measured each rule of this module under the same open-loop load. Demand in the slow phase was 3× the dependency's capacity (100 req/s against 20 workers ÷ 0.6 s = 33 req/s):

| Stack | Slow phase: dependency load | Errors phase: ok | Max dependency queue | Wasted work |
|---|---|---|---|---|
| S1 timeout | 1.00× | 184 | 284 | 430 |
| S2 timeout + **retry ×3** (backoff + jitter) | **2.72×** | **167** | **1,024** | **1,733** |
| S4 + breaker + **bulkhead 10** + fallback | 0.07× | 18 ok + 382 fallback, **0 failed** | 2 | 0 |
| S5 = S4 + retry ×2 **within a 10 % budget** | 0.07× | 14 ok + 386 fallback, 0 failed | 2 | 0 |

What it proves about §3–§5:

* **Retries are an amplifier when the failure is overload.** Three attempts tripled the load on a saturated dependency, the error phase got worse than without retries (167 ok vs 184), and p50 rose from 31 ms to about 1 s. **Jitter spreads retries in time but doesn't reduce their number.**
* **A retry budget is what makes retries safe.** S5 looks almost exactly like S4. Budgeted retries, which never retry a breaker or bulkhead rejection, add only what the dependency can absorb.
* **Timeouts alone create wasted work.** 430 responses went to clients that had already given up. Propagate the deadline so the server can drop expired requests ([5.9 §8.2](../05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md)).
* **The bulkhead kept the queue at 2.** Concurrency, not rate, is what protected the dependency, as §1 argues from Little's law.

**The fleet multiplies every per-pod limit.** A bulkhead of 10 per pod means 400 concurrent calls at the HPA maximum of 40 in [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md), against a dependency with 20 workers. So:

* size the per-pod bulkhead from the **dependency's** capacity divided by the **maximum** replica count;
* or use an adaptive concurrency limit;
* or put the limit where the capacity is, in the dependency's own admission control.

The same arithmetic applies to rate limiters (§2) and retry budgets.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Bulkhead vs rate limiter | Concurrency protects you and adapts to latency; rate protects them | §1 |
| Virtual threads | The thread pool is no longer a bulkhead; use a semaphore sized to the connection pool | §1.2–§1.3 |
| Resilience4j rate limiter | Fixed cycles with reservations, not a token bucket: 10 permits in 54 ms at 5/s across a boundary | §2.1 |
| Retries | Transient failures, idempotent operations, backoff + jitter, one layer, under a budget; Spring 7 `@Retryable` | §3 |
| Timeouts | `TimeLimiter` and client timeouts bound latency, not load | §4 |
| Decorator order | Retry outside the breaker; inside-out gave 9 downstream calls with the breaker still closed | §5.1–§5.2 |
| Breaker hygiene | Ignore your own bulkhead rejections | §5.3, §6 |
| Under load | Retries ×3: 2.72× load, queue 1,024; budgeted retries ≈ no retries; bulkhead queue 2 | §10 (6.6) |
| Fleet math | Per-pod limits × max replicas must fit the dependency | §10 |

**Next:** [6.3 Caching: Caffeine W-TinyLFU and Redis/Lettuce L1/L2 →](03-Caching-Caffeine-W-TinyLFU-and-Redis-Lettuce-L1-L2.md)
