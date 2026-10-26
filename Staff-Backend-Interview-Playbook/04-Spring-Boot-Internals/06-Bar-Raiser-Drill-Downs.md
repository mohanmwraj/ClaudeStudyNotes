# 4.6 Bar-Raiser Drill-Downs: Spring Framework & Spring Boot Internals

> Evidence for every defense is in [4.1](01-IoC-Container-Startup-BeanDefinition-PostProcessors.md)–[4.5](05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md) (Spring Framework 7.0.10, Boot 4.1.2, Security 7.1.2, all run). Answer aloud, then open the defense.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "My `@PostConstruct` cache warm-up isn't transactional" 🔥

🎤 *"I annotated the warm-up method with `@Transactional` and call it from `@PostConstruct`."*

🔍 **Probe 1: Why doesn't it work?**

<details><summary>🛡️ Defense</summary>

`@PostConstruct` runs during initialization of the **raw target**. AOP proxies are created afterwards, in `BeanPostProcessor.postProcessAfterInitialization`. Verified order ([4.1 §1](01-IoC-Container-Startup-BeanDefinition-PostProcessors.md)): step 15 `@PostConstruct`, step 18 "AOP proxies are created here". And the call is a self-invocation anyway, so it would bypass the proxy even if one existed.
</details>

🔍 **Probe 2: Where should warm-up go?**

<details><summary>🛡️ Defense</summary>

After proxies and all singletons exist: `SmartInitializingSingleton.afterSingletonsInstantiated` (step 19), or an `ApplicationReadyEvent` listener (step 24), calling the transactional method **through another bean** (or `TransactionTemplate`). For Kubernetes, make readiness depend on warm-up: Boot's readiness state flips to accepting traffic after `ApplicationReadyEvent`, so heavy warm-up in a listener before that delays traffic correctly ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)).
</details>

🔍 **Probe 3 (L6): The warm-up takes 90 s and pods get killed. Now what?**

<details><summary>🛡️ Defense</summary>

Separate liveness from readiness: a `startupProbe` with a budget above the worst warm-up, liveness that only checks "the JVM isn't wedged", readiness gated on warm-up completion. Then shrink the warm-up: load lazily on first use with request coalescing, preload from a snapshot (Redis or a file in the image), or pre-compute in a job. And cut the rest of startup with Spring AOT + the JDK AOT cache (verified 1.85 s → 0.77 s, [4.2 §5](02-Circular-References-Singleton-Caches-AOT-CDS.md)).
</details>

---

## Drill 2: "After upgrading Spring Boot, the app fails with a circular dependency" ⚡

🔍 **Probe 1: It worked for years. What changed?**

<details><summary>🛡️ Defense</summary>

Spring Boot 2.6+ sets `spring.main.allow-circular-references=false`. The cycle always existed; it's now rejected. Verified output: `BeanCurrentlyInCreationException … Requested bean is currently in creation`, plus the failure analyzer's diagram (`a ↔ b`).
</details>

🔍 **Probe 2: Just set the flag to true?**

<details><summary>🛡️ Defense</summary>

It hides a design problem and relies on **early references**: B gets A before A's init callbacks ran and, if A is proxied, B must get the proxy. Verified: during injection, A sat in `earlySingletonObjects` ([4.2 §1](02-Circular-References-Singleton-Caches-AOT-CDS.md)). Constructor cycles can't be fixed by the flag at all (verified). Historically, `@Async` beans in cycles failed with "injected into other beans in its raw version". On Spring 7.0.10 the `@Async` case worked (B got the proxy), but any custom wrapping post-processor without early-reference support would silently hand out the raw object.
</details>

🔍 **Probe 3: Fix it properly.**

<details><summary>🛡️ Defense</summary>

Find the responsibility both classes need and extract it into a third bean; or use events if one side only notifies the other; or `ObjectProvider`/`@Lazy` at one injection point as a documented, local deferral (verified: `@Lazy` injected a `…$$SpringCGLIB$$0` lazy-resolution proxy). Move to constructor injection so new cycles fail at startup, and add module-level cycle checks (Spring Modulith/ArchUnit).
</details>

---

## Drill 3: "Pods take 45 s to start; scaling up during a spike is too slow" 🔥

🔍 **Probe 1: Where does startup time go, and how do you know?**

<details><summary>🛡️ Defense</summary>

Measure, don't guess: `BufferingApplicationStartup` + `/actuator/startup`, which gave verified steps like `spring.context.refresh 2439 ms`, `beans.post-process 1072 ms`, `config-classes.parse 700 ms` ([4.1 §4](01-IoC-Container-Startup-BeanDefinition-PostProcessors.md)). Separate JVM costs (class loading/linking, JIT) from Spring costs (configuration parsing, conditions, bean creation) from application costs (connection pools, warm-up, Flyway migrations at startup!).
</details>

🔍 **Probe 2: Options, with numbers.**

<details><summary>🛡️ Defense</summary>

Verified on the same service ([4.2 §5.1](02-Circular-References-Singleton-Caches-AOT-CDS.md)): plain **1.85 s**, Spring AOT **1.52 s** (no runtime configuration parsing), JDK AOT cache **1.03 s** (pre-loaded and pre-linked classes from a training run), both **0.77 s**. Plus: run migrations as a separate job, not on every pod start; avoid `spring.main.lazy-initialization` in production (it moves latency and failures to the first requests); GraalVM native for scale-to-zero with its build and reflection trade-offs.
</details>

🔍 **Probe 3 (L6): What are the constraints of Spring AOT that bite later?**

<details><summary>🛡️ Defense</summary>

The bean graph is decided **at build time**: profile- and property-based conditions are frozen, beans registered dynamically at runtime need care, and reflection-based tricks need hints. One artifact per environment configuration isn't acceptable for most teams, so keep environment differences in **values** (URLs, credentials), not in which beans exist. The AOT cache has its own constraint: same JDK build and same classpath, so create it inside the image build.
</details>

---

## Drill 4: "We'll just turn on virtual threads" ⚡

🔍 **Probe 1: What will improve?**

<details><summary>🛡️ Defense</summary>

Requests waiting on I/O no longer hold OS threads, so the Tomcat pool stops being the queue. Verified ([4.4 §1](04-Web-Concurrency-Tomcat-Virtual-Threads-WebFlux.md)): 400 concurrent clients on a 100 ms endpoint, **50 platform threads: 481 req/s, p50 816 ms** (zero errors, pure queueing); **virtual threads: 3,098 req/s, p50 108 ms**. `@Async` also moved to virtual threads (verified thread names).
</details>

🔍 **Probe 2: What gets worse?**

<details><summary>🛡️ Defense</summary>

The bottleneck moves downstream. 3,000 virtual threads hit a 20-connection Hikari pool, so `pending` climbs and requests time out at `connectionTimeout` instead of queueing in Tomcat. Downstream services get burst traffic they never saw before. CPU-bound endpoints gain nothing. Pinning on JDK 21–23 (`synchronized` around I/O; fixed for monitors in JDK 24+). `ThreadLocal`-heavy libraries multiply memory.
</details>

🔍 **Probe 3 (L6): Rollout plan.**

<details><summary>🛡️ Defense</summary>

JDK 24+ first. Inventory blocking-in-`synchronized` and ThreadLocal caches. Add **explicit concurrency limits** where the thread pool used to provide them implicitly: bulkheads per downstream, Spring 7 `@ConcurrencyLimit`, pool sizes from Little's law. Canary one service, compare p99, pool `pending`, downstream error rates and JFR `jdk.VirtualThreadPinned` events, then roll out.
</details>

---

## Drill 5: "Let's rewrite in WebFlux for performance" ⚡

🔍 **Probe: Convince me, or talk me out of it.**

<details><summary>🛡️ Defense</summary>

For I/O waiting, WebFlux and MVC on virtual threads performed the same in my test (2,959 vs 3,098 req/s, p50 105 vs 108 ms). The cost of reactive: a different programming model, harder debugging, lost `ThreadLocal`-based context (transactions, MDC, security need reactive equivalents), and a fatal failure mode: **one blocking call on the event loop** dropped throughput to **108 req/s with 92% `ConnectException`s** (verified). Choose WebFlux for streaming, backpressure, long-lived connections, or an already non-blocking stack. For a JDBC/JPA CRUD service on Java 21+, choose MVC + virtual threads.
</details>

---

## Drill 6: "Our metrics aspect reports 3× the real request count" 🧊

🔍 **Probe 1: Explain how that's possible.**

<details><summary>🛡️ Defense</summary>

Advice order. Verified ([4.3 §4](03-AOP-Proxies-JDK-vs-CGLIB-Self-Invocation-Ordering.md)): with Spring 7's `@Retryable` and `@Transactional` on one method plus `@Order(1)`/`@Order(2)` aspects, the **retry interceptor is outermost**, so every attempt re-entered both aspects (and opened a fresh transaction). Two failures + one success = three aspect invocations for one logical call.
</details>

🔍 **Probe 2: Make the aspect count logical calls, and make an audit aspect run inside the transaction.**

<details><summary>🛡️ Defense</summary>

Put the metrics concern outside the retry: a different bean wrapping the retried one, or count at the controller boundary. For the audit aspect: give the transaction advisor an explicit order (`@EnableTransactionManagement(order = 100)`) and the aspect a larger value (`@Order(200)`), so it's inside the transaction. Then **verify** with entry/exit logging or `Advised.getAdvisors()`, because ordering across mechanisms (retry libraries, Resilience4j aspects, custom BPPs) isn't uniform.
</details>

---

## Drill 7: "Every microservice validates JWTs. How exactly?" 🔥

🔍 **Probe 1: Walk through a request.**

<details><summary>🛡️ Defense</summary>

`DelegatingFilterProxy` → `FilterChainProxy` → first matching `SecurityFilterChain` → `BearerTokenAuthenticationFilter` extracts the token → `JwtAuthenticationProvider` → `JwtDecoder` verifies the signature against the issuer's JWKS (by `kid`), validates `exp`/`nbf`/`iss`/`aud` → the converter maps `scope` to `SCOPE_*` authorities → `AuthorizationFilter` and method security decide. Verified responses: no token **401**, tampered **401 `invalid_token`**, missing scope **403 `insufficient_scope`** ([4.5 §2](05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md)).
</details>

🔍 **Probe 2: A user is fired. How fast is their access gone?**

<details><summary>🛡️ Defense</summary>

With self-contained JWTs, not until `exp`. That's why access tokens should be short-lived (5–15 min) and refresh tokens revocable at the IdP. Where seconds matter (admin actions, payments): opaque tokens with introspection (cached briefly), or a revocation list keyed by `jti` or by user + "tokens issued before" timestamp, pushed to services.
</details>

🔍 **Probe 3: What's the audience check for?**

<details><summary>🛡️ Defense</summary>

A token minted for service A (say, a low-trust reporting tool) must not be accepted by service B (payments). Without `aud` validation, any valid token from the same issuer works everywhere. Configure `spring.security.oauth2.resourceserver.jwt.audiences`, and give services distinct audiences.
</details>

---

## Drill 8: "Add rate limiting to the API" ⚡

🔍 **Probe 1: Implement it in Spring.**

<details><summary>🛡️ Defense</summary>

A `OncePerRequestFilter` in the security chain **after** `BearerTokenAuthenticationFilter`, so the key is the authenticated subject: a token bucket per key, **429 + `Retry-After`** when empty. Verified: capacity 5 → `[200, 200, 200, 200, 200, 429, 429, 429]` ([4.5 §4](05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md)). Disable Boot's automatic servlet registration of the filter bean, or it may also run outside the security chain.
</details>

🔍 **Probe 2 (L6): 30 pods. What breaks?**

<details><summary>🛡️ Defense</summary>

Per-pod buckets give each user 30× the limit, unevenly (depending on load-balancer stickiness), and limits reset on every deploy. Quotas must be **shared**: at the gateway, or in Redis with an atomic Lua token bucket (or Bucket4j's distributed backends), keyed by tenant/API key, with a fail-open or fail-closed decision when Redis is down. Keep a local limiter as per-instance load shedding, and return consistent headers so clients can back off.
</details>

---

## Drill 9: "Customers occasionally see another customer's data" 🔥

🔍 **Probe: The controller and service are plain Spring beans. Where would you look first?**

<details><summary>🛡️ Defense</summary>

**Mutable state in a singleton.** Every bean is a singleton by default and shared by all request threads, so a field like `private Customer current;` set per request is a race: under concurrency, thread B overwrites it while thread A is still reading. The same happens with a prototype injected into a singleton (verified: the "prototype" was created once, `stale: 1, 1, 1`, [4.1 §2](01-IoC-Container-Startup-BeanDefinition-PostProcessors.md)), with `ThreadLocal`s that aren't cleared in `finally` (pooled threads reuse them), and with caches keyed without the tenant. Fix: stateless singletons, request state in parameters or request scope (with a scoped proxy), `ThreadLocal.remove()` in `finally`, tenant-aware cache keys.
</details>

---

## Drill 10: "Boot keeps using its own bean instead of ours" ⚡

🔍 **Probe: How do you find out why, and fix it?**

<details><summary>🛡️ Defense</summary>

Run with `--debug` or open `/actuator/conditions`: each auto-configuration lists matched and unmatched conditions with reasons (verified: `314 evaluated, matched 162, did not match 152`). Typical causes: your bean has a different **type** than the one `@ConditionalOnMissingBean` checks (e.g. you defined a `HikariDataSource` subclass Boot doesn't recognize, or a bean of the wrong interface); your configuration is in a package that isn't scanned; or Boot's auto-configuration was processed first because yours was imported as an auto-configuration without the right `before`/`after` ordering. Remember auto-configuration is a **deferred** import: user configuration is normally processed first, and conditional beans back off.
</details>

---

# Round 2: starters, the request lifecycle, events, async and shutdown (Batch 2 deep dive)

> Evidence for Round 2 is in [4.7](07-Auto-Configuration-Internals-Production-Starter-Blueprint.md), [4.8](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md) and the new verified sections of 4.1–4.5 (Spring Boot 4.1.2, Spring Framework 7.0.10, Spring Security 7.1.2, Tomcat 11.0.27, PostgreSQL 18.6). 🎤 candidate · 🔍 probe · 🛡️ staff-level defense.

---

## Drill 11: "Our platform starter works in most services, but in two of them its bean is missing" 🔥

🎤 *"It's annotated `@ConditionalOnBean(JdbcClient.class)` and those services definitely have a `JdbcClient`."*

🔍 **Probe 1: How can a condition say "no `JdbcClient`" in a context that has one?**

<details><summary>🛡️ Defense</summary>

`@ConditionalOnBean` sees only bean **definitions registered so far**. Auto-configurations are sorted by **name** first, then by `@AutoConfigureOrder` and `before`/`after`. Verified ([4.7 §5.2](07-Auto-Configuration-Internals-Production-Starter-Blueprint.md#52-ordering-trap-1-an-auto-configuration-without-after-verified-)): without `after`, `com.acme…` was evaluated before `org.springframework…JdbcClientAutoConfiguration`. The report said `did not find any beans of type …JdbcClient`, while the finished context had `JdbcClient beans=1`. The services where it "works" define their own `JdbcClient` in user configuration, which is registered before any auto-configuration.
</details>

🔍 **Probe 2: Fix it, and make sure it can't regress.**

<details><summary>🛡️ Defense</summary>

`@AutoConfiguration(afterName = "org.springframework.boot.jdbc.autoconfigure.JdbcClientAutoConfiguration")`: a string, so the starter needs no compile dependency on Boot 4's per-technology module. The regression test is an `ApplicationContextRunner` with **Boot's real auto-configurations** in `AutoConfigurations.of(...)`, which sorts exactly like Boot. It must list the whole chain: my first run omitted `JdbcTemplateAutoConfiguration`, and since `JdbcClientAutoConfiguration` is `@ConditionalOnSingleCandidate(NamedParameterJdbcTemplate)`, there was no `JdbcClient` at all (4.7 §5.5).
</details>

🔍 **Probe 3 (L6): A team copies the pattern into their app's `@Configuration`. Does it work there?**

<details><summary>🛡️ Defense</summary>

Never. Application configuration is processed before the deferred auto-configurations, so verified: `@ConditionalOnBean(JdbcClient)` in a user `@Configuration` → `NO MATCH` with `JdbcClient beans=1` (4.7 §5.3). In application code, inject `ObjectProvider<JdbcClient>` or make the bean unconditional. `@ConditionalOnBean`/`@ConditionalOnMissingBean` belong in ordered auto-configurations.
</details>

---

## Drill 12: "We enabled Spring AOT for startup time and now a feature flag doesn't work" ⚡

🎤 *"The flag is `feature.audit.enabled=true` in the deployment and the logs show it's set, but the audit bean never runs."*

🔍 **Probe: Why, and what's the fix?**

<details><summary>🛡️ Defense</summary>

AOT ran phase one (bean definitions, conditions, profiles) **at build time**, with the build's environment. Verified ([4.2 §9.1](02-Circular-References-Singleton-Caches-AOT-CDS.md#91-what-the-bean-graph-is-fixed-at-build-time-means-in-practice-verified)): with `-Dspring.aot.enabled=true`, the environment reported `feature.audit.enabled=true` and the `eu` profile active, yet both conditional beans were absent. The generated `registerBeanDefinitions` hard-codes 46 registrations and never mentions them. Nothing warns. Fixes:

* make runtime flags runtime decisions inside an always-present bean;
* or build one AOT artifact per bean graph (profile/properties set during `process-aot`).

Before enabling AOT or native images, review every `@Conditional…` that reads the environment, and run a startup test in AOT mode.
</details>

---

## Drill 13: "Our dashboards show almost no 5xx, but customers report errors" 🔥

🎤 *"We log every response status in a servlet filter."*

🔍 **Probe 1: What does your filter see for an exception the controller doesn't handle?**

<details><summary>🛡️ Defense</summary>

**`status=200`**, verified ([4.8 §1](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#1-the-request-lifecycle-verified-) scenario 3). The exception propagates out of the filter chain, the filter's `finally` reads the status before anything was written, and only then does Tomcat make an **ERROR dispatch** to `/error`. `BasicErrorController` writes the 500 there, and a `OncePerRequestFilter` skips that dispatch by default. The client got 500; the filter logged 200.
</details>

🔍 **Probe 2: And your interceptor-based error counter?**

<details><summary>🛡️ Defense</summary>

It misses the *handled* ones. When an `@ExceptionHandler` resolves the exception, `postHandle` is skipped and `afterCompletion` receives **`ex=null`** (verified, scenario 2). So the interceptor counts neither the 404s/409s from the advice nor, correctly, the unhandled 500. Measure from the response status at the outermost layer that sees the final response, or use Spring's `ServerHttpObservationFilter`, which catches the exception, records it and sets 500 (read from its bytecode).
</details>

🔍 **Probe 3: How do you make the error *contract* consistent too?**

<details><summary>🛡️ Defense</summary>

A catch-all `@ExceptionHandler` that returns `ProblemDetail` (so nothing reaches `/error`'s different JSON shape) plus `spring.mvc.problemdetails.enabled=true` for Spring MVC's own exceptions. Verified: an unmapped path became `application/problem+json` 404. The catch-all must not swallow security exceptions (Drill 17).
</details>

---

## Drill 14: "The audit row written in our `AFTER_COMMIT` listener is sometimes missing" 🔥

🎤 *"It works locally and in QA."*

🔍 **Probe 1: Where does that write run, transactionally?**

<details><summary>🛡️ Defense</summary>

After the publisher's transaction **committed**, on the same thread, with the transaction's resources still bound (the listener reported `txActive=true`). Spring's documentation says such writes "will not be committed". In my lab the outcome depended on configuration ([4.8 §2.1](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#21-the-after_commit-write-trap-proven-both-ways-)):

* **Kept** with Hikari's default `auto-commit=true`, because the transaction manager restores auto-commit during cleanup, which commits the stray work.
* **Lost** with `auto-commit=false`.

Listener order also differed between runs. "Works in QA" means "works with QA's pool settings".
</details>

🔍 **Probe 2: Fix it.**

<details><summary>🛡️ Defense</summary>

`@Transactional(propagation = REQUIRES_NEW)` on the listener. Row B survived in both configurations. Spring 6.1+ refuses a plain `@Transactional` on a `@TransactionalEventListener` at startup (verified `IllegalStateException`). If the audit row is a compliance requirement, an in-memory listener is the wrong tool: a crash between commit and callback loses it. Write it in the same transaction, or use an outbox or Modulith's registry.
</details>

🔍 **Probe 3: The same listener stopped firing entirely after a refactor. Why?**

<details><summary>🛡️ Defense</summary>

The publisher lost its transaction (the method moved, self-invocation, `@Transactional` removed). A `@TransactionalEventListener` is **silently skipped** when there's no transaction. Verified: only the `fallbackExecution = true` listener ran (scenario 7). Either set `fallbackExecution` deliberately, or assert in a test that the publisher is transactional.
</details>

---

## Drill 15: "After we added a thread pool for reports, request ids disappeared from async logs" ⚡

🎤 *"We only added a `ThreadPoolTaskExecutor` bean called `reportExecutor` and used it with `@Async("reportExecutor")`."*

🔍 **Probe: What else changed?**

<details><summary>🛡️ Defense</summary>

Boot's task-execution auto-configuration **backed off** (`spring.task.execution.mode=auto` by default): `applicationTaskExecutor` disappeared. Every *un-qualified* `@Async` now ran on the report pool, and the `TaskDecorator` bean that copied the MDC, which Boot applies only to the executor it builds, no longer applied. Verified ([4.8 §3](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#3-async-which-executor-what-context-where-exceptions-go-verified-)): `Executor beans: reportExecutor`, `report-1 requestId=null`. With `--spring.task.execution.mode=force`: `reportExecutor, applicationTaskExecutor` and `task-1 requestId=req-42`. Also, request-path async work now queued behind report jobs. Fix: `mode=force`, or build extra executors from `ThreadPoolTaskExecutorBuilder`, and qualify every `@Async`.
</details>

---

## Drill 16: "Every deploy causes a burst of 502s and a few half-processed orders" 🔥

🎤 *"We use rolling updates and readiness probes."*

🔍 **Probe 1: What does Boot do with an in-flight request when the pod gets SIGTERM?**

<details><summary>🛡️ Defense</summary>

With `server.shutdown=graceful` (the 4.1.2 default) it stops accepting connections and **waits** for in-flight requests, up to `spring.lifecycle.timeout-per-shutdown-phase` (30 s) per phase. Verified ([4.8 §4](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#4-graceful-shutdown-phase-by-phase-verified-)): a 1.5 s request in flight at `close()` completed with **200**, and a new connection during shutdown was refused. With `immediate`, the same request was interrupted (`InterruptedException`) and the client saw a dropped connection. The 502s are new requests still routed to the pod after its connector closed. That's the Kubernetes side: a preStop sleep until the endpoint is removed from load balancers, and a grace period ≥ preStop + slowest request + remaining phases ([7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)).
</details>

🔍 **Probe 2 (L6): Where do your Kafka consumers, outbox relay and executors stop relative to the web server?**

<details><summary>🛡️ Defense</summary>

Lifecycle phases stop from highest to lowest. Verified order:

1. Kafka-like consumers (`MAX-100`);
2. `webServerGracefulShutdown` (`MAX-1024`), which drains HTTP;
3. `webServerStartStop` (`MAX-2048`);
4. my relay (`MAX-4096`), so it publishes rows written by the drained requests;
5. `ThreadPoolTaskExecutor`s (`MAX/2`);
6. lower phases;
7. `@PreDestroy` last, where pools close.

The "half-processed orders" come from work that ignores this: background loops started in `@PostConstruct` with nothing stopping them in order, or executors that don't await their queued tasks (`spring.task.execution.shutdown.await-termination=false` by default).
</details>

---

## Drill 17: "Our error-rate alert fired: thousands of 500s from the admin API" ⚡

🎤 *"We added a global `@ExceptionHandler(Exception.class)` to return `ProblemDetail` for everything."*

🔍 **Probe: Which requests became 500s?**

<details><summary>🛡️ Defense</summary>

**Method-security denials.** Verified ([4.5 §9](05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md#9-deep-dive-who-writes-your-401-and-403-and-why-a-catch-all-handler-turns-403-into-500-verified-)): a `@PreAuthorize` failure is an `AuthorizationDeniedException` thrown *inside* the dispatcher, so the catch-all handled it and returned **500**. URL-rule denials and missing tokens never reach `@ControllerAdvice`: the filter chain writes them (empty body + `WWW-Authenticate`). Fix:

* add a specific `AccessDeniedException` handler (most specific wins) that maps to 403;
* implement `AuthenticationEntryPoint` and `AccessDeniedHandler` that write `ProblemDetail` while keeping the `WWW-Authenticate` challenge;
* test both rule types.
</details>

---

## Drill 18: "Our integration test overrides a property, but the app ignores it" 🧊

🎤 *"We pass it with `new SpringApplicationBuilder(App.class).properties("x=y")`."*

🔍 **Probe: Why is it ignored?**

<details><summary>🛡️ Defense</summary>

`properties(...)` sets **default properties**, the lowest-precedence source. Verified order ([4.1 §8.1](01-IoC-Container-Startup-BeanDefinition-PostProcessors.md#81-where-a-property-value-actually-comes-from-verified)):

1. command line;
2. system properties;
3. OS environment (relaxed binding: `LAB_KEY` → `lab.key`);
4. `application.properties`;
5. `defaultProperties` last.

The packaged `application.properties` won. In the 5.11 lab that meant `schema.sql` re-ran in every simulated restart. Use `--x=y` args, `@TestPropertySource` or `@DynamicPropertySource`. And print `environment.getPropertySources()` when in doubt.
</details>

---

## L5 vs L6 signal

| Topic | L5 | L6 |
|---|---|---|
| Lifecycle | Knows `@PostConstruct` and BPPs | Places logic at the right lifecycle step; ties readiness to it |
| Cycles | Uses `@Lazy` | Explains early references and proxy hazards; enforces module boundaries |
| Startup | "Enable lazy init" | Measures steps; combines Spring AOT and the JDK AOT cache; knows AOT's build-time constraints |
| Concurrency | Knows VT vs WebFlux | Uses Little's law; bounds downstream concurrency; has a migration and verification plan |
| AOP | Knows self-invocation | Knows ordering across interceptors and verifies it |
| Security | Configures a resource server | Reasons about JWKS rotation, audiences, revocation and fleet-wide rate limits |
| Starters (Round 2) | Writes an `@Configuration` with `@ConditionalOnMissingBean` | Orders with `afterName`, tests every condition with `ApplicationContextRunner` + `FilteredClassLoader`, ships verified metadata |
| AOT (Round 2) | Turns on AOT for startup | Audits environment-dependent conditions first; knows the graph is a build artifact |
| Request lifecycle (Round 2) | Knows filters vs interceptors | Knows what each layer sees on handled/unhandled errors and the ERROR dispatch; one error contract |
| Events (Round 2) | Uses `@TransactionalEventListener` | Knows thread, transaction state, skip-without-transaction, `REQUIRES_NEW` for writes, durability limits |
| Async and shutdown (Round 2) | Uses `@Async`, sets graceful shutdown | Knows executor back-off, decorators, lifecycle phases, and sizes the grace period end to end |

## Red flags

* "`allow-circular-references=true` fixed it."
* "WebFlux is always faster."
* "Virtual threads mean we don't need to think about pool sizes anymore."
* "Our rate limiter is a `ConcurrentHashMap` in each pod" (as the quota mechanism).
* "We disabled CSRF because it was annoying" (on a session-cookie app).
* "Our starter uses `@ConditionalOnBean`; it works in our service" (no `after`, no runner test).
* "AOT is just faster startup."
* "We log errors in `HandlerInterceptor.afterCompletion`."
* "The filter logs the status, so our error rate is accurate."
* "Write the audit row in the `AFTER_COMMIT` listener."
* "Just add another `Executor` bean."
* "A global `@ExceptionHandler(Exception.class)` returns 500 for everything."

---

## Rapid-fire flashcards

<details><summary>1. BDRPP vs BFPP vs BPP?</summary>Add definitions / edit definitions / wrap or modify instances.</details>

<details><summary>2. Order of init callbacks?</summary>`@PostConstruct` → `afterPropertiesSet` → `initMethod`.</details>

<details><summary>3. When are AOP proxies created?</summary>`postProcessAfterInitialization` (after init callbacks).</details>

<details><summary>4. Safe point to use other beans at startup?</summary>`SmartInitializingSingleton` or `ApplicationReadyEvent`.</details>

<details><summary>5. Why must post-processor `@Bean` methods be static?</summary>So the configuration class isn't instantiated early (missing processing).</details>

<details><summary>6. `proxyBeanMethods = false` consequence?</summary>Calling another `@Bean` method creates a new, unmanaged instance.</details>

<details><summary>7. Prototype in singleton?</summary>Created once; use `ObjectProvider`, `@Lookup` or a scoped proxy.</details>

<details><summary>8. How does auto-configuration back off?</summary>`@ConditionalOnMissingBean` (+ deferred import after user config).</details>

<details><summary>9. Where are auto-config candidates listed?</summary>`META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`.</details>

<details><summary>10. Three singleton caches?</summary>`singletonObjects`, `earlySingletonObjects`, `singletonFactories`.</details>

<details><summary>11. Can constructor cycles be resolved?</summary>No.</details>

<details><summary>12. Spring AOT vs JDK AOT cache?</summary>Build-time bean-definition code vs pre-loaded/linked classes from a training run (they compose).</details>

<details><summary>13. JDK vs CGLIB proxy?</summary>Implements interfaces vs subclasses the class.</details>

<details><summary>14. Which `@Order` value is outermost?</summary>The lowest.</details>

<details><summary>15. Default order of the transaction advisor?</summary>Lowest precedence (innermost).</details>

<details><summary>16. Spring 7 `@Retryable` vs `@Transactional` on one method?</summary>Retry outermost (verified): each attempt is a new transaction.</details>

<details><summary>17. What happens to a final method on a CGLIB proxy?</summary>Not intercepted; Spring logs a WARN; runs on the proxy instance.</details>

<details><summary>18. Default Tomcat max threads?</summary>200.</details>

<details><summary>19. Property to enable virtual threads in Boot?</summary>`spring.threads.virtual.enabled=true`.</details>

<details><summary>20. Which JDK removed `synchronized` pinning?</summary>JDK 24 (JEP 491).</details>

<details><summary>21. Never do this in WebFlux?</summary>Block an event-loop thread.</details>

<details><summary>22. The servlet-to-Spring bridge filter?</summary>`DelegatingFilterProxy` → `FilterChainProxy`.</details>

<details><summary>23. Which filter authenticates bearer tokens?</summary>`BearerTokenAuthenticationFilter`.</details>

<details><summary>24. New filter in Spring Security 7's resource server chain?</summary>`OAuth2ProtectedResourceMetadataFilter` (RFC 9728).</details>

<details><summary>25. 401 vs 403 for JWTs?</summary>401 missing/invalid token; 403 valid token without the required scope (`insufficient_scope`).</details>

<details><summary>26. Why place a rate-limit filter after bearer authentication?</summary>To key on the user instead of the IP.</details>

<details><summary>27. Why does `@ConditionalOnBean` fail in an application `@Configuration`?</summary>User configuration is registered before the deferred auto-configurations, so auto-configured beans don't exist yet.</details>

<details><summary>28. How are auto-configurations ordered?</summary>Alphabetically by name, then `@AutoConfigureOrder`, then `before`/`after` constraints.</details>

<details><summary>29. Why `afterName` strings instead of `after` classes?</summary>No compile dependency on the module that contains them (Boot 4's per-technology modules).</details>

<details><summary>30. What does `spring-autoconfigure-metadata.properties` enable?</summary>Filtering auto-configuration candidates (e.g. `ConditionalOnClass`) without loading their classes.</details>

<details><summary>31. Since JDK 23, when do annotation processors on the class path run?</summary>Only with `-proc:full` or an explicit processor path; otherwise silently not at all.</details>

<details><summary>32. What does Spring AOT do to `@Profile` and `@ConditionalOnProperty`?</summary>Evaluates them at build time; the runtime environment can't change the bean graph.</details>

<details><summary>33. For `@ResponseBody`, when does `postHandle` run?</summary>After the body is written: headers set there are ignored.</details>

<details><summary>34. What `ex` does `afterCompletion` get when an `@ExceptionHandler` resolved the exception?</summary>`null`.</details>

<details><summary>35. Why can a servlet filter record 200 for a request that returned 500?</summary>The unhandled exception leaves the chain before Tomcat's ERROR dispatch to `/error` writes the 500.</details>

<details><summary>36. What happens to a `@TransactionalEventListener` when there's no transaction?</summary>It is skipped silently unless `fallbackExecution = true`.</details>

<details><summary>37. Which `@Transactional` propagation is allowed on a `@TransactionalEventListener` (Spring 6.1+)?</summary>`REQUIRES_NEW` or `NOT_SUPPORTED`.</details>

<details><summary>38. What happens to Boot's `applicationTaskExecutor` when you define an `Executor` bean?</summary>It backs off (mode `auto`); `spring.task.execution.mode=force` keeps it.</details>

<details><summary>39. Phase of `webServerGracefulShutdown` and its per-phase timeout?</summary>`Integer.MAX_VALUE - 1024`; `spring.lifecycle.timeout-per-shutdown-phase` (30 s).</details>

<details><summary>40. Lifecycle stop order?</summary>Highest phase first; `@PreDestroy`/destroy callbacks after all lifecycles stopped.</details>

<details><summary>41. Do security filter-chain denials reach `@ControllerAdvice`?</summary>No: entry points and access-denied handlers write them; only method-security denials (inside the dispatcher) do.</details>

<details><summary>42. Lowest-precedence property source?</summary>Default properties (`SpringApplicationBuilder.properties`, `setDefaultProperties`).</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–10) | Non-transactional warm-up, circular dependencies, slow startup, virtual threads, WebFlux rewrite, double-counting aspect, JWT validation, rate limiting, data leaks across requests, Boot's bean winning | The container's mechanics: lifecycle, proxies, cycles, startup, concurrency models, the security filter chain |
| Round 2 (11–18) | Missing starter bean, AOT vs feature flags, invisible 5xx, lost `AFTER_COMMIT` writes, async MDC loss, deploy-time 502s, 403 → 500, ignored test properties | Boot as a platform: auto-configuration ordering, build-time graphs, what each request/transaction/lifecycle layer actually sees |

**Next pillar:** [5.1 Decomposition: modular monolith, strangler fig, branch by abstraction →](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)
