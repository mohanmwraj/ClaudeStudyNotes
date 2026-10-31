# 03.1 · Archetype A: Enterprise Data Migration and Streaming Pipeline (Java, Beam/Dataflow, Kafka, BigQuery/GCS)

> **Folder:** `03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes` · file 1 of 4
> **Question this file answers:** I led a legacy-to-cloud data migration: nightly batch replaced by CDC → Kafka → Dataflow → BigQuery/GCS. What does the whiteboard look like, which three mechanisms will two Principal Engineers drill into, and how do I defend exactly-once effects, completeness, backfill and cutover with numbers and running code?
> **Composite exhibit:** "Tidewater", a national insurer's policy-and-claims pipeline. It was previewed in [02.1](../02-The-3-Viable-Options-Tradeoff-Defense-Framework/01-proving-first-principles-why-you-rejected-option-a-and-option-b.md) and [02.2](../02-The-3-Viable-Options-Tradeoff-Defense-Framework/02-quantifying-bottlenecks-before-and-after-latency-throughput-and-finops-math.md). All numbers are placeholders, made internally consistent.
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L7 `TidewaterPipeline.java` | Java 21 source level, Apache Beam 2.77.0, DirectRunner | A real Beam pipeline driven by a scripted `TestStream`: parse to a dead-letter queue; stateful dedup by event id with a bounded horizon; event-time windows with allowed lateness and late firings; per-window control totals. A reconciliation step catches a too-late event that the runner dropped. | [§12](#12-listing-and-output), compiled with `javac --release 21 -Xlint:all -Werror` and run on JDK 25 |

**Verification.** The gate extracts the listing, checks it byte for byte against the source, compiles it against the Beam 2.77.0 jars with all lint warnings treated as errors, runs it, and compares the output with §12. The program asserts its own expected panes and totals and prints `verdict: OK` only if every one holds. The constraint ledger in §9 is validated by `constraint_check.py`, and the tellings by the Folder 01 lints. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

**Who this archetype fits.** Engineers who moved an enterprise's data from on-prem batch (mainframe extracts, Oracle, ETL tools, warehouse appliances) to a cloud streaming platform. Typical résumé lines: "migrated N TB / N pipelines to GCP", "built a streaming pipeline on Dataflow", "real-time ingestion with Kafka and BigQuery".

**Why it's dangerous in a deep dive.** Data pipelines invite three claims that sound strong and collapse under one probe:
- "exactly-once";
- "real-time";
- "the numbers match".

The interviewers know the precise semantics behind each, and they will test whether you do. This file gives you the composite blueprint, three deep wells, a failure story, the trade-off defense, a numbers card, and a real Beam program that demonstrates the mechanisms.

**How to use it.** Replace Tidewater's facts with your own project's, keep the structure, and run your own pipeline's equivalent of the listing on your laptop. A Beam pipeline with `TestStream` is a cheap way to make sure you can explain *exactly* what your windows and triggers do before someone asks.

---

## 1. First principles: what interviewers assume about this archetype

### 1.1 The attack surface

| Claim on the résumé | What the interviewer suspects | The probe | What survives it |
|---|---|---|---|
| "Exactly-once pipeline" | Delegated correctness to a product name | "Where can a duplicate still come from?" | Exactly-once *effect*: at-least-once delivery + idempotent processing + a sink with exactly-once semantics, *and* reconciliation that measures it (§4) |
| "Real-time" | Undefined latency | "From what event to what event, at what percentile?" | "Source commit to queryable, p95 ≈ 3 min, measured by heartbeat rows" (§2.5) |
| "Numbers match the legacy system" | Spot-checked a few reports | "How do you know *all* of them match?" | Control totals per table per partition-day, both directions, with automated repair (§4.4, §6) |
| "Migrated N pipelines" | Lift-and-shift, no redesign | "What did you change about the data model?" | The dedup key, partitioning, clustering, the late-data policy |
| "Handles late data" | Default trigger, never tested | "What happens to an event 3 hours late?" | Allowed lateness, late firings, the drop path and how it's detected (§5) |

### 1.2 The three questions every Archetype A defense must answer

1. **Correctness:** how does each source change produce exactly one effect in the warehouse, and how do you *know*?
2. **Completeness:** when is a window's answer final, and what happens to data that arrives after that?
3. **Continuity:** how did 214 downstream reports move from the old warehouse to the new one without a day of wrong numbers?

Every section below maps to one of these.

---

## 2. The composite project: "Tidewater" fact sheet

### 2.1 Before-state

- **Sources:**
  - policy administration on a mainframe (DB2 for z/OS);
  - claims on Oracle 19c;
  - 38 tables in scope.
- **Pipeline:**
  - Nightly extracts: fixed-width files from the mainframe and CSV from Oracle.
  - An ETL tool loads them into an on-prem warehouse appliance.
  - Volume: 180M records a night at 9,000 records/s, so **5.56 h of a 6 h window**.
  - **71% of that time is one single-threaded merge stage.**
- **Growth:** 35% a year, so the window overflows in about **3.1 months** (02.2 §4.2).
- **Freshness:** about 24 h on average, **29.6 h worst case**.
- **Consumers:** 214 downstream reports, 9 of them regulatory.

### 2.2 Forcing functions

- **Freshness requirement:** claims triage committed to its regulator to acknowledge first notice of loss within a window that needs new claims queryable within **30 min at p95**. Signed off by the claims director.
- **Capacity step:** the appliance's next capacity step costs ~$38k/month, needed when the window overflows.
- **Roadmap requirement (not committed at design time):** the fraud team needed claim events within 5 min, 2 quarters later. This was the tie-breaker in 02.1 §8.3.

### 2.3 Goals and kill criteria

| ID | Goal | Threshold | Kind |
|---|---|---|---|
| K1 | Freshness, source commit → queryable | p95 ≤ 30 min | Kill |
| K2 | Regulatory counts reconcile to the source | Control totals equal per table per partition-day | Kill |
| K3 | Same code for streaming and the 7-year backfill | One pipeline, two modes | Kill |
| K4 | Headroom | 2× current volume without redesign | Kill |
| G5 | Cost per million events at 12 months ≤ on-prem | Total cost including people (02.2 §6.2) | Scored |

### 2.4 Architecture after (ownership marked)

| # | Component | Mark | What it does |
|---|---|---|---|
| A1 | Log-based CDC (DB2 and Oracle) | ◆ configuration reviewed with the DBA team | Emits row changes with source commit time, log sequence number (LSN) and table key |
| A2 | Kafka (platform team) | ○ | 38 topics; the claims topic has 48 partitions; Avro with a schema registry; 7-day retention |
| A3 | Streaming pipeline (Beam Java on Dataflow) | ★ designed; wrote dedup, windowing, sink semantics | Parse → DLQ → dedup (stateful, 7-day horizon) → enrich (reference side input, refreshed every 10 min) → hot-key salting → BigQuery (Storage Write API) + raw Avro archive (GCS, 10-min files) |
| A4 | Reconciliation job | ★ designed and wrote | Source control totals (count, sum of amounts, an order-independent hash of keys) vs warehouse totals, per table per partition-day; mismatch → alert + repair |
| A5 | Backfill | ★ designed the handoff | The same Beam pipeline in batch mode over 7 years of historical extracts in GCS; a handoff timestamp separates backfill from stream (§6) |
| A6 | BigQuery warehouse | ○ warehouse team, ◆ partitioning and clustering design | Tables partitioned by event date, clustered by `policy_id` |
| A7 | Report migration | ★ cutover plan; ○ report rewrites by analytics teams | 214 reports; 3-month dual run with automated comparisons |
| A8 | Freshness heartbeat | ★ | A heartbeat row written every minute in each source database, read from BigQuery: the measurement for K1, and also an idle-partition watermark fix (§5.4) |

### 2.5 Scale, team, timeline, outcomes

| Fact | Value | Provenance |
|---|---|---|
| Events | ~5,400M/month (~2,100/s mean); peak ~60,000/s during the mainframe's nightly renewal cycle | [M] Kafka metrics |
| Peak-to-mean | ~29× (bulk batch updates on the mainframe at night) | [E] derived |
| Workers | ~3,000 events/s per worker thread on the claims parse+dedup path; 48 partitions | [M] |
| Hot key | One broker account = 9% of claims events → salted 8 ways → < 2% per partition; peak lag 14 min → < 30 s | [M] |
| Dedup state | 7 days × ~180M unique events/day ≈ 1.26B keys; at ~40 B/key ≈ **50 GB** of pipeline state | [E] derived (§4.3) |
| Freshness | p95 ≈ 3 min, p99 ≈ 7 min (heartbeat rows, 30 days) | [M] |
| Cost | Infra $57,260/month at launch ($10.60/M events); total cost turns positive ~month 3 (02.2 §6.2) | [M]/[E] |
| Team | Me (tech lead), 5 data engineers, 2 warehouse engineers part-time, 1 SRE | — |
| Timeline | M0–M2 design + PoC; M2–M6 build; M6–M9 dual run with daily reconciliation; M9–M12 cutover of 214 reports; M14 appliance decommission | — |
| Correctness | 0 regulatory submissions with reconciliation mismatches after cutover; 11 mismatches found and repaired during the dual run (incl. INC-T4) | [M] |

---

## 3. The whiteboard blueprint

```text
 ENTERPRISE BAND (thin): mainframe DB2 (o) | Oracle 19c (o) | Kafka platform (o) | GCP org/IAM (o) | 214 reports (o)

 SOURCES               INGEST                    PIPELINE  [[ * ]] (Dataflow, Beam Java)                      SINKS
 DB2 z/OS --+                                 +-> DLQ (GCS + BQ errors)  <-- malformed / schema-incompatible
            |-- CDC <> --> Kafka (o) ---------+                                                     +--> BigQuery (o, <> partitioning)
 Oracle  ---+   LSN, commit ts,  38 topics,    [[ parse ]] -> [[ dedup 7d ]] -> [[ enrich ]] -> [[ salt hot keys ]] -+   Storage Write API, exactly-once
            |   table key        claims: 48p,   (event id)     (state ~50 GB)   (side input,                         +--> GCS raw archive (Avro, 10-min files)
 heartbeat -+                    7d retention                                   10 min refresh)
 rows (1/min)                                                                                      [[ RECONCILIATION * ]]
                                                                                                    source totals vs BQ totals
 BACKFILL [[ * ]]: same pipeline, batch mode, 7y of extracts in GCS; handoff timestamp T_h          per table per partition-day
 numbers: 5.4B ev/mo | peak 60k/s | p95 3 min | dedup 1.26B keys | 214 reports | $10.60/M
```

**How it maps to the 60-minute plan (01.1 §2).**

| Phase | What to draw and say for Archetype A |
|---|---|
| Context | Batch window (5.56 of 6 h, +35%/yr), freshness (29.6 h vs 30 min), 214 reports, 9 regulatory |
| Architecture | Left to right, as drawn; ★ on the pipeline stages, reconciliation and backfill |
| Depth menu | (1) exactly-once effect and dedup, (2) completeness: watermarks, lateness, reconciliation, (3) backfill handoff and report cutover |
| Failure | INC-T4: backfill/stream overlap double-count, caught by reconciliation (§7) |
| Trade-offs | Nightly batch vs 15-min micro-batch vs streaming (02.1 §8.3); Kafka vs Pub/Sub (Q5) |
| Hindsight | The dedup key on CDC offsets (02.3 T1); crypto-shredding (02.3 T2) |

#### How an L5 tells it

> I worked on migrating our data warehouse to GCP. We built a real-time pipeline with Kafka and Dataflow that is exactly-once and highly scalable, and it replaced the old nightly batch jobs. The numbers matched the old system and the business was really happy.

#### How an L7 tells it

> Tidewater replaced an insurer's nightly batch, 180 million records a night through a 6-hour window that would overflow in about 3 months, with CDC into Kafka and a Beam pipeline on Dataflow writing BigQuery and a GCS archive. The forcing requirement was freshness: claims triage needed new claims queryable within 30 minutes at p95, and the batch was up to 29.6 hours stale. I was the tech lead of 6 engineers. I designed the pipeline's dedup, windowing and sink semantics, the reconciliation job that proves counts against the source for every table and partition-day, and the backfill handoff, and I owned the cutover plan for 214 reports. Today p95 freshness is about 3 minutes, and no regulatory submission since cutover has had a reconciliation mismatch; during the dual run, reconciliation found 11, including 1 caused by my own backfill design.

---

## 4. Deep well 1: exactly-once *effect*

### 4.1 Derivation (from 02.1 §6)

| Step | Statement |
|---|---|
| R | Warehouse counts must equal source counts (regulatory reports) |
| I | Each source change has exactly one effect in the warehouse |
| F1 | CDC → Kafka is at-least-once: connector restarts replay from the last checkpoint |
| F2 | Pipeline workers can retry; Dataflow's model is "records are processed at least once, and the results are committed exactly once" ([Dataflow docs](https://cloud.google.com/dataflow/docs/concepts/exactly-once)) |
| F3 | Dataflow's guarantee covers the pipeline's own committed outputs; "side effects are not guaranteed to have exactly-once semantics" (same page) |
| M1 | Source duplicates (F1) must be removed by key: stateful dedup on an event id |
| M2 | Sink writes must be idempotent or transactional: BigQuery's Storage Write API gives exactly-once writes with committed-type streams and client-supplied offsets, while the default stream is at-least-once ([BigQuery docs](https://cloud.google.com/bigquery/docs/write-api)). Beam's BigQueryIO exposes both modes. |
| M3 | No custom side effects in the pipeline, such as calls to other services. Anything that must happen once goes through an idempotent sink. |
| C | Reconciliation measures the invariant independently (§4.4) |

**The sentence that survives the probe.** "Dataflow gives exactly-once *processing* inside the pipeline. The effect in BigQuery is exactly-once only because of two things I added or chose: dedup by event id for the duplicates CDC creates *before* the pipeline, and the Storage Write API in exactly-once mode for the writes it makes. Reconciliation proves the result."

#### How an L5 tells it

> Dataflow is exactly-once, so we basically didn't have to worry about duplicates. BigQuery handles the rest, and the numbers matched the source.

#### How an L7 tells it

> Dataflow gives exactly-once processing of what enters the pipeline, but our duplicates were born before it: when the CDC connector restarts, it replays from its last checkpoint, so the same row change can arrive twice in Kafka with the same log sequence number. I dedup on an event id built from that sequence number plus the table key, keeping state for 7 days, which covers the 7-day Kafka retention, so any replay Kafka can still deliver is inside the horizon. For writes, I used BigQueryIO's exactly-once Storage Write API mode rather than the cheaper at-least-once default stream, because K2 is a regulatory count. Then I distrust all of it: reconciliation compares source and warehouse totals for every table and partition-day, and in the dual run it caught 11 mismatches.

### 4.2 The dedup key: what it must and must not be

| Candidate key | Problem | Verdict |
|---|---|---|
| Kafka offset | Changes on replay into a different partition or a re-produced topic | ✗ |
| Payload hash | Two legitimate identical changes (same value set twice) collapse into one | ✗ |
| Source LSN + table key | Stable across connector replays; **tied to one CDC product's offsets** | ✓ at the time; the 02.3 T1 regret |
| Business event id minted at the source write | Stable across CDC products and backfills | ✓ v2 |

### 4.3 Dedup state size: the number interviewers ask for

- **Keys in state** = unique events per day × horizon days = 180M × 7 ≈ **1.26B keys**.
- **Bytes per key** ≈ 40, for a ~24-byte key plus state overhead (a placeholder; measure yours). That gives **~50 GB** of pipeline state.
- **Levers:**
  1. Shorten the horizon. You can't go below the replay window, or duplicates get through.
  2. Hash the key to 16 bytes, which shrinks state about 35%, with a collision risk you must quantify: for 1.26B keys and a 128-bit hash, the probability is negligible.
  3. Dedup only the tables whose consumers need exact counts. Not all 38 tables feed regulatory reports.

Tidewater chose (2), plus (3) for 21 of the 38 tables. Those 21 carry ~65% of events, so the state became 50 GB × ~0.67 × ~0.65 ≈ **22 GB**.

#### How an L5 tells it

> The dedup state was pretty big, but Dataflow handles state for you, so it scaled fine. We didn't really need to optimize it much.

#### How an L7 tells it

> The state is 7 days of event ids: about 180 million new keys a day, so around 1.26 billion keys, and at about 40 bytes each that's roughly 50 gigabytes held in the pipeline. I made 2 changes to it. I hashed the key to 16 bytes, which shrank the state by about a third with a collision probability I computed as negligible at 1.26 billion keys. And I applied exact dedup only to the 21 tables that feed regulatory or financial reports, about 65% of events, which took the state to about 22 gigabytes. The horizon stayed at 7 days, because shortening it below Kafka's retention would let a legitimate replay through as a duplicate.

### 4.4 Reconciliation: turning the invariant into a measurement

- **Totals per table per partition-day:** row count, sum of the amount column, and an order-independent hash of the keys (for example, the sum of per-key hashes modulo 2⁶⁴, with each key hashed to 64 bits).
- **The source side** is computed by a read-only query on the source replica, or by the CDC tool's own counts.
- **The warehouse side** is computed by a BigQuery query over the partition.
- **Both directions:** warehouse > source means duplicates (INC-T4); warehouse < source means loss, for example a too-late drop (§5) or a DLQ that wasn't replayed.
- **Repair:** re-run the backfill for that partition-day with idempotent partition replacement (§6).
- **The listing shows it working:** the scripted too-late event is dropped by the runner, and only the reconciliation notices (§12).

---

## 5. Deep well 2: completeness, event time and late data

### 5.1 The vocabulary interviewers expect you to use precisely

| Term | Meaning (Beam model) |
|---|---|
| Event time | When the change happened at the source (the CDC commit timestamp) |
| Processing time | When the pipeline sees it |
| Watermark | The runner's estimate that no more data older than T will arrive |
| Window | A grouping by event time (Tidewater's triage dashboard uses 1-min fixed windows) |
| Trigger | When a window emits a result: on the watermark, early (speculative) or late |
| Allowed lateness | How long after the watermark passes a window's end late data is still accepted |
| Accumulation mode | Whether late panes include earlier results (accumulating) or only new data (discarding) |

The Beam programming guide is the reference for these terms ([Beam programming guide](https://beam.apache.org/documentation/programming-guide/)).

### 5.2 Exactly-once is not completeness

Dataflow's documentation says it plainly: exactly-once processing "cannot guarantee that results are complete, because records might arrive late". Data later than the allowed lateness is dropped from windowed computations. That's why Tidewater has two outputs with different completeness semantics:
- **The raw table:** every event, regardless of lateness. It isn't windowed, so nothing is dropped, and the regulatory counts come from it.
- **The windowed aggregates:** the triage dashboard's per-minute counts. Late panes are accepted for 2 h; anything later is dropped and repaired from the raw table nightly.

### 5.3 What the listing demonstrates

The scripted `TestStream` (§12) sends:
- 2 events and a redelivery;
- a malformed row;
- a watermark advance that closes the first window *on time* with 3 events;
- a late event within the allowed lateness, which produces a *late pane* of 1;
- a second redelivery, which is deduplicated;
- a watermark advance past the lateness horizon;
- a too-late event, which the runner drops.

The reconciliation then reports exactly 1 event and 4,000 cents missing for that window. That is the drop, caught.

#### How an L5 tells it

> Late data was basically handled by Dataflow's watermarks. If something came in late it would still get processed, so we didn't lose anything.

#### How an L7 tells it

> Late data has 2 paths, and I designed them separately. The raw claims table isn't windowed, so every event lands regardless of lateness, and the regulatory counts come only from that table. The triage dashboard's per-minute aggregates are windowed by event time with 2 hours of allowed lateness and late firings, so a claim that arrives 40 minutes late updates its minute with a late pane. Anything later than 2 hours is dropped by the runner, by design. A nightly job rebuilds those minutes from the raw table, and the reconciliation flags any window where the 2 differ. In the dual run that happened 3 times, all after mainframe replays following an outage.

### 5.4 The watermark stall (a short failure story)

**INC-T7.** The triage dashboard stopped updating for 47 min. One low-volume source table had no changes overnight, and the timestamp policy didn't advance the watermark for an idle partition. The pipeline's watermark is the minimum across its inputs, so one idle partition held back every downstream window.
- **The fix had two parts.** The heartbeat rows (A8), one per minute per source database, now flow through every source topic, so no partition is ever idle. The timestamp policy also advances idle partitions to wall-clock time minus a bounded delay.
- **The heartbeat was also K1's measurement.** One mechanism serves two purposes, which is worth saying in the interview.

---

## 6. Deep well 3: backfill, the handoff, and the report cutover

### 6.1 One pipeline, two modes (K3)

The 7-year backfill runs the *same* Beam transforms in batch mode over historical extracts in GCS. That's the unified-model argument for Beam, and the reason Option B2 in 02.1 §8.3 scored 4 on "same code for backfill".

**Backfill sizing:**
- **Volume:** 7 years ≈ 7 × 365 × 180M ≈ **460B records**. That's a placeholder; use your real history. At a batch throughput of ~1.2M records/s across the job, that's ~4.4 days of runtime, run partition-by-partition, oldest first.
- **Cost** is dominated by batch worker hours. It's a one-time line item and must appear in the FinOps case as such, not hidden.

### 6.2 The handoff timestamp (the fix that INC-T4 forced)

**Rule:**
- Choose a handoff time T_h.
- The backfill writes only events with a source commit time < T_h.
- The stream writes only events with commit time ≥ T_h.
- Each partition-day has exactly one writer type, recorded in a partition-ownership table.
- A backfill write replaces the whole partition atomically: write to a staging table, then swap. So a re-run is idempotent at the partition level, and needs no row-level dedup at all.

### 6.3 The report cutover

- **Dual run for 3 months.** All 214 reports ran on both warehouses daily. A comparison job diffed their outputs, cell by cell for tabular reports, with a tolerance for floating-point aggregates.
- **Cutover order:**
  1. internal reports;
  2. operational dashboards;
  3. financial reports;
  4. the 9 regulatory reports, last, each after 30 consecutive days of zero unexplained diffs.
- **Rollback:** for 2 weeks after each report's cutover, the old report was kept runnable on the appliance.

#### How an L5 tells it

> We ran both systems in parallel for a while and compared the reports. Once everything looked good, we decided to switch over the reports to BigQuery and turned off the old warehouse.

#### How an L7 tells it

> All 214 reports ran on both warehouses daily for 3 months, and a comparison job diffed their outputs cell by cell, with a tolerance only for floating-point aggregates. I ordered the cutover by risk: internal reports first, then operational dashboards, then financial reports, and the 9 regulatory reports last, each only after 30 consecutive days of 0 unexplained differences. Every explained difference had a ticket: 61 were legacy bugs the new pipeline didn't reproduce, such as a timezone truncation in the old ETL, and those needed sign-off from the report owner, because 'the new number is right' is a business decision when a regulator has seen the old one.

---

## 7. Failure archaeology: INC-T4, the backfill/stream double-count

1. **Detection signal.** The daily reconciliation flagged the claims table for 2026-03-02: warehouse count 0.7% *above* source. It fired at 06:10, 4 hours before that day's regulatory extract was due.
2. **Bounding.** The partition-ownership log showed that only 2026-03-02 had both writer types. No other day was affected.
3. **Mitigation.** The regulatory extract was paused for that day (owner approval), and the partition was rebuilt from the backfill path alone with a partition replace. The extract ran 2 h late, within its deadline.
4. **Root cause, which was mine.** I had re-run the backfill for 2026-03-02 to fix an enrichment bug, while the stream had already written that day's later events. Dedup state lives in the streaming job, so the batch job's writes were invisible to it, and vice versa. My design assumed backfill and stream would never touch the same partition, but nothing enforced it.
5. **Fix.** The handoff timestamp rule, the partition-ownership table, and idempotent partition replacement for every backfill write (§6.2).
6. **Systemic change.** Reconciliation now checks both directions and runs within 1 h of each partition-day closing. The backfill tool refuses to write a partition the ownership table assigns to the stream.

#### How an L5 tells it

> At one point we had some duplicate records in BigQuery because of the backfill, which was kind of a tricky edge case. We cleaned up the data and added some checks so it didn't happen again.

#### How an L7 tells it

> The worst incident in the dual run was INC-T4, and the root cause was my design. I re-ran the backfill for 2 March to fix an enrichment bug, but the stream had already written that day's later events, and dedup state lives only in the streaming job, so neither path could see the other's writes. Reconciliation caught it at 06:10: the warehouse count was 0.7% above the source, 4 hours before that day's regulatory extract. The ownership log bounded it to that 1 partition. We paused the extract, rebuilt the partition from the backfill path alone, and shipped 2 hours late but inside the deadline. The fix prevents overlap by construction instead of making it unlikely: a handoff timestamp splits the 2 writers, a partition-ownership table records which writer owns each day, and every backfill write replaces a whole partition atomically.

---

## 8. Why not simpler? (three options + Option Zero)

The full matrix is in 02.1 §8.3. Summary:

| Option | Fails | Kept from it |
|---|---|---|
| Option Zero: buy appliance capacity (+$38k/month) | K1 freshness (still 29.6 h) | Nothing; it bought time during the build |
| B1 Nightly batch (status quo) | K1, K4 | The historical extract format, as the backfill's input |
| B2 15-min micro-batch (same Beam code, batch mode) | Nothing; it **tied** with streaming | The batch mode itself: it *is* the backfill path |
| B3 Streaming (chosen) | — | Chosen on the fraud team's 5-min tie-breaker |

**Kafka versus Pub/Sub** (a frequent sub-question). Kafka was chosen because:
- the CDC products in use emitted to Kafka natively;
- per-key ordering by partition, and 7-day replay, were needed for the dedup horizon;
- the platform team already ran Kafka.

Pub/Sub supports ordering keys and retention too, so this was a fit-and-ownership decision, not a capability gap, and the answer should say so (Q5).

---

## 9. Constraints and hindsight

<!-- ledger:start name=a-tidewater -->
| ID | Constraint | Category | Source | Hardness | Evidence it was real | Design consequence | Cost paid | Revisit trigger |
|---|---|---|---|---|---|---|---|---|
| TA1 | New claims queryable within 30 min at p95 | Regulatory | Claims director's commitment to the regulator (FNOL acknowledgement) | Hard | Signed requirement; the regulator's letter cited in it | Streaming path; heartbeat freshness measurement | ~2 FTE of pipeline engineering vs 1.5 for the appliance | Regulator changes the acknowledgement window |
| TA2 | Regulatory reports must reconcile to source counts | Regulatory | Reporting team's audit procedure | Hard | Audit procedure document; prior audit finding on count drift | Dedup, the exactly-once sink mode, reconciliation per partition-day | ~22 GB of dedup state; exactly-once write mode cost over at-least-once | Reports move to a source-of-truth system outside the warehouse |
| TA3 | CDC products emit to Kafka; the platform team runs Kafka | Legacy | DBA team's CDC licenses; platform team charter | Soft | License terms; the platform team's service catalog | Kafka, not Pub/Sub, as the transport | ~0.3 FTE of Kafka topic and schema operations on my team | CDC vendor adds a managed-queue target, or the platform retires Kafka |
| TA4 | 214 reports, 9 regulatory, must not show a wrong day | Stakeholder | Report owners; compliance | Hard | Report inventory; compliance sign-off procedure | 3-month dual run; cutover by risk; 30 clean days for regulatory reports | ~3 months of double warehouse cost (~$61k/month on-prem kept running) | — expires at decommission (M14) |
<!-- ledger:end -->

**Hindsight** (validated in 02.3's Tidewater ledger):
- **T1, the dedup key on CDC offsets:** a bad decision with a bad outcome. v2 uses a business event id.
- **T2, the immutable raw archive without crypto-shredding:** a bad decision with a bad outcome.
- **T3, single-region:** a good decision with a good outcome.

---

## 10. Numbers card (Archetype A)

| Number | Value | Re-derive |
|---|---|---|
| Nightly batch | 5.56 h of 6 h | 180M ÷ 9,000/s |
| Window overflow | ~3.1 months | ln(6/5.56) ÷ ln(1.35) × 12 |
| Batch staleness | ~29.6 h worst | 24 h + 5.56 h |
| Mean / peak rate | ~2,100/s / ~60,000/s | 5.4B ÷ 30 days ÷ 86,400 s; Kafka metrics |
| Dedup keys | ~1.26B | 180M/day × 7 days |
| Dedup state | ~50 GB → ~22 GB | 1.26B × 40 B; then 16-byte keys, 21 of 38 tables |
| Hot key | 9% → < 2% per partition | Salt 8 ways |
| Freshness | p95 ~3 min | Heartbeat rows |
| Backfill | ~460B records, ~4.4 days | 7 × 365 × 180M ÷ 1.2M/s |
| Unit cost | $10.60/M at launch | $57,260 ÷ 5,400M |

---

## 11. Hiring-committee scoring rubric: Archetype A

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Exactly-once** | "Dataflow is exactly-once" | Mentions dedup | Pre-pipeline duplicates + an idempotent or transactional sink | Derives it (§4.1); sizes the dedup state; reconciliation as proof |
| **Completeness** | "Watermarks handle it" | Knows allowed lateness | Separates raw (complete) and windowed (bounded-lateness) outputs | Plus the drop path, its detection, and its repair |
| **Backfill** | Not considered | A separate job | Same code, batch mode | Handoff timestamp, partition ownership, idempotent partition replace |
| **Cutover** | "Switched over" | Parallel run | Automated diffs, risk-ordered | Plus explained-difference sign-off and rollback windows |
| **Numbers** | "Big data" | Volumes | Rates, peak-to-mean, freshness percentiles | State size, backfill duration, unit cost, all derived |
| **Ownership** | "We built a pipeline" | Names components | ★ on pipeline stages | ★ with the RFC sections and the INC-T4 root cause owned |

---

## 12. Listing and output

### 12.1 Listing L7: `TidewaterPipeline.java`

<!-- listing:TidewaterPipeline.java -->
```java
// profile: beam
// TidewaterPipeline.java - the four mechanisms an Archetype A deep dive gets
// grilled on, run for real on Beam's DirectRunner with a scripted TestStream:
//   1. parse + dead-letter queue (malformed records never block the stream)
//   2. stateful dedup by event id with a bounded horizon (at-least-once in,
//      exactly-once effect out)
//   3. event-time windows with allowed lateness and late firings
//   4. reconciliation: source control totals vs warehouse totals, which is how
//      a dropped too-late event is caught instead of silently lost
// Records are "eventId|policyId|amountCents|eventTimeSeconds"; times are
// seconds after 2026-01-01T00:00:00Z.
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.coders.BooleanCoder;
import org.apache.beam.sdk.coders.KvCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.coders.VarLongCoder;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.state.StateSpec;
import org.apache.beam.sdk.state.StateSpecs;
import org.apache.beam.sdk.state.TimeDomain;
import org.apache.beam.sdk.state.Timer;
import org.apache.beam.sdk.state.TimerSpec;
import org.apache.beam.sdk.state.TimerSpecs;
import org.apache.beam.sdk.state.ValueState;
import org.apache.beam.sdk.testing.TestStream;
import org.apache.beam.sdk.transforms.Combine;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.Sum;
import org.apache.beam.sdk.transforms.windowing.AfterPane;
import org.apache.beam.sdk.transforms.windowing.AfterWatermark;
import org.apache.beam.sdk.transforms.windowing.BoundedWindow;
import org.apache.beam.sdk.transforms.windowing.FixedWindows;
import org.apache.beam.sdk.transforms.windowing.IntervalWindow;
import org.apache.beam.sdk.transforms.windowing.Window;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.PCollectionTuple;
import org.apache.beam.sdk.values.TimestampedValue;
import org.apache.beam.sdk.values.TupleTag;
import org.apache.beam.sdk.values.TupleTagList;
import org.joda.time.Duration;
import org.joda.time.Instant;

public class TidewaterPipeline {
    static final Instant T0 = Instant.parse("2026-01-01T00:00:00Z");
    static final Duration DEDUP_HORIZON = Duration.standardHours(1);   // production: 7 days
    static final Duration LATENESS = Duration.standardMinutes(5);
    static final ConcurrentLinkedQueue<String> OUT = new ConcurrentLinkedQueue<>();

    static final TupleTag<KV<String, String>> VALID = new TupleTag<KV<String, String>>() {
        private static final long serialVersionUID = 1L;
    };
    static final TupleTag<String> DEAD = new TupleTag<String>() {
        private static final long serialVersionUID = 1L;
    };
    static final TupleTag<KV<String, Long>> UNIQUE = new TupleTag<KV<String, Long>>() {
        private static final long serialVersionUID = 1L;
    };
    static final TupleTag<String> DUPS = new TupleTag<String>() {
        private static final long serialVersionUID = 1L;
    };

    static Instant at(int seconds) {
        return T0.plus(Duration.standardSeconds(seconds));
    }

    /** 1. Parse; anything malformed goes to the dead-letter output with its reason. */
    static class Parse extends DoFn<String, KV<String, String>> {
        private static final long serialVersionUID = 1L;

        @ProcessElement
        public void process(@Element String raw, MultiOutputReceiver out) {
            String[] f = raw.split("\\|");
            if (f.length != 4 || !f[2].matches("-?\\d+") || !f[3].matches("\\d+")) {
                out.get(DEAD).output("DLQ " + raw + " (expected 4 fields: id|policy|cents|time)");
                return;
            }
            out.get(VALID).output(KV.of(f[0], raw));
        }
    }

    /** 2. Keyed by event id: first copy passes, later copies inside the horizon are dropped. */
    static class Dedup extends DoFn<KV<String, String>, KV<String, Long>> {
        private static final long serialVersionUID = 1L;

        @StateId("seen")
        private final StateSpec<ValueState<Boolean>> seenSpec = StateSpecs.value(BooleanCoder.of());

        @TimerId("expiry")
        private final TimerSpec expirySpec = TimerSpecs.timer(TimeDomain.EVENT_TIME);

        @ProcessElement
        public void process(@Element KV<String, String> e, @Timestamp Instant ts,
                            @StateId("seen") ValueState<Boolean> seen,
                            @TimerId("expiry") Timer expiry, MultiOutputReceiver out) {
            if (Boolean.TRUE.equals(seen.read())) {
                out.get(DUPS).output("DUP " + e.getKey());
                return;
            }
            seen.write(true);
            expiry.set(ts.plus(DEDUP_HORIZON));     // state is bounded: it expires with the horizon
            String[] f = e.getValue().split("\\|");
            out.get(UNIQUE).output(KV.of("total", Long.parseLong(f[2])));
        }

        @OnTimer("expiry")
        public void onExpiry(@StateId("seen") ValueState<Boolean> seen) {
            seen.clear();
        }
    }

    /** Collects per-window results with the pane timing (ON_TIME / LATE). */
    static class Collect extends DoFn<KV<String, Long>, Void> {
        private static final long serialVersionUID = 1L;
        private final String label;

        Collect(String label) {
            this.label = label;
        }

        @ProcessElement
        public void process(ProcessContext c, BoundedWindow w) {
            IntervalWindow iw = (IntervalWindow) w;
            long start = (iw.start().getMillis() - T0.getMillis()) / 1000;
            OUT.add(String.format("WIN %02d:%02d %-6s %s=%d", start / 60, start % 60,
                    c.pane().getTiming(), label, c.element().getValue()));
        }
    }

    static class Note extends DoFn<String, Void> {
        private static final long serialVersionUID = 1L;

        @ProcessElement
        public void process(@Element String s) {
            OUT.add(s);
        }
    }

    public static void main(String[] args) {
        String[][] script = {
            {"e1|P-100|12000|10"}, {"e2|P-200|5000|20"}, {"e1|P-100|12000|10"}, {"garbage-row"},
            {"@30"},
            {"e3|P-100|7000|50"}, {"e4|P-300|9000|65"},
            {"@70"},
            {"e5|P-200|3000|40"}, {"e2|P-200|5000|20"},
            {"@420"},
            {"e6|P-300|4000|45"},
        };
        TestStream.Builder<String> b = TestStream.create(StringUtf8Coder.of());
        List<String> sourceRows = new ArrayList<>();
        for (String[] step : script) {
            String s = step[0];
            if (s.startsWith("@")) {
                b = b.advanceWatermarkTo(at(Integer.parseInt(s.substring(1))));
            } else {
                String[] f = s.split("\\|");
                int t = f.length == 4 ? Integer.parseInt(f[3]) : 0;
                b = b.addElements(TimestampedValue.of(s, at(t)));
                sourceRows.add(s);
            }
        }
        TestStream<String> stream = b.advanceWatermarkToInfinity();

        Pipeline p = Pipeline.create(PipelineOptionsFactory.create());
        PCollectionTuple parsed = p.apply("Source", stream)
                .apply("Parse", ParDo.of(new Parse()).withOutputTags(VALID, TupleTagList.of(DEAD)));
        parsed.get(DEAD).apply("NoteDLQ", ParDo.of(new Note()));
        PCollectionTuple deduped = parsed.get(VALID)
                .setCoder(KvCoder.of(StringUtf8Coder.of(), StringUtf8Coder.of()))
                .apply("Dedup", ParDo.of(new Dedup()).withOutputTags(UNIQUE, TupleTagList.of(DUPS)));
        deduped.get(DUPS).apply("NoteDups", ParDo.of(new Note()));
        PCollection<KV<String, Long>> windowed = deduped.get(UNIQUE)
                .setCoder(KvCoder.of(StringUtf8Coder.of(), VarLongCoder.of()))
                .apply("Window", Window.<KV<String, Long>>into(FixedWindows.of(Duration.standardMinutes(1)))
                        .triggering(AfterWatermark.pastEndOfWindow()
                                .withLateFirings(AfterPane.elementCountAtLeast(1)))
                        .withAllowedLateness(LATENESS)
                        .discardingFiredPanes());
        windowed.apply("CountEvents", Combine.perKey(new CountFn()))
                .apply("CollectCount", ParDo.of(new Collect("events")));
        windowed.apply("SumCents", Combine.perKey(Sum.ofLongs()))
                .apply("CollectSum", ParDo.of(new Collect("cents")));
        p.run().waitUntilFinish();

        List<String> lines = new ArrayList<>(OUT);
        lines.sort(null);
        lines.forEach(l -> System.out.println("  " + l));

        // 4. Reconciliation: control totals from the source vs totals that reached the "warehouse".
        Map<String, String> uniqueSource = new TreeMap<>();
        for (String r : sourceRows) {
            String[] f = r.split("\\|");
            if (f.length == 4) {
                uniqueSource.put(f[0], r);
            }
        }
        long srcCount = uniqueSource.size();
        long srcCents = uniqueSource.values().stream().mapToLong(r -> Long.parseLong(r.split("\\|")[2])).sum();
        long whCount = 0;
        long whCents = 0;
        for (String l : lines) {
            if (l.startsWith("WIN")) {
                long v = Long.parseLong(l.substring(l.indexOf('=') + 1));
                if (l.contains("events=")) {
                    whCount += v;
                } else {
                    whCents += v;
                }
            }
        }
        long dlq = lines.stream().filter(l -> l.startsWith("DLQ")).count();
        long dups = lines.stream().filter(l -> l.startsWith("DUP")).count();
        System.out.println();
        System.out.printf("source control totals   : %d unique events, %d cents (+%d malformed rows, %d redeliveries)%n",
                srcCount, srcCents, dlq, sourceRows.size() - dlq - srcCount);
        System.out.printf("warehouse totals        : %d events, %d cents%n", whCount, whCents);
        System.out.printf("dead-lettered / deduped : %d / %d%n", dlq, dups);
        long missing = srcCount - whCount;
        if (missing != 0) {
            System.out.printf("RECONCILIATION MISMATCH : %d event(s), %d cents missing -> open a repair for the affected window%n",
                    missing, srcCents - whCents);
        }
        boolean ok = dlq == 1 && dups == 2 && whCount == 5 && missing == 1 && srcCents - whCents == 4000
                && lines.contains("WIN 00:00 ON_TIME events=3") && lines.contains("WIN 00:00 LATE   events=1")
                && lines.contains("WIN 01:00 ON_TIME events=1");
        System.out.println();
        System.out.println(ok ? "verdict: OK (DLQ 1, dedup 2, on-time + late panes as scripted, too-late e6 caught by reconciliation)"
                : "verdict: CHECK (pipeline behavior differs from the script)");
    }

    /** Counts elements per key; written out so the accumulator coder is explicit. */
    static class CountFn extends Combine.CombineFn<Long, long[], Long> {
        private static final long serialVersionUID = 1L;

        @Override
        public long[] createAccumulator() {
            return new long[1];
        }

        @Override
        public long[] addInput(long[] acc, Long input) {
            acc[0]++;
            return acc;
        }

        @Override
        public long[] mergeAccumulators(Iterable<long[]> accs) {
            long[] m = new long[1];
            for (long[] a : accs) {
                m[0] += a[0];
            }
            return m;
        }

        @Override
        public Long extractOutput(long[] acc) {
            return acc[0];
        }

        @Override
        public org.apache.beam.sdk.coders.Coder<long[]> getAccumulatorCoder(
                org.apache.beam.sdk.coders.CoderRegistry registry,
                org.apache.beam.sdk.coders.Coder<Long> inputCoder) {
            return new LongArrayCoder();
        }
    }

    static class LongArrayCoder extends org.apache.beam.sdk.coders.AtomicCoder<long[]> {
        private static final long serialVersionUID = 1L;

        @Override
        public void encode(long[] value, java.io.OutputStream out) throws java.io.IOException {
            VarLongCoder.of().encode(value[0], out);
        }

        @Override
        public long[] decode(java.io.InputStream in) throws java.io.IOException {
            return new long[] {VarLongCoder.of().decode(in)};
        }
    }
}
```

### 12.2 Output (DirectRunner, Beam 2.77.0, JDK 25)

<!-- output:TidewaterPipeline.java -->
```text
  DLQ garbage-row (expected 4 fields: id|policy|cents|time)
  DUP e1
  DUP e2
  WIN 00:00 LATE   cents=3000
  WIN 00:00 LATE   events=1
  WIN 00:00 ON_TIME cents=24000
  WIN 00:00 ON_TIME events=3
  WIN 01:00 ON_TIME cents=9000
  WIN 01:00 ON_TIME events=1

source control totals   : 6 unique events, 40000 cents (+1 malformed rows, 2 redeliveries)
warehouse totals        : 5 events, 36000 cents
dead-lettered / deduped : 1 / 2
RECONCILIATION MISMATCH : 1 event(s), 4000 cents missing -> open a repair for the affected window

verdict: OK (DLQ 1, dedup 2, on-time + late panes as scripted, too-late e6 caught by reconciliation)
```

**Reading the output.**
- **Window 00:00:** an ON_TIME pane with 3 events (e1, e2, e3), then a LATE pane with 1 (e5), because discarding mode emits only the new data.
- **Window 01:00:** an ON_TIME pane with 1 (e4).
- **Dedup:** both redeliveries (e1, e2) are dropped.
- **Dead-letter queue:** the malformed row goes there with its reason.
- **The dropped event:** e6 arrived after the watermark passed the window's end plus 5 min of allowed lateness, so the runner dropped it. Only the reconciliation shows it: 1 event and 4,000 cents missing.

That is the whole of §4–§5 in one run. Change the `LATENESS` constant to 10 minutes and re-run: e6 becomes a second late pane, and the reconciliation balances.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | "Exactly-once" as a product claim | No account of CDC replays | §4.1 derivation |
| F2 | Dedup key that changes on replay | Duplicates after connector restarts | Source LSN + key, or a business event id (§4.2) |
| F3 | Unsized state | "Dataflow handles it" | 1.26B keys × bytes (§4.3) |
| F4 | Completeness assumed | Windowed numbers used for regulatory counts | Raw table for counts; windows for dashboards (§5.2) |
| F5 | Silent late drops | Missing events nobody notices | Reconciliation both directions (§4.4) |
| F6 | Idle-partition watermark stall | Dashboards freeze | Heartbeats, and an idle-advancing timestamp policy (§5.4) |
| F7 | Backfill/stream overlap | Double counts | Handoff timestamp + partition ownership (§6.2) |
| F8 | Spot-check cutover | A wrong regulatory day | Automated diffs; 30 clean days; sign-off (§6.3) |
| F9 | Hot key ignored | One partition lags | Salting or combiner lifting (02.2 §4.4) |
| F10 | Hidden backfill cost | FinOps case without the one-time line | Size and price the backfill (§6.1) |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "Dataflow is exactly-once. Why do you need dedup at all?"</b></summary>

**Initial Prompt.** "Dataflow advertises exactly-once processing. So your dedup stage is redundant, isn't it?"

**L5 Answer.** "It's for extra safety. Even though Dataflow is exactly-once, we wanted to be sure."

**Why L5 Stalls.** "Extra safety" means the candidate can't say where duplicates come from. If the stage really were redundant, it would cost 22 GB of state for nothing. If it isn't, the candidate doesn't know why.

**L7 Answer.** "It isn't redundant, because the duplicates are created before Dataflow sees them. Dataflow's guarantee is that records it reads are processed at least once and their results committed exactly once. Its docs say it doesn't cover side effects, and it can't know that two Kafka records are the same source change. When our CDC connector restarts, it replays from its last checkpoint, so the same row change arrives twice in Kafka, at different offsets. To Dataflow those are 2 legitimate records. Dedup by source event id is what collapses them. Separately, the BigQuery write uses the exactly-once Storage Write API mode, so the pipeline's own retries don't duplicate rows. The 2 mechanisms cover 2 different duplicate sources."

</details>

<details><summary><b>Q2 · "A claim arrives 3 hours late. Walk me through what happens."</b></summary>

**Initial Prompt.** "A claim's change was committed at 09:00 and reaches the pipeline at 12:00. What happens, exactly?"

**L5 Answer.** "It gets processed when it arrives. Dataflow handles late data with watermarks."

**Why L5 Stalls.** It doesn't say which outputs the claim reaches and which it doesn't, and "handles late data" hides the fact that windowed outputs drop data beyond the allowed lateness.

**L7 Answer.** "It reaches 2 of 3 outputs. The raw claims table isn't windowed, so the row lands with its event time of 09:00 and appears in the 09:00 partition. The regulatory counts come from that table, so they're complete. The GCS archive also gets it, in the 12:00 processing-time file, because the archive is written by arrival. The triage dashboard's per-minute aggregates have 2 hours of allowed lateness, so the 09:00 minute was finalized at about 11:00, and the runner drops this record from that window. The nightly rebuild recomputes the dashboard minutes from the raw table, so the dashboard is right by the next morning, and reconciliation flags the minute in the meantime. If late arrivals like this were common rather than rare, I'd raise the lateness to cover them. The cost is state held longer and more late panes."

</details>

<details><summary><b>Q3 · "How big is your dedup state, and what does it cost you?"</b></summary>

**Initial Prompt.** "Seven days of dedup state at your volume. Size it."

**L5 Answer.** "It's managed by Dataflow's state backend, so we didn't have to think much about the size."

**Why L5 Stalls.** Managed state still costs money and affects performance. A candidate who designed the horizon should know the size it implies.

**L7 Answer.** "About 180 million new event ids a day, times 7 days, is roughly 1.26 billion keys. At about 40 bytes per key with overhead, that's about 50 gigabytes, which costs real money in pipeline state storage and in checkpoint and recovery time. I made 2 reductions: 16-byte hashed keys (about a third smaller; at 1.26 billion keys the collision probability for a 128-bit hash is negligible), and exact dedup only for the 21 tables that feed regulatory or financial reports, which carry about 65% of events. That brought it to about 22 gigabytes. I didn't shorten the horizon, because it's set by the longest replay Kafka can deliver, 7 days of retention, and shortening it would let real replays through."

</details>

<details><summary><b>Q4 · "Your pipeline wrote to BigQuery, then crashed before committing the Kafka offset. Duplicates?"</b></summary>

**Initial Prompt.** "Classic failure: the sink write succeeded, the worker died before the source offset was committed. On restart, it rereads. Do you get duplicates in BigQuery?"

**L5 Answer.** "No, because Dataflow is exactly-once, so it knows the write already happened."

**Why L5 Stalls.** It's the right conclusion with the wrong mechanism. The interviewer is testing whether the candidate knows how the runner, the source and the sink cooperate.

**L7 Answer.** "No, for 2 reasons that I'd want to state separately. First, on Dataflow the Kafka read position is part of the pipeline's checkpointed state, not something my code commits to Kafka, so 'wrote but didn't commit the offset' doesn't arise in that form. Reads are by recorded offset, and the runner replays from its own checkpoint consistently with its committed outputs. Second, the BigQuery write uses exactly-once Storage Write API semantics, where appends carry offsets and a retried append at an already-written offset doesn't add rows. If I'd used the at-least-once default stream to save cost, the answer would be yes, duplicates were possible on retries. That's why I chose the exactly-once mode for the 21 regulatory tables only, and the cheaper mode for the rest."

</details>

<details><summary><b>Q5 · "Why Kafka? You're on GCP. Pub/Sub is right there."</b></summary>

**Initial Prompt.** "Pub/Sub is managed and native to Dataflow. Running Kafka on GCP looks like legacy thinking."

**L5 Answer.** "Kafka is more scalable and gives us better ordering guarantees than Pub/Sub."

**Why L5 Stalls.** Both claims are contestable: Pub/Sub scales, and it supports ordering keys. The answer reads as preference dressed as capability.

**L7 Answer.** "It was a fit-and-ownership decision, not a capability gap, and I'd say Pub/Sub would have worked. Three things tipped it. The CDC products the DBA team already licensed emitted to Kafka natively; for Pub/Sub we'd have needed a bridge, which is another component and another at-least-once hop. Per-partition ordering by table key mattered for applying updates in order, and replay over the 7-day retention set the dedup horizon; Pub/Sub's ordering keys and retention could have met both with some redesign. And the platform team already ran Kafka with an on-call rotation, while Pub/Sub would have been new to the org's tooling. If the CDC vendor added a native Pub/Sub target, I'd re-evaluate. It's in my constraint ledger as Soft, with that trigger."

</details>

<details><summary><b>Q6 · "The source team adds a NOT NULL column. Walk me through the next hour."</b></summary>

**Initial Prompt.** "Oracle DBA adds a NOT NULL column with a default to the claims table at 14:00. What does your pipeline do?"

**L5 Answer.** "The schema registry would handle it, and BigQuery supports schema changes, so it should just work."

**Why L5 Stalls.** "Should just work" isn't a plan. Schema evolution has compatible and incompatible cases, and the answer has to say which this is and what each component does.

**L7 Answer.** "At 14:00 the CDC tool starts emitting records with the new field under a new Avro schema version. Adding a field with a default is backward compatible, so the registry accepts it. My parse stage reads with the reader schema it was deployed with, so the new field is ignored and nothing breaks, but it also isn't captured. The new-schema alert pages my team. We add the column to the BigQuery table as NULLABLE (BigQuery won't add a REQUIRED column to an existing table, and old rows have no value for it anyway), deploy the pipeline with the new reader schema, and backfill the column for rows since 14:00 from the raw Avro archive, which kept the full record. An incompatible change, like a type change, would fail registry compatibility for that subject. Records that still get through with a schema we can't read go to the DLQ, and the DLQ replay tool re-processes them after the fix. The archive is what makes all of this recoverable."

</details>

<details><summary><b>Q7 · "How do you *know* all 214 reports match?"</b></summary>

**Initial Prompt.** "You said the reports match the old warehouse. All of them? Every day? How?"

**L5 Answer.** "We compared them during the parallel run, and the business users checked the important ones."

**Why L5 Stalls.** "The business users checked the important ones" is a spot check, and the interviewer just learned that most reports were never verified.

**L7 Answer.** "A comparison job ran all 214 reports on both warehouses every day for 3 months and diffed them cell by cell, with a tolerance only for floating-point aggregates. Every difference was either a defect we fixed or an explained difference with a ticket. 61 were legacy bugs, for example a timezone truncation in the old ETL that shifted late-evening claims into the next day. Those needed the report owner's sign-off, because changing a number a regulator has seen is a business decision, not an engineering one. A report could cut over only after 30 consecutive clean days, and the 9 regulatory reports went last. So 'they match' means 'every cell, every day, for at least 30 days, or a signed explanation'."

</details>

<details><summary><b>Q8 · "You salted the broker account's key. Doesn't that break ordering?"</b></summary>

**Initial Prompt.** "You split one account's events across 8 sub-keys. Updates to the same claim can now be processed out of order. Problem?"

**L5 Answer.** "It's fine, because we aggregate later, so the order doesn't matter much."

**Why L5 Stalls.** "Doesn't matter much" isn't an argument. It depends on what's keyed and which operations are order-sensitive, and the candidate didn't say.

**L7 Answer.** "It would, if I'd salted the wrong key. I salted on the account for the *aggregation* path only: the per-account rollups for the broker dashboard, which are sums and counts, so commutative and order-insensitive, and merged after the salted partial aggregates. The *apply* path, which writes each claim's current state, stays keyed by claim id, unsalted, because updates to one claim must apply in order. Kafka partitions by table key, so a claim's changes stay in one partition, in order. The hot account's events were spread across many claim ids already, so the apply path never had a hot-key problem; only the per-account aggregation did."

</details>

<details><summary><b>Q9 · "Backfill 7 years. How long, how much, and how do you avoid double counting?"</b></summary>

**Initial Prompt.** "Size the historical backfill and tell me how it coexists with the stream."

**L5 Answer.** "We ran a big batch job over the historical data. It took a few days and then we were caught up."

**Why L5 Stalls.** No size, no cost, no coexistence rule. INC-T4 shows exactly what happens without one.

**L7 Answer.** "About 460 billion records, from 7 years at about 180 million a day, run oldest-first, partition by partition. At about 1.2 million records a second across the batch job, that's around 4.4 days of runtime, priced as a one-time line in the business case. Coexistence is a rule, not a hope. A handoff timestamp: the backfill writes only events committed before it, the stream only after it. A partition-ownership table records which writer owns each day, and the backfill tool refuses to write a stream-owned partition. And every backfill write replaces a whole partition atomically, through a staging table and a swap, so re-running a day is idempotent. I added the last 2 after INC-T4, where my own re-run of 1 day overlapped the stream and produced 0.7% duplicates. Reconciliation caught it before the regulatory extract."

</details>

<details><summary><b>Q10 · "The dashboard froze for 47 minutes. Why, and how would you have known sooner?"</b></summary>

**Initial Prompt.** "Your windowed aggregates stopped emitting. Everything was 'up'. Explain."

**L5 Answer.** "There was an issue with the watermark, so the windows weren't closing. We restarted the job and it recovered."

**Why L5 Stalls.** A restart without a root cause means the next stall is waiting. And "everything was up" points to a monitoring gap the candidate didn't address.

**L7 Answer.** "The pipeline's watermark is the minimum across its inputs. One low-volume source table had no changes overnight, and our timestamp policy didn't advance the watermark for an idle partition, so that one partition held back every downstream window for 47 minutes. Health checks were green because nothing failed; work was just waiting. Two fixes. The heartbeat rows I'd added to measure freshness, 1 per minute per source database, now flow through every topic, so no partition is ever idle. And the timestamp policy now advances idle partitions to wall-clock time minus a bounded delay. For detection, the alert is now on watermark lag (wall clock minus watermark) above 10 minutes, not on job health, because a stalled watermark is invisible to liveness checks."

</details>

---

## 15. Checklist

- [ ] The exactly-once derivation for your pipeline, naming every duplicate source and the mechanism that handles it (§4.1).
- [ ] Your dedup key justified against the alternatives, and its regret if any (§4.2).
- [ ] Dedup state sized: keys × bytes, and the levers you used (§4.3).
- [ ] Reconciliation design: what's totaled, at what grain, both directions, repair path (§4.4).
- [ ] Which outputs are complete and which are bounded-lateness, and why (§5.2).
- [ ] A `TestStream` (or equivalent) run of your own windowing, so you can explain every pane (§12).
- [ ] The backfill size, duration and cost, and the coexistence rule (§6).
- [ ] The cutover plan: dual run, diffs, ordering, sign-off, rollback (§6.3).
- [ ] One failure story in the 7-step structure, with your own root cause if true (§7).
- [ ] Kafka-vs-Pub/Sub (or your transport choice) answered as fit and ownership, not capability (Q5).

---

## 16. References

- Google Cloud, "Exactly-once in Dataflow" (scope of the guarantee, side effects, completeness). <https://cloud.google.com/dataflow/docs/concepts/exactly-once>
- Google Cloud, "BigQuery Storage Write API" (stream types; exactly-once with committed type and offsets; default stream at-least-once). <https://cloud.google.com/bigquery/docs/write-api>
- Apache Beam, Programming Guide (windowing, triggers, allowed lateness, state and timers). <https://beam.apache.org/documentation/programming-guide/>
- Apache Kafka documentation (partitions, retention, consumer offsets). <https://kafka.apache.org/documentation/>
- Martin Fowler, "Strangler Fig Application" (incremental migration). <https://martinfowler.com/bliki/StranglerFigApplication.html>
- Hyrum Wright, Hyrum's Law (legacy report semantics). <https://www.hyrumslaw.com/>
