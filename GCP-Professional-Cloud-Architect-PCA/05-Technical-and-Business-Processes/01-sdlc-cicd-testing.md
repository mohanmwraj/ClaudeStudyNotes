# 05/01 · SDLC, CI/CD, Testing and Service Provisioning

**Exam guide:** 4.1 (software development lifecycle; CI/CD; testing and validation of software and infrastructure; service catalog and provisioning). Also 6.3 (release management) and 5.1 (testing frameworks). **Principles:** P12, P13.

---

## 1. The SDLC the exam assumes

Google's materials assume a **DevOps / SRE** lifecycle:

```text
Plan → Code (trunk-based, small changes, code review)
     → Build (CI: compile, unit test, scan, package immutable artifact)
     → Test (integration, contract, security, performance in ephemeral envs)
     → Release (CD: progressive delivery with automated verification + approvals)
     → Operate (observability, SLOs, incident response)
     → Learn (postmortems, error-budget policy) → back to Plan
```

**DORA's four key metrics** are the standard "how do we measure delivery performance?" answer:

| Metric | Good direction |
|---|---|
| **Deployment frequency** | Higher (on demand, many times a day) |
| **Lead time for changes** (commit → production) | Shorter |
| **Change failure rate** | Lower |
| **Time to restore service** (failed deployment recovery time) | Shorter |

Elite performers improve speed **and** stability together, through automation, small batches and fast feedback. An option that trades stability for speed, or the reverse, is usually not the best answer.

---

## 2. CI/CD on Google Cloud

| Stage | Google Cloud service | Notes |
|---|---|---|
| Source | GitHub, GitLab, Bitbucket (via **Developer Connect**), **Secure Source Manager** | Cloud Source Repositories is closed to new customers |
| Build (CI) | **Cloud Build** | Serverless builds; triggers on push, PR or tag; **private pools** (in your VPC, for private dependencies); build provenance (SLSA); approvals for manual gates |
| Artifacts | **Artifact Registry** | Containers, language packages (Maven, npm, Python), OS packages; vulnerability scanning; regional repos; remote and virtual repos |
| Deploy (CD) | **Cloud Deploy** | Managed delivery pipelines: **targets** (GKE, Cloud Run, GKE fleets via Config Sync, custom targets) with **promotion**, **approvals**, **canary** strategies, **deploy verification**, automation, **rollback**; uses Skaffold under the hood |
| GitOps for clusters | **Config Sync** | Cluster configuration and policies from Git, across a fleet |
| Infrastructure | Terraform via Cloud Build or **Infrastructure Manager** | Plan on PR, apply on merge, policy checks |
| External CI (GitHub Actions, GitLab CI, Jenkins) | Use **Workload Identity Federation**, no SA keys | Common real-world pattern; fully acceptable on the exam |

### Reference pipeline (container app)

```text
PR opened ──▶ Cloud Build: lint, unit tests, SAST, build image, scan (Artifact Analysis)
merge     ──▶ Cloud Build: build once, push digest to Artifact Registry, provenance + attestation
          ──▶ Cloud Deploy release: dev (auto) → staging (integration + load tests, verify)
          ──▶ approval (change owner) → prod canary 10% → verify SLO metrics → 100%
          ──▶ automatic rollback on verification failure
```

**Principles behind the pipeline**

* **Build once, promote the same artifact** (by image digest) through environments. Never rebuild per environment.
* **Environment configuration is separate from the artifact** (config maps, secrets from Secret Manager, Skaffold profiles).
* **Every change is traceable** from commit to build to release to deployment (audit and SoD).
* **Fast feedback**: run unit tests and scans on PRs, and slower tests on merge.

---

## 3. Testing and validation

### Software tests (which test catches which defect?)

| Test type | Catches | Where in the pipeline |
|---|---|---|
| **Unit** | Logic errors in a function or class | Every commit/PR. Fast |
| **Integration** | Broken interactions with real dependencies (DB, Pub/Sub, APIs). Use **emulators** locally (Pub/Sub, Firestore, Spanner, Bigtable) | After build, in CI |
| **Contract** | API producer and consumer incompatibility | CI for microservices / partner APIs |
| **End-to-end / UI** | User-journey failures | Staging |
| **Load / performance** | Latency or throughput regressions, capacity limits, autoscaling behavior | Staging or a pre-prod copy with realistic data. Before peak events |
| **Security** | SAST (code), dependency scanning (Artifact Analysis), DAST (**Web Security Scanner**), penetration testing | CI (SAST/SCA); staging (DAST); periodic pen tests |
| **Canary analysis** | Problems only visible with real traffic | Production, on a small slice with automated SLO checks |
| **Chaos / resilience** | Weak failure handling | Pre-prod and controlled production experiments ([07/02](../07-Operations-Excellence/02-sre-reliability-release-management.md)) |

### Infrastructure tests

| Check | Tool / approach |
|---|---|
| Syntax and plan correctness | `terraform fmt`, `terraform validate`, `terraform plan` in the PR |
| Policy compliance before apply | Policy-as-code on the plan: `gcloud beta terraform vet` (Policy Library / constraint templates), OPA, custom checks |
| Drift | Scheduled plans that report drift; Config Sync for Kubernetes |
| Runtime configuration compliance | Security Command Center findings, org policies, Policy Controller |
| Ephemeral environments | Spin up per-PR environments from modules, test, destroy |
| DR validation | Scheduled failover tests; restore-from-backup tests |

---

## 4. Service catalog and self-service provisioning

Enterprises want teams to provision **approved, compliant building blocks** quickly without a ticket queue. Patterns on Google Cloud:

| Approach | What it gives |
|---|---|
| **Terraform modules** (private registry or Git) + **Infrastructure Manager** / CI pipelines | Versioned, reviewed building blocks (a "project factory", a standard Cloud Run service, a Cloud SQL instance with HA and backups) |
| **Project factory** pattern | New projects created by automation with the right folder, billing, IAM groups, APIs, budgets, logging and network attachment |
| **Application Design Center** | Design application infrastructure from templates (with Gemini Cloud Assist), deploy to environments, organize in **App Hub** applications |
| **Google Cloud Marketplace** (with private offers and catalog controls) | Third-party and partner solutions procured and deployed consistently |
| **Org policies + custom constraints** | Guardrails so self-service can't create non-compliant resources |
| **Config Connector** | Kubernetes-native provisioning of Google Cloud resources (platform teams using GitOps) |

**Exam angle:** "Teams wait weeks for infrastructure; security needs consistency" → **self-service from approved IaC modules (catalog) with automated guardrails**, not more manual review boards and not unrestricted console access.

---

## 5. Worked scenarios

**A. "Releases happen monthly with frequent rollbacks; leadership wants faster, safer releases."**
CI with automated tests on every change; build-once artifacts; Cloud Deploy with canary and automated verification; small batch sizes; track the DORA metrics.

**B. "The integration tests are flaky and slow because they use a shared staging Pub/Sub topic and Spanner database."**
Use the **Pub/Sub and Spanner emulators** in CI for integration tests (fast, isolated), plus ephemeral test projects for full end-to-end runs.

**C. "Terraform changes occasionally open firewall rules to the internet."**
A policy-as-code check on `terraform plan` in CI (block 0.0.0.0/0 ingress) plus a hierarchical firewall policy and org policy guardrails at runtime (defense in depth).

**D. "Developers in GitHub Actions deploy to Cloud Run using a JSON key stored as a secret."**
Replace the key with Workload Identity Federation (a GitHub OIDC provider with an attribute condition on repo and branch), and disable key creation via org policy.

---

## References

* DORA research (four keys): <https://dora.dev/>
* Cloud Build overview: <https://cloud.google.com/build/docs/overview>
* Cloud Deploy overview: <https://cloud.google.com/deploy/docs/overview>
* Artifact Registry overview: <https://cloud.google.com/artifact-registry/docs/overview>
* Infrastructure Manager: <https://cloud.google.com/infrastructure-manager/docs/overview>
* Validate Terraform against policies: <https://cloud.google.com/docs/terraform/policy-validation>
* App Hub overview: <https://cloud.google.com/app-hub/docs/overview>
