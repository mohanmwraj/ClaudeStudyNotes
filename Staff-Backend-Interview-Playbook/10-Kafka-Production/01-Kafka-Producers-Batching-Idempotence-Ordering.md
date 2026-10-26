# 10.1 Kafka Producers: Batching, Durability, Idempotence, Ordering, Transactions

> **Verified stack:** Apache Kafka clients **4.2.2** against an embedded single-node **KRaft** broker (`kafka-server` 4.2.2 via `spring-kafka-test` **4.1.2**'s `EmbeddedKafkaKraftBroker`), spring-kafka **4.1.2**, JDK **25.0.4.1**. Defaults were printed from `ProducerConfig.configDef()`; every scenario was run (`KafkaProducerLab.java`, `KafkaConsumerLab.java`). Throughput numbers come from **one run each on loopback with one broker**. They show *direction*, not capacity.
>
> **Related:** [5.4 outbox](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) (how events *get* to the producer safely), [10.2 consumers](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), sibling kit [6.5 Kafka](../../Java-Backend-Master-Reference/06-Spring-Microservices/05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md).

---

## 0. First principles: a replicated, partitioned log 🔥

A Kafka topic is a set of **partitions**, and each partition is an **append-only log** replicated to several brokers. A producer's job is to turn millions of small `send()` calls into a few large, sequential appends to each partition's leader, **without losing, duplicating or reordering** records. Every producer setting trades among four things:

| Goal | Mechanism | Cost |
|---|---|---|
| **Throughput** | Batching (`linger.ms`, `batch.size`) + compression | Latency (waiting to fill a batch), CPU |
| **Durability** | `acks=all` + replication factor + `min.insync.replicas` | Latency (wait for followers), availability when replicas are down |
| **No duplicates** | Idempotence (producer id + sequence numbers) | Nothing, really. It's on by default |
| **Ordering** | One partition per ordering domain (the **key**), idempotence for safe retries | Parallelism is capped by partitions; hot keys make hot partitions |
| **Atomic multi-partition writes** | Transactions | Latency, coordinator round trips |

---

## 1. Under the hood: from `send()` to the broker ⚡

```text
caller thread                                                   kafka-producer-network-thread ("Sender")
─────────────                                                   ────────────────────────────────────────
KafkaProducer.send(record, callback)
 1. wait for topic metadata           (max.block.ms = 60 s)
 2. serialize key and value           (errors throw HERE, synchronously)
 3. choose the partition
      explicit partition  → use it
      key != null         → toPositive(murmur2(keyBytes)) % numPartitions
      key == null         → built-in "uniform sticky" partitioner: fill a batch on one partition,
                            then switch (adaptive: avoid slow brokers)
 4. RecordAccumulator.append
      per-partition Deque<ProducerBatch>, memory from a BufferPool (buffer.memory = 32 MB)
      pool exhausted → send() BLOCKS up to max.block.ms, then TimeoutException
 5. return Future<RecordMetadata>  (the record is NOT sent yet)
                                                                 loop:
                                                                  ready(): a batch is sendable if it's full
                                                                     (batch.size), linger.ms has passed, or
                                                                     flush()/close()/memory pressure
                                                                  drain(): group ready batches by LEADER broker,
                                                                     up to max.request.size per ProduceRequest
                                                                  send, keeping ≤ max.in.flight.requests.per.connection
                                                                     unacknowledged requests per broker
                                                                  on response: complete futures and run callbacks
                                                                     ON THIS THREAD (never block in a callback)
                                                                  on retriable error: re-enqueue with backoff
                                                                     (retry.backoff.ms → retry.backoff.max.ms)
                                                                     until delivery.timeout.ms (120 s) expires
```

Three consequences interviewers probe:

* **`send()` can block** the caller (metadata, full buffer). On a request thread that's a latency spike. With virtual threads it parks cheaply, but it still delays the response.
* **Callbacks run on the single network thread.** A slow callback (a DB write, a log flush to a remote sink) stalls *all* sends of that producer.
* **Serialization errors and `RecordTooLargeException` (above `max.request.size`, default 1 MB) are thrown from `send()`**, not delivered through the future. Handle both paths.

### 1.1 Defaults in kafka-clients 4.2.2 (verified)

```text
== 1. Producer defaults in kafka-clients 4.2.2
  acks                                     all
  enable.idempotence                       true
  retries                                  2147483647
  max.in.flight.requests.per.connection    5
  linger.ms                                5
  batch.size                               16384
  delivery.timeout.ms                      120000
  compression.type                         none
```

Two of these changed in living memory: `acks=all` and idempotence became defaults in **3.0**, and `linger.ms` went from 0 to **5** in **4.0** (KIP-1030). Old blog posts saying "the default is `acks=1`" or "`linger.ms` defaults to 0" are now wrong.

### 1.2 Partitioning (verified)

```text
== 2. Keys -> partitions (murmur2(key) % partitions); null keys -> sticky batches
  order-1 -> partitions [4, 4, 4]
  order-2 -> partitions [3, 3]
  order-3 -> partitions [3]
  30 null-key records (sent async) -> partitions [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
```

* Same key → same partition, every time. That's the **ordering guarantee**: per key, because per partition.
* Different keys can share a partition (`order-2` and `order-3` both landed in partition 3). Keys hash *onto* partitions; they don't own them.
* Null keys are **sticky**: the 30 async records filled a batch on one partition instead of being sprayed one per partition. Fewer, bigger batches mean more throughput.
* 🧊 **Adding partitions changes `hash % n`**, so a key moves to a different partition, and records for it can be consumed out of order across the change. Choose the partition count up front (sized for peak throughput and consumer parallelism), or migrate to a new topic.

---

## 2. Batching and compression ⚡

### 2.1 One measured run

100,000 × 200-byte records, async sends, 6-partition topic, one broker on loopback:

```text
== 3. Batching: 100,000 x 200-byte records, async sends (one measured run each)
  linger=0   batch=16384   compression=none    183,458 rec/s   avg batch= 15,738 B   records/request= 386.1   requests=   263
  linger=5   batch=16384   compression=none    329,649 rec/s   avg batch= 16,213 B   records/request= 395.3   requests=   257
  linger=20  batch=131072  compression=none    672,606 rec/s   avg batch=128,075 B   records/request=3125.0   requests=    36
  linger=20  batch=131072  compression=lz4     257,619 rec/s   avg batch=  6,658 B   records/request=4347.8   requests=    27
```

How to read it:

* **`linger.ms=0` still batches.** While one request is in flight, new records pile up in the accumulator ("natural batching"). Batches here were already about 16 KB. `linger.ms` adds *deliberate* waiting on top.
* **`linger=5` (the 4.x default)** got 1.8× the throughput of `linger=0` in this run with almost the same request count. `batch.size=16384` was the ceiling, so the gain came from fuller pipelines, not bigger batches.
* **Bigger batches (128 KB) + `linger=20`** cut requests from 257 to 36 and reached 3.7× the `linger=0` rate. Per-request overhead (headers, syscalls, broker request handling, replication round trips) is amortized over more records.
* **lz4 was slower here**, and it's an honest result: on loopback there's no network cost to save, so compression is pure CPU. The payload (all `x`) compressed to about 5 % of its size. On a real network with real JSON, compression usually wins: fewer bytes on the wire, on disk, in replication and in consumer fetches. **Measure with your payloads.** Compression is per batch, so it pays off more with bigger batches.

### 2.2 Settings that matter

| Setting | Guidance |
|---|---|
| `linger.ms` | 5–20 ms for throughput-oriented producers; 0–5 when tail latency matters more |
| `batch.size` | 32–256 KB for high-volume topics. It's a **per-partition** cap, and memory is `buffer.memory` overall |
| `compression.type` | `lz4` (fast) or `zstd` (best ratio); `none` only after measuring |
| Broker/topic `compression.type` | Keep `producer` (the broker default; verified in the embedded broker's config dump), or the broker **recompresses** every batch |
| `buffer.memory` | Sized for `throughput × (linger + request latency + retries)`; when exhausted, `send()` blocks |

---

## 3. Durability: what "acknowledged" means 🔥

```text
acks=0     fire and forget: no response at all                  → loses data silently
acks=1     the leader appended it to its log                     → lost if the leader dies before followers copy it
acks=all   every replica in the ISR (in-sync replica set) has it → survives a leader crash, IF the ISR has ≥ 2 members

replication.factor = 3, min.insync.replicas = 2, acks = all
  1 broker down  → ISR = 2 ≥ 2 → writes continue, nothing acknowledged is lost
  2 brokers down → ISR = 1 < 2 → producers get NOT_ENOUGH_REPLICAS: unavailable rather than unsafe
```

* `acks=all` waits for the **ISR**, not for all replicas. Without `min.insync.replicas=2`, an ISR shrunk to just the leader makes `acks=all` behave like `acks=1`.
* Kafka doesn't `fsync` every write by default. Durability comes from **replication across failure domains**: set `broker.rack` so replicas land in different zones.
* `unclean.leader.election.enable=false` (the default): an out-of-sync replica never becomes leader, so availability waits instead of losing acknowledged data.

---

## 4. Idempotence: why retries don't duplicate or reorder 🔥

```text
producer gets a Producer ID (PID) + epoch from the broker
every batch carries (PID, epoch, partition, firstSequence)

broker, per (PID, partition), remembers the last 5 batches' sequence numbers:
  sequence == last + 1      → append
  sequence already seen     → DUPLICATE: acknowledge again, don't append
  sequence > last + 1       → OUT_OF_ORDER_SEQUENCE: a gap, so the producer resolves it
```

The scenario it fixes:

```text
batch #7 sent → the broker appends it → the response is lost (network blip)
producer retries #7 → without idempotence: a second copy is appended
                    → with idempotence: the broker recognizes (PID, seq 7) and just acks
```

* **Why `max.in.flight.requests.per.connection ≤ 5`?** The broker keeps the state of the **last 5** batches per producer and partition. Up to 5 in-flight batches can be retried and still checked against that state, so you keep ordering **and** pipelining. Without idempotence, `max.in.flight > 1` plus retries can **reorder**: batch 1 fails, batch 2 succeeds, batch 1's retry lands after it.
* **Scope:** idempotence holds within **one producer session**. A restarted producer gets a new PID, so a record re-sent after a crash (for example by an outbox relay that crashed before marking it published) is a **new** record. End-to-end dedup still needs an idempotent consumer ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)) or a transactional producer with a stable `transactional.id`.

---

## 5. Ordering: choosing the key is a design decision 🔥

| You need ordering per… | Key | Watch out for |
|---|---|---|
| Aggregate (order, account) | aggregate id | Hot aggregates → hot partitions |
| Customer | customer id | Large customers dominate one partition |
| Nothing (independent events) | null (sticky) | Consumers must not assume any order |
| Global order | 1 partition | Throughput of one partition and one consumer, so challenge the requirement |

Rules:

* Order exists **only within a partition**, so only among records with the same key. There is no order across partitions or topics. Use event timestamps or versions if consumers need to reason across them.
* If one aggregate's events go to **two topics** (`order-created`, `order-paid`), consumers can see "paid" before "created". Use one topic per aggregate stream with typed events, or make consumers tolerate the inversion.
* The producer keeps order for records **it** sends. Two producers (two relay instances) writing the same key give no relative order. That's the [5.4 §7](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) multi-relay caveat.

---

## 6. Transactions: atomic writes across partitions 🧊

```java
props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, "payments-tx-1");   // stable identity across restarts
producer.initTransactions();          // registers with the transaction coordinator; bumps the epoch → fences zombies
producer.beginTransaction();
producer.send(new ProducerRecord<>("payments", "a0", "aborted-0"));   // ... 3 records
producer.abortTransaction();          // abort markers written to each touched partition
producer.beginTransaction();
producer.send(new ProducerRecord<>("payments", "c0", "committed-0")); // ... 2 records
producer.commitTransaction();         // coordinator logs PREPARE_COMMIT in __transaction_state, then COMMIT markers
```

**Output (verified, kafka-clients 4.2.2):**

```text
== Exactly-once building block: transactional producer + read_committed consumers
  read_uncommitted  sees [aborted-2, aborted-1, committed-1, aborted-0, committed-0]
  read_committed    sees [committed-1, committed-0]
```

What happened on the broker:

* **Aborted records are in the log.** Kafka never deletes them; `read_uncommitted` consumers see all five. (The mixed order is because the keys hash to different partitions.)
* `read_committed` consumers read only up to the **last stable offset (LSO)**, the first offset of the oldest still-open transaction, and skip aborted records using the abort markers and the aborted-transaction index.
* **Zombie fencing:** a second producer with the same `transactional.id` calls `initTransactions()`, which bumps the epoch. The old instance's writes are rejected (`ProducerFencedException`). That's how a restarted instance safely replaces a stuck one.
* The embedded 4.2.2 broker's bootstrap metadata listed `transaction.version` feature level **2**, the transactions v2 protocol from KIP-890, which bumps the epoch on every transaction to close the hanging-transaction holes of v1.

Costs and traps:

* **An open transaction blocks every `read_committed` consumer at the LSO**, on every partition it touched, until it commits, aborts or hits `transaction.timeout.ms` (default 60 s). One stuck producer stalls downstream consumers. Alert on LSO lag.
* Small transactions are expensive (coordinator round trips + markers per partition). Batch many records per transaction.
* **Kafka transactions cover Kafka only.** A database write plus a Kafka send is still a dual write, so use the outbox ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)). The consume-transform-produce use is in [10.2 §5](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md).

---

## 7. Production configuration (Spring Boot 4.1.2 + spring-kafka 4.1.2)

```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    producer:
      acks: all
      compression-type: lz4                 # measured with real payloads; zstd if bytes matter more than CPU
      batch-size: 64KB
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.ByteArraySerializer   # or your schema serializer
      properties:
        linger.ms: 10
        enable.idempotence: true            # default, stated so nobody "tunes" it off
        max.in.flight.requests.per.connection: 5
        delivery.timeout.ms: 120000
        request.timeout.ms: 30000
        max.block.ms: 5000                  # fail fast instead of blocking request threads for 60 s
    template:
      observation-enabled: true             # trace context into record headers (see 5.7)
```

```java
@Service
class OrderEventsPublisher {
    private final KafkaTemplate<String, byte[]> kafka;

    CompletableFuture<SendResult<String, byte[]>> publish(OrderEvent e) {
        return kafka.send("order-events", e.orderId(), e.toBytes())          // key = aggregate id → per-order ordering
                .whenComplete((result, ex) -> {
                    if (ex != null) failures.increment();                    // cheap, non-blocking: runs on the Sender thread
                });
    }
}
```

Topic settings that go with it: `replication.factor=3`, `min.insync.replicas=2`, partitions sized for peak throughput **and** maximum consumer parallelism (consumers in a group ≤ partitions), and `cleanup.policy=compact` for "latest state per key" topics.

---

## 8. Failure scenarios

| Scenario | What the producer does | What you do |
|---|---|---|
| Leader moves (broker restart) | `NOT_LEADER_OR_FOLLOWER` → metadata refresh → retry (idempotent, ordered) | Nothing, as long as `delivery.timeout.ms` covers the election |
| ISR below `min.insync.replicas` | `NOT_ENOUGH_REPLICAS` retries until `delivery.timeout.ms` | Alert on under-replicated partitions; the future fails eventually |
| `delivery.timeout.ms` expires | The future fails with `TimeoutException`; **the record is not sent** | Outbox (retry from the table) or a dead-letter store; never log-and-forget |
| Buffer full (broker slow) | `send()` blocks up to `max.block.ms` | Lower `max.block.ms`, apply backpressure upstream, size `buffer.memory` |
| Record > `max.request.size` | `RecordTooLargeException` from `send()` | Claim check: put the payload in object storage, send a reference |
| Producer process crash | Records still in the accumulator are lost | Outbox, or accept loss for telemetry-grade data |

---

## 9. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Production-hardened |
|---|---|
| `acks=1` "for speed" | `acks=all` + RF 3 + `min.insync.replicas=2` |
| `enable.idempotence=false` to "tune" | Idempotence on (default), `max.in.flight ≤ 5` |
| `linger.ms=0`, 16 KB batches on a high-volume topic | `linger.ms` 5–20, `batch.size` 64–256 KB, compression measured |
| Blocking or I/O in send callbacks | Callbacks only record metrics or hand off |
| `kafkaTemplate.send(...)` and ignore the future | Handle failures: outbox retry, alert, or explicit drop policy |
| Random keys "to spread load" when order matters | Key = ordering domain; watch partition skew |
| Increase partitions on a keyed topic in place | Size partitions up front; migrate to a new topic if needed |
| DB transaction + Kafka transaction = atomic | Outbox; Kafka transactions only for Kafka-to-Kafka |
| One long-running transaction | Short, batched transactions; alert on LSO lag |

---

## 10. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [apache/kafka](https://github.com/apache/kafka) | `clients/src/main/java/org/apache/kafka/clients/producer/KafkaProducer.java` | `doSend`: metadata wait, serialization, partition choice, `accumulator.append` |
| same | `clients/src/main/java/org/apache/kafka/clients/producer/internals/RecordAccumulator.java` | Per-partition deques, `ready`, `drain`, `BufferPool` |
| same | `clients/src/main/java/org/apache/kafka/clients/producer/internals/Sender.java` | The network loop, in-flight limits, retries, completing batches |
| same | `clients/src/main/java/org/apache/kafka/clients/producer/internals/BuiltInPartitioner.java` | `partitionForKey` (murmur2), uniform sticky + adaptive partitioning |
| same | `clients/src/main/java/org/apache/kafka/clients/producer/internals/TransactionManager.java` | PID/epoch, sequence numbers, transaction states |
| [spring-projects/spring-kafka](https://github.com/spring-projects/spring-kafka) | `spring-kafka/src/main/java/org/springframework/kafka/core/KafkaTemplate.java` | `send` → `CompletableFuture`, observation, transactions |

---

## 11. Interview soundbites

* "The producer batches per partition in an accumulator, and one Sender thread ships ready batches to each partition leader. `send()` is async but can block on metadata or a full buffer, and callbacks run on that single thread."
* "On loopback, `linger.ms` 5 instead of 0 gave 1.8× throughput, and 128 KB batches with linger 20 gave 3.7×. Compression lost there because loopback has no network to save. I measure with real payloads."
* "`acks=all` means the ISR, so it needs `min.insync.replicas=2` with replication factor 3 to mean something."
* "Idempotence is PID plus per-partition sequence numbers; the broker remembers the last five batches, which is why up to five in-flight requests keep ordering. It doesn't survive a producer restart, so consumers stay idempotent."
* "Ordering is per partition, so the key is the ordering domain. Adding partitions breaks key-to-partition mapping."
* "Kafka transactions are Kafka-only, and an open transaction freezes `read_committed` consumers at the LSO."

---

## 12. Deep dive: the producer against a real three-broker cluster (verified) 🔥

This module's measurements used one broker. [10.3](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) ran a KRaft cluster with three brokers, a topic at RF=3 and `min.insync.replicas=2`, and stopped brokers one at a time:

| Situation | `acks=all` (idempotent) | `acks=1` | What the application saw |
|---|---|---|---|
| All brokers up | ~2.7× the time of `acks=0`, ~1.7× of `acks=1` (loopback) | — | The cost of waiting for the ISR (§3) |
| One broker down | Writes continue | Writes continue | Nothing |
| **Two brokers down** (ISR 1 < 2) | **Refused** (`NotEnoughReplicas`, retriable) | **Accepted with one copy** | A `TimeoutException` after `delivery.timeout.ms`, **120 s** by default; every send blocked its caller that long |

What it adds to §3 and §8:

* **`acks=1` turns `min.insync.replicas` into decoration.** The setting constrains only producers that ask for `acks=all`. In the two-down state, `acks=1` happily acknowledged records that existed on one disk.
* **The refusal is invisible as such.** `NotEnoughReplicasException` is retriable, so the producer retries until the delivery timeout and reports a generic timeout. Alert on the broker's under-min-ISR partition count, not on producer exceptions.
* **Shorten `delivery.timeout.ms`** (10.3 uses 30 s, with `request.timeout.ms` 10 s), so a stuck partition fails requests in seconds, not minutes. Then decide what the caller does: the outbox ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)) turns "Kafka is refusing writes" into "the relay is behind", with no user-facing error.

**Topics as code** (10.3 §1) is where §5's "adding partitions breaks key mapping" happens without anyone deciding it. `KafkaAdmin` applied a partition increase **asynchronously** on startup, ignored config changes unless `setModifyTopicConfigs(true)`, and silently ignored a partition **decrease**. Review topic definitions like schema migrations, because they are one.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Model | A replicated, partitioned log; ordering per partition | §0 |
| Producer internals | Per-partition batches in an accumulator; one Sender thread; `send()` can block on metadata or a full buffer | §1, §1.1 |
| Partitioning | Key hash → partition; null keys: sticky partitioning | §1.2 |
| Batching | Loopback: `linger.ms` 5 → 1.8×, 128 KB + linger 20 → 3.7×; compression lost with no network to save | §2 |
| Durability | `acks=all` = the ISR; needs RF 3 + `min.insync.replicas` 2 | §3 |
| Idempotence | PID + per-partition sequence; the broker keeps the last 5 batches, so ≤ 5 in flight keeps order | §4 |
| Ordering | The key is the ordering domain; adding partitions remaps keys | §5 |
| Transactions | Kafka-only atomicity; an open transaction freezes `read_committed` consumers at the LSO | §6 |
| Configuration | `acks=all`, idempotence, bounded timeouts, observations on | §7–§8 |
| Three brokers | Two down: `acks=all` refused (120 s timeout), `acks=1` accepted with one copy | §12 (10.3) |
| Topics as code | Async partition changes, config changes ignored by default, decreases silently ignored | §12 (10.3 §1) |

**Next:** [10.2 Kafka consumers: rebalancing, EOS, retries, DLQ →](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md)
