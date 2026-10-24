# 6.2 · Request Concurrency Models — Spring MVC on Virtual Threads vs WebFlux/Reactor, Backpressure

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Spring Framework 7 reference (Web on Servlet Stack, Web on Reactive Stack); Spring Boot 4.1 configuration metadata; Reactive Streams 1.0.4 specification; Reactor 3.8 reference ("Backpressure", "Context Propagation"); JEP 444 (virtual threads), JEP 491 (synchronize without pinning).
> **Verified stack:** Spring Boot **4.1.2** (Tomcat 11.0.27, Reactor Netty 1.3.8), Spring Framework 7.0.10, Reactor Core **3.8.8**, Micrometer context-propagation 1.2.1, JDK 25, a 12-logical-CPU Windows laptop. The server and load generator share one JVM on loopback, so absolute numbers are **relative comparisons**, not capacity planning data.

---

## 1. Three ways to serve a request that waits 🔥

```
Thread-per-request, platform threads (MVC classic)   Thread-per-request, virtual threads (MVC + Loom)    Event loop (WebFlux / Netty)
 conn ─► Tomcat worker (1 of 200) ──blocks 100 ms──►   conn ─► new virtual thread ──"blocks" 100 ms──►      conn ─► event-loop thread (1 per core)
         thread held for the whole wait                       unmounts: carrier freed during the wait            registers a callback, returns at once
 limit: threads.max (200) → queue → accept-count (100)  limit: downstream resources (pools, DB, APIs)        limit: CPU; ANY blocking call stalls every
                                                                                                             connection on that loop
```

| | MVC + platform threads | MVC + virtual threads | WebFlux (Reactor + Netty) |
|---|---|---|---|
| Programming model | Imperative, blocking | **Imperative, blocking** (same code) | Functional/reactive (`Mono`/`Flux`), non-blocking end to end |
| Concurrency limit | `server.tomcat.threads.max` = **200** (verified default) | Effectively none in the server, so you **must** bound downstream use | Event-loop threads ≈ cores; concurrency bounded by memory |
| Per in-flight request | ~1 MB reserved stack + kernel thread | A few KB of heap (stack chunks) | A few KB (callbacks, buffers) |
| Blocking JDBC/JPA | Fine | **Fine** (releases its carrier while waiting) | Forbidden on event loops; R2DBC or `boundedElastic` offloading |
| Debugging | Full stack traces | Full stack traces; `jcmd Thread.dump_to_file` | Assembly-time traces; needs `checkpoint()`/`ReactorDebugAgent` |
| Backpressure | None (queues and timeouts) | None (bound with semaphores/bulkheads) | **Built in**: `request(n)` demand from subscriber to source |
| Streaming (SSE, WebSocket, 10k+ idle connections) | Possible but expensive | Fine for moderate counts | Natural fit |

---

## 2. Measured: one endpoint, a 100 ms wait, four server models 🔥

### 2.1 Runnable: Boot 4 apps on Tomcat and Netty under 400 concurrent clients

<!-- run: javac cp=@p6web timeout=300 -->
```java
package demo.web;

import java.lang.management.ManagementFactory;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

public class ThreadModels {
    static String who() { Thread t = Thread.currentThread(); return t.isVirtual() ? "virtual thread" : t.getName().replaceAll("\\d+", "N"); }

    @RestController public static class Blocking {                     // Spring MVC: the handler blocks its thread
        @GetMapping("/io") public String io() throws InterruptedException { Thread.sleep(100); return who(); }
    }
    @RestController public static class NonBlocking {                  // WebFlux: the wait is a timer, no thread held
        @GetMapping("/io") public Mono<String> io() { return Mono.delay(Duration.ofMillis(100)).map(x -> who()); }
        @GetMapping("/io-blocking") public Mono<String> ioBlocking() throws InterruptedException {
            Thread.sleep(100);                                         // ANTI-PATTERN: blocks a Netty event-loop thread
            return Mono.just(who());
        }
    }
    @SpringBootConfiguration @EnableAutoConfiguration @Import(Blocking.class) static class MvcApp { }
    @SpringBootConfiguration @EnableAutoConfiguration @Import(NonBlocking.class) static class FluxApp { }

    public static void main(String[] args) throws Exception {
        System.out.printf("%-38s %8s %8s %8s %8s  %-30s%n", "server model (400 concurrent clients)", "req/s", "p50 ms", "p99 ms", "threads", "handler thread");
        run("MVC, Tomcat platform threads (200)", MvcApp.class, "servlet", false, "/io", 4000);
        run("MVC, virtual threads", MvcApp.class, "servlet", true, "/io", 4000);
        run("WebFlux, non-blocking delay", FluxApp.class, "reactive", false, "/io", 4000);
        run("WebFlux, Thread.sleep on event loop", FluxApp.class, "reactive", false, "/io-blocking", 600);
    }

    static void run(String label, Class<?> app, String type, boolean virtual, String path, int requests) throws Exception {
        SpringApplication sa = new SpringApplication(app);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setDefaultProperties(Map.of("server.port", "0", "spring.main.web-application-type", type,
            "spring.threads.virtual.enabled", String.valueOf(virtual), "logging.level.root", "WARN",
            "spring.autoconfigure.exclude", "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration"));
        try (ConfigurableApplicationContext ctx = sa.run();
             HttpClient client = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1)
                 .executor(Executors.newVirtualThreadPerTaskExecutor()).build()) {
            int port = ((WebServerApplicationContext) ctx).getWebServer().getPort();
            URI uri = URI.create("http://localhost:" + port + path);
            load(client, uri, 400, 400);                                    // warm-up
            ManagementFactory.getThreadMXBean().resetPeakThreadCount();
            long t0 = System.nanoTime();
            long[] latencies = load(client, uri, 400, requests);
            double seconds = (System.nanoTime() - t0) / 1e9;
            String handler = client.send(HttpRequest.newBuilder(uri).build(), HttpResponse.BodyHandlers.ofString()).body();
            Arrays.sort(latencies);
            System.out.printf("%-38s %8.0f %8d %8d %8d  %-30s%n", label, requests / seconds,
                latencies[latencies.length / 2], latencies[(int) (latencies.length * 0.99)],
                ManagementFactory.getThreadMXBean().getPeakThreadCount(), handler);
        }
    }

    static long[] load(HttpClient client, URI uri, int concurrency, int requests) throws Exception {
        long[] latencies = new long[requests];
        Semaphore inFlight = new Semaphore(concurrency);
        try (var pool = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < requests; i++) {
                int idx = i;
                inFlight.acquire();
                pool.submit(() -> {
                    try {
                        long t = System.nanoTime();
                        client.send(HttpRequest.newBuilder(uri).build(), HttpResponse.BodyHandlers.discarding());
                        latencies[idx] = (System.nanoTime() - t) / 1_000_000;
                    } finally { inFlight.release(); }
                    return null;
                });
            }
        }
        return latencies;
    }
}
```

Two measured runs:

```
server model (400 concurrent clients)     req/s   p50 ms   p99 ms  threads  handler thread
MVC, Tomcat platform threads (200)         1700      233      311      226  http-nio-auto-N-exec-N
MVC, virtual threads                       3332      111      160       27  virtual thread
WebFlux, non-blocking delay                3094      111      235       47  parallel-N
WebFlux, Thread.sleep on event loop         106     2096     5537       47  reactor-http-nio-N
```

```
server model (400 concurrent clients)     req/s   p50 ms   p99 ms  threads  handler thread
MVC, Tomcat platform threads (200)         1694      235      307      226  http-nio-auto-N-exec-N
MVC, virtual threads                       3312      111      153       27  virtual thread
WebFlux, non-blocking delay                3052      112      213       47  parallel-N
WebFlux, Thread.sleep on event loop         106     2428     5531       47  reactor-http-nio-N
```

**Read it with Little's law** (throughput = concurrency ÷ latency):

* **200 platform threads × (1 / 0.1 s) = 2,000 req/s ceiling.** Measured ~1,700. The other 200 clients **queue**, so p50 is ~235 ms (100 ms of work plus ~130 ms waiting for a worker). That is the classic "thread pool exhaustion" latency signature: p50 rises before errors appear.
* **Virtual threads remove the server-side cap.** All 400 requests wait concurrently, so p50 ≈ the 100 ms of work and throughput ~2× higher (bounded by the 400 clients: 400 / 0.1 s = 4,000 ceiling). The JVM needed **27 platform threads in total** (carriers plus infrastructure) instead of 226.
* **WebFlux matches virtual threads for this I/O-bound case** (the wait is a timer on the `parallel` scheduler). No thread is held during the wait. Its p99 was a little worse in both runs.
* **Blocking an event loop is catastrophic:** Netty has one loop per core (12 here), and each `Thread.sleep(100)` freezes every connection on that loop: 12 × 10 = **120 req/s ceiling** (measured 106), with p99 of **5.5 s**. A single blocking JDBC call or `block()` in a WebFlux handler does exactly this in production.

### 2.2 Runnable: what `spring.threads.virtual.enabled=true` actually switches

<!-- run: javac cp=@p6web timeout=200 -->
```java
package demo.vt;

import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.tomcat.TomcatWebServer;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.core.task.AsyncTaskExecutor;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

public class VirtualThreadSwitch {
    @SpringBootConfiguration @EnableAutoConfiguration @EnableAsync @EnableScheduling static class App { }

    public static void main(String[] args) throws Exception {
        for (boolean virtual : new boolean[] {false, true}) {
            SpringApplication sa = new SpringApplication(App.class);
            sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
            sa.setDefaultProperties(Map.of("server.port", "0", "logging.level.root", "WARN", "spring.threads.virtual.enabled", String.valueOf(virtual),
                "spring.autoconfigure.exclude", "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration"));
            try (var ctx = sa.run()) {
                var tomcat = ((TomcatWebServer) ((WebServerApplicationContext) ctx).getWebServer()).getTomcat();
                Object tomcatExecutor = tomcat.getConnector().getProtocolHandler().getExecutor();
                AsyncTaskExecutor tasks = ctx.getBean("applicationTaskExecutor", AsyncTaskExecutor.class);
                boolean taskOnVirtual = CompletableFuture.supplyAsync(() -> Thread.currentThread().isVirtual(), tasks).get();
                System.out.printf("spring.threads.virtual.enabled=%-5s Tomcat executor=%s | applicationTaskExecutor=%s (runs on virtual: %s) | taskScheduler=%s%n",
                    virtual, tomcatExecutor.getClass().getSimpleName(), tasks.getClass().getSimpleName(), taskOnVirtual,
                    ctx.getBean("taskScheduler").getClass().getSimpleName());
            }
        }
    }
}
```

Output (verified):

```
spring.threads.virtual.enabled=false Tomcat executor=ThreadPoolExecutor | applicationTaskExecutor=ThreadPoolTaskExecutor (runs on virtual: false) | taskScheduler=ThreadPoolTaskScheduler
spring.threads.virtual.enabled=true  Tomcat executor=VirtualThreadExecutor | applicationTaskExecutor=SimpleAsyncTaskExecutor (runs on virtual: true) | taskScheduler=SimpleAsyncTaskScheduler
```

Consequences people miss:

* **`@Async` and `@Scheduled` move to virtual threads too, with no pool and no queue.** `SimpleAsyncTaskExecutor` starts a new virtual thread per task, and `spring.task.execution.simple.concurrency-limit` defaults to **none** (verified metadata). A burst of 50,000 `@Async` calls now really runs 50,000 concurrent tasks against your database. Set the concurrency limit, or guard the resource (`@ConcurrencyLimit`, a Resilience4j bulkhead, or the connection pool's own limit).
* `server.tomcat.threads.max` and `spring.task.execution.pool.*` **no longer have any effect** (their metadata says so). Capacity is now governed by **downstream resources**: Hikari's `maximumPoolSize`, HTTP-client connection pools, and rate limits of APIs. Size them deliberately, and expect `Connection is not available` errors instead of a queue in Tomcat ([5.1](../05-Persistence-JPA-Hibernate/01-JDBC-HikariCP-Connection-Pooling.md)).
* **Pinning:** since JDK 24 (JEP 491) `synchronized` no longer pins the carrier. Native frames (JNI, some drivers) and class initialization still do. Diagnose with the JFR event `jdk.VirtualThreadPinned` ([3.6](../03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md)).
* `ThreadLocal`-based caches (per-thread buffers, formatters) are rebuilt for **every** request on virtual threads. Prefer immutable shared objects or `ScopedValue`.

---

## 3. Reactive Streams and backpressure 🔥

The contract (Reactive Streams 1.0): `Publisher.subscribe(Subscriber)` → `onSubscribe(Subscription)` → the subscriber calls **`request(n)`** → the publisher may emit **at most n** `onNext` signals → then `onComplete` or `onError`. Demand flows **upstream**, data flows **downstream**. Operators sit in between and translate demand: `limitRate`, prefetching operators (`publishOn`, `flatMap`, `concatMap`), and buffering operators.

### 3.1 Runnable: demand, overflow, time-based sources, blocking detection, context propagation

<!-- run: javac cp=@p6web timeout=120 -->
```java
package demo.reactive;

import io.micrometer.context.ContextRegistry;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import org.reactivestreams.Subscription;
import reactor.core.publisher.*;
import reactor.core.scheduler.Schedulers;

public class Backpressure {
    static class ManualSubscriber<T> extends BaseSubscriber<T> {               // requests only what we tell it to
        final List<Object> got = new CopyOnWriteArrayList<>();
        final long initial;
        ManualSubscriber(long initial) { this.initial = initial; }
        protected void hookOnSubscribe(Subscription s) { request(initial); }
        protected void hookOnNext(T v) { got.add(v); }
        protected void hookOnError(Throwable t) { got.add("ERROR " + t.getClass().getSimpleName() + ": " + t.getMessage()); }
        protected void hookOnComplete() { got.add("COMPLETE"); }
    }

    static final ThreadLocal<String> REQUEST_ID = new ThreadLocal<>();

    public static void main(String[] args) throws Exception {
        // 1. demand travels upstream: limitRate(10) asks for 10, then replenishes 75% (8) at a time
        List<Long> requests = new ArrayList<>();
        Flux.range(1, 40).doOnRequest(requests::add).limitRate(10).blockLast();
        System.out.println("1. upstream saw requests: " + requests);

        // 2. publishOn uses a bounded queue: default prefetch = Queues.SMALL_BUFFER_SIZE
        requests.clear();
        Flux.range(1, 300).doOnRequest(requests::add).publishOn(Schedulers.single()).blockLast();
        System.out.println("2. publishOn prefetch: first request " + requests.getFirst() + ", then " + requests.subList(1, requests.size()));

        // 3. a producer that ignores demand (Flux.create), 1000 items pushed synchronously, subscriber requests 10, later 5 more
        for (FluxSink.OverflowStrategy strategy : FluxSink.OverflowStrategy.values()) {
            if (strategy == FluxSink.OverflowStrategy.IGNORE) continue;
            ManualSubscriber<Integer> sub = new ManualSubscriber<>(10);
            Flux.<Integer>create(sink -> { for (int i = 1; i <= 1000; i++) sink.next(i); sink.complete(); }, strategy).subscribe(sub);
            List<Object> first = List.copyOf(sub.got);
            sub.request(5);
            List<Object> later = sub.got.subList(first.size(), sub.got.size());
            System.out.printf("3. %-6s request(10) → %s…%s then %s | request(5) → %s%n", strategy,
                first.getFirst(), first.get(9), first.subList(10, first.size()), later);
        }

        // 4. a time-based source cannot slow down: Flux.interval errors when demand runs out
        ManualSubscriber<Long> slow = new ManualSubscriber<>(3);
        Flux.interval(Duration.ofMillis(5)).subscribe(slow);
        Thread.sleep(100);
        System.out.println("4. interval with request(3): " + slow.got);

        // 5. blocking inside a non-blocking scheduler is detected
        try {
            Mono.fromCallable(() -> Mono.delay(Duration.ofMillis(1)).block()).subscribeOn(Schedulers.parallel()).block();
        } catch (IllegalStateException e) {
            System.out.println("5. " + e.getMessage().replaceAll("parallel-\\d+", "parallel-N"));
        }

        // 6. ThreadLocals don't survive thread hops; Reactor Context does; automatic propagation restores registered ThreadLocals
        REQUEST_ID.set("req-42");
        String lost = Mono.fromCallable(() -> String.valueOf(REQUEST_ID.get())).subscribeOn(Schedulers.boundedElastic()).block();
        String viaContext = Mono.deferContextual(ctx -> Mono.just(ctx.<String>get("requestId")))
            .subscribeOn(Schedulers.boundedElastic()).contextWrite(c -> c.put("requestId", "req-42")).block();
        ContextRegistry.getInstance().registerThreadLocalAccessor("requestId", REQUEST_ID);
        Hooks.enableAutomaticContextPropagation();
        String restored = Mono.fromCallable(() -> String.valueOf(REQUEST_ID.get())).subscribeOn(Schedulers.boundedElastic())
            .contextWrite(c -> c.put("requestId", "req-42")).block();
        REQUEST_ID.remove();
        System.out.println("6. ThreadLocal after thread hop: " + lost + " | Reactor Context: " + viaContext
            + " | ThreadLocal with automatic context propagation: " + restored);
        Schedulers.shutdownNow();
    }
}
```

Output (verified):

```
1. upstream saw requests: [10, 8, 8, 8, 8, 8]
2. publishOn prefetch: first request 256, then [192]
3. ERROR  request(10) → 1…10 then [ERROR OverflowException: The receiver is overrun by more signals than expected (bounded queue...)] | request(5) → []
3. DROP   request(10) → 1…10 then [COMPLETE] | request(5) → []
3. LATEST request(10) → 1…10 then [] | request(5) → [1000, COMPLETE]
3. BUFFER request(10) → 1…10 then [] | request(5) → [11, 12, 13, 14, 15]
4. interval with request(3): [0, 1, 2, ERROR OverflowException: Could not emit tick 3 due to lack of requests (interval doesn't support small downstream requests that replenish slower than the ticks)]
5. block()/blockFirst()/blockLast() are blocking, which is not supported in thread parallel-N
6. ThreadLocal after thread hop: null | Reactor Context: req-42 | ThreadLocal with automatic context propagation: req-42
```

1. **`limitRate(10)`** caps upstream demand at 10, then **replenishes at 75%** (8 at a time) to keep the pipeline flowing without large bursts. Use it when a source would otherwise receive `Long.MAX_VALUE` (unbounded) demand.
2. **`publishOn` prefetches 256** (`Queues.SMALL_BUFFER_SIZE`) and replenishes 192 (75%). Every async boundary is a bounded queue. `flatMap` similarly defaults to `concurrency = 256` inner subscriptions, which is a hidden fan-out limit (or overload source) when inner publishers are HTTP calls. Set it explicitly (`flatMap(fn, 16)`).
3. **Push sources that ignore demand** (`Flux.create`, listeners and callbacks bridged into Reactor) need an **overflow strategy**:
   * `BUFFER` (the default) keeps everything: correct but unbounded memory;
   * `DROP` discards the excess (and here completed immediately);
   * `LATEST` keeps only the newest (`1000`), for gauges and UI state;
   * `ERROR` fails fast with `OverflowException`.
   For bounded buffering use `onBackpressureBuffer(maxSize, onOverflow, BufferOverflowStrategy)`.
4. **Time-based sources can't slow down.** `Flux.interval` signals an error when there is no demand for a tick. Downstream must keep up, or you add `onBackpressureDrop()`/`sample()`/`buffer(Duration)`.
5. **Blocking calls inside Reactor's non-blocking threads are rejected** by `block()`. Other blocking calls (JDBC, `Thread.sleep`, file I/O) are **not** detected: use BlockHound in tests, or offload with `subscribeOn(Schedulers.boundedElastic())`.
6. **`ThreadLocal`s (MDC, security context, trace IDs) are lost on thread hops.** The Reactor `Context` travels with the subscription. With Micrometer context-propagation, registered `ThreadLocalAccessor`s are restored around operators (`Hooks.enableAutomaticContextPropagation()`; in Boot set `spring.reactor.context-propagation=auto`, whose default is `limited`, verified). Tracing and logging across reactive and async code builds on this ([8.2 §2](../08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md#2-context-propagation-in-process-and-across-kafka-)).

| Need | Operator |
|---|---|
| Cap demand to a source (e.g. paging through an API) | `limitRate(n)`, `limitRequest(n)` |
| Bound parallel inner work | `flatMap(fn, concurrency)`, `flatMapSequential`, `concatMap` (concurrency 1) |
| Slow consumer of a push source | `onBackpressureBuffer(max, …)`, `onBackpressureDrop(cb)`, `onBackpressureLatest()` |
| Smooth bursts in time | `sample(Duration)`, `buffer(Duration)`, `window(…)`, `delayElements` |
| Offload blocking work | `publishOn/subscribeOn(Schedulers.boundedElastic())`, bounded by `reactor.schedulers.defaultBoundedElasticSize` (default 10 × cores) |

---

## 4. Choosing: MVC + virtual threads or WebFlux? ⚡

| Situation | Prefer | Why |
|---|---|---|
| CRUD and business services on JDBC/JPA, typical REST | **MVC + virtual threads** | Same throughput as reactive for I/O waits (§2.1) with plain code, stack traces and transactions ([5.4](../05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md)) |
| Streaming responses (SSE, NDJSON), WebSockets, many long-lived idle connections | **WebFlux** | Backpressure to the socket; low per-connection cost |
| API gateway or proxy, heavy fan-out with per-call timeouts and composition | WebFlux (Spring Cloud Gateway) or MVC + VT with structured concurrency | Both work; reactive composition is mature, and VT + `StructuredTaskScope` is simpler to read |
| CPU-bound endpoints | Either, with a bounded pool | Neither model creates CPU |
| Team new to reactive; heavy use of blocking libraries | MVC + VT | One blocking call on an event loop is an outage (§2.1, last row) |

The full decision framework, with numbers from Pillar 3, is in [00 §3](../00-Executive-Architecture-Map.md#3-paradigm-1--virtual-threads-vs-reactive-the-decision-quantified).

---

## 5. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| MVC p50 rises, then timeouts, CPU low | Tomcat workers all blocked on slow downstreams (200 cap) | `tomcat.threads.busy` = max; thread dump full of the same I/O frame | Virtual threads, plus timeouts and bulkheads on the downstream |
| After enabling VTs, DB errors `Connection is not available` | Concurrency no longer capped by Tomcat; Hikari is the new limit | `hikaricp.connections.pending` | Bound concurrency deliberately (semaphore, `@ConcurrencyLimit`, bulkhead); tune `connectionTimeout` |
| `@Async` storm after enabling VTs | `SimpleAsyncTaskExecutor` without a concurrency limit | Thread dumps with thousands of virtual threads | `spring.task.execution.simple.concurrency-limit` |
| WebFlux service: all requests stall for seconds | Blocking call on the event loop | Thread dump: `reactor-http-nio-*` in JDBC/socket/`sleep` frames; BlockHound in tests | Non-blocking driver, or `boundedElastic` offload |
| `OverflowException` / memory growth in reactive pipelines | Push source without an overflow strategy; unbounded `BUFFER` | Heap histogram of queues; Reactor metrics | Bounded buffers, `DROP`/`LATEST`, `limitRate` |
| Missing trace IDs or MDC in reactive or async logs | ThreadLocals lost on thread hops | Logs without IDs after `publishOn`/`flatMap` | context-propagation (`spring.reactor.context-propagation=auto`), Micrometer Tracing |
| Long JVM pauses with VTs pinned | Native frames or class-init holding a carrier | JFR `jdk.VirtualThreadPinned` | Upgrade drivers; JDK ≥ 24 for `synchronized` |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Do virtual threads make Spring MVC "as scalable as WebFlux"?</b></summary>

For I/O-bound request/response workloads, effectively yes: the thread no longer holds an OS thread while waiting, so the server isn't capped at the thread-pool size (measured: 3,300 vs 1,700 req/s, and p50 111 ms vs 235 ms, with 27 vs 226 platform threads). WebFlux still has advantages for streaming and backpressure, many idle long-lived connections, and reactive end-to-end pipelines. Virtual threads don't add backpressure, so you must bound downstream concurrency yourself.
</details>

<details><summary><b>Q2. 🔥 What happens if you call a blocking JDBC method in a WebFlux controller?</b></summary>

It runs on a Netty event-loop thread (one per core), and every other connection assigned to that loop waits until it returns. Throughput collapses to roughly loops ÷ blocking time (measured: 106 req/s, p99 5.5 s with 12 loops and 100 ms blocking). Use R2DBC/reactive clients, or wrap the call with `Mono.fromCallable(…).subscribeOn(Schedulers.boundedElastic())`. Detect it with BlockHound in tests.
</details>

<details><summary><b>Q3. ⚡ Explain backpressure in Reactor with an example of `request(n)`.</b></summary>

The subscriber signals demand with `request(n)`, and the publisher may only send n items. Operators translate demand: `limitRate(10)` requests 10 upstream and then 8 at a time (75% replenishment), and `publishOn` prefetches 256 and replenishes 192 (both verified). Sources that can't honour demand (UI events, `Flux.create` bridges, timers) need an overflow strategy: buffer, drop, latest or error.
</details>

<details><summary><b>Q4. ⚡ What changes in a Boot app when you set `spring.threads.virtual.enabled=true`?</b></summary>

Tomcat uses a `VirtualThreadExecutor` per request, the `applicationTaskExecutor` becomes a `SimpleAsyncTaskExecutor` running on virtual threads (`@Async`), and the scheduler becomes a `SimpleAsyncTaskScheduler` (all verified). Thread-pool sizing properties stop applying, and the concurrency limit defaults to none, so you must protect databases and downstream APIs explicitly.
</details>

<details><summary><b>Q5. 🧊 How do you propagate MDC or trace context through Reactor operators?</b></summary>

`ThreadLocal`s don't survive scheduler hops (verified: `null`). Put data in the Reactor `Context` (`contextWrite`, read with `deferContextual`). With Micrometer's context-propagation library, `ThreadLocalAccessor`s registered in the `ContextRegistry` are restored automatically around operators when automatic propagation is enabled (`Hooks.enableAutomaticContextPropagation()`; Boot: `spring.reactor.context-propagation=auto`). Micrometer Tracing uses this to keep trace IDs in logs.
</details>

<details><summary><b>Q6. ⚡ What's the default `flatMap` concurrency, and why does it matter?</b></summary>

256 inner subscriptions (`Queues.SMALL_BUFFER_SIZE`). A `flatMap` over 10,000 IDs that calls a downstream API therefore issues up to 256 concurrent calls, which can trip rate limits or exhaust connection pools. Pass an explicit concurrency (`flatMap(this::fetch, 16)`), or use `concatMap` for sequential processing.
</details>
