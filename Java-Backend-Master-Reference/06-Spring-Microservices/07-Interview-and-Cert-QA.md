# 6.7 · Pillar 6 — Interview & Certification Question Bank (Spring, Microservices, Resilience, Kafka)

> **Use:** A = flashcards, B = senior and architect scenarios, C = certification-style code questions with verified answers.
> **Exam scope:** Java SE 1Z0-830/831 doesn't cover Spring. Section C targets the **Spring Professional certification** (Broadcom 2V0-72.22: container, AOP, data access and transactions, Boot configuration; check the current exam guide on broadcom.com) and the reactive and messaging questions that appear in senior interviews. All questions are original. **Every program in C was run** (Spring Framework 7.0.10, Boot 4.1.2, Reactor 3.8.8, JDK 25).

---

## A. Rapid-fire

<details><summary><b>A1–A26</b></summary>

1. **When are singleton beans created in an `ApplicationContext`?** At `refresh()` (eagerly), unless `@Lazy`.
2. **What runs first: a `BeanFactoryPostProcessor` or the first bean constructor?** The BFPP (it edits definitions; [6.1 §1.1](01-Spring-Container-Internals-IoC-AOP.md#11-runnable-the-complete-lifecycle-in-the-order-spring-7-actually-calls-it)).
3. **Who calls `@PostConstruct`?** `CommonAnnotationBeanPostProcessor`, in `postProcessBeforeInitialization`, after custom BPPs (verified).
4. **Where are AOP proxies created?** `BeanPostProcessor.postProcessAfterInitialization` (`AbstractAutoProxyCreator`).
5. **Boot's default proxy type?** CGLIB (`spring.aop.proxy-target-class=true`).
6. **Does Boot allow circular references by default?** No (`spring.main.allow-circular-references=false`).
7. **Default scope of a `@Bean`?** Singleton. A prototype injected into a singleton is created **once**.
8. **`@Configuration(proxyBeanMethods=false)` effect?** Inter-bean method calls create new objects (lite mode).
9. **Spring 7 programmatic registration API?** `BeanRegistrar` (`@Import` it).
10. **Spring 7 core resilience annotations?** `@Retryable`, `@ConcurrencyLimit` (+ `@EnableResilientMethods`).
11. **Tomcat default max worker threads in Boot?** 200 (`server.tomcat.threads.max`).
12. **What does `spring.threads.virtual.enabled=true` change?** Tomcat, `@Async` and `@Scheduled` executors move to virtual threads, with no concurrency limit by default.
13. **Reactive Streams signal that carries demand?** `Subscription.request(n)`.
14. **`publishOn` default prefetch?** 256 (replenishes 192).
15. **What happens with `block()` on a `parallel` thread?** `IllegalStateException` ("not supported in thread parallel-N").
16. **Outbox in one sentence?** Write the event to a table in the same local transaction as the state change, then relay it.
17. **Idempotency-Key draft: in progress / payload mismatch / missing?** 409 / 422 / 400.
18. **Saga compensation must be…?** Idempotent, retryable, semantic (refund, not delete).
19. **Resilience4j CB failure rate before `minimumNumberOfCalls`?** −1 (not evaluated).
20. **Annotation aspect order (outer → inner)?** Retry → CircuitBreaker → RateLimiter → TimeLimiter → Bulkhead.
21. **Where should a Resilience4j fallback go when combining annotations?** On the outermost one.
22. **Kafka ordering guarantee?** Per partition only.
23. **Kafka 4.x producer defaults?** `acks=all`, idempotence on, `linger.ms=5`.
24. **Default `isolation.level`?** `read_uncommitted`.
25. **How do you opt into KIP-848?** `group.protocol=consumer` on the client.
26. **Two DLT header schemes in spring-kafka?** `kafka_dlt-*` (DeadLetterPublishingRecoverer) vs `kafka_*` (retry-topic DLT).

</details>

---

## B. Senior scenarios

<details><summary><b>B1. 🔥 Design the outbound call to a flaky partner API (p99 400 ms, SLA 99.5%) from a checkout service with a 1 s SLO.</b></summary>

Timeouts: connect 200 ms, read ~600 ms, overall deadline ~800 ms (below the SLO). One retry for idempotent GETs only (jittered, ~100 ms base), or an idempotency key for POSTs. A circuit breaker sized to traffic (time-based 30 s window, `minimumNumberOfCalls` ≈ traffic/window, 50% failure and slow-call thresholds with `slowCallDurationThreshold` ~800 ms, open 15–30 s). A bulkhead (≈ RPS × p99 × 2 concurrent calls). A fallback that degrades explicitly (cached quote, "price pending"). Metrics and alerts on breaker state, retry ratio and fallback rate. Run the call on virtual threads (or `StructuredTaskScope` for fan-out) so the waits don't consume platform threads.
</details>

<details><summary><b>B2. 🔥 You must publish `OrderPlaced` reliably to Kafka from a Spring/JPA service. Walk through the design and its failure cases.</b></summary>

In the same `@Transactional` method, save the order and insert an outbox row (aggregate ID, type, payload, `published_at` null). A relay claims rows with `FOR UPDATE SKIP LOCKED` (or Debezium CDC), sends with key = order ID, waits for the ack, then marks the row published. Failure cases: crash after send but before mark leads to a resend, so consumers must be idempotent (dedup table in the same transaction as their effect); out-of-order commits defeat high-water-mark relays, so use per-row status; outbox growth needs purging and partitioning; poison events need a DLT; and alert on the age of the oldest unpublished row. Alternative: Spring Modulith's Event Publication Registry.
</details>

<details><summary><b>B3. ⚡ Migrate a Spring MVC service from a 400-thread Tomcat pool to virtual threads. What do you check?</b></summary>

Where the implicit 400-concurrency limit protected resources: Hikari pool size and `connectionTimeout`, HTTP client pools, partner rate limits. Add explicit limits (semaphores, `@ConcurrencyLimit`, bulkheads) and fast rejection. Check `@Async`/`@Scheduled` (unbounded `SimpleAsyncTaskExecutor`), `ThreadLocal`-heavy libraries (per-request allocation), pinning (JFR `jdk.VirtualThreadPinned`; JDK ≥ 24 for `synchronized`), and thread-dump tooling (`Thread.dump_to_file`). Re-run load tests looking at p99 and downstream saturation, not just throughput.
</details>

<details><summary><b>B4. ⚡ Choreography or orchestration for a 6-step travel booking (flight, hotel, car, insurance, payment, confirmation)?</b></summary>

Orchestration: many steps, conditional branches (no car, add insurance), timeouts per step, a visible state ("where is booking 123?"), and compensations in reverse order. Use a persisted state machine (or Temporal/Camunda) with idempotent commands keyed by saga ID, a pivot step (payment) ordered after likely failures, semantic locks (`PENDING` holds) to handle the lack of isolation, a recovery job for stuck sagas, and an outbox for the commands and events it emits.
</details>

<details><summary><b>B5. ⚡ Kafka consumer lag grows only during deploys. Diagnose and fix.</b></summary>

Likely eager rebalances on each pod restart (revoke-all, verified), possibly amplified by `max.poll.interval.ms` overruns during startup or by non-graceful shutdown losing uncommitted offsets. Fix: cooperative-sticky (two-step rollout of the strategy list) or `group.protocol=consumer`; static membership (`group.instance.id`); graceful shutdown with offset commits (`SmartLifecycle` stop before destroy); readiness gating; fewer, larger pods if the group is huge. Verify with `rebalance-rate-per-hour` and per-partition lag during a deploy.
</details>

<details><summary><b>B6. 🧊 Exactly-once from Kafka into PostgreSQL: is it possible?</b></summary>

Kafka transactions only cover Kafka writes plus offsets. For a database sink, store the consumed offsets **in the database, in the same transaction** as the effect (and seek to them on assignment), or make the effect idempotent with a dedup key in that same transaction. Then commit Kafka offsets for bookkeeping. The outcome is effectively-once, without XA.
</details>

---

## C. Certification-style code questions (verified)

### C1 — Prototype into singleton

<!-- run: javac cp=@p6web -->
```java
package quiz.c1;

import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.*;

public class Scopes {
    static final AtomicInteger created = new AtomicInteger();
    public static class Cart { final int id = created.incrementAndGet(); }
    public static class Shop {
        final Cart cart; final ObjectProvider<Cart> carts;
        public Shop(Cart cart, ObjectProvider<Cart> carts) { this.cart = cart; this.carts = carts; }
    }
    @Configuration static class Config {
        @Bean @Scope("prototype") Cart cart() { return new Cart(); }
        @Bean Shop shop(Cart cart, ObjectProvider<Cart> carts) { return new Shop(cart, carts); }
    }
    public static void main(String[] args) {
        try (var ctx = new AnnotationConfigApplicationContext(Config.class)) {
            Shop a = ctx.getBean(Shop.class), b = ctx.getBean(Shop.class);
            System.out.println((a == b) + " " + a.cart.id + " " + b.cart.id + " " + a.carts.getObject().id + " " + a.carts.getObject().id
                + " " + ctx.getBean(Cart.class).id + " created=" + created.get());
        }
    }
}
```

<details><summary>Answer</summary>

`true 1 1 2 3 4 created=4`. `Shop` is a singleton (`a == b`). The prototype `Cart` injected into it was created **once**, when `Shop` was created (id 1). Each `ObjectProvider.getObject()` creates a fresh prototype (2, 3), and so does each `getBean(Cart.class)` (4). Use `ObjectProvider`, `@Lookup` methods or scoped proxies when a singleton needs fresh prototypes.
</details>

### C2 — Property sources and relaxed binding

<!-- run: javac cp=@p6web -->
```java
package quiz.c2;

import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

public class Binding {
    @ConfigurationProperties("payments.client")
    public record ClientProps(Duration readTimeout, int maxRetries, String baseUrl) { }

    @SpringBootConfiguration @EnableConfigurationProperties(ClientProps.class)
    static class App {
        @Value("${payments.client.base-url:http://default}") String viaValue;
        @Value("${payments.client.missing:#{null}}") String missing;
    }

    public static void main(String[] args) {
        System.setProperty("PAYMENTS_CLIENT_MAX_RETRIES", "7");                 // env-var style name, as a system property
        SpringApplication app = new SpringApplication(App.class);
        app.setWebApplicationType(WebApplicationType.NONE);
        app.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        app.setDefaultProperties(Map.of("logging.level.root", "OFF", "payments.client.read-timeout", "750ms",
            "payments.client.max-retries", "3", "payments.client.baseUrl", "https://psp.example"));
        try (var ctx = app.run("--payments.client.read-timeout=2s")) {
            ClientProps p = ctx.getBean(ClientProps.class);
            App a = ctx.getBean(App.class);
            System.out.println(p.readTimeout() + " " + p.maxRetries() + " " + p.baseUrl() + " | " + a.viaValue + " " + a.missing);
        }
    }
}
```

<details><summary>Answer</summary>

`PT2S 3 https://psp.example | https://psp.example null`

* `read-timeout`: the command-line argument (`--…=2s`) beats default properties (750 ms) and is converted to a `Duration`.
* `max-retries`: **3, not 7.** The upper-case, underscore form (`PAYMENTS_CLIENT_MAX_RETRIES`) is a relaxed binding rule **for environment variables only**; as a *system property* that name doesn't map to `payments.client.max-retries`.
* `baseUrl` in camelCase still binds to the `baseUrl` record component, and the `@Value("${payments.client.base-url…}")` placeholder written in canonical kebab-case also resolved it: Boot lets `@Value` match relaxed forms **when the placeholder uses the canonical form**.
* `${…:#{null}}` yields `null` when the property is absent.
</details>

### C3 — `@Primary`, `@Qualifier`, `@Order` and collections

<!-- run: javac cp=@p6web -->
```java
package quiz.c3;

import java.util.List;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;

public class Resolution {
    public interface Notifier { String name(); }
    record Email() implements Notifier { public String name() { return "email"; } }
    record Sms() implements Notifier { public String name() { return "sms"; } }
    record Push() implements Notifier { public String name() { return "push"; } }

    public record Service(Notifier primary, Notifier sms, List<Notifier> all) { }

    @Configuration static class Config {
        @Bean @Order(3) Notifier email() { return new Email(); }
        @Bean @Order(1) @Primary Notifier sms() { return new Sms(); }
        @Bean @Order(2) Notifier push() { return new Push(); }
        @Bean Service service(Notifier any, @Qualifier("sms") Notifier sms, List<Notifier> all) { return new Service(any, sms, all); }
    }
    public static void main(String[] args) {
        try (var ctx = new AnnotationConfigApplicationContext(Config.class)) {
            Service s = ctx.getBean(Service.class);
            System.out.println(s.primary().name() + " " + s.sms().name() + " " + s.all().stream().map(Notifier::name).toList()
                + " " + ctx.getBeansOfType(Notifier.class).keySet());
        }
    }
}
```

<details><summary>Answer</summary>

`sms sms [sms, push, email] [email, sms, push]`. With three candidates, the unqualified single injection picks the `@Primary` bean (`sms`). `@Qualifier("sms")` selects by bean name. `List<Notifier>` injection is **sorted by `@Order`** (1 sms, 2 push, 3 email), while `getBeansOfType` returns registration order. `@Order` doesn't affect which single bean is injected; `@Primary` (or `@Priority`/qualifiers) does.
</details>

### C4 — `@EventListener` vs `@TransactionalEventListener`

<!-- run: javac cp=@p6web -->
```java
package quiz.c4;

import java.util.*;
import javax.sql.DataSource;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.*;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.annotation.*;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

public class Events {
    record OrderPlaced(int id) { }
    static final List<String> log = new ArrayList<>();

    public static class Listeners {
        @EventListener public void sync(OrderPlaced e) { log.add("sync-" + e.id()); }
        @TransactionalEventListener public void afterCommit(OrderPlaced e) { log.add("afterCommit-" + e.id()); }
        @TransactionalEventListener(phase = TransactionPhase.AFTER_ROLLBACK) public void afterRollback(OrderPlaced e) { log.add("afterRollback-" + e.id()); }
    }
    public static class Orders {
        final ApplicationEventPublisher events;
        public Orders(ApplicationEventPublisher events) { this.events = events; }
        @Transactional public void placeAndCommit(int id) { events.publishEvent(new OrderPlaced(id)); log.add("method-" + id); }
        @Transactional public void placeAndFail(int id) { events.publishEvent(new OrderPlaced(id)); throw new IllegalStateException(); }
        public void placeWithoutTransaction(int id) { events.publishEvent(new OrderPlaced(id)); }
    }
    @Configuration @EnableTransactionManagement static class Config {
        @Bean DataSource ds() { return new DriverManagerDataSource("jdbc:h2:mem:c4"); }
        @Bean DataSourceTransactionManager tm(DataSource ds) { return new DataSourceTransactionManager(ds); }
        @Bean Listeners listeners() { return new Listeners(); }
        @Bean Orders orders(ApplicationEventPublisher p) { return new Orders(p); }
    }
    public static void main(String[] args) {
        try (var ctx = new AnnotationConfigApplicationContext(Config.class)) {
            Orders orders = ctx.getBean(Orders.class);
            orders.placeAndCommit(1);
            try { orders.placeAndFail(2); } catch (IllegalStateException ignored) { }
            orders.placeWithoutTransaction(3);
            System.out.println(log);
        }
    }
}
```

<details><summary>Answer</summary>

`[sync-1, method-1, afterCommit-1, sync-2, afterRollback-2, sync-3]`

* `@EventListener` runs **synchronously inside `publishEvent`**, on the caller's thread and within its transaction (`sync-1` comes before `method-1`).
* `@TransactionalEventListener` (default `AFTER_COMMIT`) runs after the commit (`afterCommit-1`). For the failed transaction only the `AFTER_ROLLBACK` listener fires.
* With **no transaction** (event 3) transactional listeners are **not invoked at all**, because `fallbackExecution` defaults to `false`. Events published outside transactions silently vanish for those listeners.
</details>

### C5 — Reactor laziness and ordering

<!-- run: javac cp=@p6web -->
```java
package quiz.c5;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public class Laziness {
    static final AtomicInteger dbCalls = new AtomicInteger();
    static Mono<String> loadFromDb() { dbCalls.incrementAndGet(); return Mono.just("db"); }

    public static void main(String[] args) {
        String a = Mono.just("cache").switchIfEmpty(loadFromDb()).block();
        int afterA = dbCalls.get();
        String b = Mono.just("cache").switchIfEmpty(Mono.defer(Laziness::loadFromDb)).block();
        int afterB = dbCalls.get();
        Mono<String> neverSubscribed = Mono.fromCallable(() -> { dbCalls.incrementAndGet(); return "x"; });
        System.out.println(a + " " + afterA + " " + b + " " + afterB + " " + dbCalls.get());

        var flat = Flux.just(30, 10, 20).flatMap(ms -> Mono.delay(Duration.ofMillis(ms * 5)).thenReturn(ms)).collectList().block();
        var concat = Flux.just(30, 10, 20).concatMap(ms -> Mono.delay(Duration.ofMillis(ms * 5)).thenReturn(ms)).collectList().block();
        System.out.println(flat + " " + concat);
    }
}
```

<details><summary>Answer</summary>

```
cache 1 cache 1 1
[10, 20, 30] [30, 10, 20]
```

`switchIfEmpty(loadFromDb())` **calls `loadFromDb()` while assembling the pipeline**, so the database is hit even though the cache had a value (`dbCalls` = 1). `Mono.defer(...)` postpones the call until subscription, which never happens because the source isn't empty. A `Mono.fromCallable` that is never subscribed never runs (nothing happens until subscribe). `flatMap` subscribes to the inner publishers concurrently and emits in **completion order**; `concatMap` preserves **source order** (one inner at a time).
</details>

---

## D. Study map

| Topic | Files | Practise |
|---|---|---|
| Container, lifecycle, BPP/BFPP, cycles, proxies | [6.1](01-Spring-Container-Internals-IoC-AOP.md) | C1, C2, C3, A1–A10 |
| MVC + virtual threads vs WebFlux, backpressure | [6.2](02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md) | C5, A11–A15, B3 |
| Outbox, sagas, idempotency | [6.3](03-Outbox-Saga-Idempotency.md) | C4, A16–A18, B2, B4, B6 |
| Resilience4j | [6.4](04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md) | A19–A21, B1 |
| Kafka | [6.5](05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md) | A22–A26, B5, B6 |
| Incident response | [6.6](06-Production-Failure-Modes-Diagnostics.md) | Rehearse Stories 1–6 aloud: symptom → evidence → root cause → fix |
