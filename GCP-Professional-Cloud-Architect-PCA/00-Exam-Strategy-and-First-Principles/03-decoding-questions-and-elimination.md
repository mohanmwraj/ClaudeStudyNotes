# 03 · Decoding Questions and Elimination

On the PCA exam, knowing the services is necessary but not sufficient. The exam tests whether you can see **which requirement decides the question** and **why three plausible options lose**. This file is the technique layer: a phrase dictionary, the exam's built-in preferences, elimination rules and worked examples that apply the five-step procedure from [02-first-principles-mental-models.md](02-first-principles-mental-models.md).

---

## 1. The phrase dictionary: what the words really mean

### Qualifiers (the tie-breakers)

| Phrase in the question | What it selects for | Typical winner |
|---|---|---|
| "Following Google-recommended practices" | The documented, opinionated Google way | Managed services, least privilege, groups not users, IaC, no SA keys |
| "Minimize operational overhead" / "small team" / "reduce administration" | The most managed option (P5) | Serverless / Autopilot / managed DB over VMs |
| "Most cost-effective" / "minimize cost" | The cheapest option that still meets **every** stated requirement (P9) | Autoscaling, Spot for batch, CUDs for steady state, colder storage classes |
| "Least amount of downtime" / "minimal disruption" | Continuous replication then cutover (P15) | Database Migration Service CDC, rolling or blue/green |
| "As quickly as possible" / "deadline" | Least change now; modernize later | Rehost, managed equivalents of what exists |
| "Most secure" / "reduce risk" | Defense in depth, smallest blast radius | Private IPs, VPC SC, CMEK if custody matters, IAP, WIF |
| "Without changing the application code" | Infrastructure-level fix only | Load balancer, MIG, Cloud SQL, proxies, not refactoring |
| "Scalable to meet growth" | Horizontal, elastic, managed | Regional MIG/GKE/Cloud Run, Spanner/Bigtable when data scale demands |
| "Future-proof" / "cloud-first" (Objective 1.5) | Loose coupling, open standards, managed | APIs, events, containers, managed data platforms |

### Constraint words (the hard filters)

| Phrase | Constraint it imposes |
|---|---|
| "must", "minimum", "required", "cannot", "only" | Hard filter. Any option that violates it is out, however elegant |
| "existing", "legacy", "current" | Compatibility. Respect what's there unless the question asks to replace it |
| "global users", "worldwide" | Global load balancing and possibly multi-region data |
| "regulated", "HIPAA", "PCI", "GDPR", "EU only", "sovereignty" | Residency, audit logging, key custody, de-identification |
| "spiky", "unpredictable", "seasonal" | Autoscaling, queues, serverless |
| "steady", "predictable", "24×7 for 3 years" | Committed use discounts |
| "fault-tolerant", "can be restarted", "batch" | Spot VMs |
| "real-time", "streaming", "sub-second" | Pub/Sub plus Dataflow; Bigtable or Memorystore for serving |
| "ad-hoc analysis", "data warehouse", "SQL over petabytes" | BigQuery |
| "no public IPs", "private" | Private Google Access, PSC, Cloud NAT, IAP |
| "audit", "who did what" | Cloud Audit Logs (Admin Activity is always on; Data Access must be enabled for most services) |

---

## 2. The exam's built-in preferences ("Google bias")

These preferences are consistent across Google's official materials and the questions built from them. When two options both work, the one matching these preferences wins.

1. **Managed over self-managed** (P5). Cloud SQL over MySQL on a VM; Managed Service for Apache Kafka over self-run Kafka; Cloud Run over a VM running Docker.
2. **Native over custom code.** An org policy, lifecycle rule, uptime check, log sink or Cloud Scheduler job beats a script you'd write and run.
3. **Groups over individuals; predefined roles over basic roles; least privilege always** (P6).
4. **No service account keys.** Use attached service accounts, Workload Identity Federation, Workload Identity Federation for GKE and impersonation.
5. **Regional over zonal for production; multi-region only when the requirement asks** (P1, P2).
6. **Infrastructure as code and CI/CD** over console clicks for anything repeatable (P12).
7. **Least change that meets the requirement.** Don't re-architect when a configuration change suffices; don't migrate what the case study says to keep.
8. **Highest-level AI abstraction first** (P16). An API or Gemini prompt before tuning; tuning before custom training.
9. **Security controls at the highest sensible level of the hierarchy** (P7). An org or folder policy over per-project settings.
10. **Measure before optimizing.** Use Recommender, Active Assist, Cloud Profiler, query execution plans or Migration Center assessment before resizing or rewriting.

---

## 3. Elimination rules

Apply these in order. Usually you're left with one option after rule 4.

1. **Violates a hard constraint?** Out. A zonal resource for HA, a US multi-region bucket for EU-only data, code changes when "no code changes" is stated.
2. **Doesn't actually solve the stated problem?** Out. A plausible action aimed at a different symptom, such as adding CPU to fix a latency problem caused by distance.
3. **Technically impossible or nonexistent?** Out. Watch for invented features: "enable transitive peering", "set a VPN tunnel to 50 Gbps", "Cloud Storage 'Glacier' class", "use BigQuery for OLTP row updates at 10,000 TPS".
4. **Correct but heavier than an alternative?** Out when a qualifier mentions cost, ops or speed. "Write a Cloud Run function that polls every minute" loses to a native event trigger.
5. **Two survivors?** Re-read the qualifier and the case study. The difference is usually a single word: *regional* vs *global*, *at least once* vs *exactly once*, *existing* vs *new*.

### Distractor archetypes to recognize instantly

| Archetype | Example | Why it's wrong |
|---|---|---|
| The **over-engineer** | Multi-region active-active Spanner for a 99.9% internal tool | Meets the SLA at many times the cost and complexity |
| The **under-engineer** | Single VM with snapshots for "high availability" | Snapshots are backup, not HA |
| The **hand-roller** | Cron script on a VM to copy logs nightly | A log sink does it natively and continuously |
| The **key leaker** | Create a service account key and store it in Secret Manager | Still a long-lived key; use WIF or an attached SA |
| The **basic-role grant** | Give the team Editor on the project | Violates least privilege |
| The **wrong-layer fix** | Firewall rule to stop BigQuery data exfiltration | Firewalls don't govern Google API access; VPC SC does |
| The **almost-right service** | Cloud SQL for globally consistent multi-region writes | Single-region primary; Spanner fits |
| The **ignores-the-case-study** | Migrate EHR's legacy insurance integrations to the cloud now | The case says there's no plan to move them |
| The **outdated name or product** | Use Cloud IoT Core / Container Registry / Data Catalog | Retired or replaced. Pick the current product |

---

## 4. Multiple-select questions

* The stem says **"Choose two"** or **"Choose three"**, and there's no partial credit.
* Each correct option must be **independently true and necessary**. Often the correct pair covers two halves of a requirement: one option fixes identity and the other fixes network, or one sets up replication and the other sets up failover.
* Eliminate options that are **true statements but irrelevant** to the goal. Multiple-select distractors are often correct facts that don't answer the question.
* If two options are mutually exclusive (both configure the same thing differently), at most one is correct.

---

## 5. Case-study questions: the method

1. **Before the exam,** study the four case-study breakdowns in [01-Case-Studies](../01-Case-Studies/) until you can recite each company's top three constraints from memory.
2. **During a case question,** identify which requirement the question is really about. Questions often paraphrase a case requirement without quoting it.
3. **Apply the case's standing constraints** even when the question doesn't repeat them:
   * **EHR Healthcare:** at least 99.9% availability, regulatory compliance (health data), Microsoft Active Directory identities, legacy insurance integrations stay on-premises, existing Kubernetes, MySQL/SQL Server/Redis/MongoDB, ignored email alerts.
   * **Cymbal Retail:** generative-AI catalog enrichment with human review, natural-language product discovery, conversational commerce replacing IVR load, mixed on-premises/cloud, SFTP/ETL integrations, MySQL/SQL Server/Redis/MongoDB, open-source monitoring.
   * **Altostrat Media:** already on Google Cloud (GKE, Cloud Storage, BigQuery, Cloud Run functions); some on-premises ingestion and archival; reliability and cost are top priorities; harmful-content detection; explainable and auditable AI; Kubernetes on-premises and in the cloud; Prometheus plus email alerts.
   * **KnightMotives Automotive:** mostly on-premises plus other clouds; mainframe supply chain; past breaches mean security is paramount; EU data protection; rural connectivity; data monetization; dealers have no budget for new equipment; hybrid cloud strategy; upskilling.
4. **Prefer answers that satisfy more than one case requirement at once.** Case-study questions reward solutions that fit the whole company, not just the sentence in front of you.

---

## 6. Worked examples

These are reasoning walk-throughs, not graded questions. The graded questions live in [08-Exam-Questions-and-Sample-Papers](../08-Exam-Questions-and-Sample-Papers/).

### Example 1 · The qualifier decides

> A retailer runs a stateless web front end on Compute Engine. Traffic is predictable on weekdays and triples during monthly sales. They want to reduce cost without risking availability during sales. What should they do?

* **Constraints:** stateless, predictable baseline, periodic peaks, availability must hold. **Qualifier:** cost.
* **Principles:** P3 (stateless means elastic), P9 (match pricing to load shape).
* **Derived answer:** a regional MIG with autoscaling. Cover the steady baseline with a **committed use discount** and let autoscaling add on-demand VMs for peaks. Spot VMs for the serving tier would risk availability during peaks, exactly when preemption is most likely to hurt.
* **Eliminations:** "3-year CUD for peak capacity" pays for idle capacity most of the month. "Spot VMs for all instances" risks the availability requirement. "Move to a larger machine type" doesn't address the shape of the load.

### Example 2 · The hidden case-study constraint

> (EHR Healthcare) EHR wants to start sending data from its on-premises insurance integration systems to Google Cloud for analytics. What should you recommend for connectivity?

* **Case constraints:** "secure and high-performance connection between on-premises systems and Google Cloud"; legacy integrations remain on-premises for years; 99.9% availability for customer-facing systems; regulated health data.
* **Principles:** P14 (hybrid link sizing), P2 (redundancy), P15 (retain legacy).
* **Derived answer:** Dedicated Interconnect (or Partner Interconnect if no colocation presence), with redundant connections in a topology that meets the SLA, and HA VPN as a backup or interim path. Data access stays private: Private Google Access for on-premises hosts, or a PSC endpoint for Google APIs.
* **Eliminations:** "Migrate the legacy integrations to Compute Engine first" contradicts the case. "Public internet with TLS to public endpoints" fails "secure and high-performance". "A single VPN tunnel" fails performance and redundancy.

### Example 3 · Wrong layer

> A security team must ensure that data in BigQuery and Cloud Storage in the production projects can't be copied to projects outside the organization, even by users who have the necessary IAM permissions. What should they do?

* **Constraint:** stop exfiltration *despite* valid IAM. That's beyond what IAM can do by definition.
* **Principle:** P6 (identity first, plus a context perimeter for exfiltration).
* **Derived answer:** a **VPC Service Controls** perimeter around the production projects, restricting BigQuery and Cloud Storage. Add access levels or ingress/egress rules only for legitimate flows.
* **Eliminations:** "Remove IAM permissions" breaks legitimate work and doesn't meet "even by users who have permissions". "VPC firewall egress deny rules" don't govern Google API traffic. "Organization policy restricting resource locations" controls *where resources are created*, not data copying.

### Example 4 · Managed vs custom

> Application logs from 200 projects must be retained for 7 years for audit and queried occasionally with SQL. The team wants the least operational overhead. What should they do?

* **Constraints:** many projects, 7-year retention, occasional SQL. **Qualifier:** least ops.
* **Principles:** P5, P10, P13.
* **Derived answer:** an **aggregated log sink** at the organization or folder level routing to a central **log bucket** with 7-year retention and **Log Analytics** enabled for SQL queries. A sink to BigQuery is also acceptable if heavy analytics is needed.
* **Eliminations:** "Install agents that ship logs to a self-managed Elasticsearch cluster" is heavy. "A per-project sink created by a script" works but is worse than one aggregated sink. "Export logs nightly with a Cloud Run job" is hand-rolled.

### Example 5 · Choose two

> A company is moving a payment API to GKE. They must (1) ensure only images built by their CI pipeline run in production, and (2) prevent pods from using long-lived credentials to call Google APIs. Which two actions should they take? (Choose two.)

* **Principles:** P12 (supply chain), P6 (keyless identity).
* **Derived answers:** enable **Binary Authorization** with an attestation policy that requires the CI attestor; use **Workload Identity Federation for GKE**, binding Kubernetes service accounts to IAM principals.
* **Eliminations:** "Store a service account key as a Kubernetes Secret" is a long-lived key. "Use Artifact Analysis vulnerability scanning" is useful but doesn't *enforce* provenance at deploy time. "Run pods as non-root" is good hygiene that answers neither requirement.

---

## 7. Time management in the exam

* **First pass (about 85 minutes):** answer everything you're confident about; flag anything that takes over 3 minutes and pick a provisional answer before moving on.
* **Second pass (about 25 minutes):** revisit flags. Apply elimination rule 5: re-read the qualifier and the case study.
* **Final 10 minutes:** make sure no question is blank. Don't change answers without a concrete reason; first instincts based on a principle are usually right.
