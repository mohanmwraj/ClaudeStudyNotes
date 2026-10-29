# Mock Paper 1 · Answers and Explanations

Answers for [08-mock-paper-1.md](08-mock-paper-1.md). Every option is explained. Read the explanations for the questions you got right too: you may have been right for the wrong reason.

**Tally your score by domain** using the domain labels in the questions file. A domain below 70% marks the folder to revisit.

**Quick key:**

1 A,C,E · 2 D · 3 A · 4 C · 5 B,D · 6 B · 7 A · 8 D · 9 C · 10 A · 11 B · 12 D · 13 C · 14 A · 15 C · 16 B · 17 D · 18 A,C · 19 A · 20 B · 21 D · 22 C · 23 B · 24 A · 25 D · 26 A,D · 27 C · 28 B · 29 A · 30 D · 31 C · 32 B · 33 D · 34 A,C · 35 A · 36 C · 37 B · 38 D · 39 A · 40 C · 41 B · 42 D · 43 A · 44 C · 45 B · 46 D · 47 A · 48 B,E · 49 C · 50 B

---

### Q1 · Answer: A, C, E

**Why (P12, P9, P13):** Each root cause in the executive statement maps to one capability: misconfiguration to configuration as code with review, capacity spikes to autoscaling, and inconsistent monitoring to standardized observability with SLOs.

- **A** — correct: declarative, reviewed configuration prevents misconfiguration.
- **B** — wrong: slow manual gates don't prevent errors, and they reduce delivery speed.
- **C** — correct: elastic capacity absorbs spikes.
- **D** — wrong: bigger machines are still finite and waste money.
- **E** — correct: consistent, actionable monitoring across environments.
- **F** — wrong: email alerts are already ignored, according to the case.

**Reference:** <https://cloud.google.com/architecture/framework/operational-excellence>

### Q2 · Answer: D

**Why (P2, P9):** RPO 15 minutes and RTO 1 hour call for warm standby: asynchronous replication of data, plus a ready but small compute footprint, plus automation. It's cheaper than active-active and meets both targets.

- **A** — wrong: over-engineered and costly for these targets.
- **B** — wrong: nightly exports give about a 24-hour RPO, a same-region copy doesn't survive a regional disaster, and a rebuild exceeds the RTO.
- **C** — wrong: a Cloud SQL HA standby is in another *zone* of the same region, not another region.
- **D** — correct: meets RPO and RTO at reasonable cost.

**Reference:** <https://cloud.google.com/architecture/dr-scenarios-planning-guide>

### Q3 · Answer: A

**Why (P4, P5):** Offline-first mobile sync with real-time updates and serverless scaling are Firestore's defining features.

- **A** — correct: offline persistence, sync and real-time listeners.
- **B** — wrong: no client offline sync, and instances to manage.
- **C** — wrong: no mobile sync, and it's built for very large throughput, not app profiles.
- **D** — wrong: an analytics warehouse, not an app database.

**Reference:** <https://cloud.google.com/firestore/docs>

### Q4 · Answer: C

**Why (P3, P9, P5):** Stateless autoscaled front ends, an in-memory cache for hot data and edge caching for images handle spikes with little operations work.

- **A** — wrong: pays for peak capacity all year, and disks don't scale image delivery.
- **B** — wrong: a single point of failure that can't absorb spikes.
- **C** — correct: elastic, cached and managed.
- **D** — wrong: BigQuery isn't a low-latency serving store.

**Reference:** <https://cloud.google.com/run/docs/overview/what-is-cloud-run>

### Q5 · Answer: B, D

**Why (P8, P4):** Streaming ingestion into a partitioned warehouse gives fresh ad-hoc SQL at scale, and a semantic BI layer governs the dashboards.

- **A** — wrong: Cloud SQL can't serve years of 2 TB/day analytics.
- **B** — correct: elastic ingestion and processing into BigQuery.
- **C** — wrong: Bigtable doesn't support ad-hoc SQL joins well.
- **D** — correct: governed metrics and dashboards.
- **E** — wrong: a cache isn't long-term storage.

**Reference:** <https://cloud.google.com/dataflow/docs/overview>

### Q6 · Answer: B

**Why (P5, P15):** A managed SQL Server with the license included, plus continuous migration from backups, minimizes administration, licensing work and downtime.

- **A** — wrong: self-managed, with separate licensing and manual backups.
- **B** — correct: managed, license included, minimal downtime.
- **C** — wrong: BigQuery isn't an OLTP database.
- **D** — wrong: an unnecessary rewrite.

**Reference:** <https://cloud.google.com/database-migration/docs/overview>

### Q7 · Answer: A

**Why (P1, P15):** Chatty dependencies must stay close together. Splitting them across a hybrid link turns microseconds into milliseconds per call, multiplied by thousands per transaction.

- **A** — correct: move tightly coupled components together.
- **B** — wrong: a second link adds bandwidth and redundancy, not lower latency, so the round trips stay slow.
- **C** — wrong: the same split, reversed and prolonged.
- **D** — wrong: introduces consistency problems, and doesn't remove database calls.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

### Q8 · Answer: D

**Why (P5, P8):** Low-code integration with prebuilt SaaS connectors, branching and retries is Application Integration's purpose.

- **A** — wrong: custom code and a self-managed VM.
- **B** — wrong: manual, delayed and error-prone.
- **C** — wrong: tight coupling and security risk, and SaaS systems don't expose their databases.
- **D** — correct: managed, low-code integration.

**Reference:** <https://cloud.google.com/application-integration/docs/overview>

### Q9 · Answer: C

**Why (P9, P3):** Reactive autoscaling can't help an application that needs 10 minutes to boot. You must add capacity *before* the spike, through prediction or a schedule, and shorten boot time.

- **A** — wrong: keeps many idle VMs and still reacts after load arrives.
- **B** — wrong: removes elasticity and resilience.
- **C** — correct: proactive scaling plus faster startup.
- **D** — wrong: adds a region without fixing the timing problem.

**Reference:** <https://cloud.google.com/compute/docs/instance-groups>

### Q10 · Answer: A

**Why (P15, P5):** When an application needs a full Windows OS and domain join, rehosting to Compute Engine with a managed AD domain is the least-change, supported path.

- **A** — correct: Windows VMs plus a managed AD domain.
- **B** — wrong: Cloud Run runs Linux containers only.
- **C** — wrong: for event-driven functions, not IIS applications.
- **D** — wrong: App Engine standard doesn't support this kind of Windows workload.

**Reference:** <https://cloud.google.com/compute/docs/instances/windows>

### Q11 · Answer: B

**Why (P10, P16):** Every AI use case needs trusted, discoverable data. A governed data foundation shortens every future AI project.

- **A** — wrong: multiplies copies and inconsistency.
- **B** — correct: unified, governed data for Agent Platform projects.
- **C** — wrong: locks in one model, and fine-tuning isn't the general answer for knowledge.
- **D** — wrong: silos are an existing pain point in the case.

**Reference:** <https://docs.cloud.google.com/knowledge-catalog/docs/faq>

### Q12 · Answer: D

**Why (P10, P5):** Storage Transfer Service moves data from S3 without agents and supports scheduled incremental syncs, with no servers to manage.

- **A** — wrong: an offline appliance for on-premises data, and 40 TB transfers well online from cloud to cloud.
- **B** — wrong: a self-managed VM and scripts.
- **C** — wrong: migrates databases, not objects.
- **D** — correct: managed one-time plus recurring transfer.

**Reference:** <https://cloud.google.com/storage-transfer/docs/overview>

### Q13 · Answer: C

**Why (P2, P5):** A managed in-memory store with a cross-zone replica and automatic failover meets the availability need with minimal administration.

- **A** — wrong: a single VM is a single point of failure.
- **B** — wrong: per-pod caches lose sessions when pods move or scale.
- **C** — correct: highly available, managed caching.
- **D** — wrong: far too slow for sessions.

**Reference:** <https://cloud.google.com/memorystore/docs/redis>

### Q14 · Answer: A

**Why (P14):** Hybrid name resolution from Google Cloud to on-premises uses Cloud DNS forwarding zones over the private link.

- **A** — correct: the native hybrid DNS pattern.
- **B** — wrong: brittle, and breaks when IP addresses change.
- **C** — wrong: publishes internal names publicly, and they wouldn't resolve to private addresses correctly.
- **D** — wrong: unmanageable configuration drift.

**Reference:** <https://cloud.google.com/dns/docs/zones/zones-overview>

### Q15 · Answer: C

**Why (P1, P2):** Internal L7 routing with back ends in several regions and cross-region failover is the cross-region internal Application Load Balancer.

- **A** — wrong: external, which violates the no-internet-exposure rule.
- **B** — wrong: L4 and regional, with no path routing or cross-region failover.
- **C** — correct: internal, L7, cross-region.
- **D** — wrong: external, and L4.

**Reference:** <https://cloud.google.com/load-balancing/docs/choosing-load-balancer>

### Q16 · Answer: B

**Why (P2, P15):** A managed NFS service with zone redundancy fits an application that needs POSIX semantics and HA without code changes.

- **A** — wrong: FUSE isn't fully POSIX, and that may break the CMS.
- **B** — correct: managed, regional NFS.
- **C** — wrong: a zonal disk can't be shared read-write by several VMs, and it isn't zone-redundant.
- **D** — wrong: ephemeral storage with inconsistent sync.

**Reference:** <https://cloud.google.com/filestore/docs/overview>

### Q17 · Answer: D

**Why (P3, P13):** Keeping warm instances removes cold starts, and startup CPU boost shortens the cold starts that remain.

- **A** — wrong: caps scaling, which hurts latency under load.
- **B** — wrong: has the same cold-start behavior.
- **C** — wrong: the timeout doesn't affect startup latency.
- **D** — correct: removes and shortens cold starts.

**Reference:** <https://cloud.google.com/run/docs/configuring/min-instances>

### Q18 · Answer: A, C

**Why (P9, P3):** Spot capacity suits interruptible batch work, and rightsizing requests with autoscaling removes idle nodes. Both cut cost without touching the serving tier's reliability.

- **A** — correct: discounted capacity, isolated from the web services.
- **B** — wrong: keeps paying for idle peak capacity.
- **C** — correct: accurate requests, then fewer nodes.
- **D** — wrong: doesn't fix low utilization.
- **E** — wrong: removes the visibility you need for safe optimization.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview>

### Q19 · Answer: A

**Why (P12, P16):** Training–serving skew comes from inconsistent feature computation. A single feature definition used for both training and serving removes it.

- **A** — correct: consistent features offline and online.
- **B** — wrong: keeps the skew.
- **C** — wrong: model size isn't the problem.
- **D** — wrong: more endpoints serve the same skewed features.

**Reference:** <https://cloud.google.com/vertex-ai/docs/featurestore/latest/overview>

### Q20 · Answer: B

**Why (P16, P5):** Managed conversational agents grounded in Cymbal's own content give accurate, natural answers, with built-in human escalation in the contact-center suite.

- **A** — wrong: rigid, and doesn't understand natural language.
- **B** — correct: grounded conversational AI with handoff.
- **C** — wrong: not an assistant.
- **D** — wrong: enormous effort, and still needs grounding.

**Reference:** <https://cloud.google.com/dialogflow/cx/docs>

### Q21 · Answer: D

**Why (P14):** Two VPCs in different organizations, with non-overlapping ranges, needing full private connectivity and separate administration, is VPC Network Peering's sweet spot.

- **A** — wrong: Shared VPC works only within one organization, and centralizes control.
- **B** — wrong: not private.
- **C** — wrong: per-service endpoints don't provide full network connectivity.
- **D** — correct: low-latency private connectivity with each side keeping its own administration.

**Reference:** <https://cloud.google.com/vpc/docs/vpc-peering>

### Q22 · Answer: C

**Why (P9):** Custom quotas cap bytes processed per user and per project. Required partition filters prevent accidental full scans.

- **A** — wrong: destroys data.
- **B** — wrong: Cloud SQL isn't for multi-terabyte analytics.
- **C** — correct: hard spending limits plus query hygiene.
- **D** — wrong: after-the-fact, with no control.

**Reference:** <https://cloud.google.com/bigquery/docs/partitioned-tables>

### Q23 · Answer: B

**Why (P6):** Preventing exfiltration *despite* valid IAM requires a service perimeter at the API layer.

- **A** — wrong: blocks legitimate analysis.
- **B** — correct: VPC Service Controls restricts data movement across the perimeter.
- **C** — wrong: firewalls don't govern Google API data copies.
- **D** — wrong: controls where resources are created, not data movement.

**Reference:** <https://cloud.google.com/vpc-service-controls/docs/overview>

### Q24 · Answer: A

**Why (P11, P12):** Secret Manager versions plus rotation notifications automate rotation. Reading the latest version at runtime avoids redeploys.

- **A** — correct: managed secret with automated, zero-downtime rotation.
- **B** — wrong: a secret in code, with redeploys.
- **C** — wrong: plain-text secrets in IaC.
- **D** — wrong: not a secrets manager, with no rotation, versioning or fine-grained auditing designed for secrets.

**Reference:** <https://cloud.google.com/secret-manager/docs/overview>

### Q25 · Answer: D

**Why (P6, P7):** IAM Conditions can expire a role binding automatically. Granting to a group simplifies membership.

- **A** — wrong: depends on someone remembering.
- **B** — wrong: keys are for workloads, not humans, and long-lived keys are discouraged.
- **C** — wrong: over-privileged.
- **D** — correct: automatic, auditable expiry.

**Reference:** <https://cloud.google.com/iam/docs/overview>

### Q26 · Answer: A, D

**Why (P6):** Identity-aware access for the human tool, and narrowly scoped workload identities for each pipeline step.

- **A** — correct: only the associates' group can reach the application.
- **B** — wrong: exposes an internal tool.
- **C** — wrong: massively over-privileged.
- **D** — correct: per-component least privilege.
- **E** — wrong: long-lived keys shared over email.

**Reference:** <https://cloud.google.com/iap/docs/concepts-overview>

### Q27 · Answer: C

**Why (P7, P14):** Organization-level hierarchical firewall policies are evaluated before VPC rules and can't be overridden by projects. Threat-intelligence objects keep the malicious-IP lists current.

- **A** — wrong: inconsistent, and project owners can change their own rules.
- **B** — wrong: Cloud Armor protects inbound traffic at load balancers, not VM egress.
- **C** — correct: central, unoverridable, intelligence-driven blocking.
- **D** — wrong: detection, not prevention.

**Reference:** <https://cloud.google.com/firewall/docs/firewall-policies>

### Q28 · Answer: B

**Why (P13):** Data reads are recorded in Data Access audit logs, which are on by default for BigQuery. BigQuery job metadata also shows who queried what.

- **A** — wrong: flow logs show network flows, not table reads.
- **B** — correct: who read the data, and when.
- **C** — wrong: Admin Activity logs record configuration changes, not data reads.
- **D** — wrong: unrelated.

**Reference:** <https://cloud.google.com/logging/docs/audit>

### Q29 · Answer: A

**Why (P11):** Confidential Computing encrypts memory in use with hardware-based keys, transparently to the applications.

- **A** — correct: encryption in use with no code changes.
- **B** — wrong: at rest only.
- **C** — wrong: at rest only, for Cloud Storage.
- **D** — wrong: an exfiltration control, not memory encryption.

**Reference:** <https://cloud.google.com/confidential-computing/confidential-vm/docs/confidential-vm-overview>

### Q30 · Answer: D

**Why (P10, P7):** The dataset location fixes where data is stored and processed, and the organization policy enforces it for every new resource.

- **A** — wrong: data is stored in the US.
- **B** — wrong: not enforced.
- **C** — wrong: key location doesn't control where data is stored.
- **D** — correct: EU location plus a preventive guardrail.

**Reference:** <https://cloud.google.com/resource-manager/docs/organization-policy/defining-locations>

### Q31 · Answer: C

**Why (P6):** Just-in-time, approved, time-bound elevation with audit removes standing privilege. Privileged Access Manager provides exactly that.

- **A** — wrong: standing privilege.
- **B** — wrong: shared and unaudited credentials.
- **C** — correct: approval workflow plus automatic expiry.
- **D** — wrong: long-lived keys for humans.

**Reference:** <https://cloud.google.com/iam/docs/pam-overview>

### Q32 · Answer: B

**Why (P12, P2):** Fast delivery stays safe with canary releases, automated verification, approvals and rollback.

- **A** — wrong: an all-at-once rollout risks availability.
- **B** — correct: fast and safe progressive delivery.
- **C** — wrong: slow, and large batches are risky.
- **D** — wrong: inconsistent, with no controls.

**Reference:** <https://cloud.google.com/deploy/docs/overview>

### Q33 · Answer: D

**Why (P14, P13):** Load balancers need health checks to pass. Missing firewall rules for Google's health-check and proxy ranges is a classic cause of 502s while direct access still works.

- **A** — wrong: cache size doesn't produce intermittent 502s on dynamic routes.
- **B** — wrong: possible under load, but the symptom points at health checks first.
- **C** — wrong: the whole project would be affected.
- **D** — correct: the most common root cause for this pattern.

**Reference:** <https://cloud.google.com/load-balancing/docs/load-balancing-overview>

### Q34 · Answer: A, C

**Why (P2, P12):** Only execution proves recoverability. Failover drills validate RTO, and restore tests validate backups and RPO.

- **A** — correct: measured failover drills.
- **B** — wrong: a document review isn't a test.
- **C** — correct: proves backups are usable.
- **D** — wrong: service HA doesn't protect against regional disasters, corruption or operator error.
- **E** — wrong: architecture drifts after go-live.

**Reference:** <https://cloud.google.com/architecture/dr-scenarios-planning-guide>

### Q35 · Answer: A

**Why (P15):** Phased rollout, transparent communication, training and feedback loops are the core of effective change management.

- **A** — correct: people-aware and incremental.
- **B** — wrong: a shock change that undermines trust and adoption.
- **C** — wrong: silence fuels resistance.
- **D** — wrong: inconsistent adoption.

**Reference:** <https://cloud.google.com/architecture/framework>

### Q36 · Answer: C

**Why (P9):** Spend-based commitments discount steady usage across managed services without tying you to machine types.

- **A** — wrong: Spot doesn't apply to these managed services, and it's unsuitable for steady serving.
- **B** — wrong: resource-based commitments for specific machine types don't cover Cloud SQL, Autopilot or Cloud Run, and the team wanted to avoid managing machine types.
- **C** — correct: matches the steady, multi-service usage.
- **D** — wrong: forgoes significant savings on predictable usage.

**Reference:** <https://cloud.google.com/docs/cuds>

### Q37 · Answer: B

**Why (P5, P15):** Non-differentiating capabilities should be bought. Scarce developers should work on differentiators.

- **A** — wrong: builds a commodity system.
- **B** — correct: buy, then integrate.
- **C** — wrong: keeps legacy debt.
- **D** — wrong: no decision is still a decision, and here it delays value.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

### Q38 · Answer: D

**Why (P12, P7):** Encoding the standard project setup in an automated, reviewed module guarantees consistency on every new project.

- **A** — wrong: manual, and steps get missed.
- **B** — wrong: non-compliant by default.
- **C** — wrong: detective and slow.
- **D** — correct: automated, consistent provisioning.

**Reference:** <https://cloud.google.com/architecture/security-foundations>

### Q39 · Answer: A

**Why (P8, P6):** API management policies throttle abusive clients at the edge, before the back end is overwhelmed.

- **A** — correct: rate smoothing, quotas and abuse detection.
- **B** — wrong: weakens security and worsens abuse.
- **C** — wrong: expensive, and abuse can scale too.
- **D** — wrong: doesn't address abuse.

**Reference:** <https://cloud.google.com/apigee/docs/api-platform/get-started/what-apigee>

### Q40 · Answer: C

**Why (P16, P13):** Generative quality needs an evaluation set, automated scoring and schema checks before launch, plus monitored acceptance after launch.

- **A** — wrong: customers find the errors.
- **B** — wrong: tests availability, not quality.
- **C** — correct: systematic evaluation and regression detection.
- **D** — wrong: anecdotal, and doesn't scale.

**Reference:** <https://cloud.google.com/vertex-ai/generative-ai/docs/models/evaluation-overview>

### Q41 · Answer: B

**Why (P12):** The Bigtable emulator provides a local, isolated Bigtable API for tests.

- **A** — wrong: shared and costly, and tests interfere with each other.
- **B** — correct: a local emulator plus an environment variable.
- **C** — wrong: a different data model and API.
- **D** — wrong: a different service.

**Reference:** <https://cloud.google.com/bigtable/docs/emulator>

### Q42 · Answer: D

**Why (P6, P12):** Explicit, named configurations, plus least-privilege defaults for production, prevent accidental cross-environment commands.

- **A** — wrong: easy to forget.
- **B** — wrong: relies on memory.
- **C** — wrong: over-privileged, which makes mistakes worse.
- **D** — correct: explicit context plus least privilege.

**Reference:** <https://cloud.google.com/sdk/docs/configurations>

### Q43 · Answer: A

**Why (P12, P2):** Smaller, separated state files limit each plan's blast radius. Shared modules keep the code DRY.

- **A** — correct: per-environment, per-component states and modules.
- **B** — wrong: keeps the oversized blast radius.
- **C** — wrong: local state with no locking.
- **D** — wrong: abandons IaC for critical infrastructure.

**Reference:** <https://cloud.google.com/docs/terraform/best-practices/general-style-structure>

### Q44 · Answer: C

**Why (P8):** Versioning keeps existing clients working while new clients adopt the change, and deprecation is managed with data.

- **A** — wrong: breaks clients without warning.
- **B** — wrong: silent breakage.
- **C** — correct: versioned, communicated evolution.
- **D** — wrong: an outage for everyone.

**Reference:** <https://cloud.google.com/apis/design>

### Q45 · Answer: B

**Why (P13):** Log-based metrics turn log patterns into time series, which alerting policies can evaluate against a rate threshold.

- **A** — wrong: checks reachability, not specific errors.
- **B** — correct: counts matching entries and alerts on the rate.
- **C** — wrong: network metadata only.
- **D** — wrong: daily batches are too slow for alerting.

**Reference:** <https://cloud.google.com/logging/docs/logs-based-metrics>

### Q46 · Answer: D

**Why (P12):** Feature flags separate deploying code from releasing features, and allow instant runtime kill switches.

- **A** — wrong: long-lived branches cause painful merges and big-bang releases.
- **B** — wrong: heavy per launch, and still couples deploy and release.
- **C** — wrong: doesn't give runtime control.
- **D** — correct: runtime control by segment.

**Reference:** <https://cloud.google.com/architecture/application-deployment-and-testing-strategies>

### Q47 · Answer: A

**Why (P13):** The error-budget policy shifts priorities to reliability when the budget is exhausted, which aligns incentives.

- **A** — correct: freeze risky changes and invest in reliability.
- **B** — wrong: ignores the budget, so more incidents follow.
- **C** — wrong: a higher target makes the budget *smaller*.
- **D** — wrong: hides the problem.

**Reference:** <https://sre.google/workbook/error-budget-policy/>

### Q48 · Answer: B, E

**Why (P2, P13):** Realistic load and controlled failure injection, measured against SLOs, provide empirical evidence of reliability.

- **A** — wrong: SLAs don't validate your architecture.
- **B** — correct: proves capacity and scaling at above-peak load.
- **C** — wrong: unrealistic data gives false confidence.
- **D** — wrong: removes elasticity at the riskiest moment.
- **E** — correct: proves failure tolerance.

**Reference:** <https://cloud.google.com/architecture/distributed-load-testing-using-gke>

### Q49 · Answer: C

**Why (P13):** Uptime checks probe from multiple global locations, which measures the outside-in user perspective.

- **A** — wrong: an internal cause metric, which misses DNS, network and load-balancer problems.
- **B** — wrong: no availability signal.
- **C** — correct: global, user-perspective probing with alerting.
- **D** — wrong: far too infrequent.

**Reference:** <https://cloud.google.com/monitoring/uptime-checks>

### Q50 · Answer: B

**Why (P13):** Personalized Service Health surfaces Google Cloud incidents that affect your projects, and can alert you, which cuts time spent debugging the wrong layer.

- **A** — wrong: too infrequent.
- **B** — correct: targeted, proactive incident awareness.
- **C** — wrong: blinds you during incidents.
- **D** — wrong: slow, and unnecessary when the incident is already published.

**Reference:** <https://cloud.google.com/service-health/docs/overview>
