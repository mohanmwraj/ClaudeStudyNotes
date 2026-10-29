# Domain 5 Drill · Managing Implementation (20 questions)

Original exam-style questions for objectives 5.1–5.2 (~12.5% of the exam). The notes for this domain are in [06-Managing-Implementation](../06-Managing-Implementation/).

---

### Q1 · Task 5.1 · Single answer

A health-data company wants dozens of insurance partners to integrate with its APIs. Partners must be able to sign up and get credentials through self-service. The company needs per-partner rate limits, usage analytics and, next year, paid API tiers.

Which product should you recommend?

- **A.** API Gateway in front of Cloud Run.
- **B.** An internal Application Load Balancer with IAP.
- **C.** Apigee, with API products, a developer portal, quota policies, analytics and monetization.
- **D.** Cloud Endpoints, with API keys distributed manually by email.

<details><summary>Answer</summary>

**Answer: C**

**Why (P8, P5):** Partner self-service, per-partner quotas, analytics and monetization are full-lifecycle API management features, which is Apigee's purpose.

- **A** — wrong: lightweight. It has no developer portal or monetization.
- **B** — wrong: internal access control for employees, not partner API management.
- **C** — correct: covers every stated need, now and next year.
- **D** — wrong: manual onboarding contradicts self-service, and analytics and monetization are minimal.

**Reference:** <https://cloud.google.com/apigee/docs/api-platform/get-started/what-apigee>

</details>

### Q2 · Task 5.1 · Single answer

A small team exposes three Cloud Run functions to its own mobile app. It needs API-key validation and basic quotas, with the least operational overhead and cost. It has no partner ecosystem.

What should the team use?

- **A.** API Gateway, with an OpenAPI specification that defines API key requirements and quotas.
- **B.** Apigee hybrid, with a runtime installed in an on-premises data center.
- **C.** A GKE Ingress, with a custom authentication sidecar the team writes itself.
- **D.** Cloud CDN in front of the functions.

<details><summary>Answer</summary>

**Answer: A**

**Why (P5, P9):** Simple API front doors for serverless back ends are API Gateway's niche. It's fully managed and inexpensive, with no portal or monetization overhead.

- **A** — correct: just enough API management, serverless.
- **B** — wrong: heavy hybrid infrastructure for three functions.
- **C** — wrong: custom code and a cluster to run.
- **D** — wrong: caching isn't authentication or quota management.

**Reference:** <https://cloud.google.com/api-gateway/docs/about-api-gateway>

</details>

### Q3 · Task 5.1 · Single answer

A logistics company exposes a legacy SOAP service that partners must consume as a REST/JSON API. The back end will be rewritten over the next year, and partners must not have to change their integrations when it's replaced.

What should you recommend?

- **A.** Ask every partner to rewrite their integration for SOAP now, and again after the rewrite.
- **B.** Expose the SOAP endpoint directly on the internet.
- **C.** Write a separate Cloud Run function per partner that translates their calls.
- **D.** Put an Apigee API proxy in front of the service, with SOAP-to-REST mediation, then switch the proxy's target to the new back end when it's ready.

<details><summary>Answer</summary>

**Answer: D**

**Why (P8, P15):** An API facade decouples consumers from the back end. Mediation handles protocol translation now, and the strangler pattern lets you swap implementations later without partner changes.

- **A** — wrong: imposes the cost of change on partners, twice.
- **B** — wrong: wrong protocol, and the back end is exposed.
- **C** — wrong: duplicated, per-partner custom code.
- **D** — correct: one stable contract, with the back end free to evolve.

**Reference:** <https://cloud.google.com/apigee/docs/api-platform/get-started/what-apigee>

</details>

### Q4 · Task 5.1 · Single answer

Microservice teams deploy independently. Twice this month, a provider team changed a response field and broke a consumer service in production, even though each team's unit tests passed.

Which testing practice should you recommend to catch this before deployment?

- **A.** Larger load tests before each release.
- **B.** Consumer-driven contract tests that run in the provider's CI pipeline against the consumers' published expectations.
- **C.** More unit tests inside the provider service.
- **D.** Monthly chaos experiments in production.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12):** The defect is an interface incompatibility between services. Contract tests verify that a provider still satisfies what consumers depend on, before it deploys.

- **A** — wrong: load tests find capacity problems, not contract breaks.
- **B** — correct: catches breaking API changes in CI.
- **C** — wrong: unit tests inside the provider don't know about consumers' expectations.
- **D** — wrong: chaos experiments test resilience, not API compatibility.

**Reference:** <https://cloud.google.com/architecture/application-deployment-and-testing-strategies>

</details>

### Q5 · Task 5.1 · Select TWO

A bank must run its API gateway runtime inside its own data centers, next to on-premises back ends, for latency and data-residency reasons. It also wants central management, consistent security policies and analytics across all APIs.

Which two recommendations meet these needs? (Select TWO.)

- **A.** Deploy Apigee hybrid, with the runtime plane in the bank's data centers and the management plane in Google Cloud.
- **B.** Run a different API gateway product in each data center, each configured separately.
- **C.** Expose the on-premises back ends directly with public IP addresses.
- **D.** Put Cloud CDN in front of the back ends.
- **E.** Apply OAuth 2.0 and quota policies centrally in Apigee API proxies, so every API enforces them the same way.

<details><summary>Answer</summary>

**Answer: A, E**

**Why (P14, P12):** Apigee hybrid keeps the request path on-premises while management, policy and analytics stay central. That gives consistent enforcement without moving data.

- **A** — correct: runtime where the data must stay, with central control.
- **B** — wrong: inconsistent policies and fragmented analytics.
- **C** — wrong: exposes back ends, with no management layer.
- **D** — wrong: caching doesn't provide API management.
- **E** — correct: uniform security and traffic policies across the APIs.

**Reference:** <https://cloud.google.com/apigee/docs/hybrid/latest/what-is-hybrid>

</details>

### Q6 · Task 5.1 · Single answer

A company wants to move from Oracle Database to a PostgreSQL-compatible managed database on Google Cloud, to remove license costs. It wants help converting schemas and stored procedures, and minimal downtime during cutover.

Which tool should you recommend?

- **A.** Storage Transfer Service.
- **B.** Transfer Appliance.
- **C.** Database Migration Service for heterogeneous migration, using a conversion workspace for schema and code conversion, then continuous data migration (CDC) to Cloud SQL for PostgreSQL or AlloyDB.
- **D.** Datastream, replicating the Oracle tables into BigQuery.

<details><summary>Answer</summary>

**Answer: C**

**Why (P15):** Heterogeneous database migration needs schema and code conversion plus continuous replication for a short cutover. DMS provides both.

- **A** — wrong: moves files and objects, not databases.
- **B** — wrong: offline bulk data shipping.
- **C** — correct: conversion, then CDC, then cutover.
- **D** — wrong: replicates for analytics into BigQuery, not an OLTP migration.

**Reference:** <https://cloud.google.com/database-migration/docs/overview>

</details>

### Q7 · Task 5.1 · Single answer

Before migrating, a company needs an inventory of 2,000 servers across VMware and physical hosts, with utilization data, total-cost-of-ownership estimates and rightsizing recommendations for Google Cloud.

Which tool should you use?

- **A.** Migration Center, using its discovery client or imported inventory data to generate TCO and rightsizing reports.
- **B.** Spreadsheets maintained by each application owner.
- **C.** Recommender rightsizing recommendations.
- **D.** Cloud Asset Inventory.

<details><summary>Answer</summary>

**Answer: A**

**Why (P15):** Assessment of the source estate (discovery, utilization, TCO, target sizing) is Migration Center's role.

- **A** — correct: purpose-built assessment and planning.
- **B** — wrong: manual, inconsistent and without utilization data.
- **C** — wrong: Recommender analyzes resources already in Google Cloud.
- **D** — wrong: inventories Google Cloud assets, not on-premises servers.

**Reference:** <https://cloud.google.com/migration-center/docs/migration-center-overview>

</details>

### Q8 · Task 5.1 · Single answer

Developers new to Google Cloud spend days writing Terraform for a standard three-tier architecture and trying to understand existing configurations. The platform lead wants to speed them up without weakening change control.

What should you recommend?

- **A.** Let an AI assistant apply its generated changes directly to production.
- **B.** Ban AI tools entirely.
- **C.** Copy configurations from public blog posts.
- **D.** Use Gemini Cloud Assist to draft architectures and Terraform and to explain existing resources, with every generated change going through pull-request review and the CI/CD pipeline.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12, P5):** AI assistance speeds up design, IaC authoring and understanding. The normal review, testing and pipeline controls still govern what reaches production.

- **A** — wrong: unreviewed changes in production.
- **B** — wrong: forgoes a productivity gain that can be governed.
- **C** — wrong: unvetted and often outdated.
- **D** — correct: acceleration plus governance.

**Reference:** <https://cloud.google.com/gemini/docs/cloud-assist/overview>

</details>

### Q9 · Task 5.1 · Single answer

A team builds a separate container image for each environment, because database connection strings and API keys are baked into each image. Promotions are slow, and secrets have leaked through image registries.

What should you advise?

- **A.** Keep separate images per environment, and restrict registry access.
- **B.** Build one image, supply environment configuration at deploy time, and load secrets at runtime from Secret Manager with per-service IAM.
- **C.** Encrypt the secrets inside each image with a key stored in the same image.
- **D.** Maintain a separate Git branch per environment containing the secrets.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12, P11):** Immutable artifacts are promoted unchanged, while configuration and secrets are injected per environment from managed, access-controlled stores.

- **A** — wrong: keeps rebuilds and secrets in images.
- **B** — correct: one artifact, externalized configuration, secrets managed properly.
- **C** — wrong: a key stored next to the ciphertext protects nothing.
- **D** — wrong: secrets in source control.

**Reference:** <https://cloud.google.com/secret-manager/docs/overview>

</details>

### Q10 · Task 5.1 · Single answer

A ticketing company must verify that its platform handles 200,000 concurrent users before a major concert on-sale. Its previous tests ran JMeter on one laptop.

What should you recommend?

- **A.** Run JMeter on a larger laptop.
- **B.** Run a script in a loop in Cloud Shell.
- **C.** Run distributed load tests with load-generator workers (for example, Locust) on GKE, scaled out to the required concurrency, against a production-like environment.
- **D.** Ask a sample of customers to use the site at the same time.

<details><summary>Answer</summary>

**Answer: C**

**Why (P13, P3):** Realistic high concurrency needs horizontally scaled load generators. GKE scales the workers on demand.

- **A** — wrong: one machine can't generate 200,000 concurrent users.
- **B** — wrong: Cloud Shell is a small, ephemeral VM.
- **C** — correct: Google's reference pattern for distributed load testing.
- **D** — wrong: uncontrolled, unrepeatable and too small.

**Reference:** <https://cloud.google.com/architecture/distributed-load-testing-using-gke>

</details>

### Q11 · Task 5.2 · Single answer

A developer is building a service that uses Firestore. They want fast, offline, cost-free local tests that don't touch shared cloud data.

What should they use?

- **A.** The Firestore emulator, started with `gcloud emulators firestore start`, with the client libraries pointed at it through the `FIRESTORE_EMULATOR_HOST` environment variable.
- **B.** The production Firestore database, with a test collection.
- **C.** The BigQuery sandbox.
- **D.** A Memorystore instance as a stand-in for Firestore.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12):** Emulators provide local, isolated, free instances of supported services, and the client libraries detect them through environment variables.

- **A** — correct: local Firestore semantics with no cloud resources.
- **B** — wrong: shared and costly, and risks production data.
- **C** — wrong: a different service and data model.
- **D** — wrong: a different API, so tests wouldn't be valid.

**Reference:** <https://cloud.google.com/sdk/gcloud/reference/emulators/firestore/start>

</details>

### Q12 · Task 5.2 · Single answer

Fifteen engineers apply Terraform to shared infrastructure from their laptops. State files live on individual machines, and concurrent applies have corrupted infrastructure twice.

What should you change?

- **A.** Commit the state file to the Git repository after each apply.
- **B.** Email the latest state file to the team after each change.
- **C.** Have each engineer keep a separate state file for their own changes.
- **D.** Store state remotely in a Cloud Storage backend (with versioning), which provides state locking, and run plan and apply from a CI pipeline with a dedicated service account.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12):** Shared remote state with locking prevents concurrent corruption. Pipeline-driven applies add review, consistency and least-privilege credentials.

- **A** — wrong: no locking, merge conflicts, and secrets in Git.
- **B** — wrong: no locking or source of truth.
- **C** — wrong: divergent views of the same infrastructure, which is worse.
- **D** — correct: remote state with locking plus controlled execution.

**Reference:** <https://cloud.google.com/docs/terraform/best-practices/general-style-structure>

</details>

### Q13 · Task 5.2 · Single answer

A nightly batch job calls a Google Cloud API thousands of times per minute. During peaks it receives `429 RESOURCE_EXHAUSTED` errors, and the job fails.

What should you recommend?

- **A.** Retry failed calls immediately in a tight loop until they succeed.
- **B.** Retry with exponential backoff and jitter (the client library's retry settings), smooth the request rate, and request a quota increase if sustained demand exceeds the quota.
- **C.** Switch to an API key, to bypass quotas.
- **D.** Ignore the errors and skip the failed records.

<details><summary>Answer</summary>

**Answer: B**

**Why (P8):** 429s signal rate limiting. Backoff with jitter spreads retries and recovers gracefully, and quota increases address genuine sustained demand.

- **A** — wrong: hammers the API and worsens throttling.
- **B** — correct: Google's documented retry practice, plus capacity planning.
- **C** — wrong: API keys don't bypass quotas, and many APIs don't accept them.
- **D** — wrong: silent data loss.

**Reference:** <https://cloud.google.com/storage/docs/retry-strategy>

</details>

### Q14 · Task 5.2 · Single answer

A Cloud Run service must query BigQuery. A developer proposes downloading a service account key and bundling it with the container.

What's the recommended approach?

- **A.** Bundle the key in the container image, but encrypt the image.
- **B.** Create an API key for BigQuery and pass it as an environment variable.
- **C.** Attach a dedicated, least-privilege service account to the Cloud Run service, and use a Cloud Client Library, which obtains credentials automatically through Application Default Credentials.
- **D.** Use the developer's own OAuth token, refreshed manually.

<details><summary>Answer</summary>

**Answer: C**

**Why (P6):** On Google Cloud, attached service accounts provide short-lived credentials through the metadata server. Application Default Credentials picks them up with no key files.

- **A** — wrong: still a long-lived key, and images get copied and leaked.
- **B** — wrong: API keys don't authorize BigQuery data access.
- **C** — correct: keyless, least privilege, automatic.
- **D** — wrong: personal credentials in production that will expire.

**Reference:** <https://cloud.google.com/docs/authentication/application-default-credentials>

</details>

### Q15 · Task 5.2 · Select THREE

An engineer needs to (1) list running production VMs as a readable table, (2) find out how many bytes a BigQuery query would scan before running it, and (3) copy a 2 TB directory to Cloud Storage as fast as possible.

Which three commands should the engineer use? (Select THREE.)

- **A.** `gcloud compute instances list --filter="labels.env=prod AND status=RUNNING" --format="table(name,zone.basename())"`
- **B.** `bq query --use_legacy_sql=true 'SELECT * FROM dataset.table'`
- **C.** `bq query --use_legacy_sql=false --dry_run '<query>'`
- **D.** `gcloud storage cp -r ./data gs://bucket/data/`
- **E.** `gsutil acl ch -u AllUsers:R gs://bucket`
- **F.** `kubectl get vms --all-namespaces`

<details><summary>Answer</summary>

**Answer: A, C, D**

**Why (P5):** Use the right SDK tool for each job. `--filter` and `--format` handle readable listings, `--dry_run` estimates bytes without running the query, and `gcloud storage` parallelizes large copies by default.

- **A** — correct: filtered, formatted VM listing.
- **B** — wrong: actually runs a full-scan query, which is the cost it should estimate first.
- **C** — correct: reports bytes processed without executing.
- **D** — correct: fast, parallel upload.
- **E** — wrong: makes the bucket public. It's unrelated and dangerous.
- **F** — wrong: kubectl manages Kubernetes resources, not Compute Engine VMs.

**Reference:** <https://cloud.google.com/bigquery/docs/running-queries>

</details>

### Q16 · Task 5.2 · Single answer

An engineer plans to run a 10-hour data-migration script from Cloud Shell, keeping the browser tab open overnight.

What should you advise?

- **A.** It's fine, as long as the tab stays open.
- **B.** Use the Cloud Shell Editor instead of the terminal.
- **C.** Run the script inside `tmux` in Cloud Shell, so it survives disconnects.
- **D.** Run the script as a Cloud Run job, a Batch job or on a Compute Engine VM, because Cloud Shell sessions are temporary and can end during long runs.

<details><summary>Answer</summary>

**Answer: D**

**Why (P5, P3):** Cloud Shell is an ephemeral, interactive environment, not a job runner. Long-running work belongs on compute designed for it, with retries and logging.

- **A** — wrong: sessions can still terminate, and only `$HOME` persists.
- **B** — wrong: the same ephemeral environment.
- **C** — wrong: `tmux` doesn't keep the Cloud Shell VM alive when the session is recycled.
- **D** — correct: durable execution with logging and retries.

**Reference:** <https://cloud.google.com/shell/docs/how-cloud-shell-works>

</details>

### Q17 · Task 5.2 · Single answer

Over three years, a team created hundreds of Google Cloud resources by hand. It now wants to manage them with Terraform without deleting or recreating anything.

What should it do?

- **A.** Bring the resources under Terraform management with import (import blocks or `terraform import`), optionally starting from a bulk export of existing resources to Terraform, then manage all changes through code.
- **B.** Delete the resources and recreate them from new Terraform code.
- **C.** Write new Cloud Deployment Manager templates for the resources.
- **D.** Document the current configuration in a wiki, and keep making changes in the console.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12):** Import adopts existing resources into Terraform state without disruption. Bulk export accelerates writing the initial code.

- **A** — correct: no downtime, and the resources become code.
- **B** — wrong: causes outages and data loss.
- **C** — wrong: Deployment Manager reached end of support on 2026-03-31.
- **D** — wrong: not infrastructure as code.

**Reference:** <https://cloud.google.com/docs/terraform/resource-management/import>

</details>

### Q18 · Task 5.2 · Single answer

A team still deploys infrastructure with Cloud Deployment Manager templates written in 2019, and wants to keep using a Google-managed deployment service.

What should you recommend?

- **A.** Continue using Deployment Manager unchanged.
- **B.** Migrate the templates to Terraform, deployed through Infrastructure Manager (Google's managed Terraform service) or a CI pipeline.
- **C.** Replace the templates with shell scripts run from Cloud Shell.
- **D.** Make future changes manually in the console.

<details><summary>Answer</summary>

**Answer: B**

**Why (P12):** Deployment Manager reached end of support on 2026-03-31. Infrastructure Manager is the managed successor, running standard Terraform.

- **A** — wrong: the service is unsupported.
- **B** — correct: the managed, supported path.
- **C** — wrong: imperative scripts aren't declarative IaC.
- **D** — wrong: no automation or review.

**Reference:** <https://cloud.google.com/infrastructure-manager/docs/overview>

</details>

### Q19 · Task 5.2 · Single answer

A developer is writing a new Python service that publishes messages to Pub/Sub, and asks which library to use.

What should you recommend?

- **A.** Raw HTTP requests, with hand-written OAuth token handling.
- **B.** The older, generic discovery-based Google API Client Library.
- **C.** The Cloud Client Library for Pub/Sub (`google-cloud-pubsub`), which is idiomatic, uses gRPC, and has built-in batching, retries and Application Default Credentials.
- **D.** Calling `gcloud pubsub topics publish` through a subprocess for each message.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5):** Cloud Client Libraries are Google's recommended libraries. They're idiomatic and performant, with retries and authentication built in.

- **A** — wrong: reimplements authentication, retries and batching.
- **B** — wrong: generic and older; use it only when no Cloud Client Library exists.
- **C** — correct: the recommended library.
- **D** — wrong: very slow per message, and fragile.

**Reference:** <https://cloud.google.com/apis/docs/client-libraries-explained>

</details>

### Q20 · Task 5.2 · Select TWO

An on-premises application must call Google Cloud APIs. Security requires no long-lived credentials on the servers, and API traffic must use the private Interconnect connection rather than the internet.

Which two actions should you take? (Select TWO.)

- **A.** Put an API key in the request URL.
- **B.** Configure Workload Identity Federation (using the on-premises OIDC or SAML identity provider, or X.509 certificates), and give the application a credential configuration file used through Application Default Credentials.
- **C.** Allow the application to reach Google APIs only over the public internet.
- **D.** Create a Private Service Connect endpoint for Google APIs in the VPC, advertise its IP address to on-premises over the Interconnect, and configure DNS to resolve Google API names to it.
- **E.** Store a service account key file on each server, readable only by root.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P6, P14):** Workload Identity Federation removes keys by exchanging the on-premises identity for short-lived tokens. A PSC endpoint for Google APIs gives on-premises clients a private, internal path over Interconnect.

- **A** — wrong: API keys leak in URLs and don't authorize most Cloud APIs.
- **B** — correct: keyless, short-lived authentication.
- **C** — wrong: violates the private-path requirement.
- **D** — correct: private API access reachable from on-premises.
- **E** — wrong: still a long-lived key.

**Reference:** <https://cloud.google.com/iam/docs/workload-identity-federation>

</details>
