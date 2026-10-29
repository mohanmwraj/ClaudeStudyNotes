# 02/01 · Business Requirements to Architecture

**Exam guide:** 1.1 (business requirements) and the business side of 1.5. **Principles:** P2, P5, P8, P9, P10, P13, P15.

An architect's first job is translation: turning sentences written by executives ("reduce costs", "grow internationally", "never lose a patient record") into measurable constraints that eliminate designs. The exam tests that translation more than any single product fact.

---

## 1. Functional vs non-functional requirements

* **Functional requirements** say *what* the system does: "customers can build a car online and place an order", "associates approve generated descriptions".
* **Non-functional requirements (NFRs)** say *how well* it does it. NFRs drive almost every architecture decision on the exam.

| NFR | Measured as | Drives |
|---|---|---|
| Availability | % uptime over a window (99.9%) | Zonal vs regional vs multi-regional (P1, P2) |
| Latency | p50/p95/p99 response time per user location | Region placement, CDN, caching, global load balancing |
| Throughput / scale | Requests/s, events/s, TB/day, concurrent users | Horizontal scaling, sharding, data store choice (P4) |
| Durability | Probability of data loss | Replication, backups, storage class |
| Recoverability | **RTO** (time to restore) and **RPO** (data loss window) | DR pattern (see [02/02](02-technical-requirements-ha-scalability-dr.md)) |
| Security | Threat model, required controls | IAM design, perimeters, encryption (P6, P11) |
| Compliance | Regulation, certification, audit | Residency, logging, key custody, Assured Workloads |
| Cost | Budget, unit economics ($ per order or stream) | Pricing models, managed vs self-run (P9) |
| Operability | Team size and skills, on-call burden | Managed services (P5), automation (P12) |
| Portability | Multicloud, exit strategy, open standards | Containers, Kubernetes, open data formats (Iceberg) |
| Sustainability | Carbon footprint | Region choice (low-carbon regions), efficiency |

**Technique:** for each business sentence, write the NFR it implies and a number. If the case study gives no number, the answer that adds *unnecessary* capability (and cost) is usually wrong.

---

## 2. Translating business language into constraints

| Business says | Architect hears | Typical design consequence |
|---|---|---|
| "Our data center lease expires in 6 months" | A hard deadline. Minimize change now | Rehost or replatform first (P15); Migrate to VMs, GKE for existing containers, DMS |
| "Reduce infrastructure administration costs" | Shed toil | Managed and serverless services (P5) |
| "Business is growing exponentially" | Elastic scale, no re-architecture at 10× | Horizontal, autoscaled, managed data stores that scale |
| "Customers are worldwide" | Latency and data residency vary per region | Global LB, CDN, multi-region where needed; residency review |
| "Never lose a transaction" | RPO ≈ 0 | Synchronous replication (Cloud SQL HA within a region, Spanner across regions) |
| "Must be back up within an hour after a disaster" | RTO ≤ 1 h | Warm standby in a second region, automated failover runbooks |
| "Regulated (health, finance, children's data)" | Compliance controls are hard constraints | Covered services, audit logs, encryption key control, residency |
| "Our team knows SQL, not Kubernetes" | Skills constraint | Prefer Cloud Run / BigQuery / Cloud SQL over GKE or Spark if possible |
| "Partners integrate via files today" | Integration style to support | File landing zone, event-driven processing; offer APIs later |
| "Cost management is a top priority" | Cost is the tie-breaker | Autoscaling, Spot for batch, CUDs for baseline, storage lifecycle |
| "Explainable, auditable AI" | Governance requirement on ML | Explainable AI, lineage, model registry, logging prompts and responses |

---

## 3. Business continuity planning (BCP)

* **Business continuity** keeps the *business* operating during disruption: people, processes and technology.
* **Disaster recovery (DR)** is the technology part: restoring systems and data.

| BCP step | Content |
|---|---|
| Business impact analysis (BIA) | Rank processes by criticality; for each, set the **maximum tolerable downtime**, **RTO** and **RPO** |
| Risk assessment | Threats: zone or region outage, ransomware, operator error, supplier failure, pandemic |
| Strategy | Per tier: backup/restore, pilot light, warm standby, multi-site active/active ([02/02](02-technical-requirements-ha-scalability-dr.md) §4) |
| Plan and runbooks | Who does what, failover and failback steps, communications |
| **Test** | Scheduled DR drills, game days, chaos experiments (Section 4.1, 6.6) |
| Maintain | Review after architecture changes and incidents |

**Exam angle:** an untested DR plan is a wrong answer. If an option includes "regularly test failover" or "automate the runbook", it's usually better than an otherwise equal option without it.

---

## 4. Cost optimization at design time

Cost is a design input, not an afterthought. The levers by layer (details in [05/03](../05-Technical-and-Business-Processes/03-business-processes-stakeholders-cost.md)):

| Layer | Design-time lever |
|---|---|
| Architecture | Serverless and scale-to-zero for spiky or low-traffic workloads; managed services remove ops cost; asynchronous designs smooth peaks so you provision for averages |
| Compute | Right machine family (E2 general purpose, N4/C4 balanced and performance, compute-optimized, memory-optimized, accelerator-optimized); custom machine types; Spot for fault-tolerant work; CUDs for steady baseline |
| Storage | Storage class and lifecycle per access pattern; Autoclass; delete what you don't need (retention policy, TTLs) |
| Data/analytics | BigQuery partitioning and clustering; editions with autoscaling vs on-demand; materialized views; avoid `SELECT *` |
| Network | Keep chatty services in one region; Cloud CDN; Standard Tier networking for cost-sensitive, latency-tolerant egress; Private Google Access avoids NAT processing charges for Google API traffic |
| Licensing | Bring your own license (BYOL) on sole-tenant nodes where licenses are core-bound; license-included images otherwise; managed services that include licenses (Cloud SQL for SQL Server) |
| Governance | Budgets and alerts, labels for cost allocation, billing export to BigQuery, Recommender |

**TCO vs price.** The exam often presents a "cheaper per hour" option that's more expensive in total: a self-managed database on Compute Engine looks cheaper than Cloud SQL until you add DBA time, patching, HA engineering and outage risk. TCO includes **operations, risk and opportunity cost**.

---

## 5. Supporting the application design

| Application trait | Architectural fit |
|---|---|
| Stateless HTTP services | Cloud Run, GKE Deployments, MIGs behind a load balancer |
| Event-driven, short tasks | Cloud Run functions, Eventarc, Pub/Sub push to Cloud Run |
| Long-running batch | Cloud Run jobs, Batch, GKE Jobs, Managed Service for Apache Spark, Dataflow |
| Stateful legacy monolith | Compute Engine MIG (stateful MIG if needed) or VMware Engine for as-is moves; later decompose |
| Microservices with service-to-service policy | GKE + Cloud Service Mesh (mTLS, traffic management) |
| Need for strict ordering per key | Pub/Sub ordering keys, or a Spanner/Bigtable design that encodes order |
| Very high fan-out reads | Caching (Memorystore, Cloud CDN), read replicas |

**Twelve-factor app** properties (config in environment, stateless processes, disposable instances, logs as event streams, dev/prod parity) are the implicit standard behind most "modernize" answers.

---

## 6. Integration patterns with external systems

| Pattern | When | Google Cloud building blocks | Watch out |
|---|---|---|---|
| **Synchronous API** | Partners need request/response, real time | **Apigee** (full API management: security, quotas, monetization, developer portal, analytics) or **API Gateway** (lightweight, serverless back ends) | Tight coupling. Partner outages propagate unless you add timeouts and circuit breakers |
| **Asynchronous messaging** | Decouple producers and consumers, absorb spikes | **Pub/Sub** (push/pull, at-least-once, ordering keys, dead-letter topics), Managed Service for Apache Kafka (Kafka API compatibility) | Idempotent consumers; dead-letter topics |
| **Event routing** | React to Google Cloud or SaaS events | **Eventarc** (Cloud Storage, Audit Log, Pub/Sub, third-party sources) → Cloud Run / Workflows | Filter events precisely |
| **File-based (batch)** | Legacy partners: SFTP, CSV drops | Land in **Cloud Storage**; Pub/Sub notifications or Eventarc → processing; Storage Transfer Service for scheduled pulls | Validate and quarantine bad files; make processing idempotent |
| **Change data capture** | Replicate database changes downstream | **Datastream** (MySQL, PostgreSQL, SQL Server, Oracle → BigQuery / Cloud Storage) | Schema evolution |
| **iPaaS / SaaS integration** | Connect SaaS (Salesforce, SAP, ServiceNow) with low code | **Application Integration** with **Integration Connectors** | Licensing and throughput limits |
| **Workflow orchestration** | Multi-step processes with retries and branching | **Workflows** (serverless, HTTP/API steps), **Managed Service for Apache Airflow** (data pipelines, DAGs) | Choose Workflows for service orchestration and Airflow for data DAGs |
| **B2B private service access** | Expose a service privately to another organization's VPC | **Private Service Connect** (producer service attachment ↔ consumer endpoint) | No overlapping-IP problem, unlike peering |

---

## 7. Movement of data

Choose by **volume, bandwidth, frequency and source**:

| Situation | Tool |
|---|---|
| Online transfer from another cloud (S3, Azure Blob) or HTTP list | **Storage Transfer Service** (agentless) |
| On-premises file systems to Cloud Storage, scheduled or continuous | **Storage Transfer Service with agents** (needs connectivity: Interconnect or VPN for bandwidth) |
| Hundreds of TB to PB, limited bandwidth, or > ~1 week over the network | **Transfer Appliance** (shipped device; encrypted) |
| Ad-hoc, small (GB–low TB) | `gcloud storage cp` / `rsync` (parallel composite uploads) |
| SaaS and warehouse sources (Google Ads, YouTube, S3, Redshift, Teradata) into BigQuery | **BigQuery Data Transfer Service** / BigQuery Migration Service |
| Databases with minimal downtime | **Database Migration Service** (continuous), **Datastream** for analytics replication |
| Streaming events | **Pub/Sub**, Dataflow |

Rule-of-thumb time math is in [P10](../00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md#p10--data-has-gravity-a-lifecycle-and-a-legal-home).

---

## 8. Design decision trade-offs

Every decision trades something. Name the trade explicitly; the exam rewards the option whose trade the scenario can afford.

| Decision | Gain | Cost |
|---|---|---|
| Multi-region active-active | Region-failure tolerance, low global latency | 2×+ cost, consistency complexity (Spanner or conflict handling) |
| Serverless | No ops, scale to zero | Less control, cold starts, platform limits |
| GKE | Portability, control, ecosystem | Operational skill needed (less with Autopilot) |
| Strong consistency | Simple correctness | Latency (consensus across distance) |
| Eventual consistency / async | Throughput, decoupling | Application must tolerate staleness and duplicates |
| CMEK / EKM | Key control | Operational burden; availability depends on the key |
| Lift-and-shift | Speed, low risk now | Cloud benefits not realized; tech debt remains |
| Re-architect | Long-term agility and cost | Time, risk, skills |

---

## 9. Workload disposition: build, buy, modify or deprecate

The exam guide's wording maps onto the classic migration "Rs":

| Exam term | Classic R | Choose when |
|---|---|---|
| **Buy** | Repurchase (SaaS) | Non-differentiating capability (CRM, HR, email) and a good SaaS exists |
| **Modify** | Replatform / refactor | Valuable app, but needs cloud benefits (managed DB, containers) |
| **Build** | Rebuild / rearchitect | Differentiating capability; legacy design blocks the goals |
| **Deprecate** | Retire | Low usage, duplicate functionality, end of life |
| (implicit) | Rehost | Deadline-driven move with no time to change |
| (implicit) | Retain | Can't or shouldn't move now (regulatory, scheduled replacement, mainframe dependency) |

KnightMotives' CRM is a classic **buy**. EHR's legacy insurance integrations are **retain**. Cymbal's catalog search is **modify/replace** with Agent Search for Commerce.

---

## 10. Success measurements: KPIs, ROI and metrics

Every architecture should state how success will be measured, and the exam includes options like "define KPIs before migration".

| Type | Examples |
|---|---|
| Business KPIs | Conversion rate, call deflection rate, time-to-onboard a partner, catalog items enriched per day, days-on-lot for vehicles |
| Technical KPIs / SLOs | Availability, p95 latency, error rate, deployment frequency, lead time for changes, change failure rate, MTTR (the DORA four) |
| Financial | TCO, ROI = (benefit − cost) ÷ cost, cost per transaction, payback period |
| AI quality | Groundedness, acceptance rate of generated content, hallucination rate, safety violations caught |

---

## 11. Well-Architected Framework: the pillars in one table

| Pillar | Core idea | Exam-favorite practices |
|---|---|---|
| Operational excellence | Run and improve workloads efficiently | IaC, CI/CD, observability, incident management, postmortems |
| Security, privacy, compliance | Protect data and systems | Least privilege, defense in depth, secure by default, shared responsibility |
| Reliability | Meet availability targets | Redundancy, SLOs and error budgets, graceful degradation, tested DR |
| Cost optimization | Maximize business value per dollar | FinOps culture, rightsizing, pricing models, waste elimination |
| Performance optimization | Efficient resource use for performance | Choosing correct services, caching, scaling, load testing |
| Sustainability | Minimize environmental impact | Low-carbon regions, efficient utilization, serverless, data lifecycle |

Framework home: <https://cloud.google.com/architecture/framework>

---

## 12. Worked scenarios

**A. "A logistics company wants to cut costs. Its order-tracking site has 2,000 requests/min during business hours and almost none at night."**
Load shape: diurnal, idle at night (P9). The site is stateless (P3). The most managed option is Cloud Run, which scales to zero (P5). If the database must stay on, use Cloud SQL with a smaller tier and a CUD for its steady usage. Reject: "a 3-year CUD on VMs sized for peak".

**B. "Partners send nightly CSV files over SFTP. The company wants to onboard 50 more partners quickly and process files within 15 minutes of arrival."**
Integration pattern: file-based now, event-driven processing (P8). The design: a landing bucket per partner (IAM-isolated) or an SFTP gateway in front of Cloud Storage; Pub/Sub notifications to Cloud Run or Dataflow for validation and load; Apigee for partners ready for APIs. Reject: "a cron job every hour on a VM that polls the folder".

**C. "A bank must prove which AI-generated responses were shown to customers and why."**
Governance NFR. Log prompts, grounding sources, model version and responses to an immutable store (log bucket with locked retention, or BigQuery with controls); Gen AI evals; human review for high-risk flows (P16, P13).

---

## References

* Well-Architected Framework: <https://cloud.google.com/architecture/framework>
* Architecture Center: <https://cloud.google.com/architecture>
* Disaster recovery planning guide: <https://cloud.google.com/architecture/dr-scenarios-planning-guide>
* Data transfer options: <https://cloud.google.com/storage-transfer/docs/overview>
* Application Integration: <https://cloud.google.com/application-integration/docs/overview>
