# Mock Paper 2 · Answers and Explanations

Answers for [09-mock-paper-2.md](09-mock-paper-2.md). Every option is explained. Tally your score by domain. A domain below 70% marks the folder to revisit.

**Quick key:**

1 C · 2 A · 3 D · 4 B · 5 C,E · 6 C · 7 A · 8 D · 9 B,E · 10 C · 11 A · 12 D · 13 B · 14 C · 15 A · 16 D · 17 B · 18 C · 19 A,C · 20 D · 21 A · 22 B · 23 C · 24 B · 25 D · 26 B,D · 27 A · 28 B · 29 C · 30 D · 31 A · 32 B · 33 C · 34 A · 35 B,E · 36 B · 37 D · 38 C · 39 A · 40 B · 41 C · 42 D · 43 A · 44 D · 45 B · 46 C · 47 A · 48 C,D · 49 D · 50 B

---

### Q1 · Answer: C

**Why (P13):** Success measures must reflect the stated pain points (dealer relationships, reliability, vehicles sitting on lots) and be compared with a baseline.

- **A** — wrong: an architecture detail, not an outcome.
- **B** — wrong: an activity measure.
- **C** — correct: business and reliability outcomes, measured against today.
- **D** — wrong: cost alone ignores the reason for the rebuild.

**Reference:** <https://cloud.google.com/architecture/framework>

### Q2 · Answer: A

**Why (P1, P2):** A zonal cluster is one failure domain. A regional cluster with workloads spread across zones removes the single point of failure, and SLOs make reliability measurable.

- **A** — correct: zone redundancy plus measurable objectives.
- **B** — wrong: bigger nodes are still in one zone.
- **C** — wrong: snapshots are backups, not availability.
- **D** — wrong: worse, because it's a single VM.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters>

### Q3 · Answer: D

**Why (P9, P3):** Retryable, checkpointed GPU batch jobs fit Spot capacity. Queueing and scale-to-zero keep costs proportional to the work.

- **A** — wrong: functions aren't suited to long GPU simulations.
- **B** — wrong: pays for idle GPUs around the clock.
- **C** — wrong: not designed for large-scale GPU batch work.
- **D** — correct: discounted, elastic, queued GPU batch.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/spot-vms>

### Q4 · Answer: B

**Why (P4):** Horizontal write scaling with ACID transactions, strong consistency and no application sharding is Spanner's defining capability.

- **A** — wrong: read replicas don't scale writes.
- **B** — correct: scales writes horizontally with relational semantics.
- **C** — wrong: no multi-row ACID transactions or relational schema.
- **D** — wrong: a cache, not a system of record.

**Reference:** <https://cloud.google.com/spanner/docs/instance-configurations>

### Q5 · Answer: C, E

**Why (P16, P5):** A multimodal foundation model extracts structured metadata without custom training, and managed search provides natural-language discovery.

- **A** — wrong: heavy custom training effort.
- **B** — wrong: not durable or analyzable.
- **C** — correct: schema-based multimodal extraction into the warehouse.
- **D** — wrong: doesn't scale to a vast library.
- **E** — correct: managed semantic search over the metadata.

**Reference:** <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>

### Q6 · Answer: C

**Why (P15):** Systems near end of life are retained until decommissioning, or retired early. Migration effort should go where it creates value.

- **A** — wrong: invests in a system that's going away.
- **B** — wrong: wasted migration effort.
- **C** — correct: retain or retire.
- **D** — wrong: rebuilds something that's being replaced.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

### Q7 · Answer: A

**Why (P15):** Migrate to Virtual Machines supports EC2 sources, with continuous replication, test clones, waves and rollback.

- **A** — correct: purpose-built VM migration.
- **B** — wrong: moves objects and files.
- **C** — wrong: moves databases.
- **D** — wrong: offline data shipping.

**Reference:** <https://cloud.google.com/migrate/virtual-machines/docs/5.0/migrate/what-is-migrate-to-vms>

### Q8 · Answer: D

**Why (P8, P2):** Decoupling order intake from payment authorization lets the business continue during a dependency outage. That's graceful degradation.

- **A** — wrong: synchronous retries block checkout and can overload the provider.
- **B** — wrong: loses all orders during the outage.
- **C** — wrong: capacity isn't the problem.
- **D** — correct: durable intake with asynchronous completion.

**Reference:** <https://cloud.google.com/pubsub/docs/overview>

### Q9 · Answer: B, E

**Why (P4):** Monotonically increasing keys send all inserts to the end of the key space, which is a single split. Random (UUIDv4) or bit-reversed keys spread the writes.

- **A** — wrong: an index on a sequential key hot-spots too.
- **B** — correct: random key distribution.
- **C** — wrong: more nodes don't help if all writes hit one split.
- **D** — wrong: timestamps are also monotonic.
- **E** — correct: bit-reversed sequences distribute writes while keeping integer keys.

**Reference:** <https://cloud.google.com/spanner/docs/schema-design>

### Q10 · Answer: C

**Why (P5):** When there's no transformation, a BigQuery subscription delivers messages straight to the table with no pipeline to build or run.

- **A** — wrong: works, but adds a pipeline you don't need.
- **B** — wrong: custom code to maintain.
- **C** — correct: zero-code delivery.
- **D** — wrong: delayed and manual.

**Reference:** <https://cloud.google.com/pubsub/docs/bigquery>

### Q11 · Answer: A

**Why (P12, P10, P7):** Repeatable regional deployments from code, with residency enforced by policy, make each new country an incremental deployment rather than a redesign.

- **A** — correct: designed for evolution and residency.
- **B** — wrong: residency violations, and a later re-architecture.
- **C** — wrong: brittle.
- **D** — wrong: paralysis. Design for flexibility now.

**Reference:** <https://cloud.google.com/resource-manager/docs/organization-policy/defining-locations>

### Q12 · Answer: D

**Why (P4, P1):** Stale reads trade bounded freshness for locality. Nearby replicas serve them without a round trip to the leader.

- **A** — wrong: Cloud SQL replicas don't give global consistency, and migration is a big change.
- **B** — wrong: nodes don't remove cross-region distance.
- **C** — wrong: not a fit for dynamic database reads.
- **D** — correct: lower latency within the staleness tolerance.

**Reference:** <https://cloud.google.com/spanner/docs/reads>

### Q13 · Answer: B

**Why (P4, P16):** Parallel file systems provide the aggregate throughput that large-scale training needs.

- **A** — wrong: low-performance tier.
- **B** — correct: a high-throughput parallel file system.
- **C** — wrong: a relational database.
- **D** — wrong: a single-VM bottleneck.

**Reference:** <https://cloud.google.com/managed-lustre/docs/overview>

### Q14 · Answer: C

**Why (P14, P2):** A 99.9% Interconnect SLA requires two connections in different edge availability domains in the same metro. VPN adds an extra path.

- **A** — wrong: a single connection has no SLA.
- **B** — wrong: VPN tunnels are poorly suited to a sustained 20 Gbps.
- **C** — correct: the documented 99.9% topology.
- **D** — wrong: Direct Peering gives no private VPC access and no SLA.

**Reference:** <https://docs.cloud.google.com/network-connectivity/docs/interconnect/tutorials/dedicated-creating-9999-availability>

### Q15 · Answer: A

**Why (P14):** Cross-Cloud Interconnect provides dedicated, high-bandwidth private links between Google Cloud and other major clouds.

- **A** — correct: private, reliable multicloud connectivity.
- **B** — wrong: neither private nor predictable.
- **C** — wrong: Direct Peering doesn't connect to other cloud providers.
- **D** — wrong: impractical for ongoing exchange.

**Reference:** <https://cloud.google.com/network-connectivity/docs/how-to/choose-product>

### Q16 · Answer: D

**Why (P5, P12):** Snapshot schedules are native, declarative backup policies with retention and location settings.

- **A** — wrong: scripts on every VM.
- **B** — wrong: manual and error-prone.
- **C** — wrong: ephemeral, and not a backup.
- **D** — correct: managed, scheduled, retained snapshots.

**Reference:** <https://cloud.google.com/compute/docs/disks/scheduled-snapshots>

### Q17 · Answer: B

**Why (P5, P3):** Managed transcoding, or batch-oriented compute, fits long, heavy jobs. Functions remain the event glue.

- **A** — wrong: functions still hit duration and resource limits.
- **B** — correct: the right tool for heavy media processing.
- **C** — wrong: doesn't scale, and it's unmanaged.
- **D** — wrong: a single point of failure, idle most of the time.

**Reference:** <https://cloud.google.com/transcoder/docs>

### Q18 · Answer: C

**Why (P5):** You step down from the most managed option only when a hard requirement forces it. Privileged host access needs node-level control, which is GKE Standard.

- **A** — wrong: no privileged host access.
- **B** — wrong: Autopilot restricts privileged workloads unless they're allowlisted.
- **C** — correct: full node control.
- **D** — wrong: no host access.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview>

### Q19 · Answer: A, C

**Why (P9, P13):** Model-aware load balancing evens out replica load, which cuts tail latency. Autoscaling on inference metrics matches GPU spend to demand.

- **A** — correct: routing by server state.
- **B** — wrong: pays for idle GPUs.
- **C** — correct: elastic capacity.
- **D** — wrong: large models on CPU have unacceptable latency.
- **E** — wrong: fixed capacity either wastes money or overloads.

**Reference:** <https://cloud.google.com/ai-hypercomputer/docs/overview>

### Q20 · Answer: D

**Why (P16, P5):** Managed speech recognition with multilingual models provides timestamped transcripts without custom ML work.

- **A** — wrong: analyzes images.
- **B** — wrong: translates text. It doesn't transcribe audio.
- **C** — wrong: does the reverse, text to audio.
- **D** — correct: multilingual transcription.

**Reference:** <https://cloud.google.com/speech-to-text/docs>

### Q21 · Answer: A

**Why (P16):** Retrieval-augmented generation over authoritative manuals gives current, citable answers. Citations let technicians verify procedures.

- **A** — correct: grounded and verifiable.
- **B** — wrong: fine-tuning doesn't reliably inject facts and provides no citations.
- **C** — wrong: file names don't answer repair questions.
- **D** — wrong: ungrounded answers are unsafe for repairs.

**Reference:** <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>

### Q22 · Answer: B

**Why (P5, P10):** Firestore TTL policies delete expired documents automatically, so there are no cleanup jobs.

- **A** — wrong: custom job to maintain.
- **B** — correct: native expiry.
- **C** — wrong: that's a Cloud Storage feature.
- **D** — wrong: a different service.

**Reference:** <https://cloud.google.com/firestore/docs/ttl>

### Q23 · Answer: C

**Why (P7, P6):** Preventive guardrails at the organization level, before workloads arrive, plus detection and least privilege, address breach risk from the start.

- **A** — wrong: broad privilege, with controls added after the fact.
- **B** — wrong: inconsistent security.
- **C** — correct: secure-by-default foundation.
- **D** — wrong: shared credentials, with no accountability.

**Reference:** <https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints>

### Q24 · Answer: B

**Why (P6):** Workforce Identity Federation trusts external IdPs directly, so users keep their existing identities and no duplicates are created.

- **A** — wrong: duplicate accounts and passwords.
- **B** — correct: federation with multiple IdPs.
- **C** — wrong: a directory for workloads, not console federation.
- **D** — wrong: shared credentials, with no user identity.

**Reference:** <https://cloud.google.com/iam/docs/workforce-identity-federation>

### Q25 · Answer: D

**Why (P11, P7):** Autokey automates CMEK provisioning at scale, and the organization policy enforces CMEK usage.

- **A** — wrong: inconsistent, unmanaged keys.
- **B** — wrong: CSEK isn't supported broadly and is heavy to operate.
- **C** — wrong: violates the policy.
- **D** — correct: automated, enforced CMEK.

**Reference:** <https://cloud.google.com/kms/docs/autokey-overview>

### Q26 · Answer: B, D

**Why (P6, P14):** Private serving removes public exposure, and a service perimeter blocks exfiltration of models and data, even with valid credentials.

- **A** — wrong: a public endpoint with a bearer API key.
- **B** — correct: private network access to endpoints.
- **C** — wrong: public weights mean the IP is lost.
- **D** — correct: an exfiltration perimeter.
- **E** — wrong: one over-privileged identity is a large blast radius.

**Reference:** <https://cloud.google.com/vpc-service-controls/docs/overview>

### Q27 · Answer: A

**Why (P12):** Controlling the dependency entry point (remote repositories) and using curated packages reduces supply-chain risk and lets you block versions centrally.

- **A** — correct: a controlled upstream plus curated packages.
- **B** — wrong: uncontrolled, and late detection.
- **C** — wrong: manual and unscalable.
- **D** — wrong: impractical.

**Reference:** <https://cloud.google.com/assured-open-source-software/docs/overview>

### Q28 · Answer: B

**Why (P10, P11):** You can only erase what you can find. An inventory plus automated deletion, pseudonymization and retention limits make erasure feasible across systems.

- **A** — wrong: leaves copies everywhere else.
- **B** — correct: a privacy-by-design erasure capability.
- **C** — wrong: analytics data containing personal data is in scope.
- **D** — wrong: defeats erasure.

**Reference:** <https://cloud.google.com/privacy/gdpr>

### Q29 · Answer: C

**Why (P13, P6):** Security Health Analytics continuously detects misconfigurations across the organization, and higher tiers prioritize findings by attack paths.

- **A** — wrong: network flows, not configuration posture.
- **B** — wrong: too infrequent.
- **C** — correct: continuous, risk-prioritized findings.
- **D** — wrong: latency tracing.

**Reference:** <https://cloud.google.com/security-command-center/docs/security-command-center-overview>

### Q30 · Answer: D

**Why (P13):** Google's audit reports come from Compliance Reports Manager. The company's own compliance requires its own controls and audit (shared responsibility).

- **A** — wrong: not the official channel.
- **B** — wrong: misrepresents compliance.
- **C** — wrong: unofficial and possibly outdated.
- **D** — correct: official reports, with responsibilities stated correctly.

**Reference:** <https://cloud.google.com/security/compliance/compliance-reports-manager>

### Q31 · Answer: A

**Why (P6):** A dedicated identity with exactly the role the workload needs limits the blast radius if the VM is compromised.

- **A** — correct: least privilege.
- **B** — wrong: Editor is vastly over-privileged.
- **C** — wrong: a key on disk is a long-lived, stealable credential.
- **D** — wrong: over-privileged humans.

**Reference:** <https://cloud.google.com/iam/docs/best-practices-service-accounts>

### Q32 · Answer: B

**Why (P12):** Managed promotion with verification catches bad releases. GitOps keeps cluster configuration consistent and reveals drift.

- **A** — wrong: manual and inconsistent.
- **B** — correct: consistent delivery plus drift control.
- **C** — wrong: fragmented scripts.
- **D** — wrong: blocks delivery.

**Reference:** <https://cloud.google.com/deploy/docs/overview>

### Q33 · Answer: C

**Why (P8):** Poison messages need a dead-letter path so they stop blocking the stream. Idempotency makes reprocessing safe.

- **A** — wrong: the messages fail parsing regardless of the deadline.
- **B** — wrong: loses backlog messages, and the bug remains.
- **C** — correct: isolate, fix, reprocess safely.
- **D** — wrong: more consumers retry the same poison messages.

**Reference:** <https://cloud.google.com/pubsub/docs/handling-failures>

### Q34 · Answer: A

**Why (P12):** Small, frequent integration catches conflicts early. Feature flags let incomplete work merge safely.

- **A** — correct: trunk-based development with CI.
- **B** — wrong: makes merge pain worse.
- **C** — wrong: maximizes integration risk.
- **D** — wrong: removes the safety net.

**Reference:** <https://dora.dev/>

### Q35 · Answer: B, E

**Why (P13, P15):** Shared outcomes align priorities, and frequent demos with joint reviews keep delivery tied to business value.

- **A** — wrong: guarantees misalignment.
- **B** — correct: shared ownership of outcomes.
- **C** — wrong: jargon-heavy reports don't communicate.
- **D** — wrong: far too infrequent.
- **E** — correct: continuous feedback.

**Reference:** <https://cloud.google.com/architecture/framework>

### Q36 · Answer: B

**Why (P9):** GKE cost allocation attributes shared-cluster spend to namespaces and labels in the billing export.

- **A** — wrong: impossible and absurd.
- **B** — correct: native allocation, then dashboards.
- **C** — wrong: inaccurate and unfair.
- **D** — wrong: wasteful duplication of clusters.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/how-to/cost-allocations>

### Q37 · Answer: D

**Why (P9, P16):** Batch pricing, right-sized models and caching cut inference cost without dropping the capability.

- **A** — wrong: raises cost.
- **B** — wrong: pays online prices for non-urgent work.
- **C** — wrong: drops a business requirement.
- **D** — correct: cost-optimized generative AI.

**Reference:** <https://docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes>

### Q38 · Answer: C

**Why (P2, P13):** Failback is a planned operation: resynchronize, validate, switch at low risk, and learn from the event.

- **A** — wrong: risks data loss or a second outage.
- **B** — wrong: an undocumented state drifts.
- **C** — correct: a controlled failback plus a postmortem.
- **D** — wrong: removes the DR capability.

**Reference:** <https://cloud.google.com/architecture/dr-scenarios-planning-guide>

### Q39 · Answer: A

**Why (P8):** API monetization, self-service onboarding and products are Apigee's core features.

- **A** — correct: full API business management.
- **B** — wrong: access control for content, not API management.
- **C** — wrong: manual billing, with no portal.
- **D** — wrong: insecure, with no management.

**Reference:** <https://cloud.google.com/apigee/docs/api-platform/get-started/what-apigee>

### Q40 · Answer: B

**Why (P15, P5):** Migrate to Containers extracts applications from VMs into container artifacts for GKE.

- **A** — wrong: moves VMs to VMs.
- **B** — correct: VM-to-container migration.
- **C** — wrong: databases only.
- **D** — wrong: warehouses only.

**Reference:** <https://cloud.google.com/migrate/containers/docs>

### Q41 · Answer: C

**Why (P12, P5):** Infrastructure Manager is Google's managed service for running Terraform, including state, previews and deployments.

- **A** — wrong: reached end of support on 2026-03-31.
- **B** — wrong: a self-managed runner.
- **C** — correct: managed Terraform execution.
- **D** — wrong: manual and ephemeral.

**Reference:** <https://cloud.google.com/infrastructure-manager/docs/overview>

### Q42 · Answer: D

**Why (P12):** The Spanner emulator provides fast, isolated, free test databases in CI.

- **A** — wrong: risks production.
- **B** — wrong: shared state causes interference.
- **C** — wrong: a different SQL dialect and behavior.
- **D** — correct: per-run, isolated emulator.

**Reference:** <https://cloud.google.com/spanner/docs/emulator>

### Q43 · Answer: A

**Why (P12):** Config Connector exposes Google Cloud resources as Kubernetes objects, so the existing GitOps workflow manages them too.

- **A** — correct: one declarative workflow.
- **B** — wrong: an end-of-support product.
- **C** — wrong: imperative and unmanaged.
- **D** — wrong: not infrastructure as code.

**Reference:** <https://cloud.google.com/config-connector/docs/overview>

### Q44 · Answer: D

**Why (P13, P2):** Realistic peak-load testing finds bottlenecks before customers do.

- **A** — wrong: reactive, and risks a failed launch.
- **B** — wrong: doesn't test capacity.
- **C** — wrong: normal load doesn't reveal peak bottlenecks.
- **D** — correct: validates scale ahead of the event.

**Reference:** <https://cloud.google.com/architecture/distributed-load-testing-using-gke>

### Q45 · Answer: B

**Why (P13):** Error Reporting groups exceptions, shows when each first and last occurred, and notifies on new error types.

- **A** — wrong: profiles resource usage.
- **B** — correct: exception grouping and alerting.
- **C** — wrong: network metadata.
- **D** — wrong: cost data.

**Reference:** <https://cloud.google.com/error-reporting/docs>

### Q46 · Answer: C

**Why (P12):** Cloud Run keeps earlier revisions. Shifting traffic back is instant, with no rebuild.

- **A** — wrong: slow, and risks building a different artifact.
- **B** — wrong: causes an outage.
- **C** — correct: instant rollback.
- **D** — wrong: users keep getting errors.

**Reference:** <https://cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration>

### Q47 · Answer: A

**Why (P13, P12):** Runbooks linked from alerts give consistent responses. Automating known fixes removes toil, and reviewing runbooks after incidents keeps them current.

- **A** — correct: documented, automated and continuously improved.
- **B** — wrong: inconsistent and unshareable.
- **C** — wrong: hides real problems.
- **D** — wrong: escalation isn't resolution.

**Reference:** <https://cloud.google.com/architecture/framework/operational-excellence>

### Q48 · Answer: C, D

**Why (P6, P13):** Authorized penetration testing of your own resources, plus automated vulnerability scanning, gives evidence of resistance to common attacks.

- **A** — wrong: Google's infrastructure is out of scope.
- **B** — wrong: reactive.
- **C** — correct: permitted, scoped testing.
- **D** — correct: automated detection of common vulnerabilities.
- **E** — wrong: removes evidence and detection.

**Reference:** <https://support.google.com/cloud/answer/6262505>

### Q49 · Answer: D

**Why (P12, P13):** A reliable gating suite is essential. Measure flakiness, quarantine the flaky tests and fix them with owners.

- **A** — wrong: removes quality control.
- **B** — wrong: lets real defects through.
- **C** — wrong: masks problems and slows CI.
- **D** — correct: restores trust in the pipeline.

**Reference:** <https://dora.dev/>

### Q50 · Answer: B

**Why (P13):** Distributed tracing shows where time is spent across service boundaries. OpenTelemetry is the vendor-neutral instrumentation standard.

- **A** — wrong: logs lack cross-service timing structure.
- **B** — correct: end-to-end latency breakdown.
- **C** — wrong: guesswork.
- **D** — wrong: checks availability, not latency breakdown.

**Reference:** <https://cloud.google.com/trace/docs/overview>
