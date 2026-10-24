# 8.2 · Observability — OpenTelemetry Context Propagation, Micrometer Histograms & Percentiles, Structured Logging with MDC

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** OpenTelemetry Java docs (context propagation, `Context.taskWrapping`, span links); W3C Trace Context (Level 2 `random` flag) and W3C Baggage; OpenTelemetry semantic conventions (messaging); Micrometer 1.17 docs (Timers, histograms, percentiles, SLOs, `MeterFilter`); Prometheus docs ("Histograms and summaries"); Spring Boot 4.1 reference (tracing, structured logging) and its configuration metadata.
> **Verified stack:** OpenTelemetry SDK **1.62.0** (in-memory span exporter), Micrometer **1.17.2** + Prometheus registry (prometheus-metrics 1.7.0), Spring Boot **4.1.2** with `spring-boot-starter-opentelemetry` (Micrometer Tracing 1.7.2 OTel bridge), Logback 1.5, JDK 25. All IDs, headers, metric lines and JSON keys below were captured from runs.

---

## 1. Three signals, one correlation key 🔥

```
 trace  (what happened, where, how long: spans across services)  ──┐
 metrics (how much, how often, how slow: aggregated time series)  ─┼── correlated by trace-id (logs, exemplars)
 logs   (what exactly happened: structured events)                ─┘     and by resource attributes (service, version, pod)
```

* **Traces** answer "why was *this* request slow?". **Metrics** answer "how slow are requests *in general*, and is that getting worse?". **Logs** carry details. You need all three, linked by the **trace-id** (in logs) and **exemplars** (trace-ids attached to histogram buckets).
* Context propagation is the hard part: in-process across **threads**, and across process boundaries via **headers** (HTTP, Kafka record headers, AMQP properties).

---

## 2. Context propagation in-process and across Kafka 🔥

### 2.1 Runnable: executors, virtual threads, a producer/consumer hop, baggage, and span links

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.otel;

import io.opentelemetry.api.baggage.Baggage;
import io.opentelemetry.api.baggage.propagation.W3CBaggagePropagator;
import io.opentelemetry.api.trace.*;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.opentelemetry.context.propagation.*;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.testing.exporter.InMemorySpanExporter;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.data.SpanData;
import io.opentelemetry.sdk.trace.export.SimpleSpanProcessor;
import java.util.*;
import java.util.concurrent.*;

public class ContextPropagation {
    public static void main(String[] args) throws Exception {
        InMemorySpanExporter exporter = InMemorySpanExporter.create();
        OpenTelemetrySdk otel = OpenTelemetrySdk.builder()
            .setTracerProvider(SdkTracerProvider.builder().addSpanProcessor(SimpleSpanProcessor.create(exporter)).build())
            .setPropagators(ContextPropagators.create(TextMapPropagator.composite(
                W3CTraceContextPropagator.getInstance(), W3CBaggagePropagator.getInstance())))
            .build();
        Tracer tracer = otel.getTracer("demo");
        ExecutorService plain = Executors.newFixedThreadPool(2);
        ExecutorService wrapped = Context.taskWrapping(Executors.newFixedThreadPool(2));       // propagates Context.current()
        Map<String, String> kafkaHeaders = new HashMap<>();

        Span request = tracer.spanBuilder("GET /orders/{id}").setSpanKind(SpanKind.SERVER).startSpan();
        try (Scope s = request.makeCurrent();
             Scope b = Baggage.current().toBuilder().put("tenant", "acme").build().makeCurrent()) {
            plain.submit(() -> tracer.spanBuilder("async: plain executor").startSpan().end()).get();
            wrapped.submit(() -> tracer.spanBuilder("async: Context.taskWrapping").startSpan().end()).get();
            try (var vts = Executors.newVirtualThreadPerTaskExecutor()) {
                vts.submit(() -> tracer.spanBuilder("async: virtual thread, no wrapping").startSpan().end()).get();
            }
            Span send = tracer.spanBuilder("orders publish").setSpanKind(SpanKind.PRODUCER).startSpan();
            try (Scope ss = send.makeCurrent()) {
                otel.getPropagators().getTextMapPropagator().inject(Context.current(), kafkaHeaders, Map::put);   // into record headers
            } finally { send.end(); }
        } finally {
            request.end();
        }

        // … later, in another service: the consumer extracts the context from the record headers
        TextMapGetter<Map<String, String>> getter = new TextMapGetter<>() {
            public Iterable<String> keys(Map<String, String> c) { return c.keySet(); }
            public String get(Map<String, String> c, String key) { return c.get(key); }
        };
        Context remote = otel.getPropagators().getTextMapPropagator().extract(Context.root(), kafkaHeaders, getter);
        Span consume = tracer.spanBuilder("orders process").setSpanKind(SpanKind.CONSUMER).setParent(remote).startSpan();
        String tenant;
        try (Scope s = consume.makeCurrent(); Scope b = Baggage.fromContext(remote).makeCurrent()) {
            tenant = Baggage.current().getEntryValue("tenant");
        } finally { consume.end(); }
        // a batch consumer can't have several parents: it LINKS the producer contexts instead
        Span batch = tracer.spanBuilder("orders batch (3 records)").setSpanKind(SpanKind.CONSUMER).setNoParent()
            .addLink(Span.fromContext(remote).getSpanContext()).addLink(Span.fromContext(remote).getSpanContext())
            .addLink(Span.fromContext(remote).getSpanContext()).startSpan();
        batch.end();
        plain.shutdown(); wrapped.shutdown();

        String traceparent = kafkaHeaders.get("traceparent");
        System.out.println("headers injected: " + new TreeSet<>(kafkaHeaders.keySet()) + ", baggage=" + kafkaHeaders.get("baggage"));
        System.out.println("traceparent format: " + traceparent.replaceAll("^(..)-([0-9a-f]{32})-([0-9a-f]{16})-(..)$", "$1-<32 hex trace-id>-<16 hex parent-span-id>-$4"));
        String trace = request.getSpanContext().getTraceId();
        for (SpanData d : exporter.getFinishedSpanItems())
            System.out.printf("%-38s kind=%-8s same trace as request=%-5s parent=%s links=%d%n", d.getName(), d.getKind(),
                d.getTraceId().equals(trace), parentName(d, exporter.getFinishedSpanItems()), d.getLinks().size());
        System.out.println("baggage seen by the consumer: tenant=" + tenant);
    }

    static String parentName(SpanData d, List<SpanData> all) {
        if (!d.getParentSpanContext().isValid()) return "(root)";
        return all.stream().filter(p -> p.getSpanId().equals(d.getParentSpanId())).map(SpanData::getName).findFirst().orElse("?");
    }
}
```

Output (verified):

```
headers injected: [baggage, traceparent], baggage=tenant=acme
traceparent format: 00-<32 hex trace-id>-<16 hex parent-span-id>-03
async: plain executor                  kind=INTERNAL same trace as request=false parent=(root) links=0
async: Context.taskWrapping            kind=INTERNAL same trace as request=true  parent=GET /orders/{id} links=0
async: virtual thread, no wrapping     kind=INTERNAL same trace as request=false parent=(root) links=0
orders publish                         kind=PRODUCER same trace as request=true  parent=GET /orders/{id} links=0
GET /orders/{id}                       kind=SERVER   same trace as request=true  parent=(root) links=0
orders process                         kind=CONSUMER same trace as request=true  parent=orders publish links=0
orders batch (3 records)               kind=CONSUMER same trace as request=false parent=(root) links=3
baggage seen by the consumer: tenant=acme
```

* **Context lives in a `ThreadLocal`.** A task submitted to a plain executor, or to a **virtual thread**, started a **new trace** (root span, not part of the request's trace). `Context.taskWrapping(executor)` captured the context at submit time and restored it in the worker. Spring and Micrometer offer the same for `@Async`, `TaskDecorator`, `ContextExecutorService` and Reactor ([6.2 §3.1](../06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md#31-runnable-demand-overflow-time-based-sources-blocking-detection-context-propagation)). The OTel Java agent instruments common executors automatically. Hand-made thread hand-offs are where traces break.
* **Across Kafka:** the producer **injected** `traceparent` (and `baggage`) into the record headers, and the consumer **extracted** them. Its span joined the same trace, with the producer span as its parent.
  * **`traceparent`** = `version-traceid(32 hex)-parentid(16 hex)-flags`.
  * **Flags `03`** = sampled (`01`) + the W3C Trace Context Level 2 *random* bit (`02`, the trace-id is random).
  * **Baggage** carried `tenant=acme` to the consumer. Baggage propagates to **every** downstream service and is visible in headers, so never put secrets or personal data in it.
* **Batch consumers use links, not parents:** a span can have one parent, but a batch of 3 records came from 3 producer contexts, so the batch span linked them (`links=3`). The OTel messaging conventions recommend links for batch processing.

---

## 3. Latency metrics that aggregate correctly 🔥

| Micrometer option | What is exported (verified with the Prometheus registry) | Aggregatable across instances? |
|---|---|---|
| `publishPercentiles(0.5, 0.99)` only | Prometheus **summary**: `…{quantile="0.99"}` computed **inside each JVM** | **No**: you can't combine percentiles |
| `publishPercentileHistogram()` | Prometheus **histogram**: `_bucket{le=…}` cumulative counts, `_count`, `_sum` | **Yes**: sum the buckets, then `histogram_quantile` |
| both | Only the histogram (the percentile gauges were **not** exported alongside) | Yes |
| `serviceLevelObjectives(100ms)` | An exact bucket boundary at the SLO (`le="0.1"`) | Yes: the "share of requests under 100 ms" is exact |
| `minimumExpectedValue` / `maximumExpectedValue` | Bounds the bucket range, so fewer series | — |

### 3.1 Runnable: averaging p99s lies; merged histograms don't

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.metrics;

import io.micrometer.core.instrument.*;
import io.micrometer.core.instrument.config.MeterFilter;
import io.micrometer.core.instrument.distribution.HistogramSnapshot;
import io.micrometer.core.instrument.distribution.ValueAtPercentile;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import io.micrometer.prometheusmetrics.PrometheusConfig;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

public class LatencyMetrics {
    public static void main(String[] args) {
        // Two instances behind a load balancer: A is healthy, B has a slow dependency on 10% of its requests.
        PrometheusMeterRegistry a = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT), b = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
        Timer ta = timer(a), tb = timer(b);
        Random rnd = new Random(42);
        List<Long> all = new ArrayList<>();
        for (int i = 0; i < 10_000; i++) record(ta, 20 + rnd.nextInt(30), all);                       // 20–49 ms
        for (int i = 0; i < 10_000; i++) record(tb, i % 10 == 0 ? 900 + rnd.nextInt(200) : 20 + rnd.nextInt(30), all);

        double p99a = p99(ta), p99b = p99(tb);
        Collections.sort(all);
        System.out.printf("client-side p99: A=%.0f ms, B=%.0f ms → average of p99s = %.0f ms%n", p99a, p99b, (p99a + p99b) / 2);
        System.out.printf("true p99 of all 20,000 requests = %d ms%n", all.get((int) Math.ceil(0.99 * all.size()) - 1));
        System.out.printf("p99 from MERGED histogram buckets (what Prometheus histogram_quantile does) ≈ %.0f ms%n", mergedQuantile(ta, tb, 0.99));
        System.out.println("SLO check: share of requests ≤ 100 ms (from the 100 ms SLO bucket) = "
            + String.format("%.1f%%", 100.0 * (bucket(ta, 100) + bucket(tb, 100)) / (ta.count() + tb.count())));

        System.out.println("Prometheus exposition (instance A, excerpt):");
        a.scrape().lines().filter(l -> l.startsWith("http_server_requests") && (!l.contains("_bucket") || l.contains("le=\"0.1\"")))
            .forEach(l -> System.out.println("  " + l));
        PrometheusMeterRegistry c = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
        Timer onlyPercentiles = Timer.builder("http.server.requests").tag("uri", "/orders/{id}").publishPercentiles(0.5, 0.99).register(c);
        for (int i = 0; i < 1000; i++) onlyPercentiles.record(Duration.ofMillis(20 + i % 30));
        System.out.println("percentiles only (no histogram), exposition:");
        c.scrape().lines().filter(l -> l.startsWith("http_server_requests") || l.startsWith("# TYPE http_server_requests_seconds "))
            .forEach(l -> System.out.println("  " + l));

        // cardinality: a tag with unbounded values creates one time series per value
        SimpleMeterRegistry reg = new SimpleMeterRegistry();
        reg.config().meterFilter(MeterFilter.maximumAllowableTags("orders", "user", 100, MeterFilter.deny()));
        for (int u = 0; u < 5_000; u++) reg.counter("orders", "user", "u" + u).increment();
        System.out.println("counters registered with a per-user tag (capped at 100): " + reg.find("orders").counters().size());
    }

    static Timer timer(MeterRegistry r) {
        return Timer.builder("http.server.requests").tag("uri", "/orders/{id}")
            .publishPercentiles(0.5, 0.99)                    // computed in the app: NOT aggregatable across instances
            .publishPercentileHistogram()                     // buckets: aggregatable (sum the buckets, then compute the quantile)
            .serviceLevelObjectives(Duration.ofMillis(100))   // an exact bucket boundary at the SLO
            .minimumExpectedValue(Duration.ofMillis(1)).maximumExpectedValue(Duration.ofSeconds(5))
            .register(r);
    }
    static void record(Timer t, long ms, List<Long> all) { t.record(Duration.ofMillis(ms)); all.add(ms); }
    static double p99(Timer t) {
        for (ValueAtPercentile v : t.takeSnapshot().percentileValues()) if (v.percentile() == 0.99) return v.value(java.util.concurrent.TimeUnit.MILLISECONDS);
        throw new IllegalStateException();
    }
    static double bucket(Timer t, double ms) {
        for (var c : t.takeSnapshot().histogramCounts()) if (c.bucket(java.util.concurrent.TimeUnit.MILLISECONDS) == ms) return c.count();
        throw new IllegalStateException();
    }
    static double mergedQuantile(Timer x, Timer y, double q) {
        HistogramSnapshot sx = x.takeSnapshot(), sy = y.takeSnapshot();
        double total = sx.count() + sy.count(), target = q * total, prevBound = 0, prevCount = 0;
        for (int i = 0; i < sx.histogramCounts().length; i++) {
            double bound = sx.histogramCounts()[i].bucket(java.util.concurrent.TimeUnit.MILLISECONDS);
            double cum = sx.histogramCounts()[i].count() + sy.histogramCounts()[i].count();     // cumulative counts, summed
            if (cum >= target) return prevBound + (bound - prevBound) * (target - prevCount) / (cum - prevCount);   // linear, like histogram_quantile
            prevBound = bound; prevCount = cum;
        }
        return Double.NaN;
    }
}
```

Output (verified):

```
client-side p99: A=49 ms, B=1140 ms → average of p99s = 595 ms
true p99 of all 20,000 requests = 1057 ms
p99 from MERGED histogram buckets (what Prometheus histogram_quantile does) ≈ 1058 ms
SLO check: share of requests ≤ 100 ms (from the 100 ms SLO bucket) = 95.0%
Prometheus exposition (instance A, excerpt):
  http_server_requests_seconds_bucket{uri="/orders/{id}",le="0.1"} 10000
  http_server_requests_seconds_count{uri="/orders/{id}"} 10000
  http_server_requests_seconds_sum{uri="/orders/{id}"} 344.008
  http_server_requests_seconds_max{uri="/orders/{id}"} 0.049
percentiles only (no histogram), exposition:
  # TYPE http_server_requests_seconds summary
  http_server_requests_seconds{uri="/orders/{id}",quantile="0.5"} 0.034603008
  http_server_requests_seconds{uri="/orders/{id}",quantile="0.99"} 0.049283072
  http_server_requests_seconds_count{uri="/orders/{id}"} 1000
  http_server_requests_seconds_sum{uri="/orders/{id}"} 34.4
  http_server_requests_seconds_max{uri="/orders/{id}"} 0.049
counters registered with a per-user tag (capped at 100): 100
```

* **The averaged p99 was 595 ms; the true p99 of all requests was 1,057 ms.** Instance B's slow tail is diluted by averaging, which is mathematically meaningless for percentiles. Summing the **histogram buckets** first and interpolating (as Prometheus `histogram_quantile(0.99, sum by (le) (rate(…_bucket[5m])))` does) gave ≈1,058 ms, essentially the truth.
* **The SLO bucket gives an exact compliance number:** 95.0% of requests ≤ 100 ms. Burn-rate alerts are built on such ratios.
* **Cardinality is the cost driver.** A `user` tag with 5,000 values would create 5,000 series per meter, multiplied by every histogram bucket. `MeterFilter.maximumAllowableTags` capped it at 100 here. Tag by **bounded** dimensions (route template `/orders/{id}`, status class, region), never by IDs, raw URLs or exception messages.
* Spring Boot enables histograms per meter with `management.metrics.distribution.percentiles-histogram.http.server.requests=true` and SLO buckets with `management.metrics.distribution.slo.http.server.requests=100ms,500ms`.

---

## 4. Structured JSON logs with MDC and trace correlation 🔥

### 4.1 Runnable: Spring Boot 4 ECS logging, MDC, SLF4J key-values, and an incoming `traceparent`

<!-- run: javac cp=@p8 timeout=200 -->
```java
package demo.logging;

import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.bind.annotation.*;

public class StructuredLogging {
    @RestController
    public static class Orders {
        static final Logger log = LoggerFactory.getLogger(Orders.class);
        @GetMapping("/orders/{id}")
        public String get(@PathVariable String id) {
            MDC.put("orderId", id);                                            // request-scoped context for every log line
            try {
                log.atInfo().addKeyValue("amountCents", 4200).addKeyValue("currency", "EUR").log("order loaded");
                return "ok";
            } finally {
                MDC.remove("orderId");                                         // thread pools reuse threads: always clean up
            }
        }
    }
    @SpringBootConfiguration @EnableAutoConfiguration @Import(Orders.class)
    static class App {
        @Bean SecurityFilterChain open(HttpSecurity http) throws Exception {
            return http.authorizeHttpRequests(a -> a.anyRequest().permitAll()).build();
        }
    }

    public static void main(String[] args) throws Exception {
        PrintStream original = System.out;
        ByteArrayOutputStream captured = new ByteArrayOutputStream();
        System.setOut(new PrintStream(captured, true, StandardCharsets.UTF_8));  // the console appender writes here
        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setDefaultProperties(Map.of("server.port", "0",
            "logging.structured.format.console", "ecs",                        // Elastic Common Schema JSON, one object per line
            "logging.structured.ecs.service.name", "orders-service",
            "management.tracing.export.otlp.enabled", "false"));               // no collector in this demo
        String traceId = "4bf92f3577b34da6a3ce929d0e0e4736";
        try (var ctx = sa.run(); HttpClient http = HttpClient.newHttpClient()) {
            int port = ((WebServerApplicationContext) ctx).getWebServer().getPort();
            http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/orders/A-1001"))
                .header("traceparent", "00-" + traceId + "-00f067aa0ba902b7-01").build(), HttpResponse.BodyHandlers.ofString());
        }
        System.setOut(original);

        var json = new tools.jackson.databind.ObjectMapper();
        String line = captured.toString(StandardCharsets.UTF_8).lines().filter(l -> l.contains("order loaded")).findFirst().orElseThrow();
        var node = json.readTree(line);
        List<String> keys = new ArrayList<>(node.propertyNames());
        Collections.sort(keys);
        System.out.println("ECS keys: " + keys);
        System.out.println("message=" + node.get("message").asString() + ", log.level=" + node.get("log").get("level").asString()
            + ", service.name=" + node.get("service").get("name").asString());
        System.out.println("MDC orderId=" + node.get("orderId") + ", key-values amountCents=" + node.get("amountCents") + " currency=" + node.get("currency"));
        System.out.println("traceId (from MDC) equals the incoming traceparent's trace-id: " + traceId.equals(node.path("traceId").asString())
            + ", spanId is a new 16-hex span: " + node.path("spanId").asString().matches("[0-9a-f]{16}")
            + ", ECS trace.id present: " + !node.path("trace").isMissingNode());
    }
}
```

Output (verified):

```
ECS keys: [@timestamp, amountCents, currency, ecs, log, message, orderId, process, service, spanId, traceId]
message=order loaded, log.level=INFO, service.name=orders-service
MDC orderId="A-1001", key-values amountCents=4200 currency="EUR"
traceId (from MDC) equals the incoming traceparent's trace-id: true, spanId is a new 16-hex span: true, ECS trace.id present: false
```

* **`logging.structured.format.console=ecs`** (also `logstash`, `gelf`, or a custom `StructuredLogFormatter`) made Boot write one JSON object per line: `@timestamp`, `log.level`/`log.logger`, `process.pid`/`thread`, `service.name`, `message`. No logback XML needed.
* **MDC entries and SLF4J 2 fluent key-values became top-level fields** (`orderId`, `amountCents`, `currency`). Remove MDC entries in `finally`: pooled threads otherwise leak context into the next request.
* **Trace correlation came for free:** Micrometer Tracing put the incoming request's **trace-id** into the MDC as `traceId`, and every log line of that request carried it. Note the key names: `traceId`/`spanId` (MDC names), **not** ECS `trace.id`/`span.id`. Map them with `logging.structured.json.rename` if your log pipeline expects ECS names.
* **Boot tracing defaults (verified metadata):**
  * `management.tracing.sampling.probability = 0.1`: **only 10% of new traces are sampled**. Incoming sampled `traceparent`s are honoured (parent-based sampling).
  * Propagation **consumes** W3C, B3 and B3-multi, and **produces** W3C.
  * OTLP export is on by default. This demo turned it off because no collector was running.

---

## 5. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| Traces end at an async boundary; orphan root spans | Context not propagated across executors, virtual threads or reactive hops | Root spans with no parent named like inner work | `Context.taskWrapping`, `TaskDecorator`/`ContextExecutorService`, the OTel agent, Reactor context-propagation |
| Consumer spans not connected to producers | Headers not injected or extracted; a broker proxy strips headers | Kafka record headers lack `traceparent` | Instrumented clients (OTel Kafka instrumentation), or explicit inject/extract |
| Dashboards show healthy p99 during an incident | Averaging per-instance percentiles | Compare with `histogram_quantile` over summed buckets | Histograms + server-side quantiles; SLO buckets |
| Prometheus memory and bills explode | High-cardinality tags (IDs, raw paths) | `count by (__name__)` top series | Bounded tags; `MeterFilter` caps; route templates |
| Logs can't be joined with traces | No trace-id in logs; different key names across services | Search for the trace-id fails | Tracing → MDC correlation; consistent key names (`rename`) |
| Only some requests have traces | Default 10% sampling | `sampling.probability` | Tail-based sampling in the collector; 100% for low-volume services |
| Wrong request context in logs | MDC not cleared on pooled threads | Log lines with another request's `orderId` | `try/finally` cleanup; scoped values or context propagation libraries |
| Secrets in downstream headers | Data placed in baggage | Inspect outbound headers | Never put secrets or personal data in baggage; strip at trust boundaries |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Why can't you average p99 latencies across instances, and what do you do instead?</b></summary>

Percentiles aren't linear: averaging per-instance p99s ignores how many requests each instance served and where its tail lies (measured: averaged 595 ms vs a true 1,057 ms). Export **histograms** (bucket counts), sum the buckets across instances, then compute the quantile (`histogram_quantile`), which gave ≈1,058 ms. Add SLO bucket boundaries for exact compliance ratios.
</details>

<details><summary><b>Q2. 🔥 How does trace context travel from an HTTP request to a Kafka consumer in another service?</b></summary>

The server span is current in a `ThreadLocal` context. The producer creates a PRODUCER span and injects W3C `traceparent` (+ `baggage`) into the record headers. The consumer extracts the context from the headers and starts a CONSUMER span with that context as parent (same trace-id). For batch consumption it links the producer contexts instead (verified: `links=3`). Async hops inside each service need explicit context propagation (`Context.taskWrapping`, etc.).
</details>

<details><summary><b>Q3. ⚡ What's in a `traceparent` header, and what does flag `03` mean?</b></summary>

`00-<32-hex trace-id>-<16-hex parent span-id>-<flags>`. The flags byte holds `sampled` (`01`), and since W3C Trace Context Level 2, `random` (`02`: the trace-id was randomly generated). `03` = both. The OTel Java SDK 1.62 emitted `03` (verified).
</details>

<details><summary><b>Q4. ⚡ What should and shouldn't be a metric tag?</b></summary>

Use bounded, low-cardinality dimensions you aggregate or filter by: route template, method, status class, outcome, region, instance. Never use user IDs, order IDs, raw URLs, exception messages or timestamps: each distinct value creates new time series (multiplied by histogram buckets), and costs explode. Enforce limits with `MeterFilter.maximumAllowableTags`.
</details>

<details><summary><b>Q5. 🧊 Your logs show the wrong `orderId` for some requests. Why?</b></summary>

MDC is thread-local, and servlet or executor threads are pooled. A value put into the MDC and not removed leaks into the next task on that thread. Always clear in `finally`, or use scoped mechanisms (Micrometer context propagation, `ScopedValue`), and propagate the MDC deliberately to async workers.
</details>
