# 10.3 Production Kafka: a Real 3-Broker Cluster, Durability Under Broker Loss, Topics as Code, Partition Planning, and a Strimzi 1.3 Blueprint

> **Verified stack:** Apache Kafka **4.2.2** brokers from the official test kit (`KafkaClusterTestKit`: **1 dedicated KRaft controller + 3 brokers**, real replication over loopback), kafka-clients **4.2.2**, spring-kafka **4.1.2** (`KafkaAdmin`, `TopicBuilder`), Spring Boot **4.1.2** metadata, **Strimzi 1.3.0** CRDs (released 2026-10-12) for the Kubernetes blueprint, JDK **25**. Throughput numbers are *one run on loopback on a laptop*: ratios, not capacity.
>
> **Builds on:** [10.1](01-Kafka-Producers-Batching-Idempotence-Ordering.md) and [10.2](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), which ran against a **single** broker, so replication, ISR and broker loss couldn't be shown. This file adds a real multi-broker cluster.

---

## 0. What this file proves 🔥

| Claim | Evidence |
|---|---|
| `KafkaAdmin` (topics as code) changes **partitions asynchronously**, ignores **config changes** unless told to, and **silently ignores** a partition decrease | §1 |
| `acks=all` with RF=3 cost ~2.7× the time of `acks=0` and ~1.7× of `acks=1` on loopback | §2 |
| RF=3, `min.insync.replicas=2`: one broker down → writes continue; two down → `acks=all` writes **refused**, `acks=1` writes **accepted with a single copy** | §3 |
| The refusal reaches the application as a `TimeoutException` after `delivery.timeout.ms` (default **120 s**), not as `NotEnoughReplicas` | §3 |
| The Strimzi 1.3.0 blueprint (node pools, cluster, topics, users) validates; 4 classic migration mistakes are caught | §6 |
| The Spring Boot client config for mTLS validates (25 keys, 0 problems; all 7 Kafka keys known) | §7 |
| **Not run here:** log compaction, because Kafka's log cleaner fails on Windows (§4 shows the error and explains the mechanism) | §4 |

Two test-kit lessons from building the lab. Neither is a production statement:

* **Three *combined* controller+broker nodes** hit a fatal Raft error at startup (`Received unexpected invalid request error` in two voters' Raft I/O threads). The quorum then resigned, and later metadata calls hung. The lab therefore uses a dedicated controller. In production, Strimzi runs separate controller and broker node pools (§6).
* **Windows can't run Kafka's log cleaner** (§4). Brokers belong on Linux.

---

## 1. Topics as code with spring-kafka's `KafkaAdmin` (verified) ⚡

```java
KafkaAdmin ka = new KafkaAdmin(Map.of(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap));
ka.createOrModifyTopics(TopicBuilder.name("payments").partitions(3).replicas(3)
        .config(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, "2").config(TopicConfig.RETENTION_MS_CONFIG, "3600000").build());
// v2: 6 partitions, retention 2 h; then the same with setModifyTopicConfigs(true); then a decrease to 2
```

**Output (verified):**

```text
== 1. Topics as code with spring-kafka's KafkaAdmin
  v1 (3 partitions, retention 1 h):                     partitions=3 RF=3 min.insync.replicas=2 retention.ms=3600000
  v2 (6 partitions, retention 2 h), default KafkaAdmin: partitions=3 RF=3 min.insync.replicas=2 retention.ms=3600000
  ... the same topic 3 s later:                         partitions=6 RF=3 min.insync.replicas=2 retention.ms=3600000
  v2 again with setModifyTopicConfigs(true):            partitions=6 RF=3 min.insync.replicas=2 retention.ms=7200000
  v3 (2 partitions: a DECREASE):                        partitions=6 RF=3 min.insync.replicas=2 retention.ms=7200000  (no exception)
```

**Reading it:**

* **Partition increases are applied, but not before `createOrModifyTopics` returns.** A describe right after it still showed 3; 3 s later, 6. Anything that depends on the new partitions at startup (a consumer expecting them, a test) can race.
* **Config changes are ignored by default.** Retention stayed at 1 h until `setModifyTopicConfigs(true)`. A team that edits `retention.ms` in a `NewTopic` bean and redeploys has changed nothing, silently.
* **Decreasing partitions is impossible in Kafka,** and `KafkaAdmin` didn't even fail: it left 6. Your "declared" state and the real state now disagree.

**Increasing partitions isn't free either:** the default partitioner maps a key to `hash(key) % partitions`, so adding partitions **moves keys**, which breaks per-key ordering across the change ([10.1 §5](01-Kafka-Producers-Batching-Idempotence-Ordering.md#5-ordering-choosing-the-key-is-a-design-decision-)). Plan the count up front (§5).

**Where topic definitions should live:**

* **Strimzi `KafkaTopic` resources (§6)**, reconciled by the topic operator, reviewed like any manifest;
* **or a Terraform/GitOps pipeline** with an explicit plan/apply.

`KafkaAdmin` at application startup is fine for development, and dangerous as the source of truth in production for the three reasons above, plus the app needing topic-admin ACLs.

---

## 2. What `acks` costs with real replication (one run) ⚡

```text
== 2. What acks costs with RF=3 (50,000 x 512-byte records, one run, loopback)
  acks=0     255 ms   196,078 records/s
  acks=1     395 ms   126,582 records/s
  acks=all   682 ms    73,313 records/s
```

* **`acks=all` waits for the in-sync followers to fetch the batch**, so its latency is the leader's write *plus* a replication round trip. On loopback that cost 1.7× `acks=1`. Across availability zones, the follower fetch adds the inter-zone round trip to every batch.
* **Batching recovers most of it.** `linger.ms` and `batch.size` let many records share one replication round trip ([10.1 §2](01-Kafka-Producers-Batching-Idempotence-Ordering.md#2-batching-and-compression-)). A previous run gave 331/420/567 ms, the same ordering.

---

## 3. Losing brokers: what `min.insync.replicas` really guarantees (verified) 🔥

Topic `orders`: 6 partitions, RF=3, `min.insync.replicas=2`. One record is produced with `acks=all` (idempotent) and one with `acks=1` after each step. The producer uses `delivery.timeout.ms=6000` so failures surface quickly. Brokers are stopped with a controlled shutdown, one at a time.

**Output (verified; the lab numbers this step 4 because compaction was its step 3):**

```text
== 4. Losing brokers: RF=3, min.insync.replicas=2
  healthy:          p0 L2 isr[0, 1, 2]  p1 L0 isr[0, 1, 2]  p2 L1 isr[0, 1, 2]  p3 L1 isr[0, 1, 2]  p4 L2 isr[0, 1, 2]  p5 L0 isr[0, 1, 2]
  produce acks=all: OK p4@0 (478 ms)   acks=1: OK p4@1 (31 ms)
  broker 0 stopped (2601 ms): p0 L2 isr[1, 2]  p1 L1 isr[1, 2]  p2 L1 isr[1, 2]  p3 L1 isr[1, 2]  p4 L2 isr[1, 2]  p5 L1 isr[1, 2]
  produce acks=all: OK p4@2 (255 ms)   acks=1: OK p4@3 (20 ms)
  broker 1 stopped (2365 ms): p0 L2 isr[2]  p1 L2 isr[2]  p2 L2 isr[2]  p3 L2 isr[2]  p4 L2 isr[2]  p5 L2 isr[2]
  produce acks=all: FAILED after 6240 ms: TimeoutException   acks=1: OK p4@4 (21 ms)
```

And from the producer's log during that last `acks=all` attempt:

```text
WARN ...Sender -- Got error produce response ... on topic-partition orders-4, retrying (2147483646 attempts left)
org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR : 1 is insufficient to satisfy the min.isr requirement of 2 for partition orders-4, live replica(s) broker.id are : Set(2)
```

**Reading it:**

* **One broker down (controlled shutdown, ~2.5 s):** leadership moved off broker 0 (`p1 L0 → L1`, `p5 L0 → L1`), ISRs shrank to 2, and both `acks` settings kept working. This is the configuration's purpose: **tolerate one broker loss with no write outage and no data loss.**
* **Two brokers down:** the ISR is 1, below `min.insync.replicas=2`. The broker **refused** `acks=all` writes with `NotEnoughReplicasException`. That's **retriable**, so the producer retried it until `delivery.timeout.ms` expired, and the application only saw a **`TimeoutException`**. With the defaults, which I printed from `ProducerConfig.configDef()` (`delivery.timeout.ms=120000`, `retries=2147483647`), every send would block its caller for **two minutes**.
* **The same moment, `acks=1` succeeded with one copy.** If broker 2 now dies, that record (`p4@4`) is gone, or the partition stays offline with `unclean.leader.election.enable=false`. **`acks=1` turns `min.insync.replicas` into decoration.** The setting only constrains producers that ask for `acks=all`.

| RF / `min.insync.replicas` | `acks=all` writes survive | Acknowledged data survives | Typical use |
|---|---|---|---|
| 3 / 2 | 1 broker down | 1 broker loss (2 copies on every ack) | Default for business events |
| 3 / 1 | 2 brokers down | **0**: an ack may exist on one broker only | Never for data you can't lose |
| 3 / 3 | 0 brokers down (any maintenance stops writes) | 2 broker losses | Rarely worth the availability cost |
| 5 / 3 (3+ zones) | 2 brokers down | 2 broker losses | Very critical topics, larger clusters |

**Producer-side consequences:**

* **Set `delivery.timeout.ms` to what your caller can wait** (the blueprint uses 30 s; for request paths, shorter, behind an outbox).
* **Treat `TimeoutException` as "unknown outcome"** (with idempotence, a retry with the same producer is safe).
* **Alert on the broker side,** not on application timeouts:
  * `UnderMinIsrPartitionCount > 0`: writes are being refused;
  * `UnderReplicatedPartitions > 0`: one more failure away;
  * `OfflinePartitionsCount > 0`.

---

## 4. Log compaction: what it does, and why it wasn't run here 🧊

A compacted topic keeps **the latest record per key**, forever: a changelog that a new consumer can read from offset 0 to rebuild current state (prices, inventory snapshots, a KTable's backing topic). A record with a `null` value is a **tombstone**: it deletes the key and is itself removed after `delete.retention.ms`.

**What controls when compaction happens:**

* **The active segment is never compacted:** only rolled segments (`segment.ms` / `segment.bytes`).
* **The cleaner picks partitions** whose dirty ratio exceeds `min.cleanable.dirty.ratio`.
* **Tombstones must outlive the slowest consumer.** If `delete.retention.ms` passes before a consumer reads the tombstone, that consumer never learns the key was deleted.
* **Ordering and offsets are preserved;** offsets of removed records simply disappear (consumers must tolerate gaps).

**Why it isn't verified in this kit:** the lab created a compacted topic (`segment.ms=1000`, `min.cleanable.dirty.ratio=0.01`) and wrote 17 records. Every broker's log cleaner then failed:

```text
java.nio.file.FileSystemException: ...\broker_1_data0\prices-0\00000000000000000000.timeindex.cleaned ->
  ...\00000000000000000000.timeindex.swap: The process cannot access the file because it is being used by another process
```

The cleaner writes a cleaned copy of a segment and its memory-mapped index files, then *renames* them over the originals. Windows refuses to rename a file that is still memory-mapped, so compaction can't complete there. That's one more reason brokers run on Linux. The compaction semantics above come from Kafka's documentation and design, not from a run here. Re-run `KafkaClusterLab` with `-Dlab.compaction=true` on Linux to see it.

---

## 5. Partition count planning ⚡

Partitions are the unit of parallelism, ordering and recovery cost, and the count can only grow (§1).

| Input | Rule of thumb |
|---|---|
| Throughput | `partitions ≥ max(target produce MB/s ÷ per-partition produce MB/s, target consume MB/s ÷ per-consumer MB/s)`. Measure per-partition throughput on *your* brokers and record size (§2 shows how much `acks` alone moves it) |
| Consumer parallelism | ≥ the peak consumer instance count (× listener concurrency). A partition is consumed by one member of a group at a time ([10.2 §6](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md#6-scaling-consumers-)) |
| Key cardinality and skew | A hot key pins one partition. More partitions don't help a single hot key; a key design change does |
| Growth | Choose for 1–2 years of growth up front: adding partitions later remaps keys (ordering break) |
| Cost | Each partition costs controller metadata, open files, replication fetchers and recovery time. Thousands per broker are fine on KRaft; hundreds of thousands per cluster need planning |
| Retention and size | `partition size = retention × MB/s ÷ partitions`; very large partitions make reassignments slow |

**For the order platform:**

* **`order-events`:** 12 partitions. It covers up to 12 consumer instances, the throughput is modest, and keys are order ids with low skew.
* **`product-prices`:** 6 partitions, compacted.

Both are declared in §6.

---

## 6. Strimzi 1.3.0 blueprint (validated against the CRDs) 🔥

**Validation:**

* **Method:** checked with the same structural validator as [7.5 §0](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md#0-how-these-files-were-verified): unknown fields, required fields, types. Schemas: Strimzi 1.3.0's own CRD schemas for `Kafka`, `KafkaNodePool`, `KafkaTopic`, `KafkaUser`, plus Kubernetes v1.37.1 OpenAPI for the `ConfigMap`.
* **Result:** `documents: 7, problems: 0`.
* **Strimzi 1.3.0 serves only `kafka.strimzi.io/v1`.** Blueprints written for `v1beta2` no longer apply.

```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: controllers
  namespace: kafka
  labels:
    strimzi.io/cluster: orders
spec:
  replicas: 3                                   # an odd quorum: tolerates 1 controller loss
  roles: [controller]
  storage:
    type: persistent-claim
    size: 20Gi
    class: gp3-zonal
    deleteClaim: false
  resources:
    requests: {cpu: "500m", memory: 2Gi}
    limits: {memory: 2Gi}
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: brokers
  namespace: kafka
  labels:
    strimzi.io/cluster: orders
spec:
  replicas: 3                                   # one per zone (rack awareness below)
  roles: [broker]
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 1Ti
        class: gp3-zonal
        deleteClaim: false                      # never let a CR deletion delete data
  resources:
    requests: {cpu: "4", memory: 16Gi}
    limits: {memory: 16Gi}
  jvmOptions:
    -Xms: 6g                                    # small heap; the rest is page cache, which Kafka lives on
    -Xmx: 6g
---
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: orders
  namespace: kafka
spec:
  kafka:
    version: 4.2.2                              # Strimzi 1.3.0 supports 4.2.0-4.3.1 (default 4.3.1); pin what you tested
    listeners:
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: tls                             # mTLS client certificates from KafkaUser
    authorization:
      type: simple
    rack:
      topologyKey: topology.kubernetes.io/zone  # replicas spread across zones; consumers can fetch from the nearest replica
    config:
      default.replication.factor: 3
      min.insync.replicas: 2                    # acks=all survives one broker; two down = writes refused (§3)
      unclean.leader.election.enable: false     # never elect an out-of-sync replica (no silent data loss)
      auto.create.topics.enable: false          # topics are declared (KafkaTopic), never created by a typo
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      replica.selector.class: org.apache.kafka.common.replica.RackAwareReplicaSelector
      num.partitions: 6
      log.retention.hours: 168
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  entityOperator:
    topicOperator: {}
    userOperator: {}
  cruiseControl:
    autoRebalance:                              # move partitions onto new brokers / off removed ones automatically
      - mode: add-brokers
      - mode: remove-brokers
  kafkaExporter:
    groupRegex: ".*"
    topicRegex: ".*"                            # consumer-lag metrics per group/partition (alerts, KEDA)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-metrics
  namespace: kafka
data:
  kafka-metrics-config.yml: |
    lowercaseOutputName: true
    rules:
      - pattern: kafka.server<type=(.+), name=(.+)><>Value
        name: kafka_server_$1_$2
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: order-events
  namespace: kafka
  labels:
    strimzi.io/cluster: orders
spec:
  partitions: 12                                # max consumer parallelism; can grow, never shrink (§1)
  replicas: 3
  config:
    min.insync.replicas: 2
    retention.ms: 604800000                     # 7 days
    cleanup.policy: delete
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: product-prices
  namespace: kafka
  labels:
    strimzi.io/cluster: orders
spec:
  partitions: 6
  replicas: 3
  config:
    min.insync.replicas: 2
    cleanup.policy: compact                     # latest value per key, kept forever (§4)
    min.cleanable.dirty.ratio: "0.1"
    delete.retention.ms: 86400000               # tombstones stay 1 day so slow consumers see deletes
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaUser
metadata:
  name: order-service
  namespace: kafka
  labels:
    strimzi.io/cluster: orders
spec:
  authentication:
    type: tls
  authorization:
    type: simple
    acls:
      - resource: {type: topic, name: order-events, patternType: literal}
        operations: [Write, Describe]
      - resource: {type: topic, name: product-prices, patternType: literal}
        operations: [Read, Describe]
      - resource: {type: group, name: order-service, patternType: prefix}
        operations: [Read]
      - resource: {type: cluster}
        operations: [IdempotentWrite]
  quotas:
    producerByteRate: 10485760                  # 10 MiB/s: one runaway producer can't saturate the brokers
    consumerByteRate: 20971520
```

**Negative test (verified).** The same validator on a copy with the classic migration mistakes:

```text
  Kafka/orders.spec.kafka.replicas: unknown field                  <- replicas moved to KafkaNodePool
  Kafka/orders.spec.kafka.storage: unknown field                   <- so did storage
  KafkaTopic/order-events: no schema for kafka.strimzi.io/v1beta2 KafkaTopic   <- v1beta2 is gone in 1.3.0
  KafkaTopic/order-events.spec.partition: unknown field            <- typo
documents: 3, problems: 4
```

**Decisions worth defending:**

* **Separate controller and broker pools.** Controllers are small, quorum-sized and rarely change; brokers scale with throughput and disk.
* **`unclean.leader.election.enable: false`.** If the only in-sync replica is lost, the partition goes offline rather than electing a stale replica and silently truncating acknowledged data. Availability is the price of correctness here.
* **Small JVM heap (6 GiB of 16).** Kafka serves reads from the OS page cache; a big heap steals that memory and lengthens GC.
* **Quotas per user.** Without them, one misbehaving client degrades everyone's p99.
* **Cruise Control auto-rebalance.** New brokers otherwise sit empty while old ones stay hot.
* **`kafkaExporter`.** Consumer lag per group and partition feeds both alerts and KEDA ([7.4 §4](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md#4-keda-scaling-on-events-and-to-zero-)).

---

## 7. Spring Boot client configuration for that cluster (validated) ⚡

```yaml
spring:
  kafka:
    bootstrap-servers: orders-kafka-bootstrap.kafka.svc:9093
    security:
      protocol: SSL
    ssl:
      bundle: kafka-order-service               # mTLS keystore + cluster CA truststore, from the KafkaUser and cluster CA secrets
    producer:
      acks: all
      compression-type: zstd
      batch-size: 64KB
      properties:
        enable.idempotence: true
        delivery.timeout.ms: 30000              # the default is 120000: a 2-minute block when the ISR is too small (§3)
        request.timeout.ms: 10000
        linger.ms: 10
    consumer:
      group-id: order-service
      auto-offset-reset: earliest
      enable-auto-commit: false
      isolation-level: read-committed
      max-poll-records: 200
      properties:
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        # no group.instance.id: on a Deployment it stalled partitions 45 s per rollout (10.4 §4)
        session.timeout.ms: 45000
        client.rack: ${NODE_ZONE}               # fetch from the replica in the consumer's own zone (RackAwareReplicaSelector)
    listener:
      ack-mode: record
      concurrency: 3
      observation-enabled: true
    template:
      observation-enabled: true
  ssl:
    bundle:
      pem:
        kafka-order-service:
          keystore:
            certificate: file:/etc/kafka-user/user.crt
            private-key: file:/etc/kafka-user/user.key
          truststore:
            certificate: file:/etc/kafka-cluster-ca/ca.crt
```

**Validation (verified):**

* **Spring Boot keys:** checked against the 4.1.2 metadata, `25 keys: 15 exact, 10 under a Map/List property, 0 problems` (re-run after the [10.4 §4](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) correction removed `group.instance.id`).
* **The 7 free-form Kafka keys:** all `known` to `ProducerConfig.configNames()` / `ConsumerConfig.configNames()` in kafka-clients 4.2.2.

`client.rack` + the broker's `RackAwareReplicaSelector` (§6) let a consumer fetch from a follower in its own zone. That cuts cross-zone transfer cost, often the largest Kafka line item in a cloud bill. Set `NODE_ZONE` from the node's topology label (a downward-API env var or an init step).

---

## 8. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| `acks=1` "because it's faster" | `acks=all` + `min.insync.replicas=2` + RF=3; `acks=1` accepted a single-copy write with 2 brokers down (§3) |
| Default `delivery.timeout.ms` (120 s) on a request path | A deliberate timeout, behind an outbox ([5.10](../05-Microservices-Patterns/10-Reference-Implementation-Saga-Orchestrator-Kafka-Outbox-Inbox-CQRS.md)) |
| Alerting on producer timeouts | Broker alerts: `UnderMinIsrPartitionCount`, `UnderReplicatedPartitions`, `OfflinePartitionsCount` |
| `NewTopic` beans as the source of truth | `KafkaTopic` CRs or GitOps; `KafkaAdmin` ignored config changes and a decrease (§1) |
| Partitions "add more later" | Plan for growth; adding partitions remaps keys (§5) |
| `auto.create.topics.enable=true` | `false`: a typo'd topic name is an error, not a new topic with defaults |
| `unclean.leader.election.enable=true` for availability | `false`: an offline partition beats silently truncated data |
| Large broker heaps | ~6 GiB heap; leave the rest to the page cache |
| No quotas | Per-user produce/consume quotas |
| Consumers fetch across zones | `client.rack` + `RackAwareReplicaSelector` |
| Combined controller+broker nodes everywhere | Separate controller pool in production clusters |

---

## 9. Bar-raiser Q&A 🔥

🎤 *"Our order events use `acks=all`, so they're durable."*

🔍 **What does `acks=all` actually wait for?**

<details><summary>🛡️ Defense</summary>

All replicas **currently in the ISR**, not all replicas. If the ISR has shrunk to just the leader, `acks=all` equals `acks=1`, unless `min.insync.replicas` forbids that. With RF=3 and `min.insync.replicas=2`, verified on a 3-broker cluster:

* **One broker down:** writes continued.
* **Two down:** the broker refused `acks=all` writes (`NotEnoughReplicasException: The size of the current ISR : 1 is insufficient …`).

So durability is the *pair* of settings, and only for producers that use `acks=all`. In the same state, an `acks=1` producer got `OK` on a single copy.
</details>

🔍 **Two brokers are down. What does the application see?**

<details><summary>🛡️ Defense</summary>

Not `NotEnoughReplicas`. That error is retriable, so the producer retries it internally (`2147483646 attempts left`) until `delivery.timeout.ms` expires. The app gets a `TimeoutException`: after 6 s in my test, and after **120 s** with the defaults I printed from `ProducerConfig`. That's two minutes of a request thread blocked per send. I set the timeout deliberately, publish through an outbox so the request path never waits on Kafka, and alert on `UnderMinIsrPartitionCount` at the broker instead of on application timeouts.
</details>

🔍 **We declare our topics as `NewTopic` beans. We bumped retention from 1 h to 2 h and partitions from 3 to 6. Done?**

<details><summary>🛡️ Defense</summary>

Verified with spring-kafka 4.1.2's `KafkaAdmin`:

* **Partitions:** increased, but only visible ~3 s *after* `createOrModifyTopics` returned.
* **Retention:** **unchanged**, until `setModifyTopicConfigs(true)`.
* **Decreasing partitions:** silently ignored.

On top of that, more partitions remap keys, so per-key ordering breaks at the moment of the change. I'd move topic definitions to Strimzi `KafkaTopic` resources (or GitOps with a reviewed plan) and keep `KafkaAdmin` for local development.
</details>

🔍 **Why is `unclean.leader.election.enable` false? Isn't availability more important?**

<details><summary>🛡️ Defense</summary>

An unclean election promotes a replica that's **not** in sync. The partition comes back, but every message the old leader acknowledged and the new one never got is silently gone, and offsets are reused for different data. For business events, that's worse than downtime: you can't even detect it. With it disabled, losing the last in-sync replica takes the partition offline until that broker returns. I'd rather page someone than corrupt the log. Keep RF=3 across zones so it takes two independent failures to get there.
</details>

🔍 **How many partitions should `order-events` have?**

<details><summary>🛡️ Defense</summary>

Enough for the peak consumer parallelism and throughput, sized for 1–2 years, because Kafka can't decrease the count and an increase remaps keys. Order events are modest in volume and keyed by order id (low skew), so 12: it covers up to 12 consumer instances with headroom. I'd check per-partition throughput on our brokers before going higher. Throughput isn't the only cost: each partition adds replication fetchers, open files, controller metadata and rebalance work. A single hot key isn't fixed by more partitions at all.
</details>

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Topics as code | `KafkaAdmin`: async partition increase, config changes off by default, decrease ignored | §1 |
| `acks` cost | `acks=all` ≈ 1.7× `acks=1` on loopback with RF=3; batching amortizes it | §2 |
| ISR and `min.insync.replicas` | RF=3/min 2: one broker loss tolerated; two → `acks=all` refused, `acks=1` accepted single-copy | §3 |
| Failure surfacing | `NotEnoughReplicas` retried until `delivery.timeout.ms` (default 120 s) → `TimeoutException` | §3 |
| Compaction | Latest value per key; tombstones; Windows can't run the cleaner (not verified here) | §4 |
| Partitions | Plan for growth; increases remap keys; hot keys need key design | §5 |
| Strimzi 1.3.0 | `v1` only; node pools; validated blueprint + caught mistakes | §6 |
| Client config | mTLS via SSL bundle, rack-aware fetching, dynamic membership ([10.4](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)), deliberate timeouts | §7 |

**Next:** [10.4 Consumer scaling: static membership vs KIP-848, KEDA scale-down, rolling deploys →](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)
