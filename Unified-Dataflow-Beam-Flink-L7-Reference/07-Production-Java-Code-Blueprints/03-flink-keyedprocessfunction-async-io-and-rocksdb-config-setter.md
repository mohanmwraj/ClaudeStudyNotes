# 03 · Flink `KeyedProcessFunction`, Async I/O, and the RocksDB Options Factory ("Config Setter")

> **Folder:** `07-Production-Java-Code-Blueprints/` · **File 3 of 4**
> **Anchors:** Flink docs *Process Function*, *Asynchronous I/O for External Data Access* (incl. retry support, FLIP-232),
> *State TTL*, *RocksDB state backend* · Kafka Streams `RocksDBConfigSetter` (for contrast) · Folder 04 (checkpoints,
> RocksDB, flow control) · Folder 05, file 03 (TTL) · Folder 06, file 02 (transactional sinks).
> **Prev:** [02 · Async batch RPC in Beam](02-beam-high-throughput-io-wait-antipattern-async-batch-rpc-dofn.md) · **Next:**
> [04 · Schema evolution, DLQs, drain/update lifecycle](04-schema-evolution-dead-letter-routing-and-drain-update-lifecycle.md)

---

## 0. What this file delivers

A sub-second **fraud and deduplication engine** on Flink:

1. **`KeyedProcessFunction`** per card, with:
   - exact dedup (`MapState` + TTL via the RocksDB compaction filter);
   - per-minute velocity buckets (`MapState`, cleaned by **event-time timers**);
   - an impossible-travel rule (`ValueState`);
   - a side output for duplicates.
2. **`AsyncDataStream.unorderedWaitWithRetry`** calling an external risk-scoring service, with capacity sized by Little's
   law, a timeout fallback, and exponential-backoff retries **on fallback results**, so the job never fails because the
   scorer is down.
3. **A RocksDB options factory** tuned for point lookups, plus the Kafka Streams `RocksDBConfigSetter` equivalent for
   contrast.
4. **Tests** with Flink's process-function test harness.

---

## 1. Mechanics recap

| Mechanism | Rule | Source |
|-----------|------|--------|
| Keyed state | per key, single-threaded per key; layout matters (`MapState` entries vs. big values) | Folder 04, file 02 |
| Event-time timers | fire when the watermark ≥ timer; deduplicated per (key, timestamp); stored in RocksDB | Folder 01, file 02 |
| TTL | processing time; 8 B per value; cleaned on compaction; format-changing | Folder 05, file 03 §5 |
| Async I/O | `capacity` = max in-flight per subtask (size it as λ × W); **unordered** mode still treats watermarks as barriers; in-flight inputs are **checkpointed and re-issued** after restore | Flink docs; Folder 07, file 02 §1.1 |
| Exactly-once output | transactional sink aligned to checkpoints, or idempotent sinks | Folder 06, file 02 |

**Async I/O re-issues requests after recovery.** The operator snapshots its queue of in-flight *inputs*. After a
failure, those requests are sent again, so scoring calls must be idempotent (or harmless to repeat).

---

## 2. The naive version

```java
// ANTI-PATTERN: synchronous HTTP inside processElement, ValueState<List> history, no TTL, no timers, no uid.
public class NaiveFraud extends KeyedProcessFunction<String, Txn, Decision> {
  private transient ValueState<List<Txn>> history;                      // grows forever; full rewrite per txn

  @Override
  public void processElement(Txn t, Context ctx, Collector<Decision> out) throws Exception {
    List<Txn> h = Optional.ofNullable(history.value()).orElseGet(ArrayList::new);
    if (h.stream().anyMatch(x -> x.txnId().equals(t.txnId()))) return;  // O(n) dedup per element
    h.add(t);
    history.update(h);
    long recent = h.stream().filter(x -> x.eventTimeMillis() > t.eventTimeMillis() - 300_000).count();
    String score = httpClient.send(req(t, recent), ofString()).body();  // blocks the task thread: backpressure to Kafka
    out.collect(Decision.of(t, score));
  }
}
```

---

## 3. The production blueprint

### 3.1 Domain types

```java
package dev.l7.blueprints.fraud;

public record Txn(String txnId, String cardId, String merchantId, long amountCents, long eventTimeMillis, String country) {}

public record Candidate(Txn txn, long velocity5m, boolean impossibleTravel) {}

public record Decision(String txnId, String cardId, String verdict, double score, String reason, boolean fallback) {
  public static Decision fallback(Candidate c, String why) {
    boolean risky = c.impossibleTravel() || c.velocity5m() > 10;
    return new Decision(c.txn().txnId(), c.txn().cardId(), risky ? "REVIEW" : "APPROVE", -1.0, "fallback:" + why, true);
  }
}
```

### 3.2 `KeyedProcessFunction`: dedup, velocity, impossible travel

```java
package dev.l7.blueprints.fraud;

import java.time.Duration;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.state.MapState;
import org.apache.flink.api.common.state.MapStateDescriptor;
import org.apache.flink.api.common.state.StateTtlConfig;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.metrics.Counter;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.util.OutputTag;

/**
 * Keyed by cardId. Per card:
 *  - recentTxnIds: MapState<txnId, true> with 1 h TTL (compaction filter): exact dedup, O(1) point lookup
 *  - minuteBuckets: MapState<minute, count>: velocity over the last 5 event-time minutes (5 point lookups);
 *    each bucket is removed by an EVENT-TIME timer (deterministic under replay), TTL as a backstop
 *  - last location: two tiny ValueStates for the impossible-travel rule
 */
public final class CardRiskFeatures extends KeyedProcessFunction<String, Txn, Candidate> {

  public static final OutputTag<Txn> DUPLICATES = new OutputTag<>("duplicates") {};

  private static final long MINUTE = 60_000L;
  private static final int VELOCITY_MINUTES = 5;
  private static final long TRAVEL_WINDOW_MS = Duration.ofMinutes(10).toMillis();

  private transient MapState<String, Boolean> recentTxnIds;
  private transient MapState<Long, Long> minuteBuckets;
  private transient ValueState<String> lastCountry;
  private transient ValueState<Long> lastTs;
  private transient Counter duplicates;

  @Override
  public void open(OpenContext ctx) {
    StateTtlConfig dedupTtl = StateTtlConfig.newBuilder(Duration.ofHours(1))
        .setUpdateType(StateTtlConfig.UpdateType.OnCreateAndWrite)
        .setStateVisibility(StateTtlConfig.StateVisibility.NeverReturnExpired)
        .cleanupInRocksdbCompactFilter(1_000)
        .build();
    StateTtlConfig backstopTtl = StateTtlConfig.newBuilder(Duration.ofDays(2))
        .setUpdateType(StateTtlConfig.UpdateType.OnCreateAndWrite)
        .cleanupInRocksdbCompactFilter(1_000)
        .build();

    MapStateDescriptor<String, Boolean> dedupDesc = new MapStateDescriptor<>("recent-txn-ids", String.class, Boolean.class);
    dedupDesc.enableTimeToLive(dedupTtl);
    MapStateDescriptor<Long, Long> bucketsDesc = new MapStateDescriptor<>("minute-buckets", Long.class, Long.class);
    bucketsDesc.enableTimeToLive(backstopTtl);
    ValueStateDescriptor<String> countryDesc = new ValueStateDescriptor<>("last-country", String.class);
    countryDesc.enableTimeToLive(backstopTtl);
    ValueStateDescriptor<Long> tsDesc = new ValueStateDescriptor<>("last-ts", Long.class);
    tsDesc.enableTimeToLive(backstopTtl);

    recentTxnIds = getRuntimeContext().getMapState(dedupDesc);
    minuteBuckets = getRuntimeContext().getMapState(bucketsDesc);
    lastCountry = getRuntimeContext().getState(countryDesc);
    lastTs = getRuntimeContext().getState(tsDesc);
    duplicates = getRuntimeContext().getMetricGroup().counter("duplicates");
  }

  @Override
  public void processElement(Txn t, Context ctx, Collector<Candidate> out) throws Exception {
    if (recentTxnIds.contains(t.txnId())) {                         // exact dedup (at-least-once upstream retries)
      duplicates.inc();
      ctx.output(DUPLICATES, t);
      return;
    }
    recentTxnIds.put(t.txnId(), Boolean.TRUE);

    long minute = Math.floorDiv(t.eventTimeMillis(), MINUTE);
    Long current = minuteBuckets.get(minute);
    minuteBuckets.put(minute, (current == null ? 0L : current) + 1);
    // Remove this bucket once it can no longer contribute to any 5-minute velocity (event time, deterministic).
    // Timers are deduplicated per (key, timestamp), so re-registering for the same bucket is free.
    ctx.timerService().registerEventTimeTimer((minute + VELOCITY_MINUTES + 1) * MINUTE);

    long velocity = 0;
    for (long m = minute - (VELOCITY_MINUTES - 1); m <= minute; m++) {
      Long c = minuteBuckets.get(m);                                // 5 point lookups, no iteration
      velocity += c == null ? 0 : c;
    }

    boolean impossibleTravel = false;
    String prevCountry = lastCountry.value();
    Long prevTs = lastTs.value();
    if (prevCountry != null && prevTs != null && !prevCountry.equals(t.country())
        && Math.abs(t.eventTimeMillis() - prevTs) < TRAVEL_WINDOW_MS) {
      impossibleTravel = true;
    }
    if (prevTs == null || t.eventTimeMillis() >= prevTs) {          // only move "last seen" forward in event time
      lastCountry.update(t.country());
      lastTs.update(t.eventTimeMillis());
    }

    out.collect(new Candidate(t, velocity, impossibleTravel));
  }

  @Override
  public void onTimer(long timestamp, OnTimerContext ctx, Collector<Candidate> out) throws Exception {
    long expiredMinute = timestamp / MINUTE - (VELOCITY_MINUTES + 1);
    minuteBuckets.remove(expiredMinute);                            // bounded state: ≤ ~6 buckets per active card
  }
}
```

### 3.3 Async scoring with timeout fallback and retries

```java
package dev.l7.blueprints.fraud;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.metrics.Counter;
import org.apache.flink.streaming.api.functions.async.ResultFuture;
import org.apache.flink.streaming.api.functions.async.RichAsyncFunction;

/**
 * Never fails the job because the scorer is slow or down:
 *  - transport errors → complete with a rule-based FALLBACK decision (marked fallback=true),
 *  - the retry strategy (wiring below) retries while the result is a fallback, with exponential backoff,
 *  - timeout() → final fallback when the overall async timeout elapses.
 * Requests carry the txnId as an idempotency key: async inputs are re-issued after recovery.
 */
public final class RiskScoringAsyncFn extends RichAsyncFunction<Candidate, Decision> {

  private static final HttpClient HTTP = HttpClient.newBuilder()          // one per TaskManager JVM (static)
      .version(HttpClient.Version.HTTP_2)
      .connectTimeout(Duration.ofSeconds(1))
      .build();

  private final URI scorer;
  private transient Counter fallbacks;
  private transient Counter timeouts;

  public RiskScoringAsyncFn(URI scorer) {
    this.scorer = scorer;
  }

  @Override
  public void open(OpenContext ctx) {
    fallbacks = getRuntimeContext().getMetricGroup().counter("scoring_fallbacks");
    timeouts = getRuntimeContext().getMetricGroup().counter("scoring_timeouts");
  }

  @Override
  public void asyncInvoke(Candidate c, ResultFuture<Decision> result) {
    HttpRequest req = HttpRequest.newBuilder(scorer)
        .timeout(Duration.ofMillis(300))                                  // per attempt, well under the async timeout
        .header("Content-Type", "application/json")
        .header("Idempotency-Key", c.txn().txnId())
        .POST(HttpRequest.BodyPublishers.ofString(toJson(c)))
        .build();
    HTTP.sendAsync(req, HttpResponse.BodyHandlers.ofString())
        .whenComplete((resp, err) -> {
          if (err != null || resp.statusCode() != 200) {
            fallbacks.inc();
            result.complete(List.of(Decision.fallback(c, err != null ? err.getClass().getSimpleName()
                                                                    : "http_" + resp.statusCode())));
          } else {
            result.complete(List.of(parse(c, resp.body())));
          }
        });
  }

  @Override
  public void timeout(Candidate c, ResultFuture<Decision> result) {
    timeouts.inc();
    result.complete(List.of(Decision.fallback(c, "timeout")));            // never completeExceptionally: no job failure
  }

  private static String toJson(Candidate c) {
    return "{\"txnId\":\"" + c.txn().txnId() + "\",\"amount\":" + c.txn().amountCents()
        + ",\"velocity5m\":" + c.velocity5m() + ",\"impossibleTravel\":" + c.impossibleTravel() + "}";
  }

  private static Decision parse(Candidate c, String body) {
    double score = Double.parseDouble(body.trim());                       // production: a real JSON parser + schema
    String verdict = score > 0.9 ? "DECLINE" : score > 0.6 ? "REVIEW" : "APPROVE";
    return new Decision(c.txn().txnId(), c.txn().cardId(), verdict, score, "model", false);
  }
}
```

### 3.4 Job wiring: watermarks, uids, async capacity, transactional output

```java
package dev.l7.blueprints.fraud;

import java.net.URI;
import java.time.Duration;
import java.util.concurrent.TimeUnit;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.streaming.api.datastream.AsyncDataStream;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.util.retryable.AsyncRetryStrategies;

public final class FraudGuardJob {

  public static void main(String[] args) throws Exception {
    StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
    // Checkpointing, state backend, and the RocksDB options factory come from config.yaml (§3.5).

    DataStream<Txn> txns = env.fromSource(KafkaSources.txns(args[0]),
            WatermarkStrategy.<Txn>forBoundedOutOfOrderness(Duration.ofSeconds(5))
                .withTimestampAssigner((t, ts) -> t.eventTimeMillis())
                .withIdleness(Duration.ofMinutes(1)),
            "txns")
        .uid("txns-source-v1");

    SingleOutputStreamOperator<Candidate> features = txns
        .keyBy(Txn::cardId)
        .process(new CardRiskFeatures())
        .uid("card-risk-features-v1")
        .name("card-risk-features");

    features.getSideOutput(CardRiskFeatures.DUPLICATES)
        .sinkTo(KafkaSinks.duplicatesAuditTopic(args[0]))
        .uid("duplicates-audit-v1");

    // Capacity per subtask from Little's law: e.g., 2,000 req/s per subtask × 50 ms ≈ 100 in flight → 200 with headroom.
    // Retry while the result is a FALLBACK (scorer down or slow); the last fallback is emitted after max attempts.
    AsyncRetryStrategies.ExponentialBackoffDelayRetryStrategy<Decision> retry =
        new AsyncRetryStrategies.ExponentialBackoffDelayRetryStrategyBuilder<Decision>(3, 50L, 400L, 2.0)
            .ifResult(results -> results.stream().anyMatch(Decision::fallback))
            .build();

    SingleOutputStreamOperator<Decision> decisions = AsyncDataStream
        .unorderedWaitWithRetry(features, new RiskScoringAsyncFn(URI.create("https://risk.internal/v1/score")),
            1_000, TimeUnit.MILLISECONDS, 200, retry)
        .uid("risk-scoring-async-v1")
        .name("risk-scoring-async");

    decisions
        .sinkTo(KafkaSinks.decisionsExactlyOnce(args[0], "fraud-guard-decisions-v1"))   // Folder 06, file 02 §6.2
        .uid("decisions-sink-v1");

    env.execute("fraud-guard");
  }
}
```

`KafkaSources` and `KafkaSinks` are small factories (`KafkaSource.builder()…`, and the transactional `KafkaSink` from
Folder 06, file 02). The retry-strategy builder signature follows FLIP-232 ⚠ verify per version.

### 3.5 RocksDB configuration and the options factory

```yaml
state.backend.type: rocksdb
execution.checkpointing.incremental: true
execution.checkpointing.interval: 30 s                  # decisions are visible to read_committed consumers per checkpoint
execution.checkpointing.min-pause: 10 s
execution.checkpointing.unaligned.enabled: true
execution.checkpointing.aligned-checkpoint-timeout: 10 s
taskmanager.network.memory.buffer-debloat.enabled: true
state.backend.rocksdb.memory.managed: true
taskmanager.memory.managed.fraction: 0.45
state.backend.rocksdb.predefined-options: FLASH_SSD_OPTIMIZED
state.backend.rocksdb.options-factory: dev.l7.flink.state.PointLookupOptionsFactory   # Folder 04, file 02 §7.3
state.backend.rocksdb.metrics.is-write-stopped: true
state.backend.rocksdb.metrics.estimate-pending-compaction-bytes: true
```

The factory itself is in Folder 04, file 02 §7.3: Bloom filters, 16 KB blocks, index and filter blocks in the
**shared managed cache**, `optimizeFiltersForHits`, and no private block cache.

### 3.6 Contrast: Kafka Streams' `RocksDBConfigSetter`

Kafka Streams calls its hook a **config setter**. Bounded memory there must be built by hand: one shared cache and
write-buffer manager per JVM across all stores. Flink's managed memory gives you that by default.

```java
package dev.l7.blueprints.fraud;

import java.util.Map;
import org.apache.kafka.streams.state.RocksDBConfigSetter;
import org.rocksdb.BlockBasedTableConfig;
import org.rocksdb.BloomFilter;
import org.rocksdb.Cache;
import org.rocksdb.LRUCache;
import org.rocksdb.Options;
import org.rocksdb.WriteBufferManager;

/** Kafka Streams: bound TOTAL RocksDB memory across all state stores in this JVM (shared cache + write buffers). */
public final class BoundedMemoryRocksDBConfig implements RocksDBConfigSetter {

  private static final long TOTAL_OFF_HEAP_BYTES = 2L << 30;            // 2 GiB for ALL stores
  private static final long WRITE_BUFFER_BYTES = 512L << 20;            // part of the total, counted in the cache
  private static final Cache CACHE = new LRUCache(TOTAL_OFF_HEAP_BYTES, -1, false, 0.1);
  private static final WriteBufferManager WBM = new WriteBufferManager(WRITE_BUFFER_BYTES, CACHE);

  @Override
  public void setConfig(String storeName, Options options, Map<String, Object> configs) {
    BlockBasedTableConfig table = (BlockBasedTableConfig) options.tableFormatConfig();
    table.setBlockCache(CACHE);                                          // shared (static) across stores
    table.setCacheIndexAndFilterBlocks(true);
    table.setPinTopLevelIndexAndFilter(true);
    table.setFilterPolicy(new BloomFilter(10, false));
    options.setWriteBufferManager(WBM);
    options.setTableFormatConfig(table);
    options.setMaxWriteBufferNumber(3);
  }

  @Override
  public void close(String storeName, Options options) {
    // Shared CACHE/WBM are static: do NOT close them per store.
  }
}
```

---

## 4. Tests with Flink's harness

```java
package dev.l7.blueprints.fraud;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.streaming.util.KeyedOneInputStreamOperatorTestHarness;
import org.apache.flink.streaming.util.ProcessFunctionTestHarnesses;
import org.junit.jupiter.api.Test;

class CardRiskFeaturesTest {

  private static Txn txn(String id, long ts, String country) {
    return new Txn(id, "card-1", "m-1", 1_000, ts, country);
  }

  @Test
  void dedupsVelocityAndImpossibleTravel() throws Exception {
    KeyedOneInputStreamOperatorTestHarness<String, Txn, Candidate> h =
        ProcessFunctionTestHarnesses.forKeyedProcessFunction(new CardRiskFeatures(), Txn::cardId, Types.STRING);

    h.processElement(txn("t1", 60_000, "US"), 60_000);
    h.processElement(txn("t1", 60_000, "US"), 60_000);                   // duplicate → side output
    h.processElement(txn("t2", 120_000, "US"), 120_000);
    h.processElement(txn("t3", 180_000, "FR"), 180_000);                 // country change within 10 min

    List<Candidate> out = h.extractOutputValues();
    assertEquals(3, out.size());
    assertEquals(1, h.getSideOutput(CardRiskFeatures.DUPLICATES).size());
    assertEquals(3L, out.get(2).velocity5m());                           // t1, t2, t3 within 5 minutes
    assertTrue(out.get(2).impossibleTravel());

    h.processWatermark(20 * 60_000);                                     // timers clear old buckets
    h.processElement(txn("t4", 20 * 60_000 + 1, "FR"), 20 * 60_000 + 1);
    assertEquals(1L, h.extractOutputValues().get(3).velocity5m());       // old buckets are gone
    h.close();
  }
}
```

The harness lives in Flink's streaming test utilities ⚠ verify the artifact and class names for your version. Async I/O
can be tested with `AsyncWaitOperator` harnesses, or more practically with a MiniCluster integration test against a
stubbed scorer.

---

## 5. Production failure modes and P99 debugging

| ID | Failure | Signature | Root cause | Fix |
|----|---------|-----------|------------|-----|
| F1 | **Backpressure from blocking I/O** | the scoring operator is busy at 100%; sources backpressured | sync HTTP in `processElement` | Async I/O with capacity = λ × W (Folder 04, file 03 §4) |
| F2 | **Async capacity starvation** | async operator backpressured; scorer underutilized | capacity too low for λ × W | raise capacity; check the per-attempt timeout |
| F3 | **Job restarts when the scorer fails** | restarts correlate with scorer incidents | `completeExceptionally` after retries | fallback results + retry on result; `timeout()` fallback |
| F4 | **Duplicate scoring calls after recovery** | scorer sees repeats | in-flight async inputs re-issued after restore | idempotency key (txnId); side-effect-free scoring |
| F5 | **Velocity drifts on replay** | different results when replaying | processing-time-based cleanup | event-time timers for bucket expiry (as above) |
| F6 | **State growth for dormant cards** | key count grows forever | no TTL or timers for idle keys | TTL backstop; event-time cleanup |
| F7 | **Ordered-mode latency spikes** | p99 latency equals the slowest request | `orderedWait` head-of-line blocking | `unorderedWait` unless order matters |
| F8 | **Watermark stalls downstream of async** | the async operator holds watermarks | unordered mode keeps watermark barriers; one slow request delays the watermark | timeouts bound it; tune per-attempt timeouts |
| F9 | **Kafka Streams RocksDB OOM** (contrast) | container killed | per-store caches unbounded | shared cache + WriteBufferManager (§3.6) |

---

## 6. FAANG L7 bar-raiser Q&A chains

### Q1 · "Design sub-second fraud scoring at 200k txn/s with an external model service at 50 ms p50 / 300 ms p99."

**L5 textbook answer.** Flink with a map function that calls the model, plus high parallelism.

**Why L5 breaks at petabyte scale.** Sync calls need λW = 10,000 concurrent calls. A map at parallelism 10,000 is absurd.
p99 calls block threads, backpressure hits Kafka, and checkpoints stall behind blocked operators.

**L7 principal defense.**

1. **Async I/O:** capacity per subtask = (λ / parallelism) × W with headroom, `unorderedWait`, a per-attempt timeout
   under the overall timeout.
2. **Resilience:** a fallback decision on timeout or error, retry on fallback results with backoff, an idempotency key.
   The job never fails because the model failed.
3. **Features in keyed state:**
   - exact dedup via `MapState` + TTL;
   - velocity via minute buckets with event-time cleanup;
   - impossible travel via tiny `ValueState`s;
   - all point lookups (RocksDB-friendly).
4. **Output:** a transactional Kafka sink with checkpoint-interval visibility, or idempotent decisions keyed by txnId if
   sub-second visibility is required.
5. **SLOs:** p99 decision latency, fallback rate, scorer error budget.

### Q2 · "What does Async I/O do on checkpoint and recovery?"

**L5 textbook answer.** It's checkpointed like other operators.

**Why L5 breaks.** The subtle part is that in-flight **inputs** are part of the snapshot and are **re-sent** after restore.
Non-idempotent calls repeat. And in unordered mode, watermarks act as barriers, so a slow request delays the watermark.

**L7 principal defense.**

- **The snapshot contains the queue of pending inputs;** on restore they're re-issued, so idempotency keys are required.
- **Unordered mode** emits results out of order between watermarks. Watermarks are barriers, so timeouts bound watermark
  delay.
- **Capacity** bounds both memory and in-flight requests.
- **Retries** (FLIP-232) are per element, with predicates on results or exceptions.

### Q3 · "Why event-time timers for bucket cleanup instead of TTL?"

**L5 textbook answer.** Timers are more precise.

**Why L5 breaks.** Precision isn't the point. **Determinism** is. TTL is processing time: a replay after an outage expires
or retains buckets differently, so velocity features differ between the original run and the replay. Backtests and
incident analyses won't match.

**L7 principal defense.** Event-time timers make feature state a pure function of event time, so replays and backfills
reproduce the same features. TTL stays as a **backstop** for dormant keys (memory hygiene), not as a semantic mechanism.
Timers are deduplicated per (key, timestamp), so registering per bucket costs nothing extra.

### Q4 · "Flink's RocksDB options factory vs. Kafka Streams' `RocksDBConfigSetter`: what's the key difference?"

**L5 textbook answer.** Same idea, different names.

**Why L5 breaks.** The memory model differs. Kafka Streams creates a RocksDB instance per store and partition, each with
its own cache unless you share them yourself. Unbounded native memory is the classic Kafka Streams OOM. Flink's managed
memory provides a shared, bounded cache per slot by default.

**L7 principal defense.**

- **Kafka Streams:** a static shared `LRUCache` plus a `WriteBufferManager` charged to the cache, and never closing the
  shared objects per store (§3.6).
- **Flink:** keep managed memory on, and **don't** set a private block cache in the options factory. Modify the injected
  table config only (Folder 04, file 02 §7.3).

---

## 7. Invariants checklist

1. **Keyed state as point lookups** (`MapState`, small `ValueState`). Never use list scans per element.
2. **Event-time timers for semantic cleanup; TTL as a backstop.**
3. **Async I/O capacity = λ × W per subtask.** Unordered unless order matters.
4. **Never fail the job on dependency failure.** Use fallback results plus retry-on-result.
5. **Async inputs are re-issued after recovery.** Use idempotency keys.
6. **Stable `uid`s on every stateful operator and source.**
7. **RocksDB memory stays managed and shared.** In Kafka Streams, share the cache and write-buffer manager explicitly.

---

## 8. References

- Apache Flink docs: *Process Function*, *Asynchronous I/O* (incl. FLIP-232 retry support), *Working with State* /
  *State TTL*, *RocksDB State Backend*, *Testing* (operator test harnesses).
- Apache Kafka Streams docs: *RocksDB behavior* / `RocksDBConfigSetter` (bounded memory).
- Folder 04, file 02 (options factory); Folder 05, file 03 (TTL); Folder 06, file 02 (transactional sinks).

**Next →** [04 · Schema evolution, dead-letter routing, and the drain/update lifecycle](04-schema-evolution-dead-letter-routing-and-drain-update-lifecycle.md)
