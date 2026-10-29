# Domain 1 Drill · Designing and Planning a Cloud Solution Architecture (20 questions)

Original exam-style questions for objectives 1.1–1.5 (~25% of the exam). Answer each one before opening its explanation, then read **every** option's explanation. The notes for this domain are in [02-Designing-and-Planning](../02-Designing-and-Planning/), and the principles (P1–P16) are in [02-first-principles-mental-models.md](../00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md).

---

### Q1 · Task 1.1 · Single answer

A freight company receives shipment manifests from 15 partners as CSV files over an on-premises SFTP server. It plans to onboard 40 more partners this year. Each file must be validated and loaded into BigQuery within 10 minutes of arrival. The platform team is small and wants the least operational overhead.

What should you recommend?

- **A.** Keep the SFTP server and add a cron job on a Compute Engine VM that polls the upload folder every hour, validates new files and loads them into BigQuery.
- **B.** Have partners upload to a Cloud Storage landing bucket, isolated per partner with IAM or signed URLs, and use Pub/Sub notifications on object finalize to trigger a Cloud Run service that validates each file and loads it into BigQuery.
- **C.** Build a dedicated REST API on GKE for each partner, and require partners to rewrite their integrations to call it.
- **D.** Ask partners to ship their files monthly on a Transfer Appliance, and bulk-load the data into BigQuery.

<details><summary>Answer</summary>

**Answer: B**

**Why (P8, P5):** File-based integration with event-driven processing meets the 10-minute target, scales per partner, and uses managed, serverless pieces with nothing to patch.

- **A** — wrong: hourly polling misses the 10-minute requirement, and a VM with cron is self-managed toil.
- **B** — correct: native notifications trigger processing within seconds, onboarding a partner is just a new prefix or bucket and an IAM grant, and Cloud Run scales to zero.
- **C** — wrong: a bespoke API per partner multiplies work and forces partner changes, which slows onboarding.
- **D** — wrong: Transfer Appliance is for bulk offline transfers, not near-real-time partner feeds.

**Reference:** <https://cloud.google.com/storage/docs/pubsub-notifications>

</details>

### Q2 · Task 1.1 · Single answer

The board of a retail company asks the architect for a business continuity plan covering its e-commerce platform, warehouse management system and internal reporting tools. Today, nobody has defined how long each system can be down or how much data loss is acceptable.

What should the architect do first?

- **A.** Deploy every system in an active-active configuration across two regions so that no outage is possible.
- **B.** Purchase 3-year committed use discounts in a second region to guarantee DR capacity.
- **C.** Enable daily snapshots on all VMs and document that backups exist.
- **D.** Run a business impact analysis with the process owners to set an RTO and RPO for each system, then choose a DR pattern per tier and schedule regular DR tests.

<details><summary>Answer</summary>

**Answer: D**

**Why (P2, P9):** DR design starts from business tolerance (RTO/RPO per process). Without it you either overspend on systems that don't need it or under-protect critical ones.

- **A** — wrong: it applies the most expensive pattern to everything, including reporting tools that can tolerate hours of downtime.
- **B** — wrong: a financial commitment made before the requirements are known.
- **C** — wrong: backups alone don't define recovery objectives, runbooks or tests.
- **D** — correct: a BIA, then tiered DR patterns, then testing is the documented approach.

**Reference:** <https://cloud.google.com/architecture/dr-scenarios-planning-guide>

</details>

### Q3 · Task 1.1 · Single answer

A manufacturer is planning its cloud move. It runs a homegrown HR and payroll system that's 15 years old, has no competitive value and is expensive to maintain. It also runs a proprietary pricing engine that gives it a market advantage but can't scale for seasonal demand.

Which workload disposition best fits these two systems?

- **A.** Replace the HR system with a SaaS product (buy), and refactor the pricing engine to use managed, autoscaling services (modify).
- **B.** Rehost both systems to Compute Engine unchanged, and revisit them in five years.
- **C.** Rebuild both systems from scratch as microservices on GKE.
- **D.** Retire the HR system with no replacement, and retain the pricing engine on-premises.

<details><summary>Answer</summary>

**Answer: A**

**Why (P15, P5):** Non-differentiating capabilities should be bought. Differentiating ones deserve investment so they can meet their non-functional requirements (here, seasonal scale).

- **A** — correct: buy the commodity system, and modify the strategic one to gain elasticity.
- **B** — wrong: rehosting doesn't fix the pricing engine's scalability problem and keeps the HR maintenance cost.
- **C** — wrong: rebuilding commodity HR is wasted effort.
- **D** — wrong: payroll can't simply be retired, and keeping the pricing engine on-premises ignores its scaling problem.

**Reference:** <https://cloud.google.com/architecture/migration-to-gcp-getting-started>

</details>

### Q4 · Task 1.1 · Select TWO

A company's cloud program has two stated goals: "release customer features faster" and "reduce infrastructure administration costs". The CIO asks which measurements will show whether the program is succeeding.

Which two measurements should you recommend? (Select TWO.)

- **A.** The number of virtual machines migrated each week.
- **B.** Deployment frequency and lead time for changes, compared with the pre-migration baseline.
- **C.** The total number of tickets in the IT service desk.
- **D.** Average CPU utilization across all virtual machines.
- **E.** Operations staff hours and infrastructure cost per business transaction, compared with the pre-migration baseline.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P13, P9):** Success measures must map directly to the business goals. Delivery speed is measured by DORA metrics, and administration cost by operations effort and unit cost against a baseline.

- **A** — wrong: an activity measure. Migrating VMs doesn't prove features ship faster or costs fall.
- **B** — correct: DORA's speed metrics directly measure "release features faster".
- **C** — wrong: ticket counts are noisy and not tied to either goal.
- **D** — wrong: utilization is a technical metric with no direct link to the stated outcomes.
- **E** — correct: operations hours and cost per transaction directly measure administration cost.

**Reference:** <https://dora.dev/>

</details>

### Q5 · Task 1.1 · Single answer

An order service calls a third-party email provider synchronously after each purchase to send a confirmation. When the provider is slow, checkout requests time out and customers abandon their carts. Sending the email a few seconds late is acceptable.

What should you recommend?

- **A.** Increase the order service's HTTP timeout for the email call to 60 seconds.
- **B.** Move the order service to larger machine types so it can hold more concurrent requests.
- **C.** Publish an order-placed event to Pub/Sub and have a separate email worker subscribe to it, processing messages idempotently and sending failures to a dead-letter topic.
- **D.** Collect orders in a table and send all confirmation emails once per hour from a scheduled batch job.

<details><summary>Answer</summary>

**Answer: C**

**Why (P8):** Decoupling with a durable queue isolates checkout from the provider's latency and failures. At-least-once delivery requires idempotent consumers.

- **A** — wrong: a longer timeout makes checkout even slower when the provider degrades.
- **B** — wrong: more capacity doesn't remove the synchronous dependency.
- **C** — correct: asynchronous messaging keeps checkout fast, and retries and dead-lettering handle provider problems.
- **D** — wrong: hourly batches break "a few seconds late is acceptable".

**Reference:** <https://cloud.google.com/pubsub/docs/overview>

</details>

### Q6 · Task 1.2 · Single answer

A customer portal runs on a single Compute Engine VM and uses a Cloud SQL Enterprise edition HA instance. The business now requires 99.99% availability for the serving path, from the load balancer to the database.

Which design change meets the requirement?

- **A.** Move the VM to a larger machine type, and keep the Cloud SQL Enterprise edition HA instance.
- **B.** Run the portal in a regional managed instance group across three zones behind a load balancer, and move the database to Cloud SQL Enterprise Plus edition with HA.
- **C.** Add a second VM in the same zone, and create a Cloud SQL read replica.
- **D.** Keep the single VM, rely on live migration, and take hourly disk snapshots.

<details><summary>Answer</summary>

**Answer: B**

**Why (P2, P1):** Serial components multiply their availability. A single VM (99.9%) or a 99.95% database can't support a 99.99% path. Multi-zone compute and a 99.99% database tier are both required.

- **A** — wrong: a single instance stays at 99.9%, and the database SLA stays at 99.95%.
- **B** — correct: multi-zone instances (99.99%) plus Enterprise Plus HA (99.99%) remove both weak links.
- **C** — wrong: the same zone is still one failure domain, and a read replica isn't automatic HA for writes.
- **D** — wrong: live migration covers host maintenance, not zone failures, and snapshots are backups, not availability.

**Reference:** <https://cloud.google.com/architecture/infra-reliability-guide/building-blocks>

</details>

### Q7 · Task 1.2 · Single answer

A fintech company is building a global payments ledger. Transactions must never be lost (RPO = 0), the service must keep accepting writes automatically if an entire region fails, and the data model is relational with ACID transactions.

Which database should the architect choose?

- **A.** Spanner with a multi-region instance configuration.
- **B.** Cloud SQL for PostgreSQL with a cross-region read replica that's promoted during a disaster.
- **C.** Bigtable with replication across three regions and multi-cluster routing.
- **D.** Cloud SQL HA with hourly exports to a dual-region Cloud Storage bucket.

<details><summary>Answer</summary>

**Answer: A**

**Why (P4, P2):** Only a synchronously replicated, globally consistent relational database gives RPO 0 and automatic regional failover for ACID workloads.

- **A** — correct: Spanner multi-region commits across regions with external consistency and fails over automatically (99.999% SLA).
- **B** — wrong: cross-region replication is asynchronous (RPO > 0), and promotion is a manual or scripted step.
- **C** — wrong: Bigtable has single-row transactions only, and cross-cluster replication is eventually consistent.
- **D** — wrong: hourly exports mean up to an hour of data loss and a slow restore.

**Reference:** <https://cloud.google.com/spanner/docs/instance-configurations>

</details>

### Q8 · Task 1.2 · Single answer

An operations team that's new to Google Cloud spends hours on each incident manually correlating logs, metrics and recent configuration changes across several services. Leadership wants faster root-cause analysis using Google-provided tooling, with minimal setup.

What should you recommend?

- **A.** Export all logs to a self-managed Elasticsearch cluster on Compute Engine and build correlation dashboards.
- **B.** Write custom scripts that download logs from every project after each incident and diff them.
- **C.** Engage an external consulting firm to perform root-cause analysis for every incident.
- **D.** Use Gemini Cloud Assist investigations in the Google Cloud console to analyze the affected resources' logs, metrics and recent changes and propose likely causes, then validate and apply fixes through the normal change process.

<details><summary>Answer</summary>

**Answer: D**

**Why (P13, P5):** Gemini Cloud Assist is the built-in assistant that correlates observability data and changes during troubleshooting. It speeds up diagnosis without new infrastructure, while fixes still go through controlled change.

- **A** — wrong: a heavy self-managed stack that duplicates native capabilities.
- **B** — wrong: manual and slow, which is the problem being solved.
- **C** — wrong: expensive and slow, and builds no internal capability.
- **D** — correct: native, AI-assisted investigation, with humans validating changes.

**Reference:** <https://cloud.google.com/gemini/docs/cloud-assist/overview>

</details>

### Q9 · Task 1.2 · Select TWO

A company runs critical workloads on Compute Engine VMs and GKE. After a competitor suffered a ransomware attack that also deleted its backups, the CISO requires that backups be **immutable** for a defined period, and that they can be restored in a **different region** from production.

Which two actions should you take? (Select TWO.)

- **A.** Protect the VMs with Backup and DR Service, storing backups in a backup vault in another region with an enforced minimum retention.
- **B.** Have each application team create disk snapshots in its own production project, and grant them permission to delete old snapshots.
- **C.** Rely on Compute Engine live migration to protect the VMs.
- **D.** Configure Backup for GKE backup plans that store backups in a different region, with retention locked so backups can't be deleted early.
- **E.** Increase the number of replicas of each GKE Deployment.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P2, P6):** Ransomware resilience needs backups that compromised production credentials can't delete (immutable retention), stored away from the primary failure domain.

- **A** — correct: backup vaults enforce retention, so backups can't be deleted before it expires, and the vault can sit in another region.
- **B** — wrong: snapshots in the same project are deletable by the same identities, which is exactly what attackers abuse.
- **C** — wrong: live migration handles host maintenance, not data protection.
- **D** — correct: Backup for GKE protects cluster state and volumes, with cross-region storage and locked retention.
- **E** — wrong: replicas improve availability, but ransomware or deletion affects every replica.

**Reference:** <https://cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault>

</details>

### Q10 · Task 1.3 · Single answer

A startup has a containerized, stateless REST API. Traffic is bursty and unpredictable during the day and nearly zero overnight. The two-person team has no Kubernetes experience. The API must reach a Cloud SQL instance that has only a private IP.

Which platform should you recommend?

- **A.** GKE Standard with a regional cluster and the cluster autoscaler.
- **B.** A Compute Engine managed instance group with an autoscaler and a minimum of two instances.
- **C.** Cloud Run, configured with Direct VPC egress to reach the Cloud SQL private IP.
- **D.** App Engine flexible environment with a custom runtime.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5, P9, P3):** A stateless container with spiky, often idle traffic and a tiny team is the textbook fit for a serverless platform that scales to zero. Direct VPC egress solves the private-IP requirement.

- **A** — wrong: Kubernetes operations the team can't support, and nodes keep running overnight.
- **B** — wrong: VMs run all night and need OS management.
- **C** — correct: request-driven scaling to zero, no infrastructure to run, and private connectivity through Direct VPC egress.
- **D** — wrong: App Engine flexible doesn't scale to zero, and Cloud Run is Google's recommended platform for new container workloads.

**Reference:** <https://cloud.google.com/run/docs/configuring/vpc-direct-vpc>

</details>

### Q11 · Task 1.3 · Single answer

A smart-meter company ingests about 300,000 readings per second from 20 million meters. The customer app must show each meter's most recent readings with single-digit millisecond latency. Three years of history, several petabytes, must be retained.

Which storage design should you recommend for serving the readings?

- **A.** Cloud SQL for PostgreSQL with a table indexed on meter ID and timestamp.
- **B.** Bigtable with a row key of meter ID followed by a reversed timestamp.
- **C.** BigQuery as the low-latency store queried directly by the mobile app.
- **D.** Firestore with one document per reading, using the timestamp as the document ID.

<details><summary>Answer</summary>

**Answer: B**

**Why (P4):** Very high write throughput, key-based low-latency reads and petabyte scale point to a wide-column store. Row-key design places each meter's newest readings first and avoids hot-spotting.

- **A** — wrong: a single-primary relational database can't absorb 300,000 writes per second at petabyte scale.
- **B** — correct: Bigtable scales linearly, and `meterId#reversedTs` gives fast "latest N" range scans without a monotonic key prefix.
- **C** — wrong: BigQuery is for analytics, not millisecond point lookups serving an app.
- **D** — wrong: sequential timestamp IDs hot-spot, and Firestore isn't designed for this ingest volume and history size.

**Reference:** <https://cloud.google.com/bigtable/docs/schema-design>

</details>

### Q12 · Task 1.3 · Single answer

A broadcaster stores 3 PB of video in Cloud Storage. Some programs stay popular for years, while others are rarely watched after their first week, and the team can't predict which. They want to reduce storage cost with no ongoing administration, without retrieval-fee surprises.

What should you configure?

- **A.** A lifecycle rule that moves every object to Archive class 30 days after creation.
- **B.** Change the bucket's default storage class to Nearline.
- **C.** Move the library to Persistent Disk volumes attached to a file server VM.
- **D.** Enable Autoclass on the bucket.

<details><summary>Answer</summary>

**Answer: D**

**Why (P9, P10):** When access patterns differ per object and are unpredictable, per-object automatic class management beats age-based rules.

- **A** — wrong: popular programs would land in Archive, incurring retrieval fees and the 365-day minimum.
- **B** — wrong: frequently watched content would incur Nearline retrieval charges.
- **C** — wrong: block storage on VMs costs more per GB and adds administration.
- **D** — correct: Autoclass moves each object based on its own access, without retrieval fees or early-deletion charges for the transitions it makes.

**Reference:** <https://cloud.google.com/storage/docs/autoclass>

</details>

### Q13 · Task 1.3 · Single answer

A company has 40 application projects in one Google Cloud organization. A central network team must own all subnets, firewall rules and hybrid connectivity, while application teams deploy and manage their own VMs and GKE clusters in their own projects.

What network design should you recommend?

- **A.** A Shared VPC in a host project managed by the network team, with application projects attached as service projects and application teams granted Network User on specific subnets.
- **B.** A separate VPC in each project, connected to the others with a full mesh of VPC Network Peering.
- **C.** A separate VPC in each project, connected to the others with HA VPN tunnels.
- **D.** One project containing every application's resources, with folders inside the project for each team.

<details><summary>Answer</summary>

**Answer: A**

**Why (P7, P14):** Shared VPC separates network administration (host project) from workload administration (service projects) inside one organization. That's exactly the governance model described.

- **A** — correct: centralized control of subnets, firewalls and connectivity, with delegated subnet use.
- **B** — wrong: peering meshes don't centralize control, aren't transitive and become unmanageable at 40 VPCs.
- **C** — wrong: VPN between VPCs adds cost and complexity with no governance benefit.
- **D** — wrong: projects can't contain folders, and a single project removes isolation, quota and billing boundaries.

**Reference:** <https://cloud.google.com/vpc/docs/shared-vpc>

</details>

### Q14 · Task 1.3 · Single answer

An insurer receives claim packets from 300 brokers. Each packet contains PDFs in many different layouts plus photos of vehicle damage. The insurer wants a structured JSON record per claim that matches its internal schema, including a short description of the damage visible in the photos. It wants the least development effort, and the schema will change occasionally.

What should you recommend?

- **A.** Collect and label thousands of examples, and train a custom model from scratch with AutoML for each document layout.
- **B.** Run Cloud Vision API OCR on the PDFs, and write regular expressions per broker to extract fields.
- **C.** Send the PDFs and photos to a Gemini model on Agent Platform with a response schema that matches the claim JSON, validate the output, and route low-confidence records to human review.
- **D.** Fine-tune an open-source language model on GKE GPUs to read the documents, and build a separate image model for the photos.

<details><summary>Answer</summary>

**Answer: C**

**Why (P16, P5):** One multimodal foundation model can read varied layouts and describe images. Controlled generation enforces the schema, and changing the schema means changing a prompt or response schema, not retraining.

- **A** — wrong: heavy labeling and training effort, and every schema change means retraining.
- **B** — wrong: per-broker regex across 300 layouts is brittle, and it can't describe damage in photos.
- **C** — correct: the highest abstraction that fits, with schema-conformant output and human review for edge cases.
- **D** — wrong: the most effort and infrastructure, for a task a managed foundation model already handles.

**Reference:** <https://cloud.google.com/vertex-ai/generative-ai/docs/multimodal/control-generated-output>

</details>

### Q15 · Task 1.3 · Single answer

A bank runs 200 Apache Spark jobs on an on-premises Hadoop cluster that's being decommissioned in six months. The data engineers know Spark well, and the jobs must move with minimal code changes. The bank also wants to stop managing long-running clusters where possible.

What should you recommend?

- **A.** Rewrite all jobs as Apache Beam pipelines on Dataflow.
- **B.** Move the data to Cloud Storage and run the jobs on Managed Service for Apache Spark (formerly Dataproc), using serverless batches where possible and ephemeral clusters for the rest.
- **C.** Rewrite all jobs as BigQuery SQL scheduled queries.
- **D.** Install open-source Spark on a self-managed GKE Standard cluster.

<details><summary>Answer</summary>

**Answer: B**

**Why (P15, P5):** With a deadline and existing Spark skills, the least-change managed target wins. Serverless or ephemeral clusters remove long-running cluster management.

- **A** — wrong: a full rewrite of 200 jobs within six months is risky and unnecessary.
- **B** — correct: Spark jobs run largely unchanged, with Cloud Storage replacing HDFS, and serverless mode minimizes operations.
- **C** — wrong: not every Spark job translates to SQL, and a rewrite contradicts "minimal code changes".
- **D** — wrong: self-managing Spark on Kubernetes adds operational burden.

**Reference:** <https://docs.cloud.google.com/managed-spark/docs/release-notes>

</details>

### Q16 · Task 1.3 · Select THREE

A global retailer is redesigning its storefront. Customers on four continents complain about slow page loads. Product catalog pages are read-heavy and mostly cacheable. Checkout must keep working if an entire region fails, and inventory counts must be strongly consistent worldwide to prevent overselling.

Which three design elements should you include? (Select THREE.)

- **A.** A global external Application Load Balancer with backends deployed in several regions.
- **B.** A single-region Cloud SQL primary, with cross-region read replicas accepting inventory writes in each region.
- **C.** Cloud CDN for static assets and cacheable catalog pages.
- **D.** Standard Network Service Tier, to reduce latency for international users.
- **E.** Spanner with a multi-region configuration for inventory and orders.
- **F.** DNS round robin across the regional IP addresses of each region's servers.

<details><summary>Answer</summary>

**Answer: A, C, E**

**Why (P1, P2, P4):** Global anycast load balancing and edge caching fix latency. Multi-region backends plus a globally consistent database provide regional resilience without overselling.

- **A** — correct: one anycast IP routes users to the nearest healthy region and fails over across regions.
- **B** — wrong: read replicas don't accept writes, so this design can't provide consistent multi-region inventory writes.
- **C** — correct: edge caching removes most catalog latency.
- **D** — wrong: Standard Tier routes over the public internet to the region, which increases latency and doesn't support the global load balancer.
- **E** — correct: Spanner gives strongly consistent, multi-region transactional storage with automatic failover.
- **F** — wrong: DNS round robin has no health-aware, latency-aware routing, and failover depends on client caching.

**Reference:** <https://cloud.google.com/load-balancing/docs/choosing-load-balancer>

</details>

### Q17 · Task 1.4 · Single answer

A company's data-center lease expires in four months. It runs 350 VMware VMs, managed by an operations team skilled in vSphere and NSX. Leadership wants to exit the data center with the least risk and the fewest changes, then modernize gradually.

Which migration approach should you recommend?

- **A.** Refactor all 350 applications into containers on GKE before the lease expires.
- **B.** Use Migrate to Containers to convert every VM to a container image.
- **C.** Rebuild the applications as Cloud Run services.
- **D.** Move the VMs to Google Cloud VMware Engine using VMware HCX, then modernize selected workloads after the exit.

<details><summary>Answer</summary>

**Answer: D**

**Why (P15):** A hard deadline plus deep VMware skills means rehost onto the same platform first. VMware Engine keeps vSphere/NSX tooling and needs no VM conversion.

- **A** — wrong: refactoring 350 applications in four months is high-risk and unrealistic.
- **B** — wrong: not every workload containerizes cleanly, and a mass conversion adds risk under a deadline.
- **C** — wrong: rebuilding is the slowest and riskiest option.
- **D** — correct: the fastest, lowest-change path out of the data center. Modernization follows.

**Reference:** <https://cloud.google.com/vmware-engine/docs/overview>

</details>

### Q18 · Task 1.4 · Single answer

A 6 TB PostgreSQL database that supports a 24×7 booking system must move to Google Cloud. The business accepts no more than 5 minutes of downtime during cutover.

What should you recommend?

- **A.** Use Database Migration Service with a continuous migration job to Cloud SQL for PostgreSQL, let it reach steady-state replication, then stop writes, promote the destination and repoint the application.
- **B.** Take a full `pg_dump` on Friday night, copy it to Cloud Storage, and restore it into Cloud SQL over the weekend.
- **C.** Copy the database files to a Transfer Appliance and ship it to Google.
- **D.** Replicate the database to BigQuery with Datastream, then export the tables to Cloud SQL.

<details><summary>Answer</summary>

**Answer: A**

**Why (P15, P10):** Minimal-downtime migrations rely on continuous replication (initial load plus change data capture) followed by a short, controlled cutover.

- **A** — correct: DMS continuous migration keeps the target in sync, so downtime is limited to the promotion.
- **B** — wrong: dump and restore of 6 TB takes many hours of downtime.
- **C** — wrong: an offline transfer can't keep up with a live, changing database.
- **D** — wrong: Datastream to BigQuery is analytics replication, not an OLTP migration path, and exporting adds downtime.

**Reference:** <https://cloud.google.com/database-migration/docs/overview>

</details>

### Q19 · Task 1.4 · Single answer

A company is migrating Windows Server and SQL Server workloads. It owns perpetual licenses **without** Software Assurance or License Mobility, so the license terms require dedicated physical hardware. Finance wants to reuse the existing licenses to avoid paying for them again.

Where should these workloads run?

- **A.** Cloud SQL for SQL Server, with license-included pricing.
- **B.** Standard Compute Engine VMs on shared hosts, with the customer's own licenses installed.
- **C.** Compute Engine sole-tenant nodes, using bring-your-own-license images.
- **D.** New SQL Server licenses purchased through Google Cloud Marketplace.

<details><summary>Answer</summary>

**Answer: C**

**Why (P9, P15):** Licenses that require dedicated hardware can be reused only on dedicated hosts. Sole-tenant nodes provide that, and avoid repurchasing licenses.

- **A** — wrong: license-included pricing means paying for licenses again, which finance wants to avoid.
- **B** — wrong: without License Mobility, these licenses can't run on shared multi-tenant hosts.
- **C** — correct: sole-tenant nodes satisfy dedicated-hardware license terms (BYOL).
- **D** — wrong: buying new licenses contradicts the goal.

**Reference:** <https://cloud.google.com/compute/docs/nodes/bringing-your-own-licenses>

</details>

### Q20 · Task 1.5 · Single answer

A company is building a new customer platform. Over the next three years it expects to add partner integrations, a mobile app, in-store kiosks and AI agents that act on customers' behalf, without knowing their exact requirements yet.

Which design choice best supports this future evolution?

- **A.** Let each new channel connect directly to the core databases, to avoid an extra layer.
- **B.** Expose core capabilities through versioned APIs managed in Apigee, and publish business events to Pub/Sub, so new channels and consumers can be added without changing the back ends.
- **C.** Build the platform as a single monolith on one large VM, to keep deployment simple.
- **D.** Build each partner integration as a nightly FTP batch job, written when the partner signs.

<details><summary>Answer</summary>

**Answer: B**

**Why (P8, P12):** Loose coupling through stable API contracts and events lets unknown future consumers plug in without rework. That's the essence of a cloud-first, evolvable design.

- **A** — wrong: direct database access couples every channel to the schema, so each change becomes risky.
- **B** — correct: versioned APIs plus events form the extension points future channels and agents will use.
- **C** — wrong: a monolith on one VM blocks independent scaling and evolution.
- **D** — wrong: bespoke batch integrations don't serve real-time channels and accumulate debt.

**Reference:** <https://cloud.google.com/apis/design>

</details>
