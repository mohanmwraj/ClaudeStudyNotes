# Chapter 12 — Reliability, High Availability & Disaster Recovery
> **Exam mapping:** D1 Task 1.3 (reliable & resilient architectures), D2 Task 2.2 (business continuity), D2 Task 2.4 (reliability), D3 Task 3.4 (improve reliability) | **Weight signal:** Very High: expect 8–12 questions where resilience or DR decides the answer | **Study time:** ~7 h
> [← Previous](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md) · [Index](../00-README-Start-Here.md) · [Next →](../13-Migration-and-Modernization/13-Migration-and-Modernization.md)

---

## 1. What the exam really tests here

SAP-C02 rarely asks "what is Multi-AZ?". It gives you a business with an **RTO, an RPO, a budget and an operations team of a certain size**, and asks you to pick the **cheapest architecture that still meets the objectives** with the **least operational overhead**. You must be able to:

| Skill | Typical scenario signal |
|---|---|
| Turn RTO/RPO into a DR strategy | "RPO 15 min, RTO 4 h, minimise cost" → Backup & Restore or Pilot Light, *not* active/active |
| Pick the replication primitive per data store | "RPO of seconds for MySQL across Regions" → Aurora Global Database, not RDS snapshots copied hourly |
| Pick the traffic-shifting primitive | "Static IPs, fast failover, non-HTTP" → Global Accelerator; "DNS failover" → Route 53 health checks; "failover must not depend on control plane" → ARC routing controls |
| Design fault isolation | Multi-AZ by default; multi-Region only when the RTO/RPO, regulation or latency calls for it; cells/shuffle sharding to limit blast radius |
| Apply resilience patterns in code | Retries with exponential backoff and jitter, timeouts, idempotency keys, circuit breakers, load shedding |
| Make DR work when needed | Quotas, capacity reservations, AMIs/secrets/keys/container images already in the DR Region, IaC, runbooks, game days, FIS, Resilience Hub |
| Separate *backup* from *DR* | Ransomware or corruption → immutable, isolated backups (Vault Lock, logically air-gapped vault, separate account) because replication copies the corruption |
| Lift existing (often on-prem) servers into a DR posture | AWS Elastic Disaster Recovery (DRS): block-level replication, low-cost staging area, RPO in seconds, RTO in minutes |

**Mental model for every question:** *What can fail (component, AZ, Region, data, people)? How fast must we recover (RTO)? How much data can we lose (RPO)? What is the cheapest, most automated way to meet both?*

---

## 2. Core concepts & services: deep dive

### 2.1 Vocabulary you must use correctly

| Term | Precise meaning (AWS definitions) | Exam nuance |
|---|---|---|
| **Availability** | % of time a workload can be used as intended | Measured over a period; maps to "nines" |
| **Resiliency** | Ability to keep availability and to recover from disruption within a set time | Includes HA *and* DR |
| **High availability (HA)** | Keep running through *common, expected* failures (instance, AZ) | Usually Multi-AZ, automatic, no data loss |
| **Disaster recovery (DR)** | Recover from *rare, large-scale* events (Region, data corruption, ransomware, operator error) | Usually involves another Region or isolated backups |
| **RTO** | **Maximum acceptable delay between the interruption of service and restoration of service** | Downtime budget |
| **RPO** | **Maximum acceptable amount of time since the last data recovery point** | Data-loss budget, measured in time |
| **MTTR / MTBF** | Mean time to repair / between failures | Availability ≈ MTBF / (MTBF + MTTR). Cutting MTTR is usually cheaper than raising MTBF |
| **Blast radius** | Scope of impact of a single failure | Reduced by cells, shuffle sharding, AZ independence, account separation |
| **Static stability** | System keeps working *without making changes* while a dependency (often a control plane) is impaired | Pre-provision capacity; don't rely on scaling or API calls during the event |

> **HA ≠ DR, and replication ≠ backup.** Multi-AZ RDS protects against an AZ loss but faithfully replicates a `DROP TABLE`. Cross-Region replication protects against a Region loss but also replicates ransomware encryption. You need **point-in-time, immutable backups** for logical corruption.

### 2.2 Well-Architected Reliability pillar

**Five design principles** (memorise them, the exam quotes them):

1. **Automatically recover from failure.** Monitor KPIs and trigger automated recovery when a threshold is breached (Auto Scaling health replacement, Multi-AZ failover, Route 53 failover).
2. **Test recovery procedures.** Simulate failures (FIS, game days) and validate runbooks. Untested DR is assumed broken.
3. **Scale horizontally to increase aggregate workload availability.** Replace one large resource with many small ones so that no single failure affects everyone.
4. **Stop guessing capacity.** Monitor demand and use automatic scaling. (Note the tension with static stability: for DR, pre-provision what you *must* have.)
5. **Manage change through automation.** Infrastructure as code, automated deployments, change tracked and reviewable.

**Four best-practice areas:** Foundations (quotas, network topology), Workload architecture (service architecture, distributed-system design), Change management (monitoring, scaling, deployment), Failure management (backup, fault isolation, withstand component failures, test reliability, plan for DR).

Key "foundations" points that show up as distractors:
- **Service quotas** are per account **per Region**. A DR Region with default quotas cannot absorb production load. Request increases ahead of time; use **Service Quotas** + **quota request templates** in AWS Organizations so new accounts start with the right quotas.
- **IP address planning**: non-overlapping CIDRs across Regions and on-prem so that DR VPCs can peer or attach to Transit Gateway.
- **Redundant connectivity**: Direct Connect resiliency (two locations, two connections each for maximum resiliency) plus VPN backup. (See [Chapter 04](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md).)

### 2.3 Availability math

**Serial dependencies** (all must work): `A_total = A1 × A2 × … × An`
**Parallel / redundant components** (any one suffices): `A_total = 1 − (1 − A1) × (1 − A2) × …`

Worked examples:

| Design | Calculation | Result |
|---|---|---|
| Web (99.9%) → App (99.9%) → DB (99.9%) in series | 0.999³ | **99.7%** (~26 h/yr down). Every serial hop *reduces* availability |
| Two independent 99.9% app tiers in parallel | 1 − 0.001² | **99.9999%** in theory. Redundancy *multiplies* the "nines" |
| Two Regions each 99.9%, with failover that works 99% of the time | ≈ 0.999 + (0.001 × 0.99 × 0.999) | ≈ **99.999%**, but only if failover is tested and the Regions are truly independent |
| Hard dependency on a 99.5% third-party API | Your ceiling is 99.5% unless you degrade gracefully or cache | Soft dependencies are needed to go higher |

Parallel math assumes **independent failures**. Shared dependencies (the same deployment pipeline, the same DNS provider, the same IAM control plane, the same bad config push) break the independence assumption. This is why AWS stresses AZ independence, cell architecture and staggered deployments.

**"Nines" table (365-day year):**

| Availability | Downtime / year | Downtime / month (30 d) | Typical design |
|---|---|---|---|
| 99% | 3.65 days | 7.2 h | Single instance, manual recovery |
| 99.5% | 1.83 days | 3.6 h | Single AZ with automated restart |
| 99.9% | 8.76 h | 43.2 min | Multi-AZ, automated failover |
| 99.95% | 4.38 h | 21.6 min | Multi-AZ, well-tested, quick deploy rollback |
| 99.99% | 52.6 min | 4.3 min | Multi-AZ + strong automation, cell-based, maybe multi-Region for data tier |
| 99.999% | 5.26 min | 26 s | Multi-Region active/active, automated everything, static stability |

Rule of thumb: **each extra nine costs roughly an order of magnitude more** in engineering and operations, and needs automated (not human) detection and recovery. A human cannot be paged, log in and act inside 26 seconds.

### 2.4 Fault isolation boundaries

AWS's *Fault Isolation Boundaries* whitepaper defines the layers you design around:

| Boundary | What it isolates | Design implication |
|---|---|---|
| **Partition** (aws, aws-cn, aws-us-gov) | Completely separate infrastructure and IAM | Cross-partition DR is rare; credentials and services don't span partitions |
| **Region** | Independent control planes for most services; Regions are isolated from each other | Multi-Region for Region-level events, data residency, latency |
| **Availability Zone** | One or more discrete data centers with independent power, cooling, networking; low-latency links between AZs | **Default HA unit.** Spread across ≥2 (prefer 3) AZs |
| **Zonal services** (EC2, EBS, subnets, NAT GW) | Resource lives in one AZ | You must deploy redundantly yourself |
| **Regional services** (S3, DynamoDB, SQS, Lambda) | AWS spreads across AZs for you | Already Multi-AZ; still single-Region |
| **Global services** (IAM, Route 53, CloudFront, Global Accelerator, Organizations) | Control plane usually in one Region (often us-east-1); **data plane is globally distributed** | Design recovery to use **data-plane** operations only |

#### Control plane vs data plane

- **Control plane** = APIs that create/modify/delete resources (e.g., `RunInstances`, `CreateLoadBalancer`, editing Route 53 records, IAM `CreateRole`). More complex, lower availability design goal.
- **Data plane** = the service doing its job (EC2 instance running, ELB forwarding packets, Route 53 answering DNS queries and evaluating health checks, IAM authenticating requests with existing credentials).
- **Best practice: rely on the data plane, not the control plane, during recovery.** Examples:
  - Route 53 **health checks and failover records** (data plane) instead of a Lambda that *edits* DNS records during an incident (control plane in us-east-1).
  - **ARC routing controls**: flipping a routing control is a data-plane call to a highly available cluster of five Regional endpoints.
  - **Pre-provisioned** capacity in the surviving AZs/Region instead of `RunInstances` during the event.
  - Pre-created IAM roles and break-glass users in the DR Region's accounts instead of creating them during the event.

#### Static stability

A statically stable system **continues to operate correctly when a dependency fails, without needing to make changes**. Canonical AWS example: EC2 instances keep running when the EC2 control plane is impaired. Design application stacks the same way:

- Over-provision across AZs so losing one AZ still leaves 100% of required capacity (e.g., 3 AZs × 50% each = 150%, lose one → 100%). Zonal autoshift explicitly requires this "pre-scale" approach.
- Cache configuration, credentials and DNS answers locally with safe TTLs so a config service outage doesn't take you down.
- Keep warm standby already scaled to the minimum needed for initial traffic.

#### Cell-based architecture

Split the workload into **multiple independent, identical, full-stack replicas ("cells")**, each serving a subset of customers, behind a **thin routing layer**. A failure, bad deployment or poison-pill request affects only one cell.

- Cell = complete copy of the stack (compute + data) with a max size you test to.
- **Partition key** (customer ID, tenant ID) maps requests to cells; the router must be extremely simple and highly available.
- Deploy to one cell first (a natural canary), then wave through others.
- Scale by **adding cells** rather than growing them (known-tested limits).
- Trade-offs: higher baseline cost, cross-cell queries are hard, router is a critical dependency, cell migration tooling needed.

#### Shuffle sharding

Assign each customer to a **random combination of a small number of workers** out of a larger pool. With 8 workers and shards of 2, there are 28 unique combinations. A poison-pill customer that takes down its 2 workers only fully affects the customers who share **both** workers. Everyone else still has at least one healthy worker. Route 53 uses this internally for its name servers. Exam signal: "noisy neighbour / one tenant's malformed requests should not affect others" → cell-based or shuffle sharding.

### 2.5 Multi-AZ vs multi-Region

| Factor | Multi-AZ (single Region) | Multi-Region |
|---|---|---|
| Protects against | Instance, rack, data center, **AZ** failures | **Region-wide** impairment, large-scale disaster, some regulatory requirements |
| Typical RPO | 0 (synchronous replication: RDS Multi-AZ, Aurora storage, EBS within AZ, S3/DynamoDB) | Seconds to hours (cross-Region replication is **asynchronous** except DynamoDB MRSC) |
| Typical RTO | Seconds to ~2 min (automatic) | Minutes to hours depending on strategy |
| Cost | Moderate (2–3× compute at most) | High: duplicated infra, inter-Region data transfer, more ops |
| Complexity | Low; much is managed by AWS | High: data consistency, failover orchestration, testing, config drift |
| Latency | Single-digit ms between AZs | Tens to hundreds of ms between Regions |
| When required | **Always** for production | When the business case needs RTO/RPO against Region loss, data residency, global users, or regulation demands geographic separation |

**Exam heuristic:** If the question says only "highly available" or "survive an AZ failure", **Multi-AZ is enough**; multi-Region is a costly distractor. If it says "Regional outage", "disaster affecting the entire Region", "geographically separated", go multi-Region and then pick the strategy by RTO/RPO.

### 2.6 Resilience patterns (application level)

| Pattern | What it does | AWS implementation / note |
|---|---|---|
| **Timeouts** | Bound how long a caller waits; prevents thread/connection exhaustion | Set client timeouts lower than upstream; ALB idle timeout; Lambda timeout < SQS visibility timeout; API Gateway 29 s default integration timeout (can be raised for Regional/private REST APIs) |
| **Retries with exponential backoff and jitter** | Recover from transient faults without synchronised retry storms | AWS SDKs implement retry modes (`standard`, `adaptive`) with backoff + jitter. "Full jitter" = `sleep = random(0, min(cap, base × 2^attempt))`. Limit retry count, retry only at one layer |
| **Idempotency** | Repeated requests have the same effect as one | Idempotency keys / client tokens (EC2 `ClientToken`), conditional writes in DynamoDB, Powertools for Lambda idempotency utility. **Required** for at-least-once delivery (SQS standard, EventBridge, Lambda async retries) |
| **Circuit breaker** | Stop calling a failing dependency; fail fast; probe periodically (closed → open → half-open) | Implement in code/service mesh; Step Functions can model it with a DynamoDB-stored state |
| **Bulkheads** | Partition resources so one failure doesn't sink everything | Separate thread/connection pools, separate Lambda reserved concurrency per function, separate SQS queues per tenant class, cells |
| **Load shedding** | Reject excess work early (fast 503/429) so accepted work completes within latency goals | API Gateway throttling/usage plans, WAF rate-based rules, ALB + app-level admission control, SQS as buffer |
| **Graceful degradation** | Turn hard dependencies into soft ones; serve reduced functionality | Return cached/static content (CloudFront serves stale, S3 static fallback), hide recommendations if the recommender is down |
| **Queue-based load leveling** | Decouple producer and consumer speeds | SQS, Kinesis, EventBridge; DLQs for poison messages |
| **Health checks: shallow vs deep** | *Shallow (liveness)*: process up, port responds. *Deep (readiness)*: verifies dependencies (DB, cache) | **Danger:** deep checks on the LB can mark *every* host unhealthy when a shared dependency fails (cascading removal). ELB fails open when all targets are unhealthy. Use shallow checks for LB target health, deep checks for Route 53 Regional failover decisions and alarms |
| **Constant work** | System does the same amount of work regardless of load or failure (e.g., push full config every interval, not deltas) | Avoids "bimodal behaviour" where failure mode triggers new, untested code paths. Route 53 health checkers are a classic example |
| **Avoid bimodal behaviour** | Same code path in normal and failure modes | E.g., always read from cache-plus-fallback, not "only call the backup on failure" |
| **Throttling the retries** | Token-bucket retry quotas so retries cannot exceed X% of traffic | SDK `standard` mode uses a retry quota |

### 2.7 The four DR strategies (AWS DR whitepaper)

AWS orders the strategies by **increasing cost and complexity** and **decreasing RTO/RPO**:

```text
  Cost / complexity  ───────────────────────────────────────────────►
  ┌────────────────┬────────────────┬────────────────┬────────────────────────┐
  │ Backup &       │ Pilot Light    │ Warm Standby   │ Multi-site             │
  │ Restore        │                │                │ active/active          │
  │                │                │                │ (or hot standby        │
  │                │                │                │  active/passive)       │
  ├────────────────┼────────────────┼────────────────┼────────────────────────┤
  │ RPO/RTO: hours │ RPO/RTO: tens  │ RPO/RTO:       │ RPO/RTO: near zero     │
  │                │ of minutes     │ minutes        │ (RPO not zero for      │
  │                │                │                │  corruption)           │
  └────────────────┴────────────────┴────────────────┴────────────────────────┘
  ◄─────────────────────────────────────────────── RTO / RPO (time to recover)
```

> **Indicative ranges only.** The whitepaper describes the tiers qualitatively (hours → tens of minutes → minutes → near real time). Real numbers depend on data volume, automation and testing. Treat any specific number in a question as the decider.

#### 2.7.1 Backup & Restore

- **What runs in the DR Region:** nothing but backups (and IaC templates ready to deploy).
- **Data:** Point-in-time backups copied cross-Region (and ideally cross-account): EBS snapshots, AMIs, RDS/Aurora snapshots, DynamoDB backups, EFS/FSx backups, S3 replication or AWS Backup copies.
- **Recovery:** Deploy infrastructure with **CloudFormation/CDK/Terraform**, restore data from backups, switch DNS.
- **RPO** = backup frequency (e.g., hourly snapshots → up to 1 h loss; continuous backups/PITR can reduce it). **RTO** = time to deploy + restore + validate (hours, longer for large data sets).
- **Also the baseline for every other strategy**: even active/active needs backups for corruption/ransomware.
- **Cost:** storage + cross-Region data transfer only.

```text
   PRIMARY REGION (us-east-1)                        DR REGION (us-west-2)
  ┌────────────────────────────────┐               ┌──────────────────────────────┐
  │ Route 53 ──► ALB ──► ASG (EC2) │               │  (no running compute)        │
  │                    │           │               │                              │
  │                    ▼           │  AWS Backup   │  Backup vault (copies)       │
  │            RDS / EBS / EFS ────┼──cross-Region─┼─► snapshots, AMIs, backups   │
  │                                │  copy         │                              │
  │            S3 bucket ──────────┼── S3 CRR ─────┼─► S3 bucket                  │
  └────────────────────────────────┘               │  IaC templates in pipeline   │
                                                   │  ─ on disaster: deploy stack │
                                                   │    restore data, flip DNS    │
                                                   └──────────────────────────────┘
```

#### 2.7.2 Pilot Light

- **What runs in the DR Region:** the **core data tier live and replicating** (e.g., Aurora Global Database secondary cluster, DynamoDB global table replica, S3 CRR target); **compute is off or not deployed** (ASG desired = 0, AMIs and launch templates ready, or IaC ready).
- **Recovery:** **Turn on / deploy and scale out** compute, promote the database, switch traffic. Cannot serve traffic until this is done.
- **RPO:** seconds to minutes (continuous replication). **RTO:** tens of minutes (provisioning and scaling).
- **Cost:** data replication + small DB footprint. You can cut cost further with an **Aurora headless secondary** (storage only, no DB instances) at the price of a longer RTO (add an instance before promoting).

```text
   PRIMARY REGION                                    DR REGION
  ┌─────────────────────────────────┐              ┌─────────────────────────────────┐
  │ Route 53 (failover: PRIMARY)    │              │ Route 53 (failover: SECONDARY)  │
  │   ▼                             │              │   ▼                             │
  │ ALB ─► ASG desired=6            │              │ ALB (optional) ─► ASG desired=0 │
  │            │                    │              │                  (AMI, LT ready)│
  │            ▼                    │  async,      │                                 │
  │ Aurora primary cluster ─────────┼─storage-─────┼─► Aurora secondary (read-only)  │
  │                                 │  level       │    or headless secondary        │
  │ S3 ─────────────────────────────┼─ CRR ────────┼─► S3                            │
  └─────────────────────────────────┘              └─────────────────────────────────┘
  Disaster: scale ASG 0→6, fail over Aurora global DB, health check flips DNS.
```

#### 2.7.3 Warm Standby

- **What runs in the DR Region:** a **scaled-down but fully functional** copy of production (all tiers running, minimum capacity). It can **serve traffic immediately**, at reduced capacity.
- **Recovery:** Shift traffic and **scale up** to full production capacity (Auto Scaling, larger DB instances).
- **Difference from Pilot Light (classic exam test):** Pilot light **cannot process requests** without first deploying/starting compute; warm standby **can**, just not at full load.
- **Bonus:** You can continuously test DR by sending a small share of real or synthetic traffic (weighted routing) to it.
- **RPO:** seconds. **RTO:** minutes.

```text
   PRIMARY REGION (100%)                            DR REGION (scaled down, live)
  ┌─────────────────────────────────┐              ┌─────────────────────────────────┐
  │ ALB ─► ASG desired=12           │              │ ALB ─► ASG desired=2 (min)      │
  │          │                      │              │          │                      │
  │          ▼                      │              │          ▼                      │
  │ Aurora writer (r6g.4xl) ────────┼── global ────┼─► Aurora reader (r6g.large)     │
  │ DynamoDB global table ◄─────────┼── replica ───┼─► DynamoDB global table replica │
  │ ElastiCache primary ────────────┼─ Global DS ──┼─► ElastiCache secondary         │
  └─────────────────────────────────┘              └─────────────────────────────────┘
  Route 53 failover (or weighted 100/0) + health checks.  On disaster: route to DR,
  fail over DB, scale ASG 2→12 and resize DB.
```

#### 2.7.4 Multi-site active/active (and hot standby)

- **Active/active:** Workload runs at **full capacity in ≥2 Regions** and serves traffic from all of them (Route 53 latency/geolocation/weighted routing, or Global Accelerator). Losing a Region = remove it from routing.
- **Hot standby (active/passive):** Full capacity in both, but only one serves traffic; failover is just a traffic switch.
- **Data:** Requires multi-writer or write-partitioned data: **DynamoDB global tables** (MREC: last writer wins; MRSC: RPO zero), Aurora Global Database with **write forwarding** (writes still committed in one primary Region), or application-level partitioning ("each user's home Region").
- **RTO:** near zero (seconds to the time it takes routing to react). **RPO:** near zero for infrastructure failures, **but not zero for data corruption**: a bad write replicates everywhere in about a second. You still need backups/PITR.
- **Cost:** highest (≈2× or more), plus engineering for conflict handling, global consistency and testing.

```text
                         Route 53 latency/geo records + health checks
                         (or Global Accelerator: 2 static anycast IPs)
                    ┌──────────────────────┴──────────────────────┐
                    ▼                                             ▼
   REGION A (active, 100% capacity)               REGION B (active, 100% capacity)
  ┌────────────────────────────────┐             ┌────────────────────────────────┐
  │ CloudFront ─► ALB ─► ECS/EKS   │             │ CloudFront ─► ALB ─► ECS/EKS   │
  │                  │             │             │                  │             │
  │ DynamoDB global table ◄────────┼─multi-active┼────────► DynamoDB global table │
  │ S3 (bi-directional CRR) ◄──────┼─────────────┼────────► S3 (MRAP in front)    │
  │ EventBridge global endpoint    │             │                                │
  └────────────────────────────────┘             └────────────────────────────────┘
  Region failure: health checks remove A from DNS / GA; B absorbs all traffic
  (must be pre-scaled or able to scale fast; static stability).
```

#### 2.7.5 Services used per strategy

| Layer | Backup & Restore | Pilot Light | Warm Standby | Multi-site |
|---|---|---|---|---|
| Compute | AMIs copied cross-Region, IaC | AMIs + launch templates, ASG at 0, or IaC deploy on demand | ASG at min size, ECS/EKS small, Lambda deployed | Full ASG/ECS/EKS/Lambda in each Region |
| Relational DB | Cross-Region snapshot copy, RDS automated backup replication, AWS Backup copy | RDS cross-Region read replica or Aurora Global DB (possibly headless) | Aurora Global DB with smaller instances, RDS cross-Region replica | Aurora Global DB (write forwarding) or app partitioning |
| NoSQL | DynamoDB backups copied via AWS Backup | DynamoDB global table replica | DynamoDB global table | DynamoDB global tables (MREC/MRSC) |
| Object | S3 CRR or AWS Backup for S3 | S3 CRR (+RTC) | S3 CRR (+RTC) | S3 bi-directional CRR + Multi-Region Access Points |
| Cache | Rebuild on demand | Rebuild or small Global Datastore secondary | ElastiCache Global Datastore | Global Datastore (one writer) or per-Region caches |
| Traffic | Route 53 record change (manual or failover record) | Route 53 failover + health checks; ARC routing control | Route 53 failover/weighted; ARC; Global Accelerator | Route 53 latency/geo, Global Accelerator, CloudFront |
| Orchestration | CloudFormation (StackSets), Systems Manager Automation | + ARC Region switch, Step Functions runbooks | + ARC Region switch | ARC routing controls, Region switch |
| Lift-and-shift servers | AWS Backup / DRS | **AWS Elastic Disaster Recovery** | DRS (launch and keep running) | n/a |

### 2.8 DR building blocks by service

#### Amazon S3

- **Cross-Region Replication (CRR) / Same-Region Replication (SRR):** asynchronous, **requires versioning on both buckets**, IAM role for S3. Replicates **new objects only** after the rule is created; use **S3 Batch Replication** for existing objects, previously failed objects, or objects already replicated elsewhere.
- **Delete markers** are *not* replicated unless you enable delete-marker replication (V2 rules); **deletes of specific versions are never replicated** (protects against malicious deletes).
- **Replica modification sync** and **two-way (bi-directional) replication** for active/active.
- Can change storage class and ownership in destination (cross-account: "owner override").
- SSE-KMS objects need explicit opt-in and KMS permissions; replication counts against KMS request quotas.
- **S3 Replication Time Control (RTC):** replicates most objects in seconds and **99.9% of objects within 15 minutes**, backed by an SLA. Enables replication metrics and `OperationMissedThreshold` / `OperationReplicatedAfterThreshold` events. SLA does not apply when you exceed the default **1 Gbps** replication transfer quota (soft, can be raised). Exam signal: "predictable / compliance-driven replication time" → RTC.
- **Multi-Region Access Points (MRAP):** single global endpoint that routes requests to the closest bucket over the AWS network. **Failover controls**: set buckets to **active/passive** and shift traffic between Regions (failover is between two Regions at a time). Pair with bi-directional CRR so data is in sync. Requests need SigV4A signing.
- **S3 Object Lock** (WORM; governance vs compliance mode) for immutable copies.

#### Amazon EBS & EC2

- **EBS snapshots** are incremental, stored in S3 (Regional). **Copy snapshots cross-Region/cross-account** (re-encrypt with a destination-Region KMS key). Encrypted snapshot sharing requires sharing the customer-managed KMS key (not possible with the AWS-managed `aws/ebs` key).
- **Amazon Data Lifecycle Manager (DLM)** automates snapshot/AMI creation, retention and cross-Region copy.
- **AMI copy** cross-Region (AMIs are Regional). Launch templates referencing AMI IDs must be Region-specific; use SSM Parameter Store public/custom parameters or IaC mappings.
- **Fast Snapshot Restore (FSR)** removes the lazy-load first-touch latency on restored volumes (costly; enable only for DR-critical volumes).
- **EBS Snapshots Archive** for long retention at lower cost (restore takes up to 72 h, so **not** for DR with tight RTO).
- **Recycle Bin** for EBS snapshots and AMIs: retention rules recover accidental deletes (and can be locked).
- **EC2 auto recovery** (CloudWatch alarm action or default simplified recovery) moves an instance to new hardware on system-status-check failure (same AZ, keeps IP/IDs).

#### AWS Backup

- Central, policy-based backups across EC2, EBS, EFS, FSx, RDS, Aurora, DynamoDB, DocumentDB, Neptune, S3, Storage Gateway, VMware, SAP HANA on EC2, Redshift, Timestream and more (check the feature availability table per resource).
- **Backup plans** (schedule, lifecycle to cold storage, retention) + **resource assignments** (tags).
- **Cross-Region copy** and **cross-account copy** (cross-account needs AWS Organizations) defined as copy actions in the plan.
- **Organizations backup policies** push plans to all accounts.
- **Continuous backup / PITR** for RDS, Aurora, S3 (up to 35 days).
- **AWS Backup Vault Lock**:
  - **Governance mode:** users with sufficient IAM permissions can remove the lock.
  - **Compliance mode:** after the **grace time (minimum 3 days / 72 hours)** the lock and vault become immutable. **No one, not root and not AWS, can delete recovery points before retention ends** or change the lock. Assessed by Cohasset for SEC 17a-4, CFTC, FINRA.
  - Min/max retention settings reject backup/copy jobs outside the range.
- **Logically air-gapped vault** (verified on the AWS Backup guide):
  - Specialised vault that is **always locked in compliance mode**; encrypted with an **AWS-owned key by default or optionally a customer-managed KMS key**.
  - Backups are stored in an **AWS Backup service-owned account**.
  - Can be **shared via AWS RAM** with other accounts (including other organizations) so a separate **recovery account** can restore directly. That reduces RTO because nothing needs copying back first.
  - Integrates with **Multi-party approval (MPA)** so backups can be recovered even if the owning account is compromised or inaccessible (and during the post-closure period if the account is closed).
  - Minimum retention is **7 days**. Not available in every Region. Only resource types that support cross-account/cross-Region copy can be copied in.
- **Restore testing** automates periodic test restores and validation (proves RTO).
- **AWS Backup Audit Manager** reports compliance with controls (e.g., "resources are protected by a vault lock", "cross-Region copy exists").
- **Legal holds** prevent deletion regardless of retention.

#### Amazon RDS

- **Multi-AZ DB instance:** synchronous standby in another AZ, automatic failover (typically 60–120 s), standby **not readable**.
- **Multi-AZ DB cluster** (MySQL/PostgreSQL): one writer + two readable standbys in 3 AZs, faster failover (typically under 35 s).
- **Cross-Region read replica** (MySQL, MariaDB, PostgreSQL, Oracle, SQL Server with limitations): asynchronous; **promote** to standalone in DR (manual, breaks replication; RPO = replica lag). Pilot light/warm standby building block.
- **Cross-Region automated backup replication:** replicates snapshots *and transaction logs* to a destination Region, enabling **PITR in the DR Region** (supported for Db2, MariaDB, MySQL, Oracle, PostgreSQL, SQL Server Multi-AZ DB instance deployments; **not** for Multi-AZ DB clusters; default quota 20 per account). Backup & Restore with better RPO than daily snapshot copies.
- **Manual snapshot cross-Region copy** (re-encrypt with destination KMS key).

#### Amazon Aurora

- Storage is replicated **6 ways across 3 AZs** in a Region; up to 15 Aurora Replicas; failover to a replica typically ~30 s (faster with RDS Proxy or the AWS Advanced JDBC Wrapper).
- **Aurora Global Database:**
  - One primary Region + **up to 10 secondary Regions** (raised from 5 in 2025), each secondary up to 16 read-only instances.
  - **Storage-level asynchronous replication** that does not use the DB engine's compute. Typical lag under 1 second, so **RPO is typically measured in seconds** (≈1 s typical). RTO in the order of **minutes; often under a minute** with automation.
  - **Switchover** (formerly *managed planned failover*): for **planned** operations (Region rotation, follow-the-sun, failing back after a DR event). Waits for full sync, **RPO = 0**. On recent engine versions, read/write recovery is typically **under 30 s**. Requires healthy clusters and compatible engine versions.
  - **Failover** (`failover-global-cluster --allow-data-loss`): for **unplanned** outages. Doesn't wait for sync, **RPO = replication lag (seconds)**. **Managed failover** automatically re-adds the old primary Region as a secondary when it recovers and tries to snapshot the old volume (`rds:unplanned-global-failover-...`) so you can recover unreplicated writes. **Manual failover** = detach the secondary (promote standalone) and rebuild the global DB.
  - **Global writer endpoint** keeps the same DNS name after switchover/failover, so no app config change (keep DNS TTL low, ~5 s).
  - **Write forwarding**: apps in secondary Regions can send writes, which are forwarded to the primary. Simplifies "read local, write global".
  - **Headless secondary cluster**: no instances, just replicated storage. Cheapest pilot light; must add an instance before switchover/failover.
  - **`rds.global_db_rpo`** (Aurora PostgreSQL): enforce an RPO ceiling (20 s minimum). Primary commits **block** if all secondaries lag beyond it.
- **Aurora Backtrack** (MySQL): rewind the cluster in place to undo logical errors (not DR).

#### Amazon DynamoDB

- Regional service, data replicated across 3 AZs; **PITR** (continuous backups, restore to any second in the retention window, default 35 days, configurable 1–35) and on-demand backups.
- **Global tables (version 2019.11.21):** multi-Region, **multi-active** (any replica takes reads and writes). Also supports **multi-account** global tables (MREC only).
  - **MREC (multi-Region eventual consistency, default):** async replication typically within a second; **last-writer-wins** conflict resolution; RPO = replication delay (usually a few seconds); transactions atomic only in the Region where invoked.
  - **MRSC (multi-Region strong consistency):** writes **synchronously** replicated to at least one other Region before returning; strongly consistent reads anywhere; **RPO = 0**. Must be **exactly three Regions** (3 replicas, or 2 replicas + 1 witness). Must start from an empty table. Higher write latency. No TTL, no LSIs, **no transactions**. Same-account only. Conflicting concurrent writes get `ReplicatedWriteConflictException` (retryable).
  - **SLA 99.999%** for global tables vs 99.99% single-Region.
  - Consistency mode cannot be changed after creation.
  - FIS can pause replication to simulate Region isolation.

#### Amazon ElastiCache (Valkey / Redis OSS)

- Multi-AZ with automatic failover within a Region.
- **Global Datastore:** one **primary (read/write) cluster** + up to **two secondary (read-only) clusters in other Regions**; async replication. Same node type, shard count and engine version required. **No automatic cross-Region failover**: you **promote** a secondary manually (or via automation). Same account only. Node-based clusters only (not ElastiCache Serverless).
- Memcached has no replication; treat as disposable.

#### Amazon Route 53

- Data plane designed for **100% availability SLA** (DNS query answering).
- **Health checks:** endpoint (HTTP/HTTPS/TCP, optional string match in the first 5,120 bytes), **calculated** (combine up to 256 child checks with AND/OR/x-of-y), or **CloudWatch alarm**-based. Request interval **30 s (standard) or 10 s (fast, extra cost)**, configurable failure threshold. Health checkers sit **outside VPCs and cannot reach private IPs**. For private resources, use a **CloudWatch-alarm-based health check** (alarm on a metric emitted from inside the VPC).
- **Failover routing** (active/passive): primary + secondary records; requires a health check on the primary (alias to ELB can use **Evaluate Target Health**).
- Other policies for DR/HA: **weighted** (pilot traffic to warm standby, 0 weight to drain), **latency** and **geolocation/geoproximity** (active/active), **multivalue** (up to 8 healthy records).
- **DNS TTL** affects RTO (clients cache answers). Alias records to AWS resources use the target's TTL (60 s for ELB).
- **Don't** depend on changing records via the Route 53 API during an incident (control plane in us-east-1). Use health-check-driven failover or ARC routing controls.

#### Amazon Application Recovery Controller (ARC), formerly Route 53 ARC

The service was renamed **Amazon Application Recovery Controller (ARC)**; the exam may say "Route 53 Application Recovery Controller".

| Capability | Scope | What it does |
|---|---|---|
| **Zonal shift** | Multi-AZ | **Manually** shift traffic for a supported resource (ALB, NLB, EC2 Auto Scaling groups, EKS and others; check the supported-resource list) away from an impaired AZ. Temporary, with an extendable expiry of **up to 3 days**. Great for a bad zonal deployment or a gray failure your health checks don't catch |
| **Zonal autoshift** | Multi-AZ | **AWS shifts traffic on your behalf** when AWS telemetry detects an AZ impairment. **Practice runs are required**: weekly, ~30 min shift of one resource away from an AZ, with outcome alarms. **Pre-scale** so the remaining AZs can carry the load (autoshift doesn't wait for scaling) |
| **Routing control** | Multi-Region | Simple on/off switches tied to Route 53 health checks; flipped via a **highly available cluster with five Regional endpoints** (data plane). **Safety rules** (assertion and gating rules) prevent e.g. turning both Regions off. Best for **human-in-the-loop, reliable Regional failover** |
| **Readiness check** | Multi-Region | Continuously audits that the replica (DR) cell matches production: **quotas, capacity, configuration, routing policies**. Explicitly **not** for use in the failover critical path |
| **Region switch** | Multi-Region | Managed **plans** of workflows/steps/execution blocks (e.g., scale EC2 ASG, fail over Aurora Global DB, update Route 53 health checks/routing controls, custom actions) for **active/passive (failover/failback) and active/active (shift-away/return)**. Cross-account, manual or CloudWatch-alarm triggered, dashboards, and a **data plane in each Region** so execution doesn't depend on the Region being deactivated |

#### AWS Global Accelerator

- **Two static anycast IPv4 addresses** (four with dual-stack) at AWS edge; traffic rides the AWS backbone to Regional endpoints (ALB, NLB, EC2, EIP).
- **Continuous health checks** with near-instant failover for **new connections** (no DNS caching problem).
- **Traffic dials** (0–100% per endpoint group/Region) and **endpoint weights** (0–255, default 128) for active/passive, gradual failback, blue/green.
- Works for **TCP/UDP** (non-HTTP) workloads. Exam signal: "static IPs allow-listed by partners", "fast failover not dependent on DNS TTL", "UDP gaming/VoIP".

#### Amazon CloudFront origin failover

- **Origin group** = primary + secondary origin. Fails over on configured status codes (400, 403, 404, 416, 429, 500, 502, 503, 504) or connection failure/timeouts.
- **Only for `GET`, `HEAD`, `OPTIONS`.** No failover for `POST`/`PUT` (so not a write-path DR mechanism).
- Defaults: 3 connection attempts × 10 s connection timeout = **up to 30 s before failover**; tune to 1 attempt / 1–10 s for faster failover.
- Typical pattern: S3 bucket in Region A (primary) + CRR replica in Region B (secondary).

#### Amazon EventBridge global endpoints

- Improves Regional fault tolerance for **custom events** at no additional cost (event replication adds cost).
- Associate a **Route 53 health check** (typically driven by a CloudWatch alarm on EventBridge metrics). When unhealthy, events route to an **event bus with the same name in the secondary Region**.
- **Event replication** (recommended) sends events to both Regions asynchronously and is required for automatic failback.
- AWS cites **RTO and RPO of 360 seconds (max 420 s)** following its alarm guidance.
- Producers call `PutEvents` with `EndpointId` (SDK needs AWS CRT, SigV4A).

#### Secrets, keys, images, config

- **Secrets Manager replica secrets:** replicate a secret to other Regions; rotation in the primary propagates; promote a replica to standalone during DR. Replicas encrypt with a KMS key in their Region.
- **KMS multi-Region keys:** same **key ID and key material** in multiple Regions (primary + replicas). Encrypt in one Region, decrypt in another without cross-Region calls. Each key has **independent key policies, grants, aliases**. **Cannot convert** an existing single-Region key. AWS managed keys are always single-Region. Many services (e.g., S3 CRR) still re-encrypt under the destination key.
- **ECR replication:** cross-Region and/or cross-account replication rules (registry level, filter by repository prefix); pull-through cache for upstream registries.
- **SSM Parameter Store:** no native replication; replicate with IaC, pipelines or EventBridge + Lambda.
- **AWS CloudFormation StackSets:** deploy the same stacks to many accounts and Regions from one template (service-managed permissions with Organizations, automatic deployment to new accounts). Use to **pre-provision the DR Region** (VPCs, IAM roles, KMS replica keys, security baselines, pilot-light resources) and keep it from drifting.
- **IAM** is global: roles and policies exist in every Region. Still test that apps in the DR Region assume the right roles and that SCPs don't deny the DR Region (common gotcha with Region-deny SCPs).

#### AWS Elastic Disaster Recovery (DRS)

Successor to CloudEndure Disaster Recovery.

- **Continuous block-level replication** of source servers (agent-based) to a **low-cost staging area subnet** in your AWS account in the target Region: lightweight replication servers + cheap EBS volumes; no full-size compute running.
- **Sources:** physical servers, VMware vSphere, Microsoft Hyper-V, other clouds, and **EC2 (cross-Region or cross-AZ)**.
- **RPO of seconds, RTO of minutes** (AWS's stated figures).
- **Point-in-time recovery**: launch from an earlier point (e.g., before ransomware encryption).
- Automatically **converts servers to boot natively on EC2** at launch; launch settings/templates define instance type, subnet, etc.
- **Non-disruptive drills** at any time (replication continues).
- **Failback** to on-premises (Failback Client) or back to the original Region (for EC2 sources) when ready.
- **Pricing model:** per replicating source server-hour plus the staging resources; full-size compute only when you launch drills/recovery.
- Exam signals: "hundreds of on-prem servers, mixed OS/apps, need DR in AWS with RPO in seconds and minimal cost" → **DRS**. "Migrate (one-time)" → **AWS Transform MGN** (formerly Application Migration Service), same underlying replication technology.

### 2.9 Making the DR Region actually work

| Readiness item | Why it fails in real life | Fix |
|---|---|---|
| **Service quotas** | DR account/Region has default vCPU, EIP, ENI, Lambda concurrency limits | Raise in advance; Service Quotas templates; ARC readiness checks flag mismatches |
| **Capacity** | Instance type unavailable in the DR AZs during a large event (everyone fails over) | **On-Demand Capacity Reservations** (zonal, no commitment, billed whether used or not; can combine with Savings Plans/Regional RIs for discount), flexible instance types in ASG/Fleet, Spot only for non-critical |
| **AMIs, images, artifacts** | AMI only exists in primary; container image only in primary ECR | AMI copy pipeline, ECR replication, artifact buckets replicated |
| **Secrets & keys** | Can't decrypt snapshots or connect to DB in DR | KMS multi-Region keys or re-encrypt on copy; Secrets Manager replicas |
| **Config drift** | DR stack 6 months older than prod | Same IaC pipeline deploys both Regions; StackSets; drift detection; Resilience Hub drift |
| **DNS / clients** | Long TTLs, hard-coded endpoints, client DNS caching | Low TTL on failover records, global endpoints (Aurora global writer endpoint), Global Accelerator |
| **Dependencies** | Third-party SaaS, on-prem AD, or a shared service exists only in primary | Map dependencies (Resilience Hub, X-Ray, service maps); replicate AD (AWS Managed Microsoft AD multi-Region replication) |
| **People & runbooks** | Nobody knows the steps, credentials expired | Runbooks as SSM Automation documents/Region switch plans; break-glass access; quarterly game days |
| **SCPs / guardrails** | Region-deny SCP blocks the DR Region | Include DR Region in allowed list; test with drills |

### 2.10 Testing resilience

- **DR drills / game days:** scheduled, scoped exercises that fail over for real (or to an isolated copy) and measure actual RTO/RPO against targets. Include failback.
- **Chaos engineering:** form a hypothesis about steady state → inject a real-world fault → observe → learn and fix. Start in pre-prod, move to production with guardrails.
- **AWS Fault Injection Service (FIS):** managed chaos-engineering service.
  - **Experiment template** = **actions** (e.g., stop/terminate EC2, inject CPU/memory/network latency via SSM, throttle API calls, fail over RDS/Aurora, disrupt network connectivity in subnets, pause EBS I/O, pause DynamoDB global table replication, ECS/EKS task and pod faults) + **targets** (by ARN, tags, filters) + **stop conditions** (**CloudWatch alarms** that halt the experiment).
  - **Scenario library** includes pre-built scenarios such as **AZ Availability: Power Interruption** and **Cross-Region: Connectivity**.
  - **Multi-account experiments** target resources in other accounts.
  - Priced per action-minute (based on target accounts).
- **AWS Resilience Hub:**
  - Define an **application** from CloudFormation stacks, Terraform state, AppRegistry/myApplications, resource groups or EKS clusters.
  - Attach a **resiliency policy** with **RTO/RPO targets per disruption type: Application, Cloud Infrastructure, Cloud Infrastructure AZ disruption, Cloud Infrastructure Region incident** (with suggested tiers).
  - Run an **assessment**: estimated workload RTO/RPO, compliance status (**Policy met / Policy breached**), **resiliency score**, **drift detection** (policy and resource drift).
  - **Recommendations**: resiliency (architecture), and operational (CloudWatch **alarms**, **SOPs** as SSM documents, **FIS experiments**) that you can deploy via CloudFormation.
  - Integrates with CodePipeline to assess on every release.
- **CloudWatch Synthetics canaries** test user journeys continuously from multiple Regions; **CloudWatch Application Signals/ServiceLens** for SLOs.

### 2.11 Backup strategy vs DR strategy (and ransomware)

| Question | Backup strategy | DR strategy |
|---|---|---|
| Protects against | Logical corruption, accidental/malicious deletion, ransomware, compliance retention | Loss of a site/AZ/Region, long outages |
| Mechanism | Point-in-time, versioned, **immutable**, **isolated** copies | Replication + standby infrastructure + traffic shifting |
| RPO characteristics | = backup interval (or seconds with PITR) | Seconds (async replication) to zero (sync) |
| Key AWS tools | AWS Backup (+Vault Lock, logically air-gapped vault, restore testing), S3 Versioning + Object Lock, PITR | Aurora Global DB, DynamoDB global tables, S3 CRR, DRS, Route 53/ARC/Global Accelerator |
| Failure if missing | Corruption replicated to every Region; nothing clean to restore | Backups exist but take days to rebuild infra |

**Ransomware-resilient backup architecture (Professional-level answer):**

```text
  Workload accounts (prod)                     Central backup / recovery accounts
 ┌─────────────────────────────┐   copy job   ┌─────────────────────────────────────────┐
 │ AWS Backup plan (Org policy)│──cross-acct─►│ Backup account: vault + Vault Lock       │
 │ Local vault (short retention)│  +cross-Reg │ (compliance mode, grace ≥72h)            │
 └─────────────────────────────┘              │        │                                 │
                                              │        ▼ copy                            │
                                              │ Logically air-gapped vault (compliance  │
                                              │ lock, AWS Backup service-owned storage)  │
                                              │        │  shared via AWS RAM / MPA       │
                                              └────────┼─────────────────────────────────┘
                                                       ▼
                                              ┌────────────────────────────┐
                                              │ Isolated RECOVERY account  │
                                              │ (separate creds, SCPs,     │
                                              │  restore testing here)     │
                                              └────────────────────────────┘
  + SCPs deny backup:DeleteRecoveryPoint, vault-policy changes; MFA/break-glass; GuardDuty
    Malware Protection for AWS Backup / restore scans; Audit Manager controls.
```

Key points: **separate accounts** (blast radius of compromised credentials), **separate Regions**, **immutability** (compliance-mode lock, Object Lock), **separate identity/credentials** for the recovery account, **regular restore tests**, and **point-in-time recovery** to a pre-infection state (DRS PIT snapshots, PITR).

---

## 3. Architecture patterns

### Pattern A: Statically stable Multi-AZ web tier (the default HA answer)

```text
                       Route 53 (alias → ALB, Evaluate Target Health)
                                     │
                         ┌───────────┴───────────┐
                         │  ALB (3 AZs, cross-   │
                         │  zone LB on)          │◄── ARC zonal shift / autoshift
                         └───┬────────┬────────┬─┘
                  AZ-a       │  AZ-b  │  AZ-c  │
              ┌──────────┐ ┌──────────┐ ┌──────────┐
              │ ASG 50%  │ │ ASG 50%  │ │ ASG 50%  │   = 150% of peak; lose 1 AZ → 100%
              └────┬─────┘ └────┬─────┘ └────┬─────┘
                   └────────────┼────────────┘
                     Aurora writer (AZ-a) + replicas (AZ-b, AZ-c)
                     ElastiCache Multi-AZ, SQS/DynamoDB (Regional)
```
- **When:** Every production workload. Survives an AZ loss without scaling actions (static stability) and supports zonal autoshift.
- **Trade-off:** ~50% extra compute. With 2 AZs, static stability needs 2 × 100% = 200% of peak. With 3 AZs, aggressive scaling instead of pre-scaling is cheaper but not statically stable.

### Pattern B: Pilot light with Aurora Global Database + ARC Region switch

```text
 us-east-1 (primary)                          us-west-2 (DR)
 ┌───────────────────────────┐               ┌───────────────────────────┐
 │ ALB → ASG (12)            │               │ ALB → ASG (0)  [IaC-built]│
 │ Aurora global primary ────┼──< 1 s lag ──►│ Aurora headless secondary │
 │ S3 ───────────────────────┼── CRR + RTC ─►│ S3                        │
 │ Secrets Mgr primary ──────┼── replica ───►│ Secrets Mgr replica       │
 │ KMS MRK primary ──────────┼── replica ───►│ KMS MRK replica           │
 │ ECR ──────────────────────┼── replication►│ ECR                       │
 └───────────────────────────┘               └───────────────────────────┘
      ARC Region switch plan (executes from DR Region's data plane):
      1) add Aurora instance  2) failover-global-cluster  3) scale ASG 0→12
      4) flip routing control / Route 53 health check  5) post-checks
```
- **When:** RTO ~30–60 min, RPO seconds, cost-sensitive.
- **Trade-off:** RTO includes instance provisioning; capacity in DR Region not guaranteed unless reserved.

### Pattern C: Warm standby with weighted canary traffic

- Route 53 **weighted** records: primary 95, DR 5 (or synthetic canaries only). This keeps proving that DR works.
- On disaster: set primary weight 0 (or let health checks fail it), scale DR.
- **When:** RTO in minutes, you need *confidence* that DR works, and you can afford an always-on small footprint.

### Pattern D: Active/active multi-Region with write partitioning

```text
   Users ─► Route 53 latency records (health checks) ─► nearest Region
   ┌───────────────────────────────┐            ┌───────────────────────────────┐
   │ Region A                      │            │ Region B                      │
   │ API GW → Lambda               │            │ API GW → Lambda               │
   │ DynamoDB global table (MREC) ◄┼────────────┼► DynamoDB global table (MREC) │
   │ Users homed in A write here   │            │ Users homed in B write here   │
   └───────────────────────────────┘            └───────────────────────────────┘
   Conflict avoidance: each item has a "home Region"; LWW only as a safety net.
   Need RPO 0 + strong reads? → MRSC (3 Regions, higher write latency, no transactions).
```

### Pattern E: Reliable Regional failover with ARC routing controls

```text
     ARC cluster (5 Regional endpoints)  ──► routing control "East-ON" / "West-ON"
                │ (safety rule: at least one ON)
                ▼
     Route 53 health checks bound to routing controls
                ▼
     Failover records: app.example.com → East ALB (primary) / West ALB (secondary)
     Readiness checks continuously compare quotas/capacity/config of both cells.
```
- **When:** Regulated, tier-0 apps that want **human-approved**, deterministic failover (avoid flapping and split-brain), with no control-plane dependency during the event.

### Pattern F: On-premises to AWS DR with Elastic Disaster Recovery

```text
  On-prem DC (VMware / Hyper-V / physical)          AWS Region (recovery)
 ┌───────────────────────────────┐   TLS, block-   ┌────────────────────────────────────┐
 │ App servers + DRS agent ──────┼─level, continu-─►│ Staging subnet: small replication  │
 │ DB servers  + DRS agent       │  ous (VPN/DX/   │ servers + low-cost EBS + PIT points │
 └───────────────────────────────┘  internet)      │                                    │
                                                   │ Drill/Recovery: launch converted   │
                                                   │ EC2 in recovery subnet (minutes)   │
                                                   │ Failback: replicate back to on-prem│
                                                   └────────────────────────────────────┘
```
- **When:** Many heterogeneous servers, no appetite to re-architect, need RPO seconds/RTO minutes at low standby cost. It also protects against ransomware via point-in-time launch.

### Pattern G: Cell-based architecture with thin router

```text
          Clients ─► Cell router (Route 53 / API GW + DynamoDB mapping, very simple)
                      │ tenant → cell
       ┌──────────────┼──────────────┬──────────────┐
       ▼              ▼              ▼              ▼
   Cell 1         Cell 2         Cell 3         Cell N     each = full stack
   (ALB, ECS,     ...            ...            ...        (own DB, own queue),
    DynamoDB)                                              Multi-AZ, max size tested
   Deploy wave: Cell 1 (canary) → bake → 2–3 → rest
```
- **When:** Large multi-tenant SaaS that needs to cap the blast radius of bad deploys and poison-pill tenants.

### Pattern H: Ransomware-resilient backups (see 2.11)

Central backup account + Vault Lock (compliance) + logically air-gapped vault shared to an isolated recovery account + GuardDuty Malware Protection for AWS Backup scans of recovery points + restore testing.

---

## 4. Decision tables

### 4.1 RTO/RPO/budget → DR strategy

| Requirement (indicative) | Strategy | Core services | Relative cost |
|---|---|---|---|
| RPO hours, RTO hours–1 day, lowest cost | **Backup & Restore** | AWS Backup cross-Region/cross-account copy, snapshots/AMI copy, S3 CRR, IaC | $ |
| RPO minutes, RTO hours, lowest cost, relational | Backup & Restore **+ RDS automated backup replication / PITR** | RDS cross-Region automated backups | $ |
| RPO seconds–minutes, RTO tens of minutes | **Pilot Light** | Aurora Global DB (headless OK), DynamoDB global table, S3 CRR(+RTC), AMIs, ASG at 0 / IaC, DRS for servers | $$ |
| RPO seconds, RTO minutes, must serve some traffic immediately | **Warm Standby** | All tiers running at min size, Aurora Global DB, Global Datastore, Route 53/ARC | $$$ |
| RPO ≈ 0 (infra failure), RTO ≈ 0, global users | **Multi-site active/active** | DynamoDB global tables (MRSC for RPO 0), Aurora write forwarding, Global Accelerator, Route 53 latency, MRAP | $$$$ |
| On-prem/heterogeneous servers, RPO seconds, RTO minutes, cheap standby | **DRS** (pilot-light-like) | AWS Elastic Disaster Recovery | $$ |
| Protect against corruption/ransomware | **Backups (always)** | Vault Lock compliance, logically air-gapped vault, Object Lock, PITR, separate account | + |

### 4.2 Cross-Region database options

| Option | Replication | Typical RPO | Failover | Writes in DR before failover | Notes |
|---|---|---|---|---|---|
| RDS snapshot copy | Scheduled | Hours | Restore (long) | No | Cheapest |
| RDS automated backup replication | Snapshots + txn logs | Minutes | PITR restore in DR | No | Not for Multi-AZ DB clusters |
| RDS cross-Region read replica | Async (engine) | Seconds–minutes | Promote (manual) | No | Replica lag under load |
| Aurora Global Database | Async (storage) | ~1 s typical | Switchover (RPO 0) / Failover (RPO = lag) | Write forwarding | Up to 10 secondaries; global writer endpoint |
| DynamoDB global tables MREC | Async | ~1 s | None needed (multi-active) | Yes | LWW conflicts |
| DynamoDB global tables MRSC | Sync to ≥1 other Region | **0** | None needed | Yes | Exactly 3 Regions; no transactions/TTL/LSI |
| ElastiCache Global Datastore | Async | Seconds | Manual promote | No (secondaries read-only) | ≤2 secondary Regions |
| DocumentDB global clusters | Async (storage) | Seconds | Switchover/failover | No | Similar model to Aurora |

### 4.3 Traffic-shifting options

| Need | Best fit | Why not the others |
|---|---|---|
| Simple active/passive DNS failover | **Route 53 failover + health checks** | Cheapest; subject to DNS TTL/client caching |
| Failover with static IPs, TCP/UDP, fast, no DNS caching | **Global Accelerator** | Route 53 depends on TTL; CloudFront is HTTP(S) only |
| Read-only static content, origin outage | **CloudFront origin group** | Only GET/HEAD/OPTIONS fail over |
| Deterministic, operator-controlled Regional failover with safety rules | **ARC routing controls** | Route 53 health checks alone can flap; API record edits depend on control plane |
| Orchestrated multi-step Regional recovery (DB + compute + DNS) across accounts | **ARC Region switch** | Hand-written Step Functions/Lambda scripts = more ops, less tested |
| Move traffic off one bad AZ | **ARC zonal shift / autoshift** | Route 53 is Region-level; deregistering targets manually is slow |
| Single global S3 endpoint with Regional failover | **S3 Multi-Region Access Points (failover controls)** | Route 53 CNAMEs to buckets don't work cleanly with S3 hostnames/auth |
| Event bus Regional failover | **EventBridge global endpoints** | Custom dual-publishing code is error-prone |

### 4.4 Backup vault protections

| Feature | Who can bypass | Use when |
|---|---|---|
| Vault access policy (deny delete) | Account admins can edit the policy | Baseline |
| Vault Lock **governance** | Principals with specific IAM permissions | Testing retention settings, internal governance |
| Vault Lock **compliance** (after ≥72 h grace) | **Nobody** (not root, not AWS) | Regulatory WORM, ransomware protection |
| **Logically air-gapped vault** | Nobody (compliance lock built in); restore via RAM share / MPA from another account | Ransomware, compromised account, fastest clean restore to a recovery account |
| S3 Object Lock compliance | Nobody until retention ends | S3 data WORM |
| Legal hold (Backup / S3) | Removable by authorised users | Litigation |

### 4.5 Pilot Light vs Warm Standby vs Hot Standby

| Aspect | Pilot Light | Warm Standby | Hot standby (active/passive) |
|---|---|---|---|
| Data tier in DR | Live, replicating | Live, replicating | Live, replicating |
| Compute in DR | Off / not deployed | Running at reduced size | Running at full size |
| Can serve traffic immediately | **No** | **Yes (reduced capacity)** | **Yes (full)** |
| Recovery action | Deploy/start + scale + promote DB + shift | Scale up + promote DB + shift | Promote DB + shift |
| Continuous DR testing with live traffic | Hard | Easy (weighted) | Easy |

---

## 5. Exam keyword → answer cheat list

| Stem says… | Lean towards |
|---|---|
| "Survive the failure of an AZ", "highly available" (no Region language) | Multi-AZ (ASG across AZs, RDS Multi-AZ, Aurora replicas), not multi-Region |
| "Region outage", "geographically separate", "entire Region unavailable" | Multi-Region DR strategy chosen by RTO/RPO |
| "Lowest cost" + RTO in hours | Backup & Restore with AWS Backup cross-Region copy + IaC |
| "RPO of seconds" + relational + cross-Region | Aurora Global Database |
| "RPO of zero" across Regions, NoSQL | DynamoDB global tables **MRSC** |
| "Multi-active writes in multiple Regions", "local read/write latency globally" | DynamoDB global tables (MREC) |
| "Minimal compute running in DR, core DB replicating" | Pilot Light |
| "Scaled-down fully functional copy", "can handle traffic immediately" | Warm Standby |
| "Zero downtime", "near-zero RTO", "users in both Regions served" | Multi-site active/active |
| "Planned Region rotation", "no data loss", "fail back after DR" | Aurora Global Database **switchover** |
| "Unplanned outage of primary Region" (Aurora) | Aurora Global Database **failover** (allow data loss) |
| "Hundreds of on-prem servers", "continuous replication", "RPO seconds, RTO minutes", "low-cost staging" | AWS Elastic Disaster Recovery |
| "One-time migration of servers" | AWS Transform MGN (formerly Application Migration Service), not DRS |
| "Objects replicated within 15 minutes with SLA" | S3 Replication Time Control |
| "Replicate existing objects" | S3 Batch Replication |
| "Single global endpoint for S3 with failover" | S3 Multi-Region Access Points + failover controls + bi-directional CRR |
| "Static IP addresses", "non-HTTP", "instant failover without DNS caching" | AWS Global Accelerator |
| "Failover must not rely on control plane", "safety rules", "manual but reliable Region failover" | ARC routing controls |
| "Orchestrate multi-step, cross-account Region failover with dashboards" | ARC Region switch |
| "Shift traffic away from an impaired AZ", "gray failure in one AZ" | ARC zonal shift / zonal autoshift |
| "Verify DR Region has same quotas/capacity/config" | ARC readiness checks |
| "Measure whether the application meets RTO/RPO targets", "resiliency score", "drift" | AWS Resilience Hub |
| "Inject faults", "chaos engineering", "stop experiment when alarm fires" | AWS Fault Injection Service |
| "Decrypt in DR Region without re-encrypting" | KMS multi-Region keys |
| "Secrets available in DR Region" | Secrets Manager replica secrets |
| "Container images in DR Region" | ECR cross-Region replication |
| "Deploy baseline to many accounts and Regions" | CloudFormation StackSets |
| "Guarantee EC2 capacity in DR AZ" | On-Demand Capacity Reservations |
| "Immutable backups no one can delete, including root" | AWS Backup Vault Lock **compliance mode** |
| "Recover backups even if production account is compromised", "share backups to recovery account" | Logically air-gapped vault (RAM share / MPA) |
| "Events must keep flowing if Region fails" | EventBridge global endpoints |
| "Cache cross-Region DR" | ElastiCache Global Datastore (manual promote) |
| "Static website stays up if origin bucket Region fails" | CloudFront origin group (S3 primary + CRR replica) |
| "Retry storms", "thundering herd" | Exponential backoff **with jitter**, retry quotas |
| "Duplicate processing on retries" | Idempotency keys / conditional writes |
| "One tenant's bad requests take down everyone" | Cell-based architecture / shuffle sharding |
| "Health check removes all instances when DB is slow" | Shallow LB health checks; deep checks elsewhere |
| "Private endpoint health for DNS failover" | Route 53 health check on a CloudWatch alarm |

---

## 6. Traps & distractors

1. **Multi-AZ RDS as DR.** Multi-AZ is HA within one Region. It doesn't protect against Region loss or logical corruption, and the standby isn't readable (Multi-AZ instance deployment).
2. **Read replica = backup.** Replicas copy deletes and corruption. You still need snapshots/PITR.
3. **Active/active "RPO zero".** Async replication (Aurora Global, DynamoDB MREC, S3 CRR) has a non-zero RPO, and *no* replication protects against corruption. Only DynamoDB MRSC gives RPO 0 for a Region failure.
4. **Pilot light described as "serves traffic at reduced capacity".** That's warm standby. Pilot light must deploy/start compute first.
5. **Choosing multi-site when the budget is "minimal" and RTO is hours.** Over-engineering is wrong on SAP. Pick the cheapest strategy that meets the numbers.
6. **CloudFront origin failover for write APIs.** It fails over only GET/HEAD/OPTIONS.
7. **Route 53 health checks against private IPs.** They can't reach them. Use CloudWatch-alarm health checks.
8. **Lambda that rewrites DNS records during the outage.** That's a control-plane dependency (and a script nobody tested). Prefer health-check failover or ARC routing controls.
9. **Relying on Auto Scaling during an AZ event.** That isn't statically stable, and capacity may be constrained. Pre-scale.
10. **Copying encrypted snapshots without planning keys.** Re-encrypt with a destination-Region key or use KMS multi-Region keys. Snapshots encrypted with the default AWS managed key can't be shared cross-account.
11. **"S3 CRR replicates existing objects automatically."** It doesn't. Use Batch Replication, with versioning on for both buckets.
12. **"S3 RTC 99.99% in 15 minutes."** The documented figure is **99.9%** within 15 minutes.
13. **"ElastiCache Global Datastore auto-fails over across Regions."** It doesn't. Promote manually.
14. **Expecting EBS Snapshots Archive or Glacier Deep Archive to meet a short RTO.** Restores take hours (snapshot archive restore up to 72 h).
15. **Converting an existing KMS key to multi-Region.** Not possible. Create a new MRK and re-encrypt.
16. **Governance-mode Vault Lock for ransomware.** Privileged (possibly compromised) principals can remove it. Use compliance mode or a logically air-gapped vault.
17. **Backups in the same account as production.** Compromised admin credentials can delete both. Use cross-account (ideally logically air-gapped) copies.
18. **DRS for one-time migration / MGN for DR.** Same technology, different product intent.
19. **Ignoring DR-Region quotas and SCPs.** A common hidden cause of failed failovers in scenario stems.
20. **Aurora switchover during an outage.** Switchover needs healthy clusters. For an unplanned outage, use failover.
21. **Global Accelerator for content caching** (that's CloudFront), or **CloudFront for static IPs/UDP** (that's Global Accelerator).
22. **Deep health checks on ALB targets** cause cascading failure when a shared dependency blips.
23. **Retries at every layer** multiply load (3 layers × 3 retries = 27 calls). Retry at one layer, with backoff + jitter and a cap.
24. **Zonal autoshift without pre-scaling.** Practice runs are mandatory, and autoshift doesn't wait for scaling.

---

## 7. Professional architect focus

- **Start with a business impact analysis (BIA).** Tier applications (tier 0/1/2/3) with explicit RTO/RPO per tier and per disruption type (application, infrastructure, AZ, Region). Resilience Hub policies mirror this. Typical enterprise outcome: tier 0 = multi-site or warm standby, tier 1 = pilot light, tier 2–3 = backup & restore.
- **Most outages aren't Region outages.** Bad deployments, config changes, expired certificates, quota exhaustion and dependency failures dominate. Invest first in **safe deployments** (canary, automatic rollback, one-box → one-AZ → one-cell waves), **observability** and **zonal isolation**, then multi-Region.
- **Decide who has failover authority.** Automatic Regional failover can make things worse (flapping, database split-brain). Many tier-0 designs use **automated detection + human-approved execution** (ARC routing controls, Region switch with manual trigger). AZ-level shifts are safer to automate (zonal autoshift).
- **Failback is half the plan.** Plan data resynchronisation (Aurora switchover back, DRS failback, S3 two-way replication) and test it. Many teams fail over well and then stay in DR for weeks.
- **Cost conversations.** Show the cost curve: each strategy step adds run cost and engineering cost. Cost levers: Aurora headless secondaries, Graviton in DR, a smaller warm standby, Capacity Reservations only for critical tiers, S3 replication to cheaper storage classes, lifecycle of backup copies to cold storage.
- **Test like you mean it.** Measure real RTO/RPO in game days, include people and communications, run FIS with stop conditions in production once mature. Treat DR runbooks as code.
- **Data consistency is the hard part.** Know which stores are async, how conflicts resolve (LWW), and what the application does with lost writes (idempotent replay, reconciliation jobs, event sourcing).
- **Dependencies hide everywhere.** Identity providers (on-prem AD, external IdP), licence servers, third-party APIs, CI/CD in one Region, DNS hosted elsewhere, ACM certificates (Regional; CloudFront needs us-east-1).
- **Governance.** Backup policies via Organizations, Backup Audit Manager reports, Config rules for "cross-Region backup exists", SCPs protecting backup vaults, separate security/recovery OUs.
- **Emerging / SAP-C03 preview (not core for SAP-C02):** expect more weight on **ARC (Region switch, zonal autoshift)**, **Resilience Hub** and **FIS** scenario libraries. Know each at the level in this chapter.

---

## 8. Skills checklist

- [ ] I can state the five Reliability pillar design principles and give an AWS example of each.
- [ ] I can compute serial and parallel availability and convert nines to downtime per year.
- [ ] I can explain control plane vs data plane and design recovery that uses only data-plane operations.
- [ ] I can define static stability and size a Multi-AZ deployment to survive an AZ loss without scaling.
- [ ] I can explain cell-based architecture and shuffle sharding and when each is justified.
- [ ] I can choose Multi-AZ vs multi-Region from a scenario's wording and constraints.
- [ ] I can describe retries with exponential backoff and jitter, timeouts, idempotency, circuit breakers, bulkheads, load shedding, graceful degradation and constant work.
- [ ] I can explain why deep health checks on load balancer targets are dangerous.
- [ ] I can distinguish Backup & Restore, Pilot Light, Warm Standby and Multi-site, draw each, and give indicative RTO/RPO.
- [ ] I can pick the right replication primitive for S3, EBS, AMIs, RDS, Aurora, DynamoDB, ElastiCache, secrets, keys and container images.
- [ ] I know the S3 RTC SLA (99.9% within 15 min), the versioning requirement, and Batch Replication for existing objects.
- [ ] I can explain Aurora Global Database switchover vs failover, the RPO of each, the global writer endpoint, headless secondaries and write forwarding.
- [ ] I can explain DynamoDB global tables MREC vs MRSC and the constraints of MRSC.
- [ ] I can choose between Route 53 failover, Global Accelerator, CloudFront origin failover, ARC routing control, Region switch, zonal shift/autoshift, MRAP and EventBridge global endpoints.
- [ ] I can describe AWS Elastic Disaster Recovery's architecture, RPO/RTO, drills and failback.
- [ ] I can list DR readiness items: quotas, capacity reservations, AMIs, keys, secrets, SCPs, IaC/StackSets, runbooks.
- [ ] I can design ransomware-resilient backups with Vault Lock compliance mode, logically air-gapped vaults, cross-account isolation and restore testing.
- [ ] I can explain what AWS FIS and AWS Resilience Hub do and how they fit into a resilience programme.

---

## 9. Practice questions

**Q1.** A financial services company runs a customer-facing trading portal on Amazon EC2 instances in an Auto Scaling group behind an Application Load Balancer in us-east-1, with an Amazon Aurora MySQL database. The business has defined an RPO of 5 seconds and an RTO of 30 minutes for a Regional outage. Leadership wants to minimise the ongoing cost of the DR environment in us-west-2, and the operations team is small. Which solution meets the requirements MOST cost-effectively?

- A. Configure AWS Backup to copy Aurora snapshots and AMIs to us-west-2 every hour. During a disaster, deploy the stack with CloudFormation and restore the latest snapshot.
- B. Convert the database to an Aurora Global Database with a headless secondary cluster in us-west-2. Copy AMIs and keep an Auto Scaling group with a desired capacity of zero in us-west-2. Use an automated runbook that adds a DB instance, fails over the global database, scales the Auto Scaling group, and lets Route 53 health checks fail traffic over.
- C. Create a full-size copy of the production stack in us-west-2 with an Aurora cross-Region read replica, and use Route 53 latency-based routing to send traffic to both Regions.
- D. Create an Aurora cross-Region read replica in us-west-2 and an identical Auto Scaling group running at full capacity. Use Route 53 failover routing.

**Q2.** A media company stores user-uploaded videos in an Amazon S3 bucket in eu-west-1. A new regulation requires that a copy of every object be present in eu-central-1, that the company can prove that 99.9% of objects are replicated within 15 minutes, and that operators are alerted when an object misses that threshold. The bucket already holds 400 TB of objects that must also be copied. Which combination of actions will meet these requirements? (Select TWO.)

- A. Enable versioning on both buckets, create a replication rule with S3 Replication Time Control enabled, and subscribe to `OperationMissedThreshold` events.
- B. Use S3 Batch Replication to replicate the existing objects to the destination bucket.
- C. Enable S3 Transfer Acceleration on the source bucket to guarantee replication speed.
- D. Configure an S3 Multi-Region Access Point in active/passive mode to replicate data between the buckets.
- E. Schedule an AWS DataSync task every 15 minutes to copy new objects and alert on task failure.

**Q3.** An e-commerce company is designing a new order service that must keep accepting orders even if an entire AWS Region becomes unavailable. Customers are in North America and Europe and must have low write latency from their home continent. The business accepts that, in rare cases, a few seconds of order updates made in a failed Region may be delayed until that Region recovers, and that concurrent updates to the same item resolve to the most recent write. The team wants a fully managed solution with the least operational overhead. Which data-tier design should the architect choose?

- A. Amazon DynamoDB global tables using multi-Region strong consistency (MRSC) in us-east-1, us-west-2 and eu-west-1.
- B. Amazon DynamoDB global tables using multi-Region eventual consistency (MREC) with replicas in us-east-1 and eu-west-1.
- C. Amazon Aurora Global Database with the primary in us-east-1 and a secondary in eu-west-1 with write forwarding enabled.
- D. Amazon RDS for PostgreSQL Multi-AZ DB clusters in each Region with logical replication configured in both directions.

**Q4.** A company runs 350 on-premises servers on VMware vSphere and Hyper-V, including Windows and Linux application servers and self-managed SQL Server and Oracle databases. The lease on the company's secondary data center expires in 3 months. Management wants to use AWS as the DR site with an RPO of seconds and an RTO of under 1 hour, wants to pay as little as possible for idle DR resources, and must be able to recover to a point in time before a ransomware infection. After a disaster, workloads must be able to return on premises. Which solution meets these requirements?

- A. Use AWS Transform MGN (formerly AWS Application Migration Service) to replicate the servers and launch cutover instances during a disaster.
- B. Use AWS Elastic Disaster Recovery with the replication agent on each server, replicating to a staging area subnet. Run periodic drills, and use point-in-time recovery and failback when needed.
- C. Use AWS Backup with Backup gateway for VMware to take daily backups and copy them to an AWS Region, then restore to EC2 during a disaster.
- D. Export VM images nightly with VM Import/Export to Amazon S3 and maintain CloudFormation templates to launch them as EC2 instances.

**Q5.** A healthcare company was hit by ransomware in another business unit. The attacker obtained administrator credentials in a workload account and deleted all snapshots and the backup vault in that account. The CISO asks the architect to redesign backups for 200 AWS accounts so that nobody, including compromised administrators or the root user, can delete backups or shorten their retention, and so that a clean restore can be performed quickly from a separate account even if a workload account is unreachable. Which combination of steps should the architect take? (Select THREE.)

- A. Use AWS Organizations backup policies to deploy AWS Backup plans to all accounts with copy actions to a central backup account.
- B. In the central backup account, copy recovery points to a logically air-gapped vault and share it with an isolated recovery account by using AWS RAM.
- C. Apply AWS Backup Vault Lock in governance mode to the central vault so that only the security team can change retention.
- D. Apply AWS Backup Vault Lock in compliance mode to the central backup vault with a grace time of at least 3 days, and configure minimum and maximum retention.
- E. Enable S3 Cross-Region Replication for all buckets and EBS Multi-Attach for critical volumes.
- F. Keep all backups in each workload account but enable MFA Delete on the vault.

**Q6.** A SaaS provider runs a stateless API on Amazon ECS on AWS Fargate behind a Network Load Balancer in three Availability Zones. During a recent event, one AZ had intermittent packet loss. The NLB health checks kept passing, but customer latency spiked for 40 minutes until engineers manually redeployed tasks. The company wants traffic to move away from an impaired AZ automatically during AWS-detected AZ impairments, with regular validation that the remaining AZs can carry the load. Which actions should the architect take? (Select TWO.)

- A. Enable ARC zonal autoshift for the load balancer and configure practice runs with outcome alarms.
- B. Pre-scale the ECS service so that any two AZs can handle peak traffic, rather than relying on scaling when an autoshift starts.
- C. Replace the NLB health checks with deep health checks that verify database connectivity from each task.
- D. Create Route 53 latency-based records for each AZ's NLB node IP address.
- E. Configure ARC routing controls in a cluster and write a Lambda function that toggles them when NLB errors rise.

**Q7.** A logistics company operates an Aurora PostgreSQL global database with the primary cluster in eu-west-1 and a secondary cluster in eu-central-1. A regulator requires the company to run production from eu-central-1 for 3 months each year and then move back, with no data loss during either move. Applications currently connect using the cluster endpoint of the primary. Which approach meets the requirement with the LEAST operational effort?

- A. Perform a managed failover with `--allow-data-loss` to eu-central-1, then re-add eu-west-1 as a secondary.
- B. Detach the eu-central-1 cluster from the global database, promote it, and create a new global database with eu-west-1 as a secondary.
- C. Perform an Aurora Global Database switchover to eu-central-1, and update applications to use the global writer endpoint so that future moves need no connection string change.
- D. Take a manual snapshot in eu-west-1, copy it to eu-central-1, restore it, and repoint DNS.

**Q8.** A company has a warm standby DR environment in us-east-2 for an application whose primary runs in us-east-1. A recent DR test failed for three reasons: the DR Region's EC2 On-Demand vCPU quota was too low, the AMI referenced in the DR launch template was 4 months old, and a secret used by the application did not exist in us-east-2. The company wants to detect these issues continuously and keep the DR environment consistent with production with minimal manual effort. Which combination of actions should the architect recommend? (Select THREE.)

- A. Configure ARC readiness checks for the application's resources in both Regions.
- B. Deploy both Regions from the same CI/CD pipeline using CloudFormation StackSets, with an AMI-building pipeline that copies each new AMI to us-east-2 and updates the SSM parameters referenced by the launch template.
- C. Configure AWS Secrets Manager to replicate the secret to us-east-2.
- D. Change the Route 53 health check request interval to 10 seconds.
- E. Use AWS Trusted Advisor to automatically create quota increases in us-east-2 when production scales.
- F. Enable EBS Fast Snapshot Restore in us-east-1.

**Q9.** A global gaming company runs UDP-based game servers on EC2 in ap-northeast-1 and us-west-2. Players' clients have the server addresses hard-coded and cannot handle DNS changes quickly. When a Region becomes unhealthy, new player sessions must go to the other Region within seconds. The company also wants to move 10% of traffic gradually to a new Region for testing. Which solution meets these requirements?

- A. Amazon CloudFront with an origin group containing both Regions' NLBs.
- B. Route 53 failover routing with fast (10-second) health checks and a 1-second TTL.
- C. AWS Global Accelerator standard accelerator with an endpoint group per Region, health checks, and traffic dials.
- D. An S3 Multi-Region Access Point with failover controls in front of both Regions.

**Q10.** A retailer's checkout service calls a payment provider's API. During peak sales, the provider sometimes responds slowly and returns throttling errors. The checkout service retries immediately, up to five times, at the API layer, the service layer and the client SDK layer, and customers have reported being charged twice. The architect must improve resilience and prevent duplicate charges. Which combination of changes should the architect make? (Select TWO.)

- A. Retry at a single layer using capped exponential backoff with jitter, with short timeouts and a circuit breaker that fails fast when the provider is unhealthy.
- B. Send an idempotency key with each payment request and store request outcomes so that retries return the original result.
- C. Raise the timeout of each layer to 5 minutes so that slow responses eventually succeed.
- D. Move the checkout service to a larger instance type to process retries faster.
- E. Configure Route 53 health checks against the payment provider and fail over to a second Region of the checkout service.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B**

- **Why B:** Aurora Global Database replicates at the storage layer with typical lag under 1 second, which meets the 5-second RPO. A **headless** secondary (storage only) keeps the DR database cheap, and no compute runs (Auto Scaling group at 0). That's **pilot light**. An automated runbook (or ARC Region switch) that adds an instance, fails over and scales out can meet a 30-minute RTO.
- **A:** Hourly snapshots mean an RPO of up to 1 hour, which breaks the 5-second RPO. Restore plus deploy may also exceed 30 minutes.
- **C:** Full-size active/active costs far more than needed. An Aurora cross-Region read replica can't accept writes, so latency routing would send writes to a read-only Region.
- **D:** Full-capacity compute in DR is hot standby and costs more than the requirement justifies.
- **References:** [DR options in the cloud](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html) · [Aurora Global Database switchover/failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A, B**

- **A:** S3 RTC replicates 99.9% of objects within 15 minutes under an SLA, turns on replication metrics, and emits `OperationMissedThreshold` / `OperationReplicatedAfterThreshold` events for alerting. Replication requires versioning on both source and destination.
- **B:** Replication rules apply only to new objects. **S3 Batch Replication** copies existing objects.
- **C:** Transfer Acceleration speeds up client uploads over long distances. It doesn't affect replication or carry an SLA.
- **D:** MRAP routes requests and supports failover, but CRR rules still do the replicating. MRAP itself doesn't replicate.
- **E:** DataSync has no 15-minute SLA and adds operational overhead. It isn't the native compliance mechanism.
- **References:** [S3 Replication Time Control](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-time-control.html) · [S3 Batch Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-batch-replication-batch.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: B**

- **Why B:** DynamoDB global tables in **MREC** mode are multi-active (local writes in each Region), replicate asynchronously (typically within a second) and resolve conflicts with **last writer wins**. The stem explicitly accepts both a small RPO and LWW. It's fully managed with minimal ops.
- **A:** MRSC gives RPO 0 but must use exactly three Regions and has higher write latency, because each write waits for cross-Region replication. That works against "low write latency from home continent" for transatlantic Regions. MRSC also has no transaction support. It's more than the stated needs require.
- **C:** Aurora write forwarding still commits writes in the single primary Region, so European writes cross the Atlantic. If us-east-1 fails, writes stop until failover.
- **D:** Self-managed bidirectional logical replication brings high operational overhead and conflict risk.
- **References:** [DynamoDB global tables: how they work](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: B**

- **Why B:** AWS Elastic Disaster Recovery continuously replicates VMware, Hyper-V and physical servers at the block level into a **low-cost staging area**. It supports an **RPO of seconds and RTO of minutes**, **point-in-time recovery** (to before the ransomware), non-disruptive drills and **failback** to on-premises.
- **A:** MGN is built for migration (cutover), not ongoing DR with drills, point-in-time recovery and failback.
- **C:** Daily backups give an RPO of up to 24 hours, which fails "RPO of seconds".
- **D:** Nightly exports give a poor RPO and heavy manual effort, and VM Import is slow.
- **References:** [What is Elastic Disaster Recovery](https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html) · [DRS FAQs](https://aws.amazon.com/disaster-recovery/faqs/)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: A, B, D**

- **A:** Organizations backup policies centrally enforce backup plans across all 200 accounts and copy to a separate backup account. That removes the single-account blast radius.
- **B:** A **logically air-gapped vault** is always compliance-locked and stores backups in an AWS Backup service-owned account. Sharing it through **AWS RAM** lets an isolated recovery account restore directly (faster RTO), even if the workload account is unreachable. Multi-party approval adds another recovery path.
- **D:** **Compliance-mode Vault Lock** (grace time ≥72 hours) makes recovery points undeletable by anyone, including root and AWS, until retention expires. The min/max retention settings enforce policy.
- **C:** Principals with enough IAM permissions can remove a governance-mode lock, and a compromised admin may have exactly those permissions.
- **E:** Replication copies deletions and encryption, and doesn't create immutable backups. EBS Multi-Attach is unrelated.
- **F:** MFA Delete is an S3 bucket feature, not an AWS Backup vault feature. Keeping backups in the same account fails the requirement.
- **References:** [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html) · [Logically air-gapped vault](https://docs.aws.amazon.com/aws-backup/latest/devguide/logicallyairgappedvault.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, B**

- **A:** **Zonal autoshift** lets AWS shift traffic away from an AZ when AWS telemetry detects an impairment, which covers gray failures your own health checks miss. **Practice runs are required** and check every week that the app runs normally without one AZ.
- **B:** AWS strongly recommends **pre-scaling** so the remaining AZs can carry peak load, because autoshift doesn't wait for scaling. This is static stability.
- **C:** Deep health checks on load balancer targets can remove every target when a shared dependency blips (cascading failure). They also don't make use of AWS's own impairment detection.
- **D:** Route 53 records pointing at individual NLB node IPs are fragile and bypass the load balancer's zonal shift integration. It isn't a supported pattern.
- **E:** Routing controls are designed for multi-Region failover, and a custom Lambda adds operational overhead and untested logic.
- **References:** [Zonal autoshift in ARC](https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-autoshift.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: C**

- **Why C:** **Switchover** (formerly managed planned failover) is designed for planned **Region rotation**. It waits for the secondary to fully synchronise (**RPO 0**) and keeps the global topology. With the **global writer endpoint**, connection strings stay the same when the primary moves.
- **A:** Failover with `--allow-data-loss` is meant for unplanned outages and can lose unreplicated transactions, which violates "no data loss".
- **B:** Detach-and-promote (manual failover) is more work, breaks the topology and risks data loss.
- **D:** Snapshot copy and restore means long downtime and loses writes made after the snapshot.
- **References:** [Aurora Global Database switchover and failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: A, B, C**

- **A:** **ARC readiness checks** continuously audit quotas, capacity and configuration across the production and DR replicas and flag mismatches, including the vCPU quota gap.
- **B:** Deploying both Regions from one pipeline (StackSets), with AMIs copied and parameters updated automatically, stops the DR stack from drifting.
- **C:** **Secrets Manager replica secrets** keep the secret available (and rotated) in us-east-2.
- **D:** A faster health check interval doesn't fix quotas, AMIs or secrets.
- **E:** Trusted Advisor reports quota usage but doesn't automatically raise quotas in another Region based on production scaling.
- **F:** FSR in the *primary* Region doesn't help DR readiness in us-east-2.
- **References:** [What is ARC (readiness check)](https://docs.aws.amazon.com/r53recovery/latest/dg/what-is-route53-recovery.html) · [Secrets Manager replication](https://docs.aws.amazon.com/secretsmanager/latest/userguide/create-manage-multi-region-secrets.html) · [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: C**

- **Why C:** Global Accelerator gives **static anycast IP addresses** (good for hard-coded clients), supports **UDP**, continuously health-checks endpoints and sends **new connections** to healthy endpoints without waiting for DNS caches to expire. **Traffic dials** set the percentage per Region for gradual testing.
- **A:** CloudFront serves HTTP(S) and doesn't proxy arbitrary UDP game traffic. Origin failover covers only GET/HEAD/OPTIONS.
- **B:** DNS failover depends on client resolver caching, and clients with hard-coded addresses never re-resolve.
- **D:** MRAP is an S3 feature for bucket access, not for EC2 game servers.
- **References:** [How Global Accelerator works](https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-how-it-works.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: A, B**

- **A:** Retrying at every layer multiplies load (5 × 5 × 5 attempts) and causes retry storms. Retry at one layer with **capped exponential backoff and jitter**, short **timeouts**, and a **circuit breaker** that fails fast while the provider is degraded.
- **B:** **Idempotency keys** make retried payment requests safe: the provider (or your service) returns the original outcome instead of charging again.
- **C:** Very long timeouts tie up threads and connections and cause cascading failure, and customers give up long before 5 minutes.
- **D:** A bigger instance fixes neither the retry amplification nor the duplicate charges.
- **E:** The problem is the third-party dependency, not the checkout Region. Failing over your own service won't stop the provider's throttling or the duplicates.
- **References:** [Reliability pillar: design interactions in a distributed system to mitigate or withstand failures](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/design-interactions-in-a-distributed-system-to-mitigate-or-withstand-failures.html) · [Timeouts, retries and backoff with jitter (Builders' Library)](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/) · [Making retries safe with idempotent APIs (Builders' Library)](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/)
</details>

---

## 10. References

- [Disaster Recovery of Workloads on AWS (whitepaper): DR options in the cloud](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html)
- [AWS Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
- [AWS Fault Isolation Boundaries (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/aws-fault-isolation-boundaries/abstract-and-introduction.html)
- [Reducing the Scope of Impact with Cell-Based Architecture (whitepaper)](https://docs.aws.amazon.com/wellarchitected/latest/reducing-scope-of-impact-with-cell-based-architecture/reducing-scope-of-impact-with-cell-based-architecture.html)
- [AWS Architecture Blog: Disaster Recovery (DR) Architecture on AWS, Part I](https://aws.amazon.com/blogs/architecture/disaster-recovery-dr-architecture-on-aws-part-i-strategies-for-recovery-in-the-cloud/)
- [Amazon Builders' Library: Static stability using Availability Zones](https://aws.amazon.com/builders-library/static-stability-using-availability-zones/)
- [Amazon Builders' Library: Workload isolation using shuffle-sharding](https://aws.amazon.com/builders-library/workload-isolation-using-shuffle-sharding/)
- [Amazon Builders' Library: Timeouts, retries, and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/)
- [Amazon Builders' Library: Implementing health checks](https://aws.amazon.com/builders-library/implementing-health-checks/)
- [S3 Replication Time Control](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-time-control.html)
- [S3 Multi-Region Access Points failover controls](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MrapFailover.html)
- [Aurora Global Database: switchover and failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html)
- [RDS cross-Region automated backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html)
- [DynamoDB global tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- [ElastiCache Global Datastore](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Redis-Global-Datastore.html)
- [Route 53 health check values](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-creating-values.html)
- [Amazon Application Recovery Controller (ARC)](https://docs.aws.amazon.com/r53recovery/latest/dg/what-is-route53-recovery.html)
- [ARC Region switch](https://docs.aws.amazon.com/r53recovery/latest/dg/region-switch.html)
- [ARC zonal autoshift](https://docs.aws.amazon.com/r53recovery/latest/dg/arc-zonal-autoshift.html)
- [AWS Global Accelerator: how it works](https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-how-it-works.html)
- [CloudFront origin failover](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html)
- [EventBridge global endpoints](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-global-endpoints.html)
- [KMS multi-Region keys](https://docs.aws.amazon.com/kms/latest/developerguide/multi-region-keys-overview.html)
- [Secrets Manager multi-Region secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/create-manage-multi-region-secrets.html)
- [ECR private image replication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html)
- [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [EC2 On-Demand Capacity Reservations](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html)
- [AWS Elastic Disaster Recovery](https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html) · [DRS FAQs](https://aws.amazon.com/disaster-recovery/faqs/)
- [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html)
- [AWS Backup logically air-gapped vault](https://docs.aws.amazon.com/aws-backup/latest/devguide/logicallyairgappedvault.html)
- [GuardDuty Malware Protection for AWS Backup](https://docs.aws.amazon.com/guardduty/latest/ug/malware-protection-backup.html)
- [AWS Fault Injection Service](https://docs.aws.amazon.com/fis/latest/userguide/what-is.html)
- [AWS Resilience Hub](https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html) · [Resilience Hub concepts](https://docs.aws.amazon.com/resilience-hub/latest/userguide/concepts-terms.html)
