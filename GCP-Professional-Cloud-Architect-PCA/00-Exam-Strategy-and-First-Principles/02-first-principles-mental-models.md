# 02 · First-Principles Mental Models

The PCA exam can generate thousands of scenarios, but they rest on about sixteen underlying mechanisms. If you understand a mechanism, you don't need to memorize the scenarios built on it. You can **derive** the answer and explain why each distractor fails. Every file and every answer explanation in this kit refers back to these principles by number (**P1–P16**).

Each principle has four parts:

* **Mechanism:** how Google Cloud, or physics, actually works.
* **Consequence:** what follows from it for design.
* **How it appears:** the question patterns it decides.
* **Distractor killed:** the wrong answers it lets you eliminate.

---

## P1 · Geography is physics: distance is latency, and scope is a failure domain

**Mechanism.** Light in fiber covers about 200 km per millisecond, so a round trip between Frankfurt and Iowa (about 7,000 km of fiber) can't be faster than about 70 ms. Google Cloud is organized into **regions** (independent geographic areas) and **zones** (isolated failure domains inside a region; most regions have three). Every resource has a **scope**:

| Scope | Examples | Survives |
|---|---|---|
| **Zonal** | VM instance, zonal Persistent Disk / Hyperdisk, zonal MIG, zonal GKE cluster, Filestore Basic | Nothing beyond its zone |
| **Regional** | Subnet, regional MIG, regional PD, regional GKE cluster, Cloud SQL HA, AlloyDB, Cloud Run service, regional Cloud Storage bucket, Memorystore Standard tier | Loss of a zone |
| **Multi-regional / global** | VPC network (global), firewall policies, global external Application Load Balancer, Cloud CDN, multi-region and dual-region Cloud Storage, Spanner multi-region configs, BigQuery multi-region datasets, Pub/Sub, Cloud DNS, IAM, images | Loss of a region (when configured multi-region) |

Google Cloud's **VPC network is global**: one network can contain subnets in every region, and VMs in different regions talk over Google's backbone using internal IPs with no VPN in between. That differs from most other clouds, and it's tested.

**Consequence.**

* Put compute **near users** (latency) and **near data** (see P10).
* To survive a zone failure, use **regional** resources or spread zonal ones across zones.
* To survive a region failure, replicate state to a second region **and** have a way to send traffic there (global load balancer or DNS failover).

**How it appears.** "Users worldwide complain about latency" (global external Application Load Balancer plus Cloud CDN, and backends in several regions). "Must survive a zonal outage" (regional MIG, regional GKE, Cloud SQL HA). "Must survive a regional disaster" (cross-region replica or multi-region service, plus a DR runbook).

**Distractor killed.** A single-zone design offered for an HA requirement; a VPN proposed to connect two regions of the *same* VPC (unnecessary, because the VPC is global); "increase VM size" to fix latency caused by distance.

---

## P2 · Availability is arithmetic: redundancy multiplies, dependencies divide

**Mechanism.**

* **Components in series** (all must work): A = A₁ × A₂ × … × Aₙ. For example, a 99.95% load balancer in front of a 99.9% database gives 99.85% at best.
* **Components in parallel** (any one is enough): A = 1 − (1 − A₁)(1 − A₂)…. For example, two independent 99.5% zones give 1 − 0.005² = 99.9975%.

Downtime budgets per 30-day month:

| SLA | Allowed downtime / month |
|---|---|
| 99% | ~7.2 h |
| 99.5% | ~3.6 h |
| 99.9% | ~43 min |
| 99.95% | ~22 min |
| 99.99% | ~4.3 min |
| 99.999% | ~26 s |

**Consequence.** You can't build 99.99% out of a single 99.9% component in series. You need redundancy at **every** layer, including the network: two Interconnect metros, or a 99.99% single-metro topology, or HA VPN's two tunnels. Each extra "nine" roughly multiplies cost and complexity, so match the nines to the business requirement and no more (P9).

**How it appears.** EHR Healthcare's "minimum 99.9% availability for all customer-facing systems" points to multi-zone regional deployments. It doesn't require multi-region active-active. "99.99% hybrid connectivity" means HA VPN configured correctly or an Interconnect 99.99% topology. "Five nines globally" means Spanner multi-region.

**Distractor killed.** Over-engineering, such as multi-region active-active when 99.9% is asked; under-engineering, such as one VPN tunnel or one Interconnect connection when 99.99% is asked.

---

## P3 · State is the hard part: make compute stateless and push state into managed services

**Mechanism.** A stateless instance can be killed, replaced, cloned or moved without losing anything. That's what makes autoscaling, autohealing, Spot VMs, rolling updates and multi-zone spreading cheap. A stateful instance can't be treated this way without replication, consistency protocols and backups.

**Consequence.** Externalize state:

* Sessions go to Memorystore or Firestore.
* Files go to Cloud Storage or Filestore.
* Relational data goes to Cloud SQL, AlloyDB or Spanner.
* Queues go to Pub/Sub.

Then the compute tier becomes a disposable fleet: a MIG, GKE Deployments or Cloud Run.

**How it appears.** "The application stores session data on local disk, and users lose their carts when instances scale in." Move sessions to Memorystore; don't add session affinity. "Instances must be replaceable automatically" means MIG autohealing with health checks. "Can we use Spot VMs?" Only for stateless, fault-tolerant or checkpointed work.

**Distractor killed.** Sticky sessions offered as the fix for scale-in data loss; snapshotting stateful VMs as an HA strategy; running a database on a Spot VM.

---

## P4 · Every data store is a fixed point on the consistency–scale–query triangle

**Mechanism.** A database can't simultaneously maximize horizontal scale, strong consistency across regions, low latency and rich ad-hoc queries. Each Google Cloud store picked a point:

| Need | Store | Why it fits |
|---|---|---|
| Relational, OLTP, one region, up to tens of TB, lift-and-shift MySQL/PostgreSQL/SQL Server | **Cloud SQL** | Managed familiar engines; vertical scale and read replicas |
| PostgreSQL-compatible, high performance OLTP plus fast analytics | **AlloyDB for PostgreSQL** | Disaggregated storage, columnar engine, 99.99% SLA |
| Relational, horizontal scale, **strong consistency globally**, up to 99.999% | **Spanner** | TrueTime-based external consistency; multi-region configs |
| Massive throughput, low-latency key/row lookups, time series, IoT, ad-tech | **Bigtable** | Wide-column, single-row transactions, scales linearly with nodes |
| Document data for mobile/web, offline sync, serverless scale | **Firestore** | Document model, real-time listeners, strong consistency |
| Analytics over TB–PB with SQL, serverless | **BigQuery** | Columnar, separated storage and compute; not for OLTP |
| Sub-millisecond cache or session store | **Memorystore** (Valkey, Redis) | In-memory; not a system of record |
| Unstructured objects (media, backups, data lake) | **Cloud Storage** | Object store, 11 nines durability design, storage classes |

**Consequence.** Choose by **access pattern first** (point reads vs scans vs joins vs aggregations), then by **consistency and geography**, then by **scale**, and only then by cost.

**How it appears.**

* "Global inventory, strong consistency, users on three continents" → Spanner.
* "Billions of sensor readings per day, query by device and time range" → Bigtable with a row key of device + reversed timestamp.
* "Analysts run ad-hoc SQL over 5 years of history" → BigQuery.
* "Migrate SQL Server with minimal changes" → Cloud SQL for SQL Server, or Compute Engine with licensing when Cloud SQL's limits block it.

**Distractor killed.** BigQuery for transactional order entry; Bigtable for multi-row ACID transactions or ad-hoc joins; Cloud SQL for multi-region writes; Memorystore as the only copy of data.

---

## P5 · Prefer the most managed service that meets every requirement

**Mechanism.** Every layer you run yourself (OS patching, cluster upgrades, failover scripts, capacity planning) is toil and a source of outages. Google Cloud offers a spectrum, with control increasing to the left and operational burden falling to the right:

```text
More control / more ops ─────────────────────────────────────────── Less ops / less control
Compute Engine VMs → GKE Standard → GKE Autopilot → Cloud Run → Cloud Run functions
Self-managed DB on VM → Cloud SQL / AlloyDB → Spanner (no instance ops) → Firestore
Self-run Kafka/Spark/Airflow → Managed Service for Apache Kafka / Spark / Airflow → Dataflow / BigQuery
Custom ML training → tuning a foundation model → prompting Gemini → prebuilt AI API / Agent Search
```

**Consequence.** The exam's default answer is the most managed option that satisfies every hard constraint. You step left only when a requirement forces it: a kernel module, a licensed OS, GPUs with special drivers, a protocol a managed service doesn't support, or "no code changes" for a lift-and-shift.

**How it appears.** The qualifiers "minimize operational overhead", "small operations team", "Google-recommended practice" and "reduce infrastructure administration costs" (an EHR business requirement). Hidden constraints that force you left include "requires root access", "custom kernel", "bring your own license tied to physical cores" and "must keep using existing Kubernetes manifests and Helm charts".

**Distractor killed.** Hand-built solutions such as cron jobs on a VM, custom failover scripts or self-managed Kafka when a managed service does the same thing. Also killed: the *over*-managed option that breaks a hard constraint, such as Cloud Run for a workload that needs a privileged container.

---

## P6 · Identity is the primary perimeter; the network is defense in depth

**Mechanism.** Every Google Cloud API call is authenticated (who: a user, group, service account or federated identity) and authorized by IAM (may this principal perform this permission on this resource?). Network location alone grants nothing to Google APIs. **VPC Service Controls** adds a second, context-based perimeter around Google-managed services: even a valid credential can't move data out of the perimeter.

**Consequence.**

* Grant roles to **groups**, not individuals.
* Use **predefined or custom roles**, never basic roles (Owner/Editor/Viewer) in production.
* Give workloads their own **service accounts** with minimal roles.
* Eliminate long-lived keys: use attached service accounts on Google Cloud, **Workload Identity Federation** for on-premises, other clouds and CI systems, and **Workload Identity Federation for GKE** for pods.
* Use **service account impersonation** for humans who need elevated access temporarily.
* Add VPC Service Controls when the threat is **data exfiltration** by an authorized-but-malicious or compromised identity.

**How it appears.** "A CI pipeline in GitHub Actions must deploy without stored keys" → Workload Identity Federation. "Prevent copying BigQuery data to a personal project even by someone with access" → VPC Service Controls perimeter. "Admins need SSH to VMs without public IPs or VPN" → IAP TCP forwarding.

**Distractor killed.** Downloading service account JSON keys; firewall rules as protection for Google APIs (firewalls don't govern API access); granting Editor "to unblock the team".

---

## P7 · Hierarchy and inheritance: policies flow down, so design the tree first

**Mechanism.** Resources form a tree: **Organization → Folders → Projects → resources**. Policies attached at a node are inherited by everything below:

* **IAM allow policies are additive.** A role granted at a folder applies to every project in it, and a lower level can't revoke it.
* **IAM deny policies** override allows for the listed permissions.
* **Principal access boundary (PAB) policies** cap which resources a principal can reach at all.
* **Organization policies** (constraints) restrict *what can be configured*, for example allowed regions, no external IPs or no service account key creation. They are inherited, and lower levels can be allowed to override them.
* **Hierarchical firewall policies** apply network rules at the org or folder level before VPC rules.

A **project** is the boundary for billing attribution, quotas, API enablement and most IAM grants.

**Consequence.** Design the hierarchy around **policy and ownership boundaries**, usually by environment (prod / non-prod) and business unit. Then grant at the highest node where the grant is correct for everything below, and constrain with org policies. Use **separate projects** to isolate workloads, environments and teams. They're free.

**How it appears.**

* "Ensure no resources are ever created outside the EU" → org policy `gcp.resourceLocations` at the org or folder.
* "The security team needs read access to all current and future projects" → grant at the org node to a group.
* "Prevent any project from creating external IPs on VMs" → org policy `compute.vmExternalIpAccess`.
* "Developers have Editor on a folder, but must never delete production Cloud SQL instances" → an IAM deny policy.

**Distractor killed.** Granting roles project by project when a folder-level grant is correct; trying to "remove" an inherited allow at the project level (impossible without a deny policy); one giant project for everything.

---

## P8 · Decouple with asynchrony: queues absorb spikes and isolate failures

**Mechanism.** In a synchronous chain, the slowest or least available component sets throughput and availability for the whole chain (P2). Placing a durable message buffer between producer and consumer (**Pub/Sub**, or Cloud Tasks for explicit per-task dispatch) lets each side scale and fail independently. Pub/Sub delivers **at least once** by default, so consumers must be **idempotent**, or you enable exactly-once delivery, available for pull subscriptions within one region.

**Consequence.**

* Spiky ingestion goes into Pub/Sub, then to autoscaling consumers (Dataflow, Cloud Run, GKE).
* Integrations with partners become events or files landing in a bucket, which trigger processing.
* Workflows with steps and retries use **Workflows** or Managed Service for Apache Airflow for orchestration, or **Eventarc** for event routing.

**How it appears.** "The order service fails when the email provider is slow" → publish an event and send email asynchronously. "Ingest telemetry from millions of vehicles with unpredictable bursts" → Pub/Sub, Dataflow, then Bigtable or BigQuery. "Onboard new insurance providers quickly" (EHR) → standard ingestion interfaces, such as an API through Apigee or a file drop into Cloud Storage, triggering pipelines.

**Distractor killed.** Scaling the synchronous chain vertically; point-to-point integrations for every partner; assuming exactly-once delivery without idempotent consumers.

---

## P9 · Cost follows the shape of usage: match the pricing model to the load curve

**Mechanism.** You pay for provisioned capacity (VMs, nodes, instances), consumed capacity (requests, vCPU-seconds, bytes scanned or stored) and data movement (egress between regions or to the internet). Google's pricing levers:

| Load shape | Lever |
|---|---|
| Steady, predictable 24×7 | **Committed use discounts**: resource-based (specific vCPU and memory in a region, 1 or 3 years) or spend-based/flexible (dollar commitment across services) |
| Interruptible, fault-tolerant, batch | **Spot VMs**: large discount, can be preempted at any time with about 30 seconds' notice |
| Spiky or idle much of the time | **Scale to zero**: Cloud Run, Cloud Run functions, GKE Autopilot pods, BigQuery on-demand |
| Unknown or over-provisioned | **Rightsizing recommendations** (Recommender, Active Assist) and custom machine types |
| Data accessed rarely | **Cloud Storage classes** (Standard → Nearline 30 d → Coldline 90 d → Archive 365 d minimum storage), lifecycle rules, **Autoclass** |
| Analytics | BigQuery **editions** with autoscaling slots vs **on-demand** per-TB; partitioning and clustering to cut bytes scanned |

**Consequence.** Cost-optimal answers usually **combine** levers: a CUD for the baseline, autoscaling on-demand for peaks and Spot for batch. Egress is often the hidden cost: keep chatty components in the same region and serve static content through Cloud CDN.

**How it appears.** "Optimize cloud storage costs for growing media volumes" (Altostrat) → lifecycle rules or Autoclass to colder classes, keeping hot content in Standard. "Nightly batch that can be restarted" → Spot VMs, or managed Spark with secondary Spot workers. "Steady-state production for 3 years" → 3-year CUD.

**Distractor killed.** CUDs for spiky or short-lived workloads; Spot for stateful databases or SLA-bound serving; Archive class for data read weekly (retrieval fees and the 365-day minimum make it more expensive).

---

## P10 · Data has gravity, a lifecycle and a legal home

**Mechanism.** Moving data costs time (size ÷ bandwidth) and money (egress). Rule-of-thumb transfer times at full, sustained utilization:

| Data | 100 Mbps | 1 Gbps | 10 Gbps |
|---|---|---|---|
| 1 TB | ~1 day | ~2.5 h | ~15 min |
| 10 TB | ~10 days | ~1 day | ~2.5 h |
| 100 TB | ~100 days | ~10 days | ~1 day |
| 1 PB | years | ~100 days | ~10 days |

Data also has a **lifecycle** (hot, then warm, then cold, then deleted) and often a **legal location**: residency, sovereignty, retention mandates and litigation holds.

**Consequence.**

* Move compute to the data, not data to the compute.
* For bulk one-time moves where the network would take more than about a week, ship a **Transfer Appliance**.
* For online transfers, use **Storage Transfer Service** (from other clouds, HTTP sources or on-premises file systems with agents).
* Use **BigQuery Data Transfer Service** for SaaS and warehouse sources, and **Datastream** for database change data capture.
* Encode retention in configuration: Cloud Storage retention policies and Bucket Lock, object holds, lifecycle rules, log bucket retention.
* Pin location with org policy (`gcp.resourceLocations`), regional resources and, where required, **Assured Workloads**.

**How it appears.** "Migrate 500 TB from a data center with a 1 Gbps link within 3 weeks" → Transfer Appliance. "Replicate an on-premises MySQL database continuously with minimal downtime" → Database Migration Service using CDC. "Health records must remain in the EU" → regional resources in EU regions, a resource-location org policy, and possibly Assured Workloads with data-residency controls.

**Distractor killed.** `gsutil cp` or `gcloud storage cp` over a thin link for hundreds of TB; one-time dump-and-restore when "minimal downtime" is required; multi-region buckets in the US for data that must stay in the EU.

---

## P11 · Encryption is default; key custody is the real decision

**Mechanism.** All data at rest in Google Cloud is encrypted by default with Google-managed keys, and data in transit between Google's facilities is encrypted. The architect's decision is **who controls the key-encryption key, and where it lives**:

| Option | Who holds the key | Use when |
|---|---|---|
| Google default encryption | Google | No specific requirement |
| **CMEK** (Cloud KMS software keys) | You manage the key in Cloud KMS: rotation, disable/destroy (crypto-shredding), IAM on key use | Compliance requires customer control, rotation or revocation |
| CMEK with **Cloud HSM** | You, in FIPS 140-2 Level 3 HSMs run by Google | Regulation demands HSM-backed keys |
| **Cloud EKM** | You, in an external key manager outside Google | Keys must never be in Google's possession (sovereignty) |
| **CSEK** (customer-supplied) | You supply the raw key with each request (Cloud Storage and Compute Engine only) | Legacy; rarely the best answer today |

**Cloud KMS Autokey** creates and assigns CMEK keys automatically as resources are created. **Secret Manager** stores API keys, passwords and certificates with versioning, IAM and rotation. **Sensitive Data Protection** discovers, classifies and de-identifies sensitive data (masking, tokenization, format-preserving encryption).

**Consequence.** Default encryption is already "encrypted at rest". Pick CMEK, HSM or EKM only for an explicit custody requirement, because each adds operational duty and an availability dependency: if the key is unavailable, the data is too.

**How it appears.** "The company must be able to revoke access to all data instantly" → CMEK, then disable the key. "Keys must be stored outside Google Cloud" → Cloud EKM. "Remove credit card numbers from support transcripts before analytics" → Sensitive Data Protection de-identification.

**Distractor killed.** Building your own encryption in the application when CMEK meets the need; storing secrets in environment variables, source code or instance metadata; picking CSEK when CMEK suffices.

---

## P12 · Everything as code, immutable artifacts and progressive delivery

**Mechanism.** Configuration done by hand drifts and can't be reviewed, tested or reproduced. Declarative infrastructure as code (Terraform, Infrastructure Manager, Config Connector) plus CI/CD (Cloud Build, Cloud Deploy, GitHub Actions or GitLab with Workload Identity Federation) turns change into a reviewed, versioned, repeatable event. Build an **immutable** artifact once (container image in Artifact Registry, or VM image), promote the same artifact through environments, and release it **progressively**: canary, blue/green or rolling, with automated rollback.

**Consequence.**

* Infrastructure changes go through pull requests.
* Images are signed and verified (Binary Authorization).
* Releases are gradual and observable.
* Rollback means redeploying the previous artifact, not patching in place.

**How it appears.** "Many outages are caused by misconfigured systems" (EHR executive statement) → IaC, policy as code and automated testing. "Modernize CI/CD for containerized deployments with a centralized management platform" (Altostrat) → Cloud Build, Artifact Registry, Cloud Deploy, GKE fleet management with Config Sync. "Roll out to 5% of users first" → canary with Cloud Deploy, or traffic splitting in Cloud Run or the load balancer.

**Distractor killed.** SSH-ing into servers to update them; building different artifacts per environment; big-bang releases.

---

## P13 · You can't operate what you can't observe: SLOs drive alerts, and alerts drive action

**Mechanism.** Reliability is defined from the user's point of view:

* **SLI:** a measured ratio, for example good requests ÷ valid requests.
* **SLO:** the target for an SLI over a window, for example 99.9% over 30 days.
* **Error budget:** 1 − SLO. It's the allowed unreliability, which you spend on releases and experiments.

**Google Cloud Observability** covers the signals: Cloud Monitoring (metrics, uptime checks, SLOs, alerting), Cloud Logging (log routing, log buckets, Log Analytics), Cloud Trace, Cloud Profiler, Error Reporting and Managed Service for Prometheus. Alerts should fire on **symptoms that hurt users** (SLO burn rate), not on every cause (CPU 80%), and should route to a channel a human will act on.

**Consequence.**

* Centralize logs and metrics across projects: a log sink to a central bucket, and a metrics scope.
* Define SLOs for customer-facing services and alert on burn rate.
* Route notifications to an on-call tool, not to a mailbox nobody reads.
* Keep audit logs for the required retention.

**How it appears.** EHR: "alerts are sent via email and are often ignored" plus "centralized visibility and proactive action" → Cloud Monitoring with SLO burn-rate alerting routed to an incident-management channel (PagerDuty, Slack, Pub/Sub), dashboards, centralized logging. Altostrat: "Prometheus plus email alerts" → Managed Service for Prometheus, with alerting routed beyond email.

**Distractor killed.** More email alerts; alerting on every metric threshold; exporting logs to VMs running a self-managed stack when native services meet the need.

---

## P14 · Private by default: no public IPs, reach Google services privately, and size hybrid links to the need

**Mechanism.** A workload needs three kinds of connectivity: to **Google APIs**, to **the internet**, and to **other networks** (on-premises, other VPCs, other clouds).

| Need | Mechanism |
|---|---|
| VMs without external IPs reach Google APIs | **Private Google Access** on the subnet |
| Consume a managed service or a producer's service via a private IP in your VPC | **Private Service Connect** (PSC) endpoint |
| On-premises hosts reach Google APIs privately | PSC endpoint or private.googleapis.com / restricted.googleapis.com VIPs over Interconnect or VPN |
| Outbound internet without inbound exposure | **Cloud NAT** |
| Admin access to VMs without public IPs or bastions | **IAP TCP forwarding** |
| Connect VPCs, same organization, central network team | **Shared VPC** (one host project, many service projects) |
| Connect VPCs, different organizations or peers | **VPC Network Peering** (non-transitive) or PSC (service-oriented) |
| Hub-and-spoke across many VPCs and on-premises sites | **Network Connectivity Center** |
| Hybrid link, encrypted over the internet, quick to set up | **HA VPN** (99.99% SLA with two interfaces; about 3 Gbps per tunnel) |
| Hybrid link, high bandwidth, private, low latency | **Dedicated Interconnect** (10 / 100 / 400 Gbps circuits) or **Partner Interconnect** (50 Mbps to 50 Gbps attachments, via a provider) |
| Link to AWS, Azure, OCI or Alibaba | **Cross-Cloud Interconnect** |

**Consequence.** The default design has no public IPs on VMs: Private Google Access, Cloud NAT for egress, IAP for administration, and load balancers as the only public entry points, protected by Cloud Armor. Choose hybrid connectivity by **bandwidth, SLA, lead time and encryption need**. You can run HA VPN *over* Interconnect, or use MACsec, when traffic must be encrypted on the private link.

**How it appears.** "Secure, high-performance connection between on-premises and Google Cloud" (EHR, Altostrat) → Dedicated or Partner Interconnect sized to the need, with HA VPN as a backup or interim link. "Need connectivity next week, 500 Mbps, encrypted" → HA VPN. "Partner company must consume our API privately without network peering" → Private Service Connect.

**Distractor killed.** Public IPs plus firewall rules for administration; VPN for a sustained 20 Gbps requirement; peering when transitive routing is needed (peering is non-transitive); a single Interconnect connection for a 99.99% requirement.

---

## P15 · Migration is risk management: assess, move in safe steps and modernize when the clock allows

**Mechanism.** Google's migration framework runs **Assess → Plan → Deploy → Optimize**:

* **Assess:** discovery with **Migration Center** (inventory, dependencies, TCO and rightsizing).
* **Plan:** landing zone, identity, network, and migration waves grouped by dependency.
* **Deploy:** move with the right tool.
* **Optimize:** rightsize, modernize, automate.

Strategies per workload, from fastest to most transformative:

1. **Rehost** (lift and shift)
2. **Replatform** (lift and optimize)
3. **Refactor** (move and improve)
4. **Rearchitect or rebuild** (remove and replace)
5. **Repurchase** (SaaS)
6. **Retire**
7. **Retain**

The exam guide calls the last part *workload disposition*: build, buy, modify or deprecate.

**Consequence.**

* A hard deadline (a lease expiry or contract end) favors **rehost first, modernize later**.
* Systems "scheduled to be replaced" are **retained** and connected, not migrated (EHR's legacy insurance integrations).
* Data migrations that need minimal downtime use **continuous replication** (Database Migration Service, Datastream, storage sync), then a short cutover.
* Every wave needs testing and a rollback plan.

Tools:

| Moving | Tool |
|---|---|
| VMs (VMware, AWS, Azure, physical) | Migrate to Virtual Machines |
| VMware environment as-is | **Google Cloud VMware Engine** |
| VMs to containers | Migrate to Containers |
| Databases | Database Migration Service (MySQL, PostgreSQL, SQL Server, Oracle to PostgreSQL/AlloyDB) |
| Files and objects | Storage Transfer Service, Transfer Appliance |
| Data warehouses | BigQuery Migration Service |

**How it appears.** "The data center lease expires in four months" → rehost with Migrate to VMs, or keep containers as they are on GKE. "No plan to upgrade or move these systems at the current time" → leave them on-premises and provide hybrid connectivity. "Minimize downtime during database migration" → DMS continuous migration.

**Distractor killed.** Rewriting everything before the lease expires; migrating systems the business said will stay; big-bang cutovers with no rollback.

---

## P16 · AI is a system, not a model: pick the highest abstraction, ground it, guard it and measure it

**Mechanism.** A production generative-AI solution is a pipeline:

```text
data → retrieval/grounding → model → safety/guardrails → human review → evaluation → monitoring
```

Abstractions, from least to most effort:

1. **A prebuilt API or product:** Vision, Speech-to-Text, Translation, Video Intelligence, Document AI, Agent Search (formerly Vertex AI Search), Agent Search for Commerce, Gemini Enterprise.
2. **Prompting a foundation model:** Gemini on Agent Platform, or a Model Garden model.
3. **Grounding with your data:** RAG Engine, Agent Search, Vector Search, grounding with Google Search.
4. **Tuning:** supervised fine-tuning or parameter-efficient tuning on your labeled data.
5. **Custom training:** on Agent Platform Managed Training or AI Hypercomputer (GPUs/TPUs).

Agents add tools and orchestration: the Agent Development Kit (ADK), Agent Runtime (formerly Agent Engine), and Agent Studio (formerly Vertex AI Studio). Security for AI adds:

* **Model Armor:** screens prompts and responses for prompt injection, jailbreaks, harmful content and sensitive data.
* **Sensitive Data Protection:** de-identifies training data and outputs.
* Controls on the workload itself: IAM, VPC Service Controls and CMEK.

**Consequence.** Start at the highest abstraction that meets the requirement, and descend only when accuracy, domain specificity, cost or latency forces you to. Ground generative answers in authoritative data to reduce hallucination. Put **human-in-the-loop** review where errors are costly. Make outputs **auditable and explainable**: log prompts and responses, evaluate with the Gen AI evaluation service, and use model evaluation and explanations.

**How it appears.**

* Cymbal: "generate product attributes and descriptions from supplier data, with associate review before publishing" → Gemini multimodal prompting with a HITL approval UI.
* Cymbal: "natural-language product discovery" → Agent Search for Commerce (formerly Vertex AI Search for commerce / Discovery AI).
* Altostrat: "detect and filter inappropriate content" → Gemini safety filters plus Model Armor, or video/image moderation through the Video Intelligence and Vision APIs.
* "Answer employee questions from internal documents" → Gemini Enterprise or Agent Search over the documents.

**Distractor killed.** Training a custom model from scratch when a foundation model or API does the job; fine-tuning when the real problem is missing context (use RAG); shipping gen-AI output straight to customers with no guardrails or review when the case study demands accuracy or safety.

---

## How to use the principles in the exam: the five-step procedure

1. **Extract the constraints.** List hard requirements (must, minimum, cannot, regulation, deadline) and soft qualifiers (cost, ops, speed).
2. **Name the governing principle.** "Survive a zone failure" is P1/P2; "no keys" is P6; "lease expires" is P15; "spiky" is P8/P9.
3. **Derive the mechanism** before reading the options. Say it in your head: "a regional MIG behind a global load balancer with Cloud SQL HA".
4. **Eliminate** every option that violates a hard constraint or a principle.
5. **Break ties with the qualifier.** Among the survivors, pick the most managed (P5), the cheapest that meets the SLA (P9), or the most secure, as the qualifier asks.

[03-decoding-questions-and-elimination.md](03-decoding-questions-and-elimination.md) applies this procedure to worked examples.
