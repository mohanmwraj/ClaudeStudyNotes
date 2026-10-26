# 6.6 Resilience Under Load: a Chaos Lab That Measures What Each Layer Buys (Timeouts, Retries, Breakers, Bulkheads, Fallbacks, Retry Budgets)

> **Verified stack:** Resilience4j **2.4.0** (programmatic `Decorators` in the lab; `resilience4j-spring-boot4` 2.4.0 for the blueprint), JDK **25** (`java.net.http.HttpClient`, `com.sun.net.httpserver`, virtual threads), Spring Boot **4.1.2** for the binding check. The lab ran **twice**; every conclusion below held in both runs, with counts within a few percent. Latencies are from a laptop on loopback: compare the stacks with each other, not with production numbers.
>
> **Builds on:** [6.1](01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md) (breaker internals) and [6.2](02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) (bulkheads, retries, decorator order) verified each pattern **in isolation**. This file runs them **together, under load, while the dependency degrades**. That's where interviewers push: "and what happens to the downstream?"

---

## 0. The experiment 🔥

```text
                    open-loop load: 100 req/s, constant          +-----------------------------------------------+
   load generator  ---------------------------------------->     |  dependency: 20 workers (fair semaphore)       |
   (virtual threads,      client stack S0..S5                    |  phase 1  healthy   20 ms                      |
    one per request)  (timeout / retry / breaker /               |  phase 2  slow     600 ms  -> capacity 33 rps  |
                       bulkhead / fallback / budget)             |  phase 3  errors    20 ms, 50% HTTP 500        |
                                                                 |  phase 4  recovery  20 ms                      |
                                                                 +-----------------------------------------------+
   4 s per phase · 400 requests per phase · the dependency counts arrivals, queue depth, and work done for requests
   whose client had ALREADY timed out ("wasted work")
```

**Open loop** matters. Real users keep arriving whether or not you're slow, so a saturated dependency builds a queue instead of slowing the load down. In the slow phase, demand (100 req/s) is 3× capacity (20 workers ÷ 0.6 s = 33 req/s).

| Stack | Client-side protection (Resilience4j 2.4.0) |
|---|---|
| S0 | None: `HttpClient` without a request timeout |
| S1 | Timeout 300 ms |
| S2 | Timeout + `Retry` 3 attempts, exponential backoff with jitter |
| S3 | Timeout + `CircuitBreaker`: count window 20, min 10 calls, 50 % failure or 50 % slow (> 250 ms), 1 s open, 5 half-open calls |
| S4 | S3 + semaphore `Bulkhead` (10 concurrent, no waiting) + fallback (a cached price) |
| S5 | S4 + `Retry` 2 attempts *outside* the breaker, **only within a 10 % retry budget**, never retrying breaker or bulkhead rejections |

---

## 1. Results (verified; run 1 shown, run 2 within a few percent) 🔥

```text
dependency: 20 workers; phases of 4 s; open-loop load 100 req/s; client timeout 300 ms where set
== S0 no protection (no timeout)   (dependency max queue: 284)
     phase              ok  fallback  failed   p50 ms   p99 ms  max in-flight  dependency load  wasted work
     healthy (20 ms)    400         0       0       23      147             17      399 (1.00x)            0
     slow (600 ms)      267         0     133     1837     3045            282      400 (1.00x)            0
     errors (50% 500)   209         0     191       31      713            306      399 (1.00x)            0
     recovery (20 ms)   400         0       0       31       33              5      402 (1.01x)            0
== S1 timeout 300 ms   (dependency max queue: 284)
     healthy (20 ms)    398         0       2       31       33              5      398 (1.00x)            0
     slow (600 ms)        0         0     400      310      314             33      400 (1.00x)          120
     errors (50% 500)   184         0     216       31      313             33      400 (1.00x)          310
     recovery (20 ms)   400         0       0       31       33              5      402 (1.01x)            0
== S2 timeout + retry x3 (exp. backoff + jitter)   (dependency max queue: 1024)
     healthy (20 ms)    398         0       2       31       33              5      398 (1.00x)            0
     slow (600 ms)        0         0     400     1091     1163            115     1086 (2.72x)          120
     errors (50% 500)   167         0     233     1015     1155            113     1138 (2.85x)         1733
     recovery (20 ms)   400         0       0       31       34             16      412 (1.03x)            0
== S3 timeout + circuit breaker   (dependency max queue: 22)
     healthy (20 ms)    399         0       1       31       33              5      399 (1.00x)            0
     slow (600 ms)        0         0     400        0      313             34       52 (0.13x)           22
     errors (50% 500)    16         0     384        0       32              5       34 (0.09x)            0
     recovery (20 ms)   343         0      57       31       32              5      343 (0.86x)            0
== S4 timeout + breaker + bulkhead(10) + fallback   (dependency max queue: 2)
     healthy (20 ms)    399         1       0       31       32              5      399 (1.00x)            0
     slow (600 ms)        0       400       0        0      311             12       29 (0.07x)            0
     errors (50% 500)    18       382       0        0       32              5       36 (0.09x)            0
     recovery (20 ms)   344        56       0       31       32              5      344 (0.86x)            0
== S5 S4 + retry x2 within a 10% retry budget   (dependency max queue: 2)
     healthy (20 ms)    399         1       0       31       32              5      399 (1.00x)            0
     slow (600 ms)        0       400       0        0      387             16       28 (0.07x)            0
     errors (50% 500)    14       386       0        0      109             12       36 (0.09x)            0
     recovery (20 ms)   344        56       0       31       32              5      344 (0.86x)            0
```

Run 2 (selected rows): S0 slow p99 3,050 ms, max in-flight 306; S2 load 2.71×/2.82×, max queue 1,022, wasted work 1,751; S3 slow 0.13×; S4 recovery 321 ok + 79 fallback.

---

## 2. Reading the table, stack by stack 🔥

**S0: no protection.**

* **In-flight requests grew to 306.** That's Little's law: in-flight = arrival rate × latency, and latency kept growing with the queue (p99 3 s). In a servlet app those are 306 held threads or connections. With platform threads, that is the outage.
* **The damage outlived the incident.** The slow phase's backlog was served during the error phase, so "slow-phase" requests failed with the error phase's 500s (133 failures), and the error phase's p99 was 713 ms. Without timeouts, an incident's tail lands on the *next* phase's users.

**S1: timeout only.**

* **Timeouts bound latency** (p99 ≈ 313 ms) and in-flight work (33).
* **They don't reduce load on the dependency** (1.00×).
* **They create wasted work.** The dependency served **430 requests whose client had already given up** (120 + 310). The server can't tell that nobody is waiting, so a third of its capacity during the incident went to answers that were thrown away. This is why deadlines should be *propagated* to the server ([5.9 §8.2](../05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md)), which can then drop expired work.

**S2: timeout + 3 retries (with backoff and jitter).**

* **Retries tripled the load on a dependency that was already overloaded** (2.72× and 2.85×), grew its queue to **1,024**, and produced **1,733** units of wasted work.
* **The error phase got *worse*:** 167 ok vs S1's 184, at p50 1 s instead of 31 ms.
* **Jitter isn't the fix.** Backoff with jitter spreads retries in time, but doesn't reduce their number. This is the retry storm in numbers: retries help with *independent* transient failures and hurt when the failure is *overload*.

**S3: timeout + circuit breaker.**

* **The breaker opened early in each bad phase**, cutting dependency load to **0.13×** and **0.09×**. Its queue peaked at 22 instead of 284, and rejected calls failed in **0 ms**.
* **It gave capacity back.** That's the breaker's real job: the dependency can drain its backlog instead of drowning.
* **The price:** in the recovery phase, 57 calls still failed while the breaker went OPEN → HALF_OPEN (1 s) → CLOSED (5 successful trial calls).

**S4: + bulkhead + fallback.**

* **Every failure became a degraded success** (cached price): **0 failed** in all phases.
* **The bulkhead capped concurrency at 10** and kept the dependency's queue at 2.
* **Breaker and bulkhead together** mean the caller never waits for an overloaded dependency. Whether a fallback is *acceptable* is a product decision: a cached price is fine for browsing and wrong at checkout.

**S5: + 2 retries within a 10 % retry budget.**

* **Barely different from S4**, and that's the point. The budget allowed few retries, and none of them hit an open breaker or a full bulkhead, so the load stayed at S4's level (0.07×–0.09×), not S2's 2.8×.
* **What it did cost:** some tail latency (errors-phase p99 109 ms vs 32 ms).
* **When retries pay off:** isolated failures (a dropped connection, one bad pod), and only within a budget that turns itself off under widespread failure.

---

## 3. The rules this proves ⚡

| Rule | Evidence |
|---|---|
| Every remote call needs a timeout. Not for the failed request: for everyone else's threads | S0: 306 in flight, p99 3 s, damage spilled into the next phase |
| A timeout alone doesn't protect the dependency | S1: load 1.00×, 430 wasted answers |
| Retries without a breaker and a budget amplify overload | S2: 2.85× load, queue 1,024, success *down* |
| The breaker's main beneficiary is the dependency (and your threads) | S3: load 0.09×, queue 22, instant rejections |
| Bulkhead + fallback turn failures into degraded success | S4: 0 failures |
| Retry *outside* the breaker, never retry rejections, cap with a budget | S5 ≈ S4: no amplification |
| Recovery has a tail: breaker open time + half-open probes | S3/S4: 56–79 degraded or failed calls after the dependency was healthy |

Breaker tuning follows from the table:

* **Detection speed:** window × arrival rate. Here, 20 calls at 100 req/s ≈ 0.2 s to trip.
* **Recovery tail:** `waitDurationInOpenState` plus the half-open trials.
* **The slow-call threshold** (250 ms, below the 300 ms timeout) let the breaker react to slowness *before* the timeouts piled up. Leave it out and slowness only counts once it becomes failures.

---

## 4. Blueprint: the S5 stack in Spring Boot 4.1.2 (bound and verified) 🔥

```yaml
resilience4j:
  circuitbreaker:
    instances:
      pricing:
        sliding-window-type: COUNT_BASED
        sliding-window-size: 20
        minimum-number-of-calls: 10
        failure-rate-threshold: 50
        slow-call-duration-threshold: 250ms          # below the client timeout: react to slowness before timeouts pile up
        slow-call-rate-threshold: 50
        wait-duration-in-open-state: 1s
        permitted-number-of-calls-in-half-open-state: 5
        automatic-transition-from-open-to-half-open-enabled: true
        ignore-exceptions:
          - io.github.resilience4j.bulkhead.BulkheadFullException     # our own shedding is not a dependency failure (6.2 §5.3)
  bulkhead:
    instances:
      pricing:
        max-concurrent-calls: 10
        max-wait-duration: 0ms                        # shed immediately; waiting just moves the queue into our threads
  retry:
    instances:
      pricing:
        max-attempts: 2
        wait-duration: 50ms
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2
        enable-randomized-wait: true
        randomized-wait-factor: 0.5
        retry-exception-predicate: resilienceboot.ResilienceBootCheck$RetryBudgetPredicate
        ignore-exceptions:
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException
          - io.github.resilience4j.bulkhead.BulkheadFullException
```

```java
/** Retry budget: retries may add at most 10% on top of first attempts. Resilience4j instantiates it from the YAML. */
public static class RetryBudgetPredicate implements Predicate<Throwable> {
    public static final AtomicLong firstAttempts = new AtomicLong(), retries = new AtomicLong();

    @Override
    public boolean test(Throwable t) {
        if (retries.get() + 1 > firstAttempts.get() * 0.10) return false;
        retries.incrementAndGet();
        return true;
    }
}
```

Resilience4j has no built-in retry budget, so this is the minimal version. In production, use a sliding window (for example, Resilience4j's own metrics, or two decaying counters) and count first attempts in the client, as the lab did.

**Bound in a real Boot 4.1.2 context; what the registries built (verified):**

```text
circuitbreaker pricing: type=COUNT_BASED size=20 minCalls=10 failureRate=50.0% slowCall=250ms@50.0% openWait=1000ms halfOpenCalls=5 autoHalfOpen=true ignores BulkheadFullException=true
bulkhead pricing: maxConcurrentCalls=10 maxWait=0ms
retry pricing: maxAttempts=2 firstInterval~26ms secondInterval~103ms
retry budget: after 100 first attempts, 20 failures asked to retry -> 10 allowed; CallNotPermittedException retried? false
```

**Reading it:**

* **The intervals are randomized** around 50 ms and 100 ms (± 50 %).
* **The budget allowed exactly 10 % extra attempts.**
* **Breaker rejections are never retried:** `ignore-exceptions` is checked before the predicate.

**Applying it to a client:**

* **With the annotations** (`@Retry`, `@CircuitBreaker`, `@Bulkhead` on the same method), the Spring aspects compose as Retry ( CircuitBreaker ( Bulkhead ( call ) ) ), the S5 order ([6.2 §5.1](02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md#51-what-the-spring-aspects-do-by-default-verified)).
* **The timeout lives in the HTTP client** (`JdkClientHttpRequestFactory#setReadTimeout`, [5.9 §8.2](../05-Microservices-Patterns/09-Microservices-Patterns-Catalog-Flows-Failure-Modes-Spring-Code.md)).
* **The fallback** goes in `fallbackMethod`.

---

## 5. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| No timeout ("the dependency is fast") | Timeout below the caller's deadline on every remote call (S0 → S1) |
| Retries everywhere, with backoff and jitter, "for resilience" | Retries only for transient faults, outside the breaker, within a budget (S2 vs S5) |
| Breaker tuned on failure rate only | Slow-call rate too, threshold below the timeout |
| Bulkhead that waits (`max-wait-duration` > 0) under overload | Shed immediately (0 ms); waiting moves the queue into your threads |
| Breaker counts `BulkheadFullException` | `ignore-exceptions` for your own rejections |
| Fallbacks everywhere | Fallbacks only where stale or partial data is acceptable; fail fast at checkout |
| "The dependency recovered, so we did" | Measure the recovery tail (open wait + half-open trials) |
| Timeouts without deadline propagation | Propagate the deadline so the server drops abandoned work (S1: 430 wasted answers) |

---

## 6. Bar-raiser Q&A 🔥

🎤 *"The pricing service is flaky, so we added three retries with exponential backoff and jitter."*

🔍 **What happens to pricing when it's slow because it's overloaded?**

<details><summary>🛡️ Defense</summary>

The retries multiply its load exactly when it has the least capacity. In my chaos test (open-loop 100 req/s against a dependency that could do 33 req/s), three retries pushed the dependency's load to **2.85×**, its queue to **1,024**, and **1,733** of the requests it served were for clients that had already given up. The success rate in the error phase went *down*. Jitter spreads the retries over time but doesn't reduce their number. Retries help with independent transient failures; under overload you need a breaker and a retry budget.
</details>

🔍 **So what would you put in front of it?**

<details><summary>🛡️ Defense</summary>

A stack I measured as S5:

* **a timeout** below the caller's deadline;
* **a circuit breaker** that also counts slow calls (threshold below the timeout);
* **a semaphore bulkhead** that sheds immediately;
* **a fallback** where stale data is acceptable;
* **at most one retry, outside the breaker**, never on breaker or bulkhead rejections, within a 10 % budget.

Measured, that dropped the dependency's load to **0.07–0.09×** during the incident, kept its queue at 2, and returned degraded-but-successful answers to every caller. The cost is a recovery tail: ~60 degraded answers in the first second after pricing recovered, while the breaker probed half-open.
</details>

🔍 **Why does the breaker's slow-call threshold matter?**

<details><summary>🛡️ Defense</summary>

Without it, slowness counts only once it turns into timeouts. That's after every caller has already waited the full timeout, while in-flight work piles up. With a 250 ms slow-call threshold and a 300 ms timeout, the breaker trips on *latency*. In the lab it opened within the first fraction of a second of the slow phase: dependency load fell to 0.13× and rejected calls returned in 0 ms.
</details>

🔍 **We have timeouts everywhere. Isn't that enough?**

<details><summary>🛡️ Defense</summary>

Timeouts protect the **caller's** threads. They don't protect the **dependency**: S1 kept its load at 1.00×, and the dependency spent 430 answers on requests that had already timed out. Two more things are needed:

* **a breaker,** to stop sending;
* **deadline propagation,** so the server can drop work whose caller is gone.

Without both, the dependency stays saturated and recovers later than it needs to.
</details>

---

## Summary

| Stack | Dependency load (slow / errors) | Outcome for callers | Lesson |
|---|---|---|---|
| S0 none | 1.00× / 1.00× | p99 3 s, 306 in flight, damage spills into later phases | Timeouts protect everyone else |
| S1 timeout | 1.00× / 1.00× | Fast failures; 430 wasted answers | Timeouts don't protect the dependency |
| S2 + retries | **2.72× / 2.85×** | Fewer successes, p50 1 s, queue 1,024 | Retries amplify overload |
| S3 + breaker | 0.13× / 0.09× | Instant failures; recovery tail | The breaker returns capacity |
| S4 + bulkhead + fallback | 0.07× / 0.09× | 0 failures (degraded answers) | Shed and degrade |
| S5 + budgeted retry | 0.07× / 0.09× | Same as S4, no amplification | Retry outside, within a budget |

**Next:** [6.7 Redis in production: memory, eviction, client-side caching, failover, Spring's Redis cache →](07-Redis-in-Production-Memory-Eviction-Client-Caching-Failover-Spring-Cache.md)
