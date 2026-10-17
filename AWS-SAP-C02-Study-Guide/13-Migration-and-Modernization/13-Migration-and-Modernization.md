# Chapter 13 — Migration & Modernization (Domain 4)

> **Exam mapping:** D4 Task 4.1 (select existing workloads and processes for potential migration), D4 Task 4.2 (determine the optimal migration approach), D4 Task 4.3 (determine a new architecture for existing workloads), D4 Task 4.4 (determine opportunities for modernization and enhancements) | **Weight signal:** High (Domain 4 = 20% ≈ 13 scored questions; migration also appears inside D1/D2 stems) | **Study time:** ~8 h
> [← Previous](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md) · [Index](../00-README-Start-Here.md) · [Next →](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md)

---

## 0. Read this first: 2025–2026 service-availability changes vs. what the exam expects

SAP-C02 was written in 2022. Since then AWS has renamed several migration services and closed others to new customers. **Exam questions may use the old names and may expect services that new AWS accounts can no longer sign up for.** On the exam, answer within the question's framing ("the company uses AWS Application Discovery Service…" is still a valid scenario). In real work, use the current replacement.

| Service (exam-era name) | Status as of Oct 2026 (verified on docs.aws.amazon.com) | Current replacement / note |
|---|---|---|
| AWS Application Migration Service (MGN) | **Renamed AWS Transform MGN** (8 June 2026). Same APIs and replication engine. | Same service. Exam says "AWS Application Migration Service" or "AWS MGN". |
| AWS Server Migration Service (SMS) | **Retired** | MGN (Transform MGN) |
| CloudEndure Migration | Retired (became MGN) | MGN |
| AWS Migration Hub (incl. Strategy Recommendations, Orchestrator, Journeys, EC2 recommendations) | **Closed to new customers 7 Nov 2025**; existing customers continue, no new features | **AWS Transform** |
| AWS Migration Hub Refactor Spaces | Closed to new customers 7 Nov 2025 | AWS Transform |
| AWS Application Discovery Service (Agent + Agentless Collector) | Closed to new customers 7 Nov 2025 | AWS Transform discovery/assessment |
| AWS DMS Fleet Advisor | Closed to new customers 20 May 2025; **end of support 20 May 2026** | Migration Evaluator / AWS Transform |
| AWS App2Container, Porting Assistant for .NET, Microservice Extractor for .NET | Closed to new customers 7 Nov 2025 | AWS Transform for .NET |
| AWS Snow Family (Snowball Edge) | **Not available to new customers from 7 Nov 2025**; Snowcone and older Snowball models discontinued Nov 2024; Snowmobile retired | DataSync (online), **AWS Data Transfer Terminal** (physical), partner solutions; Outposts for edge |
| Amazon FSx File Gateway | Closed to new customers 28 Oct 2024 | Direct FSx access over DX/VPN, or S3 File Gateway where appropriate |
| AWS Mainframe Modernization – Managed Runtime experience | Closed to new customers 7 Nov 2025 | Self-managed experience (also now closed to new customers; see §2.11), vendor-direct offerings, **AWS Transform for mainframe** |
| VMware Cloud on AWS | Still operating, but **sold only by Broadcom** since 30 Apr 2024 | Also consider **Amazon Elastic VMware Service (EVS)**, GA Aug 2025 |
| Migration Evaluator | Available. AWS added agentic TCO/assessment capabilities to AWS Transform in May 2026 | Either one for the business case |
| AWS App Runner (modernization target) | Closed to new customers 30 Apr 2026 | ECS on Fargate |

> **Exam rule of thumb:** if the stem names a legacy service, it is a valid answer. If two answers differ only by old vs new name (rare), they mean the same thing. **Never choose SMS over MGN** for a new rehost; SMS is the classic "retired" distractor.

---

## 1. What the exam really tests here

Domain 4 is about **judgement under constraints**, not memorising tool features. A typical stem gives you a portfolio (hundreds of VMs, a few big databases, a mainframe, file shares, a COTS app), a **deadline** (data-center lease ends, hardware end of support), a **skills profile** (small team, no container skills), **licensing** facts (SQL Server Enterprise with Software Assurance), and a **downtime budget** (cutover window of 2 hours on a Sunday). You must:

| Skill | What the exam asks you to do |
|---|---|
| **4.1 Select workloads** | Run portfolio discovery; collect utilization and dependencies; build a business case/TCO; rank applications by complexity and value; spot **zombie/idle apps to retire** and **apps to retain**; group by dependency into **waves**. |
| **4.2 Migration approach** | Pick the **R** per application; pick the **tool** per source (MGN for servers, DMS for databases, DataSync for files, offline transfer for huge data on thin pipes); design **replication + cutover + rollback**; size bandwidth; ensure the **landing zone** exists first; handle licensing (BYOL, Dedicated Hosts). |
| **4.3 New architecture** | Choose target compute (EC2, containers, serverless), storage (EBS/EFS/FSx/S3), and database (RDS/Aurora/DynamoDB/purpose-built) given the constraints; design for HA and security from day one. |
| **4.4 Modernization** | Identify **post-migration** improvements: managed services to remove ops toil, Windows/SQL Server licence exit, containers, serverless, event-driven decoupling, **strangler-fig** decomposition, purpose-built databases, rightsizing and Savings Plans. |

The recurring decision patterns:
1. **"Fastest / deadline / minimal change"** → rehost (MGN) or relocate (VMware) now, modernize later.
2. **"Reduce operational overhead"** → replatform to managed (RDS/Aurora, Elastic Beanstalk, Fargate, FSx).
3. **"Minimal downtime database migration"** → DMS **full load + CDC**, cut over when lag ≈ 0.
4. **"Heterogeneous engine change"** → schema conversion (SCT / DMS Schema Conversion) **then** DMS for data.
5. **"Hundreds of TB over a slow link with a deadline"** → do the bandwidth math → offline transfer (Snowball Edge in exam-world; Data Transfer Terminal today) + online sync of the delta.
6. **"Dependency mapping / which servers talk to each other"** → Discovery **Agent** (not agentless collector) or equivalent.
7. **"Exit expensive licences"** → SQL Server → Aurora PostgreSQL (Babelfish), .NET Framework → .NET on Linux, Oracle → PostgreSQL.

---

## 2. Core concepts & services — deep dive

### 2.1 Migration methodology

#### The three migration phases (AWS's large-migration method and MAP)

```text
 ASSESS                    MOBILIZE                          MIGRATE & MODERNIZE
 (weeks)                   (1-3+ months)                     (months-years, in waves)
 ─────────────────────     ───────────────────────────────   ─────────────────────────────────
 • Business case / TCO     • Landing zone (Control Tower,    • Wave execution: replicate →
 • Migration Readiness       accounts, network, IAM, logs)     test → cutover → hypercare
   Assessment (MRA)        • Detailed discovery & dependency • Migration factory (repeatable,
 • High-level discovery      mapping                           automated runbooks)
   (inventory, utilization)• Portfolio analysis → 7R per app • Decommission source
 • Directional 7R          • Wave plan, pilot migrations     • Optimize: rightsizing, SP/RI,
 • Executive sponsorship   • Skills/CCoE, operating model,     modernization backlog
                             security & compliance baseline
```

- **Migration Acceleration Program (MAP):** AWS's programme built on the same three phases. Provides methodology, tooling, partner support and **credits/funding** that offset migration costs. Exam signal: "the company wants AWS funding/incentives and a proven methodology for a large migration" → MAP.
- **Pilot first:** in Mobilize, migrate 2–5 low-risk apps end to end to prove the landing zone, tooling, runbooks and operating model before scaling.

#### AWS Cloud Adoption Framework (AWS CAF)

CAF organises the organisational capabilities needed for cloud transformation into **six perspectives**:

| Perspective | Owner (typical) | Focus examples |
|---|---|---|
| **Business** | CEO/CFO/strategy | Business case, portfolio management, product management, data monetisation |
| **People** | CHRO/HR, leaders | Culture, skills/training, organisational design, change management |
| **Governance** | CFO/CIO, PMO | Program/project management, benefits tracking, risk, cloud financial management |
| **Platform** | CTO, architects | Landing zone, architecture standards, CI/CD, data engineering |
| **Security** | CISO | IAM, detective controls, data protection, incident response |
| **Operations** | IT ops/SRE | Observability, incident/problem/change management, patching, capacity |

Business/People/Governance = business capabilities; Platform/Security/Operations = technical capabilities. CAF frames the journey as **Envision → Align → Launch → Scale** across four transformation domains (Technology, Process, Organization, Product).

#### Migration Readiness Assessment (MRA)

A structured, workshop-based assessment (run by AWS or a partner) that scores readiness **across the CAF perspectives** (e.g. landing zone, security, operations, skills, business case, migration process). Output: heat map of gaps + an action plan for the Mobilize phase. Exam signal: "Before committing to a large migration the CIO wants to identify organisational and technical gaps" → MRA.

#### Business case and TCO

| Tool | What it does | When |
|---|---|---|
| **Migration Evaluator** (formerly TSO Logic) | Free service. Agentless collector (or imports from RVTools/CMDB/other tools) gathers on-prem compute inventory and utilization; produces a **data-driven TCO and business case** with right-sized EC2 recommendations and licensing analysis (e.g. Windows/SQL Server BYOL vs License Included). Output: "Quick Insights" report. | Assess phase, executive business case, "projected cost of running in AWS based on actual utilization" |
| **AWS Pricing Calculator** | Manual estimate of target architecture | Detailed design costing |
| **AWS Transform (assessment)** *(emerging)* | Agentic assessment with TCO, what-if scenarios, inputs from RVTools/CMDB/third-party discovery (May 2026) | New-account equivalent |

Business-case components to remember: on-prem costs (hardware refresh, facilities, power, licences, staff), migration costs (dual running, tooling, partners, training), AWS run costs (rightsized, with Savings Plans), and **non-cost benefits** (agility, resilience, staff productivity, sustainability).

#### Landing zone readiness (link: [Chapter 02](../02-Multi-Account-Governance/02-Multi-Account-Governance.md))

**Nothing migrates until the landing zone exists.** Minimum before wave 1: multi-account structure (AWS Organizations / Control Tower), SCPs and guardrails, IAM Identity Center federation, centralised logging (CloudTrail org trail, Config), network (Transit Gateway, DX/VPN, IP plan that doesn't overlap on-prem, Route 53 Resolver hybrid DNS), security baseline (GuardDuty, Security Hub, KMS keys), backup policy, tagging standard, and account vending for migration-wave accounts. Exam trap: answers that start replicating servers before connectivity/identity/logging exist are wrong when the stem emphasises governance.

---

### 2.2 Discovery and planning tools

#### AWS Application Discovery Service (ADS)

Collects configuration, utilization and dependency data about on-prem servers and databases. Data is stored in your **Migration Hub home Region** (must be set first) and can be viewed in Migration Hub or exported (CSV, **Amazon Athena** data exploration, QuickSight).

| | **Agentless Collector** (OVA in VMware vCenter) | **Discovery Agent** (installed on each server) |
|---|---|---|
| Server types | **VMware VMs only** | VMware VMs **and physical servers** (and other hypervisors/clouds), Windows + Linux |
| Deployment | One appliance per vCenter | Per server |
| Static config (hostname, IP, MAC, disks) | Yes | Yes |
| Utilization (CPU, RAM, disk I/O) | Yes (avg/peak; ~60-min interval) | Yes, **time-series (~15-second interval)** |
| Network connections (TCP) | Yes (visualisation in Migration Hub) | Yes |
| **Running processes** | **No** (cannot "look inside" the VM) | **Yes** |
| Export network data to **Athena** / CSV | **No** | **Yes** |
| Export time-series utilization | No | Yes |
| Database discovery (Oracle, SQL Server, MySQL, PostgreSQL schemas, complexity) | **Yes** (database & analytics module via AD LDAP) | No |

Other inputs: **file-based import** (Migration Hub import template), **RVTools export**, partner discovery tools writing via the ADS API. The older Discovery Connector stopped ingesting data in Nov 2025 (use Agentless Collector).

> **Exam signals:** "physical servers" or "running processes" or "detailed dependency analysis in Athena" → **Discovery Agent**. "VMware, cannot install agents, need inventory + utilization quickly" → **Agentless Collector**. Both can run together on VMware.

#### AWS Migration Hub (legacy — closed to new customers Nov 2025)

- **Single pane of glass** to **track** migration status across tools (MGN, DMS, partner tools) per server and per application. Uses a **home Region** for all discovery/tracking data (you can migrate to any Region).
- **Grouping** discovered servers into **applications**.
- **Strategy Recommendations:** analyses discovered servers (plus optional source-code/database analysis) and recommends a 7R strategy and target (e.g. rehost to EC2, replatform to containers, move off SQL Server).
- **EC2 instance recommendations:** right-sized instance types from discovery data.
- **Migration Hub Orchestrator:** workflow templates that automate steps for rehosting with MGN, migrating SAP NetWeaver/HANA, SQL Server to EC2/RDS, etc.
- **Journeys:** guided, collaborative migration project templates.
- **Refactor Spaces:** managed strangler-fig infrastructure (API Gateway, NLB, Transit Gateway, multi-account environment) to route traffic incrementally from a monolith to new microservices.

All of these capabilities are now offered through **AWS Transform**; existing Migration Hub customers can finish in-flight projects.

#### AWS Transform *(emerging — GA May 2025; appears rarely if at all on SAP-C02)*

An **agentic AI** migration and modernization service. Capabilities relevant here:
- **VMware migration:** discovery/assessment (RVTools, collectors), dependency analysis, wave planning, network configuration conversion (VPCs, subnets, security groups), then rehost via **Transform MGN** or containerization.
- **.NET:** ports .NET Framework apps to cross-platform .NET (running on **Linux**), including newer full-stack Windows transformations (application, UI framework, SQL Server database, deployment).
- **Mainframe:** code analysis, documentation, decomposition, and **refactoring COBOL to Java** (successor tooling to AWS Blu Age).
- **Assessment/TCO** and **custom transformations** (e.g. Java version upgrades).

> On SAP-C02, use MGN/ADS/Migration Hub/Blu Age language. Mention Transform only if offered.

---

### 2.3 The 7 Rs — definition, when to use, examples, exam signals

Verified against AWS Prescriptive Guidance (Large Migration Guide). **Common in large migrations: rehost, replatform, relocate, retire. Refactor is the most complex and costly — AWS recommends migrate first, modernize after.**

| R | What it is | When to use | Examples | Exam signals |
|---|---|---|---|---|
| **Retire** | Decommission/archive | No business value; zombie apps (avg CPU+memory < 5%), idle apps (5–20% over 90 days); no inbound connections in 90 days; unsupported OS risk | Old reporting server nobody uses; duplicate apps after M&A | "Utilization data shows… no connections", "reduce migration scope and cost" |
| **Retain** | Keep on-prem for now (revisit later) | Data residency/compliance; high risk needing deep assessment; recently upgraded hardware; dependency on special hardware; mainframe/mid-range (AS/400, Solaris SPARC) not yet planned; waiting for vendor SaaS | Plant-floor control system tied to machines; app on new hardware bought last year | "must remain on premises", "regulatory", "recently invested", "no cloud equivalent hardware" |
| **Rehost** ("lift and shift") | Move servers as-is to EC2 | Deadlines, large scale, little cloud skill, COTS without vendor support for change | 500 VMware + physical servers to EC2 with MGN | "data center exit in X months", "minimal changes", "quickly", "lift and shift", "least effort" |
| **Relocate** ("hypervisor-level lift and shift") | Move VMs to a cloud version of the same platform without buying hardware or changing apps/operations; also move resources to another VPC/Region/account | Large VMware estate, keep VMware tooling/skills/operations, fastest path | vMotion/HCX VMs to **VMware Cloud on AWS** or **Amazon EVS**; move RDS instance to another account | "keep using vCenter/VMware tools", "no change to operations", "hundreds of VMs in days" |
| **Repurchase** ("drop and shop") | Replace with a different product, usually SaaS | Commodity capability (CRM, HR, email, ITSM); licence model change; custom app replaceable | On-prem CRM → Salesforce; Exchange → Microsoft 365; buy via **AWS Marketplace** | "vendor offers SaaS", "eliminate infrastructure management for a COTS product" |
| **Replatform** ("lift, tinker and shift") | Move with targeted optimisation, no core architecture change | Reduce ops toil/licences while keeping the app largely intact | SQL Server → RDS for SQL Server; Oracle → RDS; Tomcat app → Elastic Beanstalk; VMs → containers (App2Container); file server → FSx; Windows → Linux; x86 → Graviton; RabbitMQ/ActiveMQ → Amazon MQ | "reduce operational overhead without rewriting", "managed database", "minimal code change" |
| **Refactor / re-architect** | Redesign to cloud-native | Strong business need for agility/scale; monolith blocking delivery; mainframe cost/limits; unmaintainable code | Monolith → microservices on ECS/EKS/Lambda; COBOL → Java; Oracle → DynamoDB | "improve agility", "scale independently", "event-driven", "release features faster" and **no tight deadline** |

Effort/cost/time increase roughly: Retire < Retain < Relocate ≈ Rehost < Repurchase ≈ Replatform < Refactor. Long-term benefit generally increases in the same direction (except Retire, which is pure savings).

**Choosing in practice (portfolio heuristics):**
- Start by **removing scope**: identify retire (typically a noticeable slice of an estate) and retain candidates.
- Default the long tail to **rehost/relocate** to hit the deadline.
- **Replatform** where a managed service is low-effort and high-value (databases are the classic target).
- **Refactor** only the few strategic, differentiating apps, and often **after** migration.
- Re-evaluate retained apps every planning cycle.

---

### 2.4 Portfolio prioritization and wave planning

1. **Inventory and enrich**: discovery data + CMDB + interviews (owner, business criticality, RTO/RPO, compliance, licence, OS/DB versions, change freezes).
2. **Map dependencies** (network connections, shared databases, batch jobs, authentication, file shares). Apps that talk at low latency to each other usually move **in the same wave** (a "move group") to avoid cross-WAN chattiness.
3. **Score**: business value vs migration complexity. Early waves = **low complexity, low criticality** (build confidence and the factory); later waves = complex/critical apps.
4. **Assign the R and target** per app.
5. **Build waves**: commonly 2–6 week cycles; each wave moves one or more move groups, respecting change freezes and business calendars.
6. **Migration factory**: standardised, automated runbooks (e.g. **Cloud Migration Factory on AWS** solution orchestrating MGN agent install, replication, launch, and post-launch at scale), with a wave team (migration engineers, app owners, testers).
7. **Track**: Migration Hub (legacy) / AWS Transform / MGN's built-in "applications and waves" grouping.

Wave anti-patterns: splitting tightly coupled apps across waves without a hybrid network plan; migrating the shared database before the apps that depend on it without latency testing; no business sign-off on cutover windows.

---

### 2.5 Rehost deep dive

#### AWS Transform MGN (formerly AWS Application Migration Service, "MGN")

The primary AWS rehost service: **block-level, continuous replication** of physical, virtual (VMware, Hyper-V, etc.) and other-cloud servers into EC2, with automated conversion so they boot natively on AWS. Successor to CloudEndure Migration and SMS.

**How it works:**

```text
 SOURCE ENVIRONMENT                         AWS TARGET ACCOUNT / REGION
 ┌──────────────────────────┐              ┌─────────────────────────────────────────────┐
 │ Source server            │  TCP 443     │  MGN service endpoint (control plane)       │
 │  + AWS Replication Agent ├─────────────►│                                             │
 │  (block-level, continuous│              │  STAGING AREA SUBNET (dedicated, cheap)     │
 │   change capture)        │  TCP 1500    │  ┌───────────────────┐   ┌───────────────┐  │
 │                          ├─────────────►│  │ Replication server│──►│ Staging EBS   │  │
 └──────────────────────────┘ encrypted,   │  │ (t3.small default,│   │ volumes (one  │  │
   (or agentless: MGN vCenter  compressed  │  │ shared or dedic.) │   │ per src disk) │  │
    Client using VMware         over       │  └───────────────────┘   └──────┬────────┘  │
    snapshots + CBT)            Internet/  │        point-in-time EBS snapshots│          │
                                VPN/DX     │                                   ▼          │
                                           │  Conversion server (boot/driver changes)    │
                                           │                                   │          │
                                           │  OPERATIONAL SUBNETS (per launch template)  │
                                           │  ┌─────────────────┐  ┌─────────────────┐   │
                                           │  │ TEST instance   │  │ CUTOVER instance│   │
                                           │  └─────────────────┘  └─────────────────┘   │
                                           └─────────────────────────────────────────────┘
```

Key facts (verified, MGN user guide):
- **Agent install** on each source server (Windows/Linux). It communicates with the **MGN API endpoint over TCP 443** (status, agent updates, metadata) and sends **replicated data to replication servers over TCP 1500** — encrypted (TLS 1.2) and compressed.
- **Agentless option** for VMware vCenter: the **MGN vCenter Client** on a dedicated VM uses VMware snapshots + Changed Block Tracking. Use only when policy prevents agent installs; cutover can take longer because you wait for a fresh snapshot.
- **Staging area subnet**: you specify it in the **replication settings template**; best practice is a **single dedicated subnet** for all waves. Replication servers (lightweight EC2, **default t3.small**, x86 only) and staging **EBS volumes** live here, plus periodic **point-in-time snapshots**. Replication servers are shared across source servers by default; choose a **dedicated replication server** for write-intensive sources. Larger instance types (e.g. m5.large) speed initial sync.
- The staging subnet needs outbound access to the MGN endpoint (443), EC2 endpoint and S3 — via **public IP + IGW**, **NAT gateway**, or **VPC endpoints** (MGN interface endpoint, EC2 endpoint, S3 gateway endpoint) for fully private designs.
- **Data routing**: default = over the internet to the replication server's public IP (still encrypted). **"Use private IP"** routes over existing **VPN, Direct Connect or VPC peering** (it does not create the connection). Optional **bandwidth throttling** per server (Mbps); by default MGN uses all available bandwidth.
- **Launch settings**: each source server gets an **EC2 launch template** (subnet, security groups, instance type, IAM profile, tags) plus MGN launch settings (instance type right-sizing, start instance on launch, copy private IP, transfer server tags, licence BYOL vs License Included, boot mode).
- **Lifecycle**: Not ready → Initial sync → **Ready for testing** → launch **test instance** (non-disruptive; replication continues) → mark **Ready for cutover** → launch **cutover instance** (after final sync; source app quiesced) → **Finalize cutover** (stops replication, cleans staging resources) → **Archive**. You can **revert** a test or cutover launch before finalizing.
- **Post-launch actions** (must be activated at account level; run via **SSM Agent** that MGN installs, using **SSM documents**): predefined actions (e.g. install CloudWatch agent, configure Elastic Disaster Recovery replication, OS conversion, licence/subscription conversion, validation) and **custom actions** (your SSM documents, ordering 1,001–10,000), each configurable to run on **test, cutover, or both**, and optionally **block cutover** if they fail. This is MGN's "move and improve" hook.
- **Applications and waves**: group source servers into applications and waves inside MGN; import/export inventory for bulk operations.
- Targets: EBS (default) or **FSx for NetApp ONTAP** (iSCSI) storage.
- **Pricing**: **2,160 free hours (~90 days) per source server** from agent install; after that, an hourly per-server fee. You always pay for the replication servers, staging EBS/snapshots, and test/cutover EC2/EBS.
- Also used for **cross-Region / cross-AZ** EC2 migrations and other clouds → AWS.
- For **DR** (ongoing, not a migration) use **AWS Elastic Disaster Recovery** (same replication technology; see Ch. 12).

> **Cloud Migration Factory on AWS** (AWS Solution) automates large-scale MGN rehosts: bulk agent installation, prerequisite checks, launching, and wave orchestration from a metadata store — the exam answer for "hundreds of servers per week with automation and minimal manual work".

#### VM Import/Export

- Imports **VM images** (VMware VMDK/OVA, Microsoft VHD/VHDX, raw) from **S3** into **AMIs**, EBS snapshots or instances; also **exports** EC2 instances back to on-prem formats.
- **Point-in-time, offline image** — no continuous replication, so downtime = export + upload + import time. Free (pay for S3/EBS/EC2).
- Use when: a small number of VMs, golden image import, BYOL needing to bring your own OS media (e.g. Windows BYOL images onto Dedicated Hosts), or exporting back out.
- Exam trap: VM Import/Export for "hundreds of servers with minimal downtime" — wrong; that's MGN.

#### AWS Server Migration Service (SMS) — retired

Was agentless, incremental VMware/Hyper-V/Azure VM replication to AMIs. **Retired; use MGN.** Any answer proposing SMS for a new migration is a distractor.

---

### 2.6 Relocate: VMware Cloud on AWS and Amazon EVS

| | **VMware Cloud on AWS** | **Amazon Elastic VMware Service (EVS)** |
|---|---|---|
| What | VMware SDDC (vSphere, vSAN, NSX) on dedicated AWS bare metal, **operated by VMware/Broadcom** | **VMware Cloud Foundation (VCF)** deployed **inside your own Amazon VPC** on EC2 bare metal (i4i.metal at launch), **you manage** VCF |
| Who sells it | **Broadcom only** (AWS stopped reselling 30 Apr 2024) | AWS (GA Aug 2025, limited Regions) |
| Licensing | Subscription from Broadcom | **Bring your own VCF licences** (license portability) |
| Migration tool | **VMware HCX** (bulk migration, live vMotion, L2 extension) | VMware HCX |
| Ops model | Managed SDDC; customer manages workloads | Customer-managed VCF; native VPC networking integration |
| Exam signal | "Keep VMware tooling, minimal retraining, move hundreds of VMs in days, no app changes" | Same intent, newer, self-managed in your VPC (unlikely on SAP-C02) |

Relocate gets you out of the data center fast while preserving vCenter operations; afterwards, workloads can be rehosted/replatformed from the SDDC into native AWS gradually. Relocate does **not** reduce VMware licensing cost — a frequent stakeholder surprise.

---

### 2.7 Replatform targets

| Source | Replatform target | Notes |
|---|---|---|
| Self-managed MySQL/PostgreSQL/MariaDB/Oracle/SQL Server | **Amazon RDS** / **Aurora** | Remove patching, backups, HA plumbing (Multi-AZ). Oracle/SQL Server on RDS = License Included (and BYOL for Oracle; SQL Server RDS is LI only). **RDS Custom** (Oracle, SQL Server) when you need OS/DB access (legacy apps, custom agents). |
| Java/Tomcat, .NET/IIS, Node, Python, PHP, Go, Docker apps | **AWS Elastic Beanstalk** | Managed platform: provisioning, ASG, ELB, patching (managed platform updates), deployments (rolling, immutable, blue/green via CNAME swap). Good for "minimal change, no infra team". |
| Java/.NET apps on VMs | **Containers on ECS/EKS (Fargate)** via **App2Container (A2C)** | A2C analyses running apps (Java on Linux, ASP.NET on Windows), generates Dockerfile, image, ECS task/EKS manifests, CloudFormation and CI/CD pipeline. **Closed to new customers Nov 2025** — today use AWS Transform; exam still names A2C. |
| Windows file servers (SMB, NTFS ACLs, AD) | **Amazon FSx for Windows File Server** | Native SMB, AD integration (AWS Managed Microsoft AD or self-managed AD), DFS namespaces, shadow copies, Multi-AZ. Migrate with **DataSync** (preserves NTFS ACLs/metadata) or Robocopy. |
| NFS/NAS (NetApp) | **FSx for NetApp ONTAP** (SnapMirror for migration), **EFS** (Linux NFS), **FSx for OpenZFS** | ONTAP keeps multi-protocol + SnapMirror; EFS for elastic Linux NFS. |
| Message brokers (ActiveMQ, RabbitMQ) | **Amazon MQ** | Protocol-compatible (JMS, AMQP, MQTT, STOMP, OpenWire) — no code change. SQS/SNS = refactor. |
| Kafka | **Amazon MSK** | Same APIs |
| Hadoop/Spark | **Amazon EMR** | |
| Cron/batch servers | **AWS Batch**, EventBridge Scheduler + Lambda/ECS | Borderline refactor |
| Windows OS | Linux (with .NET port) | Licence savings |
| x86 | **Graviton** | Price-performance; requires ARM-compatible binaries/containers |

---

### 2.8 Repurchase

- Replace with **SaaS** or a newer/cloud version: CRM, HRIS, ITSM, email/collaboration, ERP editions.
- **AWS Marketplace**: buy SaaS/AMI/container products with AWS billing, private offers, and **BYOL** listings; procurement consolidated on the AWS invoice; can count toward commitments (EDP-type agreements, where applicable).
- Work items still exist: **data migration** into the SaaS (vendor tools, AppFlow for SaaS integrations, Transfer Family/S3 exports), **identity federation** (IAM Identity Center/IdP SAML), network/security review, user training.
- Exam signal: "commercial off-the-shelf application; the vendor now offers a SaaS version; the company wants to stop managing infrastructure" → repurchase.

---

### 2.9 Database migration deep dive

#### AWS Database Migration Service (DMS)

**Components:**
```text
 Source endpoint ──► Replication instance (or DMS Serverless) runs TASKS ──► Target endpoint
 (Oracle, SQL Server,      • table mappings (selection + transformation rules)   (RDS/Aurora, Redshift,
  MySQL, PostgreSQL,       • full load / CDC / full load + CDC                    S3, DynamoDB, Kinesis,
  MongoDB, Db2, SAP ASE,   • validation, premigration assessment                  MSK, OpenSearch,
  S3, Azure SQL, ...)      • LOB settings                                         DocumentDB, Neptune, ...)
```

- **Endpoints**: connection definitions for source and target (credentials ideally from **Secrets Manager**, TLS). Source and target can be on-prem, EC2, RDS, or another cloud — **at least one must be on AWS**.
- **Replication instance** ("DMS Standard"): an EC2-based managed instance you size (e.g. C5 for CPU-heavy heterogeneous, R5 for memory-heavy high-throughput CDC). Storage holds logs and cached changes. **Multi-AZ** option recommended for **ongoing replication/CDC** (a failover during full load fails the task; restart from failure point).
- **DMS Serverless**: no instance sizing — you set **min/max DMS Capacity Units (DCU; 1 DCU = 2 GB RAM)**, DMS calculates and provisions capacity, autoscales (not down during full load), pay per DCU-hour used, Multi-AZ optional, starts with 100 GB storage and auto-scales storage. Supports a **subset** of endpoints (MySQL/PostgreSQL/MariaDB/Oracle/SQL Server/Db2/MongoDB/DocumentDB/S3 sources; RDS-family, Redshift, S3, DynamoDB, Kinesis, MSK, OpenSearch, DocumentDB, Neptune targets). Exam signal: "unpredictable volume, avoid capacity planning, least operational overhead" → DMS Serverless.
- **Migration types**:
  - **Full load** — copy existing data; fine when you can stop writes for the duration.
  - **CDC only** — replicate changes from a point in time (e.g. after a native bulk restore or Snowball load). Uses source logs: Oracle LogMiner/Binary Reader (supplemental logging), SQL Server MS-CDC/MS-Replication, MySQL binlog (ROW format), PostgreSQL logical replication slots.
  - **Full load + CDC** — the minimal-downtime pattern: changes during full load are cached and applied, then ongoing CDC keeps target in sync until cutover.
- **Table mappings**: selection rules (include/exclude schemas/tables, row filters) and transformation rules (rename schema/table/column, add columns, change data type).
- **What DMS does NOT migrate**: it creates tables and primary keys only. **Secondary indexes, foreign keys, stored procedures, triggers, users, privileges** must be created by schema tools/native scripts. DMS replicates only limited DDL during CDC. Best practice: drop/delay secondary indexes and disable triggers/FKs for full load, add secondary indexes before CDC phase, enable triggers just before cutover.
- **Validation**: task-level data validation compares source and target rows after full load and during CDC (supported for Oracle, PostgreSQL, MySQL, MariaDB, SQL Server, Aurora, Db2 LUW, Redshift). **Premigration assessments** catch unsupported data types, missing PKs, LOB settings, etc.
- **LOB modes** (verified):
  - **Limited LOB mode** (default) — LOBs truncated at **Max LOB size (default 32 KB)**; fastest; set Max LOB size ≥ largest LOB.
  - **Full LOB mode** — migrates all LOBs regardless of size via lookups; slow.
  - **Inline LOB mode** — Full LOB mode with `InlineLobMaxSize`: small LOBs sent inline, large ones looked up. Best when most LOBs are small.
  - Per-table LOB settings override task settings. PostgreSQL JSON is treated as LOB (watch truncation).
- **Performance**: parallel load of multiple tables (`MaxFullLoadSubTasks`, default 8), **parallel-load** of partitions/ranges within a large table, multiple tasks split by row filters, batch-optimized apply for CDC, turn off target backups/Multi-AZ until cutover.
- **Homogeneous vs heterogeneous**:
  - Homogeneous (same engine): native tools are often faster/fuller fidelity; DMS useful for CDC/minimal downtime. **DMS homogeneous data migrations** (serverless, uses native tooling under the hood) for MySQL/MariaDB, PostgreSQL, MongoDB → Amazon DocumentDB.
  - Heterogeneous (engine change): **schema conversion first** (SCT or DMS Schema Conversion), then DMS for data.
- **CDC latency**: DMS CDC is **not real-time and has no latency SLA**; for strict low-latency sync use native replication.
- **Security**: replication instance in your VPC (private subnets), endpoints over TLS, KMS encryption of storage, IAM roles for S3/Kinesis/DynamoDB targets.
- **Networking**: on-prem source reachable via VPN/DX (preferred) or internet; Route 53 Resolver outbound rules if endpoints use on-prem DNS names.
- **Cost**: replication instance hours (or DCU-hours for Serverless) + storage; inbound data transfer free.

#### Schema conversion: AWS SCT vs DMS Schema Conversion

| | **AWS Schema Conversion Tool (SCT)** | **DMS Schema Conversion (DMS SC)** |
|---|---|---|
| Form | Downloadable desktop app | Fully managed, web-based, in DMS console; built on SCT engine |
| Coverage | Broadest: OLTP engines, **data warehouses** (Teradata, Netezza, Oracle DW, Vertica, Greenplum, SQL Server DW → Redshift), **application SQL embedded in code**, ETL (e.g. SSIS → Glue), big-data frameworks | Fewer source/target pairs (main OLTP pairs, e.g. Oracle/SQL Server/MySQL/PostgreSQL/Db2/Sybase → Aurora/RDS PostgreSQL or MySQL) |
| Assessment report | Yes — % auto-convertible, action items by complexity | Yes |
| **Generative AI** | — | Yes (since Dec 2024): rule engine converts first; **Amazon Bedrock**-based genAI attempts objects rules can't convert (e.g. Oracle/SQL Server/MySQL/PostgreSQL/Sybase → PostgreSQL); Region-dependent; no extra charge beyond S3 |
| Cost | Free | Free (pay for S3) |
| Exam signal | "Convert data warehouse to Redshift", "convert embedded SQL in application code", "assess conversion complexity" | "Managed, no client install, convert schema in console" |

Neither tool moves data — **schema with SCT/DMS SC, data with DMS** (or SCT data extraction agents for DW migrations).

#### Babelfish for Aurora PostgreSQL

- Adds a **T-SQL dialect and SQL Server TDS wire protocol endpoint (default port 1433)** to Aurora PostgreSQL, so SQL Server applications connect with existing drivers and **mostly unchanged T-SQL**.
- **Babelfish Compass** assesses SQL Server DDL/T-SQL for compatibility before migration.
- Migrate schema with SQL Server scripts (generate DDL via SSMS) and data with **DMS (Babelfish as target)** or SSIS/bcp.
- Exam signal: "move off SQL Server licences to Aurora PostgreSQL **with minimal application code changes**" → Babelfish. Not 100% compatible: check unsupported features with Compass.

#### Native database tools (often the right answer for homogeneous moves)

| Engine | Native method | AWS target notes |
|---|---|---|
| MySQL/MariaDB | `mysqldump`/`mydumper`; **Percona XtraBackup → S3 → restore to RDS for MySQL / Aurora MySQL**; binlog replication for sync | Restore-from-S3 is fastest for large MySQL; then binlog replication or DMS CDC for delta |
| PostgreSQL | `pg_dump`/`pg_restore`; native logical replication (publication/subscription) | Logical replication for near-zero-downtime homogeneous moves |
| Oracle | **Oracle Data Pump** (expdp/impdp, via S3 integration or `DBMS_FILE_TRANSFER` to RDS); **RMAN** (to Oracle on EC2 or RDS Custom for Oracle — **not** standard RDS for Oracle); Oracle GoldenGate; Data Guard to EC2 | RDS for Oracle: Data Pump is the standard path |
| SQL Server | **Native backup (.bak) → S3 → restore to RDS for SQL Server** (`SQLSERVER_BACKUP_RESTORE` option group); log shipping / Always On to EC2; DMS for CDC | Full + differential/log restores reduce downtime |
| MongoDB | `mongodump`/`mongorestore`; DMS; homogeneous data migrations | Target Amazon DocumentDB |

#### Large database strategy

```text
 Day 0: bulk copy  ─────────────────────────────►  Day N: sync delta  ──► Cutover
 Option A (offline): native backup / DMS-to-device → Snowball Edge → S3 → restore/load
 Option B (online): native backup → S3 over DX / restore-from-S3
                    then DMS CDC (or native replication) from the backup's log position (LSN/SCN/binlog)
                    until lag ≈ 0 → stop writes → final sync → switch connection strings/DNS
```

- DMS supports **Snowball Edge as an intermediate device** (DMS + SCT data extraction agents load to the device, AWS imports to S3, DMS loads target, and DMS CDC catches up) — the classic exam answer for "tens of TB database over a thin link, minimal downtime". (Snowball is closed to new customers since Nov 2025 — in real life, use DX + native backup/restore-from-S3 or Data Transfer Terminal.)
- Always capture the **start position** (SCN/LSN/binlog file:position) of the bulk copy so CDC starts exactly there.

---

### 2.10 Data and file migration

#### AWS DataSync (online, the default for file/object data)

- Managed transfer service for **NFS, SMB, HDFS, self-managed object storage, and other clouds' object storage (e.g. Azure Blob, Google Cloud Storage)** → **S3 (any storage class), EFS, FSx for Windows File Server, FSx for Lustre, FSx for OpenZFS, FSx for NetApp ONTAP**. It also moves data between AWS storage services (cross-Region/cross-account).
- **Agent** (VM on VMware/Hyper-V/KVM, or EC2) near the source for on-prem transfers. Some AWS-to-AWS and cloud-to-cloud transfers need no agent.
- Purpose-built protocol with parallelism. **Incremental** (only changed files after the first run), **integrity verification**, **metadata preservation** (POSIX permissions, timestamps, **NTFS ACLs** for SMB → FSx for Windows), include/exclude filters, **scheduling**, **bandwidth throttling**, CloudWatch/EventBridge monitoring, TLS in transit.
- Network: over the internet, or privately over **DX/VPN using a VPC interface endpoint** for DataSync.
- Pricing: per GB transferred (plus underlying storage).
- Exam signals: "migrate 200 TB of NFS/SMB data, preserve metadata, verify integrity, automate, schedule incremental syncs until cutover" → DataSync. "Ongoing replication of an on-prem share to EFS/FSx" → scheduled DataSync tasks.

#### AWS Transfer Family

- Fully managed **SFTP, FTPS, FTP and AS2** endpoints backed by **S3 or EFS** (plus browser-based web apps and outbound SFTP connectors).
- Identity: service-managed users (SSH keys), **AWS Directory Service / AD**, or a **custom IdP via Lambda / API Gateway**. Endpoints are public or a **VPC endpoint** (with Elastic IPs for static allow-listing; FTP is VPC-only). **Managed workflows** handle post-upload processing (copy, tag, decrypt, Lambda).
- Exam signal: "external partners send files by SFTP to an on-prem server; migrate without changing partner configuration (same hostname/keys)" → Transfer Family + Route 53 CNAME + import the existing host key.
- It is not a bulk migration tool. It **replaces the file-exchange server**.

#### AWS Storage Gateway (hybrid transition)

| Type | Protocol | Backing store | Migration role |
|---|---|---|---|
| **S3 File Gateway** | NFS / SMB | S3 objects (1 file = 1 object), local cache | Keep on-prem apps writing to a share while data lands in S3; data lake ingestion; gradual move of apps to cloud |
| **FSx File Gateway** | SMB | FSx for Windows | Low-latency on-prem cache for FSx. **Closed to new customers since Oct 2024** |
| **Volume Gateway** (cached / stored) | iSCSI | S3, with **EBS snapshots** | Create EBS volumes from snapshots in AWS → lift block volumes; backup of on-prem volumes |
| **Tape Gateway** | iSCSI VTL | S3 → archive to **S3 Glacier Flexible Retrieval / Deep Archive** | **Replace physical tape** while keeping existing backup software (Veeam, NetBackup, Commvault, etc.) |

Use Storage Gateway when **on-prem applications must keep running** through a long transition (hybrid). For a one-shot bulk copy, use DataSync. AWS does not ingest physical tape cartridges directly: use a partner tape-ingestion service, or restore the data and rewrite it through Tape Gateway.

#### Offline transfer: AWS Snow Family and AWS Data Transfer Terminal

- **Snowball Edge** (exam-era answer): a rugged device shipped to you. You copy data locally (S3-compatible endpoint / NFS), ship it back, and AWS imports it into S3. The current **Storage Optimized** model holds ~210 TB usable, and you can run multiple devices in parallel for PB scale. Data is encrypted with KMS keys, devices are tamper-evident, and chain of custody is tracked per job. DMS can use it as an intermediate for seeding large databases.
- **Current status:** Snowcone and older models were discontinued (Nov 2024), **Snowmobile is retired**, and **Snowball Edge has not been available to new customers since 7 Nov 2025** (existing customers continue). Tape Gateway on Snowball Edge was also removed (Oct 2025).
- **AWS Data Transfer Terminal** (current physical alternative): reserve time at an AWS facility, bring your own storage devices, and upload at high speed over a dedicated connection to AWS public endpoints (S3, EFS, etc.). Locations include Los Angeles, New York, the San Francisco Bay Area and Munich, plus Seattle, Phoenix, London, Paris, Sydney and Tokyo from Feb 2026. Priced hourly.
- Exam framing: "**hundreds of TB to PB**, **limited/shared bandwidth**, deadline in **weeks**" → Snowball Edge (multiple devices) + DataSync/DMS for the delta. Always confirm with the bandwidth math.

#### Bandwidth math (memorise the method)

`Days = (TB × 8 × 10^12) / (link bps × utilization × 86,400)`

| Data | 100 Mbps | 500 Mbps | 1 Gbps | 10 Gbps |
|---|---|---|---|---|
| 10 TB | ~11.6 days | ~2.3 days | ~1.2 days | ~2.8 hours |
| 100 TB | ~116 days | ~23 days | ~11.6 days | ~1.2 days |
| 500 TB | ~1.6 years | ~116 days | ~58 days | ~5.8 days |
| 1 PB | ~3.2 years | ~232 days | ~116 days | ~11.6 days |

(Assumes **80% sustained utilization**. Shared production links rarely sustain that, so halve the effective rate if the link is shared.)

Rules of thumb: 1 Gbps ≈ **8.6 TB/day at 80%**; 10 Gbps ≈ 86 TB/day. If online transfer would take longer than the project window (or more than 1–2 weeks of a link you can dedicate), move the bulk offline and the delta online.

#### AWS Direct Connect for migration

- Dedicated connections are 1/10/100 Gbps (400 Gbps at select locations); hosted connections run 50 Mbps–25 Gbps through partners. **Provisioning takes weeks to months**, so order during Mobilize. A **Site-to-Site VPN** works immediately as a bridge (and later as DX backup).
- Use a private or transit VIF for VPC traffic (MGN private-IP replication, DMS, DataSync via VPC endpoint). Use a public VIF to reach public AWS endpoints (e.g. S3) without the internet.
- Exam traps: "migrate in 2 weeks; order a new DX" is wrong because of DX lead time. **S3 Transfer Acceleration** speeds long-distance uploads over the internet but **does not add bandwidth**, so it is wrong for a saturated 100 Mbps link.

---

### 2.11 Mainframe modernization

| Pattern | Approach | Tooling (exam-era name → current) | When |
|---|---|---|---|
| **Retain / augment** | Keep the mainframe; replicate data to AWS for analytics and new digital channels | Precisely/Qlik data replication, file transfer to S3 | Risk-averse; quick value; MIPS offload |
| **Replatform** | Recompile COBOL/PL/I and run on x86 in AWS with CICS/IMS/JCL/batch emulation; data to RDS/Aurora or files | **AWS Mainframe Modernization with Micro Focus** → **Rocket Software Enterprise Server** (Micro Focus mainframe tooling now belongs to Rocket) | Keep COBOL code and skills; faster, lower risk; exit mainframe hardware/MIPS cost |
| **Refactor (automated)** | Convert COBOL/JCL/CICS/BMS screens/DB2/VSAM to **Java (Spring)** + modern web UI + relational DB | **AWS Blu Age** → **AWS Transform for mainframe** (agentic refactor on the Blu Age runtime) | Remove the COBOL skills dependency; cloud-native, elastic targets; long-term agility |
| **Rewrite / repurchase** | Manual rewrite, or replace with COTS/SaaS | — | Small/simple apps or commodity functions |
| **Rehost (emulation)** | Not possible for IBM z mainframes with MGN: **MGN only handles x86 servers** | — | Distractor |

Service status: AWS Mainframe Modernization's **Managed Runtime experience** closed to new customers in Nov 2025, and its **self-managed experience** is also no longer open to new customers. AWS recommends vendor-direct offerings and **AWS Transform for mainframe**. Existing customers continue. For the exam, the key distinction is "replatform with Micro Focus/Rocket" vs "refactor with Blu Age". Mid-range systems (AS/400, Solaris SPARC) are often **retained** or moved with partner emulation (e.g. Stromasys for SPARC).

---

### 2.12 Licensing considerations

| Topic | What to know |
|---|---|
| **License Included (LI)** | Licence cost is in the hourly price (Windows Server on EC2, SQL Server on EC2/RDS, Oracle SE2 on RDS). Simplest; good for short-term or variable usage. |
| **BYOL** | Use existing licences; compliance is your responsibility. Often requires **Dedicated Hosts** (socket/core visibility, host affinity), depending on vendor terms. |
| **Windows Server BYOL** | Microsoft terms generally require **dedicated infrastructure** (EC2 Dedicated Hosts). Microsoft's 2019 licensing change restricts BYOL on "Listed Provider" clouds for licences acquired after 1 Oct 2019. Check eligibility; LI is the safe default. |
| **SQL Server BYOL** | With **Software Assurance + License Mobility**, it can run on **default (shared) tenancy EC2**. Without License Mobility → Dedicated Hosts (subject to the same restrictions). **RDS for SQL Server is License Included only**; BYOL is not offered (**RDS Custom for SQL Server** supports bring-your-own-media). |
| **Oracle** | BYOL is allowed on EC2 and RDS for Oracle (BYOL model). Oracle's cloud policy counts vCPUs (2 vCPUs = 1 processor licence when hyper-threading is on). Many orgs **replatform/refactor to Aurora PostgreSQL** to exit. |
| **Dedicated Hosts vs Dedicated Instances** | **Dedicated Hosts**: a physical server allocated to you, with **visibility of sockets/cores**, host affinity, host recovery, and per-socket/per-core BYOL. **Dedicated Instances**: single-tenant hardware but **no socket/core visibility or placement control**, so not enough for most per-core BYOL. |
| **AWS License Manager** | Define **license configurations** (vCPU/core/socket/instance counting, hard or soft limits), attach them to AMIs/launch templates, and track usage across accounts with **Organizations**. **Host resource groups** auto-allocate and release Dedicated Hosts for BYOL. Also: installed-software discovery via SSM Inventory, **license type conversion** (LI ↔ BYOL for Windows/SQL Server on EC2), managed entitlements for Marketplace licences, and Linux subscription (RHEL/SUSE) visibility. |
| **Optimization levers** | **Optimize CPUs** (fewer cores / hyper-threading off to cut per-core licences); rightsize before licensing; **SQL Server Enterprise → Standard** where features allow; consolidation; Windows → Linux; SQL Server → Aurora PostgreSQL/Babelfish; .NET Framework → .NET on Linux. AWS offers an **Optimization and Licensing Assessment (OLA)** for this analysis. |

MGN launch settings let you choose **BYOL vs License Included** per server, and post-launch actions can convert the licence type.

---

### 2.13 Cutover strategies and rollback planning

**Pre-cutover checklist:**
- Replication healthy: MGN lag near zero, DMS CDC latency ≈ 0, validation clean.
- Test instances passed UAT and performance tests.
- **DNS TTLs lowered** (e.g. to 60 s) at least one old-TTL period before cutover.
- Change freeze in place.
- Runbook with timings and owners, plus rollback criteria and a decision deadline.
- Stakeholder go/no-go.

| Strategy | How | Pros | Cons / when |
|---|---|---|---|
| **Big-bang cutover** | Stop source writes, final sync, repoint DNS/connection strings, start target | Simple, short dual-running | All-or-nothing risk; needs a downtime window |
| **Phased / per wave** | Move groups over successive windows | Limits blast radius | Hybrid connectivity and latency between moved and unmoved apps |
| **Blue/green** | Run new (green) alongside old (blue); shift traffic with **Route 53 weighted** records or a load balancer | Fast rollback by shifting back | Needs two-way data sync or a read-only period |
| **Canary** | Send a small % of users to the target first | Detects issues with real traffic | Data consistency complexity |
| **Parallel run** | Both systems process the same inputs; compare outputs over days/weeks | Highest confidence (financial, regulated) | Most expensive; double ops |
| **Continuous-sync cutover** | Keep the target in sync for weeks (DMS CDC) and cut over at will | Minimal downtime | Ongoing replication cost |

**Rollback planning:**
- **Do not decommission the source** until hypercare ends (typically 1–4 weeks). Keep source VMs powered off but intact.
- **Reverse replication**: after cutover, run a DMS task (or native replication) **from the new target back to the old source**, so a rollback doesn't lose post-cutover writes.
- **MGN**: you can revert a test/cutover launch until you **finalize cutover**. Finalize only after acceptance.
- **DNS**: keep the low TTL through hypercare so you can flip back quickly.
- Define **objective rollback triggers** (error rate, latency, data mismatch) and a **point of no return**.

---

### 2.14 Modernization patterns

#### Strangler fig

Put a **routing facade** in front of the legacy app, then carve capabilities out into new services one at a time until the monolith is "strangled".

- Facade options: **ALB path/host-based routing**, **API Gateway** (routes, auth, throttling), **CloudFront** behaviours (path patterns to different origins). Migration Hub Refactor Spaces automated this but is closed to new customers.
- Steps:
  1. Identify bounded contexts (domain-driven design).
  2. Pick a low-risk, high-value capability.
  3. Build the new service (Fargate/Lambda).
  4. Route its paths to the new service.
  5. **Sync data** during the transition (CDC via DMS, events, or an anti-corruption layer).
  6. Retire the old code path.
- Benefits: incremental risk, value delivered continuously, rollback by re-routing.

#### Decomposing monoliths into microservices

- Decompose by **business capability**/subdomain, with **database-per-service** ownership (avoid shared-database coupling). Services communicate via APIs and **events**. Use the **saga** pattern (Step Functions) for distributed transactions and a **transactional outbox** for reliable event publishing.
- Don't over-decompose: deployment, observability and network-call overhead all grow with service count.

#### Containers (see [Chapter 07](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md))

| Option | When |
|---|---|
| **ECS on Fargate** | Simplest, no servers, AWS-native, least ops. The most common exam answer for "containerize with minimal operational overhead" |
| **ECS on EC2** | Need GPUs, specific instance types or daemon tasks; cost tuning with RIs/Spot at high utilization |
| **EKS (Fargate, managed node groups, or Auto Mode)** | Kubernetes standardisation and portability; existing K8s skills/tooling, Helm; multi-cloud consistency |
| **App Runner** | Simple web apps/APIs from source or image with minimal config. *Closed to new customers since 30 Apr 2026.* Still a valid exam answer; today use ECS on Fargate |

#### Serverless and event-driven (see [Chapter 10](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md))

- **Lambda + API Gateway + DynamoDB** for request/response, **Step Functions** for orchestration, **EventBridge** for event routing between domains, **SQS/SNS** to decouple producers from consumers and absorb spikes, **Kinesis/MSK** for streams.
- Replace cron servers with **EventBridge Scheduler**. Replace file-drop polling with **S3 event notifications**.

#### Purpose-built databases (see [Chapter 09](../09-Databases-and-Caching/09-Databases-and-Caching.md))

| Need | Service |
|---|---|
| Relational, high performance, managed | Aurora (MySQL/PostgreSQL), RDS |
| Key-value at any scale, single-digit-ms | DynamoDB (+ DAX) |
| In-memory cache / durable in-memory | ElastiCache (Valkey/Redis OSS/Memcached) / MemoryDB |
| Document (MongoDB-compatible) | DocumentDB |
| Graph | Neptune |
| Wide-column (Cassandra) | Keyspaces |
| Time series | Timestream |
| Search / log analytics | OpenSearch Service |
| Data warehouse | Redshift |

#### Managed services to cut operational overhead

Self-managed → managed:
- RabbitMQ/ActiveMQ → **Amazon MQ**; Kafka → **MSK**; Elasticsearch → **OpenSearch Service**; Airflow → **MWAA**; Hadoop → **EMR**
- File servers → **FSx/EFS**; databases → **RDS/Aurora**; Active Directory → **AWS Managed Microsoft AD**
- Bastions → **Systems Manager Session Manager**; patching → **SSM Patch Manager**; backups → **AWS Backup**

#### .NET Framework → .NET on Linux; Windows → Linux

- Port Windows-only .NET Framework apps to **cross-platform .NET (8/10)** and run them on **Linux** (EC2, ECS/EKS Fargate, Lambda), optionally on **Graviton**. This removes the Windows Server licence cost.
- Tooling: exam-era **Porting Assistant for .NET** (compatibility analysis) and **App2Container** (containerize as-is, including Windows containers). Today: **AWS Transform for .NET** (agentic porting, GA May 2025; full-stack Windows including SQL Server added later).
- Pair with **SQL Server → Aurora PostgreSQL (Babelfish)** to exit both licences.
- If porting isn't feasible yet, replatform first onto **Windows containers on ECS/EKS** or **Elastic Beanstalk (IIS)**.

#### Post-migration optimization

1. Collect **2–4 weeks** of steady-state CloudWatch metrics. For memory metrics, install the CloudWatch agent via an MGN post-launch action.
2. **Rightsize** with **AWS Compute Optimizer** (EC2, EBS, Lambda, ECS on Fargate, RDS) and Cost Explorer recommendations. Move to current-gen/Graviton instances and **gp2 → gp3** volumes.
3. Commit with **Compute Savings Plans** (flexible across EC2 family/Region/OS, Fargate, Lambda) or **EC2 Instance Savings Plans** (higher discount, fixed family/Region), plus **RDS/ElastiCache/OpenSearch/Redshift Reserved Instances**. Commit **after** rightsizing.
4. Schedule non-production (Instance Scheduler), use Spot for fault-tolerant batch, and apply S3 lifecycle/Intelligent-Tiering.
5. Feed a **modernization backlog**: the highest-cost and highest-toil apps become refactor candidates.

---

## 3. Architecture patterns

### Pattern 1 — Large-scale rehost factory (MGN + Cloud Migration Factory)

```text
 On-prem DC (VMware + physical)                     AWS Organization (Control Tower landing zone)
 ┌─────────────────────────────┐   DX (private VIF/  ┌──────────────────────────────────────────┐
 │ 800 servers                 │   transit VIF)      │ Migration account(s) per wave/app        │
 │  • Replication Agent        │════════════════════►│  Staging subnet ─ replication servers    │
 │    (bulk installed by CMF)  │   TCP 443 / 1500    │  VPC endpoints: MGN, EC2, S3 (private)   │
 └─────────────────────────────┘                     │  Test VPC (isolated) → Prod VPC (cutover)│
             ▲                                       └──────────────────────────────────────────┘
             │ automation scripts                     Cloud Migration Factory (wave metadata,
 ┌───────────┴─────────────┐                          runbooks) → MGN APIs → post-launch SSM
 │ Wave plan from discovery│                          actions (CloudWatch agent, AV, domain join,
 │ (ADS / AWS Transform)   │                          licence conversion, validation)
 └─────────────────────────┘
```
**Use when:** data-center exit, hundreds to thousands of servers, a deadline. **Trade-offs:** the fastest path, but you inherit on-prem inefficiencies, so plan an optimization wave.

### Pattern 2 — Minimal-downtime heterogeneous database migration

```text
 Oracle (on-prem) ──(1) SCT / DMS Schema Conversion──► Aurora PostgreSQL (schema, code objects)
        │                                                       ▲
        └──(2) DMS task: FULL LOAD + CDC (Multi-AZ instance) ───┘  validation ON
                                                                  secondary indexes before CDC
 (3) Cutover: lag≈0 → stop app writes → final validation → switch DNS/connection string
 (4) Rollback insurance: DMS reverse task Aurora ──► Oracle until hypercare ends
```
**Use when:** an engine change with a short downtime window. **Trade-offs:** code objects the converter can't handle need manual work; DMS CDC has no latency SLA.

### Pattern 3 — Very large database: seed offline/bulk, then CDC

```text
 Source DB ──native full backup (record SCN/LSN/binlog pos)──► S3 (via DX, Data Transfer Terminal,
                                                                    or Snowball Edge in exam-world)
                                         │ restore (RDS restore-from-S3 / Data Pump / .bak restore)
                                         ▼
                                  Target DB on AWS ◄──DMS CDC-only task starting at recorded position
```
**Use when:** tens of TB, a thin network, minimal downtime. **Trade-offs:** you must coordinate the start position, and source log retention must cover the whole seed duration.

### Pattern 4 — File estate migration with hybrid transition

```text
 Windows file servers (SMB, NTFS ACLs, AD) ──DataSync agent──(DX + VPC endpoint)──► FSx for Windows
   └─ scheduled incremental tasks until cutover; DFS Namespace repointed at cutover   (Multi-AZ, AD-joined)
 Linux NFS exports ──DataSync──► EFS / FSx for NetApp ONTAP (SnapMirror for ONTAP sources)
 App still on-prem writing files for 6 months ──► S3 File Gateway (cache) ──► S3
 Backup software writing to tape ──► Tape Gateway ──► S3 Glacier Deep Archive
 Partner SFTP drop ──► Transfer Family (SFTP, same hostname via Route 53) ──► S3
```

### Pattern 5 — Strangler fig modernization after rehost

```text
                     ┌─────────────── API Gateway / ALB (path routing) ─────────────────┐
 Clients ──► Route 53│ /orders/*  ──► Orders service (ECS Fargate) ──► DynamoDB          │
                     │ /payments/*──► Payments (Lambda + Step Functions saga)            │
                     │ /*         ──► Legacy monolith (rehosted EC2) ──► RDS             │
                     └──────────────────────────────────────────────────────────────────┘
       Events: monolith & services publish domain events to EventBridge; DMS CDC syncs
       legacy tables to new stores during transition; old code paths removed once stable
```

### Pattern 6 — VMware relocate, then modernize

```text
 vSphere DC ──HCX (bulk / vMotion, L2 extension)──► VMware Cloud on AWS SDDC or Amazon EVS (in VPC)
                                                     │ ENI/VPC connectivity to native services
                                                     ├─► Replatform DBs to RDS/Aurora (DMS)
                                                     └─► Rehost VMs to EC2 (MGN) or containerize
 Exit DC in weeks; avoid retraining; modernize on your schedule (watch VMware licence cost)
```

### Pattern 7 — Mainframe refactor

```text
 z/OS: COBOL + CICS + JCL + DB2/VSAM
   ├─ Analyse & decompose (AWS Transform for mainframe / Blu Age tooling)
   ├─ Automated refactor → Java Spring apps on ECS/EC2, Angular web UI replacing 3270 screens
   ├─ Data: DB2 → Aurora PostgreSQL, VSAM → relational, batch JCL → Groovy/Java batch, AWS Batch
   └─ Test: record mainframe transactions, replay and compare outputs (functional equivalence)
 Alternative replatform: Rocket (Micro Focus) Enterprise Server runs recompiled COBOL on EC2
```

---

## 4. Decision tables

### 4.1 Which migration tool for which source

| Source | Primary tool | Alternatives / notes |
|---|---|---|
| VMware VMs → EC2 | **MGN** (agent; agentless vCenter Client if agents are forbidden) | VM Import/Export for a handful of images; **relocate** to VMware Cloud on AWS / EVS with HCX |
| Hyper-V / KVM / other-cloud VMs (Azure, GCP) | **MGN** | VM Import/Export (images, offline) |
| **Physical servers** | **MGN (agent)** | VM Import/Export cannot read physical servers |
| EC2 → another Region/AZ/account | MGN, or AMI copy/share | Elastic Disaster Recovery is for DR, not migration |
| Database, same engine | **Native tools** (backup/restore, Data Pump, XtraBackup, pg_dump, logical replication) + **DMS CDC** for minimal downtime | DMS full load + CDC; DMS homogeneous data migrations |
| Database, engine change | **SCT or DMS Schema Conversion** (schema) + **DMS** (data) | GoldenGate, partner tools |
| SQL Server → PostgreSQL, minimal code change | **Babelfish for Aurora PostgreSQL** + DMS | Babelfish Compass assessment first |
| Data warehouse → Redshift | **SCT** (+ data extraction agents) | DMS for some sources |
| NFS / SMB / HDFS / object storage files | **DataSync** | FSx for ONTAP SnapMirror (NetApp sources), Robocopy/rsync |
| SFTP/FTPS/FTP/AS2 file exchange | **Transfer Family** | — |
| Ongoing on-prem access during transition | **Storage Gateway** (S3 File, Volume) | — |
| Tape backups (virtual tape) | **Tape Gateway** | Partner ingestion for existing physical cartridges |
| 100s TB–PB over a thin link | **Snowball Edge** (exam) / **Data Transfer Terminal** (today) + online delta | DX if there is lead time |
| Mainframe (z/OS) | **AWS Mainframe Modernization**: Rocket/Micro Focus (replatform) or **Blu Age** (refactor); today **AWS Transform for mainframe** | Retain + data replication |
| Java/.NET apps → containers | **App2Container** (exam) / AWS Transform | Manual Dockerfiles |
| .NET Framework → .NET on Linux | **Porting Assistant** (exam) / **AWS Transform for .NET** | Manual port |
| Kafka → MSK | MirrorMaker 2 | — |
| COTS → SaaS | Vendor tooling, **AWS Marketplace** for procurement | AppFlow for SaaS data flows |

### 4.2 Online vs offline transfer

| Factor | Online (DataSync, DMS, MGN over internet/VPN/DX) | Offline (Snowball Edge, Data Transfer Terminal) |
|---|---|---|
| Data volume vs bandwidth | Transfer finishes within the window (do the math) | Online would take weeks/months |
| Ongoing changes | Built-in incremental/CDC | Needs an online delta sync afterwards |
| Lead time | Immediate (internet/VPN); DX takes weeks–months | Device shipping/import takes days per round trip; Terminal needs a booking and travel |
| Network impact | Consumes production bandwidth (throttle it) | None |
| Security | TLS; private over DX/VPN | Encrypted device, chain of custody |
| Availability (2026) | All available | Snowball Edge: **existing customers only** |

### 4.3 7R selection by constraint

| Constraint in the stem | Lean toward | Avoid |
|---|---|---|
| Hard deadline (DC lease, hardware EOL), large estate | **Rehost** (MGN) / **Relocate** (VMware) | Refactor during migration |
| Limited cloud skills, small team | Rehost, Relocate, **Repurchase** (SaaS) | EKS/microservices rewrite |
| Keep VMware tools/operations, no retraining | **Relocate** | — |
| Reduce operational overhead, modest change OK | **Replatform** (RDS/Aurora, Beanstalk, Fargate, FSx, Amazon MQ) | Self-managed on EC2 |
| Expensive commercial licences (Oracle/SQL Server/Windows) | **Replatform/Refactor** to open source (Aurora PostgreSQL, Babelfish, .NET on Linux) | Rehost with LI if cost is the driver |
| Existing licences with SA/BYOL rights, short-term | Rehost with BYOL (Dedicated Hosts where required) | RDS for SQL Server BYOL (doesn't exist) |
| Agility, scale, frequent releases, no deadline | **Refactor** (microservices, serverless, event-driven) | — |
| COTS with a SaaS version | **Repurchase** | Rehost a soon-to-be-sunset app |
| Low or no usage | **Retire** | Migrating it |
| Data residency / special hardware / recently refreshed | **Retain** | — |
| Mainframe, keep COBOL skills | Replatform (Rocket/Micro Focus) | MGN |
| Mainframe, exit COBOL | Refactor (Blu Age / AWS Transform) | Manual multi-year rewrite |

### 4.4 Rehost/relocate options

| | **MGN (Transform MGN)** | **VM Import/Export** | **VMware Cloud on AWS / EVS (HCX)** | SMS |
|---|---|---|---|---|
| Sources | Physical, virtual, cloud | VM images | vSphere VMs | (retired) |
| Replication | Continuous block-level | None (one-time image) | Live vMotion / bulk | — |
| Downtime | Minutes (final sync + boot) | Hours (export + upload + import) | Near-zero (vMotion) | — |
| Scale | Thousands (with CMF) | Small | Hundreds of VMs per wave | — |
| Target | Native EC2 | AMI/EC2 | VMware SDDC on AWS | — |
| Ops model after | AWS-native | AWS-native | VMware operations retained | — |

### 4.5 File and data movement services

| Need | DataSync | Transfer Family | Storage Gateway | Snowball Edge / DTT | S3 Transfer Acceleration |
|---|---|---|---|---|---|
| One-time or scheduled bulk copy with metadata | ✅ | ❌ | ❌ | ✅ (bulk) | Partial (S3 only) |
| On-prem apps keep using NFS/SMB/iSCSI against cloud storage | ❌ | ❌ | ✅ | ❌ | ❌ |
| Partners using SFTP/FTPS/AS2 | ❌ | ✅ | ❌ | ❌ | ❌ |
| No usable bandwidth | ❌ | ❌ | ❌ | ✅ | ❌ |
| Long-distance internet uploads to S3 from clients | ❌ | ❌ | ❌ | ❌ | ✅ |
| Replace tape library | ❌ | ❌ | ✅ (Tape Gateway) | ❌ | ❌ |

### 4.6 SQL Server target options

| Target | Licence | Ops | Use when |
|---|---|---|---|
| SQL Server on EC2 | LI or BYOL (License Mobility / Dedicated Hosts) | You manage OS/DB, HA (Always On) | Full control, unsupported features on RDS, BYOL savings |
| RDS for SQL Server | **LI only** | Managed (Multi-AZ, backups, patching) | Least ops, features fit RDS |
| RDS Custom for SQL Server | LI or BYOM | Managed with OS/DB access | Legacy apps needing OS access/custom agents |
| Aurora PostgreSQL + **Babelfish** | No SQL Server licence | Managed | Exit licences with minimal app change |
| Aurora/RDS PostgreSQL (full conversion) | No SQL Server licence | Managed | Willing to rewrite T-SQL (SCT/DMS SC + genAI help) |

### 4.7 DMS deployment choices

| Option | Choose when |
|---|---|
| **DMS Standard (replication instance)** | Need full endpoint coverage, fine-grained instance control, predictable sizing; Multi-AZ for CDC |
| **DMS Serverless** | Variable/unknown workload, no capacity planning, supported endpoint pair |
| **DMS homogeneous data migrations** | Same-engine MySQL/MariaDB/PostgreSQL/MongoDB→DocumentDB with native-tool fidelity, serverless |
| **Native tools only** | Same engine, downtime window large enough, highest fidelity (all objects, users, code) |
| **Native bulk + DMS CDC** | Very large same-engine DB with minimal downtime |

---

## 5. Exam keyword → answer cheat list

| Keyword / phrase in stem | Likely answer |
|---|---|
| "Data center lease expires in N months", "as quickly as possible", "minimal changes" | **Rehost with MGN** (Cloud Migration Factory for scale) |
| "Physical servers" + continuous replication | **MGN** (not VM Import/Export, not SMS) |
| "Cannot install agents on VMware VMs" (discovery) | **ADS Agentless Collector** |
| "Running processes", "detailed dependencies", "query in Athena" | **ADS Discovery Agent** + Athena data exploration |
| "Track migration progress across tools" | **Migration Hub** (legacy) / AWS Transform |
| "Identify organisational readiness gaps" | **Migration Readiness Assessment** (CAF-based) |
| "Business case based on actual utilization", "TCO" | **Migration Evaluator** |
| "AWS funding and methodology for large migration" | **MAP** |
| "Keep using vCenter, no retraining, hundreds of VMs fast" | **Relocate**: VMware Cloud on AWS (HCX) / Amazon EVS |
| "Vendor offers SaaS", "stop managing COTS infrastructure" | **Repurchase** |
| "Reduce DB admin overhead, keep engine" | **Replatform to RDS/Aurora** |
| "Minimal downtime database migration" | **DMS full load + CDC** |
| "Different database engine" | **SCT / DMS Schema Conversion** + DMS |
| "Convert data warehouse to Redshift", "convert embedded SQL in app code" | **AWS SCT** |
| "SQL Server → PostgreSQL with minimal code changes" | **Babelfish for Aurora PostgreSQL** |
| "Avoid sizing DMS instances", "unpredictable load" | **DMS Serverless** |
| "Large LOBs truncated" | Increase Max LOB size / **Full or Inline LOB mode** |
| "Verify data matches after migration" | **DMS data validation** |
| "Tens of TB DB, slow link, minimal downtime" | **Bulk seed (Snowball/native backup to S3) + DMS CDC** |
| "Hundreds of TB/PB, limited bandwidth, weeks" | **Snowball Edge** (multiple devices) + DataSync delta |
| "Copy NFS/SMB to EFS/FSx/S3, preserve metadata, schedule" | **DataSync** |
| "Partners use SFTP, no change for partners" | **Transfer Family** |
| "Replace tape, keep backup software" | **Tape Gateway** |
| "On-prem app must keep accessing files during transition" | **S3 File Gateway** |
| "Windows file shares with NTFS ACLs and AD" | **FSx for Windows File Server** + DataSync |
| "Containerize Java/.NET apps without code changes" | **App2Container** → ECS/EKS (Fargate) |
| ".NET Framework to Linux to cut Windows licences" | **Porting Assistant / AWS Transform for .NET** |
| "Mainframe, keep COBOL" | **Replatform (Micro Focus/Rocket)** |
| "Mainframe, convert to Java" | **Refactor (Blu Age / AWS Transform for mainframe)** |
| "BYOL per-socket/per-core licences" | **EC2 Dedicated Hosts** + **License Manager** |
| "Track licence compliance across accounts" | **License Manager** + Organizations |
| "Incrementally modernize a monolith", "route some paths to new service" | **Strangler fig** (API Gateway / ALB routing) |
| "Least operational overhead containers" | **ECS on Fargate** |
| "Replace self-managed RabbitMQ/ActiveMQ without code changes" | **Amazon MQ** |
| "Quick DNS cutover/rollback" | **Lower TTL ahead of time**, Route 53 weighted records |
| "Roll back without losing new writes" | **Reverse replication** (DMS target → source) |
| "Optimise cost after migration" | **Compute Optimizer rightsizing → Savings Plans** |

---

## 6. Traps & distractors

1. **AWS Server Migration Service (SMS)**: retired. Any answer using it for a new migration is wrong; choose MGN.
2. **VM Import/Export for large-scale or low-downtime migrations**: no continuous replication, and it can't take physical servers.
3. **Agentless Collector for physical servers or process-level dependencies**: it only sees VMware VMs and cannot see processes.
4. **Refactor everything during the migration** under a tight deadline: AWS explicitly recommends migrating first and modernizing later.
5. **DMS alone for a heterogeneous migration**: DMS does not convert stored procedures, functions, triggers or secondary indexes. You need SCT / DMS Schema Conversion.
6. **DMS for "real-time, sub-second" replication**: DMS CDC has no latency SLA. Use native replication.
7. **RDS for SQL Server with BYOL**: not offered (LI only). BYOL SQL Server means EC2 (or RDS Custom BYOM).
8. **Dedicated Instances for per-core BYOL**: no socket/core visibility. You need Dedicated Hosts.
9. **Ordering Direct Connect for a migration due in 2–3 weeks**: lead time is too long. Use VPN now or offline transfer.
10. **S3 Transfer Acceleration to fix limited bandwidth**: it optimises the path but doesn't add capacity.
11. **Storage Gateway as a bulk migration tool**: it is for hybrid access. DataSync (online) or Snowball (offline) moves bulk data.
12. **EFS for Windows SMB shares**: EFS is NFS for Linux. Use FSx for Windows File Server.
13. **MGN for mainframes**: MGN is for x86 servers only.
14. **Decommissioning the source right after cutover**: it removes your rollback. Keep the source until hypercare ends.
15. **Raising DNS TTL before cutover**: lower it, ahead of time.
16. **Limited LOB mode with a Max LOB size smaller than the actual LOBs**: data is silently truncated (check the task logs). Use full/inline mode or raise the limit.
17. **Starting migration waves before the landing zone, identity, logging and network exist**: the governance-first answer wins.
18. **Splitting chatty, tightly coupled apps across waves** without considering cross-WAN latency.
19. **Relocate (VMware Cloud on AWS) "to reduce licensing cost"**: it keeps VMware licensing. Its value is speed and operational continuity.
20. **Buying Savings Plans before rightsizing**: you lock in waste.

---

## 7. Professional architect focus

- **Scope reduction is the highest-ROI activity.** Discovery data commonly reveals idle/zombie servers. Retiring them cuts migration effort, licence counts and run cost before anything moves.
- **Separate migration from modernization** on the plan and in the budget. Promise stakeholders a date for exiting the data center, and a separate roadmap for modernization. Mixing them causes slips.
- **Dependencies sink waves.** Validate discovery data with app owners: hard-coded IPs, shared file shares, batch jobs, licence servers, AD/DNS, SMTP relays and printers are the usual surprises. Plan hybrid DNS (Route 53 Resolver) and IP strategy early.
- **Licensing is a commercial negotiation, not just a technical choice.** Engage procurement and the software vendors early (Microsoft, Oracle, VMware/Broadcom). Model LI vs BYOL vs exit (open source) per workload over 3–5 years.
- **Run the factory like a product.** Standard runbooks, automation (CMF, IaC launch templates, post-launch actions), a test protocol, and metrics: servers per week, rollback rate, defects found per wave.
- **Cutover governance.** Have explicit go/no-go criteria, business sign-off, a communications plan, a rollback point of no return, and hypercare staffing. Rehearse cutovers on test instances.
- **Security from day one.** Encrypted replication (MGN TLS, DMS TLS + KMS), private connectivity (DX + VPC endpoints), least-privilege migration roles, staging resources in dedicated accounts/subnets, and clean-up of staging artefacts after finalizing.
- **Data gravity and latency.** Move databases with their primary consumers. A chatty app split across on-prem and AWS will perform worse than either alone.
- **Plan for the 2025–2026 tool changes in real projects.** New accounts must use AWS Transform (discovery, planning, .NET, mainframe, VMware), Transform MGN, DMS Schema Conversion, DataSync and Data Transfer Terminal. Snowball, ADS, Migration Hub, App2Container and Fleet Advisor are available only to existing customers or are retired.
- **Optimize after you stabilise.** Collect real utilization, rightsize, then commit (Savings Plans/RIs). Feed a modernization backlog prioritised by cost, toil, and business demand.

---

## 8. Skills checklist

- [ ] I can name the 7 Rs, give a use case and an exam signal for each, and explain why refactor is deferred in large migrations.
- [ ] I can describe the Assess → Mobilize → Migrate & Modernize phases, MAP, the six CAF perspectives, and what an MRA produces.
- [ ] I can choose between the ADS Agentless Collector and the Discovery Agent, and explain what each collects (processes, network, Athena export, physical support).
- [ ] I can explain the MGN architecture: agent (443/1500), staging subnet, replication servers (t3.small default), launch templates, test vs cutover, finalize, post-launch actions, private-IP replication.
- [ ] I know when VM Import/Export is appropriate and why SMS is a distractor.
- [ ] I can compare VMware Cloud on AWS and Amazon EVS for relocate, and explain the Broadcom sales change.
- [ ] I can design a DMS migration: endpoints, Standard vs Serverless, full load / CDC / full load + CDC, validation, LOB modes, and what DMS doesn't migrate.
- [ ] I can choose between SCT and DMS Schema Conversion, and explain when Babelfish fits.
- [ ] I can pick native tools for homogeneous migrations (XtraBackup restore-from-S3, Data Pump, .bak restore to RDS, pg logical replication).
- [ ] I can do the bandwidth math and decide between online and offline transfer, knowing the current Snow Family status.
- [ ] I can choose between DataSync, Transfer Family, Storage Gateway types and Snowball for a given scenario.
- [ ] I can distinguish mainframe replatform (Rocket/Micro Focus) from refactor (Blu Age / AWS Transform).
- [ ] I can apply licensing rules: LI vs BYOL, Dedicated Hosts vs Dedicated Instances, License Manager, and SQL Server on RDS being LI-only.
- [ ] I can write a cutover and rollback plan: TTL lowering, blue/green, parallel run, reverse replication, MGN finalize timing.
- [ ] I can propose modernization paths: strangler fig, microservices, ECS/EKS/Fargate, serverless, purpose-built DBs, managed services, .NET → Linux.
- [ ] I can sequence post-migration optimization: metrics → Compute Optimizer → Savings Plans.

---

## 9. Practice questions

**Q1.** A retailer must vacate its data center in 10 months when the lease ends. The estate has 1,050 VMware VMs and 150 physical servers. The infrastructure team has eight engineers with little AWS experience and no container skills. Discovery data collected over 120 days shows 9% of servers average under 5% CPU and memory with no inbound network connections. The HR system is a commercial product whose vendor now offers a SaaS edition with equivalent features. Most other applications are in-house .NET and Java apps on Windows and Linux. Leadership wants to minimize risk and meet the deadline while reducing the migration scope. Which combination of actions should a solutions architect recommend? **(Select THREE.)**

- A. After confirming with application owners, retire the servers that show negligible utilization and no inbound connections.
- B. Refactor all in-house applications into microservices on Amazon EKS before moving them, to avoid migrating technical debt.
- C. Repurchase the HR system as the vendor's SaaS edition and migrate its data to the SaaS platform.
- D. Rehost the remaining servers with AWS Application Migration Service in dependency-based waves, deferring modernization until after the data center exit.
- E. Use VM Import/Export to migrate the 150 physical servers in a single weekend.
- F. Retain all servers on premises until a complete application rationalization has been finished.

**Q2.** A manufacturing company is planning its migration to AWS and is an existing AWS Application Discovery Service customer. The environment has 300 VMware VMs and 60 physical Linux servers running in-house applications. Architects must identify which processes on each server communicate with which other servers so they can build move groups. The data team wants to analyze the server-to-server connection data with SQL alongside utilization time series. Which discovery approach meets these requirements?

- A. Deploy the Application Discovery Service Agentless Collector in vCenter and export the network connection data to Amazon Athena.
- B. Install the AWS Application Discovery Agent on all VMs and physical servers and turn on data exploration in Amazon Athena.
- C. Import an RVTools export into AWS Migration Hub and use Migration Hub Strategy Recommendations to infer dependencies.
- D. Deploy the Agentless Collector for the VMware VMs and use the Migration Hub import template for the physical servers.

**Q3.** A financial services company is migrating 400 Windows and Linux servers to AWS with AWS Application Migration Service (now AWS Transform MGN). An AWS Direct Connect connection with a private VIF to the migration VPC already exists. The security team requires that replicated data never traverse the public internet, that replication servers have no public IP addresses, and that the staging area reach AWS service APIs privately. Which combination of steps meets these requirements? **(Select TWO.)**

- A. In the replication settings template, choose to use private IP for data replication and choose not to create public IP addresses for replication servers.
- B. In the staging area VPC, create interface VPC endpoints for MGN and Amazon EC2 and a gateway VPC endpoint for Amazon S3, and make sure source servers resolve the MGN endpoint to its private address over Direct Connect.
- C. Enable S3 Transfer Acceleration for the buckets that MGN uses during replication.
- D. Place a NAT gateway in the staging area subnet and send the TCP 1500 replication traffic from the source servers through it.
- E. Replace MGN with VM Import/Export so that no network replication is required.

**Q4.** A SaaS provider runs a 30 TB Microsoft SQL Server Enterprise database on premises and wants to stop paying for SQL Server licences. The application uses extensive T-SQL stored procedures and connects through ADO.NET. The development team cannot rewrite the data access layer within the next 6 months. The business allows at most 30 minutes of downtime at cutover. A 10 Gbps Direct Connect connection is available. Which combination of actions should the solutions architect take? **(Select TWO.)**

- A. Run Babelfish Compass against the database's DDL and T-SQL to find unsupported features, then create an Amazon Aurora PostgreSQL cluster with Babelfish turned on and create the schema through the Babelfish endpoint.
- B. Migrate to Amazon RDS for SQL Server using the bring-your-own-license model.
- C. Use AWS DMS with a full load and change data capture task, with the Babelfish endpoint as the target, and cut over when CDC latency is near zero.
- D. Use AWS SCT to convert all T-SQL to PL/pgSQL and rewrite the application's data access layer for the PostgreSQL drivers.
- E. Take a native .bak backup, upload it to Amazon S3, and restore it directly into Aurora PostgreSQL.

**Q5.** A media company must move 600 TB of archived video from an on-premises NAS into Amazon S3 within 4 weeks, before the NAS hardware support contract ends. The site has a shared 1 Gbps internet link that runs at about 50% utilization during business hours. Provisioning a new Direct Connect connection would take about 10 weeks. Editors keep adding about 200 GB of new files each day until cutover. The company is an existing AWS Snowball Edge customer. Which solution meets the deadline?

- A. Use AWS DataSync over the internet, with bandwidth throttling during business hours and full speed overnight and on weekends.
- B. Order several Snowball Edge Storage Optimized devices to copy the archive in parallel, then use AWS DataSync over the internet to transfer files added or changed after the device copy until cutover.
- C. Turn on S3 Transfer Acceleration and use AWS CLI multipart uploads from several workstations in parallel.
- D. Order a 10 Gbps Direct Connect connection and use AWS DataSync once it is provisioned.

**Q6.** An engineering firm has three Windows file servers holding 150 TB on SMB shares with complex NTFS permissions. Users authenticate against an on-premises Active Directory and reach the shares through a DFS namespace. The firm wants a fully managed, highly available AWS file service that preserves permissions, with users cut over in one weekend after a period of incremental synchronization. Direct Connect is in place. Which combination of actions meets these requirements? **(Select TWO.)**

- A. Deploy Amazon FSx for Windows File Server in a Multi-AZ configuration, joined to the existing self-managed Active Directory domain over Direct Connect.
- B. Use AWS DataSync with SMB source locations and FSx for Windows File Server destinations. Run scheduled incremental tasks, do a final sync during the cutover weekend, and repoint the DFS namespace targets.
- C. Deploy Amazon EFS and mount it from the Windows clients with the NFS client feature.
- D. Deploy an S3 File Gateway on premises and copy the files to its SMB share with Robocopy.
- E. Create an AWS Transfer Family SFTP server and have users upload their files into FSx.

**Q7.** An insurance company rehosted its monolithic Java claims application onto Amazon EC2 behind an Application Load Balancer 3 months ago using AWS Application Migration Service. The business now wants the claims-intake capability to scale independently and to be released weekly. Leadership does not want a big-bang rewrite, wants minimal operational overhead, and needs to be able to roll back quickly if the new component misbehaves. Which approach best meets these requirements?

- A. Rewrite the entire application as AWS Lambda functions and move all traffic over on one weekend after a full regression test.
- B. Build claims intake as a new service on Amazon ECS with AWS Fargate. Add ALB listener rules that send `/claims/intake/*` to the new service's target group while all other paths still go to the monolith, and publish intake events to Amazon EventBridge for the monolith to consume.
- C. Containerize the whole monolith with AWS App2Container and run it on Amazon EKS managed node groups.
- D. Move the monolith to larger EC2 instances in an Auto Scaling group and add Amazon ElastiCache to improve throughput.

**Q8.** A company is migrating 200 Windows Server VMs running SQL Server Enterprise to Amazon EC2 across 15 AWS accounts in AWS Organizations. It owns SQL Server licences with active Software Assurance and License Mobility, and Windows Server Datacenter licences bought in 2017 without Software Assurance that are eligible for BYOL only on dedicated physical hardware. The CFO wants to reuse as many existing licences as possible, and the compliance team needs central tracking that prevents over-deployment. Which combination of actions meets these requirements? **(Select TWO.)**

- A. Launch the instances on EC2 Dedicated Hosts managed through AWS License Manager host resource groups, using BYOL Windows Server images imported with VM Import/Export.
- B. Launch the instances as Dedicated Instances to meet the Windows Server dedicated-hardware requirement.
- C. Move the databases to Amazon RDS for SQL Server with the bring-your-own-license model.
- D. Create AWS License Manager license configurations for Windows Server and SQL Server with core-based counting and hard limits, share them across the organization, and associate them with the AMIs and launch templates.
- E. Use License Included Windows Server AMIs on default tenancy and bring only the SQL Server licences.

**Q9.** A company is migrating its order-management system. The application servers move with AWS Application Migration Service, and the on-premises Oracle database moves to Amazon Aurora PostgreSQL with an AWS DMS full load and CDC task. The business requires that, for 24 hours after cutover, the company can roll back to on premises without losing any orders placed in AWS. The DNS change at cutover and any rollback must take effect within minutes. Which combination of actions meets these requirements? **(Select TWO.)**

- A. Several days before cutover, lower the TTL of the application's DNS records to 60 seconds.
- B. After cutover, start a DMS CDC task that replicates from Aurora PostgreSQL back to the on-premises Oracle database, and keep the on-premises servers intact until the rollback window closes.
- C. Finalize the cutover in MGN as soon as the cutover instances launch, so the source servers can be decommissioned that day.
- D. Raise the DNS TTL to 86,400 seconds before cutover to reduce resolver load during the switch.
- E. If a rollback is needed, export the Aurora data to an AWS Snowball Edge device and ship it to the data center.

**Q10.** A bank runs its core lending platform on IBM z/OS: COBOL programs, CICS transactions, DB2 databases and JCL batch. The mainframe contract renews in 3 years. Many COBOL developers retire within 2 years, and the bank cannot hire replacements. The bank wants to run on elastic, cloud-native AWS services, preserve the existing business logic exactly, and avoid a multi-year manual rewrite. Which approach best meets these goals?

- A. Rehost the mainframe LPARs onto Amazon EC2 with AWS Application Migration Service.
- B. Replatform with AWS Mainframe Modernization using Micro Focus (now Rocket Software) Enterprise Server, recompiling the COBOL to run on Amazon EC2.
- C. Use automated refactoring with AWS Blu Age (now part of AWS Transform for mainframe) to convert the COBOL, CICS and DB2 assets into Java services backed by Amazon Aurora PostgreSQL, and validate functional equivalence by replaying recorded production transactions.
- D. Retain the mainframe and replicate DB2 data to Amazon Redshift for analytics and new reporting.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: A, C, D**

- **A** — Servers with very low utilization and no inbound connections are textbook **retire** candidates (AWS Prescriptive Guidance's zombie/idle criteria). Retiring them shrinks scope, risk and cost.
- **C** — A COTS product with a vendor SaaS edition is a classic **repurchase**. It removes infrastructure work altogether.
- **D** — With a fixed deadline, a large estate and a small team without container skills, **rehost with MGN** in dependency-based waves is the lowest-risk path. AWS recommends modernizing after the migration.
- **B** is wrong: refactoring during a deadline-driven large migration is the most complex and costly strategy, and the team lacks the skills.
- **E** is wrong: VM Import/Export imports VM images. It cannot read physical servers directly, and it offers no continuous replication.
- **F** is wrong: retaining everything misses the lease deadline.

References: [Migration strategies (7 Rs)](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html) · [Transform MGN user guide](https://docs.aws.amazon.com/mgn/latest/ug/what-is-application-migration-service.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: B**

Only the **Discovery Agent** collects **running processes**, works on **physical servers** as well as VMs, and supports exporting **network connection and time-series data to Amazon Athena** for SQL analysis.
- **A** is wrong: the Agentless Collector can't see processes inside VMs, doesn't support physical servers, and doesn't support Athena export of network data.
- **C** is wrong: an RVTools export is a single snapshot of VMware inventory with no network connections or processes.
- **D** is wrong: the import template carries static data only (no network connections or processes), and the Agentless Collector still lacks process data.

Reference: [What is AWS Application Discovery Service? (comparison table)](https://docs.aws.amazon.com/application-discovery/latest/userguide/what-is-appdiscovery.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: A, B**

- **A** — "Use private IP for data replication" sends TCP 1500 replication traffic over the existing Direct Connect/VPN/peering. Choosing not to create public IPs keeps replication servers private.
- **B** — With no internet path, the staging subnet still needs the MGN API (TCP 443), the EC2 endpoint and S3. VPC endpoints provide that privately. Source servers also talk to the MGN endpoint on 443, so they must resolve and reach it privately over DX.
- **C** is wrong: Transfer Acceleration uses the public edge network and is unrelated to MGN replication.
- **D** is wrong: a NAT gateway is for outbound internet access from private subnets. It cannot receive inbound replication from on premises, and it implies an internet path.
- **E** is wrong: VM Import/Export gives up continuous replication and low-downtime cutover for 400 servers.

References: [MGN network requirements](https://docs.aws.amazon.com/mgn/latest/ug/Network-Requirements.html) · [Replication template reference — data routing](https://docs.aws.amazon.com/mgn/latest/ug/replication-server-settings.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: A, C**

- **A** — **Babelfish** gives Aurora PostgreSQL a T-SQL dialect and the TDS wire protocol, so ADO.NET clients and most T-SQL keep working. **Babelfish Compass** finds unsupported constructs first.
- **C** — DMS full load + CDC into the Babelfish target keeps the target in sync, so cutover fits the 30-minute window. 30 TB over 10 Gbps is practical.
- **B** is wrong: RDS for SQL Server is License Included only (no BYOL), and it doesn't eliminate SQL Server licensing.
- **D** is wrong: a full T-SQL rewrite plus a data-access-layer rewrite breaks the 6-month constraint.
- **E** is wrong: SQL Server .bak files can only be restored into SQL Server (for example RDS for SQL Server), not Aurora PostgreSQL.

References: [Babelfish for Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish.html) · [Using Babelfish as a DMS target](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.Babelfish.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: B**

The math: 600 TB at an effective ~0.5 Gbps is ≈ 600 × 8 × 10^12 / (0.5 × 10^9 × 86,400) ≈ **111 days**, and even at the full 1 Gbps it is ~56 days. Both miss the 4-week deadline. Several **Snowball Edge** devices in parallel move the bulk offline. **DataSync** then handles the ~200 GB/day delta (under an hour per day at 0.5 Gbps) until cutover. Snowball Edge is closed to *new* customers, but this company is an existing customer. A new customer would consider AWS Data Transfer Terminal.
- **A** is wrong: online transfer takes months.
- **C** is wrong: Transfer Acceleration does not add bandwidth.
- **D** is wrong: the 10-week lead time misses the deadline.

References: [AWS Snowball Edge availability change](https://docs.aws.amazon.com/snowball/latest/developer-guide/snowball-edge-availability-change.html) · [AWS DataSync](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, B**

- **A** — FSx for Windows File Server is fully managed native SMB with NTFS ACLs. It can join a self-managed AD, and Multi-AZ provides high availability.
- **B** — DataSync copies SMB data **with NTFS metadata**, runs incremental scheduled syncs, and does a final sync at cutover. Repointing DFS keeps the user experience the same.
- **C** is wrong: EFS is an NFS file system for Linux and doesn't preserve NTFS ACL semantics for Windows users.
- **D** is wrong: an S3 File Gateway stores files as S3 objects. It is a hybrid access tool, not a managed Windows file service with AD/NTFS semantics.
- **E** is wrong: Transfer Family is for SFTP/FTP/AS2 file exchange (backed by S3/EFS, not FSx), and manual user uploads don't preserve permissions.

References: [FSx for Windows File Server](https://docs.aws.amazon.com/fsx/latest/WindowsGuide/what-is.html) · [DataSync with SMB](https://docs.aws.amazon.com/datasync/latest/userguide/create-smb-location.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B**

This is the **strangler fig** pattern. The ALB acts as the routing facade, a single capability moves to a new service on **ECS Fargate** (no servers to manage), and **EventBridge** decouples it from the monolith. Rolling back means changing the listener rule back.
- **A** is wrong: a big-bang rewrite contradicts the stated constraints.
- **C** is wrong: containerizing the whole monolith doesn't let claims intake scale or release independently, and EKS node groups add operational overhead.
- **D** is wrong: vertical scaling is not modernization and doesn't enable independent releases.

References: [Strangler fig pattern (Prescriptive Guidance)](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html) · [ALB listener rules](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-rules.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: A, D**

- **A** — Windows Server licences without SA that are eligible only on dedicated hardware need **EC2 Dedicated Hosts**. License Manager **host resource groups** automate host allocation. BYOL Windows images are brought in with VM Import/Export. SQL Server with License Mobility can also run on these hosts.
- **D** — License Manager **license configurations** with hard limits, shared across the organization and attached to AMIs and launch templates, give central tracking and prevent over-deployment.
- **B** is wrong: Dedicated Instances don't provide the socket/core visibility or host control that per-core BYOL requires.
- **C** is wrong: RDS for SQL Server does not support BYOL.
- **E** is wrong: License Included Windows wastes the Windows licences the CFO wants to reuse.

References: [License Manager host resource groups](https://docs.aws.amazon.com/license-manager/latest/userguide/host-resource-groups.html) · [License configurations](https://docs.aws.amazon.com/license-manager/latest/userguide/license-configurations.html) · [EC2 Dedicated Hosts](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/dedicated-hosts-overview.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, B**

- **A** — Lowering the TTL **in advance** (at least one old-TTL period before) means the cutover change, and any rollback, propagates within minutes.
- **B** — **Reverse replication** from Aurora PostgreSQL back to Oracle keeps on-premises data current, so a rollback loses no orders. Keeping the source servers intact preserves the rollback path.
- **C** is wrong: finalizing in MGN and decommissioning the source removes the rollback option during the window.
- **D** is wrong: a long TTL delays both cutover and rollback propagation.
- **E** is wrong: shipping a device takes days, and the data would be stale.

References: [DMS ongoing replication best practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html) · [MGN launching cutover instances](https://docs.aws.amazon.com/mgn/latest/ug/launch-cutover-gs.html) · [Route 53 TTL](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-basic.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: C**

**Automated refactoring** with Blu Age (now AWS Transform for mainframe) converts COBOL/CICS/DB2 into Java and relational targets. That removes the COBOL skills dependency, enables elastic cloud-native deployment, preserves business logic through automated conversion, and avoids a manual multi-year rewrite. Transaction replay testing validates equivalence.
- **A** is wrong: MGN rehosts x86 servers and cannot migrate z/OS mainframes.
- **B** is wrong: replatforming keeps COBOL, so the skills problem stays.
- **D** is wrong: retaining the mainframe doesn't achieve the goals and keeps the contract.

References: [AWS Mainframe Modernization](https://docs.aws.amazon.com/m2/latest/userguide/what-is-m2.html) · [AWS Transform for mainframe](https://docs.aws.amazon.com/transform/latest/userguide/what-is-service.html) · [Mainframe Modernization availability change](https://docs.aws.amazon.com/m2/latest/userguide/mainframe-modernization-availability-change.html)
</details>

---

## 10. References

**Strategy & methodology**
- [AWS Prescriptive Guidance — Large migration guide: migration strategies (7 Rs)](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html)
- [AWS Prescriptive Guidance — Migration strategies and phases](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-migration/introduction.html)
- [AWS Cloud Adoption Framework (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/overview-aws-cloud-adoption-framework/welcome.html)
- [Best practices for assessing applications to be retired](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-retiring-applications/introduction.html)
- [AWS Migration Acceleration Program](https://aws.amazon.com/migration-acceleration-program/)
- [Migration Evaluator](https://aws.amazon.com/migration-evaluator/)

**Discovery & planning**
- [AWS Application Discovery Service user guide](https://docs.aws.amazon.com/application-discovery/latest/userguide/what-is-appdiscovery.html)
- [AWS Migration Hub availability change](https://docs.aws.amazon.com/migrationhub/latest/ug/migrationhub-availability-change.html)
- [AWS Transform user guide](https://docs.aws.amazon.com/transform/latest/userguide/what-is-service.html)

**Rehost / relocate**
- [AWS Transform MGN (Application Migration Service) user guide](https://docs.aws.amazon.com/mgn/latest/ug/what-is-application-migration-service.html)
- [MGN network requirements](https://docs.aws.amazon.com/mgn/latest/ug/Network-Requirements.html)
- [MGN post-launch template](https://docs.aws.amazon.com/mgn/latest/ug/post-launch-settings.html)
- [Cloud Migration Factory on AWS](https://aws.amazon.com/solutions/implementations/cloud-migration-factory-on-aws/)
- [VM Import/Export user guide](https://docs.aws.amazon.com/vm-import/latest/userguide/what-is-vmimport.html)
- [Amazon Elastic VMware Service](https://docs.aws.amazon.com/evs/latest/userguide/what-is-evs.html)
- [VMware Cloud on AWS FAQs](https://aws.amazon.com/vmware/faqs/)

**Databases**
- [AWS DMS user guide](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html)
- [AWS DMS best practices (LOBs, validation, performance)](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
- [AWS DMS Serverless](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Serverless.html)
- [DMS Schema Conversion](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SchemaConversion.html)
- [AWS Schema Conversion Tool user guide](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html)
- [Babelfish for Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish.html)
- [Importing and exporting SQL Server databases using native backup and restore (RDS)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.html)

**Data & files**
- [AWS DataSync user guide](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html)
- [AWS Transfer Family user guide](https://docs.aws.amazon.com/transfer/latest/userguide/what-is-aws-transfer-family.html)
- [AWS Storage Gateway documentation](https://docs.aws.amazon.com/storagegateway/)
- [AWS Snowball Edge availability change](https://docs.aws.amazon.com/snowball/latest/developer-guide/snowball-edge-availability-change.html)
- [AWS Data Transfer Terminal](https://aws.amazon.com/data-transfer-terminal/)
- [AWS Direct Connect user guide](https://docs.aws.amazon.com/directconnect/latest/UserGuide/Welcome.html)

**Mainframe, licensing, modernization**
- [AWS Mainframe Modernization user guide](https://docs.aws.amazon.com/m2/latest/userguide/what-is-m2.html) and [availability change](https://docs.aws.amazon.com/m2/latest/userguide/mainframe-modernization-availability-change.html)
- [AWS License Manager user guide](https://docs.aws.amazon.com/license-manager/latest/userguide/license-manager.html)
- [Microsoft licensing on AWS](https://aws.amazon.com/windows/resources/licensing/)
- [Cloud design patterns — strangler fig](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html)
- [Decomposing monoliths into microservices](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-decomposing-monoliths/introduction.html)
- [AWS Compute Optimizer](https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html) · [Savings Plans](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html)
