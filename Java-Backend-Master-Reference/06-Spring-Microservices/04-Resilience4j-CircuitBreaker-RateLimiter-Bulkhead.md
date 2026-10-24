# 6.4 · Resilience — Circuit Breaker, Retry, Rate Limiter, Bulkhead (Resilience4j 2.4 + Spring 7)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Resilience4j 2.x documentation and source (`CircuitBreakerStateMachine`, `AtomicRateLimiter`, `SemaphoreBulkhead`, aspect ordering); Michael Nygard, *Release It!* (circuit breaker, bulkhead); AWS Builders' Library, "Timeouts, retries, and backoff with jitter"; Spring Framework 7 reference ("Resilience Features").
> **Verified stack:** Resilience4j **2.4.0** (`resilience4j-all`, `resilience4j-spring-boot4`, `resilience4j-micrometer`), Spring Boot 4.1.2, Micrometer 1.17.2, JDK 25. All state transitions, counts, messages, meter names and aspect orders below were **captured from runs**.

---

## 1. What each pattern protects 🔥

| Pattern | Protects | Mechanism | Failure signal to the caller |
|---|---|---|---|
| **Timeout** | Your threads from a hung dependency | Deadline per call (client timeouts, `TimeLimiter`) | `TimeoutException` |
| **Retry** | Against *transient* failures | Re-invoke with backoff and jitter; only idempotent operations | The last exception after `maxAttempts` |
| **Circuit breaker** | The dependency (and you) from being hammered while it's down | Sliding window of outcomes → `CLOSED`/`OPEN`/`HALF_OPEN` | `CallNotPermittedException` (fail fast) |
| **Rate limiter** | A downstream quota, or your own service from overload | N permits per refresh period | `RequestNotPermitted` |
| **Bulkhead** | Everything else from one slow dependency | Cap concurrent calls (semaphore or dedicated pool) | `BulkheadFullException` |
| **Fallback** | The user experience | Cached, default or degraded response | — |

The **order of composition matters**, and so does where the fallback sits (§3).

---

## 2. Circuit breaker internals 🔥

```
         failure or slow rate ≥ threshold        waitDurationInOpenState elapsed
         (after minimumNumberOfCalls)              (next call, or automatic transition)
 CLOSED ───────────────────────────────► OPEN ─────────────────────────────────────► HALF_OPEN
   ▲  records every call in a sliding       rejects all calls                          permits N trial calls
   │  window (COUNT_BASED: last N calls;    (CallNotPermittedException)                │
   │  TIME_BASED: last N seconds)                                                       │
   └──────────── trial calls below the thresholds ◄─────────────────────────────────────┤
                                                    trial calls above the thresholds ──► OPEN
 Also: DISABLED, FORCED_OPEN (manual), METRICS_ONLY. Ignored exceptions are neither failures nor successes.
```

### 2.1 Runnable: driving the state machine call by call

<!-- run: javac cp=@p6web timeout=120 -->
```java
package demo.resilience;

import io.github.resilience4j.circuitbreaker.*;
import io.github.resilience4j.micrometer.tagged.TaggedCircuitBreakerMetrics;
import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Duration;
import java.util.TreeSet;
import java.util.function.Supplier;

public class CircuitBreakerStates {
    static int calls;

    public static void main(String[] args) throws Exception {
        CircuitBreakerConfig config = CircuitBreakerConfig.custom()
            .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
            .slidingWindowSize(10)                       // judge the last 10 calls
            .minimumNumberOfCalls(5)                     // …but not before 5 calls were recorded
            .failureRateThreshold(50)                    // open at ≥ 50% failures
            .slowCallDurationThreshold(Duration.ofMillis(50))
            .slowCallRateThreshold(50)                   // …or at ≥ 50% slow calls
            .waitDurationInOpenState(Duration.ofMillis(300))
            .permittedNumberOfCallsInHalfOpenState(3)
            .ignoreExceptions(IllegalArgumentException.class)   // a caller's bug is not the dependency's fault
            .build();
        CircuitBreakerRegistry registry = CircuitBreakerRegistry.of(config);
        CircuitBreaker cb = registry.circuitBreaker("inventory");
        cb.getEventPublisher().onStateTransition(e -> System.out.println("   ** " + e.getStateTransition()));

        SimpleMeterRegistry meters = new SimpleMeterRegistry();
        TaggedCircuitBreakerMetrics.ofCircuitBreakerRegistry(registry).bindTo(meters);

        System.out.println("1. 3 failures, 1 ignored IllegalArgumentException, 1 success (4 recorded < minimumNumberOfCalls):");
        for (int i = 0; i < 3; i++) call(cb, () -> { throw new IllegalStateException("503 from inventory"); });
        call(cb, () -> { throw new IllegalArgumentException("bad SKU"); });
        call(cb, () -> "ok");
        print(cb);

        System.out.println("2. one more failure: 5 recorded, 4 failed = 80% ≥ 50%:");
        call(cb, () -> { throw new IllegalStateException("503 from inventory"); });
        print(cb);

        System.out.println("3. while OPEN, calls fail fast without touching the dependency:");
        int before = calls;
        call(cb, () -> "ok");
        System.out.println("   dependency invoked: " + (calls - before) + " times");

        System.out.println("4. after waitDurationInOpenState, 3 trial calls succeed:");
        Thread.sleep(400);
        for (int i = 0; i < 3; i++) call(cb, () -> "ok");
        print(cb);

        System.out.println("5. slow calls also open it (6 calls of 80 ms > 50 ms threshold):");
        for (int i = 0; i < 6; i++) call(cb, () -> { sleep(80); return "ok but slow"; });
        print(cb);

        System.out.println("6. half-open trials fail → back to OPEN:");
        Thread.sleep(400);
        for (int i = 0; i < 3; i++) call(cb, () -> { throw new IllegalStateException("still down"); });
        print(cb);

        System.out.println("7. Micrometer meters: " + new TreeSet<>(meters.getMeters().stream().map(m -> m.getId().getName()).toList()));
    }

    static void call(CircuitBreaker cb, Supplier<String> dependency) {
        try {
            cb.executeSupplier(() -> { calls++; return dependency.get(); });
        } catch (CallNotPermittedException e) {
            System.out.println("   rejected: " + e.getMessage());
        } catch (RuntimeException e) { /* recorded (or ignored) by the breaker */ }
    }
    static void print(CircuitBreaker cb) {
        var m = cb.getMetrics();
        System.out.printf("   state=%s buffered=%d failed=%d slow=%d failureRate=%.1f%% slowRate=%.1f%%%n", cb.getState(),
            m.getNumberOfBufferedCalls(), m.getNumberOfFailedCalls(), m.getNumberOfSlowCalls(), m.getFailureRate(), m.getSlowCallRate());
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { throw new RuntimeException(e); } }
}
```

Output (verified):

```
1. 3 failures, 1 ignored IllegalArgumentException, 1 success (4 recorded < minimumNumberOfCalls):
   state=CLOSED buffered=4 failed=3 slow=0 failureRate=-1.0% slowRate=-1.0%
2. one more failure: 5 recorded, 4 failed = 80% ≥ 50%:
   ** State transition from CLOSED to OPEN
   state=OPEN buffered=5 failed=4 slow=0 failureRate=80.0% slowRate=0.0%
3. while OPEN, calls fail fast without touching the dependency:
   rejected: CircuitBreaker 'inventory' is OPEN and does not permit further calls
   dependency invoked: 0 times
4. after waitDurationInOpenState, 3 trial calls succeed:
   ** State transition from OPEN to HALF_OPEN
   ** State transition from HALF_OPEN to CLOSED
   state=CLOSED buffered=0 failed=0 slow=0 failureRate=-1.0% slowRate=-1.0%
5. slow calls also open it (6 calls of 80 ms > 50 ms threshold):
   ** State transition from CLOSED to OPEN
   rejected: CircuitBreaker 'inventory' is OPEN and does not permit further calls
   state=OPEN buffered=5 failed=0 slow=5 failureRate=0.0% slowRate=100.0%
6. half-open trials fail → back to OPEN:
   ** State transition from OPEN to HALF_OPEN
   ** State transition from HALF_OPEN to OPEN
   state=OPEN buffered=3 failed=3 slow=0 failureRate=100.0% slowRate=0.0%
7. Micrometer meters: [resilience4j.circuitbreaker.buffered.calls, resilience4j.circuitbreaker.calls, resilience4j.circuitbreaker.failure.rate, resilience4j.circuitbreaker.not.permitted.calls, resilience4j.circuitbreaker.slow.call.rate, resilience4j.circuitbreaker.slow.calls, resilience4j.circuitbreaker.state]
```

* **Nothing is judged before `minimumNumberOfCalls`.** With 4 recorded calls the failure rate is reported as `-1`, so a breaker on a low-traffic endpoint may *never* open. Size `minimumNumberOfCalls` to your traffic, or use a `TIME_BASED` window.
* **Ignored exceptions don't count** (the `IllegalArgumentException` wasn't recorded). Ignore client errors (4xx, validation), or one bad caller can open the breaker for everyone. With `recordExceptions`/`ignoreExceptions` or a `recordException` predicate, classify carefully: HTTP 503 and timeouts are failures, 404 is not.
* **OPEN means zero calls to the dependency** (step 3). That's the point: it gives the dependency room to recover and frees your threads immediately.
* **HALF_OPEN** permits `permittedNumberOfCallsInHalfOpenState` trial calls. All succeeding closes it with a **fresh window** (`buffered=0`); failing reopens it (step 6).
* **Slow calls count too** (step 5). A dependency that answers in 3 s instead of 50 ms is often worse than one that fails fast. Set `slowCallDurationThreshold` just above the healthy p99.
* **Meters** (verified names) for dashboards and alerts: `resilience4j.circuitbreaker.state`, `.calls` (tagged by kind), `.failure.rate`, `.slow.call.rate`, `.not.permitted.calls`, `.buffered.calls`, `.slow.calls`. Alert when state is OPEN for longer than N minutes.

---

## 3. Retry, rate limiter, bulkheads, and composition order 🔥

### 3.1 Runnable: backoff, permits, concurrency caps, and what the breaker sees

<!-- run: javac cp=@p6web timeout=120 -->
```java
package demo.resilience;

import io.github.resilience4j.bulkhead.*;
import io.github.resilience4j.circuitbreaker.*;
import io.github.resilience4j.core.IntervalFunction;
import io.github.resilience4j.decorators.Decorators;
import io.github.resilience4j.ratelimiter.*;
import io.github.resilience4j.retry.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Supplier;

public class RetryRateLimitBulkhead {
    public static void main(String[] args) throws Exception {
        // 1. retry with exponential backoff: which exceptions, how long between attempts
        RetryConfig retryConfig = RetryConfig.custom()
            .maxAttempts(4)                                                  // 1 call + 3 retries
            .intervalFunction(IntervalFunction.ofExponentialBackoff(Duration.ofMillis(50), 2.0))
            .retryExceptions(TimeoutException.class)
            .ignoreExceptions(IllegalArgumentException.class)
            .build();
        Retry retry = Retry.of("pricing", retryConfig);
        List<Long> waits = new ArrayList<>();
        retry.getEventPublisher().onRetry(e -> waits.add(e.getWaitInterval().toMillis()));
        int[] attempts = {0};
        String price = retry.executeCallable(() -> { if (++attempts[0] < 4) throw new TimeoutException("slow"); return "9.99"; });
        System.out.println("1. retry: result=" + price + " after " + attempts[0] + " attempts, waits(ms)=" + waits);
        attempts[0] = 0;
        try { retry.executeCallable(() -> { attempts[0]++; throw new IllegalArgumentException("bad request"); }); }
        catch (IllegalArgumentException e) { System.out.println("   non-retryable IllegalArgumentException: attempts=" + attempts[0]); }
        System.out.println("   jittered backoff (randomizationFactor 0.5) stays within ±50%: " + jitterBounds());

        // 2. rate limiter: 5 permits per 1 s period, don't wait for a permit
        RateLimiter limiter = RateLimiter.of("partnerApi", RateLimiterConfig.custom()
            .limitForPeriod(5).limitRefreshPeriod(Duration.ofSeconds(1)).timeoutDuration(Duration.ZERO).build());
        int allowed = 0; String rejection = "";
        for (int i = 0; i < 12; i++) {
            try { limiter.executeSupplier(() -> "ok"); allowed++; }
            catch (RequestNotPermitted e) { rejection = e.getMessage(); }
        }
        System.out.println("2. rate limiter: 12 calls → allowed=" + allowed + ", rejected=" + (12 - allowed) + " (\"" + rejection + "\")");

        // 3. semaphore bulkhead: at most 3 concurrent calls, no waiting
        Bulkhead bulkhead = Bulkhead.of("reports", BulkheadConfig.custom().maxConcurrentCalls(3).maxWaitDuration(Duration.ZERO).build());
        System.out.println("3. semaphore bulkhead: " + flood(10, () -> bulkhead.executeSupplier(RetryRateLimitBulkhead::slowReport)));

        // 4. thread-pool bulkhead: 2 threads + queue of 2, everything else rejected
        ThreadPoolBulkhead pool = ThreadPoolBulkhead.of("exports", ThreadPoolBulkheadConfig.custom()
            .coreThreadPoolSize(2).maxThreadPoolSize(2).queueCapacity(2).build());
        int accepted = 0, rejected = 0;
        List<CompletionStage<String>> futures = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            try { futures.add(pool.executeSupplier(RetryRateLimitBulkhead::slowReport)); accepted++; }
            catch (BulkheadFullException e) { rejected++; }
        }
        for (var f : futures) f.toCompletableFuture().join();
        System.out.println("4. thread-pool bulkhead: accepted=" + accepted + " (2 running + 2 queued), rejected=" + rejected);
        pool.close();

        // 5. decorator order decides what the circuit breaker counts
        for (boolean retryOutside : new boolean[] {true, false}) {
            CircuitBreaker cb = CircuitBreaker.of("cb", CircuitBreakerConfig.custom().minimumNumberOfCalls(100).build());
            Retry r = Retry.of("r", RetryConfig.custom().maxAttempts(3).waitDuration(Duration.ofMillis(1)).build());
            Supplier<String> failing = () -> { throw new IllegalStateException("down"); };
            Supplier<String> decorated = retryOutside
                ? Retry.decorateSupplier(r, CircuitBreaker.decorateSupplier(cb, failing))
                : CircuitBreaker.decorateSupplier(cb, Retry.decorateSupplier(r, failing));
            try { decorated.get(); } catch (IllegalStateException e) { }
            System.out.println("5. " + (retryOutside ? "Retry(CircuitBreaker(call)): " : "CircuitBreaker(Retry(call)): ")
                + "circuit breaker recorded " + cb.getMetrics().getNumberOfFailedCalls() + " failed call(s) for 1 user request");
        }

        // 6. the fluent builder applies decorators inside-out in the order you list them
        Supplier<String> stack = Decorators.ofSupplier(() -> "price")
            .withBulkhead(Bulkhead.ofDefaults("b"))
            .withCircuitBreaker(CircuitBreaker.ofDefaults("c"))
            .withRetry(Retry.ofDefaults("r"))
            .withFallback(List.of(CallNotPermittedException.class, BulkheadFullException.class), e -> "cached price")
            .decorate();
        System.out.println("6. Decorators: " + stack.get());
    }

    static String jitterBounds() {
        IntervalFunction f = IntervalFunction.ofExponentialRandomBackoff(Duration.ofMillis(100), 2.0, 0.5);
        long min = Long.MAX_VALUE, max = 0;
        for (int i = 0; i < 1000; i++) { long v = f.apply(3); min = Math.min(min, v); max = Math.max(max, v); }
        return "attempt 3 nominal 400 ms → observed " + (min >= 200 ? "≥200" : min) + " and " + (max <= 600 ? "≤600" : max);
    }
    static String slowReport() { try { Thread.sleep(300); } catch (InterruptedException e) { } return "report"; }
    static String flood(int n, Supplier<String> call) throws Exception {
        List<String> outcomes = new CopyOnWriteArrayList<>();
        try (var vts = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < n; i++) vts.submit(() -> {
                try { call.get(); outcomes.add("ok"); } catch (BulkheadFullException e) { outcomes.add("full"); }
            });
        }
        return "10 concurrent calls → ok=" + outcomes.stream().filter("ok"::equals).count() + ", rejected=" + outcomes.stream().filter("full"::equals).count();
    }
}
```

Output (verified):

```
1. retry: result=9.99 after 4 attempts, waits(ms)=[50, 100, 200]
   non-retryable IllegalArgumentException: attempts=1
   jittered backoff (randomizationFactor 0.5) stays within ±50%: attempt 3 nominal 400 ms → observed ≥200 and ≤600
2. rate limiter: 12 calls → allowed=5, rejected=7 ("RateLimiter 'partnerApi' does not permit further calls")
3. semaphore bulkhead: 10 concurrent calls → ok=3, rejected=7
4. thread-pool bulkhead: accepted=4 (2 running + 2 queued), rejected=6
5. Retry(CircuitBreaker(call)): circuit breaker recorded 3 failed call(s) for 1 user request
5. CircuitBreaker(Retry(call)): circuit breaker recorded 1 failed call(s) for 1 user request
6. Decorators: price
```

1. **Exponential backoff** (50 → 100 → 200 ms) between 4 attempts. Exceptions not in `retryExceptions` (here `IllegalArgumentException`, a client error) are **not retried**. In production always use **jitter** (`ofExponentialRandomBackoff`): with `randomizationFactor` 0.5, the 400 ms wait spreads over 200–600 ms (verified), so a thousand clients don't retry in lockstep.
2. **Rate limiter**: 5 permits per period, so calls 6–12 were rejected immediately (`timeoutDuration = 0`). A non-zero timeout makes callers *wait* for the next period, which is fine for batch jobs and dangerous on request threads.
3. **Semaphore bulkhead**: 3 concurrent calls, the other 7 rejected **instantly**. It runs on the caller's thread, which is a perfect fit with virtual threads.
4. **Thread-pool bulkhead**: 2 threads + queue of 2 = 4 accepted, 6 rejected. It isolates by running on its own pool (and returns `CompletionStage`). Use it when the caller must not block, or the dependency's client isn't interruptible.
5. **Order changes the numbers:** `Retry(CircuitBreaker(call))` lets the breaker see **every attempt** (3 failures per user request), so it opens sooner, and once OPEN the retry immediately gets `CallNotPermittedException`. Don't retry on that. `CircuitBreaker(Retry(call))` hides retries from the breaker (1 failure per request).
6. The `Decorators` builder applies decorators in the order listed (innermost first): `Retry(CircuitBreaker(Bulkhead(call)))` plus a fallback for "not permitted / full".

### 3.2 Runnable: the Spring Boot annotation stack, and the fallback trap

<!-- run: javac cp=@p6web timeout=200 -->
```java
package demo.resilience.boot;

import io.github.resilience4j.bulkhead.annotation.Bulkhead;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.core.Ordered;

public class AnnotationOrder {
    public static class InventoryClient {
        final AtomicInteger attempts = new AtomicInteger();
        @Retry(name = "inventory")
        @CircuitBreaker(name = "inventory", fallbackMethod = "cachedStock")
        @RateLimiter(name = "inventory")
        @Bulkhead(name = "inventory")
        public int stock(String sku) { attempts.incrementAndGet(); throw new IllegalStateException("inventory 503"); }
        int cachedStock(String sku, Throwable t) { return -1; }                  // fallback: same args + the exception

        @Retry(name = "inventory2", fallbackMethod = "cachedStock")             // fallback on the OUTERMOST aspect
        @CircuitBreaker(name = "inventory2")
        public int stock2(String sku) { attempts.incrementAndGet(); throw new IllegalStateException("inventory 503"); }

        public int attempts() { return attempts.getAndSet(0); }
    }
    @SpringBootConfiguration @EnableAutoConfiguration @Import(InventoryClient.class) static class App { }

    public static void main(String[] args) {
        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setWebApplicationType(WebApplicationType.NONE);
        sa.setDefaultProperties(Map.of("logging.level.root", "OFF",
            "spring.autoconfigure.exclude", "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration",
            "resilience4j.retry.instances.inventory.max-attempts", "3",
            "resilience4j.retry.instances.inventory.wait-duration", "10ms",
            "resilience4j.retry.instances.inventory2.max-attempts", "3",
            "resilience4j.retry.instances.inventory2.wait-duration", "10ms",
            "resilience4j.circuitbreaker.configs.default.minimum-number-of-calls", "50"));
        try (var ctx = sa.run()) {
            InventoryClient client = ctx.getBean(InventoryClient.class);
            for (String name : List.of("inventory", "inventory2")) {
                int result = name.equals("inventory") ? client.stock("SKU-1") : client.stock2("SKU-1");
                System.out.printf("%-10s fallback on %-15s result=%d, target invoked %d time(s), circuit breaker recorded %d failure(s)%n",
                    name, name.equals("inventory") ? "@CircuitBreaker:" : "@Retry:", result, client.attempts(),
                    ctx.getBean(CircuitBreakerRegistry.class).circuitBreaker(name).getMetrics().getNumberOfFailedCalls());
            }
            System.out.println("aspect order (lower = outer):");
            Map<Integer, String> order = new TreeMap<>();
            for (String bean : ctx.getBeanNamesForType(Ordered.class)) {
                Object b = ctx.getBean(bean);
                if (b.getClass().getName().startsWith("io.github.resilience4j") && b.getClass().getSimpleName().endsWith("Aspect"))
                    order.put(((Ordered) b).getOrder(), b.getClass().getSimpleName());
            }
            order.forEach((k, v) -> System.out.printf("  order %d (LOWEST_PRECEDENCE%+d) %s%n", k, (long) k - Ordered.LOWEST_PRECEDENCE, v));
        }
    }
}
```

Output (verified):

```
inventory  fallback on @CircuitBreaker: result=-1, target invoked 1 time(s), circuit breaker recorded 1 failure(s)
inventory2 fallback on @Retry:         result=-1, target invoked 3 time(s), circuit breaker recorded 3 failure(s)
aspect order (lower = outer):
  order 2147483642 (LOWEST_PRECEDENCE-5) RetryAspect
  order 2147483643 (LOWEST_PRECEDENCE-4) CircuitBreakerAspect
  order 2147483644 (LOWEST_PRECEDENCE-3) RateLimiterAspect
  order 2147483645 (LOWEST_PRECEDENCE-2) TimeLimiterAspect
  order 2147483646 (LOWEST_PRECEDENCE-1) BulkheadAspect
  order 2147483647 (LOWEST_PRECEDENCE+0) TimerAspect
```

* **Aspect order (verified):** `Retry` ( `CircuitBreaker` ( `RateLimiter` ( `TimeLimiter` ( `Bulkhead` ( method ) ) ) ) ). Lower order means outer. Change it with `resilience4j.retry.retry-aspect-order` and friends.
* **The fallback trap:** a `fallbackMethod` on the **inner** `@CircuitBreaker` converts the failure into a successful return value **before `@Retry` sees it**, so there are no retries at all (target invoked once). Put the fallback on the **outermost** annotation (here `@Retry`): 3 attempts, all 3 recorded by the breaker, then the fallback.
* Fallback methods must have the same parameters plus a trailing `Throwable` (or a more specific exception type), and live in the same bean.

---

## 4. Choosing parameters (a defensible starting point) ⚡

| Setting | Start with | Reasoning |
|---|---|---|
| Client timeout | p99.9 of the dependency × 1.5–2, **below** your own SLO | A timeout above your SLO protects nothing |
| `maxAttempts` | 2–3, **only for idempotent operations**, only for transient errors (timeouts, 503, connection reset) | Retries multiply load (3 layers × 3 attempts = 27×) |
| Backoff | Exponential from ~50–100 ms, ×2, **with jitter**, capped | Avoid synchronized retry storms |
| Retry budget | Retries ≤ ~10–20% of requests (token bucket) | Stops retry amplification during outages |
| CB window | `COUNT_BASED` 50–100 calls, or `TIME_BASED` 10–60 s for bursty traffic | Enough samples to be meaningful |
| `minimumNumberOfCalls` | ≈ calls per window at low traffic | Otherwise it never opens (rate −1) |
| `failureRateThreshold` / `slowCallRateThreshold` | 50% / 50–80% with `slowCallDurationThreshold` ≈ healthy p99 × 2 | |
| `waitDurationInOpenState` | 10–60 s (+ `automaticTransitionFromOpenToHalfOpenEnabled` if calls are rare) | Time for the dependency to recover |
| Bulkhead size | Little's law: dependency's req/s × p99 latency (in s) × headroom | Concurrency is the resource you actually share |

**Where do retries belong?** In **one** layer, as close to the failing call as possible. Never retry at every hop (client → gateway → service → dependency). Combine with **idempotency keys** for non-idempotent operations ([6.3 §5](03-Outbox-Saga-Idempotency.md#5-idempotency-keys-for-http-apis-)).

**Spring 7 core vs Resilience4j:** `@Retryable` and `@ConcurrencyLimit` (core Spring, [6.1 §4](01-Spring-Container-Internals-IoC-AOP.md#4-spring-7-additions-youll-meet-in-boot-4-code-)) cover retry and concurrency limits without a dependency. Circuit breakers, rate limiters, time limiters, thread-pool bulkheads and the metrics come from Resilience4j (directly, via `resilience4j-spring-boot4`, or behind Spring Cloud CircuitBreaker). Don't stack both retry mechanisms on one call path.

---

## 5. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| Dependency outage turns into **your** outage (threads/connections exhausted) | No timeouts or bulkhead; calls hang | Thread dump: many threads in the same client frame; `http.client.requests` latency | Timeouts everywhere; bulkhead; circuit breaker |
| Recovery takes ages after an outage, the dependency is flooded | Retry storms (no jitter, retries at every layer) | Request rate to the dependency spikes ×N after the incident | Jitter, retry budgets, one retry layer, `Retry-After` |
| Breaker never opens | `minimumNumberOfCalls` too high for the traffic; failures classified as ignored | `failure.rate` meter stuck at −1 | Tune window and minimum; fix exception classification |
| Breaker opens due to caller bugs | 4xx counted as failures | `calls{kind=failed}` correlates with client errors | `ignoreExceptions`/`recordException` predicate |
| Retries "don't happen" | Fallback on the inner `@CircuitBreaker`; self-invocation; non-retryable exception type | Target invocation count; retry metrics | Fallback on the outermost annotation; call through the proxy |
| Users see stale data unknowingly | Fallback serves cache silently | Fallback counter | Mark degraded responses (headers/fields); alert on fallback rate |
| Latency spikes at the rate limiter | `timeoutDuration` > 0 on request paths | `resilience4j.ratelimiter.waiting_threads` | Fail fast on request paths; queue in async jobs |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Explain the circuit breaker states and transitions in Resilience4j.</b></summary>

CLOSED records outcomes in a sliding window (count- or time-based). Once `minimumNumberOfCalls` are recorded, a failure or slow-call rate ≥ threshold opens it. OPEN rejects calls with `CallNotPermittedException` for `waitDurationInOpenState`, then moves to HALF_OPEN (on the next call, or automatically if enabled). HALF_OPEN permits N trial calls: below the thresholds it closes with a fresh window, otherwise it reopens. Ignored exceptions count as neither success nor failure. There are also manual states: DISABLED, FORCED_OPEN, METRICS_ONLY.
</details>

<details><summary><b>Q2. 🔥 Should Retry wrap the CircuitBreaker or the other way round?</b></summary>

Usually `Retry(CircuitBreaker(call))`, which is the Spring Boot annotation default (Retry has the outermost aspect, verified). The breaker sees every attempt, so it opens faster during outages, and the retry must not retry `CallNotPermittedException`. With `CircuitBreaker(Retry(call))` the breaker sees one outcome per user request and hides retry storms from the failure rate. Either way, place the fallback on the outermost layer, or retries silently stop.
</details>

<details><summary><b>Q3. ⚡ Semaphore bulkhead vs thread-pool bulkhead?</b></summary>

A semaphore bulkhead limits concurrent calls on the caller's thread (cheap; ideal with virtual threads; rejects or waits up to `maxWaitDuration`). A thread-pool bulkhead runs calls on a dedicated bounded pool with a queue and returns a `CompletionStage` (isolation even from non-interruptible clients, at the cost of thread hand-offs). Verified: 3 of 10 accepted with a 3-permit semaphore; 4 of 10 with 2 threads + a 2-slot queue.
</details>

<details><summary><b>Q4. ⚡ Why is "retry 3 times" dangerous in a microservice chain?</b></summary>

Retries multiply. With 3 attempts at each of 3 layers, one user request can become 27 calls to the failing service, exactly when it is overloaded. Synchronized retries (no jitter) cause thundering herds. Mitigations: retry only at one layer, only idempotent operations and transient errors, exponential backoff with jitter, retry budgets, honouring `Retry-After`, and a circuit breaker to stop retries entirely during outages.
</details>

<details><summary><b>Q5. 🧊 A team adds `@CircuitBreaker(fallbackMethod = …)` and `@Retry` to a method, and retries stop working. Why?</b></summary>

The CircuitBreaker aspect is inside the Retry aspect. Its fallback turns the exception into a normal return value before Retry observes it, so Retry sees success (verified: target invoked once). Move the fallback to the outermost annotation (`@Retry`), or handle fallback at the caller.
</details>

<details><summary><b>Q6. ⚡ How would you pick the circuit breaker parameters for a dependency doing 20 req/s with a p99 of 120 ms?</b></summary>

`COUNT_BASED` window ~100 calls (5 s of traffic) or `TIME_BASED` 10 s; `minimumNumberOfCalls` ~20; failure threshold 50%; `slowCallDurationThreshold` ~250–300 ms with a 50–80% slow-rate threshold; `waitDurationInOpenState` 10–30 s; 5–10 half-open trial calls. Pair it with a client timeout of ~300–400 ms, a bulkhead of ~20 × 0.12 × 2 ≈ 5 concurrent calls, and alerts on the OPEN state and fallback rate. Then validate in a load or chaos test.
</details>
