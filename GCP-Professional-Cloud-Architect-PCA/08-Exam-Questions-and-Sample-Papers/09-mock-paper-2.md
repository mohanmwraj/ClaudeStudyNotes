# Mock Paper 2 · 50 Questions · 120 Minutes

**Instructions:**

* Set a timer for **120 minutes**, and answer all 50 questions without notes.
* Write your answers down first. For multiple-select questions, select exactly the number requested; there's no partial credit.
* Flag questions you're unsure about and return to them. Never leave one blank.
* When you finish, mark your answers with [09-mock-paper-2-answers.md](09-mock-paper-2-answers.md), and read the explanation for every question you missed **or guessed**.

**Case studies in this paper:** Altostrat Media and KnightMotives Automotive. Case-study questions start with **Case study: …**.

**Composition:** Section 1: 13 · Section 2: 9 · Section 3: 9 · Section 4: 7 · Section 5: 6 · Section 6: 6. There are 12 case-study questions (24%) and 6 multiple-select questions.

**Scoring guide:**

* **40/50 or better:** you're ready.
* **36–39:** review your weak domains and retake.
* **Below 36:** study more.

---

### Q1 · Domain 1 · Task 1.1 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives is rebuilding its unreliable online build-to-order system, which has strained relationships with dealers. The steering committee asks how success will be measured.

Which success measures should you propose?

- **A.** The number of microservices in the new system.
- **B.** The number of lines of code migrated from the old system.
- **C.** Business and reliability KPIs agreed with dealers and the business: order accuracy, average days a vehicle spends on the lot, dealer satisfaction scores, and an availability and latency SLO for the ordering service, all measured against today's baseline.
- **D.** The cloud spend of the new system only.

### Q2 · Domain 1 · Task 1.2 · Single answer

**Case study: Altostrat Media.** Altostrat's executives say reliability is a top priority. The content delivery platform runs on GKE in a single zonal cluster, and a zone incident last quarter caused a two-hour outage.

What should you recommend first?

- **A.** Move to regional GKE clusters with workloads spread across zones (multiple replicas, topology spread constraints and PodDisruptionBudgets), and define SLOs for content delivery.
- **B.** Increase the node size in the existing zonal cluster.
- **C.** Take daily snapshots of the cluster's nodes.
- **D.** Move the platform to a single large Compute Engine VM.

### Q3 · Domain 1 · Task 1.3 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives must run tens of thousands of containerized driving-simulation jobs each week for autonomous-vehicle testing. The jobs need GPUs, can be retried and checkpoint their progress, and the budget is limited.

What platform should you recommend?

- **A.** Cloud Run functions with long timeouts.
- **B.** A fixed fleet of on-demand GPU VMs that runs around the clock.
- **C.** App Engine flexible environment.
- **D.** GKE with GPU Spot node pools and job queueing (for example, Kueue), scaling to zero when no jobs are waiting.

### Q4 · Domain 1 · Task 1.3 · Single answer

A B2B SaaS company has a relational, multi-tenant schema. Write volume in its single region is growing beyond what one database primary can handle. It needs ACID transactions and strong consistency, and it wants to avoid application-level sharding.

Which database should you recommend?

- **A.** Cloud SQL for PostgreSQL with additional read replicas.
- **B.** Spanner, using a regional instance configuration.
- **C.** Bigtable, with tenants separated by row-key prefix.
- **D.** Memorystore for Valkey in cluster mode.

### Q5 · Domain 1 · Task 1.3 · Select TWO

**Case study: Altostrat Media.** Altostrat wants to extract rich metadata from its media assets and let users discover content by describing what they want in natural language. Which two components should you recommend? (Select TWO.)

- **A.** Train a custom convolutional neural network from scratch for every type of media.
- **B.** Store all metadata only in Memorystore.
- **C.** Use Gemini multimodal models on Agent Platform to extract metadata (topics, people, places, summaries) from audio and video into a defined schema, stored in BigQuery.
- **D.** Hire contractors to tag every asset manually.
- **E.** Index the metadata and transcripts in Agent Search, to provide natural-language content discovery.

### Q6 · Domain 1 · Task 1.4 · Single answer

During a migration assessment, a team finds an internal reporting application that has eight active users and is scheduled to be decommissioned in nine months, when its function moves into a SaaS product.

What should the migration plan do with it?

- **A.** Refactor it into microservices on GKE first.
- **B.** Rehost it to Compute Engine in the first wave.
- **C.** Retain it where it is until decommissioning (or retire it early if the SaaS product is ready), rather than spending migration effort on it.
- **D.** Rebuild it as a serverless application.

### Q7 · Domain 1 · Task 1.4 · Single answer

A company must move 300 Amazon EC2 instances to Compute Engine. It wants continuous replication, the ability to test migrated VMs before cutover, wave-based cutovers, and a rollback option.

Which tool should you use?

- **A.** Migrate to Virtual Machines.
- **B.** Storage Transfer Service.
- **C.** Database Migration Service.
- **D.** Transfer Appliance.

### Q8 · Domain 1 · Task 1.1 · Single answer

An online store's checkout calls an external payment provider. When the provider has an outage, the store can't accept any orders. The business wants to keep accepting orders during provider outages and complete payment later, within its risk policy.

Which design addresses this business-continuity requirement?

- **A.** Retry the payment call synchronously in a loop until it succeeds.
- **B.** Show an error page until the provider recovers.
- **C.** Move to a larger instance type for the checkout service.
- **D.** Accept orders into a durable queue (Pub/Sub) with a "payment pending" state, retry payment authorization asynchronously with backoff, and notify customers of the outcome. This is graceful degradation.

### Q9 · Domain 1 · Task 1.2 · Select TWO

A Spanner table uses an auto-incrementing integer as its primary key. Write throughput has plateaued, and monitoring shows that one split receives most writes.

Which two changes address the hot-spotting? (Select TWO.)

- **A.** Add a secondary index on the auto-incrementing key.
- **B.** Use a UUID version 4 value as the primary key.
- **C.** Add more Spanner nodes, without changing the key.
- **D.** Switch to a timestamp-based primary key.
- **E.** Use a bit-reversed sequence for the primary key values.

### Q10 · Domain 1 · Task 1.3 · Single answer

A team publishes application events to Pub/Sub and needs them stored in a BigQuery table for analysis. No transformation is required, and the team wants the least code and infrastructure possible.

What should you recommend?

- **A.** A Dataflow streaming pipeline that reads from Pub/Sub and writes to BigQuery.
- **B.** A Cloud Run service that pulls messages and calls the BigQuery API.
- **C.** A Pub/Sub BigQuery subscription that writes messages directly to the table.
- **D.** A nightly batch job that exports messages to CSV and loads them.

### Q11 · Domain 1 · Task 1.5 · Single answer

A company plans to launch its connected-vehicle services country by country over the next five years, as local regulations permit. Each new country may impose its own data-residency rules.

Which design approach best supports this future expansion?

- **A.** Define the platform as region-agnostic infrastructure-as-code modules, with data stores and processing deployable per region, and residency enforced by folder-level organization policies, so adding a country means deploying a new regional instance of the platform.
- **B.** Build everything in a single US region, and replicate data to new countries later.
- **C.** Hard-code region names throughout the application code.
- **D.** Wait until each country's regulations are final before designing anything.

### Q12 · Domain 1 · Task 1.1 · Single answer

A global application uses a Spanner multi-region configuration. Most read requests are for product details that can tolerate being up to 15 seconds stale, but they currently suffer cross-region latency.

What should you change?

- **A.** Move the data to Cloud SQL with cross-region replicas.
- **B.** Add more Spanner nodes in the leader region.
- **C.** Cache all reads in an on-premises CDN.
- **D.** Use Spanner stale reads (bounded or exact staleness) for these queries, so they can be served by the nearest replica without contacting the leader.

### Q13 · Domain 1 · Task 1.3 · Single answer

An AI research team trains models across hundreds of GPUs and needs a POSIX file system for training data and checkpoints, with very high aggregate throughput and low latency.

Which storage option should you recommend?

- **A.** Filestore Basic HDD.
- **B.** Managed Lustre.
- **C.** Cloud SQL.
- **D.** Persistent Disk Standard attached to one VM and shared over NFS.

### Q14 · Domain 2 · Task 2.1 · Single answer

**Case study: Altostrat Media.** Altostrat's on-premises ingestion facility will send a sustained 20 Gbps of media to Google Cloud. The business needs a 99.9% SLA for this connectivity, and Altostrat has a presence in a supported colocation facility.

Which configuration should you recommend?

- **A.** A single 100 Gbps Dedicated Interconnect connection.
- **B.** Four HA VPN tunnels over the internet.
- **C.** Two Dedicated Interconnect connections in the same metro, in different edge availability domains, with Cloud Router BGP sessions on each, and HA VPN as an additional backup.
- **D.** Direct Peering with Google at the colocation facility.

### Q15 · Domain 2 · Task 2.1 · Single answer

**Case study: KnightMotives Automotive.** Some KnightMotives applications will remain on another major cloud provider for several years. They must exchange large data volumes privately and reliably with KnightMotives' new data platform on Google Cloud.

What should you recommend?

- **A.** Cross-Cloud Interconnect between Google Cloud and the other cloud provider, in a redundant configuration.
- **B.** Public internet transfers with TLS.
- **C.** Direct Peering with the other cloud provider.
- **D.** Shipping weekly Transfer Appliances between the clouds.

### Q16 · Domain 2 · Task 2.2 · Single answer

Operations wants every production VM's disks backed up daily, with backups retained for 14 days, stored in a multi-region location, and with no scripts to maintain.

What should you configure?

- **A.** A cron job on each VM that runs `gcloud compute disks snapshot`.
- **B.** Manual snapshots taken by the on-call engineer each morning.
- **C.** Local SSD copies of every disk.
- **D.** A snapshot schedule (resource policy) with daily frequency, 14-day retention and a multi-regional storage location, attached to the disks.

### Q17 · Domain 2 · Task 2.3 · Single answer

**Case study: Altostrat Media.** Altostrat uses Cloud Run functions for event-driven video transcoding. Long documentaries now exceed the functions' practical limits, and transcoding volume is spiky.

What should you recommend?

- **A.** Increase the functions' memory, and keep transcoding everything in them.
- **B.** Use the Transcoder API for standard formats (or Cloud Run jobs or GKE with GPUs for custom pipelines), triggered by the existing events.
- **C.** Transcode on editors' workstations.
- **D.** Run one permanent, very large VM for all transcoding.

### Q18 · Domain 2 · Task 2.3 · Single answer

A security vendor's agent must run as a privileged DaemonSet with host-level access on every Kubernetes node. The vendor's workload isn't on GKE Autopilot's allowlist of partner workloads.

Which platform should you choose for clusters that need this agent?

- **A.** Cloud Run.
- **B.** GKE Autopilot.
- **C.** GKE Standard.
- **D.** Cloud Run functions.

### Q19 · Domain 2 · Task 2.4 · Select TWO

A team self-hosts an open-source LLM on GKE GPU nodes. Traffic is bursty, GPU costs are high, and tail latency suffers when some replicas are overloaded while others are idle. Which two actions should you take? (Select TWO.)

- **A.** Use GKE Inference Gateway for model-aware routing based on server load and queue state.
- **B.** Keep the maximum number of GPU nodes running at all times.
- **C.** Autoscale model-server replicas on queue depth or other inference metrics, and let the GPU node pool scale with them.
- **D.** Move the large model to CPU-only nodes.
- **E.** Disable autoscaling, to keep latency predictable.

### Q20 · Domain 2 · Task 2.5 · Single answer

A podcast network wants accurate, timestamped transcripts of episodes in more than 20 languages, with minimal development effort.

Which service should you use?

- **A.** The Cloud Vision API.
- **B.** The Translation API alone.
- **C.** Text-to-Speech.
- **D.** Speech-to-Text with Chirp models.

### Q21 · Domain 2 · Task 2.5 · Single answer

**Case study: KnightMotives Automotive.** KnightMotives wants better tools for service technicians. Technicians should get answers to repair questions drawn from thousands of PDF service manuals and technical bulletins, with citations so they can verify the procedure.

What should you build?

- **A.** A grounded assistant using Agent Search over the manuals and bulletins, generating answers with Gemini and citing the source passages.
- **B.** A model fine-tuned on the manuals, with no retrieval.
- **C.** A keyword search over file names.
- **D.** A chatbot with no access to the manuals.

### Q22 · Domain 2 · Task 2.2 · Single answer

An application stores user session documents in Firestore. Sessions should be deleted automatically 24 hours after they expire, with no cleanup jobs.

What should you configure?

- **A.** A Cloud Scheduler job that runs a deletion script every hour.
- **B.** A Firestore TTL policy on the session collection's expiration timestamp field.
- **C.** Object Lifecycle Management on the Firestore database.
- **D.** BigQuery table expiration.

### Q23 · Domain 3 · Task 3.1 · Single answer

**Case study: KnightMotives Automotive.** Because of past data breaches, KnightMotives' new Google Cloud organization must start with strong preventive guardrails before workloads arrive.

Which set of initial controls should you recommend?

- **A.** Grant Owner to the cloud team, and add controls once workloads are running.
- **B.** Rely on each project team to configure its own security.
- **C.** Organization policies that disable service account key creation, restrict sharing to the company's domain, block external IPs on VMs and enforce resource locations; group-based least-privilege IAM; and Security Command Center enabled organization-wide.
- **D.** A single shared administrator account for all engineers.

### Q24 · Domain 3 · Task 3.1 · Single answer

**Case study: Altostrat Media.** Altostrat's workforce authenticates through a combination of Google Identity and several third-party identity providers, used by different subsidiaries. Altostrat wants all of these users to access Google Cloud with their existing identities, without creating duplicate accounts.

What should you configure?

- **A.** Create Cloud Identity accounts for everyone, and ask them to remember a second password.
- **B.** Workforce Identity Federation, with workforce pools and providers for each third-party IdP, alongside the existing Google identities.
- **C.** Managed Service for Microsoft Active Directory for each subsidiary.
- **D.** One shared service account per subsidiary.

### Q25 · Domain 3 · Task 3.1 · Single answer

A company's policy requires customer-managed encryption keys for every supported resource. Hundreds of teams create resources, and the security team can't create and assign keys by hand for each one.

What should you implement?

- **A.** Ask each team to create its own keys in its own projects, with no standards.
- **B.** Customer-supplied encryption keys for all services.
- **C.** Rely on Google default encryption, and document an exception.
- **D.** Cloud KMS Autokey, so CMEK keys are created and assigned automatically when resources are created, combined with an organization policy that restricts non-CMEK services.

### Q26 · Domain 3 · Task 3.1 · Select TWO

An automaker's autonomous-driving models are valuable intellectual property, and they're served for internal applications from Agent Platform endpoints. Which two measures best protect the deployed models? (Select TWO.)

- **A.** Expose the endpoints publicly, protected only by an API key.
- **B.** Serve the models from private endpoints reachable through Private Service Connect.
- **C.** Store model weights in a public Cloud Storage bucket for easy distribution.
- **D.** Place Agent Platform, Cloud Storage and BigQuery for the ML projects inside a VPC Service Controls perimeter.
- **E.** Use a single service account with the Owner role for every pipeline and endpoint.

### Q27 · Domain 3 · Task 3.1 · Single answer

Developers pull open-source packages directly from public registries during builds. Security wants control over which upstream packages are used, the ability to block compromised versions quickly, and access to curated, vulnerability-scanned packages.

What should you implement?

- **A.** Artifact Registry remote repositories as the only allowed source for builds, combined with Assured Open Source Software for curated packages.
- **B.** Let developers keep pulling from public registries, and scan production quarterly.
- **C.** Copy packages manually into a shared drive.
- **D.** Block all open-source software.

### Q28 · Domain 3 · Task 3.2 · Single answer

**Case study: KnightMotives Automotive.** EU drivers can ask KnightMotives to erase their personal data. That data is spread across operational databases, BigQuery analytics tables, Cloud Storage files and backups.

How should KnightMotives design for erasure requests?

- **A.** Delete the driver's row from the main customer database only.
- **B.** Maintain a data inventory of where personal data lives (using Sensitive Data Protection discovery and Knowledge Catalog), implement automated deletion workflows across systems, pseudonymize analytics data so it isn't directly linked to drivers, and apply retention limits so backups age out within the allowed timeframe.
- **C.** Ignore erasure requests for analytics data.
- **D.** Make a copy of all data before deleting, just in case.

### Q29 · Domain 3 · Task 3.1 · Single answer

The CISO wants continuous, organization-wide detection of misconfigurations, such as public buckets, open firewall ports and disabled logging, with findings prioritized by risk.

What should you enable?

- **A.** VPC Flow Logs in every subnet.
- **B.** A quarterly manual configuration review.
- **C.** Security Command Center with Security Health Analytics (and attack path simulation in higher tiers).
- **D.** Cloud Trace.

### Q30 · Domain 3 · Task 3.2 · Single answer

A large customer's procurement team asks for Google Cloud's SOC 2 Type II report and ISO 27001 certificate as part of a vendor-risk review of a company's SaaS product, which runs on Google Cloud.

Where should the company obtain Google's reports?

- **A.** Ask a Google engineer to email them informally.
- **B.** Claim that Google's reports make the SaaS product itself SOC 2 compliant.
- **C.** Search third-party websites for copies.
- **D.** Compliance Reports Manager, which provides Google Cloud's audit reports and certificates. The company's own SOC 2 must come from its own audit.

### Q31 · Domain 3 · Task 3.1 · Single answer

An application on Compute Engine needs to publish messages to one Pub/Sub topic. Today it runs as the Compute Engine default service account, which has the Editor role.

What should you do?

- **A.** Create a dedicated service account with only the Pub/Sub Publisher role on that topic, and attach it to the VM.
- **B.** Keep the default service account, because Editor includes Pub/Sub permissions.
- **C.** Create a key for the default service account and store it on the VM's disk.
- **D.** Grant the VM's users the Owner role.

### Q32 · Domain 4 · Task 4.1 · Single answer

A media company deploys to GKE clusters both on-premises and in Google Cloud. Failed deployments often come from configuration drift between clusters and untested promotion steps.

What should you recommend?

- **A.** Deploy to each cluster manually with `kubectl apply`.
- **B.** Cloud Deploy pipelines with automated verification at each stage, plus Config Sync to keep cluster configuration consistent with Git and to detect drift across the fleet.
- **C.** A separate deployment script per cluster, maintained by each operator.
- **D.** Freeze all deployments to on-premises clusters.

### Q33 · Domain 4 · Task 4.1 · Single answer

A Pub/Sub subscription's backlog keeps growing. Subscriber logs show the same few messages failing repeatedly with parsing errors and being redelivered endlessly, which slows processing of everything else.

What should you do?

- **A.** Increase the acknowledgment deadline to 10 minutes.
- **B.** Delete the subscription and create a new one.
- **C.** Configure a dead-letter topic with a maximum number of delivery attempts, fix the parsing bug, and make the consumer idempotent so messages can be reprocessed safely from the dead-letter topic.
- **D.** Add more subscriber instances.

### Q34 · Domain 4 · Task 4.1 · Single answer

A development team uses long-lived feature branches merged every few weeks. Merges are painful, and integration bugs appear late.

Which SDLC practice should you recommend?

- **A.** Trunk-based development with small, short-lived branches merged at least daily, continuous integration on every merge, and feature flags for incomplete work.
- **B.** Longer-lived branches, so features are fully finished before merging.
- **C.** Merge only once per quarter, with a dedicated integration team.
- **D.** Remove automated tests, to speed up merges.

### Q35 · Domain 4 · Task 4.2 · Select TWO

A manufacturer's transformation suffers from poor communication between business and technical teams: priorities conflict and projects deliver features nobody uses. Which two practices should you recommend? (Select TWO.)

- **A.** Separate business and technical roadmaps with no shared review.
- **B.** Shared objectives and KPIs that both business and technical teams own.
- **C.** Highly technical status reports sent to executives monthly.
- **D.** A single annual planning meeting, with no further check-ins.
- **E.** Regular joint product and architecture reviews with demos, where business stakeholders see working increments and adjust priorities.

### Q36 · Domain 4 · Task 4.2 · Single answer

Several teams share GKE clusters. Finance wants to show each team the cost of the workloads it runs, by namespace and label.

What should you configure?

- **A.** A separate billing account per pod.
- **B.** GKE cost allocation, which breaks cluster costs down by namespace and label in the Cloud Billing export to BigQuery, with team dashboards on top.
- **C.** Divide the cluster bill equally among all teams.
- **D.** Give each team its own cluster just for billing purposes.

### Q37 · Domain 4 · Task 4.2 · Single answer

**Case study: Altostrat Media.** Altostrat's generative-AI costs for summarizing and tagging new media are growing quickly. Cost management is an executive priority, and most processing doesn't need real-time results.

What should you recommend?

- **A.** Move all inference to the largest available model, for best quality.
- **B.** Process every asset synchronously, as soon as it arrives.
- **C.** Disable summarization.
- **D.** Use Agent Platform batch inference for non-urgent work, choose the smallest model tier that meets quality targets (for example, a Flash model), and use context caching for large repeated prompts.

### Q38 · Domain 4 · Task 4.1 · Single answer

During a regional outage, a company failed over its order system to the DR region. The primary region has now recovered.

What should the team do next?

- **A.** Immediately switch traffic back to the primary region, without checks.
- **B.** Stay in the DR region permanently without updating any documentation.
- **C.** Follow the failback runbook: resynchronize data from the DR region to the primary, validate integrity and capacity, switch traffic back during a low-traffic window, and hold a postmortem to update the DR plan.
- **D.** Delete the DR environment, to save costs.

### Q39 · Domain 5 · Task 5.1 · Single answer

A media company wants to syndicate its content to partner platforms through APIs, charge partners according to usage tiers, and give partners self-service onboarding.

Which product should you recommend?

- **A.** Apigee, with API products, a developer portal and monetization rate plans.
- **B.** Cloud CDN signed URLs only.
- **C.** API Gateway with manual invoicing based on log exports.
- **D.** Public Cloud Storage buckets per partner.

### Q40 · Domain 5 · Task 5.1 · Single answer

A company wants to move 50 stateless Linux web applications from VMs to GKE, to reduce VM management, without rewriting them first.

Which tool should you recommend?

- **A.** Migrate to Virtual Machines.
- **B.** Migrate to Containers.
- **C.** Database Migration Service.
- **D.** BigQuery Migration Service.

### Q41 · Domain 5 · Task 5.2 · Single answer

A platform team wants to deploy Terraform configurations through a Google-managed service that handles execution and state storage and exposes previews and deployments through an API, `gcloud` and the console, with no self-hosted runners.

What should it use?

- **A.** Cloud Deployment Manager.
- **B.** A Compute Engine VM running Terraform from cron.
- **C.** Infrastructure Manager.
- **D.** Cloud Shell, run manually by an engineer.

### Q42 · Domain 5 · Task 5.2 · Single answer

A team's CI pipeline must run integration tests against Spanner for every pull request, quickly and without cost or shared state.

What should they use?

- **A.** The production Spanner instance, with a test database.
- **B.** A single shared Spanner instance for all pull requests.
- **C.** Cloud SQL as a substitute for Spanner.
- **D.** The Spanner emulator, started in the CI job, with `SPANNER_EMULATOR_HOST` set for the client library.

### Q43 · Domain 5 · Task 5.2 · Single answer

A platform team already uses GitOps with Config Sync for Kubernetes. It wants to manage Google Cloud resources such as Cloud SQL instances and Pub/Sub topics declaratively, through the same Kubernetes-based workflow.

What should it use?

- **A.** Config Connector, defining Google Cloud resources as Kubernetes custom resources synced by Config Sync.
- **B.** Cloud Deployment Manager templates.
- **C.** Shell scripts run in a Kubernetes Job.
- **D.** Manual console changes, documented in Git.

### Q44 · Domain 5 · Task 5.1 · Single answer

A carmaker expects ordering traffic to spike tenfold when a popular new model opens for preorders. The rebuilt ordering system has never been tested at that scale.

What should you advise the development team to do before launch?

- **A.** Launch, and scale manually if problems appear.
- **B.** Run unit tests only.
- **C.** Test at normal traffic levels in staging.
- **D.** Run distributed load tests at or above the expected peak against a production-like environment, verify autoscaling, quotas and database capacity, and fix bottlenecks before launch.

### Q45 · Domain 6 · Task 6.2 · Single answer

A team wants to be notified when a new type of exception starts occurring in its production services, with exceptions grouped by root cause and showing when each first appeared.

Which tool should it use?

- **A.** Cloud Profiler.
- **B.** Error Reporting.
- **C.** VPC Flow Logs.
- **D.** Billing reports.

### Q46 · Domain 6 · Task 6.3 · Single answer

A new Cloud Run revision is causing errors for all users. The team needs the fastest possible rollback.

What should it do?

- **A.** Rebuild the previous version's container image from source, and redeploy it.
- **B.** Delete the Cloud Run service, and recreate it.
- **C.** Route 100% of traffic to the previous healthy revision, which is still available.
- **D.** Wait for the new revision to stabilize.

### Q47 · Domain 6 · Task 6.1 · Single answer

Following operational-excellence practices, a team wants on-call engineers to resolve known alert conditions quickly and consistently, and to reduce repetitive manual fixes.

What should it do?

- **A.** Link each alert to a runbook through the alert's documentation field, automate well-understood remediations (for example, Pub/Sub notifications triggering Cloud Run functions), and review runbooks after incidents.
- **B.** Rely on each engineer's personal notes.
- **C.** Remove alerts that recur often.
- **D.** Escalate every alert to management.

### Q48 · Domain 6 · Task 6.6 · Select TWO

Before launching a new customer portal, the security team wants evidence that the application resists common attacks. Which two activities are appropriate? (Select TWO.)

- **A.** Include Google's underlying infrastructure in the penetration test scope.
- **B.** Postpone security testing until after a breach occurs.
- **C.** Commission a penetration test of the company's own Google Cloud resources, within Google Cloud's Acceptable Use Policy (no prior notification to Google is needed).
- **D.** Run Web Security Scanner against the application to find common vulnerabilities such as XSS and outdated libraries.
- **E.** Disable audit logging during the tests.

### Q49 · Domain 6 · Task 6.5 · Single answer

About 15% of a team's CI runs fail because of flaky tests. Developers have started re-running pipelines until they pass, and real failures are occasionally ignored.

What should you recommend?

- **A.** Delete the entire test suite.
- **B.** Allow merges even when tests fail.
- **C.** Add more retries to every test, so they eventually pass.
- **D.** Track test flakiness as a quality metric, quarantine flaky tests from the gating suite while they're fixed with owners and deadlines, and keep the gating suite reliable.

### Q50 · Domain 6 · Task 6.2 · Single answer

A request through a dozen microservices on GKE and Cloud Run is slow, and logs alone can't show where the time goes.

What should the team implement?

- **A.** More verbose logging on every service.
- **B.** Distributed tracing: instrument the services with OpenTelemetry and export traces to Cloud Trace, propagating trace context between services.
- **C.** Larger machine types for all services.
- **D.** Cloud Monitoring uptime checks on each service.
