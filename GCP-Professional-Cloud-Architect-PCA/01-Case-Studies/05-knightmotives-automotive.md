# 05 · KnightMotives Automotive: Case-Study Breakdown

Official text: [KnightMotives Automotive case study (PDF)](https://services.google.com/fh/files/misc/v6.1_pca_knightmotives_automotive_case_study_english.pdf). Requirements below are quoted or closely paraphrased from it; everything else is this kit's analysis.

---

## 1. Snapshot

* Car manufacturer of **autonomous, self-driving vehicles**: BEVs, hybrids and ICE vehicles.
  * The BEV in-vehicle experience is modern.
  * Hybrid and ICE vehicles lag behind, and that's hurting sales and satisfaction.
* Goals:
  * modernize the consumer experience across **all** vehicles within **five years** using **AI** (in-vehicle, shopping, buying, service);
  * fix an **unreliable online build-to-order system** that strains dealer relationships;
  * give mechanics and salespeople better tools.
* Strategy: from "manufacturing cars" to an **"automotive experience"**. That means:
  * consistency across models;
  * AI features;
  * **data monetization**;
  * digital differentiation;
  * dealer and mechanic tooling.
* Estate:
  * mostly **on-premises** plus some apps on **other major clouds**;
  * an **outdated mainframe** (supply chain) and an outdated ERP;
  * **dealers have no budget for new equipment**;
  * fragmented vehicle code bases;
  * poor network connectivity to plants and to vehicles in rural areas.
* Security is **paramount after past breaches**. **EU data protection** compliance is critical, especially for autonomous platforms.

> ### Standing constraints (apply to every KnightMotives question)
>
> 1. **Security first**: past breaches → defense in depth, detection and response, an incident response plan, training.
> 2. **EU data protection**: residency, minimization, pseudonymization, sovereignty controls for EU data.
> 3. **Hybrid and multicloud**: an explicit "hybrid cloud strategy"; on-premises and other clouds remain for now.
> 4. **Dealers have no budget for new equipment** → browser- or SaaS-delivered dealer tools, no new hardware at dealerships.
> 5. **Unreliable connectivity** (rural vehicles, plants) → edge processing, store-and-forward, asynchronous ingestion.
> 6. **Data is siloed and AI infrastructure is obsolete** → a unified governed data platform plus modern AI infrastructure.
> 7. **People**: upskilling, attracting talent, and better business–technical communication.

---

## 2. Requirement decomposition

### Business requirements

| Requirement | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| Personalized relationship with the driver; cohesive experience across all models | A shared customer profile and a shared software and AI platform across vehicles | Customer data platform in **BigQuery**; consistent in-vehicle services backed by cloud APIs (**Apigee**); Gemini-powered features with a common back end | P16 | Separate stacks per vehicle line |
| Better **build-to-order** model: less time on the lot, transparency for dealers and customers | A reliable ordering platform with real-time status | Re-architect the configurator and ordering on **GKE / Cloud Run** (regional, autoscaled) with **Spanner** or **Cloud SQL HA**; event-driven order status (Pub/Sub) integrated with supply chain and ERP; dealer portal | P3, P8, P2 | Patching the unreliable monolith with bigger servers |
| **Monetize corporate data** to finance new technology; AI infrastructure obsolete; data siloed | Governed data products plus modern AI | **BigQuery** lakehouse (with **Google Cloud Lakehouse** for open Iceberg tables); **Knowledge Catalog** for governance and lineage; **BigQuery sharing** (formerly Analytics Hub) exchanges and **data clean rooms** for partners; **Sensitive Data Protection** de-identification; consent management | P10, P11 | Selling raw, identifiable driver data; exporting copies to buyers |
| **Security is paramount** due to past breaches | A comprehensive security program | **Security Command Center (Enterprise/Premium)** for posture and threats; **Google Security Operations** (SIEM/SOAR) for detection and response; org policies, VPC SC, CMEK; Mandiant incident response services; least privilege | P6, P7 | Point tools without centralized detection |
| Adherence to **EU data protection** regulations, especially for autonomous platforms | Residency and sovereignty for EU personal data | EU regions only for EU data (`gcp.resourceLocations` org policy); **Assured Workloads** with EU data-boundary / sovereign controls; **Cloud EKM** or CMEK for key custody; Access Transparency; pseudonymize before analytics | P10, P11, P7 | Global multi-region datasets holding EU personal data |
| Fully autonomous driving investment, initial rollout in favorable regulatory regions | Large-scale ML training and simulation, region-aware deployment | **AI Hypercomputer**: TPUs/GPUs, Managed Training Clusters, **Dynamic Workload Scheduler**; simulation on GKE with GPUs (Spot for batch simulation); data in Cloud Storage and BigQuery | P16, P9 | On-premises GPU purchases with a five-year horizon |
| Employee upskilling, talent, business–technical communication | Change and skills management | Training paths and certification (Google Skills, formerly Cloud Skills Boost); a cloud center of excellence; pairing with partners; shared KPIs | Sect. 4.2 | "Hire contractors to do everything" |

### Technical requirements

| Requirement | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| **Modernize the in-vehicle experience**: consistent UX with AI across all models; update legacy hardware and software; reliable connectivity in rural areas for real-time AI | Hybrid edge–cloud AI with intermittent connectivity | Edge/on-device inference for latency-critical and offline features, with cloud **Gemini on Agent Platform** for richer features when connected; over-the-air updates; telemetry via a **partner MQTT broker → Pub/Sub** (store-and-forward when offline) → Dataflow → **Bigtable** (time series) and BigQuery | P8, P1, P16 | Cloud IoT Core (retired); always-online designs for rural areas |
| **Network upgrades**: more data traffic; better plant ↔ HQ connectivity | Enterprise WAN modernization | **Cloud Interconnect** (Dedicated or Partner) from HQ and plants; **Network Connectivity Center** as a hub (hybrid spokes; site-to-site data transfer across Google's backbone where supported); **HA VPN** for smaller sites; **Google Distributed Cloud connected** at plants for local processing | P14 | Point-to-point VPN mesh between every site |
| **IT infrastructure modernization**: a **hybrid cloud strategy**; gradually modernize or replace legacy systems | Phased modernization with a consistent hybrid platform | **GKE fleet** across Google Cloud, **attached clusters** in other clouds and **Google Distributed Cloud** on-premises; **Cross-Cloud Interconnect** to the other clouds; mainframe: keep it running, offload data with **Mainframe Connector** to BigQuery, modernize incrementally (validate in parallel before cutover); ERP: replatform or repurchase | P15, P5 | Big-bang mainframe rewrite; abandoning other clouds immediately |
| **Autonomous vehicle development and testing**: cutting-edge AI/ML, robust simulation, evolving regulations | Scale-out training and simulation with traceability | TPUs/GPUs via AI Hypercomputer; **Agent Platform Pipelines** for reproducible training; **Model Registry** for versioning and audit; simulation farms on GKE (GPU, Spot) or Batch; data lineage in Knowledge Catalog | P16, P12 | Unversioned ad-hoc training on workstations |
| **Data monetization and insights**: robust data platform, strict security and privacy, scalable AI/ML | As in the business row | BigQuery + Knowledge Catalog + BigQuery sharing / clean rooms; VPC SC; policy tags (column-level security); row-level security; Sensitive Data Protection | P10, P6 | Granting buyers direct project access |
| **Security and risk management**: comprehensive framework, **incident response plan**, **security awareness training** | Prevent, detect, respond, educate | SCC + Google SecOps (playbooks via SOAR); incident response runbooks and tabletop exercises; org-wide guardrails; training program; Mandiant for retainer and IR | P6, P13 | Technology only, with no process or training |
| **Delightful dealer and customer experience**: improve build-to-order; modern dealer tools (sales, service, inventory); a comprehensive **CRM** | Web-based tools, no dealer hardware; CRM | Dealer web apps on Cloud Run/GKE (work in existing browsers and devices); **repurchase** a SaaS CRM integrated through **Application Integration / Apigee**, or build on AlloyDB if differentiation demands; Gemini-powered assistants for mechanics (manuals grounded with **Agent Search**) | P5, P15, P16 | Requiring dealers to buy new terminals; building a CRM from scratch with no differentiation |

---

## 3. Current to target map

| Current | Target | Approach |
|---|---|---|
| On-premises IT | Hybrid: Google Cloud plus **Google Distributed Cloud** on-premises/at plants, one GKE fleet | Gradual (hybrid strategy) |
| Apps on other clouds | Keep for now; **attached clusters** in the fleet; **Cross-Cloud Interconnect**; BigQuery Omni or Lakehouse federation for data that stays there | Multicloud |
| Mainframe supply chain | **Retain** short term; **Mainframe Connector** to stream and copy data to BigQuery for analytics; modernize incrementally | Strangler pattern |
| Outdated ERP | Replatform (for example, SAP on certified Compute Engine VMs) or repurchase (SaaS ERP) | Disposition decision |
| Unreliable build-to-order system | Rebuilt on GKE/Cloud Run + Spanner or Cloud SQL HA + Pub/Sub events | Refactor or rebuild |
| Siloed corporate data | BigQuery + Lakehouse + Knowledge Catalog | Consolidate and govern |
| Obsolete AI infrastructure | Agent Platform + AI Hypercomputer (TPU/GPU, DWS) | Replace |
| Vehicle telemetry | MQTT broker (partner) → Pub/Sub → Dataflow → Bigtable/BigQuery | New |
| Dealer tools | Browser-based apps and a SaaS CRM | No new equipment |

---

## 4. Reference architecture

```text
 Vehicles (BEV/hybrid/ICE) ── intermittent cellular ──▶ Partner MQTT broker ──▶ Pub/Sub
   on-device / edge AI (offline)                                                 │
                                                                                 ▼
   Plants (Google Distributed Cloud connected) ──Interconnect──┐            Dataflow
   HQ data center (mainframe, ERP, GDC software) ─Interconnect─┤              │   │
   Other clouds (attached clusters) ── Cross-Cloud Interconnect┤        Bigtable  BigQuery
                                                               ▼        (telemetry) (lakehouse)
                       Network Connectivity Center hub (Google backbone)        │
                                                                                 ▼
 ┌──────────────── Google Cloud (EU regions for EU data) ────────────────────────────────────┐
 │ Org policies (resource locations = EU for EU folders), Assured Workloads (EU controls),   │
 │ VPC SC perimeters, CMEK / Cloud EKM, SCC Enterprise + Google SecOps (SIEM/SOAR)            │
 │                                                                                           │
 │ Build-to-order + dealer portal: Cloud Run / GKE (regional) → Spanner / Cloud SQL HA       │
 │      ↕ events (Pub/Sub) ↕ Apigee / Application Integration ↔ SaaS CRM, ERP, Mainframe Conn.│
 │                                                                                           │
 │ Data products: BigQuery + Knowledge Catalog (lineage, quality) → BigQuery sharing /       │
 │      data clean rooms → partners;  Sensitive Data Protection de-identification             │
 │                                                                                           │
 │ AI: Agent Platform (Gemini, Agent Search for manuals, Pipelines, Model Registry)          │
 │     AI Hypercomputer (TPU/GPU, Managed Training Clusters, DWS) for autonomy training;     │
 │     GKE GPU + Spot simulation farm                                                         │
 └───────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Phased plan (five-year horizon)

| Phase | Goal | Key actions |
|---|---|---|
| **1 · Secure foundation** | Security is paramount | Landing zone with EU folders and policies, SCC, SecOps, IAM hygiene, incident response plan, training |
| **2 · Customer-facing reliability** | Fix build-to-order and dealer pain | Rebuild ordering on managed, regional services; dealer web tools; CRM integration |
| **3 · Data foundation** | Break silos, enable monetization | BigQuery and Lakehouse, Knowledge Catalog, mainframe data offload, governance and consent |
| **4 · AI everywhere** | In-vehicle and dealer AI | Gemini features, telemetry pipeline, Agent Search for service manuals |
| **5 · Autonomy at scale** | Training and simulation | AI Hypercomputer, pipelines, model registry, regulatory traceability |

---

## 6. Security, operations and cost views

**Security** (the dominant lens for this company)

* Resource hierarchy separating EU and non-EU data with location policies.
* VPC SC around data products; CMEK or Cloud EKM; Access Transparency and Access Approval.
* Chrome Enterprise Premium / IAP for workforce zero-trust access from dealers and partners (no VPN appliances needed).
* SCC for misconfigurations and threats; SecOps for SIEM/SOAR; supply chain controls (Binary Authorization) for vehicle and cloud software.

**Operations**

* Fleet-wide policy (Config Sync, Policy Controller) across clouds.
* SLOs on ordering and dealer tools.
* Asynchronous, resilient telemetry ingestion tolerant of disconnection.

**Cost and finance**

* "A shift in financial priorities on a global scale" means CapEx to OpEx.
* Spot or DWS flex-start for training and simulation; CUDs for steady platforms.
* Data monetization revenue offsets investment.

---

## 7. Likely question themes

* **"Ingest telemetry from millions of vehicles with intermittent connectivity."** → A partner MQTT broker (or edge agent with store-and-forward) into Pub/Sub, then Dataflow, then Bigtable and BigQuery. Never Cloud IoT Core (retired).
* **"Ensure EU personal data stays in the EU."** → Resource-location org policy on EU folders, EU regional resources and Assured Workloads EU controls.
* **"Share data with partners for revenue without exposing PII."** → BigQuery sharing (Analytics Hub) listings or data clean rooms, plus de-identification with Sensitive Data Protection and policy tags.
* **"Dealers have no budget for new equipment."** → Browser-based tools hosted on Google Cloud; zero-trust access via Chrome Enterprise Premium; no dealer hardware.
* **"Manage Kubernetes across on-premises, Google Cloud and another cloud consistently."** → A GKE fleet with attached clusters and Google Distributed Cloud, plus Config Sync and Policy Controller.
* **"Detect and respond to threats after past breaches."** → Security Command Center plus Google Security Operations (SIEM/SOAR), an incident response plan and training.
* **"Train autonomous-driving models at scale cost-effectively."** → TPUs/GPUs via AI Hypercomputer with Dynamic Workload Scheduler or Spot for fault-tolerant jobs; checkpointing.
* **"Modernize the mainframe without risk."** → Retain, offload data (Mainframe Connector to BigQuery), modernize incrementally with parallel validation.
* **"Connect plants and HQ to Google Cloud and each other."** → Interconnect plus Network Connectivity Center hub.
* **"Improve the unreliable build-to-order system."** → Rebuild on regional managed services with autoscaling and event-driven integration to ERP and supply chain.

Graded practice: [08/07-case-study-drill.md](../08-Exam-Questions-and-Sample-Papers/07-case-study-drill.md) (KnightMotives section) and Mock 2.
