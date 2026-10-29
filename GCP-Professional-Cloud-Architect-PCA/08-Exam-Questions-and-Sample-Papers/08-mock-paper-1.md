# Mock Paper 1 · 50 Questions · 120 Minutes

**Instructions:**

* Set a timer for **120 minutes**, and answer all 50 questions without notes.
* Write your answers on paper or in a text file (for example `1-A,C,E, 2-D, …`). For multiple-select questions, select exactly the number requested. There's no partial credit.
* Flag questions you're unsure about and return to them. Never leave one blank.
* When you finish, mark your answers with [08-mock-paper-1-answers.md](08-mock-paper-1-answers.md), and read the explanation for every question you missed **or guessed**.

**Case studies in this paper:** EHR Healthcare and Cymbal Retail. Case-study questions start with **Case study: …**. Keep [01-Case-Studies](../01-Case-Studies/) closed during the attempt; in the real exam the case text is available on screen.

**Composition** (matches the official weighting): Section 1: 13 · Section 2: 9 · Section 3: 9 · Section 4: 7 · Section 5: 6 · Section 6: 6. There are 12 case-study questions (24%) and 6 multiple-select questions. Domain and task labels are shown to help your review; the real exam doesn't label questions.

**Scoring guide:** each question is worth 1 point.

* **40/50 (80%) or better:** you're ready.
* **36–39:** review your weak domains and retake.
* **Below 36:** study more before booking.

Google doesn't publish a passing score, so these thresholds are deliberately conservative.

---

### Q1 · Domain 1 · Task 1.1 · Select THREE

**Case study: EHR Healthcare.** EHR's executive statement says many outages resulted from misconfigured systems, inadequate capacity to manage spikes in traffic, and inconsistent monitoring practices. Which three initiatives most directly address these root causes? (Select THREE.)

- **A.** Manage infrastructure and cluster configuration as code, with peer review and GitOps (Terraform and Config Sync).
- **B.** Add a manual change-approval board that reviews every configuration change weekly.
- **C.** Use horizontal pod autoscaling and cluster autoscaling (or GKE Autopilot) for customer-facing workloads.
- **D.** Move customer-facing applications to the largest available machine types.
- **E.** Standardize on Google Cloud Observability, with SLO-based alerting and centralized dashboards across all environments.
- **F.** Send all monitoring alerts to a shared email inbox.

### Q2 · Domain 1 · Task 1.2 · Single answer

An order-management application runs on a regional GKE cluster with a Cloud SQL for PostgreSQL HA instance. The business requires an RPO of 15 minutes and an RTO of 1 hour for a full regional outage, and wants to keep DR costs low.

Which DR design should you recommend?

- **A.** Multi-region active-active deployment with Spanner, replacing Cloud SQL.
- **B.** Nightly Cloud SQL exports to a bucket in the same region, and rebuild everything after a disaster.
- **C.** Rely on the Cloud SQL HA standby to fail over to another region.
- **D.** A Cloud SQL cross-region read replica in a DR region, a scaled-down GKE cluster there restorable with Backup for GKE, infrastructure as code for the remaining resources, and a tested promotion and traffic-switch runbook.

### Q3 · Domain 1 · Task 1.3 · Single answer

A fitness app stores user profiles, workout logs and preferences. Users frequently work out with no connectivity and expect their data to sync automatically when they reconnect, with near-real-time updates across their devices. The team wants a serverless database.

Which database should you choose?

- **A.** Firestore.
- **B.** Cloud SQL for MySQL.
- **C.** Bigtable.
- **D.** BigQuery.

### Q4 · Domain 1 · Task 1.3 · Single answer

**Case study: Cymbal Retail.** During flash sales, Cymbal's product pages must handle sudden traffic spikes while keeping the user experience fast. Product images are served from the same back ends today. The team wants to reduce operational overhead.

What should you recommend?

- **A.** A fixed-size Compute Engine fleet sized for the largest sale ever, with images on Persistent Disk.
- **B.** A single large VM with local SSD for images.
- **C.** Containerized front ends on GKE Autopilot or Cloud Run with autoscaling, Memorystore for hot product data, and Cloud CDN for images and cacheable pages.
- **D.** Serve product pages directly from BigQuery queries.

### Q5 · Domain 1 · Task 1.3 · Select TWO

A media company streams about 2 TB of clickstream events per day. Analysts need ad-hoc SQL over several years of history within minutes of events arriving, and business users need governed dashboards. Which two components should be part of the design? (Select TWO.)

- **A.** Cloud SQL for PostgreSQL as the analytics store.
- **B.** Pub/Sub ingestion with Dataflow streaming into partitioned BigQuery tables.
- **C.** Bigtable as the store for analysts' ad-hoc SQL joins.
- **D.** Looker on BigQuery, for a governed semantic layer and dashboards.
- **E.** Memorystore as the long-term event store.

### Q6 · Domain 1 · Task 1.4 · Single answer

**Case study: EHR Healthcare.** Several of EHR's customer-facing applications use Microsoft SQL Server. EHR wants a managed service, minimal cutover downtime, and no separate license procurement.

What should you recommend?

- **A.** SQL Server on Compute Engine VMs, with licenses purchased separately and backups copied manually.
- **B.** Cloud SQL for SQL Server (license included) with high availability, migrated with Database Migration Service using continuous migration from backups.
- **C.** Convert the databases to BigQuery.
- **D.** Rewrite the applications to use Firestore.

### Q7 · Domain 1 · Task 1.4 · Single answer

During migration planning, discovery shows that an order application makes thousands of database calls per transaction to an inventory database. The proposed plan moves the application in wave 2 and the inventory database in wave 5, months later.

What should you recommend?

- **A.** Group the application and the inventory database into the same move group and migrate them in the same wave, because splitting them would put thousands of round trips per transaction across the hybrid link.
- **B.** Keep the plan, and add a second Interconnect to reduce latency.
- **C.** Migrate the inventory database first and the application a year later.
- **D.** Cache the entire inventory database in Memorystore on-premises.

### Q8 · Domain 1 · Task 1.1 · Single answer

A company wants to synchronize customer records between Salesforce, SAP and a custom application on Cloud Run, with branching logic, retries and error notifications. The integration team prefers low-code tooling and wants to avoid writing and maintaining custom connector code.

What should you recommend?

- **A.** Custom Python scripts on a Compute Engine VM, run by cron.
- **B.** Nightly CSV exports from each system to a shared drive.
- **C.** Direct database connections between the three systems.
- **D.** Application Integration with Integration Connectors for Salesforce and SAP.

### Q9 · Domain 1 · Task 1.2 · Single answer

A VM-based application in a regional managed instance group takes about 10 minutes to start. Traffic rises sharply at 8:00 every weekday. CPU-based autoscaling reacts too late, and users see errors for the first 15 minutes of each morning.

What should you recommend?

- **A.** Lower the CPU utilization target to 20%.
- **B.** Replace the instance group with a single larger VM.
- **C.** Enable predictive autoscaling (and/or a scaling schedule that adds capacity before 8:00), and shorten startup with a pre-built custom image.
- **D.** Add a second, identical instance group in another region.

### Q10 · Domain 1 · Task 1.3 · Single answer

A company must move a legacy Windows application that depends on IIS and Active Directory domain membership. It can't be containerized in the migration timeframe.

Where should it run?

- **A.** On Compute Engine Windows Server VMs in a managed instance group, joined to a Managed Service for Microsoft Active Directory domain.
- **B.** On Cloud Run, using a Windows container.
- **C.** On Cloud Run functions.
- **D.** On App Engine standard environment.

### Q11 · Domain 1 · Task 1.5 · Single answer

**Case study: Cymbal Retail.** After catalog enrichment and conversational commerce, Cymbal expects to add more generative-AI use cases, such as personalized marketing content and demand forecasting. Leadership asks which foundational decision now will make future AI initiatives fastest to deliver.

What should you recommend?

- **A.** Let each AI project copy the data it needs into its own storage.
- **B.** Consolidate customer, catalog and interaction data into BigQuery with Knowledge Catalog governance, so AI projects on Agent Platform can use trusted, well-described data.
- **C.** Choose one large language model now, and fine-tune it on every dataset.
- **D.** Keep the data in the current silos, and decide later.

### Q12 · Domain 1 · Task 1.1 · Single answer

A company is consolidating analytics on Google Cloud. It must copy 40 TB of objects from an Amazon S3 bucket once, then copy new and changed objects every day, with no servers to manage.

What should you use?

- **A.** Transfer Appliance, shipped to the AWS region.
- **B.** A Compute Engine VM running `aws s3 sync`, then `gcloud storage cp`.
- **C.** Database Migration Service.
- **D.** Storage Transfer Service, with an agentless S3 source and a daily schedule.

### Q13 · Domain 1 · Task 1.3 · Single answer

**Case study: EHR Healthcare.** EHR uses Redis as a session and data cache for its customer-facing applications. The cache must survive a zone failure to support the 99.9% availability requirement, with minimal administration.

What should you recommend?

- **A.** Redis on a single Compute Engine VM, with hourly snapshots.
- **B.** An in-memory cache inside each application pod.
- **C.** Memorystore (for Redis, or for Valkey) in a high-availability configuration with a replica in another zone and automatic failover.
- **D.** Store sessions in BigQuery.

### Q14 · Domain 2 · Task 2.1 · Single answer

**Case study: EHR Healthcare.** EHR's new applications on Google Cloud must resolve the hostnames of the legacy insurance integration systems, which are registered in EHR's on-premises DNS servers and reachable over Cloud Interconnect.

What should you configure?

- **A.** A Cloud DNS private forwarding zone for the on-premises domain, forwarding queries to the on-premises DNS servers over the Interconnect.
- **B.** Hard-code the IP addresses of the legacy systems in each application.
- **C.** A public Cloud DNS zone containing the on-premises hostnames.
- **D.** An `/etc/hosts` file distributed to every container image.

### Q15 · Domain 2 · Task 2.1 · Single answer

Internal microservices are deployed in two regions. Internal clients need a single HTTP endpoint with path-based routing, and traffic must fail over to the other region if one region's back ends become unhealthy. No internet exposure is allowed.

Which load balancer should you use?

- **A.** A global external Application Load Balancer.
- **B.** A regional internal passthrough Network Load Balancer in each region.
- **C.** A cross-region internal Application Load Balancer.
- **D.** An external passthrough Network Load Balancer.

### Q16 · Domain 2 · Task 2.2 · Single answer

A content-management system running on several VMs requires a shared POSIX file system (NFS) for uploaded assets. The file system must remain available if a zone fails, and the application can't be changed to use object storage.

What should you provision?

- **A.** A Cloud Storage bucket mounted with Cloud Storage FUSE.
- **B.** Filestore with a regional (or enterprise) tier.
- **C.** A zonal Persistent Disk attached to all VMs in read-write mode.
- **D.** Local SSDs on each VM, synchronized with rsync.

### Q17 · Domain 2 · Task 2.3 · Single answer

A latency-sensitive payment API runs on Cloud Run. During quiet periods, the first requests after idle time take several seconds because of cold starts, which breaches the latency SLO.

What should you configure?

- **A.** Reduce the maximum number of instances to 1.
- **B.** Move the API to Cloud Run functions.
- **C.** Increase the request timeout to 60 minutes.
- **D.** Set a minimum number of instances greater than zero, and enable startup CPU boost.

### Q18 · Domain 2 · Task 2.3 · Select TWO

A company's GKE Standard clusters run steady web services and large nightly batch jobs. Node utilization averages 25%. Which two changes reduce cost without risking the web services' availability? (Select TWO.)

- **A.** Run the nightly batch jobs on a Spot VM node pool, using taints and tolerations to keep web services off it.
- **B.** Disable the cluster autoscaler and keep peak-sized node pools at all times.
- **C.** Rightsize pod resource requests (for example, with Vertical Pod Autoscaler recommendations), and let the cluster autoscaler remove underused nodes. Alternatively, move suitable workloads to Autopilot.
- **D.** Move all workloads to the largest machine type available.
- **E.** Turn off Cloud Monitoring for the clusters.

### Q19 · Domain 2 · Task 2.4 · Single answer

A fraud model performs well in offline evaluation but poorly in production. Investigation shows that feature values in production are computed with different code from the training pipeline.

What should you recommend?

- **A.** Define the features once in Agent Platform Feature Store, and use it for both training data and online serving.
- **B.** Retrain the model more often with the same separate code paths.
- **C.** Increase the model's size.
- **D.** Deploy the model to more endpoints.

### Q20 · Domain 2 · Task 2.5 · Single answer

**Case study: Cymbal Retail.** Cymbal's virtual agents on the website and mobile app must answer customers' questions in natural language, grounded in the product catalog and Cymbal's policy documents (returns, shipping), and hand off to human agents when needed.

What should you build?

- **A.** A rules-based FAQ menu with fixed answers.
- **B.** Conversational Agents (Dialogflow CX) with generative playbooks, grounded in Agent Search data stores for the catalog and policy documents, with escalation to human agents through Customer Engagement Suite.
- **C.** A Cloud Run function that returns random product suggestions.
- **D.** A custom large language model trained from scratch on Cymbal's documents.

### Q21 · Domain 2 · Task 2.1 · Single answer

A company has just acquired another company. Each has one VPC in its own Google Cloud organization, and the IP ranges don't overlap. They need low-latency, bidirectional private connectivity between all workloads in the two VPCs, with each IT team keeping control of its own network.

What should you configure?

- **A.** Shared VPC, with the acquired company's projects attached as service projects.
- **B.** Public IP addresses and firewall allow-lists on both sides.
- **C.** A Private Service Connect endpoint for each individual workload.
- **D.** VPC Network Peering between the two VPCs.

### Q22 · Domain 2 · Task 2.2 · Single answer

Analysts using BigQuery on-demand pricing occasionally run unbounded queries over multi-terabyte tables, causing surprise bills. Finance wants a hard limit on daily query spend per user and per project, without blocking normal work.

What should you configure?

- **A.** Delete large tables at the end of each day.
- **B.** Move the data to Cloud SQL.
- **C.** Custom quotas on query bytes processed per user and per project per day, combined with partitioned tables that require a partition filter.
- **D.** Ask analysts to review their own costs monthly.

### Q23 · Domain 3 · Task 3.1 · Single answer

**Case study: EHR Healthcare.** Data scientists analyze de-identified healthcare trend data in BigQuery projects that also hold some PHI. EHR must prevent any user, even one with legitimate IAM access, from copying data out of these projects to unapproved projects or personal accounts.

What should you implement?

- **A.** Remove the data scientists' IAM roles.
- **B.** A VPC Service Controls perimeter around the analytics projects, restricting BigQuery and Cloud Storage, with ingress and egress rules only for approved flows.
- **C.** VPC firewall rules that deny egress to the internet.
- **D.** An organization policy restricting resource locations to the US.

### Q24 · Domain 3 · Task 3.1 · Single answer

A Cloud Run service connects to a third-party API with an API secret that must be rotated every 30 days, without redeploying code and without downtime.

What should you implement?

- **A.** Store the secret in Secret Manager with a rotation schedule that publishes a Pub/Sub notification to a Cloud Run function, which creates a new secret version. The service reads the latest version (or a mounted secret volume) at runtime.
- **B.** Hard-code the secret and redeploy every 30 days.
- **C.** Store the secret in a plain-text environment variable in the Terraform code.
- **D.** Store the secret in a Cloud Storage bucket with public access prevention.

### Q25 · Domain 3 · Task 3.1 · Single answer

A team of external contractors needs Editor-level access to one development project for a four-week engagement. Access must expire automatically, even if someone forgets to remove it.

What should you do?

- **A.** Grant the role to each contractor individually, and set a calendar reminder to remove it.
- **B.** Create service account keys for the contractors that expire in four weeks.
- **C.** Grant the Owner role, so the contractors aren't blocked during the engagement.
- **D.** Grant the role to a contractors group with an IAM Condition that expires the binding at the engagement's end date and time.

### Q26 · Domain 3 · Task 3.1 · Select TWO

**Case study: Cymbal Retail.** Cymbal is deploying the human-in-the-loop review application and the generative-AI catalog pipeline. Which two measures follow least-privilege practice? (Select TWO.)

- **A.** Protect the review application with IAP, granting access only to the merchandising associates' Google group.
- **B.** Make the review application publicly accessible, to simplify access for associates.
- **C.** Grant associates the Owner role on the catalog project, so they can fix pipeline problems.
- **D.** Run each pipeline component with its own service account, granted only the roles it needs (for example, read supplier files, write drafts, call Agent Platform).
- **E.** Create service account keys and email them to the pipeline developers.

### Q27 · Domain 3 · Task 3.1 · Single answer

The security team must block all outbound traffic from every VPC in the organization to IP addresses on Google's threat-intelligence lists of known malicious hosts. Project administrators must not be able to override the block.

What should you implement?

- **A.** A VPC firewall egress rule in each project, created by each project owner.
- **B.** Cloud Armor policies on all external load balancers.
- **C.** A hierarchical firewall policy at the organization, with an egress deny rule using Cloud NGFW threat-intelligence objects.
- **D.** VPC Flow Logs, reviewed daily.

### Q28 · Domain 3 · Task 3.2 · Single answer

An auditor asks which users read rows from a sensitive BigQuery table over the past 90 days.

Where will you find this information?

- **A.** VPC Flow Logs for the analysts' subnets.
- **B.** Cloud Audit Logs Data Access entries for BigQuery (enabled by default for BigQuery), queried in Logs Explorer or Log Analytics, or in the BigQuery INFORMATION_SCHEMA jobs views.
- **C.** Admin Activity audit logs for the BigQuery dataset.
- **D.** Cloud Monitoring CPU metrics.

### Q29 · Domain 3 · Task 3.1 · Single answer

A genomics company processes highly sensitive patient genomes. Its compliance policy requires data to be encrypted while in use in memory, in addition to at rest and in transit, without rewriting its analysis tools.

What should you recommend?

- **A.** Run the analysis on Confidential VMs (or Confidential GKE Nodes).
- **B.** Enable CMEK on the Persistent Disks only.
- **C.** Use customer-supplied encryption keys for Cloud Storage.
- **D.** Enable VPC Service Controls.

### Q30 · Domain 3 · Task 3.2 · Single answer

A European insurer's analytics data must be stored and processed only within the EU. The team is creating new BigQuery datasets and wants this enforced, not just documented.

What should you do?

- **A.** Create datasets in the US multi-region, and copy results to the EU weekly.
- **B.** Rely on users to choose the right location.
- **C.** Encrypt the datasets with CMEK keys stored in the EU.
- **D.** Create the datasets in an EU location (the EU multi-region or an EU region), and enforce EU-only resource locations with the `gcp.resourceLocations` organization policy on the analytics folder.

### Q31 · Domain 3 · Task 3.1 · Single answer

Production administrators occasionally need elevated permissions for emergencies. The security policy requires that elevation be requested, approved by a second person, time-limited and fully audited, with no standing administrative access.

What should you implement?

- **A.** Permanent Owner grants for all administrators.
- **B.** A shared break-glass password kept in a spreadsheet.
- **C.** Privileged Access Manager entitlements that grant time-bound elevated roles after approval, with all grants audited.
- **D.** Service account keys for administrators, used only in emergencies.

### Q32 · Domain 4 · Task 4.1 · Single answer

**Case study: EHR Healthcare.** EHR wants to roll out new continuous deployment capabilities to update its software at a fast pace, without endangering the 99.9% availability requirement.

What should you recommend?

- **A.** Deploy every commit directly to all production clusters at once.
- **B.** Cloud Build for CI and Cloud Deploy delivery pipelines with canary releases to GKE, automated verification against SLO metrics, approvals for production, and automatic rollback.
- **C.** Monthly change windows with manual deployments.
- **D.** Let each team deploy with its own scripts.

### Q33 · Domain 4 · Task 4.1 · Single answer

After a new back-end service was added behind an external Application Load Balancer, the load balancer returns intermittent 502 errors. The back ends work when accessed directly from inside the VPC.

What's the most likely cause to check first?

- **A.** The Cloud CDN cache is too small.
- **B.** The VM machine type is too small.
- **C.** The project's billing account is suspended.
- **D.** The health check configuration and whether firewall rules allow traffic from Google's health-check and proxy ranges (35.191.0.0/16 and 130.211.0.0/22) to the back ends.

### Q34 · Domain 4 · Task 4.1 · Select TWO

A company has documented a DR plan for its core platform. Which two practices best ensure the plan will work when needed? (Select TWO.)

- **A.** Run scheduled DR drills that fail over to the DR region, and measure the achieved RTO and RPO against targets.
- **B.** Review the DR document annually, without executing it.
- **C.** Regularly restore backups into an isolated environment, and validate data integrity.
- **D.** Skip DR testing, because Google Cloud services are highly available.
- **E.** Test DR once at go-live, and never again.

### Q35 · Domain 4 · Task 4.2 · Single answer

**Case study: Cymbal Retail.** As Cymbal introduces virtual agents that will handle many customer calls, call-center staff are worried about their roles, and managers are unsure how workflows will change.

How should the change be managed?

- **A.** Phase the rollout (starting with a few high-volume intents), communicate the goals and timeline openly, train agents on Agent Assist and on handling escalations, and gather feedback after each phase to adjust.
- **B.** Switch all calls to virtual agents on a single day, without telling staff in advance.
- **C.** Delay any communication until the project is finished.
- **D.** Let each call-center manager decide independently whether to use the new tools.

### Q36 · Domain 4 · Task 4.2 · Single answer

After a year in production, a company's Cloud SQL, GKE Autopilot and Cloud Run usage is steady around the clock and expected to grow. Finance wants lower rates without managing specific machine types.

What should you recommend?

- **A.** Convert all workloads to Spot VMs.
- **B.** Resource-based committed use discounts for specific N2 machine types.
- **C.** Spend-based committed use discounts covering the steady Cloud SQL, GKE Autopilot and Cloud Run spend.
- **D.** No commitments, to keep flexibility.

### Q37 · Domain 4 · Task 4.2 · Single answer

A company needs a customer relationship management system. CRM doesn't differentiate it from competitors, mature SaaS products meet its needs, and its developers are scarce.

What decision best fits Google-recommended practice for workload disposition?

- **A.** Build a custom CRM on GKE, for maximum control.
- **B.** Buy (repurchase) a SaaS CRM, and integrate it with internal systems through APIs or Application Integration.
- **C.** Rehost the old on-premises CRM unchanged, indefinitely.
- **D.** Defer the decision for two years.

### Q38 · Domain 4 · Task 4.1 · Single answer

Every new project must be created in the correct folder, linked to the right billing account, given standard labels, attached to the Shared VPC, covered by a budget alert, and routed to central logging. Today this is done by hand, and steps are frequently missed.

What should you implement?

- **A.** A checklist that project requesters fill in.
- **B.** Let requesters create projects in the console and fix them later.
- **C.** A monthly audit that emails project owners about missing settings.
- **D.** A "project factory" Terraform module run by a pipeline, which creates projects with all standard settings applied automatically.

### Q39 · Domain 5 · Task 5.1 · Single answer

A public API managed by Apigee receives sudden bursts of abusive traffic from some client applications, which overload the back end.

Which Apigee capabilities should you use?

- **A.** Spike Arrest and per-app Quota policies on the API proxies, with Advanced API Security to detect abusive patterns.
- **B.** Remove authentication, to make requests faster.
- **C.** Increase back-end capacity tenfold permanently.
- **D.** Move the API to a different domain name.

### Q40 · Domain 5 · Task 5.1 · Single answer

**Case study: Cymbal Retail.** Before rolling out generative-AI attribute generation to the full catalog, Cymbal wants evidence that output quality is acceptable and that prompt changes don't introduce regressions.

Which testing approach should you recommend?

- **A.** Launch to all products, and rely on customer complaints to find errors.
- **B.** Test only that the API returns HTTP 200.
- **C.** Build an evaluation dataset of products with associate-approved attributes, score each prompt or model version with the Gen AI evaluation service and schema validation in the pipeline, and track human-in-the-loop acceptance rates after launch.
- **D.** Ask one developer to check a few outputs manually.

### Q41 · Domain 5 · Task 5.2 · Single answer

Developers want to run integration tests for code that reads and writes Bigtable on their laptops and in CI, without creating Bigtable instances.

What should they use?

- **A.** A small production Bigtable instance shared by all developers.
- **B.** The Bigtable emulator (`gcloud beta emulators bigtable start`), with the `BIGTABLE_EMULATOR_HOST` environment variable set for the client library.
- **C.** A Cloud SQL instance with a similar schema.
- **D.** BigQuery tables that mimic the Bigtable schema.

### Q42 · Domain 5 · Task 5.2 · Single answer

An engineer regularly works across development, staging and production projects with different identities, and has accidentally run commands against production twice.

What should they do?

- **A.** Use a single default project and change it manually before each command.
- **B.** Remember to add `--project` to every command.
- **C.** Request Owner access to all projects, to avoid permission errors.
- **D.** Create named `gcloud` configurations for each environment (project, account, region), switch explicitly between them, and use service account impersonation with read-only defaults for production.

### Q43 · Domain 5 · Task 5.2 · Single answer

A platform team manages networking, GKE clusters and databases for three environments with Terraform. One state file covers everything, and a routine change to a database once triggered an unexpected plan to recreate the network.

How should the Terraform code be structured?

- **A.** Split the configuration into separate root modules and state files per environment and component (for example, network, cluster, data), with shared reusable modules and remote state in Cloud Storage.
- **B.** Keep one state file, but review plans more carefully.
- **C.** Store the state on each engineer's laptop.
- **D.** Stop using Terraform for networking.

### Q44 · Domain 5 · Task 5.1 · Single answer

A team must make a breaking change to a public REST API that hundreds of external clients use.

What should you advise?

- **A.** Change the existing endpoints immediately, and notify clients afterwards.
- **B.** Silently change the response format, and hope clients adapt.
- **C.** Publish the change as a new major version (for example, `/v2`), keep `/v1` running during a communicated deprecation period, and monitor `/v1` usage before retiring it.
- **D.** Shut down the API until all clients have updated.

### Q45 · Domain 6 · Task 6.2 · Single answer

The operations team wants to be alerted whenever a specific error message, `PAYMENT_PROVIDER_TIMEOUT`, appears more than 50 times in 5 minutes in a service's application logs.

What should you configure?

- **A.** An uptime check on the service.
- **B.** A log-based metric that counts matching log entries, with a Cloud Monitoring alerting policy on its rate.
- **C.** A VPC Flow Logs filter.
- **D.** A daily log export to BigQuery, with a scheduled query.

### Q46 · Domain 6 · Task 6.3 · Single answer

A product team wants to deploy new code to production frequently, but enable new features for customers only when marketing is ready, and turn a feature off instantly if it causes problems, without redeploying.

What should you recommend?

- **A.** Long-lived feature branches merged on launch day.
- **B.** Blue/green deployments for every feature launch.
- **C.** Weekly release trains.
- **D.** Feature flags that decouple deployment from release, controlled per user segment at runtime.

### Q47 · Domain 6 · Task 6.5 · Single answer

A service's 30-day error budget was fully consumed in the first 12 days of the month, mostly because of two faulty releases.

According to SRE practice, what should happen next?

- **A.** Apply the error-budget policy: pause feature releases except reliability fixes, prioritize postmortem actions such as better tests and canary verification, and resume when the budget recovers.
- **B.** Continue releasing features at the same pace.
- **C.** Raise the SLO target, to make the budget larger.
- **D.** Stop monitoring the SLO for the rest of the month.

### Q48 · Domain 6 · Task 6.6 · Select TWO

Before a major product launch, leadership wants evidence that the production platform will remain reliable under stress. Which two activities provide the strongest evidence? (Select TWO.)

- **A.** Rely on Google Cloud's published SLAs.
- **B.** Load-test a production-like environment at about twice the expected peak, and verify autoscaling, quotas and SLO compliance.
- **C.** Test with tiny data volumes in the development environment only.
- **D.** Disable autoscaling during the launch, to keep capacity predictable.
- **E.** Run a controlled chaos experiment, such as removing a zone's capacity, and verify that the service stays within its SLO.

### Q49 · Domain 6 · Task 6.2 · Single answer

A company wants to detect, from the user's perspective, when its public checkout URL becomes unreachable from any major geography, and to be alerted within minutes.

What should you configure?

- **A.** CPU alerts on the back-end VMs.
- **B.** VPC Flow Logs on the back-end subnet.
- **C.** A Cloud Monitoring uptime check from multiple global locations against the checkout URL, with an alerting policy routed to the on-call channel.
- **D.** A monthly manual test from the office.

### Q50 · Domain 6 · Task 6.4 · Single answer

During several past incidents, the on-call team spent the first 30 minutes debugging their own systems before discovering that a Google Cloud service incident in their region was the cause.

What should you set up?

- **A.** Weekly checks of the public status page.
- **B.** Personalized Service Health alerts for incidents that affect the company's projects and regions, routed to the on-call notification channel.
- **C.** Disable alerting during Google Cloud incidents.
- **D.** Open a support case at the start of every incident.
