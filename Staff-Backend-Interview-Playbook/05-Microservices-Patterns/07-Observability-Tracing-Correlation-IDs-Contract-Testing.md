# 5.7 Observability & Testing Across Services: W3C Trace Context with OpenTelemetry, Correlation IDs in Logs, Async Propagation, Consumer-Driven Contract Testing (Pact)

> **Verified stack:** Spring Boot **4.1.2** with `spring-boot-starter-opentelemetry` (Micrometer Tracing → OpenTelemetry bridge), Spring Framework **7.0.10** `RestClient`, two services in one JVM on real HTTP; **Pact JVM 4.7.5** (consumer `junit5` + provider `junit5`). Log lines, `traceparent` values and Pact verification output are real.
>
> **Go deeper:** the sibling kit's [8.2 OpenTelemetry, Micrometer & logging](../../Java-Backend-Master-Reference/08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md) (histograms, exemplars, sampling) and [8.4 testing](../../Java-Backend-Master-Reference/08-Observability-Security-Testing/04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md) (Testcontainers).

---

## 0. First principles: one request, many processes 🔥

In a monolith, a stack trace explains a request. With N services, the request is **scattered across N processes' logs and metrics**. To reassemble it you need one ID that travels with the request across every hop (HTTP, messaging, async threads), plus a parent–child structure to see *where* time went. That's distributed tracing:

* A **trace** = one end-to-end request, identified by a **trace id** (16 bytes).
* A **span** = one unit of work (an HTTP server request, a client call, a DB query), with a span id, a parent span id, timing and attributes.
* **Context propagation** = carrying `trace id + current span id + sampling flag` across boundaries. The standard on the wire is **W3C Trace Context**:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             ││ └──────────── trace id ──────────┘ └─ parent id ──┘ └ flags (01 = sampled)
             └ version
```

---

## 1. Verified: propagation across two Spring Boot services 🔥

```java
@RestController
public static class FrontendController {                     // "order-svc"
    static final Logger log = LoggerFactory.getLogger("frontend");
    private final RestClient backend;
    FrontendController(io.micrometer.observation.ObservationRegistry observations) {
        this.backend = RestClient.builder().baseUrl("http://localhost:18101")
                .observationRegistry(observations)              // instruments the client: span + traceparent injection
                .build();
    }
    @GetMapping("/orders/{sku}")
    String order(@PathVariable String sku) {
        log.info("frontend received order for {}", sku);
        return "order accepted, stock=" + backend.get().uri("/stock/{sku}", sku).retrieve().body(String.class);
    }
}

@RestController
public static class BackendController {                       // "inventory-svc"
    static final Logger log = LoggerFactory.getLogger("backend");
    @GetMapping("/stock/{sku}")
    String stock(@PathVariable String sku, @RequestHeader(value = "traceparent", required = false) String traceparent) {
        log.info("backend handling stock lookup, received traceparent={}", traceparent);
        return "{\"sku\":\"" + sku + "\",\"available\":7}";
    }
}
```

A client calls `order-svc` with `traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`, as an upstream gateway would. Settings: `management.tracing.sampling.probability=1.0`.

**Output (verified):**

```text
== client -> order-svc with traceparent 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
... INFO ... [io-18100-exec-1] [4bf92f3577b34da6a3ce929d0e0e4736-129d293470b0722d] frontend : frontend received order for book
... INFO ... [io-18101-exec-1] [4bf92f3577b34da6a3ce929d0e0e4736-73b0ce937ddc3cfc] backend  : backend handling stock lookup, received traceparent=00-4bf92f3577b34da6a3ce929d0e0e4736-e019a5f2a77bc9da-01
== response: HTTP 200 order accepted, stock={"sku":"book","available":7}
```

Reading the IDs:

```text
trace 4bf92f35…4736 (from the gateway)
 └─ span 129d2934…722d   order-svc server span      (parent = 00f067aa… from the incoming header)
     └─ span e019a5f2…c9da   order-svc RestClient client span   ← sent as the parent-id in traceparent
         └─ span 73b0ce93…3cfc   inventory-svc server span
```

* **The same trace id** appears in both services' logs, so one search finds the whole request. Spring Boot puts `[traceId-spanId]` into every log line automatically when tracing is on (the logging *correlation* pattern), taken from the MDC.
* The `traceparent` the backend received has a **new parent id**: the client span, not the frontend's server span. Each hop creates child spans; nothing is reused.
* (Both services ran in one JVM for the lab, so Logback printed the first application's name on both lines.)

### Two Boot 4 details this lab tripped over

1. **`RestClient.Builder` isn't auto-configured unless the `spring-boot-restclient` module is on the classpath** (Boot 4 split auto-configuration into modules). Without the auto-configured builder you must attach the `ObservationRegistry` yourself, as above. Otherwise the client call creates **no span and sends no `traceparent`**, and the trace silently breaks at that hop. The same applies to any `RestTemplate`/`WebClient`/`HttpClient` you `new` up yourself.
2. **The OpenTelemetry starter exports via OTLP to `http://localhost:4318` by default.** Without a collector you get connection errors at shutdown; set the export endpoint (or disable export) explicitly per environment.

---

## 2. Propagation through async boundaries ⚡

HTTP is the easy case. Context is lost wherever **threads or transports change**:

| Boundary | What to do |
|---|---|
| `@Async`, executors | Declare a `TaskDecorator` bean such as Micrometer's `ContextPropagatingTaskDecorator`: Boot applies a `TaskDecorator` bean to its auto-configured executor. Executors you create yourself must be decorated explicitly |
| `CompletableFuture.supplyAsync(..., myExecutor)` | Same: a context-aware executor, or `ContextSnapshot.captureAll().wrap(...)` from Micrometer's context-propagation library |
| Reactor (WebFlux) | `Hooks.enableAutomaticContextPropagation()` (Boot enables it with `spring.reactor.context-propagation=auto`) |
| **Kafka** | Enable observation on templates and listener containers (`spring.kafka.template.observation-enabled=true`, `spring.kafka.listener.observation-enabled=true`) so `traceparent` travels in **record headers** |
| **Outbox** | Store the `traceparent` in the outbox row at write time and copy it into the message headers in the relay, or the trace ends at the database ([5.4 §8](04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)) |
| Virtual threads | `ThreadLocal`-based context works per virtual thread; new threads you start must inherit or be given the context |

### Correlation IDs vs trace IDs

| | Trace id | Business correlation id |
|---|---|---|
| Created by | Tracing system (or upstream) | Your edge (request id, order id, idempotency key) |
| Lifetime | One request | A whole business flow (a saga spans many requests and days) |
| Use | Latency analysis, debugging a request | Customer support, auditing a process |

Use **both**: log the trace id (automatic) and put business keys into the MDC (`MDC.put("orderId", …)`) or as **baggage** (W3C `baggage` header) when downstream services need them.

---

## 3. Sampling: you can't keep every trace 🧊

| Strategy | Where | Trade-off |
|---|---|---|
| Head sampling (`probability = 0.1`) | At trace start, decision propagated (`flags`) | Cheap; but 90% of **error** traces are dropped |
| Tail sampling | In the OpenTelemetry Collector, after the trace completes | Keep all errors and slow traces, sample the rest; needs collector memory and a decision window |
| Always sample specific routes | Parent-based + rules | Keep business-critical flows |

Production default: parent-based head sampling at the edge (a few %), plus tail sampling in the collector for errors and latency outliers.

---

## 4. Consumer-driven contract testing (verified with Pact) 🔥

**The problem:** `order-svc` calls `inventory-svc`. Unit tests on each side pass with their own assumptions; end-to-end tests are slow, flaky and run too late. A provider renames a field and the consumer breaks **in production**.

**The idea:** the **consumer** writes down exactly what it needs (a contract, here a *pact*), generated from its own tests. The **provider** replays every consumer's contract against its real implementation in its own CI. A provider change that breaks any consumer fails the provider's build.

### 4.1 Consumer side: the test generates the contract

```java
@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "inventory-svc")
class InventoryClientPactTest {

    @Pact(consumer = "order-svc")
    V4Pact stockForBook(PactDslWithProvider builder) {
        return builder
                .given("book is in stock")
                .uponReceiving("a stock lookup for book")
                    .path("/stock/book").method("GET")
                .willRespondWith()
                    .status(200)
                    .headers(java.util.Map.of("Content-Type", "application/json"))
                    .body(new PactDslJsonBody()
                            .stringValue("sku", "book")
                            .integerType("available", 7))          // type match: any integer is acceptable
                .toPact(V4Pact.class);
    }

    @Test
    void readsStock(MockServer mock) {
        InventoryClient.Stock s = new InventoryClient(mock.getUrl()).stock("book");
        assertThat(s.sku()).isEqualTo("book");
        assertThat(s.available()).isPositive();
    }
}
```

The test runs the **real** `InventoryClient` against a Pact mock server and writes `target/pacts/order-svc-inventory-svc.json`.

**Output (verified, excerpt of the generated pact):**

```json
{
    "consumer": { "name": "order-svc" },
    "interactions": [
        {
            "description": "a stock lookup for book",
            "providerStates": [ { "name": "book is in stock" } ],
            "request": { "method": "GET", "path": "/stock/book" },
            "response": {
                "body": { "content": { "available": 7, "sku": "book" }, "contentType": "application/json", "encoded": false },
                "headers": { "Content-Type": [ "application/json" ] },
                "matchingRules": {
                    "body": { "$.available": { "combine": "AND", "matchers": [ { "match": "integer" } ] } }
                },
                "status": 200
            },
            "type": "Synchronous/HTTP"
        }
    ],
    "metadata": { "pact-jvm": { "version": "4.7.5" }, "pactSpecification": { "version": "4.0" } },
    "provider": { "name": "inventory-svc" }
}
```

The `integer` matching rule matters: the consumer only cares that `available` is an integer, so the provider isn't over-constrained to return exactly 7.

### 4.2 Provider side: replay the contract against the real service

```java
@Provider("inventory-svc")
@PactFolder("target/pacts")                     // in real life: @PactBroker (or PactFlow) instead of a folder
class InventoryProviderPactTest {
    @BeforeAll static void start() { app = SpringApplication.run(InventoryApp.class, "--server.port=18200", ...); }
    @BeforeEach void target(PactVerificationContext ctx) { ctx.setTarget(new HttpTestTarget("localhost", 18200)); }
    @State("book is in stock") void bookInStock() { /* seed test data for this provider state */ }

    @TestTemplate
    @ExtendWith(PactVerificationInvocationContextProvider.class)
    void verify(PactVerificationContext ctx) { ctx.verifyInteraction(); }
}
```

**Output (verified, compatible provider):**

```text
Verifying a pact between order-svc and inventory-svc
    returns a response which
      has status code 200 (OK)
      has a matching body (OK)
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
```

Now the provider team makes a "harmless" rename, `available` → `availableQty`:

**Output (verified, provider build fails):**

```text
      has a matching body (FAILED)
1) Verifying a pact between order-svc and inventory-svc - a stock lookup for book has a matching body
    1.1) body: $ Actual map is missing the following keys: available
        -  "available": 7,
        +  "availableQty": 7,
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
```

The break was caught **in the provider's CI**, with an exact diff, before deployment, without running the consumer.

### 4.3 Making contracts work in an organization

| Practice | Why |
|---|---|
| A **Pact Broker** (or PactFlow) stores contracts and verification results | Providers fetch all consumers' pacts; versions and environments are tracked |
| **`can-i-deploy`** check in every pipeline | "Is this version compatible with what's in production?", answered before deploying |
| Provider **states** set up test data | `given("book is in stock")` maps to a `@State` method |
| Contracts express what the consumer **uses**, with matchers | Not a copy of the provider's full response |
| Message pacts for Kafka events | Same idea for asynchronous contracts (event payloads) |

**Pact vs Spring Cloud Contract (5.0):** Pact is consumer-driven and polyglot (contracts generated from consumer tests). Spring Cloud Contract is usually **provider-driven** (contracts written by the provider in Groovy/YAML/Java DSL, which generate provider tests and consumer **stubs** for WireMock). Choose Pact for many independent consumer teams in different languages; Spring Cloud Contract for Spring-heavy organizations where providers publish stubs.

---

## 5. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| Hand-built HTTP clients without instrumentation | Auto-configured builders, or attach the `ObservationRegistry` (a missing one silently breaks the trace) |
| Kafka hops without trace headers | Observation enabled on templates and listeners; `traceparent` stored in outbox rows |
| Logs without trace ids | Correlation pattern (Boot default) + business keys in the MDC |
| 100% sampling in production, or 1% head sampling that drops every error | Parent-based head sampling + tail sampling for errors and slow traces |
| End-to-end test environment as the only integration check | Consumer-driven contracts + `can-i-deploy`; a few E2E smoke tests |
| Contracts that copy the provider's full response | Matchers for what the consumer actually uses |

---

## 6. Source to read

| Repo | What to look for |
|---|---|
| [micrometer-metrics/tracing](https://github.com/micrometer-metrics/tracing) | The OpenTelemetry bridge and W3C propagators |
| [micrometer-metrics/context-propagation](https://github.com/micrometer-metrics/context-propagation) | `ContextSnapshot`, ThreadLocal accessors across thread hops |
| [open-telemetry/opentelemetry-java-instrumentation](https://github.com/open-telemetry/opentelemetry-java-instrumentation) | The Java agent alternative (zero-code instrumentation) |
| [pact-foundation/pact-jvm](https://github.com/pact-foundation/pact-jvm) | `consumer/junit5/`, `provider/junit5/` modules |
| [spring-cloud/spring-cloud-contract](https://github.com/spring-cloud/spring-cloud-contract) | Provider-driven contracts and stub generation |

---

## 7. Interview soundbites

* "W3C `traceparent` carries the trace id, the parent span id and the sampling flag. In my test the same trace id showed up in both services' logs, and the backend saw the client span as its parent."
* "Context breaks at every boundary you don't instrument: hand-built HTTP clients, executors, Kafka, the outbox. In Boot 4 a `RestClient` built without the `ObservationRegistry` sends no `traceparent` at all."
* "Head sampling drops most error traces; tail sampling in the collector keeps errors and slow requests."
* "Consumer-driven contracts: the consumer's test generates the pact, the provider's CI replays it. A field rename failed the provider build with an exact diff, before deploy."

---

## 8. Deep dive: where telemetry lies, and where contracts hide (verified) 🔥

§1 proved context propagation across HTTP. Batch 2's labs found the places where the *data* your dashboards and contracts rely on is wrong, even with propagation working:

| Signal | What was measured | Evidence | Fix |
|---|---|---|---|
| Request status in a servlet filter | `status=200` recorded for a request that returned **500** (the exception left the filter chain before Tomcat's ERROR dispatch) | [4.8 §1](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#1-the-request-lifecycle-verified-) scenario 3 | Catch, record, rethrow; or rely on `ServerHttpObservationFilter`, whose bytecode records the error and sets 500 |
| Errors seen by an interceptor | A handled exception arrived as `afterCompletion(ex=null)` | 4.8 §1 scenario 2 | Read the response status, not `ex` |
| Request id in async logs | `requestId=null` after an extra `Executor` bean displaced Boot's (and its `TaskDecorator`) | [4.8 §3](../04-Spring-Boot-Internals/08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#3-async-which-executor-what-context-where-exceptions-go-verified-) | `spring.task.execution.mode=force` or build executors from `ThreadPoolTaskExecutorBuilder` |
| Error rate | A catch-all `@ExceptionHandler` turned an authorization failure into a **500** | [4.5 §9](../04-Spring-Boot-Internals/05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md#9-deep-dive-who-writes-your-401-and-403-and-why-a-catch-all-handler-turns-403-into-500-verified-) | A specific handler for security exceptions |
| A trace across the outbox | The 5.10 relay sends records with `messageId` and `type` headers only: **no `traceparent`**, so every saga trace ends at the outbox | [5.10 §3.3](10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md#33-the-relay-claim-send-the-batch-wait-for-every-ack-then-mark) | Store the current `traceparent` in an outbox column at write time; the relay copies it into a record header |

**Contracts hide in headers too.** Modulith's Kafka externalization stamped `__TypeId__=com.acme.shop.order.OrderPlaced` on every record ([5.11 §4](11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md#4-outage-and-restart-drill-verified-)). A Pact *message* contract that checks only the JSON body would pass, while a consumer that uses type headers fails at deserialization after the producer renames a class. Message contracts should pin the headers consumers depend on, or teams should agree that consumers ignore type headers (`spring.json.use.type.headers=false`).

**Reconciliation is an observability signal.** 5.10 accounted for every send: 702/217/61 published, 276/216/60 inbox rows, 0 unpublished. The production version is a few gauges:

* age of the oldest unpublished outbox row;
* sagas by state × age;
* DLT depth;
* inbox rows vs consumed offsets.

Unlike request-level telemetry, these catch the failure modes that never produce an error log.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| `traceparent` | version-traceid-parentid-flags; same trace id across services | §0–§1 |
| Instrumentation gaps | Hand-built clients, executors, Kafka and the outbox break context | §1–§2; §8 (outbox) |
| Correlation vs trace ids | Business correlation id ≠ trace id; log both | §2 |
| Sampling | Head sampling loses errors; tail sampling in the collector keeps them | §3 |
| Contract tests | Consumer-generated pacts replayed in provider CI; `can-i-deploy` | §4: a rename failed the provider build |
| Telemetry that lies | Filter status 200 for a 500; `ex=null` for handled errors; MDC lost; 403 → 500 | §8 |
| Header contracts | `__TypeId__` FQCNs are part of the message contract | §8 (5.11) |
| Reconciliation metrics | Outbox age, saga age by state, DLT depth | §8 (5.10 §7) |

**Next:** [5.8 Bar-raiser drill-downs →](08-Bar-Raiser-Drill-Downs.md)
