# 02/06 · AI and ML Solution Selection

**Exam guide:** 1.3 ("Google Cloud AI and machine learning solutions (e.g., Gemini LLMs, Agent Builder, Model Garden, Gemini models, and AI Hypercomputer)"). Configuration and MLOps are in [03/05](../03-Managing-and-Provisioning/05-agent-platform-ml-workflows.md); AI security is in [04/04](../04-Security-and-Compliance/04-supply-chain-and-ai-security.md). **Principle:** P16.

Three of the four case studies are generative-AI stories, so this is now one of the highest-yield topics on the exam.

> **Naming:** since 2026-04-22, Vertex AI is **Gemini Enterprise Agent Platform** ("Agent Platform"). Vertex AI Studio is **Agent Studio**, Agent Engine is **Agent Runtime**, Vertex AI Search is **Agent Search**, and Vertex AI Pipelines is **Agent Platform Pipelines**. Full table: [05-product-name-rosetta.md](../00-Exam-Strategy-and-First-Principles/05-product-name-rosetta.md).

---

## 1. The abstraction ladder: start at the top

```text
Highest abstraction / least effort
 ┌──────────────────────────────────────────────────────────────────────────────────────┐
 │ 1. Packaged AI products   Gemini Enterprise (employee agents, search, NotebookLM),     │
 │                           Agent Search for Commerce, Customer Engagement Suite         │
 │ 2. Pre-trained APIs       Vision, Video Intelligence, Speech-to-Text (Chirp),           │
 │                           Text-to-Speech, Translation, Natural Language, Document AI   │
 │ 3. Foundation models      Gemini (multimodal) and Model Garden models (Imagen, Veo,     │
 │    via prompting          Claude, Llama, Gemma, …) in Agent Studio / Agent Platform API │
 │ 4. Grounding / RAG        Agent Search, RAG Engine, Vector Search, Google Search        │
 │                           grounding — give the model YOUR facts at request time         │
 │ 5. Agents                 Agent Development Kit (ADK) + Agent Runtime; tools,          │
 │                           memory, multi-agent (A2A) — model takes actions               │
 │ 6. Tuning                 Supervised fine-tuning / parameter-efficient tuning on        │
 │                           labelled examples — change style/format/domain behaviour      │
 │ 7. Custom models          AutoML or custom training on Agent Platform /                 │
 │                           AI Hypercomputer (GPUs/TPUs)                                  │
 └──────────────────────────────────────────────────────────────────────────────────────┘
Lowest abstraction / most effort, most control
```

**Descend a rung only when a requirement forces you to.** Typical reasons are domain accuracy, a proprietary task with no pre-trained equivalent, strict cost or latency at very high volume, or data that can't leave a boundary.

---

## 2. Prompting vs RAG vs tuning vs training

| Problem | Right technique | Why |
|---|---|---|
| Model gives generic answers; needs *your* current facts (catalog, policies, manuals) | **RAG / grounding** (Agent Search, RAG Engine, Vector Search) | Facts change; retrieval keeps them fresh and citable, and reduces hallucination |
| Output must follow a strict **format** (JSON matching a taxonomy) | **Controlled generation** (response schema), few-shot examples | No training needed |
| Model must adopt a specific **style or task behavior** consistently, and prompts are getting huge | **Supervised fine-tuning** | Bakes behavior into weights |
| Classification/regression on your tabular data | **BigQuery ML** or **AutoML** / custom training | Classic ML, not an LLM problem |
| Novel model architecture or research | **Custom training** on AI Hypercomputer | Full control |
| Answers must cite current public web information | **Grounding with Google Search** | Freshness |

**The most common exam trap is fine-tuning to inject knowledge.** Knowledge goes in via RAG; behavior goes in via tuning.

---

## 3. The Agent Platform component map

| Component (current name) | Purpose |
|---|---|
| **Gemini models** (Pro, Flash, Flash-Lite families) | Multimodal (text, image, audio, video, documents) reasoning and generation; long context; function calling; controlled generation |
| **Model Garden** | Catalog of Google, partner and open models (Gemini, Imagen, Veo, Chirp, Gemma; Anthropic Claude, Meta Llama, Mistral, and others) as managed APIs (MaaS) or deployable to your endpoints |
| **Agent Studio** (formerly Vertex AI Studio) | Prompt design and testing, tuning, App Builder |
| **Agent Development Kit (ADK)** | Open-source framework for building agents and multi-agent systems |
| **Agent Runtime** (formerly Agent Engine) | Managed runtime to deploy and scale agents, with **Sessions**, **Memory Bank** and **Code Execution** |
| **Agent Search** (formerly Vertex AI Search) | Managed enterprise search and RAG over websites, documents and structured data |
| **Agent Search for Commerce** | Retail search, browse and recommendations (Cymbal's "Discovery AI") |
| **RAG Engine** | Managed retrieval-augmented generation pipeline (chunking, embedding, retrieval) |
| **Vector Search** / **Agent Retrieval** | Approximate-nearest-neighbor vector database at scale |
| **Agent Platform Pipelines** | Orchestrate ML workflows (Kubeflow Pipelines / TFX) |
| **Feature Store**, **Model Registry**, **Experiments**, **Model Monitoring** | MLOps building blocks |
| **Agent Platform Inference** (online/batch), **Endpoints** | Serving custom and open models; batch inference for bulk jobs |
| **Managed Training / Serverless Training / Managed Training Clusters** | Custom training jobs; reserved large-scale clusters |
| **Gen AI evals** | Evaluate model and agent output quality (groundedness, safety, task metrics) |
| **Explainable AI** | Feature attributions and example-based explanations for predictive models |

### Consumption models for generative AI

| Model | Use for |
|---|---|
| **Pay-as-you-go** (per token or character) | Variable, unpredictable traffic |
| **Provisioned Throughput** | Guaranteed capacity and predictable latency for production volumes |
| **Batch inference** | Large offline jobs (catalog enrichment, back-catalog summarization), discounted versus online |
| **Context caching** | Repeated large prompts or context (long documents, system instructions) to cut cost and latency |

---

## 4. Packaged products and pre-trained APIs: who does what

| Need | Product |
|---|---|
| Employees search and chat across company data (Drive, Confluence, Jira, SharePoint), use prebuilt and custom **AI agents**, and work with **NotebookLM** | **Gemini Enterprise** (formerly Agentspace) |
| Customer-facing website search / RAG chatbot over your content | **Agent Search** (+ Conversational Agents) |
| Retail product search, browse and recommendations | **Agent Search for Commerce** |
| Contact center: virtual agents (voice and chat), agent assist, analytics | **Customer Engagement Suite** (Conversational Agents / Dialogflow CX, Agent Assist, Conversational Insights, CCaaS) |
| Extract fields from invoices, forms, IDs | **Document AI** (specialized processors) |
| Labels, OCR, faces, logos, **SafeSearch** (explicit content) on images | **Cloud Vision API** |
| Shot detection, labels, text, **explicit content detection**, object tracking in video | **Video Intelligence API** |
| Speech-to-text (Chirp models), text-to-speech | **Speech-to-Text**, **Text-to-Speech** |
| Translation | **Cloud Translation** (with glossaries; adaptive translation) |
| Entities, sentiment, classification of text | **Natural Language API** (or Gemini) |
| Image generation and editing (inpainting, background swap, variations) | **Imagen** (or Gemini image models) via Agent Platform |
| Video generation | **Veo** via Agent Platform |

**Exam heuristic.** If a pre-trained API exactly matches the task and the question stresses *least effort / fastest*, pick the API. If the task needs reasoning across modalities, summarization, flexible extraction to a custom schema or conversation, Gemini is usually the modern answer. Many current-blueprint questions expect Gemini where older material expected a combination of specialized APIs.

---

## 5. AI Hypercomputer (named in exam guide 1.3 and 2.4)

**AI Hypercomputer** is Google's integrated system for AI training and serving. It combines three layers:

| Layer | Content |
|---|---|
| **Performance-optimized hardware** | **Cloud TPUs** (current generations including Trillium and Ironwood), **NVIDIA GPUs** (A3/A4 VMs: H100, H200, B200 and newer), high-bandwidth networking, Hyperdisk ML, Managed Lustre, Cloud Storage with Rapid Cache |
| **Open software** | GKE (with Kueue, JobSet), Managed Training Clusters, frameworks (JAX, PyTorch/XLA, TensorFlow), serving (vLLM, JetStream, NVIDIA Triton), Pathways |
| **Flexible consumption** | On-demand; **CUDs**; **Spot**; **Dynamic Workload Scheduler**, either **flex-start** (queue for capacity, start when available, pay less) or **calendar mode** (reserve accelerators for a fixed future window); reservations |

### GPU vs TPU

| Choose **TPU** when | Choose **GPU** when |
|---|---|
| Large-scale training/serving of models in JAX, PyTorch/XLA or TensorFlow; matrix-heavy transformer workloads; best price-performance at scale | You need CUDA libraries, a broad framework and ecosystem, custom kernels, graphics/rendering, or small and medium jobs; most third-party model code |

### Matching consumption to workload

| Workload | Consumption model |
|---|---|
| Long training run, must start on a date | DWS **calendar mode** or reservations |
| Training that can wait for capacity, cost-sensitive | DWS **flex-start** |
| Fault-tolerant, checkpointed experiments | **Spot** |
| Steady serving fleet 24×7 | **CUDs** |
| Bursty inference | Autoscaling on GKE / Cloud Run GPUs, or MaaS pay-as-you-go |

---

## 6. Case-study mapping

| Case requirement | AI solution |
|---|---|
| **Cymbal:** attribute and description generation from supplier text and images, aligned to the taxonomy | Gemini multimodal + response schema + few-shot; batch inference; HITL |
| **Cymbal:** image variants, background changes, text overlays | Imagen / Gemini image editing |
| **Cymbal:** natural-language product discovery | Agent Search for Commerce |
| **Cymbal:** conversational commerce, reduce call-center cost | Customer Engagement Suite (Conversational Agents + Agent Assist), grounded in the catalog |
| **Altostrat:** summaries of audio/video | Gemini multimodal (native audio/video input) |
| **Altostrat:** metadata extraction with NLP and computer vision | Gemini to schema, or Video Intelligence + Vision + Natural Language + Speech-to-Text |
| **Altostrat:** harmful content detection | Video Intelligence explicit content, Vision SafeSearch, Gemini classification, Model Armor for chat |
| **Altostrat:** auditable, explainable AI | Explainable AI, Model Registry lineage, logging prompts/responses, Gen AI evals, grounding with citations |
| **Altostrat:** chatbots, 24/7 support | ADK agent on Agent Runtime or Conversational Agents, grounded with Agent Search |
| **KnightMotives:** autonomous-driving training and simulation | AI Hypercomputer (TPU/GPU), DWS, GKE simulation farms, Pipelines + Model Registry |
| **KnightMotives:** tools for mechanics and salespeople | Agents grounded in manuals and inventory (Agent Search), Gemini Enterprise for employees |
| **EHR:** predictions on industry trends | BigQuery ML (least effort) or Agent Platform custom models |

---

## 7. Responsible and production AI (principles the exam rewards)

* **Grounding** to reduce hallucinations, with **citations** for traceability.
* **Human-in-the-loop** where errors are costly (Cymbal's review UI).
* **Safety**: model safety settings plus **Model Armor** for prompt injection, jailbreak, sensitive-data leakage and harmful content.
* **Privacy**: **Sensitive Data Protection** to de-identify training and grounding data; don't put payment data in prompts.
* **Evaluation**: offline evaluation sets plus online monitoring (Gen AI evals; model monitoring for drift on predictive models).
* **Governance**: model versions in Model Registry; prompt and response logging; access control (IAM, VPC SC, CMEK); data residency for training data and endpoints.
* **Cost and latency**: choose model size (Flash vs Pro), batch inference, context caching and Provisioned Throughput deliberately.

---

## 8. Traps

* **Training a custom model** when Gemini or a pre-trained API meets the requirement.
* **Fine-tuning to add knowledge** that changes daily (use RAG).
* **Vision API to generate images** (it analyzes; Imagen generates).
* **Building a custom vector database and search stack** before trying Agent Search / RAG Engine (P5).
* **Gen-AI output published without review** when the case requires accuracy (Cymbal) or safety (Altostrat).
* Choosing **GPUs for everything**. When the question emphasizes large-scale training price-performance with JAX/XLA, TPUs are the intended answer.

---

## References

* Gemini Enterprise Agent Platform release notes (naming table): <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>
* AI Hypercomputer: <https://cloud.google.com/ai-hypercomputer/docs/overview>
* Dynamic Workload Scheduler: <https://cloud.google.com/compute/docs/instance-groups/about-resize-requests-mig>
* Cloud TPU overview: <https://cloud.google.com/tpu/docs/intro-to-tpu>
* Gemini Enterprise: <https://cloud.google.com/gemini-enterprise>
* Model Armor overview: <https://cloud.google.com/security-command-center/docs/model-armor-overview>
