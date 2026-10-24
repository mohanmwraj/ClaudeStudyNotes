# 8.7 · Pillar 8 — Interview & Certification Question Bank (Observability, Security, Testing)

> **Use:** A = flashcards, B = senior and architect scenarios, C = code questions with verified answers, D = study map.
> **Exam scope:** profiling, tracing, OAuth2 and JMH are outside the Oracle Java SE exams (1Z0-830). The **Spring Professional** exam (2V0-72.22) covers Spring testing (`@SpringBootTest`, slices, mock beans), Spring Security basics (filter chain, password encoding, method security) and Actuator/metrics. Its objectives predate Boot 4, so expect `@MockBean` on the exam and know that Boot 4 replaced it with `@MockitoBean`. All questions are original. **Every program in C was run** (JUnit 6.0.3, OpenTelemetry SDK 1.62.0, Spring Security 7.1.2, Mockito 5.23.0, JDK 25).

---

## A. Rapid-fire

<details><summary><b>A1–A30</b></summary>

**Profiling and dumps ([8.1](01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md))**

1. **JFR overhead with `default` / `profile` settings?** About 1% / 2%: production-safe, so keep a ring-buffer recording always on.
2. **Dump the always-on recording?** `jcmd <pid> JFR.dump name=… filename=…`; analyze with `jfr view hot-methods|contention-by-site|allocation-by-site`.
3. **Consume JFR events live in-process?** `RecordingStream` (JEP 349).
4. **Are `synchronized` monitors fair?** No. They barge: the releasing thread can re-acquire immediately (verified in 8.1).
5. **Does `synchronized` pin virtual threads on JDK 25?** No, not since JDK 24 (JEP 491). `jdk.VirtualThreadPinned` stays for native frames.
6. **Thread dump that includes virtual threads?** `jcmd <pid> Thread.dump_to_file -format=json <file>`. `ThreadMXBean` and `jstack`-style dumps omit them.
7. **`RUNNABLE` in `socketRead0`: busy CPU?** No. It's blocked in native I/O; the JVM reports it as `RUNNABLE`.
8. **Why async-profiler over a JVMTI sampler?** No safepoint bias: it samples asynchronously (`perf_events` or timer signals) and walks Java stacks without waiting for a safepoint.

**Observability ([8.2](02-Observability-OpenTelemetry-Micrometer-Logging.md))**

9. **Average per-instance p99s?** Never. Sum histogram buckets, then `histogram_quantile`.
10. **`publishPercentiles` exports what in Prometheus?** A summary computed in each JVM, so it can't be aggregated.
11. **`traceparent` layout?** `version-traceid(32 hex)-spanid(16 hex)-flags`. `01` = sampled, `02` = random trace-id.
12. **Boot's default trace sampling probability?** 0.1.
13. **Batch consumer, records from 3 traces: parent or links?** Links.
14. **What must never go in baggage?** Secrets and personal data: baggage propagates to every downstream service.
15. **Metric tag rule of thumb?** Bounded values only (route template, status class, region), never IDs or raw URLs.
16. **Boot's JSON logs in one property?** `logging.structured.format.console=ecs` (or `logstash`, `gelf`).

**Security ([8.3](03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md))**

17. **401 vs 403?** 401 = not authenticated (with a `WWW-Authenticate` challenge); 403 = authenticated but not allowed.
18. **JWT claims a resource server must check?** Signature, `iss`, `aud`, `exp`/`nbf` (60 s default skew).
19. **Scope `orders.read` becomes which authority?** `SCOPE_orders.read`.
20. **RFC 9728 in Spring Security 7.1?** Protected-resource metadata at `/.well-known/oauth-protected-resource`, advertised as `resource_metadata` in challenges.
21. **Does mTLS authorize?** No. It authenticates key holders; map identities and authorize per operation.
22. **OWASP Top 10:2025 #1 and the two new categories?** A01 Broken Access Control (now including SSRF); A03 Software Supply Chain Failures and A10 Mishandling of Exceptional Conditions.
23. **Default `PasswordEncoder` from `PasswordEncoderFactories`?** A `DelegatingPasswordEncoder` producing `{bcrypt}` hashes (C3).

**Testing and benchmarking ([8.4](04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md), [8.5](05-JMH-Benchmarking.md))**

24. **JUnit 6 Java baseline?** Java 17. Vintage deprecated, `junit-platform-runner` removed, Surefire ≥ 3.0.
25. **What replaced `@MockBean` in Boot 4?** `@MockitoBean` / `@MockitoSpyBean` from Spring Framework (`spring-test`).
26. **Default Spring test-context cache size and pause mode?** 32 contexts; `ON_CONTEXT_SWITCH` (Spring 7).
27. **Testcontainers 2 Postgres class?** `org.testcontainers.postgresql.PostgreSQLContainer`, with no generic and an explicit image.
28. **What does `@ServiceConnection` create?** Boot `ConnectionDetails` beans (e.g. JDBC URL, user, password) from the running container.
29. **What happens if JMH's annotation processor doesn't run on JDK 23+?** `Unable to find the resource: /META-INF/BenchmarkList`; compile with `-proc:full`.
30. **JMH's most stable regression metric?** `gc.alloc.rate.norm` (B/op) from `-prof gc`.

</details>

---

## B. Senior scenarios

<details><summary><b>B1. 🔥 Design observability for 40 Spring Boot microservices on Kubernetes.</b></summary>

* **Instrumentation:** the OTel Java agent or Micrometer Tracing with the OTLP exporter; W3C propagation everywhere; Kafka header inject/extract; links for batches.
* **Pipeline:** OTel Collector as a gateway with tail-based sampling (keep errors and slow traces; sample the rest), attribute scrubbing, and routing to the trace, metric and log back ends.
* **Metrics:** histograms with SLO buckets for `http.server.requests` and client calls; a `MeterFilter` cardinality cap; exemplars linking buckets to traces; RED dashboards per service and burn-rate alerts per SLO.
* **Logs:** JSON (ECS) with trace-id and span-id, consistent key names, MDC hygiene, personal-data redaction, retention by level.
* **JVM:** always-on JFR ring buffer, with a runbook to dump it plus 3 thread dumps before any restart; async-profiler on demand; continuous profiling if the budget allows.
* **Governance:** naming conventions, a shared starter that enforces all of the above, and CI checks (orphan-span ratio in staging, series-count budget per service).
</details>

<details><summary><b>B2. 🔥 p99 latency of `POST /orders` tripled after a release. CPU is flat. Walk through the investigation.</b></summary>

1. Confirm with histogram-based p99 (not averaged), split by instance, route and status. Did all instances regress, or one? (Pillar 8.2.)
2. Pull slow traces (exemplars, or a trace search on duration). Which span grew: the database, a downstream HTTP call, or a gap with no spans (time spent in the JVM)?
3. Gap in the JVM, CPU flat → a waiting problem. Dump the JFR ring buffer: `contention-by-site`, `jdk.ThreadPark`, socket-read events. Take 3 thread dumps (JSON format for virtual threads). Look for a pool wait (Hikari `getConnection`), a hot monitor, or a call without a timeout.
4. Diff the release: new `synchronized` cache, changed pool sizes, a new downstream call, logging at debug.
5. Fix, then prove it: the same histogram, plus a load test reproducing the regression. Add an alert on the leading indicator found (pool wait time, lock contention).
</details>

<details><summary><b>B3. ⚡ Secure service-to-service calls and user-delegated calls in one platform.</b></summary>

* **Users:** authorization code + PKCE at the edge (or a BFF that holds tokens server-side). APIs are resource servers that validate `iss`/`aud`/`exp` and scopes, and check ownership in services.
* **Service-to-service:** client-credentials tokens with per-service audiences, or mTLS with workload identities (SPIFFE/SPIRE or a mesh), mapped to principals and authorized per operation. For "on behalf of a user" calls, token exchange (RFC 8693) so downstream services see both identities.
* **Keys and certs:** JWKS rotation by `kid`; short-lived certificates with automated rotation; expiry alerts.
* **Egress:** SSRF guards for user-supplied URLs; an egress proxy with allow-lists.
* **Evidence:** security tests per endpoint (401 without token, 403 with wrong scope or another user's object), dependency scanning with an SBOM, and audit logs with trace-ids.
</details>

<details><summary><b>B4. ⚡ Define the test strategy for a payments service (Spring Boot, Postgres, Kafka, outbox).</b></summary>

* **Unit:** money arithmetic, state machine transitions, idempotency-key handling: JUnit 6 parameterized tables, no Spring.
* **Architecture:** ArchUnit for layering, no cycles, no `System.out`/`java.util.logging`, and "only the outbox publisher talks to Kafka".
* **Slices:** `@WebMvcTest` for validation, error mapping (problem details) and security rules (`spring-boot-starter-security-test`); `@DataJpaTest` against Testcontainers Postgres for queries, locking and constraints.
* **Integration:** one shared context with Postgres and Kafka containers via `@ServiceConnection`. Prove the outbox relay delivers exactly the committed events, consumer deduplication, and the DLT path (Awaitility, no sleeps).
* **Non-functional:** a JMH benchmark with an allocation gate for the hot serialization path; a load test for p99 under realistic concurrency; contract tests with consumers.
* **CI hygiene:** fail when Docker is missing, track skipped tests, watch the number of Spring contexts.
</details>

<details><summary><b>B5. ⚡ You're upgrading a large codebase from Boot 3 / JUnit 5 to Boot 4 / JUnit 6. What breaks in the tests?</b></summary>

`@MockBean`/`@SpyBean` are removed (move to `@MockitoBean`/`@MockitoSpyBean`). Slice annotations moved to technology test modules (add `spring-boot-starter-webmvc-test`, `-data-jpa-test`, …, or `spring-boot-starter-test-classic` as a stepping stone). JUnit 6 needs Java 17+ and Surefire/Failsafe ≥ 3.0; Vintage is deprecated and `junit-platform-runner` is gone; parameterized display names are now quoted (report filters); CSV parsing moved to FastCSV (edge cases). Testcontainers 2 renames artifacts and packages and drops JUnit 4. Add Mockito as a `-javaagent` while you are touching the build. Do it in steps, with the suite green between steps.
</details>

---

## C. Code questions (verified)

### C1 — In which order do JUnit lifecycle methods and nested tests run?

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.qa;

import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;

import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.platform.launcher.core.*;

public class Lifecycle01 {
    static final List<String> log = new ArrayList<>();

    static class OrderTest {
        OrderTest() { log.add("new OrderTest"); }
        @BeforeAll static void beforeAll() { log.add("beforeAll"); }
        @BeforeEach void beforeEach() { log.add("  beforeEach"); }
        @Test void a() { log.add("    a"); }
        @Test void b() { log.add("    b"); }
        @AfterEach void afterEach() { log.add("  afterEach"); }
        @AfterAll static void afterAll() { log.add("afterAll"); }

        @Nested class WhenPaid {
            WhenPaid() { log.add("new WhenPaid"); }
            @BeforeEach void nestedBeforeEach() { log.add("  nested beforeEach"); }
            @Test void c() { log.add("    c"); }
        }
    }

    public static void main(String[] args) {
        LauncherFactory.create().execute(LauncherDiscoveryRequestBuilder.request().selectors(selectClass(OrderTest.class))
            .configurationParameter("junit.jupiter.testmethod.order.default", "org.junit.jupiter.api.MethodOrderer$MethodName").build());
        System.out.println(String.join("\n", log));
    }
}
```

<details><summary>Answer</summary>

Output (verified):

```
beforeAll
new OrderTest
  beforeEach
    a
  afterEach
new OrderTest
  beforeEach
    b
  afterEach
new OrderTest
new WhenPaid
  beforeEach
  nested beforeEach
    c
  afterEach
afterAll
```

* `@BeforeAll` is static and runs once, before any instance exists.
* A **new instance per test method** (`PER_METHOD`): three `new OrderTest` lines for three tests, including the outer instance created for the nested test.
* Nested classes run **after** the enclosing class's own methods. The outer `@BeforeEach`/`@AfterEach` **wrap** nested tests (outer before inner).
* `@AfterAll` runs last, after the nested class.
</details>

### C2 — Parent-based sampling: who decides whether your span is recorded?

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.qa;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapGetter;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.samplers.Sampler;
import java.util.*;

public class Sampling01 {
    public static void main(String[] args) {
        var tracer = SdkTracerProvider.builder().setSampler(Sampler.parentBased(Sampler.alwaysOff())).build().get("demo");
        var w3c = W3CTraceContextPropagator.getInstance();
        TextMapGetter<Map<String, String>> getter = new TextMapGetter<>() {
            public Iterable<String> keys(Map<String, String> carrier) { return carrier.keySet(); }
            public String get(Map<String, String> carrier, String key) { return carrier == null ? null : carrier.get(key); }
        };
        String incomingTrace = "4bf92f3577b34da6a3ce929d0e0e4736";

        for (String header : List.of("00-" + incomingTrace + "-00f067aa0ba902b7-01", "00-" + incomingTrace + "-00f067aa0ba902b7-00", "")) {
            Map<String, String> incoming = header.isEmpty() ? Map.of() : Map.of("traceparent", header);
            Span span = tracer.spanBuilder("GET /orders/{id}").setParent(w3c.extract(Context.root(), incoming, getter)).startSpan();
            Map<String, String> outgoing = new HashMap<>();
            w3c.inject(Context.root().with(span), outgoing, Map::put);
            System.out.printf("incoming %-6s → recording=%-5s sameTrace=%-5s outgoing=%s%n",
                header.isEmpty() ? "(none)" : "…-" + header.substring(header.length() - 2),
                span.isRecording(), span.getSpanContext().getTraceId().equals(incomingTrace),
                outgoing.getOrDefault("traceparent", "(none)").replaceAll("^00-\\w{32}-\\w{16}", "00-<trace>-<span>"));
            span.end();
        }
    }
}
```

<details><summary>Answer</summary>

Output (verified):

```
incoming …-01   → recording=true  sameTrace=true  outgoing=00-<trace>-<span>-01
incoming …-00   → recording=false sameTrace=true  outgoing=00-<trace>-<span>-00
incoming (none) → recording=false sameTrace=false outgoing=00-<trace>-<span>-02
```

* With `parentBased(...)`, **the caller's sampled flag decides**. A sampled `traceparent` (`-01`) produced a recording span even though the root sampler was `alwaysOff`. An unsampled one (`-00`) didn't. Upstream services therefore control your trace volume, which is why tail-based sampling in the collector exists.
* The trace-id propagated in both cases (`sameTrace=true`), and the **unsampled context was still injected downstream**. Log correlation by trace-id works even for unsampled requests.
* With no incoming header, a new trace started (not recorded, because the root sampler was `alwaysOff`) and its `traceparent` carried flags **`02`**: the random-trace-id bit, without the sampled bit.
</details>

### C3 — `DelegatingPasswordEncoder`: prefixes, salts and legacy hashes

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.qa;

import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;

public class Passwords01 {
    public static void main(String[] args) {
        PasswordEncoder encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
        String h1 = encoder.encode("s3cret"), h2 = encoder.encode("s3cret");
        System.out.println("1. " + h1.substring(0, h1.indexOf('}') + 1) + " length=" + h1.length()
            + " sameHashTwice=" + h1.equals(h2) + " matches=" + encoder.matches("s3cret", h2));
        System.out.println("2. {noop} matches=" + encoder.matches("s3cret", "{noop}s3cret")
            + " upgradeEncoding=" + encoder.upgradeEncoding("{noop}s3cret"));
        try {
            encoder.matches("s3cret", "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy");   // legacy hash, no {id}
        } catch (IllegalArgumentException e) {
            System.out.println("3. " + e.getMessage());
        }
    }
}
```

<details><summary>Answer</summary>

Output (verified):

```
1. {bcrypt} length=68 sameHashTwice=false matches=true
2. {noop} matches=true upgradeEncoding=true
3. Given that there is no default password encoder configured, each password must have a password encoding prefix. Please either prefix this password with '{noop}' or set a default password encoder in `DelegatingPasswordEncoder`.
```

* The default is BCrypt with an `{id}` prefix. Two encodings of the same password differ (random salt), and both verify.
* `{noop}` (plain text) still verifies, and `upgradeEncoding` returns `true`: re-encode on next successful login (Spring's `UserDetailsPasswordService` does this automatically).
* A hash **without** an `{id}` prefix throws `IllegalArgumentException`. Spring Security 7's message tells you to add a prefix or set a default encoder for unprefixed hashes (`setDefaultPasswordEncoderForMatches(new BCryptPasswordEncoder())`). That is the migration path for legacy BCrypt columns.
</details>

### C4 — Spies: `when(...)` vs `doReturn(...)`

<!-- run: javac cp=@p8 timeout=120 -->
```java
package demo.qa;

import static org.mockito.Mockito.*;

import java.util.*;

public class Spies01 {
    public static void main(String[] args) {
        List<String> spy = spy(new ArrayList<String>());
        try {
            when(spy.get(0)).thenReturn("stubbed");
            System.out.println("1. when(spy.get(0)) worked");
        } catch (RuntimeException e) {
            System.out.println("1. when(spy.get(0)) threw " + e.getClass().getSimpleName());
        }
        doReturn("stubbed").when(spy).get(0);
        System.out.println("2. get(0)=" + spy.get(0) + " size=" + spy.size());
        spy.add("real");
        System.out.println("3. after add: size=" + spy.size() + " get(0)=" + spy.get(0));

        List<String> original = new ArrayList<>(List.of("x"));
        List<String> spyOfOriginal = spy(original);
        spyOfOriginal.add("y");
        System.out.println("4. spy size=" + spyOfOriginal.size() + ", original size=" + original.size());
    }
}
```

<details><summary>Answer</summary>

Output (verified):

```
1. when(spy.get(0)) threw IndexOutOfBoundsException
2. get(0)=stubbed size=0
3. after add: size=1 get(0)=stubbed
4. spy size=2, original size=1
```

* `when(spy.get(0))` **calls the real method first**, and the empty list throws `IndexOutOfBoundsException`. For spies, use `doReturn(...).when(spy).method()`, which doesn't invoke the real method.
* Once stubbed, `get(0)` returns the stub regardless of the real contents. Unstubbed methods (`size`, `add`) run for real.
* `spy(original)` **copies** the object's state into the spy. Changes to the spy don't affect the original, which surprises tests that keep asserting on the original reference.
</details>

---

## D. Study map

| Topic | Files | Practise |
|---|---|---|
| JFR, async-profiler, thread dumps | [8.1](01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md) | A1–A8, B2 |
| OpenTelemetry, Micrometer, structured logging | [8.2](02-Observability-OpenTelemetry-Micrometer-Logging.md) | C2, A9–A16, B1 |
| Spring Security, OAuth2/JWT, mTLS, OWASP | [8.3](03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md) | C3, A17–A23, B3 |
| JUnit 6, Mockito, Spring test contexts, Testcontainers, ArchUnit | [8.4](04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md) | C1, C4, A24–A28, B4, B5 |
| JMH | [8.5](05-JMH-Benchmarking.md) | A29–A30 |
| Incident response | [8.6](06-Production-Failure-Modes-Diagnostics.md) | Rehearse Stories 1, 2, 5, 7, 11 and 12 aloud |

**Spring Professional (2V0-72.22) mapping:** testing objectives → 8.4 §1, §4 and C1/C4 (know both `@MockBean` and `@MockitoBean`); security objectives → 8.3 §1–2 and C3; Actuator and metrics → 8.2 §3 plus Pillar 6's health and metrics material.
