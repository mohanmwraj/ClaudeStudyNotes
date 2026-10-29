# 04/01 · IAM, Identities and the Resource Hierarchy

**Exam guide:** 3.1 (IAM, resource hierarchy, separation of duties, organization policy, service account impersonation, Workload Identity Federation). **Principles:** P6, P7.

---

## 1. The resource hierarchy

```text
Organization (example.com)            ← org policies, org-level IAM, hierarchical firewall, SCC
 ├── Folder: Production               ← environment-wide policy (e.g., resource locations, no external IPs)
 │    ├── Folder: Retail BU
 │    │    ├── Project: cymbal-catalog-prod     ← billing, quotas, APIs, most IAM grants
 │    │    └── Project: cymbal-search-prod
 │    └── Folder: Shared Services
 │         ├── Project: net-host-prod (Shared VPC host)
 │         └── Project: logging-prod (central log buckets)
 ├── Folder: Non-production
 └── Folder: Sandbox                  ← looser policies, budgets, auto-cleanup
```

* **Policies inherit downward.** IAM allow policies are the **union** of all levels (additive). A permission granted at a folder can't be removed at a project; you'd need a **deny policy**.
* The **project** is the unit of billing attribution, quota, API enablement and the default IAM boundary.
* Common folder strategies: **by environment** (prod / non-prod / sandbox) at the top level, which makes environment-wide policy easy, then business unit or team below. Choose by **who sets policy** (P7).
* Every resource belongs to exactly one project; projects can move between folders, and inherited policies change when they do.

---

## 2. Identities (principals)

| Principal | Use |
|---|---|
| **Google Account / Cloud Identity / Workspace user** | Humans. Managed in Cloud Identity or Workspace, ideally synced or federated from the corporate IdP |
| **Google group** | **The recommended way to grant roles**: grant to groups, manage membership in the IdP |
| **Service account** | Workloads (VMs, Cloud Run, GKE workloads via federation, pipelines) |
| **Workforce Identity Federation principals** | Humans authenticated by an external IdP (Entra ID, Okta, AD FS, any OIDC/SAML 2.0 IdP) **without syncing users** into Cloud Identity |
| **Workload Identity Federation principals** | Workloads outside Google Cloud (AWS, Azure, on-premises with OIDC/SAML/X.509, GitHub Actions, GitLab) exchanging their native credentials for short-lived Google tokens |
| `allAuthenticatedUsers` / `allUsers` | Public access. Almost never correct for business data (blocked by domain-restricted sharing org policy) |

### Integrating a corporate directory (EHR's Active Directory, Altostrat's third-party IdPs)

| Option | How | Choose when |
|---|---|---|
| **Cloud Identity + Google Cloud Directory Sync (GCDS) + SAML SSO** | GCDS syncs users and groups one-way from AD/LDAP; authentication via SSO to AD FS / Entra ID | Classic, widely tested answer. Users and groups exist in Google, which suits Workspace or other Google services too |
| **Cloud Identity + Entra ID provisioning (SCIM) + SSO** | Entra ID provisions users and groups and acts as IdP | Microsoft Entra-centric organizations |
| **Workforce Identity Federation** | No user sync; Google Cloud trusts the external IdP directly; attribute mapping to IAM principals | Avoid duplicating identities; console and gcloud access for federated users |
| **Managed Service for Microsoft Active Directory** | A real managed AD domain in Google Cloud (trusts to on-premises AD) | **Workloads** that need AD: domain-joined Windows VMs, Kerberos/LDAP apps. It's not for Google Cloud console sign-in |

**Trap:** "Use Managed Microsoft AD so employees can log in to the Google Cloud console." Console sign-in uses Cloud Identity SSO or Workforce Identity Federation.

---

## 3. Roles and policies

| Role type | Examples | Guidance |
|---|---|---|
| **Basic** | Owner, Editor, Viewer | **Avoid in production**: too broad. Editor can modify almost everything |
| **Predefined** | `roles/storage.objectViewer`, `roles/cloudsql.client`, `roles/compute.networkUser` | **Default choice.** Maintained by Google as services evolve |
| **Custom** | Your own permission set | When predefined roles are too broad. You maintain them; they can't include every permission; org- or project-level |

**Policy types (how access is decided)**

| Policy | What it does | Attach at |
|---|---|---|
| **Allow policy** (role bindings) | Grants roles to principals, optionally with **IAM Conditions** (time, resource name/tag, request attributes) | Org, folder, project, many resources |
| **Deny policy** | Explicitly denies listed permissions to principals (with exceptions); evaluated **before** allow | Org, folder, project |
| **Principal access boundary (PAB)** | Limits which resources a set of principals is *eligible* to access, regardless of allows | Bound to principal sets (for example, all identities in a workforce pool) |
| **Organization policy** | Constrains resource *configuration* (not who can act) | Org, folder, project |

**Evaluation summary:**

1. A request is denied if any deny policy matches (unless an exception applies).
2. It's denied if a PAB excludes the resource.
3. It's allowed if any inherited allow binding grants the permission and its conditions are true.
4. Otherwise it's denied.

**IAM Conditions** examples:

* Time-bound access: `request.time < timestamp("2026-12-31T00:00:00Z")`.
* Resource-name prefix: only buckets starting `projects/_/buckets/team-a-`.
* Tag-based access: resources tagged `env=dev`.

---

## 4. Service accounts: the most-tested IAM topic

| Practice | Why |
|---|---|
| **One service account per workload / function**, minimal roles | Blast radius (P6) |
| **Never use the default Compute Engine SA with Editor** for production workloads | It's over-privileged. New organizations disable automatic Editor grants via a secure-by-default org policy |
| **Don't create service account keys**; enforce `iam.disableServiceAccountKeyCreation` (and `iam.disableServiceAccountKeyUpload`) | Keys are long-lived bearer credentials, so they leak |
| On Google Cloud: **attach** the SA to the resource (VM, Cloud Run, function) | Metadata server issues short-lived tokens |
| GKE pods: **Workload Identity Federation for GKE** | Kubernetes SA → IAM principal; no node-SA sharing; no keys |
| Outside Google Cloud: **Workload Identity Federation** (AWS, Azure, OIDC/SAML, GitHub Actions, GitLab, on-premises with X.509 or OIDC) | Short-lived tokens from existing identity |
| Humans needing elevated access: **service account impersonation** (`roles/iam.serviceAccountTokenCreator` on the SA) | No keys; every impersonation is audited; time-limited tokens |
| Just-in-time elevation: **Privileged Access Manager (PAM)** | Temporary, approved, auto-expiring grants. Fits separation of duties and break-glass |
| Who can use an SA: `roles/iam.serviceAccountUser` | Lets a principal deploy resources *as* that SA, which is effectively privilege escalation, so grant it carefully |

```bash
# A developer runs a one-off admin task as a deploy SA, without keys
gcloud storage ls gs://prod-artifacts \
  --impersonate-service-account=deployer@prod-project.iam.gserviceaccount.com
```

---

## 5. Separation of duties (SoD)

| Practice | Implementation |
|---|---|
| Different people approve and deploy | CI/CD with approvals (Cloud Deploy approvals), deploy via SA impersonation, no human write access to prod |
| Security admins aren't workload owners | Separate groups: Org Admin, Security Admin, Network Admin, Billing Admin, Logging/Audit viewers. Grant at org or folder |
| Key admins can't read data, data users can't manage keys | `roles/cloudkms.admin` vs `roles/cloudkms.cryptoKeyEncrypterDecrypter` held by different principals; keys in a separate project |
| Logging can't be tampered with by workload teams | Central logging project; locked log buckets; sinks at org level |
| Break-glass access | Emergency accounts with strong MFA, monitored usage, PAM-based time-limited elevation |
| Billing separation | Billing Account Administrator separate from project owners; budgets and alerts |

---

## 6. Organization policies (constraints) that appear in questions

| Constraint | Effect | Typical scenario |
|---|---|---|
| `gcp.resourceLocations` | Restrict where resources can be created (for example, `in:eu-locations`) | Residency (KnightMotives EU data, EHR health data) |
| `iam.allowedPolicyMemberDomains` (domain-restricted sharing) | Only identities from allowed customer IDs can be granted roles | Prevent sharing with personal Gmail or external domains |
| `iam.disableServiceAccountKeyCreation` | Block SA key creation | Keyless posture |
| `compute.vmExternalIpAccess` | Allow-list (or deny all) VMs with external IPs | Private-by-default |
| `compute.requireOsLogin` | Require OS Login for SSH | IAM-governed SSH |
| `storage.uniformBucketLevelAccess` / `storage.publicAccessPrevention` | Enforce UBLA / no public buckets | Data-leak prevention |
| `sql.restrictPublicIp` | No public IPs on Cloud SQL | Database exposure |
| `compute.restrictVpcPeering`, `compute.restrictSharedVpcHostProjects` | Control network connectivity | Network governance |
| `gcp.restrictServiceUsage` | Limit which services can be used | Allowed-services list |
| **Custom constraints** | CEL conditions on resource fields (for example, GKE clusters must enable Workload Identity) | Bespoke guardrails |

**Inheritance:** child nodes inherit the parent's policy unless they're allowed to override (merge or replace). Use **dry-run** mode to test the impact of a constraint before enforcing it. New organizations get **secure-by-default** policies (for example, key creation disabled).

---

## 7. Resource Manager tags vs labels

| | **Tags** (Resource Manager / secure tags) | **Labels** |
|---|---|---|
| Purpose | **Policy**: conditional IAM, org policy conditions, firewall targets | **Organization and billing**: cost allocation, filtering |
| Governance | Tag keys and values are resources with IAM (who can attach them) | Anyone who can edit the resource |
| Inheritance | Inherited down the hierarchy | Not inherited |

Exam: "Allow the dev team admin access only to resources marked dev" → **tags + IAM Conditions**. "Report costs per team" → **labels** + billing export.

---

## 8. Worked scenarios

**A. "500 engineers in Entra ID need Google Cloud access with existing groups; the security team doesn't want duplicate accounts."**
Workforce Identity Federation (no sync) with attribute mapping to groups; grant IAM to group principals. Alternative: Cloud Identity with SCIM provisioning plus SSO, if they also need other Google services.

**B. "A GitHub Actions pipeline deploys Terraform to production."**
Workload Identity Federation with a GitHub OIDC provider, restricted by an attribute condition (repository and branch), impersonating a narrowly scoped deploy service account. No keys in GitHub secrets.

**C. "Developers have Editor on the Dev folder. Nobody except the DBA group may delete Cloud SQL instances anywhere."**
An org-level **deny policy** for `cloudsql.instances.delete`, with the DBA group as an exception.

**D. "Auditors need read-only access to all logs in every project, now and in the future."**
Grant `roles/logging.viewer` (or `privateLogViewer` for Data Access logs), or Log Analytics access on central log buckets, to an auditors **group** at the **organization** level or on the central logging project.

---

## References

* Resource hierarchy: <https://cloud.google.com/resource-manager/docs/cloud-platform-resource-hierarchy>
* IAM overview: <https://cloud.google.com/iam/docs/overview>
* Deny policies: <https://cloud.google.com/iam/docs/deny-overview>
* Principal access boundary: <https://cloud.google.com/iam/docs/principal-access-boundary-policies>
* Workload Identity Federation: <https://cloud.google.com/iam/docs/workload-identity-federation>
* Workforce Identity Federation: <https://cloud.google.com/iam/docs/workforce-identity-federation>
* Best practices for service accounts: <https://cloud.google.com/iam/docs/best-practices-service-accounts>
* Organization policy constraints: <https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints>
* Privileged Access Manager: <https://cloud.google.com/iam/docs/pam-overview>
