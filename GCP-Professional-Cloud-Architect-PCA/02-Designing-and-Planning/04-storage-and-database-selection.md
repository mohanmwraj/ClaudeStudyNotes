# 02/04 · Storage and Database Selection

**Exam guide:** 1.3 ("choosing appropriate storage types (object, file, and databases)"), and the configuration side in 2.2. **Principles:** P4, P9, P10.

---

## 1. First question: what *shape* is the data?

```text
                        ┌── Unstructured blobs (media, backups, data lake, ML datasets) ──▶ Cloud Storage
                        ├── Shared POSIX files (lift-and-shift NFS, CMS, home dirs) ─────▶ Filestore / NetApp Volumes
 What is the data?  ────┼── Block device for one VM (boot, DB on VM) ───────────────────▶ Persistent Disk / Hyperdisk
                        ├── HPC / AI scratch with parallel high throughput ─────────────▶ Managed Lustre
                        ├── Structured, transactional (OLTP) ─────────▶ see §3 relational / NoSQL tree
                        ├── Analytical (OLAP), large scans, aggregations ─────────────────▶ BigQuery
                        └── Ephemeral, ultra-low-latency key-value (cache, sessions) ─────▶ Memorystore
```

---

## 2. Object, block and file storage

### Cloud Storage classes (all have millisecond access and the same durability design)

| Class | Minimum storage duration | Retrieval fee | Use for |
|---|---|---|---|
| **Standard** | None | None | Hot data, frequently accessed content, active data lake, serving |
| **Nearline** | 30 days | Yes | Accessed about once a month or less: recent backups, long-tail media |
| **Coldline** | 90 days | Higher | About once a quarter: older backups, DR copies |
| **Archive** | 365 days | Highest | Less than once a year: compliance archives, legal retention |

Deleting or moving an object before its minimum duration is billed as if it stayed for the minimum. That's why Archive is *wrong* for data accessed regularly.

**Location types**

* **Region:** lowest cost, data in one region, zone-redundant.
* **Dual-region:** two specific regions, geo-redundant, with optional **turbo replication** (15-minute RPO target).
* **Multi-region** (US, EU, ASIA): geo-redundant across a large area. Good for serving content widely.

**Cost and lifecycle tools**

* **Object Lifecycle Management** rules (age, created-before, storage class, number of newer versions, noncurrent time) → SetStorageClass or Delete.
* **Autoclass** moves each object between classes automatically based on its own access, with no retrieval fees or early-deletion charges for transitions it makes. Best when access patterns are **unknown or mixed**.
* Storage Insights / inventory reports show what's stored and how it's used.

**Protection**

* Object versioning.
* **Soft delete** (deleted objects recoverable for a retention window, 7 days by default).
* **Retention policy + Bucket Lock** (WORM: objects can't be deleted or replaced until they reach the retention age; a locked policy can't be removed or shortened).
* Object holds (event-based or temporary).
* **Object Retention Lock** (per-object retention).

**Access**

* IAM with **uniform bucket-level access** (recommended, disables ACLs).
* **Signed URLs** for time-limited access without a Google identity.
* **Public access prevention**.
* VPC Service Controls for exfiltration protection.

### Block storage

| Type | Characteristics | Use for |
|---|---|---|
| **Persistent Disk** (`pd-balanced`, `pd-ssd`, `pd-standard`, `pd-extreme`) | Network block storage; zonal or **regional** (synchronously replicated across two zones) | General VM disks; regional PD for HA failover of stateful VMs |
| **Hyperdisk** (Balanced, Balanced High Availability, Throughput, Extreme, ML) | Next-generation block storage; provision IOPS and throughput independently of capacity; Hyperdisk ML is read-optimized for many readers | High-performance DBs on VMs, SAP HANA, AI model loading |
| **Local SSD** | Physically attached; highest IOPS and lowest latency; **ephemeral** (data lost if the VM stops or the host fails) | Scratch, caches, temporary data, replicated databases that tolerate node loss |

### File storage

| Product | Characteristics | Use for |
|---|---|---|
| **Filestore** (Basic, Zonal, Regional, Enterprise tiers) | Managed NFS; Regional/Enterprise are zone-redundant | Lift-and-shift apps needing NFS, GKE ReadWriteMany volumes, media rendering |
| **NetApp Volumes** | Managed NetApp ONTAP features (NFS/SMB, snapshots, replication) | Enterprise NAS migrations, SMB for Windows |
| **Managed Lustre** | Parallel file system with very high throughput | HPC and AI training scratch |
| **Cloud Storage FUSE** | Mount a bucket as a file system (not fully POSIX) | Read-heavy ML datasets, simple file access to objects |

---

## 3. Databases

### The decision tree

```text
Is the workload analytical (scans, aggregations over large history, BI)?
   └─ yes → BigQuery  (+ Google Cloud Lakehouse for open Iceberg tables)

Transactional (OLTP):
   Relational/SQL with joins and ACID?
     ├─ Need horizontal write scale beyond one node, or global strong consistency,
     │  or 99.999% availability?                                  → Spanner
     ├─ PostgreSQL with high performance / mixed transactional + analytical,
     │  or AI vector search in PostgreSQL?                         → AlloyDB for PostgreSQL
     └─ Standard MySQL / PostgreSQL / SQL Server, one region, ≤ tens of TB,
        lift-and-shift compatibility?                               → Cloud SQL
   Non-relational?
     ├─ Very high throughput key/row access, time series, IoT, ad-tech, ≥ TBs,
     │  single-digit ms latency, single-row atomicity is enough?   → Bigtable
     ├─ Documents for web/mobile apps, real-time sync, offline,
     │  serverless scale, MongoDB-compatible API option?           → Firestore
     └─ In-memory cache / session / leaderboard (not system of record)? → Memorystore
   Oracle-specific features (RAC, PL/SQL heavy) without re-platforming?
     └─ Oracle Database@Google Cloud or Bare Metal Solution
```

### Database comparison

| | **Cloud SQL** | **AlloyDB** | **Spanner** | **Bigtable** | **Firestore** | **BigQuery** |
|---|---|---|---|---|---|---|
| Model | Relational (MySQL, PostgreSQL, SQL Server) | Relational (PostgreSQL-compatible) | Relational (GoogleSQL or PostgreSQL dialect); also graph, full-text, vector | Wide-column key-value (HBase API) | Document | Columnar warehouse |
| Scale | Vertical; read replicas; storage up to 64 TB | Vertical primary + read pool nodes; very high performance | **Horizontal**, effectively unlimited | Horizontal, PB scale | Horizontal, automatic | Serverless, PB scale |
| Consistency | Strong (primary) | Strong (primary) | **Strong / external consistency, global** | Strong within a cluster for single row; eventual across replicated clusters | Strong | N/A (analytical) |
| Transactions | ACID | ACID | ACID, distributed | Single-row only | ACID (document-level and multi-document) | DML, multi-statement transactions, not OLTP |
| Availability | HA 99.95% / Enterprise Plus 99.99% | 99.99% | 99.99% regional / 99.999% multi-region | Up to 99.999% with replication | 99.99% / 99.999% | 99.99% |
| Typical use | Lift-and-shift OLTP, CMS, ERP back ends | Demanding PostgreSQL OLTP + real-time analytics, gen-AI apps (vector) | Global ledgers, inventory, gaming, financial | IoT telemetry, time series, personalization, fraud features | Mobile/web app data, user profiles, catalogs | Data warehouse, BI, ML in SQL |
| Migration tool | Database Migration Service | DMS (from PostgreSQL; Oracle → AlloyDB) | Spanner migration tool (HarbourBridge), Datastream | HBase migration (snapshots / replication), Dataflow | Import/export; Atlas or Firestore MongoDB compatibility for MongoDB | BigQuery Migration Service, Data Transfer Service |

### Memorystore

| Engine | Notes |
|---|---|
| **Memorystore for Valkey** | Redis-compatible open-source engine; cluster mode; the recommended target for new caches and for Memcached migrations |
| Memorystore for Redis / Redis Cluster | Managed Redis; Standard tier = replica in another zone with automatic failover |
| Memorystore for Memcached | **Deprecated** (2026-01-20; shutdown 2029-01-31). Don't choose it for new designs |

### Bigtable row-key design (frequently tested)

* Rows are sorted lexicographically by key, and load is split by key range.
* **Avoid hot-spotting:** don't start keys with a monotonically increasing value (a timestamp or sequential ID). Prefix with a high-cardinality field (device ID or user ID), optionally hashed or salted.
* For "latest first" scans, append a **reversed timestamp**: `deviceId#(Long.MAX − ts)`.
* Keep related data in the same row or adjacent rows. Design keys for your **queries** (single-row lookups and contiguous range scans).
* Use replication with **multi-cluster routing** for availability, and app profiles to isolate batch from serving traffic.

### Spanner key design

* Avoid monotonically increasing primary keys (they hot-spot one split). Use UUIDv4, bit-reversed sequences or a hash prefix.
* **Interleaved tables** co-locate child rows with parents for efficient joins.
* Choose a regional configuration (99.99%) or a multi-region configuration (99.999%, higher write latency due to cross-region quorum).

---

## 4. Vector and AI-ready storage (increasingly tested with gen-AI scenarios)

| Option | Use when |
|---|---|
| **AlloyDB AI** (pgvector + ScaNN index) | Vector search next to operational PostgreSQL data |
| Cloud SQL for PostgreSQL / MySQL vector support | Existing Cloud SQL apps adding semantic search |
| **Spanner** vector search | Global-scale apps already on Spanner |
| **BigQuery** vector search | Analytical / batch similarity over warehouse data |
| **Firestore** vector search | Mobile/web apps on Firestore |
| **Vector Search** (Agent Platform) | Dedicated, very high-scale, low-latency ANN search |
| **Agent Search / RAG Engine** | You want managed retrieval (chunking, embedding, indexing, ranking) rather than building it |

---

## 5. Requirement → storage choice: fast lookup

| Scenario cue | Choice |
|---|---|
| "Store 2 PB of video; most files are viewed in the first month and rarely after; unpredictable which ones" | Cloud Storage with **Autoclass** |
| "Keep backups 7 years for compliance, almost never read, must be immutable" | Archive class + retention policy + **Bucket Lock** |
| "Global player profiles with strongly consistent purchases across continents" | Spanner multi-region |
| "Ingest 500,000 sensor readings/s; query recent readings per device" | Bigtable (key: deviceId#reversedTs) via Pub/Sub → Dataflow |
| "Ad-hoc SQL over 3 years of clickstream" | BigQuery (partitioned by date, clustered by user/page) |
| "Lift-and-shift PostgreSQL app, standard features, one region, minimal changes" | Cloud SQL for PostgreSQL |
| "PostgreSQL app with heavy reporting queries slowing transactions" | AlloyDB (columnar engine) or read replicas / read pool |
| "Mobile app with offline sync and real-time updates" | Firestore |
| "Shared NFS for a legacy CMS on several VMs" | Filestore (Regional/Enterprise for HA) |
| "Session store for a stateless web tier" | Memorystore (Valkey/Redis, HA tier) |
| "MongoDB workloads, minimal change" | MongoDB Atlas (Marketplace) or Firestore with MongoDB compatibility |
| "VM scratch space with maximum IOPS; data is disposable" | Local SSD |
| "Stateful VM must survive a zone failure with near-zero data loss" | Regional Persistent Disk (or Hyperdisk Balanced HA) + regional MIG with stateful config |

---

## 6. Traps

* **BigQuery as an OLTP database** (high-rate single-row updates) or as a low-latency serving store for app lookups.
* **Bigtable for ad-hoc SQL joins** or multi-row transactions.
* **Cloud SQL for global multi-region writes.** Cloud SQL has a single primary; cross-region replicas are read-only until promoted.
* **Memorystore as the only copy** of important data.
* **Coldline/Archive for data read weekly** (retrieval fees and minimum durations).
* **Multi-region buckets for data that must stay in one country**, or a US multi-region for EU-resident data.
* **Local SSD for data that must persist.**
* **Memcached for new designs.** It's deprecated; use Valkey.

---

## References

* Storage options overview: <https://cloud.google.com/products/storage>
* Cloud Storage classes: <https://cloud.google.com/storage/docs/storage-classes>
* Autoclass: <https://cloud.google.com/storage/docs/autoclass>
* Bucket Lock / retention policies: <https://cloud.google.com/storage/docs/bucket-lock>
* Choosing a database: <https://cloud.google.com/products/databases>
* Bigtable schema design: <https://cloud.google.com/bigtable/docs/schema-design>
* Spanner schema best practices: <https://cloud.google.com/spanner/docs/schema-design>
* Memorystore for Memcached deprecation: <https://cloud.google.com/memorystore/docs/memcached/deprecation>
