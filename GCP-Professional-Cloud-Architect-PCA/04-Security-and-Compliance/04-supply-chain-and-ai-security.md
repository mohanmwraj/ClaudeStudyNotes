# 04/04 · Securing the Software Supply Chain and AI Systems

**Exam guide:** 3.1 ("securing software supply chain"; "securing AI (e.g., Model Armor, Sensitive Data Protection, and secure model deployment)"). **Principles:** P6, P11, P12, P16.

---

## 1. Software supply chain: threat model

An attacker can compromise software at any link: source → dependencies → build → artifact storage → deployment → runtime. The **SLSA** framework (Supply-chain Levels for Software Artifacts) describes increasing levels of build integrity and provenance.

| Link | Threat | Google Cloud control |
|---|---|---|
| Source | Unreviewed or malicious commits | Branch protection and reviews (GitHub/GitLab/**Secure Source Manager**); **Cloud Workstations** for managed, secure developer environments |
| Dependencies | Malicious or vulnerable open-source packages | **Assured Open Source Software** (curated, scanned packages); **Artifact Registry remote repositories** (cache and control upstream); vulnerability scanning |
| Build | Tampered build system or scripts | **Cloud Build** (ephemeral, isolated builders, private pools) generating **SLSA provenance** (build attestations) |
| Artifact storage | Swapped or poisoned images | **Artifact Registry** (IAM, CMEK, immutable tags, cleanup policies) + **Artifact Analysis** (vulnerability scanning, SBOM, provenance metadata) |
| Deployment | Unverified images reach production | **Binary Authorization**: policies require attestations (built by trusted CI, passed vulnerability gate, approved) on **GKE** and **Cloud Run**; **continuous validation** checks running pods against policy |
| Runtime | Exploitation of running workloads | GKE security posture (workload vulnerability and configuration scanning), Container Threat Detection (SCC), GKE Sandbox, least-privilege service accounts |
| Release process | Unreviewed promotion to prod | **Cloud Deploy** with approvals and promotion between targets; separation of duties |

### A secure pipeline

```text
Developer → PR review → Cloud Build (private pool, no keys: WIF/attached SA)
   → build image from Assured OSS / remote-repo dependencies
   → push to Artifact Registry → Artifact Analysis scan (fail on critical CVEs)
   → generate SLSA provenance + Binary Authorization attestation (KMS-signed)
   → Cloud Deploy: dev → staging (tests) → approval → prod
   → GKE / Cloud Run with Binary Authorization ENFORCED (only attested images run)
```

**Exam distinctions**

* **Scanning ≠ enforcement.** Artifact Analysis *finds* vulnerabilities; **Binary Authorization** *blocks* unapproved images at deploy time.
* **Provenance** shows *how and where* an artifact was built. An **attestation** is a signed statement that a check passed.
* Container Registry is shut down. Answers must use **Artifact Registry**.

---

## 2. Securing AI systems

### The AI threat model (Google's Secure AI Framework, SAIF, in brief)

| Threat | Example | Control |
|---|---|---|
| **Prompt injection / jailbreak** | User input (or a retrieved document) instructs the model to ignore rules or reveal data | **Model Armor** prompt screening; system-instruction hardening; least-privilege tools; output validation |
| **Sensitive data leakage** | Model returns PII or secrets from context or training data | **Model Armor** sensitive-data filters (powered by **Sensitive Data Protection**); de-identify training and grounding data; access control on data stores |
| **Harmful content** | Hate, harassment, sexual or dangerous content in outputs | Gemini **safety settings** + Model Armor **responsible-AI filters**; human review for high-risk flows |
| **Malicious URLs** | Model surfaces phishing links | Model Armor malicious URL detection |
| **Data poisoning** | Tampered training or grounding data | Data lineage (Knowledge Catalog), access control, validation steps in pipelines, provenance |
| **Model theft / tampering** | Exfiltration of weights; swapping a model | VPC SC around Agent Platform and storage; IAM; CMEK; Model Registry versioning; Artifact Registry for model containers |
| **Excessive agency** | An agent's tools can do too much (delete records, send money) | Least-privilege service accounts per tool; allow-listed actions; **human approval** for sensitive actions; audit logging |
| **Unexplainable or unauditable decisions** | Regulators or customers ask "why?" | Explainable AI, logging prompts, responses and model versions, Gen AI evals, model cards |

### Model Armor

**Model Armor** is a managed service that **screens prompts and responses** for LLM applications, independent of model or cloud:

* **Prompt injection and jailbreak detection.**
* **Sensitive data protection** (built-in infoTypes or SDP templates: detect and de-identify).
* **Responsible-AI filters** (hate speech, harassment, sexually explicit, dangerous content) with confidence thresholds.
* **Malicious URL detection.**
* Configured through **templates**, with org/folder/project **floor settings** for minimum protection.
* Integrations: called inline via API from your app or agent; integrated with Agent Platform / Gemini, GKE inference, and Security Command Center (AI protection findings).

**Exam pattern:**

* "Protect a customer-facing chatbot (Cymbal, Altostrat) from prompt injection and prevent it from returning PII" → **Model Armor** (plus SDP templates).
* "Remove PII from the documents used for grounding or training" → **Sensitive Data Protection** de-identification *before* indexing or training.

### Secure model deployment

| Practice | Implementation |
|---|---|
| Private serving | Agent Platform **private endpoints** / **PSC**; no public endpoints for internal models |
| Perimeter | **VPC Service Controls** around Agent Platform, BigQuery, Cloud Storage |
| Identity | Dedicated service accounts for endpoints, pipelines and agents with minimal roles; Workload Identity Federation for GKE |
| Encryption | **CMEK** for datasets, models, endpoints and pipeline artifacts where required |
| Provenance and integrity | Model Registry versions with lineage; build model-serving containers through the secure supply chain (Binary Authorization on GKE/Cloud Run) |
| Rollout safety | Traffic splitting between model versions; canary with evaluation gates; rollback to the previous version |
| Monitoring | Model Monitoring (drift), Gen AI evals on samples, logging (with PII redaction), SCC AI protection |
| Governance | Model cards, documented intended use, human-in-the-loop for high-impact decisions, region choice for residency |

---

## 3. Worked scenarios

**A. "Only container images built by the company's CI pipeline and free of critical vulnerabilities may run in production GKE clusters."**
Cloud Build generates provenance; an Artifact Analysis vulnerability gate; KMS-signed Binary Authorization attestations; Binary Authorization policy **enforced** on production clusters, with continuous validation. Reject "scan images weekly and alert".

**B. "Developers pull open-source packages directly from public registries; security wants vetted packages and the ability to block a compromised version quickly."**
Assured Open Source Software for curated packages, and **Artifact Registry remote repositories** as the only allowed upstream (with VPC SC / egress controls). Block versions centrally.

**C. "An internal agent can query HR systems and send emails. Security worries about prompt injection via emails it reads."**
Model Armor screening on inputs (including retrieved content) and outputs; least-privilege tool credentials; human confirmation before sending external emails; audit logs of tool calls.

**D. "A media company must show regulators which model version produced each recommendation."**
Model Registry versioning plus prediction request-response logging, including model version (to BigQuery); Explainable AI attributions for predictive models; retention per policy.

---

## References

* SLSA and software supply chain security on Google Cloud: <https://cloud.google.com/software-supply-chain-security/docs/overview>
* Binary Authorization: <https://cloud.google.com/binary-authorization/docs/overview>
* Artifact Analysis: <https://cloud.google.com/artifact-analysis/docs/artifact-analysis>
* Assured Open Source Software: <https://cloud.google.com/assured-open-source-software/docs/overview>
* Model Armor: <https://cloud.google.com/security-command-center/docs/model-armor-overview>
* Secure AI Framework (SAIF): <https://safety.google/cybersecurity-advancements/saif/>
