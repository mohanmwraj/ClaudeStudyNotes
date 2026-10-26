# 4.4 Web Concurrency Models: Tomcat Thread Pools vs Virtual Threads vs WebFlux/Netty, Measured

> **Verified stack:** Spring Boot **4.1.2** (Tomcat **11.0.27**, Reactor Netty **1.3.8**), Spring Framework **7.0.10**, Temurin **25**. Load: a closed-loop Java `HttpClient` generator on virtual threads, **400 concurrent clients, 4,000 requests**, against an endpoint that spends **100 ms** waiting (blocking `Thread.sleep` for MVC, `Mono.delay` for WebFlux). One measured run per mode on a 12-logical-CPU laptop: compare ratios, not absolutes.
>
> **Go deeper:** the sibling kit's [3.6 virtual threads & pinning](../../Java-Backend-Master-Reference/03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md) and [6.2 MVC vs WebFlux with backpressure](../../Java-Backend-Master-Reference/06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md).

---

## 0. First principles: Little's law decides everything 🔥

> **concurrency = throughput × latency**

A service that spends 100 ms waiting per request (database, downstream HTTP) and must serve 3,000 req/s needs **300 requests in flight**. The concurrency model decides **what holds each in-flight request** and therefore what runs out first:

| Model | Each in-flight request holds | Typical ceiling |
|---|---|---|
| Thread-per-request on **platform threads** (classic Tomcat) | An OS thread (~1 MB of reserved stack, kernel scheduling) | The pool size (`server.tomcat.threads.max`, default 200) |
| Thread-per-request on **virtual threads** | A virtual thread: a heap object that **unmounts** from its carrier while blocked | Downstream resources (DB connections, rate limits) |
| **Reactive** (WebFlux on Netty) | A callback chain; a few event-loop threads multiplex everything | CPU, as long as **nothing ever blocks the event loop** |

---

## 1. The measurements (verified) 🔥

```java
@GetMapping("/block")                       // simulates a 100 ms blocking call (JDBC, HTTP client, ...)
String block() throws InterruptedException {
    Thread.sleep(100);
    return Thread.currentThread().toString();
}

@GetMapping("/delay")                       // non-blocking 100 ms wait
Mono<String> delay() { return Mono.delay(Duration.ofMillis(100)).map(x -> Thread.currentThread().toString()); }
```

**One measured run each:**

```text
== MVC, platform threads (server.tomcat.threads.max=50)
  sample thread: Thread[#45,http-nio-18080-exec-2,5,main]
  concurrency=400 requests=4000 errors=0  throughput=481 req/s  p50=816 ms  p99=909 ms  max=971 ms
== MVC, virtual threads (spring.threads.virtual.enabled=true)
  sample thread: VirtualThread[#52,tomcat-handler-1]/runnable@ForkJoinPool-1-worker-1
  concurrency=400 requests=4000 errors=0  throughput=3098 req/s  p50=108 ms  p99=265 ms  max=278 ms
== WebFlux on Netty (Mono.delay)
  sample thread: Thread[#49,parallel-2,5,main]
  concurrency=400 requests=4000 errors=0  throughput=2959 req/s  p50=105 ms  p99=340 ms  max=376 ms
== WebFlux, BLOCKING handler (Thread.sleep on the event loop)
  sample thread: Thread[#47,reactor-http-nio-3,5,main]
  concurrency=400 requests=4000 errors=3670  throughput=108 req/s  p50=1494 ms  p99=2976 ms  max=3022 ms
  errors: {ConnectException: null=3670}
```

| Mode | Throughput | p50 | What happened |
|---|---|---|---|
| Platform threads, max 50 | 481 req/s | **816 ms** | Little's law: 50 threads / 0.1 s = 500 req/s ceiling. The other 350 requests **queue**, so p50 ≈ 400/50 × 100 ms = 800 ms. The work took 100 ms; the user waited 816 |
| Virtual threads | **3,098 req/s** | 108 ms | Every request gets its own virtual thread; blocking `sleep` unmounts it from the carrier. Limited only by the client's 400 concurrency |
| WebFlux (`Mono.delay`) | 2,959 req/s | 105 ms | Same result through a different mechanism: no thread waits at all |
| WebFlux with a **blocking call** | **108 req/s**, 92% failed | 1,494 ms | 12 event-loop threads × 10 sleeps/s each ≈ 120 req/s. The loops were also too busy to accept connections in time, so most clients got `ConnectException` |

The last row is the reactive model's defining failure: one blocking call (`JdbcTemplate`, a blocking HTTP client, `Thread.sleep`, a `synchronized` waiting on I/O) on the event loop turns a server that handled 3,000 req/s into one that refuses connections.

### Which threads Boot uses (verified)

```text
virtual=false: handler=Thread[#46,http-nio-18080-exec-3,5,main] | @Async=Thread[#59,task-2,5,main]
virtual=true:  handler=VirtualThread[#53,tomcat-handler-1]/runnable@ForkJoinPool-1-worker-1 | @Async=VirtualThread[#54,task-2]/runnable@ForkJoinPool-1-worker-2
```

`spring.threads.virtual.enabled=true` switches **Tomcat's request handling and Boot's auto-configured task executor** (so `@Async`) to virtual threads, and Boot applies it to other integrations it auto-configures (scheduling, messaging listener containers, depending on the version).

---

## 2. Tomcat's thread model ⚡

```text
             ┌──────────────┐   accept    ┌────────┐   readiness events   ┌─────────────────────────┐
 clients ───►│ OS backlog   │────────────►│Acceptor│─────────────────────►│ Poller (NIO selector)   │
             │ (acceptCount │             └────────┘                      └────────────┬────────────┘
             │  default 100)│                                                          │ socket readable
             └──────────────┘                                                          ▼
                     max-connections (8192): sockets kept open             ┌─────────────────────────┐
                                                                           │ Executor: worker threads│
                                                                           │ threads.max=200         │  ← your controller runs here
                                                                           │ (or virtual threads)    │
                                                                           └─────────────────────────┘
```

| Property | Default | Meaning |
|---|---|---|
| `server.tomcat.threads.max` | 200 | Max concurrent requests being **processed** (platform-thread mode) |
| `server.tomcat.threads.min-spare` | 10 | Warm threads |
| `server.tomcat.max-connections` | 8192 | Open sockets Tomcat keeps (most may be idle keep-alive) |
| `server.tomcat.accept-count` | 100 | OS backlog once `max-connections` is reached |
| `server.tomcat.connection-timeout` | 60 s (Tomcat's default) | How long to wait for the request line after connect |

When all worker threads are busy, requests **queue silently**, and latency rises long before anything errors. That's what the 816 ms p50 above is. Watch `tomcat.threads.busy` vs `tomcat.threads.config.max` (Micrometer) and request queueing time, not only error rates.

---

## 3. Virtual threads in production ⚡

**When they help:** I/O-bound request handling with many concurrent waits (JDBC, HTTP calls), where you want the simple blocking programming model without sizing thread pools.

**What doesn't change, and the traps:**

| Trap | Why | Mitigation |
|---|---|---|
| **The bottleneck moves downstream** | 3,000 concurrent virtual threads all calling `getConnection()` on a 20-connection Hikari pool: the pool becomes the queue (Hikari `pending` climbs, `connectionTimeout` errors) | Size pools from Little's law ([2.7 §3](../02-SQL-RDBMS-Internals/07-Scaling-Replicas-Partitioning-Pooling-Sharding.md)); bound concurrency explicitly: a `Semaphore`, or Spring 7's `@ConcurrencyLimit` on the call site |
| CPU-bound work | Virtual threads don't add CPU | Keep CPU-heavy work on a bounded platform pool |
| Pinning | JDK 21–23: blocking inside `synchronized` pinned the carrier. **JDK 24+ (JEP 491) removed that for monitors**; native frames and some class-loading paths still pin | Run JDK 24+ (this playbook: 25). Diagnose with the JFR event `jdk.VirtualThreadPinned` |
| ThreadLocal-heavy code | Millions of threads × ThreadLocal caches = memory | `ScopedValue` (final in JDK 25), avoid per-thread caches of big objects |
| Unbounded `@Async` | With virtual threads there's no pool to push back | Limit concurrency where it matters (rate limiters, bulkheads, [6.2](../06-Resilience-Caching-Kafka/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)) |

```java
// Spring Framework 7: bound concurrent calls to a fragile downstream, even with virtual threads
@ConcurrencyLimit(20)
public Quote fetchQuote(String sku) { return pricingClient.quote(sku); }
```

---

## 4. WebFlux and the event loop ⚡

Reactor Netty runs a small number of **event-loop threads** (by default roughly one per CPU core: `reactor-http-nio-N`). Each loop multiplexes thousands of connections, so it must **never block**. The rules:

* Use non-blocking drivers end to end: `WebClient`, R2DBC, reactive Redis/Kafka/Mongo clients.
* If you must call blocking code, isolate it: `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`, a bounded pool sized like a platform-thread pool.
* Detect accidental blocking in tests with **BlockHound**.
* Backpressure (`limitRate`, `onBackpressureBuffer`, bounded `flatMap` concurrency) is the reactive model's real superpower: it lets producers slow down to the consumer's speed in streaming pipelines.

---

## 5. Choosing (staff-level decision table) 🧊

| Situation | Choose | Why |
|---|---|---|
| Typical CRUD/business service on JDBC/JPA, Java 21+ | **MVC + virtual threads** | Same throughput as WebFlux for I/O waits in our test, with blocking code, normal stack traces and debugging, `ThreadLocal`-based tracing and transactions working as usual |
| Streaming (SSE, WebSockets), many long-lived connections, backpressure needed | **WebFlux** | Built for streams and flow control |
| Gateway / proxy (Spring Cloud Gateway) | WebFlux (or Gateway's MVC flavor on virtual threads) | Mostly forwarding bytes |
| Fully reactive stack already (R2DBC, reactive clients) | WebFlux | Consistency |
| Java 17, can't upgrade | MVC with sized thread pools, or WebFlux for very high concurrency | No virtual threads |
| CPU-heavy endpoints | Either, with bounded pools | Neither model adds CPU |

The anti-pattern to call out in interviews: **WebFlux plus blocking JDBC** (the last row of §1's table), which gives you reactive complexity and worse-than-thread-pool behavior.

---

## 6. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| `threads.max=1000` to "handle more load" | Virtual threads, or size from Little's law; watch busy threads and queueing time |
| Virtual threads with a 10-connection pool and no limits | Bound concurrency to the downstream capacity (`@ConcurrencyLimit`, semaphores, bulkheads) |
| `JdbcTemplate` inside a WebFlux handler | MVC + virtual threads, or `subscribeOn(boundedElastic())`, or R2DBC |
| JDK 21 virtual threads with `synchronized` around I/O | JDK 24+ (JEP 491), or `ReentrantLock` |
| Latency SLOs measured only as error rates | p99 latency and queueing metrics: the platform-thread run had **zero errors** and an 816 ms median |

---

## 7. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [apache/tomcat](https://github.com/apache/tomcat) | `java/org/apache/tomcat/util/net/NioEndpoint.java` | Acceptor, Poller, `maxConnections` |
| [spring-projects/spring-boot](https://github.com/spring-projects/spring-boot) | Search for `VirtualThreadsEnabled` / `spring.threads.virtual.enabled` | Where Boot switches executors to virtual threads |
| [reactor/reactor-netty](https://github.com/reactor/reactor-netty) | `reactor-netty-core/src/main/java/reactor/netty/resources/LoopResources.java` | Event-loop thread counts |
| [openjdk/jdk](https://github.com/openjdk/jdk) | `src/java.base/share/classes/java/lang/VirtualThread.java` | Mount/unmount (`park`, `yieldContinuation`) |
| [reactor/BlockHound](https://github.com/reactor/BlockHound) | `agent/src/main/java/reactor/blockhound/BlockHound.java` | How blocking calls on non-blocking threads are detected |

---

## 8. Interview soundbites

* "Little's law: 100 ms of waiting at 3,000 req/s means 300 requests in flight. The model decides whether each holds an OS thread, a virtual thread or a callback."
* "Fifty platform threads gave 481 req/s and an 816 ms median with zero errors: pure queueing. Virtual threads gave 3,098 req/s at 108 ms, the same as WebFlux."
* "One blocking call on Netty's event loop dropped WebFlux to 108 req/s and 92% connection failures."
* "Virtual threads move the bottleneck to the connection pool, so I bound concurrency explicitly, for example with Spring 7's `@ConcurrencyLimit`."

---

## 9. Deep dive: one request's threads, and what happens to them at shutdown (verified) 🔥

§1 measured throughput per threading model. [4.8](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md) traced *which* thread runs each piece of one request, and what happens to that thread when the application stops (Boot 4.1.2, Tomcat 11.0.27, platform threads):

| Work | Thread in the trace | Consequence |
|---|---|---|
| Filter, interceptor, controller, advice, message conversion | One Tomcat worker (`http-nio-18480-exec-N`) for the whole request | `ThreadLocal`s (security context, MDC, transaction) are valid end to end |
| ERROR dispatch to `/error` after an unhandled exception | The **same** worker, a second pass through the interceptor | Error handling consumes the worker too; slow error rendering is slow request handling |
| `@EventListener` and `AFTER_COMMIT` listeners | The publisher's thread (`main` in the lab, the Tomcat worker in a request) | Listener latency is request latency |
| `@Async` | An executor thread (`task-N`, or `report-N` after another `Executor` bean displaced Boot's) | MDC/security context only follow with a `TaskDecorator` or context propagation |

**At shutdown (verified, graceful is Boot's default):**

* A new connection attempted 300 ms into the shutdown was refused (`ConnectException`, 3 ms after it was sent).
* The in-flight 1.5 s request kept its worker and completed with 200.
* The web server's phase then completed, and lower phases ran.
* With `server.shutdown=immediate`, the worker was **interrupted** (`afterCompletion ex=InterruptedException`) and the client saw a dropped connection.

Two capacity consequences of §1's Little's-law view:

* **Drain time:** a graceful drain of *N* in-flight requests needs at most *max request time* (they run in parallel), not *N ×* it. But it needs the threads and pool connections to stay alive until the drain ends, which is why the connection pool closes in destroy callbacks *after* all lifecycle phases ([4.8 §4](08-Request-Lifecycle-Events-Async-Graceful-Shutdown.md#4-graceful-shutdown-phase-by-phase-verified-)).
* **Executors:** `ThreadPoolTaskExecutor`s are themselves `SmartLifecycle` beans (phase `Integer.MAX_VALUE / 2`), so request-spawned async work can still run while the web server drains. Whether Boot's executor *waits* for queued tasks is `spring.task.execution.shutdown.await-termination` (default `false`).

The lab used platform threads. The phase ordering is independent of the threading model, but with virtual threads the number of concurrently draining requests is bounded by your own limits (§3), not by `server.tomcat.threads.max`.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Little's law | In-flight = throughput × latency; the model decides what each in-flight request holds | §0 |
| Platform threads | 50 threads: 481 req/s, 816 ms median, pure queueing | §1 |
| Virtual threads | 3,098 req/s at 108 ms, matching WebFlux; the bottleneck moves to pools | §1, §3 |
| Event loop | One blocking call: 108 req/s and 92% connection failures | §1 |
| Request threads | One worker per request incl. ERROR dispatch; listeners run on it; `@Async` leaves it | §9 (4.8 trace) |
| Shutdown | Graceful by default: refuse new, drain in-flight, then lower phases; `immediate` interrupts | §9 (4.8 §4) |
| Concurrency limits | Bound explicitly with virtual threads (`@ConcurrencyLimit`, pool sizes) | §3 |

**Next:** [4.5 Security filter chain, JWT, method security & rate limiting →](05-Security-Filter-Chain-JWT-Method-Security-Rate-Limiting.md)
