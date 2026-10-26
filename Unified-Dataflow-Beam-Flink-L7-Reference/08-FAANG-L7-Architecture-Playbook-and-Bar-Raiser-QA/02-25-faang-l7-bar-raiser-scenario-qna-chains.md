# 02 · 25 FAANG L7 Bar-Raiser Scenario Q&A Chains

> **Folder:** `08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/` · **File 2 of 3**
> **Format:** each scenario has a **Prompt**, an **L5 textbook answer**, **why L5 breaks at petabyte scale**, and the
> **L7 principal defense**, with numbers.
> **Cross-reference notation:** `[FF-ff §s]` = Folder FF, file ff, section s (e.g., `[01-02 §6]` = Folder 01, file 02,
> §6).
> **Prev:** [01 · Decision matrix](01-architecture-decision-matrix-beam-dataflow-flink-spark-kafka-streams.md) · **Next:**
> [03 · Reading list and source map](03-curated-github-source-code-and-paper-reading-list.md)

---

## How to use this file

Interviewers at the L7 bar probe four things: **(1) first principles**, meaning you derive the mechanism instead of
naming the product; **(2) quantification**, meaning you put numbers on state, latency, and cost; **(3) failure-mode
fluency**, meaning you know how it breaks and how you'd find it at 3 a.m.; and **(4) trade-off ownership**, meaning you
state what you give up. Each defense below is structured to hit all four. Practice by covering the L7 section and
answering out loud in under four minutes.

---

## Scenario 1 · Global ad-click attribution with late conversions

**Prompt.** Attribute conversions to ad clicks within a 7-day lookback, worldwide, 2M clicks/s, billing-grade
correctness.

**L5 textbook answer.** Join clicks and conversions in a stream with a 7-day window and write the results to the
warehouse.

**Why L5 breaks at petabyte scale.**

- A 7-day interval join buffers clicks for 7 days: 2M/s × 604,800 s × 200 B ≈ **240 TB of join state**.
- Mobile conversions arrive days late.
- Retries duplicate clicks.
- "Billing-grade" means exactly-once *effects* and auditability, which a warehouse append doesn't give.

**L7 principal defense.**

1. **Invert the join:** conversions are ~1000× rarer than clicks. Store clicks in a **keyed external store or
   lakehouse** (by click ID or user ID, TTL 7 days), and process *conversions* as the stream, looking up candidate clicks
   (async I/O, [07-03]). State in the engine drops by orders of magnitude.
2. **Dedup clicks** by click ID at ingestion: exact sharded dedup over the redelivery horizon [03-03 §8.4].
3. **Event-time attribution** with a defined lateness policy. Conversions beyond the streaming horizon go to a daily
   batch re-attribution that **upserts** corrections [01-01 Q2].
4. **Billing output:** an idempotent ledger (inbox pattern) keyed by (conversion ID, attribution model version)
   [06-02 §6.4]. Reconcile streaming vs. batch daily.
5. **Numbers to state:** engine state (~GBs of conversions pending lookup), external store size (~240 TB at 7-day TTL,
   compressible), lookup QPS ≈ conversion rate × candidates.

---

## Scenario 2 · Real-time leaderboard for 100M players

**Prompt.** Top-100 global and per-region leaderboards updated every second. Scores arrive at 500k/s.

**L5 textbook answer.** Key by player and keep scores in state. A global operator keeps a sorted list of the top 100.

**Why L5 breaks at petabyte scale.** A single global top-K operator is **one key** with 500k updates/s, a hot key capped
at single-thread throughput [05-02 §1.2]. Sorting on every update is wasteful. Per-player updates broadcast to one place.

**L7 principal defense.**

1. **Two-phase top-K:**
   - Phase 1: per-player state holds the best score.
   - Phase 2: local top-K per parallel subtask (only emit when a player enters or changes within the local top-K).
   - Phase 3: merge S local top-Ks globally (S × 100 candidates).

   Top-K is a commutative monoid (merge + truncate), so lifting is legal [02-01 §5].
2. **Emit only changes:** most updates don't affect the top 100, so filter early (a score below the local K-th score is
   dropped).
3. **Cadence:** a 1 s processing-time trigger for display (freshness), event-time for tournament-official results.
4. **Device clocks are adversarial:** use server receipt time for the live board and event time only for audited
   tournament windows [01-01 Q3].
5. **Throughput math:** after local filtering, global merge input ≈ S × (changes per second in the local top-K), which is
   tiny.

---

## Scenario 3 · CDC from 500 database shards into Iceberg with upserts

**Prompt.** Replicate 500 Postgres shards (≈ 300k changes/s) into Iceberg, keeping exact current state plus history.

**L5 textbook answer.** Debezium to Kafka, then Flink upserting into Iceberg by primary key.

**Why L5 breaks at petabyte scale.**

- Out-of-order or replayed changes overwrite newer rows (no version guard).
- Quiet shards stall watermarks [01-02 §6].
- Equality deletes accumulate and reads crawl [06-01 §4].
- 100 writers × many partitions produce millions of small files.
- Schema changes break consumers.

**L7 principal defense.**

1. **Version = source LSN (per shard), monotonic.** Upsert *only if newer* (a sequence guard), never by wall clock
   [01-01 F7].
2. **Heartbeats per shard** (Debezium heartbeat) so the watermark never waits on a quiet shard. Alignment bounds replay
   skew [01-02 §6.4].
3. **Iceberg:**
   - hash distribution by partition,
   - bucket(PK) partitioning so deletes touch few files,
   - commit interval sized for ~256 MB files,
   - **continuous compaction** with delete thresholds and starting sequence numbers.
4. **Schema evolution:** registry with BACKWARD_TRANSITIVE, and DDL changes handled by an explicit evolution step (add
   columns only; anything else is a migration) [07-04].
5. **History:** an append-only change table (all versions) plus a current-state upsert table. Time travel is not a
   substitute for an audit log.

---

## Scenario 4 · Fraud scoring under 200 ms p99

**Prompt.** Score every card transaction (200k/s) using per-card features and an external model (50 ms p50, 300 ms p99).

**L5 textbook answer.** A Flink map that calls the model, with high parallelism.

**Why L5 breaks at petabyte scale.** Synchronous calls need λW = 10k concurrent threads. p99 calls block operators,
backpressure reaches Kafka, checkpoints stall, and a model outage restarts the job repeatedly.

**L7 principal defense.**

- **Keyed features** (dedup, velocity buckets with event-time cleanup, travel rule) as point-lookup state [07-03 §3.2].
- **Async I/O:** capacity per subtask = λ_sub × W, `unorderedWait`, a per-attempt timeout well under the budget.
- **A fallback decision** on timeout or error, and retry-on-fallback with backoff. **Never fail the job** on a dependency.
- **Idempotency key = txnId,** because async inputs are re-issued after restore.
- **Visibility:** idempotent decisions by txnId (ms) rather than transactional (checkpoint cadence).
- **SLOs:** p99 latency, fallback rate, model error budget.

---

## Scenario 5 · Rolling 30-day distinct users per merchant, refreshed every minute

**Prompt.** 2M merchants and 1B users; show 30-day distinct users per merchant, updated each minute.

**L5 textbook answer.** A sliding 30-day window, every minute, with a set of users per merchant.

**Why L5 breaks at petabyte scale.**

- 43,200 windows per element (30 d / 1 min) [01-03 §8].
- Exact sets are holistic: O(distinct users) state per merchant per window.
- Hot merchants are hot keys.

**L7 principal defense.**

1. **Sketch:** HLL per (merchant, day). It's mergeable and a few KB, and lifting and salting work [02-01 §3.1].
2. **Slice:** daily HLL slices. The 30-day value is the union of 30 daily slices plus today's partial slice. The minute
   refresh only updates *today's* slice and recomputes the union (30 merges).
3. **Hot merchants:** `withHotKeyFanout` on the daily HLL combine [05-02 §2.2].
4. **Accuracy contract:** ~1% relative error, stated in the product spec. If exact is mandatory, a daily batch exact
   count reconciles.
5. **Storage:** 2M merchants × 31 slices × ~2 KB ≈ 124 GB, which is feasible.

---

## Scenario 6 · Migrating from Lambda to Kappa

**Prompt.** Retire the nightly batch and serve everything from streaming, with replay for backfills.

**L5 textbook answer.** Port the batch logic to the streaming engine and replay Kafka when needed.

**Why L5 breaks at petabyte scale.**

- Streaming code that uses processing time, `Instant.now()`, or late drops produces **different answers on replay**.
- Kafka retention may not cover backfill horizons.
- Replay at 50× speed overwhelms sinks and timers [01-02 W10].

**L7 principal defense.**

1. **Determinism first:** event-time windows, deterministic `DoFn`s, versioned upsert sinks. A CI two-speed replay test
   [01-01 §8, F1].
2. **History:** a tiered log (Kafka tiered storage, or a lakehouse archive as the replay source), so backfills read from
   the lake in **batch mode with the same code** [01-01 §5].
3. **Versioned outputs:** backfill writes a new version or table, validated before the switch, so readers never see
   half-rewritten history.
4. **Replay controls:** rate limits, watermark alignment, sink capacity planning.
5. **Exit criteria:** parity reconciliation between batch and Kappa for N weeks before turning the batch off.

---

## Scenario 7 · The watermark is stuck at 3 a.m.

**Prompt.** You're paged: data freshness is 2 hours and climbing; CPU is normal. Walk me through it.

**L5 textbook answer.** Scale up and restart the job.

**Why L5 breaks.** A restart can **lose the evidence** and doesn't fix holds, idle partitions, or poison messages.
Scaling doesn't change a min over a stalled input or a hold.

**L7 principal defense.** Follow the decision tree [01-02 §9.1]:

1. **Is the source watermark stuck?**
   - Idle partitions or splits (parallelism > partitions)?
   - A poison message retrying forever (Dataflow logs show a repeated exception, oldest-unacked age climbing)?
   - Real backlog?
2. **Otherwise, find the first stage where output watermark ≪ input watermark:**
   - `EARLIEST` timestamp combiner or unbounded sessions?
   - Stateful timers holding (perpetually re-armed)?
   - A control stream without watermarks?
3. **Mitigate:**
   - DLQ the poison via `--update` (Dataflow) or a hotfix;
   - idleness or heartbeats for silent inputs;
   - remove the hold leak.
4. **Verify** that OWM − IWM collapses. **Postmortem:** per-source watermark-lag alerts, DLQ standards, hold audits.

---

## Scenario 8 · Exactly-once payments ledger from Kafka

**Prompt.** Apply payment events from Kafka to account balances in Postgres. No double posting, ever.

**L5 textbook answer.** Flink with an exactly-once JDBC (XA) sink.

**Why L5 breaks at petabyte scale.**

- XA holds row locks on hot accounts for the checkpoint duration.
- Prepared transactions leak after crashes.
- Ledger availability becomes coupled to checkpoint health.
- A checkpoint stall longer than the transaction timeout means aborted transactions and lost postings [06-02 §1.3].

**L7 principal defense.**

1. **Inbox pattern:** insert the event ID into `processed_events` and update the balance **in one local transaction**
   (or one statement with a data-modifying CTE) [06-02 §6.4]. Replays become no-ops.
2. **Deterministic event IDs** from the producer (an outbox on the upstream side).
3. **At-least-once delivery is enough,** because effects are idempotent, so checkpoints only bound replay.
4. **Auditability:** append-only postings plus derived balances, with daily reconciliation.
5. **Hot accounts:** serialize per account (key by account) and batch per account per micro-interval.

---

## Scenario 9 · Sessionization with bots and late mobile events

**Prompt.** Compute session metrics (length, events) for 300M users. Bots generate endless sessions, and mobile events
arrive hours late.

**L5 textbook answer.** `Sessions.withGapDuration(30m)` with 6 hours of allowed lateness.

**Why L5 breaks at petabyte scale.**

- Bot sessions never close: unbounded state, no on-time panes, and under `EARLIEST`, a held watermark for everyone
  [01-03 §3.5].
- Late events **merge already-emitted sessions**, so accumulating outputs double-count [01-03 §7].

**L7 principal defense.**

1. **Epoch-capped sessions** (deterministic, replay-stable) [01-03 §9.3]. `END_OF_WINDOW` timestamps.
2. **Route bots out** before sessionization (a rate detector).
3. **A changelog output** with emulated retractions (containment plus pane index, order-insensitive across shuffles)
   [01-03 §9.5] into a retraction-aware sink (BigQuery CDC, Iceberg, Flink SQL).
4. **Lateness:** 6 h for mobile with coarser downstream aggregation; beyond that, batch re-sessionization.
5. **Measure** the bridge rate (retractions per upsert) and session-length p99.9 against the cap.

---

## Scenario 10 · A 2 PB backfill on a deadline and a budget

**Prompt.** Recompute 18 months of features (2 PB) in 3 days at minimal cost.

**L5 textbook answer.** Run the streaming job in batch mode with a lot of workers.

**Why L5 breaks at petabyte scale.**

- gzip inputs cap parallelism [02-01 §4.1].
- Hot keys create multi-hour tails [03-02 §3.6].
- Shuffle volume and cost explode without projection or combining.
- On-demand capacity is expensive.

**L7 principal defense.**

1. **Inputs:** splittable columnar formats with projection pushdown.
2. **Shuffle:** project before GBKs, combine early, check that lifting isn't losing [02-01 §5.3].
3. **Skew:** sample keys first, then hot-key fan-out and sub-keying [05-02].
4. **Capacity:** FlexRS / spot with a disaggregated shuffle [03-02 §5.3].
5. **Partitioning:** run per month as independent jobs (cheap failures, incremental delivery).
6. **Budget:** measure $/TB on a 1% slice, extrapolate, and fix the largest term. Plan the makespan as W/P + c_max
   [03-02 §3.3].

---

## Scenario 11 · Multi-region active-active streaming

**Prompt.** Process events in two regions; either region can fail without data loss or double-counting.

**L5 textbook answer.** Run the same pipeline in both regions and merge outputs.

**Why L5 breaks.** Both regions process overlapping data, so outputs double-count. Regions disagree whenever results
depend on arrival order or processing time. Failover replays create duplicates.

**L7 principal defense.**

1. **Deterministic, event-time pipelines,** so both regions compute *identical* results for the same input [01-01 §5].
2. **Idempotent, versioned sinks:** both regions upsert with the same keys and versions, so duplicates converge.
3. **Ingestion:** a globally replicated log (or regional logs with deterministic merge), and stable event IDs for dedup.
4. **Choose between active-active compute and active-passive with checkpoint and snapshot replication** by RTO and cost.
   Active-active doubles compute and cross-region transfer.
5. **Per-region watermarks:** a region's output is "final" only after its watermark passes. Consumers prefer the
   primary's outputs and fall back on failure.

---

## Scenario 12 · A real-time feature store without training/serving skew

**Prompt.** Serve features in real time and use the same features for training, with no skew.

**L5 textbook answer.** Compute features in streaming for serving and in SQL for training.

**Why L5 breaks.** Two implementations drift (different window boundaries, null handling, late-data policies). Models see
different feature distributions in production. Point-in-time leakage in training inflates offline metrics.

**L7 principal defense.**

- **One feature definition, two executions:** the same Beam (or Flink) code runs in streaming (online store) and batch
  (offline store) [08-01 §5.4].
- **Event-time semantics with explicit lateness,** and **point-in-time joins** for training labels (features as of the
  label timestamp).
- **Online/offline parity checks:** sample entities and compare.
- **Sliced windows** for rolling features [01-03 §9.6].
- **Feature versioning** in keys, so model versions pin feature versions.

---

## Scenario 13 · 50M IoT devices: ordering and absence detection

**Prompt.** Detect devices silent for 5 minutes and compute in-order metrics, at 50M devices.

**L5 textbook answer.** A processing-time timer per device, reset on every message.

**Why L5 breaks at petabyte scale.**

- 50M timers, each rewritten per message (often every second), means ~50M timer writes per second of commit and state
  churn [03-01 §2.4].
- Out-of-order readings break deltas.
- Bad device clocks poison watermarks.

**L7 principal defense.**

1. **Re-arm sparingly:** only move the timer when the last arm is older than, say, 30 s. Write cost drops ~30×.
2. **Or invert it:** a periodic per-shard sweep (key = device-hash shard) checks last-seen timestamps in `MapState`.
   That's 1 timer per shard instead of per device.
3. **Ordering:** an `OrderedListState` buffer with event-time flush and holds [07-01].
4. **Clamp device timestamps** at the source; partition by producer domain.
5. **Alert idempotency:** key by (device, silence episode) so retries don't duplicate pages.

---

## Scenario 14 · 4,096 Kafka partitions with skewed producers

**Prompt.** One topic with 4,096 partitions. Some are idle and some are hot. Event-time windows lag and state is huge.

**L5 textbook answer.** Add `withIdleness(1 min)` and more TaskManagers.

**Why L5 breaks at petabyte scale.**

- The min over 4,096 inputs means some partition is almost always stalled [01-02 §3.5].
- Short idleness makes the fastest partitions drive the watermark, so the slower ones' data is late.
- Hot partitions overload single subtasks.
- Backfills let fast partitions fill state.

**L7 principal defense.**

1. **Producer heartbeats** per partition (the only near-perfect watermark) [01-02 §6.3].
2. **Lag-aware, two-tier idleness** on the activity clock [01-02 §8.2], plus **watermark alignment** to bound fast
   splits.
3. **Partitioning:** reconsider the partitioning key; 4,096 partitions with idle ones means mis-sized topics.
4. **Hot partitions:** key-level skew fixes downstream (salting) and more consumers only where they help.
5. **Late-data visibility:** side outputs with per-partition counters so idleness costs are measured.

---

## Scenario 15 · Join orders with a 1B-row customer dimension updated hourly

**Prompt.** Enrich 300k orders/s with customer attributes (1B rows, ~500 GB, hourly updates).

**L5 textbook answer.** Broadcast the customer table to all workers.

**Why L5 breaks at petabyte scale.** 500 GB × parallelism is impossible to broadcast [05-02 §3.1]. A regular join keeps
both sides forever. An event-time temporal join stalls between hourly updates [05-03 §3.1].

**L7 principal defense.**

| Need | Approach |
|------|----------|
| **Freshness and determinism matter** (audit) | event-time temporal join against a versioned changelog, partitioned by customer ID, with idleness or heartbeats on the dimension source |
| **"Latest is fine"** | async lookup join against a KV store (Bigtable, Redis, DynamoDB) with a partial cache (hit ratio drives cost) [05-03 §3.2] |
| **Hot customers** | cache plus salting doesn't apply to lookups. The cache absorbs them. |

Size it: cache hit ratio × 300k/s = backend QPS. Project only the needed attributes.

---

## Scenario 16 · Checkpoints take 20 minutes on 50 TB of state

**Prompt.** A Flink job with 50 TB of RocksDB state checkpoints in 20 minutes and recovers in 2 hours.

**L5 textbook answer.** Increase the checkpoint timeout and the interval.

**Why L5 breaks at petabyte scale.** A longer interval increases replay and recovery time, and transactional sinks get even
staler. The 2-hour recovery is a state download problem that tuning the interval doesn't touch.

**L7 principal defense.**

1. **Decompose:** start delay (backpressure), alignment, sync, async upload [04-01 §3.3].
2. **Async:** incremental checkpoints, compaction churn tuning, upload bandwidth, file merging.
3. **Backpressure:** buffer debloating, aligned timeout to unaligned.
4. **Recovery:**
   - local recovery for TM restarts;
   - **ForSt disaggregated state**, so checkpoints reference DFS files and restore is lazy [04-02 §4];
   - async state execution to tolerate remote latency.
5. **Reduce state:** TTL, compaction filters, layout fixes (MapState over big values).
6. **Targets:** checkpoint ≤ 1 minute, recovery ≤ 10 minutes. Validate with game days.

---

## Scenario 17 · The Dataflow bill doubled after a refactor

**Prompt.** Throughput is unchanged, but the Dataflow cost doubled after a code refactor. Find it.

**L5 textbook answer.** The new code is slower. Optimize CPU.

**Why L5 breaks.** CPU may be flat. Streaming Engine and shuffle costs scale with **stage boundaries, bytes per element,
state operations, and timers**, which are all invisible in CPU graphs [03-01 §5; 06-03 §6].

**L7 principal defense.**

1. **Compare optimized graphs** before and after: new `Reshuffle`s or GBKs? New stateful steps? Lost fusion?
2. **Bytes per element:** did a projection disappear? Did a wide object start flowing through shuffles?
3. **State:** a `ValueState<List>` rewrite introduced? Timers re-armed per element?
4. **Logging:** per-element logs added (a Cloud Logging bill)?
5. **Fix and verify $/M events** on a shadow job, and add a cost-regression check to CI or deploy gates.

---

## Scenario 18 · A schema change broke 12 consumers

**Prompt.** A producer added a field and changed another field's type in a shared Avro topic. Twelve streaming consumers
are failing.

**L5 textbook answer.** Roll back the producer and tell the consumers to update.

**Why L5 breaks.** Consumers with savepoints and state may have **already stored** new-format data, so a rollback can break
them again. Replays of retained data hit both formats. There was no gate.

**L7 principal defense.**

1. **Immediate:** stop the producer from emitting the incompatible type. Consumers dead-letter undecodable messages
   instead of crash-looping [07-04 §4].
2. **Compatibility policy:** FULL_TRANSITIVE for shared topics, enforced in CI before deploy.
3. **Type changes are new fields** (add `amount_v2`, deprecate the old one), never in-place.
4. **Consumer state:** check whether new-format data entered state, and migrate offline if needed (State Processor API).
5. **Replay** dead-lettered records after consumers can read both formats.

---

## Scenario 19 · Dedup with up to 7 days of redelivery

**Prompt.** Upstream may redeliver events up to 7 days later. Deduplicate exactly at 1M events/s.

**L5 textbook answer.** Keep a set of seen IDs for 7 days in keyed state.

**Why L5 breaks at petabyte scale.** 1M/s × 604,800 s = 6 × 10¹¹ IDs × ~16 B ≈ **9.7 TB of dedup state**. Per-ID
timers and keys are expensive. A Bloom filter alone drops legitimate records [03-03 §2.2].

**L7 principal defense.**

1. **Tier by recency:**
   - **exact** sharded fingerprint dedup in the engine for the hot horizon (e.g., 1 hour: 3.6 × 10⁹ × 8 B ≈ 29 GB);
   - a **lakehouse anti-join** for the 7-day tail in a batch correction (or a KV store lookup for late arrivals only).
2. **Late arrivals** (beyond the hot horizon) take a slower path: check the external ID store (keyed by fingerprint, TTL
   7 d).
3. **Idempotent sinks** as the backstop, so duplicates converge [06-02 §3].
4. **Quantify** each tier's cost and the duplicate-miss probability (fingerprint collisions ≈ n²/2⁶⁵).

---

## Scenario 20 · Top-K trending hashtags per minute, globally

**Prompt.** Find the top 50 hashtags per minute globally from 3M posts/s.

**L5 textbook answer.** Count per hashtag per minute, then sort globally.

**Why L5 breaks at petabyte scale.** Celebrity hashtags are hot keys [05-02]. Exact counts for millions of distinct tags
per minute, sorted globally, means one giant reducer.

**L7 principal defense.**

1. **Local pre-aggregation** (lifting) per worker, then salted counts for hot tags.
2. **Heavy hitters:** a Count-Min sketch plus a local top-K heap per subtask, merged globally (a mergeable summary).
3. **"Trending" isn't "top":** compute velocity vs. a baseline (e.g., the ratio to a 24 h EMA), using decayed counters
   per tag. They're algebraic and need no eviction [01-03 Q1].
4. **Exactness contract:** approximate is acceptable for trends. State the error bounds.

---

## Scenario 21 · Alerts must not be missed during deploys

**Prompt.** An alerting pipeline must never miss or duplicate an alert during deployments.

**L5 textbook answer.** Use exactly-once and deploy during low traffic.

**Why L5 breaks.**

- `--drain` / drain fires partial windows (spurious or missing alerts) [07-04 §3].
- Cancel loses in-flight state.
- Duplicates appear on restarts.

**L7 principal defense.**

1. **Flink:** stop-with-savepoint (no drain) and restore the new version, so timers and windows resume intact. **Dataflow:**
   a compatible `--update`, or a snapshot plus a new job.
2. **Idempotent alerts:** alert ID = hash(rule, entity, window or episode). The paging system dedups.
3. **Breaking changes:** run new and old in parallel past the longest window, dedup at the pager, then retire the old
   one.
4. **Deploy gates:** savepoint restore test in staging; alert-diff comparison during overlap.

---

## Scenario 22 · BigQuery with under 10 seconds of freshness and exact counts

**Prompt.** Dashboards need per-minute counts in BigQuery within 10 seconds, exactly correct, including late data.

**L5 textbook answer.** Stream inserts into BigQuery from Dataflow every second.

**Why L5 breaks.** Legacy streaming inserts are best-effort dedup. Appending every early pane double-counts. DML MERGE per
pane hits quotas and cost.

**L7 principal defense.**

1. **Accumulating panes** (early panes every 5 s, on-time, batched late panes).
2. **CDC upserts** keyed by (key, window_start), sequence = (epoch, paneIndex), via the Storage Write API
   (at-least-once is fine because upserts are idempotent) [03-03 §4.4; 01-03 §9.2].
3. **`max_staleness` set to about 5–10 s** for the CDC table, a cost vs. freshness trade.
4. **Exactly correct over time:** late panes update the same rows, and reconciliation with the raw archive happens daily.

---

## Scenario 23 · GDPR deletion in streaming state and the lakehouse

**Prompt.** A user requests deletion. Remove their data from streaming state, outputs, and the lake within 30 days.

**L5 textbook answer.** Delete their rows from the warehouse.

**Why L5 breaks.** Data also lives in streaming **state** (keyed by user), checkpoints and savepoints, DLQs, Kafka topics
(retention), and Iceberg snapshots (time travel keeps old files).

**L7 principal defense.**

1. **Streaming state:** a deletion event on a control stream reaches keyed operators (by user ID) and clears state.
   Keyed deletes route naturally.
2. **Logs:** compacted topics with tombstones, or crypto-shredding (encrypt PII with a per-user key and delete the key),
   which makes old copies in checkpoints and archives unreadable.
3. **Iceberg:** row-level deletes, then **compaction plus `expire_snapshots` plus orphan cleanup** to physically remove
   files within the SLA [06-01 §4].
4. **DLQs and backups:** the same crypto-shredding, or retention ≤ SLA.
5. **Audit trail** of deletion completion per system.

---

## Scenario 24 · Reprocess 90 days with a new model while live traffic continues

**Prompt.** A new scoring model must be applied to the last 90 days, plus live traffic, without disrupting production.

**L5 textbook answer.** Replay Kafka into the production pipeline with the new model.

**Why L5 breaks.** Replaying into production mixes historical and live data, overwhelms sinks, pins watermarks behind
replayed data, and overwrites production outputs mid-validation.

**L7 principal defense.**

1. **A shadow pipeline:** the new version reads history from the lakehouse **in batch mode** (same code), writing to
   **versioned outputs** (`scores_v2`).
2. **Live:** the new version runs in parallel on live data from a chosen offset, writing v2 outputs.
3. **Compare** v1 vs. v2 distributions. Switch readers to v2 atomically (view swap) after validation.
4. **Resource isolation:** separate quotas and pools, so the backfill doesn't starve production.
5. **Retire** v1 after a rollback window.

---

## Scenario 25 · Choose Flink or Dataflow for the org-wide platform

**Prompt.** Leadership wants one streaming platform for 200 engineers across analytics, ML, and product teams. Decide.

**L5 textbook answer.** Flink, because it's open source and the most capable.

**Why L5 breaks.** Capability isn't the bottleneck. Operating stateful streaming at scale is. With 200 engineers of mixed
expertise, the platform's failure modes (checkpoints, state, upgrades) become everyone's problem, and people cost
dominates.

**L7 principal defense.**

1. **Segment** workloads by latency, state, and freshness [08-01 §1].
2. **Weighted matrix plus TCO** with people cost and sensitivity analysis [08-01 §3; 06-03 §3].
3. **A likely tiered answer:**
   - a managed engine (Dataflow, with Beam for portability, or managed Flink) for the majority of ETL and analytics;
   - self-managed or managed Flink for the few millisecond-latency stateful products;
   - batch for hourly SLOs.
4. **Unify the platform layer:** schema registry, DLQ standards, deploy gates (savepoint and update tests), cost SLOs via
   labels, golden-path templates.
5. **Exit strategy:** Beam portability and open table formats (Iceberg).
6. **Success metrics:** time-to-first-pipeline, incident rate per pipeline, $/M events, on-call load.

---

## Rapid-fire follow-ups interviewers use (with one-line L7 answers)

| Follow-up | One-line answer |
|-----------|-----------------|
| "Where do holds live: input or output watermark?" | **Output.** On the input they deadlock the stage's own timers [01-02 §3.3]. |
| "Why does the watermark charge you for disorder, not delay?" | BOO watermark = max − Δ, so late iff out-of-orderness > Δ [01-01 §2.3]. |
| "Why can't Dataflow split a hot key?" | GBK and stateful semantics promise one group or state per key. Only you can consent to splitting (lifting, salting) [03-02 Q6]. |
| "Unaligned checkpoints: what's the price?" | Channel state ≈ in-flight bytes × parallelism. Use debloating [04-01 §4.3]. |
| "Why async state in Flink 2.x?" | Little's law: remote R = 10 ms caps sync at 100 ops/s per thread [04-02 §3]. |
| "Exactly-once into Kafka can lose data. How?" | Commit delayed beyond the transaction timeout means the broker aborts [06-02 §1.3]. |
| "Bloom filters for dedup?" | Fast-negative cache in front of an exact store. Never drop on "maybe" [03-03 §2.2]. |
| "Accumulating vs. discarding into an OLAP sink?" | Accumulating + upsert versioned by (epoch, pane index) [01-03 §6.1]. |
| "Why does skew get worse with scale?" | Imbalance ≥ hot share × parallelism [05-02 §1.2]. |
| "TTL vs. timers?" | TTL is processing-time, lazy, and format-changing. Timers are exact and event-time capable [05-03 §5.5]. |

**Next →** [03 · Curated GitHub source code and paper reading list](03-curated-github-source-code-and-paper-reading-list.md)
