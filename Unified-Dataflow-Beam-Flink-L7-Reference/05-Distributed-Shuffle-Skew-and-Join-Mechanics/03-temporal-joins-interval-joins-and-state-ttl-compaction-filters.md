# 03 · Temporal Joins, Interval Joins, and State TTL with Compaction Filters

> **Folder:** `05-Distributed-Shuffle-Skew-and-Join-Mechanics/` · **File 3 of 3**
> **Anchoring papers and sources:** Begoli et al., *One SQL to Rule Them All* (SIGMOD 2019): time-varying relations,
> temporal joins · Snodgrass, *Developing Time-Oriented Database Applications in SQL* (1999) · Kang, Naughton & Viglas,
> *Evaluating Window Joins over Unbounded Streams* (ICDE 2003) · Flink docs: *Joins in Continuous Queries*, *State TTL*,
> *Lookup joins*; Flink FLIP-373 (per-operator state TTL via SQL hints) · RocksDB compaction filters · Beam
> `OrderedListState`.
> **Prev:** [02 · Skew](02-mitigating-data-skew-salting-fanout-and-broadcast-joins.md) · **Next folder:**
> `06-Lakehouse-Sinks-Backpressure-and-FinOps/`

---

## 0. The thesis

A streaming join must decide, for every record, **how long to remember it** in case a matching record arrives later.
That retention *is* the join's state, and its correctness contract:

| Join | What it remembers | State bound |
|------|-------------------|-------------|
| **Regular (unbounded) join** | everything, forever | **none**, so TTL is mandatory, and TTL trades away correctness |
| **Interval join** | each side within a time bound of the watermark | rate × (bound width + watermark lag) |
| **Window join** | per window, until window GC | rate × (window + lateness) |
| **Event-time temporal join** | the dimension's versions and the facts awaiting the watermark | keys × versions + fact rate × watermark lag |
| **Lookup (processing-time) join** | nothing in the engine (or a cache) | cache size |

**State TTL** is the escape hatch for unbounded joins and per-key state. In Flink it's implemented with timestamps
embedded in values and cleaned up during RocksDB compaction. It's processing-time based, changes the state format, and
cleans lazily. An L7 engineer chooses the join *by its state bound* and treats every TTL as an explicit correctness
trade.

---

## 1. Join semantics in streams

### 1.1 Time-varying relations

Begoli et al. model a stream as a **time-varying relation** $R(t)$. A join of streams is a join of relations evaluated
continuously. Without time bounds, the join must remember all past rows of both sides: a match for an order can arrive
years later. Time predicates (`BETWEEN`, windows, `AS OF`) are what let the engine **forget**, and forgetting is safe
only after the **watermark** guarantees no further matches.

### 1.2 Taxonomy and state math

| Join type | Predicate | Retention rule (per side) | Steady-state size |
|-----------|-----------|---------------------------|-------------------|
| Regular | `L.k = R.k` | forever (or TTL) | grows with history |
| Interval | `L.k = R.k AND R.t ∈ [L.t + a, L.t + b]` | keep $\ell$ until $W > \ell.t + b$; keep $r$ until $W > r.t - a$ | $\lambda_L (b + \Delta W) + \lambda_R(-a + \Delta W)$ |
| Window | same window | until window GC (`maxTs + lateness`) | $\lambda (w + \text{lateness})$ |
| Temporal (event time) | `R AS OF L.t` (versioned R, keyed by PK) | facts until $W > t$; versions until superseded and the watermark passes | $\lambda_L \Delta W + \lvert K_R\rvert \cdot \bar{v}$ |
| Lookup (processing time) | `R AS OF proc_time` | none (external system) | cache |

$\Delta W$ is the watermark lag, which is why the watermark stalls from Folder 01, file 02 turn directly into join-state
OOMs.

---

## 2. Interval joins

### 2.1 Mechanics (Flink `IntervalJoinOperator`)

Per key, the operator keeps **two buffers** (keyed `MapState<timestamp, List<entry>>`), one per side:

1. On a left element $\ell$: probe the right buffer for timestamps in $[\ell.t + a, \ell.t + b]$ and emit matches.
   Insert $\ell$ and register a cleanup timer at $\ell.t + b$.
2. On a right element $r$: probe the left buffer for $[r.t - b, r.t - a]$, emit matches, insert $r$, and register cleanup
   at $r.t - a$.
3. When the watermark passes a cleanup timer, evict.
4. Elements behind the watermark (late) are dropped, or side-output in versions that support late-data side outputs ⚠
   verify.

**The output timestamp** is the max of the two inputs' timestamps (so downstream event time stays consistent).

### 2.2 Sizing example

Orders (2k/s) joined with payments (2k/s) where payments arrive within [−5 min, +30 min] of the order, and the watermark
lag is 2 min:

$$
\text{left} \approx 2000 \cdot (1800 + 120)\,\mathrm{s} \approx 3.8\mathrm{M}\ \text{orders}, \qquad
\text{right} \approx 2000 \cdot (300 + 120) \approx 0.84\mathrm{M}\ \text{payments}
$$

At ~500 B per serialized entry, that's about 2.3 GB. Fine. A watermark stall of 6 hours multiplies it by ~12 and puts
RocksDB under stress.

### 2.3 Common mistakes

- **Unbounded "interval" joins written as regular joins** with a filter *after* the join: the engine can't infer the
  bound, so state is unbounded. The time predicate must be part of the join condition on rowtime attributes.
- **Asymmetric bounds without understanding retention:** the side retained longer is the one whose matches arrive later.
  Put the long-lived side's rate in the sizing formula.
- **Processing-time interval joins:** non-deterministic and replay-unsafe (Folder 01, file 01 F1).

---

## 3. Temporal joins

### 3.1 Event-time temporal join (versioned table)

```sql
-- Versioned dimension: PRIMARY KEY + event-time attribute + watermark (e.g., from upsert-kafka or CDC)
CREATE TABLE currency_rates (
  currency    STRING,
  rate        DECIMAL(18, 8),
  update_time TIMESTAMP(3),
  WATERMARK FOR update_time AS update_time - INTERVAL '5' SECOND,
  PRIMARY KEY (currency) NOT ENFORCED
) WITH ('connector' = 'upsert-kafka', 'topic' = 'rates', /* … */ 'key.format' = 'raw', 'value.format' = 'json');

SELECT o.order_id, o.amount * r.rate AS amount_usd, o.order_time
FROM orders AS o
JOIN currency_rates FOR SYSTEM_TIME AS OF o.order_time AS r
  ON o.currency = r.currency;
```

Semantics: each order joins the rate version **valid at the order's event time**, deterministically and replay-safely.

Mechanics (Flink's row-time temporal join operator):

- **Facts (left)** are buffered until the *combined* watermark passes their timestamp. Only then is the version as of
  that time final.
- **Versions (right)** are kept per key. Versions superseded *before* the watermark are garbage-collected, except the
  latest one still needed.
- **Output** happens when the watermark advances.

**The classic stall:** dimension tables update rarely (a rate changes hourly, a product catalog daily). The versioned
side's watermark doesn't advance between updates, so the combined watermark stalls, every fact is buffered, and state
grows until OOM. Fixes:

- **Idleness on the dimension source:** `table.exec.source.idle-timeout`, or per-source idleness (Folder 01, file 02 §6).
- **Heartbeats into the dimension topic.**
- **If exact as-of semantics aren't required,** use a processing-time lookup join.

### 3.2 Processing-time temporal (lookup) join

```sql
SELECT o.order_id, c.segment
FROM orders AS o
JOIN customers FOR SYSTEM_TIME AS OF o.proc_time AS c      -- proc_time AS PROCTIME() on orders
  ON o.customer_id = c.id;
-- customers is a lookup source (JDBC, HBase, …) with caching options, e.g.:
-- 'lookup.cache' = 'PARTIAL', 'lookup.partial-cache.max-rows' = '1000000',
-- 'lookup.partial-cache.expire-after-write' = '10 min'      (⚠ verify option names per connector)
```

| Event-time temporal join | Lookup join |
|--------------------------|-------------|
| deterministic and replay-safe | **non-deterministic**: the answer depends on when the lookup happens |
| needs a versioned changelog of the dimension | needs a queryable external store |
| state: buffered facts + versions | state: none (a cache) |
| latency: waits for the watermark | latency: lookup RTT (async lookups help) |

### 3.3 Temporal joins in Beam

Beam has no built-in temporal join. Three patterns:

1. **Slowly updating side input** (`PeriodicImpulse` → `View.asMap`): processing-time semantics, like a lookup join
   (Folder 05, file 02 §4.2).
2. **Window join** with `CoGroupByKey` over matching windows: approximate, window-granular.
3. **Stateful event-time temporal join** with `OrderedListState`: exact as-of semantics (§8.3).

---

## 4. Regular joins, and why TTL is a correctness decision

A regular join `orders JOIN customers ON id` in Flink SQL keeps **both sides forever**, because any future row may match
any past row. Options:

| Option | Effect |
|--------|--------|
| `table.exec.state.ttl = 1 d` (global) | rows idle for > 1 day are forgotten. **A late match after expiry is silently missed** (or, for outer joins, emits wrong null-padded results). |
| **Per-operator TTL** via the `STATE_TTL` hint (FLIP-373) | different retention per input (orders 1 day, customers 30 days) |
| Rewrite as interval or temporal join | a principled bound from event time |
| Changelog-aware design | upsert keys and primary keys let Flink drop superseded rows |

```sql
SELECT /*+ STATE_TTL('o' = '1d', 'c' = '30d') */ o.order_id, c.segment
FROM orders AS o JOIN customers AS c ON o.customer_id = c.id;
```

**Formalize the trade:** with TTL $\tau$ and match-delay distribution $D$, the missed-match rate is $\Pr[D > \tau]$.
Choose $\tau$ from the measured delay distribution (like allowed lateness, Folder 01, file 01 Q2) and **count misses**
(e.g., periodic reconciliation against the batch join).

---

## 5. State TTL in Flink: mechanics

### 5.1 Configuration surface

```java
StateTtlConfig ttl = StateTtlConfig.newBuilder(Duration.ofDays(7))
    .setUpdateType(StateTtlConfig.UpdateType.OnCreateAndWrite)        // or OnReadAndWrite (reads extend life)
    .setStateVisibility(StateTtlConfig.StateVisibility.NeverReturnExpired) // or ReturnExpiredIfNotCleanedUp
    .cleanupInRocksdbCompactFilter(1_000)                              // RocksDB: drop during compaction
    // .cleanupIncrementally(10, false)                                // heap backend: lazy incremental cleanup
    // .cleanupFullSnapshot()                                          // drop expired entries when taking full snapshots
    .build();
descriptor.enableTimeToLive(ttl);
```

### 5.2 How it works

- **Value wrapping.** Each TTL-enabled value is stored with an **8-byte last-access/modification timestamp**. That's an 8 B
  overhead per value (per element for list and map state), and a different serialized format.
- **Processing time only.** TTL is measured in processing time ⚠ verify whether event-time TTL is supported in your
  version. Consequences:
  - After a long outage, replaying old data finds state expired by wall clock even though it's "fresh" in event time.
  - Replays at high speed keep state alive longer than intended in event-time terms.
- **Visibility vs. physical deletion.** `NeverReturnExpired` hides expired values on read. Physical removal happens only
  through a cleanup strategy.
- **RocksDB compaction filter:** Flink's frocksdb fork includes a TTL compaction filter. When compaction rewrites an SST,
  entries whose timestamp is older than the TTL are **dropped**. The `queryTimeAfterNumEntries` parameter controls how
  often the filter refreshes "now" (a JNI call). For list state, the filter inspects each element.

### 5.3 The cold-data problem

Compaction filters run **only when compaction touches a file**. Data that has settled in the bottom level and isn't
rewritten may never be compacted, so expired entries linger, disk usage stays high, and `estimate-num-keys` doesn't fall.
Mitigations:

- **Periodic compaction** (RocksDB `periodic_compaction_seconds`; Flink exposes a periodic-compaction setting alongside
  the compaction filter in newer versions ⚠ verify), which forces old files through compaction.
- **Explicit timers** that clear state (deterministic, event-time capable, but each timer is state too).
- **Window or interval semantics** instead of TTL wherever a time bound exists.

### 5.4 TTL changes the state schema

Enabling or disabling TTL on existing state changes its serializer (wrapped vs. unwrapped values). Restoring a savepoint
with a different TTL setting fails with a **state migration/compatibility exception**. Decide TTL at design time, or plan
a migration (State Processor API, Folder 07, file 04).

### 5.5 TTL vs. timers

| | State TTL | Explicit timers |
|---|---|---|
| Time domain | processing time | event time **or** processing time |
| Precision | lazy (on access or compaction) | exact (fires when due) |
| Cost | 8 B per value + compaction CPU | one timer entry per key (state) + firing CPU |
| Semantics | "forget if idle" | "do X at time T" (emit, clean, alert) |
| Best for | bounded caches, dedup sets, idle-key cleanup | windowing, interval semantics, sessions, deterministic retention |

---

## 6. Beam equivalents

| Need | Beam mechanism |
|------|----------------|
| Bounded join state | windows (GC at `maxTs + allowedLateness`) with `CoGroupByKey` |
| Per-key state retention | **timers** (event or processing time) that clear state; `@OnWindowExpiration` for windowed stateful DoFns |
| Ordered buffers with range eviction | **`OrderedListState`** (`readRange`, `clearRange`) |
| Dedup with expiry | `Deduplicate` (state + timer per ID) or sharded exact dedup (Folder 03, file 03 §8.4) |
| No "TTL" primitive | retention is explicit, through timers. More code, but event-time capable and deterministic. |

---

## 7. Hardware sympathy

| Cost | Driver | Lever |
|------|--------|-------|
| Join state bytes | rate × retention × entry size | tighter time bounds; projection before joining (only the needed columns) |
| TTL overhead | +8 B per value / element | worth it for small values only when cleanup matters |
| Compaction CPU | TTL filter evaluation; periodic compaction | `queryTimeAfterNumEntries` tuning; schedule against the capacity budget |
| Interval-join probes | MapState range iteration per element | narrower bounds; time-bucketed keys |
| Temporal-join buffering | facts × watermark lag | idleness or heartbeats on the dimension; a healthy watermark |
| Lookup joins | RTT per miss | async lookups; partial caches; batched lookups |

**Project before joining.** Joining wide rows multiplies state by row width. Select only the join keys, time attributes,
and needed payload columns *before* the join operator.

---

## 8. Production Java 21 code blueprints

### 8.1 Anti-patterns

```java
// (A) Regular join with no bound or TTL: state grows forever.
tableEnv.executeSql("INSERT INTO enriched SELECT * FROM orders o JOIN payments p ON o.order_id = p.order_id");

// (B) Filtering by time AFTER the join: the planner can't bound state; the filter doesn't help retention.
// SELECT … FROM orders o JOIN payments p ON o.order_id = p.order_id WHERE p.ts BETWEEN o.ts AND o.ts + INTERVAL '30' MINUTE
// (only an interval join when the predicate is a rowtime condition the planner recognizes in the JOIN)

// (C) Event-time temporal join against a rarely updated dimension, with no idleness: watermark stalls, facts buffer forever.

// (D) Turning on TTL for existing state during an upgrade → restore fails (serializer changed).
```

### 8.2 Flink DataStream: interval join with late-data visibility

```java
package dev.l7.joins;

import java.time.Duration;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.datastream.SingleOutputStreamOperator;
import org.apache.flink.streaming.api.functions.co.ProcessJoinFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.util.OutputTag;

public final class OrderPaymentIntervalJoin {

  public record Order(String orderId, long amountCents, long ts) {}

  public record Payment(String orderId, long paidCents, long ts) {}

  public record Paid(String orderId, long amountCents, long paidCents, long latencyMs) {}

  public static SingleOutputStreamOperator<Paid> join(DataStream<Order> orders, DataStream<Payment> payments,
                                                      OutputTag<Order> lateOrders, OutputTag<Payment> latePayments) {
    return orders.keyBy(Order::orderId)
        .intervalJoin(payments.keyBy(Payment::orderId))
        .between(Duration.ofMinutes(-5), Duration.ofMinutes(30))   // payment ∈ [order − 5m, order + 30m]
        .sideOutputLeftLateData(lateOrders)                         // ⚠ verify availability in your version
        .sideOutputRightLateData(latePayments)
        .process(new ProcessJoinFunction<Order, Payment, Paid>() {
          @Override
          public void processElement(Order o, Payment p, Context ctx, Collector<Paid> out) {
            out.collect(new Paid(o.orderId(), o.amountCents(), p.paidCents(), p.ts() - o.ts()));
          }
        })
        .uid("order-payment-interval-join-v1")
        .name("order-payment-interval-join");
    // State ≈ λ_orders·(30m + ΔW) + λ_payments·(5m + ΔW). A watermark stall inflates both: monitor ΔW (Folder 01, file 02).
  }
}
```

### 8.3 Beam: exact event-time temporal join with `OrderedListState`

Facts are buffered until the watermark passes their timestamp, so the version as of that time is final. Each fact is then
joined with the latest version at or before its timestamp, using an in-order merge over both sorted lists. Timers hold
the output watermark at the earliest pending fact (Folder 01, file 02 §7.3).

```java
package dev.l7.joins;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Iterator;
import org.apache.beam.sdk.coders.BooleanCoder;
import org.apache.beam.sdk.coders.Coder;
import org.apache.beam.sdk.coders.CustomCoder;
import org.apache.beam.sdk.coders.InstantCoder;
import org.apache.beam.sdk.coders.KvCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.coders.VarLongCoder;
import org.apache.beam.sdk.state.OrderedListState;
import org.apache.beam.sdk.state.StateSpec;
import org.apache.beam.sdk.state.StateSpecs;
import org.apache.beam.sdk.state.TimeDomain;
import org.apache.beam.sdk.state.Timer;
import org.apache.beam.sdk.state.TimerSpec;
import org.apache.beam.sdk.state.TimerSpecs;
import org.apache.beam.sdk.state.ValueState;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.TimestampedValue;
import org.joda.time.Duration;
import org.joda.time.Instant;

/**
 * Input:  KV<joinKey (currency), JoinInput> in the GLOBAL window, element timestamp = event time
 *         (version effective time for rates; order time for facts).
 * Output: KV<orderId, KV<amountCents, rateMicros or -1 if no version existed yet>>.
 */
public final class EventTimeTemporalJoinFn extends DoFn<KV<String, EventTimeTemporalJoinFn.JoinInput>, KV<String, KV<Long, Long>>> {

  /** Tagged union: a fact (order) or a version (rate). */
  public record JoinInput(boolean isVersion, String factId, long value) {
    public static JoinInput fact(String orderId, long amountCents) { return new JoinInput(false, orderId, amountCents); }
    public static JoinInput version(long rateMicros) { return new JoinInput(true, "", rateMicros); }
  }

  public static final class JoinInputCoder extends CustomCoder<JoinInput> {
    public static final JoinInputCoder INSTANCE = new JoinInputCoder();

    @Override
    public void encode(JoinInput v, OutputStream out) throws IOException {
      BooleanCoder.of().encode(v.isVersion(), out);
      StringUtf8Coder.of().encode(v.factId(), out);
      VarLongCoder.of().encode(v.value(), out);
    }

    @Override
    public JoinInput decode(InputStream in) throws IOException {
      return new JoinInput(BooleanCoder.of().decode(in), StringUtf8Coder.of().decode(in), VarLongCoder.of().decode(in));
    }

    @Override
    public void verifyDeterministic() {}
  }

  /** Round timer targets up so one firing processes a batch of facts (fewer timer firings per key). */
  private static final Duration TIMER_GRANULARITY = Duration.standardSeconds(1);
  private static final Coder<KV<String, Long>> FACT_CODER = KvCoder.of(StringUtf8Coder.of(), VarLongCoder.of());

  @StateId("versions")
  private final StateSpec<OrderedListState<Long>> versionsSpec = StateSpecs.orderedList(VarLongCoder.of());

  @StateId("pendingFacts")
  private final StateSpec<OrderedListState<KV<String, Long>>> pendingSpec = StateSpecs.orderedList(FACT_CODER);

  @StateId("minPending")
  private final StateSpec<ValueState<Instant>> minPendingSpec = StateSpecs.value(InstantCoder.of());

  @TimerId("emit")
  private final TimerSpec emitSpec = TimerSpecs.timer(TimeDomain.EVENT_TIME);

  @ProcessElement
  public void process(@Element KV<String, JoinInput> e, @Timestamp Instant ts,
                      @StateId("versions") OrderedListState<Long> versions,
                      @StateId("pendingFacts") OrderedListState<KV<String, Long>> pending,
                      @StateId("minPending") ValueState<Instant> minPending,
                      @TimerId("emit") Timer emit) {
    JoinInput in = e.getValue();
    if (in.isVersion()) {
      versions.add(TimestampedValue.of(in.value(), ts));
      return;
    }
    pending.add(TimestampedValue.of(KV.of(in.factId(), in.value()), ts));
    Instant currentMin = minPending.read();
    if (currentMin == null || ts.isBefore(currentMin)) {
      // This fact is the new earliest pending fact: hold the output watermark at ts (legal: ts == current element ts)
      // and fire once the watermark passes the rounded-up target.
      minPending.write(ts);
      emit.withOutputTimestamp(ts).set(roundUp(ts));
    }
  }

  @OnTimer("emit")
  public void onEmit(OnTimerContext c,
                     @StateId("versions") OrderedListState<Long> versions,
                     @StateId("pendingFacts") OrderedListState<KV<String, Long>> pending,
                     @StateId("minPending") ValueState<Instant> minPending,
                     @TimerId("emit") Timer emit,
                     OutputReceiver<KV<String, KV<Long, Long>>> out) {
    Instant complete = c.fireTimestamp().plus(Duration.millis(1));       // watermark > fire ⇒ facts < complete are final
    Iterator<TimestampedValue<Long>> vs = versions.readRange(BoundedWindow.TIMESTAMP_MIN_VALUE, complete).iterator();
    TimestampedValue<Long> current = null;
    TimestampedValue<Long> lookahead = vs.hasNext() ? vs.next() : null;

    for (TimestampedValue<KV<String, Long>> fact : pending.readRange(BoundedWindow.TIMESTAMP_MIN_VALUE, complete)) {
      while (lookahead != null && !lookahead.getTimestamp().isAfter(fact.getTimestamp())) {   // version.t ≤ fact.t
        current = lookahead;
        lookahead = vs.hasNext() ? vs.next() : null;
      }
      long rate = current == null ? -1L : current.getValue();
      out.outputWithTimestamp(KV.of(fact.getValue().getKey(), KV.of(fact.getValue().getValue(), rate)),
          fact.getTimestamp());                                          // ≥ the timer's output timestamp (hold)
    }
    pending.clearRange(BoundedWindow.TIMESTAMP_MIN_VALUE, complete);

    // GC: versions strictly older than the latest version before `complete` can never be "as of" a future fact.
    TimestampedValue<Long> latestBefore = current;
    while (lookahead != null) {                                          // drain: find the last version < complete
      latestBefore = lookahead;
      lookahead = vs.hasNext() ? vs.next() : null;
    }
    if (latestBefore != null) {
      versions.clearRange(BoundedWindow.TIMESTAMP_MIN_VALUE, latestBefore.getTimestamp());
    }

    // Re-arm for the next pending fact, if any.
    Iterator<TimestampedValue<KV<String, Long>>> rest =
        pending.readRange(complete, BoundedWindow.TIMESTAMP_MAX_VALUE).iterator();
    if (rest.hasNext()) {
      Instant next = rest.next().getTimestamp();
      minPending.write(next);
      emit.withOutputTimestamp(next).set(roundUp(next));                 // next ≥ current hold: legal
    } else {
      minPending.clear();
    }
  }

  private static Instant roundUp(Instant ts) {
    long g = TIMER_GRANULARITY.getMillis();
    long end = Math.floorDiv(ts.getMillis(), g) * g + g;                 // next granularity boundary
    return new Instant(end - 1);                                         // fires when watermark ≥ boundary
  }
}
```

Wiring and caveats:

```java
PCollection<KV<String, JoinInput>> facts = orders.apply(MapElements.into(/* KV<String, JoinInput> */ ...)
    .via(o -> KV.of(o.currency(), JoinInput.fact(o.orderId(), o.amountCents()))));
PCollection<KV<String, JoinInput>> rates = rateUpdates.apply(MapElements.into(/* … */ ...)
    .via(r -> KV.of(r.currency(), JoinInput.version(r.rateMicros()))));

PCollectionList.of(facts).and(rates)
    .apply(Flatten.pCollections())
    .setCoder(KvCoder.of(StringUtf8Coder.of(), EventTimeTemporalJoinFn.JoinInputCoder.INSTANCE))
    .apply(Window.into(new GlobalWindows()))
    .apply(ParDo.of(new EventTimeTemporalJoinFn()));
```

- **The rates source must advance its watermark when quiet** (idleness, heartbeats, or a backlog-aware source; Folder 01,
  file 02), or facts buffer indefinitely. This is the Beam version of the Flink stall in §3.1.
- **Late versions** (behind the watermark) can't change already-emitted joins. Emit corrections only if your contract
  requires them (a retraction pattern, Folder 01, file 03 §9.5).
- **`OrderedListState` runner support** varies ⚠ verify (Dataflow streaming supports it in recent releases).

### 8.4 Flink SQL: temporal, interval, and bounded regular joins with idleness

```sql
SET 'table.exec.source.idle-timeout' = '30 s';     -- the rarely updated dimension doesn't stall the watermark

-- Interval join (bounded state)
SELECT o.order_id, p.paid_cents, p.ts - o.ts AS latency
FROM orders o, payments p
WHERE o.order_id = p.order_id
  AND p.ts BETWEEN o.ts - INTERVAL '5' MINUTE AND o.ts + INTERVAL '30' MINUTE;

-- Regular join where unbounded semantics are required: explicit per-input TTL as a documented trade
SELECT /*+ STATE_TTL('o' = '2d', 'c' = '90d') */ o.order_id, c.segment
FROM orders o JOIN customers c ON o.customer_id = c.id;
```

---

## 9. Production failure modes and P99 debugging

| ID | Failure | Signature | Root cause | Fix |
|----|---------|-----------|------------|-----|
| J1 | **Unbounded join state** | checkpoint size grows linearly; eventual OOM or disk full | regular join with no TTL or bound | interval or temporal join; `STATE_TTL`; projection |
| J2 | **Temporal-join stall** | output stops; left-side state grows; watermark flat | dimension source idle (no watermark progress) | idleness; heartbeats; lookup join if acceptable |
| J3 | **Missed matches after TTL** | reconciliation shows missing joins for late arrivals | match delay > TTL | size TTL from the delay distribution; count misses; batch correction |
| J4 | **TTL not reclaiming space** | expired data stays on disk; key count flat | compaction never touches cold files | periodic compaction; timers; window semantics |
| J5 | **Restore fails after enabling TTL** | state migration/compatibility exception | TTL changes the serializer format | decide at design time; State Processor API migration |
| J6 | **Replay expires state** | after an outage, joins fail to match during catch-up | processing-time TTL during an event-time replay | longer TTL; event-time timers for retention; replay with TTL disabled via migration |
| J7 | **Interval-join late drops** | missing pairs that arrive behind the watermark | lateness beyond the watermark | watermark tuning; late side outputs; reconciliation |
| J8 | **Lookup-join overload** | external DB saturated; high latency | cache too small; sync lookups | async lookups; partial cache; batch lookups; rate limits |
| J9 | **Wide-row state bloat** | state far larger than the join keys justify | joining full rows | project before the join |

---

## 10. FAANG L7 bar-raiser Q&A chains

### Q1 · "Enrich orders with the currency rate valid at order time. Design it."

**L5 textbook answer.** Keep the latest rates in a map (broadcast or side input) and look them up when orders arrive.

**Why L5 breaks.** "Latest when the order arrives" is processing-time semantics. Replays or backfills produce different
amounts, and late orders get today's rate instead of the historical one. Audit and finance reconciliation fail.

**L7 principal defense.**

1. **An event-time temporal join** against a **versioned** rates table (PK + event time + watermark): the rate *as of*
   the order time, deterministic and replay-safe.
2. **State:** facts buffered until the watermark passes, plus versions per currency with GC of superseded ones.
3. **Prevent the stall:** idleness or heartbeats on the rates stream.
4. **Late rate corrections:** decide whether past joins must be corrected (retractions) or are final.
5. **In Beam,** use the `OrderedListState` temporal join (§8.3). In Flink SQL, `FOR SYSTEM_TIME AS OF o.order_time`.

### Q2 · "Your Flink SQL job with a regular join grows its state by 200 GB a day. Options?"

**L5 textbook answer.** Set `table.exec.state.ttl` to a day.

**Why L5 breaks.** Global TTL silently drops matches for anything arriving after a day (and corrupts outer-join results),
and it applies the same retention to inputs with very different semantics.

**L7 principal defense.**

- **Find the time bound in the semantics:** if matches occur within an interval, rewrite as an interval join. If the
  right side is a dimension, use a temporal or lookup join.
- **If unbounded semantics are real,** set per-input `STATE_TTL` from measured match-delay distributions, and reconcile
  misses in batch.
- **Project columns before the join;** exploit primary keys (upsert semantics drop superseded rows).
- **Physically,** TTL needs compaction to reclaim space, so enable periodic compaction or verify that disk usage falls.

### Q3 · "Explain how Flink's RocksDB TTL compaction filter works, and its pitfalls."

**L5 textbook answer.** Expired state is automatically deleted by RocksDB.

**Why L5 breaks.** "Automatically" hides lazy cleanup: cold files are never compacted. It also hides the 8 B-per-value
format change (which breaks restores when toggled) and processing-time semantics (which misbehave during replays).

**L7 principal defense.**

- **Values carry an 8 B timestamp.** The compaction filter drops expired entries when compaction rewrites their SST, and
  refreshes "now" every N entries (the JNI-cost trade).
- **Visibility** (`NeverReturnExpired`) is immediate, but space reclamation is lazy. Use periodic compaction to force
  cold files through.
- **TTL is processing time:** replays after outages expire "fresh" event-time state. Use event-time timers when retention
  must follow event time.
- **Toggling TTL changes the serializer.** Plan it.

### Q4 · "Interval join vs. window join vs. temporal join: when do you use each?"

**L5 textbook answer.** Interval for time ranges, windows for windows, and temporal for dimensions.

**Why L5 breaks.** Choosing by name rather than by state bound and semantics leads to unbounded state or wrong answers.

**L7 principal defense.**

| Join | Use when | State |
|------|----------|-------|
| **Interval** | relative time bounds between two event streams (payment within 30 min of an order) | rate × (bound + watermark lag) |
| **Window** | both sides naturally belong to the same fixed or session buckets (aggregated comparisons) | window + lateness |
| **Event-time temporal** | fact × versioned dimension, *as of* the fact time | buffered facts + versions |
| **Lookup** | dimension in an external store and freshness more important than determinism | none |

Then size the state with the formulas in §1.2 and list the watermark-stall risks.

### Q5 · "How do you bound per-key state in Beam, which has no TTL?"

**L5 textbook answer.** Beam doesn't support it, so use Flink.

**Why L5 breaks.** Beam supports retention explicitly through windows and timers. Not knowing this leads to global-window
state leaks.

**L7 principal defense.**

- **Windowed state is GC'd** at `maxTs + allowedLateness`. `@OnWindowExpiration` gives a final hook.
- **Global-window state needs explicit timers:** processing time (TTL-like) or event time (deterministic). Re-arm them
  sparingly, because every timer change is part of the commit (Folder 03, file 01 §8.2).
- **`OrderedListState`** gives range eviction for time-ordered buffers.
- **The trade:** more code than Flink TTL, but event-time-correct and replay-deterministic.

---

## 11. Invariants checklist

1. **Every streaming join's state equals its retention policy.** Choose the join by its bound.
2. **Time predicates must be in the join condition** on rowtime attributes, or the state is unbounded.
3. **Event-time temporal joins need a moving watermark on the dimension side.** Use idleness or heartbeats.
4. **Lookup joins are non-deterministic.** Use them only when freshness beats replayability.
5. **TTL is a correctness trade:** miss rate = Pr[delay > τ]. Measure and reconcile.
6. **Flink TTL is processing time, lazy, and format-changing.** Plan compaction and migrations.
7. **Project before joining.**

---

## 12. References

- E. Begoli, T. Akidau, F. Hueske, J. Hyde, K. Knight, K. Knowles. *One SQL to Rule Them All.* SIGMOD 2019.
- R. T. Snodgrass. *Developing Time-Oriented Database Applications in SQL.* Morgan Kaufmann, 1999.
- J. Kang, J. F. Naughton, S. D. Viglas. *Evaluating Window Joins over Unbounded Streams.* ICDE 2003.
- Apache Flink docs: *Joins* (regular, interval, temporal, lookup), *State TTL*, *Versioned tables*, FLIP-373 (state TTL
  hints), FLIP-221 (lookup cache).
- RocksDB wiki: *Compaction Filter*, *Periodic compaction*. `ververica/frocksdb` (Flink TTL compaction filter).
- Apache Beam: `OrderedListState`, `Deduplicate`, *Timely (and stateful) processing* blog posts.

---

**End of Folder 05.** Next: `06-Lakehouse-Sinks-Backpressure-and-FinOps/`.
