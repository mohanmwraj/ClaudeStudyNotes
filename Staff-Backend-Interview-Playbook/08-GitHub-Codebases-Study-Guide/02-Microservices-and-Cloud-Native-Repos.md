# 8.2 Codebases to Study: Microservices and Cloud-Native Spring

> **Verified 2026-10-25** via the GitHub API and file trees; versions read from each repo's build files and README. Every path below exists on the default branch.
>
> **Pairs with:** [5.6 gateway, BFF, aggregator, mesh](../05-Microservices-Patterns/06-Edge-Patterns-Gateway-BFF-Aggregator-Service-Mesh.md), [6.1](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)–[6.2](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md) resilience, [Pillar 7](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) Kubernetes.

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

* The two calls are **sequential** (visits need the pet ids from the owner). Is there a per-call timeout and an overall deadline? Find where the `WebClient` timeouts are set, or notice that they aren't.
* The fallback hides the failure from the user. Is it counted? A fallback rate is an SLO signal ([6.1 §6.4](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)).
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

Connect it to [6.2 §5.1](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md): the annotation order in the source doesn't matter. The Spring aspect orders make it `Retry(CircuitBreaker(TimeLimiter(call)))`, so every retry attempt is timed out and counted by the breaker. The fault-injection parameters are worth copying: they let you **demonstrate** the breaker opening on a live system.

### 2.3 Exercises

1. `git diff` Chapter 12 and Chapter 13 of the composite service: list every line that resilience added. That's the honest cost of the pattern.
2. Run Chapter 13 with `faultPercent=50` and watch `/actuator/health` and the circuit breaker events. Predict when it opens using [6.1 §5.1](../06-Resilience-Caching-Kafka/01-Resilience4j-Circuit-Breaker-Internals-Sliding-Windows.md)'s arithmetic before you look.
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
| Cache consistency | Leases / CDC invalidation, staleness budgets | [6.4](../06-Resilience-Caching-Kafka/04-Cache-Stampede-Penetration-Avalanche-Invalidation.md) |

---

## 4. Interview soundbites

* "Petclinic microservices runs on Boot 4.0.1 and Spring Cloud 2025.1. The gateway's owner-details endpoint is a good aggregator: one batched call for all pets' visits, and a circuit breaker that degrades to an owner without visits."
* "On Kubernetes I'd drop Eureka and Config Server for platform discovery and ConfigMaps. Larsson's book does exactly that between chapters 16 and 17."
* "Larsson's chapter 13 stacks retry, time limiter and circuit breaker on a reactive call, and builds in fault injection so you can watch the breaker open. I'd copy the fault injection before I'd copy the annotations."
* "What samples skip is my checklist: outbox, idempotent consumers, contract tests, shutdown behavior, container sizing."

**Next:** [8.3 Saga, outbox and event-driven repositories →](03-Saga-Outbox-Event-Driven-Repos.md)
