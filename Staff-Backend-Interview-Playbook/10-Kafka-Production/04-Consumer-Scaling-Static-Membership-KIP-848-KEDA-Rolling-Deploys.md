# 10.4 Consumer Scaling: Static Membership vs KIP-848, KEDA Scale-Down, Rolling Deploys, and the 45-Second Stall

> **What was run:** `KafkaScaleDownLab`, a Kafka **4.2.2** KRaft cluster started in-JVM (`KafkaClusterTestKit`: 1 controller + 1 broker). Topic `order-events` has 6 partitions. Two consumers (kafka-clients 4.2.2) balance to 3 + 3, then one of them does what a pod does:
> * **Scale-down** (what KEDA does): the consumer closes. We measure how long until the survivor owns all 6 partitions.
> * **Rolling deploy:** the consumer closes and a replacement starts, with a new or the same `group.instance.id`. We measure how long until it's back to 3 + 3, and how long the survivor owned nothing.
>
> Both group protocols were measured: classic and KIP-848 (`consumer`). So were dynamic and static membership, plus `close()` vs `close(LEAVE_GROUP)`. Scale-down scenarios ran once and rolling scenarios twice.
>
> We also did three checks without a cluster:
> * `KafkaGroupFacts` printed the client and broker defaults and tried config combinations against `KafkaConsumer`'s own validation.
> * We read spring-kafka 4.1.2 bytecode (`javap`) to see how it sets `group.instance.id` and closes consumers.
> * We read KEDA v2.21.0's Kafka scaler source.
>
> **Not run:** Kubernetes. Pods are simulated by closing and starting consumers in one JVM. A real replacement pod adds its JVM start (1.3–2.3 s, [7.7 §2](../07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md)) and scheduling time. One broker is enough, because group coordination doesn't depend on replication.
>
> **Builds on:** [10.2 §2 rebalance protocols](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), [7.4 §4 KEDA](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md), [7.3 shutdown](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md). **Corrects:** [10.2](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), [10.3](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) and [7.5](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md), which put `group.instance.id: ${POD_NAME}` on Deployments (§4).

---

## 0. What this file proves 🔥

| Claim | Evidence |
|---|---|
| A **static** member's `close()` doesn't leave the group. The survivor got the partitions after **45.1 s** (classic) or **45.3 s** (KIP-848), which is the session timeout. Dynamic members took **3.0 s** and **0.5 s** | §1.1 |
| spring-kafka 4.1.2 stops consumers with plain `close()` and appends `-0…-N` to `group.instance.id`. So every scale-down of a static pod stalls all its partitions for the session timeout | §1.2 |
| Under KIP-848 the client **rejects** `session.timeout.ms`, `heartbeat.interval.ms` and `partition.assignment.strategy`. The session timeout belongs to the broker: **45 s default, 45 s minimum** | §1.3 |
| `group.instance.id=${POD_NAME}` on a **Deployment** makes every rolling replacement a *new* static member while the old one lingers: **45 s**. With the default assignor the survivor owned **nothing for 41.4 s**, so the whole group stopped | §2 |
| When the **same** id comes back (StatefulSet), the handoff takes 0.16–0.54 s with no revocation. That is the case static membership was designed for | §2 |
| KIP-848 dynamic members: **0.5 s** on scale-down, **0.6–5.7 s** on replacement (bounded by the 5 s heartbeat) | §1.1, §2.2 |
| KEDA caps replicas at the partition count, counting **pods, not consumers**: `concurrency: 3` × 12 replicas = 36 consumers for 12 partitions | §3.1 |
| KEDA's `ensureEvenDistributionOfPartitions` and `limitToPartitionsWithLag` **cannot be combined** (source) | §3.2 |

---

## 1. Scale-down: one consumer leaves (verified) 🔥

### 1.1 The measurements

Six partitions, two consumers at 3 + 3. One closes; `t = 0` is the moment it starts closing. One run each.

| # | Protocol | Membership | Leaver calls | `close()` took | Survivor owns 6/6 after |
|---|---|---|---|---|---|
| A | classic (default assignors) | dynamic | `close()` | 54 ms | 3,043 ms |
| B | classic | **static** | `close()` | 521 ms | **45,138 ms** |
| C | classic | static | `close(LEAVE_GROUP)` | 499 ms | 3,013 ms |
| D | **consumer (KIP-848)** | dynamic | `close()` | 514 ms | **514 ms** |
| E | consumer | **static** | `close()` | 113 ms | **45,308 ms** |
| F | consumer | static | `close(LEAVE_GROUP)` | 506 ms | 506 ms |
| P | classic + `CooperativeStickyAssignor` | **static** | `close()` | 499 ms | **48,023 ms** |

What this shows:

* **A static member's plain `close()` sends no LeaveGroup.** That's deliberate: static membership exists so that a member that's restarting keeps its partitions. The broker can't tell "restarting" from "gone for good". It waits for the session timeout (45 s), and only then reassigns. For those 45 s the leaver's partitions are **consumed by nobody**.
* **`close(CloseOptions.groupMembershipOperation(LEAVE_GROUP))`** (KIP-1092; present in the 4.2.2 client used here) makes a static member leave explicitly. The handoff then matches the dynamic case (C, F).
* **KIP-848 dynamic is the fastest**: 0.5 s, against about one 3 s heartbeat for the classic protocol. In the classic protocol the survivor learns about the rebalance on its next heartbeat (`heartbeat.interval.ms` = 3,000 by default).
* "Classic" with no assignor configured uses the client's default list, `[RangeAssignor, CooperativeStickyAssignor]` (printed in §1.3). The group picks the first assignor every member supports: **Range, which is eager**.

### 1.2 What spring-kafka actually does (bytecode, 4.1.2) 🧊

Two facts from `javap -c` on spring-kafka 4.1.2:

```text
KafkaMessageListenerContainer$ListenerConsumer:
    invokeinterface Consumer.close:()V                 ← the only close call: no CloseOptions, no LEAVE_GROUP
  private void checkGroupInstance(Properties, ConsumerFactory):
    getProperty("group.instance.id") … clientIdSuffix … setProperty("group.instance.id", id + suffix)
```

* The container closes with plain `close()`. A static member run by spring-kafka **never leaves on shutdown**, so every KEDA scale-down of such a pod costs the session timeout (B, E, P).
* `checkGroupInstance` **appends the container's client-id suffix** to `group.instance.id`. With `concurrency: 3`, a pod named `order-service-7d9f8-x2k4p` is **three** static members, `…-x2k4p-0`, `-1` and `-2`. One departing pod strands all of their partitions.

### 1.3 Who owns the session timeout? (verified)

`KafkaGroupFacts` printed the defaults from kafka-clients and the group coordinator (4.2.2), then built a `KafkaConsumer` with each configuration:

```text
client  group.protocol                   classic
client  partition.assignment.strategy    [RangeAssignor, CooperativeStickyAssignor]
client  session.timeout.ms               45000
client  heartbeat.interval.ms            3000
broker  group.consumer.session.timeout.ms        45000  (min 45000, max 60000)
broker  group.consumer.heartbeat.interval.ms     5000   (min 5000)
broker  group.min/max.session.timeout.ms (classic) 6000 / 1800000

  consumer protocol + session.timeout.ms=10000       REJECTED: session.timeout.ms cannot be set when group.protocol=CONSUMER
  consumer protocol + heartbeat.interval.ms=1000     REJECTED: heartbeat.interval.ms cannot be set when group.protocol=CONSUMER
  consumer protocol + CooperativeStickyAssignor      REJECTED: partition.assignment.strategy cannot be set when group.protocol=CONSUMER
  consumer protocol + group.instance.id              accepted
  classic + session.timeout.ms=10000                 accepted
```

* **Under KIP-848, liveness is the broker's job.** The session timeout is `group.consumer.session.timeout.ms`, with a **minimum of 45 s** by default. A per-group override exists (`consumer.session.timeout.ms`, a GROUP config), but it is bounded by that minimum. So a static member on KIP-848 can't be made to fail over faster than 45 s without changing **broker** configuration.
* Under the classic protocol the client chooses, within the broker's 6 s – 30 min range. The client happily accepted 5,000 ms; the broker's 6 s floor is enforced at join time, which wasn't run here.
* ⚠️ **A migration trap:** if you flip an existing classic config (like [10.3 §7](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md)'s) to `group.protocol: consumer` and keep `session.timeout.ms` or `partition.assignment.strategy`, the consumer **fails to construct**, and the application fails at startup. Delete those keys in the same change.

---

## 2. Rolling deploys: one consumer replaced (verified) 🔥

The old consumer closes with plain `close()`, as spring-kafka does (§1.2), and a replacement starts. The "id" columns are what a Deployment and a StatefulSet would give it: Deployment pods get a new random suffix every rollout (`order-service-7d9f8-x2k4p` → `order-service-5c6b7-q8m2z`), while a StatefulSet pod comes back with the same name (`shipping-consumer-1`).

| # | Protocol | Membership of the replaced pod | Back to 3 + 3 (run 1 / run 2) | Survivor dipped to | Survivor owned **nothing** for |
|---|---|---|---|---|---|
| G | classic, default (eager) | dynamic | 3,050 / 3,020 ms | 0 / 3 | 31 / 0 ms |
| H | classic, default (eager) | static, **new** id (Deployment) | **45,123 / 45,106 ms** | 0 / 0 | **41,420 / 41,425 ms** |
| I | classic, default (eager) | static, **same** id (StatefulSet) | 542 / 543 ms | 3 / 3 | 0 |
| J | KIP-848 | dynamic | 5,668 / 606 ms | 3 / 3 | 0 |
| K | KIP-848 | static, **new** id | **45,810 / 45,815 ms** | 2 / 2 | 0 |
| L | KIP-848 | static, **same** id | 159 / 540 ms | 3 / 3 | 0 |
| M | classic, cooperative-sticky | dynamic | 3,010 ms | 3 | 0 |
| N | classic, cooperative-sticky | static, **new** id | **45,077 ms** | 3 | 0 |
| O | classic, cooperative-sticky | static, **same** id | 534 ms | 3 | 0 |

### 2.1 Why the eager group stopped for 41 seconds 🧊

Scenario H is the configuration of an existing blueprint, `group.instance.id: ${POD_NAME}` in a Deployment, run under the client's default assignor:

1. The old pod closes. It's static, so it sends no LeaveGroup and the coordinator still counts it as a member.
2. The new pod joins with a **different** `group.instance.id`, so it's a new member, and its JoinGroup triggers a rebalance.
3. The rebalance is **eager**: every member revokes **all** its partitions and rejoins. The survivor drops to 0.
4. The coordinator waits for **every known member** to rejoin, including the old static member, which is never coming back. That wait ends when its session times out, 45 s after its last heartbeat.
5. Only then are partitions assigned. The survivor owned nothing for **41.4 s**. Every member of the group did.

With cooperative-sticky (N) the survivor keeps its 3 partitions, but the dead member's 3 are still stranded for 45 s. Under KIP-848 (K) the broker gave the newcomer **one** of the survivor's partitions at once (the survivor dipped to 2), while the ghost's 3 waited the 45 s. **Every protocol pays the 45 s for a new static id.** The eager one also stops everybody else.

### 2.2 Why KIP-848 replacement took 0.6 s once and 5.7 s once

Under KIP-848, partitions move by **reconciliation on heartbeats**. The survivor must give up partitions on a heartbeat before the newcomer can receive them, and the broker's heartbeat interval is 5 s (§1.3). So the handoff takes anywhere from almost nothing to about one interval, depending on where in the cycle the change lands: 606 ms in run 2, 5,668 ms in run 1. Through all of it the survivor kept processing its own partitions. That is the point of incremental protocols: nothing that isn't moving stops.

---

## 3. Scaling math: partitions, pods, concurrency, KEDA ⚡

### 3.1 KEDA's cap counts pods, not consumers

KEDA's Kafka scaler computes `replicas ≈ ceil(lag / lagThreshold)` and, with `allowIdleConsumers: false`, caps the result at the partition count ([7.4 §4.1](../07-Docker-JVM-Kubernetes/04-CPU-Throttling-GC-Choice-HPA-KEDA.md)). It has no idea that each pod runs `concurrency` consumers:

| Partitions | `concurrency` | KEDA max (= partitions) | Consumers at max | Idle consumers |
|---|---|---|---|---|
| 12 | 1 | 12 | 12 | 0 |
| 12 | 3 | 12 | 36 | **24** |

Either run **one consumer per pod** (`concurrency: 1`, the blueprint below, which keeps pod = consumer = KEDA's unit), or set `maxReplicaCount: partitions / concurrency` and multiply `lagThreshold` by `concurrency`. Idle consumers aren't free. Each holds connections and heap, joins every rebalance, and makes each scale event bigger.

### 3.2 Uneven partition counts waste replicas (KEDA source, v2.21.0)

Twelve partitions over **5** consumers split 3, 3, 2, 2, 2. The two consumers with 3 partitions set the group's throughput, so 5 replicas do the work of **4**. KEDA has an option for exactly this. `ensureEvenDistributionOfPartitions: "true"` makes `getNextFactorThatBalancesConsumersToTopicPartitions` pick the smallest **factor of the partition count** that covers the lag:

```go
// pkg/scalers/kafka_scaler.go (v2.21.0), abridged
factors := FindFactors(totalTopicPartitions)        // 12 → [1 2 3 4 6 12], sorted
for _, factor := range factors {
    if factor*lagThreshold >= totalLag { return factor }
}
```

With 12 partitions the replica count steps 1 → 2 → 3 → 4 → **6** → 12, never 5. Two constraints from the same file:

```text
"limitToPartitionsWithLag and ensureEvenDistributionOfPartitions cannot be set simultaneously"
"topic must be specified when using ensureEvenDistributionOfPartitions"
```

So pick one. [7.5](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) uses `limitToPartitionsWithLag` (scale only to the partitions that have lag), and [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md) uses even distribution. Both cap at partitions. Choose partition counts with many divisors (12, 24, 60); [10.3 §5](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md) chose 12.

### 3.3 The feedback loop static membership creates under KEDA (arithmetic)

Take `order-events` at 200 records/s per partition, a static consumer Deployment with `concurrency: 3` and 12 partitions, and KEDA at `lagThreshold: 1000`:

```text
one pod replaced in a rollout   → its 3 static members linger 45 s   → 3 partitions × 45 s × 200/s = 27,000 records of lag
KEDA: 27,000 / 1,000            → wants 27 replicas, capped at 12     → scale-up DURING the deploy
lag drains, stabilization ends  → scale-down by N pods                → each removed pod: 3 more partitions stalled 45 s
                                                                      → lag spike → scale-up …
```

Nothing is broken and nothing errors, but the dashboards show lag sawtooth and replica churn after every deploy, and the consumer-lag alert gets tuned until it's useless. With KIP-848 dynamic membership the same events cost about half a second each (D, J).

### 3.4 Two KEDA timing knobs people mix up

* `cooldownPeriod` (default 300 s) applies only to scaling **to zero**, after the last active trigger, per the KEDA documentation. Between 1 and N replicas, scaling is the generated HPA's `behavior` (default scale-down stabilization: 300 s), which you set under `advanced.horizontalPodAutoscalerConfig.behavior` ([7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md)).
* `pollingInterval` (default 30 s) is how often KEDA reads lag. At 200 records/s per partition, one interval is 6,000 records per partition before KEDA even notices.

---

## 4. ⚠️ Corrections to 10.2, 10.3 and 7.5 🧊

Three earlier blueprints set `group.instance.id: ${POD_NAME}` on consumers that run as **Deployments**, with the comment "no rebalance on a quick restart". §2 shows what that buys in a Deployment: a new static id on every rollout and a 45 s stall each time, with the whole group stopped under an eager assignor. §1 shows the same stall on every scale-down. Fixed in place:

| File | Was | Now |
|---|---|---|
| [10.2 §2.2](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md) | "Static membership … Ideal for rolling deploys"; "`consumer.close()` leaves the group immediately" | Static only with **stable** ids (StatefulSet); `close()` leaves only for **dynamic** members |
| [10.2 §7](02-Kafka-Consumers-Rebalancing-EOS-Retries-DLQ.md), [10.3 §7](03-Production-Kafka-Multi-Broker-Durability-Compaction-Strimzi-Blueprint.md), [7.5 §2](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) | `group.instance.id: ${POD_NAME}` | Removed, with a pointer here |
| [7.5 §4](../07-Docker-JVM-Kubernetes/05-Production-Blueprints-application-yml-Dockerfile-Deployment.md) | `POD_NAME` env "for Kafka static membership" | Removed from the Deployment |
| [9.5](../09-Staff-Capstone/05-Production-Readiness-Checklists.md) | "static membership for rolling deploys" | "dynamic membership on Deployments; static only with StatefulSet ids" |

The original reasoning was right for StatefulSets (I, L, O: 0.16–0.54 s, no revocation) and wrong for Deployments. **Static membership is about identity, and a Deployment pod has none.**

---

## 5. Decision table: membership × workload 🔥

| Workload | Protocol | Membership | Scale-down handoff | Rolling replacement | Notes |
|---|---|---|---|---|---|
| **Deployment** with HPA or KEDA (most consumers) | **KIP-848** (`group.protocol: consumer`; brokers ≥ 4.0) | **dynamic** | 0.5 s (D) | 0.6–5.7 s (J) | The default. Nothing else in the group stops |
| Deployment, classic-only clients or brokers | classic + cooperative-sticky | dynamic | ~3 s (A, M) | ~3 s (M) | Bounded by `heartbeat.interval.ms` |
| **StatefulSet** whose consumers keep per-partition local state (warm caches, local stores) | classic + cooperative-sticky | **static**, ordinal ids | = `session.timeout.ms` (P: 48 s at 45 s) | 0.5 s (O) | Set the session timeout just above the restart time (30 s in the blueprint); scale down rarely |
| StatefulSet on KIP-848 | consumer | static | **≥ 45 s** (E), the broker minimum | 0.16–0.54 s (L) | Lower `group.consumer.min.session.timeout.ms` on the brokers if 45 s is too long |
| Kafka Streams | — | — | — | — | Out of scope: its own rebalance protocol and standby replicas |

Two rules sit underneath the table:

* **Static membership trades scale-down speed for restart stability.** It's worth it only when a restart would otherwise rebuild expensive per-partition state.
* **Whatever you choose, budget the stall into the lag SLO.** "Lag under 30 s" and "45 s static-member timeout" can't both be true during a scale-down.

---

## 6. Blueprints (validated) ⚡

**Validation (verified):** both files were checked against Spring Boot 4.1.2's configuration metadata (1,722 properties): `blueprint-deployment.yml: 17 keys … problems: 0`; `blueprint-statefulset.yml: 16 keys … problems: 0`. Their free-form Kafka properties were passed to a real `KafkaConsumer` and both were **accepted** (§1.3).

### 6.1 Deployment + KEDA (the default)

```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    security:
      protocol: SSL
    ssl:
      bundle: kafka-shipping-consumer
    consumer:
      group-id: shipping
      auto-offset-reset: earliest
      enable-auto-commit: false
      max-poll-records: 100
      isolation-level: read-committed
      properties:
        group.protocol: consumer                 # KIP-848: broker-side assignment, no group-wide barrier
        max.poll.interval.ms: 120000
        client.rack: ${NODE_ZONE:}
        # Deliberately absent (10.4 §1.3, §4): group.instance.id, session.timeout.ms,
        # heartbeat.interval.ms, partition.assignment.strategy
    listener:
      ack-mode: record
      concurrency: 1                             # one consumer per pod: KEDA's partition cap counts pods (§3.1)
      observation-enabled: true
  ssl:
    bundle:
      pem:
        kafka-shipping-consumer:
          keystore:
            certificate: file:/etc/kafka-user/user.crt
            private-key: file:/etc/kafka-user/user.key
          truststore:
            certificate: file:/etc/kafka-cluster-ca/ca.crt
```

The Kubernetes side is a Deployment with no `replicas` plus a `ScaledObject` with `maxReplicaCount: 12` (the partitions), `ensureEvenDistributionOfPartitions` and TLS from a `TriggerAuthentication`. It's rendered and validated in [7.8](../07-Docker-JVM-Kubernetes/08-Kubernetes-Platform-Blueprints-II-Kustomize-Guardrails-Consumers-Jobs-Canary.md).

### 6.2 StatefulSet with static membership (only when restarts must keep partitions)

```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    security:
      protocol: SSL
    ssl:
      bundle: kafka-shipping-consumer
    consumer:
      group-id: shipping-stateful
      auto-offset-reset: earliest
      enable-auto-commit: false
      max-poll-records: 100
      isolation-level: read-committed
      properties:
        group.protocol: classic                  # static members on KIP-848 wait >= 45 s (broker minimum) on every scale-down
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        group.instance.id: ${POD_NAME}           # StatefulSet: shipping-stateful-0, -1, ... survive restarts
        session.timeout.ms: 30000                # a restart must rejoin within this; a scale-down stalls this long
        max.poll.interval.ms: 120000
    listener:
      ack-mode: record
      concurrency: 1                             # spring-kafka appends -0..-N to group.instance.id per consumer
      observation-enabled: true
```

`POD_NAME` comes from the downward API (`fieldRef: metadata.name`). In a StatefulSet that name is the ordinal identity, which is the whole point.

### 6.3 Shutdown budget for a consumer pod

A consumer receives no Service traffic, so the `preStop: sleep` that protects HTTP pods ([7.3 §3.3](../07-Docker-JVM-Kubernetes/03-Kubernetes-Probes-and-Graceful-Shutdown.md)) only delays its departure. The budget is:

```text
terminationGracePeriodSeconds ≥ in-flight record processing (max.poll.records × p99 per record, or AckMode.RECORD: one record)
                               + the container stop wait (spring-kafka ContainerProperties.DEFAULT_SHUTDOWN_TIMEOUT = 10000 ms, verified)
                               + commit + LeaveGroup (dynamic: ~0.5 s, D) + producer flush + pool close
                               + margin
```

30 s covers it for record-at-a-time listeners that finish each record in under a second. A batch listener that processes 100 records at 200 ms each needs 20 s for the batch alone. If the `SIGKILL` lands first, nothing is committed for that batch, and it is redelivered to the next owner. That's safe only with an idempotent consumer ([5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md)).

---

## 7. ❌ Naïve vs ✅ production-hardened

| ❌ Naïve | ✅ Hardened |
|---|---|
| `group.instance.id: ${POD_NAME}` on a Deployment "to avoid rebalances" | No static id on Deployments: every rollout is a new id and a 45 s stall (§2) |
| "`close()` leaves the group, so scale-down is instant" | Only for dynamic members. A static `close()` waits out the session timeout (§1.1) |
| Flip `group.protocol: consumer` and keep `session.timeout.ms` / the assignor | Remove them in the same change: the consumer fails to construct (§1.3) |
| "Lower `session.timeout.ms` to 10 s" on KIP-848 | Not a client setting there. The broker minimum is 45 s (§1.3) |
| `concurrency: 3` + KEDA `maxReplicaCount: partitions` | `concurrency: 1`, or divide the cap by concurrency (§3.1) |
| 12 partitions, 5 replicas | Even distribution (factors of 12) or `limitToPartitionsWithLag`, not both (§3.2) |
| `cooldownPeriod` tuned to stop 6 → 5 flapping | It only governs → 0. Tune the HPA `behavior` (§3.4) |
| `preStop: sleep 10` on consumers, copied from the API | No preStop. The grace period covers the in-flight batch + 10 s container stop (§6.3) |
| Static membership everywhere "for stability" | Static only for stateful consumers in StatefulSets, with the stall in the lag SLO (§5) |

---

## 8. Bar-raiser Q&A 🔥

🎤 *"Our consumers use static membership with the pod name, so rolling deploys don't trigger rebalances."*

🔍 **Your consumers run as a Deployment. What's the pod name after a rollout?**

<details><summary>🛡️ Defense</summary>

A new one: Deployment pods get a new hash and suffix every revision. So the replacement joins as a new static member while the old one, which never sent LeaveGroup, is still counted. I measured it: back to full assignment after 45.1 s, the session timeout. With the default assignor, which resolves to eager Range, the new member's join forced everyone to revoke, and the surviving consumer owned nothing for 41.4 s. The whole group was stopped for most of a minute per replaced pod. Static membership needs a stable identity. A StatefulSet ordinal has one (0.5 s, no revocation in my run); a Deployment pod doesn't.
</details>

🔍 **Fine, use a StatefulSet then. What happens when KEDA scales it down?**

<details><summary>🛡️ Defense</summary>

The removed ordinal never comes back, and spring-kafka closes with plain `close()`. I checked the 4.1.2 bytecode: there's no `CloseOptions`. So the broker waits the session timeout before reassigning: 48 s in my cooperative-sticky run, 45.3 s under KIP-848. With concurrency 3 that's three static members, because spring-kafka appends `-0`, `-1`, `-2` to the id. Every scale-down then strands that pod's partitions for 45 s, and those partitions build lag, which KEDA reads as a reason to scale back up. So I'd only do it for consumers with expensive per-partition state. I'd lower the classic session timeout to just above the restart time (30 s), make scale-downs rare, and put the stall in the lag SLO.
</details>

🔍 **Just set `session.timeout.ms` to 10 seconds.**

<details><summary>🛡️ Defense</summary>

On the classic protocol you can (the broker allows 6 s to 30 min), but then any restart that takes longer than 10 s, such as a slow image pull or a node drain, falls out of the group anyway, and you're back to the stall. On KIP-848 you can't: the client rejects `session.timeout.ms` outright ("cannot be set when group.protocol=CONSUMER", verified). The broker owns liveness, with `group.consumer.session.timeout.ms` defaulting to 45 s and its minimum also 45 s. Going lower means changing broker configuration for every group on the cluster. That's usually the sign that you wanted dynamic membership.
</details>

🔍 **So what do you run?**

<details><summary>🛡️ Defense</summary>

KIP-848 with dynamic members, one consumer per pod, in a Deployment scaled by KEDA. Measured: 0.5 s from a pod closing to the survivor owning its partitions. A replacement took 0.6–5.7 s depending on where the broker's 5 s heartbeat cycle was, and nothing else in the group stopped during either. KEDA caps at the partition count, 12, and steps through factors of 12 so no consumer carries more partitions than the others. No `preStop` sleep on consumers, and a grace period that covers the in-flight batch plus spring-kafka's 10 s container stop.
</details>

🔍 **Why one consumer per pod? Concurrency is cheaper than pods.**

<details><summary>🛡️ Defense</summary>

Because the autoscaler's unit is the pod. KEDA's Kafka scaler caps replicas at the partition count; it doesn't know that each pod runs three consumers. With 12 partitions and concurrency 3, KEDA's max of 12 pods is 36 consumers, 24 of them idle but still holding connections, heap and a seat in every rebalance. If you want concurrency, divide `maxReplicaCount` by it and multiply `lagThreshold` by it. One consumer per pod keeps the math honest, and the [7.7](../07-Docker-JVM-Kubernetes/07-Container-Images-and-JVM-Profiles-Blueprints-II-jlink-AOT-Workloads.md) consumer profile (Serial GC, 256 MB heap in 512 MiB) keeps pods cheap.
</details>

🔍 **We're migrating from cooperative-sticky to KIP-848. What's the risk?**

<details><summary>🛡️ Defense</summary>

Three things. First, the config: `session.timeout.ms`, `heartbeat.interval.ms` and `partition.assignment.strategy` are rejected under `group.protocol=consumer`, so leaving any of them in the file makes the application fail at startup. That's actually a good failure, because it happens in the canary. Second, the brokers must be 4.0 or newer with the new coordinator. Third, the semantics: assignment moves to the broker (`group.remote.assignor` if you need to choose), and liveness timing moves there too, with a 45 s minimum session that only matters if you use static members. I'd roll it per consumer group behind a config flag, watch the rebalance and lag metrics through one deploy and one scale-down, then remove the classic settings.
</details>

---

## 9. Source to read

* [KIP-848: The Next Generation of the Consumer Rebalance Protocol](https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol): reconciliation, broker-side assignors, and why session and heartbeat settings moved to the broker.
* [KIP-345: static membership](https://cwiki.apache.org/confluence/display/KAFKA/KIP-345%3A+Introduce+static+membership+protocol+to+reduce+consumer+rebalances) and [KIP-1092](https://cwiki.apache.org/confluence/display/KAFKA/KIP-1092%3A+Extend+Consumer%23close+with+an+option+to+leave+the+group+or+not): why a static `close()` doesn't leave, and the `CloseOptions` that can.
* [Apache Kafka consumer configs](https://kafka.apache.org/documentation/#consumerconfigs) and [group coordinator broker configs](https://kafka.apache.org/documentation/#brokerconfigs): `group.consumer.*`.
* spring-kafka [`KafkaMessageListenerContainer`](https://github.com/spring-projects/spring-kafka/blob/main/spring-kafka/src/main/java/org/springframework/kafka/listener/KafkaMessageListenerContainer.java): `checkGroupInstance` and the consumer's `close()`.
* KEDA [`pkg/scalers/kafka_scaler.go`](https://github.com/kedacore/keda/blob/main/pkg/scalers/kafka_scaler.go): `getTotalLag`, `getNextFactorThatBalancesConsumersToTopicPartitions`, the option validation.

---

## 10. Interview soundbites

* "Static membership is about identity. A Deployment pod has none, so `POD_NAME` as `group.instance.id` gave me a 45 s stall per replaced pod, and with an eager assignor the whole group sat idle for 41 s."
* "A static member's `close()` doesn't leave the group, and spring-kafka 4.1.2 only calls plain `close()`. So every scale-down of a static pod strands its partitions for the session timeout."
* "Under KIP-848 the client rejects `session.timeout.ms`. The broker owns it: 45 s default, 45 s minimum."
* "KIP-848 dynamic: half a second from a pod closing to its partitions being consumed again. That's what I run on Deployments."
* "KEDA's partition cap counts pods. With concurrency 3, 12 replicas means 24 idle consumers, so I run one consumer per pod."
* "Twelve partitions over five consumers is the throughput of four. I let KEDA step through factors of the partition count."

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Static scale-down | Plain `close()` sends no LeaveGroup: 45.1 s (classic), 45.3 s (KIP-848), 48.0 s (cooperative) vs 3.0 s / 0.5 s dynamic | §1.1 |
| spring-kafka | Plain `close()` only; `group.instance.id` + `-0…-N` per concurrent consumer | §1.2 |
| Session timeout owner | KIP-848: broker, 45 s default and minimum; client settings rejected | §1.3 |
| Rolling deploy, Deployment | New static id = 45 s; eager group fully stopped 41.4 s | §2, §2.1 |
| Rolling deploy, StatefulSet | Same id back in 0.16–0.54 s, no revocation | §2 |
| KIP-848 dynamic | 0.5 s scale-down, 0.6–5.7 s replacement (5 s heartbeat) | §1.1, §2.2 |
| KEDA math | Cap counts pods; even distribution via factors; not combinable with `limitToPartitionsWithLag` | §3.1–3.2 |
| Feedback loop | Static + KEDA: deploy → lag → scale-up → scale-down → stall | §3.3 |
| Corrections | `group.instance.id: ${POD_NAME}` removed from Deployment blueprints in 10.2, 10.3, 7.5 | §4 |
| Decision | Deployment → KIP-848 dynamic; StatefulSet with state → static, short classic timeout | §5 |
| Blueprints | Both validated (Boot metadata 0 problems; `KafkaConsumer` accepted); consumer shutdown budget | §6 |

**Next:** [10.5 Kafka bar-raiser drill-downs →](05-Bar-Raiser-Drill-Downs.md)
