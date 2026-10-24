# 8.6 · Pillar 8 — Production Failure Modes & Diagnostic Checklist (Observability, Security, Testing)

> This pillar's failures are about **seeing, trusting and proving**. The service works, but you can't tell why it is slow; it is "secure", but a token from another app gets in; it is "tested", but the suite skipped the tests that mattered. The stories below are composites; each mechanism was **reproduced in [8.1](01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md)–[8.5](05-JMH-Benchmarking.md)** on JDK 25 with the real libraries. The file ends with the toolkit, the signals to alert on, and review checklists.

---

## 1. Incident playbooks

### 🔥 Story 1 — "p99 doubled, the dashboard says everything is fine"

* **Symptom:** customers complained about slow checkouts. The latency panel showed p99 at ~600 ms, unchanged.
* **Root cause:** the panel **averaged per-instance p99s** exported as client-side percentiles (a Prometheus *summary*). One instance with a slow disk had a 2 s tail, and averaging diluted it. Reproduced in [8.2 §3.1](02-Observability-OpenTelemetry-Micrometer-Logging.md#31-runnable-averaging-p99s-lies-merged-histograms-dont): averaged p99 **595 ms**, true p99 **1,057 ms**.
* **Fix:** `publishPercentileHistogram()` (or the Boot `percentiles-histogram` property) and `histogram_quantile(0.99, sum by (le) (rate(..._bucket[5m])))`. Add SLO buckets and burn-rate alerts. Note that enabling the histogram **dropped** the percentile gauges from the Prometheus output (verified), so update dashboards in the same change.

### 🔥 Story 2 — "Traces stop at the thread pool"

* **Symptom:** in the tracing UI, requests ended after the controller span. Hundreds of orphan root spans named like inner work (`price-lookup`, `send-email`) appeared with no parent.
* **Root cause:** OTel context lives in a `ThreadLocal`. Work submitted to a plain executor, and to **virtual threads**, started new traces ([8.2 §2.1](02-Observability-OpenTelemetry-Micrometer-Logging.md#21-runnable-executors-virtual-threads-a-producerconsumer-hop-baggage-and-span-links)). A Kafka hop without header injection broke the trace again downstream.
* **Fix:** `Context.taskWrapping(executor)` / Spring `TaskDecorator` / context-propagation; instrumented Kafka clients (inject/extract `traceparent`); span **links** for batch consumers. **Detection:** alert on the ratio of root spans per service entry point.

### 🔥 Story 3 — "Support can't find the logs for a failed order"

* **Symptom:** the trace-id from the error page matched nothing in the log search.
* **Root causes:** (1) one service logged with `traceId`, another with ECS `trace.id`, and the log pipeline indexed only one ([8.2 §4.1](02-Observability-OpenTelemetry-Micrometer-Logging.md#41-runnable-spring-boot-4-ecs-logging-mdc-slf4j-key-values-and-an-incoming-traceparent): Boot's ECS output used the MDC names `traceId`/`spanId`); (2) Boot's default sampling probability is **0.1**, so 90% of requests had no trace at all.
* **Fix:** consistent key names (rename in the formatter or the pipeline), trace-ids in every log line regardless of sampling, tail-based sampling in the collector (keep errors and slow requests), 100% sampling for low-volume services.

### 🔥 Story 4 — "Customer A's order ID in customer B's log line"

* **Root cause:** MDC entries set in a filter were never removed. Pooled threads carried them into the next request; a background job then logged under the wrong order.
* **Fix:** `try/finally` MDC cleanup (or `MDC.putCloseable`), context-propagation libraries for async hops, and a test that runs two requests on one thread and asserts clean MDC.

### 🔥 Story 5 — "The service hangs every few days; restarting fixes it"

* **Evidence:** CPU near zero. Health checks timed out.
* **Diagnosis:** three `jcmd <pid> Thread.print` dumps 10 s apart: two request threads `BLOCKED` on each other's monitors. The dump printed *"Found one Java-level deadlock"* with the holder and waiter of each lock ([8.1 §4.1](01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md#41-runnable-a-deadlock-a-parked-worker-and-an-idle-consumer-seen-three-ways)).
* **Second team, same symptom:** a virtual-thread service where the hung tasks did **not** appear in `jstack`-style dumps or `ThreadMXBean`. `jcmd <pid> Thread.dump_to_file -format=json` showed them, all parked on the same downstream call without a timeout.
* **Fix:** global lock ordering (or `tryLock` with timeouts); timeouts on every remote call; an always-on JFR recording plus a runbook that captures dumps before restarting.

### 🔥 Story 6 — "Latency spikes under load, but CPU is only 40%"

* **Diagnosis:** a JFR recording dumped during the incident. `jfr view contention-by-site` pointed at one `synchronized` cache-refresh method. Monitors are **not fair**: the releasing thread re-acquired the lock repeatedly while others waited 70–215 ms (barging, reproduced in [8.1 §2.1](01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md#21-runnable-what-a-3-second-recording-tells-you-about-this-jvm)).
* **Fix:** shrink the critical section, use a concurrent structure or a striped lock, or refresh asynchronously and swap a reference. Keep `jdk.JavaMonitorEnter` and `jdk.ThreadPark` thresholds in the production JFR settings.

### 🔥 Story 7 — "A token for the billing API worked on the orders API"

* **Root cause:** the resource server validated signature, issuer and expiry, but **not the audience**. Every API trusting the same IdP accepted every token. Reproduced and fixed in [8.3 §2.1](03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md#21-runnable-real-rs256-tokens-against-a-boot-4-resource-server-valid-scoped-expired-forged-algnone-idor): a correctly signed `billing-api` token was rejected once the audience validator was added.
* **Related finding in the same review:** Alice could read Bob's order with a correctly scoped token (IDOR, **A01**). Scopes say *what kind of operation*; ownership checks say *which object*. Both are needed.

### ⚡ Story 8 — "Every call returns 401 after the IdP rotated its keys"

* **Root cause:** the public key was pasted into configuration instead of using `issuer-uri`/`jwk-set-uri`. After rotation, no token verified.
* **Fix:** JWKS discovery with refresh by `kid`; alert on a 401-rate spike; rehearse key rotation in staging.

### ⚡ Story 9 — "mTLS was on, and an unknown service still called us"

* **Evidence:** handshake succeeded; the request was rejected only because the CN happened to be unmapped.
* **Root cause:** trusting a CA means trusting **every** certificate it signs. The handshake is authentication of a key holder, not authorization ([8.3 §3.1](03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md#31-runnable-a-throwaway-ca-spring-boot-ssl-bundles-with-client-authneed-and-x509-authentication): an unknown CN completed TLS and got 403).
* **Fix:** map certificate identities (CN/SAN or SPIFFE IDs) to known principals with per-operation authorization; a dedicated CA per trust domain; certificate expiry monitoring.

### ⚡ Story 10 — "Cloud credentials leaked through the PDF-from-URL feature"

* **Root cause:** an SSRF blocklist on host strings. An attacker used the decimal form `http://2130706433/` and an IPv4-mapped IPv6 address, two of the forms that passed the naive check in [8.3 §4.1](03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md#41-runnable-an-ssrf-guard-that-resolves-before-it-judges)).
* **Fix:** resolve, check every address against loopback/private/link-local/any-local/multicast/unique-local ranges, connect to the checked IP, disable redirects, and enforce egress at the network layer (plus IMDSv2 hop limits).

### ⚡ Story 11 — "The test suite went from 6 to 25 minutes in a quarter"

* **Root cause:** each new test class added its own `@MockitoBean` mix, and a few used `@DirtiesContext`. Every distinct combination built a new Spring context ([8.4 §4.1](04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md#41-runnable-six-test-classes-one-configuration--how-many-contexts): six classes, three contexts).
* **Fix:** a shared integration-test base class with one mocked set, singleton containers, slices instead of `@SpringBootTest` where possible, and the context-cache log in CI to catch regressions.

### ⚡ Story 12 — "Green build, broken migration in production"

* **Root cause:** the repository integration tests were annotated `@Testcontainers(disabledWithoutDocker = true)`. A CI image change removed Docker, and the tests **skipped** without failing the build ([8.4 §5.1](04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md#51-runnable-a-postgres-integration-test-wired-by-serviceconnection-and-what-happens-without-docker)). Aborted and skipped tests were shown as "not failed".
* **Fix:** fail fast when Docker is missing in CI, and assert the executed test count (or the absence of skipped integration tests) in the pipeline.

### 🧊 Story 13 — "The optimization made production slower"

* **Root cause:** a microbenchmark in `main()` showed a 50× gain. It measured dead-code elimination, not the change ([8.5 §1.1](05-JMH-Benchmarking.md#11-runnable-dead-code-constant-folding-and-a-surprise-on-jdk-25): a naive loop reported 0.012 ns per `Math.sqrt`). The "faster" version allocated more and raised GC pressure.
* **Fix:** profile first (async-profiler or JFR), compare alternatives with JMH (returned values, `@State`, forks, realistic `@Param` sizes), gate on `gc.alloc.rate.norm`, and confirm with a load test.

---

## 2. The diagnostic toolkit

| Question | First tool | Then |
|---|---|---|
| Where is CPU going? | async-profiler `-e cpu` flame graph; JFR `hot-methods` | JMH for alternative implementations |
| Why is latency high with low CPU? | JFR `contention-by-site`, `jdk.ThreadPark`; 3 thread dumps | Traces: which downstream span is slow |
| Who allocates? | JFR `allocation-by-site` (`jdk.ObjectAllocationSample`); async-profiler `-e alloc` | JMH `-prof gc` B/op |
| Is the JVM hung? | `jcmd <pid> Thread.print` (deadlock section) | `Thread.dump_to_file -format=json` for virtual threads |
| Why is *this* request slow? | The trace (by trace-id from the logs or exemplar) | Span attributes, logs with the same trace-id |
| Is it getting worse overall? | Histogram metrics, SLO burn rate | Exemplars into traces |
| Why was this request rejected (401/403)? | `WWW-Authenticate` header (`error`, `error_description`), security debug logs in a test environment | Decode the token (header + claims; never paste production tokens into public sites) |
| Is the suite slow because of contexts? | `org.springframework.test.context.cache` debug log | Count contexts per CI run |

Commands to have in the runbook:

```bash
jcmd <pid> JFR.start name=incident settings=profile duration=120s filename=/tmp/incident.jfr
jcmd <pid> JFR.dump name=continuous filename=/tmp/now.jfr          # from the always-on recording
jfr view hot-methods /tmp/now.jfr ; jfr view contention-by-site /tmp/now.jfr ; jfr view allocation-by-site /tmp/now.jfr
jcmd <pid> Thread.print -l > dump1.txt                              # x3, 5–10 s apart
jcmd <pid> Thread.dump_to_file -format=json /tmp/threads.json       # includes virtual threads
asprof -e cpu -d 30 -f /tmp/cpu.html <pid>                          # Linux/macOS
curl -s localhost:8081/actuator/prometheus | grep http_server_requests_seconds_bucket | head
```

---

## 3. Signals and alerts

| Signal | Alert / meaning |
|---|---|
| SLO burn rate (fast 1 h / slow 6 h windows) on histogram-based latency and error ratios | Page on fast burn; ticket on slow burn |
| Root spans per entry point (orphan-span ratio) | Context propagation broke after a deploy |
| Log lines without trace-id | Correlation broken; MDC/tracing misconfigured |
| Active series per service (Prometheus `count by (__name__)`) | A high-cardinality tag was introduced |
| JFR `jdk.JavaMonitorEnter` / `jdk.ThreadPark` above threshold; `jdk.VirtualThreadPinned` | Lock contention; carrier pinning (native frames) |
| GC pause time and allocation rate (from JFR or Micrometer JVM metrics) | Allocation regressions |
| 401 rate, 403 rate per route and client | Key rotation or audience issues (401); probing or broken clients (403) |
| Certificate expiry (days left) per keystore and truststore | Renew before outage |
| Outbound requests to private or metadata addresses (egress logs) | SSRF attempts |
| CI: executed vs expected test counts; skipped and aborted counts; suite duration; Spring contexts created | Silent test loss; suite-time regressions |

---

## 4. Review checklists

**Observability**

- [ ] Latency timers publish **histograms** (with SLO buckets); dashboards use `histogram_quantile` over summed buckets.
- [ ] Metric tags are bounded (route templates, status class), with a `MeterFilter` cap as a safety net.
- [ ] Context propagation across executors, virtual threads, reactive operators and messaging (inject/extract), with span links for batches.
- [ ] JSON logs with trace-id and span-id in every line, consistent key names, MDC cleaned in `finally`; no secrets or personal data in logs or baggage.
- [ ] Sampling strategy chosen explicitly (Boot default 0.1); errors and slow traces kept (tail sampling).
- [ ] Always-on JFR in production (`-XX:StartFlightRecording` with a size/age-bounded ring buffer) and a runbook for dumps.

**Security**

- [ ] Resource servers validate signature (asymmetric, via JWKS), `iss`, **`aud`**, `exp`/`nbf`; short-lived tokens; no shared HMAC secrets.
- [ ] Object-level authorization (ownership) in services, with tests for horizontal access; method security on the proxy.
- [ ] CSRF on for cookie/session endpoints; bearer-only APIs stateless.
- [ ] mTLS identities mapped to principals and authorized per operation; certificate expiry monitored; reloadable SSL bundles.
- [ ] Outbound URL fetching goes through a resolve-then-check guard and an egress proxy.
- [ ] Error responses are problem details with generic messages; details only in server logs.
- [ ] Dependencies scanned, pinned and SBOM-tracked (**A03 Software Supply Chain Failures**).

**Testing and benchmarking**

- [ ] Integration tests against the production database and broker versions (Testcontainers), and they **fail** in CI when Docker is missing.
- [ ] One shared Spring test configuration; `@MockitoBean` sets standardized; `@DirtiesContext` justified.
- [ ] Mockito configured as a `-javaagent`; strict stubs on; no mocks of types you don't own.
- [ ] ArchUnit rules for layering, cycles and banned APIs, frozen for legacy code.
- [ ] JUnit 6 upgrade: Surefire/Failsafe ≥ 3.0, no Vintage tests left, report filters adjusted for quoted display names.
- [ ] Performance claims backed by profiles plus JMH (forks, returned values, `-prof gc`), not `main()` loops.
