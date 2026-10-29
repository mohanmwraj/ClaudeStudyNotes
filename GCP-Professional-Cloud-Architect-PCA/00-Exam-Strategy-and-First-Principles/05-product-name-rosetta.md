# 05 · Product Name Rosetta (2023–2026)

Google renamed a large part of its portfolio between 2024 and 2026. Most changes landed in **April 2026**, after the v6.1 exam blueprint was written. The certification page says the exam *"was updated to reflect recent branding changes"*, so a question can use the new name while your older notes use the old one. **Learn both.**

**Rule of thumb:** in almost every rename, only the product, console and documentation names changed. APIs, `gcloud` command groups, client libraries and IAM role names kept their old identifiers. For example, `gcloud dataproc`, `aiplatform.googleapis.com`, `dataplex.googleapis.com` and `roles/composer.*` still exist.

Every row below was checked against Google's documentation or release notes on 2026-10-29. Rows marked † are retirements, not renames.

---

## 1. AI and machine learning

| Old name | Current name | When | Notes |
|---|---|---|---|
| Vertex AI (platform) | **Gemini Enterprise Agent Platform** ("Agent Platform") | 2026-04-22 | Exam guide 2.4/2.5 use the new name |
| Vertex AI API | Agent Platform API | 2026-04-22 | Endpoint identifiers unchanged |
| Vertex AI Studio | **Agent Studio** | 2026-04-22 | Prompt design, tuning UI, App Builder |
| Vertex AI Agent Engine (Reasoning Engine) | **Agent Runtime** | 2026-04-22 | Managed runtime for agents (ADK, LangGraph, etc.); includes Memory Bank, Sessions, Code Execution |
| Vertex AI Search | **Agent Search** | 2026-04-22 | Enterprise search and RAG over your data. The console may still show "Vertex AI Search and AI Applications" |
| Vertex AI Search for commerce (formerly Retail Search, Discovery AI for Retail, Recommendations AI) | **Agent Search for Commerce** | 2026-04-22 | Cymbal's "Discovery AI" maps here |
| Recommendations from Vertex AI Search | Recommendations | 2026-04-22 | |
| Vertex AI Conversation | Agent Conversation | 2026-04-22 | |
| Vertex AI RAG Engine | RAG Engine | 2026-04-22 | |
| Vertex AI Vector Search / Vector Search 2.0 | Vector Search / **Agent Retrieval** | 2026-04-22 | |
| Vertex AI Model Garden | Model Garden | 2026-04-22 | Named in exam guide 1.3, 2.5 |
| Vertex AI Pipelines | **Agent Platform Pipelines** | 2026-04-22 | Named in exam guide 2.4 |
| Vertex AI Training / Prediction | Agent Platform Managed Training / Agent Platform Inference | 2026-04-22 | Endpoints → Agent Platform Endpoints |
| Vertex AI Feature Store, Model Registry, Workbench, Colab Enterprise, Experiments, Model Monitoring | Agent Platform Feature Store, Model Registry, Workbench, Colab Enterprise; Experiments on / Model Monitoring on Agent Platform | 2026-04-22 | |
| Gen AI evaluation service | Gen AI evals | 2026-04-22 | |
| Vertex AI Agent Builder | Folded into Agent Platform (Agent Studio, Agent Search, Agent Runtime) | 2026-04-22 | Exam guide 1.3 still says "Agent Builder" |
| Google Agentspace | **Gemini Enterprise** | 2025-10 | Exam guide 2.5: "Gemini Enterprise features (AI Agents and NotebookLM)" |
| Duet AI for Google Cloud | Gemini for Google Cloud (includes **Gemini Cloud Assist**, Gemini Code Assist) | 2024 | Gemini Cloud Assist is named in exam guide 1.2, 5.1 |
| Dialogflow CX | Conversational Agents (Dialogflow CX) | 2024–2025 | Part of Customer Engagement Suite |
| Contact Center AI (CCAI) | Customer Engagement Suite (with Google AI) | 2024–2026 | Conversational Agents, Agent Assist, Conversational Insights, CCaaS |
| Vertex AI SDK generative modules | Google Gen AI SDK | 2024–2025 | |

Source: [Agent Platform release notes, 2026-04-22 naming table](https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes).

---

## 2. Data and analytics

| Old name | Current name | When | Notes |
|---|---|---|---|
| Dataproc (on Compute Engine) **and** Google Cloud Serverless for Apache Spark (Dataproc Serverless) | **Managed Service for Apache Spark** | 2026-04-03 | One brand, two deployment modes: clusters and serverless. "No impact to the Dataproc API, client library, gcloud CLI, or Dataproc IAM role and permission names" |
| Cloud Composer | **Managed Service for Apache Airflow** | 2026-04-15 | Composer 3 environments; Airflow 3 GA |
| Dataplex / Dataplex Universal Catalog | **Knowledge Catalog** | 2026-04-10 | Data governance, discovery, lineage, quality. API still `dataplex.googleapis.com` |
| Data Catalog † | Legacy; replaced by Knowledge Catalog | Deprecated; shutdown began 2026 | Don't pick Data Catalog for new designs |
| BigLake | **Google Cloud Lakehouse** (Lakehouse for Apache Iceberg) | 2026-04-20 | Iceberg tables on Cloud Storage queried by BigQuery and open-source engines |
| BigLake metastore | Lakehouse runtime catalog | 2026-04-20 | |
| Analytics Hub | BigQuery sharing | 2025 | Data exchanges and listings; data clean rooms |
| Looker Studio | **Data Studio** | 2026-04 | Free self-service BI; Looker remains the governed BI platform |
| Pub/Sub Lite † | Use Pub/Sub or **Managed Service for Apache Kafka** | No new customers after 2024-09-24; turned down 2026 | |
| Memorystore for Memcached † | Migrate to **Memorystore for Valkey** | Deprecated 2026-01-20; shutdown 2029-01-31 | No new projects from 2027-02-01 |

---

## 3. Compute, containers and application platform

| Old name | Current name | When | Notes |
|---|---|---|---|
| Cloud Functions (1st/2nd gen) | **Cloud Run functions** | 2024-08 | Exam guide 1.3 uses the new name |
| Anthos / GKE Enterprise edition | **GKE**: one offering with no editions or tiers | 2025-09 | Fleet features (Config Sync, Policy Controller, Cloud Service Mesh, multi-cluster features) are part of GKE or available alongside it. Clusters "no longer have a tier" |
| Anthos Service Mesh, Traffic Director | **Cloud Service Mesh** | 2024 | |
| Anthos Config Management | Config Sync and Policy Controller | 2024 | GitOps and policy for fleets |
| Anthos clusters on VMware / bare metal | Google Distributed Cloud (software only) | 2024 | GKE on your own hardware |
| GKE on AWS/Azure, attached clusters | GKE Multi-Cloud / attached clusters | | Register to a fleet for central management |
| Container Registry † | **Artifact Registry** | Shut down 2025 | Container images and language packages |
| Cloud Source Repositories † | Secure Source Manager, or GitHub/GitLab with Developer Connect | Closed to new customers 2024-06 | |
| Cloud Deployment Manager † | **Infrastructure Manager** (managed Terraform) or Terraform | End of support 2026-03-31 | |
| Migrate for Compute Engine | Migrate to Virtual Machines | 2022 | |
| Migrate for Anthos | Migrate to Containers | 2022 | |
| Cloud IoT Core † | Partner IoT platforms or MQTT brokers → Pub/Sub | Retired 2023-08-16 | KnightMotives telemetry designs must not use it |

---

## 4. Networking, security and operations

| Old name | Current name | When | Notes |
|---|---|---|---|
| BeyondCorp Enterprise | **Chrome Enterprise Premium** | 2024 | Zero-trust access with context-aware access and IAP. Named in exam guide 3.1 |
| VPC firewall rules / Cloud Firewall | **Cloud Next Generation Firewall (Cloud NGFW)**: Essentials, Standard, Enterprise tiers | 2024 | Enterprise tier adds intrusion prevention (IPS) |
| Chronicle | Google Security Operations (SecOps) | 2024 | SIEM and SOAR |
| Stackdriver / Cloud Operations suite | **Google Cloud Observability** | 2023–2024 | Cloud Monitoring, Logging, Trace, Profiler, Error Reporting. Exam guide 6.2 uses this name |
| Cloud Storage Anywhere Cache | **Rapid Cache** | 2026 | SSD-backed zonal read cache for buckets; `gcloud storage buckets anywhere-caches` unchanged |
| Cloud DLP | **Sensitive Data Protection** (includes the DLP API) | 2023 | Named in exam guide 3.1 |
| Interconnect 10/100 Gbps | Dedicated and Cross-Cloud Interconnect now also offer **400 Gbps** | GA 2026-03-03 | |
| Interconnect 99.99% requires two metros | **Single-region 99.99% topology** also available: 4 connections in one supported metro, ordered as a `PRODUCTION_CRITICAL` connection group | GA 2026-06-02 | |

---

## 5. How to handle a name you don't recognize in the exam

1. **Look for the root noun.** "Agent Platform Pipelines" is a pipelines product, "Managed Service for Apache Spark" is Spark, and "Knowledge Catalog" is a catalog. The function rarely changed.
2. **Prefer current names over retired products.** An option built on Cloud IoT Core, Container Registry, Data Catalog or Deployment Manager is almost certainly a distractor.
3. **Don't punish an option for using the old name.** If an option says "Vertex AI Pipelines" and the design is right, it's still right. The exam's branding update may not have touched every question.
