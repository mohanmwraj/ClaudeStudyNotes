# 01 · Exam Blueprint Decoded

This file covers what the Professional Cloud Architect (PCA) exam is, how it's built and what each objective actually tests, so you study the exam that exists and not one imagined from blog posts. Everything here was checked against Google's own pages on **2026-10-29**.

---

## 1. The exam at a glance

| Item | Value (verified 2026-10-29) |
|---|---|
| Name | Google Cloud Certified – Professional Cloud Architect |
| Length | 2 hours |
| Questions | 50–60, multiple choice (one answer) and multiple select (choose N) |
| Case studies | **2 per exam**, drawn from 4 published ones; case-study questions make up **20–30%** of the exam |
| Fee | USD 200 (plus tax) |
| Languages | English, Japanese |
| Delivery | Online-proctored (remote) or onsite at a testing center |
| Prerequisites | None. Recommended: 3+ years in industry, including 1+ year designing and managing solutions on Google Cloud |
| Validity | 2 years |
| Renewal exam | 1 hour, 25 questions, USD 100. Each renewal exam has 1 case study aligned to generative AI, and case-study questions make up 90–100% of it. Two case studies are available: Cymbal Retail and Altostrat Media |
| Passing score | Not published. You get a pass/fail result, not a score breakdown |

Sources: the [certification page](https://cloud.google.com/learn/certification/cloud-architect) and the [current exam guide (PDF)](https://services.google.com/fh/files/misc/professional_cloud_architect_exam_guide_english.pdf).

> **Version note.** The exam guide in force is the **v6.1** blueprint, which went live for English exams on **30 October 2025**. In 2026 Google re-issued it with updated product names. The most visible change: Sections 2.4 and 2.5 now say **Gemini Enterprise Agent Platform** and **Agent Platform Pipelines**, where earlier copies said Vertex AI and Vertex AI Pipelines. The certification page notes: *"This exam was updated to reflect recent branding changes. Refer to the exam guide to review product names used on the exam."* Questions may use either name, so learn both. See [05-product-name-rosetta.md](05-product-name-rosetta.md).

---

## 2. Who the exam thinks you are

The guide describes the candidate as someone who can *"design, develop, and manage robust, secure, scalable, efficient, cost-effective, highly available, and flexible solutions that drive business objectives,"* and says that familiarity with the **Google Cloud Well-Architected Framework** is *"a key requirement for this role."* The framework's six pillars are *"implicitly and explicitly woven throughout the exam objectives"*:

1. Operational excellence
2. Security, privacy, and compliance
3. Reliability
4. Cost optimization
5. Performance optimization
6. Sustainability

**What this means in practice:** almost every question is a trade-off between pillars. The right answer satisfies **every stated requirement**, then wins on the pillar the question emphasizes ("most cost-effective", "least operational overhead", "most secure"). [03-decoding-questions-and-elimination.md](03-decoding-questions-and-elimination.md) turns this into a repeatable procedure.

---

## 3. The six sections and what they really test

The weights are from the current guide. The "Really tests" column is this kit's reading of what questions on that objective look like, and the last column says where to study it.

### Section 1 · Designing and planning a cloud solution architecture (~25%)

| Obj. | Official scope (condensed) | Really tests | Study in |
|---|---|---|---|
| 1.1 | Business use cases, functional/non-functional requirements, business continuity, cost, integration patterns, data movement, trade-offs, workload disposition (build/buy/modify/deprecate), KPIs/ROI, security, observability | Turning a business sentence ("lease expires in 6 months", "reduce admin cost", "99.9% availability") into a technical constraint, and picking the option that meets all of them | [02/01](../02-Designing-and-Planning/01-business-requirements-to-architecture.md) |
| 1.2 | Well-Architected Framework, HA and failover, flexibility, scalability, performance and latency, **Gemini Cloud Assist**, backup and recovery | Zonal vs regional vs multi-regional design; RTO/RPO to DR pattern; autoscaling; what Gemini Cloud Assist is for | [02/02](../02-Designing-and-Planning/02-technical-requirements-ha-scalability-dr.md) |
| 1.3 | Hybrid/multicloud integration, **AI/ML solutions (Gemini, Agent Builder, Model Garden, AI Hypercomputer)**, cloud-native networking (VPC, peering, firewalls, load balancers, Shared VPC, Private Service Connect), data processing, storage types, mapping compute to GKE / Cloud Run / Cloud Run functions, Spot VMs, custom machine types | Product selection: the "which service?" questions. The largest single block of the exam | [02/03](../02-Designing-and-Planning/03-compute-selection.md), [02/04](../02-Designing-and-Planning/04-storage-and-database-selection.md), [02/05](../02-Designing-and-Planning/05-data-processing-selection.md), [02/06](../02-Designing-and-Planning/06-ai-ml-solution-selection.md) |
| 1.4 | Migration plan: integrate with existing systems, assess and migrate (**Migration Center**), methodologies, workload testing, network and dependency planning, **license implications** | Choosing a migration strategy and tool; wave planning; BYOL vs pay-as-you-go; sole-tenant nodes for licenses | [02/07](../02-Designing-and-Planning/07-migration-planning.md) |
| 1.5 | Future improvements, evolving business needs, cloud-first design | Choosing designs that don't block the next step (managed services, loose coupling, open standards) | [02/07](../02-Designing-and-Planning/07-migration-planning.md) §8 |

### Section 2 · Managing and provisioning a cloud solution infrastructure (~17.5%)

| Obj. | Official scope (condensed) | Really tests | Study in |
|---|---|---|---|
| 2.1 | Hybrid networking, multicloud (including Google Cloud to Google Cloud), security protection (intrusion protection, access control, firewalls), VPC design and load balancing | VPN vs Interconnect sizing and SLA topologies; Shared VPC vs peering vs PSC; Cloud NGFW, Cloud Armor and load-balancer choice | [03/01](../03-Managing-and-Provisioning/01-vpc-design-and-hybrid-networking.md), [03/02](../03-Managing-and-Provisioning/02-load-balancing-and-edge.md) |
| 2.2 | Storage allocation, processing and compute provisioning, security and access, transfer and latency, retention and lifecycle, growth planning, backup and recovery | Storage classes and lifecycle rules, retention locks, disk types, Backup and DR, transfer tools | [03/03](../03-Managing-and-Provisioning/03-storage-configuration-and-lifecycle.md) |
| 2.3 | Compute provisioning, Spot vs standard, network configuration for Compute Engine, GKE, serverless and **Google Cloud VMware Engine**, orchestration, patch management, container orchestration, serverless | MIGs and autoscaling, OS patching (VM Manager), GKE Autopilot vs Standard, Cloud Run networking, VMware Engine | [03/04](../03-Managing-and-Provisioning/04-compute-provisioning-gke-serverless.md) |
| 2.4 | **Gemini Enterprise Agent Platform** for end-to-end ML: **Agent Platform Pipelines**, data integration, **AI Hypercomputer** (GPUs/TPUs, consumption models, large-scale training) | MLOps pipeline shape; choosing GPU vs TPU and a consumption model (on-demand, Spot, reservations, Dynamic Workload Scheduler) | [03/05](../03-Managing-and-Provisioning/05-agent-platform-ml-workflows.md) |
| 2.5 | Prebuilt solutions/APIs: Google AI APIs (Search, Conversation, Vision, Image, Video, Audio), **Gemini Enterprise** (AI agents, NotebookLM), **Model Garden** | Picking the highest-level AI building block that fits | [03/05](../03-Managing-and-Provisioning/05-agent-platform-ml-workflows.md) |

### Section 3 · Designing for security and compliance (~17.5%)

| Obj. | Official scope (condensed) | Really tests | Study in |
|---|---|---|---|
| 3.1 | IAM, resource hierarchy, data security (keys, encryption, secrets), separation of duties, security controls (auditing, **VPC Service Controls**, context-aware access, **organization policy**, **hierarchical firewall policy**), **CMEK with Cloud KMS**, secure remote access (**IAP**, service account impersonation, **Chrome Enterprise Premium**, **Workload Identity Federation**), software supply chain, **securing AI (Model Armor, Sensitive Data Protection, secure model deployment)** | Least privilege at scale; which control stops which threat; key custody; keyless authentication; AI guardrails | [04/01](../04-Security-and-Compliance/01-iam-and-resource-hierarchy.md) to [04/04](../04-Security-and-Compliance/04-supply-chain-and-ai-security.md) |
| 3.2 | Legislation (health records, children's privacy, data privacy, ownership, sovereignty), commercial (PCI, PII), certifications (SOC 2), audits including logs | Mapping a regulation to controls: residency, de-identification, audit logs, Assured Workloads | [04/05](../04-Security-and-Compliance/05-compliance-and-audit.md) |

### Section 4 · Analyzing and optimizing technical and business processes (~15%)

| Obj. | Official scope (condensed) | Really tests | Study in |
|---|---|---|---|
| 4.1 | SDLC, CI/CD, troubleshooting and RCA, testing and validation of software and infrastructure, service catalog and provisioning, disaster recovery | Pipeline design, blameless postmortems, DR testing | [05/01](../05-Technical-and-Business-Processes/01-sdlc-cicd-testing.md), [05/02](../05-Technical-and-Business-Processes/02-troubleshooting-rca-and-dr-processes.md) |
| 4.2 | Stakeholder management, change management, team assessment and skills readiness, decision-making, customer success, cost and resource optimization (CapEx/OpEx), business continuity | The "soft" questions: training plans, phased change, FinOps, commitments | [05/03](../05-Technical-and-Business-Processes/03-business-processes-stakeholders-cost.md) |

### Section 5 · Managing implementation (~12.5%)

| Obj. | Official scope (condensed) | Really tests | Study in |
|---|---|---|---|
| 5.1 | Application and infrastructure deployment, **API management (Apigee)**, testing frameworks (load, unit, integration), data and system migration tooling, **Gemini Cloud Assist** | Advising teams: Apigee vs API Gateway; which test catches which defect; picking the migration tool | [06/01](../06-Managing-Implementation/01-advising-teams-deployment-apis.md) |
| 5.2 | Cloud Shell Editor, Cloud Code, Cloud Shell; SDKs (`gcloud`, `gsutil`, `bq`); **emulators (Bigtable, Spanner, Pub/Sub, Firestore)**; IaC (Terraform); API-access best practices; client libraries | Which tool for which job; local testing with emulators; retries with exponential backoff; quotas | [06/02](../06-Managing-Implementation/02-programmatic-interaction-iac.md) |

### Section 6 · Ensuring solution and operations excellence (~12.5%)

| Obj. | Official scope (condensed) | Really tests | Study in |
|---|---|---|---|
| 6.1 | The Well-Architected Framework's operational excellence pillar | Operational readiness, automation, incident management, continuous improvement | [07/02](../07-Operations-Excellence/02-sre-reliability-release-management.md) |
| 6.2 | Google Cloud Observability: monitoring and logging, profiling and benchmarking, alerting strategies | Metrics vs logs vs traces vs profiler; log routing and retention; SLO-based alerting | [07/01](../07-Operations-Excellence/01-observability-monitoring-logging.md) |
| 6.3–6.6 | Deployment and release management; supporting deployed solutions; quality control; reliability in production (chaos engineering, penetration and load testing) | Canary and blue/green, error budgets, support cases, chaos and load tests | [07/02](../07-Operations-Excellence/02-sre-reliability-release-management.md) |

---

## 4. What changed from older PCA material

If you pick up an older course, book or question bank, these differences will mislead you.

| Old material says | Current exam |
|---|---|
| Case studies Mountkirk Games, TerramEarth, Helicopter Racing League, Dress4Win | **Altostrat Media, Cymbal Retail, EHR Healthcare, KnightMotives Automotive**. Only EHR Healthcare survives from the older set |
| AI/ML is a minor topic | Two whole objectives (2.4, 2.5) plus AI in 1.3 and 3.1. Three of the four case studies are about generative AI |
| Vertex AI, Vertex AI Pipelines, Vertex AI Search, Agent Engine | Gemini Enterprise Agent Platform, Agent Platform Pipelines, Agent Search, Agent Runtime |
| Cloud Functions | Cloud Run functions (renamed August 2024) |
| Anthos / GKE Enterprise edition | Plain **GKE**: there is no longer an Enterprise tier, and fleet features are part of GKE (September 2025) |
| Dataproc, Cloud Composer, Dataplex | Managed Service for Apache Spark, Managed Service for Apache Airflow, Knowledge Catalog (April 2026) |
| BeyondCorp Enterprise | Chrome Enterprise Premium |
| Cloud IoT Core | Retired in August 2023. Use partner IoT platforms or MQTT brokers feeding Pub/Sub |
| Container Registry | Shut down. Use Artifact Registry |
| Section weights 24/15/18/18/11/14 | 25 / 17.5 / 17.5 / 15 / 12.5 / 12.5 |
| "Ensuring solution and operations **reliability**" | "Ensuring solution and operations **excellence**", anchored on the Well-Architected Framework |

---

## 5. How a question is built

Almost every PCA question has the same anatomy:

```text
[Context]      A company runs X, has constraint Y (compliance, budget, skills, timeline).
[Goal]         They need to achieve Z.
[Qualifier]    "following Google-recommended practices" / "most cost-effective" /
               "minimize operational overhead" / "with the least downtime".
[Ask]          What should you do?  (or: Which two actions should you take?)
[Options]      4 options for single-answer questions; 5 (choose 2) or 6 (choose 3)
               for multiple select.
```

* **The context contains the constraints.** Underline every adjective: *existing*, *legacy*, *global*, *regulated*, *spiky*, *small team*.
* **The qualifier picks between technically valid options.** Usually two or three options *work*. Only one works *and* best satisfies the qualifier.
* **Case-study questions** add a fifth element: the case study itself. A requirement buried in the case study, such as EHR's "99.9% availability" or KnightMotives' "EU data protection", can be the deciding constraint even when the question doesn't repeat it.

---

## 6. Logistics that cost people points

* **Read both case studies you'll get before the exam.** The case-study text is available during the exam, but reading it the first time under the clock wastes minutes. [01-Case-Studies](../01-Case-Studies/) breaks every requirement down for you.
* **There is no penalty for guessing.** Never leave a question blank. Mark uncertain questions for review and come back to them.
* **Budget your time.** 120 minutes for 50–60 questions is about 2 minutes per question. Do a first pass in about 85 minutes, flagging anything over 3 minutes, and use the rest for review.
* **Online proctoring rules are strict:** clear desk, a single monitor, no talking aloud, webcam and microphone on. Run the system check days before the exam, not minutes before.
* **Retakes:** if you fail, Google's policy imposes waiting periods that grow with each attempt. Check the current rules in the [certification help center](https://support.google.com/cloud-certification/) before you book.

---

## 7. Official resources (the only ones linked from this kit)

* [Certification page](https://cloud.google.com/learn/certification/cloud-architect): logistics, registration and renewal
* [Current exam guide (PDF)](https://services.google.com/fh/files/misc/professional_cloud_architect_exam_guide_english.pdf)
* Case studies (PDF): [Altostrat Media](https://services.google.com/fh/files/misc/v6.1_pca_altostrat_media_case_study_english.pdf) · [Cymbal Retail](https://services.google.com/fh/files/misc/v6.1_pca_cymbal_retail_case_study_english.pdf) · [EHR Healthcare](https://services.google.com/fh/files/misc/v6.1_pca_ehr_healthcare_case_study_english.pdf) · [KnightMotives Automotive](https://services.google.com/fh/files/misc/v6.1_pca_knightmotives_automotive_case_study_english.pdf)
* [Official sample questions (Google Form)](https://docs.google.com/forms/d/e/1FAIpQLSf54f7FbtSJcXUY6-DUHfBG31jZ3pujgb8-a5io_9biJsNpqg/viewform): take them once, after you finish this kit, as a calibration check. This kit never copies them.
* [Google Cloud Well-Architected Framework](https://cloud.google.com/architecture/framework)
* [Cloud Architecture Center](https://cloud.google.com/architecture)
