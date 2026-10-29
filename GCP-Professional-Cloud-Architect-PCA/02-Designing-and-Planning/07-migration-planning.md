# 02/07 · Migration Planning (and Envisioning Future Improvements)

**Exam guide:** 1.4 (migration plan), 1.5 (future improvements, cloud-first) and 5.1 (migration tooling). **Principles:** P10, P14, P15.

---

## 1. The migration journey: Assess → Plan → Deploy → Optimize

| Phase | Goal | Key outputs | Google Cloud tools |
|---|---|---|---|
| **Assess** | Know what you have and what it costs | Inventory, utilization, dependencies, TCO, migration complexity, target recommendations | **Migration Center** (discovery client, imports from RVTools/CSV, asset inventory, TCO and rightsizing reports, application grouping) |
| **Plan** | Build the foundation and the sequence | **Landing zone** (resource hierarchy, identity, network, security, logging, billing), migration waves, test and rollback plans, skills plan | Enterprise foundations blueprint / Terraform; Cloud Identity; Shared VPC; Interconnect orders |
| **Deploy** | Move workloads in waves | Migrated workloads, validated and cut over | Migrate to Virtual Machines, VMware Engine, Migrate to Containers, Database Migration Service, Storage Transfer Service, Transfer Appliance, BigQuery Migration Service |
| **Optimize** | Realize cloud benefits | Rightsizing, managed-service adoption, automation, cost controls, modernization | Recommender / Active Assist, CUDs, GKE/Cloud Run modernization, observability |

**The exam's rule:** never skip *Assess* and *Plan*. "Start migrating the largest database first" is almost always wrong. "Run discovery, build a landing zone, pilot a low-risk workload" is almost always right.

---

## 2. Migration strategies (workload disposition)

| Strategy | What changes | Speed | Cloud benefit | Choose when |
|---|---|---|---|---|
| **Rehost** (lift and shift) | Nothing in the app; VM moves | Fastest | Low initially | Deadline (lease expiry), low-risk first step |
| **Replatform** (lift and optimize) | Swap platform pieces: self-managed DB → Cloud SQL, VM → GKE without code changes | Fast | Medium | Quick wins in ops cost |
| **Refactor** (move and improve) | Code changes to use cloud services | Medium | High | Valuable apps with scalability needs |
| **Rearchitect / rebuild** | New architecture (microservices, serverless, event-driven) | Slow | Highest | Differentiating apps where legacy blocks the goals |
| **Repurchase** | Replace with SaaS | Varies | High for non-core | Commodity capabilities (CRM, HR) |
| **Retire** | Turn it off | Fast | Cost saved | Unused or duplicate systems |
| **Retain** | Keep where it is (for now) | — | — | Regulatory, scheduled replacement, hard dependencies (EHR's legacy integrations, KnightMotives' mainframe) |

---

## 3. Tooling: which tool moves what

| Source → target | Tool | Key characteristics |
|---|---|---|
| VMs (VMware vSphere, AWS EC2, Azure VMs, physical) → Compute Engine | **Migrate to Virtual Machines** | Continuous replication, **test clones** before cutover, wave-based cutover, rollback; minimal downtime |
| VMware environment → same tooling in Google Cloud | **Google Cloud VMware Engine** + VMware HCX | Keep vSphere/vSAN/NSX; fastest for VMware-heavy data-center exits |
| VMs → containers (GKE / Cloud Run) | **Migrate to Containers** | Extracts the app from a VM into container artifacts; good for stateless Linux/Windows apps |
| MySQL / PostgreSQL / SQL Server → Cloud SQL | **Database Migration Service** | Homogeneous; **continuous (CDC) migration**; promote at cutover for minimal downtime |
| PostgreSQL → AlloyDB | Database Migration Service | Continuous |
| Oracle → Cloud SQL for PostgreSQL / AlloyDB | Database Migration Service (heterogeneous) with **conversion workspaces** (schema and code conversion, Gemini-assisted) | Plus data migration with CDC |
| Databases → BigQuery (analytics) | **Datastream** (CDC) | Not a cutover tool; replication for analytics |
| Data warehouses (Teradata, Redshift, Snowflake, etc.) → BigQuery | **BigQuery Migration Service** (SQL translation, assessment) + BigQuery Data Transfer Service | |
| Files/objects online (other clouds, HTTP, on-premises file systems with agents) → Cloud Storage | **Storage Transfer Service** | Scheduled or event-driven; agents for on-premises |
| Large offline data → Cloud Storage | **Transfer Appliance** | When the network would take too long (> ~1 week) |
| Hadoop/Spark → Google Cloud | **Managed Service for Apache Spark** (formerly Dataproc) + data to Cloud Storage | Re-point jobs |
| Mainframe | Retain + **Mainframe Connector** (move/copy mainframe data to BigQuery and Cloud Storage); incremental modernization with parallel validation (Dual Run) | Strangler pattern |
| Containers on other Kubernetes → GKE | Redeploy manifests via CI/CD; Backup for GKE (GKE → GKE); fleet registration for attached clusters | |

---

## 4. Building the migration plan

### 4.1 Dependency planning and waves

1. **Discover** applications and their dependencies: network flows, shared databases, batch jobs, authentication, licensing servers.
2. **Group** tightly coupled components into **move groups** that migrate together. Splitting a chatty app across on-premises and cloud adds latency through Interconnect and may break SLAs.
3. **Order the waves:**
   * **Wave 0 (pilot):** low-risk, low-dependency, representative workloads. Proves the landing zone, tooling and runbooks.
   * **Middle waves:** bulk of the estate.
   * **Final waves:** the most complex or critical systems, once the team is experienced.
   * **Deadline overrides:** systems in the data center whose lease expires first (EHR) move earlier, usually by rehosting.
4. **Plan each wave:** pre-migration checks, replication, test clone validation, cutover window, rollback criteria, post-cutover monitoring.

### 4.2 Workload testing

| Test | Purpose |
|---|---|
| Functional / smoke tests on test clones | The migrated system works before cutover |
| Performance / load tests | The target meets latency and throughput NFRs. Compare with the baseline from Assess |
| Integration tests | Dependencies (on-premises, partners, identity) reachable and correct |
| DR / failover tests | The new HA/DR design actually meets RTO/RPO |
| User acceptance | The business signs off |

### 4.3 Network planning

* **IP address plan:** non-overlapping RFC 1918 ranges between on-premises and every VPC (overlaps block peering and routing; PSC and NAT are workarounds). Plan secondary ranges for GKE pods and services.
* **Hybrid connectivity lead time:** Dedicated Interconnect takes weeks (cross-connect in a colocation facility). Start **HA VPN** immediately as the interim path.
* **Bandwidth for data migration:** use the [P10 time table](../00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md#p10--data-has-gravity-a-lifecycle-and-a-legal-home). If the network would take too long, use Transfer Appliance.
* **Hybrid DNS:** Cloud DNS **forwarding zones** (cloud → on-premises resolvers), **inbound server policies** (on-premises → Cloud DNS), and **DNS peering** across VPCs.
* **Firewall and security:** hierarchical firewall policies, Cloud NGFW rules for migrated workloads, IAP for administration.

### 4.4 Software licensing and financial impact

| Situation | Option |
|---|---|
| Windows Server / SQL Server, want simplicity | **License-included** images or **Cloud SQL for SQL Server** (license in the price) |
| Existing licenses requiring dedicated hardware (BYOL with physical-core or host restrictions) | **Sole-tenant nodes** (with in-place restarts and CPU overcommit options to optimize) |
| Microsoft licenses with License Mobility (Software Assurance) | BYOL on shared tenancy where the product's terms allow |
| Oracle databases | Bare Metal Solution or Oracle Database@Google Cloud (licensing and certification); or migrate to PostgreSQL/AlloyDB to remove licenses |
| RHEL / SLES | Pay-as-you-go images or BYOS subscriptions |
| Per-core licensed software | **Custom machine types** to minimize vCPUs; disable SMT (threads-per-core = 1) where licensing counts threads |

**Financial impact**

* Model TCO (Migration Center reports): compute, storage, network egress, licenses and operations, versus the data center (power, space, hardware refresh, staff).
* Account for **double-running costs** during migration.
* Apply **CUDs** after the steady state is known, and include migration incentives or credits where applicable.
* Moving from CapEx to OpEx changes budgeting: involve finance (Section 4.2).

---

## 5. Integrating with existing systems during and after migration

* **Identity:** keep the existing directory as the source of truth. Use AD with GCDS to Cloud Identity plus SSO, or Workforce Identity Federation (see [04/01](../04-Security-and-Compliance/01-iam-and-resource-hierarchy.md)).
* **Hybrid apps:** Interconnect plus private DNS so migrated apps reach systems that stay put (EHR insurance integrations).
* **Data sync during the transition:** DMS for cutover, Datastream for analytics, Storage Transfer for files.
* **APIs as facades:** put **Apigee** in front of legacy systems so consumers don't change when the back end migrates (strangler fig pattern).

---

## 6. Landing zone essentials (what "foundation first" means)

| Element | Recommended setup |
|---|---|
| Resource hierarchy | Organization → folders (by environment and/or business unit) → projects per app and environment |
| Identity | Cloud Identity or Workspace, synced from or federated with the corporate IdP; groups-based IAM; MFA / 2SV; separate admin accounts |
| Organization policies | Restrict resource locations, disable service account key creation, enforce uniform bucket-level access, disable external IPs where appropriate, restrict public IPs on Cloud SQL |
| Networking | Shared VPC host projects per environment; hub-and-spoke or NCC; Cloud NAT; Private Google Access; hybrid connectivity; DNS |
| Security | Security Command Center; VPC Service Controls for sensitive data; Cloud KMS strategy; Secret Manager |
| Logging and monitoring | Aggregated log sinks to a central logging project; metrics scopes; audit log retention |
| Billing | Billing account structure, budgets and alerts, labels, billing export to BigQuery |
| Automation | Everything above as Terraform in version control, deployed by CI/CD |

---

## 7. Worked scenarios

**A. "A data-center lease ends in 5 months. 600 VMware VMs, little cloud experience, minimal disruption."**
Deadline plus VMware means **VMware Engine** (keeps vSphere skills; HCX bulk or vMotion-style migration), or **Migrate to VMs** if they want native Compute Engine. Assess with Migration Center first, but keep it short. Modernize after the exit (P15).

**B. "Migrate a 4 TB MySQL database with less than 5 minutes of downtime."**
**Database Migration Service** continuous migration to Cloud SQL for MySQL; let it reach CDC steady state, stop writes, promote, repoint the app. Reject dump-and-restore.

**C. "SQL Server Enterprise on Windows; the company owns licenses with Software Assurance but wants to minimize license cost."**
Options: Cloud SQL for SQL Server (license included; simplest ops); BYOL on Compute Engine where License Mobility allows; **sole-tenant nodes** for licenses that require dedicated hardware. Rightsize cores with custom machine types.

**D. "Move 2 PB of archival media from on-premises with a 1 Gbps link in 2 months."**
At 1 Gbps, 2 PB takes about 200 days, far beyond 2 months, so ship it with **Transfer Appliance** into an Archive-class bucket (P10).

---

## 8. Envisioning future solution improvements (exam guide 1.5)

The exam's "future" objective is about designing so tomorrow's change is cheap.

| Principle | In practice |
|---|---|
| **Cloud-first design** | New capabilities start on managed, cloud-native services; on-premises only when justified |
| **Loose coupling** | APIs (Apigee), events (Pub/Sub, Eventarc), and contracts between teams let components evolve independently |
| **Open standards and portability** | Containers and Kubernetes (GKE fleets across environments), open table formats (Iceberg via Google Cloud Lakehouse), OpenTelemetry, Terraform |
| **Data as a product** | A governed data platform (BigQuery + Knowledge Catalog) is the substrate for future AI |
| **Modernization roadmap** | Rehost now, then replatform (managed DBs), refactor hot paths (Cloud Run/GKE), and add AI on the data |
| **Evolving business needs** | Design for new markets (multi-region readiness, residency controls), new channels (APIs) and new partners (data sharing) |
| **Technology improvements** | Adopt newer machine generations, managed AI capabilities, and price/performance improvements through regular architecture reviews |

**Exam angle:** between two designs that both meet today's requirements, the one that doesn't block a stated future direction wins. For example, KnightMotives' data monetization favors a governed BigQuery platform over siloed exports. Altostrat's planned on-premises migration favors fleet-managed Kubernetes now.

---

## References

* Migration to Google Cloud: getting started: <https://cloud.google.com/architecture/migration-to-gcp-getting-started>
* Migration Center: <https://cloud.google.com/migration-center/docs/migration-center-overview>
* Migrate to Virtual Machines: <https://cloud.google.com/migrate/virtual-machines/docs/5.0/migrate/what-is-migrate-to-vms>
* Database Migration Service: <https://cloud.google.com/database-migration/docs/overview>
* Transfer Appliance: <https://cloud.google.com/transfer-appliance/docs/4.0/overview>
* Sole-tenant nodes and BYOL: <https://cloud.google.com/compute/docs/nodes/bringing-your-own-licenses>
* Enterprise foundations blueprint: <https://cloud.google.com/architecture/security-foundations>
