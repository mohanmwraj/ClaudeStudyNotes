# 02/05 · Data Processing Selection

**Exam guide:** 1.3 ("choosing data processing solutions"), 1.1 ("movement of data"). **Principles:** P4, P5, P8, P10.

Data questions on the PCA aren't as deep as on the data engineer exam, but they expect you to pick the right **ingestion → processing → storage → serving** chain, and to know which product names changed in 2026.

---

## 1. The canonical pipelines

### Streaming

```text
Producers (apps, devices via MQTT broker, logs, CDC)
    │
    ▼
Pub/Sub  ──(or Managed Service for Apache Kafka when Kafka API compatibility is required)
    │
    ▼
Dataflow (Apache Beam: windowing, late data, exactly-once processing, autoscaling)
    │
    ├──▶ BigQuery (analytics; Storage Write API / BigQuery subscriptions for simple loads)
    ├──▶ Bigtable (low-latency serving of time series / features)
    └──▶ Cloud Storage (raw archive, data lake)
```

Shortcuts:

* **Pub/Sub BigQuery subscriptions** write messages straight to BigQuery with no pipeline code, when no transformation is needed.
* **Pub/Sub Cloud Storage subscriptions** write batches of messages to objects.

### Batch

```text
Sources (files in Cloud Storage, databases, SaaS)
    │   ingest: Storage Transfer Service, BigQuery Data Transfer Service, Datastream (CDC)
    ▼
Processing: BigQuery SQL (ELT)  |  Dataflow (Beam batch)  |  Managed Service for Apache Spark
    │       orchestrated by Managed Service for Apache Airflow (formerly Cloud Composer) or Workflows
    ▼
BigQuery (curated) → Looker / Data Studio / BigQuery ML / Agent Platform
```

---

## 2. Product-by-product

| Product (current name) | Formerly | What it is | Pick it when |
|---|---|---|---|
| **Pub/Sub** | — | Global, serverless messaging; at-least-once (exactly-once option for pull in a region), ordering keys, dead-letter topics, replay via seek, filtering | Decoupling, event ingestion, fan-out. Default messaging answer |
| **Managed Service for Apache Kafka** | (replaced Pub/Sub Lite) | Managed Apache Kafka clusters | Existing Kafka clients, Kafka Connect, or Kafka semantics required |
| **Dataflow** | — | Serverless Apache Beam runner, batch and streaming; Dataflow templates; Flex Templates | Transformations in streaming or batch, especially with windowing or late data, and minimal ops |
| **Managed Service for Apache Spark** | Dataproc + Dataproc Serverless / Google Cloud Serverless for Apache Spark (renamed 2026-04-03) | Managed Spark/Hadoop: **clusters** (Spark, Hive, Flink and other components; secondary Spot workers) or **serverless** batches and interactive sessions | Migrating existing Spark/Hadoop jobs with minimal change; Spark ML; teams with Spark skills |
| **BigQuery** | — | Serverless warehouse; SQL ELT, streaming ingestion, BigQuery ML, BI Engine, materialized views, **continuous queries**, Gemini in BigQuery | SQL-centric transformation and analytics; often replaces separate ETL clusters |
| **Google Cloud Lakehouse** | BigLake (renamed 2026-04-20) | Open table format (Apache Iceberg) tables on Cloud Storage with fine-grained security, readable by BigQuery and open-source engines | Open-format lakehouse; multi-engine access (Spark + BigQuery) |
| **Managed Service for Apache Airflow** | Cloud Composer (renamed 2026-04-15) | Managed Apache Airflow (Composer 3; Airflow 3 GA) | Orchestrating multi-step data pipelines across services with dependencies and schedules |
| **Workflows** | — | Serverless orchestration of HTTP/API calls and Google Cloud services | Service orchestration, lightweight pipelines, saga-style flows |
| **Cloud Data Fusion** | — | Visual, code-free ETL (CDAP) with many connectors | Teams that need GUI ETL and pre-built connectors |
| **Datastream** | — | Serverless CDC from MySQL, PostgreSQL, SQL Server, Oracle (and more) to BigQuery / Cloud Storage | Replicating operational databases for analytics in near real time |
| **Dataform** | — | SQL workflow development (SQLX), version control, testing, inside BigQuery | Managing ELT SQL transformations as code |
| **Knowledge Catalog** | Dataplex / Dataplex Universal Catalog (renamed 2026-04-10); legacy Data Catalog deprecated | Discovery, metadata, lineage, data quality, governance across BigQuery, Cloud Storage, etc. | "Discover, govern, track lineage, profile data quality" |
| **BigQuery sharing** | Analytics Hub | Share datasets via exchanges and listings; **data clean rooms** | Sharing or monetizing data without copying |
| **Looker** / **Data Studio** | Data Studio was Looker Studio (renamed back in 2026) | Looker: governed semantic modeling (LookML) and BI; Data Studio: free self-service dashboards | Enterprise governed BI vs quick dashboards |
| **Batch** | — | Managed batch job scheduling on VMs | Containerized or script batch jobs, HPC |

---

## 3. Choosing between Dataflow, Spark and BigQuery

| Situation | Choose | Reason |
|---|---|---|
| New streaming pipeline with event-time windows and late data | **Dataflow** | Beam's model handles these natively; serverless (P5) |
| Existing Spark/Hadoop jobs to migrate quickly | **Managed Service for Apache Spark** | Least change (P15); serverless mode reduces ops |
| Transformations expressible in SQL on data already in BigQuery | **BigQuery** (ELT, scheduled queries, Dataform) | No extra system (P5) |
| Simple message → table load, no transformation | **Pub/Sub BigQuery subscription** | No pipeline at all |
| GUI ETL for analysts, many connectors | **Cloud Data Fusion** | Code-free |
| Real-time SQL over a stream into BigQuery | Dataflow, or BigQuery continuous queries | Depends on complexity |

---

## 4. Orchestration choice

| Need | Choose |
|---|---|
| Data DAGs with dependencies across BigQuery, Spark, Dataflow, external systems; Python operators; backfills | **Managed Service for Apache Airflow** |
| Serverless sequencing of API calls / microservices, with retries and conditions; low cost | **Workflows** |
| Trigger on an event (object created, audit log entry, Pub/Sub message) | **Eventarc** → Cloud Run / Workflows |
| Run something on a schedule (cron) | **Cloud Scheduler** → HTTP target / Pub/Sub / Workflows |
| SQL transformation dependency graphs inside BigQuery | **Dataform** |

---

## 5. Data governance quick map

| Requirement | Control |
|---|---|
| Column-level security on sensitive fields | BigQuery **policy tags** (column-level access) + **dynamic data masking** |
| Row-level restrictions (only EU rows for EU analysts) | BigQuery **row-level security** (row access policies) |
| Discover and classify sensitive data | **Sensitive Data Protection** discovery (profiles BigQuery, Cloud Storage, databases) |
| Lineage and data quality | **Knowledge Catalog** lineage, data profiling and quality scans |
| Prevent exfiltration | VPC Service Controls perimeter around data projects |
| Share data externally without copying | BigQuery sharing / data clean rooms |
| Query data in AWS/Azure without moving it | **BigQuery Omni** (multicloud) / Lakehouse federation |

---

## 6. Requirement → processing choice: fast lookup

| Scenario cue | Choice |
|---|---|
| "Millions of vehicle events per minute, bursty, compute rolling 5-minute aggregates" | Pub/Sub → Dataflow (windowing) → Bigtable/BigQuery |
| "Move 300 existing Spark jobs from on-premises Hadoop with minimal rewrite" | Managed Service for Apache Spark (clusters or serverless); data to Cloud Storage |
| "Replicate MySQL and SQL Server changes to BigQuery continuously for analytics" | Datastream |
| "Daily load of partner CSVs into BigQuery, then a chain of SQL transforms" | Cloud Storage → BigQuery load jobs; Dataform; orchestrated by Managed Airflow or scheduled queries |
| "Analysts need dashboards on BigQuery with a governed metrics layer" | Looker |
| "Catalog all data assets, track lineage, enforce quality rules" | Knowledge Catalog |
| "Share curated datasets with external partners without copying" | BigQuery sharing (listings / clean rooms) |
| "Kafka producers on-premises must keep their client libraries" | Managed Service for Apache Kafka (with hybrid connectivity) |

---

## 7. Traps

* Choosing **Pub/Sub Lite** (turned down) or **Data Catalog** (legacy) for new designs.
* Building Dataflow pipelines for **trivial loads** when a Pub/Sub BigQuery subscription or load job suffices.
* Running **self-managed Spark/Kafka/Airflow on VMs** when managed services exist (P5).
* **Managed Airflow as a streaming engine.** It orchestrates; it doesn't process streams.
* Ignoring **idempotency**: Pub/Sub is at-least-once by default, so design sinks and consumers to deduplicate.

---

## References

* Pub/Sub overview: <https://cloud.google.com/pubsub/docs/overview>
* Dataflow overview: <https://cloud.google.com/dataflow/docs/overview>
* Managed Service for Apache Spark release notes (rename): <https://docs.cloud.google.com/managed-spark/docs/release-notes>
* Datastream overview: <https://cloud.google.com/datastream/docs/overview>
* Knowledge Catalog FAQ: <https://docs.cloud.google.com/knowledge-catalog/docs/faq>
* BigQuery row-level security: <https://cloud.google.com/bigquery/docs/row-level-security-intro>
