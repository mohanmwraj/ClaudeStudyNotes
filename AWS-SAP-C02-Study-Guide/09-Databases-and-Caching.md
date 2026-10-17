# Chapter 09 — Databases & Caching: RDS, Aurora, DynamoDB, ElastiCache & Purpose-Built DBs
> **Exam mapping:** D2 Task 2.2, 2.4, 2.5, 2.6 · D3 Task 3.3, 3.4 · D4 Task 4.3, 4.4 | **Weight signal:** High | **Study time:** ~6 h
> [← Previous](08-Storage-and-Data-Transfer.md) · [Index](00-README-Start-Here.md) · [Next →](10-Application-Integration-and-Event-Driven.md)

---

## 1. What the exam really tests here

Databases appear in more SAP-C02 questions than almost any other topic, because nearly every scenario has a data tier. You are rarely asked "what is Aurora?". You are asked to **pick the right data store and the right HA/DR/scaling feature under a business constraint**. The decisions you must make quickly:

| Decision | Typical stem signal | What you must know |
|---|---|---|
| **Which engine / service** | "relational with joins", "key-value at any scale", "graph relationships", "MongoDB-compatible", "Cassandra", "time-series", "ledger" | Purpose-built database selection (§4.1) |
| **HA inside a Region** | "survive AZ failure", "failover under 35 s", "readable standby" | Multi-AZ DB instance vs Multi-AZ DB cluster vs Aurora replicas |
| **Cross-Region DR** | "RPO of seconds, RTO under a minute", "Region outage", "regional rotation", "zero data loss for planned move" | Aurora Global Database (switchover vs failover), DynamoDB global tables (MREC vs MRSC), RDS cross-Region read replicas, cross-Region automated backups |
| **Read scaling** | "reporting queries slow the OLTP database", "global users read locally" | Read replicas, Aurora reader/custom endpoints, caching (ElastiCache, DAX), global secondaries |
| **Write scaling** | "write throughput exceeds largest instance", "hot partition", "millions of writes/sec" | DynamoDB partition design and write sharding, Aurora Limitless, sharding, queue-based load leveling |
| **Connection management** | "Lambda exhausts database connections", "too many connections during scale-out" | RDS Proxy (pooling/multiplexing), IAM auth, Data API |
| **Low-downtime change** | "major version upgrade with minimal downtime", "test schema change on production copy" | RDS/Aurora Blue/Green Deployments, Aurora cloning |
| **Recovery from human error** | "accidental DELETE, recover in minutes" | Aurora Backtrack (MySQL), PITR, DynamoDB PITR |
| **Cost** | "unpredictable / spiky traffic", "idle at night", "I/O is half the bill" | Aurora Serverless v2 (scale to 0 ACU), DynamoDB on-demand, Aurora I/O-Optimized, reserved instances / reserved capacity |
| **Migration / modernization** | "SQL Server licensing cost", "Oracle to open source", "minimal code change" | DMS + SCT, Babelfish for Aurora PostgreSQL, RDS Custom, zero-ETL (link [Chapter 13](13-Migration-and-Modernization.md)) |

The exam favours **managed, purpose-built, least-operational-overhead** answers. When two options both work, the cheaper, more managed, or more native one usually wins, unless the stem names a constraint (OS access, specific RPO, licensing) that rules it out.

---

## 2. Core concepts & services — deep dive

### 2.1 Amazon RDS

#### What it is and how it works
Amazon RDS is managed relational database **instances**: AWS runs the host, OS, patching, backups, and failover. You choose the engine, instance class and storage. Each DB instance is an EC2-like host with **EBS storage** attached; the engine is the stock engine (with RDS-specific parameter and option groups).

**Engines:** MySQL, MariaDB, PostgreSQL, Oracle (BYOL and License Included for SE2), Microsoft SQL Server (License Included; Express/Web/Standard/Enterprise), and IBM Db2. **Aurora** shares the RDS console/API but is a different architecture (§2.2).

#### Storage
- Types: **gp3** (baseline 3,000 IOPS, IOPS and throughput provisioned independently), **gp2** (legacy, burst-credit model), **Provisioned IOPS io1/io2 Block Express** (consistent low latency for production OLTP), magnetic (legacy).
- **Maximum storage:** 64 TiB per volume for most engines. RDS for **Oracle and SQL Server** can reach **256 TiB** by adding up to three additional storage volumes (each up to 64 TiB) to the primary volume (Dec 2025 feature).
- **Storage autoscaling:** set a *maximum storage threshold*; RDS grows storage automatically when free space is low (roughly: free space ≤ 10% of allocated, condition lasting ≥ 5 minutes, and ≥ 6 hours since the last storage modification). Storage **can never be shrunk** in place — to shrink, dump/restore or use DMS into a smaller instance.
- Storage modifications can put the instance in `storage-optimization` for hours; you cannot modify storage again until it completes (another reason for autoscaling headroom).

#### High availability inside a Region — two different "Multi-AZ" products

| | **Multi-AZ DB instance** | **Multi-AZ DB cluster** |
|---|---|---|
| Topology | Primary + **one standby** in another AZ | **Writer + two reader instances** in three AZs |
| Replication | **Synchronous** block-level | **Semisynchronous** (commit after ≥1 reader acknowledges) using engine-native replication |
| Standby readable? | **No** — standby is not a read scaling solution | **Yes** — two readable standbys (reader endpoint) |
| Typical failover | **60–120 seconds** (DNS CNAME flip) | **Typically under 35 seconds** |
| Engines | MySQL, MariaDB, PostgreSQL, Oracle, SQL Server (DBM or Always On AGs), Db2 | **MySQL and PostgreSQL** only |
| Storage | Any | Local NVMe-backed instance classes (`*d` classes such as m6gd/r6gd) with io1/io2/gp3 EBS |
| Write latency | Higher (synchronous cross-AZ) | Lower than Multi-AZ instance (semisync + local write cache) |
| Endpoints | One endpoint | Cluster (writer) endpoint, reader endpoint, instance endpoints |
| Cross-Region automated backup replication | Supported | **Not supported** |

Failover triggers for Multi-AZ DB instance include: primary host failure, AZ network loss, storage failure, OS patching in the maintenance window, instance-class modification, and **Reboot with failover** (how you test it). The endpoint DNS name stays the same; clients must reconnect, and **JVM DNS caching** should be ≤ 60 s.

> **Exam rule:** "Increase availability *and* offload reads with a standby in another AZ" → Multi-AZ **DB cluster** (or Aurora). "Standby for HA only" → Multi-AZ DB instance. A standby of a Multi-AZ DB instance **never** serves reads.

#### Read replicas
- **Asynchronous** replication using the engine's native mechanism (logical binlog for MySQL/MariaDB; physical for PostgreSQL, Oracle, SQL Server, Db2).
- **Up to 15 read replicas per primary** (default, adjustable quota; for Oracle, AWS recommends limiting to 5 to minimise lag). SQL Server replicas depend on Always On availability groups and have edition/version requirements — check the engine docs.
- **Cross-Region** read replicas are supported (MySQL, MariaDB, PostgreSQL, Oracle, SQL Server, Db2). You pay inter-Region data transfer. Same-Region replication traffic is free.
- **Cascading** replicas (replica of a replica): MySQL, MariaDB, and certain PostgreSQL versions only — not Oracle, SQL Server or Db2.
- A read replica can itself be **Multi-AZ** — useful because after promotion it is already highly available.
- **Promotion** turns a replica into a standalone, writable instance; replication stops permanently (one-way). This is the manual cross-Region DR mechanism for RDS: RPO = replica lag (seconds to minutes), RTO = minutes (promotion + DNS/app reconfiguration).
- MySQL/MariaDB replicas can be made writable (e.g., to add indexes); PostgreSQL replicas cannot.
- **Oracle mounted replicas** and **Db2 standby replicas** do not accept connections — they exist purely for cross-Region DR (and mounted Oracle replicas do not need an Active Data Guard licence).
- RDS **does not auto-scale read replicas** (Aurora does).
- Deleting a source instance promotes its same-Region replicas.

#### Backups, PITR, snapshots
- **Automated backups:** daily snapshot during the backup window plus transaction logs every 5 minutes. Retention **1–35 days** (0 disables automated backups and, for most engines, prevents read replicas). Enables **point-in-time restore (PITR)** to any second in the retention window up to the *latest restorable time* (typically within the last 5 minutes).
- **Every restore creates a new DB instance** with a new endpoint — no in-place restore. Plan DNS (Route 53 CNAME) or connection-string swaps.
- **Manual snapshots** are kept until deleted (100 per Region default quota), can be **copied cross-Region and cross-account** and **shared** with other accounts. You can share snapshots encrypted with a **customer managed KMS key** (and you must share the key); snapshots encrypted with the AWS managed key `aws/rds` **cannot be shared**.
- **Cross-Region automated backup replication:** RDS copies snapshots and transaction logs to a destination Region so you can **PITR in the DR Region** — a cheap pilot-light DR for RDS (default quota 20 per account; not for Multi-AZ DB clusters). Requires a KMS key in the destination Region for encrypted instances.
- **Export snapshots to S3** in Apache Parquet for analytics.
- **AWS Backup** provides centralized, policy-based backups, cross-account and cross-Region copy, Vault Lock (WORM) — the answer when the stem says "centrally manage backups across accounts" (see [Chapter 08](08-Storage-and-Data-Transfer.md) and [Chapter 12](12-Resilience-HA-and-Disaster-Recovery.md)).

#### Encryption constraints (frequently tested)
- Encryption at rest (KMS, AES-256) **must be chosen at creation**. You **cannot encrypt an existing unencrypted instance in place** and cannot disable encryption once on.
- To encrypt an existing database: **snapshot → copy snapshot with encryption enabled → restore** from the encrypted copy (downtime for writes after snapshot), or use **DMS** for a near-zero-downtime move to a new encrypted instance.
- Read replicas must match the source's encryption state; you cannot create an encrypted replica of an unencrypted source (and vice versa). Cross-Region encrypted replicas/snapshot copies use a KMS key **in the destination Region**.
- In transit: TLS; enforce with `rds.force_ssl=1` (PostgreSQL/SQL Server) or `require_secure_transport` (MySQL). Oracle and SQL Server also support **TDE** via option groups.
- KMS key access loss puts the instance into `inaccessible-encryption-credentials` state.

#### IAM database authentication
- Supported for **MySQL, MariaDB, PostgreSQL** (and Aurora MySQL/PostgreSQL). Users connect with a **15-minute authentication token** generated by `rds generate-db-auth-token` using IAM credentials; IAM policy grants `rds-db:connect` on `arn:aws:rds-db:region:account:dbuser:DbiResourceId/dbusername`.
- Benefits: no passwords stored in apps, central IAM control, CloudTrail. Requires SSL.
- Token validation consumes database resources (current docs call for roughly 300–1,000 MiB of extra memory), and older AWS guidance limited direct IAM auth to modest rates (about 200 new connections per second). For **high connection churn** (e.g., Lambda), put **RDS Proxy** in front: clients authenticate to the proxy with IAM, and the proxy keeps a pool of database connections. Note that `aws:SourceIp`/`aws:SourceVpc`-style global condition keys are not supported for IAM DB auth.
- **Kerberos** auth via AWS Managed Microsoft AD is available for SQL Server, Oracle, MySQL, PostgreSQL — the answer when the stem says "use existing Active Directory credentials".
- Password rotation without IAM auth: **Secrets Manager** with RDS-managed master user password (`ManageMasterUserPassword`) or rotation Lambda.

#### Amazon RDS Proxy
- Fully managed, highly available proxy that keeps a **connection pool** to the database and **multiplexes** many client connections over fewer database connections (connection reuse between transactions).
- Engines: RDS for MySQL, MariaDB, PostgreSQL, SQL Server; Aurora MySQL and PostgreSQL.
- **Failover:** the proxy detects the new writer and routes to it, bypassing DNS propagation and preserving client connections — AWS states failover time reduced **by up to 66%** for Aurora and RDS Multi-AZ. It can also reduce Multi-AZ DB cluster minor-version upgrade downtime to about a second.
- **Auth:** clients can be required to use **IAM authentication** to the proxy; the proxy reaches the database with credentials in **Secrets Manager** (up to 200 secrets per proxy) or end-to-end IAM auth.
- **Pinning:** session-state changes (temporary tables, session variables, certain prepared statements, statements > 16 KB) pin a client to one DB connection and reduce multiplexing — tune the app.
- **Networking:** must be in the **same VPC** as the database and **cannot be publicly accessible**; you can add extra endpoints (including in other VPCs and **read-only endpoints** for Aurora readers). Default quota 20 proxies per account per Region.
- Pricing: per vCPU-hour of the underlying database (or per ACU for Aurora Serverless).
- Use cases: **Lambda** and other bursty compute that opens many short-lived connections; apps that don't handle failover well; enforcing IAM auth.
- Note: an RDS Proxy keeps connections open, which **prevents Aurora Serverless v2 from auto-pausing to 0 ACU**.

#### Blue/Green Deployments
- Creates a **green** staging copy of the production (**blue**) topology (including read replicas and Multi-AZ setting) kept in sync by replication (physical, or logical for some PostgreSQL cases).
- Change the green side: **major/minor engine upgrade**, parameter changes, instance class, storage file-system upgrade, schema changes that are replication-compatible.
- **Switchover** has guardrails (e.g., replication lag checks) and typically takes **under a minute**, with **no data loss**; endpoints/names are swapped so **applications need no changes**. The old blue instances are renamed `-old1` and kept.
- Engines: **RDS for MySQL, MariaDB, PostgreSQL** and **Aurora MySQL / Aurora PostgreSQL** (including Aurora Global Database). Works with RDS Proxy and AWS Advanced JDBC "smart" drivers to cut downtime further.
- **Exam pattern:** "Upgrade PostgreSQL 13 → 16 with minimal downtime and the ability to test first, with least operational effort" → Blue/Green Deployment (not manual read replica promotion, not DMS).

#### RDS Custom
- Managed database with **access to the underlying OS and database host** (SSH/SSM, sysadmin) for **Oracle** and **SQL Server** only.
- For legacy/packaged apps (e.g., Oracle E-Business Suite, apps needing custom agents, specific patches, OS-level config) that standard RDS can't host.
- You can pause RDS automation, make changes, then resume. More shared responsibility than RDS; less than EC2.
- Supports Multi-AZ (SQL Server), read replicas (Oracle). **Not supported with RDS Proxy (SQL Server)**.
- **Exam pattern:** "Needs OS-level access / custom software on the DB host but wants managed backups and automation" → RDS Custom. "Full control over everything, unsupported engine/version" → EC2 self-managed.

#### Monitoring & insights
- **CloudWatch metrics** (60 s), **Enhanced Monitoring** (OS-level metrics down to 1 s via an agent, delivered to CloudWatch Logs), **RDS events** to EventBridge/SNS, log exports to CloudWatch Logs.
- **Performance Insights → CloudWatch Database Insights.** Performance Insights (DB load, top SQL, wait events) has been folded into **CloudWatch Database Insights**, which has **Standard** and **Advanced** modes. AWS set **31 July 2026** as the end of the Performance Insights console experience; instances default to Database Insights Standard mode with their existing retention, and the PI API continues. Execution plans and on-demand analysis require **Advanced** mode. Exam questions may use either name: "identify the SQL causing high DB load / wait events" → Performance Insights / Database Insights.
- **Database Activity Streams** (Aurora, RDS for Oracle, RDS for SQL Server): near-real-time stream of DB activity to **Kinesis Data Streams**, encrypted with KMS, for compliance monitoring that DBAs cannot tamper with.
- **DevOps Guru for RDS**: ML-based anomaly detection and recommendations.

#### Pricing essentials
On-demand per instance-hour; **Reserved Instances** (1/3 years; size-flexible within a family for most open-source engines and BYOL Oracle); storage GB-month and provisioned IOPS; backup storage beyond 100% of DB size; cross-Region data transfer; Multi-AZ doubles instance cost. License Included vs **BYOL** (Oracle). A stopped instance restarts automatically after **7 days**. *Emerging (not core for SAP-C02):* **Database Savings Plans** (launched Dec 2025) give a spend-based commitment across Aurora, RDS, DynamoDB, ElastiCache (Valkey), DocumentDB, Neptune, Keyspaces, Timestream, DMS and OpenSearch — see [Chapter 16](16-Cost-Optimization-and-FinOps.md).

---

### 2.2 Amazon Aurora

#### Storage architecture (why Aurora behaves differently)
- Compute (DB instances) is **decoupled** from a shared, distributed **cluster volume**.
- The cluster volume keeps **six copies of the data across three AZs** (two per AZ). Writes use a **4-of-6 quorum**, reads a **3-of-6 quorum**: Aurora tolerates losing an entire AZ plus one more copy without losing data, and losing up to two copies without losing write availability.
- The volume is split into 10 GB segments that are continuously scrubbed and **self-healed** from peers. Only redo log records cross the network ("the log is the database"), which is why Aurora replication is so fast and has low write amplification.
- **Auto-grows** up to **128 TiB**, and **256 TiB** on newer Aurora MySQL/PostgreSQL versions (July 2025). Dynamic resizing gives space back when you drop tables. You pay only for what you use.
- Continuous, incremental backup to S3 — **no performance impact** and no backup window I/O freeze. Retention 1–35 days; PITR; snapshots.

#### Replicas, failover and endpoints
- **Up to 15 Aurora Replicas** sharing the same volume (no data copy, so adding a reader takes minutes regardless of DB size). Replica lag is typically well under a second (often < 100 ms).
- **Failover:** with at least one replica, service is typically restored in **< 60 seconds, often < 30 seconds**. With **no replica**, Aurora recreates the primary — typically **< 10 minutes**. Put replicas in different AZs.
- **Promotion tiers 0–15** (0 = highest priority). Same tier → the largest instance wins. Use tier 0/1 for a right-sized failover target; put reporting replicas in a low-priority tier (2–15).
- **Endpoints:**
  - **Cluster (writer) endpoint** — always points to the current writer.
  - **Reader endpoint** — DNS round-robin across readers (balances *connections*, not queries).
  - **Custom endpoints** — your own group of instances (e.g., large instances for analytics, small for the API). Default quota 5 per cluster.
  - **Instance endpoints** — direct to one instance (diagnostics, fine-grained routing).
  - **Global writer endpoint** — for Aurora Global Database, follows the primary Region after switchover/failover.
- **Aurora Auto Scaling** adds/removes replicas using target tracking (average CPU or connections) — not supported on Global Database secondary clusters.

#### Aurora Global Database
- **One primary Region (read/write) + up to 10 read-only secondary Regions** (raised from 5 in May 2025). Storage-level replication over dedicated infrastructure, **typically under 1 second** lag, minimal impact on the primary.
- Each secondary cluster can have up to **16 read-only instances** (the primary's readers plus secondary clusters can't exceed 15 combined when attaching). A **headless** secondary (no instances, storage only) minimises DR cost — you must add an instance before failing over to it.
- **RPO is typically seconds; RTO is typically minutes** (AWS marketing quotes "RPO of 1 second, RTO under 1 minute" as typical targets). For Aurora PostgreSQL you can **bound RPO** with `rds.global_db_rpo` (20 s minimum): commits block if *all* secondaries fall behind the target.
- **Switchover** (formerly *managed planned failover*): for healthy clusters — waits for full sync, so **RPO = 0**; keeps the topology; read/write recovery typically **< 30 seconds** on recent engine versions. Use for **regional rotation, follow-the-sun, and fail-back** after a disaster.
- **Managed failover** (unplanned, `failover-global-cluster --allow-data-loss`): promotes a secondary without waiting for sync (**RPO = replication lag**). Aurora attempts **write fencing** on the old primary, snapshots the old volume at the point of failure so you can recover lost writes, and **automatically re-adds the old primary Region as a secondary** when it recovers.
- **Manual "detach and promote"**: remove the secondary from the global cluster → standalone read/write cluster; used when managed failover isn't possible (e.g., mismatched engine versions). Breaks the global topology; you rebuild it.
- **Write forwarding**: secondaries forward write statements to the primary (with configurable read consistency: eventual, session, global) — lets apps in other Regions write without connection logic changes, at the cost of cross-Region latency.
- Limitations to remember: **no Backtrack**, no Aurora Auto Scaling on secondaries, all clusters same major/minor version for managed switchover/failover, can't stop individual clusters.

#### Aurora Serverless v2
- Capacity in **ACUs** (each ≈ **2 GiB memory** + corresponding CPU/network); scales in increments as small as **0.5 ACU** in place, without dropping connections.
- Range **0–256 ACU** on recent engine versions. **Minimum 0 ACU = automatic pause and resume** (Nov 2024): the instance pauses after a configurable idle period and resumes on the next connection (resume takes seconds — not for latency-critical first requests). No compute charge while paused; storage still billed. A proxy or anything holding connections open prevents pausing.
- **Mixed-configuration clusters**: provisioned writer + Serverless v2 readers or vice versa. Readers in **promotion tiers 0–1 scale with the writer** (always ready to take over); tiers 2–15 scale independently.
- Supports Multi-AZ (up to 15 readers), Global Database secondaries, RDS Proxy, IAM auth. **Aurora Serverless v1 is deprecated** — v1-only facts (Data API was v1-only originally; v1 scaled with pauses) are outdated; the RDS Data API now works with Serverless v2 and provisioned Aurora.
- **Exam pattern:** "Unpredictable / spiky / dev-test workload, minimise cost and management" → Serverless v2; "steady 24×7 heavy load" → provisioned + Reserved Instances.

#### Cloning
- **Copy-on-write** clone of the cluster volume: creates a new cluster in minutes regardless of size; you pay only for changed pages. Cross-account cloning via AWS RAM.
- Use for: test against production data, run destructive analytics, pre-upgrade testing. Faster and cheaper than snapshot restore.

#### Backtrack (Aurora MySQL only)
- **Rewinds the existing cluster in place** to an earlier time within a **target window of up to 72 hours**, in minutes, with no new cluster.
- Must be enabled **at cluster creation or snapshot restore**; whole-cluster only (not per table); brief disruption; not supported with Global Database; you can't create cross-Region read replicas from a backtrack-enabled cluster; not available for Aurora PostgreSQL.
- **Exam pattern:** "Developer ran DELETE without WHERE; restore Aurora MySQL in minutes without creating a new cluster or changing endpoints" → Backtrack. For Aurora PostgreSQL the answer is PITR (new cluster) or a clone.

#### Other Aurora features worth knowing
- **Parallel Query (Aurora MySQL):** pushes filtering/aggregation down to thousands of storage nodes — speeds up analytic queries on OLTP data without a separate warehouse (for heavy analytics, prefer zero-ETL to Redshift).
- **Aurora I/O-Optimized vs Aurora Standard:** Standard charges per million I/O requests; I/O-Optimized has no I/O charges but higher instance and storage prices. **Choose I/O-Optimized when I/O spend is ≥ 25% of total Aurora spend.** You can switch Standard → I/O-Optimized **once every 30 days** and back at any time.
- **Babelfish for Aurora PostgreSQL:** adds a **TDS endpoint** that understands **T-SQL** and the SQL Server wire protocol, so SQL Server applications can run against Aurora PostgreSQL with little code change. Use **Babelfish Compass** to assess compatibility. Answers "move off SQL Server licensing with minimal application changes".
- **Zero-ETL integration to Amazon Redshift:** near-real-time replication of Aurora MySQL/PostgreSQL (and RDS for MySQL/PostgreSQL/Oracle, DynamoDB) data into Redshift without building pipelines — answers "analytics on transactional data without ETL and without impacting the OLTP database" (link [Chapter 11](11-Analytics-Streaming-and-AI-ML.md)).
- **Integrations:** invoke Lambda from the DB, load from/save to S3, Aurora ML (SageMaker AI, Bedrock, Comprehend), pgvector for embeddings, Database Activity Streams, cluster cache management (Aurora PostgreSQL).
- **Aurora PostgreSQL Limitless Database** (GA late 2024): automated **horizontal sharding** behind a single endpoint — a *DB shard group* of routers and shards, **sharded tables** (distributed by a shard key) and **reference tables** (replicated to all shards), serverless scaling — for **millions of write transactions per second** and petabytes. Answers "relational, PostgreSQL, write throughput beyond a single writer, avoid building app-level sharding".
- **Amazon Aurora DSQL** (GA May 2025): **serverless, distributed, PostgreSQL-compatible** database with **active-active** single- and multi-Region clusters, strong consistency, optimistic concurrency control, and **99.99% single-Region / 99.999% multi-Region** availability. Multi-Region clusters must stay within one Region set (North America, Europe, Asia Pacific). Not every PostgreSQL feature is supported (check compatibility). Treat as *emerging* for SAP-C02 — it may appear as a distractor or as the answer to "active-active multi-Region relational with strong consistency and no failover".

---

### 2.3 Amazon DynamoDB

#### Data model & partitioning
- Serverless key-value / document store. Tables have a **primary key**: partition key (PK) alone, or PK + sort key (SK). Items ≤ **400 KB** (including attribute names). Larger objects → store in **S3 and keep a pointer** in DynamoDB.
- DynamoDB hashes the PK to place items on **partitions**. Each partition supports up to **3,000 RCU and 1,000 WCU** (and ~10 GB). Throughput is spread across partitions, so **a skewed key distribution creates hot partitions** that throttle even when table-level capacity is unused.
- **Adaptive capacity** automatically gives hot partitions more of the table's throughput and **isolates frequently accessed items** (splits partitions for heat) — it mitigates, but cannot fix, a single key receiving more than per-partition limits.
- **Good PK design:** high cardinality and evenly accessed (userId, orderId, deviceId). **Bad:** status, date, country, "tenant" with one giant tenant.
- **Write sharding:** append a random or calculated suffix (`2026-10-17#7`) to spread a hot logical key across N partitions; reads scatter-gather across suffixes.

#### Capacity modes

| | **On-demand** | **Provisioned** |
|---|---|---|
| Billing | Per request (RRU/WRU) | Per provisioned RCU/WCU per hour |
| Scaling | Instant, accommodates up to double the previous peak instantly; scales further over time | Manual or **auto scaling** (target tracking on utilisation, reacts in minutes) |
| Best for | Unknown, spiky, new, or low-utilisation workloads; "least operational overhead" | Predictable, steady traffic; cost-optimise with **reserved capacity** (1- or 3-year, provisioned mode only) |
| Throttling protection | Table-level max throughput (optional cap), **warm throughput** to pre-warm for launches | Burst capacity (up to 300 s of unused capacity), auto scaling |

- **Capacity math:** 1 RCU = one strongly consistent read/s of up to 4 KB, or two eventually consistent reads/s; transactional reads cost 2×. 1 WCU = one write/s of up to 1 KB; transactional writes cost 2×.
- Table classes: **Standard** vs **Standard-Infrequent Access** (≈60% lower storage cost, higher request cost) — choose IA when storage dominates the bill.
- Default quotas: 40,000 RCU/WCU per table and 80,000 per account (provisioned), adjustable — not hard limits.

#### Secondary indexes

| | **Global Secondary Index (GSI)** | **Local Secondary Index (LSI)** |
|---|---|---|
| Key | Any PK and optional SK (different from base table) | **Same PK** as table, different SK |
| When created | Any time (add/delete online) | **Only at table creation** |
| Quota | **20 per table** (default, adjustable) | **5 per table** |
| Consistency | **Eventually consistent only** | Eventually **or strongly** consistent |
| Capacity | **Own** RCU/WCU (throttled GSI writes back-pressure the base table) | Shares base table capacity |
| Size limit | None | **10 GB per partition-key value** (item collection) |
| Scope | Entire table (across partitions) | Within a partition |

Projection: `KEYS_ONLY`, `INCLUDE`, `ALL`. **Sparse indexes** (only items that have the index key attribute) are a cheap way to index a subset ("open orders"). **GSI overloading** — a generic `GSI1PK/GSI1SK` reused by many entity types — is a single-table-design technique.

#### Consistency, transactions, PartiQL
- Reads are **eventually consistent by default**; `ConsistentRead=true` for strongly consistent reads (not on GSIs, not across Regions for MREC global tables).
- **Transactions** (`TransactWriteItems`, `TransactGetItems`): ACID across up to **100 items / 4 MB** in one Region, possibly across tables; cost 2×; idempotency tokens. Use for "debit one account and credit another atomically".
- **Conditional writes** and optimistic locking (version attribute) for concurrency control.
- **PartiQL**: SQL-compatible syntax for DynamoDB operations — does not add joins or change the performance model (a PartiQL `SELECT` without a key condition is still a scan).

#### Streams and change data capture

| | **DynamoDB Streams** | **Kinesis Data Streams for DynamoDB** |
|---|---|---|
| Retention | **24 hours** | Up to **365 days** (Kinesis retention) |
| Ordering / duplicates | Strict per-item ordering, exactly-once delivery to the stream | Per-item ordering may differ; **possible duplicates** — use timestamps/version to dedupe |
| Consumers | ≤ 2 simultaneous readers per shard (1 recommended for global tables); Lambda, KCL adapter | Many consumers, **enhanced fan-out**, Firehose, Managed Service for Apache Flink |
| Use | Triggers (Lambda), replication, aggregation, audit | Longer retention, analytics pipelines, many downstream consumers |

Stream view types: `KEYS_ONLY`, `NEW_IMAGE`, `OLD_IMAGE`, `NEW_AND_OLD_IMAGES`. Lambda event filtering reduces invocations.

#### Global tables
- Multi-Region, **multi-active** replication: each replica accepts reads and writes. **99.999% availability SLA** (vs 99.99% single-Region). Use version **2019.11.21 (current)**.
- **Multi-Region eventual consistency (MREC)** — the default: asynchronous replication, typically ≤ 1 second; **last-writer-wins** per item based on internal timestamp; strongly consistent reads are only consistent for writes made in the same Region; RPO = replication delay (seconds); add/remove replicas any time; transactions are atomic only in the originating Region.
- **Multi-Region strong consistency (MRSC)** (GA June 2025): writes **synchronously replicate to at least one other Region** before success; strongly consistent reads on any replica return the latest data; **RPO = 0**. Must use **exactly three Regions** — three replicas, or **two replicas + one witness** (the witness stores recent data for quorum, can't be read/written, and carries no storage/write charges). Restrictions: create from an **empty table**, can't add/remove a single replica later, **no transactions, no TTL, no LSIs**; writes to an item being modified in another Region fail with `ReplicatedWriteConflictException` (retryable); higher write latency.
- Global-table writes **bypass DAX** in other Regions — DAX caches there become stale until TTL expiry.
- Replication consumes write capacity in every replica Region (replicated WCU) — size provisioned capacity/auto scaling for it.

#### TTL
Per-item epoch-seconds attribute; expired items are deleted in the background **at no WCU cost**, usually within a few days of expiry (so filter expired items in queries if exactness matters). TTL deletes appear in Streams as service deletions (archive them to S3 via Lambda/Firehose). Not supported on MRSC global tables.

#### Backup, restore, export/import
- **PITR:** continuous backups with per-second granularity for the last **35 days** (configurable recovery period **1–35 days**). Restores always create a **new table** (also cross-Region). Settings like auto scaling, alarms, IAM policies, TTL and tags must be re-applied.
- **On-demand backups:** full backups kept until deleted, no performance impact. Through **AWS Backup** you gain cross-account/cross-Region copy, lifecycle to cold storage, and Vault Lock.
- **Export to S3:** full or **incremental** export from PITR data — **consumes no read capacity**, DynamoDB JSON or Amazon Ion; query with Athena. **Import from S3** (CSV, DynamoDB JSON, Ion) creates a **new table** without consuming WCU.
- **Zero-ETL integrations** to Amazon Redshift and Amazon OpenSearch Service for analytics/search on DynamoDB data.

#### DynamoDB Accelerator (DAX)
- In-VPC, **write-through**, DynamoDB-API-compatible cache — **microsecond** read latency for eventually consistent reads; minimal code change (swap the client).
- Two caches: **item cache** (GetItem/BatchGetItem) and **query cache** (Query/Scan result sets). Default TTL 5 minutes each. Updates to items **do not invalidate query-cache results** until TTL expiry. Negative results are cached.
- **Strongly consistent reads and transactional reads pass through** to DynamoDB and are not cached. Writes go through DAX synchronously to DynamoDB, so DAX adds write latency — **not useful for write-heavy** workloads (use write-around for bulk loads).
- Cluster of nodes (use ≥ 3 across AZs); one primary + read replicas; scales up/out; encryption at rest/in transit.
- **DAX vs ElastiCache:** DAX for DynamoDB read-heavy workloads with no cache-logic code; ElastiCache for caching anything (RDS query results, computed objects, sessions), richer data structures, or cross-service caching.

#### Security & fine-grained access
- **IAM** identity policies, and **resource-based policies** on tables/streams/indexes (2024) for cross-account access.
- **Fine-grained access control** with IAM condition keys: **`dynamodb:LeadingKeys`** restricts access to items whose partition key equals the caller's identity (e.g., `${cognito-identity.amazonaws.com:sub}` or `${aws:PrincipalTag/tenant}`), and **`dynamodb:Attributes`** limits which attributes can be read/written. Classic pattern: mobile users via Cognito identity pools can only access their own rows; SaaS tenant isolation in a pooled table.
- Encryption at rest is always on: AWS owned key (default), AWS managed key, or **customer managed key** (needed for key-policy control/cross-account auditing).
- Private access via **VPC gateway endpoint** (free) or interface endpoint (PrivateLink, for on-premises access over DX/VPN).

#### Single-table design (Professional depth)
Model **access patterns first**, then keys. Store multiple entity types in one table with composite keys (`PK=CUSTOMER#123`, `SK=ORDER#2026-10-17#987`) so one `Query` returns a customer and their orders (pre-joined item collection). Use overloaded GSIs for alternate access patterns and **adjacency lists** for many-to-many. Trade-offs: very efficient and cheap at scale, but harder to evolve and to run ad-hoc analytics (export to S3 / zero-ETL for analytics). Multi-table designs are fine when access patterns are independent or teams own separate services.

---

### 2.4 Amazon ElastiCache

#### Engines

| Feature | **Valkey / Redis OSS** | **Memcached** |
|---|---|---|
| Data structures | Strings, hashes, lists, sets, sorted sets, bitmaps, HyperLogLog, geospatial, streams; Valkey 8.x adds vector search, Bloom filters | Simple strings/objects |
| Threading | Mostly single-threaded command execution (I/O threading in newer versions) | **Multi-threaded** — uses many cores per node |
| Replication & HA | Yes — replicas, **Multi-AZ with automatic failover** | **No replication**; node loss = data loss for that slice |
| Persistence / backup | Snapshots (RDB) and restore | Node-based: none (serverless caches support backup) |
| Partitioning | Cluster mode enabled (shards) | Client-side consistent hashing across nodes |
| Pub/Sub, transactions, Lua/Functions | Yes | No |
| Cross-Region | **Global Datastore** | No |
| Auth | AUTH token, **RBAC** users/ACLs, **IAM authentication** | SASL (in-transit encryption from 1.6.12) |
| Choose when | You need HA, persistence, rich data types, sorted-set leaderboards, pub/sub, sessions that must survive node failure | Simplest object cache, scale out/in freely, multithreaded large nodes, losing cache is acceptable |

**Valkey** is the Linux Foundation fork of Redis OSS; ElastiCache for Valkey is priced lower than Redis OSS and is the AWS-recommended default for new Redis-compatible caches. Exam questions may still say "ElastiCache for Redis" — treat as equivalent. (Newer Valkey releases on ElastiCache add options such as full-text/vector search and a durability mode; these are beyond SAP-C02 scope.)

#### Cluster modes (Valkey/Redis OSS)
- **Cluster mode disabled:** **one shard** (1 primary + up to 5 replicas). Scale reads by adding replicas; scale writes/memory only vertically. Simple clients; multiple logical databases.
- **Cluster mode enabled:** data partitioned across **many shards** (up to 500 shards, subject to node quotas), each with a primary + up to 5 replicas; **online resharding**; scale writes and memory horizontally. Automatic failover **required**. Client must be cluster-aware.
- **Multi-AZ with automatic failover**: a replica in another AZ is promoted if the primary fails (typically well under a minute); primary endpoint DNS updates automatically.
- **Data tiering** (r6gd nodes): keeps hot data in memory, colder data on local SSD — cheaper for large datasets with skewed access.

#### Global Datastore (Valkey/Redis OSS)
- One **primary (active) cluster** replicates asynchronously to **secondary (passive) read-only clusters in up to two other Regions** (typically sub-second lag).
- **No automatic cross-Region failover** — you **manually promote** a secondary. Node-based clusters only (not serverless); same node type/shard count across Regions; same account only.
- Use for: local-latency reads in multiple Regions, cross-Region DR for the cache/session tier.

#### ElastiCache Serverless
- Create a cache with no node/shard sizing; scales compute and memory automatically; **Multi-AZ replication by default**, 99.99% availability SLA. Available for Valkey, Redis OSS and Memcached. Billed per GB-hour of data stored and **ElastiCache Processing Units (ECPUs)**.
- Answers "cache for an unpredictable workload with least operational overhead". Not compatible with Global Datastore.

#### Caching patterns

| Pattern | How it works | Pros | Cons |
|---|---|---|---|
| **Lazy loading / cache-aside** | App reads cache → on miss, reads DB and populates cache | Only requested data cached; cache failure isn't fatal | Miss penalty (3 trips); stale data until TTL/invalidation |
| **Write-through** | App writes DB and cache together | Cache always fresh for written data | Write penalty; caches data that may never be read (combine with TTL) |
| **Write-behind (write-back)** | App writes cache; async flush to DB | Fast writes, absorbs bursts | Risk of data loss; complex — rarely the exam answer |
| **TTL** | Expire entries after N seconds | Bounds staleness, frees memory | Too short = low hit rate; synchronized expiry → stampede |
| **Session store** | Externalize HTTP session state to Valkey/Redis (or DynamoDB) | Stateless web tier, no sticky sessions, Auto Scaling friendly | Must be HA (replicas, Multi-AZ) |

- **Thundering herd / cache stampede:** many clients miss the same hot key simultaneously (e.g., after expiry or a cold cache) and all hammer the database. Mitigations: **add random jitter to TTLs**, request coalescing / a lock so one caller refreshes ("single flight"), proactive refresh before expiry, pre-warming after deployment, and keeping stale-while-revalidate copies.
- Cache invalidation via DynamoDB Streams or RDS events/CDC → Lambda deleting keys, for near-real-time consistency.

### 2.5 Amazon MemoryDB
- **Durable**, Valkey/Redis OSS-compatible **in-memory primary database**: data is committed to a **Multi-AZ transactional log** before acknowledgement, so it survives node failures with no data loss; microsecond reads, single-digit-millisecond writes.
- Use it when the stem wants Redis data structures **as the system of record** (not just a cache): e.g., leaderboards, session/state stores, real-time inventory, where losing data on failover is unacceptable. ElastiCache = cache in front of a database; MemoryDB = the database.
- **MemoryDB Multi-Region** (GA Dec 2024, Valkey): active-active across up to five Regions with async replication (typically < 1 s) and automatic conflict resolution, up to 99.999% availability.
- Supports vector search, data tiering, snapshots.

---

### 2.6 Purpose-built databases

#### Amazon DocumentDB (with MongoDB compatibility)
- Managed JSON document database implementing the MongoDB API (several MongoDB API compatibility versions, such as 4.0 and 5.0; check the current list). Aurora-like architecture: storage replicated **six ways across three AZs**, up to **15 replicas**, auto-growing storage.
- **Global clusters:** one primary + **up to 10 read-only secondary Regions**, typically < 1 s lag, RTO typically under a minute, RPO seconds; switchover/failover supported.
- **Elastic clusters:** **sharded** DocumentDB that scales writes and storage horizontally (millions of reads/writes per second, petabytes) — for when one writer isn't enough.
- Migration: DMS (full load + CDC) or `mongodump`/`mongorestore`. Not every MongoDB feature is supported — check compatibility.
- Answer for "migrate MongoDB to a managed service with minimal code changes".

#### Amazon Neptune
- Managed **graph** database: property graph (Apache TinkerPop **Gremlin**, **openCypher**) and RDF (**SPARQL**). Six-way storage across 3 AZs, up to 15 read replicas, **Neptune Serverless**, **Neptune Global Database** (up to 5 secondary Regions), and **Neptune Analytics** (in-memory graph analytics, vector search for GraphRAG).
- Use cases: **fraud rings, social networks, recommendations, knowledge graphs, identity graphs, network topology** — any stem about "relationships many hops deep" where SQL joins explode.

#### Amazon Keyspaces (for Apache Cassandra)
- **Serverless**, Cassandra-compatible (CQL) wide-column database. On-demand or provisioned capacity, data replicated 3× across AZs, PITR (35 days), encryption, **multi-Region replication** (active-active, last-writer-wins).
- Answer for "migrate an on-premises Cassandra cluster and stop managing nodes, keep CQL drivers".

#### Amazon Timestream
- **Timestream for LiveAnalytics** (serverless time-series) **closed to new customers on 20 June 2025**; existing customers can continue. AWS recommends **Amazon Timestream for InfluxDB** (managed InfluxDB, single-digit-millisecond queries) for new time-series workloads.
- Exam questions written earlier may still present Timestream as "the time-series database for IoT/telemetry/DevOps metrics" — it is still the correct *category* answer; know the availability change.

#### Amazon QLDB (retired)
- Amazon Quantum Ledger Database (immutable, cryptographically verifiable journal) **reached end of support on 31 July 2025**. AWS's migration guidance is **Aurora PostgreSQL** (with audit tooling such as pgAudit, Database Activity Streams, and S3 for history). Older questions may still list QLDB for "immutable, verifiable ledger of changes owned by a central authority"; on the real exam choose it only if it is clearly the only ledger option offered. For decentralized multi-party trust, the historical answer was Amazon Managed Blockchain.

#### Amazon Redshift (brief)
Columnar, MPP **data warehouse** for OLAP: complex aggregations over TB–PB, Redshift Serverless, RA3 managed storage, Spectrum for S3, data sharing, **zero-ETL** from Aurora/RDS/DynamoDB. If the stem says "analytics/BI on historical data", it is not an OLTP database question — see [Chapter 11](11-Analytics-Streaming-and-AI-ML.md).

#### Amazon OpenSearch Service (brief)
**Search and log analytics** (full-text search, fuzzy matching, relevance, aggregations, vector search). Common pattern: DynamoDB/Aurora as system of record → Streams/CDC or **zero-ETL** → OpenSearch for search. Not a primary transactional store.

---

### 2.7 Migration & modernization angles (D4 — details in [Chapter 13](13-Migration-and-Modernization.md))
- **Homogeneous** (Oracle → RDS for Oracle, MySQL → Aurora MySQL): native tools (Data Pump, `mysqldump`, Percona XtraBackup → Aurora MySQL from S3, pg_dump), or **DMS full load + CDC** for minimal downtime. Aurora MySQL can be created from an RDS MySQL snapshot or as an **Aurora read replica of RDS MySQL/PostgreSQL** then promoted — near-zero-downtime path from RDS to Aurora.
- **Heterogeneous** (Oracle/SQL Server → Aurora PostgreSQL/MySQL): **AWS SCT** or **DMS Schema Conversion** converts schema and code; **DMS** moves data with CDC. Expect stored-procedure rewrite effort.
- **SQL Server → Aurora PostgreSQL with minimal app change:** **Babelfish** (T-SQL + TDS endpoint).
- **Relational → DynamoDB:** model access patterns first; DMS supports DynamoDB as a target; large one-off loads via S3 + **Import from S3**.
- **Unsupported customizations** (OS access, third-party agents on DB host) → **RDS Custom** or EC2.
- **Database Freedom** drivers: licence cost (Oracle/SQL Server Enterprise), scaling limits, operational toil.
- Large initial loads with limited bandwidth: Snowball Edge + DMS (see [Chapter 08](08-Storage-and-Data-Transfer.md)).

---

## 3. Architecture patterns

### Pattern 1 — Serverless API with RDS Proxy in front of Aurora
```text
 Clients ──> API Gateway ──> Lambda (thousands of concurrent invocations)
                                 │  IAM auth token (no DB password in code)
                                 ▼
                        ┌──────────────────┐   pooled + multiplexed
                        │   RDS Proxy      │── connections (few dozen) ──┐
                        │ (2+ AZs, same VPC│                             ▼
                        │  as the DB)      │              ┌─────────────────────────┐
                        └──────────────────┘              │ Aurora cluster          │
                          │ read-only proxy endpoint ───> │ writer (AZ-a)           │
                          │                               │ reader tier0 (AZ-b)     │
                          └─ Secrets Manager creds        │ reader tier2 (AZ-c)     │
                                                          └─────────────────────────┘
```
**When:** Lambda/containers scaling out cause `too many connections` errors or connection storms; you want faster, connection-preserving failover. **Trade-offs:** proxy cost (per vCPU/ACU), pinning reduces the benefit, and the proxy stops Serverless v2 from pausing. Alternatives: RDS Data API (HTTP, no connection management), or DynamoDB if the data model allows.

### Pattern 2 — Aurora Global Database for cross-Region DR and local reads
```text
        Region A (primary)                          Region B (secondary)
 ┌─────────────────────────────┐   storage-level   ┌─────────────────────────────┐
 │ App ──> global writer endpt │   replication     │ App (reads local; writes via│
 │ Aurora writer + 2 readers   │ ═══ < 1 s lag ══> │ write forwarding or global  │
 │ cluster volume (6 copies)   │                   │ writer endpoint)            │
 └─────────────────────────────┘                   │ 1-16 readers (or headless)  │
                                                   └─────────────────────────────┘
 Planned rotation / fail-back ──> SWITCHOVER (sync first, RPO 0)
 Region outage               ──> MANAGED FAILOVER (--allow-data-loss, RPO = lag),
                                 old primary auto re-added as secondary later
```
**When:** RPO of seconds and RTO of minutes for a relational workload, or global low-latency reads. **Trade-offs:** cost of replicated storage/instances and cross-Region transfer; write latency for forwarded writes; applications must use the global writer endpoint (or update DNS) and handle reconnects. Cheaper tiers: headless secondary (pilot light), cross-Region automated backups or snapshot copies (backup and restore).

### Pattern 3 — Multi-Region active-active with DynamoDB global tables
```text
   Route 53 latency routing / Route 53 ARC routing controls
        │                     │
   Region A                Region B                (Region C or witness for MRSC)
 ┌──────────┐            ┌──────────┐
 │ API +    │            │ API +    │
 │ Lambda   │            │ Lambda   │
 └────┬─────┘            └────┬─────┘
      ▼   MREC: async, LWW    ▼
 ┌──────────┐  <══════════> ┌──────────┐
 │ Replica  │               │ Replica  │
 └──────────┘               └──────────┘
```
**When:** users in several Regions write locally, and a Region failure must not stop writes. Use **MREC** for the lowest latency, and design for last-writer-wins: write each item from one "home" Region, or use idempotent/commutative updates. Use **MRSC** when you need RPO 0 and strongly consistent reads everywhere and can accept higher write latency and feature restrictions.

### Pattern 4 — Cache-aside in front of RDS (read-heavy catalogue)
```text
  App ──1─> ElastiCache (Valkey, Multi-AZ, cluster mode enabled)
   │  hit? return
   │  miss ──2─> Aurora reader endpoint ──3─> SET key value EX (300 + jitter)
   └─ writes ──> Aurora writer ──> (optional) DEL key / CDC → Lambda invalidation
```
**When:** the same queries repeat, database CPU is dominated by reads, and the latency SLO is in single-digit milliseconds. **Trade-offs:** stale reads (bounded by TTL), cache-miss penalty, one more component. Add TTL jitter to prevent stampedes. Use replicas and Multi-AZ so a node loss doesn't push the full load onto the database.

### Pattern 5 — CQRS / derived views from DynamoDB
```text
 Writes ──> DynamoDB (system of record, single-table design)
               │ DynamoDB Streams (24 h)            │ zero-ETL / export to S3
               ▼                                    ▼
          Lambda (filtered) ──> OpenSearch (search)   Redshift / Athena (analytics)
               └──> EventBridge (domain events) ──> other microservices
```
**When:** OLTP access patterns are key-based, but the business also needs full-text search, ad-hoc analytics or event-driven integration. **Trade-offs:** the read models are eventually consistent, and you must operate idempotent consumers.

### Pattern 6 — Workload isolation with Aurora custom endpoints
```text
 OLTP app ──> cluster endpoint ──> writer (r7g.2xlarge)
 Web reads ─> custom endpoint "web"  ──> readers R1,R2 (r7g.large, tier 0/1)
 BI/reports > custom endpoint "olap" ──> reader R3 (r7g.4xlarge, tier 15, last-resort failover target)
```
**When:** reporting queries degrade OLTP, and you want different instance sizes per workload without a second database. **Alternatives:** an Aurora clone for one-off heavy analytics; zero-ETL to Redshift for sustained BI.

### Pattern 7 — Low-downtime major version upgrade with Blue/Green
```text
 Blue (prod, PG 13, Multi-AZ + replica) ──replication──> Green (PG 16 copy, same topology)
        │                                                   │ test, tune parameters
        └──────── switchover (guardrails, typically < 1 min) ┘
 endpoints/names swapped → app unchanged; old blue kept as "-old1" for comparison
```
**When:** engine upgrades, static parameter changes or instance class changes, with minimal downtime and a test window first. **Trade-offs:** double cost while both environments run; some DDL/replication limitations; writes on green during testing can break replication.

### Pattern 8 — Hot-key write sharding in DynamoDB
```text
 Logical key: "VOTES#candidateA"  (100k writes/s — exceeds one partition)
 Write: PK = "VOTES#candidateA#" + rand(0..N-1)  → spreads across N partitions
 Read : Query N suffixes in parallel → sum (or a periodic aggregator writes a total item)
```
**When:** a key is inherently hot (counters, voting, one very large tenant). **Trade-offs:** read amplification and aggregation logic. Alternatives: buffer writes in SQS/Kinesis and aggregate in batches; cache reads with DAX.

---

## 4. Decision tables / "X vs Y"

### 4.1 Database selection decision tree
```text
What is the data model / access pattern?
├─ Relational, joins, ACID, SQL
│   ├─ Need OS/host access (Oracle/SQL Server)? ............ RDS Custom (or EC2)
│   ├─ Commercial engine, keep licence/features? ........... RDS for Oracle / SQL Server / Db2
│   ├─ MySQL/PostgreSQL, highest availability & scale ...... Aurora (provisioned or Serverless v2)
│   ├─ Spiky/idle workload, minimal ops .................... Aurora Serverless v2 (min 0 ACU)
│   ├─ Writes exceed one writer (PostgreSQL) ............... Aurora Limitless Database
│   ├─ Active-active multi-Region, strong consistency ...... Aurora DSQL (emerging)
│   └─ Cross-Region DR, RPO seconds ........................ Aurora Global Database
├─ Key-value / simple lookups at any scale, serverless ..... DynamoDB (+ DAX for µs reads)
├─ Document (JSON), MongoDB API ............................ DocumentDB (elastic clusters for sharding)
├─ Wide-column, Cassandra/CQL .............................. Keyspaces
├─ Graph (relationships, many hops) ........................ Neptune
├─ Time-series (IoT, metrics) .............................. Timestream for InfluxDB (LiveAnalytics: existing customers only)
├─ Immutable ledger ........................................ (QLDB retired 2025) → Aurora PostgreSQL + audit design
├─ In-memory
│   ├─ Cache in front of a DB, sessions .................... ElastiCache (Valkey/Redis OSS; Memcached for simple)
│   └─ Durable in-memory primary database .................. MemoryDB
├─ Full-text search, log analytics ......................... OpenSearch Service
└─ Analytics / data warehouse (OLAP) ....................... Redshift (Athena on S3 for ad hoc)
```

### 4.2 RDS and Aurora HA and read options

| Need | Multi-AZ DB instance | Multi-AZ DB cluster | Read replica (same Region) | Cross-Region read replica | Aurora replicas |
|---|---|---|---|---|---|
| Protects against AZ failure | Yes (auto) | Yes (auto) | Manual promote | Manual promote | Yes (auto) |
| Serves reads | No | Yes (2 readers) | Yes | Yes (remote) | Yes (up to 15) |
| Replication | Sync | Semisync | Async | Async | Shared storage (ms lag) |
| Failover time | 60–120 s | < 35 s typical | Minutes (manual) | Minutes (manual) | < 60 s, often < 30 s |
| Data loss on failover | None | None (acknowledged by ≥ 1 reader) | Possible (lag) | Possible (lag) | None (shared volume) |
| Engines | All RDS | MySQL, PostgreSQL | All RDS (cascading limits vary) | All RDS engines | Aurora |

### 4.3 Cross-Region DR options by database (detail in [Chapter 12](12-Resilience-HA-and-Disaster-Recovery.md))

| Database | Backup & restore | Pilot light / warm standby | Hot / active-active | Typical RPO / RTO (best option) |
|---|---|---|---|---|
| RDS | Cross-Region snapshot copy; cross-Region automated backups (PITR in DR Region) | Cross-Region read replica (promote) | — (no multi-writer) | RPO seconds–minutes / RTO minutes (replica) |
| Aurora | Snapshot copy | Global Database, headless or small secondary | Global Database + write forwarding; Aurora DSQL for true active-active | RPO ~1 s (0 for switchover) / RTO ~1 min to minutes |
| DynamoDB | PITR cross-Region restore; AWS Backup copy | — | Global tables MREC (RPO seconds) / MRSC (RPO 0) | RPO 0–seconds / RTO ≈ routing change |
| ElastiCache | Snapshot export/copy | Global Datastore (manual promote) | — | Seconds / minutes |
| DocumentDB | Snapshot copy | Global cluster | — | RPO seconds / RTO < 1 min typical |
| Neptune | Snapshot copy | Neptune Global Database | — | Seconds / minutes |
| Keyspaces | PITR | — | Multi-Region replication | Seconds / routing change |
| MemoryDB | Snapshots | — | MemoryDB Multi-Region | < 1 s typical / routing change |

### 4.4 Read-scaling vs write-scaling options

| Goal | Options (roughly in order of least effort) |
|---|---|
| **Scale reads (relational)** | Cache (ElastiCache) → read replicas / Aurora replicas + reader endpoint + replica Auto Scaling → custom endpoints for workload isolation → Global Database secondaries for remote users → zero-ETL to Redshift for analytics |
| **Scale writes (relational)** | Bigger instance (vertical) → faster storage (io2, Aurora I/O-Optimized for cost) → batch and queue writes (SQS load leveling) → Aurora Limitless (PostgreSQL) or application sharding → move hot access patterns to DynamoDB |
| **Scale reads (DynamoDB)** | Eventually consistent reads (half the cost) → DAX → GSIs for alternate keys → global tables for local reads |
| **Scale writes (DynamoDB)** | On-demand or higher WCU → better partition key → write sharding → batch writes and SQS buffering → global tables for multi-Region writes |
| **Scale connections** | RDS Proxy → connection pooling in the app → Data API → cap Lambda concurrency (reserved concurrency) |

### 4.5 DynamoDB on-demand vs provisioned vs reserved

| Signal in the stem | Choose |
|---|---|
| New app, unknown traffic, spiky, "no capacity planning" | On-demand |
| Steady, predictable, high utilisation | Provisioned + auto scaling |
| Steady baseline committed for 1–3 years, minimise cost | Provisioned + **reserved capacity** |
| Predictable daily peaks (e.g., a 9:00 surge) | Provisioned + scheduled scaling (Application Auto Scaling), or on-demand with warm throughput |
| Large launch event expected | Pre-warm (warm throughput) or raise provisioned capacity in advance |

### 4.6 DAX vs ElastiCache vs MemoryDB

| | DAX | ElastiCache (Valkey/Redis OSS) | ElastiCache Memcached | MemoryDB |
|---|---|---|---|---|
| Role | Cache for DynamoDB only | General cache / sessions / pub-sub | Simple object cache | **Durable** primary in-memory DB |
| Code change | Minimal (DAX client) | App implements cache logic | App implements cache logic | Use as the database |
| Latency | µs reads | sub-ms | sub-ms | µs reads, single-digit ms writes |
| HA | Multi-node, multi-AZ | Replicas, Multi-AZ, Global Datastore | None (node-based) | Multi-AZ transaction log, Multi-Region |
| Durability | Cache | Cache (snapshots) | None | Durable |

### 4.7 Point-in-time recovery and copy options

| Need | Aurora MySQL | Aurora PostgreSQL | RDS | DynamoDB |
|---|---|---|---|---|
| Undo a mistake in minutes, same endpoint | **Backtrack** (≤ 72 h, enable at creation) | — | — | — |
| Restore to any second (new resource) | PITR (1–35 days) | PITR | PITR (1–35 days) | PITR (1–35 days, new table) |
| Copy of prod for testing | **Clone** (copy-on-write) | **Clone** | Snapshot restore / Blue/Green | PITR restore / export |
| Long-term retention | Manual snapshots / AWS Backup | Same | Same | On-demand backups / AWS Backup |

### 4.8 Aurora vs RDS (when the stem lets you choose)

| Criterion | RDS (MySQL/PostgreSQL) | Aurora |
|---|---|---|
| Cost at small, steady scale | Usually lower | Higher instance price; Serverless v2 can be cheaper for spiky loads |
| Storage HA | EBS in one AZ (+ standby copy if Multi-AZ) | 6 copies across 3 AZs, always |
| Replicas | Up to 15, async, each with its own storage | Up to 15, shared storage, ms lag, auto scaling |
| Failover | 60–120 s (instance) / < 35 s (cluster) | < 60 s, often < 30 s |
| Cross-Region | Read replicas | Global Database (< 1 s lag, managed switchover/failover) |
| Extras | Broader engine and version choice | Backtrack, cloning, parallel query, Serverless v2, Limitless, Babelfish |

---

## 5. Exam keyword → answer cheat list

| Keyword / phrase in the stem | Likely answer |
|---|---|
| "Lambda functions exhaust database connections" | **RDS Proxy** |
| "Reduce failover time and keep connections open" | RDS Proxy |
| "Standby that can also serve reads, failover < 35 s, MySQL/PostgreSQL" | **Multi-AZ DB cluster** |
| "Offload reporting queries" | Read replica / Aurora reader or **custom endpoint** |
| "Cross-Region DR, RPO ~1 s, RTO ~1 min, relational" | **Aurora Global Database** |
| "Planned Region rotation without data loss" | Aurora Global Database **switchover** |
| "Region outage, promote secondary now, accept some data loss" | Global Database **managed failover** (`--allow-data-loss`) |
| "Writes from secondary Region without app connection changes" | Aurora **write forwarding** |
| "Minimise DR cost but keep Aurora replicated" | **Headless** secondary cluster |
| "Restore Aurora MySQL in minutes after bad DELETE, no new cluster" | **Backtrack** |
| "Test against production data quickly and cheaply" | **Aurora clone** |
| "Major version upgrade, minimal downtime, test first" | **Blue/Green Deployments** |
| "Unpredictable / intermittent relational workload, pay only when used" | **Aurora Serverless v2** (min 0 ACU) |
| "I/O charges are a large portion of the Aurora bill" | **Aurora I/O-Optimized** (≥ 25% rule) |
| "SQL Server app to open source with minimal code change" | **Babelfish for Aurora PostgreSQL** |
| "Analytics on OLTP data without ETL pipelines" | **Zero-ETL integration with Redshift** |
| "Needs OS access to the Oracle/SQL Server host" | **RDS Custom** |
| "Encrypt an existing unencrypted RDS database" | Snapshot → **encrypted copy** → restore (or DMS) |
| "Share an encrypted snapshot with another account" | Re-encrypt with a **customer managed KMS key**; share key + snapshot |
| "Database credentials without passwords in code" | **IAM DB authentication** (+ Secrets Manager rotation otherwise) |
| "Use corporate Active Directory credentials for the DB" | **Kerberos** with AWS Managed Microsoft AD |
| "Find the SQL causing high DB load / wait events" | **Performance Insights / CloudWatch Database Insights** |
| "Tamper-proof audit of DB activity for compliance" | **Database Activity Streams** |
| "Key-value, single-digit ms at any scale, serverless" | **DynamoDB** |
| "Microsecond reads for DynamoDB, minimal code change" | **DAX** |
| "Hot partition / throttling with spare table capacity" | Better **partition key** / **write sharding** |
| "Multi-Region active-active key-value" | **DynamoDB global tables** (MREC) |
| "Multi-Region with RPO 0 and strongly consistent reads (key-value)" | Global tables **MRSC** (3 Regions, or 2 + witness) |
| "Users may only access their own items" | IAM condition **`dynamodb:LeadingKeys`** |
| "Expire session/ephemeral items automatically at no cost" | **DynamoDB TTL** |
| "React to item changes" | **DynamoDB Streams** + Lambda |
| "Retain the change stream > 24 h / many consumers" | **Kinesis Data Streams for DynamoDB** |
| "Restore DynamoDB table to any second in the last 35 days" | **PITR** |
| "Analytics on DynamoDB without consuming RCU" | **Export to S3** (+ Athena) or zero-ETL |
| "Atomic update across multiple items" | **DynamoDB transactions** |
| "Store a 2 MB object with metadata" | Object in **S3**, pointer in DynamoDB |
| "Session store for stateless web tier" | **ElastiCache (Valkey/Redis OSS)** or DynamoDB |
| "Leaderboard / sorted rankings" | Valkey/Redis **sorted sets** (ElastiCache or MemoryDB) |
| "Redis-compatible but must not lose data" | **MemoryDB** |
| "Cross-Region replication of Redis cache" | **ElastiCache Global Datastore** |
| "Cache with no capacity planning" | **ElastiCache Serverless** |
| "Simple multithreaded cache, no persistence needed" | **Memcached** |
| "Cache stampede after expiry" | **TTL jitter**, request coalescing, pre-warming |
| "MongoDB workload, managed, minimal change" | **DocumentDB** |
| "Fraud rings / social graph / recommendations" | **Neptune** |
| "Cassandra, stop managing nodes" | **Keyspaces** |
| "IoT time-series" | **Timestream** (Timestream for InfluxDB for new customers) |
| "Write throughput beyond a single PostgreSQL writer, keep SQL" | **Aurora Limitless Database** |

---

## 6. Traps & distractors

1. **"Use the Multi-AZ standby for read traffic."** A Multi-AZ *DB instance* standby is never readable. Only a Multi-AZ *DB cluster* or Aurora replicas serve reads.
2. **"Read replicas provide automatic failover."** RDS read replicas need **manual promotion**. Aurora replicas are automatic failover targets.
3. **"Enable encryption on the running RDS instance."** You can't do this in place. Use snapshot → encrypted copy → restore, or DMS.
4. **"Share the encrypted snapshot directly."** This fails if the snapshot uses the AWS managed `aws/rds` key. Re-encrypt it with a customer managed key and grant the target account access to that key.
5. **"Cross-Region read replica gives RPO 0."** Replication is asynchronous, so RPO = lag. Only synchronous options give RPO 0: Multi-AZ within a Region, DynamoDB MRSC, and Aurora switchover for planned moves.
6. **"Aurora Global Database failover has no data loss."** Only **switchover** (planned, primary healthy) guarantees RPO 0. Unplanned failover can lose writes that hadn't replicated yet.
7. **"Backtrack for Aurora PostgreSQL" or "Backtrack on Global Database."** Backtrack is Aurora MySQL only, isn't supported with Global Database, and must be enabled at creation.
8. **"Add an LSI to the existing table."** LSIs can only be created along with the table. Use a **GSI** instead.
9. **"Strongly consistent reads from a GSI."** GSIs only support eventually consistent reads.
10. **"DAX accelerates writes / strongly consistent reads."** DAX is write-through, so it adds write latency. It passes strongly consistent reads to DynamoDB without caching them.
11. **"Increase table WCU to fix throttling"** when the cause is a hot key. Per-partition limits still apply. Fix the key design or shard the writes.
12. **"A DynamoDB Scan with a filter is efficient."** A Scan reads (and bills for) the entire table, and the filter applies after the read. Use Query on a well-designed key or GSI.
13. **"Memcached for HA session storage."** Memcached has no replication or failover. Use Valkey/Redis OSS with Multi-AZ, or DynamoDB.
14. **"ElastiCache Global Datastore fails over automatically."** Promotion is manual.
15. **"ElastiCache as the durable system of record."** Use MemoryDB when you need durability. ElastiCache is a cache.
16. **"RDS Proxy publicly accessible for on-premises apps."** Proxies are VPC-only. Reach them over VPN or Direct Connect.
17. **"Aurora Serverless v2 scales to zero with RDS Proxy attached."** Open proxy connections prevent auto-pause.
18. **"Aurora Serverless v1 behaviour."** v1 is deprecated. Don't pick v1-specific answers for new designs.
19. **"Promote a read replica to perform a major version upgrade."** It works, but it is more manual and riskier than **Blue/Green Deployments**, which keep the endpoints.
20. **"EC2 self-managed database"** when nothing in the stem requires OS-level control. It has higher operational overhead; RDS, RDS Custom or Aurora wins.
21. **"QLDB for a new ledger."** QLDB reached end of support on 31 July 2025. Be careful with options that build new workloads on it.
22. **"Redshift for OLTP" / "RDS for petabyte analytics."** These pair a service with the wrong workload type.
23. **"DynamoDB global tables MREC give strongly consistent reads globally."** Strongly consistent reads only reflect writes made in the same Region. Use MRSC for global strong consistency.
24. **"Storage autoscaling shrinks storage when data is deleted."** RDS never shrinks storage. Aurora's cluster volume does resize dynamically.
25. **"Aurora reader endpoint load-balances each query."** It balances connections through DNS. Long-lived pooled connections can pile onto one reader.

---

## 7. Professional architect focus

- **Start from access patterns and SLOs, not from the product.** Write down the read/write ratio, item or row size, query shapes, consistency needs, RPO/RTO, growth and team skills. A relational model with ad-hoc queries doesn't belong in DynamoDB. A 100k-writes/s key-value workload doesn't belong on a single RDS writer.
- **Polyglot persistence with ownership.** Each microservice can choose its own store, but every extra engine adds operational skills, backup policies, security reviews and DR runbooks. Standardise a small "paved road" (e.g., Aurora PostgreSQL, DynamoDB, ElastiCache for Valkey) and require a justification for exceptions.
- **Design for failover at the client.** Use short DNS TTLs (JVM `networkaddress.cache.ttl` ≤ 60 s), retries with exponential backoff and jitter, idempotent writes, RDS Proxy or the AWS Advanced JDBC Wrapper for fast failover, and global writer endpoints. Test with **Reboot with failover**, Global Database switchover drills and **AWS FIS** experiments (FIS can pause DynamoDB global table replication).
- **Know what "RPO 0" costs.** Synchronous cross-Region replication (DynamoDB MRSC, Aurora DSQL) adds inter-Region round trips to every write and restricts features. Most businesses accept a few seconds of RPO in exchange for large cost and latency savings. Make stakeholders choose this consciously.
- **Split-brain risk in unplanned failovers.** Stop writes to the old primary before promoting: stop applications, use a low DNS TTL, use Route 53 ARC routing controls. Aurora's write fencing is best-effort.
- **Cost levers:** Reserved Instances or reserved capacity for steady baselines; Serverless v2 and on-demand for variable load; I/O-Optimized for I/O-heavy Aurora; Graviton instance classes for better price-performance; the Standard-IA table class; right-sizing with Database Insights and Compute Optimizer; deleting idle dev databases or letting Serverless v2 pause; avoiding chatty cross-AZ traffic; reviewing backup retention and snapshot sprawl.
- **Licensing is a design input.** Oracle and SQL Server Enterprise licences often dominate TCO. Options: License Included vs BYOL, edition downgrades, Babelfish, heterogeneous migration with SCT/DMS. RDS Custom keeps the commercial engine while allowing customisation.
- **Security baseline:** private subnets; security groups that reference app security groups; no public endpoints; TLS enforced; KMS customer managed keys where you need cross-account access or key-policy control; IAM DB auth or Secrets Manager rotation; Database Activity Streams for regulated workloads; deletion protection on production; AWS Backup with Vault Lock for ransomware resilience; AWS Config rules (e.g., RDS encryption, public snapshot checks).
- **Connection storms from serverless compute:** cap Lambda concurrency (reserved concurrency) as a safety valve, reuse connections outside the handler, put RDS Proxy in front, or use the HTTP-based Data API or DynamoDB.
- **Schema change discipline:** use online DDL tools, Blue/Green for risky changes, clones for rehearsals, and backward-compatible migrations (expand → migrate → contract) so you can roll back application versions.
- **Questions to raise with stakeholders:** What data loss is acceptable for planned events, and for unplanned ones? Do we need multi-Region writes, or is "read locally, write to a home Region" enough? What is the busiest single key or tenant? How long must backups be kept, and must they be immutable? Who owns the data model as it evolves?

---

## 8. Skills checklist

- [ ] I can choose between Multi-AZ DB instance, Multi-AZ DB cluster, read replicas and Aurora replicas based on availability, read-scaling and failover-time requirements.
- [ ] I can explain how to encrypt an existing unencrypted RDS instance and how to share an encrypted snapshot across accounts.
- [ ] I can design cross-Region DR for RDS (cross-Region replica, cross-Region automated backups) and state the RPO/RTO of each.
- [ ] I can describe Aurora's storage architecture (6 copies, 3 AZs, quorum, self-healing) and explain why its replicas are fast.
- [ ] I can use promotion tiers, reader endpoints and custom endpoints to isolate workloads and control failover.
- [ ] I can explain Aurora Global Database switchover vs managed failover vs detach-and-promote, plus write forwarding, headless secondaries and `rds.global_db_rpo`.
- [ ] I know when to use Aurora Serverless v2 (0–256 ACU, auto-pause) and what its limitations are.
- [ ] I can pick between Backtrack, PITR, cloning, snapshots and Blue/Green for a given recovery or testing need.
- [ ] I can apply the I/O-Optimized 25% rule and explain the use cases for Babelfish and zero-ETL.
- [ ] I can configure RDS Proxy for Lambda with IAM auth and Secrets Manager, and list its networking constraints.
- [ ] I can design DynamoDB partition keys, identify hot partitions and apply write sharding.
- [ ] I can choose GSI vs LSI, and on-demand vs provisioned vs reserved capacity.
- [ ] I can explain the trade-offs and restrictions of global tables MREC vs MRSC.
- [ ] I can choose between DynamoDB Streams and Kinesis Data Streams for DynamoDB.
- [ ] I can write an IAM policy that uses `dynamodb:LeadingKeys` for per-user isolation.
- [ ] I know DAX's consistency behaviour and when DAX is the wrong choice.
- [ ] I can compare Valkey/Redis OSS vs Memcached vs MemoryDB, and cluster mode enabled vs disabled.
- [ ] I can implement cache-aside, write-through and TTL strategies, and mitigate thundering herd.
- [ ] I can map data models to DocumentDB, Neptune, Keyspaces, Timestream, OpenSearch and Redshift, and I know the status of QLDB and Timestream for LiveAnalytics.
- [ ] I can recommend migration paths (DMS/SCT, Babelfish, Aurora read replica of RDS, RDS Custom).

---

## 9. Practice questions

> Original SAP-C02-style questions written for this guide (not real exam questions). Answer all ten before you open the explanations.

**Q1.** A ticketing company runs its order API on AWS Lambda behind Amazon API Gateway. Orders are stored in an Amazon Aurora PostgreSQL cluster with one writer and two readers in three Availability Zones. During on-sale events, Lambda concurrency jumps from 50 to more than 3,000 within a minute. The database then logs `too many connections` errors and CPU spikes from connection setup. During a recent writer failover, many Lambda invocations kept failing for almost two minutes because cached DNS still pointed at the old writer. The security team also wants to remove the database password from the Lambda environment variables. Which solution meets these requirements with the LEAST operational overhead?

A. Increase `max_connections` in the cluster parameter group, move to a larger writer instance class, and store the password in AWS Systems Manager Parameter Store as a SecureString.
B. Create an Amazon RDS Proxy for the cluster in the same VPC, require IAM authentication from clients to the proxy, store the database credentials in AWS Secrets Manager for the proxy, and point the Lambda functions at the proxy endpoint.
C. Put an Amazon ElastiCache for Valkey cluster in front of Aurora to cache order writes, and set Lambda reserved concurrency to 100.
D. Replace the Aurora reader instances with Aurora Serverless v2 readers in promotion tier 0, and enable IAM database authentication directly on the cluster for the Lambda functions.

**Q2.** A financial services company runs a customer-facing application on Aurora MySQL in us-east-1. A regulator requires that (1) the company can recover from a full Regional outage with an RPO of seconds and an RTO measured in minutes, and (2) once each quarter, production runs from a second Region (us-west-2) for several weeks to prove the DR capability, with no data loss during the planned move. The application must keep using one connection string for writes. Which combination of actions meets these requirements? **(Select TWO.)**

A. Convert the cluster to an Aurora Global Database with a secondary cluster in us-west-2 that has at least one reader instance, and configure the application to use the global writer endpoint.
B. Create a cross-Region Aurora MySQL read replica using binary log replication in us-west-2, and promote it each quarter.
C. For the quarterly move, use the Aurora Global Database switchover operation; for a real Regional outage, use the managed failover operation with `--allow-data-loss`.
D. For the quarterly move, use the managed failover operation with `--allow-data-loss`; for a real Regional outage, detach the secondary cluster from the global database and promote it.
E. Enable Aurora Backtrack with a 72-hour window on both clusters so that any data lost during a Regional failover can be rewound.

**Q3.** A media company uses a DynamoDB table in on-demand capacity mode to store live votes for a televised talent show. The partition key is `contestantId` and the sort key is `voteTimestamp`. During the final episode, the two most popular contestants each receive about 20,000 votes per second, and the application gets `ProvisionedThroughputExceededException` errors for those contestants, even though table-level consumption is far below the account's table quotas. Other contestants' votes are written successfully. Results must be shown within 10 seconds. What should a solutions architect do to resolve the throttling?

A. Switch the table to provisioned capacity mode with 100,000 WCUs and enable auto scaling.
B. Add a global secondary index on `voteTimestamp` so writes are distributed across both the table and the index.
C. Change the write path to use a sharded partition key, such as `contestantId#<random 0–49>`, and compute totals by querying all shards in parallel (or with a periodic aggregator) for display.
D. Put DynamoDB Accelerator (DAX) in front of the table so that the vote writes are absorbed by the cache.

**Q4.** A healthcare company has a 2 TB Amazon RDS for PostgreSQL DB instance that was created years ago without encryption. A new policy requires that all databases are encrypted at rest with keys the company controls, and that a daily copy of the database is available in a separate AWS account owned by the security team for forensic restores. The company can accept a short maintenance window for writes but wants to minimise the work involved. Which approach meets these requirements?

A. Modify the DB instance and enable encryption with a customer managed AWS KMS key, then share the automated snapshots with the security account.
B. Take a snapshot, copy it with encryption enabled using a customer managed KMS key, restore a new DB instance from the encrypted copy and cut the application over; then use AWS Backup (or a scheduled snapshot copy) to share daily snapshots encrypted with the customer managed key, granting the security account use of that key in the key policy.
C. Create an encrypted read replica of the DB instance using the AWS managed `aws/rds` key, promote it, and share its daily snapshots with the security account.
D. Take a snapshot, copy it with encryption using the AWS managed `aws/rds` key, restore it, and share the resulting snapshots with the security account.

**Q5.** An e-commerce company runs RDS for PostgreSQL 13 in a Multi-AZ DB instance deployment with two read replicas. The company must upgrade to PostgreSQL 16 before end of standard support. Requirements: test the new version against a live copy of production data for a week, keep application connection strings unchanged, keep downtime at cutover to about a minute, and minimise manual steps. Which solution meets these requirements?

A. Create a new read replica, upgrade the replica to PostgreSQL 16, then promote it and update the application connection strings.
B. Use AWS DMS to replicate from the current instance to a new PostgreSQL 16 instance with CDC, then switch the application to the new endpoint.
C. Create an Amazon RDS Blue/Green Deployment that specifies PostgreSQL 16 for the green environment, test against the green environment, and then perform a switchover.
D. Perform an in-place major version upgrade during the maintenance window after taking a manual snapshot.

**Q6.** A logistics company runs an Aurora MySQL cluster with one writer (db.r7g.2xlarge) and three readers. The operations dashboard uses the reader endpoint. Every night, a finance team runs heavy reporting queries that also use the reader endpoint, and dashboard latency rises sharply. The company has added a db.r7g.4xlarge reader for reporting, but during a recent failover test Aurora promoted the large reporting instance to writer, which then ran the OLTP workload while reports ran against it. The company wants reporting isolated from the dashboard and does not want the reporting instance chosen as the writer unless no other reader is available. Which combination of steps should be taken? **(Select TWO.)**

A. Create a custom endpoint that contains only the reporting instance and point the reporting tool at it; create another custom endpoint for the dashboard readers.
B. Set the reporting instance's promotion tier to 15 and the dashboard readers to tiers 0–1.
C. Set the reporting instance's promotion tier to 0 so that it is promoted last.
D. Enable Aurora Auto Scaling on the cluster so that new readers are added when reporting runs.
E. Move the reporting queries to the cluster endpoint during the night window.

**Q7.** A fitness app has 30 million users in North America and Europe. User profiles and workout history are stored in an existing DynamoDB table in us-east-1 that already holds 4 TB of data. European users experience high write latency. The company wants users to read and write in the Region closest to them, keep writes working if one Region fails, prioritise low write latency over cross-Region read consistency, and ensure that each authenticated user (signed in through Amazon Cognito) can only access their own items. Which combination of actions meets these requirements? **(Select THREE.)**

A. Add a replica in eu-west-1 to make the table a DynamoDB global table using multi-Region eventual consistency (MREC).
B. Convert the table to a global table using multi-Region strong consistency (MRSC) with a witness in a third Region.
C. Deploy the API stack in both Regions and use Amazon Route 53 latency-based routing (with health checks) to send users to the nearest healthy Region.
D. Use a Cognito identity pool role whose IAM policy allows DynamoDB actions only when `dynamodb:LeadingKeys` matches the user's identity ID, and use the identity ID as the partition key.
E. Add an ElastiCache Global Datastore in eu-west-1 to absorb European writes and flush them to the us-east-1 table.
F. Create a global secondary index in eu-west-1 so European users can write locally.

**Q8.** An online retailer caches product pages in Amazon ElastiCache for Memcached in front of an Aurora MySQL cluster, using lazy loading with a fixed 60-minute TTL. At the top of every hour, Aurora CPU reaches 100% for several minutes and page latency spikes. Separately, the retailer wants to move HTTP session data out of the web servers so they can be scaled in aggressively, and sessions must survive the loss of a single cache node or an Availability Zone. Which combination of changes addresses both issues? **(Select TWO.)**

A. Add random jitter to the cache TTLs (for example, 55–65 minutes) and use request coalescing so only one request repopulates a missing hot key.
B. Reduce the TTL to 60 seconds so the cache is refreshed more often.
C. Store sessions in an ElastiCache for Valkey replication group with at least one replica in another AZ and Multi-AZ automatic failover enabled.
D. Store sessions in the existing Memcached cluster and add more nodes.
E. Replace the cache with DynamoDB Accelerator (DAX) in front of Aurora.

**Q9.** A software company runs a line-of-business application on SQL Server Enterprise Edition on Amazon EC2. Licensing makes up most of its database cost. The application contains about 1,200 T-SQL stored procedures and uses the SQL Server client drivers. Leadership wants to move to an open-source-compatible managed database within six months, with minimal application code changes, and keep the option to modernise gradually to PostgreSQL-native code. Which approach best meets these requirements?

A. Rehost to Amazon RDS for SQL Server Standard Edition using native backup and restore.
B. Migrate to Amazon Aurora PostgreSQL with Babelfish enabled, assess compatibility with Babelfish Compass, migrate data with AWS DMS, and point the application's SQL Server drivers at the Babelfish TDS endpoint.
C. Use AWS SCT to convert all stored procedures to PL/pgSQL, rewrite the data access layer to use PostgreSQL drivers, and migrate to Amazon RDS for PostgreSQL.
D. Migrate to Amazon RDS Custom for SQL Server so the company can install its own licensing tools on the host.

**Q10.** A company runs 40 Aurora PostgreSQL clusters. Thirty are development and test clusters on db.r6g.large provisioned instances; they are used about 6 hours on weekdays and are idle at night and on weekends. The remaining 10 production clusters run steady, I/O-intensive workloads; Cost Explorer shows that I/O charges make up about 45% of their Aurora spend. Which combination of actions will reduce costs the MOST without reducing production performance? **(Select TWO.)**

A. Convert the development and test clusters to Aurora Serverless v2 with a minimum capacity of 0 ACUs so they auto-pause when idle, and don't attach RDS Proxy to them.
B. Purchase 3-year Reserved Instances for the development and test clusters.
C. Switch the production clusters to the Aurora I/O-Optimized storage configuration.
D. Add RDS Proxy to the development and test clusters so that idle connections are pooled.
E. Move the production clusters to Aurora Standard storage and reduce the number of readers.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**

**Why:** RDS Proxy pools and multiplexes thousands of short-lived Lambda connections over a small number of database connections, which removes connection storms and the CPU cost of connection setup. During failover the proxy routes to the new writer without waiting for DNS propagation and keeps client connections open (AWS cites up to 66% faster failover). Requiring IAM authentication to the proxy, with the proxy holding the credentials in Secrets Manager, removes the password from Lambda. It is fully managed and needs only a change of endpoint.

**Why not the others:**
- **A:** Raising `max_connections` and scaling up only moves the ceiling (each connection uses memory). It doesn't fix the DNS caching on failover, and the app still handles a password.
- **C:** Caching writes in ElastiCache is unsafe and doesn't address connection management. Capping concurrency at 100 would throttle the on-sale traffic.
- **D:** Serverless v2 readers don't change the connection count to the writer. Direct IAM DB auth adds per-connection token validation load on the database (it suits modest connection rates, not thousands of new connections per second), and it does nothing for failover time.

**References:** [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html) · [High availability for Aurora (RDS Proxy)](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.AuroraHighAvailability.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A and C.**

**Why:** Aurora Global Database replicates at the storage layer with lag typically under a second, which gives an RPO of seconds and an RTO of minutes. The **global writer endpoint** always points to the current primary, so the application keeps one write connection string. **Switchover** (formerly managed planned failover) waits until the secondary is fully synchronised, so RPO = 0, which is right for the quarterly regulatory rotation. **Managed failover** (`--allow-data-loss`) is the documented method for an unplanned Regional outage. It promotes the secondary without waiting for sync and later re-adds the old primary Region as a secondary.

**Why not the others:**
- **B:** Binlog-based cross-Region replicas have higher lag and a manual promotion. Promotion breaks replication, so rotating every quarter means rebuilding each time, and the write endpoint changes.
- **D:** It reverses the operations. Using `--allow-data-loss` for a planned move risks losing data, and detach-and-promote is the manual fallback that breaks the global topology.
- **E:** Backtrack isn't supported on Aurora Global Database, and it can't recover writes that never replicated to the other Region.

**References:** [Using switchover or failover in Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html) · [Using Amazon Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: C.**

**Why:** The throttling is a **hot partition**. Every vote for a popular contestant goes to the same partition key value, and a single partition supports about 1,000 WCU. Adaptive capacity and on-demand mode can't push one key value past per-partition limits. Write sharding (appending a suffix from 0–49) spreads each contestant's writes across many partitions. Totals are computed by querying the shards in parallel or by a periodic aggregator, which easily meets the 10-second display requirement.

**Why not the others:**
- **A:** More table-level capacity doesn't raise per-partition limits. The table isn't hitting its total throughput anyway.
- **B:** A GSI doesn't reduce the writes to the base table's hot partition. It adds more writes, and a throttled GSI can back-pressure the table.
- **D:** DAX is a write-through cache. Every write still goes to DynamoDB, so DAX doesn't absorb write load.

**References:** [Best practices for designing and using partition keys effectively](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-design.html) · [Using write sharding to distribute workloads evenly](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-sharding.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: B.**

**Why:** You can't encrypt an existing unencrypted RDS instance in place. The supported path is snapshot → copy the snapshot with encryption enabled → restore a new instance from the encrypted copy → cut over, which is acceptable here because a short write outage is allowed. Using a **customer managed KMS key** satisfies "keys the company controls" and is required for cross-account sharing. Snapshots encrypted with the AWS managed `aws/rds` key can't be shared. AWS Backup (with cross-account copy) or a scheduled snapshot copy/share provides the daily copy, provided the key policy lets the security account use the key.

**Why not the others:**
- **A:** Encryption can't be enabled by modifying an existing instance.
- **C:** You can't create an encrypted read replica from an unencrypted source. Snapshots encrypted with `aws/rds` can't be shared across accounts.
- **D:** The encryption method works, but `aws/rds` snapshots can't be shared with another account, and an AWS managed key doesn't meet "keys the company controls".

**References:** [Encrypting Amazon RDS resources](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html) · [Sharing a DB snapshot](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ShareSnapshot.html) · [AWS Backup cross-account backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/create-cross-account-backup.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: C.**

**Why:** RDS Blue/Green Deployments copy the full production topology (Multi-AZ and read replicas) into a green environment that replication keeps in sync. You can create the green environment on PostgreSQL 16 and test it for as long as needed. The switchover has built-in guardrails, typically takes under a minute, loses no data, and swaps names/endpoints so connection strings don't change.

**Why not the others:**
- **A:** You can't upgrade a PostgreSQL read replica independently and keep it replicating. Promoting it also changes the endpoint, which requires app changes, and the replicas would have to be rebuilt by hand.
- **B:** DMS works but adds significant manual effort (tasks, validation, LOB handling, sequence resets), and the endpoint changes.
- **D:** An in-place major upgrade can't be tested against live data beforehand, and its downtime is usually much longer than a minute.

**References:** [Overview of Amazon RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A and B.**

**Why:** **Custom endpoints** let you route the reporting tool only to the large reporting instance and the dashboard only to its readers, so the workloads are isolated. **Promotion tiers** control failover. Tier 0 is the highest priority and 15 the lowest. Putting the reporting instance in tier 15 and the dashboard readers in tiers 0–1 means Aurora promotes a dashboard reader first. Within a tier Aurora prefers the largest instance, which is why the big reporting instance won when every reader was in the same tier.

**Why not the others:**
- **C:** Tier 0 is the *highest* priority, so this makes the problem worse.
- **D:** Auto Scaling adds readers behind the reader endpoint. That doesn't isolate reporting from the dashboard, and new readers would also be failover candidates.
- **E:** The cluster endpoint is the writer. Running heavy reports on it would hurt OLTP writes.

**References:** [Amazon Aurora endpoint connections](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html) · [High availability for Aurora — promotion tiers](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.AuroraHighAvailability.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: A, C and D.**

**Why:** Adding an eu-west-1 replica turns the existing table into a **global table** with multi-active replication. **MREC** is the default, has the lowest write latency, and you create it by adding a replica to an existing populated table. **Route 53 latency-based routing** with health checks sends users to the nearest healthy Region and shifts them away if a Region fails. A Cognito identity pool role with an IAM condition on **`dynamodb:LeadingKeys`** set to `${cognito-identity.amazonaws.com:sub}` restricts each user to items whose partition key is their own identity ID.

**Why not the others:**
- **B:** MRSC can only be created from an **empty** table, adds cross-Region latency to every write (the stem prioritises low write latency), and must use exactly three Regions.
- **E:** Global Datastore replicates a cache from a primary to read-only secondaries. Secondaries don't accept writes, and a cache isn't a durable write path.
- **F:** GSIs belong to the table in its own Region. They don't create regional write endpoints.

**References:** [How DynamoDB global tables work](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html) · [Using IAM policy conditions for fine-grained access control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: A and C.**

**Why:** Every key was written with the same fixed TTL, so hot keys expire together at the top of the hour and every request misses at once: a **cache stampede (thundering herd)**. TTL jitter spreads expirations out, and request coalescing (or a lock / single-flight refresh) means only one caller rebuilds each hot key. For sessions, an **ElastiCache for Valkey** replication group with a replica in another AZ and **Multi-AZ automatic failover** keeps session data through a node or AZ failure.

**Why not the others:**
- **B:** A shorter TTL raises the miss rate and database load, and keys can still expire together.
- **D:** Memcached has no replication or failover. Losing a node loses those sessions.
- **E:** DAX only works with DynamoDB, not Aurora.

**References:** [Caching strategies (ElastiCache)](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Strategies.html) · [Comparing Valkey, Memcached and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/SelectEngine.html) · [Minimizing downtime with Multi-AZ](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/AutoFailover.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: B.**

**Why:** **Babelfish for Aurora PostgreSQL** provides a TDS endpoint that understands T-SQL and the SQL Server wire protocol. The application keeps its SQL Server drivers and most of its T-SQL while running on an open-source-compatible engine with no SQL Server licence. Babelfish Compass identifies unsupported features before you migrate, and DMS moves the data. Because the same data can also be reached through the PostgreSQL port, the company can modernise gradually to PL/pgSQL.

**Why not the others:**
- **A:** It's still SQL Server with licensing costs. Standard Edition may also lack Enterprise features the app uses.
- **C:** A full conversion of 1,200 procedures plus a data-access rewrite is a lot of work and risk for six months, and it contradicts "minimal code changes".
- **D:** RDS Custom for SQL Server still needs a SQL Server licence and doesn't reduce licensing cost.

**References:** [Babelfish for Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish.html) · [AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: A and C.**

**Why:** The dev/test clusters are idle most of the week. **Aurora Serverless v2 with a minimum of 0 ACUs** auto-pauses idle instances, so there is no compute charge while paused (storage is still billed), and it scales to the capacity needed during working hours. Leaving RDS Proxy off matters because a proxy's open connections prevent auto-pause. For production, AWS guidance is to choose **Aurora I/O-Optimized** when I/O is 25% or more of Aurora spend. At 45%, removing per-request I/O charges lowers total cost with no performance trade-off.

**Why not the others:**
- **B:** Reserved Instances commit you to paying 24×7 for instances that are idle about 80% of the time. Serverless v2 with auto-pause saves more and adds no long-term commitment.
- **D:** RDS Proxy adds cost and blocks Serverless v2 from scaling to zero. Dev/test has no connection-pooling problem.
- **E:** Aurora Standard is the more expensive option at 45% I/O, and removing readers could reduce production availability and performance.

**References:** [Aurora Serverless v2 — how it works](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.how-it-works.html) · [Scaling to zero ACUs with automatic pause and resume](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html) · [Amazon Aurora storage configurations](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.StorageReliability.html)
</details>

---

## 10. References

**Amazon RDS**
- [What is Amazon RDS?](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html)
- [Multi-AZ DB instance deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html) · [Failing over a Multi-AZ DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.Failover.html)
- [Multi-AZ DB cluster deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html) · [Failing over a Multi-AZ DB cluster](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts-failover.html)
- [Working with DB instance read replicas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html) · [Differences between read replicas for DB engines](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.Overview.Differences.html)
- [Replicating automated backups to another AWS Region](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html)
- [Encrypting Amazon RDS resources](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html)
- [IAM database authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [Amazon RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html)
- [Amazon RDS Custom](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-custom.html)
- [Increasing DB instance storage capacity / storage autoscaling](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.ModifyingExisting.html)
- [Quotas and constraints for Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html)
- [Monitoring DB load with CloudWatch Database Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)

**Amazon Aurora**
- [What is Amazon Aurora?](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_AuroraOverview.html)
- [Amazon Aurora storage](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.StorageReliability.html) · [High availability for Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.AuroraHighAvailability.html)
- [Aurora endpoint connections](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html)
- [Using Amazon Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html) · [Switchover or failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html) · [Write forwarding](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-write-forwarding.html)
- [How Aurora Serverless v2 works](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.how-it-works.html) · [Scaling to zero ACUs](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html)
- [Backtracking an Aurora DB cluster](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.Managing.Backtrack.html) · [Cloning an Aurora volume](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Clone.html)
- [Babelfish for Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish.html)
- [Aurora zero-ETL integrations with Amazon Redshift](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/zero-etl.html)
- [Aurora PostgreSQL Limitless Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/limitless.html)
- [What is Amazon Aurora DSQL?](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is-aurora-dsql.html)

**Amazon DynamoDB**
- [What is Amazon DynamoDB?](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Introduction.html)
- [Quotas in DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ServiceQuotas.html)
- [Partition key design best practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-design.html)
- [How DynamoDB global tables work (MREC/MRSC)](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html)
- [Point-in-time recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Point-in-time-recovery.html)
- [DAX and DynamoDB consistency models](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.consistency.html)
- [Change data capture with DynamoDB Streams / Kinesis Data Streams](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/streamsmain.html)
- [Using IAM policy conditions for fine-grained access control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html)
- [Time to Live (TTL)](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)

**Caching and in-memory**
- [Comparing Valkey, Memcached and Redis OSS](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/SelectEngine.html)
- [ElastiCache caching strategies](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Strategies.html)
- [ElastiCache Global Datastore](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Redis-Global-Datastore.html) · [Prerequisites and limitations](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Redis-Global-Datastores-Getting-Started.html)
- [What is Amazon MemoryDB?](https://docs.aws.amazon.com/memorydb/latest/devguide/what-is-memorydb.html) · [MemoryDB Multi-Region](https://docs.aws.amazon.com/memorydb/latest/devguide/multi-region.html)

**Purpose-built databases**
- [Amazon DocumentDB global clusters](https://docs.aws.amazon.com/documentdb/latest/developerguide/global-clusters.html) · [DocumentDB elastic clusters](https://docs.aws.amazon.com/documentdb/latest/developerguide/docdb-using-elastic-clusters.html)
- [Amazon Neptune global database](https://docs.aws.amazon.com/neptune/latest/userguide/neptune-global-database.html)
- [What is Amazon Keyspaces?](https://docs.aws.amazon.com/keyspaces/latest/devguide/what-is-keyspaces.html)
- [Amazon Timestream for LiveAnalytics availability change](https://docs.aws.amazon.com/timestream/latest/developerguide/AmazonTimestreamForLiveAnalytics-availability-change.html)
- [Amazon Redshift zero-ETL integrations](https://docs.aws.amazon.com/redshift/latest/mgmt/zero-etl-using.html)

**Whitepapers & guidance**
- [AWS Prescriptive Guidance — DynamoDB global tables](https://docs.aws.amazon.com/prescriptive-guidance/latest/dynamodb-global-tables/introduction.html)
- [Database caching strategies using Redis (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/welcome.html)
- [Disaster Recovery of Workloads on AWS (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html)
- [AWS Well-Architected — Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)

---
> [← Previous: Storage & Data Transfer](08-Storage-and-Data-Transfer.md) · [Index](00-README-Start-Here.md) · [Next: Application Integration & Event-Driven →](10-Application-Integration-and-Event-Driven.md)
