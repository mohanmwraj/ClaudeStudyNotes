# 02 · EHR Healthcare: Case-Study Breakdown

Official text: [EHR Healthcare case study (PDF)](https://services.google.com/fh/files/misc/v6.1_pca_ehr_healthcare_case_study_english.pdf). Requirements below are quoted from it; everything else is this kit's analysis.

---

## 1. Snapshot

* SaaS provider of electronic health record software to multinational medical offices, hospitals and insurance providers.
* Business growing "exponentially year over year". They must scale, **adapt their disaster recovery plan** and **roll out continuous deployment**.
* Runs in **multiple colocation facilities**; **the lease on one data center is about to expire**. Google Cloud has been chosen to replace the colocation facilities.
* Customer-facing apps are web-based; many are **already containerized on Kubernetes**. Data is in **MySQL, MS SQL Server, Redis and MongoDB**.
* **Legacy file- and API-based integrations with insurance providers stay on-premises**: "no plan to upgrade or move these systems at the current time."
* Users are in **Microsoft Active Directory**. Monitoring uses open-source tools; **alerts are sent by email and often ignored**.

> ### Standing constraints (apply to every EHR question)
>
> 1. **≥ 99.9% availability** for all customer-facing systems → multi-zone regional design at minimum.
> 2. **Regulated health data** ("maintain regulatory compliance") → HIPAA-style controls: a BAA, audit logs, least privilege, encryption, residency where required.
> 3. **Deadline**: a colocation lease is expiring → migrate fast; rehost or move containers as they are first.
> 4. **Legacy insurance integrations remain on-premises** → hybrid connectivity, not migration.
> 5. **Existing assets**: Kubernetes, MySQL, SQL Server, Redis, MongoDB, Microsoft AD.
> 6. **Root causes of past outages**: misconfiguration, capacity spikes and inconsistent monitoring → IaC/GitOps, autoscaling and centralized observability.

---

## 2. Requirement decomposition

### Business requirements

| Requirement (quoted) | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| "On-board new insurance providers as quickly as possible." | Partner integration must be self-service and repeatable, not a custom project per provider | **Apigee** API management (developer portal, API keys/OAuth, quotas, analytics) for API partners; a standard **Cloud Storage** landing bucket with Pub/Sub notifications for file partners; reusable **Dataflow** templates; **Cloud Healthcare API** (FHIR, HL7v2) where health data standards apply | P8, P5 | A bespoke VPN or point-to-point integration per provider |
| "Provide a minimum 99.9% availability for all customer-facing systems." | About 43 minutes of downtime a month. Survive a zone failure without manual action | **Regional GKE clusters** (nodes in 3 zones), **Cloud SQL HA** (regional, synchronous standby), **Memorystore Standard tier/HA**, a **global external Application Load Balancer**, health checks | P2, P1 | Single-zone clusters; overbuilding to multi-region active-active "for availability" |
| "Provide centralized visibility and proactive action on system performance and usage." | One pane of glass across environments, plus alerts that people act on | **Cloud Monitoring** with a metrics scope over all projects, dashboards, **SLOs with burn-rate alerting**; **Cloud Logging** aggregated sinks; alert notification channels to on-call tools (PagerDuty, Slack) instead of email; **Managed Service for Prometheus** for existing Prometheus-style metrics | P13 | More email alerts; per-cluster self-managed monitoring stacks |
| "Increase ability to provide insights into healthcare trends." | An analytics platform over operational data | **BigQuery** as the warehouse fed by **Datastream** (CDC from MySQL, SQL Server) and Dataflow; **Looker** for governed reporting | P4, P10 | Running analytics queries against the OLTP databases |
| "Reduce latency to all customers." | Customers are multinational. Serve from close to them | **Global external Application Load Balancer** (anycast IP, Premium Tier) with backends in multiple regions as growth demands; **Cloud CDN** for static assets | P1 | Bigger VMs; DNS round-robin to one region |
| "Maintain regulatory compliance." | Health data rules (HIPAA in the US, others for multinational customers) | Sign Google's **BAA**; use only **covered services**; **Assured Workloads** for regulated controls where required; **CMEK** if key control is mandated; **VPC Service Controls** around PHI projects; **Data Access audit logs** enabled; **Sensitive Data Protection** de-identification for analytics; org policies for location | P11, P6, P7 | Assuming "encrypted by default" alone equals compliance |
| "Decrease infrastructure administration costs." | Shed toil | Managed services: GKE (consider **Autopilot**), Cloud SQL, Memorystore, a managed MongoDB option; **IaC** for repeatability; CUDs for steady baseline | P5, P9 | Rehosting databases on self-managed VMs long term |
| "Make predictions and generate reports on industry trends based on provider data." | ML on the analytics platform | **BigQuery ML** for in-warehouse forecasting and classification; **Agent Platform** (formerly Vertex AI) for custom models; Looker or Data Studio for reports | P16 | Building a custom training cluster for simple forecasting |

### Technical requirements

| Requirement (quoted) | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| "Maintain legacy interfaces to insurance providers with connectivity to both on-premises systems and cloud providers." | Legacy stays put; the new cloud apps must reach it | **Hybrid connectivity**: Dedicated Interconnect (EHR is already in colocation facilities, where Interconnect is typically available) or Partner Interconnect, with **HA VPN** as backup; **Cloud Router** with BGP | P14, P15 | Migrating the legacy integrations now |
| "Provide a consistent way to manage customer-facing applications that are container-based." | One management model for all clusters | **GKE fleets** with **Config Sync** (GitOps for config) and **Policy Controller** (guardrails); **Cloud Deploy** for consistent release pipelines | P12 | Per-cluster manual kubectl management |
| "Provide a secure and high-performance connection between on-premises systems and Google Cloud." | Private, high-bandwidth, redundant | **Dedicated Interconnect** in a 99.9% or 99.99% topology (99.99%: four connections across two metros, or four in one supported metro as a `PRODUCTION_CRITICAL` connection group); MACsec or HA VPN over Interconnect if encryption is required on the link | P14, P2 | Single connection; public internet |
| "Provide consistent logging, log retention, monitoring, and alerting capabilities." | Standardized across all environments | **Aggregated log sinks** (organization or folder level) to central **log buckets** with retention set to policy; **Log Analytics**; Cloud Monitoring alerting policies defined as code | P13, P12 | Different tools per team |
| "Maintain and manage multiple container-based environments." | dev/test/prod (and possibly per-customer) clusters | Separate projects per environment under folders; regional GKE per environment; fleet-wide config; **Terraform** to stamp out environments | P7, P12 | One cluster with namespaces for prod and dev (weak isolation for regulated data) |
| "Dynamically scale and provision new environments." | Autoscaling plus environment templating | **Cluster autoscaler** / Autopilot, **Horizontal Pod Autoscaler**; Terraform or Infrastructure Manager modules for new environments | P9, P12 | Manual capacity planning |
| "Create interfaces to ingest and process data from new providers." | Scalable, decoupled ingestion | Apigee for APIs → **Pub/Sub** → **Dataflow** → BigQuery / Cloud Healthcare API; file drops to Cloud Storage → Eventarc or Pub/Sub notifications → processing | P8 | Synchronous direct writes from partners into production databases |

---

## 3. Current to target map

| Current | Target | How to move | Notes |
|---|---|---|---|
| Kubernetes clusters in colocation | **GKE** regional clusters (Standard or Autopilot) | Re-deploy manifests and Helm charts through CI/CD; images to **Artifact Registry** | Containers port with minimal change. A fast win before the lease deadline |
| MySQL | **Cloud SQL for MySQL** (HA) | **Database Migration Service**, continuous (CDC) migration then cutover | Minimal downtime |
| MS SQL Server | **Cloud SQL for SQL Server** (HA) | Database Migration Service for SQL Server (backup-based continuous migration) | Licensing is included in Cloud SQL pricing |
| Redis | **Memorystore** (Valkey or Redis, Standard/HA) | Re-provision; caches can be rebuilt; use RDB import if state matters | |
| MongoDB | **MongoDB Atlas** on Google Cloud Marketplace (least change) or **Firestore with MongoDB compatibility** | Atlas Live Migration / mongodump-restore | Choose Atlas for full MongoDB feature parity |
| Microsoft Active Directory | **Cloud Identity** with **Google Cloud Directory Sync** (users and groups) + SAML SSO to AD FS or Entra ID; or **Workforce Identity Federation** | GCDS one-way sync; AD stays the source of truth | **Managed Service for Microsoft AD** if workloads need domain join |
| Open-source monitoring, email alerts | **Google Cloud Observability** + Managed Service for Prometheus | Dual-run during migration | Alert routing to on-call, SLO-based alerting |
| Legacy insurance integrations (on-premises) | **Retained**, reached over Interconnect | None (by design) | Revisit when replacement is scheduled |
| Colocation DR | Cross-region DR on Google Cloud | Cloud SQL cross-region read replica (promotable), GKE in a second region, **Backup for GKE**, **Backup and DR Service** | The "adapt their DR plan" requirement |

---

## 4. Reference architecture

```text
                     Customers (multinational)          Insurance providers (new)
                              │                                  │
                  Global external Application LB           Apigee (API mgmt,
                  + Cloud Armor + Cloud CDN                 dev portal, quotas)
                              │                                  │
   ┌──────────────────────────┴────────── Google Cloud ──────────┴──────────────────────┐
   │ Org → Folders (prod / non-prod) → Projects per env      Org policies, VPC SC (PHI)  │
   │                                                                                     │
   │  Region A (primary)                          Region B (DR)                          │
   │  ┌───────────────────────────────┐          ┌──────────────────────────────┐       │
   │  │ Regional GKE (3 zones), fleet │          │ Regional GKE (scaled down)   │       │
   │  │ Config Sync + Policy Ctrl     │          │ restored via Backup for GKE  │       │
   │  │ Cloud SQL MySQL HA ───────────┼─ async ─▶│ Cloud SQL cross-region replica│      │
   │  │ Cloud SQL SQL Server HA       │          │                              │       │
   │  │ Memorystore (HA)  Atlas/Firestore         │                              │       │
   │  └──────────────┬────────────────┘          └──────────────────────────────┘       │
   │                 │ Datastream CDC / Pub/Sub → Dataflow                               │
   │                 ▼                                                                   │
   │        BigQuery (+ BigQuery ML) ──▶ Looker reports;  Cloud Healthcare API (FHIR)     │
   │                                                                                     │
   │  Cloud Monitoring / Logging (aggregated sinks, SLOs, burn-rate alerts → on-call)    │
   │  Cloud Build → Artifact Registry → Cloud Deploy (canary) → GKE                      │
   └───────────────────────────────┬─────────────────────────────────────────────────────┘
                                   │ Dedicated Interconnect (redundant) + HA VPN backup
                                   │ Cloud Router (BGP)
                     ┌─────────────┴─────────────┐
                     │ Remaining colocation DC   │  Legacy insurance integrations (retained)
                     │ Microsoft AD ──GCDS──▶ Cloud Identity (SSO via SAML)
                     └───────────────────────────┘
```

---

## 5. Phased plan

| Phase | Goal | Key actions |
|---|---|---|
| **0 · Foundation (weeks)** | Landing zone | Resource hierarchy, Cloud Identity + GCDS + SSO, Shared VPC, Interconnect order (lead time) plus HA VPN immediately, org policies, logging sinks, BAA |
| **1 · Lease-driven move** | Exit the expiring colocation facility first | Move containerized apps to GKE; databases via DMS continuous migration; cut over per application; rehost any VMs with **Migrate to Virtual Machines** |
| **2 · Reliability and operations** | Meet 99.9% and fix monitoring | Regional HA everywhere, SLOs, burn-rate alerts, Config Sync, Cloud Deploy canaries, DR region and tested runbooks |
| **3 · Data and insights** | Healthcare trend analytics | Datastream to BigQuery, de-identification, BigQuery ML forecasts, Looker |
| **4 · Partner scale** | Fast onboarding | Apigee developer portal, standard ingestion templates, Healthcare API |

---

## 6. Security, operations and cost views

**Security and compliance**

* Groups mapped from AD drive IAM. No basic roles; predefined roles per environment folder.
* Workload Identity Federation for GKE (no service account keys); Secret Manager for credentials.
* VPC Service Controls perimeter around projects holding patient data; Private Google Access; no public IPs on nodes (**private GKE clusters**).
* Data Access audit logs on for services handling patient data; logs retained per policy in locked log buckets.
* CMEK where policy demands customer-controlled keys; Sensitive Data Protection to de-identify data used for analytics and ML.

**Operations**

* SLOs on every customer-facing service. Alert on burn rate to an on-call rotation and stop email-only alerts.
* GitOps (Config Sync) prevents the "misconfigured systems" outages. Policy Controller blocks non-compliant manifests.
* Autoscaling (HPA plus cluster autoscaler, or Autopilot) answers "inadequate capacity to manage spikes".

**Cost**

* Committed use discounts for the steady GKE and Cloud SQL baseline.
* Autoscaling for growth; rightsizing recommendations after migration.
* Retire colocation contracts as waves complete (CapEx to OpEx).

---

## 7. Likely question themes

* **"How should EHR connect its remaining on-premises systems?"** → Dedicated Interconnect, redundant per the SLA, plus HA VPN backup. Not a migration of legacy systems.
* **"How should EHR manage users for Google Cloud?"** → Keep AD as source of truth; GCDS to Cloud Identity plus SAML SSO, or Workforce Identity Federation.
* **"Which database service for the MySQL workloads with minimal downtime migration?"** → Cloud SQL for MySQL HA with Database Migration Service.
* **"How to provide consistent management of container environments?"** → GKE fleets with Config Sync and Policy Controller; Cloud Deploy.
* **"Alerts are ignored. What should they do?"** → SLO-based alerting in Cloud Monitoring routed to on-call channels; dashboards; fewer, actionable alerts.
* **"Design for 99.9%"** → regional (multi-zone) GKE and Cloud SQL HA. Multi-region isn't required for 99.9%, but DR to a second region is part of "adapt their DR plan".
* **"Retain logs for compliance"** → aggregated sink to a log bucket with a retention policy (and a lock if it must be immutable).
* **"Onboard providers faster"** → Apigee plus standardized ingestion (Pub/Sub, Dataflow, Healthcare API).
* **"Ensure that PHI can't be exfiltrated to unauthorized projects"** → VPC Service Controls.
* **"Generate predictions on trends with the least effort"** → BigQuery ML.

Graded practice: [08/07-case-study-drill.md](../08-Exam-Questions-and-Sample-Papers/07-case-study-drill.md) (EHR section), Mock 1 and Mock 3.
