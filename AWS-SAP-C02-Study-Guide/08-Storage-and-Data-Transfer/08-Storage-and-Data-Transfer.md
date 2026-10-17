# Chapter 08 — Storage: S3, EBS, EFS, FSx, Storage Gateway, Backup & Data Transfer
> **Exam mapping:** D2 Task 2.2, D2 Task 2.5, D2 Task 2.6, D3 Task 3.3, D3 Task 3.5, D4 Task 4.2, D4 Task 4.3 | **Weight signal:** High | **Study time:** ~9 h
> [← Previous](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md) · [Index](../00-README-Start-Here.md) · [Next →](../09-Databases-and-Caching/09-Databases-and-Caching.md)

> **Facts verified on docs.aws.amazon.com / aws.amazon.com as of October 2026.** Where the current AWS service has changed since the SAP-C02 exam was written, both views appear as **"Exam view"** and **"Current reality"**. On exam day, pick the answer that fits the exam's view of the world unless the stem clearly signals the newer feature.

---

## 1. What the exam really tests here

Storage questions on SAP-C02 rarely ask "what is S3?". They give you a business situation and ask you to choose the **cheapest, most resilient or fastest storage design, or the one with the least operational overhead**. Expect these patterns:

| Scenario shape | What you must decide |
|---|---|
| "Data accessed frequently for 30 days, rarely after, must keep 7 years, retrieval within 12 h acceptable" | Storage class waterfall plus lifecycle rules, minimum-duration and minimum-size traps, Object Lock for WORM |
| "Replicate to another Region/account, protect against ransomware, replicas owned by the backup account, objects use SSE-KMS" | CRR settings: KMS opt-in, destination key, owner override, delete-marker behaviour, Batch Replication for existing objects, RTC |
| "Thousands of on-prem Windows users / NetApp filers / Linux NFS / HPC scratch" | EFS vs FSx for Windows vs FSx for ONTAP vs FSx for OpenZFS vs FSx for Lustre |
| "Move 300 TB in 3 weeks over a 1 Gbps link" | Bandwidth maths, then DataSync vs Snowball Edge vs Direct Connect vs Transfer Acceleration |
| "Keep the on-prem backup software, get rid of tapes" | Tape Gateway → S3 Glacier Flexible Retrieval / Deep Archive |
| "Central, immutable, cross-account backups for 400 accounts with compliance proof" | AWS Backup + Organizations backup policies + cross-account/cross-Region copy + Vault Lock (compliance) / logically air-gapped vault + Audit Manager |
| "Database needs 150,000 IOPS, sub-ms latency" / "cut EBS cost" | io2 Block Express vs gp3, gp2→gp3 migration, instance limits, snapshot tiers |
| "Global users upload large files slowly" / "503 Slow Down" | Transfer Acceleration, multipart upload, prefix parallelism, byte-range GETs |

The decisions that separate a Professional answer from an Associate answer:
- **Know the constraints, not just the features.** For example: minimum storage durations, the 128 KB minimum billable size, that lifecycle actions are not replicated, that SSE-KMS objects are not replicated unless you opt in, that S3 gateway endpoints cannot be reached from on-premises, and that Multi-Attach works only within one AZ.
- **Combine services.** For example: DataSync over Direct Connect through a VPC interface endpoint, S3 File Gateway with lifecycle rules, or AWS Backup with Organizations policies and Vault Lock.
- **Reason about cost**, including request costs, retrieval fees, cross-Region transfer, KMS request costs (S3 Bucket Keys), and paying for capacity you provisioned but don't use (gp2 sized up for IOPS, io1).

---

## 2. Core concepts & services — deep dive

### 2.1 Amazon S3 — fundamentals a Professional must have cold

- **Object store**, flat namespace (a "prefix" is part of the key). Buckets are **Regional**, names are globally unique (general purpose buckets).
- **Maximum object size.** *Exam view:* 5 TB, single PUT up to 5 GB, multipart required above 5 GB. *Current reality:* since **December 2025 the maximum object size is 50 TB**. Multipart allows 10,000 parts of up to 5 GiB each. Single PUT is still limited to 5 GB.
- **Durability** 99.999999999% (11 nines) for all current classes. **Availability** varies by class (see table).
- **Consistency:** **strong read-after-write consistency** for all PUTs and DELETEs of objects and for LIST operations, in all Regions, at no extra cost (since December 2020). Bucket **configuration** changes (for example, policies or versioning) can take time to propagate. Don't design around reading a configuration back immediately after writing it.
- **Bucket types:** *general purpose buckets* (classic), *directory buckets* (S3 Express One Zone, one AZ, or Local Zone), *table buckets* (S3 Tables, Apache Iceberg), and *vector buckets* (S3 Vectors, GA December 2025).
- **Encryption:** every new object has been encrypted at rest by default with **SSE-S3** since January 2023. Options: SSE-S3, **SSE-KMS** (audit trail and key-policy control; enable **S3 Bucket Keys** to cut KMS request cost and avoid KMS throttling), **DSSE-KMS** (dual-layer, for compliance), and SSE-C (customer-provided key, sent with every request).
- **Private connectivity:** a **gateway VPC endpoint** for S3 is free, works only inside the same Region, and **cannot be used from on-prem or across peering/TGW**. An **interface VPC endpoint (PrivateLink)** for S3 is chargeable, has private IPs, and **is reachable from on-prem over Direct Connect or VPN**. Use bucket policy conditions `aws:SourceVpce` / `aws:SourceVpc` to lock a bucket to endpoints.

### 2.2 S3 storage classes (memorise this table)

| Storage class | AZs | Availability (design) | Min storage duration | Min billable object size | Retrieval fee | First-byte / retrieval | Typical use |
|---|---|---|---|---|---|---|---|
| **S3 Standard** | ≥3 | 99.99% | None | None | No | ms | Hot data, default |
| **S3 Intelligent-Tiering** | ≥3 | 99.9% | None | None (objects <128 KB are **not monitored**; they stay in the Frequent tier) | **No retrieval fees**. Per-object monitoring/automation fee | ms for Frequent, Infrequent (30 d) and Archive Instant Access (90 d) tiers. Optional **Archive Access** (≥90 d, activate; minutes–hours) and **Deep Archive Access** (≥180 d, activate; hours) need a restore | Unknown or changing access patterns, data lakes |
| **S3 Standard-IA** | ≥3 | 99.9% | **30 days** | **128 KB** | Per GB | ms | Backups, DR copies, older data still needing instant access |
| **S3 One Zone-IA** | **1** | 99.5% | **30 days** | **128 KB** | Per GB | ms | Re-creatable data, secondary CRR copies, thumbnails |
| **S3 Express One Zone** | **1 (you choose the AZ)** | 99.95% | None | None | No | **Single-digit ms**, up to 10x faster than Standard, lower request cost | Latency-sensitive ML training, analytics scratch, co-located with compute |
| **S3 Glacier Instant Retrieval** | ≥3 | 99.9% | **90 days** | **128 KB** | Per GB (higher than IA) | **ms** | Archive accessed about once a quarter that must be instant (medical images, news media) |
| **S3 Glacier Flexible Retrieval** | ≥3 | 99.99% (after restore) | **90 days** | 40 KB metadata overhead per object (32 KB billed at Glacier rate + 8 KB at Standard rate) | Per GB (Bulk is free) | **Expedited 1–5 min** (provisioned capacity optional), **Standard 3–5 h**, **Bulk 5–12 h** | Archives, backups needing minutes-to-hours access |
| **S3 Glacier Deep Archive** | ≥3 | 99.99% (after restore) | **180 days** | 40 KB overhead per object (same split) | Per GB | **Standard ≤12 h**, **Bulk ≤48 h** (no Expedited) | 7–10+ year compliance retention, tape replacement |

Key gotchas:
- **Early deletion:** if you delete, overwrite or transition an object before its minimum duration, you pay the remaining days pro rata.
- **Restored Glacier objects** are temporary copies billed at Standard rates for the restore period. The object's storage class stays GLACIER/DEEP_ARCHIVE.
- **Restore at scale:** use **S3 Batch Operations** restore jobs. The restore request rate is 1,000 TPS per account. Throughput is about 1–2 PB/day.
- **Reduced Redundancy Storage** is legacy. Never pick it.
- **One Zone-IA and Express One Zone are the only classes not resilient to the loss of an AZ.** A question that requires surviving an AZ loss rules them out.
- **Amazon Glacier (the original vault-based service, separate from the S3 Glacier storage classes)** stopped accepting new customers on **December 15, 2025**. *Exam view:* "Glacier Vault Lock" can still appear as a WORM option. *Current reality:* new designs use S3 Glacier storage classes plus **S3 Object Lock**.

### 2.3 Lifecycle rules

A lifecycle configuration has up to 1,000 rules per bucket. Rules are filtered by **prefix, object tags, and object size** (`ObjectSizeGreaterThan` / `ObjectSizeLessThan`). There are two action types:
- **Transition** actions move objects down the "waterfall": Standard → Standard-IA → Intelligent-Tiering → One Zone-IA → Glacier IR → Glacier Flexible → Deep Archive. Transitions only go **down**. You can't use lifecycle to move Glacier objects back up. To do that, restore the object and then copy it.
- **Expiration** actions:
  - expire current versions (this adds a delete marker in versioned buckets)
  - permanently delete **noncurrent versions** after N days, optionally keeping the newest N noncurrent versions
  - delete **expired object delete markers**
  - **abort incomplete multipart uploads** after N days. This is a classic cost-hygiene answer.

Transition constraints (verified):
- **Objects smaller than 128 KB are not transitioned by default** (since September 2024), because transition request costs would outweigh the storage savings. You can override this with an object-size filter.
- **30-day rule.** *Exam view:* objects must stay in Standard at least 30 days before a lifecycle transition to Standard-IA or One Zone-IA. *Current reality:* **in July 2026 AWS removed the 30-day waiting period**, so transitions can be set at 0 days. The **30-day minimum storage charge for IA classes still applies**. SAP-C02 answer keys were written under the old rule, so prefer answers consistent with it.
- A single rule cannot move an object out of a class before that class's minimum duration ends. Example: Glacier IR at day 4, then Deep Archive at day 20, is invalid. Deep Archive must be at ≥ day 94.
- Transitions to Glacier Flexible Retrieval or Deep Archive are billed from the date the rule is satisfied, even if the physical move happens later.
- Lifecycle **actions are not replicated** by S3 Replication. Configure the same rules on both buckets if you need them.

### 2.4 Versioning and MFA Delete

- Bucket states: **Unversioned → Enabled → Suspended**. You can never return to Unversioned.
- A DELETE without a version ID creates a **delete marker**. A DELETE with a version ID permanently removes that version.
- Versioning is **required** for Replication and Object Lock. It costs money because every version is billed, so pair it with noncurrent-version lifecycle rules.
- **MFA Delete** requires an MFA code to (a) change the bucket's versioning state or (b) permanently delete an object version. Only the **bucket owner's root user** can enable it, and only through the CLI or API, not the console. It is less flexible than Object Lock and doesn't work with lifecycle-driven deletes, so for ransomware protection at scale prefer **Object Lock + replication to a separate account**.

### 2.5 S3 Replication (CRR / SRR) — the Professional details

**Requirements:** versioning on both source and destination, and an IAM role S3 can assume (`s3:GetObjectVersionForReplication`, `s3:ReplicateObject`, `s3:ReplicateDelete`, `s3:ReplicateTags`). For cross-account replication, the destination bucket policy must allow the source role.

| Feature | Behaviour |
|---|---|
| **Live replication (CRR/SRR)** | Asynchronous. Replicates **only objects created after** the rule exists. Most objects arrive within 15 minutes, but there is no SLA (AWS's table says "24–48 hours, not SLA-backed" for completeness) |
| **S3 Replication Time Control (RTC)** | **SLA-backed: replicates most objects in seconds and 99.9% within 15 minutes** (some older AWS pages say 99.99%; the RTC page and SLA say 99.9%). The SLA does not apply while you exceed the S3 request-rate guidelines or the default **1 Gbps RTC transfer quota** (you can request an increase). Enables replication metrics and events (for example, `OperationMissedThreshold`). Extra cost. Does **not** apply to Batch Replication |
| **S3 Batch Replication** | On-demand job (runs through Batch Operations). Use it to replicate **existing objects**, **objects that previously FAILED**, **objects already replicated to another destination**, and **replicas of replicas** (chained A→B→C) |
| **Delete marker replication** | With a V2 configuration (rules with `Filter`), delete markers are **not replicated by default**. You can enable it on non-tag-based rules. **Deletes that specify a version ID are never replicated**, which protects against malicious deletion. Delete markers created by **lifecycle expiration are never replicated** |
| **Replica modification sync** | Replicates metadata changes (ACLs, tags, Object Lock settings) made **on replicas** back to the source. Used with **two-way (bi-directional) replication**, for example behind Multi-Region Access Points |
| **Ownership override** (`AccessControlTranslation` / owner override) | Cross-account replicas become owned by the **destination account**. Today, setting **Object Ownership = Bucket owner enforced** on the destination achieves the same result and disables ACLs |
| **Encrypted objects** | SSE-S3 and **SSE-C** objects replicate by default. **SSE-KMS and DSSE-KMS objects are NOT replicated unless you opt in** with `SourceSelectionCriteria > SseKmsEncryptedObjects = Enabled` **and** specify `ReplicaKmsKeyID`, a symmetric **customer managed key in the destination Region**. The role needs `kms:Decrypt` on the source key and `kms:Encrypt` on the destination key. **Cross-account:** you must use a customer managed key, because AWS managed keys (`aws/s3`) can't be used cross-account, and the destination key policy must allow the source account's role. High volumes can hit KMS throttling (503s), so request a KMS quota increase or use Bucket Keys |
| **What is NOT replicated** | Objects already existing before the rule (use Batch Replication); objects in **Glacier Flexible, Deep Archive, or Intelligent-Tiering Archive/Deep Archive tiers**; bucket-level configuration (lifecycle, notifications, policies); lifecycle actions; objects the bucket owner lacks permission to read; objects tagged **after** PUT under tag-based rules |
| **Multiple destinations** | One source can replicate to many destination buckets (different Regions/accounts). Replicas can go straight into a cheaper class (for example, Glacier Deep Archive or One Zone-IA in the DR bucket) |

S3 replication treats multi-Region KMS keys like single-Region keys. You still name a destination-Region key.

### 2.6 S3 Object Lock (WORM)

- Requires versioning. You can enable it on new **or existing** buckets. Once enabled, you can't disable it.
- Works per **object version**. Two independent mechanisms:
  - **Retention period** in one of two modes:
    - **Governance mode:** users with `s3:BypassGovernanceRetention` can override it if they send the `x-amz-bypass-governance-retention` header.
    - **Compliance mode:** **nobody, including the root user**, can delete the version or shorten its retention until it expires. The retention period can be extended but not shortened.
  - **Legal hold:** on/off flag with no expiry. Needs `s3:PutObjectLegalHold`. Independent of retention.
- **Default retention** on the bucket applies to new objects.
- Assessed for SEC 17a-4(f), FINRA, and CFTC requirements.
- Replication copies retention settings to replicas. **S3 Batch Operations** can apply retention or legal holds to billions of existing objects.

### 2.7 Access control: Block Public Access, Object Ownership, policies, access points

**Evaluation logic:** an explicit Deny anywhere wins. Within one account, IAM policy **or** bucket policy can allow. **Cross-account access needs both** the caller's IAM policy and the bucket policy (or an ACL / access point policy) to allow it. SCPs and RCPs (resource control policies) are guardrails on top.

- **S3 Block Public Access (BPA):** four settings (block new public ACLs, ignore public ACLs, block new public bucket policies, restrict public buckets). Can be set at the **account level** (and enforced organisation-wide via policies) and at the bucket level. **On by default for new buckets since April 2023.** If a stem says "ensure no bucket in any account can ever be public", the answer is account-level BPA plus an SCP denying `s3:PutAccountPublicAccessBlock` changes.
- **S3 Object Ownership:**
  - **Bucket owner enforced** (default for new buckets since April 2023): **ACLs disabled**, and the bucket owner owns every object. This fixes the classic "cross-account uploader owns the object, and the bucket owner can't read it" problem.
  - **Bucket owner preferred** and **Object writer** are legacy settings.
- **Bucket policies:** resource-based. Use them for cross-account access, enforcing TLS (`aws:SecureTransport`), enforcing encryption headers or KMS key, restricting to a VPC endpoint, restricting to an organisation (`aws:PrincipalOrgID`), or restricting to IP ranges. Size limit 20 KB, which is why access points exist.
- **S3 Access Points:**
  - Named network endpoints, each with its **own policy**. They simplify a shared data lake with hundreds of consumers.
  - An access point can be **restricted to a VPC** (network origin = VPC), so it only accepts requests from that VPC through an endpoint.
  - **Delegation pattern:** the bucket policy delegates access control to access points owned by the same account (condition `s3:DataAccessPointAccount`). Each team then manages its own access point policy. Cross-account access points are supported.
  - Access points can also front FSx for OpenZFS/ONTAP volumes. S3 Object Lambda access points also exist (see below).
- **Multi-Region Access Points (MRAP):**
  - A **single global endpoint** that routes requests over the AWS backbone (Global Accelerator-based) to the **closest healthy bucket** in up to 17 supported Regions.
  - **Failover controls:** set Regions **active or passive** to build an **active-passive** design, then shift traffic in minutes through the routing-control API (failover is between two Regions at a time).
  - Pair it with **two-way CRR plus replica modification sync** so writes made after failover flow back. Add **RTC** to bound RPO.
  - Requests must be signed with SigV4A.
- **S3 Access Grants:** map corporate directory identities (IAM Identity Center users and groups) to S3 prefixes at scale. Useful for "thousands of workforce users need per-folder access".
- **Presigned URLs:**
  - Grant time-limited access to a single object operation (GET or PUT) using the **signer's** permissions.
  - Maximum **7 days** when signed with long-term IAM user credentials (SigV4). The URL stops working earlier if the signing role session expires.
  - Common pattern: browser uploads directly to S3 via a presigned PUT or POST, so large files never pass through the app tier.

### 2.8 Performance

- **At least 3,500 PUT/COPY/POST/DELETE and 5,500 GET/HEAD requests per second per partitioned prefix.** There's no limit on the number of prefixes, so spread keys across prefixes (for example, hash or date shards) and parallelise.
  - Example: 10 prefixes ≈ 55,000 GET/s.
  - Scaling is gradual, and you'll see **HTTP 503 Slow Down** while S3 re-partitions. Retry with exponential backoff.
- **SSE-KMS can be the real bottleneck.** Every object request calls KMS, and KMS has per-Region request quotas. Use **S3 Bucket Keys** or request a quota increase.
- **Multipart upload:**
  - Recommended above 100 MB, required above 5 GB per PUT. Parts are 5 MiB–5 GiB, up to 10,000 parts.
  - Parallel parts give higher throughput and resilience, because a failed part is simply retried.
  - Add a lifecycle rule to **abort incomplete multipart uploads**.
- **Byte-range fetches:** parallel ranged GETs speed up downloads and let you read only part of an object (for example, file headers).
- **S3 Transfer Acceleration:**
  - Uploads enter at the nearest **CloudFront edge location** and travel over the AWS backbone to the bucket.
  - Requires a DNS-compliant bucket name with no dots and uses the `bucket.s3-accelerate.amazonaws.com` endpoint.
  - You pay only when the transfer is actually accelerated.
  - Best for **long-distance uploads of large objects by globally distributed clients**. It doesn't help clients in the same Region.
- **CloudFront** caches reads. **S3 Express One Zone** gives single-digit-ms latency and very high request rates per directory bucket, and authenticates with **`CreateSession`** session tokens. **Mountpoint for Amazon S3** gives high-throughput file-like reads for data lakes and ML.

### 2.9 Event-driven S3

| | **S3 Event Notifications** | **Amazon EventBridge** (enable on bucket) |
|---|---|---|
| Destinations | SNS, **SQS standard (not FIFO)**, Lambda | 20+ targets (Step Functions, Kinesis, API destinations, other accounts/buses, etc.) |
| Filtering | Prefix/suffix only. A prefix/suffix combination can't overlap between rules for the same event type | Advanced content filtering on any field (size, metadata, requester) |
| Extras | Simple, cheap, low latency | Archive & replay, multiple rules per event, cross-account buses, schema registry |
| When the exam wants it | "Trigger a Lambda on upload to prefix X" | "Several consumers", "filter on object size/metadata", "replay", "fan out to Step Functions" |

Both deliver at least once, so make consumers idempotent. For fan-out with notifications, send to SNS and then to several SQS queues.

### 2.10 Data management at scale

- **S3 Batch Operations:**
  - Runs one operation on billions of objects from a manifest (an **S3 Inventory** report or a CSV).
  - Operations: copy (including cross-account and storage-class change), **invoke Lambda**, replace tags, replace ACLs, **restore from Glacier**, **set Object Lock retention / legal hold**, **Batch Replication**, compute checksums.
  - Gives you a completion report and retries.
  - Answer for "re-encrypt or re-tag 2 billion existing objects with least effort".
- **S3 Inventory:** daily or weekly CSV, ORC, or Parquet list of objects with metadata (encryption status, replication status, storage class, Object Lock). Query it with Athena. It's the standard manifest source for Batch Operations.
- **S3 Storage Lens:**
  - Organisation-wide storage analytics dashboard (delegated admin supported).
  - **Free metrics** keep 14 days of history.
  - **Advanced metrics & recommendations** (paid) keep 15 months and add activity metrics, prefix-level aggregation, CloudWatch publishing, and cost-optimisation and data-protection recommendations, such as buckets without lifecycle rules for incomplete multipart uploads or buckets without versioning.
- **Storage Class Analysis:** observes access patterns and recommends when to move data to Standard-IA.
- **Requester Pays:** the requester pays request and data-transfer costs, and the bucket owner pays for storage. Requests must include `x-amz-request-payer: requester`, and anonymous access is not allowed. Use it to share large datasets with partners or researchers.
- **S3 Object Lambda:**
  - Transforms data on GET using a Lambda function behind an Object Lambda access point (redact PII, resize images, convert formats).
  - *Current reality:* **closed to new customers since November 7, 2025**. AWS suggests Lambda behind CloudFront, API Gateway, or function URLs instead.
  - *Exam view:* it can still be the correct answer for "different consumers need different views of the same object without storing copies".
- **S3 Tables:** **table buckets** store **Apache Iceberg** tables. Tables are first-class resources with table-level permissions and automatic maintenance (compaction, snapshot management, unreferenced-file removal). They integrate with Athena, Redshift, EMR, and Glue/Lake Formation via the AWS analytics integration. Use them for a managed, high-TPS Iceberg data lake.
- **S3 Metadata:** automatically maintained, queryable Iceberg tables (stored in an AWS managed table bucket) containing a **journal table** (near-real-time change log) and an optional **live inventory table** (current state of all objects). Use it to find objects by metadata with SQL instead of LIST calls.
- **Emerging (not core):** **S3 Vectors** (vector buckets for embeddings and RAG, GA December 2025, integrates with Bedrock Knowledge Bases and OpenSearch).

### 2.11 Amazon EBS

EBS is **network-attached block storage, scoped to one AZ**. A volume can attach only to instances in its AZ, and is replicated within that AZ. To move data across AZs or Regions, take a **snapshot** and copy it.

| Type | Media | Size | Max IOPS / volume | Max throughput / volume | Key facts |
|---|---|---|---|---|---|
| **gp3** | SSD | 1 GiB–**64 TiB** | **80,000** (500 IOPS/GiB; max reached at 160 GiB) | **2,000 MiB/s** (0.25 MiB/s per provisioned IOPS) | **Baseline 3,000 IOPS + 125 MiB/s included regardless of size**. Performance provisioned **independently of size**. About 20% cheaper per GiB than gp2. Default choice. *(Older material and exam keys: 16,000 IOPS / 1,000 MiB/s / 16 TiB. Limits were raised in 2025.)* |
| **gp2** | SSD | 1 GiB–16 TiB | 16,000 (3 IOPS/GiB, minimum 100; max at 5,334 GiB) | 250 MiB/s | Performance tied to size. Volumes under 1 TiB **burst to 3,000 IOPS** with I/O credits (watch `BurstBalance`). Over-provisioning size to get IOPS is the classic cost trap → move to gp3 |
| **io2 Block Express** | SSD | 4 GiB–64 TiB | **256,000** (Nitro) | **4,000 MiB/s** | **99.999% durability**, sub-ms (<500 µs average) latency, **Multi-Attach**, NVMe reservations. Pick it for mission-critical databases (Oracle, SAP HANA, SQL Server) |
| **io1** | SSD | 4 GiB–16 TiB | 64,000 | 1,000 MiB/s | Previous-gen provisioned IOPS, 99.8–99.9% durability. io2 is better and cheaper for most uses |
| **st1** | HDD | 125 GiB–16 TiB | 500 (1 MiB I/O) | **500 MiB/s** | Throughput-optimised: big data, log processing, data warehouses, Kafka. **Not bootable** |
| **sc1** | HDD | 125 GiB–16 TiB | 250 | 250 MiB/s | Cold HDD, lowest cost. **Not bootable** |

- **Instance limits matter too.** Each instance type has a maximum EBS bandwidth and IOPS. A 256,000-IOPS volume on a small instance won't reach 256,000. Non-Nitro instances can attach volumes provisioned above 64,000 IOPS but achieve at most 32,000.
- **EBS-optimized** gives dedicated EBS bandwidth. It's default and free on current-generation instances.
- **RAID 0** across volumes adds throughput and IOPS. Never use RAID 5/6, which wastes IOPS on parity.
- **Elastic Volumes:** change type, size, IOPS, and throughput **online** (for example, gp2 → gp3 with no downtime). Size can only grow. After modifying, extend the file system yourself. There's a cooldown before the next modification.
- **Multi-Attach:**
  - Works on **io1/io2 only**, up to **16 Nitro instances in the same AZ**. Windows supports io2 only.
  - Requires a **cluster-aware file system** (not XFS/ext4) and application-level write ordering (I/O fencing via NVMe reservations).
  - Not available for boot volumes.
  - Not a substitute for EFS or FSx when you need shared files.
- **Snapshots:**
  - Stored in AWS-managed S3 storage, **incremental** (only changed blocks; deleting an older snapshot doesn't break newer ones). Regional.
  - Can be copied **cross-Region and cross-account**, including **time-based copy** with a guaranteed completion duration.
  - **Encrypted snapshot sharing requires a customer managed KMS key**. You can't share snapshots encrypted with the default `aws/ebs` key.
  - **Lazy loading:** a volume restored from a snapshot pulls blocks from S3 on first access, so first reads are slow. Fixes:
    - **Fast Snapshot Restore (FSR):** enabled per snapshot **per AZ**, billed per AZ-hour, default **5 FSR-enabled snapshots per Region**, uses volume-creation credits, snapshots ≤16 TiB.
    - Initialise manually (read every block with `fio`/`dd`).
    - Use provisioned initialisation rate when creating volumes.
  - **EBS Snapshots Archive:** converts the snapshot to a **full** snapshot in a low-cost tier, up to 75% cheaper. **90-day minimum.** Restore takes **24–72 hours**. Use it for end-of-project or compliance snapshots, not routine backups.
  - **Recycle Bin:** retention rules (tag- or Region-level) that keep deleted **EBS snapshots and EBS-backed AMIs** recoverable for a set period. Rules can be **locked**. Protects against accidental or malicious deletion.
  - **Amazon Data Lifecycle Manager (DLM):** policy-based creation, retention, cross-Region/cross-account copy of EBS snapshots and EBS-backed AMIs, at no extra charge. Choose **AWS Backup** instead when you need cross-service, organisation-wide policies, vault immutability, or compliance reports.
- **Encryption:**
  - **Encryption by default** is a per-account, **per-Region** setting. Encryption uses AES-256 with KMS, covers data at rest, in transit between instance and volume, snapshots, and volumes created from them, and has negligible performance impact.
  - To encrypt an existing unencrypted volume: **snapshot → copy the snapshot with encryption → create a volume** (or restore with encryption enabled). You can't encrypt a volume in place.
  - To enforce it, use an SCP or Config rule plus encryption-by-default in every Region (for example, via StackSets or Control Tower controls).
- **Instance store vs EBS:**

| | Instance store | EBS |
|---|---|---|
| Persistence | **Ephemeral**: lost on stop, hibernate, terminate, or host failure. Survives reboot | Persistent, independent lifecycle |
| Performance | Highest (local NVMe, millions of IOPS on some types), included in instance price | Up to 256,000 IOPS per io2 BX volume |
| Snapshots/backup | None built in | Snapshots, AWS Backup, DLM |
| Use | Caches, buffers, scratch, temp; **replicated** data stores (Cassandra, Kafka, Elasticsearch with replicas) | Boot volumes, databases, anything that must survive |

### 2.12 Amazon EFS

- **Managed NFS (v4.0/v4.1) file system** for **Linux** clients (EC2, ECS, EKS via CSI driver, Lambda, on-prem). It **is not for Windows SMB**; use FSx for Windows for that. Pay per GB used, elastic to petabytes, POSIX permissions, close-to-open consistency, NFS advisory locking.
- **File system types:**
  - **Regional** (data across ≥3 AZs, 99.99% availability; recommended).
  - **One Zone** (single AZ, cheaper, 99.9%, backed up automatically with AWS Backup).
- **Mount targets:** one per AZ (ENI with an IP). Security groups must allow TCP 2049. Use the **EFS mount helper** (`amazon-efs-utils`) for **TLS encryption in transit** and IAM authorisation. **Encryption at rest** must be chosen **at creation**; to change it later, create a new file system and copy the data.
- **Performance modes:**
  - **General Purpose** is the default, lowest latency, and required for One Zone and Elastic throughput.
  - **Max I/O** is previous generation, higher latency, and not supported with Elastic throughput or One Zone. AWS now recommends General Purpose for everything. An exam answer that says "Max I/O for highly parallel workloads" reflects the older guidance.
- **Throughput modes:**
  - **Elastic** (default, recommended): scales automatically. You pay per GB read/written. Regional file systems reach up to 20–60 GiBps read, 1–5 GiBps write (Region-dependent) and up to 1,500 MiBps per client with efs-utils v2+. Best for spiky workloads, where average throughput is ≤5% of peak.
  - **Provisioned:** set a throughput level independent of size, for known steady high throughput. After switching to it, you can't decrease or switch away for 24 h.
  - **Bursting:** baseline 50 KiBps per GiB stored in Standard (50 MiBps per TiB) with burst credits. Small file systems run out of credits. The classic fix for "EFS is slow and the file system is small" is **switch to Elastic** (or Provisioned).
- **Storage classes & lifecycle:**
  - **Standard** (SSD, sub-ms).
  - **Infrequent Access (IA)**: tens of ms, 128 KiB minimum billable per file.
  - **Archive**: tens of ms, **90-day minimum**, **Elastic throughput only**.
  - Lifecycle policies move files to IA or Archive after N days without access, and optionally **back to Standard on first access**. (One Zone file systems use the same storage tiers but within one AZ.)
- **Access points:** application-specific entry points that **enforce a POSIX user/group and a root directory**. Combine them with IAM file system policies for multi-tenant containers or Lambda functions.
- **Replication:** to another Region or AZ, **including cross-account**.
  - Destination is **read-only** until you fail over (delete the replication configuration).
  - **RPO 15 minutes for most file systems**. Monitor with `TimeSinceLastSync`.
  - Failback: reverse the replication direction.
- **Hybrid access:** on-prem servers mount EFS over **Direct Connect or Site-to-Site VPN** using the **mount target IP**. DNS names need a Route 53 Resolver inbound endpoint or hosts entries. EFS is also usable across VPCs via peering or Transit Gateway. Use DataSync to migrate or keep it in sync.
- **Backup:** AWS Backup (automatic backups on by default for new file systems created in the console).

### 2.13 Amazon FSx family

**FSx for Windows File Server**
- Fully managed native Windows file servers: **SMB 2.0–3.1.1**, NTFS ACLs, **Active Directory integration required** (AWS Managed Microsoft AD or **self-managed on-prem AD**), Volume Shadow Copies (end-user restores), data deduplication, quotas, SSD or HDD.
- **Deployment types:**
  - Single-AZ 1 (legacy, the only type supporting **DFS Replication**).
  - Single-AZ 2.
  - **Multi-AZ**: an active/standby Windows Server Failover Cluster across two AZs with synchronous replication. **Automatic failover typically < 30 s.** DNS name unchanged, so failover is transparent to Windows clients. Linux SMB clients don't fail over automatically. AWS recommends Multi-AZ for most production workloads.
- **DFS Namespaces** group several file systems under one namespace (scale beyond a single file system, or migrate share-by-share). **Continuously available (CA) shares** on Multi-AZ suit **SQL Server Always On FCI** storage.
- Accessible from on-prem over DX/VPN. Migrate with **DataSync** (Basic mode), which preserves NTFS ACLs, or with Robocopy.
- **FSx File Gateway** (on-prem cache for FSx for Windows) has been **closed to new customers since October 28, 2024**. AWS now suggests connecting clients directly over SMB (client-side caching), or FSx for ONTAP FlexCache.

**FSx for Lustre**
- Parallel, POSIX, sub-ms file system for **HPC, ML training, genomics, media rendering, EDA, financial simulation**. Throughput scales to hundreds of GB/s and millions of IOPS. Linux clients.
- **Deployment types:**
  - **Scratch** (Scratch 1/2): **no replication, data lost if a server fails**, 200 MBps/TiB baseline with burst up to 6x. **Cheapest. For short-term jobs.**
  - **Persistent** (Persistent 1/2): replicated **within one AZ** (Intelligent-Tiering storage replicates across AZs), failed servers replaced automatically. Persistent 2 offers 125–1,000 MBps/TiB on SSD. For long-running workloads.
- **Storage classes:** SSD, HDD (Persistent 1, optional SSD read cache), **Intelligent-Tiering** (elastic, auto-tiers to IA after 30 days and Archive Instant after 90 days).
- **Data Repository Association (DRA) with S3:** link a file system directory to an S3 prefix. Files are **lazy-loaded** on first access (metadata imported). **Automatic import/export** keeps S3 and Lustre in sync. Typical flow: data lake in S3 → spin up Lustre → compute → export results to S3 → delete Lustre.
- **EFA and GPUDirect Storage** support on Persistent 2 for GPU clusters.

**FSx for NetApp ONTAP**
- Managed NetApp ONTAP: **multi-protocol NFS (v3/v4.x), SMB, iSCSI, and NVMe/TCP** on the **same data**.
- **Multi-AZ or Single-AZ** HA pairs, plus scale-out (multiple HA pairs). SSD tier plus an elastic **capacity pool** tier with automatic tiering. Deduplication, compression, compaction (big storage savings).
- **Snapshots, FlexClone** (instant writable clones for dev/test), **SnapMirror** (replication from on-prem NetApp → AWS, or Region → Region for DR), **SnapLock** (WORM), **FlexCache** (cache volumes near users), antivirus (Vscan), AD integration.
- Pick it for **"migrate on-prem NetApp with minimal change"**, **"Linux and Windows clients accessing the same data"**, **"iSCSI LUNs for databases or VMware Cloud on AWS datastores"**, or **"existing SnapMirror tooling"**.

**FSx for OpenZFS**
- Managed OpenZFS over **NFS v3/v4.0/v4.1/v4.2** for Linux, Windows, and macOS.
- Up to **2 million IOPS** with hundreds-of-µs latency (from cache). Instant **snapshots and clones**, compression, per-volume quotas.
- **Deployment types:** Multi-AZ (HA), Single-AZ (HA), Single-AZ (non-HA). HA failover typically ≤60 s.
- **Storage classes:** SSD or Intelligent-Tiering.
- Pick it for **"migrate on-prem ZFS or Linux NFS file servers"**, **"latency-sensitive NFS workloads (EDA, media, analytics)"**, or **"instant clones for dev/test"**. It is NFS only (no SMB, no iSCSI).

### 2.14 AWS Storage Gateway

Hybrid storage that runs on-prem as a VM (VMware ESXi, Hyper-V, KVM, Nutanix AHV) or in AWS on **EC2**. It presents local protocols and stores data in AWS, with a **local cache** for low-latency access to hot data and an upload buffer. The **Storage Gateway Hardware Appliance is no longer sold (as of May 12, 2025)**; existing appliances are supported until May 2028.

| Gateway | Protocol on-prem | Data lands in | Key facts |
|---|---|---|---|
| **S3 File Gateway** | **NFS (v3/v4.1) and SMB** | **S3 objects (one file = one object)**, in Standard, Standard-IA, One Zone-IA or Intelligent-Tiering | Native S3 objects usable by analytics and Lambda. Lifecycle to Glacier is possible, but objects must be restored before the gateway can read them. Use `RefreshCache` when other apps write to the bucket directly. SMB with AD authentication. File-share audit logs. Good for backups to S3, data-lake ingest, and on-prem apps needing cloud-backed shares |
| **FSx File Gateway** | SMB | FSx for Windows | **Closed to new customers since October 28, 2024**. Existing customers continue. *Exam view:* "on-prem low-latency SMB cache for FSx for Windows" |
| **Volume Gateway — Cached** | iSCSI block volumes | Primary data in S3 (AWS-managed), hot data cached locally | Up to **32 TiB per volume**, 32 volumes, **1,024 TiB per gateway**. Point-in-time snapshots appear as **EBS snapshots**. Use it to reduce on-prem SAN capacity |
| **Volume Gateway — Stored** | iSCSI | **Full dataset on-prem**, asynchronously backed up as EBS snapshots | Up to **16 TiB per volume**, 32 volumes, **512 TiB per gateway**. Low-latency access to all data plus offsite backup/DR (restore to EC2 from EBS snapshot) |
| **Tape Gateway** | iSCSI **Virtual Tape Library** (media changer + tape drives) | Virtual tapes in S3. **Archived tapes move to S3 Glacier Flexible Retrieval or Glacier Deep Archive** | Works with existing backup software (Veeam, NetBackup, Commvault, Backup Exec, etc.) **without changing workflows**. Tape retention lock. **Answer for "replace physical tape / offsite tape vaulting"** |

AWS Backup can back up Volume Gateway volumes. Gateways can use a VPC interface endpoint so activation and data traffic stay private over DX/VPN.

### 2.15 Data transfer services

**AWS DataSync** (online, managed, recurring or one-time)
- Moves files and objects between **on-prem NFS, SMB, HDFS, and self-managed object storage**, **other clouds** (Google Cloud Storage, Azure Blob/Files, Wasabi, Cloudflare R2, Backblaze B2, OCI, IBM COS, and others), and **AWS storage**: S3 (any class, including Glacier/Deep Archive), EFS, all four FSx types.
- **Agent:** a VM (VMware, Hyper-V, KVM) or EC2 instance, required for on-prem or self-managed sources. **Enhanced mode** handles virtually unlimited object counts with parallel list, transfer, and verify. It transfers between S3, EFS, FSx for Lustre, and FSx for OpenZFS **with no agent**, and between other clouds' object storage and S3 with no agent. **Basic mode** is required for some locations, for example FSx for Windows.
- **Features:**
  - Purpose-built parallel protocol, typically much faster than rsync or robocopy.
  - TLS in transit, integrity **verification**.
  - Incremental (changed data only), preserves metadata (POSIX, NTFS ACLs, timestamps).
  - Include/exclude **filters** and **manifests**.
  - **Scheduling** (hourly, daily, cron).
  - **Bandwidth throttling** (adjustable during a run).
  - Task reports, CloudWatch and EventBridge integration.
- **Network:** public endpoint, FIPS endpoint, or a **VPC interface endpoint**, so traffic flows privately over **Direct Connect or VPN**.
- Exam answer for: "migrate 200 TB of NFS/SMB to EFS/FSx/S3 over DX, then keep it in sync until cutover"; "nightly copy of new files"; "copy between AWS Regions/accounts"; "move data from Azure/GCS to S3".

**AWS Transfer Family** (managed file-transfer endpoints for partners and users)
- **Protocols:** **SFTP, FTPS, FTP, AS2**, plus browser-based **Transfer Family web apps**. Backends are **S3 or EFS**. Multi-AZ (up to 3 AZs).
- **Endpoint types:**
  - **Public:** SFTP only.
  - **VPC, internal**, or **VPC, internet-facing with Elastic IPs**: static IPs that partners can allow-list, and security groups to restrict source IPs.
  - **FTP (unencrypted) is supported only on VPC internal endpoints.**
- **Identity:**
  - Service-managed users (SSH keys, SFTP only).
  - **AWS Directory Service / Microsoft AD**.
  - **Custom identity provider** via **Lambda or API Gateway** (Okta, Entra ID, Cognito, Secrets Manager passwords, LDAP).
- **Logical directories** give chroot-style home directories mapped to buckets and prefixes.
- **Managed workflows** run post-upload steps (copy, tag, delete, **PGP decrypt**, custom Lambda such as malware scan). **SFTP connectors** push or pull files to or from remote partner SFTP servers. **AS2 connectors** handle B2B EDI.
- Exam answer for: "partners currently SFTP to our on-prem server; move it to AWS without changing partner clients; land files in S3; authenticate with our existing IdP".

**AWS Snow Family** (offline, physical)
- **Current reality (verify on exam day; this is the 2026 state):**
  - **Snowcone** (SSD and HDD) was discontinued November 12, 2024, with support for existing devices ending November 12, 2025.
  - **Snowball Edge previous-generation models** (80 TB Storage Optimized, 52-vCPU and GPU Compute Optimized) were discontinued November 12, 2024.
  - **Snowball Edge (Storage Optimized 210 TB and Compute Optimized 104 vCPU) has been available only to existing customers since November 7, 2025.** In practice, **no Snow Family device can be ordered by a new customer today.**
  - **Snowmobile** (100 PB truck) is no longer offered.
  - AWS now points new customers to **AWS DataSync** (online), **AWS Data Transfer Terminal** (physical sites where you bring your own storage devices and upload at high speed over a direct AWS connection), AWS Partner solutions, and **AWS Outposts** for edge compute.
- **Exam view (still what SAP-C02 questions expect):**
  - **Snowball Edge Storage Optimized** is for multi-TB to PB migrations where the network is too slow or too expensive, or for disconnected sites.
  - **Snowball Edge Compute Optimized** is for edge compute in disconnected or rugged environments (EC2-compatible instances, EKS Anywhere, S3-compatible storage, clustering of 3–16 devices).
  - **Snowcone** is for tiny, portable edge collection. **Snowmobile** is for exabyte scale (≥10 PB).
  - Data is always **encrypted** (KMS keys; keys never stored on the device). Devices are tamper-evident with E Ink shipping labels and managed through **AWS OpsHub**.
  - **Snowball imports go into S3.** To end up in Glacier, import into S3 and apply a **lifecycle rule**. You can't import straight into a Glacier vault.
  - Typical end-to-end time is about a week per device cycle (order, ship, copy, ship back, ingest). Several devices in parallel scale the job.

**Online vs offline: bandwidth math (do this in your head on exam day)**

```text
Transfer time (seconds) = Data (bits) / (Link speed (bits/s) × Utilisation)

Data (bits) = TB × 8 × 10^12          (decimal TB, as storage vendors quote)

Days = (TB × 8 × 10^12) / (Gbps × 10^9 × U × 86,400)
     ≈ TB / (10.8 × Gbps × U)          ← handy shortcut: 1 Gbps ≈ 10.8 TB/day at 100%

Examples (100% utilisation unless stated):
  100 TB over 1 Gbps    = 8×10^14 / 10^9 = 800,000 s ≈ 9.3 days
  100 TB over 1 Gbps @80% ≈ 11.6 days
  100 TB over 10 Gbps   ≈ 0.93 days (~22 h)
  1 PB over 1 Gbps      ≈ 93 days     → offline / bigger pipe
  1 PB over 10 Gbps @80% ≈ 11.6 days
  50 TB over 100 Mbps   ≈ 46 days     → offline (Snowball, exam view)
```

Rules of thumb:
- If online transfer at realistic utilisation (60–80%, and only the spare capacity on a shared link) takes **longer than about a week, or longer than the project window**, the exam answer is usually **Snowball Edge** (exam view).
- If the link is fast enough, use **DataSync** (files) or **S3 multipart / Transfer Acceleration** (objects from many distant clients).
- Ordering Direct Connect takes **weeks to months**, so "need to move data in 2 weeks, no DX today" rules out a new DX.
- For ongoing hybrid sync after the bulk load, use DataSync schedules or Storage Gateway.

### 2.16 AWS Backup

**Centralised, policy-based backup** across AWS services and some on-prem/hybrid resources.
- **Supported resources (current):**
  - Compute and block: EC2 (EBS-backed), EBS, Storage Gateway volumes.
  - Object and file: **S3**, **EFS**, **FSx (all four)**.
  - Databases: **DynamoDB**, RDS (all engines, including Multi-AZ clusters), Aurora, **Aurora DSQL**, DocumentDB, Neptune, Redshift (provisioned and Serverless), Timestream for LiveAnalytics, **SAP HANA on EC2**.
  - Other: VMware (on-prem, VMware Cloud on AWS), **CloudFormation stacks**, **EKS clusters and persistent storage**.
- **Building blocks:**
  - **Backup plan:** rules with schedule (cron or frequency), backup window, **lifecycle** (warm → cold storage for supported types; cold requires ≥90 days), retention, **copy actions** (to another Region and/or account), and **continuous backup / PITR** for supported services (for example, RDS, S3, SAP HANA).
  - **Resource assignment:** by **tags**, resource ARNs, or conditions.
  - **Backup vault:** a container for recovery points, **encrypted with its own KMS key** (for fully managed resource types, independent of the source key), with a **vault access policy** (for example, deny `DeleteRecoveryPoint`).
- **AWS Backup Vault Lock:**
  - **Governance mode:** removable by users with sufficient IAM permissions.
  - **Compliance mode:** after a **grace time of at least 3 days (72 h)**, the lock and retention **cannot be changed or removed by anyone, including the root user or AWS**. Min/max retention enforced on new jobs. Assessed for SEC 17a-4, CFTC, FINRA.
- **Logically air-gapped vault:**
  - A special vault **always locked in compliance mode**. Backups are stored in an AWS service-owned account, encrypted with an AWS owned key (or optionally a CMK).
  - **Shareable via AWS RAM** to other accounts, even outside your organisation, for fast restore or restore testing. Integrates with **Multi-party approval** so you can recover even if the owning account is compromised or closed.
  - Use it for **ransomware resilience**.
- **Cross-Region copy:** for DR distance or compliance. **Cross-account copy:** requires **AWS Organizations**. Typical "fan-in" to a central backup account whose vault access policy only allows copies in.
- **AWS Organizations backup policies:** the management account (or a delegated administrator) pushes backup plans to OUs and accounts, so plans are created and enforced automatically in member accounts. Combine with **SCPs** that deny tampering with backup roles or vaults.
- **Legal holds:** keep selected recovery points beyond their retention (for litigation) until the hold is released.
- **Restore testing:** scheduled, automated test restores with validation (for example, a Lambda check) and automatic cleanup. Proves RTO and that backups really restore.
- **AWS Backup Audit Manager:** frameworks of **controls** (for example, "resources are protected by a backup plan", "backups encrypted", "cross-Region copy exists", "vault locked", "copy in a logically air-gapped vault"), daily **reports**, and integration with AWS Audit Manager. This is the answer for **"prove backup compliance to auditors"**.
- **Pricing:** backup storage (warm/cold), restores, restore testing, cross-Region data transfer, Audit Manager evaluations. Incremental backups for supported types (EBS, EFS, S3, and others) keep cost down.

---

## 3. Architecture patterns

### Pattern 1 — Cost-optimised object lifecycle with compliance lock

```text
 Ingest (apps, Firehose, DataSync)
          │
          ▼
 ┌────────────────────┐ day 0–30  ┌──────────────────┐ day 30–90 ┌───────────────────┐ day 90+  ┌────────────────────┐
 │ S3 Standard        │──────────►│ S3 Standard-IA   │──────────►│ S3 Glacier IR /   │────────►│ S3 Glacier Deep    │
 │ (or Int-Tiering if │ lifecycle │ (≥128 KB objects)│ lifecycle │ Flexible Retrieval│lifecycle│ Archive (7–10 yrs) │
 │  pattern unknown)  │           └──────────────────┘           └───────────────────┘         └─────────┬──────────┘
 └────────────────────┘                                                                                  │ expire at
   Object Lock (Compliance, default retention 7y) + versioning + noncurrent-version expiry       day 2,555 │
   Lifecycle: abort incomplete MPU after 7 days                                                           ▼  delete
```
- **Use when** access drops predictably with age and regulation needs WORM.
- **Trade-offs:** minimum durations and per-object transition fees. Small objects should be aggregated (tar/Parquet) before archiving to avoid the 40 KB Glacier overhead and per-request costs. Use Intelligent-Tiering instead when access is unpredictable.

### Pattern 2 — Ransomware-resilient cross-account replication ("data bunker")

```text
   Production account (Region A)                          Backup/Log-archive account (Region B)
 ┌───────────────────────────────┐   CRR + RTC (15 min)  ┌────────────────────────────────────┐
 │ Bucket: prod-data (versioned) │══════════════════════►│ Bucket: bunker (versioned)         │
 │ SSE-KMS (CMK-A)               │  SseKmsEncryptedObjects│ SSE-KMS (CMK-B, key policy allows  │
 │ Replication role: decrypt A,  │  = Enabled             │   source role kms:Encrypt)         │
 │   encrypt B                   │  ReplicaKmsKeyID=CMK-B │ Object Ownership: bucket owner     │
 │ Delete-marker replication OFF │  Owner override        │   enforced; Object Lock Compliance │
 └───────────────────────────────┘                        │ Bucket policy: deny all but repl.  │
        │ existing objects                                │   role + break-glass; SCP protects │
        └── S3 Batch Replication (one-time) ─────────────►│ Lifecycle → Glacier Deep Archive   │
                                                          └────────────────────────────────────┘
```
- Deletes and delete markers in production don't propagate, and versioned deletes are never replicated. Object Lock in the bunker means even a compromised admin in the bunker account can't purge data.
- **Trade-offs:** you pay twice for storage, plus replication, inter-Region transfer, and KMS requests. RTC adds cost but gives an SLA-backed RPO.

### Pattern 3 — Multi-Region active-passive S3 with a single endpoint

```text
                      Application (any Region)  ── SigV4A ──►  S3 Multi-Region Access Point
                                                                   │ routing: Region A = active
                                                                   │          Region B = passive
                              ┌────────────────────────────────────┴───────────────────────┐
                              ▼                                                            ▼
                    Bucket A (us-east-1)  ◄══ two-way CRR + RTC + replica modification sync ══►  Bucket B (us-west-2)
  Failover: submit routing update (A passive, B active) → traffic shifts in minutes; writes in B replicate back to A
```
- **Use when** an RTO of minutes is required for object storage with one global hostname.
- **Trade-offs:** cost (MRAP routing fee, replication, RTC), and clients must support SigV4A. CloudFront origin failover only covers GET/HEAD/OPTIONS, so it doesn't fail over writes.

### Pattern 4 — Large-scale online migration with DataSync over Direct Connect

```text
 On-prem data centre                                      AWS (Region)
 ┌─────────────┐  NFS/SMB  ┌──────────────┐  TLS over DX private VIF → TGW/VPC   ┌──────────────────────┐
 │ NAS / filer │──────────►│ DataSync     │═══════════════════════════════════════►│ DataSync VPC         │
 │ (300 TB)    │           │ agent (VM)   │   (bandwidth limit 70% business hrs,  │ interface endpoint    │
 └─────────────┘           └──────────────┘    100% nights; schedule hourly)       └──────────┬───────────┘
                                                                                             ▼
                                                    S3 / EFS / FSx for Windows / FSx for ONTAP / FSx for OpenZFS
 Phase 1: bulk copy  → Phase 2: incremental syncs (changed files only, verify) → Phase 3: cutover (final sync, read-only source)
```
- **Trade-offs:** needs enough bandwidth (check with the formula). On large links, add agents and split the dataset across several tasks for parallelism. If the link is too slow, the exam answer is Snowball Edge for the bulk load plus DataSync for the delta.

### Pattern 5 — Hybrid file services with Storage Gateway

```text
 Branch / DC users (SMB, AD auth)      Backup server (Veeam/NetBackup)     App servers (iSCSI)
            │                                    │ iSCSI VTL                      │
            ▼                                    ▼                                ▼
   ┌──────────────────┐               ┌──────────────────┐            ┌──────────────────────┐
   │ S3 File Gateway  │               │ Tape Gateway     │            │ Volume Gateway       │
   │ (local cache)    │               │ (cache + buffer) │            │ cached | stored      │
   └────────┬─────────┘               └────────┬─────────┘            └──────────┬───────────┘
            ▼ objects (1 file = 1 object)      ▼ virtual tapes                     ▼ EBS snapshots
        S3 bucket ── lifecycle ──► Glacier   S3 → eject/archive → Glacier Flexible / Deep Archive
```
- **Use when** on-prem applications must keep local protocols with cloud-backed capacity, or you're replacing tape.

### Pattern 6 — HPC burst on FSx for Lustre linked to S3

```text
 S3 data lake (input, PB) ──DRA (lazy load / auto import)──► FSx for Lustre (Scratch 2 or Persistent 2)
                                                                   ▲   │  hundreds of GB/s, sub-ms
                                         EC2 HPC / GPU fleet (EFA) ─┘   │
                                         (Spot via AWS Batch / ParallelCluster)
 Results ◄──────────────────auto export / data repository task────────────┘   then delete the file system
```
- **Scratch** is for jobs of hours to days where the data can be re-created from S3. **Persistent 2** is for long-lived shared HPC/ML.

### Pattern 7 — Organisation-wide immutable backup

```text
 Management / delegated-admin account: AWS Organizations BACKUP POLICY (daily 35d, monthly 1y, copy to central)
          │ applied to OUs
          ▼
 Member accounts (hundreds) ── tag backup=gold ──► local vault (CMK) ──copy──► Central Backup account
                                                                              ├─ Region A vault: Vault Lock COMPLIANCE
                                                                              └─ Region B logically air-gapped vault
                                                                                  (shared via RAM to Recovery account)
 Backup Audit Manager framework + daily reports ─► auditors; Restore testing (weekly) ─► proves RTO
 SCP: deny backup:DeleteBackupVault*, backup:PutBackupVaultAccessPolicy, iam changes to backup roles
```

### Pattern 8 — Partner file exchange (B2B)

```text
 Partners (SFTP/AS2 clients, allow-listed static IPs)
        │
        ▼
 Transfer Family server (VPC endpoint, internet-facing, EIPs, SG allow-list)
        │ custom IdP (API Gateway + Lambda → Okta/AD/Secrets Manager)
        ▼
 S3 (logical dirs per partner, SSE-KMS) ── managed workflow: PGP decrypt → malware scan (Lambda/GuardDuty) → tag → copy
        │
        └── EventBridge → Step Functions → downstream ETL
```

---

## 4. Decision tables / "X vs Y"

### 4.1 EBS vs EFS vs FSx vs S3

| Requirement | EBS | EFS | FSx for Windows | FSx for Lustre | FSx for ONTAP | FSx for OpenZFS | S3 |
|---|---|---|---|---|---|---|---|
| Access type | Block, 1 instance (Multi-Attach io1/io2 ≤16, same AZ) | NFSv4 shared file, thousands of Linux clients | SMB shared file | POSIX parallel file (Lustre client) | NFS + SMB + iSCSI + NVMe/TCP | NFS v3/v4.x | Object API (HTTP) |
| Scope | Single AZ | Regional (multi-AZ) or One Zone | Single- or Multi-AZ | Single AZ (replicated within AZ for persistent) | Single- or Multi-AZ | Single- or Multi-AZ | Regional (≥3 AZs) except One Zone classes |
| OS clients | Any (attached) | Linux (and macOS) | Windows (Linux SMB possible) | Linux | Linux, Windows, macOS, VMware | Linux, Windows, macOS | Any via SDK/HTTP |
| Typical latency | Sub-ms (io2 BX) | ~1 ms read | Sub-ms–ms | Sub-ms | Sub-ms | Hundreds of µs | ~100–200 ms first byte (Express One Zone: single-digit ms) |
| Capacity model | Provisioned | Elastic, pay per use | Provisioned | Provisioned (or elastic Intelligent-Tiering) | Provisioned SSD + elastic capacity pool | Provisioned SSD or elastic Intelligent-Tiering | Elastic |
| Exam trigger words | Boot volume, database on EC2, "lowest latency block" | "Shared POSIX for Linux / containers / Lambda", "unpredictable growth" | "Windows, SMB, AD, DFS, home directories, SQL Server FCI" | "HPC, ML training, genomics, parallel, S3-linked scratch" | "NetApp, SnapMirror, multi-protocol, iSCSI LUNs" | "ZFS, Linux NFS migration, snapshots/clones, low latency NFS" | "Unlimited, durable, static assets, data lake, archive" |

### 4.2 Which data-transfer service?

| Situation | Best answer | Why not the others |
|---|---|---|
| One-time or recurring copy of **files** (NFS/SMB/HDFS) to S3/EFS/FSx, enough bandwidth | **DataSync** (agent, over DX/VPN via VPC endpoint) | Storage Gateway is for ongoing hybrid access, not migration. Snowball is too slow if the link is fast |
| Migrate from **another cloud's object storage** to S3 | **DataSync** (Enhanced mode, agentless to S3) | Custom scripts mean higher operational overhead |
| **Partners/customers** must keep using **SFTP/FTPS/AS2** clients | **Transfer Family** | DataSync doesn't expose SFTP endpoints |
| Hundreds of TB to PB, **slow link or deadline**, or disconnected site | **Snowball Edge Storage Optimized** (exam view). *Current: existing customers only; otherwise Data Transfer Terminal or partners* | Online transfer would take weeks or months |
| Edge compute in rugged/disconnected location | **Snowball Edge Compute Optimized** (exam view) / **Outposts** (current) | Snowcone discontinued |
| Global clients uploading **large objects** to one bucket | **S3 Transfer Acceleration** + multipart | DataSync needs an agent at every client site |
| Continuous on-prem app access to cloud storage (NFS/SMB/iSCSI/VTL) | **Storage Gateway** | DataSync is for transfers, not live access |
| Database migration | **AWS DMS** (see Chapter 09/10) | DataSync is for files, not database engines |
| Dedicated private consistent bandwidth for ongoing hybrid traffic | **Direct Connect** (weeks to provision), VPN in the meantime | — |
| Copy S3 → S3 for existing objects, same or cross account/Region | **S3 Batch Replication** or **Batch Operations Copy** (or DataSync) | Live CRR doesn't copy existing objects |

### 4.3 Which Storage Gateway type?

| Need | Gateway |
|---|---|
| On-prem apps write files via NFS/SMB; data should be **native S3 objects** for analytics/lifecycle | **S3 File Gateway** |
| On-prem Windows users need low-latency cached SMB access to **FSx for Windows** | **FSx File Gateway** (exam view; closed to new customers since October 2024) |
| Block storage (iSCSI), want primary data in AWS with **local cache**, reduce on-prem SAN | **Volume Gateway — Cached** |
| Block storage, need **entire dataset local** with low latency, plus cloud backup/DR as EBS snapshots | **Volume Gateway — Stored** |
| Keep existing backup software, **replace physical tapes**, long-term retention in Glacier/Deep Archive | **Tape Gateway** |

### 4.4 S3 replication options

| Need | Use |
|---|---|
| Copy new objects to another Region (DR, latency, compliance) | CRR |
| Aggregate logs or copy to another account in the same Region (sovereignty) | SRR |
| RPO guarantee for replication | CRR/SRR **+ RTC** (99.9% within 15 min, SLA) |
| Copy **existing**, previously **failed**, or **replica** objects | **Batch Replication** |
| Keep metadata changes in sync both ways, active-active or MRAP failover | **Two-way replication + replica modification sync** |
| Replicas owned by destination account | **Owner override** / destination **Bucket owner enforced** |
| Replicate SSE-KMS objects | Opt-in `SseKmsEncryptedObjects` + destination-Region **CMK** + role KMS permissions |

### 4.5 Backups: AWS Backup vs DLM vs native snapshots vs S3 replication

| Need | Choose |
|---|---|
| Central, cross-service policy, org-wide, compliance reports, immutability | **AWS Backup** (+ Organizations policies, Vault Lock, Audit Manager) |
| EBS snapshot/AMI schedules only, no extra cost, per-account | **Amazon Data Lifecycle Manager** |
| Recover deleted snapshots/AMIs | **Recycle Bin** |
| Continuous replica of objects in another Region (not point-in-time) | **S3 CRR** (pair with versioning; replication is not a backup by itself) |
| Point-in-time S3 restore | **AWS Backup for S3** (continuous backups up to 35 days, plus periodic) |
| Long-term cheap EBS snapshot retention | **EBS Snapshots Archive** (≥90 days, 24–72 h restore) |

### 4.6 EBS volume choice

| Requirement | Choose |
|---|---|
| General workloads, boot, most databases up to 80,000 IOPS / 2,000 MiB/s | **gp3** |
| > 80,000 IOPS, sub-ms consistent latency, 99.999% durability, Multi-Attach | **io2 Block Express** |
| Sequential throughput, big data, logs, cheap | **st1** |
| Cold, infrequent, lowest cost block | **sc1** |
| Temporary, highest IOPS, data replicated elsewhere | **Instance store** |

---

## 5. Exam keyword → answer cheat list

- "**Unknown / changing access patterns**", "no retrieval fees" → **S3 Intelligent-Tiering**
- "Accessed once a quarter, **must be immediate**" → **S3 Glacier Instant Retrieval**
- "Retrieval **within minutes** occasionally" → **Glacier Flexible Retrieval Expedited** (buy **provisioned capacity** if it must be guaranteed)
- "Retain 7–10 years, retrieval **within 12/48 hours**, cheapest" → **Glacier Deep Archive**
- "**Re-creatable**, infrequent, cheapest with ms access" → **S3 One Zone-IA**
- "**Single-digit millisecond**, co-locate with compute in one AZ" → **S3 Express One Zone** (directory bucket)
- "**WORM**, regulator (SEC 17a-4), even root can't delete" → **S3 Object Lock Compliance mode** (or **AWS Backup Vault Lock compliance** for backups)
- "Prevent deletion but allow some admins to override" → **Object Lock Governance mode**
- "Litigation, keep until released" → **Legal hold** (S3 or AWS Backup)
- "Replicate within **15 minutes**, SLA" → **S3 RTC**
- "Replicate **existing** objects" → **S3 Batch Replication**
- "Replicas should be owned by destination account" → **Owner override / Bucket owner enforced**
- "One **global endpoint**, multi-Region **failover** for S3" → **Multi-Region Access Points + failover controls + two-way CRR**
- "Hundreds of teams need different permissions on a shared bucket" → **S3 Access Points** (delegate from bucket policy). Workforce directory identities → **S3 Access Grants**
- "Bucket accessible only from a specific VPC" → **VPC endpoint + bucket policy `aws:SourceVpce`** or **VPC-only access point**
- "On-prem access to S3 privately over DX" → **S3 interface endpoint (PrivateLink)**, not a gateway endpoint
- "Uploads from users worldwide are slow" → **S3 Transfer Acceleration + multipart upload**
- "**503 Slow Down**" → spread across **more prefixes**, exponential backoff, check **KMS quotas / Bucket Keys**
- "Temporary access to a private object without AWS credentials" → **Presigned URL**
- "Partners pay for downloads" → **Requester Pays**
- "Apply an action to **billions of existing objects**" → **S3 Batch Operations** (+ S3 Inventory manifest)
- "Organisation-wide storage usage visibility and recommendations" → **S3 Storage Lens (advanced)**
- "Several consumers / advanced filtering of S3 events" → **EventBridge**. "Simple trigger Lambda/SQS" → **S3 Event Notifications**
- "Query object metadata with SQL" → **S3 Metadata**. "Managed Iceberg tables" → **S3 Tables**
- "Cut EBS cost without downtime" → **gp2 → gp3 via Elastic Volumes**
- "**>80,000 IOPS**, sub-ms, mission-critical DB" → **io2 Block Express** on Nitro
- "Shared block device for clustered app (Oracle RAC-like / cluster FS)" → **io2 Multi-Attach** (same AZ)
- "Volumes from snapshots need full performance immediately" → **Fast Snapshot Restore**
- "Recover accidentally deleted snapshots/AMIs" → **Recycle Bin**
- "Shared file system for Linux EC2/containers/Lambda, grows automatically" → **EFS** (Elastic throughput, lifecycle to IA/Archive)
- "EFS slow, small file system, burst credits exhausted" → switch to **Elastic throughput**
- "Windows file shares, AD, DFS, SMB" → **FSx for Windows File Server (Multi-AZ)**
- "HPC / ML, S3-linked, sub-ms, hundreds of GB/s, temporary" → **FSx for Lustre Scratch + DRA**
- "Migrate **NetApp**, SnapMirror, NFS+SMB+iSCSI" → **FSx for NetApp ONTAP**
- "Migrate **ZFS** / Linux NFS, clones" → **FSx for OpenZFS**
- "**Replace tape**, keep backup software" → **Tape Gateway → Glacier Deep Archive**
- "On-prem NFS/SMB app, store as S3 objects, local cache" → **S3 File Gateway**
- "iSCSI, keep all data local, backup to AWS" → **Volume Gateway Stored**. "iSCSI, cache only hot data" → **Cached**
- "Migrate NAS to AWS over DX, keep in sync until cutover, verify integrity" → **DataSync**
- "Partners use **SFTP / AS2**, no client change" → **AWS Transfer Family** (custom IdP via Lambda/API Gateway)
- "PB of data, **limited bandwidth**, weeks deadline" → **Snowball Edge** (exam view). Multiple devices in parallel
- "Central backup for all accounts, enforced automatically" → **AWS Backup + Organizations backup policies**
- "Prove backup compliance to auditors" → **AWS Backup Audit Manager**
- "Backups immune to compromised accounts" → **Cross-account copy + Vault Lock compliance** / **logically air-gapped vault**
- "Validate backups restore within RTO" → **AWS Backup restore testing**

---

## 6. Traps & distractors

1. **"Use a gateway VPC endpoint so on-prem servers reach S3 privately over Direct Connect."** Wrong. Gateway endpoints only work for traffic originating in the VPC. Use an **interface endpoint** (or a public VIF).
2. **"Enable CRR and existing objects will be copied."** Wrong. Live replication only covers new objects. Use **Batch Replication**.
3. **"CRR copies SSE-KMS objects automatically."** Wrong. You must opt in and specify a destination-Region key. For cross-account, use a **customer managed** key, not `aws/s3`.
4. **"Replication protects against accidental deletes, so we don't need versioning/backup."** Partly wrong. Delete markers *can* be replicated if enabled, and corruption (overwrites) replicates too. Use **versioning + Object Lock + separate-account replica**.
5. **"Replicate lifecycle expirations to keep buckets identical."** Lifecycle actions are never replicated. Configure lifecycle on both buckets.
6. **"Store 10 million 20 KB log files in Glacier Deep Archive to save money."** The 40 KB per-object overhead and per-object transition fees can cost more than the storage saved. Aggregate first, or keep small objects in Standard/Intelligent-Tiering.
7. **"Standard-IA for data deleted after 7 days."** The 30-day minimum charge applies. Standard is cheaper.
8. **"S3 One Zone-IA for the only copy of critical data."** Not AZ-resilient. Use Standard-IA (One Zone-IA is fine for replicas or re-creatable data).
9. **"Glacier Flexible Retrieval for data that must be available within milliseconds."** Use **Glacier Instant Retrieval**.
10. **"MFA Delete via console by an IAM admin."** Only the root user can enable it, via CLI/API. For scale or compliance, Object Lock is usually the intended answer.
11. **"Object Lock governance mode satisfies SEC 17a-4."** Governance can be bypassed. The regulator answer is **compliance mode**.
12. **"CloudFront origin failover provides multi-Region S3 write failover."** Origin failover covers GET/HEAD/OPTIONS only. Use **MRAP failover controls** for writes.
13. **"Increase S3 performance by requesting a limit increase."** There's no per-bucket throughput quota to raise. Use more prefixes and parallelism (and check KMS).
14. **"Transfer Acceleration for uploads from EC2 in the same Region."** No benefit, and you'd pay for nothing. Use it for distant clients.
15. **"EBS volume shared across AZs with Multi-Attach for HA."** Multi-Attach is single-AZ only and needs a cluster-aware file system. For multi-AZ shared storage use EFS or FSx Multi-AZ.
16. **"Increase gp2 volume size to get more IOPS."** It works, but gp3 lets you buy IOPS separately and is cheaper. The cost-optimised answer is gp3.
17. **"io1 volume with 150,000 IOPS."** io1 maxes at 64,000. You need **io2 Block Express** (Nitro).
18. **"st1/sc1 as boot volume."** HDD volumes aren't bootable.
19. **"Instance store for the database's only copy."** Ephemeral, lost on stop or host failure.
20. **"Share an encrypted EBS snapshot (default aws/ebs key) with another account."** Not possible. Re-encrypt with a CMK and share the key.
21. **"EFS for Windows SMB file shares"** → wrong protocol. **"FSx for Windows for Linux NFS HPC"** → wrong too.
22. **"EFS Max I/O for best performance."** Max I/O has higher latency and isn't supported with Elastic throughput or One Zone. Current best practice is General Purpose + Elastic.
23. **"FSx for Lustre Scratch for long-term primary data."** Scratch isn't replicated. Use Persistent, or keep the master copy in S3.
24. **"Snowball imports directly into Glacier."** Import lands in S3. Use lifecycle to move it to Glacier.
25. **"Order Direct Connect to finish a 2-week migration."** DX takes weeks to months to provision. Use Snowball (exam view) or DataSync over the existing internet/VPN link if the maths allows.
26. **"Storage Gateway to migrate 500 TB once."** Gateways are for ongoing hybrid access. For one-time migration, use **DataSync** or Snowball.
27. **"S3 File Gateway reading objects archived to Glacier directly."** Archived objects must be restored first.
28. **"DataSync for live, low-latency access by on-prem apps."** DataSync moves data on a schedule. For live access, use Storage Gateway or FSx over DX.
29. **"AWS Backup Vault Lock governance mode to stop a compromised root user."** Only **compliance mode** (after grace time) is immune.
30. **"Cross-account backup copy without AWS Organizations."** AWS Backup cross-account copy requires Organizations.
31. **"Event Notifications to an SQS FIFO queue."** Not supported. Use a standard queue, or EventBridge.
32. **"S3 Select / S3 Object Lambda / Amazon Glacier vaults for new builds."** These are closed to new customers (S3 Select since 2024; Object Lambda since November 7, 2025; Glacier vaults since December 15, 2025). The exam may still reference Object Lambda as valid. Recognise it, but know the current alternatives.

---

## 7. Professional architect focus

- **Model total cost, not just $/GB.** Include requests (PUT/transition/lifecycle), retrieval, minimum durations, per-object overhead, KMS calls (enable Bucket Keys), replication transfer, NAT gateway charges for S3 traffic (use a gateway endpoint), and cross-AZ data transfer for EBS/EFS/FSx clients.
- **Separate durability from recoverability.** 11 nines protects against hardware loss, not against `rm -rf`, ransomware, bad deployments, or a compromised admin. Always ask: *What is our logical-corruption RPO? Is there an immutable copy in a different account and Region?*
- **Data classification drives class choice and retention.** Run Storage Class Analysis or Storage Lens for 30–60 days before choosing lifecycle thresholds. Intelligent-Tiering is a sensible default for data lakes with unknown patterns. Lifecycle Glacier rules suit compliance archives.
- **Blast radius and governance at org scale:**
  - account-level BPA everywhere
  - SCPs preventing BPA changes, unencrypted uploads, or deletion of backup vaults
  - RCPs to restrict access to your org's identities (`aws:PrincipalOrgID`)
  - Config conformance packs for S3/EBS encryption
  - delegated admin for Storage Lens and AWS Backup
- **Hybrid file migrations:**
  - Inventory protocols first (NFS v3/v4, SMB, iSCSI, multi-protocol).
  - Check permissions model (POSIX vs NTFS ACLs), small-file counts (which hurt throughput), and change rate (sizes the incremental syncs).
  - Plan cutover windows. DataSync verification gives auditable evidence.
- **Performance testing:** EBS is capped by the *instance*, EFS by throughput mode and per-client limits, FSx by provisioned throughput capacity, and S3 by prefix parallelism and KMS. Benchmark (fio, Elbencho) before go-live.
- **Service lifecycle awareness:** several storage features moved to maintenance in 2024–2025 (Snowball Edge, Snowcone, FSx File Gateway, Storage Gateway hardware appliance, Glacier vaults, S3 Object Lambda, S3 Select). In real designs, avoid building new dependencies on them. Raise this with stakeholders when a vendor proposal relies on them.
- **What to raise with stakeholders:** retention legal requirements (and deletion obligations such as GDPR erasure, which conflict with compliance-mode WORM), RTO/RPO per dataset, data residency (SRR vs CRR, Local Zone directory buckets), egress costs for data sharing (Requester Pays), and who owns the restore runbook (restore testing).

---

## 8. Skills checklist

- [ ] I can state the minimum storage duration, minimum billable size, AZ count and retrieval times for every S3 storage class from memory.
- [ ] I can design a lifecycle policy that respects minimum-duration and 128 KB transition constraints and cleans up noncurrent versions and incomplete multipart uploads.
- [ ] I can configure cross-account CRR for SSE-KMS objects with owner override, RTC, and Batch Replication for existing data.
- [ ] I can explain what S3 replication does **not** replicate (existing objects, lifecycle actions, versioned deletes, Glacier-tier objects, bucket config).
- [ ] I can choose between Object Lock governance and compliance, legal hold, and MFA Delete.
- [ ] I can secure a bucket with BPA, Object Ownership (bucket owner enforced), bucket policy conditions (`aws:SourceVpce`, `aws:PrincipalOrgID`, `aws:SecureTransport`), and access points.
- [ ] I can design an MRAP active-passive failover with two-way replication.
- [ ] I can fix S3 throughput problems (prefixes, multipart, byte-range, Transfer Acceleration, KMS quotas).
- [ ] I can pick the right EBS type with the 2025 gp3/io2 limits and explain instance-level bottlenecks.
- [ ] I can explain snapshots, FSR, Snapshots Archive, Recycle Bin and DLM, and when AWS Backup replaces DLM.
- [ ] I can choose EFS throughput/performance mode and storage classes, and mount EFS from on-prem.
- [ ] I can pick the right FSx flavour from a scenario in under 30 seconds.
- [ ] I can map each Storage Gateway type to its protocol and target storage.
- [ ] I can do bandwidth maths and decide between DataSync, Snowball Edge, Transfer Acceleration and Transfer Family.
- [ ] I can state the current (2026) availability of Snow Family devices and their alternatives.
- [ ] I can design an organisation-wide AWS Backup strategy with policies, cross-account/Region copies, Vault Lock, logically air-gapped vaults, legal holds, restore testing and Audit Manager.

---

## 9. Practice questions

> Original SAP-C02-style questions (not real exam questions). Answer as the exam expects.

**Q1.** A brokerage firm must retain trade-confirmation PDFs (average 2 MB each, about 40 TB per year) for 7 years to satisfy SEC Rule 17a-4. Records are read heavily for the first 30 days, occasionally for disputes during the first year (a response within minutes is acceptable), and almost never afterwards (retrieval within 48 hours is acceptable). Auditors require that no user, including the AWS account root user, can delete or alter a record before its retention expires. The solution must minimise storage cost and operational overhead. Which solution meets these requirements?

- A. Store objects in S3 Standard with versioning and MFA Delete enabled by the root user. Add a lifecycle rule that transitions objects to S3 Glacier Flexible Retrieval after 30 days and to S3 Glacier Deep Archive after 365 days.
- B. Store objects in an S3 bucket with Object Lock enabled and a default retention of 7 years in compliance mode. Add a lifecycle rule that transitions objects to S3 Glacier Flexible Retrieval after 30 days and to S3 Glacier Deep Archive after 365 days, and expires them after 7 years.
- C. Store objects in an S3 bucket with Object Lock enabled and a default retention of 7 years in governance mode. Add a lifecycle rule that transitions objects to S3 Glacier Instant Retrieval after 30 days and expires them after 7 years.
- D. Store objects in S3 Standard-IA. Each night, copy new objects to an Amazon Glacier vault with a Vault Lock policy that denies deletes for 7 years, then delete the S3 copies after 30 days.

**Q2.** A media company's production account (us-east-1) stores 400 TB of assets in an S3 bucket encrypted with SSE-KMS using a customer managed key. Security requires a ransomware-resistant copy in a separate backup account in us-west-2. Requirements: replicas must be owned by the backup account; deletions made in production must not remove data in the backup copy; all existing objects must also be copied; and new objects must reach the backup bucket within 15 minutes under an SLA. Which combination of actions should a solutions architect take? **(Select THREE.)**

- A. Configure a CRR rule with S3 Replication Time Control, enable replication of objects encrypted with AWS KMS, specify a customer managed key in us-west-2 as the replica key, and grant the replication role `kms:Decrypt` on the source key and `kms:Encrypt` on the destination key.
- B. Enable delete marker replication on the CRR rule so that the backup bucket stays consistent with production.
- C. Set S3 Object Ownership to bucket owner enforced on the destination bucket (or enable owner override in the rule), and allow the source replication role in the destination bucket policy.
- D. Run an S3 Batch Replication job for the objects that existed before the rule was created.
- E. Use the AWS managed key `aws/s3` in the backup account as the replica encryption key to avoid managing key policies.
- F. Rely on the CRR rule to replicate existing objects automatically within 48 hours of creation.

**Q3.** A research institute must move 150 TB of genomics files from an on-premises NFS cluster to Amazon S3 within 3 weeks, then keep the two locations synchronised for 2 months until the on-premises cluster is decommissioned. The institute has an existing 10 Gbps AWS Direct Connect connection, of which about 60% is available for migration traffic, and only during nights and weekends. Security policy forbids sending data over the public internet. The team wants integrity verification and the least operational overhead. What should a solutions architect recommend?

- A. Order three AWS Snowball Edge Storage Optimized devices for the bulk copy, then use S3 File Gateway to synchronise changes until decommissioning.
- B. Deploy an AWS DataSync agent on premises, create a DataSync VPC interface endpoint reachable over the Direct Connect private VIF, and create a scheduled task with a bandwidth limit, task scheduling for nights and weekends, and data verification enabled.
- C. Enable S3 Transfer Acceleration on the bucket and run `aws s3 sync` from several on-premises servers each night through the internet gateway.
- D. Deploy a Volume Gateway in stored mode, copy the NFS data to the iSCSI volumes, and restore EBS snapshots in AWS into Amazon S3.

**Q4.** A manufacturing company runs NetApp filers on premises. They serve NFS exports to Linux engineering workstations, SMB shares to Windows users (authenticated with the corporate Active Directory) on the same datasets, and iSCSI LUNs to a SQL Server cluster. The company uses SnapMirror for DR between two data centres and wants to move the primary storage to AWS with minimal change to tooling, processes and client configuration, with resilience to an Availability Zone failure. Which solution best meets these requirements?

- A. Deploy Amazon FSx for NetApp ONTAP in a Multi-AZ deployment, join the SVM to Active Directory, and use SnapMirror to replicate the volumes from the on-premises filers before cutover.
- B. Migrate NFS data to Amazon EFS, SMB data to Amazon FSx for Windows File Server Multi-AZ, and the LUNs to Amazon EBS io2 volumes using AWS DataSync.
- C. Deploy Amazon FSx for OpenZFS Multi-AZ for NFS and SMB, and use Volume Gateway for the iSCSI LUNs.
- D. Deploy S3 File Gateway for NFS and SMB and Volume Gateway cached volumes for iSCSI, with data replicated by SnapMirror into Amazon S3.

**Q5.** A pharmaceutical company keeps a 500 TB genomics dataset in Amazon S3. Twice a month, scientists run a 48-hour simulation on thousands of EC2 Spot Instances that require a POSIX-compliant shared file system with sub-millisecond latency and hundreds of GB/s of aggregate throughput. Intermediate data can be regenerated from S3; final results must be stored in S3. The company wants to minimise cost. Which storage solution should a solutions architect recommend?

- A. Create an Amazon FSx for Lustre Persistent 2 file system with SSD storage that runs permanently and is linked to the S3 bucket through a data repository association.
- B. For each run, create an Amazon FSx for Lustre Scratch file system linked to the S3 bucket with a data repository association, export results to S3 at the end of the job, and delete the file system.
- C. Create an Amazon EFS Regional file system in Max I/O performance mode with Provisioned throughput and copy the dataset into it with AWS DataSync before each run.
- D. Attach Multi-Attach enabled io2 Block Express volumes to all instances in the cluster and copy the dataset from S3 at the start of each run.

**Q6.** A photo-sharing application writes user uploads to a single S3 bucket using keys of the form `uploads/<timestamp>-<uuid>.jpg`. During marketing events, write rates reach 15,000 PUT requests per second and the application receives many HTTP 503 Slow Down errors. Separately, professional users in Asia and Europe upload 2–8 GB RAW files to the bucket in us-east-1 and complain about slow and frequently failed uploads. Which actions will resolve both issues? **(Select TWO.)**

- A. Change the key naming scheme to distribute objects across many prefixes (for example, a hash-based prefix such as `uploads/<hash>/...`) and implement exponential backoff with retries.
- B. Open an AWS Support case to raise the bucket's PUT request quota to 20,000 requests per second.
- C. Enable S3 Transfer Acceleration on the bucket and have clients upload using multipart upload with parallel parts to the accelerate endpoint.
- D. Enable S3 Replication Time Control to replicate uploads to buckets in Asia and Europe.
- E. Move the bucket to S3 Express One Zone in a single Availability Zone of us-east-1 to remove the request-rate limit for global users.

**Q7.** A financial services company has 350 AWS accounts in AWS Organizations. The CISO requires that all Amazon RDS, Amazon DynamoDB, and Amazon EBS resources tagged `backup=critical` are backed up daily with 35-day retention. Copies must be kept in a dedicated backup account in a second Region, where they cannot be deleted or have their retention shortened by anyone, including administrators of the management account, and the company must produce daily evidence of compliance for auditors. Which combination of steps meets these requirements with the least operational overhead? **(Select THREE.)**

- A. Use AWS Organizations backup policies, managed from a delegated administrator account, to deploy a backup plan that selects resources by the `backup=critical` tag and includes a cross-account, cross-Region copy action.
- B. In the central backup account, create the destination backup vault and apply AWS Backup Vault Lock in compliance mode with a minimum retention of 35 days after the grace period.
- C. Configure AWS Backup Audit Manager frameworks with controls for backup plan coverage, retention, cross-Region copy and vault lock, and schedule daily compliance reports.
- D. Create Amazon Data Lifecycle Manager policies in every account with cross-account copy events to the backup account.
- E. Apply AWS Backup Vault Lock in governance mode in the central account and restrict the `backup:DeleteRecoveryPoint` permission with an SCP.
- F. Write an AWS Lambda function in each account that snapshots tagged resources daily and copies them to the backup account.

**Q8.** A hospital backs up 300 TB of clinical data each month with Veritas NetBackup to an on-premises LTO tape library. Tapes are shipped to an off-site vault and kept for 10 years. Restores of tapes older than 6 months happen a few times per year, and 48-hour restore times are acceptable. The hospital wants to stop managing physical tapes and the off-site vault, without changing its backup software or procedures, at the lowest storage cost. What should a solutions architect recommend?

- A. Deploy AWS Storage Gateway Tape Gateway, configure NetBackup to use the virtual tape library, and archive ejected virtual tapes to the S3 Glacier Deep Archive pool.
- B. Deploy S3 File Gateway, configure NetBackup to write to an SMB share, and apply an S3 Lifecycle rule to transition objects to S3 Glacier Deep Archive after 30 days.
- C. Deploy Volume Gateway in cached mode, present iSCSI volumes to NetBackup as disk targets, and take daily EBS snapshots with Amazon Data Lifecycle Manager.
- D. Use AWS DataSync to copy the NetBackup catalog and backup images to S3 Glacier Flexible Retrieval every night.

**Q9.** A company is reviewing EBS costs and performance for two workloads in production:
1. 800 general-purpose application servers, each with a 2 TiB gp2 data volume that only ever needs about 4,000 IOPS and 200 MiB/s.
2. A business-critical Oracle database on a Nitro-based EC2 instance that needs a sustained 180,000 IOPS with consistent sub-millisecond latency and the highest available volume durability.

Which actions should a solutions architect take? **(Select TWO.)**

- A. Modify the application servers' volumes from gp2 to gp3 with Elastic Volumes, provisioning 4,000 IOPS and 200 MiB/s, without downtime.
- B. Migrate the Oracle database to a single io1 volume provisioned with 180,000 IOPS.
- C. Migrate the Oracle database storage to io2 Block Express volumes provisioned with 180,000 IOPS on an instance type whose EBS bandwidth supports that level.
- D. Reduce the application servers' gp2 volumes to 1 TiB to lower cost, relying on burst credits for peak IOPS.
- E. Move the Oracle database to instance store volumes in RAID 0 for the highest IOPS, with nightly EBS snapshots.

**Q10.** A global SaaS provider stores customer documents in S3 in us-east-1. It must keep serving reads and writes with an RTO of under 15 minutes if us-east-1 S3 becomes impaired, with an RPO of 15 minutes. Applications in several Regions must use a single S3 endpoint without code changes during failover. Under normal conditions all traffic should go to us-east-1. Which solution meets these requirements?

- A. Create a second bucket in us-west-2 with one-way CRR from us-east-1. Put an Amazon CloudFront distribution with an origin group (primary us-east-1, secondary us-west-2) in front of both buckets and point applications at the distribution for reads and writes.
- B. Create a second bucket in us-west-2. Configure two-way CRR with S3 Replication Time Control and replica modification sync. Create an S3 Multi-Region Access Point over both buckets with us-east-1 active and us-west-2 passive, and use the failover controls to shift traffic when needed.
- C. Create a second bucket in us-west-2 with CRR. Create Amazon Route 53 failover records that point a custom domain to the two S3 Regional endpoints, with health checks on the us-east-1 endpoint.
- D. Use AWS Backup continuous backups for S3 with cross-Region copy to us-west-2, and restore to a new bucket in us-west-2 during an outage.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B**

- **Why:** SEC 17a-4 WORM that even root can't bypass requires **S3 Object Lock in compliance mode**. Lifecycle matches the access pattern:
  - **Glacier Flexible Retrieval** gives minutes-level access (Expedited 1–5 min) during the dispute year.
  - **Deep Archive** fits the "48 hours acceptable" period at the lowest cost.
  - Expiration at 7 years removes the data once retention ends.
  - 2 MB objects are well above the small-object thresholds, so transition costs are reasonable.
- **A:** MFA Delete is not a WORM control. The root user (who holds the MFA device) can still delete. It doesn't meet 17a-4.
- **C:** Governance mode can be bypassed by users with `s3:BypassGovernanceRetention`. Glacier IR for 7 years also costs more than Deep Archive when access is this rare.
- **D:** More operational overhead (a nightly copy job). Amazon Glacier vaults are a separate, older service, closed to new customers since December 15, 2025. Standard-IA plus copy duplicates storage.
- **References:** [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html) · [Storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html) · [Archive retrieval options](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects-retrieval-options.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A, C, D**

- **A:** SSE-KMS objects replicate only when you opt in and specify a destination-Region KMS key, with the right role permissions. **RTC** provides the 15-minute SLA (99.9% of objects within 15 minutes).
- **C:** Owner override or bucket owner enforced makes the backup account own the replicas. The destination bucket policy must trust the source replication role.
- **D:** Live replication never copies pre-existing objects. **Batch Replication** does.
- **B:** Replicating delete markers would let production deletions hide data in the backup copy, which contradicts the requirement. Leaving it off (the default for V2 rules) is correct.
- **E:** AWS managed keys can't be used cross-account, so cross-account SSE-KMS replication requires a customer managed key.
- **F:** CRR does not replicate existing objects. "24–48 hours" refers to non-RTC replication of *new* objects, without an SLA.
- **References:** [Replicating encrypted objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-config-for-kms-objects.html) · [What S3 replicates](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-what-is-isnot-replicated.html) · [Replication overview / Batch Replication / RTC](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: B**

- **Maths:** 150 TB × 8 × 10¹² bits ÷ (10 × 10⁹ bps × 0.6) ≈ 200,000 s ≈ **2.3 days** of transfer time. Even limited to nights and weekends (roughly 60% of the week), the bulk copy finishes in about 4–5 calendar days, well within 3 weeks.
- **Why B:** DataSync gives private transfer over DX (VPC interface endpoint), scheduling, bandwidth throttling, incremental syncs for the 2-month coexistence period, and built-in integrity verification, all as a managed service.
- **A:** Snowball isn't needed when the network suffices. Ship-and-ingest cycles take longer than 2.3 days, and (current reality) Snowball Edge is available only to existing customers. S3 File Gateway is a hybrid access service, not a sync/migration tool.
- **C:** Uses the public internet, which violates policy. Transfer Acceleration helps distant clients, not a DX-connected data centre. `aws s3 sync` lacks managed verification and reporting.
- **D:** Volume Gateway presents block storage, not NFS files. Converting EBS snapshots to S3 objects is convoluted and adds operational overhead.
- **References:** [What is DataSync](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html) · [DataSync task modes](https://docs.aws.amazon.com/datasync/latest/userguide/choosing-task-mode.html) · [Snow device updates](https://aws.amazon.com/blogs/storage/aws-snow-device-updates/)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: A**

- **Why:** FSx for NetApp ONTAP is the only managed option that serves **NFS, SMB and iSCSI from the same data**, supports **SnapMirror** from on-prem NetApp (minimal tooling change), joins **Active Directory**, and offers **Multi-AZ** HA.
- **B:** Splits data across three services, so it breaks multi-protocol access to the same dataset. DataSync can't migrate iSCSI LUNs. It also requires major process change.
- **C:** FSx for OpenZFS is NFS-only (no SMB, no SnapMirror). Volume Gateway keeps storage on-prem-centric.
- **D:** Storage Gateway is a hybrid cache, not primary storage for AWS-hosted workloads. SnapMirror can't target S3 through a gateway.
- **References:** [What is FSx for ONTAP](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/what-is-fsx-ontap.html) · [FSx for OpenZFS](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/what-is-fsx.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: B**

- **Why:** **FSx for Lustre Scratch** is the lowest-cost Lustre deployment for short-term, processing-heavy jobs (200 MBps/TiB baseline, burst up to 6x). Data can be regenerated from S3, so the lack of replication is acceptable. A **data repository association** lazy-loads from S3 and exports results back. Deleting the file system between runs avoids paying for idle capacity.
- **A:** Persistent 2 running permanently costs much more for a workload active only about 4 days a month. Persistent is for long-lived data that must survive server failures.
- **C:** EFS can't deliver Lustre-class sub-ms parallel throughput for thousands of HPC clients at this cost. Max I/O adds latency. Copying 500 TB each run adds time and cost.
- **D:** Multi-Attach is limited to 16 instances in one AZ and needs a cluster file system. It isn't a shared POSIX file system for thousands of nodes.
- **References:** [FSx for Lustre deployment options](https://docs.aws.amazon.com/fsx/latest/LustreGuide/using-fsx-lustre.html) · [EBS Multi-Attach](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volumes-multi.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, C**

- **A:** S3 supports at least 3,500 PUT/s **per partitioned prefix**. A single `uploads/` prefix with timestamp keys concentrates load. Spreading keys across many prefixes lets S3 scale further, and backoff handles transient 503s while S3 scales.
- **C:** Transfer Acceleration routes distant uploads through CloudFront edge locations over the AWS backbone. **Multipart upload** with parallel parts improves throughput and lets failed parts be retried without restarting 8 GB uploads.
- **B:** There is no per-bucket request-rate quota to raise. Scaling comes from prefixes.
- **D:** RTC replicates data *after* it lands in us-east-1. It doesn't speed up uploads into us-east-1.
- **E:** Express One Zone is single-AZ storage for latency-sensitive compute co-located in that AZ. It does nothing for long-haul internet uploads, and it reduces durability against AZ loss.
- **References:** [S3 performance](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-performance.html) · [Transfer Acceleration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/transfer-acceleration.html) · [Multipart upload](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: A, B, C**

- **A:** **Organizations backup policies** push and enforce one backup plan (tag-based selection, cross-account cross-Region copy) to all 350 accounts with no per-account work. Cross-account copy requires Organizations, which the company has.
- **B:** **Vault Lock compliance mode** makes retention immutable after the grace time (at least 3 days), even for root or management-account admins.
- **C:** **Backup Audit Manager** gives continuous control evaluation and daily reports for auditors.
- **D:** DLM covers only EBS snapshots and AMIs, not RDS or DynamoDB, and needs per-account policies. Higher overhead.
- **E:** Governance-mode locks can be removed by sufficiently privileged users. SCPs don't apply to the management account, so admins there could still act.
- **F:** Custom code in 350 accounts means the highest operational overhead, with no immutability.
- **References:** [AWS Backup overview](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html) · [Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html) · [Organizations backup policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: A**

- **Why:** **Tape Gateway** presents an iSCSI virtual tape library that NetBackup already supports, so procedures don't change. Archived virtual tapes in the **S3 Glacier Deep Archive** pool give the lowest cost for 10-year retention, and Deep Archive retrieval (within 12 hours standard) fits the 48-hour restore window.
- **B:** Changes the backup target from tape to file share, so procedures change. NetBackup tape workflows and catalogs wouldn't map one-to-one.
- **C:** EBS snapshots of cached volumes are much more expensive than Deep Archive for 10 years. Disk targets change procedures.
- **D:** DataSync copies files. It doesn't integrate with NetBackup's tape catalog, and Glacier Flexible Retrieval is pricier than Deep Archive for this access pattern.
- **References:** [Tape Gateway](https://docs.aws.amazon.com/storagegateway/latest/tgw/WhatIsStorageGateway.html) · [Storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, C**

- **A:** gp3 includes a 3,000 IOPS / 125 MiB/s baseline and lets you buy extra IOPS and throughput independently of size. It's about 20% cheaper per GiB than gp2. Elastic Volumes changes the type online.
- **C:** 180,000 IOPS exceeds io1 (64,000) and gp3 (80,000). **io2 Block Express** supports up to 256,000 IOPS, 4,000 MiB/s, sub-ms latency and 99.999% durability on Nitro instances, provided the instance's EBS bandwidth supports it.
- **B:** io1 maxes out at 64,000 IOPS per volume.
- **D:** gp2 volumes cannot be shrunk. Burst credits (up to 3,000 IOPS) wouldn't sustain 4,000 IOPS anyway.
- **E:** Instance store is ephemeral, so data is lost on stop or host failure. Snapshots of instance store aren't possible. This fails the durability requirement.
- **References:** [EBS volume types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html) · [gp3/gp2 performance](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: B**

- **Why:** **Multi-Region Access Points** give one global endpoint. **Failover controls** (active/passive routing) shift traffic to us-west-2 in minutes, so the RTO is under 15 minutes. **Two-way CRR with RTC** bounds the RPO at 15 minutes (SLA-backed). **Replica modification sync** keeps metadata consistent and lets writes made during failover flow back.
- **A:** CloudFront origin failover applies only to GET, HEAD and OPTIONS. Writes don't fail over. One-way CRR also wouldn't carry writes back after failover.
- **C:** S3 virtual-hosted endpoints require the bucket name to match the hostname, so one custom domain can't front two differently named Regional buckets for authenticated API calls. DNS failover also doesn't handle SigV4 Region scoping.
- **D:** Restoring from backup into a new bucket takes far longer than 15 minutes for large datasets and changes the endpoint.
- **References:** [MRAP failover controls](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MrapFailover.html) · [Multi-Region Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiRegionAccessPoints.html) · [Replication (two-way, RTC)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
</details>

---

## 10. References

**Amazon S3**
- [Amazon S3 storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [Transitioning objects using S3 Lifecycle (constraints)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html)
- [Managing the lifecycle of objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [S3 removes 30-day minimum for transitions to Standard-IA / One Zone-IA (July 2026)](https://aws.amazon.com/about-aws/whats-new/2026/07/s3-removes-30-day-transitions-standard-ia-one-zone-ia/)
- [S3 maximum object size increased to 50 TB (December 2025)](https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-s3-maximum-object-size-50-tb/)
- [Archive retrieval options](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects-retrieval-options.html)
- [Replicating objects (CRR/SRR, RTC, Batch Replication, two-way)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [What does S3 replicate?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-what-is-isnot-replicated.html)
- [Replicating encrypted objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-config-for-kms-objects.html)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [MFA Delete](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiFactorAuthenticationDelete.html)
- [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [Object Ownership](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)
- [S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Multi-Region Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiRegionAccessPoints.html) · [MRAP failover controls](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MrapFailover.html)
- [Presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)
- [Optimizing S3 performance](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-performance.html) · [Transfer Acceleration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/transfer-acceleration.html) · [Multipart upload](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
- [Event notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [S3 Batch Operations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops.html) · [S3 Storage Lens](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage_lens.html)
- [Requester Pays](https://docs.aws.amazon.com/AmazonS3/latest/userguide/RequesterPaysBuckets.html)
- [S3 Object Lambda availability change](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazons3-ol-change.html)
- [S3 Express One Zone](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-high-performance.html)
- [S3 Tables](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables.html) · [S3 Metadata tables](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metadata-tables-overview.html) · [S3 Vectors](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors.html)

**Amazon EBS**
- [EBS volume types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html) · [General Purpose SSD (gp3/gp2)](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)
- [Multi-Attach](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volumes-multi.html)
- [Fast snapshot restore](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-fast-snapshot-restore.html) · [EBS Snapshots Archive](https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-archive.html)
- [EBS encryption](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html)
- [EC2 instance store](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html)

**Amazon EFS & FSx**
- [EFS performance](https://docs.aws.amazon.com/efs/latest/ug/performance.html) · [EFS features, storage classes](https://docs.aws.amazon.com/efs/latest/ug/features.html) · [EFS replication](https://docs.aws.amazon.com/efs/latest/ug/efs-replication.html)
- [FSx for Windows — Single-AZ vs Multi-AZ](https://docs.aws.amazon.com/fsx/latest/WindowsGuide/high-availability-multiAZ.html)
- [FSx for Lustre deployment and storage options](https://docs.aws.amazon.com/fsx/latest/LustreGuide/using-fsx-lustre.html)
- [FSx for NetApp ONTAP](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/what-is-fsx-ontap.html)
- [FSx for OpenZFS](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/what-is-fsx.html)

**Storage Gateway, transfer and backup**
- [Volume Gateway](https://docs.aws.amazon.com/storagegateway/latest/vgw/WhatIsStorageGateway.html) · [Storage Gateway quotas](https://docs.aws.amazon.com/storagegateway/latest/vgw/resource-gateway-limits.html)
- [Tape Gateway](https://docs.aws.amazon.com/storagegateway/latest/tgw/WhatIsStorageGateway.html)
- [FSx File Gateway (availability notice)](https://docs.aws.amazon.com/filegateway/latest/filefsxw/what-is-file-fsxw.html)
- [AWS DataSync](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html) · [DataSync task modes](https://docs.aws.amazon.com/datasync/latest/userguide/choosing-task-mode.html)
- [AWS Transfer Family](https://docs.aws.amazon.com/transfer/latest/userguide/what-is-aws-transfer-family.html)
- [Snowball Edge developer guide (availability notice)](https://docs.aws.amazon.com/snowball/latest/developer-guide/whatisedge.html) · [AWS Snow device updates (Storage Blog)](https://aws.amazon.com/blogs/storage/aws-snow-device-updates/) · [AWS Data Transfer Terminal](https://aws.amazon.com/data-transfer-terminal/)
- [AWS service availability updates (October 2025)](https://aws.amazon.com/about-aws/whats-new/2025/10/aws-service-availability/)
- [AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html) · [Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html) · [Logically air-gapped vault](https://docs.aws.amazon.com/aws-backup/latest/devguide/logicallyairgappedvault.html) · [Restore testing](https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-testing.html)
- [Organizations backup policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup.html)
- [AWS Overview whitepaper — Storage](https://docs.aws.amazon.com/whitepapers/latest/aws-overview/storage-services.html)
