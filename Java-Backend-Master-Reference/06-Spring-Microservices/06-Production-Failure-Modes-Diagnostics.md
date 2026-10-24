# 6.6 · Pillar 6 — Production Failure Modes & Diagnostic Checklist (Spring & Microservices)

> Microservice incidents are rarely one bug. They are **interactions**: a slow dependency plus missing timeouts plus retries plus a thread or connection limit. This file has composite war stories (each mechanism **reproduced in [6.1](01-Spring-Container-Internals-IoC-AOP.md)–[6.5](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md)**), the diagnostic toolkit, the health-check trap, metrics and alerts, and a review checklist.

---

## 1. Incident playbooks

### 🔥 Story 1 — "The recommendation API got slow, and checkout went down"

* **Symptom:** checkout p50 went from 80 ms to 2 s, then a flood of timeouts. Checkout itself was healthy; only the "you may also like" widget called the slow API.
* **Evidence:** thread dump: 200 of 200 Tomcat workers in `SocketInputStream.read` under the recommendation client. `tomcat.threads.busy = 200`. The outbound client had **no read timeout**.
* **Root cause:** one non-critical dependency consumed the shared request-thread pool. That is the 200-thread ceiling from [6.2 §2.1](02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md#21-runnable-boot-4-apps-on-tomcat-and-netty-under-400-concurrent-clients) (p50 doubled long before errors appeared).
* **Fix:** connect and read timeouts on every client; a **bulkhead** for the recommendation call; a circuit breaker with an empty-list fallback ([6.4](04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md)); the call made concurrently with a deadline (`StructuredTaskScope` or `CompletableFuture.orTimeout`).
* **Prevention:** chaos test (latency injection) per dependency; alert on `tomcat.threads.busy / max > 0.8`.

### 🔥 Story 2 — "We turned on virtual threads and the database fell over"

* **Symptom:** after `spring.threads.virtual.enabled=true`, throughput rose at first, then `Connection is not available, request timed out` errors, and a CPU spike on PostgreSQL.
* **Root cause:** Tomcat's 200-thread cap had been the **implicit** concurrency limit. With virtual threads, 3,000 concurrent requests reached the 30-connection pool and the database. A burst of `@Async` work ran unbounded too, because `SimpleAsyncTaskExecutor` has no concurrency limit by default ([6.2 §2.2](02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md#22-runnable-what-springthreadsvirtualenabledtrue-actually-switches)).
* **Fix:** explicit limits where the resource is: Hikari `connectionTimeout` of a few seconds, a semaphore or `@ConcurrencyLimit` on DB-heavy endpoints, `spring.task.execution.simple.concurrency-limit`, and fast rejection (`503` + `Retry-After`) instead of queueing.

### 🔥 Story 3 — "Retry storm after a 2-minute database blip"

* **Symptom:** the database recovered after 2 minutes, but the platform stayed down for 25 more.
* **Evidence:** the database saw 9× normal QPS after recovery; logs showed retries at the gateway, BFF **and** service layers, each with 3 attempts and fixed 100 ms delays.
* **Root cause:** retry amplification (3 × 3 × 3) with no jitter kept the database saturated ([6.4 §4](04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md#4-choosing-parameters-a-defensible-starting-point-)).
* **Fix:** retry at one layer only, exponential backoff **with jitter**, a retry budget, and a circuit breaker that stops retries when the dependency is down.

### 🔥 Story 4 — "Customers were charged twice"

* **Root cause:** the mobile client retried `POST /payments` after a timeout, while the first request was still processing. There was no idempotency key, and the server-side retry to the payment provider didn't forward a key either.
* **Fix:** `Idempotency-Key` with claim-first semantics, `409` while in progress and replay when done ([6.3 §5.1](03-Outbox-Saga-Idempotency.md#51-runnable-a-boot-endpoint-hammered-by-a-retrying-client)); the key forwarded to the provider.

### 🔥 Story 5 — "The warehouse never heard about 0.1% of orders"

* **Root cause:** `orderRepository.save(order); kafkaTemplate.send(event);`. Pods killed during deploys between commit and send lost events, and a failed commit after a send created ghost orders ([6.3 §2.1](03-Outbox-Saga-Idempotency.md#21-runnable-dual-writes-vs-outbox-a-crashing-relay-and-an-idempotent-consumer)).
* **Fix:** transactional outbox with a `SKIP LOCKED` relay (or Debezium), plus idempotent consumers in the warehouse.

### 🔥 Story 6 — "WebFlux service: p99 of 5 seconds at low CPU"

* **Evidence:** thread dump: `reactor-http-nio-*` threads in JDBC driver frames. A "quick" `repository.findById()` had been added to a reactive handler.
* **Root cause:** blocking on the event loop: 12 loops × 100 ms of blocking = 120 req/s for **all** endpoints ([6.2 §2.1](02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md#21-runnable-boot-4-apps-on-tomcat-and-netty-under-400-concurrent-clients)).
* **Fix:** R2DBC, or `subscribeOn(boundedElastic())` as a stopgap; BlockHound in CI. Long term: MVC + virtual threads for JDBC-based services.

### ⚡ Story 7 — "Consumer lag spikes on every deployment"

* **Root cause:** eager rebalances (the default `RangeAssignor` wins the strategy list) on every pod restart, and no static membership ([6.5 §2.1](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md#21-runnable-a-second-consumer-joins-a-6-partition-topic)).
* **Fix:** a two-phase rollout to `CooperativeStickyAssignor` (or `group.protocol=consumer`), `group.instance.id` per pod, and graceful shutdown so offsets are committed.

### ⚡ Story 8 — "One bad message stopped a partition for 6 hours"

* **Root cause:** the error handler used unlimited blocking retries for a deterministic failure (a JSON field the code couldn't parse).
* **Fix:** bounded retries; the exception registered as **not retryable**; a DLT with alerting ([6.5 §4.1](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md#41-runnable-poison-pills-non-retryable-errors-retry-topics-and-what-lands-in-the-dlt)); `ErrorHandlingDeserializer`.

### ⚡ Story 9 — "Downstream analytics stopped updating, yet producers were fine"

* **Root cause:** a producer instance hung mid-transaction. `read_committed` consumers cannot read past the LSO, so they stalled until the transaction timed out. A second issue: two instances shared one `transactional.id` and kept fencing each other (`InvalidProducerEpochException`).
* **Fix:** unique `transactional.id` per instance; a sane `transaction.timeout.ms`; alerts on LSO-stalled lag ([6.5 §3](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md#3-delivery-guarantees-and-exactly-once-)).

### ⚡ Story 10 — "Emails are sent synchronously and slow down signup"

* **Root cause:** `NotificationService.sendWelcome()` was `@Async`, but sat in a field-injection cycle with `UserService`. Spring handed out a **raw early reference**, so `@Async` was silently bypassed (on Spring 7 there was no startup error, [6.1 §2.1](01-Spring-Container-Internals-IoC-AOP.md#21-runnable-four-cycles-four-outcomes)).
* **Fix:** break the cycle (constructor injection makes it fail fast), and verify with `AopUtils.isAopProxy` in a test.

### ⚡ Story 11 — "The circuit breaker never opened during the outage"

* **Root cause:** `minimumNumberOfCalls=100` on an endpoint doing 30 calls per window (failure rate stuck at `-1`), and timeouts classified as ignored exceptions ([6.4 §2.1](04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md#21-runnable-driving-the-state-machine-call-by-call)).
* **Fix:** size windows to traffic; record timeouts and `5xx`; dashboard the `failure.rate` meter.

### ⚡ Story 12 — "Retries stopped working after we added a fallback"

* **Root cause:** `fallbackMethod` on `@CircuitBreaker`, which sits inside `@Retry`. Retry never saw a failure ([6.4 §3.2](04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md#32-runnable-the-spring-boot-annotation-stack-and-the-fallback-trap)).
* **Fix:** move the fallback to the outermost annotation.

### ⚡ Story 13 — "Kubernetes restarted every pod when the payment provider went down"

* **Root cause:** a team added the circuit-breaker health indicator to the **liveness** group, with a custom status mapping that made `CIRCUIT_OPEN` = `DOWN`. A downstream outage became "this pod is broken", followed by restarts, cold caches and a thundering herd.
* **Fix:** liveness = "the process is wedged" only. Readiness = "I can serve traffic" (consider dependencies carefully: if all pods share the same dependency, readiness failing everywhere just removes all capacity). Dependency state belongs on dashboards and alerts (§2.2).

---

## 2. Diagnostic toolkit

### 2.1 Spring Boot Actuator, Resilience4j and Kafka commands

```text
/actuator/health, /health/liveness, /health/readiness   probes (enabled automatically on Kubernetes)
/actuator/metrics/<name>, /actuator/prometheus           http.server.requests, tomcat.threads.*, hikaricp.*, resilience4j.*, spring.kafka.*
/actuator/threaddump (or jcmd <pid> Thread.dump_to_file -format=json <file> for virtual threads)
/actuator/loggers/<logger>  POST {"configuredLevel":"DEBUG"}   change log levels without a restart
/actuator/conditions, /beans, /configprops, /env (sanitized), /startup, /httpexchanges
/actuator/circuitbreakers, /circuitbreakerevents, /retries, /retryevents, /ratelimiters, /bulkheads   (resilience4j-spring-boot4)
kafka-consumer-groups.sh --bootstrap-server … --describe --group billing    lag per partition, owners, committed offsets
kafka-consumer-groups.sh … --reset-offsets --to-datetime … --execute       replay (group must be inactive)
kafka-transactions.sh --bootstrap-server … list / describe / abort        hung transactions blocking read_committed
```

### 2.2 Runnable: what an OPEN circuit breaker does to Actuator health

<!-- run: javac cp=@p6web timeout=200 -->
```java
package demo.health;

import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import java.net.URI;
import java.net.http.*;
import java.util.Map;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;

public class HealthAndBreakers {
    @SpringBootConfiguration @EnableAutoConfiguration static class App { }

    public static void main(String[] args) throws Exception {
        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setDefaultProperties(Map.of("server.port", "0", "logging.level.root", "OFF",
            "spring.autoconfigure.exclude", "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration",
            "management.endpoint.health.probes.enabled", "true",                    // automatic on Kubernetes
            "management.endpoint.health.show-details", "always",
            "management.health.circuitbreakers.enabled", "true",
            "resilience4j.circuitbreaker.instances.inventory.register-health-indicator", "true"));
        try (var ctx = sa.run(); HttpClient http = HttpClient.newHttpClient()) {
            String base = "http://localhost:" + ((WebServerApplicationContext) ctx).getWebServer().getPort() + "/actuator/health";
            var cb = ctx.getBean(CircuitBreakerRegistry.class).circuitBreaker("inventory");
            for (String state : new String[] {"CLOSED", "OPEN"}) {
                if (state.equals("OPEN")) cb.transitionToOpenState();
                System.out.printf("breaker %-6s → %s | /liveness %s | /readiness %s%n", state,
                    get(http, base), get(http, base + "/liveness"), get(http, base + "/readiness"));
            }
        }
    }

    static String get(HttpClient http, String url) throws Exception {
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create(url)).build(), HttpResponse.BodyHandlers.ofString());
        var json = new tools.jackson.databind.ObjectMapper().readTree(r.body());
        var breakers = json.path("components").path("circuitBreakers");
        return r.statusCode() + " " + json.path("status").asString() + (breakers.isMissingNode() ? ""
            : " (circuitBreakers=" + breakers.path("status").asString() + ", inventory=" + breakers.path("details").path("inventory").path("status").asString() + ")");
    }
}
```

Output (verified):

```
breaker CLOSED → 200 UP (circuitBreakers=UP, inventory=UP) | /liveness 200 UP | /readiness 200 UP
breaker OPEN   → 200 UP (circuitBreakers=UNKNOWN, inventory=CIRCUIT_OPEN) | /liveness 200 UP | /readiness 200 UP
```

* With `register-health-indicator=true`, an OPEN breaker reports **`CIRCUIT_OPEN`**, and the `circuitBreakers` component aggregates to **`UNKNOWN`**. The **overall status stays `UP`** with the default status order, and the **liveness and readiness groups are unaffected** (they contain only `livenessState`/`readinessState` by default).
* That default is usually right: a downstream outage shouldn't restart your pods (Story 13). If you map `CIRCUIT_OPEN` to `DOWN` (`management.health.status.order`/`http-mapping`), do it only for a dedicated health group that isn't used as a Kubernetes probe.

### 2.3 Graceful shutdown (verified defaults)

`server.shutdown=graceful` (the default in Boot 4.1.2 metadata) stops accepting new requests and lets in-flight ones finish, within `spring.lifecycle.timeout-per-shutdown-phase=30s`. `SmartLifecycle` beans (Kafka listener containers) stop **before** singletons are destroyed ([6.1 §1.1](01-Spring-Container-Internals-IoC-AOP.md#11-runnable-the-complete-lifecycle-in-the-order-spring-7-actually-calls-it)). On Kubernetes, the pod's `terminationGracePeriodSeconds` must exceed this, plus a short `preStop` sleep so endpoints are removed from load balancers before the app stops accepting.

---

## 3. Metrics and alerts

| Signal | Metric | Alert / meaning |
|---|---|---|
| Request latency and errors | `http.server.requests` (histogram, by `uri`/`status`) | SLO burn rate ([8.2 §3](../08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md#3-latency-metrics-that-aggregate-correctly-)) |
| Thread-pool saturation (MVC, platform threads) | `tomcat.threads.busy` / `tomcat.threads.config.max` | > 80% sustained |
| Connection-pool waits | `hikaricp.connections.pending`, `.acquire` | Pending > 0 sustained |
| Outbound dependency health | `http.client.requests` per `client.name` | p99 vs timeout; error rate |
| Breaker state | `resilience4j.circuitbreaker.state`, `.failure.rate`, `.not.permitted.calls` | OPEN > N minutes; not-permitted rate |
| Retries | `resilience4j.retry.calls{kind=successful_with_retry,failed_with_retry}` | Retry ratio > budget |
| Bulkhead and rate limiter rejections | `resilience4j.bulkhead.available.concurrent.calls`, `resilience4j.ratelimiter.waiting_threads` | Sustained zero availability |
| Kafka lag and rebalances | `records-lag-max`, exported group lag, `rebalance-rate-per-hour` | Lag growth; rebalances outside deploys |
| DLT traffic | Message rate on `*-dlt` topics | Any message |
| Outbox lag | Age of the oldest unpublished outbox row | > 1 minute |
| Saga health | Count of sagas per state older than N minutes | Any stuck saga |

---

## 4. Code-review checklist (Spring & microservices)

- [ ] Constructor injection; no circular dependencies; BPP/BFPP `@Bean` methods `static`.
- [ ] No self-invocation of proxied methods (`@Transactional`, `@Async`, `@Retryable`, `@Cacheable`); no field access through proxies.
- [ ] Every outbound call has connect and read timeouts and an overall deadline below the caller's SLO.
- [ ] Retries: only idempotent operations and transient errors; exponential backoff with jitter; one layer; budgeted.
- [ ] Circuit breakers: windows sized to traffic, exceptions classified, fallback on the outermost layer, state on dashboards.
- [ ] Bulkheads or concurrency limits around each scarce resource, **especially with virtual threads**.
- [ ] Non-idempotent endpoints accept `Idempotency-Key` (400/409/422 semantics); keys forwarded downstream.
- [ ] No dual writes: events go through an outbox or CDC; consumers are idempotent.
- [ ] Sagas persist state, have idempotent steps and compensations, timeouts, and a recovery job.
- [ ] Reactive code: no blocking on event loops (BlockHound in tests); explicit `flatMap` concurrency; bounded buffers; context propagation for MDC and tracing.
- [ ] Kafka: keys chosen for ordering and spread; cooperative or KIP-848 rebalancing; static membership; bounded retries plus a DLT with alerts; `read_committed` for transactional topics; unique `transactional.id`s.
- [ ] Health: liveness doesn't depend on downstream services; graceful shutdown fits within the pod's grace period.
