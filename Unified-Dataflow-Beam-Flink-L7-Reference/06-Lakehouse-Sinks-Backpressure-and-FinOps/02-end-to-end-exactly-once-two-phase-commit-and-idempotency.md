# 02 · End-to-End Exactly-Once: Two-Phase Commit and Idempotency

> **Folder:** `06-Lakehouse-Sinks-Backpressure-and-FinOps/` · **File 2 of 3**
> **Anchoring papers and sources:** J. Gray, *Notes on Data Base Operating Systems* (1978): two-phase commit · Gray &
> Lamport, *Consensus on Transaction Commit* (ACM TODS 2006) · Kafka KIP-98 (*Exactly Once Delivery and Transactional
> Messaging*), KIP-890 (*Transactions Server-Side Defense*), KIP-939 (*Support Participation in 2PC*) · Flink FLIP-143 and
> FLIP-191 (unified Sink API, Sink V2) · Carbone et al., *State Management in Apache Flink* (PVLDB 2017) · Helland, *Life
> beyond Distributed Transactions* (CIDR 2007) · Kleppmann, *Designing Data-Intensive Applications* (ch. 9, 11).
> **Prev:** [01 · Iceberg and BigQuery sinks](01-streaming-into-iceberg-bigquery-and-small-file-compaction.md) · **Next:**
> [03 · Cloud FinOps](03-cloud-finops-dataflow-vs-flink-k8s-vs-spark-structured-streaming.md)

---

## 0. The thesis

End-to-end exactly-once means each input's effect appears in the external world **once**, under any failure. There are
exactly two ways to get it:

1. **Atomic visibility tied to the engine's consistency point.** In Flink, that's two-phase commit aligned with
   checkpoints: pre-commit at the barrier, commit when the checkpoint completes.
2. **Idempotent effects.** Retries are harmless because writes are keyed by deterministic IDs and guarded by versions.
   That's Dataflow's model (Folder 03), and often the better design on any engine.

2PC buys atomicity at the cost of **visibility latency** (a checkpoint interval), **coupling to checkpoint health**, and
**timeout-driven data loss** if commits are delayed past the external system's transaction timeout. Idempotency buys
decoupling at the cost of **key design** and **sink support**. Helland's maxim holds: at scale, prefer idempotent
messages and entities over distributed transactions.

---

## 1. First principles

### 1.1 The guarantee, formally

For input log $L$ and failure schedule $F$, the external state $X_F(L)$ must equal $X_\varnothing(L)$ (Folder 03,
file 03 §1). The engine's checkpoint gives exactly-once *internal* state. Externally, a record's effect can:

- **happen before the consistency point and be lost on rollback** (the replay re-applies it, so a duplicate), or
- **be withheld until the consistency point** (2PC), or
- **be applied any number of times with the same result** (idempotence).

### 1.2 Two-phase commit, mapped onto checkpoints

| 2PC role | Flink |
|----------|-------|
| Coordinator | `CheckpointCoordinator` (JobManager) |
| Participants | sink writers and committers |
| PREPARE | the barrier reaches the sink, which flushes and **pre-commits** (e.g., Kafka: flush the producer and keep the transaction open but complete; files: close and stage) and emits **committables** into checkpoint state |
| Vote | the sink acknowledges the checkpoint (the committables are durable in the checkpoint) |
| COMMIT decision | checkpoint *n* completes (metadata written) |
| COMMIT | `notifyCheckpointComplete(n)`, so the committer commits the committables for *n* (and anything earlier still pending) |
| Recovery | restore checkpoint *n*. Committables in state are **re-committed** (must be idempotent). Transactions newer than *n* are **aborted**. |

```mermaid
sequenceDiagram
    autonumber
    participant SRC as Sources
    participant SW as Sink writer
    participant JM as CheckpointCoordinator
    participant SC as Sink committer
    participant EXT as External system (Kafka / store)
    SRC->>SW: records (epoch n)
    SW->>EXT: write inside open transaction T_n
    JM-->>SW: barrier(n)
    SW->>EXT: flush T_n (prepared; not visible)
    SW->>JM: ack(n) with committable{T_n} in state
    JM->>JM: checkpoint n COMPLETE
    JM->>SC: notifyCheckpointComplete(n)
    SC->>EXT: commit T_n (idempotent)
    Note over SW,EXT: crash before COMPLETE → restore n-1 → abort T_n → replay<br/>crash after COMPLETE, before commit → restore n → re-commit T_n
```

### 1.3 The failure-point table

| Crash point | State after restore | External outcome | Correct? |
|-------------|---------------------|------------------|----------|
| Before the barrier reaches the sink | checkpoint *n−1* | $T_n$ open and uncommitted, so aborted (on restore or by timeout); records replayed into a new transaction | ✅ |
| After pre-commit, before checkpoint *n* completes | checkpoint *n−1* | $T_n$ prepared but not in a completed checkpoint, so **aborted**; replayed | ✅ |
| After checkpoint *n* completes, before the commit call | checkpoint *n* (contains $T_n$) | committer **re-commits** $T_n$ on restore | ✅ if commit is idempotent |
| Commit delayed longer than the **external transaction timeout** | checkpoint *n* | the external system **already aborted** $T_n$, so re-commit fails and **data is lost** | ❌ |
| Two jobs with the same transactional identity | — | the new producer **fences** the old (epoch bump); old writes fail | ✅ by design, ❌ if accidental |

**The timeout row is the critical one.** 2PC is safe only if the participant keeps prepared transactions alive until the
coordinator decides. Kafka transactions have a timeout. If checkpoints stall (backpressure, Folder 04) or the job is down
longer than the timeout, prepared data is aborted by the broker and **silently lost**.

---

## 2. Kafka transactions in depth

### 2.1 Mechanics (KIP-98)

- **A transactional producer** has a `transactional.id`. `initTransactions()` registers it with the **transaction
  coordinator**, bumps the **producer epoch** (fencing older instances), and aborts any of its unfinished transactions.
- **Writes within a transaction** go to partitions. Commit or abort is recorded through **control records** (markers) in
  each partition and in the transaction log (`__transaction_state`).
- **Consumers with `isolation.level=read_committed`** read only up to the **Last Stable Offset (LSO)**, the first offset of
  any still-open transaction. **One long-open transaction blocks every read_committed consumer on that partition** from
  progressing past it.

### 2.2 Flink `KafkaSink` with `EXACTLY_ONCE`

- **Transactional IDs** derive from a configured **prefix**, the subtask index, and a checkpoint-related counter. On
  restore, the sink probes and aborts lingering transactions for its prefix ⚠ verify the exact naming scheme and pooling
  behavior per connector version.
- **The prefix must be unique per job (and stable across restarts of the same job).** Two jobs sharing a prefix fence each
  other. A changed prefix leaves old transactions lingering (holding the LSO) until they time out.

**Timeouts must satisfy:**

$$
T_{\text{txn timeout}} \;>\; T_{\text{checkpoint interval}} + T_{\text{max checkpoint duration}} + T_{\text{max restart/downtime you want to survive}}
$$

and the broker's `transaction.max.timeout.ms` (default 15 min) must be ≥ the producer's `transaction.timeout.ms`.
Flink's default producer transaction timeout has historically been larger (1 hour), which fails at producer init until
the two are aligned ⚠ verify defaults.

**Visibility latency for `read_committed` consumers** ≈ checkpoint interval + checkpoint duration. A 1-minute interval
means downstream sees data in about 1–2-minute steps.

**Newer Kafka work** (KIP-890's server-side defenses against hanging transactions, and KIP-939 for participating in an
external 2PC coordinator) improves robustness and opens cleaner integration paths. Check connector support for your
versions ⚠ verify.

### 2.3 Dataflow / Beam

- **`KafkaIO.write().withEOS(numShards, sinkGroupId)`** uses Kafka transactions keyed per shard, with runner-managed state
  for sequencing (Folder 03, file 03 §8.5).
- **Beam has no generic 2PC.** Dataflow commits per bundle, so sinks rely on idempotence, offsets (BigQuery Storage Write
  API), or transactions per bundle/shard.
- **Beam on Flink:** `@RequiresStableInput` buffers input until the checkpoint completes, so a sink's writes happen only
  for checkpointed input. That makes deterministic or idempotent writes effectively exactly-once, at a latency of one
  checkpoint interval.

---

## 3. Idempotency: usually the better design

### 3.1 Idempotent effect patterns

| Pattern | Mechanism | Example |
|---------|-----------|---------|
| **Keyed upsert with version guard** | `INSERT … ON CONFLICT DO UPDATE … WHERE stored.version < new.version` | pane-versioned aggregates (Folder 01, file 03 §9.2); CDC state tables |
| **Insert-if-absent by event ID** (inbox) | dedup table and effect in the **same local transaction** | ledger postings, payments |
| **Deterministic object names + conditional put** | write `…/checkpoint-<n>/part-<k>`; if it exists, it's already done | file sinks, atomic publish |
| **Idempotency keys on APIs** | the provider dedups by key (Stripe-style) | payments, notifications |
| **Commutative and idempotent data types** | max, set union, CRDTs | counters as G-counters per writer, last-writer-wins by version |

### 3.2 Idempotency vs. 2PC

| Dimension | 2PC (Flink checkpoint-aligned) | Idempotent writes |
|-----------|-------------------------------|-------------------|
| Visibility latency | checkpoint interval | per write (ms) |
| Coupling | sink freshness tied to checkpoint health | independent |
| Failure mode | **data loss** if commit > external timeout | duplicates are harmless |
| Sink requirement | transactions (Kafka, XA, staged files) | keys + upsert / conditional writes |
| Throughput | batched per checkpoint | per-write overhead (batch it) |
| Ordering | atomic batch per checkpoint | needs a version guard for reordering |

**Default to idempotent writes. Use 2PC when the sink is an append-only log whose consumers can't dedup** (Kafka topics
read by many consumers) or when **atomic multi-record visibility** is required (all-or-nothing per epoch).

---

## 4. JDBC and databases

| Approach | How | Caveats |
|----------|-----|---------|
| **XA exactly-once** (Flink JDBC `exactlyOnceSink`) | prepared XA transactions per checkpoint; commit on completion | DB XA support required (Postgres needs `max_prepared_transactions > 0`); **prepared transactions hold locks** until commit; long checkpoints mean long-held locks and bloat; orphan prepared transactions after crashes need recovery |
| **Idempotent upsert** | `ON CONFLICT … WHERE version <` | requires a key and version; the simplest robust choice |
| **Inbox pattern** | insert event ID + apply effect in one local transaction | requires the effect to be in the same database |
| **Outbox pattern** (producer side) | write business row + outbox row in one transaction; CDC publishes the outbox | exactly-once *publishing* from OLTP without dual writes |

---

## 5. Hardware sympathy: the cost of exactly-once

| Mechanism | Cost driver |
|-----------|-------------|
| Kafka transactions | coordinator round trips per transaction; control records per partition; read_committed consumers wait for the LSO |
| Checkpoint-aligned commits | output bursts at each checkpoint (commit storms); sink load is periodic, not smooth |
| XA | lock retention; WAL growth for prepared transactions |
| Idempotent upserts | index lookups per write (unique key); version comparisons; batch to amortize |
| Inbox dedup tables | an index insert per event; GC of old IDs (partition by day, drop old partitions) |

---

## 6. Production Java 21 code blueprints

### 6.1 Anti-patterns

```java
// (A) "Exactly-once" Kafka sink with a transaction timeout shorter than worst-case checkpoint + restart time.
KafkaSink.<String>builder()
    .setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
    .setTransactionalIdPrefix("orders")              // (B) shared by two jobs → mutual fencing
    .setProperty("transaction.timeout.ms", "60000")   // 1 min, with 2-min checkpoints → broker aborts → DATA LOSS
    // ...

// (C) Side effects inside a RichMapFunction: replayed after every failure → duplicates downstream.
public Enriched map(Event e) { emailClient.send(e.user(), template(e)); return enrich(e); }

// (D) XA sink with 10-minute checkpoints on a hot OLTP table: prepared transactions hold row locks for minutes.
```

### 6.2 Flink: correctly configured transactional Kafka sink

```java
package dev.l7.eos;

import java.time.Duration;
import java.util.Properties;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;

public final class TransactionalKafka {

  /**
   * Invariant: txn timeout > checkpoint interval + max checkpoint duration + tolerated downtime,
   * and broker transaction.max.timeout.ms ≥ producer transaction.timeout.ms.
   */
  public static KafkaSink<String> sink(String brokers, String topic, String jobScopedPrefix,
                                       Duration checkpointInterval, Duration maxCheckpointDuration,
                                       Duration toleratedDowntime) {
    long txnTimeoutMs = checkpointInterval.plus(maxCheckpointDuration).plus(toleratedDowntime).toMillis();
    Properties producer = new Properties();
    producer.setProperty("transaction.timeout.ms", Long.toString(txnTimeoutMs));
    producer.setProperty("enable.idempotence", "true");
    producer.setProperty("compression.type", "lz4");

    return KafkaSink.<String>builder()
        .setBootstrapServers(brokers)
        .setKafkaProducerConfig(producer)
        .setRecordSerializer(KafkaRecordSerializationSchema.builder()
            .setTopic(topic)
            .setValueSerializationSchema(new SimpleStringSchema())
            .build())
        .setDeliveryGuarantee(DeliveryGuarantee.EXACTLY_ONCE)
        .setTransactionalIdPrefix(jobScopedPrefix)   // unique per job, stable across restarts of THAT job
        .build();
  }
}
// Downstream consumers: isolation.level=read_committed (visibility ≈ checkpoint cadence).
// Monitor: checkpoint duration vs. txn timeout headroom; consumer LSO lag; aborted-transaction rate.
```

### 6.3 Flink Sink V2: a checkpoint-aligned atomic-publish sink (⚠ verify interfaces for your Flink version)

```java
package dev.l7.eos;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.Serializable;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.apache.flink.api.connector.sink2.Committer;
import org.apache.flink.api.connector.sink2.CommitterInitContext;
import org.apache.flink.api.connector.sink2.CommittingSinkWriter;
import org.apache.flink.api.connector.sink2.Sink;
import org.apache.flink.api.connector.sink2.SinkWriter;
import org.apache.flink.api.connector.sink2.SupportsCommitter;
import org.apache.flink.api.connector.sink2.WriterInitContext;
import org.apache.flink.core.io.SimpleVersionedSerializer;

/**
 * Two-phase commit onto an object store / filesystem:
 *   write  → records go to an IN-PROGRESS object (invisible to readers),
 *   PREPARE (barrier) → close it; committable = (temp, final) goes into checkpoint state,
 *   COMMIT (checkpoint complete) → atomically publish temp → final; IDEMPOTENT (final exists ⇒ already committed).
 * Temp objects from epochs that never completed are orphans → clean up by age (like Iceberg orphan removal).
 */
public final class AtomicPublishSink implements Sink<String>, SupportsCommitter<AtomicPublishSink.Staged> {

  public record Staged(String tempPath, String finalPath) implements Serializable {}

  /** Minimal storage contract. publish() must be atomic: HDFS rename, or conditional put / copy on object stores. */
  public interface ObjectStore extends Serializable {
    Appender create(String path) throws IOException;

    boolean exists(String path) throws IOException;

    void publish(String tempPath, String finalPath) throws IOException;

    interface Appender extends AutoCloseable {
      void append(String line) throws IOException;

      @Override
      void close() throws IOException;
    }
  }

  private final ObjectStore store;
  private final String baseDir;

  public AtomicPublishSink(ObjectStore store, String baseDir) {
    this.store = store;
    this.baseDir = baseDir;
  }

  @Override
  public SinkWriter<String> createWriter(WriterInitContext ctx) {
    return new Writer(store, baseDir, ctx.getTaskInfo().getIndexOfThisSubtask());
  }

  @Override
  public Committer<Staged> createCommitter(CommitterInitContext ctx) {
    return new PublishCommitter(store);
  }

  @Override
  public SimpleVersionedSerializer<Staged> getCommittableSerializer() {
    return new StagedSerializer();
  }

  static final class Writer implements CommittingSinkWriter<String, Staged> {
    private final ObjectStore store;
    private final String baseDir;
    private final int subtask;
    private ObjectStore.Appender current;
    private String currentTemp;
    private String currentFinal;

    Writer(ObjectStore store, String baseDir, int subtask) {
      this.store = store;
      this.baseDir = baseDir;
      this.subtask = subtask;
    }

    @Override
    public void write(String element, Context context) throws IOException {
      if (current == null) {
        String name = "part-" + subtask + "-" + UUID.randomUUID();           // the committable fixes the name
        currentFinal = baseDir + "/" + name + ".jsonl";
        currentTemp = baseDir + "/_inprogress/" + name + ".jsonl";
        current = store.create(currentTemp);
      }
      current.append(element);
    }

    @Override
    public void flush(boolean endOfInput) {
      // Data becomes durable at prepareCommit (close). Nothing to do here.
    }

    @Override
    public Collection<Staged> prepareCommit() throws IOException {
      if (current == null) {
        return List.of();
      }
      current.close();                                                       // PREPARE: complete but invisible
      Staged staged = new Staged(currentTemp, currentFinal);
      current = null;
      return List.of(staged);                                                // goes into checkpoint state
    }

    @Override
    public void close() throws IOException {
      if (current != null) {
        current.close();                                                     // un-prepared temp → orphan by design
      }
    }
  }

  static final class PublishCommitter implements Committer<Staged> {
    private final ObjectStore store;

    PublishCommitter(ObjectStore store) {
      this.store = store;
    }

    @Override
    public void commit(Collection<CommitRequest<Staged>> requests) {
      for (CommitRequest<Staged> r : requests) {
        Staged s = r.getCommittable();
        try {
          if (store.exists(s.finalPath())) {
            r.signalAlreadyCommitted();                                      // re-commit after restore: no-op
          } else if (!store.exists(s.tempPath())) {
            r.signalFailedWithKnownReason(new IllegalStateException("staged object missing: " + s));
          } else {
            store.publish(s.tempPath(), s.finalPath());                      // COMMIT (atomic)
          }
        } catch (IOException transientError) {
          r.retryLater();                                                    // retried by the framework
        }
      }
    }

    @Override
    public void close() {
    }
  }

  static final class StagedSerializer implements SimpleVersionedSerializer<Staged> {
    @Override
    public int getVersion() {
      return 1;
    }

    @Override
    public byte[] serialize(Staged s) throws IOException {
      ByteArrayOutputStream bytes = new ByteArrayOutputStream();
      try (DataOutputStream out = new DataOutputStream(bytes)) {
        out.writeUTF(s.tempPath());
        out.writeUTF(s.finalPath());
      }
      return bytes.toByteArray();
    }

    @Override
    public Staged deserialize(int version, byte[] serialized) throws IOException {
      if (version != 1) {
        throw new IOException("unknown committable version " + version);   // versioned for safe upgrades
      }
      try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(serialized))) {
        return new Staged(in.readUTF(), in.readUTF());
      }
    }
  }
}
```

### 6.4 Idempotent database effects: versioned upsert and the inbox pattern

```java
package dev.l7.eos;

import org.apache.flink.connector.jdbc.JdbcConnectionOptions;
import org.apache.flink.connector.jdbc.JdbcExecutionOptions;
import org.apache.flink.connector.jdbc.JdbcSink;
import org.apache.flink.streaming.api.functions.sink.SinkFunction;

public final class IdempotentJdbc {

  public record OrderState(String orderId, String status, long version) {}

  public record Posting(String eventId, String accountId, long amountCents) {}

  /** Current-state table: replays and reorders are harmless (version guard). */
  static final String UPSERT = """
      INSERT INTO order_state AS t (order_id, status, version) VALUES (?, ?, ?)
      ON CONFLICT (order_id) DO UPDATE SET status = EXCLUDED.status, version = EXCLUDED.version
      WHERE t.version < EXCLUDED.version
      """;

  /** Ledger effect applied at most once per event: dedup row and balance update in ONE statement/transaction. */
  static final String INBOX_APPLY = """
      WITH ins AS (
        INSERT INTO processed_events (event_id) VALUES (?) ON CONFLICT DO NOTHING RETURNING 1
      )
      UPDATE accounts SET balance_cents = balance_cents + ?
      WHERE account_id = ? AND EXISTS (SELECT 1 FROM ins)
      """;

  public static SinkFunction<OrderState> orderStateSink(String url, String user, String password) {
    return JdbcSink.sink(UPSERT,
        (ps, o) -> {
          ps.setString(1, o.orderId());
          ps.setString(2, o.status());
          ps.setLong(3, o.version());
        },
        JdbcExecutionOptions.builder().withBatchSize(500).withBatchIntervalMs(200).withMaxRetries(5).build(),
        new JdbcConnectionOptions.JdbcConnectionOptionsBuilder().withUrl(url)
            .withUsername(user).withPassword(password).build());
  }

  public static SinkFunction<Posting> ledgerSink(String url, String user, String password) {
    return JdbcSink.sink(INBOX_APPLY,
        (ps, p) -> {
          ps.setString(1, p.eventId());
          ps.setLong(2, p.amountCents());
          ps.setString(3, p.accountId());
        },
        JdbcExecutionOptions.builder().withBatchSize(200).withMaxRetries(5).build(),
        new JdbcConnectionOptions.JdbcConnectionOptionsBuilder().withUrl(url)
            .withUsername(user).withPassword(password).build());
  }
}
```

The JDBC connector's sink API has moved across versions (legacy `SinkFunction`-returning factories vs. newer Sink V2
builders) ⚠ verify for your connector release. **The SQL is the durable part.** `processed_events` should be partitioned
by day and pruned beyond the maximum replay horizon.

---

## 7. Production failure modes and P99 debugging

| ID | Failure | Signature | Root cause | Fix |
|----|---------|-----------|------------|-----|
| T1 | **Silent loss after a long outage** | gaps in sink data covering the outage window; aborted transactions in broker metrics | prepared transactions exceeded `transaction.timeout.ms` | timeout > interval + checkpoint duration + tolerated downtime; alert on headroom |
| T2 | **Producer init failures** | "transaction timeout is larger than the maximum allowed by the broker" | producer timeout > broker `transaction.max.timeout.ms` | align broker and producer settings |
| T3 | **read_committed consumers stuck** | consumer lag grows while the topic receives data; LSO stuck | a long-open or lingering transaction (job down; changed prefix) | stable prefixes; abort lingering transactions; shorter checkpoint durations |
| T4 | **`ProducerFencedException` loops** | sink restarts repeatedly after a deploy | two jobs or instances with the same transactional identity | unique prefix per job; stop the old job before starting the new |
| T5 | **Duplicates despite "exactly-once"** | dupes downstream | side effects outside the sink (in map functions); non-transactional consumers; at-least-once sinks | effects only in sinks; idempotent keys; read_committed |
| T6 | **Freshness tied to checkpoint health** | sink data stops when checkpoints fail | 2PC visibility | fix checkpoints (Folder 04); consider idempotent sinks for freshness-critical outputs |
| T7 | **XA lock contention** | OLTP latency spikes; lock waits | prepared transactions held for the checkpoint duration | upserts or inbox instead of XA; shorter intervals |
| T8 | **Orphan staged files** | storage grows with temp objects | epochs that never committed | age-based cleanup with margins |
| T9 | **Commit storms** | periodic sink latency spikes at each checkpoint | batched commits per checkpoint | spread checkpoints; smaller intervals; sink capacity |

### Runbook · T1 (data missing after an incident)

1. List incidents where the job was down or checkpoints were failing longer than `transaction.timeout.ms`.
2. Check the broker's aborted-transaction metrics and the transaction log for the job's prefix around that time.
3. Recover by **replaying from source offsets** covering the window into the sink (the dedup or idempotency strategy
   decides whether a replay is safe).
4. Prevent it:
   - timeout headroom alerts (timeout − (interval + p99 checkpoint duration + current downtime));
   - set the timeout from the RTO you commit to;
   - consider idempotent sinks for data where loss is unacceptable and duplicates are cheap to absorb.

---

## 8. FAANG L7 bar-raiser Q&A chains

### Q1 · "How does Flink achieve exactly-once into Kafka? What can still go wrong?"

**L5 textbook answer.** Flink uses Kafka transactions committed on checkpoints, so it's exactly-once.

**Why L5 breaks at petabyte scale.** The mechanism has a **timeout-dependent safety condition** and couples freshness to
checkpoint health. In real incidents, jobs down longer than the transaction timeout lose data silently, and lingering
transactions stall every `read_committed` consumer.

**L7 principal defense.**

1. **2PC mapped onto checkpoints:** pre-commit at the barrier, committables in state, commit on completion, idempotent
   re-commit after restore, abort of newer transactions (§1.2).
2. **The safety condition:** txn timeout > interval + checkpoint duration + tolerated downtime, and broker max ≥ producer
   timeout.
3. **Fencing:** a unique, stable transactional ID prefix per job, and producer epochs.
4. **Consumer side:** read_committed and the LSO. Visibility ≈ checkpoint cadence, and long-open transactions block
   readers.
5. **Operations:** headroom alerts, prefix hygiene, a replay plan for data lost to timeouts.

### Q2 · "2PC or idempotent writes for a payments ledger fed by a stream?"

**L5 textbook answer.** 2PC, because money needs transactions.

**Why L5 breaks.** XA 2PC holds database locks for a checkpoint interval on hot rows, couples ledger availability to
checkpoint health, and brings operational pain (orphan prepared transactions). Money needs **at-most-once effects per
event and auditability**, which the inbox pattern provides with a single local transaction.

**L7 principal defense.**

- **Inbox pattern:** insert the event ID into a dedup table and apply the posting in **the same local transaction**
  (§6.4). Replays become no-ops, there are no distributed locks, and every event is auditable.
- **Deterministic event IDs** from upstream (Folder 03, file 03 §3.2).
- **Producer side:** the outbox pattern for publishing ledger events without dual writes.
- **Reserve 2PC** for sinks that can't dedup (append-only logs read by many consumers).

### Q3 · "Our Iceberg tables stop updating whenever checkpoints fail. Why, and is that acceptable?"

**L5 textbook answer.** Checkpoints are failing, so fix them.

**Why L5 breaks.** That's right but incomplete. Iceberg commits *are* checkpoint-aligned 2PC, so **freshness is a function
of checkpoint health**. The architecture choice made checkpoint SLOs part of the data freshness SLO.

**L7 principal defense.**

- **The coupling is the price of exactly-once atomic visibility.** Alert on snapshot age (freshness) alongside
  checkpoint metrics.
- **Fix checkpoint health:** backpressure, alignment, upload (Folder 04).
- **If freshness is critical beyond checkpoint reliability,** consider a decoupled path. Write idempotently to a
  low-latency store for serving, and keep the Iceberg table as the exactly-once system of record.

### Q4 · "Why must a Sink V2 committer be idempotent?"

**L5 textbook answer.** For safety.

**Why L5 breaks.** "For safety" doesn't name the failure: a crash after checkpoint completion but before or during commit.
On restore, the committables from the completed checkpoint are committed *again*.

**L7 principal defense.**

- **Notifications are best effort,** and restore re-delivers committables from completed checkpoints, so commit(T) can
  run twice.
- **Implement "already committed" detection:**
  - the final object exists;
  - a Kafka transaction is already committed (the producer API tolerates re-commit of a recovered transaction);
  - for Iceberg, the snapshot summary has max-committed-checkpoint ≥ n.
- **Signal `alreadyCommitted`** rather than failing.

---

## 9. Invariants checklist

1. **Exactly-once effects require atomic visibility (2PC) or idempotence.** There's no third way.
2. **2PC safety:** external transaction timeout > interval + checkpoint duration + tolerated downtime.
3. **Committers must be idempotent.** Restores re-commit.
4. **Transactional identities must be unique per job and stable across restarts.**
5. **Side effects belong in sinks, never in map functions.**
6. **Prefer idempotent writes** (versioned upserts, inbox, conditional puts). Use 2PC for non-dedupable append logs.
7. **2PC freshness = checkpoint health.** Alert on both.

---

## 10. References

- J. Gray. *Notes on Data Base Operating Systems.* 1978. J. Gray, L. Lamport. *Consensus on Transaction Commit.* ACM
  TODS 31(1), 2006.
- P. Helland. *Life beyond Distributed Transactions: an Apostate's Opinion.* CIDR 2007.
- M. Kleppmann. *Designing Data-Intensive Applications.* O'Reilly, 2017 (ch. 9 consistency and consensus, ch. 11 stream
  processing).
- Apache Kafka: KIP-98 (exactly-once and transactions), KIP-890 (transactions server-side defense), KIP-939 (2PC
  participation).
- Apache Flink: FLIP-143 and FLIP-191 (Sink API / Sink V2), *Kafka connector: exactly-once*, *JDBC connector:
  exactly-once (XA)*.
- P. Carbone et al. *State Management in Apache Flink.* PVLDB 10(12), 2017.

**Next →** [03 · Cloud FinOps: Dataflow vs. Flink on Kubernetes vs. Spark Structured Streaming](03-cloud-finops-dataflow-vs-flink-k8s-vs-spark-structured-streaming.md)
