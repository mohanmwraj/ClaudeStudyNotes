# 01 · Case-Study Method

Each exam includes **two** of the four published case studies, and case-study questions are **20–30%** of the exam: roughly 10–18 questions. That makes them the highest-yield preparation you can do. You know the four companies in advance, so every minute spent here pays off directly.

| Case study | Industry | Starting point | Dominant themes | Breakdown |
|---|---|---|---|---|
| **EHR Healthcare** | Healthcare SaaS | Colocation data centers; one lease expiring | Migration under a deadline, 99.9% availability, hybrid connectivity, regulated data, containers at scale, observability | [02-ehr-healthcare.md](02-ehr-healthcare.md) |
| **Cymbal Retail** | Online retail | Mixed on-premises and cloud; many databases; IVR call center | Generative AI for catalog content, conversational commerce, product discovery, stack modernization | [03-cymbal-retail.md](03-cymbal-retail.md) |
| **Altostrat Media** | Media and content | Already on Google Cloud (GKE, Cloud Storage, BigQuery, Cloud Run functions) plus legacy on-premises ingestion | Generative AI on media, content safety, explainable AI, hybrid Kubernetes, storage cost, CI/CD | [04-altostrat-media.md](04-altostrat-media.md) |
| **KnightMotives Automotive** | Automotive manufacturer | Mostly on-premises plus other clouds; mainframe; outdated ERP | Hybrid and multicloud, data monetization, security after breaches, EU data protection, autonomous-driving AI, dealer tooling | [05-knightmotives-automotive.md](05-knightmotives-automotive.md) |

---

## 1. How each breakdown is organized

Every case file in this folder uses the same structure, so you can compare companies:

1. **Snapshot:** the company in five lines.
2. **Standing constraints:** the requirements that silently apply to *every* question about the company. Memorize these.
3. **Requirement decomposition:** each official business and technical requirement mapped to the constraint it implies, the Google Cloud design that satisfies it, the principle behind it and the trap to avoid.
4. **Current to target map:** each existing system mapped to its Google Cloud destination and migration tool.
5. **Reference architecture:** one diagram of a design that satisfies all requirements together.
6. **Phased plan:** what to do first and why.
7. **Security, operations and cost views.**
8. **Likely question themes:** short "if asked X, think Y" prompts.

---

## 2. The reading technique (use it on any scenario)

Read a case study in four passes:

| Pass | Look for | Write down |
|---|---|---|
| 1. **Business driver** | Why they're changing: growth, cost, deadline, AI ambition, competition | One sentence: "They need X because Y" |
| 2. **Hard constraints** | Numbers (99.9%, five years), regulations (health, EU, PCI), "no plan to", "no budget", "must" | The standing-constraints list |
| 3. **Existing estate** | Every named technology: databases, Kubernetes, identity provider, monitoring tools, integration styles | A current to target table |
| 4. **Pain points** | Words like *unreliable*, *ignored*, *misconfigured*, *manual*, *siloed*, *outdated* | Each pain point paired with the capability that fixes it |

Executive statements matter. They usually name the tie-breaker pillar:

* Altostrat: *"Reliability and cost management are our top priorities."*
* EHR: outages from *"misconfigured systems, inadequate capacity to manage spikes in traffic, and inconsistent monitoring practices."*
* KnightMotives: safety and data.
* Cymbal: efficiency, experience and conversion.

---

## 3. Patterns shared across the four companies

Several needs appear in more than one case study. Learn each pattern once:

| Pattern | Appears in | Standard Google Cloud answer |
|---|---|---|
| MySQL + SQL Server + Redis + MongoDB estate | EHR, Cymbal | Cloud SQL (MySQL, SQL Server) via Database Migration Service; Memorystore (Valkey/Redis); MongoDB Atlas on Google Cloud Marketplace or Firestore with MongoDB compatibility |
| Open-source monitoring with email alerts that get ignored | EHR, Cymbal, Altostrat | Google Cloud Observability: Cloud Monitoring and Logging, Managed Service for Prometheus, SLOs with burn-rate alerts routed to on-call tooling (PagerDuty, Slack, Pub/Sub webhooks) |
| Existing Kubernetes clusters | EHR, Cymbal, Altostrat | GKE (regional clusters), fleets with Config Sync and Policy Controller, Cloud Deploy for delivery |
| Secure, high-performance hybrid connectivity | EHR, Altostrat, KnightMotives | Dedicated or Partner Interconnect in an SLA topology; HA VPN as backup or interim; Cloud Router with BGP |
| Legacy file and batch integrations (SFTP, ETL, file-based) | EHR, Cymbal | Keep or wrap them initially; land files in Cloud Storage; event-driven processing with Pub/Sub, Dataflow or Cloud Run; APIs through Apigee for new partners |
| Third-party / enterprise identity (Active Directory, external IdPs) | EHR, Altostrat | Cloud Identity with Google Cloud Directory Sync and SAML SSO, or Workforce Identity Federation; Managed Service for Microsoft AD for AD-dependent workloads |
| Generative AI with human or safety controls | Cymbal (HITL), Altostrat (harmful content, explainability), KnightMotives (safety) | Gemini on Agent Platform with grounding, Model Armor, safety filters, human-in-the-loop review, evaluation and logging |
| Analytics and predictions on business data | All four | BigQuery as the analytical core; BigQuery ML or Agent Platform for predictions; Looker or Data Studio for reports |

---

## 4. Answering a case-study question: a checklist

* [ ] Which company? Recall its standing constraints.
* [ ] Which requirement is this question really testing? Find its row in the decomposition table.
* [ ] Does any option contradict a standing constraint? Eliminate it.
* [ ] Of the remaining options, which satisfies *additional* case requirements as a side effect? That's usually the intended answer.
* [ ] Is the option consistent with the company's existing estate? Google's answers usually build on what the company already runs, such as Altostrat's GKE and BigQuery or EHR's Kubernetes, rather than replacing it.

Graded case-study practice: [08-Exam-Questions-and-Sample-Papers/07-case-study-drill.md](../08-Exam-Questions-and-Sample-Papers/07-case-study-drill.md) has 40 questions (10 per company), and every mock paper includes questions on two case studies.
