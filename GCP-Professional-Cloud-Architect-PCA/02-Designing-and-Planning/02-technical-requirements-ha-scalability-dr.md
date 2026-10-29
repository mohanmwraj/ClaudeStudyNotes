# 02/02 · Technical Requirements: HA, Scalability, Performance, Backup and DR

**Exam guide:** 1.2 (and the DR part of 4.1). **Principles:** P1, P2, P3, P9, P13.

---

## 1. Availability building blocks, layer by layer

High availability is a property of the **whole path**: DNS → load balancer → compute → data → dependencies. A design is only as available as its weakest serial component (P2).

### Published SLAs worth knowing (monthly uptime)

| Service and configuration | SLA |
|---|---|
| Compute Engine: instances across **multiple zones** (Premium Tier, most regions) | **99.99%** |
| Compute Engine: single instance (memory-optimized: 99.95%) | **99.9%** |
| GKE: regional cluster control plane / zonal control plane | 99.95% / 99.5% |
| Cloud Run | 99.95% |
| Cloud SQL Enterprise edition (HA) / **Enterprise Plus** (HA, includes maintenance) | 99.95% / **99.99%** |
| AlloyDB for PostgreSQL (HA primary) | 99.99% |
| Spanner: regional / **multi-region** | 99.99% / **99.999%** |
| Bigtable: single cluster / replicated with multi-cluster routing | 99.9% / up to 99.999% |
| Firestore: regional / multi-region | 99.99% / 99.999% |
| Cloud Storage Standard: regional / dual- and multi-region | 99.9% / 99.95% |
| BigQuery | 99.99% |
| HA VPN (two interfaces, correctly configured) | 99.99% |
| Interconnect: redundant pair in one metro / critical topology | 99.9% / 99.99% |

Always confirm current numbers on the per-service SLA pages. The *ratios* between zonal, regional and multi-regional are what the exam tests, not the decimals.

### Per-layer HA patterns

| Layer | Zonal failure tolerance | Regional failure tolerance |
|---|---|---|
| Entry point | Regional external/internal load balancer | **Global external Application Load Balancer** (anycast, cross-region failover), or Cloud DNS failover / geolocation routing policies with health checks |
| VMs | **Regional MIG** (instances spread across zones), autohealing with health checks | MIGs in two regions behind a global LB |
| Containers | **Regional GKE cluster** (control plane and nodes in 3 zones); PodDisruptionBudgets; topology spread | Clusters in two regions; multi-cluster Gateway; Backup for GKE |
| Serverless | Cloud Run is regional (zone-redundant by design) | Cloud Run in two regions behind a global LB with **serverless NEGs** |
| Relational DB | **Cloud SQL HA** (synchronous standby in another zone; automatic failover), AlloyDB HA | Cloud SQL **cross-region read replica** (promote on disaster; async, so RPO > 0); **Spanner multi-region** (RPO 0, automatic) |
| NoSQL | Bigtable cluster (zonal) + replication | Bigtable replication across regions with multi-cluster routing; Firestore multi-region |
| Cache | Memorystore Standard tier / HA (replica in another zone, automatic failover) | Cross-region replication (Memorystore for Valkey / Redis Cluster) or rebuild cache in DR region |
| Objects | Regional bucket (zone-redundant) | **Dual-region** or **multi-region** bucket; **turbo replication** for dual-region (RPO target 15 min) |
| Files | Filestore Enterprise/Regional tier (regional) | Filestore backups or replication to another region |

---

## 2. Failover design

| Approach | How it works | RTO | Cost | Use when |
|---|---|---|---|---|
| **Active-passive (cold/warm)** | Secondary is idle or scaled down; promote on failure | Minutes–hours | Lower | Most business apps; RPO > 0 acceptable |
| **Active-active** | All sites serve traffic; global LB distributes; data replicated multi-master or via Spanner | Seconds (automatic) | Highest | Global user base, near-zero RTO and RPO |
| **DNS-based failover** | Cloud DNS routing policy with health checks switches records | Bounded by TTL and health-check interval | Low | Non-HTTP workloads, hybrid failover |
| **Load-balancer failover** | Global LB stops sending to unhealthy backends | Seconds | Included | HTTP(S), TCP/SSL proxy workloads |

**Key facts**

* Cloud SQL HA failover is automatic within the region. The instance keeps its IP, and clients reconnect.
* Cross-region replicas need a **promote** step: manual, or scripted with **cross-region disaster recovery (DR replicas)** for Enterprise Plus, which supports switchover and failover with replica-to-primary role swap.
* Spanner multi-region configurations fail over automatically with zero data loss, because writes commit across regions using Paxos.
* GKE regional clusters keep the control plane available during a zone outage. Workloads need **≥ 2 replicas** spread across zones to survive one.

---

## 3. Scalability

| Platform | Scaling mechanism | Signals |
|---|---|---|
| Compute Engine MIG | Autoscaler (add/remove VMs) | CPU utilization, load-balancer serving capacity, Cloud Monitoring metrics (including Pub/Sub backlog), **schedules**; **predictive autoscaling** for workloads with long start-up and cyclical load |
| GKE | **Horizontal Pod Autoscaler** (replicas), **Vertical Pod Autoscaler** (requests), **cluster autoscaler** (nodes), **node auto-provisioning** (new node pools); Autopilot does nodes for you | CPU/memory, custom and external metrics |
| Cloud Run | Request-based autoscaling, **concurrency** per instance (default 80, up to 1000), **min instances** (avoid cold starts), **max instances** (protect downstream) | Concurrent requests, CPU |
| Cloud Run functions | One request per instance by default (configurable concurrency in current generation) | Requests/events |
| Dataflow | Horizontal autoscaling of workers; Streaming Engine; vertical autoscaling | Backlog, throughput |
| BigQuery | Serverless slots; editions with autoscaling slot reservations | Query demand |
| Spanner | Add nodes/processing units; managed autoscaler | CPU utilization, storage |
| Bigtable | Add nodes; built-in autoscaling | CPU, storage |
| Pub/Sub | Fully managed, no capacity planning | — |

**Scaling limits are quotas and downstream capacity.** A design that autoscales the front end into a fixed-size database just moves the bottleneck. Use queues (P8), connection pooling (Cloud SQL Auth Proxy / managed connection pooling, AlloyDB), caching and **max instances** to protect dependencies. Request quota increases ahead of planned growth.

---

## 4. Disaster recovery: RTO/RPO to pattern

Google's DR guide frames recovery as **cold, warm and hot** patterns:

| Pattern | Description | Typical RTO | Typical RPO | Google Cloud implementation |
|---|---|---|---|---|
| **Backup and restore (cold)** | Data backed up; infrastructure re-created on demand from IaC | Hours–days | Hours (last backup) | Snapshots/backup vaults in another region, Cloud Storage dual/multi-region, Terraform to rebuild |
| **Pilot light** | Core data replicated live; minimal compute off or tiny | Tens of minutes–hours | Minutes | Cloud SQL cross-region replica, images ready, MIG at size 0 |
| **Warm standby** | Scaled-down full stack running in DR region | Minutes | Seconds–minutes | Second-region GKE/MIG at reduced size, replicas, global LB ready to shift |
| **Multi-site active-active (hot)** | Full capacity in ≥ 2 regions serving traffic | Near zero | Near zero | Global LB, Spanner multi-region / Firestore multi-region, stateless compute in each region |

**Choose the cheapest pattern that meets the RTO/RPO** (P9). Hybrid DR (on-premises primary with Google Cloud as DR) uses the same patterns, with Interconnect or VPN and replication tools (Backup and DR Service, database replication).

**DR checklist the exam likes**

* Replicate data to a **different region** (a zone isn't a DR site).
* Keep infrastructure as **code** so the DR environment is reproducible.
* Make backups **immutable** (backup vaults, Bucket Lock) to survive ransomware and operator error.
* **Test** failover regularly and measure the achieved RTO/RPO.
* Plan **failback**.
* Check quotas and capacity in the DR region (reservations if capacity must be guaranteed).

---

## 5. Backup and recovery by service

| Service | Backup / recovery capability |
|---|---|
| Persistent Disk / Hyperdisk | **Snapshots** (incremental, stored multi-regionally or regionally, schedule-based snapshot policies); **machine images** (full VM config + disks); instant snapshots for fast local recovery |
| Compute Engine / VMware / databases at scale | **Backup and DR Service**: centralized, policy-based backups, with **backup vaults** that enforce immutability and retention (indelible backups) |
| GKE | **Backup for GKE**: cluster state and persistent volumes; restore to the same or another cluster/region |
| Cloud SQL | Automated daily backups plus **point-in-time recovery** (transaction logs); on-demand backups; backups can be retained after instance deletion |
| AlloyDB | Continuous backup and PITR; on-demand and scheduled backups |
| Spanner | Backups (including cross-region copy); **PITR** with version retention up to 7 days |
| Firestore | Scheduled backups; PITR (up to 7 days) |
| Bigtable | Backups (table-level), copy to other clusters |
| BigQuery | **Time travel** (up to 7 days), **fail-safe** (7 additional days, recover via support), table snapshots, cross-region dataset replication |
| Cloud Storage | **Object versioning**, **soft delete** (default 7-day retention of deleted objects), retention policies and **Bucket Lock** (WORM), object holds, dual/multi-region |
| Filestore | Backups (regional), snapshots |

---

## 6. Performance and latency

| Lever | Effect |
|---|---|
| Put compute near users (multi-region) and near data (same region as DB) | Cuts round trips (P1) |
| **Global external Application Load Balancer** + **Premium Tier** | Users enter Google's network at the nearest edge, then cross the backbone |
| **Cloud CDN** / **Media CDN** | Cache static and video content at the edge |
| **Memorystore** | Sub-millisecond reads for hot keys and sessions |
| Read replicas (Cloud SQL, AlloyDB read pools) | Offload reads |
| **AlloyDB columnar engine**, **BigQuery BI Engine** | Accelerate analytical queries |
| Bigtable **row-key design** | Avoid hot-spotting (no monotonically increasing prefixes such as raw timestamps) |
| Spanner **key design** | Avoid sequential primary keys; use UUIDv4 or bit-reversed sequences; interleaved tables for locality |
| Machine family choice | Compute-optimized or high-clock series for latency-sensitive compute; local SSD for scratch I/O |
| **Rapid Cache** (formerly Anywhere Cache) | Zonal SSD read cache for Cloud Storage. Speeds up read-heavy analytics or AI training data in one zone |
| Load testing and profiling | Measure before tuning: Cloud Profiler, Cloud Trace, load tests |

---

## 7. Flexibility of cloud resources

* **Custom machine types:** pick exact vCPU/memory (for example, a license-bound app needing 6 vCPUs and 40 GB).
* **Live migration:** Google moves VMs during host maintenance without reboot (not for GPU VMs and some specialized types, which terminate and restart per maintenance policy).
* **Resizing:** stop and change machine type; resize disks online.
* **Instance templates and MIGs:** declarative fleet definitions; rolling updates to new templates.
* **Sole-tenant nodes:** dedicated physical hosts for compliance or BYOL licensing.
* **Reservations:** guarantee zonal capacity (for DR or peak events), combinable with CUDs.

---

## 8. Gemini Cloud Assist (named in exam guide 1.2 and 5.1)

**Gemini Cloud Assist** is the AI assistant built into Google Cloud, part of **Gemini for Google Cloud**. It helps across the lifecycle:

| Activity | What it does |
|---|---|
| **Design** | Generates architectures from natural-language requirements (integrated with **Application Design Center**), suggests services, produces diagrams and Terraform |
| **Deploy and operate** | Explains resources and configurations, generates `gcloud` commands and IaC, answers "how do I…" in context |
| **Troubleshoot** | **Investigations**: analyzes logs, metrics, configuration and recent changes to propose root causes and fixes |
| **Optimize** | Surfaces cost and performance insights (with FinOps hub / Recommender), explains bills, suggests rightsizing |

**Exam angle:**

* When a question asks for the **fastest way for a team to understand, design or troubleshoot** using Google-provided tooling, Gemini Cloud Assist is a valid and modern answer.
* It **assists**; it doesn't replace IAM, change management or testing. An answer that lets AI make unreviewed production changes is wrong.

---

## 9. Worked scenarios

**A. "A web app on one Compute Engine VM must reach 99.99% availability with minimal cost increase."**
A single VM is at most 99.9% (P2). The design: a regional MIG with at least 2–3 instances across zones, autohealing, and a load balancer. Externalize state (P3). The database must match: Cloud SQL Enterprise Plus HA (99.99%) or AlloyDB.

**B. "RPO 5 minutes, RTO 1 hour, cost-sensitive, regional disaster."**
Warm standby or pilot light. Cloud SQL cross-region replica (async, RPO seconds–minutes), images and IaC in the DR region, a MIG pre-created at small size, and a global LB or DNS cutover runbook. Hot active-active is over-engineered here.

**C. "A team accidentally deleted objects in a production bucket yesterday."**
If soft delete (default 7 days) or object versioning was on, restore. Going forward: keep versioning plus lifecycle rules for noncurrent versions, add a retention policy for critical data, and use least-privilege IAM so a single user can't bulk-delete.

**D. "Users in Asia see 300 ms latency to a US-only app; data must remain in the US."**
Cache static content with Cloud CDN, and use a global external Application Load Balancer with Premium Tier so traffic enters Google's network nearby. Data stays in the US. If dynamic responses must be fast, consider read-only caches of non-regulated data in Asia. You can't break the residency requirement to fix latency.

---

## References

* Building blocks of reliability: <https://cloud.google.com/architecture/infra-reliability-guide/building-blocks>
* DR planning guide: <https://cloud.google.com/architecture/dr-scenarios-planning-guide>
* Cloud SQL high availability: <https://cloud.google.com/sql/docs/mysql/high-availability>
* Backup and DR Service: <https://cloud.google.com/backup-disaster-recovery/docs/concepts/backup-dr>
* Gemini Cloud Assist: <https://cloud.google.com/gemini/docs/cloud-assist/overview>
* Compute Engine SLA: <https://cloud.google.com/compute/sla>
