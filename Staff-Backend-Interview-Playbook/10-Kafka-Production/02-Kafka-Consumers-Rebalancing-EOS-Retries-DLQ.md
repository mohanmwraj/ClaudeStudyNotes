# 10.2 Kafka Consumers: Groups, Lag, Rebalancing (Eager vs Cooperative vs KIP-848), Exactly-Once, Retries and DLQs

> **Verified stack:** Apache Kafka clients **4.2.2** + embedded single-node KRaft broker (`kafka-server` 4.2.2), spring-kafka **4.1.2** (Spring Framework 7.0.10), JDK **25.0.4.1**. Defaults were printed from `ConsumerConfig.configDef()` and a fresh `DefaultErrorHandler`; every scenario was run (`KafkaConsumerLab.java`, `ConsumerOpsLab.java`, `RetryTopicLab.java`). Rebalance **timings** depend on heartbeat intervals and a single local broker; the *what moved* is the result to remember.
>
> **Prereqs:** [10.1 producers](01-Kafka-Producers-Batching-Idempotence-Ordering.md). **Related:** [5.4 idempotent consumer](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md), [7.4 KEDA lag scaling](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md), sibling kit [6.5 consumer groups](../../Java-Backend-Master-Reference/06-Spring-Microservices/05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md).

---

## 0. First principles: a position in a log 🔥

A consumer doesn't receive messages; it **reads a log from a position** (an offset) and periodically saves that position. Everything follows from three facts:

1. **A partition is read by exactly one consumer in a group.** Parallelism is capped by the partition count.
2. **The committed offset is the *next* offset to read**, stored in the internal `__consumer_offsets` topic. After a crash, the group resumes from there.
3. **Processing and committing are two separate steps**, so their order decides the delivery semantics:

| Order | Semantics | Failure between the steps |
|---|---|---|
| Process, then commit | **At-least-once** | Reprocessed after restart (duplicates) |
| Commit, then process | **At-most-once** | Lost |
| Process + commit atomically | **Exactly-once effects** | Kafka→Kafka: transactions (§5). Kafka→DB: dedup row + effect in one DB transaction ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)) |

### 0.1 Defaults in kafka-clients 4.2.2 (verified)

```text
  group.protocol                   classic
  partition.assignment.strategy    [class org.apache.kafka.clients.consumer.RangeAssignor, class org.apache.kafka.clients.consumer.CooperativeStickyAssignor]
  max.poll.records                 500
  max.poll.interval.ms             300000
  session.timeout.ms               45000
  heartbeat.interval.ms            3000
  enable.auto.commit               true
  auto.commit.interval.ms          5000
  isolation.level                  read_uncommitted
  auto.offset.reset                latest
  fetch.min.bytes                  1
  fetch.max.wait.ms                500
  max.partition.fetch.bytes        1048576
```

Things worth saying out loud: the classic protocol is still the default; the assignor list starts with the **eager** `RangeAssignor`; auto-commit is **on**; isolation is **`read_uncommitted`**; and a new group starts at **`latest`**, so a new consumer group silently skips everything already in the topic unless you set `earliest`.

---

## 1. Under the hood: the poll loop ⚡

```text
while (running) {
    records = consumer.poll(timeout)        ← fetches from partition leaders (fetch.min.bytes / fetch.max.wait.ms),
                                              returns ≤ max.poll.records; also drives group membership,
                                              rebalance callbacks and auto-commit of the PREVIOUS batch
    process(records)                        ← your code: must finish within max.poll.interval.ms
    commit (or let auto-commit do it on the next poll)
}

background heartbeat thread (classic protocol): "I'm alive" every heartbeat.interval.ms;
    the coordinator evicts after session.timeout.ms without heartbeats  → detects DEAD processes
max.poll.interval.ms: if poll() isn't called again in time, the client itself leaves the group
                                                                     → detects STUCK processing
```

`KafkaConsumer` is **not thread-safe**: one consumer per thread. Spring Kafka's `concurrency: 3` means three consumers, each on its own thread, in the same group.

### 1.1 Verified: processing that outlives `max.poll.interval.ms`

Batch processing takes 6 s, `max.poll.interval.ms=3000`, manual commit:

```text
== 2. Processing a batch takes 6 s, max.poll.interval.ms = 3000
  assigned [0, 1, 2]
  polled 50 records; processing...
  commitSync -> CommitFailedException: Offset commit cannot be completed since the consumer is not part of an active group for auto partition assignment; it is likely that the consumer was kicked out of the group.
  LOST [0, 1, 2] (the group moved on without us)
  assigned [0, 1, 2]
  next poll re-delivers from the last committed offsets: [0@0] -> the batch is processed twice
```

The client log said: *"consumer poll timeout has expired. This means the time between subsequent calls to poll() was longer than the configured max.poll.interval.ms…"*. The work was done, the commit was refused, the partitions were **lost** (not gracefully revoked), and the batch was **processed again**. In production this shows up as a "rebalance storm": every slow batch triggers a rebalance, which triggers redelivery, which is slow again.

Fixes, in order:

1. Make processing per poll **bounded**: lower `max.poll.records` (500 records × 50 ms each = 25 s).
2. Raise `max.poll.interval.ms` to cover the honest worst case, but not to hours, or a truly stuck consumer holds partitions forever.
3. Move slow work off the poll thread **and** pause the partitions (`consumer.pause`) until it finishes, committing only completed offsets.
4. Make processing idempotent anyway (§0).

### 1.2 Verified: consumer lag

Lag is the distance between the end of the log and the group's committed position, **per partition**:

```java
Map<TopicPartition, OffsetAndMetadata> committed =
        admin.listConsumerGroupOffsets("billing").partitionsToOffsetAndMetadata().get();
Map<TopicPartition, ListOffsetsResultInfo> ends = admin.listOffsets(latestSpecs).all().get();
long lag = ends.get(tp).offset() - committed.get(tp).offset();
```

900 records across 3 partitions; the consumer processed 300 and committed:

```text
== 1. Lag = log-end offset - committed offset, per partition (consumer processed 300 then committed)
  orders-0  log-end=289  committed=289  lag=0
  orders-1  log-end=308  committed=11  lag=297
  orders-2  log-end=303  committed=0  lag=303
  total lag = 600
```

The **total** hides the story: partition 0 is caught up, partitions 1 and 2 aren't. Alert on **per-partition lag** and on **lag growth rate** (or time lag: the age of the oldest unconsumed record). A total that's flat but nonzero is fine; a lag that keeps climbing is an incident.

---

## 2. Rebalancing: eager vs cooperative vs KIP-848 🔥

A rebalance reassigns partitions when members join, leave, crash or change subscriptions. The question is **how much work stops** while it happens.

### 2.1 Verified: c1 owns 6 partitions, c2 joins

(Output from one run; the `←` annotations are added.)

```text
== Classic protocol, eager RangeAssignor
    2251 ms  c1 ASSIGNED [0, 1, 2, 3, 4, 5]   now owns [0, 1, 2, 3, 4, 5]
    2753 ms  c2 subscribes
    5262 ms  c1 REVOKED  [0, 1, 2, 3, 4, 5]                     ← EVERYTHING stops, including partitions that stay with c1
    5269 ms  c2 ASSIGNED [3, 4, 5]   now owns [3, 4, 5]
    5269 ms  c1 ASSIGNED [0, 1, 2]   now owns [0, 1, 2]
    5269 ms  (c2 got work 2516 ms after subscribing)
== Classic protocol, CooperativeStickyAssignor (incremental)
    7343 ms  c1 ASSIGNED [0, 1, 2, 3, 4, 5]   now owns [0, 1, 2, 3, 4, 5]
    7845 ms  c2 subscribes
   10357 ms  c1 REVOKED  [3, 4, 5]                              ← only the partitions that MOVE
   10357 ms  c2 ASSIGNED []   now owns []                       ← round 1: nothing yet
   10357 ms  c1 ASSIGNED []   now owns [0, 1, 2]                ← c1 never stopped consuming 0-2
   13358 ms  c2 ASSIGNED [3, 4, 5]   now owns [3, 4, 5]         ← round 2: the freed partitions
   13358 ms  c1 ASSIGNED []   now owns [0, 1, 2]
   13358 ms  (c2 got work 5513 ms after subscribing)
== KIP-848 consumer protocol (group.protocol=consumer, server-side assignment)
   15504 ms  c1 ASSIGNED [0, 1, 2, 3, 4, 5]   now owns [0, 1, 2, 3, 4, 5]
   16005 ms  c2 subscribes
   16028 ms  c2 ASSIGNED []   now owns []                       ← member joins instantly, no group-wide barrier
   20702 ms  c1 REVOKED  [3, 4, 5]                              ← c1 releases on its next heartbeat
   20704 ms  c1 ASSIGNED []   now owns [0, 1, 2]
   21081 ms  c2 ASSIGNED [3, 4, 5]   now owns [3, 4, 5]
   21081 ms  (c2 got work 5076 ms after subscribing)
```

| | Eager (Range, RoundRobin) | Cooperative (CooperativeSticky) | KIP-848 (`group.protocol=consumer`) |
|---|---|---|---|
| Who computes the assignment | A consumer (the group leader) | A consumer (the group leader) | **The broker's group coordinator** (assignors `uniform`, `range`, per the broker config dump) |
| What's revoked | **All** partitions of **all** members | Only partitions that move | Only partitions that move |
| Barrier | Every member must rejoin (JoinGroup + SyncGroup) | Same, but twice | **None**: each member reconciles on its own heartbeat |
| Work stopped during rebalance | Everything | Only the moving partitions | Only the moving partitions |
| Client complexity | Simple | Two-phase | Simple client, logic on the broker |

Why c2 waited *longer* in the cooperative and KIP-848 runs: cooperative needs **two** rounds, and KIP-848 reconciles on heartbeats (the broker's `group.consumer.heartbeat.interval.ms = 5000` in this run). The win isn't that the new member starts sooner. It's that **c1 never stopped processing partitions 0–2**. In an eager group of 30 consumers, one pod restarting pauses all 30. In a cooperative or KIP-848 group, it pauses only that pod's partitions.

### 2.2 Making rebalances rare and cheap ⚡

* **Static membership** (`group.instance.id` = the pod name from a **StatefulSet**, or another id that survives restarts): a restart within `session.timeout.ms` rejoins as the same member, with **no rebalance**. ⚠️ **Not for Deployments:** their pods get a new name on every rollout, which turned each replacement into a 45 s stall, and every scale-down of a static member waits the session timeout ([10.4 §1–2](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)).
* **Migrate eager → cooperative** with two rolling bounces: first `[CooperativeStickyAssignor, RangeAssignor]` (both), then `[CooperativeStickyAssignor]` alone. Or move to **KIP-848** (`group.protocol=consumer`, GA since Kafka 4.0). Note that client-side assignor settings don't apply under KIP-848; `group.remote.assignor` picks the broker-side one.
* **Commit in `onPartitionsRevoked`**, flush local state, and stop in-flight work for exactly the revoked partitions. `onPartitionsLost` (verified above) means you **can't** commit anymore: someone else may already own them.
* **Graceful shutdown**: for a **dynamic** member, `consumer.close()` leaves the group immediately, instead of the group waiting `session.timeout.ms` (45 s) to notice. A **static** member's `close()` deliberately doesn't leave ([10.4 §1.1](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)). In Kubernetes, `terminationGracePeriodSeconds` must cover the in-flight batch and the container stop ([10.4 §6.3](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md), [7.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)).

---

## 3. Commits in Spring Kafka ⚡

* The listener container sets `enable.auto.commit=false` unless you set it, and commits itself according to `AckMode`.
* `AckMode.BATCH` (default): commit after the listener has processed **all** records returned by one poll. `RECORD`: after each record (more commits, less redelivery). `MANUAL` / `MANUAL_IMMEDIATE`: your code calls `Acknowledgment.acknowledge()`.
* **Never hand records to another thread pool and return** with auto/batch commits: the offset commits while the work is still queued, and a crash loses it (at-most-once by accident).

---

## 4. Retries and dead-letter topics 🔥

### 4.1 Two strategies

**Blocking retries** (`DefaultErrorHandler`): the container re-seeks the partition to the failed record and redelivers it, holding up everything behind it on that partition. The default backoff, read from a fresh 4.1.2 handler, is `FixedBackOff[interval=0, maxAttempts=9]`: **10 delivery attempts with no delay**, then log and skip. In production you give it a backoff and a recoverer:

```java
var eh = new DefaultErrorHandler(new DeadLetterPublishingRecoverer(template), new FixedBackOff(1000, 3));  // 1 try + 3 retries
eh.addNotRetryableExceptions(IllegalArgumentException.class);   // permanent errors go straight to the DLT
factory.setCommonErrorHandler(eh);
```

**Non-blocking retries** (`@RetryableTopic`): the failed record is **republished** to a retry topic with a "not before" timestamp header. A consumer of that topic pauses the partition until the record is due, then retries. The main partition keeps flowing.

```java
@RetryableTopic(attempts = "4", backOff = @BackOff(delay = 1000, multiplier = 2.0),   // spring-kafka 4: org.springframework.kafka.annotation.BackOff
                exclude = IllegalArgumentException.class)
@KafkaListener(id = "nb", topics = "payments-nb")
public void on(ConsumerRecord<String, String> r) { ... }

@DltHandler
public void dlt(ConsumerRecord<String, String> r) { ... }       // alert, store, offer replay
```

Spring Kafka 4 dropped the `spring-retry` dependency: `@RetryableTopic` takes the Kafka project's own `@BackOff` annotation, not `org.springframework.retry.annotation.Backoff`.

### 4.2 Verified: the same three records through both

Same key (one partition), sent in order `poison-1` (always throws `IllegalStateException`), `next-1` (fine), `bad-1` (throws non-retryable `IllegalArgumentException`). Output from one run; the `←` annotations are added and empty `header occurrences: []` lines are omitted:

```text
== Same key (one partition), records sent in order: poison-1, next-1, bad-1
     194 ms  BLK    payments-blk           poison-1
     194 ms  NB     payments-nb            poison-1
     731 ms  NB     payments-nb            next-1                         ← NB: next-1 OVERTAKES poison-1
     731 ms  NB     payments-nb            bad-1
    1213 ms  BLK    payments-blk           poison-1                       ← BLK: retry 1 (1 s later)
    1222 ms  NB     payments-nb-retry-1000 poison-1 retry_topic-attempts=2
    1248 ms  NB     payments-nb-dlt        bad-1    retry_topic-attempts=2   ← not retryable → straight to DLT
               kafka_exception-cause-fqcn           java.lang.IllegalArgumentException
               kafka_original-topic                 payments-nb
               kafka_original-offset                2
               kafka_dlt-original-consumer-group    nb
    2229 ms  BLK    payments-blk           poison-1                       ← BLK: retry 2
    3233 ms  NB     payments-nb-retry-2000 poison-1 retry_topic-attempts=3
    3245 ms  BLK    payments-blk           poison-1                       ← BLK: retry 3
    3896 ms  BLK    payments-blk           next-1                         ← BLK: next-1 waited ~3.7 s behind the poison pill
    3897 ms  BLK    payments-blk           bad-1
    3916 ms  BLK    payments-blk-dlt       poison-1
               kafka_dlt-exception-cause-fqcn       java.lang.IllegalStateException
               kafka_dlt-original-topic             payments-blk
               kafka_dlt-original-offset            0
               kafka_dlt-original-consumer-group    blk
    4414 ms  BLK    payments-blk-dlt       bad-1
               kafka_dlt-exception-cause-fqcn       java.lang.IllegalArgumentException
               kafka_dlt-original-topic             payments-blk
               kafka_dlt-original-offset            2
               kafka_dlt-original-consumer-group    blk
    7243 ms  NB     payments-nb-retry-4000 poison-1 retry_topic-attempts=4
    7769 ms  NB     payments-nb-dlt        poison-1 retry_topic-attempts=5
               kafka_original-topic                 payments-nb
               kafka_original-offset                0
               kafka_dlt-original-consumer-group    nb
               kafka_exception-cause-fqcn           java.lang.IllegalStateException
               header occurrences: [retry_topic-original-timestamp x4, retry_topic-attempts x4, retry_topic-backoff-timestamp x4]
== Topics that exist now
  payments-blk
  payments-blk-dlt
  payments-nb
  payments-nb-dlt
  payments-nb-retry-1000
  payments-nb-retry-2000
  payments-nb-retry-4000
```

What the run proves:

| | Blocking (`DefaultErrorHandler`) | Non-blocking (`@RetryableTopic`) |
|---|---|---|
| Order on the partition | **Preserved**: `next-1` ran after the poison pill was dead-lettered | **Broken**: `next-1` ran at 731 ms while `poison-1` was still retrying |
| Throughput while retrying | The partition is **stalled** (head-of-line blocking, ~3.7 s here) | Main topic keeps flowing |
| Topics | `<topic>-dlt` (verified: spring-kafka 4 default; older versions used `.DLT`) | `-retry-1000`, `-retry-2000`, `-retry-4000` (suffix = delay by default) + `-dlt`, auto-created |
| Non-retryable exceptions | Straight to the DLT | Straight to the DLT (`bad-1` at 1,248 ms) |
| DLT headers | `kafka_dlt-*` (original topic/partition/offset/group, exception class, cause, message, stack trace) | `kafka_original-*` + `kafka_exception-*` + `kafka_dlt-original-consumer-group`; retry headers accumulate per hop (×4) |
| Max time a record can be delayed | `attempts × backoff`, but it holds the partition | Sum of the backoffs; nothing else waits |

**How to choose:** if **per-key order matters** (account balance updates, state machines), use blocking retries with *short* backoff, then the DLT, and make the DLT replay order-aware. If records are **independent** (emails, indexing, notifications), use non-blocking retries. A common hybrid: a couple of fast blocking retries for blips, then the DLT.

### 4.3 Poison pills you can't even deserialize ⚡

If the value deserializer throws inside `poll()`, the container can't hand the record to your listener at all. Wrap deserializers in **`ErrorHandlingDeserializer`**: the failure becomes a `DeserializationException` the error handler treats as **not retryable** and routes to the DLT with the raw bytes.

### 4.4 Operating a DLT 🧊

* A DLT nobody reads is a data-loss bin with a nice name. Alert when anything arrives; dashboard its size and age.
* Keep **retention long enough** for a weekend incident (days, not hours).
* Build a **replay tool**: read from the DLT, fix or filter, republish to the original topic (headers say which). Make sure consumers are idempotent first, since replays are duplicates by definition.
* Classify errors: a DLT full of `NullPointerException` from one bad deploy is a rollback-and-replay; one bad record is a data fix.

---

## 5. Exactly-once processing 🧊

### 5.1 Kafka → Kafka: transactions

Consume-transform-produce where the **output records and the input offsets commit atomically**:

```java
producer.beginTransaction();
for (var r : records) producer.send(transform(r));
producer.sendOffsetsToTransaction(nextOffsets(records), consumer.groupMetadata());   // offsets join the transaction
producer.commitTransaction();                                                       // outputs + offsets, or neither
// downstream consumers use isolation.level=read_committed
```

The building block was verified in [10.1 §6](01-Kafka-Producers-Batching-Idempotence-Ordering.md): `read_uncommitted` saw aborted records, `read_committed` saw only committed ones. In Spring Kafka, setting `spring.kafka.producer.transaction-id-prefix` makes the container run each poll's processing in a Kafka transaction and send the offsets to it. Kafka Streams does all of this with `processing.guarantee=exactly_once_v2`.

### 5.2 Kafka → anything else: idempotence

Transactions don't extend to your database, an HTTP call or an email. For those, "exactly-once" means **at-least-once delivery + idempotent effect**:

```sql
-- same DB transaction as the business change (complete version in 5.4)
insert into processed_message(consumer, message_id) values ('shipping', :eventId)
on conflict do nothing;            -- 0 rows → duplicate → skip the side effect
```

Where you can't dedup (a third-party API), use **its** idempotency key, derived from the event id.

---

## 6. Scaling consumers ⚡

* **Consumers ≤ partitions.** The 7th consumer on a 6-partition topic sits idle. Scaling on lag beyond the partition count does nothing (KEDA's Kafka scaler caps at the partition count by default; see [7.4](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)).
* **Parallelism inside a partition** while keeping per-key order: process different keys concurrently, the same key sequentially (for example a per-key queue on virtual threads), committing only the contiguous completed prefix of offsets. Libraries like Confluent's Parallel Consumer implement exactly this.
* **Share groups** (KIP-932, "queues for Kafka") add queue-style consumption with per-record acknowledgement and no partition-count cap on consumers. Check their status in your broker version before designing around them (the embedded 4.2.2 broker printed `group.share.enable = false` by default).

---

## 7. Production configuration and listener

```yaml
spring:
  kafka:
    consumer:
      group-id: shipping
      auto-offset-reset: earliest           # a NEW group reads history, instead of silently skipping it
      enable-auto-commit: false              # the container commits
      max-poll-records: 100                  # bounded work per poll
      isolation-level: read_committed        # if upstream producers are transactional
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.ErrorHandlingDeserializer
      properties:
        spring.deserializer.value.delegate.class: org.apache.kafka.common.serialization.ByteArrayDeserializer
        max.poll.interval.ms: 120000
        group.protocol: consumer             # KIP-848 (brokers ≥ 4.0); otherwise cooperative-sticky:
        # partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        # no group.instance.id: a Deployment pod gets a new name per rollout (10.4 §4)
    listener:
      ack-mode: record
      concurrency: 3                         # ≤ partitions / replicas
      observation-enabled: true              # continue traces from record headers (5.7)
```

```java
@Configuration
class KafkaErrorHandling {
    @Bean
    DefaultErrorHandler errorHandler(KafkaTemplate<Object, Object> template) {
        var backoff = new ExponentialBackOff(200, 2.0);
        backoff.setMaxElapsedTime(5_000);                                         // a few fast blocking retries, order kept
        var eh = new DefaultErrorHandler(new DeadLetterPublishingRecoverer(template), backoff);
        eh.addNotRetryableExceptions(ValidationException.class, JsonProcessingException.class);
        return eh;                                                                 // Boot wires a single CommonErrorHandler bean into the factory
    }
}

@Component
class ShipmentListener {
    @KafkaListener(topics = "order-events", groupId = "shipping")
    @Transactional                                                                // DB transaction: dedup row + side effect
    public void on(ConsumerRecord<String, byte[]> r) {
        String eventId = new String(r.headers().lastHeader("eventId").value(), StandardCharsets.UTF_8);
        if (!dedup.firstTime("shipping", eventId)) return;                         // insert … on conflict do nothing
        shipments.createFor(OrderPlaced.parse(r.value()));
    }
}
```

---

## 8. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| Default `auto.offset.reset=latest` for a new group | `earliest`, deliberately |
| Auto-commit + async hand-off | Container-managed commits; commit only completed work |
| 500 records × slow processing per poll | Bounded `max.poll.records`, honest `max.poll.interval.ms`, pause/resume for long work |
| Eager `RangeAssignor` (the first default) | Cooperative-sticky, or KIP-848 with brokers ≥ 4.0; dynamic members on Deployments, static only with StatefulSet ids ([10.4](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)) |
| `DefaultErrorHandler` defaults (10 instant attempts, then log and skip) | Backoff + DLT recoverer + non-retryable classification |
| Non-blocking retries for order-sensitive data | Blocking retries (short) → DLT when key order matters |
| Plain deserializer | `ErrorHandlingDeserializer` so poison pills reach the DLT |
| DLT with no alert, short retention, no replay | Alerts, long retention, a replay tool, idempotent consumers |
| "Kafka EOS makes my DB writes exactly-once" | EOS for Kafka→Kafka; dedup row + effect in one DB transaction otherwise |
| Scale consumers past the partition count | Partitions sized for max parallelism; per-key parallelism inside partitions if needed |
| Alert on total lag | Per-partition lag and lag growth / time lag |

---

## 9. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [apache/kafka](https://github.com/apache/kafka) | `clients/src/main/java/org/apache/kafka/clients/consumer/internals/ConsumerCoordinator.java` | Classic protocol: join/sync, `onJoinPrepare` (revocation), cooperative two-phase logic |
| same | `clients/src/main/java/org/apache/kafka/clients/consumer/CooperativeStickyAssignor.java` | How "sticky" and "only move what must move" are computed |
| same | `group-coordinator/src/main/java/org/apache/kafka/coordinator/group/` | KIP-848 server-side assignment and reconciliation |
| same | `clients/src/main/java/org/apache/kafka/clients/consumer/internals/AsyncKafkaConsumer.java` | The new consumer implementation used with `group.protocol=consumer` |
| [spring-projects/spring-kafka](https://github.com/spring-projects/spring-kafka) | `spring-kafka/src/main/java/org/springframework/kafka/listener/DefaultErrorHandler.java` | Seek-to-current retries, classification |
| same | `spring-kafka/src/main/java/org/springframework/kafka/listener/DeadLetterPublishingRecoverer.java` | DLT naming, headers, partition choice |
| same | `spring-kafka/src/main/java/org/springframework/kafka/retrytopic/` | `RetryTopicConfigurer`, back-off manager, topic naming |

---

## 10. Interview soundbites

* "A consumer reads a log from a committed position. Process-then-commit is at-least-once, so exactly-once effects come from idempotent processing or Kafka transactions."
* "`max.poll.interval.ms` is the processing-liveness check. I reproduced a 6-second batch with a 3-second limit: the commit failed, partitions were lost, and the batch ran twice."
* "Eager rebalancing revoked all six partitions to move three. Cooperative and KIP-848 revoked only the three that moved. The old consumer never stopped."
* "Blocking retries keep per-key order but stall the partition. In my run `next-1` waited 3.7 seconds. Non-blocking retry topics keep throughput but let `next-1` overtake the poison pill. I choose based on whether order matters."
* "Spring Kafka's default error handler retries ten times with no delay and then skips. I always configure backoff, a dead-letter recoverer, and non-retryable exceptions. In 4.x the DLT suffix is `-dlt`."
* "Consumers beyond the partition count are idle, so lag-based autoscaling is capped by partitions."

---

## 11. Deep dive: membership, scaling and shutdown on Kubernetes (verified) 🔥

§2 measured rebalance *protocols*. [10.4](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) measured what Kubernetes does to a group: pods leaving on scale-down and being replaced on rollout.

| One of two consumers… | Classic (default assignors) | KIP-848 | Static member, plain `close()` |
|---|---|---|---|
| leaves (KEDA scale-down) | 3.0 s | **0.5 s** | **45.1 s / 45.3 s**: no LeaveGroup, the group waits out the session |
| is replaced by a pod with a **new** id (Deployment) | 3.0 s | 0.6–5.7 s | **45 s**; under the eager default the survivor owned **nothing for 41.4 s** |
| is replaced by a pod with the **same** id (StatefulSet) | — | — | 0.16–0.54 s, no revocation |

Three facts from the same module change how §2.2 and §7 read:

* **§2.2 and §7 were corrected in place.** `group.instance.id: ${POD_NAME}` on a Deployment gave every rollout a new static member and a 45 s stall. Static membership needs an identity that survives restarts, and a Deployment pod doesn't have one.
* **Under KIP-848 the client rejects** `session.timeout.ms`, `heartbeat.interval.ms` and `partition.assignment.strategy` at construction (verified). The session timeout is the broker's, with a default and a minimum of 45 s. Remove those keys when you switch §7's config to `group.protocol: consumer`.
* **spring-kafka 4.1.2 stops consumers with plain `close()`**, and appends `-0…-N` to `group.instance.id` per concurrent consumer (bytecode). A static pod with `concurrency: 3` is three members, which strand their partitions together on every scale-down.

§6's "capped by partitions" gets a correction too: **KEDA's cap counts pods**. With `concurrency: 3` and 12 partitions, 12 replicas are 36 consumers, 24 of them idle. The [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) consumer therefore runs one consumer per pod, KIP-848, no static id, no preStop, and a 30 s grace period covering spring-kafka's 10 s container stop.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Model | A consumer reads from a committed position; process-then-commit is at-least-once | §0 |
| Defaults (4.2.2) | `auto.offset.reset=latest`, 45 s session, 300 s `max.poll.interval.ms` | §0.1 |
| Poll-loop liveness | A 6 s batch with a 3 s limit: commit failed, partitions lost, batch processed twice | §1.1 |
| Lag | Measured per partition; total lag hides hot partitions | §1.2 |
| Rebalance protocols | Eager revoked 6 partitions to move 3; cooperative and KIP-848 revoked only the 3 | §2.1 |
| Membership | Dynamic on Deployments; static only with StatefulSet ids (corrected) | §2.2, §11 |
| Commits | The container commits per `AckMode`; never hand records to another pool and return | §3 |
| Retries and DLTs | Blocking keeps order but stalled `next-1` 3.7 s; retry topics keep throughput but reorder; default `FixedBackOff(0, 9)`; DLT suffix `-dlt` | §4 |
| Exactly-once | Kafka → Kafka transactions; Kafka → elsewhere: idempotent effects | §5 |
| Scaling | Consumers ≤ partitions; KEDA's cap counts pods, so one consumer per pod | §6, §11 |
| Kubernetes | 0.5 s KIP-848 handoff vs 45 s static; KIP-848 rejects classic settings; spring-kafka plain `close()` | §11 (10.4) |

**Next:** [10.3 Production Kafka: multi-broker durability, compaction, topics as code, Strimzi →](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md)
