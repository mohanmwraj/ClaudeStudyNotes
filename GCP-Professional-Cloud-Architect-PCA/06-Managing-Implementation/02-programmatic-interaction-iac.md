# 06/02 · Interacting with Google Cloud Programmatically

**Exam guide:** 5.2 (Cloud Shell Editor, Cloud Code, Cloud Shell Terminal; Google Cloud SDKs: gcloud, gsutil, bq; Cloud Emulators: Bigtable, Spanner, Pub/Sub, Firestore; Infrastructure as Code: Terraform; accessing Google API best practices; Google API client libraries). **Principles:** P6, P12.

---

## 1. Developer environments

| Tool | What it is | Use it when |
|---|---|---|
| **Cloud Shell** (terminal) | Browser-based shell on an ephemeral VM, with **5 GB persistent home directory**, pre-installed `gcloud`, `bq`, `kubectl`, `terraform`, language runtimes; authenticated as you | Quick administration from anywhere, without installing tools |
| **Cloud Shell Editor** | Browser IDE (Code-OSS based) on Cloud Shell, with **Cloud Code** built in | Light development and editing IaC or manifests in the browser |
| **Cloud Code** | IDE extensions (VS Code, JetBrains) for Kubernetes and Cloud Run development: Skaffold-based iterative deploys, debugging, YAML validation, emulators, Secret Manager and API integration, Gemini Code Assist | Day-to-day development on GKE / Cloud Run |
| **Cloud Workstations** | Managed, secure, customizable development environments in your VPC (VPC SC compatible) | Enterprises needing secure, standardized dev environments (no code on laptops) |

Cloud Shell sessions are temporary: anything outside `$HOME` is lost when the VM recycles, and an inactive home directory can eventually be deleted. Don't use Cloud Shell for long-running jobs.

---

## 2. The SDK command-line tools

| Tool | Scope | Notes |
|---|---|---|
| **`gcloud`** | Almost every service | Configurations (`gcloud config configurations`), `--project`, `--impersonate-service-account`, `--format` / `--filter` for scripting, `gcloud auth application-default login` for local ADC |
| **`gcloud storage`** | Cloud Storage | The recommended, faster successor to `gsutil` (parallelism by default) |
| `gsutil` | Cloud Storage (legacy) | Still works and is named in the exam guide. Prefer `gcloud storage` for new scripts |
| **`bq`** | BigQuery | Queries, loads, dataset and table management, `bq query --dry_run` to estimate bytes scanned |
| `kubectl` | Kubernetes / GKE | `gcloud container clusters get-credentials` to configure |
| `cbt` | Bigtable (legacy CLI) | `gcloud bigtable` covers most needs now |

```bash
# Work in a project as a least-privilege SA, without a key
gcloud config set project ehr-prod
gcloud compute instances list \
  --filter="status=RUNNING AND labels.env=prod" \
  --format="table(name,zone.basename(),machineType.basename())" \
  --impersonate-service-account=ops-readonly@ehr-prod.iam.gserviceaccount.com

# Estimate query cost before running it
bq query --use_legacy_sql=false --dry_run \
  'SELECT region, COUNT(*) FROM analytics.events WHERE event_date = "2026-10-01" GROUP BY region'

# Copy objects (gcloud storage parallelizes by default)
gcloud storage cp -r ./exports gs://cymbal-landing/exports/
```

---

## 3. Emulators for local and CI testing

| Emulator | Start | How clients find it |
|---|---|---|
| **Pub/Sub** | `gcloud beta emulators pubsub start` | `PUBSUB_EMULATOR_HOST` (set via `$(gcloud beta emulators pubsub env-init)`) |
| **Firestore** | `gcloud emulators firestore start` | `FIRESTORE_EMULATOR_HOST` |
| **Bigtable** | `gcloud beta emulators bigtable start` | `BIGTABLE_EMULATOR_HOST` |
| **Spanner** | `gcloud emulators spanner start` (or the emulator container) | `SPANNER_EMULATOR_HOST` |
| Datastore | `gcloud beta emulators datastore start` | `DATASTORE_EMULATOR_HOST` |

**Why emulators?** Fast, free, isolated integration tests on a laptop or CI runner, with no shared cloud resources or costs.

**Limits:** emulators don't reproduce production performance, IAM, quotas or every feature. Use them for functional tests, and real (ephemeral) cloud resources for performance and end-to-end tests.

---

## 4. Infrastructure as Code

| Tool | Status and fit |
|---|---|
| **Terraform** (Google provider) | The de-facto standard and the exam's IaC answer. Modules, plan/apply, drift detection. Use the **Cloud Foundation Toolkit / Fabric** modules and the enterprise foundations blueprint |
| **Infrastructure Manager** | Google-managed service that runs Terraform (state, execution, previews) via API, `gcloud` or the console. Replaces Deployment Manager |
| **Config Connector** | Manage Google Cloud resources as Kubernetes custom resources (GitOps with Config Sync) |
| **Cloud Deployment Manager** | **End of support 2026-03-31**. Don't choose it for new work |
| Pulumi, others | Valid, but not the exam's focus |

### Terraform practices the exam rewards

* **Remote state in a Cloud Storage bucket** (with object versioning). The GCS backend provides **state locking**. Restrict access to the state bucket, because state can contain sensitive values.
* **One state per environment and component** (blast-radius control); environments as separate directories or workspaces with variables.
* **Modules** for reusable building blocks (project factory, network, GKE cluster).
* **Plan in CI on every PR; apply from CI on merge**, with a dedicated service account via Workload Identity Federation. No human `apply` from laptops in production.
* **Policy validation** on plans (`gcloud beta terraform vet`, OPA) before apply.
* **Import** existing resources (`terraform import` / import blocks) when adopting IaC for a brownfield estate.

```hcl
terraform {
  backend "gcs" {
    bucket = "acme-tfstate-prod"
    prefix = "network/shared-vpc"
  }
}

resource "google_compute_network" "shared" {
  name                    = "prod-shared-vpc"
  project                 = "net-host-prod"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}
```

---

## 5. Accessing Google APIs: best practices

| Practice | Detail |
|---|---|
| **Authenticate with Application Default Credentials (ADC)** | Client libraries find credentials automatically: an attached service account on Google Cloud, Workload Identity Federation config outside, `gcloud auth application-default login` for local dev. No key files |
| **Least privilege** | Dedicated SAs per workload; narrow roles; IAM Conditions where useful |
| **Retry with exponential backoff and jitter** | For `429 RESOURCE_EXHAUSTED`, `503 UNAVAILABLE` and other transient errors. Client libraries implement this by default for idempotent calls; make your own calls idempotent |
| **Respect quotas** | Monitor quota usage, request increases ahead of launches, set the quota project correctly, spread load |
| **Use regional / private endpoints when required** | Private Google Access or PSC for private routing; regional endpoints for residency where offered |
| **Efficient calls** | Batch requests, pagination, field masks, streaming APIs where available (BigQuery Storage Read/Write API) |
| **Long-running operations** | Many admin calls return an operation; poll or wait for completion rather than assuming success |
| **API keys** | Only for APIs that accept them (for example, Maps and some public APIs). **Restrict** keys by API and by application or referrer. Never a substitute for IAM on Cloud resources |
| **Secure the transport** | TLS by default; VPC SC to restrict API access to perimeters |

---

## 6. Google API client libraries

| Library type | Description | Guidance |
|---|---|---|
| **Cloud Client Libraries** (idiomatic, per service, for example `google-cloud-storage`, `google-cloud-pubsub`) | Recommended. Idiomatic, gRPC where available, built-in retries, auth via ADC | **Default choice** |
| **Google API Client Libraries** (generated, REST-discovery-based) | Older generic libraries covering all Google REST APIs | When no Cloud Client Library exists for an API |
| **Google Gen AI SDK** | Unified SDK for Gemini models (on Agent Platform or the Gemini API) | Gen-AI app development (supersedes older Vertex AI generative modules) |
| Firebase SDKs | Client-side mobile and web access with security rules | Mobile/web apps on Firestore etc. |

---

## 7. Worked scenarios

**A. "Developers' integration tests against a shared Pub/Sub topic interfere with each other and cost money."**
Run the **Pub/Sub emulator** in each developer and CI environment (`PUBSUB_EMULATOR_HOST`).

**B. "A batch job calling the Translation API fails intermittently with 429 errors during peaks."**
Exponential backoff with jitter (the client library's retry settings), smoothing the request rate (Cloud Tasks for rate-limited dispatch), and requesting a quota increase if sustained demand exceeds quota.

**C. "Infrastructure was created by hand over three years; the company wants it in IaC without recreating resources."**
Terraform with **import** (import blocks), modules for standardization, remote state in GCS, CI-driven plan/apply. Optionally bulk-export existing resources to Terraform (`gcloud beta resource-config bulk-export --resource-format=terraform`) as a starting point.

**D. "An on-premises application must call BigQuery without storing a service account key."**
Workload Identity Federation (OIDC or SAML from the on-premises IdP, or X.509 certificates) with a credential configuration file consumed by ADC. Route privately via Interconnect plus a PSC endpoint for Google APIs.

---

## References

* Cloud Shell: <https://cloud.google.com/shell/docs/how-cloud-shell-works>
* Cloud Code: <https://cloud.google.com/code/docs>
* gcloud storage: <https://cloud.google.com/storage/docs/discover-object-storage-gcloud>
* Pub/Sub emulator: <https://cloud.google.com/pubsub/docs/emulator>
* Spanner emulator: <https://cloud.google.com/spanner/docs/emulator>
* Terraform on Google Cloud best practices: <https://cloud.google.com/docs/terraform/best-practices/general-style-structure>
* Application Default Credentials: <https://cloud.google.com/docs/authentication/application-default-credentials>
* Retry strategy: <https://cloud.google.com/storage/docs/retry-strategy>
* Client libraries explained: <https://cloud.google.com/apis/docs/client-libraries-explained>
