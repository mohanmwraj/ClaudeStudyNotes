# Mock Paper 3 · 50 Questions · 120 Minutes

**Instructions:**

* Set a timer for **120 minutes**, and answer all 50 questions without notes.
* Write your answers down first. For multiple-select questions, select exactly the number requested; there's no partial credit.
* Flag questions you're unsure about and return to them. Never leave one blank.
* When you finish, mark your answers with [10-mock-paper-3-answers.md](10-mock-paper-3-answers.md), and read the explanation for every question you missed **or guessed**.

**Case studies in this paper:** EHR Healthcare and Altostrat Media. Case-study questions start with **Case study: …**.

**Composition:** Section 1: 13 · Section 2: 9 · Section 3: 9 · Section 4: 7 · Section 5: 6 · Section 6: 6. There are 12 case-study questions (24%) and 6 multiple-select questions.

**Scoring guide:**

* **40/50 or better:** you're ready.
* **36–39:** review your weak domains and retake.
* **Below 36:** study more.

---

### Q1 · Domain 1 · Task 1.1 · Single answer

**Case study: EHR Healthcare.** EHR wants to decrease infrastructure administration costs for its container platform after migration. Its operations team currently patches nodes, plans capacity and upgrades clusters by hand.

What should you recommend?

- **A.** Self-managed Kubernetes on Compute Engine VMs, to keep full control.
- **B.** GKE Autopilot for the customer-facing workloads, so Google manages nodes, scaling, patching and upgrades, combined with managed database services.
- **C.** GKE Standard with auto-upgrade disabled, to avoid surprise changes.
- **D.** Run the containers directly on large VMs with Docker.

### Q2 · Domain 1 · Task 1.2 · Single answer

**Case study: EHR Healthcare.** EHR's business requirements set a minimum of 99.9% availability for customer-facing systems. A new architect proposes multi-region active-active for every system to be safe.

Which statement is correct?

- **A.** 99.9% allows roughly 43 minutes of downtime per month, which a regional, multi-zone design with managed HA services meets. A second region belongs in the DR plan, not necessarily in active-active serving.
- **B.** 99.9% allows roughly 4 minutes of downtime per month, so every system must be multi-region active-active.
- **C.** 99.9% allows about 7 hours of downtime per month, so single-zone deployments are acceptable.
- **D.** 99.9% means no downtime is allowed, so on-premises redundancy must also be retained.

### Q3 · Domain 1 · Task 1.3 · Single answer

**Case study: Altostrat Media.** Altostrat wants personalized content recommendations ("because you watched…") on its apps, based on viewing behavior, with minimal ML development and the ability to optimize for engagement.

What should you recommend?

- **A.** Build a custom collaborative-filtering model in notebooks, and serve it from a VM.
- **B.** Show every user the same "most popular" list from a daily BigQuery query.
- **C.** The managed Recommendations capability (formerly Recommendations from Vertex AI Search), fed with Altostrat's content catalog and user events.
- **D.** Ask users to select their favorite genres once, and filter content by genre.

### Q4 · Domain 1 · Task 1.3 · Single answer

Whenever a scanned document lands in a Cloud Storage bucket, it must be processed within seconds. The team wants no polling and no servers to manage.

What should you design?

- **A.** A Compute Engine VM that lists the bucket every minute.
- **B.** A nightly batch job that processes all new files.
- **C.** A Cloud Scheduler job that triggers a full-bucket scan every 5 minutes.
- **D.** An Eventarc trigger on the object-finalized event that invokes a Cloud Run service to process each new document.

### Q5 · Domain 1 · Task 1.3 · Select TWO

**Case study: Altostrat Media.** Altostrat wants to analyze media content to identify trends and extract insights, combining transcripts of its programs with audience engagement data. Which two components should you recommend? (Select TWO.)

- **A.** Store transcripts, content metadata and engagement events in BigQuery.
- **B.** Store all transcripts in Memorystore for fast access.
- **C.** Export everything to spreadsheets for analysts.
- **D.** Use Gemini in BigQuery (generative AI functions in SQL) to classify topics and sentiment across transcripts at scale, joined with engagement metrics.
- **E.** Use Cloud SQL as the analytics warehouse for all historical content.

### Q6 · Domain 1 · Task 1.4 · Single answer

**Case study: EHR Healthcare.** Some of EHR's applications use MongoDB. EHR wants to move these databases to a managed service with minimal application changes and full MongoDB feature compatibility.

What should you recommend?

- **A.** Rewrite the applications to use Cloud SQL for PostgreSQL.
- **B.** MongoDB Atlas on Google Cloud (through Google Cloud Marketplace), using Atlas live migration tooling.
- **C.** Store the documents as files in Cloud Storage.
- **D.** Install MongoDB on a single Compute Engine VM.

### Q7 · Domain 1 · Task 1.4 · Single answer

While planning a migration, the network team discovers that several on-premises subnets overlap with the RFC 1918 ranges planned for the new VPC. Workloads on both sides must communicate through Cloud Interconnect.

What should you recommend?

- **A.** Proceed as planned. Cloud Router resolves overlapping ranges automatically.
- **B.** Use VPC Network Peering to connect the overlapping ranges.
- **C.** Re-plan the VPC's address ranges so they don't overlap with on-premises networks, and use Private Service Connect or NAT only where an overlap truly can't be avoided.
- **D.** Assign public IP addresses to all workloads to avoid the overlap.

### Q8 · Domain 1 · Task 1.1 · Single answer

A partner sends order webhooks in large, unpredictable bursts. The partner retries only a few times, so dropped requests mean lost orders. Processing each order takes several seconds.

How should the receiving endpoint be designed?

- **A.** A Cloud Run endpoint that validates each request, publishes it to Pub/Sub and returns success immediately, with subscribers processing orders asynchronously and idempotently.
- **B.** A single VM that processes each order synchronously before responding.
- **C.** A Cloud Run endpoint that processes each order fully before responding, with maximum instances set to 1.
- **D.** Ask the partner to send fewer orders.

### Q9 · Domain 1 · Task 1.2 · Single answer

Two days ago, an analyst accidentally overwrote an important BigQuery table with incorrect results. There's no separate backup.

How can the data be recovered most quickly?

- **A.** Recovery is impossible without a backup.
- **B.** Restore from Persistent Disk snapshots of the BigQuery service.
- **C.** Ask the analyst to recompute the table from memory.
- **D.** Use BigQuery time travel to query the table as of a point before the overwrite (`FOR SYSTEM_TIME AS OF`), and restore it into a table.

### Q10 · Domain 1 · Task 1.3 · Single answer

A containerized nightly job processes files for about three hours and doesn't serve HTTP requests. The team wants no infrastructure to manage and to pay only while it runs.

Which platform should you use?

- **A.** A GKE Standard cluster that runs around the clock.
- **B.** Cloud Run jobs, triggered by Cloud Scheduler.
- **C.** Cloud Run functions with an HTTP trigger.
- **D.** An always-on Compute Engine VM.

### Q11 · Domain 1 · Task 1.5 · Single answer

**Case study: Altostrat Media.** Altostrat's legacy on-premises content-ingestion systems are slated for migration to Google Cloud in the near future. A new ingestion feature is needed now.

How should the new feature be designed so it doesn't block the planned migration?

- **A.** Build it into the legacy on-premises ingestion system, and migrate it later with everything else.
- **B.** Build it on a new on-premises server, to keep it close to the content.
- **C.** Build it cloud-first: on-premises sources upload files to Cloud Storage, and Eventarc triggers serverless processing, so the processing stays unchanged once ingestion itself moves to the cloud.
- **D.** Postpone the feature until after the migration.

### Q12 · Domain 1 · Task 1.1 · Single answer

A company's development and test environments run 24 hours a day, but are used only during working hours on weekdays. Leadership wants to cut their cost substantially without affecting developers.

What should you recommend?

- **A.** Schedule non-production resources to stop or scale to zero outside working hours (for example, instance schedules for VMs, and Autopilot or Cloud Run that scale with use), and set budgets with alerts.
- **B.** Buy 3-year committed use discounts for all development and test VMs.
- **C.** Move development and test to the most expensive machine types, to finish work faster.
- **D.** Delete the development environments.

### Q13 · Domain 1 · Task 1.3 · Single answer

**Case study: EHR Healthcare.** EHR needs interfaces to ingest clinical data from new providers in healthcare standards (HL7v2 messages and FHIR resources), and to make the data available for analytics in near real time.

What should you recommend?

- **A.** Parse HL7v2 messages with custom code on a VM, and store them in text files.
- **B.** Load all messages into Memorystore.
- **C.** Email the messages to a data team, which uploads them weekly.
- **D.** The Cloud Healthcare API with HL7v2 and FHIR stores, using Pub/Sub notifications for downstream processing and streaming export of FHIR data to BigQuery for analytics.

### Q14 · Domain 2 · Task 2.1 · Single answer

On-premises servers connected through Cloud Interconnect must call Cloud Storage and BigQuery APIs privately. The APIs are also protected by a VPC Service Controls perimeter.

How should on-premises API traffic be routed?

- **A.** Over the public internet, to the default API endpoints.
- **B.** To the `restricted.googleapis.com` virtual IP range (or a Private Service Connect endpoint for the VPC-SC API bundle), advertised to on-premises through Cloud Router, with on-premises DNS resolving Google API names to it.
- **C.** Through a Classic VPN tunnel to `www.google.com`.
- **D.** Through Direct Peering with Google's public edge.

### Q15 · Domain 2 · Task 2.1 · Single answer

A web application's back-end VMs sit behind a global external Application Load Balancer with Cloud Armor. The security team wants to ensure that nobody can bypass the load balancer and reach the back ends directly from the internet.

What should you configure?

- **A.** Remove external IP addresses from the back-end VMs, and allow ingress to the serving port only from Google's load-balancer proxy and health-check ranges.
- **B.** Rely on Cloud Armor alone, while keeping public IP addresses on the back ends.
- **C.** Put the back ends in a public subnet with an allow-all firewall rule.
- **D.** Change the application port to a non-standard number.

### Q16 · Domain 2 · Task 2.2 · Single answer

**Case study: Altostrat Media.** Altostrat's metadata-extraction and transcoding jobs run in one zone of `us-central1`, and repeatedly read the same popular media files from a US multi-region bucket. Altostrat wants higher read throughput and lower data-transfer costs, without moving or duplicating the bucket.

What should you recommend?

- **A.** Copy the popular files to Local SSDs on every worker VM.
- **B.** Move all media to a Nearline bucket.
- **C.** Create a Rapid Cache (formerly Anywhere Cache) for the bucket in the zone where the jobs run.
- **D.** Disable object versioning on the bucket.

### Q17 · Domain 2 · Task 2.3 · Single answer

A stateless application in a managed instance group sometimes hangs while its VMs stay in the RUNNING state, so the hung instances keep failing requests for hours.

What should you configure?

- **A.** A larger machine type.
- **B.** A daily reboot of all instances, run from cron.
- **C.** Manual monitoring by the on-call engineer.
- **D.** MIG autohealing with an application health check, and an initial delay long enough for startup, so unhealthy instances are recreated automatically.

### Q18 · Domain 2 · Task 2.3 · Single answer

A SaaS company onboards several large enterprise customers each month. Each one needs a dedicated, isolated environment with its own project, GKE cluster and Cloud SQL instance, configured identically. Today each environment takes two weeks to build by hand.

What should you recommend?

- **A.** Clone an existing customer's project manually with the console.
- **B.** Parameterized Terraform modules, run by a pipeline (or Infrastructure Manager), that create the project, GKE cluster, Cloud SQL instance and policies for each new customer from one template.
- **C.** Put all customers in one shared cluster without isolation.
- **D.** Hire more engineers to build environments faster by hand.

### Q19 · Domain 2 · Task 2.4 · Single answer

A churn-prediction model deployed on an Agent Platform endpoint gradually loses accuracy as customer behavior changes. The team finds out only when business metrics drop.

What should you implement?

- **A.** Model Monitoring on the endpoint to detect feature drift and training–serving skew, with alerts that trigger an Agent Platform Pipelines retraining run.
- **B.** A larger model, deployed once.
- **C.** Manual quarterly accuracy reviews.
- **D.** Disable logging of prediction requests, to reduce cost.

### Q20 · Domain 2 · Task 2.5 · Single answer

**Case study: Altostrat Media.** Altostrat wants an advanced chatbot that provides personalized assistance. It should remember a user's earlier conversations and preferences, call tools such as "find episodes" and "manage subscription", and ground its answers in Altostrat's help content.

What should you build?

- **A.** A static FAQ page.
- **B.** A rules-based chatbot with fixed decision trees.
- **C.** A single prompt to a Gemini model, with no memory or tools.
- **D.** An agent built with the Agent Development Kit and deployed on Agent Runtime, using Agent Platform Sessions and Memory Bank for context, tools for actions, and Agent Search for grounding.

### Q21 · Domain 2 · Task 2.5 · Select TWO

A legal-services company needs to (1) translate video subtitles into 15 languages, and (2) extract parties, dates and amounts from scanned contracts into structured fields. Which two Google AI services should you use? (Select TWO.)

- **A.** Imagen, for extracting text from scanned contracts.
- **B.** The Cloud Translation API, for the subtitles.
- **C.** The Video Intelligence API, for translating subtitles.
- **D.** Speech-to-Text, for reading scanned contracts.
- **E.** Document AI, using a contract or custom extraction processor, for the scanned contracts.

### Q22 · Domain 2 · Task 2.2 · Single answer

A company keeps 500 TB of historical data in BigQuery. Most tables are written once and rarely modified, and the data compresses well. Finance wants lower storage costs without moving the data out of BigQuery.

What should you recommend?

- **A.** Export all data to Coldline Cloud Storage, and delete the tables.
- **B.** Recreate all tables every month.
- **C.** Rely on BigQuery's automatic long-term storage pricing for tables and partitions unmodified for 90 days, and evaluate the physical (compressed) storage billing model for the datasets.
- **D.** Move the data to Cloud SQL.

### Q23 · Domain 3 · Task 3.1 · Single answer

**Case study: EHR Healthcare.** EHR has placed its Cloud Healthcare API and BigQuery projects inside a VPC Service Controls perimeter. On-premises integration servers, which reach Google Cloud over Interconnect, must still call the Healthcare API.

What should you configure?

- **A.** Remove the Healthcare API from the perimeter's restricted services.
- **B.** An access level for the on-premises IP ranges, used in an ingress rule for the Healthcare API, with on-premises traffic routed privately to `restricted.googleapis.com` over the Interconnect.
- **C.** Give the on-premises servers public IP addresses and allow them in a firewall rule.
- **D.** Disable the perimeter during business hours.

### Q24 · Domain 3 · Task 3.1 · Single answer

After an incident in which a developer accidentally made a bucket of customer data public, the CISO wants to make public Cloud Storage buckets impossible across the organization, apart from one documented project for public web assets.

What should you implement?

- **A.** A weekly script that scans for public buckets and emails their owners.
- **B.** Training for developers about bucket permissions.
- **C.** VPC firewall rules that block public access.
- **D.** Enforce the `storage.publicAccessPrevention` organization policy at the organization, with an override only on the public-assets project.

### Q25 · Domain 3 · Task 3.1 · Single answer

**Case study: Altostrat Media.** Altostrat deploys containers to GKE clusters in Google Cloud and on-premises from its centralized CI/CD platform. Security requires that only images built and signed by that pipeline can run on any cluster.

What should you implement?

- **A.** Binary Authorization, with policies requiring attestations from the CI pipeline's attestor, enforced on all fleet clusters.
- **B.** A naming convention for approved image tags.
- **C.** Weekly vulnerability reports emailed to developers.
- **D.** Restrict access to the Artifact Registry console.

### Q26 · Domain 3 · Task 3.1 · Select TWO

A BigQuery table contains employee data, including a salary column. Analysts may query the table but must see salaries only as masked values. HR managers must see real salaries. Which two actions should you take? (Select TWO.)

- **A.** Tag the salary column with a policy tag and configure a dynamic data-masking rule for analysts.
- **B.** Grant analysts the BigQuery Admin role.
- **C.** Grant HR managers the Fine-Grained Reader role on the policy tag, so they see unmasked values.
- **D.** Export the table to CSV without the salary column each day.
- **E.** Share the table publicly and rely on analysts not to look at salaries.

### Q27 · Domain 3 · Task 3.1 · Single answer

An application on AWS EC2 needs to read objects from a Cloud Storage bucket. Security forbids service account keys.

What should you configure?

- **A.** A service account key, stored in AWS Secrets Manager.
- **B.** A public bucket, accessed with signed URLs generated manually each week.
- **C.** Workload Identity Federation with an AWS provider, so the EC2 instance's AWS role can impersonate a Google service account that has read access to the bucket.
- **D.** An API key for Cloud Storage.

### Q28 · Domain 3 · Task 3.2 · Single answer

Auditors of a regulated company require evidence that audit logs couldn't have been altered or deleted by administrators during the retention period, and visibility into any access by Google personnel to company data.

What should you implement?

- **A.** Route audit logs through an organization-level aggregated sink to a central log bucket whose retention policy is locked, restrict IAM on the logging project to a small security group, and enable Access Transparency logs.
- **B.** Keep logs in each project's `_Default` bucket, with default settings.
- **C.** Export logs to a spreadsheet each month.
- **D.** Ask administrators to promise not to delete logs.

### Q29 · Domain 3 · Task 3.1 · Single answer

A retail website's login endpoint is being hit by credential-stuffing bots, millions of attempts an hour from rotating IP addresses, behind a global external Application Load Balancer.

What should you configure?

- **A.** A VPC firewall rule blocking the top 10 offending IP addresses.
- **B.** Cloud Armor rate-based rules on the login path, with bot management through reCAPTCHA (Google Cloud Fraud Defense) integration and Adaptive Protection.
- **C.** Larger back-end instances to absorb the traffic.
- **D.** Move the login page to a different URL.

### Q30 · Domain 3 · Task 3.2 · Single answer

A company with 500 projects must find out which BigQuery datasets and Cloud Storage buckets contain personal data, such as names, emails and national IDs, to prepare for a privacy audit. The inventory must stay current as data changes.

What should you use?

- **A.** A one-time manual survey of data owners.
- **B.** VPC Flow Logs analysis.
- **C.** Cloud Asset Inventory resource listings.
- **D.** Sensitive Data Protection discovery, configured at the organization level to continuously profile BigQuery and Cloud Storage and report sensitivity and risk.

### Q31 · Domain 3 · Task 3.1 · Single answer

Many teams are building generative-AI applications in different projects. The security team wants a minimum level of protection against prompt injection and sensitive-data leakage applied consistently everywhere, even if a team forgets to configure it.

What should you implement?

- **A.** A wiki page describing recommended prompts.
- **B.** VPC firewall rules on each project.
- **C.** Model Armor floor settings at the organization (or folder) level, which enforce minimum screening for all applications beneath it, with per-application templates for stricter needs.
- **D.** A quarterly review of each team's prompts.

### Q32 · Domain 4 · Task 4.1 · Single answer

A company runs workloads on Google Cloud and on-premises. Operational workflows, such as restarting failed ingestion jobs, rotating credentials and scaling for scheduled events, are done by hand and differ between environments.

What should you recommend?

- **A.** Automate these workflows as code (for example, with Workflows and event triggers, and runbooks attached to alerts), deploy them through the same CI/CD process for both environments, and measure reliability with SLOs.
- **B.** Write separate manual checklists for each environment.
- **C.** Assign one engineer per environment to perform the tasks.
- **D.** Stop running scheduled events.

### Q33 · Domain 4 · Task 4.1 · Single answer

After a project was moved into a folder protected by a VPC Service Controls perimeter, a data pipeline in another project started failing with `PERMISSION_DENIED` errors, although its IAM roles are unchanged.

What should you check first?

- **A.** The pipeline's machine type.
- **B.** Whether the BigQuery dataset is partitioned.
- **C.** The VPC Service Controls audit logs (Policy Denied entries) to identify the blocked request, then add an appropriate ingress or egress rule, after testing it in dry-run mode.
- **D.** The billing account status.

### Q34 · Domain 4 · Task 4.1 · Single answer

Infrastructure changes are tested only in a shared staging environment that has drifted from production. Teams block each other, and drift hides bugs.

What should you recommend?

- **A.** Test infrastructure changes directly in production.
- **B.** Create ephemeral test environments from the same Terraform modules for each pull request, run automated tests and policy checks, then destroy them.
- **C.** Stop testing infrastructure changes.
- **D.** Freeze the staging environment permanently.

### Q35 · Domain 4 · Task 4.2 · Single answer

**Case study: EHR Healthcare.** EHR's executive statement says its on-premises strategy required a major investment of time and money training the team on distinctly different systems and managing similar but separate environments.

What should the cloud operating model emphasize to address this?

- **A.** Let each team choose different tools in each environment.
- **B.** Keep separate on-premises and cloud operations teams with different processes.
- **C.** Delay training until all systems have migrated.
- **D.** Standardize on one platform and toolchain (GKE fleets, Terraform, Cloud Deploy, Google Cloud Observability) across environments, and train the team on that common stack.

### Q36 · Domain 4 · Task 4.2 · Select TWO

A company runs a large fleet of Compute Engine VMs for a steady, business-critical application, and expects the load to stay stable for at least three years. Which two actions will reduce costs most appropriately? (Select TWO.)

- **A.** Commit now, at current peak-provisioned sizes, before any analysis.
- **B.** Rightsize the VMs first, using Recommender and utilization data.
- **C.** Run the production database on Spot VMs.
- **D.** Purchase 3-year committed use discounts for the rightsized steady-state baseline.
- **E.** Disable monitoring to save its cost.

### Q37 · Domain 4 · Task 4.2 · Single answer

A team plans to set and lock a 10-year retention policy on a new compliance bucket today, "to test how it works", before legal has confirmed the required retention period.

What should you advise?

- **A.** Treat locking as an irreversible decision: test with an unlocked retention policy on a test bucket, confirm the requirement with legal, and lock only once it's agreed.
- **B.** Lock it now. It can be undone later if needed.
- **C.** Lock it with a 100-year period, to be safe.
- **D.** Skip the retention policy entirely.

### Q38 · Domain 4 · Task 4.1 · Single answer

A company wants to use Google Cloud as the disaster-recovery site for its on-premises VMware and physical servers. Its RTO is 8 hours, and it wants to pay as little as possible until a disaster occurs.

What should you recommend?

- **A.** Run a full duplicate of the production environment in Google Cloud continuously.
- **B.** Take tape backups and store them in an office.
- **C.** Replicate backups of the on-premises workloads to Google Cloud with Backup and DR Service (a pilot-light approach), and recover VMs in Google Cloud on demand following a tested runbook.
- **D.** Do nothing until a disaster happens.

### Q39 · Domain 5 · Task 5.1 · Single answer

During a multi-year transition, a company's partner APIs are served partly by on-premises legacy systems and partly by new services on Google Cloud. Partners should use one consistent API, with the same security and analytics, regardless of where each back end runs.

What should you recommend?

- **A.** Give partners separate endpoints for on-premises and cloud services.
- **B.** An Apigee API layer that fronts both on-premises and cloud back ends (with Apigee hybrid if the runtime must sit on-premises), so back ends can migrate without partner changes.
- **C.** Expose on-premises APIs directly to the internet.
- **D.** Wait until migration is complete before offering partner APIs.

### Q40 · Domain 5 · Task 5.1 · Single answer

A load test of a Cloud Run service backed by Cloud SQL shows that, at high traffic, new database connections fail, because the service scales to hundreds of instances and each opens many connections.

What should you advise the team?

- **A.** Remove Cloud SQL and store data in memory.
- **B.** Increase the Cloud Run request timeout.
- **C.** Disable autoscaling entirely.
- **D.** Use connection pooling (in the application or a managed pooler) with small per-instance pools, cap Cloud Run's maximum instances to what the database can support, and consider read replicas for read traffic.

### Q41 · Domain 5 · Task 5.2 · Single answer

Each night, a team loads 2 TB of CSV files from Cloud Storage into BigQuery. They currently use streaming inserts from a script, which is costly and slow.

What should they do instead?

- **A.** Use BigQuery batch load jobs (for example, `bq load` from the Cloud Storage files).
- **B.** Stream the rows faster with more threads.
- **C.** Load the files into Cloud SQL first, then copy them to BigQuery.
- **D.** Convert the CSV files to images.

### Q42 · Domain 5 · Task 5.2 · Single answer

An automation script creates a Cloud SQL instance through the API, then immediately tries to create a database on it. The second call fails because the instance isn't ready yet.

What's the correct approach?

- **A.** Add a fixed 10-second sleep between the calls.
- **B.** Retry the second call in a tight loop without delay.
- **C.** Treat the create call as a long-running operation: poll (or wait on) the returned operation until it completes successfully, then create the database.
- **D.** Create the database before the instance.

### Q43 · Domain 5 · Task 5.2 · Single answer

Developers building services for GKE want a fast inner development loop from their IDE: edit code, have it rebuilt and redeployed to a development cluster automatically, and debug it in place.

What should they use?

- **A.** Manual `docker build` and `kubectl apply` commands after every change.
- **B.** Cloud Code in their IDE, which uses Skaffold for continuous build and deploy to the development cluster, with integrated debugging.
- **C.** Cloud Shell, run on a schedule.
- **D.** Deployment Manager templates.

### Q44 · Domain 5 · Task 5.1 · Single answer

A team has used Database Migration Service to replicate a large PostgreSQL database to Cloud SQL, and is about to cut over. The business wants assurance that the data matches.

What should you advise before cutover?

- **A.** Cut over immediately; replication guarantees perfect data.
- **B.** Compare the database sizes in gigabytes.
- **C.** Ask a user to spot-check a few records after cutover.
- **D.** Run data validation between source and target (for example, row counts, column aggregates and checksums, using the open-source Data Validation Tool), and resolve any discrepancies before promoting the destination.

### Q45 · Domain 6 · Task 6.2 · Select TWO

Cloud Logging costs have grown sharply. Most volume comes from verbose debug logs and load-balancer health-check request logs, while audit logs must be retained for compliance. Which two actions reduce cost appropriately? (Select TWO.)

- **A.** Disable Admin Activity audit logs.
- **B.** Delete the `_Required` log bucket.
- **C.** Add exclusion filters to the `_Default` sink for debug-level application logs and health-check request logs.
- **D.** Disable Data Access audit logs for the regulated services, to save money.
- **E.** Reduce the VPC Flow Logs sampling rate and aggregation detail where full fidelity isn't needed.

### Q46 · Domain 6 · Task 6.3 · Single answer

A team deploys a new version of a service on GKE, and wants 10% of production traffic to go to it first, with automated analysis before it receives more traffic.

What should you recommend?

- **A.** A canary release, using Cloud Deploy's canary strategy (or Gateway API weighted traffic splitting), with automated verification of error rate and latency before each traffic increase.
- **B.** Replace all pods at once, and roll back if users complain.
- **C.** Deploy the new version to a separate cluster, and tell 10% of users the new URL.
- **D.** Release only on weekends, to reduce impact.

### Q47 · Domain 6 · Task 6.6 · Single answer

A team wants to verify that its services handle a slow downstream dependency gracefully, with timeouts, retries with backoff and circuit breaking, before a real slowdown happens in production.

What should it do?

- **A.** Wait for the dependency to slow down naturally.
- **B.** Disable timeouts, so requests eventually succeed.
- **C.** Increase the dependency's capacity permanently.
- **D.** Inject latency faults into calls to the dependency (for example, with Cloud Service Mesh fault injection) in a controlled experiment, and observe whether SLOs hold.

### Q48 · Domain 6 · Task 6.5 · Select TWO

A company has launched a generative-AI support assistant. Leadership asks how quality will be controlled after launch. Which two measures should you recommend? (Select TWO.)

- **A.** Monitor only the assistant's uptime.
- **B.** Continuously sample production conversations, and score them with the Gen AI evaluation service for groundedness, helpfulness and safety.
- **C.** Trust the model's output without measurement.
- **D.** Collect user feedback signals (ratings, escalations to humans, resolution rates), and review them against targets, feeding problems back into prompts and grounding data.
- **E.** Disable conversation logging, so no data is retained.

### Q49 · Domain 6 · Task 6.4 · Single answer

Production checkout is completely down for all customers, and the team suspects a problem with a Google Cloud managed service. The company has an Enhanced Support plan.

How should the team engage Google support?

- **A.** Open a low-priority case, to avoid bothering support.
- **B.** Post the problem on a public forum, and wait for answers.
- **C.** Open a case with P1 (critical impact) priority, including project and resource IDs, timestamps, error details, business impact and steps taken, while continuing its own mitigation.
- **D.** Wait 24 hours before opening a case.

### Q50 · Domain 6 · Task 6.2 · Single answer

A team is defining a latency SLO for its public API.

Which SLI definition follows SRE best practice?

- **A.** Average CPU utilization of the API servers over a day.
- **B.** The proportion of valid requests served faster than a threshold (for example, 300 ms), measured at the load balancer, over a 28-day window.
- **C.** The mean response time measured from inside the server process.
- **D.** The number of deployments per week.
