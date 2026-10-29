# 06/01 · Advising Teams: Deployment, API Management, Testing and Migration Tooling

**Exam guide:** 5.1 (application and infrastructure deployment; API management best practices (Apigee); testing frameworks (load/unit/integration); data and system migration and management tooling; Gemini Cloud Assist). **Principles:** P5, P8, P12, P15.

In this section the architect acts as an **advisor**: you're asked what to recommend to a development or operations team.

---

## 1. Application and infrastructure deployment advice

| Team situation | Recommendation |
|---|---|
| Manual deployments, drift between environments | IaC (Terraform) for infrastructure; CI/CD with build-once artifacts; GitOps (Config Sync) for clusters |
| Risky releases | Progressive delivery: canary or blue/green via **Cloud Deploy**, Cloud Run traffic splitting or MIG canary updates; automated verification and rollback |
| Configuration baked into images | Externalize config (environment, ConfigMaps) and secrets (**Secret Manager**) |
| Snowflake VMs | Golden images + MIGs, or containerize |
| Many teams, inconsistent setups | Platform team provides golden paths: templates and modules, a project factory, standard pipelines |
| Need to deploy to on-premises and cloud clusters consistently | Fleet + Config Sync + Cloud Deploy targets (Altostrat) |

Deployment strategies are compared in [07/02](../07-Operations-Excellence/02-sre-reliability-release-management.md#3-deployment-and-release-management).

---

## 2. API management with Apigee

### When to choose which API product

| Product | What it is | Choose when |
|---|---|---|
| **Apigee** (Apigee X on Google Cloud; **Apigee hybrid** with runtime on-premises or in other clouds) | Full-lifecycle API management platform | Partner or public APIs; monetization; developer portal; advanced security; analytics; many teams and APIs; legacy back-end facades |
| **API Gateway** | Lightweight, serverless gateway for Cloud Run, Cloud Run functions, App Engine back ends | Simple API front door with auth and quotas for serverless back ends |
| **Cloud Endpoints** | ESPv2 proxy with OpenAPI/gRPC | Existing Endpoints deployments; lightweight API management on GKE/Compute Engine |
| Cloud Load Balancing + Cloud Armor | L7 routing and protection | Not API management by itself (no keys, products, developer onboarding) |

### Apigee capabilities the exam expects

| Capability | Use |
|---|---|
| **API proxies** | Decouple consumers from back ends. The back end can be migrated or replaced without consumer changes (strangler pattern) |
| **Security policies** | API keys, **OAuth 2.0**, JWT validation, mTLS; **Advanced API Security** (abuse detection, security scoring) |
| **Traffic management** | **Quota** (per developer or app), **spike arrest**, caching |
| **Mediation** | Transform payloads (XML ↔ JSON), protocol bridging (SOAP to REST) for legacy systems |
| **API products and developer portal** | Package APIs, self-service onboarding with keys. **"Onboard new insurance providers as quickly as possible"** (EHR) |
| **Analytics** | Usage, latency and errors per API, developer and app |
| **Monetization** | Rate plans for paid APIs (KnightMotives data monetization via APIs) |
| **Apigee hybrid** | Runtime plane on-premises or in other clouds with a Google-managed management plane. Fits hybrid estates |

### API design best practices (also the "accessing Google APIs" mindset)

* **Versioning** (`/v1/`, `/v2/`) and backward compatibility; deprecate with notice.
* **Resource-oriented design** (Google's API Design Guide): standard methods, consistent naming.
* **Pagination** for list operations; **field masks** for partial responses and updates.
* **Idempotency** (request IDs) so clients can retry safely.
* **Rate limiting and quotas** to protect back ends; return 429 with retry hints.
* **Consistent error model** (status codes plus structured details).
* **Security by default**: OAuth/JWT, TLS, least-privilege scopes, no secrets in URLs.
* **OpenAPI or protobuf contracts** as the source of truth, with contract tests in CI.

---

## 3. Testing frameworks to recommend

| Test type | Recommendation on Google Cloud |
|---|---|
| **Unit** | Language-native frameworks (JUnit, pytest, Go test, Jest) in Cloud Build on every PR |
| **Integration** | Real dependencies in ephemeral projects, or **emulators** (Pub/Sub, Firestore, Bigtable, Spanner) for speed and isolation; Testcontainers |
| **Load** | **Distributed load testing** with Locust/JMeter/k6 running on **GKE** (scale load generators horizontally); test autoscaling, quotas and database limits; run before peak events (Cymbal's sales). Watch Cloud Monitoring and Trace during the test |
| **Contract** | Consumer-driven contract tests for microservices and partner APIs |
| **Security** | SAST, dependency scanning (Artifact Analysis), DAST (Web Security Scanner), periodic penetration tests (no prior approval from Google needed to pen-test your own projects, within the Acceptable Use Policy) |
| **Resilience** | Fault injection (Cloud Service Mesh fault injection, chaos tools); DR drills |

**Rule:** test in an environment that resembles production (same instance types, realistic data volumes, IaC-built). Load tests against a tiny staging database give false confidence.

---

## 4. Data and system migration and management tooling: quick chooser

| Moving | Recommend | Avoid |
|---|---|---|
| VMs from VMware, AWS, Azure, physical | **Migrate to Virtual Machines** (test clones, waves, rollback) | Manual image exports |
| VMware as-is (keep vSphere) | **VMware Engine** + HCX | Rebuilding everything |
| VMs to containers | **Migrate to Containers** | Hand-writing Dockerfiles for hundreds of apps first |
| MySQL / PostgreSQL / SQL Server | **Database Migration Service** (continuous) | Dump/restore when downtime matters |
| Oracle to PostgreSQL / AlloyDB | DMS conversion workspaces (Gemini-assisted conversion) + CDC | Manual schema rewrite as the first step |
| Analytics replication | **Datastream** | Custom CDC scripts |
| Files online | **Storage Transfer Service** | `cp` scripts for TB-scale recurring transfers |
| Files offline (PB) | **Transfer Appliance** | Saturating a thin WAN for months |
| Data warehouse | **BigQuery Migration Service** (assessment, SQL translation) + Data Transfer Service | Manual SQL rewrites |
| Inventory, TCO, planning | **Migration Center** | Spreadsheets |

---

## 5. Gemini Cloud Assist (and Gemini Code Assist) when advising teams

| Tool | Helps whom | With what |
|---|---|---|
| **Gemini Cloud Assist** | Architects, operators, SREs, FinOps | Designing architectures (Application Design Center), generating IaC and `gcloud`, explaining configurations, **investigating** incidents (log and metric correlation), cost insights |
| **Gemini Code Assist** | Developers | Code completion and generation, explanations, unit-test generation, code review assistance in IDEs |

**Exam guidance:**

* Recommending these to accelerate onboarding, troubleshooting or IaC authoring is valid.
* Generated changes still go through review, testing and CI/CD (P12).
* Enterprise editions add governance, such as data not used for training and admin controls.

---

## 6. Worked scenarios

**A. "EHR must let new insurance providers integrate in days, not months, with per-provider rate limits and usage visibility."**
Apigee: API products per partner tier, a developer portal for self-service keys/OAuth, quotas and spike arrest, analytics; proxies in front of the ingestion back ends (Pub/Sub, Cloud Run).

**B. "A team wants simple authentication and quotas for three Cloud Run functions exposed to a mobile app."**
API Gateway (lightweight, serverless), or Apigee if monetization, a developer portal or advanced security is needed. For three internal functions, API Gateway is the least-overhead answer.

**C. "Black Friday traffic last year overwhelmed the order database; the team has never load-tested."**
Distributed load testing on GKE (Locust) against a production-like environment. Tune autoscaling (max instances), connection pooling, caching and quotas, and request quota increases in advance.

**D. "A legacy SOAP service must be offered as a REST API to partners while it's being rewritten."**
An Apigee proxy with SOAP-to-REST mediation. Swap the back end to the new service later without partner changes.

---

## References

* Apigee overview: <https://cloud.google.com/apigee/docs/api-platform/get-started/what-apigee>
* Apigee hybrid: <https://cloud.google.com/apigee/docs/hybrid/latest/what-is-hybrid>
* API Gateway overview: <https://cloud.google.com/api-gateway/docs/about-api-gateway>
* Google API design guide: <https://cloud.google.com/apis/design>
* Distributed load testing with GKE: <https://cloud.google.com/architecture/distributed-load-testing-using-gke>
* Gemini Code Assist: <https://cloud.google.com/gemini/docs/codeassist/overview>
