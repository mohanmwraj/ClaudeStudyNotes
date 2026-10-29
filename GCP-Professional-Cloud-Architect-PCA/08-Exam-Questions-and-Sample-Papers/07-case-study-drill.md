# Case-Study Drill · 40 Questions (10 per Case Study)

Every PCA exam includes **two** of these four case studies, and case-study questions make up 20–30% of the exam. Before each section, re-read the company's **standing constraints** box in [01-Case-Studies](../01-Case-Studies/). Most wrong answers here are technically valid but violate a constraint stated in the case study.

| Section | Case study | Breakdown |
|---|---|---|
| Q1–Q10 | EHR Healthcare | [02-ehr-healthcare.md](../01-Case-Studies/02-ehr-healthcare.md) |
| Q11–Q20 | Cymbal Retail | [03-cymbal-retail.md](../01-Case-Studies/03-cymbal-retail.md) |
| Q21–Q30 | KnightMotives Automotive | [05-knightmotives-automotive.md](../01-Case-Studies/05-knightmotives-automotive.md) |
| Q31–Q40 | Altostrat Media | [04-altostrat-media.md](../01-Case-Studies/04-altostrat-media.md) |

---

## EHR Healthcare

### Q1 · Case: EHR Healthcare · Task 1.4 · Single answer

**Case study: EHR Healthcare.** The lease on one of EHR's colocation data centers expires in five months. That facility hosts several containerized customer-facing applications, their MySQL and Redis databases, and a handful of VMs. EHR's legacy insurance integrations run in a different colocation facility.

How should EHR plan its first migration wave?

- **A.** Start with the legacy insurance integrations, because they're the oldest systems.
- **B.** Refactor every application in the expiring facility into Cloud Run services before moving anything.
- **C.** Prioritize the workloads in the expiring facility: deploy the containerized applications to GKE, migrate the MySQL databases to Cloud SQL with Database Migration Service continuous migration, re-provision Redis on Memorystore, and rehost the remaining VMs with Migrate to Virtual Machines.
- **D.** Wait until every colocation lease is close to expiring, and migrate everything at once.

<details><summary>Answer</summary>

**Answer: C**

**Why (P15, P5):** The lease deadline sets the wave order. Containers and databases move with minimal change to managed services, and minimal-downtime tools reduce risk.

- **A** — wrong: the case says there's no plan to move the legacy integrations, and they're not in the expiring facility.
- **B** — wrong: refactoring everything risks missing the lease deadline.
- **C** — correct: deadline-driven, low-change, managed targets.
- **D** — wrong: a big-bang migration multiplies risk and ignores the deadline.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

</details>

### Q2 · Case: EHR Healthcare · Task 2.1 · Single answer

**Case study: EHR Healthcare.** New applications on Google Cloud must exchange data with the legacy insurance integrations that remain on-premises. The technical requirements call for a secure, high-performance connection, and customer-facing systems need at least 99.9% availability.

Which connectivity design should you recommend?

- **A.** Send traffic over the public internet with TLS to public endpoints on both sides.
- **B.** A single Partner Interconnect VLAN attachment from one provider.
- **C.** Direct Peering between EHR's network and Google.
- **D.** Dedicated Interconnect in a redundant topology that meets the SLA, with Cloud Router BGP sessions, plus HA VPN as a backup path.

<details><summary>Answer</summary>

**Answer: D**

**Why (P14, P2):** EHR is already in colocation facilities, where Dedicated Interconnect is typically available. Redundant connections meet the availability need, and HA VPN adds a separate failure path.

- **A** — wrong: fails the "secure and high-performance" requirement.
- **B** — wrong: a single attachment has no redundancy.
- **C** — wrong: Direct Peering doesn't provide private VPC connectivity.
- **D** — correct: private, high-bandwidth and redundant.

**Reference:** <https://cloud.google.com/network-connectivity/docs/how-to/choose-product>

</details>

### Q3 · Case: EHR Healthcare · Task 3.1 · Single answer

**Case study: EHR Healthcare.** EHR manages all users in Microsoft Active Directory and wants AD to remain the source of truth for identities and group membership. Employees should sign in to Google Cloud with their existing corporate credentials.

What should you recommend?

- **A.** Deploy Managed Service for Microsoft Active Directory, and have employees sign in to the Google Cloud console with it.
- **B.** Use Google Cloud Directory Sync to synchronize users and groups from Active Directory to Cloud Identity, and configure SAML single sign-on against EHR's identity provider (for example, AD FS).
- **C.** Create Cloud Identity accounts manually, and ask users to choose new passwords.
- **D.** Use Workload Identity Federation for employee sign-in.

<details><summary>Answer</summary>

**Answer: B**

**Why (P6, P7):** GCDS keeps Active Directory authoritative, with one-way sync of users and groups, and SSO keeps authentication on the corporate IdP. Groups then drive IAM.

- **A** — wrong: Managed Microsoft AD serves AD-dependent workloads, not console sign-in.
- **B** — correct: the standard AD integration pattern.
- **C** — wrong: duplicate identities and passwords, and AD stops being the source of truth.
- **D** — wrong: Workload Identity Federation is for workloads, not people.

**Reference:** <https://cloud.google.com/architecture/identity/federating-gcp-with-active-directory-introduction>

</details>

### Q4 · Case: EHR Healthcare · Task 1.3 · Single answer

**Case study: EHR Healthcare.** EHR's customer-facing applications use MySQL. The databases must meet the 99.9% availability requirement, administration costs must fall, and the migration should cause minimal downtime.

Which target and migration approach should you choose?

- **A.** Cloud SQL for MySQL with high availability (regional), migrated with a Database Migration Service continuous migration job.
- **B.** MySQL installed on a single Compute Engine VM, restored from a dump.
- **C.** Bigtable, with the application rewritten to use its API.
- **D.** Spanner, with the schema and application redesigned before migration.

<details><summary>Answer</summary>

**Answer: A**

**Why (P5, P2, P15):** A managed MySQL service with zonal-failure protection meets availability and reduces administration. Continuous migration minimizes downtime.

- **A** — correct: managed HA plus minimal-downtime migration.
- **B** — wrong: a single VM is self-managed, has no HA, and dump/restore causes downtime.
- **C** — wrong: a different data model, and a rewrite isn't justified.
- **D** — wrong: over-engineered, and a redesign conflicts with the lease timeline.

**Reference:** <https://cloud.google.com/database-migration/docs/overview>

</details>

### Q5 · Case: EHR Healthcare · Task 6.2 · Single answer

**Case study: EHR Healthcare.** EHR's monitoring alerts are currently sent by email and are often ignored. The business wants centralized visibility and proactive action on system performance across all environments.

What should you recommend?

- **A.** Add more distribution lists to the email alerts, so more people see them.
- **B.** Send an SMS for every metric that crosses a threshold.
- **C.** Define SLOs for customer-facing services, alert on SLO burn rate through on-call channels (for example, PagerDuty) with runbooks, build dashboards in a central metrics scope, and use Managed Service for Prometheus for existing open-source metrics.
- **D.** Disable most alerts, to reduce noise.

<details><summary>Answer</summary>

**Answer: C**

**Why (P13):** Actionable, symptom-based alerting routed to people on call, plus a single pane of glass, directly answers "ignored email alerts" and "centralized visibility".

- **A** — wrong: more email doesn't make alerts actionable.
- **B** — wrong: floods people with noise and cause-based alerts.
- **C** — correct: SLO-driven, routed, centralized observability.
- **D** — wrong: reduces visibility instead of improving it.

**Reference:** <https://cloud.google.com/stackdriver/docs/solutions/slo-monitoring>

</details>

### Q6 · Case: EHR Healthcare · Task 2.3 · Select TWO

**Case study: EHR Healthcare.** EHR must "provide a consistent way to manage customer-facing applications that are container-based" and "maintain and manage multiple container-based environments". Past outages were caused by misconfigured systems.

Which two actions should you recommend? (Select TWO.)

- **A.** Let each team manage its clusters manually with `kubectl`.
- **B.** Register all GKE clusters in a fleet, and manage cluster configuration from Git with Config Sync.
- **C.** Run all environments, including production, in one cluster separated only by namespaces.
- **D.** Allow each team to choose its own deployment tooling.
- **E.** Enforce configuration guardrails across the fleet with Policy Controller constraints.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P12, P7):** GitOps across a fleet makes configuration consistent and reviewable. Policy guardrails block the misconfigurations that caused past outages.

- **A** — wrong: manual changes are the source of misconfiguration.
- **B** — correct: consistent, declarative, version-controlled configuration.
- **C** — wrong: weak isolation for regulated production workloads.
- **D** — wrong: inconsistency is the problem being solved.
- **E** — correct: preventive policy enforcement.

**Reference:** <https://cloud.google.com/kubernetes-engine/enterprise/config-sync/docs/overview>

</details>

### Q7 · Case: EHR Healthcare · Task 3.2 · Single answer

**Case study: EHR Healthcare.** EHR stores protected health information for US medical providers and must maintain regulatory compliance after moving to Google Cloud.

Which combination of measures should you recommend?

- **A.** Sign Google's Business Associate Agreement, use only HIPAA-covered services for PHI, place PHI projects inside a VPC Service Controls perimeter, enable Data Access audit logs, and use CMEK where EHR's policies require customer-controlled keys.
- **B.** Rely on Google's default encryption at rest, which makes the workloads compliant.
- **C.** Store PHI in a public Cloud Storage bucket protected by obscure object names.
- **D.** Keep PHI exports on engineers' laptops, for faster analysis.

<details><summary>Answer</summary>

**Answer: A**

**Why (P6, P11, P13):** Compliance is a shared responsibility. Contractual coverage (BAA, covered services), exfiltration controls, audit evidence and key custody where required are EHR's part.

- **A** — correct: layered, compliance-aligned controls.
- **B** — wrong: encryption alone doesn't equal compliance.
- **C** — wrong: public exposure of PHI.
- **D** — wrong: uncontrolled copies of regulated data.

**Reference:** <https://cloud.google.com/security/compliance/hipaa>

</details>

### Q8 · Case: EHR Healthcare · Task 1.1 · Single answer

**Case study: EHR Healthcare.** EHR wants to "on-board new insurance providers as quickly as possible" and to "create interfaces to ingest and process data from new providers". Providers differ: some offer APIs, others send files.

What should you recommend?

- **A.** A dedicated VPN tunnel and a custom integration project for each new provider.
- **B.** Apigee for API-based providers (developer portal, credentials, quotas), and a standardized file landing zone in Cloud Storage, both feeding a reusable Pub/Sub and Dataflow ingestion pipeline (with the Cloud Healthcare API for healthcare data standards).
- **C.** Have providers email their data files to an operations mailbox.
- **D.** Give providers credentials to write directly into EHR's production databases.

<details><summary>Answer</summary>

**Answer: B**

**Why (P8, P5):** Standardized, self-service onboarding interfaces with a decoupled, reusable processing pipeline turn each new provider into configuration rather than a project.

- **A** — wrong: bespoke work per provider is slow.
- **B** — correct: repeatable onboarding for both API and file providers.
- **C** — wrong: manual and insecure.
- **D** — wrong: dangerous coupling, and a security risk.

**Reference:** <https://cloud.google.com/apigee/docs/api-platform/get-started/what-apigee>

</details>

### Q9 · Case: EHR Healthcare · Task 1.2 · Single answer

**Case study: EHR Healthcare.** EHR's customers are multinational, and the business requirements include reducing latency for all customers while keeping at least 99.9% availability.

Which design should you recommend for the customer-facing web tier?

- **A.** One very large zonal GKE cluster in a single region.
- **B.** DNS round robin pointing at the remaining colocation data center.
- **C.** A regional external load balancer on the Standard network tier.
- **D.** A global external Application Load Balancer with Cloud CDN, routing to regional GKE clusters in regions near major customer populations.

<details><summary>Answer</summary>

**Answer: D**

**Why (P1, P2):** Anycast global load balancing on Google's network, edge caching and regional (multi-zone) back ends close to users address both latency and availability.

- **A** — wrong: zonal and single-region, so latency and availability both suffer.
- **B** — wrong: no health-aware or latency-aware routing, and it keeps the colocation dependency.
- **C** — wrong: regional only, and Standard Tier increases latency for distant users.
- **D** — correct: global entry point, edge caching, resilient regional back ends.

**Reference:** <https://cloud.google.com/load-balancing/docs/choosing-load-balancer>

</details>

### Q10 · Case: EHR Healthcare · Task 1.3 · Single answer

**Case study: EHR Healthcare.** EHR wants to provide insights into healthcare trends and make predictions from provider data, with minimal impact on the production databases and the least specialist ML effort. Patient privacy must be protected.

What should you recommend?

- **A.** Replicate operational data to BigQuery with Datastream, de-identify sensitive fields with Sensitive Data Protection, build forecasts with BigQuery ML, and publish reports in Looker.
- **B.** Run analytics queries directly against the production Cloud SQL instances.
- **C.** Build a custom GPU training cluster for all predictions.
- **D.** Export monthly CSV files to analysts' laptops.

<details><summary>Answer</summary>

**Answer: A**

**Why (P4, P16, P11):** Change data capture into an analytical store protects OLTP performance. De-identification protects privacy, and in-warehouse ML gives predictions with SQL skills.

- **A** — correct: a low-impact, privacy-aware, low-effort analytics and ML path.
- **B** — wrong: analytical load harms customer-facing databases.
- **C** — wrong: unnecessary complexity for trend forecasting.
- **D** — wrong: stale, insecure copies of sensitive data.

**Reference:** <https://cloud.google.com/datastream/docs/overview>

</details>

## Cymbal Retail

### Q11 · Case: Cymbal Retail · Task 1.3 · Single answer

**Case study: Cymbal Retail.** Cymbal's current web application finds products by querying relational databases for names and categories. Customers can't find products when they describe what they need in natural language. Cymbal wants better search relevance with the least custom development.

What should you recommend?

- **A.** Add more indexes and `LIKE` clauses to the relational queries.
- **B.** Agent Search for Commerce (formerly Vertex AI Search for commerce, the "Discovery AI" in the case study), fed with the product catalog and user events.
- **C.** Store the catalog in Bigtable and scan it for keyword matches.
- **D.** Build custom embedding models and a self-managed vector database before evaluating managed options.

<details><summary>Answer</summary>

**Answer: B**

**Why (P16, P5):** Managed retail search provides semantic understanding, ranking and personalization over a catalog. It's the highest abstraction that fits, and it's named in the case study.

- **A** — wrong: keyword matching can't interpret natural-language intent.
- **B** — correct: purpose-built product discovery.
- **C** — wrong: Bigtable isn't a search engine.
- **D** — wrong: heavy custom work before trying the managed product.

**Reference:** <https://cloud.google.com/retail/docs>

</details>

### Q12 · Case: Cymbal Retail · Task 2.5 · Single answer

**Case study: Cymbal Retail.** Suppliers send product titles, free-text descriptions and photos. Cymbal needs product attributes derived from all of these that align with the product category and Cymbal's existing catalog structure, with minimal custom ML work.

What should you recommend?

- **A.** The Natural Language API's entity extraction on the descriptions only.
- **B.** Vision API labels on the photos only.
- **C.** A Gemini multimodal model on Agent Platform, prompted with the category taxonomy and few-shot examples from the existing catalog, with a response schema that enforces Cymbal's attribute structure.
- **D.** A new model trained from scratch on millions of labeled products.

<details><summary>Answer</summary>

**Answer: C**

**Why (P16):** One multimodal model reasons over text and images together. Controlled generation guarantees taxonomy-conformant, machine-validatable output.

- **A** — wrong: ignores images, and generic entities don't map to Cymbal's attributes.
- **B** — wrong: ignores text, and generic labels don't match the catalog structure.
- **C** — correct: multimodal, schema-aligned and low effort.
- **D** — wrong: enormous effort compared with prompting a foundation model.

**Reference:** <https://cloud.google.com/vertex-ai/generative-ai/docs/multimodal/control-generated-output>

</details>

### Q13 · Case: Cymbal Retail · Task 2.5 · Single answer

**Case study: Cymbal Retail.** From one base product photo, Cymbal wants to generate color variations, change backgrounds and add text overlays for marketing.

Which capability should you use?

- **A.** The Cloud Vision API.
- **B.** The Video Intelligence API.
- **C.** Document AI.
- **D.** Imagen (or Gemini image generation and editing models) on Agent Platform.

<details><summary>Answer</summary>

**Answer: D**

**Why (P16):** These are image-generation and editing tasks, such as variations, background replacement and inpainting, which generative image models provide.

- **A** — wrong: analyzes images, but doesn't create or edit them.
- **B** — wrong: analyzes video.
- **C** — wrong: extracts data from documents.
- **D** — correct: generative image editing.

**Reference:** <https://cloud.google.com/vertex-ai/generative-ai/docs/image/overview>

</details>

### Q14 · Case: Cymbal Retail · Task 1.1 · Single answer

**Case study: Cymbal Retail.** Associates must be able to approve, reject or modify generative-AI suggestions before the product catalog is updated.

Which design satisfies the human-in-the-loop requirement?

- **A.** Store generated content as drafts with a status in a database, and provide a review web application on Cloud Run, protected by IAP, where associates approve, reject or edit drafts. Approved items are published to the catalog and re-indexed for search.
- **B.** Publish generated content to the catalog automatically, and let associates fix errors afterwards.
- **C.** Email spreadsheets of suggestions to associates, and have them reply with corrections.
- **D.** Give associates direct write access to the production catalog database.

<details><summary>Answer</summary>

**Answer: A**

**Why (P16, P6):** HITL needs an explicit draft state, a governed review interface and a controlled publish step. IAP restricts the tool to authorized associates.

- **A** — correct: review before publication, with auditability and access control.
- **B** — wrong: violates "before updating the product catalog".
- **C** — wrong: manual, error-prone and unscalable.
- **D** — wrong: bypasses workflow and least privilege.

**Reference:** <https://cloud.google.com/iap/docs/concepts-overview>

</details>

### Q15 · Case: Cymbal Retail · Task 3.1 · Select TWO

**Case study: Cymbal Retail.** Cymbal's AI virtual agents will converse with customers on the website and in the mobile app. All customer data, including interactions with virtual agents, must be handled securely and comply with industry regulations.

Which two measures should you recommend? (Select TWO.)

- **A.** Screen the virtual agent's prompts and responses with Model Armor, to block prompt injection and prevent sensitive-data leakage.
- **B.** Rely on a Cloud Armor WAF policy alone to secure the conversations.
- **C.** Store complete transcripts, including payment card numbers, to train future models.
- **D.** Use Sensitive Data Protection to detect and de-identify PII and card numbers in transcripts before they're stored or analyzed.
- **E.** Disable all logging of virtual-agent interactions.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P16, P11):** LLM-specific threats need prompt and response screening. Regulated data in transcripts must be minimized or de-identified, for PCI and privacy.

- **A** — correct: guards the conversational interface.
- **B** — wrong: a WAF doesn't understand prompts or sensitive content.
- **C** — wrong: retaining card data expands PCI scope and risk.
- **D** — correct: privacy-preserving storage and analytics.
- **E** — wrong: removes auditability and operational insight.

**Reference:** <https://cloud.google.com/security-command-center/docs/model-armor-overview>

</details>

### Q16 · Case: Cymbal Retail · Task 1.1 · Single answer

**Case study: Cymbal Retail.** Cymbal wants to reduce call-center staffing costs. Today an IVR routes calls to agents who manually enter orders when customers can't complete transactions themselves.

What should you recommend?

- **A.** Hire more call-center agents, to reduce wait times.
- **B.** Add more levels to the IVR menu.
- **C.** Shut down phone support entirely.
- **D.** Deploy Customer Engagement Suite conversational agents for voice and chat that can complete orders through tools calling Cymbal's order APIs, with Agent Assist supporting the human agents who handle escalations.

<details><summary>Answer</summary>

**Answer: D**

**Why (P16, P9):** Conversational agents that complete transactions deflect calls, which cuts staffing cost. Agent Assist makes the remaining human interactions faster.

- **A** — wrong: increases cost.
- **B** — wrong: worsens the customer experience, with no automation of orders.
- **C** — wrong: harms customers and conversion.
- **D** — correct: automation plus augmentation.

**Reference:** <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>

</details>

### Q17 · Case: Cymbal Retail · Task 1.4 · Single answer

**Case study: Cymbal Retail.** To reduce data-center hosting costs, Cymbal is modernizing its databases: MySQL, Microsoft SQL Server, Redis and MongoDB. It wants managed services and minimal application changes.

Which migration plan should you recommend?

- **A.** Database Migration Service to Cloud SQL for MySQL and Cloud SQL for SQL Server; Memorystore (Valkey or Redis) for Redis; and MongoDB Atlas on Google Cloud Marketplace or Firestore with MongoDB compatibility for MongoDB.
- **B.** Consolidate all four databases into a single Spanner database immediately.
- **C.** Rehost every database on self-managed Compute Engine VMs indefinitely.
- **D.** Move all operational data into BigQuery.

<details><summary>Answer</summary>

**Answer: A**

**Why (P5, P15):** Matching each engine to its managed equivalent minimizes application change while removing infrastructure administration.

- **A** — correct: managed, compatible targets for each engine.
- **B** — wrong: a massive redesign for no stated requirement.
- **C** — wrong: keeps the administrative burden.
- **D** — wrong: BigQuery isn't an OLTP database.

**Reference:** <https://cloud.google.com/database-migration/docs/overview>

</details>

### Q18 · Case: Cymbal Retail · Task 2.2 · Single answer

**Case study: Cymbal Retail.** Cymbal still relies on legacy SFTP file transfers and nightly ETL batch jobs with on-premises systems. Errors are discovered late, and remediation is manual.

How should Cymbal modernize these integrations?

- **A.** Keep the nightly ETL on the on-premises servers, and add more operators.
- **B.** Land files in Cloud Storage (using Storage Transfer Service agents or an SFTP gateway for partners that require SFTP), trigger validation and processing on arrival with Pub/Sub or Eventarc and Dataflow, and orchestrate multi-step flows with Managed Service for Apache Airflow.
- **C.** Have partners email files to an operations team.
- **D.** Ship files weekly on a Transfer Appliance.

<details><summary>Answer</summary>

**Answer: B**

**Why (P8, P5):** Event-driven processing catches errors at arrival, managed orchestration handles dependencies and retries, and file landing keeps partner compatibility.

- **A** — wrong: keeps the late-discovery and manual-remediation problems.
- **B** — correct: automated, observable and managed.
- **C** — wrong: manual and insecure.
- **D** — wrong: offline bulk transfer doesn't fit recurring integrations.

**Reference:** <https://cloud.google.com/storage/docs/pubsub-notifications>

</details>

### Q19 · Case: Cymbal Retail · Task 6.2 · Single answer

**Case study: Cymbal Retail.** Cymbal monitors its systems with Grafana, Nagios and Elastic, each run by a different team. It wants proactive monitoring with less tooling to operate, while keeping the Grafana dashboards engineers like.

What should you recommend?

- **A.** Self-host all three tools on a GKE cluster.
- **B.** Keep Nagios and retire the other two tools.
- **C.** Use Cloud Monitoring uptime checks and alerting in place of Nagios, Managed Service for Prometheus queried from the existing Grafana, and Cloud Logging with Log Analytics in place of Elastic.
- **D.** Remove monitoring tools to reduce operating costs.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5, P13):** Managed equivalents cover each tool's role, removing self-operated infrastructure while preserving familiar dashboards.

- **A** — wrong: still self-managed, just relocated.
- **B** — wrong: loses metrics and log analytics.
- **C** — correct: managed coverage of checks, metrics and logs, keeping Grafana.
- **D** — wrong: blind operations.

**Reference:** <https://cloud.google.com/stackdriver/docs/managed-prometheus>

</details>

### Q20 · Case: Cymbal Retail · Task 1.3 · Single answer

**Case study: Cymbal Retail.** Data silos across Cymbal's MySQL, SQL Server and MongoDB systems prevent a unified view of the customer journey. Analysts need near-real-time data, and governance must track where data comes from.

What should you recommend?

- **A.** Nightly CSV exports from each database, emailed to analysts.
- **B.** Federated queries from analysts' tools directly into each production database.
- **C.** Datastream change data capture into BigQuery as the unified analytics platform, with Knowledge Catalog for discovery, lineage and governance.
- **D.** Copy all customer data into Memorystore.

<details><summary>Answer</summary>

**Answer: C**

**Why (P4, P10):** CDC into a central warehouse unifies the data in near real time without loading production systems. A governance catalog tracks lineage.

- **A** — wrong: stale, manual and insecure.
- **B** — wrong: loads production databases, and the data isn't unified.
- **C** — correct: near-real-time unified analytics with governance.
- **D** — wrong: a cache, not an analytics platform.

**Reference:** <https://cloud.google.com/datastream/docs/overview>

</details>

## KnightMotives Automotive

### Q21 · Case: KnightMotives Automotive · Task 1.3 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives wants to collect telemetry from millions of vehicles to power real-time AI features and analytics. Many vehicles drive in rural areas with intermittent connectivity.

Which ingestion architecture should you recommend?

- **A.** Cloud IoT Core device registry and MQTT bridge, feeding BigQuery.
- **B.** Vehicles write directly to a Cloud SQL database over the cellular network.
- **C.** In-vehicle buffering with store-and-forward, publishing through a partner MQTT broker into Pub/Sub, processed by Dataflow into Bigtable (low-latency time series) and BigQuery (analytics).
- **D.** Vehicles upload CSV files to dealers during service visits.

<details><summary>Answer</summary>

**Answer: C**

**Why (P8, P1):** Intermittent connectivity calls for buffering at the edge and asynchronous, elastic ingestion. Separate serving and analytics stores fit their access patterns.

- **A** — wrong: Cloud IoT Core was retired in August 2023.
- **B** — wrong: a single relational database can't absorb millions of intermittent writers.
- **C** — correct: resilient, scalable ingestion, with the right stores.
- **D** — wrong: far too slow for real-time features.

**Reference:** <https://cloud.google.com/pubsub/docs/overview>

</details>

### Q22 · Case: KnightMotives Automotive · Task 3.2 · Single answer

**Case study: KnightMotives Automotive.** Adherence to EU data protection regulations is critical, especially for KnightMotives' emerging autonomous-driving platforms, which process personal data about EU drivers.

What should you recommend?

- **A.** Store all driver data in global multi-region datasets, to maximize availability.
- **B.** Place EU workloads in a dedicated folder with the `gcp.resourceLocations` organization policy restricted to EU locations, apply Assured Workloads EU data-boundary controls, and pseudonymize personal data before analytics.
- **C.** Rely on a VPC Service Controls perimeter alone.
- **D.** Label EU resources with `region=eu`.

<details><summary>Answer</summary>

**Answer: B**

**Why (P7, P10, P11):** Enforced residency (organization policy), regime controls (Assured Workloads) and data minimization (pseudonymization) together address EU data-protection obligations.

- **A** — wrong: global datasets can place EU personal data outside the EU.
- **B** — correct: enforced residency, governance and privacy-by-design.
- **C** — wrong: an exfiltration control, not residency.
- **D** — wrong: labels don't enforce anything.

**Reference:** <https://cloud.google.com/assured-workloads/docs/overview>

</details>

### Q23 · Case: KnightMotives Automotive · Task 1.1 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives wants to monetize corporate data, such as aggregated driving and road-condition data, to finance new technology. Buyers must never receive personally identifiable information.

What should you recommend?

- **A.** Export raw tables to buyers' Cloud Storage buckets.
- **B.** Grant buyers the Viewer role on the analytics project.
- **C.** Email monthly extracts to buyers.
- **D.** Publish curated, de-identified datasets through BigQuery sharing (formerly Analytics Hub) listings or data clean rooms, using Sensitive Data Protection for de-identification and BigQuery policy tags to protect sensitive columns.

<details><summary>Answer</summary>

**Answer: D**

**Why (P10, P11, P6):** Share governed, de-identified data products without copying raw data, and with controls that prevent re-identification.

- **A** — wrong: raw data includes PII, and copies escape control.
- **B** — wrong: over-broad access to everything in the project.
- **C** — wrong: uncontrolled copies.
- **D** — correct: governed, privacy-preserving data sharing.

**Reference:** <https://cloud.google.com/sensitive-data-protection/docs/sensitive-data-protection-overview>

</details>

### Q24 · Case: KnightMotives Automotive · Task 3.1 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives needs modern sales, service and inventory tools for dealers. Dealers have no budget for new equipment, and security is paramount because of past breaches.

What should you recommend?

- **A.** Deliver the dealer tools as web applications on Google Cloud, accessed through Chrome Enterprise Premium (IAP with context-aware access), so dealers use their existing browsers and devices.
- **B.** Ship VPN appliances to every dealership.
- **C.** Build thick-client desktop applications that require new dealer hardware.
- **D.** Publish the dealer tools on the internet without authentication, for simplicity.

<details><summary>Answer</summary>

**Answer: A**

**Why (P6, P5):** Browser-delivered applications need no new hardware. Zero-trust access gives per-application identity and device checks without VPN appliances.

- **A** — correct: no new equipment, strong security.
- **B** — wrong: hardware cost and network-level access.
- **C** — wrong: violates the no-budget constraint.
- **D** — wrong: insecure, especially after past breaches.

**Reference:** <https://cloud.google.com/chrome-enterprise-premium/docs/overview>

</details>

### Q25 · Case: KnightMotives Automotive · Task 2.3 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives' IT is largely on-premises, with some applications on other major cloud platforms. Its hybrid cloud strategy calls for consistent management of Kubernetes workloads across all of these environments.

What should you recommend?

- **A.** Separate management tools and processes for each environment.
- **B.** Migrate every workload to GKE in a single weekend.
- **C.** A GKE fleet that includes GKE clusters on Google Cloud, attached clusters running in the other clouds, and Google Distributed Cloud on-premises, managed with Config Sync and Policy Controller.
- **D.** Abandon containers in favor of VMs.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12, P15):** Fleets give one management model across Google Cloud, other clouds and on-premises. GitOps and policy keep configuration consistent while modernization proceeds gradually.

- **A** — wrong: fragmentation is the problem being solved.
- **B** — wrong: an unrealistic big bang that contradicts "gradually modernizing".
- **C** — correct: unified hybrid and multicloud management.
- **D** — wrong: a step backwards for modernization.

**Reference:** <https://cloud.google.com/kubernetes-engine/enterprise/config-sync/docs/overview>

</details>

### Q26 · Case: KnightMotives Automotive · Task 3.1 · Select TWO

**Case study: KnightMotives Automotive.** After past data breaches, KnightMotives requires a comprehensive security framework, an incident response plan and security awareness training.

Which two recommendations best address detection and response? (Select TWO.)

- **A.** Security Command Center (Premium or Enterprise) for organization-wide posture management, vulnerability findings and threat detection.
- **B.** Rely on perimeter firewalls alone.
- **C.** Google Security Operations (SIEM and SOAR) with response playbooks, backed by a documented incident response plan that's rehearsed in tabletop exercises.
- **D.** A manual security audit once a year.
- **E.** Disable audit logs to reduce costs.

<details><summary>Answer</summary>

**Answer: A, C**

**Why (P6, P13):** Continuous detection across the organization plus orchestrated, rehearsed response forms the core of a modern security operations capability.

- **A** — correct: posture and threat detection at organization scope.
- **B** — wrong: perimeter-only security ignores identity, data and insider threats.
- **C** — correct: SIEM/SOAR plus a practiced plan.
- **D** — wrong: far too infrequent.
- **E** — wrong: destroys forensic evidence.

**Reference:** <https://cloud.google.com/security-command-center/docs/security-command-center-overview>

</details>

### Q27 · Case: KnightMotives Automotive · Task 2.4 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives' AI infrastructure is obsolete. It needs large-scale training for autonomous driving, including many fault-tolerant experiments and periodic long training runs tied to regulatory submission dates. The runs must be traceable.

What should you recommend?

- **A.** Buy new on-premises GPU clusters, depreciated over five years.
- **B.** Use only on-demand accelerators for every job.
- **C.** Train on dealers' workstations overnight.
- **D.** Use AI Hypercomputer, with Spot or Dynamic Workload Scheduler flex-start capacity for checkpointed experiments, calendar-mode reservations for deadline-bound runs, and Agent Platform Pipelines with Model Registry for reproducibility and traceability.

<details><summary>Answer</summary>

**Answer: D**

**Why (P16, P9, P12):** Match each workload type to a consumption model (cheap interruptible capacity for experiments, guaranteed capacity for deadlines), and record lineage for regulators.

- **A** — wrong: capital expense and obsolescence risk, plus slow procurement.
- **B** — wrong: expensive, and capacity isn't guaranteed for deadline runs.
- **C** — wrong: insecure and impractical.
- **D** — correct: cost-optimized, deadline-safe and traceable.

**Reference:** <https://cloud.google.com/ai-hypercomputer/docs/overview>

</details>

### Q28 · Case: KnightMotives Automotive · Task 1.4 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives' supply chain runs on an outdated mainframe, which makes promotions and new data uses difficult. The business can't tolerate supply-chain disruption.

How should the mainframe be approached?

- **A.** Rewrite all mainframe applications in six months and switch over in one cutover.
- **B.** Retain the mainframe in the short term, offload its data to BigQuery with Mainframe Connector for analytics and new uses, and modernize functions incrementally, validating each against the mainframe before cutover.
- **C.** Shut down the mainframe and rely on spreadsheets until a replacement is ready.
- **D.** Move the mainframe hardware into a Google data center unchanged.

<details><summary>Answer</summary>

**Answer: B**

**Why (P15):** For high-risk legacy cores, retain and strangle: unlock the data first, then replace functions incrementally with parallel validation.

- **A** — wrong: a big-bang rewrite of critical systems is extremely risky.
- **B** — correct: value now, risk-managed modernization.
- **C** — wrong: disrupts the business.
- **D** — wrong: not an offering, and it changes nothing.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

</details>

### Q29 · Case: KnightMotives Automotive · Task 2.1 · Single answer

**Case study: KnightMotives Automotive.** Network upgrades are needed to support growing data traffic and improve connectivity between manufacturing plants and headquarters. Large plants generate heavy traffic, and some small plants generate very little.

What should you recommend?

- **A.** Cloud Interconnect at headquarters and the large plants, HA VPN for the small plants, and a Network Connectivity Center hub to connect the sites, using site-to-site data transfer over Google's backbone where supported.
- **B.** A full mesh of VPN tunnels between every pair of plants.
- **C.** The public internet with no encryption between sites.
- **D.** Direct Peering at every plant.

<details><summary>Answer</summary>

**Answer: A**

**Why (P14, P9):** Size each link to its site's needs. A hub-and-spoke on Google's backbone replaces an unmanageable mesh.

- **A** — correct: right-sized links and centralized hub routing.
- **B** — wrong: grows quadratically and is hard to operate.
- **C** — wrong: insecure and unreliable.
- **D** — wrong: Direct Peering reaches Google's public services only, not private site-to-site or VPC connectivity.

**Reference:** <https://cloud.google.com/network-connectivity/docs/network-connectivity-center/concepts/overview>

</details>

### Q30 · Case: KnightMotives Automotive · Task 4.2 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives lists employee upskilling, attracting top-tier talent and better communication between business and technical teams as critical objectives of its transformation.

What should you recommend?

- **A.** Outsource all technology work permanently.
- **B.** Wait until the transformation is complete before addressing skills.
- **C.** Require employees to self-study in their own time, with no structured program.
- **D.** Assess skills gaps against the target architecture, provide training paths and certifications, establish a cloud center of excellence, set shared business–technical KPIs, and hire selectively for critical roles.

<details><summary>Answer</summary>

**Answer: D**

**Why (P15):** People readiness is planned like any other workstream: assess, train, enable through a CCoE, align with shared goals and fill critical gaps.

- **A** — wrong: no internal capability.
- **B** — wrong: staff can't run what they weren't prepared for.
- **C** — wrong: unstructured, inequitable and ineffective.
- **D** — correct: a structured talent and communication strategy.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

</details>

## Altostrat Media

### Q31 · Case: Altostrat Media · Task 2.2 · Single answer

**Case study: Altostrat Media.** Altostrat wants to optimize Cloud Storage costs for its growing media library while maintaining high availability and scalability. Some content stays popular for years, while other content is rarely accessed, unpredictably. Egress for streaming is also significant.

What should you recommend?

- **A.** Move every object older than 7 days to Archive class.
- **B.** Enable Autoclass on the media buckets, and deliver content through Media CDN to reduce origin egress.
- **C.** Move the media library to Filestore.
- **D.** Delete content that hasn't been viewed in the last 30 days.

<details><summary>Answer</summary>

**Answer: B**

**Why (P9, P10):** Per-object automatic class management suits unpredictable access, and edge delivery reduces egress and origin load, without hurting availability.

- **A** — wrong: popular content would incur Archive retrieval costs and its minimum duration.
- **B** — correct: automatic storage-cost optimization plus egress reduction.
- **C** — wrong: file storage is costlier per GB for a large library.
- **D** — wrong: destroys the library, which is the business's asset.

**Reference:** <https://cloud.google.com/storage/docs/autoclass>

</details>

### Q32 · Case: Altostrat Media · Task 2.3 · Single answer

**Case study: Altostrat Media.** Altostrat must provide scalable, performant Kubernetes environments both on-premises (for content ingestion and archival workflows) and in the cloud, managed consistently.

What should you recommend?

- **A.** Self-managed open-source Kubernetes on-premises, with separate tooling from GKE.
- **B.** Move the on-premises workflows to plain VMs and stop using Kubernetes there.
- **C.** Google Distributed Cloud (software only) on-premises, registered to the same fleet as Altostrat's GKE clusters and managed with Config Sync.
- **D.** Run Cloud Run on-premises.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5, P12):** Google-managed Kubernetes software on-premises, in the same fleet, gives one consistent operating model across environments.

- **A** — wrong: inconsistent tooling and more operational burden.
- **B** — wrong: contradicts the Kubernetes requirement.
- **C** — correct: consistent hybrid Kubernetes.
- **D** — wrong: Cloud Run is a Google Cloud managed service, not an on-premises platform.

**Reference:** <https://cloud.google.com/kubernetes-engine/enterprise/config-sync/docs/overview>

</details>

### Q33 · Case: Altostrat Media · Task 5.1 · Single answer

**Case study: Altostrat Media.** Altostrat wants to modernize CI/CD for its containerized deployments with a centralized management platform, deploying consistently to GKE clusters in the cloud and on-premises.

What should you recommend?

- **A.** Cloud Build for builds, Artifact Registry for images (with vulnerability scanning), and Cloud Deploy delivery pipelines that promote releases across GKE targets, with Binary Authorization enforcing trusted images.
- **B.** A separate Jenkins server on a VM for each team.
- **C.** Developers building images on laptops and pushing them directly to production clusters.
- **D.** Manual deployments using copied YAML files.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12, P5):** Managed build, artifact and delivery services provide one consistent, auditable path to every environment, with supply-chain enforcement.

- **A** — correct: a centralized, managed CI/CD platform.
- **B** — wrong: fragmented, self-managed tooling.
- **C** — wrong: no traceability or controls.
- **D** — wrong: manual and error-prone.

**Reference:** <https://cloud.google.com/deploy/docs/overview>

</details>

### Q34 · Case: Altostrat Media · Task 2.5 · Single answer

**Case study: Altostrat Media.** Altostrat wants to automatically generate concise summaries of its back catalog, which holds thousands of hours of podcasts, interviews and documentaries. Cost matters more than speed for the back catalog.

What should you recommend?

- **A.** Train a custom summarization model on GPUs.
- **B.** Have editors write the summaries manually.
- **C.** Use the Natural Language API's sentiment analysis.
- **D.** Use a Gemini multimodal model on Agent Platform, which accepts audio and video input directly, and run the back catalog through batch inference.

<details><summary>Answer</summary>

**Answer: D**

**Why (P16, P9):** A multimodal foundation model summarizes audio and video natively, and batch inference lowers cost for large, non-urgent workloads.

- **A** — wrong: unnecessary effort and cost.
- **B** — wrong: doesn't scale to thousands of hours.
- **C** — wrong: sentiment isn't a summary.
- **D** — correct: native multimodal summarization at batch prices.

**Reference:** <https://cloud.google.com/vertex-ai/generative-ai/docs/multimodal/batch-prediction-gemini>

</details>

### Q35 · Case: Altostrat Media · Task 3.1 · Single answer

**Case study: Altostrat Media.** Altostrat must design AI-powered detection of harmful content for media uploaded to its platform. Clear violations should be blocked automatically, and borderline cases reviewed by people.

Which design should you recommend?

- **A.** A weekly batch job that samples 1% of uploads for manual review.
- **B.** An event-driven pipeline: uploads to Cloud Storage trigger Eventarc and a Cloud Run service, which runs Video Intelligence explicit content detection and Vision SafeSearch (or Gemini classification). Clear violations go to a quarantine bucket, and borderline items go to a human review queue.
- **C.** Rely on viewers to report inappropriate content.
- **D.** Block every upload until an editor watches it in full.

<details><summary>Answer</summary>

**Answer: B**

**Why (P8, P16):** Automated classification on arrival scales moderation, quarantine contains risk, and human review handles ambiguity.

- **A** — wrong: most harmful content would go unchecked.
- **B** — correct: automated, timely, with humans in the loop.
- **C** — wrong: reactive, and harm happens first.
- **D** — wrong: doesn't scale.

**Reference:** <https://cloud.google.com/video-intelligence/docs>

</details>

### Q36 · Case: Altostrat Media · Task 3.2 · Select TWO

**Case study: Altostrat Media.** Altostrat requires that its AI systems are auditable and that their decisions can be explained. This applies to its recommendation and dynamic-pricing models as well as its generative chatbot.

Which two measures should you recommend? (Select TWO.)

- **A.** Use a third-party black-box API that doesn't log requests.
- **B.** Use Explainable AI feature attributions for the predictive models, and version every model in Model Registry with lineage.
- **C.** Disable logging of model inputs and outputs, to save cost.
- **D.** Let models update themselves in production without evaluation.
- **E.** Log prompts, grounding sources, responses and model versions (with PII redacted) to BigQuery, and evaluate generative output regularly with the Gen AI evaluation service.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P16, P13):** Explainability (attributions) plus traceability (versions, lineage, logs) and ongoing evaluation make AI decisions auditable.

- **A** — wrong: unexplainable and unauditable.
- **B** — correct: explanations and lineage for predictive models.
- **C** — wrong: removes the audit trail.
- **D** — wrong: ungoverned changes.
- **E** — correct: an audit trail and quality evidence for generative AI.

**Reference:** <https://cloud.google.com/vertex-ai/docs/model-registry/introduction>

</details>

### Q37 · Case: Altostrat Media · Task 2.1 · Single answer

**Case study: Altostrat Media.** Altostrat's on-premises content ingestion system receives large video files continuously, and they must reach Cloud Storage for processing. The technical requirements call for secure, high-performance hybrid connectivity for data ingestion.

What should you recommend?

- **A.** Upload files over the public internet from a script on an ingestion server.
- **B.** Ship disks to Google every week.
- **C.** Dedicated or Partner Interconnect (with HA VPN as backup), using Storage Transfer Service agents on-premises to move files continuously into Cloud Storage.
- **D.** A single Classic VPN tunnel.

<details><summary>Answer</summary>

**Answer: C**

**Why (P14, P10):** Sustained large-file ingestion needs private, high-bandwidth links. Managed transfer agents handle parallelism, retries and scheduling.

- **A** — wrong: neither private nor reliably high-performance.
- **B** — wrong: offline shipping doesn't suit continuous ingestion.
- **C** — correct: secure, high-performance, managed transfer.
- **D** — wrong: limited bandwidth and lower SLA.

**Reference:** <https://cloud.google.com/storage-transfer/docs/overview>

</details>

### Q38 · Case: Altostrat Media · Task 6.2 · Single answer

**Case study: Altostrat Media.** Altostrat uses Cloud Monitoring together with self-run Prometheus, and alerts are primarily delivered by email. Reliability is one of the executives' top priorities.

What should you recommend?

- **A.** Move Prometheus collection to Managed Service for Prometheus, define SLOs for key user journeys such as playback start and API availability, and route burn-rate alerts to on-call channels (PagerDuty or Slack) with runbooks.
- **B.** Add more email recipients to every alert.
- **C.** Replace alerting with a daily summary email.
- **D.** Run a second self-managed Prometheus server for redundancy, and keep email alerts.

<details><summary>Answer</summary>

**Answer: A**

**Why (P13, P5):** Managed metrics remove operational toil. SLO-based alerts routed to on-call responders make reliability measurable and actionable.

- **A** — correct: managed collection, user-centric SLOs, actionable routing.
- **B** — wrong: email remains easy to ignore.
- **C** — wrong: delays detection.
- **D** — wrong: more self-management, with the same alerting weakness.

**Reference:** <https://cloud.google.com/stackdriver/docs/managed-prometheus>

</details>

### Q39 · Case: Altostrat Media · Task 1.4 · Single answer

**Case study: Altostrat Media.** Altostrat plans to migrate its on-premises archive (about 3 PB of rarely accessed media) to Google Cloud within three months. The data center's internet connection is 1 Gbps and is shared with production traffic.

What should you recommend?

- **A.** Copy the archive over the existing 1 Gbps connection with `gcloud storage cp`.
- **B.** Upgrade to a 10 Gbps connection and copy the archive over it during nights and weekends.
- **C.** Replicate the archive with Database Migration Service.
- **D.** Use Transfer Appliance to move the archive into an Archive-class Cloud Storage bucket.

<details><summary>Answer</summary>

**Answer: D**

**Why (P10, P9):** At 1 Gbps, 3 PB would take about 300 days. Even part-time 10 Gbps barely fits and disrupts production. Offline transfer is the documented answer, and Archive class fits rarely accessed data.

- **A** — wrong: misses the timeline by months and saturates production.
- **B** — wrong: at off-hours utilization it's still months, and it adds cost and lead time.
- **C** — wrong: DMS migrates databases, not files.
- **D** — correct: bulk offline transfer to the cheapest suitable storage class.

**Reference:** <https://cloud.google.com/transfer-appliance/docs/4.0/overview>

</details>

### Q40 · Case: Altostrat Media · Task 3.1 · Single answer

**Case study: Altostrat Media.** Altostrat's new personalized chatbot and recommendation features require millions of consumers to sign in, including with social logins. Today, user management is a combination of Google Identity and third-party identity providers.

What should you use to authenticate consumers?

- **A.** Create a Cloud Identity account for every consumer.
- **B.** Identity Platform, providing customer identity and access management with social and enterprise identity providers.
- **C.** Managed Service for Microsoft Active Directory.
- **D.** One shared service account used by all consumer sessions.

<details><summary>Answer</summary>

**Answer: B**

**Why (P6, P5):** Consumer-facing authentication at scale, with social logins, is customer identity and access management, which is Identity Platform's role. Workforce identity is a different problem.

- **A** — wrong: Cloud Identity is for workforce identities, not millions of consumers.
- **B** — correct: managed customer identity and access management.
- **C** — wrong: a directory for workloads, not consumer authentication.
- **D** — wrong: no per-user identity, and insecure.

**Reference:** <https://cloud.google.com/identity-platform/docs/concepts>

</details>
