# 04 · Schema Evolution, Dead-Letter Routing, and the Drain/Update Lifecycle

> **Folder:** `07-Production-Java-Code-Blueprints/` · **File 4 of 4**
> **Anchors:** Dataflow docs (*Update an existing pipeline*, *Stop a running pipeline: drain vs. cancel*, *Dataflow
> snapshots*) · Flink docs (*Savepoints*, *Checkpoints vs. Savepoints*, *State Schema Evolution*, *Custom State
> Serialization*, *State Processor API*), FLIP-263 (serializer snapshot compatibility resolution) · Confluent Schema
> Registry compatibility modes · Avro and Protobuf evolution rules · Kleppmann, *DDIA* ch. 4 (encoding and evolution).
> **Prev:** [03 · Flink fraud engine](03-flink-keyedprocessfunction-async-io-and-rocksdb-config-setter.md) · **Next folder:**
> `08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/`

---

## 0. The thesis

A streaming pipeline is a **long-lived process whose state outlives its code**. Three contracts determine whether you can
change it safely:

1. **Wire and state encoding contracts.** Old bytes must decode under new code (backward compatibility), and new bytes
   under old code if you might roll back (forward compatibility). That covers source messages, shuffle and state coders,
   and sink schemas.
2. **Graph identity contracts.** The new job must map its stateful steps onto the old job's state: Dataflow transform
   names (or a name mapping), Flink operator `uid`s.
3. **Lifecycle semantics.** Update, drain, cancel, savepoint, snapshot. Each has a different effect on in-flight data,
   open windows, and exactly-once guarantees.

Bad records are a fourth contract. They must become **data with a path** (a dead-letter queue) instead of exceptions that
retry forever and pin watermarks.

---

## 1. Encoding evolution: the rules

### 1.1 Compatibility directions

| Direction | Means | Needed for |
|-----------|-------|------------|
| **Backward** | new reader reads old data | upgrades (new code restores old state; consumes old messages) |
| **Forward** | old reader reads new data | rollbacks; old consumers during rolling producer upgrades |
| **Full** | both | safe two-way deploys |
| **Transitive** | holds across *all* versions, not just adjacent ones | long retention (state or messages older than one release) |

### 1.2 Format rules

| Format | Safe changes | Unsafe changes |
|--------|--------------|----------------|
| **Avro** | add a field **with a default**; remove a field **that had a default**; widen types per promotion rules | rename without aliases; add a field without a default (breaks backward); change types incompatibly |
| **Protobuf** | add fields with new numbers; mark removed fields `reserved` | **reuse field numbers**; change a field's type or wire type; change `required` semantics (proto2) |
| **Beam custom coders** | version byte + extension block from v1 (file 01 §3.1) | reorder or retype core fields; change key encodings (remaps state addresses) |
| **Beam schemas** (`Row`) | add nullable fields; explicit **encoding positions** keep the wire order stable | change field types; remove fields without a migration ⚠ verify Dataflow update support for schema changes |
| **Flink POJO serializer** | add or remove fields (defaults on restore) | change a field's type; rename the class or package |
| **Flink Avro serializer** | Avro evolution rules | incompatible Avro changes |
| **Flink Kryo (generic)** | **none guaranteed** | any change. Never put Kryo-serialized types in long-lived state. |
| **BigQuery tables** | add nullable columns; relax REQUIRED → NULLABLE | change column types; drop columns read by sinks |
| **Iceberg** | add, drop, rename, and reorder columns (columns are tracked by **ID**); type promotions | incompatible type changes |

**Key encodings are special.** Any change to how a *key* is encoded (Beam key coder, Flink key serializer or `hashCode`)
changes **where its state lives**. Old state becomes unreachable, even if values decode fine. Treat key types as frozen.

### 1.3 Flink serializer compatibility resolution

On restore, Flink compares the **serializer snapshot written with the state** against the new serializer. Since Flink
1.19 (FLIP-263), the *new* snapshot resolves compatibility given the *old* one ⚠ verify the exact signature. The outcomes
of `TypeSerializerSchemaCompatibility` (the class the curriculum calls "StateSerializerSchemaCompatibility"):

| Result | Meaning |
|--------|---------|
| `compatibleAsIs()` | read old bytes directly |
| `compatibleAfterMigration()` | Flink reads with the old serializer and rewrites with the new one (heap: on restore; RocksDB: on access or during migration) |
| `compatibleWithReconfiguredSerializer(s)` | use a reconfigured serializer instance |
| `incompatible()` | restore fails; you need an offline migration (State Processor API, §5.4) |

---

## 2. Graph identity

| Engine | Identity of stateful steps | How to rename or remove |
|--------|---------------------------|--------------------------|
| **Dataflow** | **transform (step) names** in the pipeline graph | `--transformNameMapping='{"Old":"New","Removed":""}'` on `--update` |
| **Flink** | **operator `uid`** (or an auto-generated hash, which is fragile) | keep `uid`s stable; `--allowNonRestoredState` to drop state of removed operators; State Processor API to rename or transform |

**Rule:** set explicit, versioned identities from day one: Beam transform names like `"ParseOrders"`, Flink
`.uid("parse-orders-v1")`. Auto-generated identities change when unrelated parts of the graph change.

---

## 3. Lifecycle semantics

### 3.1 Dataflow

| Operation | In-flight data | Open windows / state | Use |
|-----------|----------------|----------------------|-----|
| **`--update`** (in-place replacement) | preserved | **preserved and transferred** (subject to compatibility checks) | normal deploys of compatible changes |
| **Drain** | finishes processing buffered data; stops reading new data | **watermarks advance to infinity: all windows fire NOW, with incomplete data** (partial aggregates); timers fire | retiring a pipeline, or incompatible changes where partial windows are acceptable or correctable downstream |
| **Cancel** | stops immediately; uncommitted work discarded | state discarded | emergencies; when a replacement will reprocess from source positions |
| **Snapshot** + new job `--createFromSnapshot` | snapshot captures job state (and optionally Pub/Sub source state) | restored into a new job | migrations, rollbacks, cloning ⚠ verify source support |

**Drain emits partial windows.** A sink that treats windows as final (append-only) gets truncated aggregates. Either make
the sink an **upsert keyed by (key, window)** so the replacement job can emit corrections, or accept and document the
partial window at drain time. In Beam, drained panes carry pane metadata ⚠ verify `PaneInfo` timing during drain.

### 3.2 Flink

| Operation | Effect |
|-----------|--------|
| **Stop with savepoint** (`flink stop --savepointPath …`) | takes a savepoint, then stops gracefully. Open windows and timers stay in state, ready to resume. |
| **Stop with savepoint + `--drain`** | emits **`MAX_WATERMARK`** first: fires all event-time timers (partial windows) and flushes. Use only when permanently retiring. |
| **Savepoint (canonical vs. native)** | canonical: portable format, slower; native: the state backend's format (e.g., RocksDB SSTs), faster, same backend required ⚠ verify the version matrix |
| **Retained checkpoint restore** | fast; meant for recovery; format and version guarantees weaker than savepoints |
| **Cancel** | state discarded unless checkpoints are retained |
| **Restore with `--allowNonRestoredState`** | skips state of operators missing from the new job. Deliberate deletions only. |

**Kubernetes operator:** `upgradeMode: savepoint | last-state | stateless` maps these choices to declarative upgrades
(Folder 06, file 03 §7.2).

---

## 4. Dead-letter routing

### 4.1 Principles

1. **Never let a record retry forever.** In Dataflow streaming, that pins the watermark (Folder 01, file 02, W4). In
   Flink, it causes restart loops.
2. **Classify failures:**
   - **permanent** (malformed, schema violation): dead-letter immediately;
   - **transient** (timeouts, 5xx): retry with budget, then dead-letter;
   - **systemic** (dependency down): circuit-break and pause, don't dead-letter everything.
3. **The envelope must make replay possible:** original bytes plus source coordinates plus enough context to fix and
   re-inject.
4. **DLQ rate is an SLO.** Alert on rate and on new error classes, not just on volume.

### 4.2 The error envelope

| Field | Why |
|-------|-----|
| `payload` (original bytes, base64 or raw) | replay without re-reading the source |
| `source` (topic/partition/offset, or Pub/Sub message ID, or file and offset) | provenance; dedup on replay |
| `eventTime` | re-inject with the original event time |
| `stage` / transform name | where it failed |
| `errorClass`, `message`, `stackHash` | grouping and triage |
| `attempts` | retry history |
| `pipelineVersion` | was it fixed in a later release? |
| `firstSeen` | age and SLA |

### 4.3 Replay

1. Fix the code or the data.
2. Select DLQ records by `errorClass`/`stage`/version.
3. Re-inject them into the pipeline's input (or a dedicated replay input), **preserving event time and idempotency
   keys**, so downstream dedup or upserts absorb any partial earlier effects.
4. Watch lateness. Replayed events may be behind the watermark, so windowed consumers need upsert semantics or a
   batch correction path (Folder 01, file 01 Q2).

---

## 5. Production Java 21 code blueprints

### 5.1 Anti-patterns

```java
// (A) Exceptions escape the DoFn: Dataflow retries the bundle forever, and the watermark is pinned at this element.
Order parse(byte[] bytes) { return mapper.readValue(bytes, Order.class); }        // throws on bad input

// (B) Flink operator without uid: any graph change → "cannot map savepoint state".
stream.keyBy(Order::id).process(new Dedup());

// (C) Kryo-serialized POJO with a changed field type in RocksDB state → restore fails, no migration path.

// (D) Drain before an "incompatible" deploy, with an append-only sink → permanent truncated hourly aggregates.

// (E) Reusing a Protobuf field number for a new meaning → old messages decode into the wrong field silently.
```

### 5.2 Beam: parse with failures as data (`WithFailures`) and a replayable envelope

```java
package dev.l7.blueprints.lifecycle;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.apache.beam.sdk.io.kafka.KafkaRecord;
import org.apache.beam.sdk.transforms.MapElements;
import org.apache.beam.sdk.transforms.WithFailures;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.TypeDescriptor;
import org.joda.time.Instant;

public final class ParseWithDeadLetters {

  public record Order(String orderId, long amountCents, long eventTimeMillis) implements java.io.Serializable {}

  /** Replayable error envelope (give it an explicit coder or schema in production). */
  public record ErrorEnvelope(String payloadB64, String source, long eventTimeMillis, String stage, String errorClass,
                              String message, int stackHash, String pipelineVersion, long firstSeenMillis)
      implements java.io.Serializable {}

  public static WithFailures.Result<PCollection<Order>, ErrorEnvelope> parse(
      PCollection<KafkaRecord<String, byte[]>> raw, String pipelineVersion) {
    return raw.apply("ParseOrders", MapElements
        .into(TypeDescriptor.of(Order.class))
        .via((KafkaRecord<String, byte[]> r) -> OrderCodec.decode(r.getKV().getValue()))    // may throw
        .exceptionsInto(TypeDescriptor.of(ErrorEnvelope.class))
        .exceptionsVia((WithFailures.ExceptionElement<KafkaRecord<String, byte[]>> ee) -> {
          KafkaRecord<String, byte[]> r = ee.element();
          Exception ex = ee.exception();
          return new ErrorEnvelope(
              Base64.getEncoder().encodeToString(r.getKV().getValue() == null ? new byte[0] : r.getKV().getValue()),
              r.getTopic() + "/" + r.getPartition() + "@" + r.getOffset(),
              r.getTimestamp(),
              "ParseOrders",
              ex.getClass().getName(),
              String.valueOf(ex.getMessage()),
              java.util.Arrays.hashCode(ex.getStackTrace()),
              pipelineVersion,
              Instant.now().getMillis());
        }));
  }

  /** Minimal codec for the example: "orderId|amountCents|eventTimeMillis". Production: Avro/Proto + registry. */
  static final class OrderCodec {
    static Order decode(byte[] bytes) {
      String[] f = new String(bytes, StandardCharsets.UTF_8).split("\\|", -1);
      if (f.length != 3) {
        throw new IllegalArgumentException("expected 3 fields, got " + f.length);
      }
      return new Order(f[0], Long.parseLong(f[1]), Long.parseLong(f[2]));
    }
  }
}
```

```java
WithFailures.Result<PCollection<Order>, ErrorEnvelope> parsed = ParseWithDeadLetters.parse(raw, "orders-2026.10.3");
parsed.output().apply("Enrich", /* … */);
parsed.failures().apply("DLQ", new DeadLetterSink("orders"));   // Kafka DLQ topic and/or BigQuery table for triage
```

Newer Beam releases add an **error-handler API** for I/O connectors (bad-record routers / `withBadRecordErrorHandler`) to
standardize this ⚠ verify availability.

### 5.3 Flink: DLQ side output with the same envelope

```java
package dev.l7.blueprints.lifecycle;

import org.apache.flink.streaming.api.functions.ProcessFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.util.OutputTag;

public final class ParseOrDeadLetter extends ProcessFunction<byte[], ParseWithDeadLetters.Order> {

  public static final OutputTag<ParseWithDeadLetters.ErrorEnvelope> DLQ = new OutputTag<>("dlq") {};

  private final String pipelineVersion;

  public ParseOrDeadLetter(String pipelineVersion) {
    this.pipelineVersion = pipelineVersion;
  }

  @Override
  public void processElement(byte[] bytes, Context ctx, Collector<ParseWithDeadLetters.Order> out) {
    try {
      out.collect(ParseWithDeadLetters.OrderCodec.decode(bytes));
    } catch (RuntimeException ex) {                                  // permanent: never rethrow (restart loop)
      ctx.output(DLQ, new ParseWithDeadLetters.ErrorEnvelope(
          java.util.Base64.getEncoder().encodeToString(bytes), "kafka", ctx.timestamp() == null ? -1 : ctx.timestamp(),
          "parse-orders", ex.getClass().getName(), String.valueOf(ex.getMessage()),
          java.util.Arrays.hashCode(ex.getStackTrace()), pipelineVersion, System.currentTimeMillis()));
    }
  }
}
// raw.process(new ParseOrDeadLetter(v)).uid("parse-orders-v1"); stream.getSideOutput(ParseOrDeadLetter.DLQ).sinkTo(dlqSink);
```

### 5.4 Flink: offline state migration with the State Processor API (⚠ verify APIs for your Flink version)

When a state type changes incompatibly (Kryo to POJO, a field retyped, a key restructured), migrate **offline**: read the
old savepoint, transform, and write a new savepoint under a new `uid`.

```java
package dev.l7.blueprints.lifecycle;

import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.state.api.OperatorIdentifier;
import org.apache.flink.state.api.OperatorTransformation;
import org.apache.flink.state.api.SavepointReader;
import org.apache.flink.state.api.SavepointWriter;
import org.apache.flink.state.api.StateBootstrapTransformation;
import org.apache.flink.state.api.functions.KeyedStateBootstrapFunction;
import org.apache.flink.state.api.functions.KeyedStateReaderFunction;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.util.Collector;
// Flink 1.x: org.apache.flink.contrib.streaming.state.EmbeddedRocksDBStateBackend; 2.x: org.apache.flink.state.rocksdb.* (⚠ verify)
import org.apache.flink.contrib.streaming.state.EmbeddedRocksDBStateBackend;

public final class MigrateProfileState {

  public record ProfileV1(long totalCents, String tier) {}                        // old state type

  public record ProfileV2(long totalCents, String tier, long schemaVersion) {}    // new state type

  public record KeyedV1(String userId, ProfileV1 profile) {}

  public static void main(String[] args) throws Exception {
    String oldSavepoint = args[0];
    String newSavepoint = args[1];
    StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

    SavepointReader reader = SavepointReader.read(env, oldSavepoint, new EmbeddedRocksDBStateBackend());
    DataStream<KeyedV1> oldProfiles = reader.readKeyedState(
        OperatorIdentifier.forUid("user-profile-v1"), new ReadV1());

    StateBootstrapTransformation<KeyedV1> v2 = OperatorTransformation
        .bootstrapWith(oldProfiles)
        .keyBy(KeyedV1::userId)
        .transform(new WriteV2());

    SavepointWriter
        .fromExistingSavepoint(env, oldSavepoint, new EmbeddedRocksDBStateBackend())
        .removeOperator(OperatorIdentifier.forUid("user-profile-v1"))
        .withOperator(OperatorIdentifier.forUid("user-profile-v2"), v2)            // the new job uses uid "user-profile-v2"
        .write(newSavepoint);

    env.execute("migrate-user-profile-v1-to-v2");
  }

  static final class ReadV1 extends KeyedStateReaderFunction<String, KeyedV1> {
    private transient ValueState<ProfileV1> profile;

    @Override
    public void open(OpenContext ctx) {
      profile = getRuntimeContext().getState(new ValueStateDescriptor<>("profile", ProfileV1.class));
    }

    @Override
    public void readKey(String userId, Context ctx, Collector<KeyedV1> out) throws Exception {
      ProfileV1 p = profile.value();
      if (p != null) {
        out.collect(new KeyedV1(userId, p));
      }
    }
  }

  static final class WriteV2 extends KeyedStateBootstrapFunction<String, KeyedV1> {
    private transient ValueState<ProfileV2> profile;

    @Override
    public void open(OpenContext ctx) {
      profile = getRuntimeContext().getState(new ValueStateDescriptor<>("profile", ProfileV2.class));
    }

    @Override
    public void processElement(KeyedV1 v, Context ctx) throws Exception {
      profile.update(new ProfileV2(v.profile().totalCents(), v.profile().tier(), 2L));
    }
  }
}
```

The same tool is how you turn TTL on for existing state (Folder 05, file 03 §5.4), re-key state, or split one operator's
state into two.

### 5.5 Operational commands

```bash
# ---------------- Dataflow ----------------
# 1) Safety net: snapshot the running streaming job (and Pub/Sub source state) before risky changes  (⚠ verify flags)
gcloud dataflow snapshots create --job-id="$JOB_ID" --region="$REGION" --snapshot-ttl=7d --snapshot-sources=true

# 2) In-place update with renamed and removed steps (same --jobName; compatibility is checked by the service)
mvn -q compile exec:java -Dexec.mainClass=dev.l7.OrdersPipeline -Dexec.args="\
  --runner=DataflowRunner --project=$PROJECT --region=$REGION --jobName=orders-enrichment \
  --update --transformNameMapping='{\"ParseOrders\":\"ParseOrdersV2\",\"LegacyAudit\":\"\"}' \
  --labels=pipeline=orders-enrichment,version=2026-10-3"

# 3) Rollback or migration path: start a NEW job from the snapshot
#    --createFromSnapshot=$SNAPSHOT_ID  (pipeline option on the new job)

# 4) Retire: drain (fires all windows with current data). Cancel only when replaying from source positions.
gcloud dataflow jobs drain "$JOB_ID" --region="$REGION"

# ---------------- Flink ----------------
# Upgrade: stop with a savepoint (state kept, windows NOT fired), then restore the new version from it.
flink stop --type canonical --savepointPath s3://bucket/savepoints/orders "$FLINK_JOB_ID"
flink run -d -s s3://bucket/savepoints/orders/savepoint-xxxx orders-enrichment-2.jar

# Removing an operator deliberately: allow dropping its state
flink run -d -s s3://bucket/savepoints/orders/savepoint-xxxx --allowNonRestoredState orders-enrichment-3.jar

# Retire permanently (fires all event-time timers via MAX_WATERMARK):
flink stop --drain --savepointPath s3://bucket/savepoints/orders-final "$FLINK_JOB_ID"
```

### 5.6 Pre-deploy compatibility gate (CI)

```text
1. Encoding: run coder/serializer compatibility tests (old-release decoder × new data, new decoder × old data).
2. Schema registry: check compatibility (BACKWARD_TRANSITIVE for state-like topics; FULL for shared topics).
3. Graph identity:
   - Dataflow: diff transform names vs. the running job; generate --transformNameMapping; run the service-side
     compatibility validation for updates where available (⚠ verify).
   - Flink: assert every stateful operator has an explicit uid; restore the latest PROD savepoint into a STAGING job
     with the new jar (fail CI on non-restorable state).
4. Semantics: replay a fixed offset range in staging; diff outputs vs. the current version (Folder 01, file 01 §8, F1).
5. Rollback plan: snapshot or savepoint ID recorded; previous artifact pinned; DLQ replay plan if parsing changed.
```

---

## 6. Production failure modes and P99 debugging

| ID | Failure | Signature | Root cause | Fix |
|----|---------|-----------|------------|-----|
| U1 | **Dataflow update rejected** | compatibility check fails | renamed steps, changed coders or windowing on stateful steps, removed side inputs | `--transformNameMapping`; compatible coders; snapshot + new job for breaking changes |
| U2 | **Workers crash decoding state after update** | decode exceptions in stateful steps | coder changed without versioning | versioned coders with an extension block (file 01); roll back to the snapshot |
| U3 | **Truncated aggregates after drain** | final-looking windows missing late data | drain fires windows early | upsert sinks keyed by (key, window); corrections from the replacement job |
| U4 | **Data gap after cancel + restart** | missing range | the new job started at "latest" | restart from committed source positions or a snapshot |
| U5 | **Flink "cannot map state"** | restore fails | missing or changed `uid` | stable `uid`s; State Processor API rename |
| U6 | **Flink serializer incompatibility** | `StateMigrationException` / incompatible serializer | Kryo state; incompatible type change; TTL toggled | POJO or Avro serializers; offline migration (§5.4) |
| U7 | **Schema registry break** | consumers fail deserialization after a producer deploy | incompatible schema change allowed by a lax mode | enforce compatibility modes in CI; transitive checks |
| U8 | **Protobuf silent corruption** | wrong values, no errors | reused field numbers | `reserved` numbers; lint rules |
| U9 | **DLQ flood** | DLQ rate spikes; real failures masked | a systemic outage dead-lettering everything | circuit breakers for transient failures; DLQ only for permanent ones; alert on rate |
| U10 | **Replay duplicates** | double effects after DLQ replay | missing idempotency keys | replay with original keys; idempotent sinks (Folder 06, file 02) |

---

## 7. FAANG L7 bar-raiser Q&A chains

### Q1 · "Dataflow: update, drain, or cancel for a deploy that changes an aggregation's window size?"

**L5 textbook answer.** Use `--update`. It preserves state.

**Why L5 breaks.** Changing windowing on a stateful step is generally **not update-compatible**: state is addressed by
(key, window), and the windows themselves change. The update is rejected, or worse, semantics break. Drain fires all open
windows early with partial data. Cancel loses in-flight state.

**L7 principal defense.**

1. **It's a breaking change,** so plan a **replacement** rather than an in-place update.
2. **Option A:** run the new pipeline **in parallel** (new subscription or consumer group from a chosen position), let it
   warm up past the longest window plus lateness, switch consumers to its output, then drain the old one.
3. **Option B:** drain the old job (accepting partial final windows) with **upsert sinks keyed by (key, window)**, so the
   new job's outputs for overlapping windows supersede them.
4. **Snapshot first** for rollback. Pin the old artifact. Diff outputs during overlap.

### Q2 · "Flink: stop-with-savepoint vs. `--drain`. When is each right?"

**L5 textbook answer.** Drain is the graceful option, so always drain.

**Why L5 breaks.** `--drain` emits `MAX_WATERMARK`, which fires every event-time timer, so open windows emit **partial
results** and timers run "at the end of time". Restoring from a drained savepoint resumes with those windows already
emitted, which double-counts or truncates.

**L7 principal defense.** For **upgrades,** use stop-with-savepoint without drain: windows and timers stay in state and
resume on the new version. Use **`--drain` only to retire** a job permanently, when emitting final results is desired.
Prefer canonical savepoints for portability across backends and versions, and native ones for speed within the same
backend ⚠ verify the matrix.

### Q3 · "You need to change a state type from a Kryo-serialized class to a new POJO. How?"

**L5 textbook answer.** Change the class and restore. Flink handles schema evolution.

**Why L5 breaks.** Kryo has **no evolution guarantees**, and Flink can't migrate Kryo state. The restore fails with an
incompatible serializer, or deserializes garbage.

**L7 principal defense.**

1. **Offline migration with the State Processor API:** read the old savepoint with the old type, transform, and write a
   new savepoint with the POJO (or Avro) type under a new `uid` (§5.4).
2. **Deploy the new job** from the migrated savepoint.
3. **Going forward,** set `pipeline.generic-types=false` so Kryo can't creep back. Use POJO or Avro with evolution rules,
   and add compatibility tests to CI.

### Q4 · "Design the dead-letter strategy for a 500k events/s pipeline."

**L5 textbook answer.** Catch exceptions and write failed records to an error topic.

**Why L5 breaks at petabyte scale.** Catching everything turns a **dependency outage** into millions of dead-lettered
records, masking the outage and creating a replay nightmare. Envelopes without source coordinates or event time can't be
replayed correctly. Unbounded retries instead pin watermarks.

**L7 principal defense.**

- **Classify:**
  - **permanent** errors → DLQ immediately;
  - **transient** errors → retry with budget and jitter, then DLQ;
  - **systemic** errors → circuit-break, pause or slow intake, and alert. Don't DLQ.
- **The envelope:** payload, source coordinates, event time, stage, error class, stack hash, version, first seen.
- **Storage:** a Kafka DLQ topic (for replay) plus a BigQuery or lake table (for triage dashboards grouped by error class
  and version).
- **Replay tooling:** select by class or version, re-inject with original event time and idempotency keys, monitor
  lateness.
- **SLOs:** DLQ rate per million, new-error-class alerts, DLQ age.

### Q5 · "Which schema registry compatibility mode do you choose for a topic consumed by streaming jobs with savepoints?"

**L5 textbook answer.** BACKWARD, the default.

**Why L5 breaks.** BACKWARD checks only against the *previous* schema. A streaming job restoring from an old savepoint,
or replaying weeks of retained data, may read messages written several versions ago. Rolling back a consumer (old reader,
new data) needs FORWARD compatibility.

**L7 principal defense.**

- **Producers that may roll back while consumers lag:** **FULL_TRANSITIVE** (or at least BACKWARD_TRANSITIVE plus FORWARD
  for the last N versions).
- **Topics retained or replayed beyond one release:** **transitive** modes.
- **Enforce in CI,** before the producer deploys, and pair with versioned state coders so stored state follows the same
  discipline.

---

## 8. Invariants checklist

1. **State outlives code.** Every encoding needs backward compatibility, plus forward compatibility if rollback matters.
2. **Key encodings are frozen.** Changing them relocates state.
3. **Set explicit, versioned identities from day one:** Beam transform names, Flink `uid`s.
4. **Update for compatible changes; replacement for breaking ones.** Drain and `--drain` fire partial windows.
5. **Snapshot or savepoint before every risky deploy,** with the rollback artifact pinned.
6. **Failures are data:** classified, enveloped, replayable, and monitored as SLOs.
7. **Never Kryo in long-lived state.** Migrate offline with the State Processor API.

---

## 9. References

- Google Cloud Dataflow: *Update an existing pipeline*, *Stop a running pipeline* (drain vs. cancel), *Dataflow
  snapshots*.
- Apache Flink: *Savepoints*, *Checkpoints vs. Savepoints*, *State Schema Evolution*, *Custom State Serialization*,
  FLIP-263, *State Processor API*, *Kubernetes Operator: upgrade modes*.
- Confluent: *Schema Registry: schema evolution and compatibility*. Apache Avro specification (schema resolution).
  Protocol Buffers: *Updating a message type*.
- M. Kleppmann. *Designing Data-Intensive Applications*, ch. 4 (Encoding and Evolution).
- Apache Beam: `MapElements#exceptionsInto/exceptionsVia`, `WithFailures`, error handlers for I/Os ⚠ verify.

---

**End of Folder 07.** Next: `08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/`.
