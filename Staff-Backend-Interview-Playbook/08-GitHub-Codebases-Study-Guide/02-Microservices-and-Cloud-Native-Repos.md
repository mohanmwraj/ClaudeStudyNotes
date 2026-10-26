# 8.2 Codebases to Study: Microservices and Cloud-Native Spring

> **Verified 2026-10-25** via the GitHub API and file trees; versions read from each repo's build files and README. Every path below exists on the default branch.
>
> **Pairs with:** [5.6 gateway, BFF, aggregator, mesh](../05-Microservices-Patterns/06-Edge-Patterns-Gateway-BFF-Aggregator-Service-Mesh.md), [6.1](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)–[6.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) resilience, [Pillar 7](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) Kubernetes.

---

## 0. How to read a microservices sample critically 🔥

Samples exist to show *wiring*. They usually skip the parts that make distributed systems hard. As you read, keep a list of what's **missing**, because that list is your interview material:

| Question | Where it usually goes missing |
|---|---|
| Who owns which data, and how do other services get it? | Shared DB or synchronous lookups everywhere |
| What happens when a downstream is slow, not down? | Timeouts not set, or only a breaker on error rate |
| How do events get published reliably? | Direct `send()` after `save()` (a dual write) |
| Are consumers idempotent? | Rarely shown |
| How do services evolve contracts independently? | No contract tests, no versioning |
| How does it behave during a rollout or a pod kill? | Not covered by the sample |

---

## 1. spring-petclinic/spring-petclinic-microservices ⚡

| | |
|---|---|
| Repository | [spring-petclinic/spring-petclinic-microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) (`main`, 2,227 stars, pushed 2026-10-23) |
| Versions (root `pom.xml`) | Spring Boot **4.0.1**, Spring Cloud **2025.1.0**, Java **17** |
| Services (`docker-compose.yml`) | `config-server`, `discovery-server` (Eureka), `customers-service`, `visits-service`, `vets-service`, `genai-service` (Spring AI chat), `api-gateway`, `tracing-server` (Zipkin), `admin-server` (Spring Boot Admin), Prometheus, Grafana |

### 1.1 The file worth the most time: the gateway's aggregator

`spring-petclinic-api-gateway/src/main/java/org/springframework/samples/petclinic/api/boundary/web/ApiGatewayController.java` (excerpt):

```java
@GetMapping(value = "owners/{ownerId}")
public Mono<OwnerDetails> getOwnerDetails(final @PathVariable int ownerId) {
    return customersServiceClient.getOwner(ownerId)
        .flatMap(owner ->
            visitsServiceClient.getVisitsForPets(owner.getPetIds())            // ONE call for all pets
                .transform(it -> {
                    ReactiveCircuitBreaker cb = cbFactory.create("getOwnerDetails");
                    return cb.run(it, throwable -> emptyVisitsForPets());       // degrade: owner without visits
                })
                .map(addVisitsToOwner(owner))
        );
}
```

What it gets right, in the vocabulary of [5.6](../05-Microservices-Patterns/06-Edge-Patterns-Gateway-BFF-Aggregator-Service-Mesh.md):

* **No N+1 across services**: visits for all pets in one request (`getVisitsForPets(petIds)`), not one call per pet.
* **Optional data degrades**: if visits fail, the owner page still renders with an empty visit list. Customers data is required, so it isn't wrapped.
* **Breaker around the optional call only**, through Spring Cloud CircuitBreaker's `ReactiveCircuitBreakerFactory` (Resilience4j underneath).

What to probe:

* The two calls are **sequential** (visits need the pet ids from the owner). Is there a per-call timeout and an overall deadline? Find where the `WebClient` timeouts are set, or notice that they aren't. (Answered in §5.1: none on the clients; the breaker's time limiter is 10 s.)
* The fallback hides the failure from the user. Is it counted? A fallback rate is an SLO signal ([6.1 §6.4](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)).
* The gateway is also the aggregator (a BFF in practice). Who owns it when there are three frontends?

### 1.2 Other files

| Path | What to look for |
|---|---|
| `spring-petclinic-api-gateway/src/main/java/org/springframework/samples/petclinic/api/application/CustomersServiceClient.java` | Load-balanced `WebClient` via service discovery |
| `spring-petclinic-api-gateway/src/main/java/org/springframework/samples/petclinic/api/application/VisitsServiceClient.java` | The batched call used above |
| `spring-petclinic-config-server/src/main/java/org/springframework/samples/petclinic/config/ConfigServerApplication.java` | Centralized configuration (Spring Cloud Config) |
| `spring-petclinic-discovery-server/src/main/java/org/springframework/samples/petclinic/discovery/DiscoveryServerApplication.java` | Eureka |
| `spring-petclinic-vets-service/src/main/java/org/springframework/samples/petclinic/vets/system/CacheConfig.java` | Local caching of slowly changing reference data |
| `spring-petclinic-customers-service/src/main/java/org/springframework/samples/petclinic/customers/config/MetricConfig.java` | Custom Micrometer metrics |
| `spring-petclinic-genai-service/src/main/java/org/springframework/samples/petclinic/genai/PetclinicChatClient.java` | An LLM-backed service calling the others as tools |
| `docker-compose.yml` | The full topology, including Zipkin, Prometheus and Grafana |

### 1.3 Platform question to ask 🧊

On Kubernetes, **Eureka and Config Server duplicate platform features**: Services + DNS do discovery, ConfigMaps/Secrets (+ a reloader) do configuration. Keeping them means running and securing two extra stateful-ish components. A strong answer: "On Kubernetes I'd use platform discovery and config, keep Spring Cloud Gateway (or a Gateway API implementation) at the edge, and use Spring Cloud CircuitBreaker or Resilience4j in the services." The Packt book (§2) walks through exactly that migration.

---

## 2. Magnus Larsson: *Microservices with Spring Boot and Spring Cloud* (Packt) ⚡

| Edition | Repository | Status (2026-10-25) |
|---|---|---|
| Fourth | [PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Fourth-Edition](https://github.com/PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Fourth-Edition) | Pushed 2026-07-03. README: *"The source code has been upgraded from Spring Boot 3.5.0 used in the book to 3.5.16"* |
| Third | [PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Third-Edition](https://github.com/PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Third-Edition) | Pushed 2025-02-24 |

Use the **Fourth Edition**. Its value is that **the same system evolves chapter by chapter**, so you can diff two chapters and see exactly what a capability costs.

### 2.1 Chapter map (from the files each chapter adds)

| Chapter | What appears in the tree | Topic |
|---|---|---|
| 03 | `2-basic-rest-services/…` | Basic REST services (product, recommendation, review, composite) |
| 04–05 | `docker-compose` files; Chapter 05 adds `springdoc-openapi-starter-webflux-ui` | Containers, then API documentation (OpenAPI) |
| 06 | Mongo configuration | Persistence |
| 07 | `spring-cloud-starter-stream-rabbit` and `-stream-kafka` | Reactive services and event-driven updates (Spring Cloud Stream) |
| 09 | `eureka-server` | Service discovery |
| 10 | `gateway` | Edge server (Spring Cloud Gateway) |
| 11 | `authorization-server`, `Chapter11/auth0/` | OAuth 2.0 / OIDC security |
| 12 | `config-server`, `Chapter12/config-repo/` | Centralized configuration |
| 13 | `Chapter13/config-repo/product-composite.yml` with `resilience4j.*` | **Resilience4j**: retry, time limiter, circuit breaker |
| 14 | `management.zipkin.tracing.endpoint` in `Chapter14/config-repo/application.yml` | Distributed tracing (Zipkin) |
| 15 | `Chapter15/kubernetes/first-attempts/` | First Kubernetes deployment |
| 16 | `Chapter16/kubernetes/helm/` | Helm charts |
| 17 | Helm + ConfigMaps, **no Eureka, no Config Server** | Replacing Spring Cloud infrastructure with Kubernetes features |
| 18 | `istio` | Service mesh |
| 19 | `kubernetes/efk` | Centralized logging (EFK) |
| 20 | Prometheus/Grafana, `kubernetes/resilience-tests` | Monitoring |
| 23 | native-image configuration | GraalVM native images |

### 2.2 Files to read

| Path | What to look for |
|---|---|
| `Chapter13/microservices/product-composite-service/src/main/java/se/magnus/microservices/composite/product/services/ProductCompositeIntegration.java` | `@Retry` + `@TimeLimiter` + `@CircuitBreaker(fallbackMethod = "getProductFallbackValue")` on a reactive `Mono` call, with fault-injection parameters `delay` and `faultPercent` |
| `Chapter13/config-repo/product-composite.yml` | The Resilience4j configuration (`resilience4j.circuitbreaker`, `.retry`, `.timelimiter`) and `management.health.circuitbreakers.enabled` |
| `Chapter03/2-basic-rest-services/microservices/product-composite-service/src/main/java/se/magnus/microservices/composite/product/services/ProductCompositeIntegration.java` | The same class before any resilience: diff it with Chapter 13 |
| `Chapter17/kubernetes/helm/` | What replaces Eureka and Config Server on Kubernetes |
| `Chapter20/kubernetes/resilience-tests/` | Testing resilience on the cluster |

The Chapter 13 method signature, quoted:

```java
@Retry(name = "product")
@TimeLimiter(name = "product")
@CircuitBreaker(name = "product", fallbackMethod = "getProductFallbackValue")
public Mono<Product> getProduct(int productId, int delay, int faultPercent) { … }
```

Connect it to [6.2 §5.1](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md): the annotation order in the source doesn't matter. The Spring aspect orders make it `Retry(CircuitBreaker(TimeLimiter(call)))`, so every retry attempt is timed out and counted by the breaker. The fault-injection parameters are worth copying: they let you **demonstrate** the breaker opening on a live system.

### 2.3 Exercises

1. `git diff` Chapter 12 and Chapter 13 of the composite service: list every line that resilience added. That's the honest cost of the pattern.
2. Run Chapter 13 with `faultPercent=50` and watch `/actuator/health` and the circuit breaker events. Predict when it opens using [6.1 §5.1](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)'s arithmetic before you look.
3. Compare Chapter 16 and Chapter 17: write down every Spring Cloud component removed and the Kubernetes feature that replaced it.
4. Port the composite service to the [7.5 blueprint](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md): probes on the main port, preStop, `JAVA_TOOL_OPTIONS`, no CPU limit.

---

## 3. What both samples leave out (your critique list) 🧊

| Gap | Production answer | Kit reference |
|---|---|---|
| Events published without an outbox | Transactional outbox + idempotent consumers | [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) |
| Cross-service consistency | Sagas with compensations, semantic locks | [5.3](../05-Microservices-Patterns/03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md) |
| Contract evolution | Consumer-driven contracts (Pact), versioned events | [5.7](../05-Microservices-Patterns/07-Observability-Tracing-Correlation-IDs-Contract-Testing.md) |
| Container memory/CPU sizing | Heap + non-heap budget, `ActiveProcessorCount` | [7.1](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md), [7.4](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md) |
| Graceful shutdown during rollouts | preStop + graceful drain + grace budget | [7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md) |
| Cache consistency | Leases / CDC invalidation, staleness budgets | [6.4](../06-Resilience-Caching/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |

---

## 4. Interview soundbites

* "Petclinic microservices runs on Boot 4.0.1 and Spring Cloud 2025.1. The gateway's owner-details endpoint is a good aggregator: one batched call for all pets' visits, and a circuit breaker that degrades to an owner without visits."
* "On Kubernetes I'd drop Eureka and Config Server for platform discovery and ConfigMaps. Larsson's book does exactly that between chapters 16 and 17."
* "Larsson's chapter 13 stacks retry, time limiter and circuit breaker on a reactive call, and builds in fault injection so you can watch the breaker open. I'd copy the fault injection before I'd copy the annotations."
* "What samples skip is my checklist: outbox, idempotent consumers, contract tests, shutdown behavior, container sizing."

---

## 5. Deep dive: what the samples actually configure (verified 2026-10-26) 🧊

Pinned for this section: petclinic microservices at commit [`e8b747ab52`](https://github.com/spring-petclinic/spring-petclinic-microservices/tree/e8b747ab522721076cacb5cf688eb8a54ba8c5c9) ([Spring Cloud `2025.1.0`](https://github.com/spring-petclinic/spring-petclinic-microservices/blob/e8b747ab522721076cacb5cf688eb8a54ba8c5c9/pom.xml#L32)), Larsson's Fourth Edition at commit [`db9e0fa7d4`](https://github.com/PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Fourth-Edition/tree/db9e0fa7d41756224a149a5a870647e0f0426b2e), Resilience4j `v2.4.0`. All **18 paths cited in this file** resolve at those commits.

### 5.1 Petclinic's real timeouts: the probe in §1.1, answered

§1.1 asked where the `WebClient` timeouts are set. In the gateway at the pin:

* **There are none on the clients.** [`VisitsServiceClient`](https://github.com/spring-petclinic/spring-petclinic-microservices/blob/e8b747ab522721076cacb5cf688eb8a54ba8c5c9/spring-petclinic-api-gateway/src/main/java/org/springframework/samples/petclinic/api/application/VisitsServiceClient.java#L46) calls `.retrieve()` on a load-balanced `WebClient` with no response timeout, and nothing in the gateway's `application.yml` sets one.
* **The only bound is the circuit breaker's time limiter.** The application declares a default customizer for every breaker:

```java
public Customizer<ReactiveResilience4JCircuitBreakerFactory> defaultCustomizer() {
    return factory -> factory.configureDefault(id -> new Resilience4JConfigBuilder(id)
        .circuitBreakerConfig(CircuitBreakerConfig.ofDefaults())
        .timeLimiterConfig(TimeLimiterConfig.custom().timeoutDuration(Duration.ofSeconds(10)).build())
        .build());
```

What that means for the owner-details page (§1.1):

| Call | Bounded by | Consequence |
|---|---|---|
| `getVisitsForPets` (inside `cb.run`, [here](https://github.com/spring-petclinic/spring-petclinic-microservices/blob/e8b747ab522721076cacb5cf688eb8a54ba8c5c9/spring-petclinic-api-gateway/src/main/java/org/springframework/samples/petclinic/api/boundary/web/ApiGatewayController.java#L61)) | The time limiter: **10 s**, then the fallback (owner without visits) | A slow visits service makes the page wait up to 10 s before degrading |
| `getOwner` (not wrapped) | Nothing | A hung customers service hangs the request |
| The breaker itself | [`CircuitBreakerConfig.ofDefaults()`](https://github.com/spring-petclinic/spring-petclinic-microservices/blob/e8b747ab522721076cacb5cf688eb8a54ba8c5c9/spring-petclinic-api-gateway/src/main/java/org/springframework/samples/petclinic/api/ApiGatewayApplication.java#L87): count-based, [window 100, minimum 100 calls](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/CircuitBreakerConfig.java#L47), 50 % failures | Can't open before 100 calls in the window; in a demo it effectively never opens |

Without that customizer, Spring Cloud CircuitBreaker would have used [`TimeLimiterConfig.ofDefaults()`](https://github.com/spring-cloud/spring-cloud-circuitbreaker/blob/v5.0.1/spring-cloud-circuitbreaker-resilience4j/src/main/java/org/springframework/cloud/circuitbreaker/resilience4j/Resilience4JConfigBuilder.java#L33), which is [1 second](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-timelimiter/src/main/java/io/github/resilience4j/timelimiter/TimeLimiterConfig.java#L14). Either way the time limit is a breaker setting nobody sees in the client code. That's why "find the timeout" is a review question ([8.9 C12](09-Staff-Level-System-and-Code-Review-Checklist-20-Questions.md)).

### 5.2 Larsson's Chapter 13, worked through from the configuration

[`product-composite.yml`](https://github.com/PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Fourth-Edition/blob/db9e0fa7d41756224a149a5a870647e0f0426b2e/Chapter13/config-repo/product-composite.yml#L120) at the pin:

| Setting | Value |
|---|---|
| Circuit breaker | count-based, window **5**, failure threshold **50 %**, open for **10 s**, **3** half-open calls, automatic transition on |
| Time limiter | **2 s** ([line](https://github.com/PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Fourth-Edition/blob/db9e0fa7d41756224a149a5a870647e0f0426b2e/Chapter13/config-repo/product-composite.yml#L102)) |
| Retry | **3** attempts, **1 s** apart, only on `WebClientResponseException$InternalServerError` ([line](https://github.com/PacktPublishing/Microservices-with-Spring-Boot-and-Spring-Cloud-Fourth-Edition/blob/db9e0fa7d41756224a149a5a870647e0f0426b2e/Chapter13/config-repo/product-composite.yml#L107)) |

`minimumNumberOfCalls` isn't set, so its default of 100 applies. But Resilience4j [caps it at the window size for count-based windows](https://github.com/resilience4j/resilience4j/blob/v2.4.0/resilience4j-circuitbreaker/src/main/java/io/github/resilience4j/circuitbreaker/internal/CircuitBreakerMetrics.java#L51), so the breaker evaluates after 5 calls. With Spring's aspect order `Retry(CircuitBreaker(TimeLimiter(call)))` ([6.2 §5.1](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)), each retry attempt is one breaker call. That gives a prediction to check on a live system (§2.3, exercise 2). **It's derived from the configuration, not run here:**

* With `faultPercent=100`, request 1 is three failed attempts (calls 1–3). Request 2's first two attempts are calls 4–5: the window is full with 5/5 failures, and the breaker opens.
* Request 2's third attempt is rejected with `CallNotPermittedException`. That isn't in `retryExceptions`, so it isn't retried; the fallback answers.
* A 2 s time-limiter timeout is a `TimeoutException`, not an `InternalServerError`, so **timeouts are never retried** here. That's a sensible choice for a slow dependency ([6.6](../06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md)), and worth saying out loud in an interview.

### 5.3 What I'd change

| Sample | Change | Evidence |
|---|---|---|
| Petclinic gateway | Response and connect timeouts on both `WebClient`s, below the 10 s limiter | §5.1 |
| Petclinic gateway | A breaker sized for the traffic (window and minimum calls far below 100), or none | §5.1 |
| Petclinic gateway | Count and alert on fallbacks; "owner without visits" hides the outage | [6.1](../06-Resilience-Caching/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md) |
| Larsson Chapter 13 | A retry budget instead of a fixed 3 attempts | 2.72× load on an overloaded dependency ([6.6](../06-Resilience-Caching/06-Resilience-Under-Load-Chaos-Lab-Measured-Stack.md)) |
| Both | On Kubernetes, drop Eureka and Config Server (as Larsson's Chapter 17 does) | §1.3 |

## Summary

| Topic | Key point | Section |
|---|---|---|
| Reading samples | Keep a list of what's missing: data ownership, slow dependencies, outbox, idempotency, contracts, rollout behaviour | §0 |
| Petclinic aggregator | One batched call for all pets' visits; a breaker that degrades to an owner without visits | §1.1 |
| Petclinic timeouts | No client timeouts; a 10 s time limiter; `ofDefaults()` breaker needs 100 calls before it can open | §5.1 |
| Platform | On Kubernetes, Eureka and Config Server duplicate Services and ConfigMaps | §1.3 |
| Larsson | One system evolving by chapter; diff chapters to see what each capability costs | §2 |
| Chapter 13 | Window 5, 50 %, 10 s open; 2 s time limit; retries only on 500s; predicted to open on the 5th call | §5.2 |
| The gap list | Outbox, sagas, contracts, sizing, shutdown, cache consistency | §3 |

**Next:** [8.3 Saga, outbox and event-driven repositories →](03-Saga-Outbox-Event-Driven-Repos.md)
