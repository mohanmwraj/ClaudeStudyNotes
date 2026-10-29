# 03/05 · Agent Platform: End-to-End ML Workflows and Prebuilt AI

**Exam guide:**

* **2.4:** "Leveraging Gemini Enterprise Agent Platform for end-to-end ML workflows": Agent Platform Pipelines, data integration, AI Hypercomputer, GPUs/TPUs, consumption models, large-scale training.
* **2.5:** "Configuring prebuilt solutions or APIs with Agent Platform": Google AI APIs, Gemini Enterprise (AI agents, NotebookLM), Model Garden.

**Principles:** P5, P9, P12, P16. Product selection is in [02/06](../02-Designing-and-Planning/06-ai-ml-solution-selection.md).

> Older questions may say *Vertex AI*, *Vertex AI Pipelines* or *Vertex AI Search*. The current names are **Agent Platform**, **Agent Platform Pipelines** and **Agent Search** (renamed 2026-04-22).

---

## 1. The ML lifecycle on Agent Platform

```text
 Data (BigQuery, Cloud Storage, operational DBs via Datastream)
   │  prepare/validate: Dataflow, BigQuery SQL, Managed Service for Apache Spark; labels: Data Labeling
   ▼
 Features ──▶ Agent Platform Feature Store (BigQuery-backed offline store; online serving)
   │
   ▼
 Train ──▶ AutoML (tabular, image, text, video) | custom training (containers, prebuilt frameworks)
   │      | Managed Training Clusters / GKE for large-scale; hyperparameter tuning (Vizier)
   │      | track runs in Experiments; metadata + lineage recorded automatically
   ▼
 Evaluate ──▶ Model Evaluation, Gen AI evals (for generative/agent systems), fairness/explainability
   ▼
 Register ──▶ Model Registry (versions, aliases like "champion", lineage, BigQuery ML models too)
   ▼
 Deploy ──▶ Endpoints (online inference, autoscaling, GPUs, traffic split between versions,
   │        private endpoints via PSC) | Batch Inference (bulk, offline) | GKE / Cloud Run GPUs
   ▼
 Monitor ──▶ Model Monitoring (training–serving skew, prediction drift, feature attribution drift)
   │        + Cloud Monitoring/Logging (latency, errors), request-response logging
   └──────▶ trigger retraining → back to Pipelines
```

**Agent Platform Pipelines** (formerly Vertex AI Pipelines) **orchestrates this whole loop**:

* Pipelines are defined with the **Kubeflow Pipelines SDK** (or TFX), compiled and run serverlessly.
* Each step is a container; artifacts and **lineage** are recorded in ML Metadata.
* **Step caching** skips unchanged steps.
* **Scheduled runs**, or event-triggered runs: new data in Cloud Storage → Eventarc → a **Cloud Run function** that submits the pipeline run.
* **Conditional deployment**: deploy only if the new model beats the champion on evaluation metrics.
* Reproducibility and auditability (KnightMotives' autonomy regulation; Altostrat's "auditable AI").

---

## 2. Preparing for Agent Platform data integration

| Concern | Recommended approach |
|---|---|
| Where training data lives | **BigQuery** (structured) and **Cloud Storage** (unstructured). Agent Platform reads both directly. Keep data and training in the **same region** |
| Data movement from operational systems | **Datastream** (CDC) or Dataflow into BigQuery; Storage Transfer for files |
| Feature consistency between training and serving | **Feature Store** (single definition, offline + online) to avoid training–serving skew |
| Data quality and governance | Knowledge Catalog data quality scans and lineage; schema validation steps in pipelines |
| Sensitive data | **Sensitive Data Protection** to discover and de-identify PII before training; BigQuery policy tags; least-privilege service accounts for pipelines |
| Security perimeter | **VPC Service Controls** around Agent Platform, BigQuery and Cloud Storage; **CMEK** for datasets, models and endpoints where required; **private endpoints** (PSC) for serving |
| Residency | Choose the Agent Platform region deliberately. Training, models and endpoints stay where you create them |
| Unstructured data for gen AI | Agent Search / RAG Engine data stores (from Cloud Storage, BigQuery, websites, connectors); chunking and embeddings managed for you |

---

## 3. AI Hypercomputer in practice

### Integrating GPUs and TPUs

| Use | Options |
|---|---|
| Custom training on accelerators | Agent Platform custom training with GPU/TPU machine specs; **Managed Training Clusters** (reserved, large-scale, Slurm-like experience); **GKE** with GPU/TPU node pools, **Kueue** (job queueing) and **JobSet** |
| Distributed training | Data/model parallelism; TPU **multislice**; high-bandwidth networking; **checkpoint** to Cloud Storage regularly (needed with Spot/flex capacity) |
| Fast data loading | **Hyperdisk ML** (read-only, many readers), **Managed Lustre**, Cloud Storage + **Rapid Cache**, Cloud Storage FUSE with caching |
| Serving | Agent Platform endpoints with GPUs; **GKE** inference (vLLM, JetStream, Triton; **GKE Inference Gateway** for model-aware routing); **Cloud Run with GPUs** for scale-to-zero inference; Model Garden **MaaS** for zero-ops open/partner models |
| Where Cloud Run functions fit | Lightweight, event-driven glue: trigger pipeline runs, pre/post-process requests, react to model-monitoring alerts. Not for heavy training or serving |

### Optimizing for consumption models

| Model | Best for | Trade-off |
|---|---|---|
| **On-demand** | Short, unplanned jobs | Highest price; capacity not guaranteed for scarce accelerators |
| **Spot** | Fault-tolerant, checkpointed training; batch inference | Preemption at any time |
| **Dynamic Workload Scheduler: flex-start** | Jobs that can wait for capacity; starts when all requested accelerators are available | Start time not guaranteed; lower price |
| **Dynamic Workload Scheduler: calendar mode** | Reserve accelerators for a fixed future window (for example, a 2-week training run starting Monday) | Must plan ahead |
| **Reservations** (+ CUDs) | Guaranteed capacity for production serving or critical training | Pay whether used or not |
| **CUDs** | Steady 24×7 serving fleets | 1–3 year commitment |
| Gen AI model consumption | Pay-as-you-go tokens vs **Provisioned Throughput**; **batch inference** for offline jobs | Throughput guarantees vs flexibility |

### Running large-scale AI training: a checklist

* [ ] Data staged near accelerators (same region), on a high-throughput store (Hyperdisk ML / Managed Lustre / Rapid Cache).
* [ ] Capacity strategy chosen (calendar mode or reservation for deadline-bound runs; flex-start or Spot for opportunistic ones).
* [ ] Checkpointing to Cloud Storage; automatic restart on failure or preemption.
* [ ] Orchestration: Agent Platform Pipelines or Managed Training Clusters / GKE with Kueue.
* [ ] Experiment tracking, model versioning in Model Registry, lineage captured.
* [ ] Cost guardrails: budgets, quotas, labels per team or project.

---

## 4. Prebuilt solutions and APIs (2.5)

### Differentiating the Google AI APIs

| Exam-guide category | Product to choose | Typical task |
|---|---|---|
| **Search** | **Agent Search** (enterprise/site search, RAG, structured data); **Agent Search for Commerce** (retail); Grounding with Google Search | Search your content in natural language; ground LLM answers |
| **Conversation** | **Conversational Agents** (Dialogflow CX) / Agent Conversation; Customer Engagement Suite (Agent Assist, Conversational Insights, CCaaS) | Chat and voice virtual agents, contact centers |
| **Vision** | **Cloud Vision API** (labels, OCR, faces, logos, landmarks, **SafeSearch**); **Document AI** (structured documents); Gemini for open-ended visual reasoning | Analyze images and documents |
| **Image** | **Imagen** (generate, edit, upscale, background replacement, inpainting); Gemini image models | Create or modify images (Cymbal variants) |
| **Video** | **Video Intelligence API** (labels, shots, explicit content, text, object tracking); **Veo** (generate video); **Transcoder API** (encode) | Analyze, generate or transcode video (Altostrat) |
| **Audio** | **Speech-to-Text** (Chirp models), **Text-to-Speech**, Gemini native audio understanding, Gemini Live API (real-time voice) | Transcribe, synthesize, converse by voice |
| Language | **Translation**, **Natural Language API** (entities, sentiment, classification), Gemini | Text understanding and translation |

### Gemini Enterprise features (AI agents and NotebookLM)

**Gemini Enterprise** (formerly Google Agentspace) is the **employee-facing** agent platform:

* **Enterprise search and chat** across connected sources (Google Workspace, Microsoft 365/SharePoint, Confluence, Jira, ServiceNow, Salesforce and others), **respecting source permissions**.
* **AI agents**: Google-built agents (for example, deep research) plus custom agents built with no-code designers or ADK and published to the organization's agent gallery, with admin governance.
* **NotebookLM** (Enterprise): source-grounded research and summarization over uploaded or connected documents, with citations.
* Enterprise controls: identity integration, data residency options, VPC SC and CMEK support, audit logging.

**Exam pattern:** "Employees need to find answers across Drive, SharePoint and Jira, and automate common tasks, with existing permissions respected and minimal development" → **Gemini Enterprise**. If the audience is **customers on a website or app**, it's **Agent Search / Conversational Agents** instead.

### Integrating Model Garden models

| Path | When |
|---|---|
| **MaaS (managed API)** for Gemini, partner models (for example Claude) and select open models | Zero infrastructure; pay per token; fastest integration |
| **Deploy to an Agent Platform endpoint** (one-click deploy of open models such as Gemma, Llama) | Need private serving, custom tuning or specific hardware; you pay for endpoint resources |
| **Deploy to GKE** (vLLM, etc.) | Full control, portability, shared GPU infrastructure, cost optimization at scale |
| **Tune** a Model Garden model | Behavior or style adaptation with labelled data (after prompting and RAG are exhausted) |

Check each model's **license and terms**, **regional availability** and **data-governance commitments** before choosing it for regulated workloads.

---

## 5. Reference: event-driven retraining (combining the pieces)

```text
New labelled data lands in gs://training-data ──Eventarc──▶ Cloud Run function
     │                                                           │ submits run
     ▼                                                           ▼
 BigQuery (curated) ◀── Dataflow preprocessing ◀──  Agent Platform Pipelines run:
                                                      1. validate data
                                                      2. train (Spot / DWS flex-start, checkpoints)
                                                      3. evaluate vs champion
                                                      4. if better → register in Model Registry
                                                      5. deploy to endpoint with 10% traffic split
 Model Monitoring (drift) ──alert──▶ Cloud Monitoring ──▶ on-call / auto-trigger pipeline
```

---

## 6. Traps

* **Orchestrating ML steps with ad-hoc cron scripts on VMs** instead of Agent Platform Pipelines (P5, P12).
* **Computing features differently in training and serving code** (skew). Use Feature Store or shared transformations.
* **On-demand accelerators for a deadline-critical multi-week run** without reservation or calendar mode (capacity risk).
* **Spot for training without checkpointing.**
* **Gemini Enterprise for a customer-facing storefront chatbot** (it's for employees), or Agent Search for internal Drive/Jira search when Gemini Enterprise fits better.
* **Self-hosting an open model on GKE when MaaS meets the requirement with zero ops**, unless control, cost at scale or privacy demands it.

---

## References

* Agent Platform release notes (names): <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>
* Pipelines introduction: <https://cloud.google.com/vertex-ai/docs/pipelines/introduction>
* Feature Store overview: <https://cloud.google.com/vertex-ai/docs/featurestore/latest/overview>
* Model Registry: <https://cloud.google.com/vertex-ai/docs/model-registry/introduction>
* AI Hypercomputer: <https://cloud.google.com/ai-hypercomputer/docs/overview>
* Gemini Enterprise: <https://cloud.google.com/gemini-enterprise>
* Model Garden: <https://cloud.google.com/model-garden>
