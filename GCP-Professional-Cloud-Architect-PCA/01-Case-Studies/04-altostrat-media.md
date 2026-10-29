# 04 · Altostrat Media: Case-Study Breakdown

Official text: [Altostrat Media case study (PDF)](https://services.google.com/fh/files/misc/v6.1_pca_altostrat_media_case_study_english.pdf). Requirements below are quoted from it; everything else is this kit's analysis. Altostrat is also one of the two case studies on the **renewal** exam.

---

## 1. Snapshot

* A media company with a large library of **podcasts, interviews, news broadcasts and documentaries** (audio, video and documents).
* Wants **generative AI** for:
  * personalized recommendations, natural-language interaction and self-service support;
  * revenue through dynamic pricing, targeted marketing and personalized product suggestions.
* **Already on Google Cloud**:
  * **GKE** for the content management and delivery platform;
  * **Cloud Storage** for the media library;
  * **BigQuery** as the primary warehouse;
  * **Cloud Run functions** for event-driven transcoding, metadata extraction and recommendations.
* **Legacy on-premises systems** for **content ingestion and archival**, slated for migration "in the near future".
* Identity is **Google Identity plus third-party IdPs**. Monitoring is **Cloud Monitoring plus Prometheus**, with **email alerts**.
* Executive statement: **"Reliability and cost management are our top priorities."**

> ### Standing constraints (apply to every Altostrat question)
>
> 1. **Build on the existing Google Cloud estate** (GKE, Cloud Storage, BigQuery, Cloud Run functions). Don't replace it.
> 2. **Reliability and cost are the tie-breakers** (executive statement).
> 3. **Hybrid**: on-premises ingestion and archival for now, so there's hybrid connectivity *and* Kubernetes on-premises *and* in the cloud.
> 4. **AI must be safe and accountable**: harmful-content detection, and "AI systems are auditable and their decisions can be explained".
> 5. **Media at scale**: storage costs must fall while availability is maintained, and volumes keep growing.

---

## 2. Requirement decomposition

### Business requirements

| Requirement (quoted) | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| "Accelerate and enhance the reliability of operational workflows across all environments. [Google Cloud + On-premises]" | Consistent automation and reliability across hybrid | GKE **fleets** spanning GKE on Google Cloud and **Google Distributed Cloud (software only)** on-premises; **Config Sync** and **Policy Controller**; CI/CD with **Cloud Build + Cloud Deploy**; **Workflows** / Eventarc for event-driven operations; SLOs | P12, P13 | Separate tooling per environment |
| "Simplify infrastructure management for rapid application deployment." | Less toil, faster releases | **GKE Autopilot** where possible; **Cloud Run** for stateless services; IaC; Cloud Deploy pipelines | P5 | Moving the platform to self-managed VMs |
| "Optimize cloud storage costs while maintaining high availability and scalability for media content." | Right storage class per access pattern, without losing availability | **Cloud Storage Autoclass** (automatic class transitions per object), or **lifecycle rules** Standard → Nearline → Coldline → Archive for aging content; keep hot content in Standard in a multi-region or dual-region bucket; **Media CDN / Cloud CDN** to cut egress and origin reads | P9, P10 | Archive class for content still viewed weekly; moving media off Cloud Storage to cheaper "disks" |
| "Enable natural language interaction with the platform with 24/7 user support." | A conversational agent grounded in Altostrat content and help docs | **Conversational Agents** (Dialogflow CX) or an **ADK agent on Agent Runtime** grounded via **Agent Search** over help content and metadata; Gemini as the model; human handoff | P16 | A rules-only FAQ bot; a staffed support desk only |
| "Automatically generate concise summaries of media content." | Multimodal summarization | **Gemini** multimodal (native audio and video input) via Agent Platform; batch inference for the back catalog; **Speech-to-Text (Chirp)** transcripts as an input or alternative | P16 | Building a custom summarization model |
| "Extract rich metadata from media assets using NLP and computer vision." | Labels, entities, topics, faces/logos, shot changes, transcripts | **Gemini** multimodal extraction to a schema; or prebuilt **Video Intelligence API** (labels, shots, text, explicit content), **Vision API**, **Natural Language API**, **Speech-to-Text**; results stored in BigQuery | P16, P5 | Training custom vision models first |
| "Detect and filter inappropriate content." | Moderation of uploaded and generated content | **Video Intelligence explicit content detection** and **Vision SafeSearch** for media; **Gemini safety filters** plus **Model Armor** for chatbot prompts and responses; HITL review queue for borderline cases | P16 | Relying only on user reports |
| "Analyze media content to identify trends and extract insights." | Analytics over metadata plus behavior | Metadata and engagement events in **BigQuery**; BigQuery ML; Gemini in BigQuery for unstructured analysis | P4 | Analytics on the GKE application database |
| "Inform content strategy and decision-making with data." | Dashboards and KPIs | **Looker** (governed semantic layer) or **Data Studio** over BigQuery | P13 | Ad-hoc CSV exports |

### Technical requirements

| Requirement (quoted) | What it really means | Google Cloud design | P | Trap |
|---|---|---|---|---|
| "Modernize CI/CD for containerized deployments with a centralized management platform." | One pipeline and one control plane for all clusters | **Cloud Build** → **Artifact Registry** (with vulnerability scanning) → **Cloud Deploy** (promotion and canary across GKE targets); fleet management with **Config Sync**; **Binary Authorization** | P12 | Per-team Jenkins servers on VMs |
| "Secure, high-performance hybrid cloud connectivity for data ingestion." | Large media files from on-premises ingestion | **Dedicated or Partner Interconnect** (high bandwidth), HA VPN backup; transfer with **Storage Transfer Service** (on-premises agents); **Transfer Appliance** for the archival back catalog if it's very large | P14, P10 | Public internet uploads; a single VPN tunnel for multi-Gbps ingest |
| "Provide scalable, performant kubernetes environments both on-premises and in the cloud." | Kubernetes on-premises managed like GKE | **Google Distributed Cloud (software only)** for VMware or bare metal on-premises, registered to the same **fleet** as GKE; one console and policy model | P5, P12 | Vanilla self-managed Kubernetes on-premises with separate tooling |
| "Optimize cloud storage costs for growing media volumes." | Same as the business requirement, with growth | Autoclass or lifecycle rules; object versioning with lifecycle cleanup; Storage Insights to analyze usage | P9 | Deleting content; Nearline for frequently accessed assets |
| "Design AI-powered detection of harmful content." | Moderation pipeline | An event-driven pipeline: upload → Cloud Storage → Eventarc → Cloud Run (or the existing Cloud Run functions) → Video Intelligence / Vision SafeSearch / Gemini classification → quarantine bucket + review queue | P8, P16 | A batch job that runs weekly |
| "Ensure that AI systems are auditable and their decisions can be explained" | Explainability and traceability | **Explainable AI** feature attributions for predictive models (recommendations, pricing); **model cards** and **Model Registry** lineage; log prompts, responses and model versions (Cloud Logging / BigQuery); **Gen AI evals**; **grounding with citations** for generative answers; **Cloud Audit Logs** | P16, P13 | A black-box third-party model with no logging |
| "Leverage LLMs and conversational AI for personalized experiences and content virality." | Personalization plus generative marketing copy | Gemini for personalized copy and teasers; **Recommendations** (Agent Search) for media; BigQuery user features | P16 | Generic, non-personalized content |
| "Develop advanced chatbots with natural language understanding to provide personalized assistance." | Agents with user context and tools | ADK agents on **Agent Runtime** (sessions, memory) or Conversational Agents with generative playbooks; tools to fetch the user's history; grounding | P16 | A keyword chatbot |
| "Automated summarization for diverse media." | Audio, video and text | Gemini multimodal; batch inference for the archive | P16 | Separate models per media type when one multimodal model works |

---

## 3. Current to target map

| Current | Target | Notes |
|---|---|---|
| GKE platform | Keep GKE; add **fleet** management, Autopilot where suitable, Cloud Deploy | Build on what exists |
| Cloud Storage media library | Keep; add **Autoclass** or lifecycle rules, Media CDN, **Rapid Cache** for read-heavy processing in a zone | |
| BigQuery warehouse | Keep; add BigQuery ML, Gemini in BigQuery, Looker | |
| Cloud Run functions (transcoding, metadata, recommendations) | Keep for event glue; move heavy transcoding to **Transcoder API** or Cloud Run jobs / GKE with GPUs if needed; move metadata extraction to Gemini or the Video Intelligence API | |
| On-premises ingestion and archival | Hybrid now (Interconnect plus Storage Transfer Service); migrate archive to **Cloud Storage Archive class** (Transfer Appliance for large archives); later move ingestion into Cloud Storage + Eventarc | "Slated for migration in the near future" |
| Kubernetes on-premises (implied) | **Google Distributed Cloud (software only)**, fleet-registered | |
| Google Identity + third-party IdPs | Cloud Identity with SAML SSO, or **Workforce Identity Federation** for workforce; **Identity Platform** for customer sign-in | |
| Cloud Monitoring + Prometheus, email alerts | **Managed Service for Prometheus**; alerting to PagerDuty, Slack or Pub/Sub; SLOs | |

---

## 4. Reference architecture

```text
 On-prem ingest/archive ──Interconnect + Storage Transfer Service──▶ Cloud Storage (landing)
        │ (Google Distributed Cloud, fleet member)                          │ Eventarc
        ▼                                                                  ▼
  ┌───────────── GKE fleet (cloud + on-prem) ─────────────┐    Cloud Run / functions pipeline:
  │ Config Sync · Policy Controller · Cloud Service Mesh  │     ├─ Transcoder API
  │ Cloud Build → Artifact Registry → Cloud Deploy        │     ├─ Gemini (summaries, metadata,
  │ Binary Authorization                                  │     │   moderation classification)
  └───────────────────────────────────────────────────────┘     ├─ Video Intelligence / Vision SafeSearch
                                                                ├─ quarantine bucket + HITL queue
                                                                ▼
  Cloud Storage media library (Autoclass / lifecycle) ──▶ Media CDN ──▶ viewers
                                                                │
  BigQuery (metadata, engagement events, features) ◀────────────┘
     ├─ BigQuery ML / Agent Platform models (recs, dynamic pricing) + Explainable AI
     ├─ Looker dashboards (content strategy)
     └─ Agent Search index (help content + catalog metadata)
                       │ grounding
  Chatbot: ADK agent on Agent Runtime / Conversational Agents ── Model Armor ── users (24/7)
  Audit: prompts/responses + model versions logged → BigQuery; Cloud Audit Logs; Gen AI evals
  Observability: Managed Prometheus + Cloud Monitoring SLOs → on-call (not email)
```

---

## 5. Phased plan

| Phase | Goal | Key actions |
|---|---|---|
| **1 · Reliability and cost foundation** | The top priorities | SLOs and alerting, Autoclass/lifecycle on media buckets, Media CDN, fleet + Config Sync, Cloud Deploy |
| **2 · AI on the library** | Metadata, summaries, moderation | Event-driven Gemini and Video Intelligence pipeline; backfill the archive with batch inference |
| **3 · Engagement** | Chatbot and personalization | Agent Search grounding, agent on Agent Runtime, Model Armor, Recommendations |
| **4 · Hybrid exit** | Migrate ingestion and archival | Interconnect, Storage Transfer, Transfer Appliance for archives, retire on-premises |
| **5 · Revenue** | Dynamic pricing and targeted marketing | BigQuery ML / Agent Platform models with explainability, experiments |

---

## 6. Security, operations and cost views

**Security**

* Workforce identity through Workforce Identity Federation for third-party IdPs, or Cloud Identity SSO.
* Identity Platform for end users.
* Workload Identity Federation for GKE; Binary Authorization; Artifact Analysis scanning.
* Model Armor on chatbot traffic; Sensitive Data Protection on transcripts if they contain PII.

**Operations**

* SLOs for streaming start time and API availability; burn-rate alerting.
* Managed Service for Prometheus keeps PromQL dashboards.
* Fleet-wide policies cut configuration drift.

**Cost (a top priority)**

* Storage: Autoclass or lifecycle rules.
* Egress: Media CDN.
* Compute: GKE Autopilot pay-per-pod; Spot node pools for batch transcoding and back-catalog AI jobs.
* AI: batch inference for the archive; CUDs for the steady GKE baseline.

---

## 7. Likely question themes

* **"Reduce storage cost for a growing library where access drops off over time, with no operational effort."** → Cloud Storage Autoclass (or lifecycle rules if access patterns are predictable).
* **"Run Kubernetes on-premises and in the cloud with one management model."** → Google Distributed Cloud (software only) plus GKE in one fleet, with Config Sync.
* **"Centralized CI/CD for containers."** → Cloud Build, Artifact Registry and Cloud Deploy.
* **"Summarize long video interviews."** → Gemini multimodal on Agent Platform (batch inference for the back catalog).
* **"Detect explicit content in uploaded videos."** → Video Intelligence API explicit content detection (or Gemini classification) in an event-driven pipeline, plus human review.
* **"Make AI recommendations explainable."** → Explainable AI feature attributions; log model versions and inputs; model cards.
* **"The chatbot must not produce harmful responses or leak data."** → Model Armor plus safety settings, and grounding.
* **"Alerts are only emailed."** → Managed Service for Prometheus and Cloud Monitoring alerting with on-call channels and SLOs.
* **"Move the on-premises archive (petabytes) to the cloud."** → Transfer Appliance into the Archive storage class.
* **"Ingest media continuously from on-premises."** → Interconnect plus Storage Transfer Service agents.

Graded practice: [08/07-case-study-drill.md](../08-Exam-Questions-and-Sample-Papers/07-case-study-drill.md) (Altostrat section), Mock 2 and Mock 3.
