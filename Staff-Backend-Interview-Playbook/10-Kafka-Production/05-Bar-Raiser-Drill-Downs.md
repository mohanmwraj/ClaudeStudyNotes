# 10.5 Bar-Raiser Drill-Downs: Kafka in Production

> Evidence: [10.1](01-Kafka-Producers-Batching-Idempotence-Ordering.md)–[10.4](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) (Kafka 4.2.2, spring-kafka 4.1.2, KRaft clusters started in-JVM, all run). Kafka questions come up in system design *and* in "tell me about an incident" rounds. The bar-raiser keeps asking "and then what happens?" until your design either holds or breaks. Drills 1–5 were Pillar 6's drills 8–12 before Kafka got its own pillar.
>
> 🎤 candidate · 🔍 interviewer probe · 🛡️ staff-level defense

---

## Drill 1: "We publish order events with `acks=1` because it's faster" 🔥

🔍 **Probe 1: What can you lose?**

<details><summary>🛡️ Defense</summary>

Any record the leader acknowledged but followers hadn't copied when the leader died. `acks=all` waits for the ISR. It only means something with `min.insync.replicas=2` on a replication factor of 3: one broker can die without losing acknowledged data, two make writes unavailable rather than unsafe. Since 3.0 `acks=all` is the default (verified in 4.2.2), so `acks=1` is a deliberate downgrade.
</details>

🔍 **Probe 2: A retry after a lost response. Duplicate? Reordered?**

<details><summary>🛡️ Defense</summary>

Neither, with idempotence (the default): the broker tracks producer id + per-partition sequence for the last 5 batches, acknowledges the duplicate without appending it, and rejects gaps. That's why `max.in.flight ≤ 5` keeps ordering. But a *restarted* producer has a new id, so re-sends after a crash are new records. Consumers stay idempotent.
</details>

🔍 **Probe 3: You need more throughput. What do you change?**

<details><summary>🛡️ Defense</summary>

Batching, not durability. One run on loopback, 100k × 200 B: linger 0 → 183k rec/s; linger 5 (the 4.x default) → 330k; 128 KB batches with linger 20 → 673k with 36 requests instead of 257. lz4 lost there (257k) because loopback has no network to save. With real payloads over a real network I'd expect compression to win, but I'd measure.
</details>

🔍 **Probe 4 (L6): Throughput still isn't enough, so someone proposes doubling partitions on the topic.**

<details><summary>🛡️ Defense</summary>

On a keyed topic, `murmur2(key) % n` changes, so keys move to new partitions. Records for the same order can be consumed out of order across the change, and any per-partition state in consumers is now wrong. Plan the partition count up front for peak throughput and consumer parallelism, or migrate to a new topic with a cutover.
</details>

---

## Drill 2: "Our consumer group keeps rebalancing" ⚡

🔍 **Probe 1: First thing you check?**

<details><summary>🛡️ Defense</summary>

Whether processing per poll exceeds `max.poll.interval.ms`. Reproduced: a 6 s batch with a 3 s limit gave `CommitFailedException`, `onPartitionsLost`, a rejoin, and the same batch delivered again. Fix: fewer records per poll, an honest interval, pause/resume for long work, and idempotent processing.
</details>

🔍 **Probe 2: Each rebalance pauses all 30 consumers for seconds. Why, and how do you fix it?**

<details><summary>🛡️ Defense</summary>

The default assignor list starts with the eager `RangeAssignor`, which revokes **everything** from everyone. Verified with one joiner: eager revoked all 6 partitions to move 3; cooperative-sticky and KIP-848 revoked only the 3 that moved, and the old member never stopped consuming the others. I migrate to cooperative (two rolling bounces) or to `group.protocol=consumer` on 4.x brokers.
</details>

🔍 **Probe 3: Rolling deploys cause a rebalance per pod. Can you avoid them?**

<details><summary>🛡️ Defense</summary>

Static membership: `group.instance.id` set to a stable pod identity, meaning a StatefulSet ordinal, not a Deployment pod name ([10.4 §2](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)). A restart within `session.timeout.ms` rejoins as the same member with no rebalance. And graceful shutdown: a **dynamic** member's `close()` leaves the group at once (0.5 s under KIP-848), so give the pod a grace period long enough to get there; a **static** member's `close()` doesn't leave at all ([10.4 §1](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md)).
</details>

---

## Drill 3: "We use Kafka exactly-once, so duplicates are impossible" 🧊

🔍 **Probe 1: Exactly-once for what?**

<details><summary>🛡️ Defense</summary>

Kafka transactions make **output records and input offsets** commit atomically for Kafka-to-Kafka processing, with `read_committed` consumers downstream. Verified building block: after an aborted and a committed transaction, `read_uncommitted` saw 5 records and `read_committed` saw 2. Aborted records are still in the log; they're filtered.
</details>

🔍 **Probe 2: The consumer writes to Postgres and calls a payment API.**

<details><summary>🛡️ Defense</summary>

Kafka transactions don't cover those. That's at-least-once delivery + idempotent effects: a dedup row in the same DB transaction as the business change ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)), and the provider's idempotency key derived from the event id.
</details>

🔍 **Probe 3 (L6): Downstream `read_committed` consumers stopped making progress, with no errors. What do you look for?**

<details><summary>🛡️ Defense</summary>

An open transaction. `read_committed` consumers can't read past the **last stable offset**, the start of the oldest open transaction on that partition. A hung producer freezes them until `transaction.timeout.ms` (60 s default) aborts it, or longer if it keeps the transaction alive. Alert on LSO lag. Zombie fencing (same `transactional.id` → epoch bump → `ProducerFencedException` for the old one) handles the restarted-instance case.
</details>

---

## Drill 4: "A poison message is blocking our consumer" ⚡

🔍 **Probe 1: What does Spring Kafka do by default?**

<details><summary>🛡️ Defense</summary>

`DefaultErrorHandler` with `FixedBackOff[interval=0, maxAttempts=9]` (read from a fresh 4.1.2 instance): 10 attempts with no back-off, then it logs and **skips** the record. (Measured, they weren't instant either: ~0.5 s apart on a caught-up partition, waiting for the in-flight fetch, [8.6 §7](../08-GitHub-Codebases-Study-Guide/06-Framework-Internals-by-Stack-Trace-Spring-Hibernate-HikariCP-Caffeine-Kafka.md).) That's neither safe nor visible. I configure backoff, a `DeadLetterPublishingRecoverer`, and non-retryable exceptions. If the value can't even be deserialized, `ErrorHandlingDeserializer` turns it into a non-retryable exception that reaches the DLT.
</details>

🔍 **Probe 2: Blocking retries or retry topics?**

<details><summary>🛡️ Defense</summary>

It depends on whether order matters, and I measured both with the same records. Blocking kept order but stalled the partition: `next-1` waited about 3.7 s behind the poison pill. `@RetryableTopic` kept the main topic flowing but `next-1` **overtook** the poison pill at 731 ms. For account balances or state machines I use short blocking retries then the DLT; for independent work, retry topics. In spring-kafka 4 the DLT suffix is `-dlt` and retry topics are suffixed with the delay (`-retry-1000`, `-retry-2000`, `-retry-4000`).
</details>

🔍 **Probe 3 (L6): What happens to the DLT afterwards?**

<details><summary>🛡️ Defense</summary>

Alerts on arrival, retention of days, a dashboard with age and count, and a replay tool that republishes to the original topic (the headers carry original topic, partition, offset, consumer group and exception). Replays are duplicates by definition, so consumers must be idempotent first. A DLT nobody reads is just data loss with extra steps.
</details>

---

## Drill 5: "Consumer lag is growing; let's add pods" ⚡

🔍 **Probe 1: Will that help?**

<details><summary>🛡️ Defense</summary>

Only up to the partition count: one partition, one consumer per group. Past that, pods sit idle (KEDA's Kafka scaler caps replicas at the partition count unless told otherwise). Then I check **per-partition** lag: the total hides skew. Verified example: total lag 600 was 0 + 297 + 303.
</details>

🔍 **Probe 2: One partition has all the lag.**

<details><summary>🛡️ Defense</summary>

A hot key (key skew) or one slow record type. More consumers can't help; that partition has one owner. Options: a better key (more granular ordering domain), parallel processing per key inside the partition (commit only the contiguous completed prefix), or isolating the hot tenant to its own topic.
</details>

---

# Round 2: Kafka on Kubernetes, multi-broker durability, topics as code (Batch 3 deep dive)

> Evidence for Round 2 is in [10.3](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) (a 3-broker KRaft cluster, Strimzi 1.3.0 blueprint), [10.4](04-Consumer-Scaling-Static-Membership-KIP-848-KEDA-Rolling-Deploys.md) (scale-down and rolling-deploy handoffs, kafka-clients 4.2.2, spring-kafka 4.1.2 bytecode, KEDA 2.21.0 source) and [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md). 🎤 candidate · 🔍 probe · 🛡️ staff-level defense.

---

## Drill 6: "We use static membership with the pod name, so rolling deploys don't rebalance" 🔥

🎤 *"`group.instance.id: ${POD_NAME}`. It's in our standard template."*

🔍 **Probe 1: Your consumers are a Deployment. What happens on a rollout?**

<details><summary>🛡️ Defense</summary>

Every replacement pod gets a new name, so it joins as a **new** static member while the old one, which never sent LeaveGroup, is still counted. Measured: back to full assignment after **45.1 s**, the session timeout, per replaced pod. Under the client's default assignors (which resolve to eager Range) the new member's join made everyone revoke, and the surviving consumer owned **nothing for 41.4 s**: the whole group stopped. With cooperative-sticky only the dead member's partitions waited, but they still waited 45 s. Static membership needs an identity that survives restarts; Deployment pods don't have one.
</details>

🔍 **Probe 2: And when KEDA scales down?**

<details><summary>🛡️ Defense</summary>

Same 45 s, for a different reason. spring-kafka 4.1.2 closes consumers with plain `close()` (I checked the bytecode: no `CloseOptions`), and a static member's `close()` deliberately doesn't leave the group. So the departing pod's partitions sit unconsumed until the session times out: 45.1 s classic, 45.3 s under KIP-848, 48 s with cooperative-sticky. With `concurrency: 3` that's three members per pod, because spring-kafka appends `-0`, `-1`, `-2` to the id.
</details>

🔍 **Probe 3 (L6): What would you run instead, and how fast is it?**

<details><summary>🛡️ Defense</summary>

KIP-848 with dynamic members on Deployments: **0.5 s** from a pod closing to the survivor owning its partitions, and 0.6–5.7 s for a replacement, bounded by the broker's 5 s heartbeat. Nothing else in the group stopped either way. Static membership stays for StatefulSets whose consumers keep expensive per-partition state: the same id came back in 0.16–0.54 s with no revocation. There, I set a classic session timeout just above the restart time and budget the scale-down stall into the lag SLO.
</details>

---

## Drill 7: "KEDA scales our consumer from 1 to 12 replicas on a 12-partition topic" ⚡

🎤 *"Max replicas equals partitions, so no consumer is ever idle."*

🔍 **Probe 1: What's the listener concurrency?**

<details><summary>🛡️ Defense</summary>

If it's 3, then 12 replicas are 36 consumers for 12 partitions, and 24 of them are idle. KEDA's Kafka scaler caps the replica count at the partition count; it has no idea how many consumers each pod runs. Idle consumers still hold connections and heap and take part in every rebalance. So either one consumer per pod, which is what [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) does, or `maxReplicaCount = partitions / concurrency` with `lagThreshold` multiplied by the concurrency.
</details>

🔍 **Probe 2: KEDA picks 5 replicas. Good?**

<details><summary>🛡️ Defense</summary>

No better than 4. Twelve partitions over five consumers split 3, 3, 2, 2, 2, and the two with three partitions set the pace. KEDA has `ensureEvenDistributionOfPartitions`, which picks the smallest factor of the partition count that covers the lag, so 12 partitions step 1 → 2 → 3 → 4 → 6 → 12. From the v2.21.0 source: it can't be combined with `limitToPartitionsWithLag` ("cannot be set simultaneously") and requires `topic`. That's also why partition counts with many divisors (12, 24, 60) are a good default.
</details>

🔍 **Probe 3 (L6): You tuned `cooldownPeriod` to stop flapping between 6 and 4. Did it help?**

<details><summary>🛡️ Defense</summary>

It can't: `cooldownPeriod` governs only scaling to zero. Between 1 and N replicas, the generated HPA's `behavior` decides, so the knob is `advanced.horizontalPodAutoscalerConfig.behavior`: a scale-down stabilization window and a slow policy (two pods per two minutes in 7.8), because every removed consumer is a rebalance. And if the consumers use static membership, every scale-down is also a 45 s stall that builds lag and invites the next scale-up. That's the flapping loop.
</details>

---

## Drill 8: "We're moving to KIP-848. It's one property: `group.protocol: consumer`" ⚡

🎤 *"The new protocol is incremental, so it's strictly better."*

🔍 **Probe 1: Your config also sets `session.timeout.ms` and the cooperative assignor. What happens?**

<details><summary>🛡️ Defense</summary>

The application fails at startup. I tried each combination against `KafkaConsumer`'s own validation: under `group.protocol=consumer`, `session.timeout.ms`, `heartbeat.interval.ms` and `partition.assignment.strategy` are **rejected** ("cannot be set when group.protocol=CONSUMER"). That's a good failure, because it shows up in the canary, but the change is three deletions, not one addition.
</details>

🔍 **Probe 2: Where did the session timeout go?**

<details><summary>🛡️ Defense</summary>

To the broker: `group.consumer.session.timeout.ms`, default 45 s, with a **minimum** of 45 s (`group.consumer.min.session.timeout.ms`), and a heartbeat interval of 5 s (minimum 5 s). A per-group override exists as a GROUP config, bounded by those limits. For dynamic members it hardly matters, because they leave explicitly. For static members it means a scale-down can't be faster than 45 s without changing broker configuration for every group.
</details>

🔍 **Probe 3 (L6): How do you roll it out?**

<details><summary>🛡️ Defense</summary>

Per consumer group, behind a config flag, on brokers that run the new coordinator (4.0+). Watch through one deploy and one scale-down: rebalance time, lag, and the error rate in the canary. The measured upside: 0.5 s handoff on scale-down against ~3 s for classic, which waits for the survivor's 3 s heartbeat to learn about the rebalance. Replacement can take up to one 5 s broker heartbeat, during which nothing else stops.
</details>

---

## Drill 9: "Replication factor 3 means we can lose two brokers" 🔥

🎤 *"Three copies of everything."*

🔍 **Probe 1: Two brokers are down. What happens to an `acks=all` write?**

<details><summary>🛡️ Defense</summary>

With `min.insync.replicas=2` it's **refused**: the ISR is 1, below the minimum, and the broker answers `NotEnoughReplicas`. Measured on a 3-broker cluster. That's the design working: RF 3 + min ISR 2 tolerates **one** broker loss for writes. With two down you keep reading, but you stop accepting writes you can't protect.
</details>

🔍 **Probe 2: What does the application see?**

<details><summary>🛡️ Defense</summary>

Not that error. `NotEnoughReplicas` is retriable, so the producer retries until `delivery.timeout.ms` expires, **120 s** by default, and then reports a generic `TimeoutException`. Every send blocked its caller for two minutes. So I set `delivery.timeout.ms` to about 30 s and `request.timeout.ms` to 10 s, alert on the brokers' under-min-ISR partition count rather than on producer exceptions, and put an outbox in front of Kafka so "Kafka refuses writes" becomes "the relay is behind" instead of a user-facing error.
</details>

🔍 **Probe 3 (L6): A team uses `acks=1` "for latency". Same scenario?**

<details><summary>🛡️ Defense</summary>

Their writes are **accepted with a single copy**, measured at the same moment the `acks=all` writes were refused. If that last broker dies, those records are gone, or the partition stays offline with unclean leader election disabled. `min.insync.replicas` only constrains producers that ask for `acks=all`, so `acks=1` turns it into decoration. The latency gain was about 1.7× on loopback, a small price to keep durability.
</details>

---

## Drill 10: "Topics are created by the application at startup, with Spring's `KafkaAdmin`" ⚡

🎤 *"Topics as code. We bump the partition count in the `NewTopic` bean when we need more."*

🔍 **Probe 1: You change partitions from 3 to 6 and deploy. When does it take effect?**

<details><summary>🛡️ Defense</summary>

Asynchronously. Measured: right after startup the topic still had 3 partitions; 3 s later it had 6. And it happens on whichever pod starts first, during a rolling deploy, with no review step. Adding partitions also changes `hash(key) % n`, so keys move partitions and per-key ordering breaks across the change. That should be a planned operation, not a side effect of a deploy.
</details>

🔍 **Probe 2: You also changed `retention.ms`. Applied?**

<details><summary>🛡️ Defense</summary>

No. `KafkaAdmin` ignores config changes on existing topics unless `setModifyTopicConfigs(true)`. With it, retention changed. And a partition **decrease** (6 → 2) was silently ignored, with no exception. So the code says one thing and the cluster another, and nothing tells you.
</details>

🔍 **Probe 3 (L6): Where should topic definitions live?**

<details><summary>🛡️ Defense</summary>

In the platform's repository, applied by an operator: Strimzi `KafkaTopic` resources, reviewed like schema migrations, because they are one. The 10.3 blueprint validates them against the Strimzi 1.3.0 CRDs. The application declares what it needs (topic name, expected partitions) and fails fast if the topic doesn't match, rather than creating or mutating it.
</details>

---

## Drill 11: "Our consumer pods use the same shutdown settings as the API: preStop sleep 10, grace 45" ⚡

🎤 *"Consistency across services."*

🔍 **Probe 1: What does the preStop sleep do for a consumer?**

<details><summary>🛡️ Defense</summary>

Nothing useful. The sleep exists so load balancers stop sending HTTP requests before the server closes its listener. A consumer has no Service traffic, so the sleep only delays its departure. Its partitions keep being consumed during those 10 s, but the rebalance to the remaining pods starts 10 s later on every scale-down and rollout.
</details>

🔍 **Probe 2: Then what does the grace period need to cover?**

<details><summary>🛡️ Defense</summary>

The in-flight work plus the leave. With `AckMode.RECORD`: the current record, spring-kafka's container stop (`DEFAULT_SHUTDOWN_TIMEOUT` = 10 s, verified), the commit, and the LeaveGroup (0.5 s for a KIP-848 dynamic member), plus margin, so 30 s in 7.8. A batch listener processing 100 records at 200 ms needs 20 s for the batch alone. If `SIGKILL` lands first, the batch isn't committed and is redelivered, which is safe only with idempotent processing.
</details>

🔍 **Probe 3 (L6): And if the consumers are static members?**

<details><summary>🛡️ Defense</summary>

Then a clean shutdown doesn't help the group at all: a static member's `close()` doesn't send LeaveGroup, so the group waits the full session timeout (45 s measured) no matter how fast the pod exits. That's the case where the shutdown budget and the membership model have to be designed together: dynamic members leave fast when they exit cleanly; static members are built not to leave.
</details>

---

## L5 vs L6 signal

| Topic | L5 answer | L6 answer |
|---|---|---|
| Kafka producer | `acks=all`, idempotence | ISR math, sequence numbers and the 5-in-flight limit, partition-count changes, transactions and LSO stalls |
| Kafka consumer | Consumer groups, commit after processing | Rebalance protocols with evidence, `max.poll.interval.ms` failure mode, retry strategy vs ordering, DLT operations, partition-capped scaling |
| Kafka on Kubernetes | Static membership "to avoid rebalances"; KEDA capped at partitions | Measured handoffs per membership model and protocol; knows spring-kafka's plain `close()`; divides KEDA's cap by consumers per pod |
| Durability in practice | RF 3, `acks=all` | min ISR math per broker loss, what the app sees (120 s timeout), `acks=1` accepting single copies, alerts on under-min-ISR |
| Topics as code | Creates topics from the app | Knows `KafkaAdmin`'s async and silent behaviours; operator-managed `KafkaTopic` reviewed like migrations |

---

## Red flags

* `acks=1` or idempotence disabled "for performance".
* "Exactly-once" without saying exactly-once *what*.
* Scaling consumers past partitions; alerting on total lag only.
* A DLT with no alerting and no replay path.
* `group.instance.id` = pod name on a Deployment.
* `concurrency` > 1 with KEDA `maxReplicaCount` = partitions.
* Switching to `group.protocol: consumer` without removing the classic settings.
* Default `delivery.timeout.ms` (120 s) on request paths.
* Partition counts changed by an application deploy.
* A preStop sleep on Kafka consumers.

---

## Rapid-fire flashcards

<details><summary>1. Kafka 4.x producer defaults for acks, idempotence, linger?</summary>`all`, `true`, 5 ms.</details>

<details><summary>2. Why `max.in.flight ≤ 5` with idempotence?</summary>The broker tracks the last 5 batch sequences per producer and partition.</details>

<details><summary>3. What does `read_committed` stop at?</summary>The last stable offset (start of the oldest open transaction).</details>

<details><summary>4. Consumer default `auto.offset.reset`?</summary>`latest`: new groups skip existing data.</details>

<details><summary>5. Eager vs cooperative vs KIP-848?</summary>Eager revokes all; cooperative revokes only moving partitions (two rounds); KIP-848 is broker-side, incremental, with no group barrier.</details>

<details><summary>6. `DefaultErrorHandler` default?</summary>`FixedBackOff(0, 9)`: 10 attempts with no back-off (≈0.5 s apart when the consumer is caught up), then log and skip.</details>

<details><summary>7. Spring Kafka 4 DLT suffix?</summary>`-dlt` (older versions used `.DLT`).</details>

<details><summary>8. Blocking vs non-blocking retries?</summary>Blocking keeps order but stalls the partition; non-blocking keeps throughput but breaks per-key order.</details>

<details><summary>9. Max useful consumers in a group?</summary>The partition count.</details>

<details><summary>10. Static member, plain `close()`: how long until its partitions move?</summary>The session timeout: 45.1 s classic, 45.3 s KIP-848, 48 s cooperative. No LeaveGroup is sent.</details>

<details><summary>11. Static id = Deployment pod name, eager assignor, one pod replaced?</summary>45 s to recover, and the survivor owned nothing for 41.4 s: the whole group stopped.</details>

<details><summary>12. KIP-848 dynamic member leaves: handoff?</summary>0.5 s (classic: ~3 s, one heartbeat).</details>

<details><summary>13. How does spring-kafka 4.1.2 close consumers and name static members?</summary>Plain `close()`; `group.instance.id` + `-0…-N` per concurrent consumer.</details>

<details><summary>14. Which client settings does KIP-848 reject?</summary>`session.timeout.ms`, `heartbeat.interval.ms`, `partition.assignment.strategy` ("cannot be set when group.protocol=CONSUMER").</details>

<details><summary>15. KIP-848 session timeout default and minimum?</summary>Broker-side `group.consumer.session.timeout.ms`: 45 s default, 45 s minimum; heartbeat 5 s.</details>

<details><summary>16. KEDA's partition cap counts…?</summary>Pods, not consumers: concurrency 3 × 12 replicas = 36 consumers for 12 partitions.</details>

<details><summary>17. `ensureEvenDistributionOfPartitions` on 12 partitions?</summary>Replicas step through factors: 1, 2, 3, 4, 6, 12. Can't be combined with `limitToPartitionsWithLag`.</details>

<details><summary>18. KEDA `cooldownPeriod` applies to…?</summary>Scaling to zero only; 1 ↔ N is the HPA `behavior`.</details>

<details><summary>19. RF 3, min ISR 2, two brokers down?</summary>`acks=all` refused (`NotEnoughReplicas`, retriable → `TimeoutException` after 120 s); `acks=1` accepted with one copy.</details>

<details><summary>20. `KafkaAdmin` partition increase, config change, partition decrease?</summary>Applied asynchronously; ignored unless `setModifyTopicConfigs(true)`; silently ignored.</details>

<details><summary>21. Does a Kafka consumer pod need a preStop sleep?</summary>No: no Service traffic. Grace = in-flight work + 10 s container stop + leave + margin.</details>

---

## Summary

| Round | Drills | What it tests |
|---|---|---|
| Round 1 (1–5) | `acks=1`, rebalancing groups, "exactly-once", poison messages, lag and adding pods | Producer durability and idempotence, rebalance protocols, EOS boundaries, retry vs DLT, partition-capped scaling |
| Round 2 (6–11) | Static membership on Deployments, KEDA with concurrency, migrating to KIP-848, losing two brokers, topics as code, consumer shutdown | Kafka as it runs on Kubernetes: membership vs pod identity, autoscaler math, broker-owned liveness, what min ISR really refuses, deploy-time topic changes |

**Next pillar:** [7.1 JVM in containers: cgroups v2, memory, OOMKilled →](../07-Docker-JVM-Kubernetes/01-JVM-in-Containers-cgroups-v2-Memory-OOMKilled.md)
