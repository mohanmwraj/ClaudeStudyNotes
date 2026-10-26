# 03 · Cloud FinOps: Dataflow vs. Flink on Kubernetes vs. Spark Structured Streaming

> **Folder:** `06-Lakehouse-Sinks-Backpressure-and-FinOps/` · **File 3 of 3**
> **Anchoring sources:** FinOps Foundation framework (inform, optimize, operate) · cloud pricing pages (Dataflow, GCE,
> EC2, S3/GCS, inter-zone networking) · Flink Kubernetes Operator autoscaler (FLIP-271) · Apache Spark Structured
> Streaming docs (triggers, state store) · Barroso, Hölzle & Ranganathan, *The Datacenter as a Computer* (3rd ed., 2018).
> **Prev:** [02 · End-to-end exactly-once](02-end-to-end-exactly-once-two-phase-commit-and-idempotency.md) · **Next
> folder:** `07-Production-Java-Code-Blueprints/`

> **Pricing note.** Prices change and vary by region, contract, and discount. Every number here is **illustrative**,
> chosen to show *structure* and *ratios*, never a quote. Plug in your own rates and keep the formulas.

---

## 0. The thesis

Streaming cost isn't "VM hours". It's a sum of terms whose **drivers are architectural decisions** made long before the
bill arrives:

$$
\text{TCO} = \underbrace{C_{\text{compute}}}_{\text{vCPU·h, GB·h, idle capacity}} + \underbrace{C_{\text{state/shuffle}}}_{\text{SE units, shuffle GB, state storage}} + \underbrace{C_{\text{storage}}}_{\text{checkpoints, PD, lake}} + \underbrace{C_{\text{requests}}}_{\text{object-store PUT/GET}} + \underbrace{C_{\text{network}}}_{\text{cross-AZ, egress}} + \underbrace{C_{\text{platform}}}_{\text{managed premiums, licenses}} + \underbrace{C_{\text{people}}}_{\text{on-call, tuning}}
$$

An L7 engineer can attribute each term to a design choice. For example:

- fusion breaks drive shuffle and Streaming Engine units;
- checkpoint file counts drive request costs;
- all-to-all shuffles across zones drive network costs;
- hot keys drive autoscaler waste.

They then optimize the *largest* term first, measured in **unit economics** ($ per million events, $ per TB processed,
$ per TB-month of state), not in totals.

---

## 1. First principles: the cost terms and their drivers

| Term | Dataflow | Flink on K8s (self-managed) | Spark Structured Streaming |
|------|----------|-----------------------------|----------------------------|
| Compute | worker vCPU/GB-hours (service pricing) | node hours (VMs, spot), bin-packing efficiency | cluster node hours (DBU or instance) |
| State / shuffle | **Streaming Engine** (SECUs or data processed); **Shuffle** (batch, GB) | local NVMe/EBS for RocksDB; **checkpoint storage + requests**; ForSt request costs (2.x) | state store (RocksDB) on local disk; checkpoint storage |
| Idle capacity | autoscaling granularity (per worker VM) | node pools, scaling lag, max parallelism | micro-batch cluster sizing; `availableNow` runs |
| Network | inter-zone traffic usually inside service-managed paths ⚠ verify | **cross-AZ shuffles**, Kafka fetches across AZ | same as Flink |
| Requests | managed internally | **S3/GCS PUT/GET** for checkpoints, savepoints, lake commits | checkpoint and state files |
| Platform | managed service premium; FlexRS / CUD discounts ⚠ verify | operator, monitoring, upgrades: **people** | vendor DBU premium (managed) or self-managed effort |
| People | lowest ops burden | highest (but full control) | medium |

### 1.1 Unit economics

$$
u_{\text{event}} = \frac{\text{TCO per day}}{\text{events per day}} \qquad u_{\text{TB}} = \frac{\text{TCO per day}}{\text{TB processed per day}}
$$

Track them **per pipeline** (via labels) and **per stage** where possible. A pipeline whose $u_{\text{event}}$ doubles
after a code change has a regression even if the total bill looks flat.

---

## 2. The big levers (in order of typical impact)

### 2.1 Stop moving bytes you don't need

Every byte crosses: serialization CPU, shuffle or Streaming Engine billing, network, storage. Fixes, all covered earlier:

- **Projection** before shuffles and joins (Folder 02, file 03; Folder 05, file 03).
- **Combine early** (lifting, local-global) (Folder 02, file 01; Folder 05, file 02).
- **Fewer fusion breaks** (no defensive `Reshuffle`) (Folder 02, file 01).
- **Slicing** instead of sliding windows (1,440× amplification) (Folder 01, file 03).
- **Compression** where network or storage binds.

### 2.2 Eliminate idle capacity

$$
\text{idle fraction} \approx 1 - \frac{\text{average utilization}}{\text{provisioned capacity}}
$$

| Cause | Fix |
|-------|-----|
| Provisioned for peak | autoscaling (Dataflow horizontal autoscaling; Flink operator autoscaler; Spark dynamic allocation) |
| Coarse scaling steps | **smaller workers** (Folder 03, file 01 §5.2) |
| Hot keys inflate scale-out without throughput gain | key-space fixes (Folder 05, file 02); cap max workers |
| Streaming jobs for data that only needs hourly freshness | **scheduled incremental batch** (Spark `Trigger.AvailableNow`, Dataflow batch on new files, Flink batch) |

### 2.3 Use cheaper capacity safely

| Capacity type | Safe when | Engine support |
|---------------|-----------|----------------|
| **Spot / preemptible** | recovery is cheap (shuffle off-node, fast restore) | Dataflow **FlexRS** (batch); Flink with fast recovery (local recovery, ForSt) and checkpoint headroom; Spark with RSS / decommissioning |
| **Committed use / reservations** | steady baseline load | all clouds ⚠ verify product-specific CUDs |
| **Arm instances** | JVM/Python workloads without x86-only native deps | Flink, Spark on K8s; Dataflow Arm workers ⚠ verify |

### 2.4 Network: the cross-AZ tax

All-to-all shuffles in a multi-AZ Kubernetes cluster send about $(1 - 1/z)$ of shuffle bytes across zones (for $z$
zones). At an illustrative $0.01/GB *each direction*:

$$
C_{\text{xAZ}} \approx D_{\text{shuffle}} \cdot \Big(1 - \frac{1}{z}\Big) \cdot 2 \cdot \$0.01/\mathrm{GB}
$$

**Example:** 200 TB/month of Flink network shuffle across 3 AZs is about 133 TB cross-AZ, which is roughly **$2,700 per
month** in transfer charges, often more than the extra compute you'd pay for a single-AZ deployment. Mitigations:

- **Kafka rack-aware fetching** (consumers fetch from the same-AZ replica: KIP-392, `client.rack` plus a rack-aware
  replica selector on brokers);
- **zone-affinity scheduling** for tightly coupled jobs (accept zone-failure risk; recover via checkpoints in regional
  storage);
- **fewer shuffles and smaller shuffle bytes** (§2.1).

### 2.5 Object-store requests: checkpoints and lakes

$$
C_{\text{req}} \approx \underbrace{\frac{86400}{T_{\text{ckpt}}} \cdot F_{\text{ckpt}}}_{\text{PUTs/day}} \cdot p_{\text{PUT}} \;+\; \text{GETs (restores, ForSt cache misses, reads)} \cdot p_{\text{GET}}
$$

**Example:** 1-minute checkpoints × 3,000 new files per checkpoint (many subtasks, incremental SSTs, channel state) is
4.3M PUTs per day. At an illustrative $0.005 per 1,000 PUTs, that's **~$650 per month per job** in requests alone.
Mitigations:

- longer intervals where SLOs allow (Folder 04, file 01 §3.4);
- **small-state inlining** into metadata;
- larger RocksDB target file sizes;
- checkpoint **file merging** (FLIP-306, recent Flink ⚠ verify maturity);
- unaligned checkpoints only when needed (channel state = many files);
- for lakes, fewer commits and compaction (file 01).

---

## 3. Platform comparison (structure, not quotes)

### 3.1 Qualitative

| Dimension | Dataflow | Flink on K8s (self-managed) | Spark Structured Streaming |
|-----------|----------|-----------------------------|----------------------------|
| Ops burden | lowest (managed; autoscaling; no state disks) | highest (operator, upgrades, state tuning, capacity) | medium (managed platforms reduce it) |
| Latency floor | ~100s of ms to seconds (commit per stage) | **ms** (pipelined) | **micro-batch** (≥ hundreds of ms to seconds); low-latency modes vary by vendor ⚠ verify |
| Exactly-once sink visibility | per commit / triggering frequency | checkpoint interval | micro-batch commit |
| State scaling | managed backend | RocksDB local / ForSt remote | RocksDB state store per partition |
| Cost elasticity | strong (autoscaling, FlexRS for batch) | strong with the operator autoscaler and spot, if recovery is fast | strong for `availableNow` scheduled runs |
| Cost transparency | service SKUs (SE, shuffle, workers) | raw infrastructure plus people | DBUs or instances |
| Lock-in | GCP (Beam code is portable to Flink and Spark runners) | low | medium (vendor features) |

### 3.2 An illustrative monthly model

Assumptions (illustrative): 50k events/s average, 1 KB events (~130 TB/month in), a moderate stateful aggregation (2 TB
state), 1-minute freshness.

| Cost term | Dataflow (Streaming Engine) | Flink on K8s (3 AZ, on-demand) | Flink on K8s (1 AZ, 60% spot) |
|-----------|-----------------------------|--------------------------------|-------------------------------|
| Compute | workers sized for user code (small VMs) | nodes for compute **+ local NVMe for state** | same nodes, ~60–70% spot discount on the spot share |
| State / shuffle | Streaming Engine units (driven by shuffle bytes, state ops, timers) | included in nodes (disk) | included |
| Checkpoint storage + requests | n/a (managed) | S3/GCS storage + **PUTs** (§2.5) | same |
| Cross-AZ network | ⚠ verify how inter-zone traffic is billed for managed services | **significant** (§2.4) | ~0 |
| People | low | high (on-call, upgrades) | high, plus spot-recovery engineering |
| Risk | vendor dependence | AZ outage → checkpoint restore elsewhere | zone outage → restore in another zone (RTO hit) |

**How to use the table:**

1. Price each term with your rates.
2. Compute $u_{\text{event}}$.
3. Add **people cost** honestly: one SRE-year often exceeds the managed premium for small fleets and is dwarfed by it for
   very large fleets.

**The crossover heuristic:** managed services win for *many small or medium pipelines and small teams*. Self-managed wins
for *a few very large, steady pipelines with a platform team*.

---

## 4. Flink on Kubernetes: autoscaling that actually saves money

The Flink Kubernetes Operator's **job autoscaler** (FLIP-271) sizes each vertex's parallelism from observed **busy time
and processing rate**, aiming at a **target utilization** and keeping headroom for **catch-up** after restarts:

$$
p_v^{\text{new}} = \left\lceil p_v \cdot \frac{\text{busy}_v}{\text{target utilization}} \cdot \frac{\lambda_{\text{target}}}{\lambda_{\text{current}}} \right\rceil \quad\text{(conceptually)}
$$

**Caveats:**

- **Rescaling restarts** the job (or uses in-place rescaling with the adaptive scheduler where supported ⚠ verify), so
  restore time is a cost. Disaggregated state (ForSt) cuts it.
- **Max parallelism** (key groups) caps scale-out. Set it deliberately (e.g., 720 or 1,440, highly composite numbers) at
  job creation, because it can't change without a state migration.
- **Skewed vertices** won't benefit. The autoscaler will raise parallelism for nothing (busy max ≫ avg). Fix skew first.

---

## 5. Spark Structured Streaming: when micro-batch is the cheap answer

- **`Trigger.AvailableNow`** processes everything available, then stops. Run it every 15–60 minutes from a scheduler for
  pipelines whose SLO is "hourly", and pay for minutes instead of 24×7 clusters.
- **`Trigger.ProcessingTime("1 minute")`** gives continuous micro-batches. Size the cluster for per-batch work and watch
  batch duration vs. trigger interval.
- **State:** use the RocksDB state store provider for large state, with watermark-based state eviction.
- **Cost trap:** tiny trigger intervals mean per-batch scheduling overhead dominates and clusters never scale down.

---

## 6. Dataflow cost levers

| Lever | Effect |
|-------|--------|
| Streaming Engine + small workers | finer scaling granularity; no state disks (Folder 03, file 01) |
| Resource-based SE billing | pay for backend resources used. Fewer boundaries, cheaper state layouts, and fewer timer re-arms reduce cost. |
| At-least-once streaming mode | removes dedup costs where sinks are idempotent (Folder 03, file 03 §5) |
| FlexRS (batch) | preemptible plus delayed start for backfills |
| Right fitting / Prime | per-stage resources; vertical autoscaling (Folder 03, file 03 §6) |
| Max workers and autoscaling bounds | caps runaway scale-out from hot keys |
| Labels | per-pipeline attribution in billing export (§7.3) |
| Logging hygiene | Cloud Logging ingestion is billed. Per-element `LOG.info` at 100k/s is a cost incident. |

---

## 7. Production code and configuration blueprints

### 7.1 Anti-patterns

```text
(A) 24×7 streaming cluster for a dashboard refreshed hourly.
(B) Per-element INFO logging in a DoFn/ProcessFunction at 200k events/s → logging bill > compute bill.
(C) Multi-AZ Flink with all-to-all shuffles and no rack-aware Kafka fetching → cross-AZ transfer dominates.
(D) 30-second checkpoints on a job with 4,000 subtasks → millions of object-store PUTs per day.
(E) Unbounded autoscaling on a hot-key pipeline → max workers, same throughput.
```

### 7.2 Flink Kubernetes Operator: autoscaled, spot-friendly deployment (⚠ verify keys per operator version)

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: orders-enrichment
  labels: { team: payments, pipeline: orders-enrichment, cost-center: cc-1234 }
spec:
  image: registry.internal/flink-jobs/orders-enrichment:2.1.0
  flinkVersion: v2_0
  serviceAccount: flink
  flinkConfiguration:
    # --- autoscaler (FLIP-271) ---
    job.autoscaler.enabled: "true"
    job.autoscaler.metrics.window: "5m"
    job.autoscaler.stabilization.interval: "2m"
    job.autoscaler.target.utilization: "0.65"
    job.autoscaler.target.utilization.boundary: "0.15"
    job.autoscaler.catch-up.duration: "10m"      # headroom to drain backlog after restarts
    job.autoscaler.restart.time: "3m"            # expected restart cost, used in decisions
    pipeline.max-parallelism: "720"              # fixed at creation: caps scale-out (key groups)
    jobmanager.scheduler: adaptive               # in-place rescaling where supported
    # --- cheaper recovery (spot) ---
    execution.checkpointing.interval: "2 min"
    execution.checkpointing.incremental: "true"
    execution.state-recovery.from-local: "true"
    restart-strategy.type: exponential-delay
    # --- request-cost hygiene ---
    state.storage.fs.memory-threshold: "100kb"   # inline small state into checkpoint metadata
    taskmanager.network.memory.buffer-debloat.enabled: "true"
  jobManager:
    resource: { memory: "4g", cpu: 1 }
  taskManager:
    resource: { memory: "8g", cpu: 2 }           # small TMs → fine-grained scaling
    podTemplate:
      spec:
        nodeSelector: { node-pool: spot-arm64 }
        tolerations: [{ key: "spot", operator: "Exists", effect: "NoSchedule" }]
  job:
    jarURI: local:///opt/flink/usrlib/orders-enrichment.jar
    parallelism: 8
    upgradeMode: last-state                      # resume from latest checkpoint on upgrades
```

### 7.3 Attribution: cost per pipeline from the GCP billing export

```sql
-- Net cost per pipeline label and SKU over the last 30 days (Cloud Billing export to BigQuery).
SELECT
  (SELECT value FROM UNNEST(labels) WHERE key = 'pipeline')        AS pipeline,
  service.description                                               AS service,
  sku.description                                                   AS sku,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)), 2) AS net_cost
FROM `billing_ds.gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX`
WHERE usage_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY pipeline, service, sku
HAVING net_cost > 0
ORDER BY net_cost DESC;

-- Unit economics: join with daily event counts (from pipeline metrics exported to BigQuery).
SELECT p.pipeline, p.day, c.net_cost / NULLIF(p.events, 0) * 1e6 AS usd_per_million_events
FROM pipeline_daily_events p
JOIN pipeline_daily_cost c USING (pipeline, day)
ORDER BY usd_per_million_events DESC;
```

```text
# Dataflow: label every job so billing can attribute it (⚠ verify flag syntax per SDK)
--labels=team=payments,pipeline=orders-enrichment,env=prod
--maxNumWorkers=60                       # caps runaway scaling (hot keys)
--workerMachineType=n2-standard-2        # Streaming Engine: start small
--dataflowServiceOptions=enable_streaming_engine_resource_based_billing
```

### 7.4 Cross-AZ reduction for Kafka consumers

```properties
# Broker (once per cluster): allow fetching from the closest replica (KIP-392)
replica.selector.class=org.apache.kafka.common.replica.RackAwareReplicaSelector
broker.rack=us-east-1a

# Consumer (Flink KafkaSource / KafkaIO consumer config): declare the zone the TaskManager or worker runs in
client.rack=us-east-1a
```

Inject `client.rack` per pod from the node's zone label (a downward API or init script) so each TaskManager fetches
same-zone replicas.

### 7.5 Spark: scheduled incremental processing instead of 24×7

```java
// Runs from a scheduler every 30 minutes; processes everything new, commits, exits: pay for minutes, not days.
Dataset<Row> events = spark.readStream().format("kafka")
    .option("kafka.bootstrap.servers", brokers).option("subscribe", "orders")
    .option("maxOffsetsPerTrigger", 50_000_000L)
    .load();

events.selectExpr("CAST(value AS STRING) AS json")
    .writeStream()
    .format("iceberg")                                    // or delta / parquet
    .option("checkpointLocation", "s3://lake/checkpoints/orders-hourly")
    .trigger(Trigger.AvailableNow())
    .toTable("lake.ops.orders_raw")
    .awaitTermination();
```

---

## 8. Cost incidents: failure modes and runbooks

| ID | Incident | Signature | Root cause | Fix |
|----|----------|-----------|------------|-----|
| $1 | **Runaway autoscaling** | workers at max; throughput flat; bill spikes | hot key or unsplittable work | key-space fix; max-worker caps; alert on cost per event |
| $2 | **Cross-AZ transfer surprise** | network SKU ≫ compute | multi-AZ all-to-all shuffles; cross-AZ Kafka fetches | rack-aware fetching; zone affinity; fewer shuffles |
| $3 | **Checkpoint request explosion** | object-store request SKU spikes | short intervals × many files; unaligned channel state | longer intervals; inlining; file merging; debloating |
| $4 | **Logging bill** | Cloud Logging ingestion ≫ expectation | per-element logs; debug left on | sampling; metrics instead of logs; log-level policy |
| $5 | **Idle 24×7 clusters** | low utilization all day | streaming for batch-grade SLOs | `availableNow`, scheduled batch; scale-to-zero |
| $6 | **Streaming Engine cost growth** | SE units grow faster than traffic | added fusion breaks; state rewrites; chatty timers | review the graph; state layouts; timer hygiene (Folder 03, file 01) |
| $7 | **Small-file lake costs** | request plus query costs grow; slow queries | frequent commits, no compaction | distribution; compaction; snapshot expiry (file 01) |
| $8 | **Over-retention** | storage grows indefinitely | retained checkpoints/savepoints; snapshots never expired | retention policies; lifecycle rules on buckets |

### Runbook · $1

1. Alert on **cost per million events** rising faster than throughput (unit economics, §1.1), not only on totals.
2. Inspect busy max vs. avg per vertex or stage. Skew means scaling is futile.
3. Cap max workers immediately, then apply key-space fixes (Folder 05, file 02).
4. Postmortem: add an autoscaling efficiency SLO, measured as throughput gained per worker added.

---

## 9. FAANG L7 bar-raiser Q&A chains

### Q1 · "Dataflow, Flink on Kubernetes, or Spark Structured Streaming for a new platform? Argue it on cost."

**L5 textbook answer.** Flink on Kubernetes is cheapest because it's open source. Managed services cost more.

**Why L5 breaks at petabyte scale.** "Open source is cheaper" ignores people cost, idle capacity, cross-AZ network,
object-store requests, and recovery engineering for spot. For a small team running 40 medium pipelines, the on-call and
tuning cost of self-managed Flink can exceed any managed premium.

**L7 principal defense.**

1. **Write the TCO equation** (§0) and price each term with real rates, *including people*.
2. **Segment workloads:**
   - ms-latency, complex event processing: Flink.
   - Managed elasticity on GCP with many pipelines and a small team: Dataflow (Beam keeps code portable).
   - Hourly-SLO incremental processing: Spark `availableNow` or scheduled batch.
3. **Unit economics** per segment ($/M events), with a crossover analysis.
4. **Risk adjustments:** lock-in (Beam portability), AZ resilience, upgrade cadence.
5. **Decision:** mixed by workload class, under one governance model (labels, cost SLOs).

### Q2 · "Our Flink bill doubled after a multi-AZ migration, but compute didn't change. Why?"

**L5 textbook answer.** Storage costs went up.

**Why L5 breaks.** The likely culprit is **cross-AZ network transfer**: all-to-all shuffles and Kafka fetches crossing
zones, billed per GB in each direction.

**L7 principal defense.**

- **Quantify:** shuffle bytes × (1 − 1/z) × 2 × rate (§2.4), plus Kafka consumer bytes from other-AZ leaders.
- **Fix:**
  - **rack-aware Kafka fetching** (KIP-392);
  - **reduce shuffle bytes** (projection, combine, fewer exchanges);
  - **zone affinity** for tightly coupled jobs, with regional checkpoint storage for zone-failure recovery.
- **Decide explicitly:** is multi-AZ *active* processing worth $X/month, versus single-AZ with checkpoint-based failover
  (an RTO of minutes)?

### Q3 · "How do you make spot instances safe for a stateful streaming job?"

**L5 textbook answer.** Flink checkpoints handle failures, so just use spot.

**Why L5 breaks.** Frequent preemptions plus slow restores (TB state downloads) plus replay mean a job that is *recovering*
much of the time. Cost savings vanish into lost throughput and SLO breaches.

**L7 principal defense.**

- **Make recovery cheap:**
  - local recovery (when pods reschedule on the same node);
  - **disaggregated state (ForSt)** for near-instant restore;
  - incremental checkpoints;
  - small TMs (smaller blast radius).
- **Keep catch-up headroom** (autoscaler catch-up duration), use mixed pools (on-demand baseline plus spot burst), and
  diversify instance types to reduce correlated preemptions.
- **Measure "recovering time %" and $/M events,** and stop if the savings don't materialize.

### Q4 · "Give me three changes that cut a Dataflow streaming bill by 40% without touching business logic."

**L5 textbook answer.** Use smaller machines and reduce `maxNumWorkers`.

**Why L5 breaks.** Shrinking capacity without changing the cost *drivers* just adds lag.

**L7 principal defense.** Attack the drivers:

1. **Remove defensive `Reshuffle`s and extra GBKs.** Fewer stage boundaries means fewer Streaming Engine bytes and
   operations (Folder 03, file 01 §7).
2. **Project and compress before shuffles,** and combine early, so fewer bytes per element.
3. **Cheapen state:** bag/map layouts instead of value rewrites, and fewer timer re-arms.
4. **If sinks are idempotent,** switch to at-least-once streaming mode (removes dedup cost).
5. **Logging hygiene, and small Streaming Engine workers.**

Validate each on a shadow pipeline with $/M events.

---

## 10. Invariants checklist

1. **Measure unit economics** ($/M events, $/TB) per pipeline via labels. Totals hide regressions.
2. **The cheapest byte is the one you don't move:** projection, combine, fewer boundaries.
3. **Idle capacity is the silent majority of waste.** Autoscale, use small workers, run batch for batch-grade SLOs.
4. **Cross-AZ shuffles and fetches are billed.** Use rack-aware Kafka and zone affinity deliberately.
5. **Checkpoint and lake file counts become request bills.** Tune intervals and file counts.
6. **Spot is only cheap if recovery is cheap.**
7. **Count people cost** in build-vs-buy decisions.

---

## 11. References

- FinOps Foundation: *FinOps Framework* (inform, optimize, operate; unit economics).
- L. A. Barroso, U. Hölzle, P. Ranganathan. *The Datacenter as a Computer*, 3rd ed. Morgan & Claypool, 2018.
- Google Cloud: *Dataflow pricing*, *Streaming Engine billing*, *FlexRS*, *Cloud Billing export to BigQuery* (schema).
- Apache Flink Kubernetes Operator: *Autoscaler* (FLIP-271); Flink FLIP-306 (checkpoint file merging).
- Apache Kafka: KIP-392 (*Allow consumers to fetch from closest replica*).
- Apache Spark: *Structured Streaming Programming Guide* (triggers, `availableNow`, state store providers).
- Cloud provider pricing pages for object storage requests and inter-zone transfer (verify current rates).

---

**End of Folder 06.** Next: `07-Production-Java-Code-Blueprints/`.
