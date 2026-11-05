# 01 · Complete Java 21 Spring Boot Micrometer + OTel, Exemplar and Custom-Meter Code

> **Folder 07 — Production Blueprints: Spring Boot, Kubernetes and Rule Catalogs · File 1 of 3.**
> Pinned to the **Spring Boot 4.1.2** BOM:
> - Spring Framework 7.0.10
> - **Micrometer 1.17.2**, Micrometer Tracing 1.7.2
> - **OpenTelemetry Java 1.62.0**
> - Prometheus `client_java` (prometheus-metrics) 1.7.0
>
> Java source level **21**, compiled on JDK 25.0.4.1.
> Labels: **[D]** documented / read in pinned source or jar metadata · **[M]** measured · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `CheckoutObservabilityConfig.java` | Registry-wide guardrails: a pod tag, deny filters, a tag-cardinality cap, a histogram policy for `checkout.*` timers, an `ObservationPredicate` that skips actuator traffic, and a virtual-thread executor with metrics | compiled |
| L2 `CheckoutMetrics.java` | Business meters with closed tag sets: `MeterProvider` reuse, a strongly-referenced gauge, SLO-bucketed summary, long-task timer and a PSP timer | compiled |
| L3 `PaymentGatewayClient.java` | One `Observation` producing a timer (low-cardinality tags) and a span (plus high-cardinality attributes); `@Observed`; an instrumented `RestClient` | compiled |
| L4 `checkout-application.yaml` | Boot 4.1 actuator, metrics, tracing, exemplar and OTLP configuration, with every key valid in the Boot 4.1.2 metadata | validated by L5 |
| L5 `boot_micrometer_lab.py` | **Buckets.** A Python port of Micrometer's `PercentileHistogramBuckets` matches the real 1.17.2 registry: 276/66/48 buckets, and **69 and 54 `le` boundaries identical one by one**. **Names.** The naming port reproduces all 14 exposed series names. **Budget.** The `http.server.requests` series budget comes out at 28.8k/22.8k/2.8k per pod under three histogram policies. **Config lint.** It lints `application.yaml` against 643 properties shipped in 12 Boot jars and catches six Boot-3-era mistakes | <1 s |

**Verification.**
- **Compilation.** L1–L3 were compiled with `javac -proc:none --release 21 -Xlint:all -Werror` against 40 jars from Maven Central (Boot 4.1.2 BOM versions), each checked against its published SHA-1. They compiled clean with zero warnings [M].
- **Runtime oracle.** A small Java program ran these classes against the real Micrometer 1.17.2 `PrometheusMeterRegistry` on JDK 25 and recorded bucket counts, every `le` boundary and the exposed series names. It is kept in `fixtures/micrometer-1.17.2-oracle/` with its source. L5's ports are checked against that output [M].
- **Configuration keys.** These come from the `spring-configuration-metadata.json` inside the Boot 4.1.2 jars, kept in `fixtures/spring-boot-4.1.2-metadata/` [D].
- **Not run.** No Spring application context was started.

---

## 0. Orientation

**What this file answers.**
- What a production Spring Boot 4.1 service must emit.
- What the code looks like.
- What each line costs in series, and why each default is or is not acceptable.
- How metrics, traces, exemplars and logs stay joined.

**Signal flow out of one pod.**

```text
                       ┌──────────────────────── checkout pod (Java 21, Boot 4.1) ─────────────────────────┐
 HTTP request ───────► │ ServerHttpObservationFilter ──► Observation "http.server.requests"                 │
                       │      │ low-card key values (method, uri template, status, outcome, exception)      │
                       │      ├─► DefaultMeterObservationHandler ─► Timer http.server.requests (+histogram)  │
                       │      └─► Micrometer Tracing (OTel bridge) ─► Span (+ high-card attributes)          │
                       │ Business code: CheckoutMetrics (Counter/Timer/Summary/Gauge/LongTaskTimer)          │
                       │                PaymentGatewayClient: Observation "checkout.payment.charge"          │
                       │ MDC: traceId/spanId ─► structured JSON logs (logging.structured.format.console)     │
                       └──────┬──────────────────────────────┬───────────────────────────────┬──────────────┘
                              │ GET :8081/actuator/prometheus │ OTLP/HTTP :4318 /v1/traces     │ stdout JSON
                              │ OpenMetrics + exemplars       │ sampler: parent-based ratio 0.1 │
                              ▼                               ▼                                 ▼
                        Prometheus/Alloy scrape      otel-router (Folder 06 file 01)      Alloy → Loki
                        exemplar {trace_id} ──────────────────► Tempo  ◄──────── trace_id in structured metadata
```

**The three rules everything below enforces.**
1. **Bounded tags.** Every tag value comes from a closed set.
2. **Explicit histograms.** Every histogram has explicit min/max and SLO boundaries.
3. **One instrumentation point per operation.** Use one `Observation`, not hand-rolled timers plus spans.

---

## 1. First principles

### 1.1 From a Micrometer meter to Prometheus series [D][M]

Micrometer names are dotted and unit-free. The Prometheus registry turns them into OpenMetrics names. L5 §2 ports `PrometheusNamingConvention` and `client_java`'s `sanitizeMetricName`, and reproduces the 14 names the real registry exposed:

| Meter (type) | Exposed series |
|---|---|
| `checkout.orders` (Counter) | `checkout_orders_total` |
| `checkout.psp.latency` (Timer) | `checkout_psp_latency_seconds_{bucket,count,sum,max}` |
| `checkout.basket.items` (DistributionSummary, baseUnit `items`) | `checkout_basket_items_{count,sum,max}` (+ `_bucket` from SLOs) |
| `checkout.psp.inflight` (Gauge) | `checkout_psp_inflight` |
| `checkout.reconciliation.active` (LongTaskTimer) | `checkout_reconciliation_active_seconds_{count,sum,max}` |

**Traps the port makes visible.**
- **Reserved suffixes.** `.total` and `.created` are stripped (`orders.total` → `orders_total`; `cache.gets.created` → `cache_gets_total`), because `client_java` 1.x adds its own suffixes [D].
- **Timers get `_seconds`.** Every timer gets `_seconds` and a `_max` gauge. `_max` is a decaying per-pod maximum: never `sum` it, and only `max` it.
- **Base units are appended.** Gauges and counters with a `baseUnit` get it appended (`queue.size` with `bytes` → `queue_size_bytes`).

### 1.2 Percentile histograms: where the buckets come from [D][M]

`PercentileHistogramBuckets` builds one fixed ladder in base units (nanoseconds for timers):

```text
 1, 2, 3, then for exp = 2, 4, 6, … 62:   start = 2^exp, delta = start/3,
          add start, start+delta, … while value < 4·start − delta        (Java long: 4·2^62 overflows → skipped)
 → 276 buckets in total + Inf        a timer keeps only buckets in [minimumExpectedValue, maximumExpectedValue]
 Prometheus registry boundaries = ladder ∩ [min, max]  ∪  SLO boundaries  ∪  {min, max}  ∪  {+Inf}
```

Ground truth from the real registry (fixture) and the port (L5 §1), identical boundary by boundary:

| Timer configuration | Ladder buckets kept | Exposed `le` boundaries |
|---|---|---|
| default (1 ms … 30 s), `percentiles-histogram: true` | 66 | **69** (0.001, 0.001048576, … 28.633115306, 30.0, +Inf) |
| `checkout.*` policy (5 ms … 10 s + SLOs 100 ms, 300 ms, 1 s) | 48 | **54** |

**Consequences.**
- **Multiplied out.** Each bucket is a series per tag combination, so 69 buckets × tag sets × pods is your bill (§1.5).
- **SLO boundaries make thresholds exact.** `le="0.3"` exists only because 300 ms is configured as an SLO boundary. Without it, a "99% under 300 ms" SLI can only be approximated by interpolating between 0.268 and 0.358, and the File 03 recording rules that select `le="0.3"` return **nothing**.
- **Client-side percentiles do not aggregate.** `percentiles: 0.99` emits one gauge per pod per tag set. Averaging or summing those across pods is mathematically meaningless (Folder 02 file 03). Use them only for single-instance debugging.

### 1.3 The Observation API: one call site, two signals [D]

`Observation.createNotStarted(name, registry)…observe(…)` is handled by every registered handler:
- `DefaultMeterObservationHandler` creates a **timer** (plus a long-task timer while active) tagged with **low-cardinality** key values.
- The tracing handler creates a **span** with low- **and** high-cardinality key values as attributes.

L3 puts `psp` and `currency` in low cardinality (bounded) and `order.id` in high cardinality (unbounded). The order ID is then searchable in Tempo and never becomes a metric label.

- `ObservationPredicate` (L1) vetoes observations. Skipping `/actuator/*` keeps scrapes and probes out of RED **and** out of traces.
- `@Observed` works only with `management.observations.annotations.enabled=true` (default **false** [D]). Boot then registers the aspect.
- Inject Boot's `RestClient.Builder` (L3). It carries the client observation convention, so you get `http.client.requests` plus `traceparent` propagation. `RestClient.create()` silently produces neither.

### 1.4 Tracing, sampling and exemplars in Boot 4.1 [D]

From the 4.1.2 metadata:

| Property | Default | Note |
|---|---|---|
| `management.tracing.sampling.probability` | **0.1** | Head sampling at the root (`parent-based-trace-id-ratio` sampler) |
| `management.tracing.exemplars.include` | **`sampled-traces`** | Values: `none`, `sampled-traces`, `all`. **"'all' is not supported when using Prometheus."** |
| `management.tracing.propagation.produce` / `.consume` | `W3C` / `W3C, B3, B3_MULTI` | Emit W3C only, accept B3 from legacy callers |
| `management.opentelemetry.tracing.export.otlp.endpoint` | none | Boot 4 location; `management.otlp.tracing.endpoint` was **removed in 4.0.0** (deprecation level `error`) |
| `management.opentelemetry.tracing.export.otlp.transport` | `http` | `grpc` also available |
| `management.opentelemetry.tracing.export.max-queue-size` | 2048 | Raise for bursty services; dropped spans are silent |
| `management.prometheus.metrics.export.enabled` | true | `management.metrics.export.prometheus.*` is the pre-3.0 location |

**Exemplars are the bridge to Folder 05.**
- With `sampled-traces`, every exemplar points at a trace the SDK exported. That fixes the "trace not found" problem caused by unsampled exemplars.
- It does not survive a downstream tail sampler that drops the trace (Folder 06 file 01).
- Align the tail policy with what exemplars select (errors and slow requests), or accept that some exemplars dangle.
- Exemplars appear only in the **OpenMetrics** exposition. Prometheus negotiates it by default in 3.x, while other scrapers may not.

### 1.5 The series budget of `http.server.requests` [M]

**Tag set.** The tags are `method`, `uri` (the *template*, e.g. `/orders/{id}`), `status`, `outcome`, `exception` and `error`. `outcome` and `error` derive from `status` and `exception`, so they rarely multiply series. L5 §3 takes 40 routes × 2 methods × 5 statuses = 400 tag sets per pod:

| Policy | Buckets | Series/pod | 60 pods |
|---|---|---|---|
| percentile histogram, default 1 ms–30 s | 69 | 28,800 | 1.73 M |
| clamped 5 ms–10 s + 3 SLO boundaries | 54 | 22,800 | 1.37 M |
| SLO boundaries only (no percentile histogram) | 4 | 2,800 | 168 k |

**URI tag guard.** `management.metrics.web.server.max-uri-tags` (default **100** [D]) caps distinct `uri` values. After the cap, Boot's `MaximumAllowableTagsMeterFilter` denies new ones and logs a warning once.
- It protects you from `uri` explosions caused by unmatched routes, for example a scanner probing 50k random paths.
- **It does not protect custom meters.** That is why L1 adds `maximumAllowableTags` for the `tenant` tag.

### 1.6 Gauges, providers, virtual threads [D]

**Gauges hold weak references.**
- `registry.gauge(name, obj)` keeps a **weak** reference to `obj`.
- If nothing else references it, GC collects it and the gauge reports `NaN` forever.
- L2 keeps the `AtomicInteger` in a field.

**`Meter.MeterProvider` (`builder.withRegistry(registry)`).**
- It creates or looks up meters for dynamic tag values without rebuilding the builder per call.
- Tag values still have to be bounded. L2 maps unknown PSPs to `other`.

**Virtual threads (`spring.threads.virtual.enabled=true`).**
- Executors built with `newVirtualThreadPerTaskExecutor()` are not `ThreadPoolExecutor`s. `ExecutorServiceMetrics` can time submitted tasks but has no pool gauges to report.
- In-flight concurrency must be measured explicitly (L2's `checkout.psp.inflight`).
- On a JDK 21 runtime, `synchronized` blocks pin the carrier thread. JDK 24 (JEP 491) removed that pinning, so prefer a JDK ≥ 24 runtime even for `--release 21` code.

<!-- listing:CheckoutObservabilityConfig.java -->
```java
package com.acme.checkout.observability;

import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Tag;
import io.micrometer.core.instrument.binder.jvm.ExecutorServiceMetrics;
import io.micrometer.core.instrument.config.MeterFilter;
import io.micrometer.core.instrument.distribution.DistributionStatisticConfig;
import io.micrometer.observation.ObservationPredicate;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.micrometer.metrics.autoconfigure.MeterRegistryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.server.observation.ServerRequestObservationContext;

/**
 * Registry-wide policy for the checkout service (Spring Boot 4.1, Micrometer 1.17).
 * Everything here is a guardrail: what may be created, with which buckets, at what cardinality.
 */
@Configuration(proxyBeanMethods = false)
public class CheckoutObservabilityConfig {

    private static final double MS = Duration.ofMillis(1).toNanos();

    /** Pod identity for exemplar/trace joins; application and region come from management.metrics.tags. */
    @Bean
    MeterRegistryCustomizer<MeterRegistry> podTag(@Value("${HOSTNAME:local}") String pod) {
        return registry -> registry.config().commonTags("pod", pod);
    }

    /** Meters nobody reads cost series in every pod; deny them before they are created. */
    @Bean
    MeterFilter denyUnusedMeters() {
        return MeterFilter.denyNameStartsWith("jvm.compilation");
    }

    /**
     * A tenant tag is useful until a crawler invents 10,000 tenants. After 50 distinct values the
     * meter is denied (and Micrometer logs it once) instead of creating series without bound.
     */
    @Bean
    MeterFilter tenantCardinalityGuard() {
        return MeterFilter.maximumAllowableTags("checkout.orders", "tenant", 50, MeterFilter.deny());
    }

    /**
     * Every checkout.* timer: percentile histogram clamped to 5 ms .. 10 s plus SLO boundaries that
     * line up with the alerting thresholds, so histogram_quantile and le="0.3" ratios are exact there.
     */
    @Bean
    MeterFilter checkoutLatencyHistograms() {
        return new MeterFilter() {
            @Override
            public DistributionStatisticConfig configure(Meter.Id id, DistributionStatisticConfig config) {
                if (id.getType() != Meter.Type.TIMER || !id.getName().startsWith("checkout.")) {
                    return config;
                }
                return DistributionStatisticConfig.builder()
                    .percentilesHistogram(true)
                    .serviceLevelObjectives(100 * MS, 300 * MS, 1000 * MS)
                    .minimumExpectedValue(5 * MS)
                    .maximumExpectedValue(10_000 * MS)
                    .build()
                    .merge(config);
            }
        };
    }

    /** No observation (metric or span) for scrapes and probes: they would dominate traces and RED. */
    @Bean
    ObservationPredicate ignoreActuatorRequests() {
        return (name, context) -> {
            if (context instanceof ServerRequestObservationContext server) {
                return !server.getCarrier().getRequestURI().startsWith("/actuator");
            }
            return true;
        };
    }

    /**
     * Virtual-thread executor for PSP calls. ExecutorServiceMetrics wraps it with execution/idle
     * timers; pool gauges (active, queued) exist only for ThreadPoolExecutor/ForkJoinPool, not for
     * thread-per-task executors, so in-flight work is tracked by CheckoutMetrics' gauge instead.
     */
    @Bean(destroyMethod = "close")
    ExecutorService pspExecutor(MeterRegistry registry) {
        return ExecutorServiceMetrics.monitor(registry, Executors.newVirtualThreadPerTaskExecutor(), "psp-calls",
            List.of(Tag.of("threads", "virtual")));
    }
}
```

<!-- listing:CheckoutMetrics.java -->
```java
package com.acme.checkout.observability;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.LongTaskTimer;
import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;
import org.springframework.stereotype.Component;

/**
 * Business and dependency meters for checkout. Rules applied throughout:
 * tag values come from closed sets (enums or an allow-list), meters are created once and reused
 * via MeterProvider, and gauges hold a strong reference to their state.
 */
@Component
public final class CheckoutMetrics {

    public enum PaymentMethod { CARD, WALLET, BNPL, GIFT_CARD }

    public enum Outcome { SUCCESS, DECLINED, ERROR }

    private static final Set<String> KNOWN_PSPS = Set.of("adyen", "stripe", "braintree");

    private final MeterRegistry registry;
    private final AtomicInteger pspInFlight;
    private final DistributionSummary basketItems;
    private final LongTaskTimer reconciliation;
    private final Meter.MeterProvider<Timer> pspLatency;
    private final Meter.MeterProvider<Counter> orders;

    public CheckoutMetrics(MeterRegistry registry) {
        this.registry = registry;
        // registry.gauge keeps only a weak reference to the state object; the field keeps it alive.
        this.pspInFlight = registry.gauge("checkout.psp.inflight", new AtomicInteger());
        this.basketItems = DistributionSummary.builder("checkout.basket.items")
            .description("Items per completed order")
            .baseUnit("items")
            .serviceLevelObjectives(1, 5, 10, 25, 50)
            .register(registry);
        this.reconciliation = LongTaskTimer.builder("checkout.reconciliation.active")
            .description("Running ledger reconciliation jobs")
            .register(registry);
        this.pspLatency = Timer.builder("checkout.psp.latency")
            .description("Payment service provider call latency")
            .withRegistry(registry);
        this.orders = Counter.builder("checkout.orders")
            .description("Completed orders by payment method and outcome")
            .withRegistry(registry);
    }

    public void orderCompleted(PaymentMethod method, Outcome outcome, int items) {
        orders.withTags("payment_method", lower(method), "outcome", lower(outcome)).increment();
        basketItems.record(items);
    }

    /** Times a PSP call; the psp tag is mapped onto a closed set so a typo cannot mint new series. */
    public <T> T timePsp(String psp, Supplier<T> call) {
        String pspTag = KNOWN_PSPS.contains(psp) ? psp : "other";
        Timer.Sample sample = Timer.start(registry);
        pspInFlight.incrementAndGet();
        String outcome = "error";
        try {
            T result = call.get();
            outcome = "success";
            return result;
        } finally {
            pspInFlight.decrementAndGet();
            sample.stop(pspLatency.withTags("psp", pspTag, "outcome", outcome));
        }
    }

    public void reconcile(Runnable job) {
        reconciliation.record(job);
    }

    private static String lower(Enum<?> value) {
        return value.name().toLowerCase(Locale.ROOT);
    }
}
```

<!-- listing:PaymentGatewayClient.java -->
```java
package com.acme.checkout.observability;

import io.micrometer.observation.Observation;
import io.micrometer.observation.ObservationRegistry;
import io.micrometer.observation.annotation.Observed;
import io.micrometer.tracing.Span;
import io.micrometer.tracing.Tracer;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

/**
 * Outbound PSP calls. One Observation produces both a timer (checkout.payment.charge, tagged only
 * with LOW-cardinality key values) and a span (which also carries the HIGH-cardinality ones).
 */
@Service
public class PaymentGatewayClient {

    public record ChargeRequest(String orderId, String psp, long amountMinor, String currency) { }

    public record ChargeResult(String id, String status) { }

    private final RestClient http;
    private final ObservationRegistry observations;
    private final CheckoutMetrics metrics;
    private final Tracer tracer;

    public PaymentGatewayClient(RestClient.Builder builder, ObservationRegistry observations,
                                CheckoutMetrics metrics, Tracer tracer) {
        // Inject Boot's RestClient.Builder: it carries the observation convention that emits
        // http.client.requests and propagates traceparent. RestClient.create() would lose both.
        this.http = builder.baseUrl("https://psp-gateway.internal").build();
        this.observations = observations;
        this.metrics = metrics;
        this.tracer = tracer;
    }

    public ChargeResult charge(ChargeRequest request) {
        return Observation.createNotStarted("checkout.payment.charge", observations)
            .contextualName("charge " + request.psp())
            .lowCardinalityKeyValue("psp", request.psp())
            .lowCardinalityKeyValue("currency", request.currency())
            .highCardinalityKeyValue("order.id", request.orderId())
            .observe(() -> metrics.timePsp(request.psp(), () -> {
                Span span = tracer.currentSpan();
                if (span != null) {
                    span.event("psp.request.sent");
                }
                return http.post()
                    .uri("/v1/charges")
                    .body(request)
                    .retrieve()
                    .body(ChargeResult.class);
            }));
    }

    /** Needs management.observations.annotations.enabled=true (Boot then registers ObservedAspect). */
    @Observed(name = "checkout.fraud.score", contextualName = "fraud-score",
        lowCardinalityKeyValues = {"model", "gbdt-v7"})
    public double fraudScore(ChargeRequest request) {
        return request.amountMinor() > 500_00 ? 0.42 : 0.05;
    }
}
```

<!-- listing:checkout-application.yaml -->
```yaml
# application.yaml for the checkout service (Spring Boot 4.1.2). Every key is checked by
# boot_micrometer_lab.py against the configuration metadata shipped in the Boot 4.1.2 jars.
spring:
  application:
    name: checkout
  threads:
    virtual:
      enabled: true
management:
  server:
    port: 8081
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true
      show-details: never
  metrics:
    tags:
      application: ${spring.application.name}
      region: ${REGION:unknown}
    distribution:
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 100ms,300ms,1s
      minimum-expected-value:
        http.server.requests: 5ms
      maximum-expected-value:
        http.server.requests: 10s
    web:
      server:
        max-uri-tags: 150
  observations:
    annotations:
      enabled: true
    key-values:
      team: payments
  tracing:
    sampling:
      probability: 0.1
    exemplars:
      include: sampled-traces
    propagation:
      produce: [w3c]
      consume: [w3c, b3]
  opentelemetry:
    resource-attributes:
      service.namespace: shop
      deployment.environment.name: ${ENVIRONMENT:production}
    tracing:
      sampler: parent-based-trace-id-ratio
      export:
        max-queue-size: 8192
        otlp:
          endpoint: http://otel-router.observability.svc:4318/v1/traces
          transport: http
          compression: gzip
          timeout: 5s
  prometheus:
    metrics:
      export:
        enabled: true
```

<!-- listing:boot_micrometer_lab.py -->
```python
"""boot_micrometer_lab.py - what a Spring Boot 4.1 / Micrometer 1.17 service actually exposes, checked
against ground truth produced by the real libraries:

  1. Port of Micrometer's PercentileHistogramBuckets (powers of 4 with thirds, Java long overflow and
     all) plus the Prometheus registry's boundary assembly (percentile buckets in [min, max] + SLOs +
     min + max + Inf), compared boundary-for-boundary with fixtures/micrometer-1.17.2-oracle/oracle.json,
     which was produced by running Micrometer 1.17.2 on JDK 25 with this folder's Java classes.
  2. Port of PrometheusNamingConvention + client_java 1.7.0 sanitizeMetricName, compared with the
     series names the real registry exposed.
  3. The series budget of http.server.requests under three histogram policies.
  4. A linter for application.yaml against the configuration metadata shipped in the Spring Boot 4.1.2
     jars (fixtures/spring-boot-4.1.2-metadata/properties.json): unknown keys, keys removed in 4.0
     (deprecation level "error" with their replacements), enum values, and ranges.

Deterministic, stdlib only. Usage: python boot_micrometer_lab.py <target.md>
"""
import json
import math
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent


def java_long(x):
    x &= 0xFFFFFFFFFFFFFFFF
    return x - (1 << 64) if x >= 1 << 63 else x


def percentile_buckets():
    """PercentileHistogramBuckets static initialiser (DIGITS = 2), with Java signed-long arithmetic."""
    out = {1.0, 2.0, 3.0}
    exp = 2
    while exp < 64:
        current = java_long(1 << exp)
        delta = java_long(int(current / 3)) if current >= 0 else java_long(-(-current // 3))
        nxt = java_long(java_long(current << 2) - delta)
        while current < nxt:
            out.add(float(current))
            current = java_long(current + delta)
        exp += 2
    out.add(math.inf)
    return sorted(out)


def histogram_boundaries(min_ns, max_ns, slos_ns=()):
    """Buckets the Prometheus registry exposes for a timer with publishPercentileHistogram."""
    pct = [b for b in percentile_buckets() if min_ns <= b <= max_ns]
    bounds = sorted(set(pct) | set(slos_ns) | {float(min_ns), float(max_ns)})
    return [b / 1e9 for b in bounds] + [math.inf]


def prometheus_name(name):
    s = re.sub(r"[^a-zA-Z0-9_:]", "_", name)
    return "_" + s if s[:1].isdigit() else s


def sanitize_metric_name(name):
    suffixes = ["_total", "_created", "_bucket", "_info", ".total", ".created", ".bucket", ".info"]
    stripped = True
    while stripped:
        stripped = False
        if name in suffixes:
            return name[1:]
        for suf in suffixes:
            if name.endswith(suf):
                name, stripped = name[: -len(suf)], True
                break
    return name


def micrometer_prometheus_names(name, kind, base_unit=None):
    """PrometheusNamingConvention.name + what the text format appends per meter type."""
    n = prometheus_name(name)
    if kind in ("counter", "summary", "gauge") and base_unit and not n.endswith("_" + base_unit):
        n += "_" + base_unit
    if kind in ("timer", "long_task_timer") and not n.endswith("_seconds"):
        n += "_seconds"
    n = sanitize_metric_name(n)
    if kind == "counter":
        return [n + "_total"]
    if kind == "gauge":
        return [n]
    return [n + "_count", n + "_max", n + "_sum"]


def parse_yaml_subset(text):
    """Indentation-based subset: nested maps, scalars, [inline, lists], comments. Keys may contain dots."""
    root, stack = {}, [(-1, None)]
    stack[0] = (-1, root)
    for raw in text.splitlines():
        line = raw.split(" #")[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        key, _, value = line.strip().partition(":")
        value = value.strip()
        while stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if value == "":
            parent[key] = {}
            stack.append((indent, parent[key]))
        elif value.startswith("[") and value.endswith("]"):
            parent[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            parent[key] = value
    return root


def flatten(d, prefix=""):
    for k, v in d.items():
        path = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            yield from flatten(v, path)
        else:
            yield path, v


def lint(config_text, meta):
    props, enums = meta["properties"], meta["enums"]
    findings = []
    for path, value in flatten(parse_yaml_subset(config_text)):
        prop, name = props.get(path), path
        if prop is None:                                  # a Map-typed property owns arbitrary sub-keys
            parts = path.split(".")
            for i in range(len(parts) - 1, 0, -1):
                cand = ".".join(parts[:i])
                if cand in props and (props[cand].get("type") or "").startswith("java.util.Map"):
                    prop, name = props[cand], cand
                    break
        if prop is None:
            findings.append(("ERROR", path, "unknown property (no metadata in Boot 4.1.2)"))
            continue
        dep = prop.get("deprecation")
        if dep:
            lvl = "ERROR" if dep.get("level") == "error" else "WARN"
            findings.append((lvl, path, f"deprecated since {dep.get('since')}; use {dep.get('replacement')}"))
            continue
        typ = prop.get("type") or ""
        if typ in enums and not str(value).startswith("${"):
            vals = value if isinstance(value, list) else [value]
            for v in vals:
                if v.upper().replace("-", "_") not in enums[typ]:
                    findings.append(("ERROR", path, f"'{v}' not in {enums[typ]}"))
        if name == "management.tracing.sampling.probability":
            if not 0.0 <= float(value) <= 1.0:
                findings.append(("ERROR", path, "probability must be within [0, 1]"))
        if name == "management.tracing.exemplars.include" and str(value).lower() == "all":
            findings.append(("ERROR", path, "'all' is not supported when using Prometheus (metadata description)"))
    return findings


BOOT3_STYLE = """
management:
  tracing:
    enabled: true
    sampling:
      probability: 1.5
    exemplars:
      include: all
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces
  opentelemetry:
    tracing:
      export:
        otlp:
          transport: thrift
  metrics:
    distribution:
      percentiles-histogram:
        http.server.requests: true
    export:
      prometheus:
        enabled: true
"""


def main():
    target = pathlib.Path(sys.argv[1]).resolve()
    fx = target.parent / "fixtures"
    oracle = json.loads((fx / "micrometer-1.17.2-oracle" / "oracle.json").read_text(encoding="utf-8"))
    meta = json.loads((fx / "spring-boot-4.1.2-metadata" / "properties.json").read_text(encoding="utf-8"))
    checks = []
    MS = 1e6

    print("== 1. Percentile-histogram buckets: Python port vs the real Micrometer 1.17.2 registry ==")
    allb = percentile_buckets()
    tdef = [b for b in allb if 1 * MS <= b <= 30_000 * MS]
    chk = [b for b in allb if 5 * MS <= b <= 10_000 * MS]
    oc = oracle["bucket_counts"]
    print(f"generator: {len(allb)} buckets in total (oracle {oc['all_buckets']}); timer default 1ms..30s keeps "
          f"{len(tdef)} (oracle {oc['timer_default_buckets']}); clamped 5ms..10s keeps {len(chk)} (oracle {oc['checkout_buckets']})")
    http_b = histogram_boundaries(1 * MS, 30_000 * MS)
    psp_b = histogram_boundaries(5 * MS, 10_000 * MS, (100 * MS, 300 * MS, 1000 * MS))

    def same(mine, theirs):
        th = [math.inf if x == "+Inf" else float(x) for x in theirs]
        return len(mine) == len(th) and all(a == b or abs(a - b) <= 1e-9 * max(1, abs(b)) for a, b in zip(mine, th))
    ok_http = same(http_b, oracle["le_boundaries"]["http_server_requests_seconds_bucket"])
    ok_psp = same(psp_b, oracle["le_boundaries"]["checkout_psp_latency_seconds_bucket"])
    print(f"http.server.requests (defaults): {len(http_b)} le boundaries, identical to oracle: {ok_http}")
    print(f"checkout.psp.latency (5ms..10s + SLO 100ms/300ms/1s): {len(psp_b)} le boundaries, identical: {ok_psp}")
    print(f"first boundaries: {[round(b, 9) for b in http_b[:4]]} ... last: {http_b[-3:]}")
    checks.append(("bucket port == real registry", len(allb) == oc["all_buckets"] and len(tdef) == oc["timer_default_buckets"]
                   and len(chk) == oc["checkout_buckets"] and ok_http and ok_psp))
    print()

    print("== 2. Meter names: Micrometer -> Prometheus exposition ==")
    meters = [("checkout.orders", "counter", None), ("checkout.psp.latency", "timer", None),
              ("checkout.basket.items", "summary", "items"), ("checkout.psp.inflight", "gauge", None),
              ("checkout.reconciliation.active", "long_task_timer", None), ("http.server.requests", "timer", None)]
    mine = sorted(n for m in meters for n in micrometer_prometheus_names(*m))
    print(f"ported names: {mine}")
    print(f"identical to the {len(oracle['exposed_series_names'])} names the real registry exposed: "
          f"{mine == oracle['exposed_series_names']}")
    traps = [("orders.total", "counter", None), ("cache.gets.created", "counter", None), ("queue.size", "gauge", "bytes")]
    for t in traps:
        print(f"  {t[0]!r:<22} ({t[1]}) -> {micrometer_prometheus_names(*t)}")
    checks.append(("naming port == real registry", mine == oracle["exposed_series_names"]))
    print("-> '.total' and '.created' are reserved suffixes: client_java strips them before adding its own.")
    print()

    print("== 3. http.server.requests series budget (per pod, then fleet of 60 pods) ==")
    tagsets = 40 * 2 * 5   # routes x methods actually used x status codes seen; outcome/error derive from status
    policies = [("percentiles-histogram, default 1ms..30s", len(http_b)),
                ("percentiles-histogram clamped 5ms..10s + 3 SLOs", len(psp_b)),
                ("SLO boundaries only (100ms, 300ms, 1s)", 4)]
    rows = []
    for name, nb in policies:
        per_pod = tagsets * (nb + 3)          # buckets + _count + _sum + _max
        rows.append(per_pod)
        print(f"{name:<52} {nb:>3} buckets -> {per_pod:>7,} series/pod, {per_pod * 60:>10,} for 60 pods")
    checks.append(("budget ordering", rows[0] > rows[1] > rows[2]))
    print("-> the histogram policy is a cost decision: clamping min/max removes ~20% of series; SLO-only")
    print("   buckets cut 90%+ but leave histogram_quantile with 4 points. Clamp everything, enable full")
    print("   percentile histograms only on SLO-bearing endpoints, and never on per-tenant meters.")
    print()

    print("== 4. application.yaml vs the Spring Boot 4.1.2 configuration metadata ==")
    cfg = (HERE / "checkout-application.yaml").read_text(encoding="utf-8")
    keys = list(flatten(parse_yaml_subset(cfg)))
    f_ok = lint(cfg, meta)
    print(f"checkout-application.yaml: {len(keys)} keys checked against {len(meta['properties'])} properties "
          f"from {len(meta['jars'])} jars -> {len(f_ok)} findings")
    f_bad = lint(BOOT3_STYLE, meta)
    print("a Boot 3-era configuration:")
    for lvl, path, msg in f_bad:
        print(f"  {lvl:<5} {path}: {msg}")
    errors = {p for lvl, p, _ in f_bad if lvl == "ERROR"}
    checks.append(("clean config passes", not f_ok))
    checks.append(("boot-3 config caught", {"management.tracing.enabled", "management.otlp.tracing.endpoint",
                                             "management.tracing.sampling.probability",
                                             "management.tracing.exemplars.include",
                                             "management.opentelemetry.tracing.export.otlp.transport",
                                             "management.metrics.export.prometheus.enabled"} <= errors))
    print("-> Boot 4 moved OTLP trace export to management.opentelemetry.tracing.export.otlp.*. Boot binds")
    print("   unknown keys to nothing without failing (spring-boot-properties-migrator reports renamed ones")
    print("   at startup), so a stale endpoint key means no exporter is configured and traces simply stop.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:boot_micrometer_lab.py -->
```text
== 1. Percentile-histogram buckets: Python port vs the real Micrometer 1.17.2 registry ==
generator: 276 buckets in total (oracle 276); timer default 1ms..30s keeps 66 (oracle 66); clamped 5ms..10s keeps 48 (oracle 48)
http.server.requests (defaults): 69 le boundaries, identical to oracle: True
checkout.psp.latency (5ms..10s + SLO 100ms/300ms/1s): 54 le boundaries, identical: True
first boundaries: [0.001, 0.001048576, 0.001398101, 0.001747626] ... last: [28.633115306, 30.0, inf]

== 2. Meter names: Micrometer -> Prometheus exposition ==
ported names: ['checkout_basket_items_count', 'checkout_basket_items_max', 'checkout_basket_items_sum', 'checkout_orders_total', 'checkout_psp_inflight', 'checkout_psp_latency_seconds_count', 'checkout_psp_latency_seconds_max', 'checkout_psp_latency_seconds_sum', 'checkout_reconciliation_active_seconds_count', 'checkout_reconciliation_active_seconds_max', 'checkout_reconciliation_active_seconds_sum', 'http_server_requests_seconds_count', 'http_server_requests_seconds_max', 'http_server_requests_seconds_sum']
identical to the 14 names the real registry exposed: True
  'orders.total'         (counter) -> ['orders_total']
  'cache.gets.created'   (counter) -> ['cache_gets_total']
  'queue.size'           (gauge) -> ['queue_size_bytes']
-> '.total' and '.created' are reserved suffixes: client_java strips them before adding its own.

== 3. http.server.requests series budget (per pod, then fleet of 60 pods) ==
percentiles-histogram, default 1ms..30s               69 buckets ->  28,800 series/pod,  1,728,000 for 60 pods
percentiles-histogram clamped 5ms..10s + 3 SLOs       54 buckets ->  22,800 series/pod,  1,368,000 for 60 pods
SLO boundaries only (100ms, 300ms, 1s)                 4 buckets ->   2,800 series/pod,    168,000 for 60 pods
-> the histogram policy is a cost decision: clamping min/max removes ~20% of series; SLO-only
   buckets cut 90%+ but leave histogram_quantile with 4 points. Clamp everything, enable full
   percentile histograms only on SLO-bearing endpoints, and never on per-tenant meters.

== 4. application.yaml vs the Spring Boot 4.1.2 configuration metadata ==
checkout-application.yaml: 28 keys checked against 643 properties from 12 jars -> 0 findings
a Boot 3-era configuration:
  ERROR management.tracing.enabled: deprecated since 4.0.0; use management.tracing.export.enabled
  ERROR management.tracing.sampling.probability: probability must be within [0, 1]
  ERROR management.tracing.exemplars.include: 'all' is not supported when using Prometheus (metadata description)
  ERROR management.otlp.tracing.endpoint: deprecated since 4.0.0; use management.opentelemetry.tracing.export.otlp.endpoint
  ERROR management.opentelemetry.tracing.export.otlp.transport: 'thrift' not in ['GRPC', 'HTTP']
  ERROR management.metrics.export.prometheus.enabled: deprecated since 3.0.0; use management.prometheus.metrics.export.enabled
-> Boot 4 moved OTLP trace export to management.opentelemetry.tracing.export.otlp.*. Boot binds
   unknown keys to nothing without failing (spring-boot-properties-migrator reports renamed ones
   at startup), so a stale endpoint key means no exporter is configured and traces simply stop.

checks: 5/5 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Build: Boot 4 modular starters (Gradle Kotlin DSL)

```kotlin
// build.gradle.kts (the compile check above used the same BOM versions as plain jars)
plugins {
    java
    id("org.springframework.boot") version "4.1.2"
    id("io.spring.dependency-management") version "1.1.7"
}
java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-restclient")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-opentelemetry")   // Micrometer Tracing → OTel, OTLP export
    implementation("io.micrometer:micrometer-registry-prometheus")                  // /actuator/prometheus
    runtimeOnly("org.springframework.boot:spring-boot-properties-migrator")         // logs renamed keys at startup; remove after migrating
    testImplementation("org.springframework.boot:spring-boot-starter-micrometer-metrics-test")
}
```

⚠ **Not built here.** The Gradle plugin versions were not built in this environment, and the dependency-management plugin version is illustrative. The artifact names come from the Boot 4.1.2 BOM (`spring-boot-dependencies-4.1.2.pom`) [D].

### 2.2 Logs that join traces

```yaml
# application.yaml additions: JSON logs with traceId/spanId from MDC (Boot puts them there when tracing is on)
logging:
  structured:
    format:
      console: ecs
    ecs:
      service:
        environment: production
  include-application-name: true
```

- **Format.** `logging.structured.format.console` accepts `ecs`, `logstash`, `gelf` or a class name [D].
- **Correlation.** With tracing active, the trace and span IDs land in every log line.
- **Ingestion.** Alloy moves `trace_id` into Loki structured metadata (Folder 06 file 03), never into a label.

### 2.3 Container and JVM settings that change the metrics

```yaml
# Deployment excerpt (full manifests in File 02)
containers:
  - name: checkout
    image: registry.acme.internal/checkout:4.12.0
    ports:
      - name: http
        containerPort: 8080
      - name: management
        containerPort: 8081
    env:
      - name: JAVA_TOOL_OPTIONS
        value: >-
          -XX:MaxRAMPercentage=70 -XX:+UseZGC -XX:+ExitOnOutOfMemoryError
          -Djdk.tracePinnedThreads=short
      - name: REGION
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['topology.kubernetes.io/region']
    resources:
      requests:
        cpu: "2"
        memory: 2Gi
      limits:
        memory: 2Gi
    readinessProbe:
      httpGet:
        path: /actuator/health/readiness
        port: management
    livenessProbe:
      httpGet:
        path: /actuator/health/liveness
        port: management
```

**Why.**
- **Separate management port.** It keeps scrapes off the application thread pool and lets NetworkPolicy restrict `/actuator`. The port name `management` is what the ServiceMonitor selects (File 02).
- **No CPU limit.** CFS throttling would distort latency histograms (Folder 03 file 03).
- **`MaxRAMPercentage`.** It sizes the heap from the cgroup limit, so `jvm_memory_max_bytes` is meaningful.
- **`ExitOnOutOfMemoryError`.** It turns a zombie JVM into a restart that `kube_pod_container_status_restarts_total` can see.

⚠ **Two settings need checking.**
- **`REGION` from a pod label.** It requires the label to exist on the pod (via an admission policy). Many clusters inject it from node topology instead.
- **`-Djdk.tracePinnedThreads`.** Check it against your JDK, because JEP 491 changed pinning behaviour.

### 2.4 PromQL against these meters

```promql
# RED: request rate, error ratio, p99 (template URIs only, actuator excluded)
sum by (uri) (rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[$__rate_interval]))
sum(rate(http_server_requests_seconds_count{job="checkout", outcome="SERVER_ERROR"}[5m]))
  / sum(rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[5m]))
histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{job="checkout", uri!~"/actuator.*"}[5m])))

# Latency SLI: share of requests under 300 ms, exact because 0.3 is an SLO boundary
sum(rate(http_server_requests_seconds_bucket{job="checkout", le="0.3", uri!~"/actuator.*"}[5m]))
  / sum(rate(http_server_requests_seconds_count{job="checkout", uri!~"/actuator.*"}[5m]))

# Business: orders by outcome, PSP p99 per provider, in-flight PSP calls
sum by (outcome) (rate(checkout_orders_total[5m]))
histogram_quantile(0.99, sum by (le, psp) (rate(checkout_psp_latency_seconds_bucket[5m])))
sum by (pod) (checkout_psp_inflight)

# Guardrail health: how close the uri tag is to max-uri-tags (150 configured)
count by (pod) (count by (pod, uri) (http_server_requests_seconds_count{job="checkout"})) / 150
```

---

## 3. Failure modes and FinOps debugging

### F1. Traces stop after the Boot 4 upgrade

**Symptom.** Tempo receives nothing from upgraded services. Metrics are fine.

**Signature.** The configuration still has `management.otlp.tracing.endpoint`. The app starts without errors. `management.opentelemetry.tracing.export.otlp.endpoint` is unset.

**Root cause.** The key was removed in 4.0.0 (deprecation level `error`, with a replacement) [D]. Boot binds nothing to an unknown key, so no exporter is configured.

**Fix.** Rename the keys. L5 §4 lists six such Boot-3-era mistakes, all caught by metadata.

**Prevention.**
- Add `spring-boot-properties-migrator` during the upgrade.
- Run a CI lint of `application.yaml` against the Boot metadata (L5).
- Add a synthetic check that a trace from each service reaches Tempo.

### F2. `uri` cardinality explosion (or silently missing endpoints)

**Symptom.** Active series jump after a scanner hits the service. Later, new endpoints have no metrics.

**Signature.** Many `uri` values look like raw paths (`/orders/8812731`). Or `uri="UNKNOWN"` dominates. The warning "Reached the maximum number of URI tags" appears.

**Root cause.**
- Non-templated URIs: string-built `RestTemplate` URLs, filters writing their own tags, or unmatched routes.
- Then `max-uri-tags` denies *all* new `uri` values, including legitimate new endpoints.

**Fix.**
- Use URI templates (`uri("/v1/charges/{id}", id)`).
- Map unmatched routes to `UNKNOWN` (Boot does this for 404s).
- Raise `max-uri-tags` only after fixing the source.

**Prevention.** Alert on `count(count by (uri) (...))` approaching the cap (§2.4). Review new meters in code review against the three rules (§0).

### F3. A gauge reads NaN forever

**Symptom.** `checkout_psp_inflight` shows NaN or disappears minutes after startup.

**Signature.** The gauge was registered with a temporary object: `registry.gauge("x", new AtomicInteger())` without keeping the reference.

**Root cause.** Micrometer keeps a weak reference to gauge state, and GC collected it.

**Fix.** Keep the state in a field (L2), or use `Gauge.builder(…).strongReference(true)`.

**Prevention.** Unit-test meters with `SimpleMeterRegistry` after `System.gc()`. Add an ArchUnit or lint rule flagging `registry.gauge(…, new …)`.

### F4. p99 dashboards disagree with the SLO

**Symptom.** The Grafana p99 panel shows 280 ms, but the SLO burn alert fires for latency.

**Signature.**
- The panel averages per-pod client-side `percentiles` gauges, or interpolates between 0.268 and 0.358 because `le="0.3"` is missing.
- The SLO uses the bucket ratio.

**Root cause.** Client-side percentiles don't aggregate. Without an SLO boundary at the threshold, quantiles and ratios are interpolations.

**Fix.**
- Configure SLO boundaries at every alert threshold (L1, L4).
- Drop client-side `percentiles` for fleet views.
- Compute quantiles from summed bucket rates.

**Prevention.** A lint that cross-checks rule-catalog thresholds (File 03) against the configured `slo` boundaries.

### F5. Exemplars missing or dangling

**Symptom.** No diamonds on latency panels, or diamonds that open "trace not found".

**Signature.** One of three causes:
- the scraper negotiates plain text, not OpenMetrics;
- `exemplars.include: all` was tried, which is unsupported with Prometheus;
- tail sampling drops traces that head sampling kept.

**Root cause.** Exemplars depend on the exposition format, the head sampling decision and every downstream sampler.

**Fix.**
- Keep `sampled-traces`.
- Ensure OpenMetrics scraping (`scrape_protocols` in File 02).
- Align tail-sampling policies with exemplar selection (errors and slow requests always kept).

**Prevention.** Track exemplar resolution rate as an SLI (Folder 05 file 02).

### F6. Histogram bill doubles after enabling `percentiles-histogram` globally

**Symptom.** Mimir active series for the tenant double after a "harmless" configuration change.

**Signature.** `management.metrics.distribution.percentiles-histogram.all: true`, or histograms on per-tenant timers. Every timer now exposes 69 buckets.

**Root cause.** The bucket ladder × tag sets × pods (§1.5). Client-request timers with many `uri`/`clientName` values are the worst.

**Fix.**
- Enable histograms per meter prefix that has an SLO.
- Clamp min/max.
- Use SLO-only buckets elsewhere.

**Prevention.** A cardinality budget per service in CI: a Micrometer test that counts `registry.getMeters()` histogram buckets against the budget.

### F7. Client calls invisible in traces and RED

**Symptom.** Spans stop at the service boundary. There are no `http.client.requests` metrics for the PSP.

**Signature.** `RestClient.create()` or `new RestTemplate()` is used instead of the Boot-provided builder.

**Root cause.** Instrumentation is attached to the auto-configured builders, so a hand-built client has no observation registry.

**Fix.** Inject `RestClient.Builder` (L3) or `RestTemplateBuilder`.

**Prevention.** An ArchUnit rule forbids `RestClient.create` in main code. The trace-completeness synthetic catches regressions.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Instrument a new Spring Boot service for production."</b></summary>

**Initial Prompt.** What do you add on day one?

**L5 Textbook Answer.** Actuator plus the Prometheus registry. Add `@Timed` on methods and enable percentiles.

**Why L5 Fails at 3 AM or on the Bill.**
- `@Timed` everywhere and global percentiles multiply series (§1.5, F6).
- Client-side percentiles can't be aggregated (F4).
- There is no tracing or exemplar join.
- Boot 3-style keys silently do nothing on Boot 4 (F1).

**L7 Principal Defense.**
- **Platform conventions:** a separate management port; actuator exposure limited to health, info and prometheus; common tags from config.
- **Guardrails** (L1): cardinality caps, a histogram policy only on SLO-bearing timers with SLO boundaries at alert thresholds, and an actuator predicate.
- **Business meters** with closed tag sets (L2), and Observations for outbound calls (L3).
- **Tracing** at 0.1 head sampling with `sampled-traces` exemplars and the OTLP endpoint under the Boot 4 keys.
- **Logs** in ECS/JSON with trace IDs.
- **CI checks:** a configuration lint against Boot metadata, a series-budget test, and a trace-completeness synthetic.
</details>

<details><summary><b>Q2 · "Timer, DistributionSummary, Counter, Gauge or LongTaskTimer?"</b></summary>

**Initial Prompt.** Model these: PSP latency, basket size, orders, in-flight calls, a 20-minute reconciliation job.

**L5 Textbook Answer.** Use a timer for anything with time, and gauges for the rest.

**Why L5 Fails at 3 AM or on the Bill.**
- A timer on a 20-minute job reports nothing until it finishes, so a hung job is invisible.
- A gauge for orders loses increments between scrapes.
- A gauge on a temporary object goes NaN (F3).

**L7 Principal Defense.**
- **Latency** is a Timer with histogram buckets.
- **Basket size** is a DistributionSummary with SLO buckets (1, 5, 10, 25, 50 items).
- **Orders** are a Counter with method and outcome tags.
- **In-flight** is a Gauge on a strongly held `AtomicInteger`.
- **The job** is a LongTaskTimer, which exposes active count and current duration while running, so "reconciliation running > 30 min" is alertable.

All are shown in L2, with the exposed names verified against the real registry (L5 §2).
</details>

<details><summary><b>Q3 · "How do metrics and traces stay consistent?"</b></summary>

**Initial Prompt.** Teams instrument with both Micrometer timers and OTel spans by hand.

**L5 Textbook Answer.** Use both libraries; they're complementary.

**Why L5 Fails at 3 AM or on the Bill.** Two instrumentation points drift:
- different names and boundaries;
- spans without metrics;
- metrics tagged with high-cardinality IDs copied from span attributes.

Correlation breaks and bills grow.

**L7 Principal Defense.**
- One `Observation` per operation (L3) feeds both the meter handler (low-cardinality key values only) and the tracing handler (all key values).
- The split between low and high cardinality is decided once, in code review.
- Exemplars link the two at query time.
- I'd forbid direct OTel SDK span creation in application code except for library gaps, and use `ObservationConvention`s to keep names uniform across services.
</details>

<details><summary><b>Q4 · "Our Prometheus memory doubled after a Boot upgrade. Why?"</b></summary>

**Initial Prompt.** No code changes except the version bump.

**L5 Textbook Answer.** Boot adds more metrics in new versions.

**Why L5 Fails at 3 AM or on the Bill.** It doesn't quantify or locate. The usual culprits are:
- a histogram default or property now applied to more meters;
- new client or observation meters (`http.client.requests` per `uri`);
- renamed tags causing a series churn spike during the rollout.

**L7 Principal Defense.**
- Diff `/actuator/prometheus` between versions in CI: series count per metric name, buckets per histogram.
- In production, use `topk(20, count by (__name__) ({job="checkout"}))` before and after.
- Then apply the budget: per-prefix histograms, clamped ranges, and `MeterFilter.deny` for unread meters.
- The churn from renamed labels is transient (head series age out). The steady-state growth is what needs fixing.
</details>

<details><summary><b>Q5 · "Head sampling at 10% — what do we lose and how do we mitigate?"</b></summary>

**Initial Prompt.** Finance wants 1%.

**L5 Textbook Answer.** Sampling is fine, because metrics carry the aggregate truth.

**Why L5 Fails at 3 AM or on the Bill.**
- At 1% head sampling, rare errors are almost never traced.
- Exemplars exist only for sampled traces, so drill-down from a latency spike has nothing to click.
- Downstream tail sampling can drop even those (F5).

**L7 Principal Defense.**
- Keep RED in metrics, unsampled.
- Head-sample at a rate that gives enough traces per endpoint per minute (Folder 05: exemplars per bucket per scrape).
- Add tail sampling for errors and slow requests in the collector tier (Folder 06), with policies aligned to exemplar selection.
- Budget by spans/s, not by percentage.
- Large-volume, low-value endpoints (health, static) are excluded by predicate before sampling even matters.
</details>

<details><summary><b>Q6 · "Virtual threads: what changes for observability?"</b></summary>

**Initial Prompt.** We enabled `spring.threads.virtual.enabled`.

**L5 Textbook Answer.** Nothing; Micrometer still works.

**Why L5 Fails at 3 AM or on the Bill.**
- Thread-pool saturation metrics vanish: no pool to measure.
- Pinning on JDK 21 (`synchronized` around blocking I/O) silently serialises work on few carriers.
- Connection pools become the real limiter: HikariCP pending requests rise (Folder 03).

**L7 Principal Defense.**
- **Concurrency.** Measure it explicitly (in-flight gauges) and watch the downstream limiters: DB pool pending, HTTP client pool.
- **Pinning.** Run JDK ≥ 24 for JEP 491, and capture pinning events (JFR) in pre-production.
- **Latency.** Rely on latency histograms rather than thread metrics to detect saturation, because queueing shows up as latency.
- **Utilisation.** CPU utilisation per pod becomes the primary utilisation signal again.
</details>

<details><summary><b>Q7 · "How do you test instrumentation?"</b></summary>

**Initial Prompt.** Metrics broke silently twice last quarter.

**L5 Textbook Answer.** Check dashboards after deploy.

**Why L5 Fails at 3 AM or on the Bill.** Dashboards show breakage after customers do. Names, tags and buckets are an API contract, and they need tests like any API.

**L7 Principal Defense.**
- **Unit tests.** Use `SimpleMeterRegistry` with assertions on names, tags and bucket boundaries (L5's approach against the real registry is the model).
- **Contract test.** Snapshot `/actuator/prometheus` names and label keys and diff them in PRs.
- **Configuration lint.** Check against Boot metadata (L5 §4).
- **Rule tests.** Unit-test recording and alerting rules against those metric names (File 03).
- **Production synthetics.** Run a trace-completeness probe.

Breaking a metric then fails CI, not the on-call.
</details>

<details><summary><b>Q8 · "Should services push OTLP metrics instead of being scraped?"</b></summary>

**Initial Prompt.** We're standardising on OpenTelemetry.

**L5 Textbook Answer.** Yes, OTLP everywhere is simpler.

**Why L5 Fails at 3 AM or on the Bill.** Push loses:
- the scrape-derived `up` signal and target metadata (relabeling, ServiceMonitor ownership);
- staleness handling.

Push also brings delta vs cumulative temporality decisions and per-pod `service.instance.id` cardinality. Exemplars and native-histogram support differ by path ⚠.

**L7 Principal Defense.**
- Keep Prometheus scraping for Kubernetes services: `up`, discovery-driven labels and staleness are free.
- Use OTLP for traces and logs, plus metrics for short-lived or serverless workloads that can't be scraped.
- If pushing, set `management.otlp.metrics.export.*` deliberately: step, temporality, and `histogram-flavor` (explicit or base-2 exponential [D]).
- Push to the collector tier, not directly to the backend, and reconcile counts with the scraped path during migration.
</details>

---

## 5. Invariants checklist

- [ ] Every tag value comes from a closed set; custom meters with potentially open tags have `maximumAllowableTags` guards.
- [ ] Percentile histograms are enabled only per SLO-bearing prefix, clamped (min/max), with SLO boundaries at every alert threshold.
- [ ] No client-side `percentiles` in fleet dashboards or alerts.
- [ ] Gauges hold strong references; dynamic tags use `MeterProvider`.
- [ ] Outbound HTTP uses Boot-provided builders; one `Observation` per operation with an explicit low- vs high-cardinality split.
- [ ] Actuator traffic is excluded by `ObservationPredicate`; management runs on its own port.
- [ ] Boot 4 keys are used (`management.opentelemetry.tracing.export.otlp.*`); the configuration is linted against metadata in CI.
- [ ] `exemplars.include: sampled-traces`; scraping negotiates OpenMetrics; tail sampling keeps what exemplars point to.
- [ ] Logs are structured (ECS/JSON) with trace IDs; trace IDs never become Loki labels.

---

## 6. References

- Spring Boot 4.1 reference, metrics: <https://docs.spring.io/spring-boot/reference/actuator/metrics.html>
- Spring Boot 4.1 reference, tracing: <https://docs.spring.io/spring-boot/reference/actuator/tracing.html>
- Spring Boot 4.1 reference, observability: <https://docs.spring.io/spring-boot/reference/actuator/observability.html>
- Spring Boot structured logging: <https://docs.spring.io/spring-boot/reference/features/logging.html>
- Micrometer concepts (meters, naming, histograms): <https://docs.micrometer.io/micrometer/reference/concepts.html>
- Micrometer Observation API: <https://docs.micrometer.io/micrometer/reference/observation.html>
- `PercentileHistogramBuckets` source (v1.17.2): <https://github.com/micrometer-metrics/micrometer/blob/v1.17.2/micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/PercentileHistogramBuckets.java>
- `PrometheusNamingConvention` (v1.17.2): <https://github.com/micrometer-metrics/micrometer/blob/v1.17.2/implementations/micrometer-registry-prometheus/src/main/java/io/micrometer/prometheusmetrics/PrometheusNamingConvention.java>
- Prometheus `client_java` naming (v1.7.0): <https://github.com/prometheus/client_java/blob/v1.7.0/prometheus-metrics-model/src/main/java/io/prometheus/metrics/model/snapshots/PrometheusNaming.java>
- Spring Boot 4.1.2 BOM: <https://repo1.maven.org/maven2/org/springframework/boot/spring-boot-dependencies/4.1.2/spring-boot-dependencies-4.1.2.pom>
- JEP 491, synchronize virtual threads without pinning: <https://openjdk.org/jeps/491>
