# 03 · Cymbal Retail: Case-Study Breakdown

Official text: [Cymbal Retail case study (PDF)](https://services.google.com/fh/files/misc/v6.1_pca_cymbal_retail_case_study_english.pdf). Requirements below are quoted from it; everything else is this kit's analysis. Cymbal is also one of the two case studies on the **renewal** exam.

---

## 1. Snapshot

* A fast-growing **online retailer** with a huge, multi-sub-vertical **product catalog** that's hard to manage.
* Three initiatives:
  * **Catalog and Content Enrichment:** generative AI creates attributes, descriptions and images from supplier data.
  * **Conversational Commerce with Product Discovery:** AI virtual agents on the website and app, using **Google Cloud's Discovery AI** to retrieve relevant products.
  * **Technical Stack Modernization:** cloud infrastructure, secure data handling, third-party integrations, proactive monitoring and security.
* The estate:
  * Mixed on-premises and cloud.
  * MySQL, SQL Server, Redis and MongoDB.
  * Kubernetes.
  * **Legacy SFTP and ETL batch integrations**.
  * A custom web app that searches by querying relational databases for names and categories.
  * An **IVR** routing calls to agents who **manually enter orders**.
  * Grafana, Nagios and Elastic for monitoring.
* Pain points: manual and error-prone processes, **data silos** with no unified customer view, and difficulty integrating new technology.

> ### Standing constraints (apply to every Cymbal question)
>
> 1. **Generative output must be reviewed by people** before it reaches the catalog (human-in-the-loop UI).
> 2. **Attributes must align with Cymbal's existing catalog structure** → constrained, schema-conformant generation, not free text.
> 3. **Natural-language product discovery** is a must, using Google's retail search capabilities (now **Agent Search for Commerce**, formerly Vertex AI Search for commerce / Discovery AI).
> 4. **Reduce call-center staffing and data-center hosting costs** → virtual agents deflect calls; migrate off data centers.
> 5. **Scale with an extensive and growing catalog** without hurting user experience.
> 6. **Customer data and virtual-agent interactions must be secure and compliant** (PCI for payments, privacy for PII).

---

## 2. Requirement decomposition

### Business requirements

| Requirement (quoted) | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| "Automate Product Catalog Enrichment: Reduce manual effort, minimize errors, and ensure accuracy and consistency across the product catalog." | Gen AI drafts content at scale; consistency is enforced by schema and review | **Gemini** (multimodal) on **Agent Platform** with **controlled generation** (response schema matching the catalog taxonomy); **Agent Platform Batch Inference** for bulk onboarding; HITL review before publishing | P16, P5 | Letting the model write straight to the live catalog; free-form text that ignores the taxonomy |
| "Improve Product Discoverability: Enhance search relevance and enable customers to find products more efficiently." | Replace keyword/SQL `LIKE` search with semantic, personalized retail search | **Agent Search for Commerce** (search, browse, autocomplete, recommendations) fed with the product catalog and user events | P16 | Building a custom vector search and ranking stack from scratch first |
| "Increase Customer Engagement: …interactive and personalized shopping experience… potentially reduce product returns." | Conversational, personalized help; better product information reduces returns | Conversational agents grounded in the catalog via Agent Search for Commerce; recommendations; accurate generated attributes | P16 | A static FAQ bot with no catalog grounding |
| "Drive Sales Conversion: …improve sales conversion rates and drive revenue growth." | Measure it: conversion is the KPI | Agent Search for Commerce optimization objectives; A/B testing; analytics in BigQuery | P13 | No success metric defined |
| "Reduce costs: Reduce call center staffing costs and data-center hosting costs." | Deflect calls to self-service; leave the data center | **Customer Engagement Suite**: Conversational Agents in voice and chat to replace the IVR menu and complete orders; **Agent Assist** for remaining human agents; migrate workloads to managed services | P9, P5 | Keep the IVR and hire more agents; lift-and-shift with no managed services |

### Technical requirements

| Requirement (quoted) | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| "Attribute Generation: Accurately derive relevant product attributes from various supplier data, including titles, descriptions, and images, ensuring the attributes align with the product category and Cymbal's existing catalog structure." | Multimodal extraction into a fixed schema | Gemini multimodal prompts with the category taxonomy in context; **response schema / JSON mode** so output is machine-validatable; few-shot examples from existing catalog entries; evaluation with Gen AI evals | P16 | Separate OCR, vision and NLP models stitched together when one multimodal model suffices; fine-tuning before trying prompting with schema constraints |
| "Image Generation and Enhancement: Generate different product image variations from a base image (e.g., showcasing various colors)… background changes, product color adjustments, and the addition of text overlays." | Image editing, not just text-to-image | **Imagen** on Agent Platform (image editing: inpainting, background replacement, variations) or **Gemini image generation and editing** models from Model Garden; text overlays can also be rendered deterministically in an image pipeline | P16 | Vision API (it *analyzes* images; it doesn't generate them) |
| "Automate Product Discovery: Process customer requests expressed in natural language and return highly relevant product results." | Semantic retail search | **Agent Search for Commerce** (the Discovery AI in the case study) | P16, P5 | Keyword search over Cloud SQL; BigQuery as an online search engine |
| "Scalability and Performance: …handle Cymbal's extensive product catalog and accommodate their anticipated growth…" | Managed and elastic | Agent Search for Commerce scales with the catalog; front ends on GKE Autopilot or Cloud Run with autoscaling; Memorystore cache; Cloud CDN for images | P3, P9 | Fixed-size VM fleet |
| "Human-in-the-Loop (HITL) Review: Provide a user interface (UI) for associates to review and manage Gen AI-generated content, allowing them to approve, reject, or modify suggestions before updating the product catalog." | A workflow with a draft state | Generated drafts stored in **Cloud SQL / AlloyDB / Firestore** with status; a review web app on **Cloud Run** behind **IAP** for associates; on approval, publish to the catalog and re-index Agent Search; feed rejections back into prompt and evaluation sets | P16, P6 | Auto-publish with occasional spot checks; giving associates direct database access |
| "Data Security and Compliance: Ensure all customer data, including product information and interactions with virtual agents, are handled securely and comply with relevant industry regulations." | PCI DSS for payments, privacy for PII, safe AI | **Sensitive Data Protection** to redact PII and card numbers from transcripts and logs; **Model Armor** to screen prompts and responses (prompt injection, sensitive data leakage); IAM least privilege; VPC Service Controls; CMEK if required; payment data kept out of LLM context (tokenized) | P11, P6, P16 | Sending raw card numbers through the LLM; logging full transcripts unredacted |

---

## 3. Current to target map

| Current | Target | How to move |
|---|---|---|
| MySQL | **Cloud SQL for MySQL** (or **AlloyDB** if it moves to PostgreSQL for performance) | Database Migration Service (continuous) |
| SQL Server | **Cloud SQL for SQL Server** | Database Migration Service for SQL Server |
| Redis | **Memorystore** (Valkey or Redis) | Re-provision; warm cache |
| MongoDB | **MongoDB Atlas** (Marketplace) or **Firestore with MongoDB compatibility** | Atlas live migration / dump-restore |
| Kubernetes clusters | **GKE** (Autopilot to reduce operations) | Redeploy via CI/CD; images to Artifact Registry |
| Custom catalog search (SQL queries on names and categories) | **Agent Search for Commerce** | Import the catalog (BigQuery or Cloud Storage), stream user events, integrate the API into the web app |
| IVR plus manual order entry | **Customer Engagement Suite**: Conversational Agents (voice and chat) with tools that call order APIs; **Agent Assist** for human agents; Conversational Insights for analytics | Phase calls over gradually; start with top intents |
| SFTP file transfers and ETL batch | Files land in **Cloud Storage**. Transfer options: **Storage Transfer Service** agents for on-premises file systems, or an SFTP gateway in front of Cloud Storage for partners that insist on SFTP. Processing: **Dataflow** or **Managed Service for Apache Spark**, orchestrated by **Managed Service for Apache Airflow** (formerly Cloud Composer), or replaced by **Application Integration / Integration Connectors** for SaaS | Wave by integration |
| Data silos | **BigQuery** as the unified customer and commerce analytics platform; **Datastream** CDC from operational databases; Knowledge Catalog for governance | |
| Grafana, Nagios, Elastic | **Cloud Monitoring / Logging**, **Managed Service for Prometheus** (Grafana can keep querying it), uptime checks replace Nagios, Log Analytics replaces Elastic queries | Dual-run, then retire |

---

## 4. Reference architecture

```text
 Suppliers ──(files/API)──▶ Cloud Storage landing ──▶ Pub/Sub ──▶ Workflows / Cloud Run
                                                                   │
                         ┌─────────────────────────────────────────┘
                         ▼
   Gemini (multimodal, response schema = catalog taxonomy) + Imagen / image editing
                         │  drafts (status = PENDING)
                         ▼
   Cloud SQL / Firestore "drafts" ◀──▶ HITL Review UI (Cloud Run behind IAP) ── associates
                         │ approved
                         ▼
   Product catalog (system of record) ──▶ Agent Search for Commerce (index, rank, recs)
                                                   ▲            │
   Web / mobile app (GKE or Cloud Run) ────────────┘            │
        │  chat & voice                                          │
        ▼                                                        │
   Conversational Agents (Customer Engagement Suite) ── tools ──▶ Order / inventory APIs
        │  guardrails: Model Armor; PII redaction: Sensitive Data Protection
        ▼
   Agent Assist for remaining human agents

   Operational DBs (Cloud SQL, Memorystore, Atlas) ──Datastream──▶ BigQuery (unified view,
   conversion analytics, BigQuery ML) ──▶ Looker / Data Studio
   Observability: Cloud Monitoring + Managed Prometheus + Logging; SLOs on search & checkout
```

---

## 5. Phased plan

| Phase | Goal | Key actions |
|---|---|---|
| **1 · Quick AI value** | Catalog enrichment with HITL | Gemini attribute and description generation in batch; review UI; measure acceptance rate and error rate |
| **2 · Discovery** | Better search, then conversion | Agent Search for Commerce with catalog and user events; A/B test against legacy search |
| **3 · Conversational commerce** | Deflect calls | Conversational agents on web and app first, then voice in place of the IVR; Agent Assist |
| **4 · Modernize the stack** | Leave the data center | Databases via DMS; GKE; integrations to Cloud Storage plus event-driven processing; observability migration |
| **5 · Unified data** | Break silos | Datastream to BigQuery; customer 360; governance with Knowledge Catalog |

You could argue phase 4 should run in parallel, because "reduce data-center hosting costs" is a business requirement. In exam answers, the AI features are the stated core of the case, and infrastructure modernization supports them.

---

## 6. Security, operations and cost views

**Security**

* PCI scope minimization: card data handled by a PCI-compliant payment provider or tokenized; never placed in LLM prompts.
* Sensitive Data Protection inspects and de-identifies transcripts before storage or analytics.
* Model Armor templates on the virtual agent's prompts and responses.
* IAP on internal tools (the review UI); Workload Identity Federation for GKE; VPC SC around data projects.

**Operations**

* SLOs on search latency and checkout success; alerting to on-call.
* Track gen-AI quality KPIs: attribute acceptance rate, edit distance, returns rate.

**Cost**

* Batch inference for bulk catalog work, which is cheaper than online calls.
* Autoscaling front ends; CUDs for the steady database baseline.
* Call deflection reduces staffing cost; retire data-center hosting.

---

## 7. Likely question themes

* **"How should Cymbal improve natural-language product search with the least custom development?"** → Agent Search for Commerce (Vertex AI Search for commerce / Discovery AI).
* **"Generated attributes must match the existing taxonomy."** → Gemini with a response schema or controlled generation plus few-shot examples, then validation and HITL.
* **"Associates must approve generated content."** → a draft store plus a review UI on Cloud Run behind IAP; publish on approval.
* **"Create color variants and new backgrounds from one product photo."** → Imagen (or Gemini image) editing on Agent Platform, not the Vision API.
* **"Reduce call center costs."** → Conversational agents (Customer Engagement Suite) that handle orders end to end, with Agent Assist for escalations.
* **"Protect customer PII in chat logs."** → Sensitive Data Protection de-identification; Model Armor for sensitive-data leakage in responses.
* **"Unify customer data across MySQL, SQL Server and MongoDB for analytics."** → Datastream (CDC) to BigQuery.
* **"Replace Nagios, Grafana and Elastic with minimal effort."** → Cloud Monitoring uptime checks and alerting, Managed Service for Prometheus with Grafana, Cloud Logging and Log Analytics.
* **"Bulk-generate descriptions for 2 million SKUs cost-effectively."** → Agent Platform Batch Inference with Gemini.
* **"Ensure the virtual agent can't be tricked into revealing other customers' data."** → Model Armor (prompt injection, jailbreak), tool-level authorization and IAM, least-privilege tools.

Graded practice: [08/07-case-study-drill.md](../08-Exam-Questions-and-Sample-Papers/07-case-study-drill.md) (Cymbal section) and Mock 1.
