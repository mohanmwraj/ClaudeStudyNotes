# 02 · High-Throughput I/O in Beam: the Wait Anti-Pattern and the Async Batch RPC `DoFn`

> **Folder:** `07-Production-Java-Code-Blueprints/` · **File 2 of 4**
> **Anchors:** J. D. C. Little, *L = λW* (1961) · Dean & Barroso, *The Tail at Scale* (CACM 2013) · AWS Architecture
> Blog, *Exponential Backoff and Jitter* (M. Brooker, 2015) · Beam `GroupIntoBatches`, `RequestResponseIO` docs ·
> Folder 02, file 02 (bundles, `@FinishBundle`, `SharedResource`) · Folder 03, file 03 (idempotency keys).
> **Prev:** [01 · Stateful DoFn blueprint](01-beam-stateful-dofn-timers-onwindowexpiration-and-custom-coders.md) · **Next:**
> [03 · Flink KeyedProcessFunction, Async I/O, RocksDB](03-flink-keyedprocessfunction-async-io-and-rocksdb-config-setter.md)

---

## 0. The thesis

A `DoFn` that makes one synchronous RPC per element is capped at **1 / latency** elements per second per thread. No amount
of autoscaling fixes that efficiently: it multiplies threads, connections, and cost to buy concurrency that **one thread
could provide asynchronously**. Little's law says how much concurrency is needed. Batching says how to amortize per-call
overhead. Bounded in-flight requests protect the backend. Idempotency keys make retries safe. Bundle semantics say where
results can be emitted, and with which timestamps and windows.

---

## 1. First principles

### 1.1 Little's law for RPC-bound `DoFn`s

$$
N_{\text{in-flight}} = \lambda \cdot W
$$

| Target λ (elements/s) | RPC latency W | Required in-flight N | Sync threads needed (1 req/thread) | Async: 1 thread × N requests |
|-----------------------|---------------|----------------------|------------------------------------|------------------------------|
| 10,000 | 20 ms | 200 | 200 threads | ✅ |
| 200,000 | 20 ms | 4,000 | 4,000 threads (with stacks, context switches, connections) | ✅ (bounded by backend capacity) |
| 200,000 | 20 ms, batches of 100 | 40 batches | 40 threads | ✅ |

**Batching** divides the number of in-flight *requests* by the batch size $b$. **Async** decouples in-flight requests
from threads. Combined:

$$
N_{\text{requests in flight}} = \frac{\lambda \cdot W_{\text{batch}}}{b}
$$

### 1.2 The cost of the synchronous pattern

- **Threads:** Dataflow and Flink scale *workers*. A worker with T harness threads and sync RPCs maxes out at T / W
  elements/s. Scaling to the target λ needs λW / T workers, mostly idle and waiting on I/O.
- **Connections:** each thread or `DoFn` instance often opens its own pool (Folder 02, file 02 §3.2), so connection
  storms hit the backend on every autoscale.
- **Tail latency:** a slow p99 call blocks a whole thread for its duration, and the **bundle can't commit until every
  element finishes**, so p99 RPC latency becomes p50 bundle latency at large bundle sizes.

### 1.3 Batching trade-offs

| Batch size $b$ | Effect |
|----------------|--------|
| ↑ | fewer requests and less overhead per element; better backend efficiency |
| ↑ | **latency ↑**: wait to fill, plus a bigger request; the batch's latency is about its slowest item's |
| ↑ | larger blast radius per failure (one bad element can fail a batch, so the API needs per-item results) |

Bound waiting with a **max buffering duration**, and choose $b$ where marginal throughput gain flattens.

### 1.4 Backpressure and backend protection

An async client without limits turns a pipeline into a **DDoS on your own backend**: every element starts a request
immediately. A **semaphore** (max in-flight requests per process) gives two things:

- **Backend protection:** concurrency ≤ the limit across all threads of the worker.
- **Natural backpressure:** `acquire()` blocks `@ProcessElement` when the backend is saturated, which slows the bundle,
  which slows reading. No unbounded memory.

**Retries** need **exponential backoff with full jitter**, $\text{sleep} = \text{random}(0, \min(\text{cap},
\text{base} \cdot 2^{n}))$, to avoid synchronized retry storms, plus a retry budget. Only idempotent requests may be
retried (Folder 03, file 03 §3.2).

---

## 2. Where results may be emitted: bundle semantics recap

- **In `@ProcessElement`,** outputs inherit the **current** element's window (you may set timestamps within skew rules).
  You can't emit a *different* element's result into *its* window from here.
- **In `@FinishBundle`,** outputs need an **explicit timestamp and window** (`FinishBundleContext.output(value, ts,
  window)`, or the tagged overload for side outputs).
- **The bundle commits after `@FinishBundle`.** Every async request must be **completed** (or failed into a DLQ) before
  it returns. Returning early loses results. Throwing retries the whole bundle, so idempotency is required.

So a bundle-scoped async `DoFn` buffers `(element, timestamp, window)`, issues batched async calls during
`@ProcessElement` (bounded by the semaphore), and **drains all futures in `@FinishBundle`**, emitting each result with its
original timestamp and window.

For **streaming** pipelines with small bundles, prefer **`GroupIntoBatches`** (key- and time-scoped batching, independent
of bundle size). Its output is in-window by construction.

---

## 3. The anti-pattern

```java
// ANTI-PATTERN: one blocking call per element, client per element, no timeout, no batching, no limits, no idempotency.
class SyncEnrichFn extends DoFn<Event, Enriched> {
  @ProcessElement
  public void process(@Element Event e, OutputReceiver<Enriched> out) throws Exception {
    HttpClient client = HttpClient.newHttpClient();                                  // TLS handshake per element
    HttpResponse<String> r = client.send(HttpRequest.newBuilder(uri(e)).build(),      // blocks the thread; no timeout
        HttpResponse.BodyHandlers.ofString());
    out.output(parse(e, r.body()));                                                   // a 5xx throws → the whole bundle
  }                                                                                   // retries → duplicate side effects
}
// Throughput ≈ threads / 20 ms. The autoscaler adds workers, each opening hundreds of connections. Backend melts.
```

---

## 4. Blueprint A: `GroupIntoBatches` (streaming-first)

```java
package dev.l7.blueprints.io;

import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.GroupIntoBatches;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.WithKeys;
import org.apache.beam.sdk.util.ShardedKey;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.TypeDescriptors;
import org.joda.time.Duration;

public final class BatchedEnrichment {

  /**
   * Key by a coarse routing key (e.g., tenant or backend shard). GroupIntoBatches emits batches of ≤ 100 or after
   * 1 s, whichever comes first; withShardedKey lets the runner add parallel shards per key (no hot key).
   */
  public static PCollection<Enriched> enrich(PCollection<Event> events) {
    return events
        .apply("KeyByTenant", WithKeys.of((Event e) -> e.tenantId()).withKeyType(TypeDescriptors.strings()))
        .apply("Batch", GroupIntoBatches.<String, Event>ofSize(100)
            .withMaxBufferingDuration(Duration.standardSeconds(1))     // latency bound
            .withShardedKey())                                         // runner-managed sharding of hot keys
        .apply("CallBatchApi", ParDo.of(new DoFn<KV<ShardedKey<String>, Iterable<Event>>, Enriched>() {
          private transient EnrichmentClient client;

          @Setup
          public void setup() {
            client = EnrichmentClient.shared();                        // process-wide pooled client (§5.1)
          }

          @ProcessElement
          public void process(@Element KV<ShardedKey<String>, Iterable<Event>> batch, OutputReceiver<Enriched> out) {
            // One request per batch; outputs inherit the batch's window and timestamp.
            for (Enriched r : client.enrichBatch(batch.getValue())) {  // client enforces deadline + retries
              out.output(r);
            }
          }
        }));
  }
}
```

| | `GroupIntoBatches` | Bundle-scoped async (§5) |
|---|---|---|
| Batch size control | exact (size + max duration) | depends on runner bundles |
| Latency | ≤ max buffering duration | ≤ bundle duration |
| State cost | stateful (buffers in runner state; commits) | none (in memory) |
| Concurrency | parallel via keys and shards; a sync call per batch is often fine | async in-flight within a thread |
| Best for | streaming; predictable batches | batch, or high-λ streaming with large bundles |

---

## 5. Blueprint B: the bundle-scoped async batch RPC `DoFn`

### 5.1 Shared client, deadline, and concurrency limit

```java
package dev.l7.blueprints.io;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;

/**
 * Process-wide (static) resources: ONE HTTP/2 client and ONE concurrency limit per worker JVM, shared by every DoFn
 * instance and bundle thread. That bounds backend load regardless of how many instances the runner creates.
 */
public final class AsyncBatchClient {

  private static final int MAX_IN_FLIGHT_REQUESTS = 256;               // per worker JVM: size from backend capacity
  private static final Semaphore IN_FLIGHT = new Semaphore(MAX_IN_FLIGHT_REQUESTS);
  private static final HttpClient HTTP = HttpClient.newBuilder()
      .version(HttpClient.Version.HTTP_2)                              // multiplexed streams: few connections
      .connectTimeout(Duration.ofSeconds(2))
      .executor(Executors.newFixedThreadPool(8))                       // response handling threads
      .build();

  private AsyncBatchClient() {}

  /** Blocks if MAX_IN_FLIGHT_REQUESTS are outstanding: natural backpressure into @ProcessElement. */
  public static void acquirePermit() throws InterruptedException {
    IN_FLIGHT.acquire();
  }

  public static void releasePermit() {
    IN_FLIGHT.release();
  }

  public static CompletableFuture<HttpResponse<String>> post(URI uri, String jsonBody, String idempotencyKey,
                                                             Duration deadline) {
    HttpRequest req = HttpRequest.newBuilder(uri)
        .timeout(deadline)                                             // per-request deadline: never wait forever
        .header("Content-Type", "application/json")
        .header("Idempotency-Key", idempotencyKey)                     // retries are safe server-side
        .POST(HttpRequest.BodyPublishers.ofString(jsonBody))
        .build();
    return HTTP.sendAsync(req, HttpResponse.BodyHandlers.ofString());
  }
}
```

### 5.2 The `DoFn`

```java
package dev.l7.blueprints.io;

import java.net.URI;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import org.apache.beam.sdk.metrics.Counter;
import org.apache.beam.sdk.metrics.Distribution;
import org.apache.beam.sdk.metrics.Metrics;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
import org.apache.beam.sdk.values.TupleTag;
import org.joda.time.Instant;

/**
 * Bundle-scoped async batching:
 *  - buffer (element, timestamp, window); every BATCH_SIZE elements issue ONE async batch call (bounded by the
 *    process-wide semaphore: backpressure),
 *  - retry retryable failures with exponential backoff + full jitter (idempotency keys make that safe),
 *  - in @FinishBundle, wait for ALL futures (bounded by a bundle deadline), then emit each result with its ORIGINAL
 *    timestamp and window; exhausted failures go to a dead-letter output.
 */
public final class AsyncBatchEnrichFn extends DoFn<Event, Enriched> {

  public static final TupleTag<Enriched> ENRICHED = new TupleTag<>() {};
  public static final TupleTag<FailedEvent> FAILED = new TupleTag<>() {};

  private static final int BATCH_SIZE = 100;
  private static final int MAX_ATTEMPTS = 5;
  private static final Duration REQUEST_DEADLINE = Duration.ofSeconds(2);
  private static final long BUNDLE_DEADLINE_SECONDS = 120;
  private static final long BACKOFF_BASE_MS = 100;
  private static final long BACKOFF_CAP_MS = 5_000;

  private final URI endpoint;

  private final Distribution batchLatencyMs = Metrics.distribution(AsyncBatchEnrichFn.class, "batch_latency_ms");
  private final Distribution batchSize = Metrics.distribution(AsyncBatchEnrichFn.class, "batch_size");
  private final Counter retries = Metrics.counter(AsyncBatchEnrichFn.class, "retries");
  private final Counter deadLettered = Metrics.counter(AsyncBatchEnrichFn.class, "dead_lettered");
  // Convention used by Beam GCP IOs so the Dataflow autoscaler can discount backend-throttled time ⚠ verify.
  private final Counter throttlingMsecs = Metrics.counter(AsyncBatchEnrichFn.class, "throttling-msecs");

  private record Pending(Event event, Instant timestamp, BoundedWindow window) {}

  private record BatchResult(List<Pending> items, List<Enriched> results, Throwable failure) {}

  private transient List<Pending> buffer;
  private transient List<CompletableFuture<BatchResult>> inFlight;

  public AsyncBatchEnrichFn(URI endpoint) {
    this.endpoint = endpoint;
  }

  @StartBundle
  public void startBundle() {
    buffer = new ArrayList<>(BATCH_SIZE);
    inFlight = new ArrayList<>();
  }

  @ProcessElement
  public void process(@Element Event e, @Timestamp Instant ts, BoundedWindow window) throws InterruptedException {
    buffer.add(new Pending(e, ts, window));
    if (buffer.size() >= BATCH_SIZE) {
      dispatch();
    }
  }

  @FinishBundle
  public void finishBundle(FinishBundleContext c) throws Exception {
    if (!buffer.isEmpty()) {
      dispatch();
    }
    CompletableFuture.allOf(inFlight.toArray(CompletableFuture[]::new))
        .get(BUNDLE_DEADLINE_SECONDS, TimeUnit.SECONDS);               // bounded: a hung backend fails the bundle
    for (CompletableFuture<BatchResult> f : inFlight) {
      BatchResult r = f.join();
      if (r.failure() == null) {
        for (int i = 0; i < r.items().size(); i++) {
          Pending p = r.items().get(i);
          c.output(ENRICHED, r.results().get(i), p.timestamp(), p.window());   // original timestamp AND window
        }
      } else {
        for (Pending p : r.items()) {
          deadLettered.inc();
          c.output(FAILED, new FailedEvent(p.event(), String.valueOf(r.failure())), p.timestamp(), p.window());
        }
      }
    }
    inFlight.clear();
  }

  // -------------------------------------------------------------------------------------------------------------

  private void dispatch() throws InterruptedException {
    List<Pending> batch = buffer;
    buffer = new ArrayList<>(BATCH_SIZE);
    batchSize.update(batch.size());
    AsyncBatchClient.acquirePermit();                                  // blocks when saturated (backpressure)
    long start = System.nanoTime();
    CompletableFuture<BatchResult> f = callWithRetry(batch, 1)
        .handle((results, err) -> new BatchResult(batch, results, err))
        .whenComplete((ignored, err) -> {
          AsyncBatchClient.releasePermit();
          batchLatencyMs.update(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start));
        });
    inFlight.add(f);
  }

  /** Thrown for non-retryable outcomes so that no retry layer ever retries them. */
  static final class NonRetryableException extends RuntimeException {
    NonRetryableException(String message) {
      super(message);
    }
  }

  private CompletableFuture<List<Enriched>> callWithRetry(List<Pending> batch, int attempt) {
    String idempotencyKey = batchKey(batch);                           // deterministic: same batch ⇒ same key
    // handle() classifies ONLY this attempt's outcome. A downstream retry chain's failure is never re-caught here,
    // so retries don't multiply across attempts.
    return AsyncBatchClient.post(endpoint, toJson(batch), idempotencyKey, REQUEST_DEADLINE)
        .handle((resp, err) -> {
          if (err != null) {                                           // transport error / timeout
            return attempt >= MAX_ATTEMPTS || isPermanent(err)
                ? CompletableFuture.<List<Enriched>>failedFuture(err)
                : retryLater(batch, attempt, false);
          }
          if (resp.statusCode() == 200) {
            return CompletableFuture.completedFuture(parse(batch, resp));
          }
          boolean retryable = resp.statusCode() == 429 || resp.statusCode() >= 500;
          if (!retryable || attempt >= MAX_ATTEMPTS) {
            return CompletableFuture.<List<Enriched>>failedFuture(
                new NonRetryableException("HTTP " + resp.statusCode() + " after " + attempt + " attempt(s)"));
          }
          return retryLater(batch, attempt, resp.statusCode() == 429);
        })
        .thenCompose(f -> f);                                          // flatten CompletableFuture<CompletableFuture<…>>
  }

  private CompletableFuture<List<Enriched>> retryLater(List<Pending> batch, int attempt, boolean throttled) {
    retries.inc();
    long cap = Math.min(BACKOFF_CAP_MS, BACKOFF_BASE_MS << Math.min(attempt, 20));
    long sleepMs = ThreadLocalRandom.current().nextLong(cap + 1);       // full jitter
    if (throttled) {
      throttlingMsecs.inc(sleepMs);
    }
    return CompletableFuture
        .supplyAsync(() -> null, CompletableFuture.delayedExecutor(sleepMs, TimeUnit.MILLISECONDS))
        .thenCompose(ignored -> callWithRetry(batch, attempt + 1));
  }

  // ---- domain plumbing (serialize, parse, classify) ----

  private static String batchKey(List<Pending> batch) {
    StringBuilder sb = new StringBuilder();
    for (Pending p : batch) {
      sb.append(p.event().eventId()).append(',');
    }
    return Integer.toHexString(sb.toString().hashCode()) + "-" + batch.size();   // production: SHA-256 of ids
  }

  private static String toJson(List<Pending> batch) {
    StringBuilder sb = new StringBuilder("{\"items\":[");
    for (int i = 0; i < batch.size(); i++) {
      if (i > 0) {
        sb.append(',');
      }
      sb.append("{\"id\":\"").append(batch.get(i).event().eventId()).append("\"}");
    }
    return sb.append("]}").toString();
  }

  private static List<Enriched> parse(List<Pending> batch, HttpResponse<String> resp) {
    // Production: parse per-item results; map item-level errors to FAILED instead of failing the whole batch.
    List<Enriched> out = new ArrayList<>(batch.size());
    for (Pending p : batch) {
      out.add(new Enriched(p.event(), resp.body().length()));
    }
    return out;
  }

  private static boolean isPermanent(Throwable err) {
    Throwable root = (err instanceof java.util.concurrent.CompletionException && err.getCause() != null)
        ? err.getCause() : err;
    return root instanceof NonRetryableException
        || root instanceof IllegalArgumentException;                   // e.g., serialization bugs: don't retry
  }
}
```

```java
// Wiring with a dead-letter path (never let failures retry forever and pin the watermark):
PCollectionTuple results = events.apply("AsyncEnrich",
    ParDo.of(new AsyncBatchEnrichFn(URI.create("https://enrich.internal/v1/batch")))
        .withOutputTags(AsyncBatchEnrichFn.ENRICHED, TupleTagList.of(AsyncBatchEnrichFn.FAILED)));
results.get(AsyncBatchEnrichFn.FAILED).apply("DLQ", new DeadLetterSink("enrich"));
```

`Event`, `Enriched`, `FailedEvent`, `EnrichmentClient`, and `DeadLetterSink` are domain classes. Give `Event` and
`Enriched` explicit coders or schemas (Folder 02, file 03).

### 5.3 Why each line is there

| Element | Failure it prevents |
|---------|---------------------|
| Static `HttpClient` (HTTP/2) | connection storms (instances ≈ stages × threads) |
| Static semaphore | backend overload; unbounded memory from unbounded futures |
| Batch size + bundle flush | per-request overhead; tiny requests |
| Per-request deadline | hung calls pinning bundles (and the watermark) |
| Bundle deadline in `@FinishBundle` | a bundle waiting forever |
| Backoff with full jitter | synchronized retry storms (thundering herd) |
| Idempotency key per batch | duplicate side effects on retries and bundle replays |
| Original timestamp **and window** on output | the global-window corruption anti-pattern (Folder 02, file 02 §7.1) |
| Dead-letter output | poison records retrying forever (Folder 01, file 02, W4) |
| `throttling-msecs` counter | autoscaler scaling up against a throttled backend |

---

## 6. Caching enrichment lookups

When many elements request the same keys (user profiles, product metadata), a **process-wide cache** with TTL often beats
batching:

- **Hit ratio** $h$ reduces backend calls to $(1 - h)\lambda$.
- **Staleness** is bounded by TTL. Make it explicit in the contract.
- **Memory** is bounded by max entries × entry size, shared across instances (static), never per instance.

Use a proven cache library (e.g., Caffeine with `maximumSize` and `expireAfterWrite`) held in a static, shared field. For
cross-worker caching, Beam's request/response utilities can integrate external caches (Redis) ⚠ verify the
`RequestResponseIO` cache features for your version.

---

## 7. Production failure modes and P99 debugging

| ID | Failure | Signature | Root cause | Fix |
|----|---------|-----------|------------|-----|
| I1 | **I/O-bound throughput ceiling** | low CPU, high latency per element; autoscaling adds workers with little gain | synchronous per-element RPC | async + batching (§5), `GroupIntoBatches` (§4) |
| I2 | **Backend meltdown on autoscale** | backend 429/5xx spikes when workers scale out | unbounded concurrency; per-instance pools | static semaphore; shared client; rate limits |
| I3 | **Stuck bundles** | "Operation ongoing …" logs; watermark pinned | no deadlines | per-request and per-bundle deadlines |
| I4 | **Duplicate side effects** | backend shows repeats after retries or bundle failures | non-idempotent calls | idempotency keys; deterministic batch keys |
| I5 | **Wrong windows** | downstream windowed aggregates miss data | `@FinishBundle` outputs into the global window | original `(timestamp, window)` |
| I6 | **Retry storms** | synchronized retry spikes | no jitter; unlimited retries | full jitter; retry budgets; DLQ |
| I7 | **Tiny batches in streaming** | batch-size metric ~1–3 | bundle-scoped batching with small streaming bundles | `GroupIntoBatches` with max buffering duration |
| I8 | **Hot-key batching** | one tenant's batches serialize | `GroupIntoBatches` on a skewed key | `withShardedKey()`; finer routing keys |
| I9 | **Memory growth** | heap grows with in-flight futures | no limit on outstanding batches per bundle | the semaphore bounds outstanding batches; smaller bundles |

---

## 8. FAANG L7 bar-raiser Q&A chains

### Q1 · "Each element needs a 20 ms lookup. You need 200k elements/s. Design the step."

**L5 textbook answer.** Add workers and threads until throughput is reached.

**Why L5 breaks at petabyte scale.** Sync calls need λW = 4,000 concurrent threads, which means a fleet of mostly idle
workers, 4,000+ connections to the backend, and a connection storm at each autoscale. Tail latency also gates bundle
commits.

**L7 principal defense.**

1. **Little's law:** 4,000 in flight. With batches of 100, that's 40 batch requests in flight. Async decouples those from
   threads.
2. **Shared HTTP/2 client** and a **process-wide semaphore** sized from backend capacity, which also gives backpressure.
3. **Deadlines, backoff with jitter, idempotency keys, DLQ.**
4. **Emit with original timestamps and windows** in `@FinishBundle`. In streaming, use `GroupIntoBatches` with sharded
   keys.
5. **A cache** if keys repeat. Measure the hit ratio.
6. **Validate** with batch-latency and batch-size distributions and backend error rates.

### Q2 · "Why not just set `numberOfWorkerHarnessThreads` to 1,000?"

**L5 textbook answer.** More threads means more concurrency, so it should work.

**Why L5 breaks.** Threads cost memory (stacks), context switches, and per-thread DoFn instances with their resources
(Folder 02, file 02 §3.2). The backend sees connection explosions, and GC and scheduling overhead dominate. It also
doesn't fix tail latency gating bundle commits.

**L7 principal defense.** Concurrency should come from **async I/O within threads**, bounded by a semaphore. Threads match
CPU work. Size harness threads for CPU, and size in-flight requests by Little's law within the backend's limits.

### Q3 · "Bundle-scoped batching or `GroupIntoBatches`?"

**L5 textbook answer.** `GroupIntoBatches` is the Beam way.

**Why L5 breaks.** It depends on bundle shapes and latency. In batch pipelines bundles are large, so bundle-scoped async
gives big batches with no state cost. In streaming, bundles are small, so bundle batching degenerates and
`GroupIntoBatches` gives controlled batches at the cost of state and commits.

**L7 principal defense.**

| Context | Choice | Why |
|---------|--------|-----|
| Batch | bundle-scoped async (§5) | big bundles, no state |
| Streaming | `GroupIntoBatches.ofSize(n).withMaxBufferingDuration(d).withShardedKey()` | predictable batch size and latency; hot keys sharded |

Measure the batch-size distribution, because the runner's bundle sizes decide it.

### Q4 · "How do you make retries of an external enrichment call safe?"

**L5 textbook answer.** Retry with backoff.

**Why L5 breaks.** Backoff prevents storms, not duplicates. Bundle retries replay whole bundles, re-sending requests that
already succeeded.

**L7 principal defense.**

- **Idempotency keys derived from committed data:** deterministic per element or batch (event IDs, Folder 03, file 03
  §3.2).
- **Server-side dedup** by key.
- **Classify errors:** retryable (429/5xx/timeouts) vs. permanent (4xx validation).
- **Retry budgets** and full jitter.
- **A DLQ** after exhaustion.
- **For read-only lookups,** idempotency is natural. For writes, it's mandatory.

---

## 9. Invariants checklist

1. **Concurrency = λ × W (Little).** Get it from async I/O, not threads.
2. **Batch to amortize overhead,** bounded by a max buffering duration.
3. **One shared client and one concurrency limit per process.** The semaphore is backpressure.
4. **Deadlines everywhere:** per request and per bundle.
5. **Retries need idempotency keys, full jitter, budgets, and a DLQ.**
6. **Emit with original timestamps and windows** from `@FinishBundle`.
7. **In streaming, prefer `GroupIntoBatches` with sharded keys.**

---

## 10. References

- J. D. C. Little. *A Proof for the Queuing Formula L = λW.* Operations Research 9(3), 1961.
- J. Dean, L. A. Barroso. *The Tail at Scale.* CACM 56(2), 2013.
- M. Brooker. *Exponential Backoff and Jitter.* AWS Architecture Blog, 2015.
- Apache Beam: `GroupIntoBatches` (incl. `withShardedKey`), `DoFn.FinishBundleContext`, `RequestResponseIO` ⚠ verify,
  *Common pipeline patterns: calling external services*.
- Folder 02, file 02 (bundles, lifecycle, `SharedResource`); Folder 03, file 03 (idempotency).

**Next →** [03 · Flink KeyedProcessFunction, Async I/O, and the RocksDB options factory](03-flink-keyedprocessfunction-async-io-and-rocksdb-config-setter.md)
