# Mock Paper 3 · Answers and Explanations

Answers for [10-mock-paper-3.md](10-mock-paper-3.md). Every option is explained. Tally your score by domain. A domain below 70% marks the folder to revisit.

**Quick key:**

1 B · 2 A · 3 C · 4 D · 5 A,D · 6 B · 7 C · 8 A · 9 D · 10 B · 11 C · 12 A · 13 D · 14 B · 15 A · 16 C · 17 D · 18 B · 19 A · 20 D · 21 B,E · 22 C · 23 B · 24 D · 25 A · 26 A,C · 27 C · 28 A · 29 B · 30 D · 31 C · 32 A · 33 C · 34 B · 35 D · 36 B,D · 37 A · 38 C · 39 B · 40 D · 41 A · 42 C · 43 B · 44 D · 45 C,E · 46 A · 47 D · 48 B,D · 49 C · 50 B

---

### Q1 · Answer: B

**Why (P5, P9):** Autopilot shifts node operations, including patching, scaling and upgrades, to Google, which directly cuts administration cost. Managed databases do the same for the data tier.

- **A** — wrong: adds administration.
- **B** — correct: the most managed Kubernetes option.
- **C** — wrong: disabling upgrades increases risk and toil later.
- **D** — wrong: no orchestration, and more manual work.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview>

### Q2 · Answer: A

**Why (P2, P9):** Translate nines into a downtime budget, then pick the cheapest design that meets it. Multi-zone regional services meet 99.9%, and multi-region is a DR concern.

- **A** — correct: the right arithmetic and the right design.
- **B** — wrong: 4 minutes a month is 99.99%.
- **C** — wrong: 7 hours a month is about 99%.
- **D** — wrong: no SLA means zero downtime.

**Reference:** <https://cloud.google.com/architecture/infra-reliability-guide/building-blocks>

### Q3 · Answer: C

**Why (P16, P5):** Managed recommendations trained on your catalog and events give personalization without building and operating ML systems.

- **A** — wrong: custom ML, served from a VM.
- **B** — wrong: not personalized.
- **C** — correct: managed, event-driven personalization.
- **D** — wrong: crude, and not behavior-based.

**Reference:** <https://cloud.google.com/retail/docs>

### Q4 · Answer: D

**Why (P8, P5):** Native events trigger processing within seconds, with no polling and no servers.

- **A** — wrong: polling on a self-managed VM.
- **B** — wrong: too slow.
- **C** — wrong: still polling, and full scans waste effort.
- **D** — correct: event-driven and serverless.

**Reference:** <https://cloud.google.com/storage/docs/pubsub-notifications>

### Q5 · Answer: A, D

**Why (P4, P16):** Analytics belongs in the warehouse, and generative-AI functions in SQL classify unstructured text at scale next to the engagement data.

- **A** — correct: a unified analytical store.
- **B** — wrong: a cache isn't an analytics platform.
- **C** — wrong: doesn't scale, and isn't governed.
- **D** — correct: AI-driven insight directly in BigQuery.
- **E** — wrong: not suited to large-scale analytics.

**Reference:** <https://cloud.google.com/bigquery/docs/generative-ai-overview>

### Q6 · Answer: B

**Why (P15, P5):** Full MongoDB compatibility with minimal change, as a managed service, points to MongoDB Atlas on Google Cloud.

- **A** — wrong: a rewrite.
- **B** — correct: managed MongoDB with migration tooling.
- **C** — wrong: not a database.
- **D** — wrong: self-managed, with no HA.

**Reference:** <https://cloud.google.com/mongodb>

### Q7 · Answer: C

**Why (P14):** Routing can't distinguish overlapping prefixes. Fix the address plan first, and use PSC or NAT only as workarounds for overlaps that can't be avoided.

- **A** — wrong: Cloud Router doesn't resolve overlaps.
- **B** — wrong: peering forbids overlapping ranges.
- **C** — correct: plan non-overlapping ranges.
- **D** — wrong: exposes workloads and doesn't fix private routing.

**Reference:** <https://cloud.google.com/vpc/docs/vpc>

### Q8 · Answer: A

**Why (P8):** Acknowledge fast and process asynchronously. A durable queue absorbs bursts so no order is dropped.

- **A** — correct: buffer, then process idempotently.
- **B** — wrong: a single point of failure, and synchronous processing drops requests in bursts.
- **C** — wrong: capped capacity drops requests.
- **D** — wrong: not a design.

**Reference:** <https://cloud.google.com/pubsub/docs/overview>

### Q9 · Answer: D

**Why (P10):** BigQuery time travel retains earlier table states for up to 7 days by default, so you can restore without separate backups.

- **A** — wrong: time travel makes recovery possible.
- **B** — wrong: BigQuery isn't backed by your Persistent Disks.
- **C** — wrong: not a recovery method.
- **D** — correct: query a point in time and restore it.

**Reference:** <https://cloud.google.com/bigquery/docs/time-travel>

### Q10 · Answer: B

**Why (P5, P9):** Run-to-completion containers without HTTP map to Cloud Run jobs. You pay only while the job runs.

- **A** — wrong: an always-on cluster.
- **B** — correct: serverless batch execution.
- **C** — wrong: functions are request-driven and not for multi-hour jobs.
- **D** — wrong: pays for idle time.

**Reference:** <https://cloud.google.com/run/docs/overview/what-is-cloud-run>

### Q11 · Answer: C

**Why (P8, P15):** Building new capability cloud-first, with storage events plus serverless processing, means the planned migration only moves the upload source. The processing stays the same.

- **A** — wrong: adds to the legacy system that's being migrated.
- **B** — wrong: new on-premises investment.
- **C** — correct: future-proof, migration-friendly design.
- **D** — wrong: delays business value.

**Reference:** <https://cloud.google.com/storage/docs/pubsub-notifications>

### Q12 · Answer: A

**Why (P9):** Pay only when resources are used. Schedules and scale-to-zero platforms remove idle cost, and budgets catch drift.

- **A** — correct: removes idle spend.
- **B** — wrong: commits to paying for idle capacity.
- **C** — wrong: raises cost.
- **D** — wrong: blocks development.

**Reference:** <https://cloud.google.com/billing/docs/how-to/budgets>

### Q13 · Answer: D

**Why (P5, P8):** The Cloud Healthcare API natively ingests HL7v2 and FHIR, publishes change notifications, and streams to BigQuery for analytics.

- **A** — wrong: custom parsing, and unmanaged.
- **B** — wrong: not durable or analyzable.
- **C** — wrong: manual and insecure.
- **D** — correct: standards-native ingestion plus analytics.

**Reference:** <https://cloud.google.com/healthcare-api/docs/introduction>

### Q14 · Answer: B

**Why (P14, P6):** On-premises clients must use the restricted VIP (or a PSC endpoint for the VPC-SC bundle) for private access that's compatible with VPC Service Controls.

- **A** — wrong: not private, and may be blocked by the perimeter.
- **B** — correct: private, perimeter-compatible API access.
- **C** — wrong: nonsensical routing.
- **D** — wrong: public edge, not a private path.

**Reference:** <https://cloud.google.com/vpc/docs/private-google-access>

### Q15 · Answer: A

**Why (P14, P6):** Without public IPs, and with firewall ingress limited to Google's load-balancer and health-check ranges, the load balancer and Cloud Armor are the only way in.

- **A** — correct: enforces the load balancer as the entry point.
- **B** — wrong: public back ends can be reached directly, bypassing Cloud Armor.
- **C** — wrong: fully exposed.
- **D** — wrong: obscurity isn't security.

**Reference:** <https://cloud.google.com/load-balancing/docs/load-balancing-overview>

### Q16 · Answer: C

**Why (P1, P9):** A zonal SSD read cache serves repeated reads close to the compute, which raises throughput and cuts multi-region data-transfer charges, with no change to the bucket.

- **A** — wrong: duplicates data on ephemeral disks, and needs custom synchronization.
- **B** — wrong: adds retrieval fees for hot data.
- **C** — correct: Rapid Cache is built for exactly this.
- **D** — wrong: unrelated.

**Reference:** <https://docs.cloud.google.com/storage/docs/rapid/use-rapid-cache>

### Q17 · Answer: D

**Why (P3, P5):** Application health checks detect hung instances that still look "running", and autohealing replaces them automatically.

- **A** — wrong: doesn't detect or fix hangs.
- **B** — wrong: crude, and still leaves hours of failures.
- **C** — wrong: manual toil.
- **D** — correct: automatic detection and replacement.

**Reference:** <https://cloud.google.com/compute/docs/instance-groups/autohealing-instances-in-migs>

### Q18 · Answer: B

**Why (P12, P7):** Parameterized IaC stamps out identical, isolated environments in minutes, with policy built in.

- **A** — wrong: manual and drift-prone.
- **B** — correct: repeatable environment provisioning.
- **C** — wrong: violates the isolation requirement.
- **D** — wrong: doesn't scale.

**Reference:** <https://cloud.google.com/infrastructure-manager/docs/overview>

### Q19 · Answer: A

**Why (P13, P16):** Model monitoring detects drift before business metrics suffer, and automated retraining closes the loop.

- **A** — correct: detect, alert, retrain.
- **B** — wrong: size doesn't prevent drift.
- **C** — wrong: too slow.
- **D** — wrong: removes the data you need for monitoring.

**Reference:** <https://cloud.google.com/vertex-ai/docs/pipelines/introduction>

### Q20 · Answer: D

**Why (P16):** Personalized, tool-using, grounded assistance needs an agent framework with sessions and memory. That's ADK on Agent Runtime, with Agent Search for grounding.

- **A** — wrong: not conversational.
- **B** — wrong: rigid.
- **C** — wrong: no memory, tools or grounding.
- **D** — correct: a full agent architecture.

**Reference:** <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>

### Q21 · Answer: B, E

**Why (P16, P5):** Choose the prebuilt API that matches each task: Translation for text, and Document AI for structured extraction from documents.

- **A** — wrong: Imagen generates images. It doesn't extract text.
- **B** — correct: managed translation.
- **C** — wrong: Video Intelligence analyzes video. It doesn't translate.
- **D** — wrong: Speech-to-Text transcribes audio, not scans.
- **E** — correct: document field extraction.

**Reference:** <https://cloud.google.com/document-ai/docs/overview>

### Q22 · Answer: C

**Why (P9):** BigQuery automatically discounts unmodified data after 90 days. Physical storage billing can save more for highly compressible data, with no data movement.

- **A** — wrong: loses queryability and adds complexity.
- **B** — wrong: resets the long-term pricing clock.
- **C** — correct: built-in cost levers.
- **D** — wrong: Cloud SQL isn't for 500 TB of analytics.

**Reference:** <https://cloud.google.com/bigquery/pricing>

### Q23 · Answer: B

**Why (P6, P14):** Access levels and ingress rules let known on-premises networks into the perimeter, and the restricted VIP keeps the path private.

- **A** — wrong: weakens protection for PHI.
- **B** — correct: controlled, private, perimeter-aware access.
- **C** — wrong: public exposure doesn't satisfy VPC Service Controls.
- **D** — wrong: absurd.

**Reference:** <https://cloud.google.com/vpc-service-controls/docs/overview>

### Q24 · Answer: D

**Why (P7):** An organization policy prevents public access everywhere, with a narrow, documented exception.

- **A** — wrong: detective, and too late.
- **B** — wrong: not enforcement.
- **C** — wrong: firewalls don't control bucket IAM.
- **D** — correct: a preventive guardrail.

**Reference:** <https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints>

### Q25 · Answer: A

**Why (P12, P6):** Binary Authorization enforces signed provenance at deploy time on every cluster in the fleet.

- **A** — correct: enforcement across environments.
- **B** — wrong: tags are mutable.
- **C** — wrong: detection, not enforcement.
- **D** — wrong: doesn't control what runs.

**Reference:** <https://cloud.google.com/binary-authorization/docs/overview>

### Q26 · Answer: A, C

**Why (P11, P6):** Policy tags with masking rules give column-level protection. Fine-Grained Reader on the tag grants unmasked access to authorized users.

- **A** — correct: masked values for analysts.
- **B** — wrong: grossly over-privileged.
- **C** — correct: unmasked access for HR.
- **D** — wrong: stale copies and extra pipelines.
- **E** — wrong: exposes sensitive data.

**Reference:** <https://cloud.google.com/bigquery/docs/column-data-masking-intro>

### Q27 · Answer: C

**Why (P6):** Workload Identity Federation trusts AWS identities, so EC2 roles exchange their credentials for short-lived Google tokens, with no keys.

- **A** — wrong: still a long-lived key.
- **B** — wrong: insecure and manual.
- **C** — correct: keyless cross-cloud access.
- **D** — wrong: API keys don't authorize Cloud Storage object access.

**Reference:** <https://cloud.google.com/iam/docs/workload-identity-federation>

### Q28 · Answer: A

**Why (P13, P6):** Immutable (locked) retention, central collection, restricted administration and Access Transparency together give audit-grade evidence.

- **A** — correct: tamper-resistant logs, plus visibility into Google access.
- **B** — wrong: project owners can change these settings.
- **C** — wrong: not tamper-evident.
- **D** — wrong: not a control.

**Reference:** <https://cloud.google.com/logging/docs/buckets>

### Q29 · Answer: B

**Why (P6):** Edge rate limiting plus bot detection stops distributed credential stuffing. Static IP blocks can't keep up with rotating addresses.

- **A** — wrong: rotating IP addresses defeat static rules.
- **B** — correct: rate limits plus bot management at the edge.
- **C** — wrong: absorbs the attack instead of stopping it.
- **D** — wrong: obscurity.

**Reference:** <https://cloud.google.com/armor/docs/cloud-armor-overview>

### Q30 · Answer: D

**Why (P10, P11):** Organization-level discovery continuously profiles data stores for sensitive data, which keeps the inventory current.

- **A** — wrong: a one-time survey goes stale and is unreliable.
- **B** — wrong: network data says nothing about content.
- **C** — wrong: lists resources, not their sensitive content.
- **D** — correct: continuous sensitive-data discovery.

**Reference:** <https://cloud.google.com/sensitive-data-protection/docs/sensitive-data-protection-overview>

### Q31 · Answer: C

**Why (P7, P16):** Floor settings inherited down the hierarchy enforce minimum AI protection everywhere. Templates handle stricter per-application needs.

- **A** — wrong: guidance only.
- **B** — wrong: firewalls don't inspect prompts.
- **C** — correct: inherited, enforced minimum protection.
- **D** — wrong: infrequent and manual.

**Reference:** <https://cloud.google.com/security-command-center/docs/model-armor-overview>

### Q32 · Answer: A

**Why (P12, P13):** Workflows codified and deployed the same way in every environment are faster and more reliable, and SLOs show the improvement.

- **A** — correct: automated, consistent and measured.
- **B** — wrong: manual and divergent.
- **C** — wrong: single points of failure.
- **D** — wrong: abandons a business need.

**Reference:** <https://cloud.google.com/architecture/framework/operational-excellence>

### Q33 · Answer: C

**Why (P6, P13):** When IAM is unchanged but access is denied after a perimeter change, VPC Service Controls is the prime suspect. Its logs identify the blocked call, and dry-run validates the fix.

- **A** — wrong: unrelated.
- **B** — wrong: unrelated.
- **C** — correct: diagnose and fix the perimeter rule.
- **D** — wrong: billing problems cause different errors.

**Reference:** <https://cloud.google.com/vpc-service-controls/docs/overview>

### Q34 · Answer: B

**Why (P12):** Ephemeral environments built from the same modules eliminate drift and contention. Every change is tested in isolation.

- **A** — wrong: risky.
- **B** — correct: isolated, consistent testing.
- **C** — wrong: removes quality control.
- **D** — wrong: drift persists.

**Reference:** <https://cloud.google.com/docs/terraform/policy-validation>

### Q35 · Answer: D

**Why (P5, P12):** One platform and toolchain across environments reduces training and operating cost, which is exactly the pain EHR describes.

- **A** — wrong: recreates the problem.
- **B** — wrong: duplicates processes.
- **C** — wrong: the team can't operate what it hasn't learned.
- **D** — correct: standardization plus training.

**Reference:** <https://cloud.google.com/kubernetes-engine/enterprise/config-sync/docs/overview>

### Q36 · Answer: B, D

**Why (P9):** Optimize usage first, then commit. Rightsizing before buying CUDs avoids locking in waste.

- **A** — wrong: commits to over-provisioned sizes.
- **B** — correct: rightsizing first.
- **C** — wrong: Spot is unsuitable for production databases.
- **D** — correct: discounts on the steady baseline.
- **E** — wrong: loses visibility.

**Reference:** <https://cloud.google.com/docs/cuds>

### Q37 · Answer: A

**Why (P10):** Some decisions are one-way doors. Locking a retention policy can't be undone, so validate requirements and test on unlocked policies first.

- **A** — correct: careful handling of an irreversible decision.
- **B** — wrong: locking is irreversible.
- **C** — wrong: an arbitrary, irreversible over-retention.
- **D** — wrong: ignores the compliance need.

**Reference:** <https://cloud.google.com/storage/docs/bucket-lock>

### Q38 · Answer: C

**Why (P9, P2):** An 8-hour RTO fits a pilot-light or backup-based DR pattern. You pay mainly for storage until you need to recover.

- **A** — wrong: hot standby is far more than an 8-hour RTO needs.
- **B** — wrong: slow, and not in a cloud recovery site.
- **C** — correct: cost-effective hybrid DR.
- **D** — wrong: no recovery capability.

**Reference:** <https://cloud.google.com/backup-disaster-recovery/docs/concepts/backup-dr>

### Q39 · Answer: B

**Why (P8, P15):** An API facade gives partners one stable contract while back ends move from on-premises to cloud.

- **A** — wrong: exposes migration details to partners.
- **B** — correct: one consistent API layer across hybrid back ends.
- **C** — wrong: insecure and unmanaged.
- **D** — wrong: delays business value.

**Reference:** <https://cloud.google.com/apigee/docs/hybrid/latest/what-is-hybrid>

### Q40 · Answer: D

**Why (P3, P2):** Serverless scale-out can overwhelm a fixed-size database. Pooling, instance caps and read replicas protect it.

- **A** — wrong: in-memory data isn't durable.
- **B** — wrong: doesn't reduce connections.
- **C** — wrong: removes elasticity.
- **D** — correct: protects the database.

**Reference:** <https://cloud.google.com/sql/docs/mysql/instance-settings>

### Q41 · Answer: A

**Why (P9, P5):** Batch load jobs from Cloud Storage are the efficient path for bulk files. Streaming inserts are for real-time needs, and they cost more.

- **A** — correct: bulk loading.
- **B** — wrong: still the costly path.
- **C** — wrong: an unnecessary hop.
- **D** — wrong: nonsensical.

**Reference:** <https://cloud.google.com/bigquery/docs/batch-loading-data>

### Q42 · Answer: C

**Why (P12):** Admin API calls often return long-running operations. Wait for completion explicitly instead of guessing.

- **A** — wrong: fixed sleeps are fragile.
- **B** — wrong: hammers the API.
- **C** — correct: operation-aware automation.
- **D** — wrong: impossible ordering.

**Reference:** <https://cloud.google.com/sql/docs/mysql/admin-api>

### Q43 · Answer: B

**Why (P12):** Cloud Code with Skaffold automates the edit, build, deploy and debug loop for Kubernetes development.

- **A** — wrong: slow and manual.
- **B** — correct: a fast inner loop in the IDE.
- **C** — wrong: not a development loop.
- **D** — wrong: an end-of-support IaC tool, not a development loop.

**Reference:** <https://cloud.google.com/code/docs>

### Q44 · Answer: D

**Why (P15, P13):** Validate migrated data systematically before the point of no return.

- **A** — wrong: assumes perfection without evidence.
- **B** — wrong: size doesn't prove correctness.
- **C** — wrong: too late, and anecdotal.
- **D** — correct: systematic validation before cutover.

**Reference:** <https://github.com/GoogleCloudPlatform/professional-services-data-validator>

### Q45 · Answer: C, E

**Why (P9, P13):** Cut low-value volume, such as debug logs, health checks and excessive flow-log detail, while keeping the audit logs compliance requires.

- **A** — wrong: Admin Activity logs can't be disabled, and they're required evidence.
- **B** — wrong: the `_Required` bucket can't be deleted.
- **C** — correct: exclusions for noisy logs.
- **D** — wrong: violates compliance for regulated services.
- **E** — correct: tuned flow-log volume.

**Reference:** <https://cloud.google.com/logging/docs/routing/overview>

### Q46 · Answer: A

**Why (P12, P13):** A canary with automated verification limits the blast radius and decides promotion with data.

- **A** — correct: measured progressive delivery.
- **B** — wrong: an all-at-once rollout.
- **C** — wrong: not traffic splitting.
- **D** — wrong: timing isn't a safety mechanism.

**Reference:** <https://cloud.google.com/deploy/docs/deployment-strategies/canary>

### Q47 · Answer: D

**Why (P2, P13):** Controlled fault injection proves resilience behaviors before real incidents test them.

- **A** — wrong: reactive.
- **B** — wrong: causes cascading failures.
- **C** — wrong: doesn't test the failure handling.
- **D** — correct: proactive resilience testing.

**Reference:** <https://cloud.google.com/architecture/framework/reliability>

### Q48 · Answer: B, D

**Why (P16, P13):** Generative quality needs ongoing automated evaluation plus real user signals, fed back into improvements.

- **A** — wrong: uptime says nothing about answer quality.
- **B** — correct: continuous automated evaluation.
- **C** — wrong: unmanaged risk.
- **D** — correct: user-outcome signals.
- **E** — wrong: removes the evidence needed for quality control (instead, retain logs with PII redacted).

**Reference:** <https://cloud.google.com/vertex-ai/generative-ai/docs/models/evaluation-overview>

### Q49 · Answer: C

**Why (P13):** Set priority by business impact, and include complete information to get the fastest response, while continuing your own mitigation.

- **A** — wrong: misprioritized.
- **B** — wrong: no support commitment.
- **C** — correct: P1 with complete details.
- **D** — wrong: delays help.

**Reference:** <https://cloud.google.com/support>

### Q50 · Answer: B

**Why (P13):** Good SLIs are user-centric ratios measured as close to the user as practical: the share of requests faster than a threshold, not averages or resource metrics.

- **A** — wrong: a resource metric.
- **B** — correct: a ratio-based, user-centric latency SLI.
- **C** — wrong: averages hide tail latency, and in-process measurement misses network effects.
- **D** — wrong: a delivery metric.

**Reference:** <https://sre.google/sre-book/service-level-objectives/>
