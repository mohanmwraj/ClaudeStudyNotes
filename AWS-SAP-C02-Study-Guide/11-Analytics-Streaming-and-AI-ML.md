# Chapter 11 — Analytics, Streaming, Data Lakes & AI/ML Services

> **Exam mapping:** D2 Task 2.4 (reliability), 2.5 (performance), 2.6 (cost) · D3 Task 3.3 (performance), 3.5 (cost) · D4 Task 4.4 (modernization opportunities) | **Weight signal:** Medium–High (analytics shows up inside many scenarios; Kinesis/Athena/Lake Formation/Redshift are frequent) | **Study time:** ~6 h
> [← Previous](10-Application-Integration-and-Event-Driven.md) · [Index](00-README-Start-Here.md) · [Next →](12-Resilience-HA-and-Disaster-Recovery.md)

**Naming you may see on the exam (old ↔ new):** Kinesis Data Firehose ↔ **Amazon Data Firehose** · Kinesis Data Analytics (for Apache Flink / SQL) ↔ **Amazon Managed Service for Apache Flink** (the legacy SQL applications are gone, so build new work on Flink) · Amazon SageMaker ↔ **Amazon SageMaker AI** (the "next generation" Amazon SageMaker brand now covers the unified data + AI platform, **SageMaker Unified Studio**) · Amazon QuickSight ↔ **Amazon Quick Sight**, part of **Amazon Quick** (first launched in Oct 2025 as "Amazon Quick Suite"; the existing QuickSight APIs still work) · Amazon DataZone ↔ now underpins **Amazon SageMaker Catalog** in SageMaker Unified Studio.

---

## 1. What the exam really tests here

SAP-C02 doesn't test analytics like the Data Engineer exam. You won't write Spark code. You will have to **pick the right managed pipeline shape** and **fix a broken or costly one**. Typical scenario stems:

| Scenario shape | The decision you must make |
|---|---|
| "Millions of IoT devices / clickstream events, need near-real-time dashboards and long-term analytics, least operational overhead" | Kinesis Data Streams vs Data Firehose vs MSK. Where to land the data (S3 in Parquet) and how to query it (Athena / Redshift / OpenSearch) |
| "Kinesis stream costs too much / consumers are throttled / multiple consumers lag" | Shard maths, on-demand vs provisioned, **enhanced fan-out**, KPL aggregation, resharding |
| "Athena bill exploded / queries slow" | Columnar formats (Parquet/ORC), compression, partitioning, **partition projection**, CTAS, workgroup data-usage limits |
| "Data lake across many accounts; analysts must only see some columns/rows; central governance" | **Lake Formation**: LF-Tags (TBAC), data filters (row/column/cell), cross-account sharing via AWS RAM, hybrid access mode |
| "Data warehouse: BI spikes at 9 AM / separate business units need the same data without copies / DR in another Region" | Redshift **concurrency scaling**, **data sharing**, RA3/Serverless, cross-Region snapshot copy |
| "Nightly Hadoop/Spark job on-prem; migrate and cut cost" | EMR transient clusters + Spot task nodes / instance fleets, **EMR Serverless**, or Glue for simpler ETL |
| "Existing Kafka estate, migrate with minimal code change" | **Amazon MSK** (Provisioned Standard/Express or Serverless), MSK Connect, MirrorMaker 2 / MSK Replicator |
| "Add ML / AI capability with the least effort" | Use a **managed AI service** (Textract, Transcribe, Comprehend, Rekognition…) before SageMaker AI. Pick the right **SageMaker AI inference** type for cost |
| "Generative AI over company documents" (emerging, not core) | **Amazon Bedrock Knowledge Bases** (RAG) + **Guardrails** |

The pattern that runs through all of these: **serverless/managed beats self-managed** when the stem says "least operational overhead". **Columnar + partitioned + compressed** beats everything when the stem says "reduce Athena/Spectrum cost". **Separate storage from compute**: S3 is the system of record, and engines (Athena, EMR, Redshift Spectrum, Glue) are interchangeable.

---

## 2. Core concepts & services — deep dive

### 2.1 Amazon Kinesis Data Streams (KDS)

**What it is:** A durable, ordered, replayable streaming log. Producers write **records** (partition key + data blob). KDS hashes the partition key (MD5) to a **shard**. Consumers read shards in order and track their own position (sequence numbers). Data is replicated synchronously across three AZs.

**Capacity per shard (provisioned mode):**

| Dimension | Limit per shard |
|---|---|
| Write | **1 MB/s or 1,000 records/s**, whichever you hit first |
| Read (shared-throughput consumers) | **2 MB/s total**, shared by *all* standard consumers. **5 GetRecords calls/s**, up to 10 MB / 10,000 records per call |
| Read (enhanced fan-out) | **2 MB/s per registered consumer per shard**, pushed over HTTP/2 (`SubscribeToShard`) |
| Max record payload | Up to **10 MiB** (raised from 1 MB. Records of 1–10 MiB use burst capacity). Older study material and older exam items assume **1 MB** |
| Registered EFO consumers per stream | **20** (On-demand Standard and Provisioned), **50** with On-demand Advantage |
| Retention | **24 h default**, extendable to **7 days** (extended) or up to **365 days / 8,760 h** (long-term) |

**Capacity modes:**

| | **Provisioned** | **On-demand Standard** | **On-demand Advantage** (account-level setting, launched Nov 2025) |
|---|---|---|---|
| You manage | Shard count (`UpdateShardCount`, split/merge) | Nothing | Nothing. You can set **warm throughput** ahead of known peaks |
| Default / max throughput | Shards × 1 MB/s | New streams start at 4 MB/s write / 8 MB/s read and scale automatically. Up to 10 GB/s write in us-east-1/us-west-2/eu-west-1 (200 MB/s elsewhere by default) | Up to 10 GiB/s |
| Billing (us-east-1 list, examples) | **$0.015 per shard-hour** + **$0.014 per million PUT payload units** (25 KB units) | Per stream-hour + **per GB ingested** (~$0.08/GB) and **per GB retrieved** (~$0.04/GB) | No stream-hour charge, about 60% lower per-GB rates, **EFO at no extra charge**, but a **minimum commitment of 25 MB/s ingest and 25 MB/s retrieval** across the account's on-demand streams |
| Best for | Steady, predictable traffic with high utilization | Unknown or spiky traffic, new workloads | Large estates (>10 MB/s total, many streams, many consumers) |

You can switch a stream between provisioned and on-demand **twice per 24 hours**. The default soft quota is 50 on-demand streams per account. Provisioned shard quotas are 20,000 per account in us-east-1/us-west-2/eu-west-1, lower elsewhere. Both are adjustable.

> **Cost reasoning (exam favourite):** Size provisioned shards on **both** dimensions: `shards = max(ingest MB/s ÷ 1, records/s ÷ 1,000, read MB/s ÷ 2 per standard consumer group)`. Many small records are limited by the **records/s** cap, not by MB/s. The fix is **KPL aggregation**, which packs many user records into one Kinesis record and cuts both the shard count and the PUT payload units. A stream with 20 shards running at 10% utilization is the classic "right-size it" answer. On-demand is *not* automatically cheaper. It costs more for steady, high-utilization traffic and less for spiky or idle traffic.

**Ordering & partition keys:** Ordering is guaranteed **only within a shard** (in practice, per partition key). A low-cardinality partition key, such as `country=US`, creates **hot shards**. Use high-cardinality keys (device ID, user ID). If you need strict global order, you need one shard and you accept the 1 MB/s ceiling, so redesign instead.

**Resharding (provisioned):** `SplitShard` (one hot shard → two) and `MergeShards` (two cold adjacent shards → one). `UpdateShardCount` does uniform scaling for you. A parent shard is closed but readable until its retention expires. The KCL processes **parent before child** to keep ordering.

**Producers:** AWS SDK `PutRecord`/`PutRecords` (≤500 records per call), **Kinesis Producer Library (KPL)** (batching, aggregation, retries, async), **Kinesis Agent** (log files), and direct service integrations: IoT Core rules, CloudWatch Logs subscription filters, DynamoDB Streams → KDS (DynamoDB "Kinesis Data Streams for DynamoDB"), and API Gateway service proxy.

**Consumers:**
- **KCL (Kinesis Client Library):** Uses a **DynamoDB lease table** (named after the application) to assign **one lease per shard** to exactly one worker at a time and to store **checkpoints**. The rule of thumb is **max useful workers = number of shards**. If the lease table is throttled, leases churn, so use on-demand capacity for it. KCL 3.x adds load-aware lease balancing (worker-metrics and coordinator-state tables in DynamoDB). Delivery is **at-least-once**, so consumers must be **idempotent**.
- **AWS Lambda** event source mapping: Polls per shard. **Parallelization factor** (up to 10 concurrent batches per shard), bisect-on-error, maximum retry attempts, maximum record age, and an on-failure destination (SQS/SNS/S3). Can use EFO.
- **Amazon Data Firehose**, **Managed Service for Apache Flink**, **Glue streaming**, **EMR Spark Streaming**, **Redshift streaming ingestion** (materialized view on a stream).
- **NEW (Aug 2026):** KDS **streaming tables** deliver a stream directly into **Apache Iceberg tables on Amazon S3 Tables** with built-in compaction. A companion feature delivers to general-purpose S3 buckets. Both require **on-demand** mode. This is new, so expect Firehose to remain the "answer" on SAP-C02.

**Enhanced fan-out (EFO):** Each registered consumer gets its own **2 MB/s per shard** pipe with push delivery and about **70 ms** propagation, compared with ~200 ms+ for polling. Use it when **more than 2–3 consumers** read the same stream or when consumers need lower latency. Cost: per consumer-shard-hour + per GB (free in On-demand Advantage).

**Security:** IAM (resource policies are supported for cross-account access), **SSE with KMS** (AWS-managed or CMK), interface **VPC endpoint** (PrivateLink), TLS in transit.

**Related:** **Kinesis Video Streams** ingests video/audio from devices for playback, Rekognition Video, and SageMaker AI. If the stem says "camera" or "video fragments", the answer is KVS, not KDS.

### 2.2 Amazon Data Firehose (formerly Kinesis Data Firehose)

**What it is:** A fully managed, auto-scaling **delivery** service with no shards and no consumers to write. It **buffers** records and delivers them to a destination. It is **near-real-time**, not sub-second (unless zero buffering is used for supported destinations).

- **Sources:** Direct PUT (SDK, Kinesis Agent, CloudWatch Logs, EventBridge, IoT, WAF logs, etc.), **Kinesis Data Streams**, **Amazon MSK**.
- **Destinations:** **Amazon S3**, **Amazon Redshift** (staged in S3, then `COPY`), **OpenSearch Service** and **OpenSearch Serverless**, **Splunk**, **Snowflake**, **Apache Iceberg tables** (including S3 Tables), **HTTP endpoint**, and third-party partners (Datadog, Dynatrace, New Relic, MongoDB, Sumo Logic, LogicMonitor, Coralogix, Elastic, Honeycomb…).
- **Buffering hints:** Size **1–128 MiB** (S3/Redshift/Iceberg. 1–100 for OpenSearch. Smaller for some partners) and interval **0–900 s**. The S3 default is **5 MiB / 300 s**. **Whichever is reached first** triggers delivery. **Zero buffering** (interval 0) gives delivery within seconds, but it is **not available with dynamic partitioning** or for the S3 backup. Intervals under 60 s use multipart upload, which means more S3 PUT cost.
- **Transformation:** An optional **AWS Lambda** function (convert, enrich, filter. Return `Ok`/`Dropped`/`ProcessingFailed`). Failed records go to an S3 error prefix.
- **Record format conversion:** **JSON → Apache Parquet or ORC**, using a schema from a **Glue Data Catalog table**. This is the classic "cheap Athena" lever. Convert CSV/logs to JSON first with Lambda.
- **Dynamic partitioning:** Partitions S3 output by keys extracted from the record (inline JQ parsing or Lambda), e.g. `customer_id=/year=/month=/`. This avoids a later Glue job to re-partition. Dynamic partitioning uses larger minimum buffer sizes and is billed per GB processed.
- **Compression** (GZIP, Snappy, Zip, Hadoop-compatible Snappy), **SSE-KMS**, **source record backup** to S3 (all records or failed only).
- **Pricing:** Per GB ingested (Direct PUT/KDS records are rounded up to **5 KB** increments), plus format conversion, dynamic partitioning, and VPC delivery charges. No idle cost.
- **Limits to remember:** Firehose **does not replay** data and **does not support multiple custom consumers**. It is a pipe, not a log. For replay or fan-out, put **KDS in front** of Firehose.

### 2.3 Amazon Managed Service for Apache Flink (formerly Kinesis Data Analytics)

- Fully managed **Apache Flink** for **stateful stream processing**: windowed aggregations, joins of streams, anomaly detection, complex event processing, exactly-once state semantics through **checkpoints** and **snapshots** (savepoints).
- **Sources/sinks:** KDS, MSK/Kafka, Firehose, S3, DynamoDB, OpenSearch, and more (via Flink connectors). Write applications in Java, Scala, Python, or SQL. Use **Studio notebooks** (Zeppelin) for interactive SQL/Python.
- **Billing:** **KPU** (Kinesis Processing Unit = 1 vCPU + 4 GB memory) per hour, plus an orchestration KPU per application and running-storage charges. Supports auto scaling of parallelism.
- **Exam cue:** "Real-time analytics on streaming data with SQL/windows, minimal ops" → Managed Flink. "Just land it in S3/Redshift" → Firehose. The legacy "Kinesis Data Analytics for SQL" is discontinued, so any modern answer is Flink.

### 2.4 Amazon MSK (Managed Streaming for Apache Kafka)

| Option | What you manage | Notes |
|---|---|---|
| **MSK Provisioned – Standard brokers** | Broker count/size, EBS storage (or **tiered storage**), partitions | Full Kafka configuration control, broad version support, ZooKeeper or **KRaft** |
| **MSK Provisioned – Express brokers** | Broker count/size only | Up to **3× throughput per broker**, **up to 20× faster scaling**, 90% faster recovery, **pay-as-you-go storage with no sizing**, no maintenance windows, **3-AZ only**, best-practice config guardrails |
| **MSK Serverless** | Nothing (cluster-level) | Auto-scales capacity, **IAM authentication**. Per-cluster quotas: **200 MBps ingress / 400 MBps egress**, 2,400 partitions (non-compacted), 8 MiB max message, unlimited retention. Best for variable, small-to-medium workloads |

- **MSK Connect:** Managed **Kafka Connect** workers (source/sink connectors, such as Debezium CDC → MSK → S3 sink) with auto scaling.
- **MSK Replicator:** Managed cross-cluster replication, in the same Region or **across Regions** (DR, aggregation). The self-managed alternative is MirrorMaker 2 on MSK Connect.
- **Security:** VPC-only brokers (multi-VPC private connectivity via PrivateLink is supported), **IAM access control**, SASL/SCRAM (Secrets Manager), mTLS (ACM Private CA), KMS at rest, TLS in transit.
- **When MSK instead of Kinesis:** An existing Kafka ecosystem or skills, **migrating on-prem Kafka with no code change**, need for Kafka-specific features (log compaction, Kafka Streams, exactly-once transactions, consumer groups, very long retention via tiered storage, message sizes and configs you control), open-source portability. **When Kinesis instead:** You want the most AWS-native, least-ops option (no partitions/brokers to reason about in on-demand mode), deep AWS integrations, pay-per-use.

### 2.5 AWS Glue

| Component | What it does | Exam cue |
|---|---|---|
| **Glue Data Catalog** | Hive-compatible **central metastore** (databases, tables, partitions, schemas) shared by Athena, EMR, Redshift Spectrum, Glue, Lake Formation, Quick Sight | "Single metadata catalog for the data lake". Cross-account access via catalog resource policy or Lake Formation |
| **Crawlers** | Scan S3/JDBC/DynamoDB, infer schema, create/update tables and partitions, run on a schedule or on S3 events | "Discover schema automatically". For a predictable layout, **partition projection** in Athena avoids crawler cost and latency |
| **ETL jobs – Spark** (PySpark/Scala) | Serverless Spark, billed per **DPU-second** (1 DPU = 4 vCPU, 16 GB), 1-minute minimum on Glue 2.0+, auto scaling, **Flex** execution class for non-urgent jobs (lower price, spare capacity) | Batch ETL without managing clusters |
| **Glue streaming ETL** | Spark Structured Streaming from KDS / MSK / Kafka into S3, Data Catalog, etc. | Micro-batch streaming ETL with schema handling |
| **Python shell jobs** | Single-node Python (0.0625 or 1 DPU) for light tasks | Small scripts and API calls. Not for big data |
| **Glue for Ray** | Ray-based Python scaling | **Closed to new customers from 30 Apr 2026**. AWS recommends Ray on EKS (KubeRay) |
| **Job bookmarks** | Persist state so each run processes **only new data** (incremental loads) | "Avoid reprocessing old files" |
| **Glue Data Quality** | Rules in **DQDL**, recommendations, run in pipelines or on Catalog tables, alert or fail jobs | "Validate data quality before curated zone" |
| **Glue DataBrew** | **Visual, no-code** data preparation (250+ transforms), profiling | "Business analysts clean data without code" |
| **Glue Studio** | Visual job authoring and monitoring | Low-code ETL |
| **Workflows / triggers**, **Schema Registry** | Orchestration of crawlers and jobs. Schema evolution control for KDS/MSK/Lambda producers (Avro/JSON/Protobuf) | Use Step Functions or MWAA for complex multi-service orchestration |
| **Zero-ETL / connectors** | Managed ingestion from SaaS apps (Salesforce, SAP, ServiceNow, Zendesk…) into Redshift / Lakehouse | "Ingest SaaS data with no pipeline code" |

**Gotchas:** Glue is not a long-running interactive cluster. Choose EMR for fine-grained Spark/Hadoop tuning, custom frameworks (Presto/Trino, HBase, Flink, Hudi tuning) or persistent clusters. Small files kill Spark and Athena performance: compact them (Glue job, Iceberg `OPTIMIZE`, Firehose buffering).

### 2.6 Amazon Athena

**What it is:** **Serverless, interactive SQL** (Trino/Presto-based engine v3) on data in S3, using the Glue Data Catalog for schemas. Also **Athena for Apache Spark** (notebooks). Pay **per TB scanned** (~$5/TB list price in us-east-1, 10 MB minimum per query. DDL and failed queries are not charged, cancelled queries are charged for data scanned), or buy **Provisioned Capacity** (DPU-hours) for predictable and isolated workloads.

**Cost & performance levers (memorize the order):**
1. **Columnar formats:** **Parquet / ORC**. Athena reads only the columns referenced. This often gives 30–90% less scanned data.
2. **Compression:** Snappy/ZSTD/GZIP. Use splittable formats for parallelism (Parquet/ORC are splittable internally).
3. **Partitioning:** `dt=2026-10-17/region=eu/` with `WHERE` filters on partition columns.
4. **Partition projection:** Athena **computes** partitions from table properties (integer, date, enum, injected types) instead of calling Glue `GetPartitions`. It is faster for highly partitioned tables and needs **no crawler or `MSCK REPAIR TABLE`** when new partitions arrive. Caveats: it only works in Athena (Spectrum/EMR use regular partition metadata), and it is slow if more than half the projected partitions are empty.
5. **File sizing:** Aim for ~128 MB–1 GB objects. Compact small files.
6. **CTAS / INSERT INTO / UNLOAD:** Transform raw → partitioned Parquet in one SQL statement. CTAS is the "no-ETL-infrastructure" way to build the curated zone.
7. **Query result reuse**, `LIMIT`, approximate functions, bucketing.

**Workgroups:** Separate users, teams, and applications. Each workgroup has its own **query result location and encryption**, engine version, and **data usage controls**: a **per-query limit** (cancels any query scanning more than X) and **per-workgroup limits** over hourly/daily windows (alarm through CloudWatch/SNS, optionally a Lambda action). Use IAM policies that restrict users to their workgroup, and enforce workgroup settings. Tags give cost allocation.

**Federated query:** Lambda-based **data source connectors** (DynamoDB, RDS/Aurora, Redshift, CloudWatch Logs, DocumentDB, HBase, on-prem JDBC, SaaS) let one SQL statement join S3 with operational stores. Cross-account Glue catalogs can be registered as data sources.

**Apache Iceberg tables:** ACID `INSERT/UPDATE/DELETE/MERGE`, **time travel**, schema/partition evolution, hidden partitioning, `OPTIMIZE` (compaction) and `VACUUM`. Iceberg is AWS's strategic open table format (Lake Formation, Glue, EMR, Redshift, Firehose, and S3 Tables all support it).

**Security:** IAM + **Lake Formation** fine-grained permissions, SSE-S3/SSE-KMS/CSE-KMS for results, interface VPC endpoint.

### 2.7 Amazon EMR

**What it is:** Managed big-data frameworks: Spark, Hive, Presto/Trino, HBase, Flink, Hudi, Iceberg, Delta, and more. It comes in **three deployment models**:

| Model | Use when | Key points |
|---|---|---|
| **EMR on EC2** | Need full control, custom AMIs/bootstrap, HBase/HDFS, long-running clusters, specific instance types | **Primary** (master), **core** (runs HDFS DataNode + tasks), **task** (compute only, **no HDFS**, so **ideal for Spot**) |
| **EMR on EKS** | Org standardizes on Kubernetes. Want to consolidate Spark with other containerized apps on shared EKS clusters | "Virtual clusters" map to namespaces. Pay EC2/Fargate + EMR uplift. Fast job start on existing capacity |
| **EMR Serverless** | Want Spark/Hive **without sizing or managing clusters**. Intermittent jobs | Applications with **pre-initialized capacity** (warm pool) and **maximum capacity** limits. Per vCPU/GB-second billing. Auto-stop when idle |

**EMR on EC2 capacity choices:**
- **Instance groups:** One instance type per group (up to 48 task groups). Use **EMR managed scaling** or custom auto scaling policies.
- **Instance fleets:** **Up to 5 instance types per fleet** (or **30** with the CLI/API and an allocation strategy), separate **On-Demand and Spot target capacities**, **price-capacity-optimized** Spot allocation (default from EMR 6.10), a **Spot provisioning timeout** with *switch to On-Demand* or *terminate*, **multiple subnets/AZs** (EMR picks the best AZ at launch. The cluster still lives in **one AZ**), On-Demand Capacity Reservations. This is the most resilient way to get Spot capacity.
- **Spot guidance:** Primary and core On-Demand (core holds HDFS data, and losing core nodes risks job failure), **task nodes on Spot**. With **EMRFS (S3)** as storage you can even run core on Spot for fault-tolerant transient jobs.

**Storage:** **EMRFS** reads and writes S3 directly. S3 has been strongly consistent since 2020, so the old "EMRFS consistent view" (DynamoDB-backed) is unnecessary and deprecated. **HDFS** is ephemeral on core node instance store/EBS and is lost when the cluster terminates. **Decouple storage (S3) from compute** so clusters can be transient.

**Transient vs long-running:**
- **Transient:** Launch → run steps → **auto-terminate**. The cheapest for scheduled batch. Orchestrate with Step Functions/MWAA. Use an **auto-termination idle timeout** as a safety net.
- **Long-running:** Interactive/ad-hoc (EMR Studio notebooks), HBase, Presto serving. Use managed scaling plus Spot task fleets, and Reserved Instances/Savings Plans for the always-on base.

**Security:** Security configurations (at-rest encryption for EMRFS/local disks, in-transit TLS), **Kerberos**, **runtime roles** for steps, **Lake Formation integration** for fine-grained access, Block Public Access for EMR, private subnets with S3 gateway endpoints.

### 2.8 AWS Lake Formation

**What it is:** A governance layer on top of S3 + the Glue Data Catalog. You **register S3 locations** with Lake Formation. It then **vends temporary, scoped credentials** to integrated engines (Athena, Redshift Spectrum, EMR, Glue, Quick Sight, SageMaker), so permissions are enforced centrally rather than in a sprawl of bucket policies and IAM policies.

**Permission model:**
- **Data lake administrators** grant **database/table/column** permissions (`SELECT`, `INSERT`, `DELETE`, `DESCRIBE`, `ALTER`, `DROP`, `CREATE_TABLE`, `DATA_LOCATION_ACCESS`, grantable options) to IAM principals, IAM Identity Center users/groups, SAML groups, external accounts, organizations, or OUs.
- **LF-Tags / tag-based access control (LF-TBAC):** Attach key-value LF-Tags (e.g. `domain=sales`, `classification=pii`) to databases, tables, and columns, then grant on **tag expressions**. This **scales to thousands of tables**, because new tables that inherit tags are automatically covered. On the exam, "hundreds of tables, permissions keep growing, many consumer accounts" → **LF-TBAC**.
- **Data filters** give **row-level**, **column-level**, and **cell-level** security (a row filter expression combined with column include/exclude). Example: "EU analysts see only `region='EU'` rows and never the `ssn` column."
- **Cross-account sharing:** Lake Formation uses **AWS RAM** under the hood (named-resource grants or LF-Tag grants to accounts, OUs, or the whole organization). The consumer account's data lake admin accepts the share, creates **resource links** to the shared database/table, and re-grants to local principals. No data is copied. Typical layout: **central governance account** (catalog + permissions) with **producer accounts** (S3 data) and **consumer accounts**, the "data mesh" pattern.
- **IAMAllowedPrincipals / hybrid access mode:** By default, new catalog objects grant `Super` to `IAMAllowedPrincipals`, so plain IAM still works. **Hybrid access mode** lets you register a location so **opted-in principals use Lake Formation permissions** while **everyone else keeps IAM-only access**. Use it for **incremental, non-disruptive adoption** of Lake Formation on an existing lake.
- **Table formats:** **Governed tables are discontinued** (support ended 31 Dec 2024). For ACID and transactions use **Apache Iceberg** (also Hudi and Delta Lake), which Lake Formation governs like any other catalog table, including **Amazon S3 Tables** integrated through the Glue Data Catalog.
- **Other features:** Blueprints/workflows (ingest from JDBC/logs, now largely superseded by Glue/zero-ETL), audit through CloudTrail, data sharing to Redshift (Redshift datashares managed by Lake Formation).

**Gotchas:** S3 bucket policies and KMS key policies still apply. Lake Formation's registered role needs access to the bucket and key. Lake Formation permissions **don't** stop direct S3 `GetObject` by a principal that has IAM S3 permissions on the bucket. Remove broad S3 IAM access so that **all reads go through the governed path**.

### 2.9 Amazon Redshift

**Architecture:** An MPP, columnar data warehouse. A leader node plans queries and compute nodes execute slices. **RA3 nodes** (ra3.large/xlplus/4xlarge/16xlarge) separate compute from **Redshift Managed Storage (RMS)**, which is S3-backed with local SSD caching. You scale compute and storage independently, and RA3 unlocks **data sharing**, **Multi-AZ**, **cluster relocation**, and **concurrency scaling for writes**. Current docs also list a newer **RG** node family. DC2 is legacy local-SSD compute.

**Redshift Serverless:** No clusters. Capacity is measured in **RPUs** (1 RPU = 16 GB memory). **Base capacity defaults to 128 RPUs** and is adjustable **from 4 up to 512 RPUs** (1,024 in some Regions). You pay per RPU-second (60-second minimum) only while queries run. Set **max capacity** and **RPU-hour usage limits** for cost control. **AI-driven scaling** uses a price-performance slider. Namespaces (data) are separate from workgroups (compute). Best for **unpredictable, intermittent, or dev/test** workloads. For a steady 24×7 heavy warehouse, provisioned RA3 with **Reserved Nodes** is usually cheaper.

**Key features:**

| Feature | What it gives you | Exam cue |
|---|---|---|
| **Redshift Spectrum** | Query S3 data (Glue Catalog / Lake Formation tables) from Redshift using a separate Spectrum fleet. Billed per TB scanned | "Join warehouse tables with years of cold data in S3 without loading it" |
| **Data sharing** | **Live, transactionally consistent** sharing of databases/schemas/tables/views/UDFs across clusters, Serverless workgroups, **accounts, and Regions**. Supports **reads and writes**. No copy. Requires RA3 or Serverless. Can be listed on **AWS Data Exchange** | "Central ETL cluster feeds several BI clusters owned by different business units. Isolate compute, no copies" |
| **Concurrency scaling** | Transient extra clusters absorb **bursts of concurrent queries** (reads and common writes: COPY, INSERT, UPDATE, DELETE, CTAS, VACUUM). Enabled per **WLM queue**. Clusters accrue **one hour of free credit per day**. Beyond that you pay per second | "Dashboards slow at 9 AM Monday when 500 users log in" |
| **Elastic resize / classic resize** | Change node count/type. Elastic is quick for compatible changes | Sustained growth, not bursts |
| **Materialized views** | Precomputed results, **auto refresh**, automatic query rewrite, **auto-MV**. Also the target for **streaming ingestion** from KDS/MSK | "Speed up repeated dashboard aggregations", "ingest stream into Redshift with low latency" |
| **Zero-ETL integrations** | Managed replication into Redshift from **Aurora MySQL/PostgreSQL, RDS for MySQL/PostgreSQL/Oracle, DynamoDB**, Oracle Database@AWS, self-managed DBs, and SaaS apps (Salesforce, SAP, ServiceNow, Zendesk…) | "Near-real-time analytics on OLTP data **without building pipelines**" |
| **WLM** | **Automatic WLM** (recommended) with queue priorities, or manual WLM. **Query monitoring rules** (abort/log/hop long queries), **short query acceleration** | "Prevent ad-hoc queries from starving ETL" |
| **Federated query** | Query live data in RDS/Aurora PostgreSQL and MySQL from Redshift | Join operational and warehouse data |
| **Redshift ML** | `CREATE MODEL` in SQL uses SageMaker AI Autopilot | ML for SQL users |
| **Snapshots & DR** | Automated snapshots (incremental, configurable retention up to 35 days), manual snapshots (kept until deleted), **cross-Region snapshot copy** (a KMS-encrypted provisioned cluster needs a **snapshot copy grant** in the destination Region), restore single table. **Multi-AZ** (RA3) for in-Region HA. **Relocation** moves a cluster to another AZ | "DR in another Region with RPO of hours" → automated cross-Region snapshot copy |

**Security:** VPC (**enhanced VPC routing** forces COPY/UNLOAD traffic through the VPC so endpoints/flow logs apply), KMS encryption, IAM/Identity Center federation, row-level security, column-level grants, dynamic data masking, audit logging to S3/CloudWatch.

Note: Redshift is ending support for **Python UDFs after 30 June 2026**. Migrate them to Lambda UDFs or SQL UDFs.

### 2.10 Amazon OpenSearch Service

- **Managed domains** (OpenSearch / legacy Elasticsearch ≤7.10): data nodes, **dedicated master (cluster manager) nodes** (use 3), zone awareness / **Multi-AZ with Standby**, EBS or instance storage. OR1/OR2-type instances use S3-backed durable storage for indexing-heavy workloads.
- **Storage tiers:** **Hot** (EBS/instance store) → **UltraWarm** (S3-backed with caching, **read-only**, **requires dedicated master nodes**, pay for data stored, no replica overhead) → **Cold** (detached, cheapest. **Requires UltraWarm**. Reattach to warm to query). Automate the transitions with **Index State Management (ISM)**, e.g. hot 7 days → warm 30 days → cold 1 year → delete.
- **OpenSearch Serverless:** **Collections** of type **search**, **time series**, or **vector search**. Capacity in **OCUs** with auto scaling, separate indexing and search compute, encryption/network/data-access policies. Choose it for spiky or unknown workloads and as a vector store for Bedrock Knowledge Bases.
- **OpenSearch Ingestion:** Managed Data Prepper pipelines (from S3, Kafka/MSK, HTTP, OTel) for log/trace ingestion. **Direct query / zero-ETL** analyzes S3 data (and CloudWatch Logs, Security Lake) without full ingestion.
- **Security:** VPC access or public endpoint with resource policy, **fine-grained access control** (index/document/field-level), SAML / Cognito / IAM Identity Center for Dashboards, KMS, node-to-node TLS.
- **Use cases:** **Log analytics** (CloudWatch Logs subscription → Firehose → OpenSearch), full-text search, observability (traces), security analytics, vector search. Not a system of record: keep raw data in S3.

### 2.11 Amazon Quick Sight (formerly Amazon QuickSight)

- Serverless BI, now the BI component of **Amazon Quick** (QuickSight became "Quick Suite" in Oct 2025, now "Amazon Quick". APIs unchanged).
- **SPICE:** In-memory columnar engine. Import datasets for fast, consistent dashboards and to avoid hammering the source (Athena per-scan cost, RDS load). Scheduled or incremental refresh. **Direct query** is for always-fresh data.
- **Embedding:** Embed dashboards/visuals/Q&A in apps for **registered users** (IAM/Identity Center/SAML) or **anonymous users** (session-capacity pricing). Namespaces give multi-tenant isolation.
- **Security:** **Row-level security** (user/group-based dataset rules, or **tag-based RLS** for anonymous embedding), **column-level security**, VPC connections to private data sources, Lake Formation-governed data via Athena.
- **Generative BI:** Natural-language Q&A and authoring (formerly "Amazon Q in QuickSight").

### 2.12 AWS Clean Rooms, Amazon DataZone & SageMaker Unified Studio (brief)

- **AWS Clean Rooms:** Multiple parties (e.g. advertiser + publisher) analyze **combined datasets without sharing or copying raw data**. Members configure tables with **analysis rules** (aggregation, list, custom SQL with approved queries), **cryptographic computing (C3R)**, **differential privacy**, and **Clean Rooms ML** (lookalike modeling). Exam cue: "collaborate with a partner on overlapping customers without exposing PII." *Emerging / SAP-C03 preview.*
- **Amazon DataZone → SageMaker Catalog:** A business data catalog with **projects**, **publish/subscribe** access workflows, glossaries, and lineage. It now underpins **Amazon SageMaker Catalog** inside **SageMaker Unified Studio**, a single environment for SQL analytics (Athena/Redshift), data processing (Glue/EMR), ML (SageMaker AI), and generative AI (Bedrock) over a **lakehouse** (Iceberg on S3 + Redshift managed storage, unified in the Glue Data Catalog). Existing DataZone domains can be upgraded into it. Exam cue: "business users discover and request access to governed data products across accounts."

### 2.13 Modern data architecture on AWS (lake house)

S3 is the system of record, organized into zones (medallion-style layers):

| Zone (AWS term) | Medallion term | Contents | Format / controls |
|---|---|---|---|
| **Raw / landing** | Bronze | Immutable copies as ingested (JSON, CSV, logs, CDC) | Original format, compressed. Restricted access. Lifecycle to Glacier. Object Lock if regulated |
| **Curated / stage / cleansed** | Silver | Validated, deduplicated, typed, conformed, PII tokenized | **Parquet/Iceberg**, partitioned. Glue Data Quality gates |
| **Consumption / analytics / refined** | Gold | Business aggregates, data products, ML features | Iceberg/Parquet, Redshift tables/MVs, SPICE. Lake Formation grants per consumer |

- **Separate accounts** for producers, a central governance (catalog) account, and consumers. **Lake Formation + RAM** for sharing. **Glue Data Catalog** as the single metastore. **Engines are interchangeable:** Athena (ad hoc), Redshift (warehouse/BI), EMR/Glue (ETL), SageMaker AI (ML), OpenSearch (search/logs).
- **Iceberg everywhere** is AWS's current direction (S3 Tables, Firehose Iceberg destination, KDS streaming tables, Redshift/Athena/EMR/Glue read-write).

### 2.14 AI/ML services

#### Amazon SageMaker AI (ML platform)

- **Build:** Studio / Unified Studio notebooks, **Canvas** (no-code ML. This is also the AWS-recommended migration path from Amazon Forecast), **JumpStart** (pre-trained and foundation models), Data Wrangler, **Ground Truth** (labelling), **Feature Store** (online/offline).
- **Train:** Managed training jobs (GPU, **Trainium**). **Managed Spot Training** (up to ~90% savings. **Checkpoint to S3** so interrupted jobs resume), distributed training, HyperPod (resilient large-scale clusters), automatic model tuning, Autopilot.
- **Deploy (inference options)** is the exam-relevant decision:

| Option | Traffic / payload | Cost behaviour | Pick when |
|---|---|---|---|
| **Real-time endpoint** | Persistent, low-latency, synchronous | Pay per instance-hour, 24×7. Auto scaling. **Multi-model endpoints** / inference components pack many models onto shared instances | Steady traffic, millisecond latency, GPU needed |
| **Serverless inference** | Intermittent, spiky. Tolerates **cold starts**. Memory 1–6 GB, max 200 concurrency per endpoint. **No GPUs, no VPC configuration**, no multi-model | Pay per ms of compute + data. **Scales to zero**. Optional provisioned concurrency | Unpredictable or low traffic, small CPU models |
| **Asynchronous inference** | **Large payloads (up to 1 GB)**, **long processing (up to 1 hour)**. Requests queued, input/output in S3, SNS notification | Instances, but can **scale to zero** when the queue is empty | Large documents/images/video. Near-real-time with tolerance for delay |
| **Batch transform** | Offline scoring of a whole dataset in S3. No endpoint | Pay only for job duration | Nightly/periodic bulk predictions |

- **Operate:** Pipelines (MLOps CI/CD), Model Registry, **Model Monitor** (data/model drift), **Clarify** (bias/explainability), shadow tests, Inferentia instances (Neo compilation) for cheaper inference, **SageMaker Savings Plans**.
- **Security:** VPC-only domains/jobs, network isolation, KMS, IAM execution roles, PrivateLink endpoints.

#### Amazon Bedrock (generative AI) — *Emerging / SAP-C03 preview, not core SAP-C02*

- Serverless API access to **foundation models** from Amazon (Nova, Titan embeddings) and third parties (Anthropic, Meta, Mistral, Cohere, etc.). Your prompts and data are **not used to train base models**. PrivateLink and CloudTrail support.
- **Pricing modes:** On-demand (per token), **batch inference** (discounted, asynchronous), **Provisioned Throughput** (purchased model units for consistent high volume. Required for some customized models), cross-Region inference profiles for burst capacity.
- **Knowledge Bases:** Managed **RAG**. Ingest from S3/Confluence/SharePoint/web, chunk + embed, store in a vector store (OpenSearch Serverless, Aurora PostgreSQL pgvector, S3 Vectors, Neptune Analytics, partners), retrieve-and-generate with citations.
- **Agents:** Orchestrate multi-step tasks, calling **action groups** (Lambda/OpenAPI) and knowledge bases. **Bedrock AgentCore** provides runtime, memory, identity, gateway, and observability for production agents.
- **Guardrails:** Content filters, denied topics, word filters, **PII detection/redaction**, contextual grounding checks (hallucination), automated reasoning checks. Apply to any model, or standalone via `ApplyGuardrail`.
- **Customization:** Fine-tuning, continued pre-training, distillation. Model evaluation.

#### "Pick the managed AI service" table

| Requirement in the stem | Service | Notes / status |
|---|---|---|
| Detect objects, faces, unsafe content, text in images/video. Face comparison / liveness | **Amazon Rekognition** | Image + stored/streaming video (via Kinesis Video Streams). Custom Labels for domain-specific objects |
| Extract text, **forms (key-value pairs)**, **tables**, signatures, invoices, IDs from scanned docs/PDFs | **Amazon Textract** | More than OCR: it understands document structure. Queries feature. Async API for multi-page PDFs. Pair with Amazon A2I for human review |
| Sentiment, entities, key phrases, language, **PII detection/redaction**, custom classification/entities on text | **Amazon Comprehend** | Topic modeling, event detection, and prompt-safety classification are **closed to new customers from 30 Apr 2026** (AWS points to Bedrock) |
| Extract medical conditions, medications, dosages, PHI, ICD-10-CM/RxNorm/SNOMED CT codes from clinical text | **Amazon Comprehend Medical** | HIPAA-eligible |
| Speech → text, call recordings, subtitles, **PII redaction in transcripts**, custom vocabulary | **Amazon Transcribe** | **Call Analytics** (sentiment, issues, talk time). **Transcribe Medical** |
| Translate text between languages, real-time or batch, custom terminology | **Amazon Translate** | |
| Text → lifelike speech, SSML, neural voices | **Amazon Polly** | |
| Chatbot / voice bot with intents & slots (IVR in Amazon Connect) | **Amazon Lex** | Same tech as Alexa |
| Intelligent **enterprise search** over document repositories with natural-language questions | **Amazon Kendra** | Connectors (SharePoint, S3, Confluence…). GenAI Index usable as a retriever |
| Real-time **personalized recommendations** | **Amazon Personalize** | Ingests interactions. Real-time and batch |
| Time-series demand forecasting | **Amazon Forecast** | **Closed to new customers since Jul 2024**. AWS recommends **SageMaker Canvas**. Older exam items may still name Forecast |
| Online fraud detection (fake accounts, payment fraud) | **Amazon Fraud Detector** | **Closed to new customers since 7 Nov 2025**. AWS suggests AutoGluon / SageMaker AI, or **AWS WAF Fraud Control** for account creation/takeover |
| Generative-AI assistant for employees over enterprise data | **Amazon Q Business** (and **Amazon Quick** agents/index) | Respects source ACLs. Connectors |
| Generative-AI coding assistant | **Amazon Q Developer** | AWS is moving IDE users to **Kiro** (2026). Q in the AWS console continues. Treat details cautiously |
| Custom ML model, bespoke algorithm, full control | **SageMaker AI** | Only when no managed AI service fits |
| Generative AI / LLM apps, RAG, agents | **Amazon Bedrock** | Emerging for SAP-C03 |

> **Rule:** If a purpose-built AI service fits, it is the **least-operational-overhead** answer. SageMaker AI is right when the stem says "custom model", "data scientists", "bring your own algorithm/container", or "the team has already trained a model".

---

## 3. Architecture patterns

### Pattern A — Serverless streaming ingestion to a queryable data lake (IoT / telemetry)

```text
 Devices --MQTT--> AWS IoT Core --rule--> Kinesis Data Streams (on-demand)
                                              |        |                 |
                                              |        |                 +--> Lambda (alerts, idempotent) --> SNS / DynamoDB
                                              |        +--> Managed Service for Apache Flink (1-min windows, anomalies)
                                              |                      '--> OpenSearch real-time dashboard
                                              v
                                 Amazon Data Firehose
                       (Lambda transform -> JSON->Parquet via Glue table schema,
                        dynamic partitioning device_type=/dt=/, buffer 128 MiB / 300 s)
                                              v
                    S3 raw/curated zone (Parquet, partitioned, SSE-KMS)
                                              v
     Glue Data Catalog (partition projection) --> Athena (workgroups + limits) --> Quick Sight (SPICE)
```

- **Why:** KDS gives **replay + multiple consumers**. Firehose handles **delivery, batching, conversion** with zero code. Parquet + partitions keep Athena cheap.
- **Trade-offs:** Firehose adds buffer latency (seconds to minutes). If only S3 landing is needed (no replay, one consumer), drop KDS and use **IoT Core → Firehose directly**, which is cheaper and simpler.

### Pattern B — Clickstream analytics

```text
 Web/mobile SDK --> API Gateway --> Kinesis Data Streams --+--> Firehose --> S3 raw (Parquet) --> Glue ETL (sessionize) --> S3 curated (Iceberg)
                                                           |                                                                   |
                                                           +--> Flink (real-time top-N pages) --> DynamoDB --> app widgets     |
                                                           +--> Lambda --> Personalize event tracker --> recommendations       v
                                                                                       Redshift Serverless (Spectrum / COPY) --> Quick Sight
```

### Pattern C — Centralized log analytics

```text
 Member accounts: CloudWatch Logs --subscription filter--> cross-account destination --> Firehose (central log account)
                  VPC Flow Logs / ALB / CloudTrail -----------------------------------------> S3 central (Object Lock) --> Athena (partition projection)
                                                                                    |
                                                                                    v
                                         OpenSearch (hot 7 d -> UltraWarm 30 d -> cold, via ISM) --> Dashboards / alerting
```

- **Why:** Search and alert on recent logs in OpenSearch, and keep everything cheaply in S3 for Athena and compliance. **Amazon Security Lake** (OCSF format) is the managed alternative for security logs.

### Pattern D — Governed multi-account lake house (data mesh)

```text
  Producer acct A (S3 + Glue tables)        Producer acct B
             \                                 /
              \  register / share catalog     /
               v                             v
        Central governance acct: Glue Data Catalog + Lake Formation
        (LF-Tags: domain, classification; data filters for rows/columns)
               |  share via AWS RAM (LF-Tag grants to OUs / accounts)
               v
   Consumer acct X (resource links) --> Athena / Redshift Spectrum / EMR / Quick Sight
   Consumer acct Y (resource links) --> SageMaker AI
   (SageMaker Unified Studio / Catalog for discovery + subscription requests)
```

### Pattern E — Transactional DB to analytics without pipelines (zero-ETL)

```text
 Aurora MySQL/PostgreSQL / RDS / DynamoDB --zero-ETL integration--> Redshift (Serverless or RA3)
                                                                      |-- materialized views (auto refresh)
                                                                      |-- data sharing --> BU warehouses (other accounts/Regions)
                                                                      '-- Spectrum --> S3 history
```

- Replaces DMS/Glue CDC pipelines. Data lands in seconds, and heavy analytics no longer hits the OLTP source.

### Pattern F — Kafka modernization

```text
 On-prem Kafka --MirrorMaker 2 (on MSK Connect)--> Amazon MSK (Express brokers, 3 AZ)
                                                     |-- MSK Connect (Debezium CDC sources, S3 sink)
                                                     |-- Firehose (MSK source) --> S3 / Iceberg
                                                     '-- Managed Flink (stream processing)
 DR: MSK Replicator --> standby MSK cluster in second Region
```

### Pattern G — Batch big data on transient compute

```text
 EventBridge Scheduler --> Step Functions --> EMR RunJobFlow (instance fleets: On-Demand primary/core,
                                              Spot task fleet, price-capacity-optimized, 3 subnets)
                                          --> Spark steps on EMRFS/S3 --> auto-terminate
                    (alternatives: EMR Serverless application with max capacity; Glue job with Flex)
```

### Pattern H — ML inference selection

```text
 Interactive app (ms latency, steady)  -> SageMaker real-time endpoint (auto scaling, multi-model)
 Sporadic, small, CPU                  -> SageMaker serverless inference
 Big payloads / long runs              -> S3 -> SageMaker async inference (scale to 0) -> SNS
 Nightly scoring                       -> SageMaker batch transform (or Redshift ML)
 Off-the-shelf AI task                 -> Textract / Comprehend / Rekognition / Transcribe (no model mgmt)
 GenAI over company docs (emerging)    -> Bedrock Knowledge Bases + Guardrails
```

---

## 4. Decision tables / "X vs Y"

### 4.1 Kinesis Data Streams vs Data Firehose vs MSK vs SQS

| Criterion | **Kinesis Data Streams** | **Amazon Data Firehose** | **Amazon MSK** | **Amazon SQS** |
|---|---|---|---|---|
| Model | Ordered, replayable log (shards) | Managed delivery pipe (buffer → destination) | Managed Apache Kafka (topics/partitions) | Message queue (messages deleted after processing) |
| Latency | ~70 ms (EFO) to ~200 ms+ | Seconds to minutes (buffering. Zero-buffer option for some destinations) | Low ms | Low ms (long polling) |
| Multiple independent consumers | Yes (standard shared 2 MB/s/shard, or EFO) | No (one destination per stream) | Yes (consumer groups) | No (one consumer per message). Fan out with SNS → SQS |
| Replay | Yes, within retention (24 h – 365 days) | No | Yes, within retention (unlimited with tiered storage / Serverless) | No (DLQ redrive only) |
| Ordering | Per shard (partition key) | N/A | Per partition | FIFO queues only (per message group) |
| Scaling / ops | On-demand (none) or provisioned shards | None | Brokers/partitions (Provisioned) or none (Serverless) | None |
| Code to write | Producers + consumers (KCL/Lambda) | Producers only (or none via integrations) | Kafka clients, Connect | Producers + consumers |
| Typical answer when | Real-time custom processing, multiple consumers, replay, AWS-native | "Load streaming data into S3/Redshift/OpenSearch/Splunk with least effort", convert to Parquet | Existing Kafka, open-source portability, Kafka features | Decouple microservices, work queues, buffering bursts to a backend |

### 4.2 Athena vs Redshift vs EMR (vs OpenSearch)

| Criterion | **Athena** | **Redshift (provisioned / Serverless)** | **EMR** | **OpenSearch** |
|---|---|---|---|---|
| Best for | Ad hoc SQL on S3, infrequent queries, log analysis | High-concurrency BI, complex joins, consistent sub-second–seconds dashboards, data warehouse | Large-scale custom processing (Spark, Hive, Presto, HBase, Flink), ML feature engineering | Full-text search, log/observability analytics, vector search |
| Ops | Serverless | Serverless option, or managed clusters | Clusters (on EC2/EKS) or EMR Serverless | Managed domains or Serverless |
| Pricing | Per TB scanned (or provisioned capacity) | Node-hours / RPU-seconds + RMS storage | EC2 + EMR uplift (or vCPU/GB-seconds) | Instance-hours + storage (or OCUs) |
| Data location | S3 (plus federated sources) | Local RMS + Spectrum on S3 | S3 (EMRFS) / HDFS | Indexed in the cluster (UltraWarm/cold on S3) |
| Pick when stem says | "Serverless", "query S3 directly", "no infrastructure", "pay per query" | "Thousands of BI users", "complex joins", "data warehouse", "consistent performance" | "Existing Hadoop/Spark jobs", "custom frameworks", "petabyte ETL with full control" | "Search", "near-real-time log exploration", "Kibana/Dashboards" |

### 4.3 Glue vs EMR (vs EMR Serverless vs Managed Flink)

| Criterion | **AWS Glue** | **EMR Serverless** | **EMR on EC2 / EKS** | **Managed Service for Apache Flink** |
|---|---|---|---|---|
| Abstraction | Serverless ETL + catalog + crawlers + data quality | Serverless Spark/Hive runtime | Full cluster control | Serverless Flink runtime |
| Tuning control | Limited (worker type/count, Spark conf) | Moderate (Spark conf, capacity limits) | Full (instances, AMIs, bootstrap, frameworks) | Parallelism, KPUs |
| Frameworks | Spark (batch + streaming), Python shell | Spark, Hive | Spark, Hive, Presto/Trino, HBase, Flink, Hudi, etc. | Flink |
| Best for | Catalog-centric ETL, incremental loads (bookmarks), simple-to-moderate pipelines | Migrating Spark jobs without managing clusters | Lift-and-shift Hadoop, long-running/interactive clusters, Spot-heavy cost optimization | Stateful real-time stream processing |
| Cost lever | Flex execution, auto scaling, right DPU count | Pre-initialized vs on-demand, max capacity | Spot task fleets, transient clusters, Graviton, Savings Plans | Auto scaling KPUs |

### 4.4 Redshift Serverless vs provisioned RA3

| Need | Choose |
|---|---|
| Spiky, intermittent, unknown, dev/test, new project | **Serverless** (RPU-seconds, usage limits) |
| Steady 24×7 heavy load, predictable | **Provisioned RA3 + Reserved Nodes** |
| Isolate workloads/teams with chargeback on shared data | Either, with **data sharing** (producer → consumer warehouses) |
| Bursty concurrency on a provisioned cluster | **Concurrency scaling** |
| In-Region AZ failure tolerance | **RA3 Multi-AZ** (or relocation) |
| Region-level DR | **Cross-Region snapshot copy** (restore in DR Region) |

### 4.5 Kinesis capacity mode quick picker

| Traffic pattern | Mode |
|---|---|
| Unknown, new, spiky, idle overnight | On-demand Standard |
| Steady, well-understood, high utilization | Provisioned (right-sized, KPL aggregation) |
| Large estate: >10 MB/s total, many streams, ≥3 consumers per stream | On-demand Advantage (watch the 25 MB/s minimum commitment) |

### 4.6 Data movement options into the lake/warehouse

| Source | Best managed option |
|---|---|
| Aurora/RDS/DynamoDB → Redshift | **Zero-ETL integration** |
| Relational DB CDC → S3/Kafka | **AWS DMS** (CDC) or Debezium on **MSK Connect** |
| SaaS (Salesforce, SAP, ServiceNow…) → S3/Redshift | **Glue zero-ETL / connectors** or **Amazon AppFlow** |
| Logs/streams → S3/OpenSearch/Splunk | **Data Firehose** |
| On-prem files → S3 | **DataSync** (online), Snowball (offline) |
| DynamoDB → S3 for analytics | **DynamoDB export to S3** (no RCU impact) or zero-ETL |

---

## 5. Exam keyword → answer cheat list

| Keyword / phrase in stem | Likely answer |
|---|---|
| "Near-real-time delivery to S3/Redshift/OpenSearch/Splunk, least operational overhead" | **Data Firehose** |
| "Real-time, multiple consumers, replay, ordering per device" | **Kinesis Data Streams** (partition key = device ID) |
| "Multiple consumers throttled / latency high reading same stream" | **Enhanced fan-out** |
| "ProvisionedThroughputExceeded on writes, one hot shard" | Higher-cardinality **partition key**, then split shard |
| "Many tiny records, too many shards" | **KPL aggregation** (records/s limit), right-size shards |
| "Unpredictable stream traffic, don't want to manage shards" | **KDS on-demand** |
| "Convert JSON to Parquet before landing in S3" | **Firehose record format conversion** (Glue schema) |
| "Partition data in S3 by customer as it arrives" | **Firehose dynamic partitioning** |
| "Windowed aggregations / anomaly detection on streams with SQL" | **Managed Service for Apache Flink** |
| "Existing Kafka, minimal code change" | **Amazon MSK** (+ MSK Connect / MirrorMaker 2) |
| "Kafka, no capacity planning, modest throughput" | **MSK Serverless** |
| "Kafka, high throughput, no storage management, fast scaling" | **MSK Express brokers** |
| "Discover schema / populate catalog automatically" | **Glue crawler** |
| "Process only new data since last run" | **Glue job bookmarks** |
| "Business analysts prepare data visually, no code" | **Glue DataBrew** |
| "Validate data quality rules in pipeline" | **Glue Data Quality** (DQDL) |
| "Query S3 with SQL, serverless, pay per query" | **Athena** |
| "Reduce Athena cost / scanned bytes" | **Parquet/ORC + compression + partitioning (projection) + CTAS** |
| "Highly partitioned table, slow partition lookups, new partitions daily" | **Athena partition projection** |
| "Limit how much data a team's queries can scan" | **Athena workgroup data usage controls** |
| "Join S3 data with DynamoDB/RDS in one SQL query" | **Athena federated query** |
| "ACID updates/deletes on S3 data, time travel, GDPR delete" | **Apache Iceberg** (Athena/EMR/Glue) |
| "Existing Hadoop/Spark jobs, lowest cost, interruptible" | **EMR transient cluster + Spot task nodes / instance fleets** |
| "Spark without managing clusters" | **EMR Serverless** (or Glue) |
| "Run Spark on existing Kubernetes platform" | **EMR on EKS** |
| "Fine-grained (column/row/cell) data lake permissions" | **Lake Formation data filters** |
| "Permissions for hundreds of tables / many accounts, scalable" | **Lake Formation LF-Tags (TBAC)** + RAM sharing |
| "Adopt Lake Formation without breaking existing IAM users" | **Hybrid access mode** |
| "Data warehouse, thousands of BI users, complex joins" | **Redshift** |
| "Query S3 data from Redshift without loading" | **Redshift Spectrum** |
| "Share live warehouse data with another account/Region, no copies" | **Redshift data sharing** |
| "Spikes of concurrent dashboard queries" | **Concurrency scaling** |
| "OLTP to warehouse without ETL pipelines" | **Zero-ETL integration** |
| "Intermittent warehouse usage, pay only when querying" | **Redshift Serverless** |
| "Warehouse DR to another Region" | **Cross-Region snapshot copy** |
| "Log search + dashboards, cost-effective long retention" | **OpenSearch with UltraWarm/cold + ISM** |
| "Embed dashboards in SaaS app per tenant, row filtering" | **Quick Sight embedding + RLS** |
| "Fast dashboards, avoid repeated Athena scans" | **Quick Sight SPICE** |
| "Analyze combined data with a partner without sharing raw data" | **AWS Clean Rooms** |
| "Extract forms/tables from scanned documents" | **Textract** |
| "Medical entities / ICD-10 codes from clinical notes" | **Comprehend Medical** |
| "Detect PII in text / redact" | **Comprehend** (text), **Transcribe** (audio transcripts), **Macie** (S3 at scale), **Bedrock Guardrails** (GenAI) |
| "Recommendations" | **Personalize** |
| "Large payload / long-running ML inference, scale to zero" | **SageMaker async inference** |
| "Infrequent inference, tolerate cold start, no GPU" | **SageMaker serverless inference** |
| "Score a whole dataset nightly" | **SageMaker batch transform** |
| "Reduce ML training cost" | **Managed Spot Training** with checkpoints |
| "Generative AI chatbot over company documents" (emerging) | **Bedrock Knowledge Bases** (+ Guardrails) |

---

## 6. Traps & distractors

1. **"Use Firehose" when the requirement needs replay, multiple consumers, or sub-second latency.** Firehose buffers and delivers to one destination. Put KDS in front.
2. **"Switch to on-demand to save money"** on a steady, well-utilized stream. On-demand per-GB pricing usually costs more for steady traffic. Right-size provisioned shards (and aggregate) instead.
3. **"Add more shards"** to fix *read* contention among many consumers. EFO is the designed fix. Adding shards also raises cost and doesn't change the 5 GetRecords/s per-shard pattern for each consumer.
4. **Forgetting the 1,000 records/s limit.** A 0.5 KB × 3,000 records/s workload needs 3 shards without aggregation, not 2.
5. **SQS for streaming analytics / replay.** SQS has no replay and no multi-consumer fan-out without SNS. It isn't an analytics stream.
6. **Kinesis Data Streams to directly "write Parquet to S3".** KDS doesn't transform. Firehose (or the newer KDS S3 delivery/streaming tables) does.
7. **Glue crawler to "speed up Athena".** Crawlers maintain metadata. They don't reduce bytes scanned. Format, partitioning, and projection do.
8. **GZIP-compressed CSV/JSON as the "best" Athena optimization.** Compression helps, but **columnar Parquet/ORC** is the bigger win. Large non-splittable GZIP files also limit parallelism.
9. **Redshift for occasional ad hoc queries on S3 logs.** Athena is cheaper and serverless. Conversely, **Athena for 2,000 concurrent dashboard users** is wrong: use Redshift (or SPICE).
10. **"Copy data to each account" for cross-account analytics.** Use Lake Formation sharing via RAM or Redshift data sharing. No copies, central governance.
11. **S3 bucket policies per prefix for column/row-level control.** S3 can't filter columns or rows. Use Lake Formation data filters.
12. **Lake Formation "governed tables"** as the ACID answer. They're discontinued. The modern answer is **Iceberg**.
13. **EMR core nodes on Spot for long-running HDFS clusters.** Losing core nodes loses HDFS blocks. Put task nodes on Spot and keep core On-Demand, unless data lives in S3 and the job is fault tolerant.
14. **Spot for the EMR primary node** of a long-running cluster. Primary-node loss terminates the cluster.
15. **Reserved Instances for a cluster idle 19 h/day.** Transient clusters, Serverless, or Spot beat paying for idle reserved capacity.
16. **"EMRFS consistent view"** to fix S3 consistency. S3 is strongly consistent, so this is unnecessary.
17. **Concurrency scaling to give each business unit its own isolated, separately billed warehouse.** That's **data sharing** with consumer clusters/workgroups.
18. **Redshift cross-Region DR via "Multi-AZ".** Multi-AZ is in-Region. Region DR needs cross-Region snapshot copy (or data sharing to a consumer in the DR Region for reads).
19. **SageMaker real-time endpoint for sporadic large-payload jobs.** You pay 24×7, and payload limits apply. Use **async** (scale to zero). Serverless has **no GPU** and small memory/payload limits.
20. **Building a custom SageMaker model** when Textract/Comprehend/Rekognition/Transcribe solves it. That's more operational overhead.
21. **Rekognition to extract key-value pairs from forms.** Rekognition detects text in images, but **Textract** understands forms and tables.
22. **Amazon Forecast / Fraud Detector for a *new* customer build.** Both are closed to new customers. If they appear as options on SAP-C02, the item may predate the change. Prefer SageMaker AI (Canvas/Autopilot) or WAF Fraud Control where offered. Otherwise pick by functional fit.
23. **MSK Serverless for very high sustained throughput.** It has per-cluster ingress quotas (200 MBps by default). Use Provisioned (Express) for sustained heavy loads.
24. **OpenSearch as the primary data store.** Keep the source of truth in S3. Indices can be rebuilt.
25. **Quick Sight direct query to Athena for a high-traffic dashboard.** Every view scans S3. Use **SPICE**.

---

## 7. Professional architect focus

- **Design the data contract first.** Schema registry (Glue Schema Registry), partition keys, event time vs processing time, idempotency keys. Most streaming failures come from schema drift, hot keys, and duplicates (all Kinesis/Kafka consumers are at-least-once).
- **Storage format is an architectural decision.** Standardize on **Iceberg/Parquet** in curated zones. That decision drives Athena/Spectrum cost, GDPR deletes (Iceberg `DELETE` + `VACUUM`), and engine portability. Plan **compaction** (small-file problem from streaming) and **snapshot expiration**.
- **Cost modelling conversations with stakeholders:** Kinesis (shard-hours vs per-GB), Athena (TB scanned, so ask "how often, how much data?"), Redshift (24×7 provisioned with RIs vs Serverless with usage limits), EMR (Spot %, transient vs persistent), OpenSearch (hot-tier sizing and replicas dominate, so tier aggressively). Always propose **guardrails**: Athena workgroup limits, Redshift Serverless max RPU-hours, AWS Budgets, cost-allocation tags per team/workgroup.
- **Governance at scale:** A central catalog account, LF-Tags designed around **data domain × sensitivity**, data filters for PII, IAM Identity Center for human access, CloudTrail + Lake Formation audit. Choose **hybrid access mode** to migrate from IAM-based access without a big-bang cut-over. Make sure S3 IAM access doesn't bypass Lake Formation.
- **Multi-Region & resilience:** KDS/Firehose are Regional, so replicate with consumers that re-publish, or dual-write. MSK has **MSK Replicator**. S3 has **CRR**. Redshift has cross-Region snapshots and data sharing. OpenSearch has cross-cluster replication. Glue Catalog has no native cross-Region replication (re-create via IaC or crawlers). Document the RPO/RTO of each tier: analytics is often allowed a looser RTO than OLTP, so say so explicitly.
- **Security defaults:** KMS CMKs per data domain, VPC endpoints (S3 gateway, Kinesis/Glue/Athena interface), Redshift enhanced VPC routing, EMR in private subnets with Block Public Access, OpenSearch in VPC with fine-grained access control, Macie on raw buckets for PII discovery.
- **Modernization path (D4.4):** On-prem Hadoop → EMR (lift) → EMR Serverless/Glue (re-platform) → S3/Iceberg lake house + Athena/Redshift (re-architect). On-prem Kafka → MSK. Teradata/Oracle DW → Redshift (with AWS SCT/DMS). ETL tools → Glue. Nightly batch → streaming (KDS + Flink) only when the business needs fresher data. Don't stream for its own sake.
- **AI adoption:** Start with managed AI services. Move to SageMaker AI only for differentiating models. For generative AI, Bedrock + Knowledge Bases + Guardrails, with data residency, PII handling, and human review (A2I) agreed with compliance. Watch for **service availability changes**: Forecast, Fraud Detector, Glue for Ray, and some Comprehend features are closed to new customers.
- **Anti-patterns to call out:** One giant shared Redshift cluster for every team (no isolation). Copying datasets into every account. CSV in the curated zone. Crawlers running every 5 minutes on huge buckets. Persistent EMR clusters for nightly jobs. OpenSearch storing years of logs in the hot tier. Hand-rolled Kafka on EC2 without a reason.

---

## 8. Skills checklist

- [ ] I can compute the provisioned shard count from MB/s, records/s, and consumer read needs, and explain when KPL aggregation reduces it.
- [ ] I can compare provisioned vs On-demand Standard vs On-demand Advantage pricing for a given traffic profile.
- [ ] I can explain enhanced fan-out, when to use it, and its limit of 20 consumers (50 in Advantage).
- [ ] I can describe KCL's DynamoDB lease table, checkpoints, and why max useful workers = shards.
- [ ] I can state Kinesis retention defaults and maximums (24 h → 7 days → 365 days).
- [ ] I can configure Firehose buffering, Lambda transformation, Parquet conversion, dynamic partitioning, and S3 backup, and say when Firehose is *not* enough.
- [ ] I can choose between KDS, Firehose, MSK (Standard/Express/Serverless), and SQS from a scenario.
- [ ] I can list Glue components (Catalog, crawlers, Spark/streaming/Python shell jobs, bookmarks, Data Quality, DataBrew) and when to use each.
- [ ] I can list the five biggest Athena cost/performance levers, including partition projection and workgroup data limits.
- [ ] I can design an EMR cluster with instance fleets, Spot task nodes, and transient execution, and choose between EMR on EC2, EMR on EKS, and EMR Serverless.
- [ ] I can design Lake Formation cross-account sharing with LF-Tags, data filters, RAM, and resource links, and explain hybrid access mode.
- [ ] I can pick Redshift features: RA3/RMS, Serverless, Spectrum, data sharing, concurrency scaling, MVs, zero-ETL, WLM, cross-Region snapshots.
- [ ] I can design OpenSearch hot/UltraWarm/cold tiering with ISM and know the prerequisites (dedicated masters, UltraWarm before cold).
- [ ] I can explain Quick Sight SPICE, embedding, and RLS.
- [ ] I can draw the medallion raw/curated/consumption lake house and the streaming IoT → KDS → Firehose → S3 → Athena reference pattern.
- [ ] I can choose the right SageMaker AI inference option (real-time, serverless, async, batch) and cost levers (Spot training, Savings Plans, multi-model).
- [ ] I can map business problems to Rekognition, Textract, Comprehend(/Medical), Transcribe, Translate, Polly, Lex, Kendra, Personalize, and know which services are closed to new customers.
- [ ] I can describe Bedrock Knowledge Bases, Agents, Guardrails, and Provisioned Throughput at a high level (emerging).

---

## 9. Practice questions

**Q1.** A logistics company ingests telemetry from 40,000 trucks into an Amazon Kinesis Data Streams stream in provisioned mode. During launch the stream was sized at 24 shards for an expected peak that never materialized. Current steady traffic is 3,000 records per second with an average record size of 0.5 KB, flat across the day. Two consumer applications (a KCL application and an AWS Lambda function) read the stream using shared throughput. The operations team needs the ability to replay the last 72 hours of data. CloudWatch shows `IncomingBytes` at about 6% of the provisioned capacity. The producers are Java applications that the company controls. Which solution reduces cost the MOST while meeting the requirements?

- A. Switch the stream to on-demand capacity mode so the company pays only for the data ingested and retrieved.
- B. Update the producers to use the Kinesis Producer Library with record aggregation enabled, then reduce the stream to 2 shards with `UpdateShardCount`, keeping 72-hour extended retention.
- C. Reduce the stream to 2 shards with `UpdateShardCount` without changing the producers, and keep 72-hour extended retention.
- D. Replace the stream with an Amazon Data Firehose stream that delivers to Amazon S3, and have both consumers read the objects from S3.
- E. Register both consumers for enhanced fan-out and reduce the stream to 3 shards.

**Q2.** A media company sends JSON clickstream events through Amazon Data Firehose into an S3 bucket using the default settings. Analysts query the data with Amazon Athena. Almost every query filters on `event_date` and `site_id` and selects 5 of the 120 attributes. The monthly Athena bill has grown to more than the rest of the analytics platform combined, and queries are slow. The company wants to reduce Athena cost and improve performance with the LEAST operational overhead. **Which combination of actions should a solutions architect take? (Select TWO.)**

- A. Enable record format conversion on the Firehose stream to write Apache Parquet, using an AWS Glue Data Catalog table for the schema.
- B. Enable dynamic partitioning on the Firehose stream to write objects under `site_id=/event_date=/` prefixes, and configure partition projection on the Athena table.
- C. Schedule an AWS Glue crawler to run every 15 minutes on the bucket and increase the Firehose buffer interval to 900 seconds.
- D. Enable GZIP compression on the Firehose output and keep the JSON format so that existing queries continue to work.
- E. Load the data nightly into an Amazon Redshift provisioned cluster with the COPY command and move analysts to Redshift.

**Q3.** A fintech company uses a provisioned Kinesis data stream with 50 shards for payment events. Over the past year, the number of downstream applications reading the stream with the KCL has grown from two to six (fraud scoring, ledger, notifications, analytics, audit, and a data lake loader). The applications now see frequent `ReadProvisionedThroughputExceeded` exceptions, and fraud scoring end-to-end latency has risen from 300 ms to more than 4 seconds. Write traffic is stable at 30% of the stream's write capacity. The company needs to restore low latency for all consumers with minimal code changes. What should the solutions architect recommend?

- A. Double the shard count to 100 with `UpdateShardCount` so that each consumer gets more read throughput.
- B. Register each consumer application as an enhanced fan-out consumer and upgrade the applications to a KCL version that uses `SubscribeToShard`.
- C. Replace the KCL applications with Lambda functions that use a parallelization factor of 10 on the standard iterator.
- D. Insert an Amazon SNS topic with Amazon SQS queues per application between the stream and the consumers.

**Q4.** A retail group runs a central data lake in a governance account. It holds 600 AWS Glue Data Catalog tables over Amazon S3, and new tables are added weekly. Forty consumer accounts in AWS Organizations need analyst access through Amazon Athena. Columns that contain customer PII must never be visible to consumer-account analysts. In addition, each country's marketing team must see only the rows for its own country in the `orders` tables. The company wants a solution that scales as tables are added and minimizes ongoing administration. **Which combination of steps meets these requirements? (Select TWO.)**

- A. Define LF-Tags such as `classification=pii|general` and `domain`, assign them to databases, tables, and columns, and grant tag-based permissions on non-PII tag expressions to the consumer accounts or OUs through Lake Formation cross-account sharing.
- B. Write S3 bucket policies for each consumer account that allow access only to object prefixes that don't contain PII.
- C. Create Lake Formation data filters with row filter expressions on `country` for the `orders` tables, and grant each country's marketing principals `SELECT` through the matching filter.
- D. Run a nightly AWS Glue job that writes a separate, PII-free copy of every table to a bucket in each consumer account.
- E. Create one Athena view per country in each consumer account and use IAM policies to restrict which views each analyst can query.

**Q5.** A healthcare analytics company has a 50 TB table of uncompressed CSV files in Amazon S3 that hundreds of analysts query with Amazon Athena. The table is partitioned by month. Some analysts run `SELECT *` queries without filters, and an Amazon Quick Sight dashboard in direct-query mode against Athena is opened about 3,000 times per day. Finance requires predictable spending and a mechanism that stops runaway queries. **Which combination of actions will reduce cost and enforce limits? (Select THREE.)**

- A. Use Athena CTAS (or INSERT INTO) statements to rewrite the table as Snappy-compressed Parquet partitioned by month and region, and point analysts to the new table.
- B. Enable S3 Intelligent-Tiering on the bucket that stores the CSV files.
- C. Create Athena workgroups per team with a per-query data usage control limit, enforce workgroup settings, and restrict users to their workgroup with IAM.
- D. Move the CSV table into Amazon RDS for PostgreSQL and point Quick Sight to RDS.
- E. Switch the Quick Sight dataset to SPICE with a scheduled refresh.
- F. Enable S3 Transfer Acceleration on the bucket to make Athena queries finish faster.

**Q6.** A financial services company runs a provisioned Amazon Redshift RA3 cluster in a central data account. Nightly ETL loads curated data into it. Three business units, each with its own AWS account, need to query the live curated data for their own BI dashboards. Each business unit must pay for its own compute, must not affect the central cluster's ETL performance, and must not maintain separate copies of the data. Query patterns in the business units are unpredictable and idle at night. Which solution meets these requirements with the LEAST operational overhead?

- A. Enable concurrency scaling on the central cluster and create a WLM queue for each business unit with query monitoring rules.
- B. Each night, UNLOAD the curated tables to S3 in Parquet and have each business unit query them with Redshift Spectrum from its own cluster.
- C. Create datashares on the central cluster and authorize them for each business unit's account. Each business unit consumes the datashare from its own Amazon Redshift Serverless workgroup.
- D. Share a manual snapshot of the central cluster with each business unit account every morning and have each business unit restore it to its own cluster.

**Q7.** A company runs a nightly Apache Spark job on a persistent 40-node Amazon EMR cluster that uses only On-Demand Instances. The job takes about 5 hours, and the cluster is idle the rest of the day. The input data already lives in Amazon S3 but is copied into HDFS before each run. The job is idempotent and can be retried. The company wants to significantly reduce cost without rewriting the Spark code. **Which combination of actions should the solutions architect recommend? (Select TWO.)**

- A. Purchase 3-year Reserved Instances for all 40 nodes.
- B. Replace the persistent cluster with a transient cluster launched nightly by AWS Step Functions that reads input from and writes output to S3 through EMRFS and terminates automatically when the steps finish.
- C. Use instance fleets with On-Demand primary and core nodes and a Spot task fleet that spans multiple instance types and subnets with the price-capacity-optimized allocation strategy.
- D. Run the primary node on Spot Instances to reduce the largest single instance cost.
- E. Rewrite the job as an AWS Glue Python shell job to avoid cluster costs.

**Q8.** A gaming company runs three self-managed Apache Kafka clusters on premises with about 300 topics, dozens of Kafka Connect connectors, and producers and consumers written with standard Kafka client libraries. Sustained ingress is about 400 MBps with predictable growth. The company wants to move to AWS, reduce the effort spent on broker storage management and scaling, and avoid application code changes. Migration must allow a gradual consumer cut-over. Which solution meets these requirements?

- A. Create Amazon Kinesis Data Streams in on-demand mode and update producers and consumers to use the KPL and KCL.
- B. Create an Amazon MSK Serverless cluster and migrate topics with MirrorMaker 2 running on Amazon EC2.
- C. Create an Amazon MSK Provisioned cluster with Express brokers, replicate topics from on premises with MirrorMaker 2 running on MSK Connect, and move the existing connectors to MSK Connect.
- D. Deploy Apache Kafka on Amazon EC2 instances in an Auto Scaling group with EBS volumes and replicate with MirrorMaker 2.

**Q9.** A medical imaging startup has trained a deep learning model (GPU required) that analyzes uploaded scans. Each scan is 200–800 MB, inference takes 6–15 minutes per scan, and clinicians need results within 30 minutes of upload. Uploads are sporadic: there are zero on most nights and weekends, and bursts of up to 300 per day otherwise. The startup wants to minimize cost, avoid paying for idle capacity, and be notified when each result is ready. Which deployment option should the solutions architect choose?

- A. A SageMaker AI real-time endpoint on GPU instances with target-tracking auto scaling and a minimum of one instance.
- B. A SageMaker AI serverless inference endpoint with 6 GB of memory and provisioned concurrency.
- C. A SageMaker AI asynchronous inference endpoint on GPU instances with an auto scaling policy that scales to zero when the queue is empty, and Amazon SNS success and error notifications.
- D. A SageMaker AI batch transform job scheduled every 24 hours over the S3 upload prefix.

**Q10.** An insurance company receives thousands of scanned claim packets per day as multi-page PDFs. Each packet contains claim forms with key-value fields and tables, plus free-text physician notes. The company needs to extract the form fields and table data into a database, and identify diagnoses and medications in the physician notes with standard medical codes so that claims can be auto-adjudicated. The company has no ML expertise and wants the LEAST operational overhead. **Which combination of services should be used? (Select TWO.)**

- A. Amazon Textract asynchronous document analysis with the FORMS and TABLES features.
- B. Amazon Rekognition DetectText on each page image.
- C. Amazon Comprehend Medical entity detection and ICD-10-CM / RxNorm ontology linking on the extracted note text.
- D. Amazon Comprehend custom entity recognition trained on a labelled set of medical terms.
- E. A custom named-entity recognition model trained and hosted on Amazon SageMaker AI.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B**

- **Why B:** Each shard accepts 1 MB/s **or 1,000 records/s**. 3,000 records/s × 0.5 KB ≈ 1.5 MB/s. Without aggregation, the **records/s** limit forces at least 3 shards. KPL aggregation packs many user records into fewer Kinesis records, so the binding limit becomes bytes: 1.5 MB/s → 2 shards for writes. Two standard consumers read 2 × 1.5 = 3 MB/s, and 2 shards × 2 MB/s = 4 MB/s is enough. Shard-hours drop from 24 to 2 (~$22/month instead of ~$263 at $0.015/shard-hour), extended-retention shard-hours drop by the same ratio, and aggregation also cuts PUT payload units because fewer 25 KB units are billed for many tiny records.
- **A:** On-demand Standard charges per GB ingested and retrieved plus a per-stream hourly fee. At ~3.9 TB/month ingested and ~7.9 TB retrieved, that is several hundred dollars a month, more than a right-sized provisioned stream. On-demand suits unknown or spiky traffic, not flat traffic.
- **C:** 2 shards support only 2,000 records/s. The 3,000 records/s workload would be throttled (`ProvisionedThroughputExceeded`).
- **D:** Firehose has no replay and no multiple real-time consumers. It would break the KCL/Lambda processing model.
- **E:** 3 shards would work (with no headroom at exactly 3,000 records/s), but EFO adds per consumer-shard-hour and per-GB charges that aren't needed for two consumers. It costs more than B.
- **Refs:** https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html · https://docs.aws.amazon.com/streams/latest/dev/kinesis-kpl-concepts.html · https://aws.amazon.com/kinesis/data-streams/pricing/
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A, B**

- **A:** Parquet is columnar, so Athena reads only the 5 referenced columns out of 120. This is usually the biggest reduction in bytes scanned. Firehose does the conversion natively using a Glue table schema, with no extra jobs.
- **B:** Dynamic partitioning writes data into partition prefixes as it arrives, and partition projection lets Athena prune `site_id`/`event_date` without crawlers or `MSCK REPAIR`. Queries then scan only the relevant partitions.
- **C:** Crawlers maintain metadata but don't reduce bytes scanned, and running one every 15 minutes adds cost. A longer buffer gives slightly bigger files but doesn't address row/column pruning.
- **D:** GZIP reduces bytes but JSON is still row-based, so every column is read. It's a weaker fix than Parquet and doesn't add partition pruning.
- **E:** Adds a cluster to run and pay for 24×7 and changes the analyst workflow. That's more operational overhead.
- **Refs:** https://docs.aws.amazon.com/firehose/latest/dev/record-format-conversion.html · https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html · https://docs.aws.amazon.com/athena/latest/ug/partition-projection.html
</details>

<details><summary>Show answer — Q3</summary>

**Correct: B**

- **Why B:** With shared-throughput consumers, all six applications compete for the same **2 MB/s and 5 GetRecords calls per second per shard**, so they are throttled and fall behind. **Enhanced fan-out** gives each registered consumer a dedicated 2 MB/s per shard with HTTP/2 push (~70 ms propagation). KCL 2.x+ supports EFO through configuration, so code changes are minimal. Up to 20 consumers can register per stream.
- **A:** More shards raises aggregate read capacity and cost, but every consumer still polls every shard, and write capacity is already underused. It treats the symptom at higher cost.
- **C:** Lambda on the standard iterator still shares the per-shard read limits. A parallelization factor raises processing concurrency, not shard read throughput, and it means a rewrite.
- **D:** Adds components and latency, loses Kinesis ordering and replay semantics, and requires substantial rework.
- **Refs:** https://docs.aws.amazon.com/streams/latest/dev/enhanced-consumers.html · https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html
</details>

<details><summary>Show answer — Q4</summary>

**Correct: A, C**

- **A:** **LF-TBAC** scales to hundreds of tables and many accounts. New tables that receive tags are automatically covered by existing grants. Column-level tags exclude PII columns. Cross-account grants to accounts or OUs use AWS RAM, and consumer admins create resource links. No data is copied.
- **C:** **Data filters** give row-level (and cell-level) security. A row filter on `country` granted per marketing team enforces "own country only" for Athena and other integrated engines.
- **B:** S3 bucket policies work at object/prefix level. They can't hide columns inside files or filter rows, and per-account policies don't scale.
- **D:** Copies per account multiply storage and pipelines, go stale, and decentralize governance.
- **E:** Per-account views multiply administration (40 accounts × countries). IAM can't stop users from querying the underlying tables unless Lake Formation also controls access.
- **Refs:** https://docs.aws.amazon.com/lake-formation/latest/dg/tag-based-access-control.html · https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html · https://docs.aws.amazon.com/lake-formation/latest/dg/cross-account-permissions.html
</details>

<details><summary>Show answer — Q5</summary>

**Correct: A, C, E**

- **A:** Converting uncompressed CSV to compressed, partitioned Parquet typically cuts bytes scanned by an order of magnitude. CTAS does it in SQL with no extra infrastructure.
- **C:** Workgroup **per-query data usage controls** cancel queries that exceed a scan threshold, which stops runaway `SELECT *` queries. Enforced settings and IAM scoping prevent bypass. Per-workgroup limits with alarms give predictable spend.
- **E:** **SPICE** serves the 3,000 daily dashboard views from in-memory data. Athena is queried only at refresh time instead of on every view.
- **B:** Intelligent-Tiering lowers storage cost, not the per-TB-scanned query cost that dominates here.
- **D:** RDS isn't suited to a 50 TB analytical scan workload, and it adds operational overhead.
- **F:** Transfer Acceleration speeds up client uploads and downloads over long distances. It does nothing for Athena scans.
- **Refs:** https://docs.aws.amazon.com/athena/latest/ug/ctas.html · https://docs.aws.amazon.com/athena/latest/ug/workgroups-setting-control-limits-cloudwatch.html · https://docs.aws.amazon.com/athena/latest/ug/performance-tuning.html · https://docs.aws.amazon.com/quicksuite/latest/userguide/what-is.html
</details>

<details><summary>Show answer — Q6</summary>

**Correct: C**

- **Why C:** **Redshift data sharing** gives live, transactionally consistent access to the producer's data across accounts without copies. Consumer queries run on the **consumer's compute**, so business units pay for their own queries and the ETL cluster is isolated. **Redshift Serverless** suits unpredictable, idle-at-night usage because you pay only while queries run. RA3 producers support data sharing.
- **A:** Concurrency scaling runs on the producer account's bill and doesn't give per-account isolation or chargeback. Consumers still need access in their own accounts.
- **B:** Creates nightly copies (stale data) and adds UNLOAD pipelines and Spectrum scan costs.
- **D:** Daily snapshot restores create full copies, introduce a day of staleness, and add heavy operational work.
- **Refs:** https://docs.aws.amazon.com/redshift/latest/dg/datashare-overview.html · https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-capacity.html
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B, C**

- **B:** A **transient cluster** removes about 19 idle hours per day. Reading and writing S3 directly through **EMRFS** removes the HDFS copy step and lets the cluster be disposable. Step Functions (or EventBridge Scheduler) orchestrates creation, steps, and auto-termination.
- **C:** **Instance fleets** with a Spot task fleet across multiple instance types and subnets, using the price-capacity-optimized strategy, get large Spot discounts with a lower interruption risk. Keeping primary and core on On-Demand protects the cluster. The idempotent job tolerates task-node loss.
- **A:** RIs commit to 24×7 capacity for a 5-hour job, which pays for idle time.
- **D:** Losing the primary node terminates the cluster, and it's a single small instance, so the savings are negligible for the risk.
- **E:** Python shell jobs are single-node and can't run a 40-node Spark workload. It also means rewriting the code.
- **Refs:** https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-instance-fleet.html · https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-plan-longrunning-transient.html · https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-plan-instances-guidelines.html
</details>

<details><summary>Show answer — Q8</summary>

**Correct: C**

- **Why C:** **Amazon MSK** runs open-source Kafka, so existing clients and connectors work unchanged. **Express brokers** remove storage provisioning (pay-as-you-go storage), scale up to 20× faster, and offer up to 3× throughput per broker, which suits 400 MBps sustained ingress. **MirrorMaker 2 on MSK Connect** replicates topics continuously, so consumers can cut over gradually. Existing Kafka Connect connectors move to MSK Connect.
- **A:** Kinesis isn't Kafka-API compatible. Producers and consumers would have to be rewritten.
- **B:** MSK Serverless has a default per-cluster ingress quota of **200 MBps**, below the 400 MBps sustained load, and running MirrorMaker on EC2 adds operational work.
- **D:** Self-managed Kafka keeps all the broker, storage, and scaling work the company wants to get rid of.
- **Refs:** https://docs.aws.amazon.com/msk/latest/developerguide/msk-broker-types-express.html · https://docs.aws.amazon.com/msk/latest/developerguide/limits.html · https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect.html
</details>

<details><summary>Show answer — Q9</summary>

**Correct: C**

- **Why C:** **Asynchronous inference** is designed for **large payloads (up to 1 GB)** and **long processing (up to 1 hour)**. Requests are queued with input in S3, the endpoint can **scale to zero** when idle, and **SNS notifications** report success or failure. It supports GPU instances.
- **A:** A real-time endpoint with a minimum of one GPU instance runs 24×7 (paying for idle nights and weekends). Real-time invocation also isn't meant for 800 MB payloads or 15-minute processing.
- **B:** Serverless inference supports **no GPUs**, a maximum of 6 GB of memory, and small payloads and short timeouts. It can't run this model.
- **D:** A 24-hour batch schedule misses the 30-minute result requirement.
- **Refs:** https://docs.aws.amazon.com/sagemaker/latest/dg/async-inference.html · https://docs.aws.amazon.com/sagemaker/latest/dg/serverless-endpoints.html · https://docs.aws.amazon.com/sagemaker/latest/dg/deploy-model.html
</details>

<details><summary>Show answer — Q10</summary>

**Correct: A, C**

- **A:** **Textract** extracts text **plus structure**: key-value pairs (FORMS) and tables (TABLES). The asynchronous API handles multi-page PDFs stored in S3. It is fully managed and needs no ML expertise.
- **C:** **Comprehend Medical** detects medical conditions, medications, dosages, and PHI, and links them to **ICD-10-CM and RxNorm** codes, which is exactly what auto-adjudication needs. It is HIPAA-eligible.
- **B:** Rekognition detects words in images but doesn't understand forms or tables.
- **D:** Custom entity recognition needs labelled training data and model management, and it doesn't provide standard medical ontology codes.
- **E:** A custom SageMaker AI model requires ML expertise and ongoing operations. That's the opposite of least operational overhead.
- **Refs:** https://docs.aws.amazon.com/textract/latest/dg/what-is.html · https://docs.aws.amazon.com/comprehend-medical/latest/dev/comprehendmedical-welcome.html
</details>

---

## 10. References

**Streaming**
- Amazon Kinesis Data Streams Developer Guide: https://docs.aws.amazon.com/streams/latest/dev/introduction.html
- KDS quotas and limits: https://docs.aws.amazon.com/streams/latest/dev/service-sizes-and-limits.html
- KDS enhanced fan-out: https://docs.aws.amazon.com/streams/latest/dev/enhanced-consumers.html
- KDS pricing: https://aws.amazon.com/kinesis/data-streams/pricing/
- Amazon Data Firehose Developer Guide: https://docs.aws.amazon.com/firehose/latest/dev/what-is-this-service.html
- Firehose dynamic partitioning: https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html
- Firehose record format conversion: https://docs.aws.amazon.com/firehose/latest/dev/record-format-conversion.html
- Amazon Managed Service for Apache Flink: https://docs.aws.amazon.com/managed-flink/latest/java/what-is.html
- Amazon MSK Developer Guide: https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html
- MSK Express brokers: https://docs.aws.amazon.com/msk/latest/developerguide/msk-broker-types-express.html
- MSK quotas: https://docs.aws.amazon.com/msk/latest/developerguide/limits.html

**Data lake, ETL & query**
- AWS Glue Developer Guide: https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html
- Glue job bookmarks: https://docs.aws.amazon.com/glue/latest/dg/monitor-continuations.html
- Glue Data Quality: https://docs.aws.amazon.com/glue/latest/dg/glue-data-quality.html
- AWS Glue for Ray availability change: https://docs.aws.amazon.com/glue/latest/dg/awsglue-ray-jobs-availability-change.html
- Amazon Athena User Guide: https://docs.aws.amazon.com/athena/latest/ug/what-is.html
- Athena partition projection: https://docs.aws.amazon.com/athena/latest/ug/partition-projection.html
- Athena performance tuning: https://docs.aws.amazon.com/athena/latest/ug/performance-tuning.html
- Athena workgroups: https://docs.aws.amazon.com/athena/latest/ug/workgroups-manage-queries-control-costs.html
- Amazon EMR Management Guide (instance fleets): https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-instance-fleet.html
- EMR Serverless: https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/emr-serverless.html
- EMR on EKS: https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html
- AWS Lake Formation Developer Guide: https://docs.aws.amazon.com/lake-formation/latest/dg/what-is-lake-formation.html
- Lake Formation tag-based access control: https://docs.aws.amazon.com/lake-formation/latest/dg/tag-based-access-control.html
- Lake Formation data filters: https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html
- Lake Formation hybrid access mode: https://docs.aws.amazon.com/lake-formation/latest/dg/hybrid-access-mode.html

**Warehouse, search, BI, collaboration**
- Amazon Redshift Management Guide: https://docs.aws.amazon.com/redshift/latest/mgmt/welcome.html
- Redshift Serverless capacity: https://docs.aws.amazon.com/redshift/latest/mgmt/serverless-capacity.html
- Redshift data sharing: https://docs.aws.amazon.com/redshift/latest/dg/datashare-overview.html
- Redshift concurrency scaling: https://docs.aws.amazon.com/redshift/latest/dg/concurrency-scaling.html
- Redshift zero-ETL integrations: https://docs.aws.amazon.com/redshift/latest/mgmt/zero-etl-using.html
- Redshift snapshots: https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-snapshots.html
- OpenSearch UltraWarm: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ultrawarm.html
- OpenSearch Serverless: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html
- Amazon Quick (Quick Sight): https://docs.aws.amazon.com/quicksuite/latest/userguide/what-is.html
- AWS Clean Rooms: https://docs.aws.amazon.com/clean-rooms/latest/userguide/what-is.html
- Amazon SageMaker Unified Studio: https://docs.aws.amazon.com/sagemaker-unified-studio/latest/userguide/what-is-sagemaker-unified-studio.html

**AI/ML**
- SageMaker AI inference options: https://docs.aws.amazon.com/sagemaker/latest/dg/deploy-model.html
- SageMaker AI serverless inference: https://docs.aws.amazon.com/sagemaker/latest/dg/serverless-endpoints.html
- SageMaker AI asynchronous inference: https://docs.aws.amazon.com/sagemaker/latest/dg/async-inference.html
- SageMaker AI managed Spot training: https://docs.aws.amazon.com/sagemaker/latest/dg/model-managed-spot-training.html
- Amazon Bedrock User Guide: https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html
- Bedrock Knowledge Bases: https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html
- Bedrock Guardrails: https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html
- Amazon Textract: https://docs.aws.amazon.com/textract/latest/dg/what-is.html
- Amazon Comprehend Medical: https://docs.aws.amazon.com/comprehend-medical/latest/dev/comprehendmedical-welcome.html
- Amazon Comprehend feature availability change: https://docs.aws.amazon.com/comprehend/latest/dg/comprehend-availability-change.html
- Amazon Forecast (availability notice): https://docs.aws.amazon.com/forecast/latest/dg/what-is-forecast.html
- Amazon Fraud Detector availability change: https://docs.aws.amazon.com/frauddetector/latest/ug/frauddetector-availability-change.html

**Architecture guidance**
- Big Data Analytics Options on AWS (whitepaper): https://docs.aws.amazon.com/whitepapers/latest/big-data-analytics-options/welcome.html
- Build Modern Data Streaming Architectures on AWS (whitepaper): https://docs.aws.amazon.com/whitepapers/latest/build-modern-data-streaming-analytics-architectures/build-modern-data-streaming-analytics-architectures.html
- Data lake layer definitions (Prescriptive Guidance): https://docs.aws.amazon.com/prescriptive-guidance/latest/defining-bucket-names-data-lakes/data-layer-definitions.html
- AWS Well-Architected Data Analytics Lens: https://docs.aws.amazon.com/wellarchitected/latest/analytics-lens/analytics-lens.html
